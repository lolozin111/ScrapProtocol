--[[
	ShopConfig.lua
	Game pass and developer product IDs + effects. Matches "Monetization" section of the
	design doc.

	IMPORTANT: the Id values below are placeholders (0). Create the real Game Passes and
	Developer Products for this experience in the Creator Dashboard, then paste their
	numeric IDs in here — ShopService reads this table to know what to grant.
]]

local ShopConfig = {}

ShopConfig.GamePasses = {
	AutoMiner = {
		Id = 0, -- TODO: paste real Game Pass id
		DisplayName = "Auto-Miner",
		PriceRobux = 349,
	},
	DoubleScrap = {
		Id = 0, -- TODO
		DisplayName = "2x Scrap Rate",
		PriceRobux = 299,
	},
	ExtraRobotSlot = {
		Id = 0, -- TODO
		DisplayName = "Extra Robot Slot",
		PriceRobux = 249,
	},
	VipVault = {
		Id = 0, -- TODO
		DisplayName = "VIP Vault",
		PriceRobux = 449,
	},
}

-- DeveloperProducts: Grant.Currency + Grant.Amount tells ShopService what to add
-- when ProcessReceipt fires. "InstantCraft" and "WaveRevive" are flags handled
-- specially in ShopService/WaveService rather than a currency grant.
ShopConfig.DeveloperProducts = {
	ScrapPackSmall = { Id = 0, DisplayName = "Scrap Pack (S)", PriceRobux = 49,  Grant = { Currency = "Scrap", Amount = 500 } },
	ScrapPackMed   = { Id = 0, DisplayName = "Scrap Pack (M)", PriceRobux = 149, Grant = { Currency = "Scrap", Amount = 1800 } },
	ScrapPackLarge = { Id = 0, DisplayName = "Scrap Pack (L)", PriceRobux = 399, Grant = { Currency = "Scrap", Amount = 6000 } },
	CorePackSmall  = { Id = 0, DisplayName = "Core Pack (S)",  PriceRobux = 99,  Grant = { Currency = "Cores", Amount = 25 } },
	CorePackMed    = { Id = 0, DisplayName = "Core Pack (M)",  PriceRobux = 249, Grant = { Currency = "Cores", Amount = 75 } },
	InstantCraft   = { Id = 0, DisplayName = "Instant Craft Token", PriceRobux = 39, Grant = { Currency = "InstantCraftTokens", Amount = 1 } },
	WaveRevive     = { Id = 0, DisplayName = "Wave Revive Token",   PriceRobux = 59, Grant = { Currency = "WaveReviveTokens", Amount = 1 } },
}

return ShopConfig
