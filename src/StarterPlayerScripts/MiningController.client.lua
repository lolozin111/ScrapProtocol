--[[
	MiningController.client.lua
	Minimal input handling for mining: player clicks/taps an ore node, client fires the
	server with which node it hit. All the actual validation and rewards happen server-side
	in MiningService — this script should stay "dumb" on purpose.

	Swap the ProximityPrompt approach below for a tool-swing animation + hit detection later;
	ProximityPrompt is the fastest way to get the loop testable in week one.

	Depleted nodes: MiningService replicates whether a node is currently empty via a "Depleted"
	Attribute (Attributes replicate to clients for free, no RemoteEvent needed) — this just
	toggles the prompt off/on to match, purely so the player doesn't get a prompt for a node
	that's about to silently reject them. The server is what actually enforces it either way.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local MineNode = ReplicatedStorage.Remotes.MineNode
local MineFailed = ReplicatedStorage.Remotes.MineFailed

local ORE_NODE_TAG = "OreNode" -- tag every ore node with this in Studio's Tag Editor

-- MineNode is fire-and-forget, so without this a rejected attempt (wrong tool tier, depleted,
-- too far) used to fail completely silently — the player just saw nothing happen with no clue
-- why. MiningService now always explains itself here instead.
MineFailed.OnClientEvent:Connect(function(reason: string)
	warn("[Mining]", reason)
end)

local function applyDepletedState(node: Instance, prompt: ProximityPrompt)
	prompt.Enabled = not node:GetAttribute("Depleted")
end

local function setupNode(node: Instance)
	if node:FindFirstChildOfClass("ProximityPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Mine"
	prompt.ObjectText = node:FindFirstChild("OreType") and node.OreType.Value or "Ore"
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 12
	prompt.Parent = node

	applyDepletedState(node, prompt)
	node:GetAttributeChangedSignal("Depleted"):Connect(function()
		applyDepletedState(node, prompt)
	end)

	prompt.Triggered:Connect(function(player)
		if player == Players.LocalPlayer then
			MineNode:FireServer(node)
		end
	end)
end

for _, node in ipairs(CollectionService:GetTagged(ORE_NODE_TAG)) do
	setupNode(node)
end
CollectionService:GetInstanceAddedSignal(ORE_NODE_TAG):Connect(setupNode)
