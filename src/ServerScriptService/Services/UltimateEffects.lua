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
	  ctx.Nearby(radius, excludeTarget, max)   live enemies within radius of the target, nearest first
	  ctx.NearestTo(record, radius, exclude)   nearest live enemy to some OTHER enemy, for chaining
	  ctx.DealDamage(record, amount)           routes through the normal damage pipeline
	  ctx.ApplyStatus(record, key, overrides)  bleed / stun / slow / shred — see StatusConfig
	  ctx.EveryNthShot(n)                      true on every nth shot fired this encounter
	  ctx.CountHitOn(record)                   how many times this weapon has hit THAT enemy

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

-- Detonator: "every time you kill an enemy, an explosion will happen and any enemy nearby will
-- take a chunk of damage, perfect for helping with wave clearing."
--
-- Damage is a fraction of the killing blow rather than a flat number, so it scales with whatever
-- weapon is carrying the mod instead of needing a re-tune every time weapon damage moves. The
-- corpse itself is excluded — it is already dead, and including it would make the numbers read as
-- if the blast overkilled something.
UltimateEffects.OnKill.Detonator = function(ctx)
	local splash = ctx.Damage * (ctx.Params.DamageFraction or 0.6)
	if splash <= 0 then
		return
	end
	for _, record in ipairs(ctx.Nearby(ctx.Params.Radius or 18, true)) do
		ctx.DealDamage(record, splash)
	end
end

----------------------------------------------------------------------
-- OnHit
----------------------------------------------------------------------

-- Ricochet: "every 3rd shot will ricochet to nearby enemies, up to 5, where each ricochet will
-- increase the damage of the next one until the ricochet projectile dies off. If no enemy is found
-- nearby the last enemy hit then the ricochet bullet just disappears."
--
-- Walks body to body rather than fanning out from the original target: each bounce searches around
-- the enemy it just hit, and stops the moment it finds nothing in range. Already-hit enemies are
-- excluded so a bullet cannot bounce back and forth between the same two targets forever.
UltimateEffects.OnHit.Ricochet = function(ctx)
	if not ctx.EveryNthShot(ctx.Params.EveryNthShot or 3) then
		return
	end

	local damage = ctx.Damage * (ctx.Params.FirstBounceFraction or 0.5)
	local growth = ctx.Params.DamageGrowth or 0.35
	local radius = ctx.Params.Radius or 26
	local from = ctx.Target
	local hit = { [ctx.Target] = true }

	for _ = 1, (ctx.Params.MaxBounces or 5) do
		local next_ = ctx.NearestTo(from, radius, hit)
		if not next_ then
			break -- nothing in range: the bullet dies off here, as specced
		end
		ctx.DealDamage(next_, damage)
		hit[next_] = true
		from = next_
		damage *= (1 + growth) -- each bounce lands harder than the last
	end
end

-- Leg Breaker: "every 5th shot will make an enemy stunned for a full 5 seconds, and while they are
-- stunned their defenses drop to 0."
--
-- The shred is applied at its stack cap rather than as a separate "set defence to zero" path, so it
-- expires on the normal status clock and shows up in the same queries everything else uses.
UltimateEffects.OnHit.LegBreaker = function(ctx)
	if not ctx.EveryNthShot(ctx.Params.EveryNthShot or 5) then
		return
	end
	ctx.ApplyStatus(ctx.Target, "Stun", { Duration = ctx.Params.StunSeconds or 5 })
	ctx.ApplyStatus(ctx.Target, "ArmourShred", {
		Stacks = ctx.Params.ShredStacks or 4,
		Duration = ctx.Params.StunSeconds or 5,
	})
end

-- .100mm: "able to pierce up to 7 enemies, where each enemy hit will lose 50% of their defense."
--
-- One ArmourShred stack is exactly a 50% reduction (see StatusConfig), so the spec maps onto the
-- status system without a special case — and two different shredders hitting the same enemy
-- compound properly instead of overwriting each other.
UltimateEffects.OnHit.PierceShred = function(ctx)
	ctx.ApplyStatus(ctx.Target, "ArmourShred", { Stacks = ctx.Params.ShredStacks or 1 })

	local damage = ctx.Damage * (ctx.Params.DamageFraction or 0.8)
	local extra = (ctx.Params.MaxTargets or 7) - 1 -- the direct hit is one of the seven
	for _, record in ipairs(ctx.Nearby(ctx.Params.Radius or 22, true, extra)) do
		ctx.ApplyStatus(record, "ArmourShred", { Stacks = ctx.Params.ShredStacks or 1 })
		if damage > 0 then
			ctx.DealDamage(record, damage)
		end
	end
end

-- Shark Bullet: "if an enemy was shot 5 times, apply a stack of bleed (up to 3 stacks)."
--
-- The count is per ENEMY, not per player — five hits spread across five different enemies should
-- not bleed anything. Tracked on the enemy record so it dies with them.
UltimateEffects.OnHit.SharkBullet = function(ctx)
	local per = ctx.Params.HitsPerStack or 5
	local count = ctx.CountHitOn(ctx.Target)
	if count % per ~= 0 then
		return
	end
	ctx.ApplyStatus(ctx.Target, "Bleed", { Stacks = 1 })
end

-- AimBot: "every 3rd bullet will be autotracked into an enemy head, causing a headshot."
--
-- SCOPE NOTE: the "autotracked" half is not implemented, and deliberately so. Shots are hitscan
-- rays fired by the client (see CombatClient's own scope note) — redirecting one mid-flight would
-- mean inventing projectile steering, and silently moving a player's aim tends to feel worse than
-- it sounds. What ships is the payoff: every 3rd landed shot counts as a headshot. If real aim
-- assist is wanted later it belongs client-side in the raycast, not here.
UltimateEffects.OnHit.AimBot = function(ctx)
	if not ctx.EveryNthShot(ctx.Params.EveryNthShot or 3) then
		return
	end
	-- The Instakill testing flag is gone; this is the intended behaviour. Damage numbers are what
	-- made it verifiable without it — a gold headshot number every 3rd hit is unmistakable.
	local bonus = (ctx.Params.HeadshotMultiplier or 1.5) - 1
	if bonus > 0 then
		ctx.DealDamage(ctx.Target, ctx.Damage * bonus, "Headshot")
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
