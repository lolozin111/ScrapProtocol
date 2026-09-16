--[[
	EnemyAI.lua
	Named enemy AI patterns, looked up by name (EnemyConfig.Types[key].AIPattern) — same
	flat-table-of-named-strategies shape as RobotBehaviors.lua, for the same reason: a new pattern
	is one new function here plus pointing an EnemyConfig entry at its name, no engine changes.

	CombatEncounterService drives these from ONE shared per-encounter tick loop (see that file),
	the same "one loop iterates every live thing" convention as AutoMinerService/SmeltService's
	background loops — NOT one coroutine per spawned enemy. Each pattern function below is called
	once per tick per enemy and does one tick's worth of thinking; it is not itself a loop.

	`enemy` is the per-instance record CombatEncounterService builds at spawn (Model, Humanoid,
	wave-SCALED ContactDamage/Defense already resolved onto it — see that file — plus
	ContactRange/AttackCooldown copied as-is from EnemyConfig, SpawnTime stamped at spawn (see
	SPAWN_GRACE_SECONDS below), though CombatEncounterService currently overrides ContactRange to
	BaseConfig.WallAttackRange for base defense specifically — see spawnEnemy's comment there, and
	LastAttackTime/LastMoveThink timestamps this file maintains). `context` is shared across every
	enemy in the tick: { TargetPosition, Now, DamageTarget, TargetPart?, TargetPlayer? }. The last two
	are raid-only (RunRaidCombat's aiContext sets both; RunWave's has neither, since base defense has
	no player to point at) — TargetPart is the player's live HumanoidRootPart, there for consumers like
	EnemyAnimation.lua whose damage lands off an async animation marker instead of this loop's own
	polling and so needs the player's position at the INSTANT of the hit, not this tick's snapshot;
	TargetPlayer is the Player itself, there so a hit can apply a status through PlayerSpeed, which a
	bare position can never do. Both nil in a wave — anything that reads them must tolerate that.

	TargetPosition is deliberately just a point in space, not tied to any particular kind of
	target — base defense currently points it at the plot's own anchor position (the wall), NOT
	the player, so an enemy chases and attacks whatever CombatEncounterService is defending this
	encounter, whatever that turns out to be. A future raid-room mode that wants enemies chasing
	the PLAYER instead just passes the player's own position here — this file doesn't change.

	DamageTarget(amount) is a closure CombatEncounterService supplies so a Shield
	(RobotBehaviors.Utility.Shield) can absorb incoming hits before whatever's actually being
	defended (the wall's HP pool, today) takes the rest. This file never needs to know what it's
	ultimately damaging, or that shields exist — it just always damages through this one
	indirection, once it's decided an attack lands.
]]

local StatusEffects = require(script.Parent.StatusEffects)
local EnemyAnimation = require(script.Parent.EnemyAnimation)

local EnemyAI = {}

-- How often a Chasing enemy re-issues a MoveTo while it's still out of contact range — not every
-- single tick, so a fast tick rate doesn't spam Humanoid:MoveTo (and the pathfinding work behind
-- it) for no benefit.
local MOVE_THINK_INTERVAL = 0.5

-- Extra slack (studs) added ONLY to the "am I close enough to attack" check below, on top of
-- enemy.ContactRange — NOT used for where MoveTo aims (see standPoint below, still the exact
-- ring). Humanoid:MoveTo doesn't guarantee landing exactly on its target point: its own arrival
-- tolerance can stop a walker a couple studs short, and on real terrain (a sloped/raised base edge,
-- a corner that isn't a perfect circle) the enemy can physically run out of ground to stand on
-- before reaching the exact ring, especially now that the ring sits right at the base's true edge
-- (see CombatEncounterService's WALL_STOP_MARGIN comment). Without this slack, an enemy that stops
-- even slightly short of ContactRange sits there forever, stuck in the elseif branch re-issuing the
-- same MoveTo it just failed to complete — visibly stopped, but never actually attacking, which is
-- exactly what "not hitting the base, no damage" looks like. This makes "close enough" tolerant of
-- that real-world imprecision instead of demanding a pixel-perfect arrival.
local ATTACK_RANGE_SLACK = 12

-- Freshly-spawned enemies can't land a hit for this long after CombatEncounterService.spawnEnemy
-- stamps their SpawnTime — they still walk in and close the distance normally during this window,
-- only the actual damage tick is held back. Without this, an enemy that happens to spawn already
-- inside ContactRange (a tight spawn ring, a corner of a small room) can land a hit the very instant
-- it appears, before the player's even had a chance to react — "so it avoid player feeling like the
-- game is unfair."
local SPAWN_GRACE_SECONDS = 1

-- Chaser: walk straight at the target, deal ContactDamage on a cooldown once within ContactRange.
-- Every enemy type used this alone for the first pass, per the original "simple wave AI" ask — this
-- was deliberately the only pattern until EnemyConfig.EliteTypes.Siegebreaker introduced Slam below,
-- the second pattern the game has ever had. A ranged/kiting pattern, or one that retreats below a
-- health threshold, is a new function here later, not a rewrite of either of these two.
EnemyAI.Patterns = {}

-- Opt-in per-type facing fix (EnemyConfig `WalkFacingOffset`, degrees). A rig whose body was built
-- pointing somewhere other than its HumanoidRootPart's forward walks and fights sideways, because the
-- Humanoid turns the ROOT and the body is bolted to it at whatever angle it was built. The Hulk solves
-- the same problem inside EnemyAnimation; this is the cheap version for a plain Chaser, and it needs
-- nothing from the rig: no Motor6Ds, no RigAttachments, no joints of any kind, since it turns the whole
-- assembly rather than anything inside it. That matters — some of these enemy models have no animation
-- joints at all, so a fix that turned the body AT a joint had nothing to turn.
--
-- Turning is a physics constraint, not per-frame CFrame writes: writing the root's CFrame every tick
-- fights the Humanoid's own movement controller and the enemy barely covers ground (learned on the
-- Hulk — see EnemyAnimation.startTurning, which this deliberately mirrors).
local function ensureFacing(enemy)
	if enemy.FacingAlign or enemy.FacingChecked then
		return
	end
	enemy.FacingChecked = true -- one attempt per enemy, whatever the outcome

	local offset = enemy.TypeData and enemy.TypeData.WalkFacingOffset
	local rootPart = enemy.Model and enemy.Model.PrimaryPart
	if not offset or not rootPart then
		return
	end

	-- The Humanoid's own rotation would fight the constraint, and an NPC whose physics Roblox handed to
	-- a nearby player's client would fight it too (same two lessons as the Hulk).
	if enemy.Humanoid then
		enemy.Humanoid.AutoRotate = false
	end
	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)

	local attachment = Instance.new("Attachment")
	attachment.Name = "FacingAttachment"
	attachment.Parent = rootPart

	local align = Instance.new("AlignOrientation")
	align.Name = "FacingAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = math.huge
	align.Responsiveness = 25
	align.MaxAngularVelocity = math.rad((enemy.TypeData and enemy.TypeData.TurnSpeed) or 360)
	local _, spawnYaw = rootPart.CFrame:ToEulerAnglesYXZ()
	align.CFrame = CFrame.fromEulerAnglesYXZ(0, spawnYaw, 0)
	align.Parent = rootPart
	enemy.FacingAlign = align
end

-- Points a WalkFacingOffset enemy at whatever it's chasing, with its own build angle added on top.
local function aimFacing(enemy, rootPart: BasePart, targetPosition: Vector3)
	local align = enemy.FacingAlign
	if not align then
		return
	end
	local flat = Vector3.new(targetPosition.X - rootPart.Position.X, 0, targetPosition.Z - rootPart.Position.Z)
	if flat.Magnitude < 0.1 then
		return -- standing on top of the target: keep the facing we already have rather than spinning
	end
	align.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit) * CFrame.Angles(0, math.rad(enemy.TypeData.WalkFacingOffset), 0)
end

EnemyAI.Patterns.Chaser = function(enemy, context)
	local model = enemy.Model
	local humanoid = enemy.Humanoid
	local rootPart = model and model.PrimaryPart
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	-- A stunned enemy neither moves nor attacks. Checked before anything else so a stun is a real
	-- interrupt rather than a slow — Move(zero) stops whatever walk was already in progress.
	if StatusEffects.IsStunned(enemy) then
		humanoid:Move(Vector3.new(0, 0, 0))
		EnemyAnimation.Locomotion(enemy, false)
		return
	end

	-- Slowing statuses scale the enemy's own MoveSpeed. Recomputed every think rather than set once,
	-- so it restores itself the moment the status expires with nothing to remember to undo. Scaled
	-- from the RECORD's MoveSpeed, not humanoid.WalkSpeed — the latter is what these statuses
	-- mutate, so reading it back would compound the slow on every think until the enemy froze.
	local desiredSpeed = (enemy.MoveSpeed or humanoid.WalkSpeed) * StatusEffects.GetSpeedMultiplier(enemy)
	if math.abs(humanoid.WalkSpeed - desiredSpeed) > 0.01 then
		humanoid.WalkSpeed = desiredSpeed
	end

	local toEnemy = rootPart.Position - context.TargetPosition
	local distance = toEnemy.Magnitude
	local inRange = distance <= enemy.ContactRange + ATTACK_RANGE_SLACK

	-- Whole-model facing correction, for a type whose EnemyConfig entry sets WalkFacingOffset (nothing
	-- happens for any other type). Set up once per enemy, aimed every tick.
	ensureFacing(enemy)
	aimFacing(enemy, rootPart, context.TargetPosition)

	-- Idle/Move animations for a type whose EnemyConfig entry sets Animations; a no-op for every other
	-- type, and for an "Animated" enemy falling back to this pattern (its own Tick owns its tracks).
	-- Fed this walk decision rather than measured velocity, for the reason EnemyAnimation.Tick's Move
	-- block gives.
	EnemyAnimation.Locomotion(enemy, not inRange)

	if inRange then
		-- Move(zero) stops whatever walk is already in progress the instant we cross into range,
		-- and stays as a defensive backstop every tick — cheap, and covers the moment right after
		-- crossing the boundary before the standPoint walk below would've naturally stopped anyway.
		humanoid:Move(Vector3.new(0, 0, 0))
		if context.Now - enemy.LastAttackTime >= enemy.AttackCooldown and context.Now - enemy.SpawnTime >= SPAWN_GRACE_SECONDS then
			enemy.LastAttackTime = context.Now
			context.DamageTarget(enemy.ContactDamage)
		end
	elseif context.Now - enemy.LastMoveThink >= MOVE_THINK_INTERVAL then
		enemy.LastMoveThink = context.Now
		-- The actual fix: MoveTo used to always target TargetPosition itself (the base's dead
		-- center), so every walk command was aimed PAST the ContactRange ring and relied entirely
		-- on Move(zero) catching it after the fact each tick — any momentary jostle out of range
		-- (physics, another enemy, tick timing) re-fired this branch and sent it walking at the
		-- literal center again, which could creep an enemy further in each time it happened. Instead,
		-- aim MoveTo at a point ON the ContactRange boundary circle itself, along the current bearing
		-- from the target to the enemy — Roblox's own MoveTo arrival naturally stops the enemy right
		-- at the ring by design, it's never asked to walk any further than that in the first place.
		local direction = distance > 0 and (toEnemy / distance) or Vector3.new(1, 0, 0)
		local standPoint = context.TargetPosition + direction * enemy.ContactRange
		humanoid:MoveTo(standPoint)
	end
end

----------------------------------------------------------------------
-- Slam — Siegebreaker's pattern (EnemyConfig.EliteTypes.Siegebreaker). Chases exactly like Chaser
-- above (this file's walking half is copy-identical on purpose — one boundary-circle MoveTo
-- convention, not two), but the attack half is a three-state cycle instead of a flat per-tick
-- cooldown hit: Idle -> winding up -> impact. No coroutines, no task.wait — same as everywhere else
-- in this codebase, this function is called once per tick per enemy and returns immediately every
-- time; the "wait" is just comparing context.Now against a timestamp stashed on the record, the
-- same polling convention RunWave/RunRaidCombat use for everything else.
--
-- Siegebreaker's own EnemyConfig entry sets ContactDamage = 0 — the slam REPLACES contact damage,
-- it doesn't stack on top of it, so this pattern never calls context.DamageTarget outside the
-- impact branch below.
----------------------------------------------------------------------

-- Matches HudKit.COLOR.Bad — the same "this is dangerous" red the HUD already trains a player to
-- read, so the battlefield doesn't need to teach a second color for the same meaning.
local SLAM_WARNING_COLOR = Color3.fromRGB(190, 90, 75)

-- Thin on purpose — this is a flat ground decal, not a real cylinder prop; same convention
-- GroundEffectService's own puddle/patch visuals use for the identical "lay a Cylinder flat" trick
-- (Size.X is a Cylinder's height axis, so a small X keeps it a disc instead of a drum).
local SLAM_DISC_HEIGHT = 0.2

-- Approximates "straight down to the floor" from a HumanoidRootPart position — HipHeight plus half
-- the root part's own size is the standard "root to feet" offset. This only feeds a VISUAL (where
-- the ground disc sits), never the mechanic itself (the radius check below compares full 3D
-- positions, unprojected, exactly as specified) — being a stud or two off the true floor height
-- costs nothing but doesn't matter here.
local function slamGroundPosition(enemy): Vector3
	local rootPart = enemy.Model and enemy.Model.PrimaryPart
	local drop = 3
	if rootPart and enemy.Humanoid then
		drop = enemy.Humanoid.HipHeight + rootPart.Size.Y * 0.5
	end
	return enemy.SlamCentre - Vector3.new(0, drop, 0)
end

-- Builds the telegraph: a flat Neon cylinder on the ground plus a colour tint on the enemy model
-- itself, so the commit reads both from above (where it will land) and from eye level (that it has
-- committed at all). This whole codebase has no telegraph precedent and no animation import pass
-- (deferred post-launch, see this file's header conventions elsewhere) — same "missing art never
-- breaks the loop" rule as everything else here, just inverted: there IS no art to be missing, this
-- IS the art, drawn instead of loaded, same as WeldingPanel's robot rigs.
--
-- pcall'd exactly like UltimateEffects wraps its own effect functions — a telegraph is a tell, not
-- the mechanic underneath it (that's the radius check in the impact branch below, which runs
-- unconditionally regardless of whether this succeeded). A broken visual should cost the player the
-- warning, never the encounter.
local function spawnTelegraph(enemy)
	local ok = pcall(function()
		local part = Instance.new("Part")
		part.Name = "SlamTelegraph"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false -- must never stop a shot or a MoveTo, it's a decal, not a wall
		part.CanTouch = false
		part.Material = Enum.Material.Neon
		part.Transparency = 0.55
		part.Color = SLAM_WARNING_COLOR
		part.Shape = Enum.PartType.Cylinder
		-- Starts near-zero radius — updateTelegraph grows it to SlamRadius across the wind-up below,
		-- so the disc itself reads as a countdown, not just a static warning marker.
		part.Size = Vector3.new(SLAM_DISC_HEIGHT, 0.1, 0.1)
		part.CFrame = CFrame.new(slamGroundPosition(enemy)) * CFrame.Angles(0, 0, math.rad(90))
		-- Same folder the enemy Model itself lives in (CombatEncounterService.spawnEnemy's
		-- parentFolder) — NOT a child of the Model — so the encounter's own teardown
		-- (playerFolder:Destroy() when the wave/raid ends) destroys this for free, no extra wiring.
		-- The other half of "this can never outlive its enemy" is the Humanoid.Died hook back in
		-- CombatEncounterService.spawnEnemy, for the case where the enemy dies mid-wind-up and the
		-- REST of the encounter keeps running — that path can't reach this file at all, so it has to
		-- be handled there, not here. See that comment for why a tick-based check can't do it.
		part.Parent = enemy.Model.Parent

		-- Tint the enemy itself the same warning colour — the model visibly commits, not just the
		-- ground under it. Reverted in destroyTelegraph below.
		local originalColors = {}
		for _, descendant in ipairs(enemy.Model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				originalColors[descendant] = descendant.Color
				descendant.Color = SLAM_WARNING_COLOR
			end
		end
		enemy.SlamOriginalColors = originalColors
		enemy.SlamTelegraphPart = part
	end)
	if not ok then
		warn(("[EnemyAI] Slam telegraph failed to build for %s — the hit will still land on schedule, just without a visual tell."):format(tostring(enemy.TypeKey)))
	end
end

-- Grows the disc from spawnTelegraph's near-zero start up to the full SlamRadius, in step with how
-- much of the wind-up has elapsed — called every tick the enemy is winding up, same polling
-- convention as the rest of this file. Silently does nothing if the part is already gone (torn down
-- by CombatEncounterService's death hook, or never built because spawnTelegraph's pcall failed).
local function updateTelegraph(enemy, context)
	local part = enemy.SlamTelegraphPart
	if not part or not part.Parent then
		return
	end
	pcall(function()
		local elapsed = enemy.SlamWindup - (enemy.SlamImpactAt - context.Now)
		local fraction = enemy.SlamWindup > 0 and math.clamp(elapsed / enemy.SlamWindup, 0, 1) or 1
		local diameter = math.max(enemy.SlamRadius * 2 * fraction, 0.2)
		part.Size = Vector3.new(SLAM_DISC_HEIGHT, diameter, diameter)
	end)
end

-- Tears the telegraph down: restores the enemy's own original colours and destroys the ground
-- disc. Called from the impact branch below on the normal path (the slam resolved). The ABNORMAL
-- path — the enemy dies mid-wind-up instead of surviving to impact — is handled by
-- CombatEncounterService.spawnEnemy's Humanoid.Died hook, not here, because a dead enemy stops
-- appearing in aliveEnemies and this pattern function simply never runs for it again; polling from
-- inside this file cannot detect that death. Two teardown paths, one already-guaranteed rule: this
-- part can never outlive its enemy.
local function destroyTelegraph(enemy)
	pcall(function()
		if enemy.SlamOriginalColors then
			for part, color in pairs(enemy.SlamOriginalColors) do
				if part.Parent then
					part.Color = color
				end
			end
		end
	end)
	enemy.SlamOriginalColors = nil
	if enemy.SlamTelegraphPart then
		if enemy.SlamTelegraphPart.Parent then
			enemy.SlamTelegraphPart:Destroy()
		end
		enemy.SlamTelegraphPart = nil
	end
end

-- Keyed by TypeKey so a misconfigured type warns once, not once per tick — this runs inside the
-- encounter loop, and a per-tick warn would bury the Output window it's trying to be seen in.
local warnedMissingSlamFields = {}

EnemyAI.Patterns.Slam = function(enemy, context)
	local model = enemy.Model
	local humanoid = enemy.Humanoid
	local rootPart = model and model.PrimaryPart
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Unlike ContactDamage (which every type inherits from its faction template), the four Slam
	-- fields exist ONLY on types that opt into this pattern — so an EnemyConfig entry setting
	-- AIPattern = "Slam" without them would reach the arithmetic below with nils and THROW, from
	-- inside the tick loop. That's the failure mode CombatEncounterService's own pattern dispatch
	-- guard exists to prevent (a stranded encounter coroutine locks the player out of starting
	-- another run for the rest of the session), and it would sail straight past that guard because
	-- the pattern itself resolves fine — it's the config that's incomplete. Degrade to standing
	-- still, which is the same visible symptom as a missing pattern, with a warn that says why.
	if not (enemy.SlamWindup and enemy.SlamDamage and enemy.SlamRadius and enemy.SlamCooldown) then
		if not warnedMissingSlamFields[enemy.TypeKey] then
			warnedMissingSlamFields[enemy.TypeKey] = true
			warn(("[EnemyAI] Enemy type %s uses AIPattern \"Slam\" but is missing one of SlamWindup/SlamDamage/SlamRadius/SlamCooldown in EnemyConfig — it will stand still. Add all four."):format(
				tostring(enemy.TypeKey)))
		end
		humanoid:Move(Vector3.new(0, 0, 0))
		return
	end

	-- Same interrupt as Chaser: a stunned enemy neither moves nor attacks. This also freezes the
	-- slam cycle if it lands mid-wind-up — SlamImpactAt is an absolute timestamp, not a counter, so
	-- a stun doesn't delay the eventual impact, it just pauses this pattern's own polling (movement,
	-- the telegraph's growth) until the stun clears; the impact still resolves on the first
	-- non-stunned tick where context.Now has already passed SlamImpactAt.
	if StatusEffects.IsStunned(enemy) then
		humanoid:Move(Vector3.new(0, 0, 0))
		return
	end

	local desiredSpeed = (enemy.MoveSpeed or humanoid.WalkSpeed) * StatusEffects.GetSpeedMultiplier(enemy)
	if math.abs(humanoid.WalkSpeed - desiredSpeed) > 0.01 then
		humanoid.WalkSpeed = desiredSpeed
	end

	-- Winding up or resolving an impact takes over completely — no movement, no re-targeting, no
	-- distance check, while enemy.SlamImpactAt is set. That's the entire point: an enemy that could
	-- still steer or retarget mid-wind-up would just relocate onto whoever's standing there when the
	-- timer runs out, and the telegraph would be lying about where the hit lands.
	if enemy.SlamImpactAt then
		if context.Now < enemy.SlamImpactAt then
			humanoid:Move(Vector3.new(0, 0, 0))
			updateTelegraph(enemy, context)
			return
		end

		-- Impact. Stamp the NEXT-ready time from NOW — impact — not from when the wind-up started,
		-- per EnemyConfig.lua's own comment on SlamCooldown: measuring from wind-up start would let
		-- SlamWindup and SlamCooldown silently trade against each other, so a future tuning pass that
		-- shortens the telegraph (to make it harder to react to) would ALSO shorten the real cooldown
		-- as a side effect nobody asked for. Measuring from impact keeps the two knobs independent.
		enemy.SlamImpactAt = nil
		enemy.SlamNextReadyAt = context.Now + enemy.SlamCooldown
		destroyTelegraph(enemy)

		-- The entire mechanic, and it is deliberately mode-agnostic: context.TargetPosition is the
		-- base's fixed anchor point in a wave (RunWave) and the player's own LIVE position in a raid
		-- (RunRaidCombat) — see this file's header on TargetPosition. The identical check below
		-- means the wall (which cannot move) always eats the hit in base defense — a heavy,
		-- telegraphed blow with no way to avoid it, which is fine, it's a wall — while a raid player
		-- CAN walk out of the SlamRadius circle during the SlamWindup seconds they were just shown,
		-- making the same code a genuine, learnable dodge there. Do NOT split this into a
		-- wave-branch and a raid-branch "to make it fair" — the fairness difference is exactly the
		-- point, and it already falls out of what TargetPosition means in each mode without this
		-- file ever needing to know which mode it's in.
		if (context.TargetPosition - enemy.SlamCentre).Magnitude <= enemy.SlamRadius then
			context.DamageTarget(enemy.SlamDamage)
		end
		return
	end

	local toEnemy = rootPart.Position - context.TargetPosition
	local distance = toEnemy.Magnitude

	if distance <= enemy.ContactRange + ATTACK_RANGE_SLACK then
		-- Same defensive backstop as Chaser's Move(zero) — see that pattern's own comment.
		humanoid:Move(Vector3.new(0, 0, 0))
		if context.Now >= (enemy.SlamNextReadyAt or 0) and context.Now - enemy.SpawnTime >= SPAWN_GRACE_SECONDS then
			-- Commit: lock the centre NOW, at the moment the wind-up begins — not re-read at impact.
			-- Reading it again at impact would let anything that moves the enemy between commit and
			-- impact (a future knockback effect, physics jostle) desync the telegraph from where the
			-- hit actually resolves. A telegraph that can drift from its own hit is worse than none.
			enemy.SlamCentre = rootPart.Position
			enemy.SlamImpactAt = context.Now + enemy.SlamWindup
			spawnTelegraph(enemy)
		end
	elseif context.Now - enemy.LastMoveThink >= MOVE_THINK_INTERVAL then
		enemy.LastMoveThink = context.Now
		local direction = distance > 0 and (toEnemy / distance) or Vector3.new(1, 0, 0)
		local standPoint = context.TargetPosition + direction * enemy.ContactRange
		humanoid:MoveTo(standPoint)
	end
end

----------------------------------------------------------------------
-- Animated — VoidwakenHulk's pattern (EnemyConfig.BossTypes.VoidwakenHulk). Unlike Chaser/Slam
-- above, the actual thinking (walking, attack selection, marker-timed hit detection) lives in
-- EnemyAnimation.lua, not here — that file is sized for animation bookkeeping (loading tracks,
-- listening for markers, per-attachment fist tracking) that has nothing to do with the rest of
-- this module, the same "extract when the shape stops matching the file" call as MainHud's own
-- panel extractions. This is deliberately the thinnest possible bridge: EnemyAnimation must never
-- require this module back (that would be circular, since this file requires it above), so it
-- takes Chaser as a plain function argument instead of reaching for EnemyAI.Patterns.Chaser
-- itself — its fallback for "no usable animation" without ever needing to know this table exists.
----------------------------------------------------------------------

EnemyAI.Patterns.Animated = function(enemy, context)
	EnemyAnimation.Tick(enemy, context, EnemyAI.Patterns.Chaser)
end

return EnemyAI
