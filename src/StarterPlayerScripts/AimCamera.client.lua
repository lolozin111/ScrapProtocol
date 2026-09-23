--[[
	AimCamera.client.lua
	The over-the-shoulder aim camera that engages WHILE A GUN IS EQUIPPED — see
	Shared/AimCameraConfig.lua for every tunable number this file reads (never edit a number here;
	it belongs in that config).

	Holstering, dying, or the character being removed undoes every single thing this file changes.
	Nothing here is a trust boundary: it's camera framing, character facing and a cosmetic torso
	lean, all client-only. The server never learns any of it (CombatClient's own aim raycast is
	unaffected by any of this — see the note at the bottom of this file on why it already agrees
	with a centre-locked mouse without needing a change).

	=== WHY AN INDEPENDENT EQUIP WATCHER, NOT A SHARED ONE ===
	CombatClient.client.lua already tracks the equipped weapon Tool via Character.ChildAdded/Removed
	plus a WeaponTool attribute check, because WeaponToolService re-clones a fresh Tool instance on
	every equip rather than reusing one. This file needs exactly the same fact and re-derives it the
	same way instead of reading CombatClient's private local — coupling two otherwise-unrelated
	client scripts (one about firing, one about the camera) so that a change to one's internal
	variable name breaks the other is worse than eight duplicated lines of watcher.

	=== WHY A DIRECT ROOT-CFRAME WRITE FOR YAW, NOT AN AlignOrientation CONSTRAINT ===
	EnemyAnimation.lua (server-side NPCs) turns them with an AlignOrientation specifically because an
	NPC's Humanoid is being driven by MoveTo/pathfinding at the same time, and per-frame CFrame writes
	were fighting that controller. The local player's own character has no such second driver once
	Humanoid.AutoRotate is off below: nothing else ever touches this root part's orientation, so a
	plain CFrame write (position untouched, only the Y-axis rotation replaced) is sufficient and is
	one BindToRenderStep instead of an extra Attachment + constraint per character.

	=== WHY BindToRenderStep AT Character-PRIORITY-PLUS-ONE, NOT PLAIN RenderStepped ===
	Plain RenderStepped connections fire at an unspecified point relative to Roblox's own core camera
	and character-control scripts (which themselves use BindToRenderStep at Enum.RenderPriority.Camera
	and .Character). Binding explicitly one tick after Character guarantees this frame's `camera.CFrame`
	already reflects the mouse look AND that the built-in character controller has already had its say
	for the frame — so this script's root-CFrame write is the last thing touching orientation before
	the frame renders, instead of possibly being clobbered by something that runs after it.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AimCameraConfig = require(ReplicatedStorage.Shared.AimCameraConfig)
local Hud = require(script.Parent.HudKit)

local LocalPlayer = Players.LocalPlayer

-- Cached once, same as CombatClient.client.lua does — nothing in this codebase ever replaces
-- Workspace.CurrentCamera at runtime, so re-reading the property every frame would just be wasted work.
local camera = Workspace.CurrentCamera

----------------------------------------------------------------------
-- Equip watcher — see header. Identically shaped to CombatClient's, deliberately not shared.
----------------------------------------------------------------------

local equippedTool: Tool? = nil

local function isWeaponTool(instance: Instance): boolean
	return instance:IsA("Tool") and instance:GetAttribute("WeaponTool") == true
end

local function watchEquip(character: Model)
	equippedTool = nil
	for _, child in ipairs(character:GetChildren()) do
		if isWeaponTool(child) then
			equippedTool = child
		end
	end
	character.ChildAdded:Connect(function(child)
		if isWeaponTool(child) then
			equippedTool = child
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child == equippedTool then
			equippedTool = nil
		end
	end)
end

----------------------------------------------------------------------
-- Crosshair — four ticks around a centre gap, no image asset. Its own ScreenGui (not a HudKit panel:
-- it is not a menu, it must never be gated by the one-panel-at-a-time rule) with IgnoreGuiInset = true
-- so scale-0.5 is the true viewport centre — the SAME coordinate space CombatClient's
-- Camera:ViewportPointToRay/UserInputService:GetMouseLocation use, or the drawn dot would sit a few
-- pixels off from where the locked mouse (and therefore the shot) actually is.
----------------------------------------------------------------------

local crosshairGui = Hud.new("ScreenGui", {
	Name = "AimCrosshair",
	DisplayOrder = Hud.LAYER.Hud,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = LocalPlayer:WaitForChild("PlayerGui"),
})

local crosshairRoot = Hud.new("Frame", {
	Name = "Crosshair",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(0, 0),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = crosshairGui,
})

do
	local gap = AimCameraConfig.CrosshairGapPixels
	local arm = AimCameraConfig.CrosshairArmPixels
	local thickness = AimCameraConfig.CrosshairThicknessPixels
	local reach = gap + arm / 2 -- distance from centre to the MIDDLE of each tick, so the tick's near
		-- edge lands exactly on the gap boundary instead of the gap being measured from the tick centre

	local function tick(offsetX: number, offsetY: number, sizeX: number, sizeY: number)
		Hud.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(offsetX, offsetY),
			Size = UDim2.fromOffset(sizeX, sizeY),
			BackgroundColor3 = AimCameraConfig.CrosshairColor,
			BackgroundTransparency = AimCameraConfig.CrosshairTransparency,
			BorderSizePixel = 0,
			Parent = crosshairRoot,
		})
	end

	tick(0, -reach, thickness, arm) -- top
	tick(0, reach, thickness, arm) -- bottom
	tick(-reach, 0, arm, thickness) -- left
	tick(reach, 0, arm, thickness) -- right
end

local function setCrosshairVisible(visible: boolean)
	crosshairRoot.Visible = visible and AimCameraConfig.ShowCrosshair == true
end

----------------------------------------------------------------------
-- Rig — the joints and their ORIGINAL C0s, captured once per character. Every per-frame pitch write
-- multiplies onto these originals, never onto the live C0 — see onRenderStep below for why.
----------------------------------------------------------------------

type Rig = {
	humanoid: Humanoid,
	rootPart: BasePart,
	waist: Motor6D,
	neck: Motor6D,
	originalWaistC0: CFrame,
	originalNeckC0: CFrame,
}

local currentRig: Rig? = nil
local aimEngaged = false
local currentYaw = 0
local currentPitch = 0
local offsetTween: Tween? = nil

-- Warned once EVER (module-level, never reset), same convention as DashClient's
-- warnedAnimationFailure: a rig that isn't R15 fails this the same way on every single respawn, and
-- spamming Output on each one teaches nobody anything a single line didn't already say.
local warnedBadRig = false

local function buildRig(humanoid: Humanoid?, rootPart: Instance?, upperTorso: Instance?, head: Instance?): Rig?
	local waist = upperTorso and upperTorso:FindFirstChild("Waist")
	local neck = head and head:FindFirstChild("Neck")

	if not (humanoid and rootPart and rootPart:IsA("BasePart") and waist and waist:IsA("Motor6D") and neck and neck:IsA("Motor6D")) then
		if not warnedBadRig then
			warnedBadRig = true
			warn("[AimCamera] Character is missing Humanoid/HumanoidRootPart/Waist/Neck (not an R15 rig?) — leaving the camera in ordinary free-look for this character instead of guessing.")
		end
		return nil
	end

	return {
		humanoid = humanoid,
		rootPart = rootPart :: BasePart,
		waist = waist :: Motor6D,
		neck = neck :: Motor6D,
		originalWaistC0 = (waist :: Motor6D).C0,
		originalNeckC0 = (neck :: Motor6D).C0,
	}
end

----------------------------------------------------------------------
-- Engage / disengage — every property this file ever touches is listed in BOTH functions, so nothing
-- can be left half-applied. Called from the per-frame step whenever "should the aim camera be on"
-- flips, not from the equip watcher directly, so both share one source of truth for the transition.
----------------------------------------------------------------------

local function tweenCameraOffset(humanoid: Humanoid, target: Vector3)
	if offsetTween then
		offsetTween:Cancel()
	end
	-- Held in a local and played off that, rather than `(offsetTween :: Tween):Play()` on the next
	-- line: a statement starting with "(" right after a closing ")" is the Luau "Ambiguous syntax"
	-- parse error, and a parse error here means the whole script never loads — no camera at all, no
	-- runtime warning saying why.
	local tween = TweenService:Create(
		humanoid,
		TweenInfo.new(AimCameraConfig.OffsetTweenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CameraOffset = target }
	)
	offsetTween = tween
	tween:Play()
end

local function disengage()
	if not aimEngaged then
		return
	end
	aimEngaged = false

	local rig = currentRig
	if rig then
		tweenCameraOffset(rig.humanoid, Vector3.zero)
		rig.humanoid.AutoRotate = true
		-- Snapped, not tweened — TorsoPitchFollowSeconds already smoothed the lean IN; unwinding it a
		-- second time on the way out would just be the same pose taking twice as long to leave.
		rig.waist.C0 = rig.originalWaistC0
		rig.neck.C0 = rig.originalNeckC0
	end

	LocalPlayer.CameraMinZoomDistance = AimCameraConfig.DefaultMinZoom
	LocalPlayer.CameraMaxZoomDistance = AimCameraConfig.DefaultMaxZoom
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	setCrosshairVisible(false)
	currentPitch = 0
end

local function engage()
	local rig = currentRig
	if aimEngaged or not rig then
		return -- no rig means buildRig already warned once; leave the camera alone, per this file's header
	end
	aimEngaged = true

	tweenCameraOffset(rig.humanoid, AimCameraConfig.ShoulderOffset)
	LocalPlayer.CameraMinZoomDistance = AimCameraConfig.ZoomDistance
	LocalPlayer.CameraMaxZoomDistance = AimCameraConfig.ZoomDistance
	rig.humanoid.AutoRotate = false

	-- Seed the smoothed yaw from the character's CURRENT facing, not 0 and not the camera's, so the
	-- very first frame of aiming doesn't snap-turn the body before YawFollowSeconds gets a chance to
	-- ease it — the per-frame step below closes the rest of the gap smoothly.
	local _, yaw = rig.rootPart.CFrame:ToEulerAnglesYXZ()
	currentYaw = yaw

	-- Mouse lock and the crosshair are NOT set here — they're set every frame in onRenderStep, because
	-- both have to drop out again the instant a HUD panel opens without a full disengage (see there).
end

----------------------------------------------------------------------
-- Angle smoothing — framerate-independent exponential approach, wrapped to the shortest direction
-- around the circle so a yaw crossing the +-180 seam doesn't spin the long way round.
----------------------------------------------------------------------

local function approachAngle(current: number, target: number, tau: number, dt: number): number
	if tau <= 1e-4 then
		return target -- a configured 0 means "don't smooth this", not "divide by zero"
	end
	local alpha = 1 - math.exp(-dt / tau)
	local diff = (target - current + math.pi) % (2 * math.pi) - math.pi
	return current + diff * alpha
end

----------------------------------------------------------------------
-- Per-frame update
----------------------------------------------------------------------

local function onRenderStep(dt: number)
	local shouldEngage = equippedTool ~= nil and currentRig ~= nil

	if shouldEngage and not aimEngaged then
		engage()
	elseif not shouldEngage and aimEngaged then
		disengage()
	end

	if not aimEngaged then
		return
	end

	local rig = currentRig :: Rig -- aimEngaged only ever flips true inside engage(), which returns early
		-- without setting it when currentRig is nil, and CharacterRemoving (below) disengages BEFORE
		-- nil-ing currentRig — so the two can never disagree here.

	-- A HUD panel being open means the player is clicking buttons, not aiming: give the mouse back and
	-- freeze the character exactly as it's posed. Nothing here calls disengage() — the camera offset,
	-- zoom lock and AutoRotate stay put so re-opening the crosshair on panel-close is instant rather
	-- than re-running the whole tween.
	if Hud.isPanelOpen() then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		setCrosshairVisible(false)
		return
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	setCrosshairVisible(true)

	local lookVector = camera.CFrame.LookVector

	-- Yaw: flatten the camera's look direction to the XZ plane and turn the character to match. When
	-- the camera looks nearly straight up/down the flattened vector degenerates towards zero — keep
	-- the last facing rather than let a near-zero vector send CFrame.lookAt an unstable direction.
	local flat = Vector3.new(lookVector.X, 0, lookVector.Z)
	local targetYaw = currentYaw
	if flat.Magnitude > 1e-4 then
		local _, yaw = CFrame.lookAt(Vector3.new(), flat.Unit):ToEulerAnglesYXZ()
		targetYaw = yaw
	end
	currentYaw = approachAngle(currentYaw, targetYaw, AimCameraConfig.YawFollowSeconds, dt)
	rig.rootPart.CFrame = CFrame.new(rig.rootPart.Position) * CFrame.Angles(0, currentYaw, 0)

	-- Pitch: the camera's vertical angle, clamped to MaxTorsoPitchDegrees BEFORE smoothing (so the
	-- smoothing chases the already-legal target instead of overshooting past the clamp on a fast
	-- mouse flick), then split between the neck and the waist by NeckPitchShare.
	--
	-- Sign is applied as-derived from the rig's own C0 axes and has not been eyeballed in Studio (no
	-- runtime to check against) — if a look-up bends the torso forward instead of back, negate the
	-- `currentPitch *` multiplications below; nothing else about the feature depends on which way this
	-- points.
	local maxPitch = math.rad(AimCameraConfig.MaxTorsoPitchDegrees)
	local pitchTarget = math.clamp(math.asin(math.clamp(lookVector.Y, -1, 1)), -maxPitch, maxPitch)
	currentPitch = approachAngle(currentPitch, pitchTarget, AimCameraConfig.TorsoPitchFollowSeconds, dt)

	local neckShare = AimCameraConfig.NeckPitchShare
	rig.waist.C0 = rig.originalWaistC0 * CFrame.Angles(currentPitch * (1 - neckShare), 0, 0)
	rig.neck.C0 = rig.originalNeckC0 * CFrame.Angles(currentPitch * neckShare, 0, 0)
end

RunService:BindToRenderStep("AimCameraFacing", Enum.RenderPriority.Character.Value + 1, onRenderStep)

----------------------------------------------------------------------
-- Character lifecycle — reacquire everything cleanly on every spawn; never leave a reference to a
-- dead character's Motor6Ds around for onRenderStep to write into.
----------------------------------------------------------------------

local function onCharacterAdded(character: Model)
	aimEngaged = false
	currentRig = nil
	currentYaw = 0
	currentPitch = 0
	setCrosshairVisible(false)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default -- in case a respawn happens mid-aim

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	local upperTorso = character:WaitForChild("UpperTorso", 5)
	local head = character:WaitForChild("Head", 5)
	currentRig = buildRig(humanoid, rootPart, upperTorso, head)

	if humanoid then
		humanoid.Died:Connect(disengage)
	end

	watchEquip(character)
end

if LocalPlayer.Character then
	onCharacterAdded(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

-- Fires WHILE the old character still exists, before it's torn down — the correct moment to disengage
-- and drop every reference, so nothing here ever writes to a Motor6D that's about to be destroyed.
LocalPlayer.CharacterRemoving:Connect(function()
	disengage()
	currentRig = nil
	equippedTool = nil
end)

--[[
	=== CombatClient.client.lua VERIFICATION (no change made there — see this file's header) ===
	CombatClient reads the aim ray from `UserInputService:GetMouseLocation()` and feeds it straight
	into `camera:ViewportPointToRay(x, y)`. Both of those are defined in the same coordinate space:
	full-viewport pixels, NOT the GUI-inset-adjusted space a ScreenGui without IgnoreGuiInset draws
	in (this is also why Mouse.X/Y and GetMouseLocation have always agreed with ViewportPointToRay —
	it's the same space Roblox's own Mouse object used internally before GetMouseLocation existed).
	`Enum.MouseBehavior.LockCenter` locks the OS cursor to the centre of that same full viewport, so
	`GetMouseLocation()` while locked returns exactly the viewport's centre pixel, and
	`ViewportPointToRay` at that point returns a ray identical to `camera.CFrame.LookVector` — i.e.
	dead centre, exactly where this file's crosshair is drawn. No change was needed; this is stated
	from the documented behaviour of both APIs, not from having run it, since a locked-mouse aim
	shot landing exactly under the crosshair is a Studio Play-Solo check, not something provable by
	reading code alone.
]]
