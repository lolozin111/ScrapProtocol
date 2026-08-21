--[[
	CraftingRecipes.lua
	Recipe table for both crafting trees. Matches "Crafting" section of the design doc.

	Cost keys must match ore/currency keys used elsewhere (OreConfig.Ores keys, plus
	"Scrap" and "Cores" for the two currencies). CraftingService reads this table —
	add a new tier here and it's immediately craftable, no service code changes needed.
]]

local CraftingRecipes = {}

CraftingRecipes.Weapons = {
	PipePistol = {
		DisplayName = "Pipe Pistol",
		Tier = 1,
		Cost = { ScrapIron = 25 },
		DPS = 12, -- used by WaveService's combat simulation; replace with real weapon
		          -- damage-per-shot x fire-rate once you have actual gun-firing code
	},
	ScrapSMG = {
		DisplayName = "Scrap SMG",
		Tier = 2,
		Cost = { ScrapIron = 40, CopperWire = 20 },
		DPS = 18,
	},
	RailRifle = {
		DisplayName = "Rail Rifle",
		Tier = 3,
		Cost = { SteelPlating = 35, CopperWire = 25 },
		DPS = 26,
	},
	ArcCannon = {
		DisplayName = "Arc Cannon",
		Tier = 4,
		Cost = { GoldContacts = 20, SteelPlating = 50 },
		DPS = 38,
	},
	-- VoidiumLauncher (Tier 5) — add once Voidium mining ships post-MVP.
}

CraftingRecipes.Robots = {
	Scrapbot = {
		DisplayName = "Scrapbot",
		Tier = 1,
		Cost = { ScrapIron = 30 },
		DPS = 4,
		HP = 40,
	},
	SentryDrone = {
		DisplayName = "Sentry Drone",
		Tier = 2,
		Cost = { CopperWire = 25, ScrapIron = 20 },
		DPS = 7,
		HP = 25,
	},
	IronGuardian = {
		DisplayName = "Iron Guardian",
		Tier = 3,
		Cost = { SteelPlating = 40, CopperWire = 20 },
		DPS = 5,
		HP = 120,
	},
	ArcTurret = {
		DisplayName = "Arc Turret",
		Tier = 4,
		Cost = { GoldContacts = 25, SteelPlating = 45 },
		DPS = 12, -- splash damage; treat as AoE in WaveService
		HP = 60,
	},
	-- TitanMech (Tier 5) — add once Voidium mining ships post-MVP.
}

-- Max robots a single player can have deployed at once (MVP value; +1 per
-- "Extra Robot Slot" game pass purchase — apply that as a per-player override).
CraftingRecipes.BaseMaxDeployedRobots = 3

return CraftingRecipes
