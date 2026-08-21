--[[
	MiningService.lua
	Handles ore-node hits. The client only ever says "I hit this node" — the server decides
	whether that's legal (tool tier, unlock gate, distance) and how much ore it's worth.
	Never let the client tell the server how much ore to grant.

	Expects ore nodes in the workspace to be Parts/Models tagged with a StringValue named
	"OreType" whose value matches a key in OreConfig.Ores (e.g. "ScrapIron"). Tag your map's
	ore nodes this way in Studio — no code changes needed to add more nodes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OreConfig = require(ReplicatedStorage.Shared.OreConfig)
local DataService = require(script.Parent.DataService)

local Remotes = ReplicatedStorage.Remotes
local MineNode = Remotes.MineNode

local MAX_MINING_DISTANCE = 12 -- studs; reject hits from further away than this

local MiningService = {}

local function getOreTypeFromNode(node: Instance): string?
	local marker = node:FindFirstChild("OreType")
	if marker and marker:IsA("StringValue") then
		return marker.Value
	end
	return nil
end

local function playerCanMine(player: Player, oreKey: string): boolean
	local oreData = OreConfig.Ores[oreKey]
	if not oreData then
		return false
	end
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	if oreData.MinToolTier and profile.ToolTier < oreData.MinToolTier then
		return false
	end
	if oreData.MinWaveUnlock and profile.HighestWave < oreData.MinWaveUnlock then
		return false
	end
	return true
end

MineNode.OnServerEvent:Connect(function(player: Player, node: Instance)
	if typeof(node) ~= "Instance" or not node:IsDescendantOf(workspace) then
		return
	end

	local character = player.Character
	if not character or not character.PrimaryPart then
		return
	end

	local nodePosition = node:IsA("BasePart") and node.Position
		or (node:IsA("Model") and node.PrimaryPart and node.PrimaryPart.Position)
	if not nodePosition then
		return
	end
	if (character.PrimaryPart.Position - nodePosition).Magnitude > MAX_MINING_DISTANCE then
		return
	end

	local oreKey = getOreTypeFromNode(node)
	if not oreKey or not playerCanMine(player, oreKey) then
		return
	end

	local oreData = OreConfig.Ores[oreKey]
	local profile = DataService.Get(player)
	local toolData = OreConfig.ToolTiers[profile.ToolTier]

	local yield = math.floor(oreData.BaseYield * toolData.YieldMultiplier + 0.5)
	DataService.AddOre(player, oreKey, yield)

	Remotes.InventoryUpdate:FireClient(player, { OreCounts = profile.OreCounts })
end)

return MiningService
