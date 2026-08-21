--[[
	EnvironmentFX.client.lua
	Two cheap, purely cosmetic effects for "the world feels different as you go further out" —
	scoped deliberately small. True procedural terrain streaming/regeneration is a much bigger
	project than a solo month supports; this fakes the feeling instead:

	1. Tagged "Tree" models sway gently (a sine-wave tilt, not real physics).
	2. Fog/atmosphere thickens with distance from the ExpeditionStart anchor, so the base feels
	   clear and safe while the far end of the path feels hazier and more remote.

	The third piece of "stuff out of bounds disappears" needs ZERO code: set
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
-- Distance-based fog — clear near the base, hazier further down the Expedition path
----------------------------------------------------------------------

-- NOTE: an earlier version of this used NEAR_FOG_END = 100000. That made the near->far lerp
-- stay in the tens-of-thousands for almost the entire path (Roblox's default view distance is
-- nowhere near that), so fog was effectively invisible everywhere except the very last few
-- studs. These values are scaled to the compact path (ExpeditionConfig.SlotSpacing = 12,
-- up to 8 slots ≈ 96 studs out) so the haze is actually visible well before you reach the end.
local NEAR_FOG_END = 400    -- clear near the base — still large enough that nothing looks foggy at 0 distance
local FAR_FOG_END = 45      -- noticeably hazy by the time you're near the far end of the path
local FAR_DISTANCE = 80     -- studs from the anchor at which fog reaches its haziest
local NEAR_COLOR = Color3.fromRGB(150, 160, 170)
local FAR_COLOR = Color3.fromRGB(90, 80, 75)

local function getAnchorPosition(): Vector3?
	local anchor = CollectionService:GetTagged("ExpeditionStart")[1]
	return anchor and anchor.Position
end

RunService.Heartbeat:Connect(function()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local anchorPosition = getAnchorPosition()
	if not root or not anchorPosition then
		return
	end

	local distance = (root.Position - anchorPosition).Magnitude
	local t = math.clamp(distance / FAR_DISTANCE, 0, 1)

	Lighting.FogEnd = NEAR_FOG_END + (FAR_FOG_END - NEAR_FOG_END) * t
	Lighting.FogStart = 0
	Lighting.FogColor = NEAR_COLOR:Lerp(FAR_COLOR, t)
end)
