--[[
	ResourceZoneService.lua
	Procedurally scatters ore nodes in a ring around the base anchor — the same Part tagged
	"ExpeditionStart" that the Expedition queue and EnvironmentFX's distance fog already treat
	as "the base." This is the third system to reuse it on purpose, so there's still only one
	Part to place in the whole map. Further from the anchor skews toward rarer, higher-tier ore
	(ResourceZoneConfig.OreWeightBands) — the same "go further = better, but more remote" idea
	as everything else out here.

	Every spawned node is tagged "OreNode" (the same tag MiningController already listens for)
	with a StringValue "OreType" child (the same convention hand-placed ore nodes already use)
	— so MiningService and MiningController don't need to know or care whether a given node was
	placed by hand in Studio or generated here. Depletion/respawn (HitsRemaining/Depleted
	attributes) is handled entirely by MiningService, not here — this module's only job is
	placing nodes on valid ground and picking what ore each one is.

	Placement: for each node, roll a random angle/radius around the anchor (skipping a cone
	around the Expedition lane direction so the two systems don't overlap), raycast straight
	down to find real ground at that XZ, and only accept the spot if it's far enough from every
	already-placed node. A spot that fails (off the edge of the map, too crowded) is retried a
	few times, then skipped — see the Output window for a summary of how many nodes actually
	got placed.

	This runs once at server start and does NOT regenerate on a lever like Expedition does —
	nodes stay put and depletion/respawn keeps the zone feeling fresh over time instead of the
	whole layout reshuffling. Add a lever-triggered regenerate remote later if you also want the
	zone's layout to reshuffle on demand.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ResourceZoneConfig = require(ReplicatedStorage.Shared.ResourceZoneConfig)
local OreConfig = require(ReplicatedStorage.Shared.OreConfig)

local START_TAG = "ExpeditionStart"
local ORE_NODE_TAG = "OreNode"

local ResourceZoneService = {}

local zoneFolder = Workspace:FindFirstChild("ResourceZone")
if not zoneFolder then
	zoneFolder = Instance.new("Folder")
	zoneFolder.Name = "ResourceZone"
	zoneFolder.Parent = Workspace
end

----------------------------------------------------------------------
-- Ore rolling
----------------------------------------------------------------------

local function rollOreType(distance: number): string
	local weights = ResourceZoneConfig.OreWeightBands[#ResourceZoneConfig.OreWeightBands].Weights
	for _, band in ipairs(ResourceZoneConfig.OreWeightBands) do
		if distance <= band.MaxDistance then
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

----------------------------------------------------------------------
-- Node construction
----------------------------------------------------------------------

local function buildOreNode(oreKey: string, position: Vector3): Part
	local oreData = OreConfig.Ores[oreKey]

	local part = Instance.new("Part")
	part.Name = oreKey .. "OreNode"
	part.Size = ResourceZoneConfig.NodeSize
	part.Anchored = true
	part.CanCollide = true
	part.Material = Enum.Material.Rock
	part.Color = ResourceZoneConfig.NodeColors[oreKey] or Color3.fromRGB(120, 120, 120)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	part:SetAttribute("HitsRemaining", oreData.MaxHits)
	part:SetAttribute("Depleted", false)

	local oreTypeValue = Instance.new("StringValue")
	oreTypeValue.Name = "OreType"
	oreTypeValue.Value = oreKey
	oreTypeValue.Parent = part

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.new(0, 150, 0, 32)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.SourceSansBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextSize = 16
	label.Text = ("%s (%d/%d)"):format(oreData.DisplayName, oreData.MaxHits, oreData.MaxHits)
	label.Parent = billboard

	part.Parent = zoneFolder
	CollectionService:AddTag(part, ORE_NODE_TAG)

	return part
end

----------------------------------------------------------------------
-- Placement
----------------------------------------------------------------------

-- Raycasts straight down from well above the map to find real ground at (x, z). Returns nil if
-- nothing was hit (e.g. off the edge of a small test baseplate) so the caller can retry
-- elsewhere instead of placing a floating node.
local function findGroundPosition(x: number, z: number, anchorY: number, raycastParams: RaycastParams): Vector3?
	local origin = Vector3.new(x, anchorY + ResourceZoneConfig.RaycastHeight, z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -ResourceZoneConfig.RaycastHeight * 2, 0), raycastParams)
	if not result then
		return nil
	end
	return result.Position + Vector3.new(0, ResourceZoneConfig.NodeSize.Y / 2, 0)
end

-- candidateDir and laneDir are both unit Vector2s on the XZ plane; true if candidateDir falls
-- inside the excluded cone centered on laneDir.
local function isWithinLaneCone(candidateDir: Vector2, laneDir: Vector2): boolean
	local cosAngle = candidateDir:Dot(laneDir)
	return cosAngle > math.cos(math.rad(ResourceZoneConfig.LaneExcludeConeDegrees))
end

local function populateZone()
	local anchor = CollectionService:GetTagged(START_TAG)[1]
	if not anchor then
		warn("[ResourceZoneService] No Part tagged '" .. START_TAG .. "' found — skipping generation. See the README.")
		return
	end

	local anchorPosition = anchor.Position
	local laneDirRaw = Vector2.new(anchor.CFrame.LookVector.X, anchor.CFrame.LookVector.Z)
	local laneDir = laneDirRaw.Magnitude > 0.001 and laneDirRaw.Unit or Vector2.new(0, -1)

	local expeditionFolder = Workspace:FindFirstChild("Expedition")
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = expeditionFolder and { zoneFolder, expeditionFolder } or { zoneFolder }

	local placed = {} -- list of Vector3 positions already used, for spacing checks

	for _ = 1, ResourceZoneConfig.NodeCount do
		local placedThisNode = false

		for _attempt = 1, ResourceZoneConfig.MaxPlacementAttempts do
			local angle = math.random() * math.pi * 2
			local candidateDir = Vector2.new(math.cos(angle), math.sin(angle))

			if not isWithinLaneCone(candidateDir, laneDir) then
				local radius = ResourceZoneConfig.MinRadius
					+ math.random() * (ResourceZoneConfig.MaxRadius - ResourceZoneConfig.MinRadius)
				local x = anchorPosition.X + candidateDir.X * radius
				local z = anchorPosition.Z + candidateDir.Y * radius

				local tooClose = false
				for _, existing in ipairs(placed) do
					if (Vector2.new(x, z) - Vector2.new(existing.X, existing.Z)).Magnitude < ResourceZoneConfig.MinNodeSpacing then
						tooClose = true
						break
					end
				end

				if not tooClose then
					local groundPosition = findGroundPosition(x, z, anchorPosition.Y, raycastParams)
					if groundPosition then
						local oreKey = rollOreType(radius)
						buildOreNode(oreKey, groundPosition)
						table.insert(placed, groundPosition)
						placedThisNode = true
						break
					end
				end
			end
		end

		if not placedThisNode then
			warn(("[ResourceZoneService] Couldn't find a valid spot for a node after %d attempts — skipping it. "
				.. "If this happens a lot, MaxRadius is probably bigger than your map."):format(
				ResourceZoneConfig.MaxPlacementAttempts))
		end
	end

	print(("[ResourceZoneService] populated %d/%d ore nodes"):format(#placed, ResourceZoneConfig.NodeCount))
end

task.defer(populateZone) -- start as soon as the anchor exists

return ResourceZoneService
