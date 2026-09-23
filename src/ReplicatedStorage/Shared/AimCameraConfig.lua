--[[
	AimCameraConfig.lua
	The over-the-shoulder aim camera that engages WHILE A GUN IS EQUIPPED (the user's call,
	2026-09-22): "when you equip a gun, i want the player POV to snap more to the right and the
	player orientation faces the camera, where the player torsos go up and down depending if they
	are looking up or down".

	Read by StarterPlayerScripts/AimCamera.client.lua. Holster the gun and every one of these is
	undone — the game goes back to Roblox's ordinary free-look third person, which is what you want
	while mining, building and walking around base.

	Why a config at all for a feel change: aim feel is the single most re-tuned thing in a shooter,
	and every number below is one someone will want to nudge after playing for ten minutes. None of
	them should mean editing the camera loop.
]]

local AimCameraConfig = {}

-- How far the camera sits over the character's right shoulder, as a Humanoid.CameraOffset (studs,
-- relative to the head: +X right, +Y up, +Z back). X is the "snap to the right" itself; Y lifts the
-- view just above the shoulder line so the character's own head doesn't eat the middle of the
-- screen at close range.
AimCameraConfig.ShoulderOffset = Vector3.new(2.5, 0.5, 0)

-- Seconds for the offset to slide in/out when a gun is drawn or holstered. Instant reads as a
-- glitch; anything past ~0.25 feels like the camera is lagging behind the draw.
AimCameraConfig.OffsetTweenSeconds = 0.18

-- Locked third-person distance while aiming. Roblox's zoom is the player's own preference the rest
-- of the time; a shooter camera needs a known distance, or the shoulder offset means something
-- different at every zoom level.
AimCameraConfig.ZoomDistance = 12

-- Restored on holster so the player's own scroll-wheel zoom range comes back.
AimCameraConfig.DefaultMinZoom = 0.5
AimCameraConfig.DefaultMaxZoom = 128

-- The character turns to face wherever the camera looks (yaw only). This is what makes movement
-- strafe rather than steer: A and D sidestep instead of turning you. Seconds-to-catch-up; 0 would
-- pin the body to the camera with no give at all, which reads as stiff.
AimCameraConfig.YawFollowSeconds = 0.06

-- TORSO PITCH — R15's Waist joint, so the upper body leans up/down with the camera's vertical aim
-- while the legs stay level. Clamped well short of the camera's own pitch range: past roughly 45
-- degrees an R15 torso starts to intersect its own legs, and the gun ends up pointing through the
-- character.
AimCameraConfig.MaxTorsoPitchDegrees = 45
AimCameraConfig.TorsoPitchFollowSeconds = 0.08

-- How much of the pitch the NECK takes instead of the waist. Splitting it stops the whole torso
-- folding in half when looking straight down — the head leads, the waist follows.
AimCameraConfig.NeckPitchShare = 0.35

-- The mouse is locked to the middle of the screen while aiming (that IS the aim point — the firing
-- code already raycasts from the mouse position, which is now always screen centre). A crosshair is
-- therefore not decoration: without one there is nothing on screen saying where the shot goes.
AimCameraConfig.ShowCrosshair = true
AimCameraConfig.CrosshairGapPixels = 5    -- empty space at the centre, so the dot you aim at stays visible
AimCameraConfig.CrosshairArmPixels = 9    -- length of each of the four ticks
AimCameraConfig.CrosshairThicknessPixels = 2
AimCameraConfig.CrosshairColor = Color3.fromRGB(237, 231, 220) -- HudKit.COLOR.Text
AimCameraConfig.CrosshairTransparency = 0.15

return AimCameraConfig
