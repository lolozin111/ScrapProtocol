--[[
	CraftingRecipes.lua
	Recipe table for both crafting trees. Matches "Crafting" section of the design doc.

	Cost keys must match ore/currency keys used elsewhere (OreConfig.Ores keys, plus
	"Scrap" and "Cores" for the two currencies). CraftingService reads this table —
	add a new tier here and it's immediately craftable, no service code changes needed.

	Projectile names a ballistics profile in ProjectileConfig.lua — guns fire real travelling
	projectiles, not hitscan. A recipe without one falls back to a fast flat default.

	FireRate/BaseDamage replace the old flat DPS field (FireRate * BaseDamage = the same DPS
	numbers this table used to have directly) — split apart so ModConfig.lua's mods can multiply
	each independently (e.g. Speed Coil raises FireRate but lowers BaseDamage). See CombatMath.lua's
	GetEffectiveStats for where these get combined with any equipped mods.
]]

local CraftingRecipes = {}

CraftingRecipes.Weapons = {
	PipePistol = {
		DisplayName = "Pipe Pistol",
		Description = "A length of scrap pipe rigged with a firing pin. Ugly, but it works.",
		Projectile = "Pistol", -- see ProjectileConfig.lua
		Tier = 1,
		Cost = { ScrapIron = 25 },
		FireRate = 2, BaseDamage = 6, -- 12 DPS base, same as before the FireRate/BaseDamage split
	},
	ScrapSMG = {
		DisplayName = "Scrap SMG",
		Description = "Salvaged parts bolted into a rapid-fire frame. Sprays more than it aims.",
		Projectile = "SMG", -- see ProjectileConfig.lua
		Tier = 2,
		Cost = { ScrapIron = 40, CopperWire = 20 },
		FireRate = 6, BaseDamage = 3, -- 18 DPS base
	},
	RailRifle = {
		DisplayName = "Rail Rifle",
		Description = "A scavenged electromagnetic rail, jury-rigged to punch through plating.",
		Projectile = "Rail", -- see ProjectileConfig.lua
		Tier = 3,
		Cost = { SteelPlating = 35, CopperWire = 25 },
		FireRate = 2, BaseDamage = 13, -- 26 DPS base
	},
	ArcCannon = {
		DisplayName = "Arc Cannon",
		Description = "Overcharged capacitors crammed into a housing that probably shouldn't hold them.",
		Projectile = "Arc", -- see ProjectileConfig.lua
		Tier = 4,
		Cost = { GoldContacts = 20, SteelPlating = 50 },
		FireRate = 1, BaseDamage = 38, -- 38 DPS base
	},
	-- VoidiumLauncher (Tier 5) — add once Voidium mining ships post-MVP.
}

CraftingRecipes.Robots = {
	Scrapbot = {
		DisplayName = "Scrapbot",
		Description = "A wobbly chassis stitched from scrap with a single trigger-happy arm.",
		Tier = 1,
		Cost = { ScrapIron = 30 },
		FireRate = 2, BaseDamage = 2, -- 4 DPS base
		HP = 40,
	},
	SentryDrone = {
		DisplayName = "Sentry Drone",
		Description = "Light, fast, and built to spray fire before it gets torn apart.",
		Tier = 2,
		Cost = { CopperWire = 25, ScrapIron = 20 },
		FireRate = 3.5, BaseDamage = 2, -- 7 DPS base
		HP = 25,
	},
	IronGuardian = {
		DisplayName = "Iron Guardian",
		Description = "Slow and heavily plated — built to take hits so you don't have to.",
		Tier = 3,
		Cost = { SteelPlating = 40, CopperWire = 20 },
		FireRate = 1, BaseDamage = 5, -- 5 DPS base
		HP = 120,
	},
	ArcTurret = {
		DisplayName = "Arc Turret",
		Description = "A stationary cannon with a wide blast radius and a short fuse.",
		Tier = 4,
		Cost = { GoldContacts = 25, SteelPlating = 45 },
		FireRate = 1, BaseDamage = 12, -- 12 DPS base; splash damage, treat as AoE in WaveService
		HP = 60,
	},
	-- TitanMech (Tier 5) — add once Voidium mining ships post-MVP.
}

-- Max robots a single player can have deployed at once (MVP value; +1 per
-- "Extra Robot Slot" game pass purchase — apply that as a per-player override).
CraftingRecipes.BaseMaxDeployedRobots = 3

return CraftingRecipes
