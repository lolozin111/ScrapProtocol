--[[
	NodeConfig.lua
	Static data for the "Expedition" layer: Combat Outposts, the Shop, and the Heal Station —
	the strategic node types scattered around the open world, separate from home-base defense.

	This is what turns the map into a real decision: raid a harder outpost for better loot at
	the cost of more damage taken, or play it safe near a Heal Station; spend what you find at
	the Shop, or hoard it for crafting back at base.
]]

local NodeConfig = {}

----------------------------------------------------------------------
-- Combat Outposts
----------------------------------------------------------------------
-- Place a Combat node with a NumberValue child "Tier" matching one of these keys.
-- DamagePerSecond is chip damage taken by the player for every second an outpost's
-- enemy HP pool isn't yet cleared — weak gear means a slower fight means more damage,
-- which is the actual risk/reward lever. A raid that reaches 0 player HP fails: no loot.

NodeConfig.CombatTiers = {
	[1] = {
		Name = "Scrap Camp",
		EnemyHP = 120,
		DamagePerSecond = 3,
		CooldownSeconds = 45,
		Loot = {
			{ Kind = "Ore", OreKey = "ScrapIron", Min = 15, Max = 30, Chance = 1.0 },
			{ Kind = "Currency", CurrencyKey = "Scrap", Min = 5, Max = 15, Chance = 1.0 },
			{ Kind = "Ore", OreKey = "CopperWire", Min = 5, Max = 10, Chance = 0.4 },
		},
	},
	[2] = {
		Name = "Raider Camp",
		EnemyHP = 190,
		DamagePerSecond = 4,
		CooldownSeconds = 75,
		Loot = {
			{ Kind = "Ore", OreKey = "SteelPlating", Min = 10, Max = 20, Chance = 1.0 },
			{ Kind = "Currency", CurrencyKey = "Scrap", Min = 15, Max = 30, Chance = 1.0 },
			{ Kind = "Currency", CurrencyKey = "Cores", Min = 1, Max = 3, Chance = 0.5 },
		},
	},
	[3] = {
		Name = "Warband Stronghold",
		EnemyHP = 480,
		DamagePerSecond = 8,
		CooldownSeconds = 120,
		Loot = {
			{ Kind = "Ore", OreKey = "GoldContacts", Min = 5, Max = 12, Chance = 1.0 },
			{ Kind = "Currency", CurrencyKey = "Cores", Min = 3, Max = 8, Chance = 1.0 },
			{ Kind = "Currency", CurrencyKey = "Scrap", Min = 30, Max = 60, Chance = 1.0 },
		},
	},
}

----------------------------------------------------------------------
-- Heal Station
----------------------------------------------------------------------

NodeConfig.HealCooldownSeconds = 20 -- free, but not spammable mid-raid

----------------------------------------------------------------------
-- Shop — the actual sink for Scrap/Cores currency
----------------------------------------------------------------------

NodeConfig.ShopCatalog = {
	ScrapBundle = {
		DisplayName = "Scrap Iron Bundle",
		CostCurrency = "Scrap", CostAmount = 40,
		Grant = { Kind = "Ore", OreKey = "ScrapIron", Amount = 25 },
	},
	CopperBundle = {
		DisplayName = "Copper Wire Bundle",
		CostCurrency = "Scrap", CostAmount = 60,
		Grant = { Kind = "Ore", OreKey = "CopperWire", Amount = 20 },
	},
	SteelBundle = {
		DisplayName = "Steel Plating Bundle",
		CostCurrency = "Scrap", CostAmount = 90,
		Grant = { Kind = "Ore", OreKey = "SteelPlating", Amount = 15 },
	},
	InstantCraftToken = {
		DisplayName = "Instant Craft Token",
		CostCurrency = "Scrap", CostAmount = 50,
		Grant = { Kind = "Currency", CurrencyKey = "InstantCraftTokens", Amount = 1 },
	},
	GoldCache = {
		DisplayName = "Gold Contacts Cache",
		CostCurrency = "Cores", CostAmount = 10,
		Grant = { Kind = "Ore", OreKey = "GoldContacts", Amount = 8 },
	},
}

return NodeConfig
