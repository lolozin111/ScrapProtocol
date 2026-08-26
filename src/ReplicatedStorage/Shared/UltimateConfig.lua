--[[
	UltimateConfig.lua
	Ultimate mods — Mythical-rarity passives that live in a weapon's own dedicated FOURTH slot.

	These are not bigger versions of ordinary mods. Every entry in ModConfig.Mods is a stat
	multiplier (FireRate / Damage / HP); an Ultimate is a BEHAVIOUR — corpses detonate, rounds
	ricochet, a shot strips armour. That difference is why they get their own config, their own
	slot, and their own effect-dispatch table rather than being bolted onto ModConfig.

	SLOT EXCLUSIVITY runs both ways: only an Ultimate can occupy the Ultimate slot, and an Ultimate
	can never occupy one of the three regular ModConfig slots. Enforced server-side in
	CraftingService (EquipUltimate / EquipMod), not just hidden in the UI.

	DESIGN INTENT (from the Black Market spec — see DESIGN_NOTES.md): a passive with no drawback, or
	with a drawback whose upside is genuinely worth it. They are meant to feel game-changing rather
	than incremental, which is also why they are mid-to-endgame content gated behind Black Market
	cases rather than craftable.

	=== ADDING CONTENT ===
	The six below are real, specced content — not placeholders. Adding another is:

	  1. an entry here — DisplayName / Description / Effect / Params
	  2. IF it needs behaviour no existing effect covers, one function in
	     UltimateEffects.lua under the hook it fires on

	`Effect` is a NAME looked up in UltimateEffects.OnHit / .OnKill — the same flat-table-of-named-
	strategies pattern EnemyAI.Patterns and RobotBehaviors already use. `Trigger` records which hook
	it lives on (documentation for whoever is reading the config; the dispatch uses the table it is
	actually in). `Params` is handed to the effect untouched, so tuning never means editing code.

	"Every Nth shot" passives count through CombatEncounterService's per-encounter shot counter —
	see EveryNthShot in the Params below. The counter is per encounter, not per life, so leaving a
	wave and coming back does not bank progress toward a free proc.

	If a future passive needs a hook that does not exist yet (on-reload, on-crit, on-wave-start),
	that is a new hook point in CombatEncounterService plus a new table here — deliberately the only
	kind of change that should ever require touching the combat engine again.
]]

local UltimateConfig = {}

-- Which slot index the Ultimate occupies. Deliberately ModConfig.SlotsPerItem + 1 so the UI can lay
-- it out as "the fourth slot" — but it is stored in its own profile field
-- (profile.EquippedUltimate), NOT in EquippedMods, so a regular mod can never land in it by an
-- off-by-one and an Ultimate can never be read as a regular mod by CombatMath.
UltimateConfig.SlotLabel = "ULTIMATE"

-- Every Ultimate is Mythical. Kept as a field rather than assumed so the rarity badge/colour
-- lookup goes through ModConfig.Rarities like everything else.
UltimateConfig.Rarity = "Mythical"

UltimateConfig.Mods = {
	Detonator = {
		DisplayName = "Detonator",
		Description = "Enemies you kill explode, damaging everything nearby. Made for clearing waves.",
		Effect = "Detonator",
		Trigger = "OnKill",
		Params = {
			Radius = 18,          -- "15-20 magnitude"
			DamageFraction = 0.6, -- of the killing blow, to each enemy caught
		},
	},

	Ricochet = {
		DisplayName = "Ricochet",
		Description = "Every 3rd shot bounces between nearby enemies, hitting harder with each bounce.",
		Effect = "Ricochet",
		Trigger = "OnHit",
		Params = {
			EveryNthShot = 3,
			MaxBounces = 5,
			Radius = 26,             -- how far it will look for the next body
			FirstBounceFraction = 0.5, -- of the original hit
			DamageGrowth = 0.35,     -- each bounce hits 35% harder than the last
		},
	},

	LegBreaker = {
		DisplayName = "Leg Breaker",
		Description = "Every 5th shot stuns an enemy for 5 seconds and drops their defenses to nothing.",
		Effect = "LegBreaker",
		Trigger = "OnHit",
		Params = {
			EveryNthShot = 5,
			StunSeconds = 5,
			-- ArmourShred stacked to its cap, which multiplies defence down to ~6% — near enough to
			-- "drops to 0" while still going through the same status system as every other debuff
			-- rather than being a special case.
			ShredStacks = 4,
		},
	},

	HundredMil = {
		DisplayName = ".100mm",
		Description = "Rounds punch through up to 7 enemies, tearing half the armour off each one.",
		Effect = "PierceShred",
		Trigger = "OnHit",
		Params = {
			MaxTargets = 7,
			Radius = 22,
			DamageFraction = 0.8, -- pierced targets take slightly less than the direct hit
			ShredStacks = 1,      -- one stack = "loses 50% of their defense"
		},
	},

	SharkBullet = {
		DisplayName = "Shark Bullet",
		Description = "Hit the same enemy 5 times and they start bleeding. Stacks up to 3 times.",
		Effect = "SharkBullet",
		Trigger = "OnHit",
		Params = {
			HitsPerStack = 5,
			MaxStacks = 3,
		},
	},

	AimBot = {
		DisplayName = "AimBot",
		Description = "Every 3rd bullet finds a head. (Testing: instantly kills.)",
		Effect = "AimBot",
		Trigger = "OnHit",
		Params = {
			EveryNthShot = 3,
			HeadshotMultiplier = 1.5,
			-- TEMPORARY, by request: outright kill rather than a damage bonus, so it is obvious the
			-- passive is firing. Flip to false for the intended 1.5x headshot.
			Instakill = true,
		},
	},
}

-- Sorted list of keys, for any UI that needs a stable order (a pairs() walk reshuffles between
-- renders, which reads as a flicker in a list that refreshes as often as the inventory does).
function UltimateConfig.SortedKeys(): { string }
	local keys = {}
	for key in pairs(UltimateConfig.Mods) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

return UltimateConfig
