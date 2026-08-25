--[[
	DamagePipeline.lua
	Turns one hit's raw data into a single final damage number, server-side only — this is the
	`damageTaken`-style function discussed for the combat engine. Deliberately built as an ORDERED
	LIST of small, independent modifier steps rather than one big formula: each step reads the
	running damage value plus the hit packet, returns a new damage value, and the next step never
	knows or cares how the previous one got its number. Balancing later is "add, remove, or
	reorder a step," never "untangle one function that does five things at once."

	Order is meaningful, not cosmetic. The three steps below happen to all be multiplicative, so
	swapping RangeFalloff and DefenseMitigation wouldn't change today's result — but the FIRST time
	an ADDITIVE step shows up (a flat "weak point" bonus, say), order stops being free: +10 applied
	BEFORE DefenseMitigation gets reduced by the target's defense same as everything else; +10
	applied AFTER it bypasses defense entirely, like a real headshot. Where a future step belongs
	in the list is itself a balance decision — leave a comment on it when the time comes.

	Hit packet shape (built by whatever calls Resolve — CombatEncounterService today):
	{
		BaseDamage = number,       -- pre-mod/affix/pipeline damage, from CombatMath
		                           -- .GetEffectiveWeaponStats(...).Damage (players) or
		                           -- CombatMath.GetEffectiveStats("Robots", key, profile).Damage
		Origin = Vector3,         -- where the shot/hit originated (for range falloff)
		HitPosition = Vector3,    -- where it actually landed
		RangeProfile = table?,    -- optional, see applyRangeFalloff below; nil = no falloff at all
		Penetration = number?,    -- flat reduction to the target's effective Defense before
		                           -- DefenseMitigation runs; nil/0 = no penetration. A weapon or a
		                           -- future Forge affix can supply this — the pipeline doesn't
		                           -- care where it came from, only that it's a number on the packet.
		TargetDefense = number,   -- the enemy's EnemyConfig.Defense (or 0 for an undefended target)
	}
]]

local DamagePipeline = {}

-- Absolute floor — no combination of high defense + bad range ever reduces a landed hit to 0.
-- Keeps a weak starter weapon still able to (slowly) kill anything, rather than needing a hard
-- damage-vs-defense cap tuned by hand for every future enemy type.
DamagePipeline.MinimumDamage = 1

-- RangeFalloff: RangeProfile = { FalloffStart, FalloffEnd, MinMultiplier }. Full damage (1x) at or
-- under FalloffStart studs; linearly drops to MinMultiplier by FalloffEnd studs; MinMultiplier
-- beyond that. A weapon with no RangeProfile at all (most weapons — only shotguns/snipers should
-- bother) skips this step entirely at 1x, so most of CraftingRecipes.Weapons never needs to know
-- this system exists.
local function applyRangeFalloff(damage: number, packet): number
	local profile = packet.RangeProfile
	if not profile then
		return damage
	end
	local distance = (packet.HitPosition - packet.Origin).Magnitude
	if distance <= profile.FalloffStart then
		return damage
	end
	if distance >= profile.FalloffEnd then
		return damage * profile.MinMultiplier
	end
	local t = (distance - profile.FalloffStart) / (profile.FalloffEnd - profile.FalloffStart)
	local multiplier = 1 + (profile.MinMultiplier - 1) * t
	return damage * multiplier
end

-- DefenseMitigation: ratio-based, not flat subtraction — `damage * 100/(100+effectiveDefense)`.
-- Chosen over flat subtraction specifically because flat subtraction can hit 0 outright against a
-- heavily-defended target (a weak weapon becomes literally unable to hurt it); the ratio only ever
-- approaches 0 as defense climbs, so more defense is always meaningfully strong without a single
-- number ever making a target unkillable to a specific weapon. Penetration reduces the target's
-- EFFECTIVE defense before the ratio is computed, so it's "ignore some of their defense," not a
-- separate damage bonus.
local function applyDefenseMitigation(damage: number, packet): number
	local penetration = packet.Penetration or 0
	local effectiveDefense = math.max((packet.TargetDefense or 0) - penetration, 0)
	local mitigation = 100 / (100 + effectiveDefense)
	return damage * mitigation
end

local function applyMinimumFloor(damage: number): number
	return math.max(damage, DamagePipeline.MinimumDamage)
end

-- The ordered list itself — see this file's header on why order is a real decision, not
-- bookkeeping. Add a new step by inserting a `{ Name = "...", Fn = ... }` entry wherever in this
-- list it needs to run; nothing else in this file or in CombatEncounterService needs to change.
DamagePipeline.Steps = {
	{ Name = "RangeFalloff", Fn = applyRangeFalloff },
	{ Name = "DefenseMitigation", Fn = applyDefenseMitigation },
	{ Name = "MinimumFloor", Fn = applyMinimumFloor },
}

-- Runs `packet` through every step in order, threading the damage value through each, and returns
-- the final number (rounded — health bars and combat text don't need fractional studs of damage).
function DamagePipeline.Resolve(packet): number
	local damage = packet.BaseDamage
	for _, step in ipairs(DamagePipeline.Steps) do
		damage = step.Fn(damage, packet)
	end
	return math.round(damage)
end

return DamagePipeline
