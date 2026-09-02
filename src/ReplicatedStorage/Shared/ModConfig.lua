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

	Rarity: every mod below is still Common — mods themselves stay flat-craftable for now. This
	table is shared with ForgeConfig.lua's weapon-rolling system, though, which is what actually
	activates the non-Common tiers: a weapon Forged with Rarity="Rare" looks up ModConfig
	.Rarities.Rare for its DisplayName/Badge/Color. Mods could start dropping by rarity too later
	(rarer mods = stronger tradeoffs, gated behind a loot table instead of flat crafting) — nothing
	below stops that, it just isn't built yet.
]]

local ModConfig = {}

ModConfig.SlotsPerItem = 3

-- Badge is a 1-letter tag for tight UI spaces (inventory tile corners) where the full DisplayName
-- doesn't fit. Color is unused by mods themselves right now (every mod is Common) but is what the
-- Forge's weapon rows/tiles use to convey a roll's rarity at a glance.
ModConfig.Rarities = {
	Common = { DisplayName = "Common", Badge = "C", Color = Color3.fromRGB(180, 180, 180) },
	Uncommon = { DisplayName = "Uncommon", Badge = "U", Color = Color3.fromRGB(110, 190, 110) },
	Rare = { DisplayName = "Rare", Badge = "R", Color = Color3.fromRGB(90, 150, 220) },
	Epic = { DisplayName = "Epic", Badge = "E", Color = Color3.fromRGB(170, 100, 220) },
	Legendary = { DisplayName = "Legendary", Badge = "L", Color = Color3.fromRGB(230, 175, 60) },
	-- Mythical is Ultimate-mod-only (see UltimateConfig.lua). No ordinary mod or Forged weapon
	-- ever rolls it — ForgeConfig.RarityOrder deliberately stops at Legendary — so its presence
	-- here is purely so the badge/colour lookup works for the Ultimate slot like everything else.
	Mythical = { DisplayName = "Mythical", Badge = "M", Color = Color3.fromRGB(235, 90, 200) },
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

-- Multiplies a base FireRate/BaseDamage/HP triple by whatever mods currently sit in
-- profile.EquippedMods[itemKey] (a {[slotIndex] = modKey} table, may be nil or sparse). A mod that
-- doesn't touch a given stat simply has no multiplier field for it — treated as 1x/no-op here
-- rather than needing special-casing per mod. `hp` may be nil (weapons have none); it stays nil.
--
-- WHY THIS LIVES IN THE CONFIG rather than in CombatMath.lua, where it used to be the only copy:
-- CombatMath is a ServerScriptService module, so the HUD physically cannot require it. The Welding
-- Station's rig diagram shows the player their robot's mod-adjusted damage/HP, and the ONLY ways to
-- get that number client-side are a second implementation of this loop or a round trip. A second
-- implementation is the thing that drifts — the same reasoning that put cost resolution in
-- Shared/Wallet.lua so the HUD can't disagree with what the server will charge. CombatMath's
-- applyMods now delegates here, so there is still exactly one copy of the math.
function ModConfig.ApplyMods(fireRate: number, baseDamage: number, hp: number?, itemKey: string, profile): (number, number, number?)
	local equipped = profile.EquippedMods and profile.EquippedMods[itemKey]
	if not equipped then
		return fireRate, baseDamage, hp
	end
	for _, modKey in pairs(equipped) do
		local mod = modKey and ModConfig.Mods[modKey]
		if mod then
			if mod.FireRateMultiplier then
				fireRate *= mod.FireRateMultiplier
			end
			if mod.DamageMultiplier then
				baseDamage *= mod.DamageMultiplier
			end
			if hp and mod.HPMultiplier then
				hp *= mod.HPMultiplier
			end
		end
	end
	return fireRate, baseDamage, hp
end

return ModConfig
