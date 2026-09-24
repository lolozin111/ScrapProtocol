--[[
	ScorchAuraVisual.client.lua

	Keeps the Scorch Aura's ring lying on the FLOOR beneath the player, every frame.

	Why this is a client script at all, since the ring is a server-created part:

	The ring has been positioned three different ways, and the first two each fixed one half of the
	problem while breaking the other. Positioned from a server Heartbeat it lagged, because a server
	tick runs after the frame the player is looking at and then has to cross the network. Welded to
	the HumanoidRootPart the lag went away — the weld is solved by the client's own physics — but a
	weld is RIGID, so jumping carried the ring up into the air and the thing drawn as a zone on the
	floor stopped being on the floor. That is the bug this file exists to close.

	Driving it from the client gets both properties at once: it runs on the player's own frame with
	no round trip, and the ring's Y is free to be decided independently of the character's. The part
	stays Anchored and the server writes its CFrame exactly once, at creation (see RunBuffService's
	ensureGearVisual), so nothing ever fights these per-frame local writes or replicates them back.

	The damage test is still server-authoritative and lives in RunBuffService's ScorchAura gear
	behavior. It is measured on the floor plane — horizontal distance from the root, bounded by
	RunBuffConfig's ScorchAura Base.Height — precisely so that this ring cannot advertise a reach the
	burn will not honour. The X/Z used here is the root's own X/Z, the same value that test uses, so
	the two are incapable of disagreeing horizontally.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- Lays a Cylinder-shaped Part's disc flat. The rotation is about Z, NOT X: such a Part has its axis
-- along LOCAL X, so its flat faces point along X and it stands on edge like a coin by default.
-- Rotating about X spins it around its own axis and changes nothing visible — the original bug that
-- made this render as an upright dome half-buried in the floor. RunBuffService's updateAuraVisual
-- carries the long version of this.
local FLAT = CFrame.Angles(0, 0, math.rad(90))

-- Lifted off the surface by a hair so the disc doesn't z-fight with the floor it sits on.
local SURFACE_LIFT = 0.08

-- How far down to look for a floor. Generous, because a raid room can be tall and a player can be
-- mid-fall; if nothing is found at all we fall back to a fixed drop below the root rather than
-- leaving the ring behind at its last position, which would read as the ring sticking to the air.
local PROBE_DEPTH = 300
local FALLBACK_DROP = 3

local probe = RaycastParams.new()
probe.FilterType = Enum.RaycastFilterType.Exclude
probe.IgnoreWater = true

-- Cached across frames, revalidated by Parent rather than trusted: the ring is destroyed and rebuilt
-- whenever the aura is re-granted or the run ends, and a stale reference would silently stop moving.
local cachedRing = nil
local cachedCharacter = nil

local function findRing(character)
	if cachedRing and cachedRing.Parent and cachedCharacter == character then
		return cachedRing
	end
	cachedRing = nil
	cachedCharacter = nil
	for _, child in ipairs(character:GetChildren()) do
		-- Set by RunBuffService for every gear visual. An attribute, not the model's name, because a
		-- real model cloned out of ServerStorage.RunGearModels keeps the TEMPLATE's name — only the
		-- placeholder builder names its models "<Key>_Visual".
		if child:IsA("Model") and child:GetAttribute("RunGearItem") == "ScorchAura" then
			local ring = child.PrimaryPart or child:FindFirstChild("AuraRing")
			if ring and ring:IsA("BasePart") then
				cachedRing = ring
				cachedCharacter = character
				return ring
			end
		end
	end
	return nil
end

RunService.RenderStepped:Connect(function()
	local character = LocalPlayer.Character
	if not character then
		cachedRing = nil
		cachedCharacter = nil
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	-- No aura owned, or the run ended and its visual was destroyed. Nothing to do, and deliberately
	-- not a warning: not having the gear is the normal case, not a fault.
	local ring = findRing(character)
	if not ring then
		return
	end

	-- The aura model is parented to the character, so excluding the character excludes the ring too.
	probe.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -PROBE_DEPTH, 0), probe)
	local floorY = hit and (hit.Position.Y + SURFACE_LIFT) or (root.Position.Y - FALLBACK_DROP)

	ring.CFrame = CFrame.new(root.Position.X, floorY, root.Position.Z) * FLAT
end)
