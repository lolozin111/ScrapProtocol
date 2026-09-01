--[[
	EnvironmentFX.client.lua
	Purely cosmetic client-side effect(s) for "the world feels different as you go further out."

	1. Tagged "Tree" models sway gently (a sine-wave tilt, not real physics).

	A distance-based fog/haze effect (fog thickening with distance from the ExpeditionStart
	anchor) used to live here too. It was removed — player feedback was that it made it hard
	to see, which defeats the point of a cosmetic effect. Removing the per-frame writes wasn't
	enough on its own: a place that has a hand-placed Atmosphere instance under Lighting (added
	in Studio, not created by this script) would still show whatever Haze/Density that instance
	was saved with, and Lighting.FogEnd would keep whatever value the old loop last wrote. So on
	startup this script explicitly clears both to Roblox's "no fog" defaults, once, so visibility
	is correct regardless of what a given place file has saved — see DESIGN_NOTES.md for the
	history of the tuning passes that led here before it was pulled.

	The "stuff out of bounds disappears" piece needs ZERO code: set
	Workspace.StreamingEnabled = true in Studio's Properties panel (with a MinRadius/
	TargetRadius you're happy with) and the engine handles distance-based part
	streaming for you — see the README.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------------
-- Tree sway
----------------------------------------------------------------------

local TREE_TAG = "Tree"
local SWAY_DEGREES = 2.5
local SWAY_SPEED = 0.6 -- radians/sec-ish; just a phase multiplier, not physically exact

local swayingTrees = {} -- [Model|BasePart] = { basePivot = CFrame, phase = number }

local function registerTree(tree: Instance)
	if tree:IsA("Model") and tree.PrimaryPart then
		swayingTrees[tree] = { basePivot = tree:GetPivot(), phase = math.random() * math.pi * 2 }
	elseif tree:IsA("BasePart") then
		swayingTrees[tree] = { basePivot = tree.CFrame, phase = math.random() * math.pi * 2 }
	end
end

for _, tree in ipairs(CollectionService:GetTagged(TREE_TAG)) do
	registerTree(tree)
end
CollectionService:GetInstanceAddedSignal(TREE_TAG):Connect(registerTree)
CollectionService:GetInstanceRemovedSignal(TREE_TAG):Connect(function(tree)
	swayingTrees[tree] = nil
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for tree, data in pairs(swayingTrees) do
		if tree.Parent then
			local angle = math.rad(SWAY_DEGREES) * math.sin(now * SWAY_SPEED + data.phase)
			local sway = data.basePivot * CFrame.Angles(angle, 0, angle * 0.6)
			if tree:IsA("Model") then
				tree:PivotTo(sway)
			else
				tree.CFrame = sway
			end
		else
			swayingTrees[tree] = nil -- cleaned up if the tree was destroyed/streamed out
		end
	end
end)

----------------------------------------------------------------------
-- Visibility reset — override anything a place file has saved, once
----------------------------------------------------------------------
-- This used to be a Heartbeat loop that recomputed Fog/Atmosphere every frame based on distance
-- from the ExpeditionStart anchor. That's gone (see header), but merely deleting the writes
-- would leave the bug half-fixed: a hand-placed Atmosphere instance under Lighting keeps
-- whatever Haze/Density it was saved with, and Lighting.FogEnd keeps whatever value the old loop
-- last wrote. So this runs once, on script start, to force both back to "no fog" — correct
-- regardless of what a given place file has saved, not just the one currently open in Studio.
Lighting.FogStart = 0
Lighting.FogEnd = 100000

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if atmosphere then
	atmosphere.Density = 0
	atmosphere.Haze = 0
end
