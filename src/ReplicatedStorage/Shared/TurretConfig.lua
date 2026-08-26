--[[
	TurretConfig.lua
	Pure data + formulas for the dedicated Turret system (Base Defense & Turrets, round 2). This
	SUPERSEDES last round's "every deployed Robot gets a physical body" approach — turrets are now
	their own first-class thing, bought as blueprints at the Hub's rotating Shop station, placed
	into a limited number of base slots, and leveled up individually. CraftingRecipes.Robots/
	DeployedRobots/RobotBehaviorConfig are UNTOUCHED and still exist — they're still real, still
	used for raid combat support (RunRaidCombat) — they just no longer double as "the turret system."

	Turrets deliberately have NO mod slots (per direct instruction) — variety comes entirely from
	which Type you place (distinct Range/FireRate/BaseDamage/AOE per type below) plus how far
	you've leveled each individual placed instance, not from equippable modifiers.

	Studio setup: same "functional before art" convention as everywhere else — build a Model per
	Types key in ServerStorage.TurretModels (TurretService.lua), floor at local Y=0, PrimaryPart
	set, and ideally a child Attachment named "Muzzle" for the fire-particle effect to spawn from
	(falls back to the model's own PrimaryPart position if missing). No Model yet? TurretService
	builds a small placeholder pedestal instead, same as before.
]]

local TurretConfig = {}

----------------------------------------------------------------------
-- Types — no mods, so all the variety lives right here. Numbers are first-guess base stats (before
-- any Level/Tier scaling, see GetTurretEffectiveStats below) — worth a playtest before treating as
-- final, same as every other numbers-first-pass in this project.
--
-- ECONOMY (reworked — a turret is EARNED, not bought outright):
--   BlueprintCost  Scrap, paid once at the Hub Shop. Unlocks the RECIPE permanently
--                  (profile.UnlockedTurretBlueprints) — it does not hand you a turret.
--   CraftCost      Scrap + raw ore, paid at the Welding Station for EACH turret you build.
--                  This is the real gate: you have to go mine for it. The upper half of the
--                  roster also wants REFINED materials (RefinedOreConfig — Steel Ingot, Copper
--                  Coil, Hardened Plate, Gold Bar, Voidium Core), which means smelting the ore
--                  first. That is what makes the Forge's Smelting tab worth using: refined
--                  materials are the "you did the extra processing step" tier of input, and they
--                  gate the good turrets rather than being an alternative to raw ore.
--   Upgrades       Cores (see UpgradeCurrency below), which is what keeps Cores — a boss-wave-only
--                  drop — meaningfully scarce rather than just another pile of numbers.
--
-- Scrap is the game's main currency by design: raids and loot pay it out, and almost everything
-- worth building spends it. Ore comes from mining. Cores come from clearing wave milestones. Each
-- of the three activities feeds a different part of the same build, so no one of them can be
-- skipped by grinding another harder.
--
-- These numbers are deliberate placeholders pending a real playtest — drop rates per gamemode
-- aren't settled yet, so treat the RATIOS (blueprint ≈ 2x a craft, craft climbs steeply by tier)
-- as the intent and the absolute values as provisional.
----------------------------------------------------------------------

TurretConfig.Types = {
	PulseTurret = {
		DisplayName = "Pulse Turret",
		Description = "Cheap and quick — rapid, light hits, short range. Good against thin swarms.",
		BlueprintCost = { Scrap = 250 },
		CraftCost = { Scrap = 120, ScrapIron = 40, CopperWire = 15 },
		Range = 40, FireRate = 3.0, BaseDamage = 4, AOE = 1, -- AOE = how many nearest-in-range
			-- targets it hits per shot; 1 = single-target.
		ParticleColor = Color3.fromRGB(120, 200, 255),
	},
	FlakTurret = {
		DisplayName = "Flak Turret",
		Description = "Wide burst radius, hits several enemies at once — thin the crowd, not the boss.",
		BlueprintCost = { Scrap = 450 },
		CraftCost = { Scrap = 200, ScrapIron = 60, CopperWire = 30 },
		Range = 38, FireRate = 1.1, BaseDamage = 7, AOE = 3,
		ParticleColor = Color3.fromRGB(255, 170, 90),
	},
	SniperTurret = {
		DisplayName = "Sniper Turret",
		Description = "Long range, heavy single-target damage, slow to fire.",
		BlueprintCost = { Scrap = 700 },
		CraftCost = { Scrap = 320, SteelPlating = 35, CopperWire = 40, SteelIngot = 10 },
		Range = 75, FireRate = 0.55, BaseDamage = 24, AOE = 1,
		ParticleColor = Color3.fromRGB(255, 80, 80),
	},
	ArcTurret = {
		DisplayName = "Arc Turret",
		Description = "Crackling mid-range arc that jumps between nearby enemies.",
		BlueprintCost = { Scrap = 850 },
		CraftCost = { Scrap = 400, SteelPlating = 45, SteelIngot = 15, CopperCoil = 10 },
		Range = 48, FireRate = 1.6, BaseDamage = 9, AOE = 4,
		ParticleColor = Color3.fromRGB(150, 220, 255),
	},
	MortarTurret = {
		DisplayName = "Mortar Turret",
		Description = "Very long range, huge splash, very slow — set up far back and let it work.",
		BlueprintCost = { Scrap = 1100 },
		CraftCost = { Scrap = 520, GoldContacts = 20, HardenedPlate = 12 },
		Range = 95, FireRate = 0.35, BaseDamage = 30, AOE = 5,
		ParticleColor = Color3.fromRGB(200, 140, 60),
	},
	RailTurret = {
		DisplayName = "Rail Turret",
		Description = "Punishing single-target damage at real range — the premium sniper.",
		BlueprintCost = { Scrap = 1400 },
		CraftCost = { Scrap = 650, GoldContacts = 35, GoldBar = 8, VoidiumCore = 2 },
		Range = 65, FireRate = 0.8, BaseDamage = 34, AOE = 1,
		ParticleColor = Color3.fromRGB(180, 255, 200),
	},
}

----------------------------------------------------------------------
-- Rotating Hub Shop stock — a PURE function of wall-clock time, deliberately not backed by any
-- persisted state: both client (to display "today's stock") and server (to validate a purchase)
-- call this independently and always agree, as long as they're within the same rotation window.
-- Uses a small self-contained deterministic hash (seededRandom) instead of math.random/
-- math.randomseed on purpose — reseeding the GLOBAL random generator here would be a side effect
-- that perturbs every OTHER system's randomness (enemy spawns, loot rolls, etc.) the moment the
-- shop's stock is merely looked up, which is exactly the kind of spooky-action-at-a-distance bug
-- worth avoiding by construction.
----------------------------------------------------------------------

TurretConfig.ShopRotationPeriodSeconds = 6 * 3600 -- new stock every 6 hours, same for every player
TurretConfig.ShopStockSize = 3 -- how many of the Types above are purchasable at once

-- Deterministic pseudo-random in [0, 1) from a single number seed — classic GLSL-style sine hash.
-- Not cryptographic, doesn't need to be; just needs to be stable and cheap.
local function seededRandom(seed: number): number
	local x = math.sin(seed) * 43758.5453
	return x - math.floor(x)
end

function TurretConfig.GetRotatingStock(now: number): { string }
	local period = math.floor(now / TurretConfig.ShopRotationPeriodSeconds)

	local keys = {}
	for key in pairs(TurretConfig.Types) do
		table.insert(keys, key)
	end
	table.sort(keys) -- pairs() order isn't guaranteed stable — sort first so the shuffle below
		-- starts from the same order every time, on both client and server.

	-- Fisher-Yates, seeded off `period` (and each index, so every swap draws a different value)
	-- rather than a single seed reused across the whole shuffle.
	for i = #keys, 2, -1 do
		local r = seededRandom(period * 97 + i)
		local j = math.floor(r * i) + 1
		keys[i], keys[j] = keys[j], keys[i]
	end

	local stock = {}
	for i = 1, math.min(TurretConfig.ShopStockSize, #keys) do
		table.insert(stock, keys[i])
	end
	return stock
end

----------------------------------------------------------------------
-- Slots — how many base-defense turret slots a player has, purely a function of ResearchTier
-- (profile.ResearchTier — currently a skeleton field always 1, see DataService.lua, until the real
-- Research phase ships). Player's own words: "for research T1, it will be only 2, and then every
-- odd numbered tier increases the slot by 1, every even increases by 2."
----------------------------------------------------------------------

function TurretConfig.GetSlotCount(researchTier: number?): number
	local tier = math.max(researchTier or 1, 1)
	local slots = 2 -- Tier 1 baseline
	for t = 2, tier do
		slots += (t % 2 == 0) and 2 or 1
	end
	return slots
end

----------------------------------------------------------------------
-- Leveling — every placed Turret instance (profile.Turrets, see DataService.lua) levels up
-- independently. Every 10 levels bumps its Tier; crossing into a new Tier additionally requires
-- profile.ResearchTier to have caught up (skeleton gate — always fails past Tier 1 until Research
-- ships, by design, per direct instruction: "just have some skeleton... until we have the real
-- deal"). Numbers below are a first guess worth a playtest, same as everything else in this file.
----------------------------------------------------------------------

-- How close you have to stand to click a turret slot (empty pad or placed turret) to open its
-- panel. Turrets are placed and managed by clicking them in the world rather than through a menu
-- — see TurretService.makeSlotInteractive. Roomier than StationConfig.InteractDistance (12) on
-- purpose: the slot ring sits out toward the edge of the plot, so demanding you stand right on
-- top of a pad would mean awkward shuffling between slots.
TurretConfig.SlotInteractDistance = 24

TurretConfig.LevelsPerTier = 10

function TurretConfig.GetTurretTier(level: number): number
	return math.floor((math.max(level, 1) - 1) / TurretConfig.LevelsPerTier) + 1
end

TurretConfig.UpgradeCurrency = "Cores"
TurretConfig.UpgradeBaseCost = 20
TurretConfig.UpgradeGrowthRate = 1.2 -- +20% cost per level — "grind a little to max it out"

-- Cost to go from `level` to `level + 1`.
function TurretConfig.GetTurretUpgradeCost(level: number): number
	return math.floor(TurretConfig.UpgradeBaseCost * (TurretConfig.UpgradeGrowthRate ^ (math.max(level, 1) - 1)))
end

TurretConfig.DamageGrowthPerLevel = 0.08 -- +8% Damage per level
TurretConfig.RangeGrowthPerLevel = 0.02  -- +2% Range per level — deliberately mild, range creep
	-- getting out of hand would make the slot/placement decision matter less over time.
TurretConfig.FireRateGrowthPerLevel = 0.02
TurretConfig.TierDamageBonus = 0.15 -- extra flat +15% Damage on top, per Tier past the first —
	-- makes crossing into a new Tier (and the ResearchTier gate that guards it) feel like a real
	-- breakthrough, not just "10 more levels of the same slope."

-- Fully resolved stats for one turret instance at its current Level — what CombatEncounterService
-- actually fires with. AOE is a pure type trait (how many nearest-in-range targets one shot hits),
-- not affected by Level/Tier — only how HARD and how FAR/OFTEN it hits scales.
function TurretConfig.GetTurretEffectiveStats(typeKey: string, level: number)
	local typeData = TurretConfig.Types[typeKey]
	if not typeData then
		return nil
	end

	level = math.max(level, 1)
	local tier = TurretConfig.GetTurretTier(level)
	local tierBonus = 1 + (tier - 1) * TurretConfig.TierDamageBonus
	local levelGrowth = 1 + (level - 1) * TurretConfig.DamageGrowthPerLevel

	return {
		Range = typeData.Range * (1 + (level - 1) * TurretConfig.RangeGrowthPerLevel),
		FireRate = typeData.FireRate * (1 + (level - 1) * TurretConfig.FireRateGrowthPerLevel),
		Damage = typeData.BaseDamage * tierBonus * levelGrowth,
		AOE = typeData.AOE,
		Tier = tier,
	}
end

return TurretConfig
