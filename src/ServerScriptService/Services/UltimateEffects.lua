--[[
	UltimateEffects.lua
	The behaviours behind Ultimate mods, looked up by name (UltimateConfig.Mods[key].Effect).

	Same flat-table-of-named-strategies shape as EnemyAI.Patterns and RobotBehaviors, for the same
	reason: a new passive is one function here plus a config entry pointing at its name — never an
	engine change. Grouped by HOOK, because when a passive fires is as much a part of it as what it
	does, and a name only means something relative to its hook.

	HOOKS (fired by CombatEncounterService's RequestFireWeapon handler, so they work identically in
	base defense and in raid rooms):

	  OnHit   — a player shot landed and damage was applied. Fires even if the target died.
	  OnKill  — that shot reduced the target to 0 health. Fires AFTER OnHit.

	Everything an effect is allowed to touch arrives on `ctx`, so no effect ever reaches into the
	encounter's internals:

	  ctx.Params        the mod's own Params table, untouched from UltimateConfig
	  ctx.Target        the enemy record that was hit/killed
	  ctx.Damage        final damage the shot actually dealt, post-pipeline
	  ctx.Origin        where the shot came from
	  ctx.Nearby(radius, excludeTarget, max)   live enemies within radius of the target
	  ctx.DealDamage(record, amount)           routes through the normal damage pipeline
	  ctx.StripDefense(record, seconds)        temporarily treats that enemy's Defense as 0

	WHY ctx.DealDamage RATHER THAN TOUCHING HUMANOIDS: secondary damage still has to run the same
	DamagePipeline as everything else, or an Ultimate would quietly bypass Defense mitigation and the
	minimum-damage floor. An effect says how much and to whom; the pipeline stays the only thing that
	decides what a hit actually lands for.

	A missing effect name warns once and does nothing — one bad config entry costs that passive, not
	the encounter, same as the guarded AIPattern dispatch.
]]

local UltimateEffects = {}

UltimateEffects.OnHit = {}
UltimateEffects.OnKill = {}

----------------------------------------------------------------------
-- OnKill
----------------------------------------------------------------------

-- "Enemies you kill detonate." Damage is a fraction of the killing blow rather than a flat number,
-- so the passive scales with the weapon carrying it instead of needing its own tuning pass every
-- time weapon damage moves.
--
-- The corpse itself is excluded from the blast: it is already dead, and including it would make the
-- numbers read as if the explosion overkilled something.
UltimateEffects.OnKill.CorpseDetonation = function(ctx)
	local radius = ctx.Params.Radius or 18
	local fraction = ctx.Params.DamageFraction or 0.5
	local splash = ctx.Damage * fraction
	if splash <= 0 then
		return
	end

	for _, record in ipairs(ctx.Nearby(radius, true)) do
		ctx.DealDamage(record, splash)
	end
end

----------------------------------------------------------------------
-- OnHit
----------------------------------------------------------------------

-- "Shots bounce to a nearby enemy." Bounces are resolved instantly rather than as travelling
-- projectiles — this game has no projectile physics (see CombatClient's own scope note; shots are
-- hitscan), so a real arc would be inventing a system rather than using one.
--
-- Each bounce picks the nearest enemy it has not already hit, so a single shot cannot chain back
-- and forth between the same two targets.
UltimateEffects.OnHit.Ricochet = function(ctx)
	local radius = ctx.Params.Radius or 24
	local bounces = ctx.Params.Bounces or 1
	local fraction = ctx.Params.DamageFraction or 0.5
	local damage = ctx.Damage * fraction
	if damage <= 0 then
		return
	end

	local candidates = ctx.Nearby(radius, true, bounces)
	for _, record in ipairs(candidates) do
		ctx.DealDamage(record, damage)
	end
end

-- "Punches through several enemies and strips their armour." The strip is the real payload — the
-- extra damage is secondary. Stripping Defense to 0 for a window means the follow-up shots from
-- ANY source (the player, robots, turrets) land at full value, which is what makes this feel like
-- a squad-wide opener rather than a personal damage bonus.
UltimateEffects.OnHit.PierceAndStrip = function(ctx)
	local radius = ctx.Params.Radius or 20
	local maxTargets = ctx.Params.MaxTargets or 5
	local fraction = ctx.Params.DamageFraction or 0.75
	local strip = ctx.Params.StripSeconds or 10

	-- The directly-hit target gets stripped too — it is the one the shot actually pierced.
	ctx.StripDefense(ctx.Target, strip)

	local damage = ctx.Damage * fraction
	for _, record in ipairs(ctx.Nearby(radius, true, maxTargets - 1)) do
		ctx.StripDefense(record, strip)
		if damage > 0 then
			ctx.DealDamage(record, damage)
		end
	end
end

----------------------------------------------------------------------
-- Dispatch
----------------------------------------------------------------------

local warnedMissing: { [string]: boolean } = {}

-- Runs `effectName` for `hook` if it exists. Returns false (and warns once) if it does not, so a
-- typo'd or not-yet-written Effect costs that passive rather than throwing inside the fire handler
-- and killing the shot.
function UltimateEffects.Fire(hook: string, effectName: string?, ctx): boolean
	if not effectName then
		return false
	end
	local table_ = UltimateEffects[hook]
	local fn = table_ and table_[effectName]
	if not fn then
		local id = hook .. "." .. tostring(effectName)
		if not warnedMissing[id] then
			warnedMissing[id] = true
			warn(("[UltimateEffects] No %q effect named %q — that Ultimate does nothing. Add it to UltimateEffects.lua or fix the Effect name in UltimateConfig."):format(hook, tostring(effectName)))
		end
		return false
	end

	-- pcall'd: an effect is content-shaped code that will be edited often, and a bad one should cost
	-- its own passive, not the player's shot or the whole encounter loop.
	local ok, err = pcall(fn, ctx)
	if not ok then
		warn(("[UltimateEffects] %s errored: %s"):format(effectName, tostring(err)))
		return false
	end
	return true
end

return UltimateEffects
