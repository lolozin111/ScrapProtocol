--[[
	EnemyAwareness.lua
	Whether a raid enemy knows you're there yet — the user's design (DESIGN_NOTES, "The user's enemy
	AI design", 2026-09-21). A shared utility, not a service: no remotes of its own to wire, not in
	Main.server.lua's list, required by CombatEncounterService (the EnemyMovement/CombatMath precedent).

	Before this, every raid enemy spawned already locked onto the player — the user's "raider is too
	big, they can see me all the way of the map" — because there was no "hasn't seen you" state for
	anything to start in. Now an enemy whose type is listed in EnemyAwarenessConfig starts a Combat
	room UNAWARE and walks through three states:

	  Idle    — stands, plays its idle, for a few seconds.
	  Wander  — strolls to a random spot near where it spawned, at a fraction of its speed.
	  Alerted — fights, for the rest of the room. The normal EnemyAI pattern takes over completely.

	It becomes Alerted by SPOTTING the player (in range and in line of sight), by being DAMAGED (by
	anything — CombatEncounterService hooks the one function all damage goes through), or by answering
	a Raider's ALARM. A Raider that is alerted by spotting or being shot raises the alarm: every other
	unaware enemy in the room rolls its type's AnswersAlarm chance, and the player gets the alarm FX
	(EnemyAlarm.client.lua).

	What this file does NOT change: an enemy with no Awareness state (every wave enemy, every
	Ambush/Boss enemy, every type with no config entry) never gets one, IsAware says true, Tick
	returns false, and the encounter loop runs it exactly as before this file existed.

	Must never require CombatEncounterService or EnemyAI — both sit above it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EnemyAwarenessConfig = require(ReplicatedStorage.Shared.EnemyAwarenessConfig)
local EnemyMovement = require(script.Parent.EnemyMovement)
local EnemyAnimation = require(script.Parent.EnemyAnimation)
local StatusEffects = require(script.Parent.StatusEffects)

local EnemyAwareness = {}

-- Same group CombatEncounterService puts every enemy in. Casting AS it means other enemies never
-- block a sight line — only real geometry does (EnemyMovement's LOS check does the same).
local ENEMY_COLLISION_GROUP = "CombatEnemies"

-- Arrived at a wander point within this many studs (horizontal).
local WANDER_ARRIVE_DISTANCE = 3

-- Per player: when that player's room last had an alarm raised. Per player rather than per enemy so
-- two Raiders spotting you a second apart are one alarm, not two (EnemyAwarenessConfig.AlarmCooldown).
local lastAlarmAt: { [number]: number } = {}

local warnedNoRemote = false

local function setState(record, state: string)
	record.Awareness.State = state
	local model = record.Model
	if model and model.Parent then
		-- Mirrored so it can be watched live in Studio's Properties panel during a playtest — the
		-- fastest way to tell "it never saw me" from "it saw me and is stuck".
		model:SetAttribute("AwarenessState", state)
	end
end

local function randomIdleSeconds(): number
	local minS, maxS = EnemyAwarenessConfig.IdleSecondsMin, EnemyAwarenessConfig.IdleSecondsMax
	return minS + math.random() * math.max(maxS - minS, 0)
end

local function isAlive(record): boolean
	local humanoid = record.Humanoid
	return humanoid ~= nil and humanoid.Health > 0 and record.Model ~= nil and record.Model.PrimaryPart ~= nil
end

-- Eye height above the root, measured once. EnemyMovement already measured the rig for pathing; reuse
-- its height when it exists rather than walking the model a second time.
local function eyeOffset(record): number
	local awareness = record.Awareness
	if awareness.EyeOffset then
		return awareness.EyeOffset
	end
	local height = record.Movement and record.Movement.Height
	if not height then
		local ok, size = pcall(function()
			return record.Model:GetExtentsSize()
		end)
		height = ok and size and size.Y or 5
	end
	awareness.EyeOffset = height * 0.4
	return awareness.EyeOffset
end

-- In range AND nothing solid between the enemy's eyes and the player. Aimed at the Head when there is
-- one, so a player crouched behind low cover whose root is hidden but whose head isn't still gets seen.
local function canSee(record, config): boolean
	local player = record.Awareness.Player
	local character = player and player.Character
	local targetPart = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	local rootPart = record.Model.PrimaryPart
	if not targetPart or not targetPart:IsA("BasePart") or not rootPart then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return false
	end

	local eye = rootPart.Position + Vector3.new(0, eyeOffset(record), 0)
	local toTarget = targetPart.Position - eye
	if toTarget.Magnitude > config.SightRange then
		return false
	end

	local params = RaycastParams.new()
	params.CollisionGroup = ENEMY_COLLISION_GROUP
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { record.Model }
	local ok, result = pcall(function()
		return Workspace:Raycast(eye, toTarget, params)
	end)
	if not ok then
		return false
	end
	return result == nil or result.Instance:IsDescendantOf(character)
end

local function fireAlarmFx(player: Player, raider: Model)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("EnemyAlarm")
	if not remote then
		if not warnedNoRemote then
			warnedNoRemote = true
			warn("[EnemyAwareness] ReplicatedStorage.Remotes.EnemyAlarm is missing — the alarm still calls enemies in, but the player gets no sound/marker. It's declared in default.project.json; re-sync Rojo.")
		end
		return
	end
	pcall(function()
		remote:FireClient(player, raider)
	end)
end

local function raiseAlarm(raiderRecord)
	local awareness = raiderRecord.Awareness
	local player = awareness.Player
	if not player then
		return
	end
	local now = os.clock()
	local last = lastAlarmAt[player.UserId]
	if last and now - last < EnemyAwarenessConfig.AlarmCooldown then
		return
	end
	lastAlarmAt[player.UserId] = now

	-- The roster is append-only for the whole encounter (see CombatEncounterService's comment on it),
	-- so it holds the dead too — the alive filter here is load-bearing, not tidiness.
	for _, other in ipairs(awareness.Enemies or {}) do
		if other ~= raiderRecord and isAlive(other) and not EnemyAwareness.IsAware(other) then
			local config = EnemyAwarenessConfig.Get(other.TypeKey)
			if config and math.random() < (config.AnswersAlarm or 0) then
				EnemyAwareness.Alert(other, "Alarm")
			end
		end
	end

	fireAlarmFx(player, raiderRecord.Model)
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

-- Called by RunRaidCombat for every enemy it spawns. Leaves record.Awareness nil — i.e. always aware —
-- unless this room starts unaware AND the type has an EnemyAwarenessConfig entry.
function EnemyAwareness.Init(record, opts)
	if not opts or not opts.StartUnaware then
		return
	end
	if not EnemyAwarenessConfig.Get(record.TypeKey) then
		return
	end
	local rootPart = record.Model and record.Model.PrimaryPart
	if not rootPart then
		return
	end
	local now = os.clock()
	record.Awareness = {
		State = "Idle",
		SpawnPosition = rootPart.Position,
		IdleUntil = now + randomIdleSeconds(),
		-- Staggered so a room of enemies spawned on the same frame doesn't raycast on the same frame.
		NextSightAt = now + math.random() * EnemyAwarenessConfig.SightCheckInterval,
		Player = opts.Player,
		Enemies = opts.Enemies,
	}
	setState(record, "Idle")
end

function EnemyAwareness.IsAware(record): boolean
	return record.Awareness == nil or record.Awareness.State == "Alerted"
end

-- Returns true when this handled the enemy for the tick (it's unaware), false when the caller should
-- run the normal EnemyAI pattern. Never yields.
function EnemyAwareness.Tick(record, context): boolean
	if EnemyAwareness.IsAware(record) then
		return false
	end
	if not isAlive(record) then
		return true
	end
	local awareness = record.Awareness
	local config = EnemyAwarenessConfig.Get(record.TypeKey)
	if not config then
		return false -- can't happen (Init checked), but an unaware enemy with no rules should fight
	end

	local now = os.clock()
	if now >= awareness.NextSightAt then
		awareness.NextSightAt = now + EnemyAwarenessConfig.SightCheckInterval
		if canSee(record, config) then
			EnemyAwareness.Alert(record, "Spotted")
			return false -- fights starting THIS tick, rather than standing idle one tick longer
		end
	end

	if StatusEffects.IsStunned(record) then
		EnemyMovement.Stop(record)
		return true
	end

	local humanoid = record.Humanoid
	local rootPos = record.Model.PrimaryPart.Position

	if awareness.State == "Idle" then
		EnemyMovement.Stop(record)
		EnemyAnimation.Ambient(record, "Idle")
		if now >= awareness.IdleUntil then
			local angle = math.random() * math.pi * 2
			-- sqrt for a uniform spread across the disc; plain random() * radius bunches points at the centre.
			local distance = math.sqrt(math.random()) * (config.WanderRadius or 0)
			awareness.WanderPoint = awareness.SpawnPosition + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			awareness.WanderGiveUpAt = now + EnemyAwarenessConfig.WanderGiveUpSeconds
			setState(record, "Wander")
		end
		return true
	end

	-- Wander. Speed is recomputed every tick from the record's own MoveSpeed (same rule EnemyAI uses),
	-- so a slow that lands mid-stroll still applies, and nothing has to be undone on alert — the
	-- pattern sets its own speed from MoveSpeed the moment it takes over.
	local speed = (record.MoveSpeed or humanoid.WalkSpeed) * EnemyAwarenessConfig.WanderSpeedMultiplier * StatusEffects.GetSpeedMultiplier(record)
	if math.abs(humanoid.WalkSpeed - speed) > 0.01 then
		humanoid.WalkSpeed = speed
	end

	local point = awareness.WanderPoint
	local flat = Vector3.new(point.X - rootPos.X, 0, point.Z - rootPos.Z)
	if flat.Magnitude <= WANDER_ARRIVE_DISTANCE or now >= awareness.WanderGiveUpAt then
		awareness.WanderPoint = nil
		awareness.IdleUntil = now + randomIdleSeconds()
		setState(record, "Idle")
		EnemyMovement.Stop(record)
		EnemyAnimation.Ambient(record, "Idle")
		return true
	end

	EnemyMovement.WalkTo(record, point, context)
	EnemyAnimation.Ambient(record, "Walk")
	return true
end

-- reason: "Spotted" | "Damaged" | "Alarm". No-op for an enemy that's already aware (including every
-- enemy with no Awareness state at all).
function EnemyAwareness.Alert(record, reason: string)
	if EnemyAwareness.IsAware(record) then
		return
	end
	setState(record, "Alerted")
	record.Awareness.WanderPoint = nil
	EnemyAnimation.Ambient(record, nil) -- the pattern's own Locomotion/attack tracks take over from here
	EnemyMovement.Stop(record) -- drop the wander path; the pattern starts its own walk fresh

	-- Only a Raider that noticed the player ITSELF raises the alarm — one answering another Raider's
	-- doesn't re-raise it (which would also defeat the cooldown by chaining).
	local config = EnemyAwarenessConfig.Get(record.TypeKey)
	if config and config.RaisesAlarm and reason ~= "Alarm" then
		raiseAlarm(record)
	end
end

-- Hooked in CombatEncounterService.resolveAndApplyDamage, which every damage source goes through, so
-- shooting an enemy from beyond its sight range still wakes it up — and a Raider shot that way still
-- raises the alarm.
function EnemyAwareness.OnDamaged(record)
	-- A shot that KILLS an unaware enemy wakes nothing: a clean stealth kill on a Raider shouldn't
	-- still raise the alarm with its dying breath. (This runs after the damage has landed, so a dead
	-- Humanoid here means this was the killing hit.)
	if not isAlive(record) then
		return
	end
	if record.Awareness and not EnemyAwareness.IsAware(record) then
		EnemyAwareness.Alert(record, "Damaged")
	end
end

return EnemyAwareness
