--[[
	OreConfig.lua
	Static data for every mineable ore tier. Matches "Mining" section of the design doc.

	Tune numbers here, not in MiningService — keep game logic and game balance separate
	so you (or an AI assistant) can rebalance the economy without touching code that can break.
]]

local OreConfig = {}

-- ToolTiers: swing speed (seconds between hits) and a flat yield multiplier.
-- SwingTime is enforced SERVER-SIDE as a real cooldown on both mining remotes (MiningService's
-- MineNode and MineShaftService's MineShaftHit, via RateLimiter) — it is the anti-spam gate, not
-- just a display number, so lowering it genuinely raises how fast a player can mine.
-- Every player starts at tier 1 (DataService's defaultProfile). Tiers 2+ are purchased via the
-- Workbench's "Tools" tab (MiningService.UpgradeTool), costed by ToolTierCosts below — this is
-- the ONLY way ToolTier ever goes up, so an ore with a MinToolTier > 1 (see below) is
-- unreachable until the player upgrades that many times.
OreConfig.ToolTiers = {
	{ Name = "Rusty Pickaxe",  SwingTime = 1.2, YieldMultiplier = 1.0 },
	{ Name = "Pneumatic Drill", SwingTime = 0.8, YieldMultiplier = 1.5 },
	{ Name = "Laser Cutter",   SwingTime = 0.5, YieldMultiplier = 2.25 },
	{ Name = "Plasma Drill",   SwingTime = 0.3, YieldMultiplier = 3.25 },
}

-- Cost to upgrade INTO this tier from the one before it (tier 1 is the free starting tool, so
-- there's no entry for it). Tune freely — these just need to feel like a fair use of the ore
-- you'd have gathered by the time you're bumping into that tier's MinToolTier gate.
OreConfig.ToolTierCosts = {
	[2] = { ScrapIron = 50, CopperWire = 20 },
	[3] = { CopperWire = 45, SteelPlating = 35 },
	[4] = { SteelPlating = 60, GoldContacts = 20, SteelIngot = 12 }, -- refined: see RefinedOreConfig
}

-- Ores: BaseYield is how much you get per hit at ToolTier 1 before the multiplier.
-- MinWaveUnlock gates the ore behind wave-defense progress (0 = available immediately).
-- MaxHits/RespawnSeconds control node depletion (see MiningService/ResourceZoneService): a node
-- survives this many successful mines before going empty, then comes back after this many
-- seconds. Common ore takes more hits and comes back faster; rarer ore is the opposite, so
-- scarcity actually means something the further out you go.
OreConfig.Ores = {
	ScrapIron = {
		DisplayName = "Scrap Iron",
		Description = "Common scrap metal — the backbone of almost everything you'll build.",
		BaseYield = 3,
		MinWaveUnlock = 0,
		MaxHits = 8,
		RespawnSeconds = 15,
	},
	CopperWire = {
		DisplayName = "Copper Wire",
		Description = "Salvaged wiring, stripped and coiled. Essential for anything electronic.",
		BaseYield = 2,
		MinWaveUnlock = 0,
		MaxHits = 7,
		RespawnSeconds = 20,
	},
	SteelPlating = {
		DisplayName = "Steel Plating",
		Description = "Heavier armor plate — harder to cut loose, but worth the extra swing.",
		BaseYield = 1,
		MinWaveUnlock = 0,       -- physically minable early, but nodes require ToolTier >= 2 (see MiningService)
		MinToolTier = 2,
		MaxHits = 5,
		RespawnSeconds = 35,
	},
	GoldContacts = {
		DisplayName = "Gold Contacts",
		Description = "Corroded gold-plated contacts pulled from old circuit boards. Rare and valuable.",
		BaseYield = 1,
		MinWaveUnlock = 5,       -- locked until the player has cleared wave 5 at least once
		MinToolTier = 3,
		MaxHits = 3,
		RespawnSeconds = 60,
	},
	VoidiumShard = {
		DisplayName = "Voidium Shard",
		Description = "A shard of something that isn't from around here. Handle carefully.",
		BaseYield = 1,
		MinWaveUnlock = 15,      -- post-MVP content; leave nodes out of the map until you ship this
		MinToolTier = 4,
		MaxHits = 2,
		RespawnSeconds = 120,
	},
}

return OreConfig
