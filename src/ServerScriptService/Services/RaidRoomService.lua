--[[
	RaidRoomService.lua
	Instanced Raid Rooms — see RaidConfig.lua's header for the full design rationale (the
	"instanced version of Expedition" this and that file were built to be). Owns the whole run
	end to end: spend Energy, generate a map (RaidConfig.GenerateMap), allocate a private instance
	slot, teleport the player in, build/enter rooms, resolve each node type's own end condition,
	and hand the player back to the branching-map GUI (client-side) to pick where they go next.

	One run per player at a time, entirely self-contained in its own Workspace folder — see
	allocateSlot below for how concurrent players never share space. Nothing here touches
	ExpeditionService/NodeService at all; that's still the older shared-world conveyor and keeps
	working exactly as it did. This is a parallel system, not a replacement (yet).

	Flow, node type by node type (see RaidConfig.NodeTypes for the six types):
	  Start      -> entered once, instantly, right when the raid begins. No encounter — the map
	                choice for the first fork shows immediately.
	  Combat     -> hands off to CombatEncounterService.RunRaidCombat (the same real engine base
	                defense uses, just chasing the player instead of a wall — see that function's
	                own header). A room built with RaidConfig.SpawnPointName Parts spawns exactly
	                what they specify (see collectSpawnPoints); one without falls back to a random
	                composition off RaidConfig.CombatTierComposition, same as before that existed.
	                Cleared grants run-scoped loot (grantRunLoot — see RUN ECONOMY below) and
	                advances — see advanceFromNode below. Defeated fails the whole raid.
	  Ambush     -> like Combat, but several RunRaidCombat calls back to back as separate waves
	                (RaidConfig.RollAmbushWaveCount, scaled by the WHOLE raid's progress — see
	                state.TotalNodesVisited below) instead of just one — a rarer, tougher variant.
	                Loot grants per wave cleared; any wave lost fails the whole raid, same as Combat.
	  Heal       -> waits for the player to interact with a RaidConfig.InteractPointName Part in the
	                room (see beginInteractGated below), THEN full-heals the player's Humanoid, then
	                waits for a "Continue" RaidRoomAction before advancing.
	  Shop       -> same interact-gate as Heal, then shows NodeConfig.ShopCatalog (spendable only
	                against this run's OWN collected currency — see RUN ECONOMY below), waits for
	                "Buy" (repeatable) and "Continue" RaidRoomActions.
	  Boss       -> RaidConfig.GenerateMap already picked which nodes are Boss (see that file's
	                placeBossNodes) — this just runs one tougher RunRaidCombat encounter off
	                RaidConfig.BossComposition/EnemyConfig.BossTypes (beginBoss below). Cleared
	                fully heals the player, grants NodeConfig.BossLoot, and offers a rarity-weighted
	                card pick (RaidConfig.RollCardChoices) BEFORE advancing — the player has to
	                actually choose (RaidRoomAction "ChooseCard") before the map moves on. Defeated
	                fails the whole raid, same as Combat/Ambush.

	There's no dedicated "Extraction" node type (see RaidConfig.lua's header) — any of the types
	above can end up as a dead-end leaf of THIS generated map's tree (there can be several scattered
	across one map, not just one), and advanceFromNode below is what tells the difference: a leaf
	(empty Connections) calls onMapCleared instead of showMapChoice, regardless of what type it
	happened to be. Reaching one no longer ends the raid outright — onMapCleared marks the raid's
	first clear (unlocking the Extract action from then on) and immediately regenerates a brand new
	map to keep going. Actually banking everything and leaving is its own explicit action now — see
	RequestExtractRaid below — available any time after that first clear.

	RUN ECONOMY — loot earned mid-raid no longer touches the player's real profile immediately (see
	grantRunLoot/addRunReward/settleRunLoot below). Scrap/Cores collected this run sit in
	state.RunCurrencyCollected — the raid's OWN Shop spends against that, not the player's real
	currency ("scraps collected through the entire run, instead of the scraps that you currently
	have as a player, in your base") — and everything else earned sits in state.RunLoot until the
	raid actually ends. Currency is always banked in full; everything else is banked in full too
	UNLESS the raid ended in a Defeat/Abandon AND the specific drop was tagged RunLocked (and not
	also Permanent) on its loot-table entry — see NodeConfig.lua's own comment on those tags.
]]

-- Players is back (it was removed once, see the git history / DataService.PlayerSaving note
-- below) — exit doors need Players:GetPlayerFromCharacter to resolve a Touched hit's owner.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local RaidConfig = require(ReplicatedStorage.Shared.RaidConfig)
local NodeConfig = require(ReplicatedStorage.Shared.NodeConfig)
local WaveConfig = require(ReplicatedStorage.Shared.WaveConfig)
local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local DevShortcuts = require(script.Parent.DevShortcuts)
local DataService = require(script.Parent.DataService)
local RaidEnergyService = require(script.Parent.RaidEnergyService)
local CombatEncounterService = require(script.Parent.CombatEncounterService)
local BlackMarketService = require(script.Parent.BlackMarketService)
local PlayerActivityService = require(script.Parent.PlayerActivityService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestStartRaid = Remotes.RequestStartRaid
local RaidMapUpdate = Remotes.RaidMapUpdate
local ChooseRaidNode = Remotes.ChooseRaidNode
local RaidRoomUpdate = Remotes.RaidRoomUpdate
local RaidRoomAction = Remotes.RaidRoomAction
local AbandonRaid = Remotes.AbandonRaid
local RequestExtractRaid = Remotes.RequestExtractRaid

local RaidRoomService = {}

local raidsFolder = Workspace:FindFirstChild("RaidInstances")
if not raidsFolder then
	raidsFolder = Instance.new("Folder")
	raidsFolder.Name = "RaidInstances"
	raidsFolder.Parent = Workspace
end

----------------------------------------------------------------------
-- Instance slot allocation — see RaidConfig's "Instancing" comment for why this is code-driven
-- (a fixed point in the sky + per-slot offset) instead of a hand-placed Studio anchor. Slots are a
-- simple free-list: handed out on raid start, returned on any raid end (win, loss, abandon,
-- disconnect) — reused across runs/players rather than growing forever.
----------------------------------------------------------------------

local freeSlots = {}
for i = RaidConfig.MaxConcurrentInstances, 1, -1 do
	table.insert(freeSlots, i)
end

local function allocateSlot(): number?
	return table.remove(freeSlots)
end

local function releaseSlot(slotIndex: number?)
	if slotIndex then
		table.insert(freeSlots, slotIndex)
	end
end

local function slotOrigin(slotIndex: number): Vector3
	return RaidConfig.InstanceOrigin + Vector3.new((slotIndex - 1) * RaidConfig.InstanceSlotSpacing, 0, 0)
end

----------------------------------------------------------------------
-- Room construction — one named entry per type in ServerStorage.RaidRoomModels (a Model, or a
-- Folder of Models to pick a variant from), falling back to a plain big square if that type has
-- nothing usable built yet. See RaidConfig's own comment on this.
----------------------------------------------------------------------

-- Same "low guard rail around the edge" idea MineShaftService.lua's buildSurfaceGuardRail already
-- uses for ITS placeholder floor — not a full wall/enclosure, just enough to stop casually walking
-- (or getting shoved by an enemy) off the edge. Genuinely necessary here in a way it might not be
-- for a real Room Model: this floor is a bare square floating alone at RaidConfig.InstanceOrigin
-- with nothing else around it for hundreds of studs in any direction, so walking off the edge is a
-- straight fall into the void with nothing to catch it. INVISIBLE (Transparency = 1, collision
-- only) rather than a visible concrete wall — now that RaidConfig.FallbackRoomSize is a much bigger
-- 260x260 (was 50x50), a chunky visible wall running the whole way around such a big open area
-- would look worse than just not being able to see the edge at all; the collision is still real,
-- only the visual is gone.
local GUARD_RAIL_THICKNESS = 2
local GUARD_RAIL_HEIGHT = 8

local function buildFallbackGuardRail(model: Model, origin: Vector3, size: Vector3)
	local halfX, halfZ = size.X / 2, size.Z / 2

	local function rail(name: string, localX: number, localZ: number, sizeX: number, sizeZ: number)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = true
		part.Transparency = 1
		part.Material = Enum.Material.Concrete
		part.Color = RaidConfig.FallbackRoomColor
		part.Size = Vector3.new(sizeX, GUARD_RAIL_HEIGHT, sizeZ)
		part.CFrame = CFrame.new(origin) * CFrame.new(localX, GUARD_RAIL_HEIGHT / 2, localZ)
		part.Parent = model
	end

	rail("GuardRailNorth", 0, -halfZ - GUARD_RAIL_THICKNESS / 2, size.X + GUARD_RAIL_THICKNESS * 2, GUARD_RAIL_THICKNESS)
	rail("GuardRailSouth", 0, halfZ + GUARD_RAIL_THICKNESS / 2, size.X + GUARD_RAIL_THICKNESS * 2, GUARD_RAIL_THICKNESS)
	rail("GuardRailEast", halfX + GUARD_RAIL_THICKNESS / 2, 0, GUARD_RAIL_THICKNESS, size.Z)
	rail("GuardRailWest", -halfX - GUARD_RAIL_THICKNESS / 2, 0, GUARD_RAIL_THICKNESS, size.Z)
end

-- Physical exits for the fallback room — see RaidConfig.ExitDoorName's own comment for the full
-- design (why a Part name + an optional index attribute, why "too few doors" isn't an error). Built
-- along the room's NORTH edge (negative Z), inset from that edge so they sit clear of
-- GuardRailNorth rather than clipping into it, and given an explicit ExitDoorIndexAttribute rather
-- than relying on the X-sort fallback — these ARE laid out left-to-right by construction, but the
-- attribute is what an authored Room Model actually needs, so the fallback exercises the same path.
local function buildFallbackExitDoors(model: Model, origin: Vector3, size: Vector3)
	local doorSize = RaidConfig.FallbackExitDoorSize
	local count = RaidConfig.FallbackExitDoorCount

	for i = 1, count do
		local door = Instance.new("Part")
		door.Name = RaidConfig.ExitDoorName
		door.Anchored = true
		door.CanCollide = true
		-- Built already sealed, matching sealExitDoors exactly, so the placeholder room's own doors
		-- are invisible-until-cleared the same way an authored room's are rather than being the one
		-- place a dark slab still shows up.
		door.Transparency = RaidConfig.ExitDoorSealedTransparency
		door.Material = Enum.Material.Slate
		door.Color = RaidConfig.ExitDoorSealedColor
		door.Size = doorSize
		door:SetAttribute(RaidConfig.ExitDoorIndexAttribute, i)

		-- Evenly spaced and centred across the room's X width; sat on the floor rather than
		-- floating, since the fallback floor's own top face is origin.Y (buildFallbackRoom offsets
		-- the floor Part downward by half its own height, not this door's).
		local localX = size.X * (i / (count + 1) - 0.5)
		door.CFrame = CFrame.new(origin + Vector3.new(localX, doorSize.Y / 2, -size.Z / 2 + RaidConfig.FallbackExitDoorInset))
		door.Parent = model
	end
end

-- Studs the placeholder interact stand-in sits away from the room's spawn point (see below) — far
-- enough that reaching it is a real, deliberate walk, not just standing still at spawn.
local FALLBACK_INTERACT_POINT_OFFSET = 20

local function buildFallbackRoom(nodeType: string, origin: Vector3): Model
	local size = RaidConfig.FallbackRoomSize
	local floor = Instance.new("Part")
	floor.Name = "FallbackFloor"
	floor.Size = size
	floor.Anchored = true
	floor.CanCollide = true
	floor.Material = Enum.Material.Concrete
	floor.Color = RaidConfig.FallbackRoomColor
	floor.CFrame = CFrame.new(origin) * CFrame.new(0, -size.Y / 2, 0)

	local model = Instance.new("Model")
	model.Name = nodeType .. "_Fallback"
	model.PrimaryPart = floor
	floor.Parent = model

	-- Marks this room as the placeholder, not an authored one — resolveEnemyPlacements below warns
	-- when an authored Combat/Ambush room has no SpawnZone/SpawnPoint (a half-built room is a bug
	-- worth finding), but the placeholder legitimately has neither by design; without this flag that
	-- warn would fire on literally every raid until real Room Models exist, drowning the one case it
	-- actually exists to catch.
	model:SetAttribute("PlaceholderRoom", true)

	buildFallbackGuardRail(model, origin, size)
	buildFallbackExitDoors(model, origin, size)

	-- Heal/Shop rooms need a RaidConfig.InteractPointName Part to gate on (see beginInteractGated)
	-- — without a real authored Room Model, the fallback square had NONE, so Heal/Shop fired
	-- immediately on entry no matter what, silently skipping the interact requirement entirely
	-- rather than falling back to it. A stand-in Part here means the gate actually applies even
	-- before real art exists — swap it out for real content later (an NPC, a machine) just by
	-- naming that Part/Model the same way in an authored Room Model, same as everywhere else in
	-- this project.
	if nodeType == "Heal" or nodeType == "Shop" then
		local interactHeight = 5
		local interactPoint = Instance.new("Part")
		interactPoint.Name = RaidConfig.InteractPointName
		interactPoint.Size = Vector3.new(4, interactHeight, 4)
		interactPoint.Anchored = true
		interactPoint.CanCollide = true
		interactPoint.Material = Enum.Material.Neon
		interactPoint.Color = (RaidConfig.NodeTypes[nodeType] and RaidConfig.NodeTypes[nodeType].Color) or RaidConfig.FallbackRoomColor
		interactPoint.CFrame = CFrame.new(origin) * CFrame.new(0, size.Y / 2 + interactHeight / 2, FALLBACK_INTERACT_POINT_OFFSET)
		interactPoint.Parent = model
	end

	return model
end

-- Resolves one entry of ServerStorage.RaidRoomModels into an actual room template, or nil if that
-- type has nothing usable built yet (caller falls back to the placeholder square).
--
-- A Model is the template, used directly — unchanged, so every room already built keeps working.
-- A FOLDER is a VARIANT SET: one random Model child is picked per node. buildRoom looks up exactly
-- ONE thing per node type, so a fifteen-node map otherwise walks through the identical box a dozen
-- times; this turns "make the map pretty" into as many small Studio jobs as wanted instead of one
-- big one. Backwards compatible by construction — neither branch knows about the other.
--
-- Variants without a PrimaryPart are SKIPPED rather than picked and then fallen back on, so one
-- half-built variant can't drop a fraction of runs into the placeholder square at random — which
-- would present as an intermittent, unreproducible "sometimes the room is the grey box". They warn
-- by name instead, since a variant that simply never appears is otherwise invisible.
local function pickRoomTemplate(entry: Instance?): Model?
	if entry == nil then
		return nil
	end

	if entry:IsA("Model") then
		return entry.PrimaryPart and entry or nil
	end

	if not entry:IsA("Folder") then
		return nil
	end

	local variants = {}
	local skipped = {}
	for _, child in ipairs(entry:GetChildren()) do
		if child:IsA("Model") then
			if child.PrimaryPart then
				table.insert(variants, child)
			else
				table.insert(skipped, child.Name)
			end
		end
	end

	if #skipped > 0 then
		warn(("[RaidRoomService] %s: variant Model(s) %s have no PrimaryPart and were skipped."):format(
			entry:GetFullName(), table.concat(skipped, ", ")))
	end

	if #variants == 0 then
		return nil
	end
	return variants[math.random(1, #variants)]
end

-- Builds (and returns) the room Model for `nodeType` at `origin`, parented into `parentFolder`.
-- Doesn't need to be told a rotation — every room is generated fresh at its own isolated slot
-- origin, so there's nothing to line up against.
local function buildRoom(nodeType: string, origin: Vector3, parentFolder: Instance): Model
	local typeConfig = RaidConfig.NodeTypes[nodeType]
	local roomModelsFolder = ServerStorage:FindFirstChild(RaidConfig.RoomModelsFolderName)
	local entry = typeConfig and roomModelsFolder and roomModelsFolder:FindFirstChild(typeConfig.RoomFolder)
	local template = pickRoomTemplate(entry)

	local model
	if template then
		model = template:Clone()
		model:PivotTo(CFrame.new(origin))
	else
		-- Fires for a missing entry AND for a present-but-unusable one (a Model with no PrimaryPart, a
		-- variant Folder with no usable Model in it). The message always claimed to cover the
		-- PrimaryPart case; it now actually does, which matters most while rooms are being authored.
		warn(("[RaidRoomService] No usable %q room Model found in ServerStorage.%s (missing, or missing a PrimaryPart) — using a plain placeholder room."):format(
			typeConfig and typeConfig.RoomFolder or nodeType, RaidConfig.RoomModelsFolderName))
		model = buildFallbackRoom(nodeType, origin)
	end

	model.Parent = parentFolder
	return model
end

-- See RaidConfig.PlayerSpawnName's own comment. A Part named exactly that anywhere in `roomModel`
-- sets BOTH position and facing (the player is pivoted to its full CFrame, not just its Position) —
-- no RoomSpawnHeightOffset stacked on top, since the author placed the Part exactly where they want
-- the player to land, and adding an offset would float them above their own marker. Absent (or no
-- roomModel at all, e.g. mid-teardown), falls back to today's exact origin + height-offset behaviour
-- unchanged and with no warn — a room legitimately may not have one yet, and the fallback placeholder
-- room never will.
local function teleportPlayerToRoom(player: Player, roomOrigin: Vector3, roomModel: Instance?)
	local character = player.Character
	if not character then
		return
	end

	local spawnPart = nil
	local spawnPartCount = 0
	if roomModel then
		for _, descendant in ipairs(roomModel:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant.Name == RaidConfig.PlayerSpawnName then
				spawnPartCount += 1
				if not spawnPart then
					spawnPart = descendant
				end
			end
		end
	end

	if spawnPartCount > 1 then
		warn(("[RaidRoomService] %s has %d %s Parts — using the first found."):format(
			roomModel:GetFullName(), spawnPartCount, RaidConfig.PlayerSpawnName))
	end

	if spawnPart then
		character:PivotTo(spawnPart.CFrame)
	else
		character:PivotTo(CFrame.new(roomOrigin + Vector3.new(0, RaidConfig.RoomSpawnHeightOffset, 0)))
	end
end

-- Room-authored enemy placement — see RaidConfig.SpawnPointName/SpawnPointEnemyAttribute's own
-- comment. Returns nil if `roomModel` has no SpawnPoint Parts at all (the caller then falls back to
-- the older procedural circle-around-center spawn, unchanged), otherwise a list of
-- {Position, TypeKey} ready to hand straight to CombatEncounterService.RunRaidCombat's
-- explicitSpawns parameter. A SpawnPoint with a missing or unrecognized EnemyType attribute is
-- skipped (spawns nothing there) with a warn() — never silently guesses an enemy type, per the
-- explicit design ask.
local function collectSpawnPoints(roomModel: Model): { { Position: Vector3, TypeKey: string } }?
	local points = nil
	for _, descendant in ipairs(roomModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == RaidConfig.SpawnPointName then
			points = points or {}
			local typeKey = descendant:GetAttribute(RaidConfig.SpawnPointEnemyAttribute)
			if typeof(typeKey) == "string" and CombatEncounterService.IsValidEnemyType(typeKey) then
				table.insert(points, { Position = descendant.Position, TypeKey = typeKey })
			else
				warn(("[RaidRoomService] %s has no valid %s attribute (got %s) — spawning nothing there."):format(
					descendant:GetFullName(), RaidConfig.SpawnPointEnemyAttribute, tostring(typeKey)))
			end
		end
	end
	return points
end

-- Forward-declared for the same reason enterNode is below — resolveEnemyPlacements (right after
-- collectSpawnZones/placeInZones) needs to call this to draw a type key for each zone-filled
-- position, but pickRaidSpawnKeys itself isn't defined until further down this file (it also backs
-- the plain procedural fallback beginCombat/beginAmbush already use).
local pickRaidSpawnKeys

-- Room-authored spawn volumes — see RaidConfig.SpawnZoneName's own comment for the full contract.
-- Returns nil if `roomModel` has no SpawnZone Parts at all (same "caller falls back to procedural"
-- shape collectSpawnPoints above uses), otherwise a list of {Part, Weight} ready for placeInZones.
local function collectSpawnZones(roomModel: Instance): { { Part: BasePart, Weight: number } }?
	local zones = nil
	for _, descendant in ipairs(roomModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == RaidConfig.SpawnZoneName then
			zones = zones or {}
			local weight = descendant:GetAttribute(RaidConfig.SpawnZoneWeightAttribute)
			if typeof(weight) ~= "number" or weight <= 0 then
				-- A zero/negative weight must never reach the weighted draw in placeInZones — it
				-- would either divide by zero (an empty total) or make the zone impossible to land
				-- on while still contributing nothing to the sum, neither of which is what an author
				-- setting a bad number actually meant.
				weight = 1
			end

			-- Force these here rather than trusting the author to set them in Studio, so the zone can
			-- stay bright and visible while building the room and still disappear in game.
			-- CanQuery = false is not cosmetic: an invisible query-able volume in front of the player
			-- is the exact "I click and nothing happens" bug this project has already hit once, and
			-- it conveniently keeps the zone itself out of placeInZones' own floor raycast below, for
			-- free — no per-zone filter entry needed in that RaycastParams.
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.Anchored = true

			table.insert(zones, { Part = descendant, Weight = weight })
		end
	end
	return zones
end

-- One random candidate point inside `zone`'s own box, in WORLD space. Offsets are picked in the
-- part's OBJECT space (its own Size, centred on its own CFrame) and only then transformed by
-- zone.CFrame — that's what makes a rotated zone work exactly as drawn instead of only an
-- axis-aligned one. Starts at the TOP face on Y (not centre), since this is meant to be a downward
-- raycast origin looking for floor beneath it, not a point already floating mid-volume.
local function randomPointInZone(zone: BasePart): Vector3
	local offsetX = (math.random() - 0.5) * zone.Size.X
	local offsetZ = (math.random() - 0.5) * zone.Size.Z
	local offsetY = zone.Size.Y / 2
	return (zone.CFrame * CFrame.new(offsetX, offsetY, offsetZ)).Position
end

-- Weighted-random placement of up to `count` enemies across `zones` (see collectSpawnZones above),
-- each candidate checked against a downward raycast for real floor and a minimum distance from the
-- player before it's accepted — see RaidConfig.SpawnZoneMinPlayerDistance/FloorOffset/
-- MaxPlacementAttempts/RaycastExtraDepth's own comments for what each constant guards against.
-- Returns however many positions actually resolved, which may be fewer than `count` if a zone keeps
-- failing (see the per-enemy warn below) — a short encounter beats a stuck one, so this never falls
-- back to an unchecked position just to hit the count.
local function placeInZones(zones: { { Part: BasePart, Weight: number } }, player: Player, count: number): { Vector3 }
	local totalWeight = 0
	for _, zone in ipairs(zones) do
		totalWeight += zone.Weight
	end

	local character = player.Character
	local characterPosition = character and character:GetPivot().Position
	local roomModel = zones[1] and zones[1].Part:FindFirstAncestorWhichIsA("Model")

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	-- Only the player's own character needs excluding here — a player standing in the zone would
	-- otherwise get raycast-hit and mistaken for floor. The zones themselves need no entry: they're
	-- already CanQuery = false (collectSpawnZones sets that), which excludes them from any raycast
	-- automatically.
	raycastParams.FilterDescendantsInstances = character and { character } or {}

	local positions = {}
	for _ = 1, count do
		local placed = false
		for _attempt = 1, RaidConfig.SpawnZoneMaxPlacementAttempts do
			-- Re-drawing the zone every attempt (not just once per enemy) means one consistently bad
			-- zone (e.g. floating over a gap with nothing below it) can't doom this enemy's placement
			-- on its own — a later attempt can land in a different, better zone entirely.
			local roll = math.random() * totalWeight
			local cumulative = 0
			local chosenZone = zones[#zones]
			for _, zone in ipairs(zones) do
				cumulative += zone.Weight
				if roll <= cumulative then
					chosenZone = zone
					break
				end
			end

			local candidate = randomPointInZone(chosenZone.Part)
			local rayResult = Workspace:Raycast(
				candidate,
				Vector3.new(0, -(chosenZone.Part.Size.Y + RaidConfig.SpawnZoneRaycastExtraDepth), 0),
				raycastParams)
			if rayResult then
				local position = rayResult.Position + Vector3.new(0, RaidConfig.SpawnZoneFloorOffset, 0)
				if not characterPosition or (position - characterPosition).Magnitude >= RaidConfig.SpawnZoneMinPlayerDistance then
					table.insert(positions, position)
					placed = true
					break
				end
			end
		end
		if not placed then
			warn(("[RaidRoomService] %s couldn't place an enemy in a SpawnZone after %d attempts — skipping it."):format(
				roomModel and roomModel.Name or "?", RaidConfig.SpawnZoneMaxPlacementAttempts))
		end
	end
	return positions
end

-- Guarantees an elite is somewhere in an already-resolved placement list, for the admin dev
-- shortcut only. AUTHORED SpawnPoints are the reason this exists: a room that names its own
-- composition never reaches pickRaidSpawnKeys, so the forced-elite shortcut would silently do
-- nothing in exactly the rooms most likely to be hand-built for testing — the "I click and nothing
-- happens" shape this codebase keeps getting bitten by. Overriding one authored entry is a real
-- liberty to take with a room author's intent, which is why it is gated on the shortcut and nothing
-- else, and why it announces itself in Output.
--
-- Idempotent: if the list already contains an elite (the zone-fill path routes through
-- pickRaidSpawnKeys, which with eliteChance = 1 has already put one there), this does nothing
-- rather than adding a second.
local function ensureEliteInPlacements(state, placements): boolean
	for _, entry in ipairs(placements) do
		if EnemyConfig.EliteTypes[entry.TypeKey] then
			return false
		end
	end

	local elites = {}
	for key in pairs(EnemyConfig.EliteTypes) do
		if CombatEncounterService.HasModelFor(key) then
			table.insert(elites, key)
		end
	end
	if #elites == 0 or #placements == 0 then
		return false
	end

	local index = math.random(1, #placements)
	local replaced = placements[index].TypeKey
	placements[index].TypeKey = elites[math.random(1, #elites)]
	print(("[Admin] %s — dev shortcut overrode an authored SpawnPoint (%s -> %s) to force an elite."):format(
		state.Player.Name, tostring(replaced), placements[index].TypeKey))
	return true
end

-- Shared resolver for both beginCombat and each wave of beginAmbush — decides, in priority order,
-- whether this encounter uses authored SpawnPoints, authored SpawnZones, both, or falls back to the
-- original procedural composition (returning nil tells the caller to do exactly that, unchanged).
-- Points and zones COEXIST in one room — see RaidConfig.SpawnZoneName's own comment — so authored
-- points always count against the room's enemy budget first, and zones only fill whatever's left.
local function resolveEnemyPlacements(state, count: number, eliteChance: number?, forceElite: boolean?): { { Position: Vector3, TypeKey: string } }?
	local points = state.RoomFolder and collectSpawnPoints(state.RoomFolder)
	local zones = state.RoomFolder and collectSpawnZones(state.RoomFolder)

	if not points and not zones then
		-- A half-built Combat/Ambush room (no SpawnZone, no SpawnPoint) still has to be playable via
		-- the procedural fallback, but that should be findable rather than silently indistinguishable
		-- from an intentionally-plain room — except the fallback placeholder room, which legitimately
		-- has neither by design (see buildFallbackRoom's PlaceholderRoom attribute) and would
		-- otherwise trip this warn on literally every single raid.
		if state.RoomFolder and not state.RoomFolder:GetAttribute("PlaceholderRoom") then
			local node = state.Map.Nodes[state.CurrentNodeId]
			warn(("[RaidRoomService] %s room has no %s or %s Parts — falling back to the procedural spawn ring."):format(
				node and node.Type or "?", RaidConfig.SpawnZoneName, RaidConfig.SpawnPointName))
		end
		return nil
	end

	if points and not zones then
		if forceElite then
			ensureEliteInPlacements(state, points)
		end
		return points -- otherwise today's behaviour, unchanged
	end

	local combined = points and table.clone(points) or {}
	local remaining = math.max(0, count - #combined)
	if remaining > 0 then
		local positions = placeInZones(zones, state.Player, remaining)
		-- Reuses pickRaidSpawnKeys rather than a second draw, so a zone-filled enemy rolls off the
		-- exact same weighted, built-model-filtered roster the procedural path already uses — one
		-- place decides "what can spawn," this only ever decides "where."
		-- eliteChance rides along for the same reason the roster does: a zone-filled room and a
		-- procedural one should roll the same encounter, differing only in WHERE things stand.
		local typeKeys = pickRaidSpawnKeys(#positions, eliteChance)
		for i, position in ipairs(positions) do
			table.insert(combined, { Position = position, TypeKey = typeKeys[i] })
		end
	end

	-- Every zone placement can legitimately fail — a zone floating over a gap with no floor beneath
	-- it, or one packed so close to the entrance that nothing in it ever clears
	-- SpawnZoneMinPlayerDistance. Handing an EMPTY list back would reach RunRaidCombat's zero-spawn
	-- path, which does not strand the run (it warns and resolves "Cleared") but DOES hand the player
	-- a free clear and full loot for a room that never fought back. Falling back to the procedural
	-- ring instead keeps the encounter real: same missing-content rule the rest of this file follows,
	-- applied to geometry that turned out to be unusable rather than absent.
	if #combined == 0 then
		return nil
	end
	if forceElite then
		ensureEliteInPlacements(state, combined)
	end
	return combined
end

----------------------------------------------------------------------
-- Run-scoped loot economy — see this file's own header ("RUN ECONOMY") and RaidConfig.lua's. Loot
-- earned mid-raid lands in the CURRENT raid's own state, not the player's real profile, until the
-- raid actually ends (settleRunLoot below) — unlike NodeService.grantLoot/pushInventory (the older
-- Expedition system this deliberately doesn't share code with), which bank straight to the profile
-- the instant loot is granted, since Expedition has no concept of a "run" to hold anything back for.
----------------------------------------------------------------------

local function pushInventory(player: Player, profile)
	Remotes.InventoryUpdate:FireClient(player, {
		Scrap = profile.Scrap,
		Cores = profile.Cores,
		OreCounts = profile.OreCounts,
	})
end

local function pushRunCurrencyUpdate(state)
	RaidRoomUpdate:FireClient(state.Player, {
		Status = "RunCurrencyUpdate",
		RunCurrencyCollected = state.RunCurrencyCollected,
	})
end

-- One shared sink for anything earned this run — a Combat/Ambush/Boss loot roll, or a Shop
-- purchase's Grant. Scrap/Cores go straight into the live, run-only currency pool (spendable again
-- this same run at the Shop, always banked in full at raid end — see settleRunLoot) since they're
-- fungible and never worth holding a player's actual find hostage over. Everything else (Ore, and
-- any future item-style drop) becomes its own entry in state.RunLoot, carrying whatever
-- RunLocked/Permanent tags its source data set (see NodeConfig.lua's own comment) for
-- settleRunLoot to apply on a non-clean exit.
local function addRunReward(state, kind: string, key: string, amount: number, runLocked: boolean?, permanent: boolean?)
	if kind == "Currency" and (key == "Scrap" or key == "Cores") then
		state.RunCurrencyCollected[key] = (state.RunCurrencyCollected[key] or 0) + amount
		pushRunCurrencyUpdate(state)
	else
		table.insert(state.RunLoot, { Kind = kind, Key = key, Amount = amount, RunLocked = runLocked or false, Permanent = permanent or false })
	end
end

-- Rolls a NodeConfig-style loot table (Chance/Min/Max per entry) into the run's own pools via
-- addRunReward above, scaling every rolled amount by `multiplier` (RaidConfig.GetLootMultiplier —
-- "make that the rewards scale with difficulty"). Returns the granted list in the same
-- {Kind, Key, Amount} shape the client's toast rendering already expects.
local function grantRunLoot(state, lootTable, multiplier: number?)
	multiplier = multiplier or 1
	local granted = {}
	for _, entry in ipairs(lootTable) do
		if math.random() <= entry.Chance then
			local amount = math.max(1, math.floor(math.random(entry.Min, entry.Max) * multiplier + 0.5))
			local key = entry.OreKey or entry.CurrencyKey
			addRunReward(state, entry.Kind, key, amount, entry.RunLocked, entry.Permanent)
			table.insert(granted, { Kind = entry.Kind, Key = key, Amount = amount })
		end
	end
	return granted
end

-- Called exactly once, at the very end of a raid (Extract, Defeated, or Abandoned) — banks
-- everything actually kept into the player's real profile. Currency is always kept in full (it was
-- never spendable outside this raid's own Shop anyway, so there's no real "quit penalty" to attach
-- to it). Non-currency RunLoot entries are filtered by `isForfeit`: a clean Extract (isForfeit =
-- false) keeps everything; a Defeat/Abandon (isForfeit = true) drops anything RunLocked UNLESS it's
-- also Permanent — "they just get everything that they collected thru the run, EXCEPT run locked
-- items... unless the item has a tag called permanent."
local function settleRunLoot(state, isForfeit: boolean)
	local profile = DataService.Get(state.Player)
	if not profile then
		return
	end
	for currencyKey, amount in pairs(state.RunCurrencyCollected) do
		if amount > 0 then
			DataService.AddCurrency(state.Player, currencyKey, amount)
		end
	end
	for _, entry in ipairs(state.RunLoot) do
		if not (isForfeit and entry.RunLocked and not entry.Permanent) then
			if entry.Kind == "Ore" then
				DataService.AddOre(state.Player, entry.Key, entry.Amount)
			elseif entry.Kind == "Currency" then
				DataService.AddCurrency(state.Player, entry.Key, entry.Amount)
			end
		end
	end
	pushInventory(state.Player, profile)
end

----------------------------------------------------------------------
-- Active raid state — userId -> state table. Only one active raid per player at a time.
----------------------------------------------------------------------

local activeRaids: { [number]: any } = {}

local enterNode -- forward-declared, mutually referenced by the Combat/Ambush branches, showMapChoice, and onMapCleared

----------------------------------------------------------------------
-- Exit doors — the physical replacement for clicking a circle on the map GUI. See
-- RaidConfig.ExitDoorName's own comment for the full contract these three functions implement.
-- Declared here (after enterNode's forward-declare, before anything that opens a choice) because
-- unlockExitDoors has to call enterNode itself the moment a door resolves.
----------------------------------------------------------------------

-- Every ExitDoorName Part in the room, sorted into branch order. GetDescendants (not GetChildren)
-- because an authored room is free to nest its doors inside sub-Models for organization; the sort
-- itself is a strict weak ordering (equal elements never compare true either direction) so
-- table.sort can never throw on it, per RaidConfig's own numbered-first / X-fallback rule.
local function collectExitDoors(roomModel: Instance?): { BasePart }
	if not roomModel then
		return {}
	end
	local doors = {}
	for _, descendant in ipairs(roomModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == RaidConfig.ExitDoorName then
			table.insert(doors, descendant)
		end
	end
	table.sort(doors, function(a, b)
		local indexA = a:GetAttribute(RaidConfig.ExitDoorIndexAttribute)
		local indexB = b:GetAttribute(RaidConfig.ExitDoorIndexAttribute)
		local numberedA = typeof(indexA) == "number"
		local numberedB = typeof(indexB) == "number"
		if numberedA and numberedB then
			return indexA < indexB
		elseif numberedA ~= numberedB then
			return numberedA -- numbered doors sort ahead of unnumbered ones, mixed rooms allowed
		end
		return a.Position.X < b.Position.X
	end)
	return doors
end

-- Puts every door in the CURRENT room back to inert, sealed state — called the instant a room is
-- entered (see enterNode) so a door can never be caught mid-fight still looking open/walkable from
-- whatever choice led here. Also strips the label/prompt an unlock added, rather than leaving them
-- dangling on a door that's about to look sealed again.
local function sealExitDoors(state)
	for _, door in ipairs(collectExitDoors(state.RoomFolder)) do
		-- Solid but invisible — see RaidConfig.ExitDoorSealedTransparency's own comment. CanCollide
		-- stays TRUE precisely because the door is invisible: the doorway has to keep blocking or a
		-- player walks out of a room mid-fight into open sky.
		door.CanCollide = true
		door.Transparency = RaidConfig.ExitDoorSealedTransparency
		door.Material = Enum.Material.Slate
		door.Color = RaidConfig.ExitDoorSealedColor

		local label = door:FindFirstChild("ExitLabel")
		if label then
			label:Destroy()
		end
		local prompt = door:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt:Destroy()
		end
	end
end

-- Only shows if a NodeTypes entry is somehow missing its own Color — every real node type has one,
-- so this is a "should never actually render" defensive fallback, not a balance number, hence not
-- in RaidConfig.
local EXIT_DOOR_FALLBACK_COLOR = Color3.fromRGB(140, 140, 140)

-- Lights up one door per branch out of the current node, in `connections` order (collectExitDoors'
-- sort decides which physical door is "branch 1", same numbering RaidConfig.ExitDoorName's comment
-- documents for authors). Returns false — and WARNS instead of erroring — when the room simply
-- doesn't have enough doors built for the branches on offer here: same "missing content never
-- strands a run" contract buildRoom's own placeholder fallback follows, just for geometry instead
-- of a whole Model. An in-progress authored room with only one door still has to be playable, via
-- the old clickable GUI map for that one node, instead of hanging the player in an unfinished room.
local function unlockExitDoors(state, connections: { number }): boolean
	local doors = collectExitDoors(state.RoomFolder)
	if #doors < #connections then
		local currentNode = state.Map.Nodes[state.CurrentNodeId]
		warn(("[RaidRoomService] %s room has %d exit door(s) built but needs %d for its branches — falling back to the clickable map for this choice."):format(
			currentNode and currentNode.Type or "?", #doors, #connections))
		return false
	end

	-- Captures the node this batch of doors belongs to BEFORE connecting — enterNode destroys the
	-- whole room (doors included) the moment a choice resolves, but a Touched/Triggered connection
	-- could still be mid-fire; this is the exact stale-prompt guard beginInteractGated uses further
	-- down this file, for the same reason (this room could already be gone by the time the event
	-- actually runs).
	local nodeIdAtEntry = state.CurrentNodeId
	local fired = false -- guards two doors (or two Touched events in one frame) both resolving
	local liveConnections = {}

	local function disconnectAll()
		for _, connection in ipairs(liveConnections) do
			connection:Disconnect()
		end
	end

	for i, childId in ipairs(connections) do
		local door = doors[i]
		local destNode = state.Map.Nodes[childId]
		local typeConfig = destNode and RaidConfig.NodeTypes[destNode.Type]
		local color = (typeConfig and typeConfig.Color) or EXIT_DOOR_FALLBACK_COLOR
		local displayName = (typeConfig and typeConfig.DisplayName) or (destNode and destNode.Type) or "?"

		door.Color = color
		door.Material = Enum.Material.Neon
		door.Transparency = RaidConfig.ExitDoorUnlockedTransparency
		-- Solid + a prompt, or open + walk-through — never both at once, per
		-- ExitDoorUseProximityPrompt's own comment on why this is a config flip, not two features.
		door.CanCollide = RaidConfig.ExitDoorUseProximityPrompt

		local label = Instance.new("BillboardGui")
		label.Name = "ExitLabel" -- sealExitDoors finds and destroys it by this name
		label.AlwaysOnTop = true
		label.MaxDistance = 200
		label.Size = UDim2.new(0, 200, 0, 40)
		label.StudsOffsetWorldSpace = Vector3.new(0, door.Size.Y / 2 + RaidConfig.ExitDoorLabelHeightOffset, 0)
		label.Parent = door

		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBold
		text.TextScaled = true
		text.TextColor3 = color
		-- Same text shape the map circles already use — see RaidConfig.ExitDoorSealedColor's
		-- comment on unlocked doors learning the destination type's own colour language.
		text.Text = (destNode and destNode.Tier) and (displayName .. " · T" .. destNode.Tier) or displayName
		text.Parent = label

		local function tryEnter()
			if fired or state.CurrentNodeId ~= nodeIdAtEntry then
				return
			end
			fired = true
			disconnectAll()
			enterNode(state, childId)
		end

		if RaidConfig.ExitDoorUseProximityPrompt then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Enter"
			prompt.ObjectText = displayName
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = RaidConfig.ExitDoorPromptDistance
			prompt.RequiresLineOfSight = false
			prompt.Parent = door
			table.insert(liveConnections, prompt.Triggered:Connect(function(triggeringPlayer)
				if triggeringPlayer ~= state.Player then
					return
				end
				tryEnter()
			end))
		else
			table.insert(liveConnections, door.Touched:Connect(function(hit)
				-- Resolve the toucher through Players, not just "any BasePart touched us" — ignores
				-- dropped tools, projectiles, ragdolled corpses, anything that isn't the player's own
				-- character. GetPlayerFromCharacter returns nil for a non-character hit.Parent, so
				-- this also safely no-ops rather than erroring on those.
				local touchingPlayer = hit.Parent and Players:GetPlayerFromCharacter(hit.Parent)
				if touchingPlayer ~= state.Player then
					return
				end
				tryEnter()
			end))
		end
	end

	return true
end

-- Shared by every RaidMapUpdate fire — Nodes/StartNodeId/CurrentNodeId/MapsCleared are identical on
-- every call, only ReachableIds/ChoicePending/AllowNodeClick actually vary. ChoicePending gates the
-- client's "Go Back To Base" button (only bail while a choice is actually showing) and, since
-- 2026-09-09, also tells the client to un-collapse the Sector Map — the map is the input device
-- again, and a choice the player cannot see reads as a stalled run.
--
-- AllowNodeClick is now true for every choice while RaidConfig.ExitDoorsEnabled is false. It used to
-- be true ONLY in the too-few-doors fallback, back when doors were the real input and the circles
-- were decorative.
local function mapUpdatePayload(state, reachableIds: { number }, choicePending: boolean, allowNodeClick: boolean)
	return {
		Active = true,
		Nodes = state.Map.Nodes,
		StartNodeId = state.Map.StartNodeId,
		CurrentNodeId = state.CurrentNodeId,
		ReachableIds = reachableIds,
		ChoicePending = choicePending,
		AllowNodeClick = allowNodeClick,
		MapsCleared = state.MapsCleared,
	}
end

-- Offers the next choice. Which INPUT that uses is RaidConfig.ExitDoorsEnabled's call:
--
--   false (today) — the Sector Map is the input. unlockExitDoors is never called, so any doors
--     authored into the room stay exactly as sealExitDoors left them on entry: solid, invisible,
--     unlabelled, no prompt. AllowNodeClick goes out true and the player clicks a circle.
--   true — the original physical design: one door per branch lights up in its destination's colour,
--     and the clickable map comes back only for a room without enough doors built (unlockExitDoors
--     returns false, which is a warn(), never an error — see its own comment).
--
-- Short-circuit order matters: with the flag off, unlockExitDoors is not called at all, so a room
-- missing doors cannot warn about geometry nothing is asking for any more.
local function showMapChoice(state)
	local node = state.Map.Nodes[state.CurrentNodeId]
	local doorsUnlocked = RaidConfig.ExitDoorsEnabled and unlockExitDoors(state, node.Connections) or false
	RaidMapUpdate:FireClient(state.Player, mapUpdatePayload(state, node.Connections, true, not doorsUnlocked))
end

-- Reaching a map's dead-end (a leaf — empty Connections, regardless of its Type) — see
-- RaidConfig.lua's "CHAPTERED MAPS" header note and this file's own header. No longer the raid's
-- actual end: it marks the first "clear" (unlocking RequestExtractRaid below, if this is the very
-- first one) and always regenerates a brand new map, continuing straight into it — "generate a new
-- one with different paths... it can keep going."
local function onMapCleared(state)
	state.MapsCleared += 1
	local justUnlocked = not state.ExtractUnlocked
	state.ExtractUnlocked = true
	RaidRoomUpdate:FireClient(state.Player, {
		Status = "MapCleared",
		MapsCleared = state.MapsCleared,
		ExtractUnlocked = state.ExtractUnlocked,
		JustUnlocked = justUnlocked,
	})

	state.Map = RaidConfig.GenerateMap()
	enterNode(state, state.Map.StartNodeId)
end

-- Called wherever a room's own encounter/action finishes and the raid needs to move on — the one
-- place that decides "show the next fork" vs. "this was a leaf, clear the map" purely by whether
-- the CURRENT node has any Connections left, never by its Type (there's no dedicated Extraction
-- type to check for anymore — see this file's header).
local function advanceFromNode(state)
	local node = state.Map.Nodes[state.CurrentNodeId]
	if node and #node.Connections == 0 then
		onMapCleared(state)
	else
		showMapChoice(state)
	end
end

-- The single teardown funnel for a raid, however it ended — Extract, Defeat, Abandon, a mid-fight
-- "Interrupted", or a disconnect all route through here. That's why the PlayerActivityService
-- release lives here and nowhere else: every exit path already has to call this, so there's no
-- branch left where the activity could leak and soft-lock the player out of raiding.
local function cleanupRaid(state, sendReturnHome: boolean?)
	activeRaids[state.Player.UserId] = nil
	PlayerActivityService.Release(state.Player, PlayerActivityService.Activities.Raid)
	if state.RoomFolder then
		state.RoomFolder:Destroy()
	end
	releaseSlot(state.SlotIndex)

	if sendReturnHome then
		-- Same "safely out, clean slate" respawn every other exit path in this codebase uses
		-- (Recall, End Expedition, the mine's reset eviction) — PlotService's own CharacterAdded
		-- hook lands them back on their own base plot automatically.
		local player = state.Player
		if player.Parent then
			player:LoadCharacter()
		end
	end
end

local function failRaid(state, reason: string)
	settleRunLoot(state, true) -- forfeit: dying counts the same as abandoning for RunLocked drops
	RaidRoomUpdate:FireClient(state.Player, { Status = "Defeated", Reason = reason })
	cleanupRaid(state, true)
end

local function completeRaid(state)
	settleRunLoot(state, false) -- clean exit — everything collected is kept, no forfeiture

	-- Contraband is paid on a CLEAN extract only, never on a defeat or an abandon. That is what
	-- makes extracting a decision rather than a formality — see BlackMarketService.Income.
	local income = BlackMarketService.Income
	BlackMarketService.AwardContraband(
		state.Player,
		math.random(income.RaidExtractMin, income.RaidExtractMax),
		"Raid extraction")
	RaidRoomUpdate:FireClient(state.Player, { Status = "Extracted" })
	cleanupRaid(state, true)
end

-- Picks `count` random type keys from WaveConfig.EnemyTypes — same pool base defense draws from,
-- so raids and base defense feel like the same roster of threats. See RaidConfig
-- .CombatTierComposition for how `count`/multiplier are decided per Tier.
--
-- Filtered down to types that actually have a built Model first (CombatEncounterService
-- .HasModelFor) — drawing from the full unfiltered list meant an unlucky run of picks landing on a
-- not-yet-built type could spawn NOTHING for an entire wave, which read as "the wave got skipped"
-- even though nothing was actually broken, just missing art. Falls back to the full list if
-- somehow NONE of them have models yet, so this doesn't hang/error on a totally empty
-- ServerStorage.EnemyModels — RunRaidCombat's own zero-spawn fallback still catches that case.
-- Assigns the forward-declared local above (see that declaration's own comment for why) rather than
-- `local function`, which would otherwise shadow it with a second, still-nil local of the same name.
pickRaidSpawnKeys = function(count: number, eliteChance: number?): { string }
	local available = {}
	for _, key in ipairs(WaveConfig.EnemyTypes) do
		if CombatEncounterService.HasModelFor(key) then
			table.insert(available, key)
		end
	end
	if #available == 0 then
		available = WaveConfig.EnemyTypes
	end
	local keys = {}
	for _ = 1, count do
		table.insert(keys, available[math.random(1, #available)])
	end

	-- Elite substitution. EnemyConfig.EliteTypes was previously unreachable from a raid by any
	-- procedural path: pickBossSpawnKeys used to read EliteTypes, and when the elite/boss pools were
	-- split on 2026-09-09 so a boss could never leak into a WAVE, boss rooms moved onto BossTypes and
	-- nothing was left reading EliteTypes on the raid side. That was fallout from the split rather
	-- than a decision — EnemyAI.Patterns.Slam's whole design turns on a raid player being able to
	-- walk out of the telegraphed circle (see that file, and DESIGN_NOTES' "Siegebreaker — design
	-- rationale"), which nothing could ever exercise while no raid spawned one.
	--
	-- Rolled HERE rather than at the call sites because this function is already the single place
	-- that decides "what can spawn" for both the procedural ring and zone-filled placements (see
	-- resolveEnemyPlacements' own comment on why it reuses this rather than drawing separately).
	--
	-- Unlike the normal roster above, there is deliberately NO fall back to the unfiltered list when
	-- no elite has a built model: the roster fallback exists so a raid is never empty, but an elite
	-- is a bonus threat, and spawning a key with no Model would just warn and skip inside spawnEnemy,
	-- silently costing the room one enemy. No model yet simply means no elite — the room rolls out
	-- as an ordinary one.
	if #keys > 0 and eliteChance and eliteChance > 0 and math.random() <= eliteChance then
		local elites = {}
		for key in pairs(EnemyConfig.EliteTypes) do
			if CombatEncounterService.HasModelFor(key) then
				table.insert(elites, key)
			end
		end
		if #elites > 0 then
			keys[math.random(1, #keys)] = elites[math.random(1, #elites)]
		end
	end

	return keys
end

-- Same idea as pickRaidSpawnKeys above, but for Boss encounters — draws from EnemyConfig.BossTypes
-- instead of the normal roster (see RaidConfig.BossComposition's own comment on why), filtered down
-- to built models the same way.
--
-- This used to read EnemyConfig.EliteTypes, which was the same table CombatEncounterService's wave
-- elite pick drew from — so the raid's terminal encounter was also a routine spawn every fifth
-- wave, and a boss stopped reading as one. BossTypes is boss-only and read from here and nowhere
-- else.
--
-- EliteTypes is NOT raid-exclusive-to-waves as a result, and never was meant to be: Combat rooms
-- draw from it through pickRaidSpawnKeys' EliteChance substitution (see above). What the split
-- bought is one-directional — a BOSS can never turn up in a wave or an ordinary room. An elite
-- turning up in a Combat room is the intended shape, not a leak.
local function pickBossSpawnKeys(count: number): { string }
	local available = {}
	for key in pairs(EnemyConfig.BossTypes) do
		if CombatEncounterService.HasModelFor(key) then
			table.insert(available, key)
		end
	end
	if #available == 0 then
		for key in pairs(EnemyConfig.BossTypes) do
			table.insert(available, key)
		end
	end
	if #available == 0 then
		return {}
	end
	local keys = {}
	for _ = 1, count do
		table.insert(keys, available[math.random(1, #available)])
	end
	return keys
end

-- Shared by both beginCombat and beginAmbush — the encounter center to spawn/chase around, off the
-- room's own built Model if it has one (PrimaryPart), else the slot's bare origin.
local function roomEncounterCenter(state): Vector3
	return state.RoomFolder and state.RoomFolder.PrimaryPart
		and (state.RoomFolder.PrimaryPart.Position + Vector3.new(0, RaidConfig.RoomSpawnHeightOffset, 0))
		or (slotOrigin(state.SlotIndex) + Vector3.new(0, RaidConfig.RoomSpawnHeightOffset, 0))
end

local function beginCombat(state, node)
	state.InCombat = true
	local composition = RaidConfig.CombatTierComposition[node.Tier] or RaidConfig.CombatTierComposition[1]
	local roomCenter = roomEncounterCenter(state)

	-- Count is rolled FIRST now, unconditionally — resolveEnemyPlacements needs it up front to know
	-- how many zone-filled positions (if any) to top authored SpawnPoints up to, not just to size the
	-- procedural fallback roll the way this used to work.
	local count = math.random(composition.EnemyCountMin, composition.EnemyCountMax)

	-- A room built with RaidConfig.SpawnPointName/SpawnZoneName Parts decides some or all of its own
	-- composition (see resolveEnemyPlacements); one with neither falls back to the original
	-- procedural roll, unchanged from before either of those existed.
	-- Dev shortcut: an admin outside a Player Test Session gets a guaranteed elite in every raid
	-- fight, so a newly-built elite Model can be seen in a raid without rerolling a 20-35% chance
	-- until it happens. Prints, deliberately — the shortcut exists to test the ENEMY, and an admin
	-- who forgot it was on could otherwise read a forced spawn as proof the EliteChance roll works.
	-- /admin off, or Player Test Mode, turns it back into the real roll.
	local eliteChance = composition.EliteChance
	local forceElite = DevShortcuts.Active(state.Player)
	if forceElite then
		eliteChance = 1
		print(("[Admin] %s — forcing an elite into this Combat room (dev shortcut, not the %d%% roll)."):format(
			state.Player.Name, math.floor((composition.EliteChance or 0) * 100 + 0.5)))
	end

	local explicitSpawns = resolveEnemyPlacements(state, count, eliteChance, forceElite)
	local spawnKeys = {}
	if not explicitSpawns then
		spawnKeys = pickRaidSpawnKeys(count, eliteChance)
	end

	task.spawn(function()
		local status = CombatEncounterService.RunRaidCombat(state.Player, roomCenter, spawnKeys, composition.Multiplier, function(eventStatus, payload)
			payload = payload or {}
			-- Stamps this file's own Status vocabulary ("CombatStart"/"CombatTick"/"CombatEnd") onto
			-- whatever CombatEncounterService handed back — safe to write directly onto payload
			-- since it's a fresh table built fresh for this one call, never reused elsewhere. Its
			-- "End" event carries a Result field (Cleared/Defeated/Interrupted), deliberately NOT
			-- named Status, so it survives sitting right next to this — see that file's comment.
			payload.Status = "Combat" .. eventStatus -- "CombatStart" / "CombatTick" / "CombatEnd"
			RaidRoomUpdate:FireClient(state.Player, payload)
		end, explicitSpawns)

		-- The raid could have already been torn down out from under this task (player disconnected,
		-- abandoned) while combat was resolving — activeRaids no longer having this entry is the
		-- signal that happened, and there's nothing left to advance.
		if activeRaids[state.Player.UserId] ~= state then
			return
		end
		state.InCombat = false

		if status == "Cleared" then
			local tierData = NodeConfig.CombatTiers[node.Tier]
			if tierData then
				local lootMultiplier = RaidConfig.GetLootMultiplier(node.Tier, state.TotalNodesVisited)
				local loot = grantRunLoot(state, tierData.Loot, lootMultiplier)
				RaidRoomUpdate:FireClient(state.Player, { Status = "Cleared", Loot = loot })
			else
				RaidRoomUpdate:FireClient(state.Player, { Status = "Cleared", Loot = {} })
			end
			advanceFromNode(state)
		elseif status == "Defeated" then
			failRaid(state, "Your gear couldn't hold against this room.")
		else -- "Interrupted" — character/connection lost mid-fight, nothing more to do
			cleanupRaid(state, false)
		end
	end)
end

-- Ambush — same underlying engine as Combat, just run several times back to back as separate waves
-- instead of once. Wave count AND enemy strength now scale off the WHOLE raid's progress
-- (state.TotalNodesVisited, carried across map regenerations — see RaidConfig.lua's own "RUN
-- PROGRESSION" comment), not a node's own within-map Tier — "make sure there is a certain amount
-- of enemies that scale as you go through the run, same thing as for minimum waves as you go
-- through the run... on the first map you may have an ambush that does 3 waves, but on the 3rd map
-- you will have an ambush that does 5 instead, with stronger enemies as well." Always the
-- procedural spawn (never SpawnPoints — the design ask explicitly picked "random amount of waves"
-- over hand-placed-per-wave content), so every wave gets its own fresh composition. Loot grants
-- once per wave cleared (same NodeConfig.CombatTiers[tier].Loot Combat uses, scaled by
-- RaidConfig.GetLootMultiplier — "make that the rewards scale with difficulty"), rewarding the
-- extra risk; any single wave lost fails the whole raid, same as Combat.
local function beginAmbush(state, node)
	state.InCombat = true
	local composition = RaidConfig.CombatTierComposition[node.Tier] or RaidConfig.CombatTierComposition[1]
	local waveCount = RaidConfig.RollAmbushWaveCount(state.TotalNodesVisited)
	local runMultiplier = RaidConfig.GetRunProgressionMultiplier(state.TotalNodesVisited)
	local roomCenter = roomEncounterCenter(state)

	-- Ambush normally rolls NO elites at all (see the wave loop below for why). The dev shortcut is
	-- the one exception: "any combat scenario" is the point of it, and an Ambush is several fights
	-- in a row, so it is the fastest place to look at a new elite Model repeatedly. Rolled once for
	-- the whole node rather than per wave so the log line does not repeat 2-8 times.
	local eliteChance = nil
	local forceElite = DevShortcuts.Active(state.Player)
	if forceElite then
		eliteChance = 1
		print(("[Admin] %s — forcing an elite into every wave of this Ambush (dev shortcut; Ambush normally rolls none)."):format(
			state.Player.Name))
	end

	task.spawn(function()
		local tierData = NodeConfig.CombatTiers[node.Tier]

		for waveIndex = 1, waveCount do
			-- Each wave within one Ambush node ramps up slightly on top of its Tier's base
			-- composition — "nothing too crazy," so this is a small, capped nudge per wave, not a
			-- second multiplier system to tune in parallel with CombatTierComposition. runMultiplier
			-- stacks on top of that — the SAME Ambush node hits harder later in the raid than the
			-- identical node would have on map 1.
			local waveBonus = math.floor((waveIndex - 1) / 2)
			local count = math.random(composition.EnemyCountMin + waveBonus, composition.EnemyCountMax + waveBonus)
			local waveMultiplier = composition.Multiplier * runMultiplier * (1 + (waveIndex - 1) * 0.08)

			-- Resolved fresh EVERY wave, deliberately — a room with SpawnZones should give each wave
			-- of an Ambush its own random placements rather than every wave materialising in the same
			-- spots, which is what resolving once outside this loop (the way beginCombat resolves
			-- once for its single encounter) would produce.
			--
			-- eliteChance is nil for a real player, deliberately: an Ambush is already the tougher
			-- variant (2-8 waves, each ramping, any single loss failing the whole raid), and dropping
			-- a slam unit into an arbitrary wave of one would compound two difficulty spikes that
			-- were tuned independently. Combat rooms are the scoped home for elites; revisit for
			-- Ambush only with its own number, not by reusing the Combat one. It is non-nil only for
			-- the admin dev shortcut set above.
			local explicitSpawns = resolveEnemyPlacements(state, count, eliteChance, forceElite)
			local spawnKeys = {}
			if not explicitSpawns then
				spawnKeys = pickRaidSpawnKeys(count, eliteChance)
			end

			local status = CombatEncounterService.RunRaidCombat(state.Player, roomCenter, spawnKeys, waveMultiplier, function(eventStatus, payload)
				payload = payload or {}
				payload.Status = "Ambush" .. eventStatus -- "AmbushStart" / "AmbushTick" / "AmbushEnd"
				payload.Wave = waveIndex
				payload.WaveTotal = waveCount
				RaidRoomUpdate:FireClient(state.Player, payload)
			end, explicitSpawns)

			-- Same "torn down out from under this task" guard beginCombat uses — checked after every
			-- individual wave, not just once at the end, since a disconnect/abandon could land mid-sequence.
			if activeRaids[state.Player.UserId] ~= state then
				return
			end

			if status == "Defeated" then
				state.InCombat = false
				failRaid(state, "Your gear couldn't hold against this room.")
				return
			elseif status == "Interrupted" then
				state.InCombat = false
				cleanupRaid(state, false)
				return
			end

			-- "Cleared" — grant this wave's loot, then either a short breather before the next wave
			-- or, on the last one, hand back to the map.
			if tierData then
				local lootMultiplier = RaidConfig.GetLootMultiplier(node.Tier, state.TotalNodesVisited)
				local loot = grantRunLoot(state, tierData.Loot, lootMultiplier)
				RaidRoomUpdate:FireClient(state.Player, { Status = "AmbushWaveCleared", Wave = waveIndex, WaveTotal = waveCount, Loot = loot })
			else
				RaidRoomUpdate:FireClient(state.Player, { Status = "AmbushWaveCleared", Wave = waveIndex, WaveTotal = waveCount, Loot = {} })
			end

			if waveIndex < waveCount then
				task.wait(2)
			end
		end

		state.InCombat = false
		advanceFromNode(state)
	end)
end

-- The actual Heal/Shop payoff, run once the player's interacted (or immediately, if the room has
-- no interact Part — see beginInteractGated below).
local function doHeal(state)
	local character = state.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	RaidRoomUpdate:FireClient(state.Player, { Status = "HealApplied" })
	-- Waits for a "Continue" RaidRoomAction before advancing — see RaidRoomAction handler below.
end

local function revealShop(state)
	RaidRoomUpdate:FireClient(state.Player, { Status = "ShopCatalog", Catalog = NodeConfig.ShopCatalog })
	-- Waits for "Buy" (any number of times) and "Continue" — see RaidRoomAction handler below.
end

-- Heal/Shop used to trigger the instant the room was entered; now they wait for the player to
-- interact with a Part named RaidConfig.InteractPointName inside the room — see that constant's
-- own comment. A room with no such Part yet (the fallback square, or an authored room that hasn't
-- added one) just runs `onInteract` immediately, same as the old behavior, so nothing's blocked on
-- art that doesn't exist yet.
local function beginInteractGated(state, actionText: string, onInteract: (any) -> ())
	local part = state.RoomFolder and state.RoomFolder:FindFirstChild(RaidConfig.InteractPointName)
	if not part or not part:IsA("BasePart") then
		onInteract(state)
		return
	end

	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = part
	end
	prompt.ActionText = actionText
	prompt.ObjectText = ""
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false

	RaidRoomUpdate:FireClient(state.Player, { Status = "AwaitingInteraction", ActionText = actionText })

	-- Captures the exact node this prompt belongs to — enterNode destroys the whole room (this Part
	-- and Prompt included) the moment the player moves to a different node, but a Triggered
	-- connection could still be mid-fire; this guards against acting on a stale prompt from a room
	-- the player already left.
	local nodeIdAtEntry = state.CurrentNodeId
	local connection
	connection = prompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer ~= state.Player or state.CurrentNodeId ~= nodeIdAtEntry then
			return
		end
		connection:Disconnect()
		onInteract(state)
	end)
end

-- Boss — RaidConfig.GenerateMap's placeBossNodes already decided which nodes are Boss; this just
-- runs one tougher RunRaidCombat encounter (RaidConfig.BossComposition, drawing from
-- EnemyConfig.BossTypes via pickBossSpawnKeys instead of the normal roster). Clearing it fully
-- heals the player and offers a rarity-weighted card pick BEFORE advancing — "once the boss fight
-- clears, you get healed, and you roll some cards with buffs... pretty roguelike" — the player has
-- to actually choose (see RaidRoomAction's "ChooseCard" handler below) before the map moves on.
local function beginBoss(state, node)
	state.InCombat = true
	local composition = RaidConfig.BossComposition
	local roomCenter = roomEncounterCenter(state)
	local runMultiplier = RaidConfig.GetRunProgressionMultiplier(state.TotalNodesVisited)
	local count = math.random(composition.EnemyCountMin, composition.EnemyCountMax)

	-- Authored placement for Boss rooms — collectSpawnPoints DIRECTLY, deliberately NOT the full
	-- resolveEnemyPlacements point+zone path beginCombat/beginAmbush use. A zone-filled enemy here
	-- would inherit `multiplier` below, i.e. composition.Multiplier (2.6x), so every body a zone
	-- added would be an ELITE body and the room's difficulty would jump far past what its enemy
	-- count suggests — see DESIGN_NOTES "Boss escort", Decision 3. Zones in a Boss room therefore
	-- stay inert until the escort build gives minions their own multiplier and their own roster.
	-- Points only, as the 2026-09-07 round always intended and this path never actually did.
	-- With points authored, THEY decide the count (one Part, one enemy) and the BossComposition
	-- roll above only sizes the procedural fallback, exactly as in beginCombat.
	local explicitSpawns = state.RoomFolder and collectSpawnPoints(state.RoomFolder)
	local spawnKeys = {}
	if not explicitSpawns then
		spawnKeys = pickBossSpawnKeys(count)
	end
	local multiplier = composition.Multiplier * runMultiplier

	task.spawn(function()
		local status = CombatEncounterService.RunRaidCombat(state.Player, roomCenter, spawnKeys, multiplier, function(eventStatus, payload)
			payload = payload or {}
			payload.Status = "Boss" .. eventStatus -- "BossStart" / "BossTick" / "BossEnd"
			RaidRoomUpdate:FireClient(state.Player, payload)
		end, explicitSpawns)

		if activeRaids[state.Player.UserId] ~= state then
			return
		end
		state.InCombat = false

		if status == "Cleared" then
			local character = state.Player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = humanoid.MaxHealth
			end

			local lootMultiplier = RaidConfig.GetLootMultiplier(node.Tier, state.TotalNodesVisited)
			local granted = grantRunLoot(state, NodeConfig.BossLoot, lootMultiplier)

			local cardChoices = RaidConfig.RollCardChoices(3)
			state.PendingCardChoice = cardChoices

			RaidRoomUpdate:FireClient(state.Player, {
				Status = "BossCleared",
				Loot = granted,
				HealedToFull = true,
				CardChoices = cardChoices,
			})
			-- Deliberately NOT calling advanceFromNode yet — see RaidRoomAction's "ChooseCard".
		elseif status == "Defeated" then
			failRaid(state, "The boss was too much this time.")
		else -- "Interrupted"
			cleanupRaid(state, false)
		end
	end)
end

enterNode = function(state, nodeId: number)
	local node = state.Map.Nodes[nodeId]
	if not node then
		return
	end
	state.CurrentNodeId = nodeId
	if node.Type ~= "Start" then
		-- Persists across map regenerations (state itself outlives any one state.Map) — the counter
		-- Ambush's wave count/strength and every encounter's loot payout scale off, see
		-- RaidConfig.lua's own "RUN PROGRESSION" comment.
		state.TotalNodesVisited += 1
	end

	if state.RoomFolder then
		state.RoomFolder:Destroy()
	end
	local origin = slotOrigin(state.SlotIndex)
	state.RoomFolder = buildRoom(node.Type, origin, state.InstanceFolder)
	teleportPlayerToRoom(state.Player, origin, state.RoomFolder)

	local typeConfig = RaidConfig.NodeTypes[node.Type]
	RaidRoomUpdate:FireClient(state.Player, {
		Status = "Entered",
		Type = node.Type,
		Tier = node.Tier,
		DisplayName = typeConfig and typeConfig.DisplayName or node.Type,
	})

	-- Doors are sealed the instant a room is entered — never left "unlocked" from whatever choice
	-- led here — and BEFORE the branch chain below, deliberately: the Start branch calls
	-- showMapChoice, which unlocks doors, so sealing after the chain would immediately undo it.
	sealExitDoors(state)

	-- The persistent minimap needs to learn where the player is the moment they arrive, not only
	-- when a choice opens — ReachableIds empty/ChoicePending false here since nothing's offered yet.
	RaidMapUpdate:FireClient(state.Player, mapUpdatePayload(state, {}, false, false))

	if node.Type == "Start" then
		showMapChoice(state)
	elseif node.Type == "Combat" then
		beginCombat(state, node)
	elseif node.Type == "Ambush" then
		beginAmbush(state, node)
	elseif node.Type == "Boss" then
		beginBoss(state, node)
	elseif node.Type == "Heal" then
		beginInteractGated(state, "Heal", doHeal)
	elseif node.Type == "Shop" then
		beginInteractGated(state, "Shop", revealShop)
	end
end

----------------------------------------------------------------------
-- Start a raid
----------------------------------------------------------------------

RequestStartRaid.OnServerEvent:Connect(function(player: Player)
	if activeRaids[player.UserId] then
		return -- already mid-raid
	end
	local character = player.Character
	if not character or not character:FindFirstChildOfClass("Humanoid") or character.Humanoid.Health <= 0 then
		return
	end

	-- Claim the player's combat state BEFORE spending anything. Base defense and raids both write
	-- CombatEncounterService's single activeEncounters slot for this UserId, so starting a raid
	-- mid-wave used to corrupt both fights (see PlayerActivityService's header). Checked ahead of
	-- the Energy spend and the slot allocation so a refused raid costs the player nothing.
	local acquired, busyReason = PlayerActivityService.TryAcquire(player, PlayerActivityService.Activities.Raid)
	if not acquired then
		RaidRoomUpdate:FireClient(player, { Status = "Busy", Reason = busyReason })
		return
	end

	-- Slot allocation moved AHEAD of the Energy spend. It used to sit after, which meant a player
	-- who hit a full server (no free instance slot) had already been charged Energy for a raid
	-- that then never started, with nothing refunding it. Ordering the two so the only failure
	-- that can happen after the charge is "no failure" avoids needing a refund path at all.
	local slotIndex = allocateSlot()
	if not slotIndex then
		PlayerActivityService.Release(player, PlayerActivityService.Activities.Raid)
		RaidRoomUpdate:FireClient(player, { Status = "NoSlotsFree" })
		return
	end

	if not RaidEnergyService.TrySpendEnergy(player, RaidConfig.EnergyCost) then
		releaseSlot(slotIndex)
		PlayerActivityService.Release(player, PlayerActivityService.Activities.Raid)
		RaidRoomUpdate:FireClient(player, { Status = "NoEnergy" })
		return
	end

	local instanceFolder = Instance.new("Folder")
	instanceFolder.Name = tostring(player.UserId) .. "_RaidInstance"
	instanceFolder.Parent = raidsFolder

	local state = {
		Player = player,
		SlotIndex = slotIndex,
		InstanceFolder = instanceFolder,
		RoomFolder = nil :: Instance?,
		Map = RaidConfig.GenerateMap(),
		CurrentNodeId = nil :: number?,
		InCombat = false,
		MapsCleared = 0, -- how many map chapters this raid has finished so far — see onMapCleared
		ExtractUnlocked = false, -- true once the first map's been cleared — see RequestExtractRaid
		TotalNodesVisited = 0, -- persists across map regenerations — drives Ambush/loot scaling for
			-- the WHOLE raid, not just the current map chapter (see enterNode)
		RunLoot = {}, -- non-currency loot collected this raid, settled (with RunLocked/Permanent
			-- filtering) only when the raid actually ends — see settleRunLoot
		RunCurrencyCollected = { Scrap = 0, Cores = 0 }, -- this raid's own live-spendable currency —
			-- "scraps collected... instead of the scraps that you currently have as a player, in
			-- your base" — always banked in full whenever/however the raid ends
		PendingCardChoice = nil :: any, -- set by beginBoss right after a Boss clear, cleared by
			-- RaidRoomAction's "ChooseCard" handler
		CollectedCards = {}, -- placeholder record of what's been picked — no real buff effects
			-- wired up yet, see RaidConfig.lua's own "Card system" comment
	}
	activeRaids[player.UserId] = state

	-- Authoritative 0/0 the instant the raid actually begins — the client resets its own "Scraps
	-- Collected" display off this, NOT off every "Entered a Start node" (onMapCleared's regenerated
	-- maps ALSO start at a fresh Start node, but the run's collected currency should carry over
	-- across chapters, not reset there too).
	pushRunCurrencyUpdate(state)

	enterNode(state, state.Map.StartNodeId)
end)

----------------------------------------------------------------------
-- Map choice
----------------------------------------------------------------------

ChooseRaidNode.OnServerEvent:Connect(function(player: Player, nodeId: number)
	local state = activeRaids[player.UserId]
	if not state or state.InCombat or typeof(nodeId) ~= "number" then
		return
	end
	local currentNode = state.Map.Nodes[state.CurrentNodeId]
	if not currentNode or not table.find(currentNode.Connections, nodeId) then
		return -- not a valid choice from here — either stale UI or a spoofed id
	end
	enterNode(state, nodeId)
end)

----------------------------------------------------------------------
-- In-room actions (Heal "Continue", Shop "Buy"/"Continue")
----------------------------------------------------------------------

RaidRoomAction.OnServerEvent:Connect(function(player: Player, actionKey: string, payload: any)
	local state = activeRaids[player.UserId]
	if not state or state.InCombat then
		return
	end
	local node = state.Map.Nodes[state.CurrentNodeId]
	if not node then
		return
	end

	if actionKey == "Continue" then
		if node.Type == "Heal" or node.Type == "Shop" then
			advanceFromNode(state)
		end
	elseif actionKey == "Buy" then
		-- Spends against THIS RAID's own collected currency (state.RunCurrencyCollected), not the
		-- player's real profile — "you are only able to purchase stuff with the scraps collected
		-- through the entire run, instead of the scraps that you currently have as a player, in
		-- your base." The purchased item's Grant itself becomes a run reward via addRunReward (same
		-- path Combat/Ambush/Boss loot goes through), so it's subject to the same RunLocked
		-- forfeiture rule on a non-clean exit if the catalog ever tags one that way.
		if node.Type ~= "Shop" or typeof(payload) ~= "string" then
			return
		end
		local item = NodeConfig.ShopCatalog[payload]
		if not item then
			RaidRoomUpdate:FireClient(player, { Status = "ShopResult", Success = false, Reason = "Unknown item" })
			return
		end
		local have = state.RunCurrencyCollected[item.CostCurrency] or 0
		if have < item.CostAmount then
			RaidRoomUpdate:FireClient(player, { Status = "ShopResult", Success = false, Reason = ("Not enough %s collected this run"):format(item.CostCurrency) })
			return
		end
		state.RunCurrencyCollected[item.CostCurrency] = have - item.CostAmount
		pushRunCurrencyUpdate(state)
		local grant = item.Grant
		addRunReward(state, grant.Kind, grant.OreKey or grant.CurrencyKey, grant.Amount, grant.RunLocked, grant.Permanent)
		RaidRoomUpdate:FireClient(player, { Status = "ShopResult", Success = true, ItemKey = payload })
	elseif actionKey == "ChooseCard" then
		-- Placeholder only — records what was picked, applies no real buff effect yet. "for the...
		-- card system after boss, just make it a placeholder for now... I will make a list/table
		-- for you to add later." Wire real effects onto state.CollectedCards once that list exists.
		if node.Type ~= "Boss" or not state.PendingCardChoice or typeof(payload) ~= "string" then
			return
		end
		local chosen = nil
		for _, card in ipairs(state.PendingCardChoice) do
			if card.Key == payload then
				chosen = card
				break
			end
		end
		if not chosen then
			return
		end
		table.insert(state.CollectedCards, chosen)
		state.PendingCardChoice = nil
		RaidRoomUpdate:FireClient(player, { Status = "CardChosen", Card = chosen })
		advanceFromNode(state)
	end
end)

----------------------------------------------------------------------
-- Abandon — bail out early, banking everything collected this run EXCEPT any RunLocked drop (see
-- settleRunLoot/RaidConfig.lua's "RUN ECONOMY" comment) but giving up on this run's map chapter.
-- Available any time a raid is active (before OR after the first clear), unlike Extract below which
-- needs that first clear. Blocked mid-Combat, same reasoning NodeService blocks Heal/Shop/new raids
-- while activeRaids is true — you can't dodge a losing fight for free by abandoning out from under
-- it.
----------------------------------------------------------------------

AbandonRaid.OnServerEvent:Connect(function(player: Player)
	local state = activeRaids[player.UserId]
	if not state or state.InCombat then
		return
	end
	settleRunLoot(state, true) -- forfeit: RunLocked (non-Permanent) drops are lost on Abandon
	RaidRoomUpdate:FireClient(player, { Status = "Abandoned" })
	cleanupRaid(state, true)
end)

----------------------------------------------------------------------
-- Extract — bank everything and leave cleanly, only available once state.ExtractUnlocked (see
-- onMapCleared — "before the first clear, is just an abandon button... an extract button should be
-- available after the first clear"). Blocked mid-Combat for the same reason Abandon is.
----------------------------------------------------------------------

RequestExtractRaid.OnServerEvent:Connect(function(player: Player)
	local state = activeRaids[player.UserId]
	if not state or state.InCombat or not state.ExtractUnlocked then
		return
	end
	completeRaid(state)
end)

-- DataService.PlayerSaving, NOT Players.PlayerRemoving. This handler writes to the player's
-- profile, and PlayerRemoving handlers run in connection order — DataService is required first in
-- Main.server.lua, so its own handler (which saves and then clears the cache) always ran before
-- this one. settleRunLoot's DataService.Get therefore returned nil and every bit of currency and
-- loot collected during the raid was silently dropped, which is the exact opposite of what the
-- comment below describes. PlayerSaving fires before the save and before the cache clear, so the
-- write actually lands and gets persisted in the same pass. See DataService's own comment there.
DataService.PlayerSaving:Connect(function(player)
	local state = activeRaids[player.UserId]
	if state then
		-- Treated the same as Abandon for run-loot purposes (forfeit RunLocked non-Permanent drops)
		-- — a disconnect mid-raid isn't a clean Extract, and without this the run's own collected
		-- currency/loot would just silently vanish instead of ever reaching DataService at all.
		settleRunLoot(state, true)
		-- Best-effort only: if state.InCombat, CombatEncounterService.RunRaidCombat's own loop
		-- will notice the player is gone on its next tick and resolve itself to "Interrupted" —
		-- its playerFolder cleanup doesn't depend on this raid's InstanceFolder still existing.
		cleanupRaid(state, false)
	end
end)

return RaidRoomService
