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
	                RaidConfig.BossComposition/EnemyConfig.EliteTypes (beginBoss below). Cleared
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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local RaidConfig = require(ReplicatedStorage.Shared.RaidConfig)
local NodeConfig = require(ReplicatedStorage.Shared.NodeConfig)
local WaveConfig = require(ReplicatedStorage.Shared.WaveConfig)
local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local DataService = require(script.Parent.DataService)
local RaidEnergyService = require(script.Parent.RaidEnergyService)
local CombatEncounterService = require(script.Parent.CombatEncounterService)
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
-- Room construction — one named Model per type in ServerStorage.RaidRoomModels, falling back to a
-- plain big square if that type has no Model built yet. See RaidConfig's own comment on this.
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

	buildFallbackGuardRail(model, origin, size)

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

-- Builds (and returns) the room Model for `nodeType` at `origin`, parented into `parentFolder`.
-- Doesn't need to be told a rotation — every room is generated fresh at its own isolated slot
-- origin, so there's nothing to line up against.
local function buildRoom(nodeType: string, origin: Vector3, parentFolder: Instance): Model
	local typeConfig = RaidConfig.NodeTypes[nodeType]
	local roomModelsFolder = ServerStorage:FindFirstChild(RaidConfig.RoomModelsFolderName)
	local template = typeConfig and roomModelsFolder and roomModelsFolder:FindFirstChild(typeConfig.RoomFolder)

	local model
	if template and template:IsA("Model") and template.PrimaryPart then
		model = template:Clone()
		model:PivotTo(CFrame.new(origin))
	else
		if not (template and template:IsA("Model")) then
			warn(("[RaidRoomService] No %q Model found in ServerStorage.%s (or it's missing a PrimaryPart) — using a plain placeholder room."):format(
				typeConfig and typeConfig.RoomFolder or nodeType, RaidConfig.RoomModelsFolderName))
		end
		model = buildFallbackRoom(nodeType, origin)
	end

	model.Parent = parentFolder
	return model
end

local function teleportPlayerToRoom(player: Player, roomOrigin: Vector3)
	local character = player.Character
	if not character then
		return
	end
	character:PivotTo(CFrame.new(roomOrigin + Vector3.new(0, RaidConfig.RoomSpawnHeightOffset, 0)))
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

local function showMapChoice(state)
	local node = state.Map.Nodes[state.CurrentNodeId]
	RaidMapUpdate:FireClient(state.Player, {
		Active = true,
		Nodes = state.Map.Nodes,
		StartNodeId = state.Map.StartNodeId,
		CurrentNodeId = state.CurrentNodeId,
		ReachableIds = node.Connections,
	})
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
local function pickRaidSpawnKeys(count: number): { string }
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
	return keys
end

-- Same idea as pickRaidSpawnKeys above, but for Boss encounters — draws from EnemyConfig.EliteTypes
-- instead of the normal roster (see RaidConfig.BossComposition's own comment on why), filtered down
-- to built models the same way.
local function pickBossSpawnKeys(count: number): { string }
	local available = {}
	for key in pairs(EnemyConfig.EliteTypes) do
		if CombatEncounterService.HasModelFor(key) then
			table.insert(available, key)
		end
	end
	if #available == 0 then
		for key in pairs(EnemyConfig.EliteTypes) do
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

	-- A room built with RaidConfig.SpawnPointName Parts fully decides its own composition; one
	-- without falls back to the original procedural roll, unchanged from before this existed.
	local explicitSpawns = state.RoomFolder and collectSpawnPoints(state.RoomFolder)
	local spawnKeys = {}
	if not explicitSpawns then
		local count = math.random(composition.EnemyCountMin, composition.EnemyCountMax)
		spawnKeys = pickRaidSpawnKeys(count)
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
			local spawnKeys = pickRaidSpawnKeys(count)

			local status = CombatEncounterService.RunRaidCombat(state.Player, roomCenter, spawnKeys, waveMultiplier, function(eventStatus, payload)
				payload = payload or {}
				payload.Status = "Ambush" .. eventStatus -- "AmbushStart" / "AmbushTick" / "AmbushEnd"
				payload.Wave = waveIndex
				payload.WaveTotal = waveCount
				RaidRoomUpdate:FireClient(state.Player, payload)
			end)

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
-- EnemyConfig.EliteTypes via pickBossSpawnKeys instead of the normal roster). Clearing it fully
-- heals the player and offers a rarity-weighted card pick BEFORE advancing — "once the boss fight
-- clears, you get healed, and you roll some cards with buffs... pretty roguelike" — the player has
-- to actually choose (see RaidRoomAction's "ChooseCard" handler below) before the map moves on.
local function beginBoss(state, node)
	state.InCombat = true
	local composition = RaidConfig.BossComposition
	local roomCenter = roomEncounterCenter(state)
	local runMultiplier = RaidConfig.GetRunProgressionMultiplier(state.TotalNodesVisited)
	local count = math.random(composition.EnemyCountMin, composition.EnemyCountMax)
	local spawnKeys = pickBossSpawnKeys(count)
	local multiplier = composition.Multiplier * runMultiplier

	task.spawn(function()
		local status = CombatEncounterService.RunRaidCombat(state.Player, roomCenter, spawnKeys, multiplier, function(eventStatus, payload)
			payload = payload or {}
			payload.Status = "Boss" .. eventStatus -- "BossStart" / "BossTick" / "BossEnd"
			RaidRoomUpdate:FireClient(state.Player, payload)
		end)

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
	teleportPlayerToRoom(state.Player, origin)

	local typeConfig = RaidConfig.NodeTypes[node.Type]
	RaidRoomUpdate:FireClient(state.Player, {
		Status = "Entered",
		Type = node.Type,
		Tier = node.Tier,
		DisplayName = typeConfig and typeConfig.DisplayName or node.Type,
	})

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

Players.PlayerRemoving:Connect(function(player)
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
