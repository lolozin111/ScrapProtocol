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

-- Optional per-entry tags any Loot table below (or a Shop item's Grant in ShopCatalog further down)
-- MAY set: RunLocked, RunRoomService.settleRunLoot (RaidRoomService.lua) reads it when a Raid Room
-- run ends WITHOUT a clean Extract (Defeated or Abandoned) — a RunLocked drop is lost on that kind
-- of exit ("if they abandon it they lose such run items"), UNLESS Permanent is ALSO set on the same
-- entry, which carries it over regardless ("unless the item has a tag called permanent, where it
-- can be carried over"). Neither tag is set on anything below yet — every drop here currently
-- behaves exactly as it always has (always kept) until specific entries are tagged later. This only
-- applies to Raid Rooms; Expedition's older Combat Outposts read these same tables but don't have
-- any concept of a "run" to lock things to, so the tags are simply inert there. Scrap/Cores
-- currency loot is exempt from RunLocked entirely regardless of the tag — see RaidRoomService's own
-- comment on why currency is always kept.
NodeConfig.CombatTiers = {
	[1] = {
		Name = "Scrap Camp",
		EnemyHP = 120,
		DamagePerSecond = 3,
		CooldownSeconds = 45,
		Loot = {
			{ Kind = "Ore", OreKey = "IronOre", Min = 15, Max = 30, Chance = 1.0 },
			{ Kind = "Currency", CurrencyKey = "Scrap", Min = 5, Max = 15, Chance = 1.0 },
			{ Kind = "Ore", OreKey = "CopperOre", Min = 5, Max = 10, Chance = 0.4 },
		},
	},
	[2] = {
		Name = "Raider Camp",
		EnemyHP = 190,
		DamagePerSecond = 4,
		CooldownSeconds = 75,
		Loot = {
			{ Kind = "Ore", OreKey = "GoldOre", Min = 10, Max = 20, Chance = 1.0 },
			{ Kind = "Currency", CurrencyKey = "Scrap", Min = 15, Max = 30, Chance = 1.0 },
		},
	},
	[3] = {
		Name = "Warband Stronghold",
		EnemyHP = 480,
		DamagePerSecond = 8,
		CooldownSeconds = 120,
		Loot = {
			{ Kind = "Ore", OreKey = "PlatinumOre", Min = 5, Max = 12, Chance = 1.0 },
			{ Kind = "Currency", CurrencyKey = "Scrap", Min = 30, Max = 60, Chance = 1.0 },
		},
	},
}

----------------------------------------------------------------------
-- Boss loot (Raid Rooms only) — richer than a Tier-3 Combat room's own table, on top of the same
-- run-progression multiplier RaidRoomService already applies to every encounter's rewards
-- (RaidConfig.GetLootMultiplier). Placeholder amounts, same as the Boss/card system generally —
-- tune once real combat balance exists.
----------------------------------------------------------------------

NodeConfig.BossLoot = {
	{ Kind = "Ore", OreKey = "PlatinumOre", Min = 10, Max = 20, Chance = 1.0 },
	{ Kind = "Currency", CurrencyKey = "Scrap", Min = 50, Max = 90, Chance = 1.0 },
}

----------------------------------------------------------------------
-- Heal Station
----------------------------------------------------------------------

NodeConfig.HealCooldownSeconds = 20 -- free, but not spammable mid-raid

----------------------------------------------------------------------
-- Shop — the actual sink for the run's collected Scrap. Deliberately Scrap-only: Cores are no
-- longer collected room by room (see RaidConfig.ExtractionRewards), so a Cores price here would be
-- unbuyable until the first map clear, and Cores are meant to be a prize you carry home anyway.
----------------------------------------------------------------------

NodeConfig.ShopCatalog = {
	ScrapBundle = {
		DisplayName = "Iron Ore Bundle",
		CostCurrency = "Scrap", CostAmount = 40,
		Grant = { Kind = "Ore", OreKey = "IronOre", Amount = 25 },
	},
	CopperBundle = {
		DisplayName = "Copper Ore Bundle",
		CostCurrency = "Scrap", CostAmount = 60,
		Grant = { Kind = "Ore", OreKey = "CopperOre", Amount = 20 },
	},
	SteelBundle = {
		DisplayName = "Gold Ore Bundle",
		CostCurrency = "Scrap", CostAmount = 90,
		Grant = { Kind = "Ore", OreKey = "GoldOre", Amount = 15 },
	},
	InstantCraftToken = {
		DisplayName = "Instant Craft Token",
		CostCurrency = "Scrap", CostAmount = 50,
		Grant = { Kind = "Currency", CurrencyKey = "InstantCraftTokens", Amount = 1 },
	},
	GoldCache = {
		DisplayName = "Platinum Ore Cache",
		CostCurrency = "Scrap", CostAmount = 120,
		Grant = { Kind = "Ore", OreKey = "PlatinumOre", Amount = 8 },
	},
}

return NodeConfig
