--[[
	MineShaftService.lua
	The dig-down mine — a real 3D voxel grid (MineShaftConfig.GridWidth x GridLength cells, 32
	square by default) starting from a Part tagged "MineShaftStart". This REPLACES two earlier
	versions of this file — see DESIGN_NOTES.md for the full history — but the short version:

	This is built in genuinely real, ordinary world space, directly below wherever you place the
	"MineShaftStart" Part. There's no teleporting anywhere and no separate hidden area: **you're
	responsible for placing that anchor somewhere with real open air underneath it** (up on a
	platform, not on top of your map's actual ground) — the whole grid gets built straight down
	from there using normal, solid, CanCollide Parts, and mining one out just leaves real open air
	that gravity naturally pulls the player into, exactly like it would with any other block. No
	CSG, no carving, no capability-restricted engine properties, no fake pocket dimension. Two
	earlier versions of this file tried to make digging work by modifying/relocating around
	whatever real ground already existed under the anchor, and both got needlessly complicated and
	broke in different ways — see DESIGN_NOTES.md. Placing the anchor somewhere already-clear
	sidesteps that whole problem instead of trying to solve it in code.

	Only the first layer (Depth 0, directly under the anchor) is generated up front — that's the
	quarry floor you actually walk onto, filling the entire GridWidth x GridLength footprint. Every
	layer after that is generated on demand: destroying a block checks its 6 face-adjacent
	neighbors (down/up/+X/-X/+Z/-Z — MineShaftConfig.RevealNeighborOffsets) and spawns a fresh
	block in any of them that have never been touched before. Since Depth 0 starts completely
	filled in, mining a Depth-0 block only ever reveals the one directly below it — but past Depth
	0, sideways neighbors are still unexplored too, so the mine naturally grows into real connected
	tunnels the deeper you go, not just a single one-block-wide shaft per surface cell.

	Most cells roll as Rock filler (destroys for nothing — it's there so ore feels like something
	you dig for, not something sitting right next to you); some roll as an actual Ore resource; a
	few, more often the deeper you go, roll as a Lava pocket that bursts for real damage instead of
	a reward when you break through it. See MineShaftConfig.KindWeightBands for the depth-scaled
	odds.

	Does NOT reuse MiningService's generic OreNode/MineNode pipeline on purpose: every other ore
	node in the game respawns in place after depleting, but a mine cell needs to reveal NEW cells
	around it instead, and can resolve as filler or a hazard instead of ore at all — different
	enough behavior that bolting it onto MiningService as a special case would be messier than this
	file owning its own small mining flow. The tool-tier/wave gate itself is NOT duplicated though —
	both this and MiningService call the shared OreGate.CanMine. (It used to be a near-identical
	private copy in each file, with a comment here telling you to remember to change both.)

	Every cell's state is tracked server-side only (the `cells` table below) and blocks replicate
	to every client automatically as real Parts — there is no per-player mine state, same
	multiplayer-synced requirement the ring zone (and every version of this file) had.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MineShaftConfig = require(ReplicatedStorage.Shared.MineShaftConfig)
local OreConfig = require(ReplicatedStorage.Shared.OreConfig)
local RaidEnergyConfig = require(ReplicatedStorage.Shared.RaidEnergyConfig)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local DataService = require(script.Parent.DataService)
local RaidEnergyService = require(script.Parent.RaidEnergyService)
local PlotService = require(script.Parent.PlotService)
local StationService = require(script.Parent.StationService)
local RateLimiter = require(script.Parent.RateLimiter)
local OreGate = require(script.Parent.OreGate)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local START_TAG = "MineShaftStart"
local BLOCK_TAG = "ShaftBlock"
local MAX_MINING_DISTANCE = 12 -- studs; same as MiningService — reject hits from further away than this

local MineShaftService = {}

local shaftFolder = Workspace:FindFirstChild("MineShaft")
if not shaftFolder then
	shaftFolder = Instance.new("Folder")
	shaftFolder.Name = "MineShaft"
	shaftFolder.Parent = Workspace
end

-- The CFrame the whole grid is generated relative to — set once in populateGrid, read by every
-- coordinate->world-position conversion after that. Local +X/+Z match the anchor's own
-- right/forward; local Y increases DOWNWARD as Depth increases (see cellCFrame below).
local originCFrame: CFrame? = nil

-- Sparse 3D grid: cells[ix][iy][iz] is one of:
--   nil    -> never generated — an "available" cell a neighbor reveal can spawn a new block into
--   Part   -> a live, mineable block currently occupies this cell
--   false  -> previously mined out — permanently empty, never regenerated
-- ix/iz run 1..GridWidth/1..GridLength (horizontal grid coordinates); iy is Depth, 0..MaxDepth,
-- increasing downward from the surface layer.
local cells: { [number]: { [number]: { [number]: any } } } = {}

local function getCell(ix: number, iy: number, iz: number): any
	local byX = cells[ix]
	local byY = byX and byX[iy]
	return byY and byY[iz]
end

local function setCell(ix: number, iy: number, iz: number, value: any)
	cells[ix] = cells[ix] or {}
	cells[ix][iy] = cells[ix][iy] or {}
	cells[ix][iy][iz] = value
end

local function inBounds(ix: number, iy: number, iz: number): boolean
	return ix >= 1 and ix <= MineShaftConfig.GridWidth
		and iz >= 1 and iz <= MineShaftConfig.GridLength
		and iy >= 0 and iy <= MineShaftConfig.MaxDepth
end

-- Maps a live block Part back to the coordinates that spawned it, so a hit on a block that's
-- already been mined out from under the player (a stale/duplicate click) is just ignored rather
-- than granting ore twice or double-revealing its neighbors.
local blockOwner: { [Instance]: { ix: number, iy: number, iz: number } } = {}

-- Per-player cooldown for Lava contact damage (MineShaftConfig.LavaTouchDamage) — one shared
-- table keyed by player rather than tracked per-block, so brushing against several Lava blocks in
-- a row still only ticks at the configured interval instead of once per block touched.
local lavaTouchDebounce: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(player)
	lavaTouchDebounce[player] = nil
end)

-- How many blocks have been successfully mined out since the last reset — see
-- MineShaftConfig.ResetBlockThreshold and performReset further down.
local totalMinedCount = 0

-- True while the mine is mid-reset (players being cleared out, grid being rebuilt) — MineShaftHit
-- rejects hits during this window rather than operating on a grid that's being torn down under it.
local isLocked = false

-- Forward-declared, actually assigned further down (after getPlayerDepth exists, which it needs
-- to find players currently inside the mine to eject). Referenced as an upvalue from the
-- MineShaftHit handler below, well above its own definition — the standard Lua/Luau
-- forward-declare pattern for that.
local performReset

-- Same forward-declare, same reason: the RecallFromMine handler needs this to check the player is
-- genuinely down in the mine, and that handler is wired up above getPlayerDepth's own definition.
-- Without the declaration here, the name inside that closure would resolve as a GLOBAL (nil) at
-- runtime rather than picking up the local defined later in the file.
local getPlayerDepth

----------------------------------------------------------------------
-- Rolling what a cell is, and (if Ore) which ore
----------------------------------------------------------------------

local function rollOreForDepth(depth: number): string
	local weights = MineShaftConfig.OreWeightBands[#MineShaftConfig.OreWeightBands].Weights
	for _, band in ipairs(MineShaftConfig.OreWeightBands) do
		if depth <= band.MaxDepth then
			weights = band.Weights
			break
		end
	end

	local total = 0
	for _, weight in pairs(weights) do
		total += weight
	end
	local roll = math.random() * total
	local cumulative = 0
	for oreKey, weight in pairs(weights) do
		cumulative += weight
		if roll <= cumulative then
			return oreKey
		end
	end
	return next(weights) or "ScrapIron" -- fallback, should be unreachable
end

-- Returns "Rock", "Hazard", "Bedrock", or ("Ore", oreKey). Bedrock is a hard floor past
-- MaxDepth — see this file's header and MineShaftConfig.MaxDepth.
local function rollKindForDepth(depth: number): (string, string?)
	if depth >= MineShaftConfig.MaxDepth then
		return "Bedrock"
	end

	local band = MineShaftConfig.KindWeightBands[#MineShaftConfig.KindWeightBands]
	for _, candidate in ipairs(MineShaftConfig.KindWeightBands) do
		if depth <= candidate.MaxDepth then
			band = candidate
			break
		end
	end

	local total = band.Rock + band.Ore + band.Hazard
	local roll = math.random() * total
	if roll <= band.Rock then
		return "Rock"
	elseif roll <= band.Rock + band.Ore then
		return "Ore", rollOreForDepth(depth)
	else
		return "Hazard"
	end
end

----------------------------------------------------------------------
-- Block construction
----------------------------------------------------------------------

-- Converts grid coordinates into a world CFrame — depth increases downward, ix/iz spread
-- horizontally around the anchor exactly like the old quarry grid did.
local function cellCFrame(ix: number, iy: number, iz: number): CFrame
	local localX = (ix - (MineShaftConfig.GridWidth + 1) / 2) * MineShaftConfig.CellSize
	local localZ = -(iz - 0.5) * MineShaftConfig.CellSize
	local localY = -(iy * MineShaftConfig.CellSize + MineShaftConfig.CellSize / 2)
	return (originCFrame :: CFrame) * CFrame.new(localX, localY, localZ)
end

-- Builds the mineable block at (ix, iy, iz), registers it in `cells`/`blockOwner`, and returns
-- it. Called both for the initial Depth-0 floor and for every neighbor reveal after that. Doesn't
-- attach a label/billboard to the block itself on purpose — with a grid this size, a persistent
-- BillboardGui on every single block would be a real performance problem. Instead
-- MineShaftController.client.lua shows one reusable hover label, reading these same Attributes
-- off whichever block the player is actually looking at.
local function buildBlock(ix: number, iy: number, iz: number): Part
	local kind, oreKey = rollKindForDepth(iy)

	local part = Instance.new("Part")
	part.Size = Vector3.new(MineShaftConfig.CellSize, MineShaftConfig.CellSize, MineShaftConfig.CellSize)
	part.Anchored = true
	part.CanCollide = true
	part.Material = Enum.Material.Rock
	part.CFrame = cellCFrame(ix, iy, iz)
	part:SetAttribute("Kind", kind)
	part:SetAttribute("Depth", iy) -- read back by the hazard loop below, and the client hover label

	if kind == "Bedrock" then
		part.Name = "Bedrock"
		part.Color = MineShaftConfig.BedrockColor
		-- Deliberately no HitsRemaining/MaxHits — MineShaftHit rejects Bedrock outright before
		-- ever touching those, so there's nothing to track.
	elseif kind == "Rock" then
		part.Name = "RockFiller"
		part.Color = MineShaftConfig.RockColor
		part:SetAttribute("HitsRemaining", MineShaftConfig.RockMaxHits)
		part:SetAttribute("MaxHits", MineShaftConfig.RockMaxHits)
	elseif kind == "Hazard" then
		part.Name = "LavaPocket"
		part.Material = Enum.Material.Neon
		part.Color = MineShaftConfig.LavaColor
		part:SetAttribute("HitsRemaining", MineShaftConfig.LavaMaxHits)
		part:SetAttribute("MaxHits", MineShaftConfig.LavaMaxHits)
		-- Small ongoing damage just for standing in/against a live Lava block — separate from (and
		-- much smaller than) MineShaftConfig.LavaDamage, the big burst dealt when one actually gets
		-- mined through. "You're touching something hot" vs. "you dug into an active pocket."
		part.Touched:Connect(function(hit: BasePart)
			local hitCharacter = hit.Parent
			local player = hitCharacter and Players:GetPlayerFromCharacter(hitCharacter)
			if not player then
				return
			end
			local now = os.clock()
			if lavaTouchDebounce[player] and now - lavaTouchDebounce[player] < MineShaftConfig.LavaTouchIntervalSeconds then
				return
			end
			lavaTouchDebounce[player] = now
			local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid:TakeDamage(MineShaftConfig.LavaTouchDamage)
			end
		end)
	else -- Ore
		local oreData = OreConfig.Ores[oreKey]
		part.Name = oreKey .. "Block"
		part.Color = MineShaftConfig.OreColors[oreKey] or Color3.fromRGB(120, 120, 120)
		part:SetAttribute("OreKey", oreKey)
		part:SetAttribute("HitsRemaining", oreData.MaxHits)
		part:SetAttribute("MaxHits", oreData.MaxHits)
	end

	part.Parent = shaftFolder
	CollectionService:AddTag(part, BLOCK_TAG)

	setCell(ix, iy, iz, part)
	blockOwner[part] = { ix = ix, iy = iy, iz = iz }

	return part
end

-- Checks the 6 face-adjacent neighbors of a just-destroyed cell and spawns a fresh block in any
-- that are still completely unexplored (nil in `cells`) and in bounds. This is what makes mining
-- feel like carving into one connected quarry instead of poking isolated single-block holes: at
-- Depth 0 every sideways neighbor is already occupied from generation, so only "down" is ever
-- available there, but from Depth 1 on, sideways neighbors are just as unexplored as the one
-- below, so tunnels naturally branch out instead of only ever going straight down.
local function revealNeighbors(ix: number, iy: number, iz: number)
	for _, offset in ipairs(MineShaftConfig.RevealNeighborOffsets) do
		local nx, ny, nz = ix + offset[1], iy + offset[2], iz + offset[3]
		if inBounds(nx, ny, nz) and getCell(nx, ny, nz) == nil then
			buildBlock(nx, ny, nz)
		end
	end
end

----------------------------------------------------------------------
-- Grid generation
----------------------------------------------------------------------

-- A low guard rail around the Depth-0 footprint's edge — NOT a full wall or an enclosure (there's
-- no pocket to seal anymore, this is real open air). Just enough to stop casually walking off the
-- edge of the quarry floor, since deeper layers only exist where you've actually dug.
local function buildSurfaceGuardRail(footprintWidth: number, footprintLength: number)
	local thickness = MineShaftConfig.WallThickness
	local height = MineShaftConfig.SurfaceGuardHeight
	local halfWidth = footprintWidth / 2
	local railSpanZ = footprintLength + thickness * 2

	local function rail(localX: number, localZ: number, sizeX: number, sizeZ: number, name: string)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = true
		part.Material = Enum.Material.Rock
		part.Color = MineShaftConfig.WallColor
		part.Size = Vector3.new(sizeX, height, sizeZ)
		part.CFrame = (originCFrame :: CFrame) * CFrame.new(localX, height / 2, localZ)
		part.Parent = shaftFolder
	end

	-- originCFrame sits at the near (front) edge, local Z = 0; the footprint extends to
	-- Z = -footprintLength, so "far" is more negative.
	rail(0, thickness / 2, footprintWidth + thickness * 2, thickness, "SurfaceGuardNear")
	rail(0, -footprintLength - thickness / 2, footprintWidth + thickness * 2, thickness, "SurfaceGuardFar")
	rail(halfWidth + thickness / 2, -footprintLength / 2, thickness, railSpanZ, "SurfaceGuardEast")
	rail(-halfWidth - thickness / 2, -footprintLength / 2, thickness, railSpanZ, "SurfaceGuardWest")
end

-- Builds just the Depth-0 floor (assumes originCFrame is already set) — split out from
-- populateGrid so a full reset (performReset, further down) can call this alone to rebuild the
-- floor without also re-deriving originCFrame or building a second, overlapping guard rail on top
-- of the one that's already there from the very first generation.
local function regenerateDepthZero()
	local placedCount = 0
	local total = MineShaftConfig.GridWidth * MineShaftConfig.GridLength
	for ix = 1, MineShaftConfig.GridWidth do
		for iz = 1, MineShaftConfig.GridLength do
			buildBlock(ix, 0, iz)
			placedCount += 1
			-- Yield periodically instead of building the whole floor in one uninterrupted
			-- stretch — keeps this from hitching the server for however long that takes.
			if placedCount % 500 == 0 then
				task.wait()
			end
		end
	end

	print(("[MineShaftService] populated %d/%d Depth-0 blocks"):format(placedCount, total))
end

-- One-time setup: finds the anchor, derives originCFrame, builds the (also one-time) guard rail,
-- then builds the Depth-0 floor. Every reset after this reuses the same cached originCFrame and
-- guard rail via regenerateDepthZero instead of calling this again.
local function populateGrid()
	local anchor = CollectionService:GetTagged(START_TAG)[1]
	if not anchor then
		warn("[MineShaftService] No Part tagged '" .. START_TAG .. "' found — skipping generation. See the README.")
		return
	end

	originCFrame = anchor.CFrame * CFrame.new(0, 0, -MineShaftConfig.ForwardOffset)

	local footprintWidth = MineShaftConfig.GridWidth * MineShaftConfig.CellSize
	local footprintLength = MineShaftConfig.GridLength * MineShaftConfig.CellSize
	buildSurfaceGuardRail(footprintWidth, footprintLength)

	regenerateDepthZero()
end

task.defer(populateGrid) -- start as soon as the anchor exists

----------------------------------------------------------------------
-- Mining a block
----------------------------------------------------------------------

Remotes.MineShaftHit.OnServerEvent:Connect(function(player: Player, block: Instance)
	if isLocked then
		Remotes.MineFailed:FireClient(player, "The mine is resetting — try again in a few seconds")
		return
	end

	if typeof(block) ~= "Instance" or not block:IsDescendantOf(Workspace) then
		return
	end

	local coords = blockOwner[block]
	if not coords or getCell(coords.ix, coords.iy, coords.iz) ~= block then
		return -- stale click — this block already got mined out from under the player
	end

	local character = player.Character
	if not character or not character.PrimaryPart then
		return
	end
	if (character.PrimaryPart.Position - block.Position).Magnitude > MAX_MINING_DISTANCE then
		return
	end

	local kind = block:GetAttribute("Kind")
	if kind == "Bedrock" then
		Remotes.MineFailed:FireClient(player, "Solid bedrock — nothing more to find this deep yet")
		return
	end

	if kind == "Ore" then
		local canMine, reason = OreGate.CanMine(player, block:GetAttribute("OreKey"))
		if not canMine then
			Remotes.MineFailed:FireClient(player, reason or "Can't mine this yet")
			return
		end
	end
	-- Rock and Hazard blocks have no gate — they're filler/danger, not something you need to earn
	-- access to.

	-- Swing pacing, same OreConfig.ToolTiers[].SwingTime source MiningService uses — the mine
	-- already gates ore on ToolTier, so a better tool paying off with faster digging here too is
	-- the consistent behavior. Enforced server-side because MineShaftHit is fire-and-forget with
	-- only a distance check in front of it: without this, a modified client could clear a block
	-- (and then the whole grid, revealing neighbors as it went) as fast as it could send packets.
	--
	-- Deliberately AFTER the Bedrock/ore-gate rejections above so a blocked hit doesn't also burn
	-- the player's swing timer, but BEFORE HitsRemaining is decremented — the decrement is the
	-- thing actually worth protecting.
	local swingProfile = DataService.Get(player)
	local swingTier = swingProfile and swingProfile.ToolTier or 1
	-- Falls back to tier 1 rather than indexing blind: this runs before the profile is known to
	-- exist on every path, and a ToolTier past the end of the table (a save written against a
	-- longer ladder, a bad value) would otherwise error inside the remote handler.
	local swingToolData = OreConfig.ToolTiers[swingTier] or OreConfig.ToolTiers[1]
	if not RateLimiter.Check(player, "MineShaftHit", swingToolData.SwingTime) then
		Remotes.MineFailed:FireClient(player, "Swinging too fast — wait for your tool to reset")
		return
	end

	local hitsRemaining = block:GetAttribute("HitsRemaining") or 0
	if hitsRemaining <= 0 then
		return -- shouldn't be reachable (the block would already be gone), but never grant on a dead one
	end
	hitsRemaining -= 1

	if hitsRemaining > 0 then
		block:SetAttribute("HitsRemaining", hitsRemaining)
		return
	end

	-- Final hit — resolve based on kind before clearing the cell.
	if kind == "Ore" then
		local oreKey = block:GetAttribute("OreKey")
		local oreData = OreConfig.Ores[oreKey]
		local profile = DataService.Get(player)
		local toolData = OreConfig.ToolTiers[profile.ToolTier]
		local yield = math.floor(oreData.BaseYield * toolData.YieldMultiplier + 0.5)
		DataService.AddOre(player, oreKey, yield)
		Remotes.InventoryUpdate:FireClient(player, { OreCounts = profile.OreCounts })

		-- Same rare Energy Drink roll every other mining hit gets (see MiningService).
		if math.random() <= RaidEnergyConfig.EnergyDrinkFindChance then
			RaidEnergyService.GrantEnergyDrink(player)
		end
	elseif kind == "Hazard" then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:TakeDamage(MineShaftConfig.LavaDamage)
		end
		Remotes.MineFailed:FireClient(player, "That was a Lava Pocket!")
	end
	-- Rock: nothing to grant — it's filler, it just clears and advances like anything else.

	local ix, iy, iz = coords.ix, coords.iy, coords.iz
	blockOwner[block] = nil
	setCell(ix, iy, iz, false) -- permanently empty now — never regenerate this cell
	block:Destroy()

	-- Spawn fresh blocks in whichever neighbors haven't been explored yet. No explicit teleport
	-- needed here — this cell is now real, ordinary open air (nothing fake about it), so the
	-- player just falls/steps into it under normal gravity, same as breaking any other block in
	-- front of them would work. That's the whole point of building this in real space instead of
	-- a relocated pocket: there's nothing left to fake.
	revealNeighbors(ix, iy, iz)

	totalMinedCount += 1
	if totalMinedCount >= MineShaftConfig.ResetBlockThreshold then
		-- performReset checks `isLocked` itself and bails if a reset's already underway, so this
		-- is safe even if several hits cross the threshold in the same tick.
		task.spawn(performReset)
	end
end)

----------------------------------------------------------------------
-- Suit upgrades — same sequential-tier pattern as MiningService.UpgradeTool
----------------------------------------------------------------------

Remotes.UpgradeSuit.OnServerInvoke = function(player: Player)
	if not PlotService.IsPlayerInOwnPlot(player) then
		return { Success = false, Reason = PlotConfig.NotInBaseMessage }
	end
	if not StationService.IsPlayerNearStation(player, "Crafting") then
		return { Success = false, Reason = StationConfig.Types.Crafting.NotThereMessage }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	local nextTier = profile.SuitTier + 1
	local nextSuitData = MineShaftConfig.SuitTiers[nextTier]
	if not nextSuitData then
		return { Success = false, Reason = "Already at the max suit tier" }
	end

	local cost = MineShaftConfig.SuitTierCosts[nextTier]
	if not cost then
		return { Success = false, Reason = "No cost configured for this tier — add one to MineShaftConfig.SuitTierCosts" }
	end

	local spent = DataService.TrySpend(player, cost)
	if not spent then
		return { Success = false, Reason = "Not enough resources" }
	end

	profile.SuitTier = nextTier
	Remotes.InventoryUpdate:FireClient(player, {
		OreCounts = profile.OreCounts,
		SuitTier = profile.SuitTier,
	})

	return { Success = true, SuitTier = profile.SuitTier }
end

----------------------------------------------------------------------
-- Recall — get back to the surface without having to climb out. Requested specifically because
-- the mine has no ladder/climb-out mechanic yet: once you're a few levels down, walking back up
-- isn't possible on your own, so there needs to be a way out that isn't "get stuck."
----------------------------------------------------------------------

Remotes.RecallFromMine.OnServerEvent:Connect(function(player: Player)
	-- This remote had NO validation at all, which made it a free full-heal on demand: LoadCharacter
	-- respawns at full health, so binding this to a key made the player effectively unkillable
	-- anywhere in the game — including mid-Combat-Outpost raid, while NodeService.runRaid was
	-- actively ticking damage against them. The two checks below scope it back to what it's
	-- actually for: getting OUT of the mine when there's no way to climb back up.
	local character = player.Character
	if not character then
		return
	end

	-- Actually in the mine? getPlayerDepth raycasts down onto live shaft blocks, so this is nil
	-- for anyone standing anywhere else in the world — including on the mine's own surface guard
	-- rail, which is correct: you can walk off that.
	if getPlayerDepth(character) == nil then
		Remotes.MineFailed:FireClient(player, "Recall only works while you're down in the mine")
		return
	end

	-- Paced as well as gated. Recall is a full heal, so even legitimately inside the mine it
	-- shouldn't be spammable as a heal button during the depth-hazard damage loop.
	if not RateLimiter.Check(player, "RecallFromMine", MineShaftConfig.RecallCooldownSeconds) then
		Remotes.MineFailed:FireClient(player, "Recall is still recharging")
		return
	end

	-- LoadCharacter respawns the player at a normal Roblox SpawnLocation, at full health — same
	-- "you're safely out, here's a clean slate" idea as Return to Base healing you on Expedition
	-- exit. Inventory/profile data is untouched (that all lives in DataService, not on the
	-- character), so nothing is lost by doing this.
	player:LoadCharacter()
end)

----------------------------------------------------------------------
-- Environmental hazards — ambient depth-based damage unless Suit tier covers it. Separate from
-- (and stacks with) the discrete Lava block kind above — this is "the air down here is
-- dangerous," Lava is "you dug into an active pocket."
----------------------------------------------------------------------

-- Raycasts a short distance down from the player's HumanoidRootPart, looking only at Parts inside
-- shaftFolder. If they're standing on (or falling toward) a live block, its Depth attribute tells
-- us exactly how deep they are — no separate per-player depth tracking needed, the world geometry
-- already knows.
-- Assigned (not declared) — see the forward declaration near the top of this file.
getPlayerDepth = function(character: Model): number?
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { shaftFolder }

	local result = Workspace:Raycast(hrp.Position, Vector3.new(0, -20, 0), raycastParams)
	if not result or not CollectionService:HasTag(result.Instance, BLOCK_TAG) then
		return nil -- not above a live block (e.g. mid-fall, or standing on the guard rail)
	end

	return result.Instance:GetAttribute("Depth")
end

----------------------------------------------------------------------
-- Full reset — see MineShaftConfig.ResetIntervalSeconds/ResetBlockThreshold/ResetLockSeconds.
----------------------------------------------------------------------

-- Tears the mine down and rebuilds it from scratch. Fired on a timer and also immediately once
-- enough has been mined (see the MineShaftHit handler above and the timer loop below). Ejects
-- anyone currently inside first, then holds the mine locked for a few seconds before actually
-- clearing/rebuilding it — both so nobody's standing on a block that's about to be destroyed out
-- from under them, and so the reset reads as an actual event instead of blocks silently swapping
-- underfoot.
performReset = function()
	if isLocked then
		return -- a reset is already underway (e.g. the timer and the block threshold landed at once)
	end
	isLocked = true
	print("[MineShaftService] Resetting the mine...")

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and getPlayerDepth(character) ~= nil then
			Remotes.MineFailed:FireClient(player, "The mine shaft collapsed and is resetting!")
			player:LoadCharacter() -- same "safely out, clean slate" respawn Recall uses
		end
	end

	task.wait(MineShaftConfig.ResetLockSeconds)

	for _, block in ipairs(CollectionService:GetTagged(BLOCK_TAG)) do
		block:Destroy()
	end
	cells = {}
	blockOwner = {}
	totalMinedCount = 0

	regenerateDepthZero()
	isLocked = false
	print("[MineShaftService] Mine reset complete")
end

-- Fires performReset on a timer regardless of how much has been dug. Independent of the
-- block-threshold trigger in MineShaftHit — the two can occasionally land close together, which
-- is harmless since performReset's own isLocked guard makes a second call while one's already
-- running a no-op.
task.spawn(function()
	while true do
		task.wait(MineShaftConfig.ResetIntervalSeconds)
		performReset()
	end
end)

-- Which raw Tier (1-3) of `hazardType` applies at `depth`, or 0 if too shallow for even Tier 1.
local function rawHazardTier(hazardType, depth: number): number
	local tier = 0
	for i, tierData in ipairs(hazardType.Tiers) do
		if depth >= tierData.MinDepth then
			tier = i
		end
	end
	return tier
end

-- Resolves how much damage `hazardType` actually deals a player standing at `depth` with the
-- given `suitTier`, applying that suit's per-hazard Tier reduction (see MineShaftConfig
-- .SuitTiers' comment — "Tier 2 becomes the new Tier 1" once gear knocks it down). Returns nil if
-- the hazard doesn't apply at all here, or the player's gear fully absorbs the current Tier.
local function resolveHazardDamage(hazardType, depth: number, suitTier: number): number?
	local tier = rawHazardTier(hazardType, depth)
	if tier == 0 then
		return nil
	end

	local suitData = MineShaftConfig.SuitTiers[suitTier]
	local protection = (suitData and suitData.Protection and suitData.Protection[hazardType.Key]) or 0
	local effectiveTier = tier - protection
	if effectiveTier <= 0 then
		return nil -- gear fully covers whatever Tier is actually present here
	end

	return hazardType.Tiers[effectiveTier].BaseDamage
end

-- Fast loop, just for the client's depth readout (DepthUpdate fires every tick regardless of
-- hazard state, with nil when the player isn't in the mine at all, so the HUD can hide its depth
-- panel/Recall button). Deliberately its OWN loop on MineShaftConfig.DepthReportIntervalSeconds
-- rather than sharing the slower hazard-damage loop below — the HUD updating a couple seconds
-- late after you stop moving reads as broken, but hazard damage ticking that fast would need every
-- DamagePerTick number retuned to match. Same shared-loop-over-every-player pattern as
-- RaidEnergyService's regen loop and AutoMinerService's passive tick — one loop, not a per-player
-- timer.
task.spawn(function()
	while true do
		task.wait(MineShaftConfig.DepthReportIntervalSeconds)
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if character and humanoid and humanoid.Health > 0 then
				Remotes.DepthUpdate:FireClient(player, getPlayerDepth(character))
			end
		end
	end
end)

-- Slower loop, just for ambient hazard damage — see MineShaftConfig.HazardCheckIntervalSeconds's
-- comment for why this stays decoupled from the fast depth-report loop above. Heat and Toxic Air
-- are now resolved and applied independently every tick (see resolveHazardDamage) — deep enough
-- for both, you take both hits in the same tick, not just whichever one is "worse."
task.spawn(function()
	while true do
		task.wait(MineShaftConfig.HazardCheckIntervalSeconds)
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if character and humanoid and humanoid.Health > 0 then
				local depth = getPlayerDepth(character)
				if depth then
					local profile = DataService.Get(player)
					local suitTier = (profile and profile.SuitTier) or 1
					for _, hazardType in ipairs(MineShaftConfig.HazardTypes) do
						local damage = resolveHazardDamage(hazardType, depth, suitTier)
						if damage then
							humanoid:TakeDamage(damage)
						end
					end
				end
			end
		end
	end
end)

return MineShaftService
