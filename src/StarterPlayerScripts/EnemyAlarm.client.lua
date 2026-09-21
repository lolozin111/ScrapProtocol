--[[
	EnemyAlarm.client.lua
	What the player sees and hears when a Raider catches them — the user's ask: "once they spot they
	will have a little effect and sound play to notify the player they got caught".

	Fired by the server (EnemyAwareness, via the EnemyAlarm RemoteEvent) with the Raider's Model, only
	to the player who was spotted. Three things, all cosmetic:
	  a sound (EnemyAwarenessConfig.AlarmSound — a built-in client sound by default),
	  a "!" above the Raider that raised it, so you know WHICH one to deal with,
	  a red flash around the screen edge, so it lands even when that Raider is off-screen.

	Everything the alarm actually DOES — which enemies answer it — happened on the server before this
	fired. Nothing here can change who's hunting you.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Hud = require(script.Parent:WaitForChild("HudKit"))
local EnemyAwarenessConfig = require(ReplicatedStorage.Shared.EnemyAwarenessConfig)

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EnemyAlarm")
local player = Players.LocalPlayer

local COLOR = Hud.COLOR

-- The edge flash: one full-screen frame, transparent in the middle via a UIStroke that IS the edge,
-- built once and re-flashed. A UIStroke on a transparent frame is the cheapest "vignette" Roblox has.
local flash = Instance.new("Frame")
flash.Name = "AlarmFlash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundTransparency = 1
flash.Active = false
flash.ZIndex = 50
flash.Parent = Hud.screenGui

local edge = Instance.new("UIStroke")
edge.Color = COLOR.Bad
edge.Thickness = 18
edge.Transparency = 1
edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
edge.Parent = flash

local FLASH_IN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_OUT = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local flashTween: Tween? = nil

local function flashEdge()
	-- Cancel-then-play, the HudKit convention: two alarms close together restart the flash instead
	-- of stacking tweens that fight over the same property.
	if flashTween then
		flashTween:Cancel()
	end
	edge.Transparency = 1
	flashTween = TweenService:Create(edge, FLASH_IN, { Transparency = 0.15 })
	flashTween:Play()
	flashTween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			flashTween = TweenService:Create(edge, FLASH_OUT, { Transparency = 1 })
			flashTween:Play()
		end
	end)
end

local function playSound()
	local soundId = EnemyAwarenessConfig.AlarmSound
	if not soundId or soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = EnemyAwarenessConfig.AlarmSoundVolume or 0.8
	sound.Parent = Hud.screenGui -- a Sound under PlayerGui plays as a 2D, non-positional sound
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	-- A sound that never loads never fires Ended; don't leak it.
	task.delay(5, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function markRaider(raider: Model?)
	local anchor = raider and (raider:FindFirstChild("Head") or raider.PrimaryPart)
	if not anchor or not anchor:IsA("BasePart") then
		return -- the Raider died or streamed out before this arrived; the flash and sound still land
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AlarmMarker"
	billboard.Size = UDim2.fromOffset(44, 56)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, anchor.Size.Y * 0.5 + 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = anchor

	local mark = Instance.new("TextLabel")
	mark.Size = UDim2.fromScale(1, 1)
	mark.BackgroundTransparency = 1
	mark.Text = "!"
	mark.Font = Hud.FONT and Hud.FONT.Display or Enum.Font.GothamBlack
	mark.TextScaled = true
	mark.TextColor3 = COLOR.Bad
	mark.TextStrokeColor3 = COLOR.Panel
	mark.TextStrokeTransparency = 0
	mark.Parent = billboard

	-- Parented to the player's own GUI rather than into the Raider's model, so it can't be copied
	-- into the enemy's server-side state or outlive a Raider that gets cleaned up mid-alarm.
	billboard.Parent = player:WaitForChild("PlayerGui")

	-- A quick pop so it reads as an event, not a static label.
	mark.Size = UDim2.fromScale(0.4, 0.4)
	mark.Position = UDim2.fromScale(0.3, 0.3)
	TweenService:Create(mark, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
	}):Play()

	task.delay(EnemyAwarenessConfig.AlarmMarkerSeconds or 2.5, function()
		billboard:Destroy()
	end)
end

remote.OnClientEvent:Connect(function(raider)
	playSound()
	flashEdge()
	markRaider(typeof(raider) == "Instance" and raider:IsA("Model") and raider or nil)
end)
