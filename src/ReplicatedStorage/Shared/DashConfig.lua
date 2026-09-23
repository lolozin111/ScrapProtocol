--[[
	DashConfig.lua
	Every tunable number for the player's stamina and dash. Shared (not server-only) for the same reason
	Wallet.lua is: the HUD's stamina cells and the client's "can I dash right now" prediction have to
	agree with what DashService will actually allow, and two copies of these numbers would drift.

	=== MODEL ===
	Stamina is a small number of CHARGES, not a continuous bar. A dash spends one charge. Charges refill
	one at a time, RechargeSeconds each, and only while below MaxCharges (the timer doesn't bank time
	while full). The server (DashService) owns the real count; the client predicts it so a dash feels
	instant, and is corrected by StaminaUpdate if the server disagrees.

	The dash itself is movement, and a player's character is simulated on their own client, so the
	client performs it. The server's job is keeping the charge count honest, so any later system that
	reads stamina (an upgrade, a perk, a UI) is reading a number a modified client can't inflate.
]]

local DashConfig = {}

----------------------------------------------------------------------
-- Stamina
----------------------------------------------------------------------

-- Charges a player starts with. "In the beginning": a future upgrade would add a profile field on top
-- of this, not change this number.
DashConfig.MaxCharges = 3

-- Seconds to refill ONE charge. With 3 empty charges, a full refill takes 3x this.
DashConfig.RechargeSeconds = 5

-- A fresh character (spawn or respawn) starts with full charges.
DashConfig.RefillOnRespawn = true

----------------------------------------------------------------------
-- Dash movement
----------------------------------------------------------------------

-- Horizontal speed (studs/second) during the dash, and how long it lasts. Distance is roughly
-- Speed x Duration: 80 x 0.22 = about 17.6 studs.
DashConfig.Speed = 80
DashConfig.Duration = 0.22

-- I-FRAMES: seconds of invulnerability starting the moment a dash is granted (the user's call,
-- 2026-09-22 — "make it when you dash that you have some iframes during the dash"). Slightly longer
-- than Duration on purpose: a dash that ends a hair before a swing lands still reads to the player as
-- "I dodged that", and the gap between client-side dash start and the server seeing it is real. Set
-- to 0 to turn i-frames off entirely. Only the DASHING player is protected, and only from damage —
-- status effects already ticking on them keep ticking.
DashConfig.IFrameSeconds = 0.3

-- Minimum seconds between two dashes, even with charges to spare, so all three can't fire on the same
-- frame. The server's rate limit uses a slightly shorter window (ServerCooldownFactor) so ordinary
-- network jitter between two honest dashes is never rejected.
DashConfig.Cooldown = 0.35
DashConfig.ServerCooldownFactor = 0.8

-- Which way to dash when the player isn't pressing a direction: "Facing" (the way the character
-- faces) or "None" (no dash, and no charge spent).
DashConfig.WhenStandingStill = "Facing"

-- Whether a dash can start while airborne (jumping or falling).
DashConfig.AllowInAir = false

----------------------------------------------------------------------
-- Input
----------------------------------------------------------------------

DashConfig.Keys = { Enum.KeyCode.Q, Enum.KeyCode.ButtonB }

-- Show an on-screen dash button on touch devices.
DashConfig.TouchButton = true

----------------------------------------------------------------------
-- Animation (for the dash animation still to be made)
----------------------------------------------------------------------

-- "" = no animation yet: the dash still works, it just plays nothing. Paste the published id here
-- ("rbxassetid://...") once the dash animation exists.
DashConfig.AnimationId = ""

-- Playback speed (1 = as published). Tune so the animation's length matches Duration.
DashConfig.AnimationSpeed = 1

-- Fade in/out time for the track, in seconds.
DashConfig.AnimationFadeTime = 0.05

-- Priority the track plays at, forced in code so it always overrides walking/running.
DashConfig.AnimationPriority = Enum.AnimationPriority.Action

-- true: stop the animation when the dash movement ends (Duration). false: let it play to its own end.
DashConfig.StopAnimationWithDash = false

return DashConfig
