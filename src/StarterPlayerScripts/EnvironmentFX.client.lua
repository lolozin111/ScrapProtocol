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

-- NOTE: two earlier versions of this used NEAR_FOG_END values (100000, then 400) that stayed
-- too large across most of the path for the fog to read as visible against a plain grey
-- baseplate/skybox — technically applying, but not noticeable. This version ramps up fast and
-- hard, and uses a FAR_COLOR with real contrast against the default sky instead of another
-- grey, so it's unmistakable well before the end of the (now even shorter) path.
local NEAR_FOG_END = 150    -- still fairly clear right at the base
local FAR_FOG_END = 20      -- thick, obvious haze
local FAR_DISTANCE = 45     -- studs from the anchor at which fog reaches its haziest — most of an 8-slot path
local NEAR_COLOR = Color3.fromRGB(180, 190, 200)
local FAR_COLOR = Color3.fromRGB(70, 58, 50)

local function getAnchorPosition(): Vector3?
	local anchor = CollectionService:GetTagged("ExpeditionStart")[1]
	return anchor and anchor.Position
end

if not getAnchorPosition() then
	warn("[EnvironmentFX] No Part tagged 'ExpeditionStart' found yet — distance fog has nothing to measure from until one exists.")
end

-- CONFIRMED via testing: this place has an Atmosphere instance under Lighting, and Atmosphere
-- suppresses classic Lighting.Fog* rendering outright — that's why FogEnd was computing sane
-- numbers (105-130) but nothing was visible. Atmosphere.Haze (not Density) is the property that
-- actually reads as "foggy," so that's the primary knob now; Density and Color ride along for
-- extra depth. Lighting.Fog* is left in place below as a harmless no-op fallback for anyone
-- testing this in a place that DOESN'T have an Atmosphere.
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local NEAR_HAZE = 0
local FAR_HAZE = 5      -- Atmosphere.Haze goes 0-10; 5 is a strong, unmistakable haze on purpose — dial back once you've confirmed it's visible
local BASE_DENSITY = atmosphere and atmosphere.Density or 0.3
local FAR_DENSITY = 0.6

-- Two earlier tuning passes on this still didn't read as visible in testing. Rather than guess
-- a third time, this prints the live numbers every couple seconds — if it's STILL not visible
-- once FogEnd is reported down near 20-30, the bug isn't the math anymore and the Output log
-- here is what we need to see to find the real cause (e.g. check Lighting in Explorer for an
-- Atmosphere object and what Technology is set, and screenshot both).
local lastDebugPrint = 0

RunService.Heartbeat:Connect(function()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local anchorPosition = getAnchorPosition()
	if not root or not anchorPosition then
		return
	end

	local distance = (root.Position - anchorPosition).Magnitude
	local t = math.clamp(distance / FAR_DISTANCE, 0, 1)
	local fogEnd = NEAR_FOG_END + (FAR_FOG_END - NEAR_FOG_END) * t

	Lighting.FogEnd = fogEnd
	Lighting.FogStart = 0
	Lighting.FogColor = NEAR_COLOR:Lerp(FAR_COLOR, t)

	if atmosphere then
		atmosphere.Haze = NEAR_HAZE + (FAR_HAZE - NEAR_HAZE) * t
		atmosphere.Density = BASE_DENSITY + (FAR_DENSITY - BASE_DENSITY) * t
		atmosphere.Color = NEAR_COLOR:Lerp(FAR_COLOR, t)
	end

	local now = os.clock()
	if now - lastDebugPrint > 2 then
		lastDebugPrint = now
		local hazeText = atmosphere and ("%.2f"):format(atmosphere.Haze) or "n/a"
		print(("[EnvironmentFX] distance=%.0f t=%.2f FogEnd=%.0f Haze=%s"):format(
			distance, t, fogEnd, hazeText))
	end
end)
