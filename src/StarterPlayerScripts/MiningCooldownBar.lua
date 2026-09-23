--[[
	MiningCooldownBar.lua
	The swing cooldown, shown as a quiet bar instead of a rejection toast.

	Before this, swinging again too soon fired MineFailed("Swinging too fast — wait for your tool to
	reset") and MainHud toasted it. The user's call (2026-09-22): "is really ugly... make it instead
	for a almost transparent grey bar appear on the top center (a little bit lower than top actually)
	that goes down (from right to left) and then dissapears". A toast is for something you did wrong;
	a cooldown is just the tool working, and it wants a readout, not a scolding.

	CLIENT-PREDICTED ON PURPOSE. The bar starts the instant you swing, from the swing time this
	client can already compute — ToolModConfig.SwingTime is shared, and HudKit.profile mirrors the
	ToolTier and equipped mod the server charges you for — rather than waiting for a server round
	trip. A cooldown bar that starts a ping late would be wrong at exactly the moment it matters.
	The server still enforces the real limit (RateLimiter in MiningService/MineShaftService); this is
	display only, and nothing here can grant a swing.

	Restarting mid-run is normal: every accepted swing calls Start() again, which resets the bar from
	full rather than queueing. The server's clock is what actually gates, so the most recent swing is
	always the one worth showing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local OreConfig = require(ReplicatedStorage.Shared.OreConfig)
local ToolModConfig = require(ReplicatedStorage.Shared.ToolModConfig)
local Hud = require(script.Parent.HudKit)

local LocalPlayer = Players.LocalPlayer

local MiningCooldownBar = {}

-- Vertical placement as a fraction of screen height. Not pinned to the very top: that edge already
-- carries the wallet readouts and Roblox's own top bar, and a bar tucked under them reads as part of
-- the chrome instead of as feedback about what you just did.
local BAR_Y_SCALE = 0.14
local BAR_WIDTH = 220
local BAR_HEIGHT = 6
-- Almost transparent, per the request: present enough to track out of the corner of your eye while
-- you're looking at the rock you're hitting, never enough to pull focus.
local TRACK_TRANSPARENCY = 0.85
local FILL_TRANSPARENCY = 0.45
local FADE_SECONDS = 0.18

local gui = Hud.new("ScreenGui", {
	Name = "MiningCooldown",
	DisplayOrder = Hud.LAYER.Hud,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = LocalPlayer:WaitForChild("PlayerGui"),
})

local track = Hud.new("Frame", {
	Name = "Track",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, BAR_Y_SCALE, 0),
	Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = TRACK_TRANSPARENCY,
	BorderSizePixel = 0,
	Visible = false,
	Parent = gui,
}, { Hud.new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

-- Anchored LEFT so shrinking the width drains it right-to-left, the direction asked for. Grey, not
-- the HUD's accent orange: this is a neutral "not yet", and orange in this game means "you can act".
local fill = Hud.new("Frame", {
	Name = "Fill",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 0, 0.5, 0),
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(190, 186, 180),
	BackgroundTransparency = FILL_TRANSPARENCY,
	BorderSizePixel = 0,
	Parent = track,
}, { Hud.new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

local activeTween: Tween? = nil
local fadeTween: Tween? = nil
-- Bumped on every Start(); a finishing drain only hides the bar if it is still the newest one, so a
-- swing landing mid-drain can't be hidden by the previous swing's completion.
local runToken = 0

-- The swing time the server will actually charge, derived the same way both mining services derive
-- it: the tool tier's base time through ToolModConfig, which applies the equipped tool mod. Falls
-- back to tier 1 exactly as the services do, rather than indexing blind into ToolTiers.
local function swingSeconds(): number
	local profile = Hud.profile
	local tier = (profile and profile.ToolTier) or 1
	local toolData = OreConfig.ToolTiers[tier] or OreConfig.ToolTiers[1]
	return ToolModConfig.SwingTime(profile, toolData.SwingTime)
end

local function cancelTweens()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	if fadeTween then
		fadeTween:Cancel()
		fadeTween = nil
	end
end

-- Starts (or restarts) the drain. Safe to call on every swing attempt.
function MiningCooldownBar.Start()
	local duration = swingSeconds()
	if duration <= 0 then
		return
	end

	runToken += 1
	local token = runToken

	cancelTweens()
	track.Visible = true
	track.BackgroundTransparency = TRACK_TRANSPARENCY
	fill.BackgroundTransparency = FILL_TRANSPARENCY
	fill.Size = UDim2.fromScale(1, 1)

	local drain = TweenService:Create(
		fill,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{ Size = UDim2.fromScale(0, 1) }
	)
	activeTween = drain
	drain.Completed:Connect(function(state: Enum.PlaybackState)
		if state ~= Enum.PlaybackState.Completed or token ~= runToken then
			return -- cancelled, or a newer swing already owns the bar
		end
		local fade = TweenService:Create(
			track,
			TweenInfo.new(FADE_SECONDS),
			{ BackgroundTransparency = 1 }
		)
		local fillFade = TweenService:Create(
			fill,
			TweenInfo.new(FADE_SECONDS),
			{ BackgroundTransparency = 1 }
		)
		fadeTween = fade
		fade.Completed:Connect(function()
			if token == runToken then
				track.Visible = false
			end
		end)
		fade:Play()
		fillFade:Play()
	end)
	drain:Play()
end

-- Hidden outright when the character dies or the player leaves the mine mid-cooldown: a bar left
-- draining over a respawn screen is the kind of stuck-UI artifact that reads as a bug.
function MiningCooldownBar.Hide()
	runToken += 1
	cancelTweens()
	track.Visible = false
end

LocalPlayer.CharacterRemoving:Connect(function()
	MiningCooldownBar.Hide()
end)

return MiningCooldownBar
