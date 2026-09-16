--[[
	LoadingScreen.client.lua
	Covers the screen on join until the game's assets have downloaded, so the player never walks into
	a half-loaded base with gray boxes and missing icons. A Skip button appears after SKIP_AFTER seconds
	for anyone who would rather play while the rest streams in; loading carries on in the background
	either way.

	Lives in ReplicatedFirst because that is the only place a LocalScript runs before the rest of the
	game has replicated. For the same reason it cannot require HudKit (StarterPlayerScripts is not
	there yet), so the few colors and fonts below are copied from HudKit.COLOR/FONT — keep them matched
	if the palette is retuned.

	What gets preloaded: every asset-carrying instance (meshes, images, sounds, animations, particles)
	under Workspace, ReplicatedStorage, Lighting, StarterGui and SoundService, plus every rbxassetid://
	string in EnemyConfig — enemy animations are ids in config, not instances, and would otherwise only
	download the first time an enemy tries to play one.
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local SKIP_AFTER = 5 -- seconds before the Skip button appears
local BATCH_SIZE = 20 -- assets per PreloadAsync call; smaller = smoother progress bar
local READY_HOLD = 0.4 -- seconds "Ready" stays up before fading
local FADE_TIME = 0.5

-- Copied from HudKit (see header).
local COLOR = {
	Panel = Color3.fromRGB(22, 18, 15),
	PanelLight = Color3.fromRGB(40, 35, 31),
	Line = Color3.fromRGB(60, 53, 47),
	Text = Color3.fromRGB(237, 231, 220),
	Muted = Color3.fromRGB(167, 156, 140),
	Accent = Color3.fromRGB(224, 122, 59),
}
local function font(name: string, fallback: Enum.Font): Enum.Font
	local ok, value = pcall(function()
		return (Enum.Font :: any)[name]
	end)
	return (ok and typeof(value) == "EnumItem") and value or fallback
end
local FONT_DISPLAY = font("MontserratBold", Enum.Font.GothamBold)
local FONT_BODY = Enum.Font.SourceSans
local FONT_BODY_BOLD = Enum.Font.SourceSansBold

local ASSET_CLASSES = {
	"MeshPart", "UnionOperation", "FileMesh", "Decal", "ImageLabel", "ImageButton", "Sound", "Animation",
	"SurfaceAppearance", "ParticleEmitter", "Beam", "Trail", "Sky", "Clothing", "MaterialVariant",
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadingScreen"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 1000 -- above the HUD
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- One CanvasGroup so the whole screen fades out as a unit.
local root = Instance.new("CanvasGroup")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = COLOR.Panel
root.BorderSizePixel = 0
root.Parent = screenGui

local center = Instance.new("Frame")
center.AnchorPoint = Vector2.new(0.5, 0.5)
center.Position = UDim2.fromScale(0.5, 0.5)
center.Size = UDim2.new(0, 420, 0, 190)
center.BackgroundTransparency = 1
center.Parent = root

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, 44)
title.Font = FONT_DISPLAY
title.Text = "SALVAGE PROTOCOL"
title.TextColor3 = COLOR.Text
title.TextSize = 34
title.Parent = center

local rule = Instance.new("Frame")
rule.AnchorPoint = Vector2.new(0.5, 0)
rule.Position = UDim2.new(0.5, 0, 0, 52)
rule.Size = UDim2.new(0, 64, 0, 3)
rule.BackgroundColor3 = COLOR.Accent
rule.BorderSizePixel = 0
rule.Parent = center

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Position = UDim2.new(0, 0, 0, 74)
status.Size = UDim2.new(0.7, 0, 0, 20)
status.Font = FONT_BODY_BOLD
status.Text = "Connecting…"
status.TextColor3 = COLOR.Muted
status.TextSize = 16
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = center

local count = Instance.new("TextLabel")
count.BackgroundTransparency = 1
count.AnchorPoint = Vector2.new(1, 0)
count.Position = UDim2.new(1, 0, 0, 74)
count.Size = UDim2.new(0.3, 0, 0, 20)
count.Font = FONT_BODY
count.Text = ""
count.TextColor3 = COLOR.Muted
count.TextSize = 16
count.TextXAlignment = Enum.TextXAlignment.Right
count.Parent = center

local track = Instance.new("Frame")
track.Position = UDim2.new(0, 0, 0, 100)
track.Size = UDim2.new(1, 0, 0, 8)
track.BackgroundColor3 = COLOR.PanelLight
track.BorderSizePixel = 0
track.Parent = center
Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = COLOR.Accent
fill.BorderSizePixel = 0
fill.Parent = track
Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

local skip = Instance.new("TextButton")
skip.AnchorPoint = Vector2.new(0.5, 0)
skip.Position = UDim2.new(0.5, 0, 0, 136)
skip.Size = UDim2.new(0, 140, 0, 40)
skip.BackgroundColor3 = COLOR.PanelLight
skip.AutoButtonColor = false
skip.Font = FONT_BODY_BOLD
skip.Text = "Skip"
skip.TextColor3 = COLOR.Text
skip.TextSize = 18
skip.Visible = false
skip.Parent = center
Instance.new("UICorner", skip).CornerRadius = UDim.new(0, 6)
local skipStroke = Instance.new("UIStroke")
skipStroke.Color = COLOR.Line
skipStroke.Thickness = 1
skipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
skipStroke.Parent = skip

screenGui.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()

local hoverInfo = TweenInfo.new(0.12)
skip.MouseEnter:Connect(function()
	TweenService:Create(skip, hoverInfo, { BackgroundColor3 = COLOR.Line }):Play()
	TweenService:Create(skipStroke, hoverInfo, { Color = COLOR.Accent }):Play()
end)
skip.MouseLeave:Connect(function()
	TweenService:Create(skip, hoverInfo, { BackgroundColor3 = COLOR.PanelLight }):Play()
	TweenService:Create(skipStroke, hoverInfo, { Color = COLOR.Line }):Play()
end)

----------------------------------------------------------------------
-- Dismiss
----------------------------------------------------------------------

local dismissed = false
local function dismiss()
	if dismissed then
		return
	end
	dismissed = true
	skip.Active = false
	local tween = TweenService:Create(root, TweenInfo.new(FADE_TIME), { GroupTransparency = 1 })
	tween.Completed:Connect(function()
		screenGui:Destroy()
	end)
	tween:Play()
end

skip.Activated:Connect(dismiss)

task.delay(SKIP_AFTER, function()
	if not dismissed then
		skip.Visible = true
	end
end)

----------------------------------------------------------------------
-- Loading
----------------------------------------------------------------------

local function setProgress(done: number, total: number)
	if dismissed then
		return
	end
	local fraction = total > 0 and math.clamp(done / total, 0, 1) or 1
	TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(fraction, 1) }):Play()
	count.Text = ("%d%%"):format(math.floor(fraction * 100 + 0.5))
end

local function isAsset(inst: Instance): boolean
	for _, className in ipairs(ASSET_CLASSES) do
		if inst:IsA(className) then
			return true
		end
	end
	return false
end

-- Enemy animation ids live as strings in config, not as instances anywhere in the tree.
local function collectConfigIds(into: { any })
	local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("EnemyConfig")
	if not module then
		return
	end
	local ok, config = pcall(require, module)
	if not ok then
		warn("[LoadingScreen] Could not read EnemyConfig for animation ids: " .. tostring(config))
		return
	end
	local seen, seenIds = {}, {}
	local function walk(value)
		if type(value) == "string" then
			if string.match(value, "^rbxassetid://%d+$") and not seenIds[value] then
				seenIds[value] = true
				table.insert(into, value)
			end
		elseif type(value) == "table" and not seen[value] then
			seen[value] = true
			for _, v in pairs(value) do
				walk(v)
			end
		end
	end
	walk(config)
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end
status.Text = "Loading assets"

local assets = {}
for _, serviceName in ipairs({ "Workspace", "ReplicatedStorage", "Lighting", "StarterGui", "SoundService" }) do
	local service = game:GetService(serviceName)
	for _, inst in ipairs(service:GetDescendants()) do
		if isAsset(inst) then
			table.insert(assets, inst)
		end
	end
end
collectConfigIds(assets)

local total = #assets
setProgress(0, total)
for i = 1, total, BATCH_SIZE do
	local batch = table.move(assets, i, math.min(i + BATCH_SIZE - 1, total), 1, {})
	-- PreloadAsync can throw on a malformed id; one bad asset must not strand the screen.
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(batch)
	end)
	if not ok then
		warn("[LoadingScreen] Preload batch failed: " .. tostring(err))
	end
	setProgress(math.min(i + BATCH_SIZE - 1, total), total)
end

if not dismissed then
	status.Text = "Ready"
	status.TextColor3 = COLOR.Accent
	skip.Visible = false
	task.wait(READY_HOLD)
	dismiss()
end
