--[[
	DamageNumbers.client.lua
	Floating damage numbers — the "did that actually do anything?" readout.

	WHY: every damage source in this game resolved silently. A Ricochet bounce, a bleed tick, a
	Detonator blast and a plain bullet all looked identical from the outside, which made it
	impossible to tell whether an Ultimate mod was firing at all or just doing very little. Reported
	directly as "the mods seemed to half work, I couldn't tell half of the time".

	Its own LocalScript rather than another section of MainHud.client.lua: that file is already
	3,800 lines and near Luau's 200-locals-per-scope ceiling (see HudKit.lua's header), and this
	needs nothing from it.

	COLOUR CARRIES THE SOURCE. That is the whole point — a white number tells you damage happened,
	but a purple one tells you your Ultimate fired. Server-side, every call site tags what kind of
	damage it was; see CombatEncounterService.resolveAndApplyDamage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DamageNumber = Remotes:WaitForChild("DamageNumber")

local LocalPlayer = Players.LocalPlayer

-- One entry per damage kind the server can tag. Anything unrecognised falls back to Normal rather
-- than rendering nothing, so a new kind added server-side still shows up while its colour is chosen.
local KINDS = {
	Normal    = { Color = Color3.fromRGB(255, 255, 255), Size = 20 },
	Headshot  = { Color = Color3.fromRGB(255, 220, 90),  Size = 26, Prefix = "" },
	-- Blast damage. Its own colour because a grenade in a crowd is otherwise a wall of white
	-- numbers indistinguishable from gunfire — and how many enemies a throw actually caught is the
	-- only thing worth knowing about a grenade launcher.
	Explosion = { Color = Color3.fromRGB(255, 140, 50),  Size = 25, Prefix = "" },
	Ultimate  = { Color = Color3.fromRGB(235, 90, 200),  Size = 24 }, -- Mythical pink, matching the slot
	Status    = { Color = Color3.fromRGB(150, 230, 130), Size = 16 }, -- bleed/poison ticks
	Turret    = { Color = Color3.fromRGB(120, 200, 255), Size = 18 },
	Robot     = { Color = Color3.fromRGB(180, 180, 190), Size = 16 },
	Drone     = { Color = Color3.fromRGB(255, 160, 120), Size = 18 }, -- your companion, not a turret
	-- The one entry that is not damage. A Support Core's whole output is a slowly rising health
	-- bar, which is the least legible thing in the game until it has a number on it.
	Heal      = { Color = Color3.fromRGB(120, 235, 150), Size = 20, Prefix = "+" },
}

local RISE_STUDS = 6
local LIFETIME = 0.9

-- Numbers are spawned into a plain folder rather than parented to the enemy: an enemy that dies
-- mid-flight would take its own damage number with it, and the number for the killing blow is the
-- one you most want to read.
local folder = Workspace:FindFirstChild("DamageNumbers")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "DamageNumbers"
	folder.Parent = Workspace
end

local function spawnNumber(position: Vector3, amount: number, kind: string?)
	local style = KINDS[kind or "Normal"] or KINDS.Normal

	local anchor = Instance.new("Part")
	anchor.Name = "DamageNumber"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	-- Small random horizontal scatter so several hits landing on the same body in the same instant
	-- don't stack into one unreadable smear.
	anchor.CFrame = CFrame.new(position + Vector3.new(
		(math.random() - 0.5) * 3,
		(math.random() - 0.5) * 1.5,
		(math.random() - 0.5) * 3))
	anchor.Parent = folder

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 140, 0, 44)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 220
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.SourceSansBold
	label.TextColor3 = style.Color
	label.TextStrokeTransparency = 0.35
	label.TextSize = style.Size
	label.Text = (style.Prefix or "") .. tostring(math.max(1, math.floor(amount + 0.5)))
	label.Parent = billboard

	-- Rise and fade. Tweened rather than stepped per frame so a burst of numbers costs one tween
	-- each instead of a RunService connection each.
	TweenService:Create(anchor, TweenInfo.new(LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = anchor.CFrame + Vector3.new(0, RISE_STUDS, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()

	Debris:AddItem(anchor, LIFETIME + 0.1)
end

DamageNumber.OnClientEvent:Connect(function(position: Vector3, amount: number, kind: string?)
	if typeof(position) ~= "Vector3" or type(amount) ~= "number" then
		return
	end
	spawnNumber(position, amount, kind)
end)
