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
	enemy in the tick: { TargetPosition, Now, DamageTarget }.

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
-- Every enemy type uses this today (see EnemyConfig.lua's faction templates) — deliberately the
-- only pattern for this first pass, per the "simple wave AI" ask. A ranged/kiting pattern, or one
-- that retreats below a health threshold, is a new function here later, not a rewrite of this one.
EnemyAI.Patterns = {}

EnemyAI.Patterns.Chaser = function(enemy, context)
	local model = enemy.Model
	local humanoid = enemy.Humanoid
	local rootPart = model and model.PrimaryPart
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	local toEnemy = rootPart.Position - context.TargetPosition
	local distance = toEnemy.Magnitude

	if distance <= enemy.ContactRange + ATTACK_RANGE_SLACK then
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

return EnemyAI
