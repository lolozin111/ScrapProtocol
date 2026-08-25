--[[
	RobotBehaviors.lua
	Named robot behaviors, looked up by RobotBehaviorConfig.Robots[key].Behavior — mirrors
	EnemyAI.lua's shape and reasoning exactly (flat table of named strategies, one shared tick loop
	in CombatEncounterService drives every deployed robot through these, not one coroutine per
	robot).

	SCOPE NOTE: this file's own targeting/effect logic stays exactly as originally written — every
	behavior here still just acts on its own cooldown against `context.AliveEnemies` (nearest-to-
	the-player-first), no travel, no real position of its own, no physical Model. Deployed robots
	stay a purely abstract system — the physical, positioned, individually-leveled "Turrets" thing
	(TurretConfig.lua/TurretService.lua, Base Defense & Turrets phase round 2) turned out to be its
	own dedicated system instead of a skin over DeployedRobots (round 1's approach) — see
	CombatEncounterService.lua's own header for the full picture. This file's shape never needed to
	change for any of that.

	Combat behaviors damage enemies through `context.DamageEnemy`, using the robot's own
	CombatMath-derived FireRate as its attack cooldown (1/FireRate seconds between actions) — same
	number the old headless sim already computed DPS from, just spent as discrete hits now instead
	of a continuous rate.

	Utility behaviors buff the player instead. None of the 4 robots built so far are configured to
	use these (see RobotBehaviorConfig.lua's header on why) — they're real, working code, just
	unused until a support-flavored robot recipe points at one.
]]

local RobotBehaviors = {}
RobotBehaviors.Combat = {}
RobotBehaviors.Utility = {}

----------------------------------------------------------------------
-- Combat
----------------------------------------------------------------------

-- SingleTarget: hits whichever enemy is first in context.AliveEnemies (CombatEncounterService
-- keeps that list ordered nearest-to-the-player-first, so this behaves like "focus the closest
-- threat" without needing its own distance math).
RobotBehaviors.Combat.SingleTarget = function(robot, context)
	local cooldown = 1 / math.max(robot.EffectiveStats.FireRate, 0.01)
	if context.Now - robot.LastActionTime < cooldown then
		return
	end
	local target = context.AliveEnemies[1]
	if not target then
		return
	end
	robot.LastActionTime = context.Now
	context.DamageEnemy(target, robot.EffectiveStats.Damage)
end

-- Cleave: hits the nearest `TargetCount` enemies at once (from RobotBehaviorConfig's per-robot
-- tunable, default 2) — same per-hit damage as SingleTarget, just spread across more targets, so a
-- Cleave robot trades single-target focus for board-wide chip damage rather than being strictly
-- better or worse.
RobotBehaviors.Combat.Cleave = function(robot, context)
	local cooldown = 1 / math.max(robot.EffectiveStats.FireRate, 0.01)
	if context.Now - robot.LastActionTime < cooldown then
		return
	end
	if #context.AliveEnemies == 0 then
		return
	end
	robot.LastActionTime = context.Now
	local count = math.min(robot.BehaviorConfig.TargetCount or 2, #context.AliveEnemies)
	for i = 1, count do
		context.DamageEnemy(context.AliveEnemies[i], robot.EffectiveStats.Damage)
	end
end

----------------------------------------------------------------------
-- Utility
----------------------------------------------------------------------

-- Shield: grants (or tops up, capped) a temporary absorb pool that CombatEncounterService's
-- DamageTarget indirection drains before whatever's actually being defended takes the rest — the
-- base's WallHP, currently (base defense moved from "protect the player" to "protect the wall",
-- see CombatEncounterService.lua's header; this behavior didn't need to change, only what it's
-- ultimately shielding did). Expects CooldownSeconds/ShieldAmount/ShieldCap on the robot's
-- RobotBehaviorConfig entry; all three fall back to reasonable defaults if a future robot's entry
-- omits them.
RobotBehaviors.Utility.Shield = function(robot, context)
	local cfg = robot.BehaviorConfig
	local cooldown = cfg.CooldownSeconds or 15
	if context.Now - robot.LastActionTime < cooldown then
		return
	end
	robot.LastActionTime = context.Now
	local amount = cfg.ShieldAmount or 25
	local cap = cfg.ShieldCap or 50
	context.PlayerState.Shield = math.min((context.PlayerState.Shield or 0) + amount, cap)
end

-- SpeedBoost: temporary WalkSpeed multiplier via context.GrantSpeedBoost, which CombatEncounterService
-- supplies as a closure that also handles reverting it after DurationSeconds. Expects
-- CooldownSeconds/SpeedMultiplier/DurationSeconds on the robot's config entry.
RobotBehaviors.Utility.SpeedBoost = function(robot, context)
	local cfg = robot.BehaviorConfig
	local cooldown = cfg.CooldownSeconds or 20
	if context.Now - robot.LastActionTime < cooldown then
		return
	end
	robot.LastActionTime = context.Now
	context.GrantSpeedBoost(cfg.SpeedMultiplier or 1.3, cfg.DurationSeconds or 5)
end

return RobotBehaviors
