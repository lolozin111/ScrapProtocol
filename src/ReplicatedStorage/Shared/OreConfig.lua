--[[
	OreConfig.lua
	Static data for every mineable ore tier. Matches "Mining" section of the design doc.

	Tune numbers here, not in MiningService — keep game logic and game balance separate
	so you (or an AI assistant) can rebalance the economy without touching code that can break.
]]

local OreConfig = {}

-- ToolTiers: swing speed (seconds between hits) and a flat yield multiplier.
-- Equip a tool by setting the player's ToolTier in their profile (see DataService).
OreConfig.ToolTiers = {
	{ Name = "Rusty Pickaxe",  SwingTime = 1.2, YieldMultiplier = 1.0 },
	{ Name = "Pneumatic Drill", SwingTime = 0.8, YieldMultiplier = 1.5 },
	{ Name = "Laser Cutter",   SwingTime = 0.5, YieldMultiplier = 2.25 },
	{ Name = "Plasma Drill",   SwingTime = 0.3, YieldMultiplier = 3.25 },
}

-- Ores: BaseYield is how much you get per hit at ToolTier 1 before the multiplier.
-- MinWaveUnlock gates the ore behind wave-defense progress (0 = available immediately).
OreConfig.Ores = {
	ScrapIron = {
		DisplayName = "Scrap Iron",
		BaseYield = 3,
		MinWaveUnlock = 0,
	},
	CopperWire = {
		DisplayName = "Copper Wire",
		BaseYield = 2,
		MinWaveUnlock = 0,
	},
	SteelPlating = {
		DisplayName = "Steel Plating",
		BaseYield = 1,
		MinWaveUnlock = 0,       -- physically minable early, but nodes require ToolTier >= 2 (see MiningService)
		MinToolTier = 2,
	},
	GoldContacts = {
		DisplayName = "Gold Contacts",
		BaseYield = 1,
		MinWaveUnlock = 5,       -- locked until the player has cleared wave 5 at least once
		MinToolTier = 3,
	},
	VoidiumShard = {
		DisplayName = "Voidium Shard",
		BaseYield = 1,
		MinWaveUnlock = 15,      -- post-MVP content; leave nodes out of the map until you ship this
		MinToolTier = 4,
	},
}

return OreConfig
