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
	Everything below is a PLACEHOLDER pending the real table of contents. Adding a real one is:

	  1. an entry here — DisplayName / Description / Effect / Params
	  2. IF it needs behaviour no existing effect covers, one function in
	     UltimateEffects.lua under the hook it fires on

	`Effect` is a NAME looked up in UltimateEffects.OnHit / .OnKill — the same flat-table-of-named-
	strategies pattern EnemyAI.Patterns and RobotBehaviors already use. `Params` is handed to that
	function untouched, so tuning a passive never means editing code.

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
	----------------------------------------------------------------------
	-- PLACEHOLDERS. Real numbers, real behaviour, deliberately conservative tuning — these exist
	-- to prove the hooks fire end to end, not to be balanced content. Replace freely.
	----------------------------------------------------------------------

	Detonator = {
		DisplayName = "Detonator Core",
		Description = "Enemies you kill detonate, dealing area damage to everything near the corpse.",
		Effect = "CorpseDetonation",
		Params = {
			Radius = 18,           -- studs
			DamageFraction = 0.6,  -- of the killing blow's damage, dealt to each nearby enemy
		},
	},

	Ricochet = {
		DisplayName = "Ricochet Chip",
		Description = "Your shots bounce to a nearby enemy for reduced damage.",
		Effect = "Ricochet",
		Params = {
			Radius = 24,
			Bounces = 1,
			DamageFraction = 0.5,
		},
	},

	Breacher = {
		DisplayName = "Breacher Round",
		Description = "Shots punch through several enemies and strip their armour completely for a short time.",
		Effect = "PierceAndStrip",
		Params = {
			Radius = 20,
			MaxTargets = 5,
			DamageFraction = 0.75,
			StripSeconds = 10, -- Defense treated as 0 for this long — see DamagePipeline
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
