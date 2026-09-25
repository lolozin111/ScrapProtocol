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

	ONE BAR AT A TIME, AND CLICKING DOES NOT RESTART IT. Start() is called on every click and is a
	no-op while a drain is already running: the bar exists to answer "how much longer until I can hit
	again", and a player mashing the button is asking that question constantly. Restarting on each
	click answered it with a lie — a full bar for a cooldown about to end. Only a click after the bar
	has emptied begins a new one.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local OreConfig = require(ReplicatedStorage.Shared.OreConfig)
local ToolModConfig = require(ReplicatedStorage.Shared.ToolModConfig)
local Hud = require(script.Parent.HudKit)
local Sfx = require(script.Parent.Sfx)

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

----------------------------------------------------------------------
-- State machine, not tweens. The first version drove the drain with a TweenService tween and did its
-- bookkeeping in the tween's Completed callback, and clicking fast enough broke it: cancelled tweens
-- still fire Completed, a new tween can start before the old one's callback has run, and the
-- "visible" flag ended up disagreeing with what was on screen. The user asked for plain conditions
-- instead, and they're right — two booleans and a clock cannot race with each other.
--
--   barActive  — a cooldown is being shown right now. A click while true changes nothing.
--   endsAt     — the clock the cooldown finishes at; remaining = endsAt - now.
--   duration   — what the bar is a fraction OF, so the fill is remaining/duration.
--
-- One Heartbeat connection owns the visuals for as long as barActive holds, and nothing outside it
-- ever writes the fill's size.
----------------------------------------------------------------------

local barActive = false
local endsAt = 0
local duration = 0
local fadeUntil = 0 -- after the drain empties: the short fade-out window, then everything resets
local stepConnection: RBXScriptConnection? = nil

-- The swing time the server will actually charge, derived the same way both mining services derive
-- it: the tool tier's base time through ToolModConfig, which applies the equipped tool mod. Falls
-- back to tier 1 exactly as the services do, rather than indexing blind into ToolTiers.
local function swingSeconds(): number
	local profile = Hud.profile
	local tier = (profile and profile.ToolTier) or 1
	local toolData = OreConfig.ToolTiers[tier] or OreConfig.ToolTiers[1]
	return ToolModConfig.SwingTime(profile, toolData.SwingTime)
end

local function resetBar()
	barActive = false
	endsAt = 0
	duration = 0
	fadeUntil = 0
	track.Visible = false
	track.BackgroundTransparency = TRACK_TRANSPARENCY
	fill.BackgroundTransparency = FILL_TRANSPARENCY
	fill.Size = UDim2.fromScale(1, 1)
	if stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

local function onStep()
	local now = os.clock()

	if barActive then
		local remaining = endsAt - now
		if remaining > 0 then
			-- Straight fraction of the cooldown left. Recomputed from the clock every frame rather
			-- than animated, so a dropped frame or a mid-cooldown click can't leave it showing the
			-- wrong width.
			fill.Size = UDim2.fromScale(math.clamp(remaining / math.max(duration, 0.001), 0, 1), 1)
			return
		end

		-- Emptied. barActive drops HERE, not after the fade: the cooldown is genuinely over, and a
		-- click during the fade-out must be able to start the next bar rather than be swallowed by a
		-- countdown that has already finished.
		barActive = false
		fadeUntil = now + FADE_SECONDS
		fill.Size = UDim2.fromScale(0, 1)
	end

	if fadeUntil == 0 then
		resetBar() -- nothing running and nothing fading: tear the frame loop down
		return
	end

	local fadeLeft = fadeUntil - now
	if fadeLeft <= 0 then
		resetBar()
		return
	end

	local progress = 1 - (fadeLeft / FADE_SECONDS)
	track.BackgroundTransparency = TRACK_TRANSPARENCY + (1 - TRACK_TRANSPARENCY) * progress
	fill.BackgroundTransparency = FILL_TRANSPARENCY + (1 - FILL_TRANSPARENCY) * progress
end

-- Called on EVERY click, accepted or not. Does nothing while a bar is already running: the bar
-- answers "how much longer until I can hit again", and a player mashing the button is asking that
-- constantly — restarting it there would answer with a full bar for a cooldown about to end.
function MiningCooldownBar.Start()
	if barActive then
		return
	end

	local seconds = swingSeconds()
	if seconds <= 0 then
		return
	end

	-- The swing sound hangs off the same guard as the bar, which is exactly where it wants to be:
	-- Start() is called on every click but no-ops while a bar is running, so a player mashing the
	-- button gets ONE swing sound per actual swing instead of one per click. Wiring this to the
	-- click itself would machine-gun it. SoundConfig gives MineSwing a pitch range too, so the
	-- repeats do not read as one sample retriggered.
	Sfx.play("MineSwing")

	barActive = true
	duration = seconds
	endsAt = os.clock() + seconds
	fadeUntil = 0

	track.Visible = true
	track.BackgroundTransparency = TRACK_TRANSPARENCY
	fill.BackgroundTransparency = FILL_TRANSPARENCY
	fill.Size = UDim2.fromScale(1, 1)

	if not stepConnection then
		stepConnection = RunService.Heartbeat:Connect(onStep)
	end
end

-- Cleared outright when the character dies or is removed mid-cooldown: a bar left draining over a
-- respawn screen is the kind of stuck-UI artifact that reads as a bug.
function MiningCooldownBar.Hide()
	resetBar()
end

LocalPlayer.CharacterRemoving:Connect(function()
	MiningCooldownBar.Hide()
end)

return MiningCooldownBar
