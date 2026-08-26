--[[
	CraftingRecipes.lua
	Recipe table for both crafting trees. Matches "Crafting" section of the design doc.

	Cost keys must match ore/currency keys used elsewhere (OreConfig.Ores keys, plus
	"Scrap" and "Cores" for the two currencies). CraftingService reads this table —
	add a new tier here and it's immediately craftable, no service code changes needed.

	Projectile names a ballistics profile in ProjectileConfig.lua — guns fire real travelling
	projectiles, not hitscan. A recipe without one falls back to a fast flat default.

	Family names a group in WeaponFamilyConfig.lua. Everything in a locked family is hidden in the
	Forge and refused server-side, so a weapon added without a Family (or with an unknown one) is
	unforgeable rather than accidentally free — see ForgeService.ForgeWeapon.

	HeadshotMultiplier makes a hit on the target's Head part deal more. Optional; no field means a
	head is worth exactly as much as a torso, which is right for a flamethrower and wrong for a bow.
	Snipers deliberately set it to 1: their damage is already in the base number, and the user's spec
	says the Regular Sniper hits for full "no matter if headshot".

	WieldSpeedMultiplier slows the player while the gun is HELD (not merely owned) — the cost of
	carrying something heavy. Applied by WeaponToolService through PlayerSpeed.

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
		Family = "Salvage",
		Tier = 1,
		Cost = { ScrapIron = 25 },
		FireRate = 2, BaseDamage = 6, -- 12 DPS base, same as before the FireRate/BaseDamage split
	},
	ScrapSMG = {
		DisplayName = "Scrap SMG",
		Description = "Salvaged parts bolted into a rapid-fire frame. Sprays more than it aims.",
		Projectile = "SMG", -- see ProjectileConfig.lua
		Family = "Salvage",
		Tier = 2,
		Cost = { ScrapIron = 40, CopperWire = 20 },
		FireRate = 6, BaseDamage = 3, -- 18 DPS base
	},
	RailRifle = {
		DisplayName = "Rail Rifle",
		Description = "A scavenged electromagnetic rail, jury-rigged to punch through plating.",
		Projectile = "Rail", -- see ProjectileConfig.lua
		Family = "Salvage",
		Tier = 3,
		Cost = { SteelPlating = 35, CopperWire = 25 },
		FireRate = 2, BaseDamage = 13, -- 26 DPS base
	},
	ArcCannon = {
		DisplayName = "Arc Cannon",
		Description = "Overcharged capacitors crammed into a housing that probably shouldn't hold them.",
		Projectile = "Arc", -- see ProjectileConfig.lua
		Family = "Salvage",
		Tier = 4,
		Cost = { GoldContacts = 20, SteelPlating = 50 },
		FireRate = 1, BaseDamage = 38, -- 38 DPS base
	},
	-- VoidiumLauncher (Tier 5) — add once Voidium mining ships post-MVP.

	----------------------------------------------------------------------
	-- Bows — arcing, silent, and the only family that genuinely rewards aiming at heads.
	----------------------------------------------------------------------

	RegularBow = {
		DisplayName = "Scrap Bow",
		Description = "Bent rebar and cable. Slow, quiet, and unforgiving if you can't lead a shot.",
		Projectile = "Bow",
		Family = "Bows",
		Tier = 2,
		Cost = { ScrapIron = 45, CopperWire = 15 },
		FireRate = 1.2, BaseDamage = 20, -- 24 DPS on body shots, 60 if every arrow finds a head
		HeadshotMultiplier = 2.5, -- the whole point of the family: body damage is mediocre on purpose
	},
	Longbow = {
		DisplayName = "Longbow",
		Description = "A heavier draw and a heavier arrow. Punches through a line of bodies.",
		Projectile = "Longbow",
		Family = "Bows",
		Tier = 3,
		Cost = { SteelPlating = 40, CopperWire = 30 },
		FireRate = 0.8, BaseDamage = 34, -- 27 DPS single-target, far more into a crowd (Pierce 4)
		HeadshotMultiplier = 2.2,
	},

	----------------------------------------------------------------------
	-- Snipers — flat, fast, piercing. Damage does not care where it lands.
	----------------------------------------------------------------------

	RegularSniper = {
		DisplayName = "Longshot Rifle",
		Description = "Enormous damage, glacial rate of fire, and it fights you every step you take.",
		Projectile = "Sniper",
		Family = "Snipers",
		Tier = 3,
		Cost = { SteelPlating = 55, GoldContacts = 15 },
		FireRate = 0.5, BaseDamage = 90, -- 45 DPS, but delivered in one hit — burst, not sustain
		HeadshotMultiplier = 1, -- "amazing damage (no matter if headshot)" — no bonus by design
		WieldSpeedMultiplier = 0.55, -- the stated drawback: carrying it slows you right down
		Penetration = 12, -- shrugs off armour; snipers should not be walled by a tanky enemy
	},
	QuickSniper = {
		DisplayName = "Scout Rifle",
		Description = "Traded most of the punch for a trigger you can actually pull. Still not an SMG.",
		Projectile = "QuickSniper",
		Family = "Snipers",
		Tier = 3,
		Cost = { SteelPlating = 35, CopperWire = 35 },
		FireRate = 1.6, BaseDamage = 30, -- 48 DPS, spread over enough shots to correct your aim
		HeadshotMultiplier = 1,
		Penetration = 6,
	},

	----------------------------------------------------------------------
	-- Miniguns
	----------------------------------------------------------------------

	Minigun = {
		DisplayName = "Rotary Cannon",
		Description = "Each round is almost nothing. There are a great many rounds.",
		Projectile = "Minigun",
		Family = "Miniguns",
		Tier = 4,
		Cost = { SteelPlating = 60, GoldContacts = 25, SteelIngot = 10 },
		FireRate = 12, BaseDamage = 4, -- 48 DPS, the highest sustained in the game and the least burst
		-- Deliberately left plain. The user's spec says so outright ("i dont have that many ideas for
		-- the minigun at the moment") — so this is an honest placeholder stat line to revisit, not an
		-- oversight. Do not invent a gimmick for it without asking.
	},
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
