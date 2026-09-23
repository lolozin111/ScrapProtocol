--[[
	MineShaftService.lua
	The dig-down mine — a real 3D voxel grid (MineShaftConfig.GridWidth x GridLength cells, 16
	square by default, at 12 studs a cell: a 192 x 192 stud footprint) starting from a Part tagged
	"MineShaftStart". This REPLACES two earlier
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
local ToolModConfig = require(ReplicatedStorage.Shared.ToolModConfig)
local DroneService = require(script.Parent.DroneService)
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
local MAX_MINING_DISTANCE = 24 -- studs; two cells at MineShaftConfig.CellSize (12) — a block this
                                -- big puts its own centre further from you than the old 6-stud one did,
                                -- so the old 12 rejected ordinary sideways mining. Keep in lockstep with
                                -- MineShaftController.client.lua's CLICK_DISTANCE.

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
-- Reset-progress sign — a world-space BillboardGui floating above the mine, showing the same
-- "N / Threshold BLOCKS" progress the HUD used to carry in a top-centre bar (MineResetBar.lua,
-- deleted — it crowded the player's screen; see DESIGN_NOTES.md/commit history for the request that
-- replaced it). A BillboardGui already faces each client's own camera on its own — no hand-rolled
-- facing math needed — so building and updating ONE instance here, server-side, means every player
-- looks at the exact same sign instead of each client keeping a synced copy over a remote. That's
-- also why MineResetUpdate was removed from default.project.json: nothing needs it anymore, every
-- reader of this state is now a plain Instance property this file sets directly.
----------------------------------------------------------------------

local SIGN_UPDATE_INTERVAL = 1 -- seconds between periodic refreshes; state-change call sites below
                                -- (lock starting, reset finishing) update immediately on top of this
                                -- so those two transitions never wait out the tick. Same reasoning
                                -- MAX_MINING_DISTANCE above gets for staying a local instead of a
                                -- MineShaftConfig entry — this is a refresh-rate knob, not gameplay.

local SIGN_HEIGHT_ABOVE_SURFACE = 40 -- studs above the Depth-0 floor's top surface (local Y = 0 in
	-- cellCFrame's coordinate space — see its comment) the sign floats at. Picked by eye, not
	-- derived from MineShaftConfig.SurfaceGuardHeight: that value only sizes the low guard rail
	-- around the floor's edge and has nothing to do with how high a sign needs to float to be seen
	-- across a 192x192 footprint, so this stays its own constant rather than reusing that one.
local SIGN_WIDTH_STUDS = 120 -- BillboardGui.Size, unlike every other GuiObject's, is denominated in
local SIGN_HEIGHT_STUDS = 30 -- STUDS even for its Offset component — a fixed world-space size that
	-- shrinks with distance like any other object, not a fixed on-screen pixel size the way a
	-- ScreenGui's would be. First pass was 34x13 and the user could not read it at all from the pit's
	-- edge ("its too small, i cant see anything, make it a big rectangle"): against a 192-stud
	-- footprint, a 34-stud sign is barely a sixth of the pit's width. 120 makes it read as signage
	-- over the quarry — deliberately more than half the footprint wide.
local SIGN_MAX_VIEW_DISTANCE = 1200 -- studs; the sign is big enough now to be worth seeing from
	-- across the map, and 650 cut it off well before it stopped being legible.

-- HudKit lives under StarterPlayerScripts — a client-only container this server-side file can't
-- (and shouldn't) require across — so this mirrors the handful of palette values it needs, exactly
-- like ReplicatedFirst/LoadingScreen.client.lua keeps its own copy of a few HudKit colors for the
-- same reason (it can't require HudKit either, since it runs before replication).
local SIGN_TEXT_COLOR = Color3.fromRGB(237, 231, 220)  -- HudKit.COLOR.Text
local SIGN_BAD_COLOR = Color3.fromRGB(255, 70, 45)     -- HudKit.COLOR.Bad, pushed hot: this sign is
	-- read from across a desert, where the HUD's muted (190, 90, 75) reads as brown, not alarm.
-- Deliberately NOT HudKit values: the HUD's palette is muted because it sits over the game, while
-- this sign competes with open sky and pale sand from 300 studs away and has to win.
local SIGN_TRACK_COLOR = Color3.fromRGB(28, 22, 18)    -- near-black, so the fill reads as lit
local SIGN_FILL_COLOR = Color3.fromRGB(255, 125, 30)   -- saturated orange, the family HudKit.Accent
	-- belongs to but at full chroma
local SIGN_FILL_HOT_COLOR = Color3.fromRGB(255, 205, 60) -- the gradient's far end

-- "5000" reads as a threshold you have to count digits on; "5,000" reads at a glance. Ported
-- verbatim from the deleted MineResetBar.lua rather than retyped — see the house style note in
-- CLAUDE.md about extracting exact text instead of hand-retyping UI helpers.
local function withCommas(value: number): string
	local text = tostring(math.floor(value))
	while true do
		local replaced, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		text = replaced
		if count == 0 then
			break
		end
	end
	return text
end

-- Assigned once by buildResetSign (called from populateGrid) and read/written by updateResetSign
-- after that. nil until then, so every updateResetSign call guards on signReadout being set —
-- SIGN_UPDATE_INTERVAL's periodic loop starts immediately at file load, well before populateGrid
-- (itself task.defer'd) has necessarily run.
local signReadout: TextLabel? = nil
local signFill: Frame? = nil

-- Builds the reset-progress sign once: an invisible, non-collidable/queryable/touchable anchor Part
-- centred over the Depth-0 footprint (local X = 0, same left-right centring cellCFrame uses; local
-- Z = -footprintLength / 2, the midpoint between the near edge at Z = 0 and the far edge at
-- Z = -footprintLength) and floating SIGN_HEIGHT_ABOVE_SURFACE studs above it, carrying a
-- BillboardGui styled like the deleted HUD bar (dark plate, Line-colored border, Accent fill).
-- Parented into shaftFolder alongside the guard rail so both get cleaned up/rebuilt with everything
-- else, but — like the guard rail — NOT tagged BLOCK_TAG, so performReset's "destroy every
-- BLOCK_TAG part" sweep leaves it standing.
-- Only needs footprintLength (for the Z centring below) — footprintWidth isn't a parameter because
-- cellCFrame's own local-X formula already centres ix = 1..GridWidth on local X = 0, same as
-- originCFrame's, so there's no separate width-centring math to do here.
local function buildResetSign(footprintLength: number)
	local anchor = Instance.new("Part")
	anchor.Name = "MineResetSignAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = (originCFrame :: CFrame) * CFrame.new(0, SIGN_HEIGHT_ABOVE_SURFACE, -footprintLength / 2)
	anchor.Parent = shaftFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MineResetSign"
	billboard.Adornee = anchor
	billboard.Size = UDim2.new(0, SIGN_WIDTH_STUDS, 0, SIGN_HEIGHT_STUDS) -- studs, not pixels — see
		-- SIGN_WIDTH_STUDS/SIGN_HEIGHT_STUDS's comment above
	billboard.MaxDistance = SIGN_MAX_VIEW_DISTANCE
	billboard.LightInfluence = 0 -- flat, HUD-like colors regardless of the mine's actual lighting
	billboard.Parent = anchor

	-- Layout, straight off the user's own sketch (2026-09-22): the COUNT is the loud part, sitting
	-- big above a fat pill-shaped bar, with "MINE RESET" as a small caption underneath. The first
	-- version was a dark HUD plate with the label on top and the numbers small at the bottom, and it
	-- read as "eee idk, its not smth players would catch their attention" against a desert map. So:
	-- no panel behind it (the sketch has none — the bar just floats), and saturated colors rather
	-- than the HUD's deliberately-drab browns, which vanish against sand.
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.BackgroundTransparency = 1
	plate.Size = UDim2.new(1, 0, 1, 0)
	plate.Parent = billboard

	-- Every label is TextScaled against a fraction of the plate's height: BillboardGui text has no
	-- meaningful pixel/stud relationship, so a fixed TextSize would be meaningless here.
	local readout = Instance.new("TextLabel")
	readout.Name = "Readout"
	readout.BackgroundTransparency = 1
	readout.Size = UDim2.new(1, 0, 0.52, 0)
	readout.Font = Enum.Font.GothamBlack
	readout.Text = ""
	readout.TextColor3 = SIGN_TEXT_COLOR
	readout.TextScaled = true
	readout.TextStrokeColor3 = Color3.new(0, 0, 0)
	readout.TextStrokeTransparency = 0.35 -- the sign floats against open sky and pale sand; without
		-- an outline the white count washes out on the bright half of that background
	readout.Parent = plate

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = SIGN_TRACK_COLOR
	track.BorderSizePixel = 0
	track.Position = UDim2.new(0, 0, 0.58, 0)
	track.Size = UDim2.new(1, 0, 0.4, 0)
	track.Parent = plate
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0) -- fully round ends: the sketch's pill
	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = SIGN_FILL_COLOR
	trackStroke.Thickness = 3
	trackStroke.Transparency = 0.45
	trackStroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = SIGN_FILL_COLOR
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	-- Hot orange into yellow across the fill — one flat color still read as a stripe; the gradient is
	-- what makes it look lit from inside at a distance.
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new(SIGN_FILL_COLOR, SIGN_FILL_HOT_COLOR)
	fillGradient.Parent = fill

	-- No caption: a "MINE RESET" line under the bar was too small to read at the distance this sign
	-- is actually looked at from, so it was only adding clutter (the user's call, 2026-09-22). The
	-- count over a filling bar, floating above the pit, says what it is on its own.

	signFill = fill
	signReadout = readout
end

-- Updates the sign in place — called immediately on the two state transitions that actually matter
-- (the reset lock starting, the rebuilt mine coming back online) plus a periodic tick besides, same
-- cadence the old HUD bar's broadcast used. Mirrors MineResetBar.lua's now-deleted refresh() exactly
-- (RESETTING… in Bad during the lock, "N / Threshold BLOCKS" otherwise) since the information it's
-- presenting hasn't changed, only where it's rendered.
local function updateResetSign()
	if not signReadout or not signFill then
		return -- buildResetSign hasn't run yet (still waiting on populateGrid/its anchor tag)
	end

	if isLocked then
		signReadout.Text = "RESETTING…"
		signFill.BackgroundColor3 = SIGN_BAD_COLOR
		signFill.Size = UDim2.new(1, 0, 1, 0)
		return
	end

	local threshold = math.max(1, MineShaftConfig.ResetBlockThreshold)
	local mined = math.clamp(totalMinedCount, 0, threshold)
	-- Just the two numbers, per the sketch ("2400 5000" written big above the bar) — the word BLOCKS
	-- cost a third of the line's width to say what the sign's own position over the pit already says.
	signReadout.Text = ("%s / %s"):format(withCommas(mined), withCommas(threshold))
	signFill.BackgroundColor3 = SIGN_FILL_COLOR
	signFill.Size = UDim2.new(mined / threshold, 0, 1, 0)
end

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
	return next(weights) or "IronOre" -- fallback, should be unreachable
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
		-- Metal, where Rock/Bedrock stay Enum.Material.Rock: the saturated ore colours do most of the
		-- "this one is worth something" work, but a sheen next to matte rock is what makes an ore seam
		-- readable from across the quarry rather than only once you're standing on it.
		part.Material = Enum.Material.Metal
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

-- One-time setup: finds the anchor, derives originCFrame, builds the (also one-time) guard rail and
-- reset-progress sign, then builds the Depth-0 floor. Every reset after this reuses the same cached
-- originCFrame/guard rail/sign via regenerateDepthZero instead of calling this again.
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
	buildResetSign(footprintLength)
	updateResetSign() -- give it real numbers immediately instead of leaving "0 / 0 BLOCKS" showing
		-- until the first periodic tick (SIGN_UPDATE_INTERVAL seconds later)

	regenerateDepthZero()
end

task.defer(populateGrid) -- start as soon as the anchor exists

----------------------------------------------------------------------
-- Mining a block
----------------------------------------------------------------------

-- Grants a block's contents and clears its cell. Extracted so the Split-Head Pick's blast can reuse
-- the exact same resolution for the neighbours it shears loose — a second copy would drift, and the
-- two ore gates in this codebase already proved how that ends.
local function clearBlock(player: Player, character: Model, block: Instance, coords, kind: string)
	if kind == "Ore" then
		local oreKey = block:GetAttribute("OreKey")
		local oreData = OreConfig.Ores[oreKey]
		local profile = DataService.Get(player)
		local toolData = OreConfig.ToolTiers[profile.ToolTier]
		local yield = math.floor(
			oreData.BaseYield * ToolModConfig.YieldMultiplier(profile, toolData.YieldMultiplier) + 0.5)
		yield += DroneService.BonusOreFor(player, oreKey, yield) -- Scavenger Core; 0 for every other
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
end

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

	-- HumanoidRootPart, not character.PrimaryPart — see MiningService's matching comment;
	-- PrimaryPart is not guaranteed to be set on a character model.
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end
	if (rootPart.Position - block.Position).Magnitude > MAX_MINING_DISTANCE then
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
	if not RateLimiter.Check(player, "MineShaftHit", ToolModConfig.SwingTime(swingProfile, swingToolData.SwingTime)) then
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

	clearBlock(player, character, block, coords, kind)

	-- Split-Head Pick: shears the face-adjacent cells loose along with the one you hit. Applied AFTER
	-- the target so the player always gets what they actually aimed at even if something below goes
	-- wrong, and skipping Hazards deliberately — setting off a lava pocket you never touched, from a
	-- cell you may not even be able to see, would be a punishment with no tell in front of it.
	local blast = ToolModConfig.BlastRadius(swingProfile)
	if blast > 0 then
		for _, offset in ipairs(MineShaftConfig.RevealNeighborOffsets) do
			local nx, ny, nz = coords.ix + offset[1], coords.iy + offset[2], coords.iz + offset[3]
			local neighbour = inBounds(nx, ny, nz) and getCell(nx, ny, nz)
			-- getCell returns false for an already-mined cell and nil for an unexplored one, so this
			-- only ever picks up a real live block Part.
			if neighbour and typeof(neighbour) == "Instance" then
				local neighbourCoords = blockOwner[neighbour]
				local neighbourKind = neighbour:GetAttribute("Kind")
				if neighbourCoords and neighbourKind ~= "Hazard" and neighbourKind ~= "Bedrock" then
					clearBlock(player, character, neighbour, neighbourCoords, neighbourKind)
				end
			end
		end
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

	local result = Workspace:Raycast(hrp.Position, Vector3.new(0, -40, 0), raycastParams) -- ~3.3 cells at CellSize 12, the reach -20 gave at 6
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
	updateResetSign() -- immediate, not the next periodic tick — "RESETTING…" should appear the
		-- instant the lock starts, not up to SIGN_UPDATE_INTERVAL seconds late
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
	updateResetSign() -- immediate, same reasoning as the lock-start call above: a fresh
		-- 0 / Threshold sign the instant mining is legal again, not up to a second late
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

-- Periodic reset-progress refresh — see SIGN_UPDATE_INTERVAL's comment above for why this stays a
-- cheap tick instead of firing once per mined block. Also the mechanism that gives a player who
-- joins mid-run a correct sign within one tick instead of whatever it happened to show at boot.
task.spawn(function()
	while true do
		updateResetSign()
		task.wait(SIGN_UPDATE_INTERVAL)
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
