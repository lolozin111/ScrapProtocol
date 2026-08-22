--[[
	ModConfig.lua
	Pure data for the weapon/robot mod-slot system — "Base" bundle sub-feature #1 (see
	DESIGN_NOTES.md's "## Base" section). Each weapon and each robot TYPE has
	ModConfig.SlotsPerItem slots (3), and each slot holds one unlockable mod that multiplies
	FireRate / Damage / HP on that item.

	Key design decision: mods apply per item TYPE, not per individual robot instance.
	CraftedRobots is a plain count ([robotKey] = ownedCount), not a list of unique robot IDs, and
	DeployedRobots is just a repeatable list of robotKeys — there's no per-instance identity
	anywhere in this codebase to hang a per-instance loadout off of. So equipping a mod on
	"Scrapbot" affects every deployed Scrapbot at once. This is a deliberate simplification (see
	DESIGN_NOTES.md: "no new subsystem required") — building real per-instance robot identity would
	be a much bigger lift for a payoff the game doesn't need yet.

	Multiplier fields are all OPTIONAL — a mod that doesn't touch a stat just omits that field, and
	CombatMath.lua treats a missing multiplier as 1x/no-op. HP-affecting mods are simply inert when
	equipped on a weapon (weapons have no HP field to multiply) — no special-casing needed, the
	multiply-if-present logic in CombatMath just skips it.

	Rarity: every mod below is Common for now — ModConfig.Rarities exists as the structure to hang
	a real rarity-weighted-drop system off of later (rarer mods = stronger tradeoffs, gated behind
	a loot table instead of flat crafting), but with only one tier populated it's currently just a
	display label the HUD's mod picker shows next to each mod's name. Add more tiers to
	ModConfig.Rarities and set individual mods' Rarity field once that system actually exists.
]]

local ModConfig = {}

ModConfig.SlotsPerItem = 3

ModConfig.Rarities = {
	Common = { DisplayName = "Common", Color = Color3.fromRGB(180, 180, 180) },
	-- Rare / Epic / Legendary, etc. — add tiers here once mods drop via a weighted loot table
	-- instead of being flat-craftable from the start. Every mod below is Common until then.
}

ModConfig.Mods = {
	SpeedCoil = {
		DisplayName = "Speed Coil",
		Description = "+25% fire rate, -15% damage",
		Rarity = "Common",
		Cost = { CopperWire = 20 },
		FireRateMultiplier = 1.25,
		DamageMultiplier = 0.85,
	},
	HeavyRounds = {
		DisplayName = "Heavy Rounds",
		Description = "-20% fire rate, +35% damage",
		Rarity = "Common",
		Cost = { ScrapIron = 30 },
		FireRateMultiplier = 0.8,
		DamageMultiplier = 1.35,
	},
	Stabilizer = {
		DisplayName = "Stabilizer",
		Description = "+10% fire rate",
		Rarity = "Common",
		Cost = { ScrapIron = 20, CopperWire = 10 },
		FireRateMultiplier = 1.1,
	},
	ScavengedCapacitor = {
		DisplayName = "Scavenged Capacitor",
		Description = "+15% damage",
		Rarity = "Common",
		Cost = { ScrapIron = 15 },
		DamageMultiplier = 1.15,
	},
	ReinforcedPlating = {
		DisplayName = "Reinforced Plating",
		Description = "+40% HP, -10% fire rate (HP bonus only matters on robots)",
		Rarity = "Common",
		Cost = { SteelPlating = 25 },
		HPMultiplier = 1.4,
		FireRateMultiplier = 0.9,
	},
	OverclockedCore = {
		DisplayName = "Overclocked Core",
		Description = "+40% fire rate, -30% damage, -15% HP (HP penalty only matters on robots)",
		Rarity = "Common",
		Cost = { GoldContacts = 15, SteelPlating = 20 },
		FireRateMultiplier = 1.4,
		DamageMultiplier = 0.7,
		HPMultiplier = 0.85,
	},
}

return ModConfig
