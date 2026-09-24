--[[
	OrbitBladesVisual.client.lua

	Draws the Orbit Blades on the client, so they stop lagging a network round trip behind the
	player. Second of these; ScorchAuraVisual.client.lua is the first and carries the longer version
	of why the client owns position at all.

	Why this one was left alone when the aura was fixed, and why that reason is now void:

	The aura's lag was cured by welding its ring to the HumanoidRootPart — the weld is solved by the
	client's own physics, so no round trip. That fix could not be applied here, and the old comment
	in RunBuffService said so: a weld is a FIXED local offset from the root, and blades genuinely
	move relative to the root every frame as they orbit. There is no static C0 that reproduces an
	orbit. But the aura's SECOND fix (keeping the ring on the floor through a jump) threw the weld
	out and had the client set the CFrame outright, and a moving orbit is no harder to compute
	client-side than a fixed offset. The blocker was specific to welding, and nothing welds now.

	What keeps the drawn blade and the cutting blade the same blade:

	Both sides compute the angle from `Workspace:GetServerTimeNow()`, a clock synchronized between
	server and clients, times `RunBuffConfig`'s shared `OrbitBlades.Base.OrbitSpeed`. Same inputs,
	same formula, no messages — so there is nothing to replicate and nothing to drift. That is also
	why the server's angle stopped being an accumulated `state.Angle += dt * 2`: an accumulated
	value is unreproducible by definition, and nothing this script could do would land on it.

	Damage stays server-authoritative in RunBuffService's GearBehaviors.OrbitBlades, which computes
	blade positions from the same helper rather than reading these parts — the parts are a drawing,
	and a drawing is not evidence of anything.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RunBuffConfig = require(ReplicatedStorage.Shared.RunBuffConfig)

local LocalPlayer = Players.LocalPlayer

local ORBIT_SPEED = RunBuffConfig.Items.OrbitBlades.Base.OrbitSpeed
local FALLBACK_RADIUS = RunBuffConfig.Items.OrbitBlades.Base.OrbitRadius

-- Cached across frames and revalidated by Parent rather than trusted: the model is destroyed and
-- rebuilt whenever the blade COUNT changes (a Lv4 grant adds one) or the run ends, and a stale
-- reference would silently stop moving.
local cachedModel = nil
local cachedCharacter = nil

local function findModel(character)
	if cachedModel and cachedModel.Parent and cachedCharacter == character then
		return cachedModel
	end
	cachedModel = nil
	cachedCharacter = nil
	for _, child in ipairs(character:GetChildren()) do
		-- Set by RunBuffService's ensureOrbitBladesVisual. An attribute, not the model's name,
		-- because a real model cloned from ServerStorage.RunGearModels keeps the TEMPLATE's name —
		-- only the placeholder builder names its model "OrbitBlades_Visual".
		if child:IsA("Model") and child:GetAttribute("RunGearItem") == "OrbitBlades" then
			cachedModel = child
			cachedCharacter = character
			return child
		end
	end
	return nil
end

RunService.RenderStepped:Connect(function()
	local character = LocalPlayer.Character
	if not character then
		cachedModel = nil
		cachedCharacter = nil
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	-- No blades owned, or the run ended and the visual was destroyed. Not a warning: not having the
	-- gear is the normal case, not a fault.
	local model = findModel(character)
	if not model then
		return
	end

	-- Both published by the server. BladeCount could be counted off the children instead, but the
	-- attribute is what the server actually built to, and the count has to match the server's or
	-- every blade sits at the wrong angle — the spacing term divides by it.
	local count = model:GetAttribute("BladeCount")
	local radius = model:GetAttribute("OrbitRadius")
	if type(count) ~= "number" or count < 1 then
		return
	end
	if type(radius) ~= "number" then
		radius = FALLBACK_RADIUS
	end

	local baseAngle = Workspace:GetServerTimeNow() * ORBIT_SPEED
	local spacing = 2 * math.pi / count
	local origin = root.Position

	for i = 1, count do
		local blade = model:FindFirstChild("Blade" .. tostring(i))
		if blade and blade:IsA("BasePart") then
			local angle = baseAngle + (i - 1) * spacing
			blade.CFrame = CFrame.new(origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
		end
	end
end)
