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
	[2] = { Scrap = 200, IronOre = 15 },
	[3] = { Scrap = 450, IronOre = 40, CopperOre = 25 },
	[4] = { Scrap = 900, GoldOre = 40, PlatinumOre = 20, SteelIngot = 10 }, -- refined: see RefinedOreConfig
}

-- Ores: BaseYield is how much you get per hit at ToolTier 1 before the multiplier.
-- MinWaveUnlock gates the ore behind wave-defense progress (0 = available immediately).
-- MaxHits/RespawnSeconds control node depletion (see MiningService/ResourceZoneService): a node
-- survives this many successful mines before going empty, then comes back after this many
-- seconds. Common ore takes more hits and comes back faster; rarer ore is the opposite, so
-- scarcity actually means something the further out you go.
--
-- SellPrice is Scrap paid per unit when selling to the Shop (NodeConfig.ShopCatalog does the
-- buying side) — anchored below what the Shop charges to buy the same ore back, so selling and
-- immediately rebuying is always a loss.
OreConfig.Ores = {
	IronOre = {
		DisplayName = "Iron Ore",
		Description = "Common iron ore, streaked through almost every wall down here. The backbone of everything you'll build.",
		BaseYield = 3,
		MinWaveUnlock = 0,
		MaxHits = 8,
		RespawnSeconds = 15,
		SellPrice = 1,
	},
	CopperOre = {
		DisplayName = "Copper Ore",
		Description = "Green-veined copper ore. Smelts down into the conductor behind anything electrical.",
		BaseYield = 2,
		MinWaveUnlock = 0,
		MaxHits = 7,
		RespawnSeconds = 20,
		SellPrice = 2,
	},
	-- Gold and Platinum trade gate slots in this rework so the value ladder reads
	-- Iron -> Copper -> Gold -> Platinum -> Voidium: GoldOre keeps the mining stats that used to
	-- belong to the key "SteelPlating" (the stats stay with the SLOT, not the metal), and
	-- PlatinumOre keeps the stats that used to belong to "GoldContacts" below.
	GoldOre = {
		DisplayName = "Gold Ore",
		Description = "Soft yellow ore in thin seams. Worth more to a buyer than to a builder.",
		BaseYield = 1,
		MinWaveUnlock = 0,       -- physically minable early, but nodes require ToolTier >= 2 (see MiningService)
		MinToolTier = 2,
		MaxHits = 5,
		RespawnSeconds = 35,
		SellPrice = 5,
	},
	PlatinumOre = {
		DisplayName = "Platinum Ore",
		Description = "A dense, pale ore that dulls a blade fast. Rare enough that most crews never see a seam.",
		BaseYield = 1,
		MinWaveUnlock = 5,       -- locked until the player has cleared wave 5 at least once
		MinToolTier = 3,
		MaxHits = 3,
		RespawnSeconds = 60,
		SellPrice = 9,
	},
	VoidiumShard = {
		DisplayName = "Voidium Shard",
		Description = "A shard of something that isn't from around here. Handle carefully.",
		BaseYield = 1,
		MinWaveUnlock = 15,      -- post-MVP content; leave nodes out of the map until you ship this
		MinToolTier = 4,
		MaxHits = 2,
		RespawnSeconds = 120,
		SellPrice = 20,
	},
}

return OreConfig
