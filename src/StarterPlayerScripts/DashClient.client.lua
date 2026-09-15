--[[
	DashClient.client.lua
	Performs the dash. A character is simulated on its OWN client, so the dash movement has to be
	driven here rather than by the server — DashService (server) only ever decides whether a
	charge exists to spend, exactly like a weapon's damage is server-authoritative while its
	swing/recoil is client-cosmetic.

	=== FLOW ===
	Press -> local checks (alive, cooldown, predicted charge, grounded, a direction to go) -> spend
	the PREDICTED charge immediately (StaminaState.PredictSpend, so the HUD reacts the same frame)
	-> fire RequestDash with no arguments (nothing here is legitimate for the server to read from
	the client — see DashService's header) -> drive horizontal velocity locally for Duration.
	StaminaUpdate always arrives after, correcting the prediction if the server disagreed (e.g. the
	RateLimiter caught a double-press this script's own Cooldown should have already blocked).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local DashConfig = require(ReplicatedStorage.Shared.DashConfig)
local StaminaState = require(script.Parent.StaminaState)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
-- Bounded wait with an explicit message instead of an open-ended WaitForChild, whose only symptom is an
-- "Infinite yield possible" line and a Q key that silently does nothing. See DashService's matching note.
local RequestDash = Remotes:WaitForChild("RequestDash", 10)
local StaminaUpdate = Remotes:WaitForChild("StaminaUpdate", 10)
if not (RequestDash and StaminaUpdate) then
	warn("[DashClient] ReplicatedStorage.Remotes is missing RequestDash and/or StaminaUpdate — dashing is DISABLED. Restart `rojo serve` and reconnect the Studio plugin so Rojo picks up default.project.json.")
	return
end

local LocalPlayer = Players.LocalPlayer

local ACTION_NAME = "Dash"

local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local dashTrack: AnimationTrack? = nil
local warnedAnimationFailure = false

-- Local pacing so a held/mashed key can't even ATTEMPT a remote faster than the design intends —
-- independent of RateLimiter's server-side window, which exists for the client that skips this.
local lastDashAt = 0

local activeAttachment: Attachment? = nil
local activeVelocity: LinearVelocity? = nil
-- Bumped by every cleanup so a task.delay scheduled by an OLDER dash can tell it's stale (a new
-- dash, a death, or a respawn already tore its constraint down) and does nothing when it fires.
local dashToken = 0

local function cleanupDash()
	dashToken += 1
	if activeVelocity then
		activeVelocity:Destroy()
		activeVelocity = nil
	end
	if activeAttachment then
		activeAttachment:Destroy()
		activeAttachment = nil
	end
	if dashTrack and DashConfig.StopAnimationWithDash then
		dashTrack:Stop(DashConfig.AnimationFadeTime)
	end
end

local function loadAnimation()
	dashTrack = nil
	if DashConfig.AnimationId == "" or not humanoid then
		return -- no animation published yet; the dash still works, it just plays nothing
	end

	local ok, result = pcall(function()
		local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
		local anim = Instance.new("Animation")
		anim.AnimationId = DashConfig.AnimationId
		return animator:LoadAnimation(anim)
	end)

	if ok then
		dashTrack = result
		dashTrack.Priority = DashConfig.AnimationPriority
	elseif not warnedAnimationFailure then
		-- Warn once, not once per dash attempt — an animation that fails to load fails the same
		-- way every time, and this is a client cosmetic, not a reason to spam Output.
		warnedAnimationFailure = true
		warn("[DashClient] Failed to load dash animation: " .. tostring(result))
	end
end

local function onCharacterAdded(newCharacter: Model)
	cleanupDash()
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid")
	rootPart = newCharacter:WaitForChild("HumanoidRootPart")
	loadAnimation()
	humanoid.Died:Connect(cleanupDash)
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if LocalPlayer.Character then
	onCharacterAdded(LocalPlayer.Character)
end

-- Flattened to the XZ plane and normalized — dash speed must not vary with camera pitch or a
-- half-pressed diagonal, and Y is never touched by the dash (see the LinearVelocity setup below).
local function directionFor(hum: Humanoid, root: BasePart): Vector3?
	local move = hum.MoveDirection
	move = Vector3.new(move.X, 0, move.Z)
	if move.Magnitude > 0.05 then
		return move.Unit
	end

	if DashConfig.WhenStandingStill == "Facing" then
		local look = root.CFrame.LookVector
		look = Vector3.new(look.X, 0, look.Z)
		if look.Magnitude > 0.001 then
			return look.Unit
		end
		return nil
	end

	-- "None": standing fully still with no input direction means no dash, and — per the caller —
	-- no charge spent and no remote fired.
	return nil
end

local function performDash(dir: Vector3)
	StaminaState.PredictSpend()
	RequestDash:FireServer()

	cleanupDash() -- only one dash constraint alive at a time
	local token = dashToken

	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = rootPart

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DashVelocity"
	velocity.Attachment0 = attachment
	-- World-space, not Attachment0-space: `dir` is already a world-space vector (from MoveDirection
	-- or LookVector), so driving it relative to the attachment's own rotation would send the player
	-- sideways whenever their character isn't facing straight down +Z.
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	-- LinearVelocity has no single "MaxForce" split by axis — PerAxis + MaxAxesForce is the actual
	-- API for "drive X/Z, leave Y untouched": zero force on Y means gravity and any concurrent jump
	-- velocity are never fought by this constraint.
	velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	velocity.MaxAxesForce = Vector3.new(math.huge, 0, math.huge)
	velocity.VectorVelocity = dir * DashConfig.Speed
	velocity.Parent = rootPart

	activeAttachment = attachment
	activeVelocity = velocity

	if dashTrack then
		dashTrack:Play(DashConfig.AnimationFadeTime, 1, DashConfig.AnimationSpeed)
	end

	task.delay(DashConfig.Duration, function()
		if dashToken ~= token then
			return -- a newer cleanup (another dash, a death) already tore this one down
		end
		cleanupDash()
	end)
end

local function tryDash()
	if UserInputService:GetFocusedTextBox() then
		return -- typing in chat/a text field must not also dash
	end
	if not character or not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	if now - lastDashAt < DashConfig.Cooldown then
		return
	end

	StaminaState.Settle()
	if StaminaState.Charges < 1 then
		return
	end

	if not DashConfig.AllowInAir and humanoid.FloorMaterial == Enum.Material.Air then
		return
	end

	local dir = directionFor(humanoid, rootPart)
	if not dir then
		return
	end

	lastDashAt = now
	performDash(dir)
end

local function handleAction(actionName: string, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	tryDash()
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction(ACTION_NAME, handleAction, DashConfig.TouchButton, table.unpack(DashConfig.Keys))

StaminaUpdate.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	StaminaState.ApplyServerUpdate(payload.Charges, payload.MaxCharges, payload.RechargeRemaining, payload.RechargeSeconds)
end)
