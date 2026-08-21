--[[
	ExpeditionService.lua
	Procedurally lays out a chain of Node instances (Heal/Shop/Combat, same NodeService
	handles them regardless of how they were created) stretching out from a hand-placed
	anchor. This is the "loop of 5-8 nodes with a fork every few steps" mechanic.

	How it works:
	  1. Find the Part tagged "ExpeditionStart" — its position and facing (-Z / LookVector)
	     define where the path begins and which way it runs.
	  2. Walk forward SlotSpacing studs at a time for a random 5-8 slots — spacing is kept
	     short (ExpeditionConfig.SlotSpacing) so the whole path stays close to the anchor
	     instead of trailing off into the distance.
	  3. Every 3rd slot (ExpeditionConfig.ForkInterval) is a FORK: two node options appear
	     side by side, each independently rolled. Interacting with either one (a completed
	     heal, a shop purchase, or a cleared raid) destroys its sibling — the path commits to
	     whichever you engaged with. Every other slot has a flat 30% chance of holding a
	     single node at all, so slot count and node count both vary run to run — EXCEPT that
	     ExpeditionConfig.MinTotalNodes forces extra nodes into empty slots if a run rolls too
	     sparse, and ExpeditionConfig.MaxCombatNodes stops Combat from being rolled once a
	     path already has that many fights.
	  4. Combat nodes spawned this way are one-time: NodeService destroys them after a
	     successful raid, unlike the permanent hand-placed nodes near base.
	  5. A thin, non-collide strip is laid between each consecutive path point (including
	     both branches of a fork) so the route is actually visible underfoot, not just a line
	     of floating nodes.

	A Part tagged "ExpeditionLever" lets players regenerate the whole path on demand — pulling
	it clears every currently-spawned expedition node and rolls a new layout.

	NOTE: this drives ONE shared path in the world, not a separate instance per player/party.
	That's fine for prototyping the mechanic solo, but if this ships to real concurrent
	players you'll want each party running their own instanced expedition area so they can't
	block or race each other for the same nodes — a bigger architectural change than this
	scaffold takes on.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ExpeditionConfig = require(ReplicatedStorage.Shared.ExpeditionConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local START_TAG = "ExpeditionStart"
local LEVER_TAG = "ExpeditionLever"
local NODE_TAG = "Node"

local NODE_COLORS = {
	Combat = Color3.fromRGB(178, 76, 24),
	Shop = Color3.fromRGB(53, 96, 107),
	Heal = Color3.fromRGB(79, 140, 100),
}

local ExpeditionService = {}

local expeditionFolder = Workspace:FindFirstChild("Expedition")
if not expeditionFolder then
	expeditionFolder = Instance.new("Folder")
	expeditionFolder.Name = "Expedition"
	expeditionFolder.Parent = Workspace
end

----------------------------------------------------------------------
-- Node construction
----------------------------------------------------------------------

local function buildNode(nodeType: string, tier: number?, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = nodeType .. "Node"
	part.Size = Vector3.new(6, 6, 6)
	part.Anchored = true
	part.CanCollide = true
	part.Color = NODE_COLORS[nodeType] or Color3.fromRGB(120, 120, 120)
	part.Material = Enum.Material.Metal
	part.CFrame = cframe
	part:SetAttribute("IsExpeditionNode", true)

	local nodeTypeValue = Instance.new("StringValue")
	nodeTypeValue.Name = "NodeType"
	nodeTypeValue.Value = nodeType
	nodeTypeValue.Parent = part

	if nodeType == "Combat" then
		local tierValue = Instance.new("NumberValue")
		tierValue.Name = "Tier"
		tierValue.Value = tier or 1
		tierValue.Parent = part
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.new(0, 140, 0, 36)
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.SourceSansBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextSize = 18
	label.Text = tier and ("%s · T%d"):format(nodeType, tier) or nodeType
	label.Parent = billboard

	part.Parent = expeditionFolder
	CollectionService:AddTag(part, NODE_TAG)

	return part
end

local function linkSiblings(a: Part, b: Part)
	local aRef = Instance.new("ObjectValue")
	aRef.Name = "SiblingNode"
	aRef.Value = b
	aRef.Parent = a

	local bRef = Instance.new("ObjectValue")
	bRef.Name = "SiblingNode"
	bRef.Value = a
	bRef.Parent = b
end

-- Rolls a node type but refuses to hand out any more Combat nodes once the path has already
-- hit ExpeditionConfig.MaxCombatNodes — falls back to Shop if it keeps rolling Combat anyway.
local function rollNodeTypeCapped(combatCount: number): string
	for _ = 1, 8 do
		local nodeType = ExpeditionConfig.RollNodeType()
		if nodeType ~= "Combat" or combatCount < ExpeditionConfig.MaxCombatNodes then
			return nodeType
		end
	end
	return "Shop"
end

-- A thin, non-collide strip between two points so the path actually reads as a path underfoot,
-- not just a line of floating nodes.
local function buildPathSegment(fromPos: Vector3, toPos: Vector3)
	local distance = (toPos - fromPos).Magnitude
	if distance < 0.5 then
		return
	end

	local segment = Instance.new("Part")
	segment.Name = "PathSegment"
	segment.Size = Vector3.new(4, 0.2, distance)
	segment.Anchored = true
	segment.CanCollide = false
	segment.Material = Enum.Material.Ground
	segment.Color = Color3.fromRGB(96, 84, 68)
	segment.CFrame = CFrame.lookAt(fromPos:Lerp(toPos, 0.5), toPos)
	segment.Parent = expeditionFolder
end

----------------------------------------------------------------------
-- Path generation
----------------------------------------------------------------------

local function clearExpedition()
	for _, child in ipairs(expeditionFolder:GetChildren()) do
		child:Destroy()
	end
end

local function generateExpedition()
	local anchor = CollectionService:GetTagged(START_TAG)[1]
	if not anchor then
		warn("[ExpeditionService] No Part tagged '" .. START_TAG .. "' found — skipping generation. See the README.")
		return
	end

	clearExpedition()

	local pathLength = math.random(ExpeditionConfig.PathLengthMin, ExpeditionConfig.PathLengthMax)
	local cursor = anchor.CFrame
	local previousPoint = anchor.Position

	local combatCount = 0
	local totalNodeCount = 0
	local openSlots = {} -- regular slots that rolled no node; fallback spots if we come up short of the floor

	for slotIndex = 1, pathLength do
		cursor = cursor * CFrame.new(0, 0, -ExpeditionConfig.SlotSpacing)
		local tier = ExpeditionConfig.GetTierForSlot(slotIndex)

		if slotIndex % ExpeditionConfig.ForkInterval == 0 then
			local leftCFrame = cursor * CFrame.new(-ExpeditionConfig.ForkLateralOffset, 0, 0)
			local rightCFrame = cursor * CFrame.new(ExpeditionConfig.ForkLateralOffset, 0, 0)

			local leftType = rollNodeTypeCapped(combatCount)
			if leftType == "Combat" then
				combatCount += 1
			end
			local rightType = rollNodeTypeCapped(combatCount)
			if rightType == "Combat" then
				combatCount += 1
			end

			local leftNode = buildNode(leftType, leftType == "Combat" and tier or nil, leftCFrame)
			local rightNode = buildNode(rightType, rightType == "Combat" and tier or nil, rightCFrame)
			linkSiblings(leftNode, rightNode)
			totalNodeCount += 2

			buildPathSegment(previousPoint, leftCFrame.Position)
			buildPathSegment(previousPoint, rightCFrame.Position)
		else
			if math.random() <= ExpeditionConfig.NodeSpawnChance then
				local nodeType = rollNodeTypeCapped(combatCount)
				if nodeType == "Combat" then
					combatCount += 1
				end
				buildNode(nodeType, nodeType == "Combat" and tier or nil, cursor)
				totalNodeCount += 1
			else
				table.insert(openSlots, { CFrame = cursor, Tier = tier })
			end
			buildPathSegment(previousPoint, cursor.Position)
		end

		previousPoint = cursor.Position
	end

	-- Floor: if RNG left us under MinTotalNodes, force extra nodes into random slots that
	-- rolled empty until we hit it (there are always enough open/fork slots to reach 5+ given
	-- PathLengthMin = 5).
	while totalNodeCount < ExpeditionConfig.MinTotalNodes and #openSlots > 0 do
		local pickIndex = math.random(1, #openSlots)
		local slot = table.remove(openSlots, pickIndex)
		local nodeType = rollNodeTypeCapped(combatCount)
		if nodeType == "Combat" then
			combatCount += 1
		end
		buildNode(nodeType, nodeType == "Combat" and slot.Tier or nil, slot.CFrame)
		totalNodeCount += 1
	end
end

----------------------------------------------------------------------
-- Lever + startup
----------------------------------------------------------------------

Remotes.RegenerateExpedition.OnServerEvent:Connect(function(player: Player, lever: Instance)
	if typeof(lever) ~= "Instance" or not CollectionService:HasTag(lever, LEVER_TAG) then
		return
	end
	generateExpedition()
end)

task.defer(generateExpedition) -- roll an initial path as soon as the anchor exists

return ExpeditionService
