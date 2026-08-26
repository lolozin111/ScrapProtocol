--[[
	StatusConfig.lua
	Status effects an enemy can be under — bleed, poison, stun, slow, armour shred, and whatever
	comes next.

	WHY THIS EXISTS AS ITS OWN SYSTEM: almost every piece of Black Market content wants one. Leg
	Breaker stuns; .100mm shreds armour; SharkBullet bleeds; the IceThrower slows and frostbites;
	the PoisonThrower stacks poison; the Trailblazer's trail bleeds; Sticky grenades slow. Building
	each of those into its own mod or gun would mean seven half-implementations of the same idea
	that cannot interact — a bleed from a bullet and a bleed from a trail would be different things,
	stacking rules would drift, and nothing could ever ask "is this enemy stunned?"

	One system, applied by anything, ticked in one place, read by combat and AI.

	=== STACKING ===
	`MaxStacks` is the cap. Re-applying at cap does NOT extend duration by default — that is what
	`RefreshOnStack` is for. This matters for the PoisonThrower, which is explicitly designed so the
	status "can run off pretty quickly" if you stop applying it, so poison refreshes rather than
	being permanently maintainable by one early hit.

	=== DAMAGE ===
	`DamagePerStackPerTick` is a FLAT number, deliberately not a percentage of the applier's damage.
	A damage-over-time that scales off whatever weapon applied it makes a strong gun's bleed strictly
	better than a weak gun's bleed for the same status, which turns a status into a second damage
	stat instead of its own thing. Tune per status here.

	=== ADDING ONE ===
	An entry here plus, if it changes BEHAVIOUR rather than just dealing damage, a check wherever
	that behaviour lives (StatusEffects.IsStunned in EnemyAI, GetSpeedMultiplier for movement,
	GetDefenseMultiplier in the damage path). Pure damage-over-time statuses need nothing but an
	entry.
]]

local StatusConfig = {}

StatusConfig.Types = {
	----------------------------------------------------------------------
	-- Damage over time
	----------------------------------------------------------------------

	Bleed = {
		DisplayName = "Bleeding",
		MaxStacks = 3,
		Duration = 6,
		TickInterval = 1,
		DamagePerStackPerTick = 4,
		RefreshOnStack = true,
	},

	Poison = {
		DisplayName = "Poisoned",
		MaxStacks = 5,
		Duration = 8,
		TickInterval = 1,
		-- Rises faster than linearly with stacks so a fully-stacked PoisonThrower genuinely beats a
		-- regular flamethrower, which is the stated design goal — while a single stack stays weak,
		-- so the payoff is in maintaining it.
		DamagePerStackPerTick = 3,
		StackDamageBonus = 0.35, -- +35% per stack beyond the first, compounding the flat value
		RefreshOnStack = true,
	},

	Burn = {
		DisplayName = "Burning",
		MaxStacks = 1,
		Duration = 4,
		TickInterval = 0.5,
		DamagePerStackPerTick = 6,
		RefreshOnStack = true,
	},

	----------------------------------------------------------------------
	-- Control
	----------------------------------------------------------------------

	-- Cannot move or attack. EnemyAI checks this before doing either.
	Stun = {
		DisplayName = "Stunned",
		MaxStacks = 1,
		Duration = 5,
		RefreshOnStack = true,
		PreventsAction = true,
	},

	-- Movement only; a slowed enemy still attacks at its normal rate.
	Slow = {
		DisplayName = "Slowed",
		MaxStacks = 1,
		Duration = 3,
		RefreshOnStack = true,
		SpeedMultiplier = 0.5,
	},

	-- Two applications become a Stun — the IceThrower's whole gimmick. Handled generically here
	-- (EscalatesTo/EscalatesAtStacks) rather than as special-case code in the gun, so any future
	-- status can build to another one the same way.
	Frostbite = {
		DisplayName = "Frostbitten",
		MaxStacks = 2,
		Duration = 6,
		RefreshOnStack = true,
		SpeedMultiplier = 0.7,
		EscalatesAtStacks = 2,
		EscalatesTo = "Stun",
		EscalateDuration = 2,
	},

	----------------------------------------------------------------------
	-- Defensive debuffs
	----------------------------------------------------------------------

	-- Painted by a Recon drone. A DEBUFF ON THE TARGET rather than a bonus for whoever marked it,
	-- so a marked enemy takes more from your turrets, your robots and anyone else's guns too — which
	-- is what makes Recon the Core you run when something else is doing the damage, instead of a
	-- worse Combat Core. Short, and refreshed every drone tick, so it falls off as soon as the enemy
	-- leaves the drone's range.
	Marked = {
		DisplayName = "Marked",
		MaxStacks = 1,
		Duration = 4,
		RefreshOnStack = true,
		DefenseMultiplierPerStack = 0.75, -- a quarter off its armour; deliberately modest
	},

	-- Multiplicative, so two shredders stack sensibly instead of one overwriting the other, and a
	-- full strip is just a multiplier of 0. Replaces the earlier all-or-nothing DefenseStripped
	-- flag, which could not express .100mm's "loses 50% of their defense".
	ArmourShred = {
		DisplayName = "Armour Shredded",
		MaxStacks = 4,
		Duration = 8,
		RefreshOnStack = true,
		DefenseMultiplierPerStack = 0.5, -- each stack halves what's left
	},
}

function StatusConfig.Get(key: string)
	return StatusConfig.Types[key]
end

return StatusConfig
