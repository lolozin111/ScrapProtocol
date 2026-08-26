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

	OnHitStatus = { Key, IntervalSeconds?, Chance?, Overrides? } applies a StatusConfig effect on
	contact. IntervalSeconds is per TARGET — a spray weapon lands dozens of hits a second, so without
	it every status would sit at max stacks permanently.

	GroundEffect = { Chance, Radius, Duration, ... } leaves something behind where the projectile
	stops, via GroundEffectService. Chance is what keeps a spray weapon from carpeting the floor.

	Explosion = { Radius, MinMultiplier, Status?, PullStuds? } does area damage where the projectile
	stops. For a weapon whose ProjectileConfig sets NoContactDamage, BaseDamage IS the blast damage.

	Behavior names a strategy in WeaponBehaviors.lua, with BehaviorParams passed to it. This is for
	weapons whose gimmick is genuinely new code rather than a number — delayed detonation, tethers,
	airbursts. Everything above should be preferred where it can express the idea, since config costs
	nothing to add and a behaviour is a function somebody has to maintain.

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
	-- Flamethrowers. All three are the same cone emitter (ProjectileConfig's Pellets/SpreadDegrees)
	-- with a different status bolted on, which is why one fire pattern bought the whole family.
	--
	-- Their damage lives in the STATUS, not the pellets. Direct damage is deliberately feeble: a
	-- flamethrower that also hit hard on contact would be a shotgun with a debuff attached. Range is
	-- the balancing lever — you have to be close enough to be in real trouble.
	----------------------------------------------------------------------

	Flamethrower = {
		DisplayName = "Flamethrower",
		Description = "A pressurised tank and a bad idea. Everything in the cone keeps burning.",
		Projectile = "Flame",
		Family = "Flamethrowers",
		Tier = 3,
		Cost = { SteelPlating = 45, CopperWire = 40 },
		FireRate = 8, BaseDamage = 3, -- 24 DPS on contact; the Burn is where the real damage is
		-- No IntervalSeconds: Burn is this gun's damage, so it refreshes on every hit and stops the
		-- moment you stop firing. That is the intended feel — sustained pressure, not a fire-and-forget
		-- debuff you apply once and walk away from.
		OnHitStatus = { Key = "Burn" },
	},

	IceThrower = {
		DisplayName = "Ice Thrower",
		Description = "A mist so cold it burns. Slows what it touches, and freezes what it touches twice.",
		Projectile = "IceFlame",
		Family = "Flamethrowers",
		Tier = 4,
		Cost = { SteelPlating = 50, GoldContacts = 20, CopperCoil = 15 },
		FireRate = 8, BaseDamage = 2, -- weaker than the regular thrower on purpose; it pays in control
		-- Frostbite already slows on its own and escalates to a Stun at 2 stacks (StatusConfig), so
		-- "slows down enemies, applies frostbite every 2 seconds, stunned at two stacks" is entirely
		-- config — this gun contains no ice-specific code anywhere.
		OnHitStatus = { Key = "Frostbite", IntervalSeconds = 2 },
	},

	PoisonThrower = {
		DisplayName = "Poison Thrower",
		Description = "A slow, drooping green cloud. Patient work — and it keeps working after you stop.",
		Projectile = "PoisonFlame",
		Family = "Flamethrowers",
		Tier = 4,
		Cost = { SteelPlating = 45, GoldContacts = 25, VoidiumShard = 8 },
		FireRate = 7, BaseDamage = 2,
		-- Five seconds per stack, five stacks: a full ramp takes 25 seconds of sustained fire, and
		-- Poison's own duration means it drains away if you stop. Fully stacked it out-damages the
		-- regular Flamethrower (StatusConfig.Poison compounds +35% per stack) — which is the whole
		-- trade: the highest ceiling in the family and by far the longest climb to it.
		OnHitStatus = { Key = "Poison", IntervalSeconds = 5 },
		-- Puddles: damage dealt to enemies you are not even shooting. 4% per pellet keeps the floor
		-- readable — at 7 shots/s x 5 pellets that is still roughly one new puddle a second.
		GroundEffect = {
			Chance = 0.04,
			Radius = 7,
			Duration = 8,
			TickInterval = 1,
			Status = { Key = "Poison" },
			Color = Color3.fromRGB(120, 200, 70),
		},
	},

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

	ExplosiveBow = {
		DisplayName = "Explosive Bow",
		Description = "Arrows that wait. Land several in one body before the first goes off.",
		Projectile = "ExplosiveArrow",
		Family = "Bows",
		Tier = 4,
		Cost = { SteelPlating = 45, GoldContacts = 25, CopperCoil = 20 },
		FireRate = 1.1, BaseDamage = 16, -- low on impact; the arrows are a bank, not a payment
		HeadshotMultiplier = 1.8,
		Behavior = "ExplosiveArrow",
		BehaviorParams = {
			FuseSeconds = 2.5,
			DamageFraction = 0.9,  -- each arrow's detonation, relative to the damage it landed for
			PerArrowBonus = 0.4,   -- every arrow past the first adds 40% to ALL of them
		},
	},

	StringedBow = {
		DisplayName = "Stringed Bow",
		Description = "Two arrows, one cord. Land them on different targets and drag them together.",
		Projectile = "StringedArrow",
		Family = "Bows",
		Tier = 5,
		Cost = { GoldContacts = 40, VoidiumShard = 12, CopperCoil = 25 },
		FireRate = 1.3, BaseDamage = 18,
		HeadshotMultiplier = 1.8,
		Behavior = "StringedArrow",
		BehaviorParams = {
			CycleLength = 4, FirstShot = 3, SecondShot = 4,
			BonusFraction = 1.5, -- dealt to BOTH ends of the string
		},
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
	-- Grenade launchers. The projectile does nothing on contact — it bounces off enemies and walls
	-- alike and detonates on its own fuse (see ProjectileConfig's Grenade profile). BaseDamage here
	-- is BLAST damage, applied with linear falloff to everything in the radius.
	----------------------------------------------------------------------

	GrenadeLauncher = {
		DisplayName = "Grenade Launcher",
		Description = "Lobbed, bouncy, and utterly indifferent to what you were actually aiming at.",
		Projectile = "Grenade",
		Family = "GrenadeLaunchers",
		Tier = 4,
		Cost = { SteelPlating = 55, GoldContacts = 20, HardenedPlate = 12 },
		-- 55 DPS against ONE target and far more into a group — the "crazy AOE damage" the spec asks
		-- for lives in the radius, not in this number. Slow enough that a miss genuinely costs you.
		FireRate = 0.7, BaseDamage = 78,
		Explosion = {
			Radius = 18,
			MinMultiplier = 0.35, -- rim hits still land for a third; standing on it is much worse
			Penetration = 8,      -- blast ignores some armour, so it stays a crowd answer
		},
	},

	StickyGrenade = {
		DisplayName = "Sticky Launcher",
		Description = "Detonates in a mess of adhesive. Whatever survives is slowed and bunched up.",
		Projectile = "StickyGrenade",
		Family = "GrenadeLaunchers",
		Tier = 5,
		Cost = { GoldContacts = 35, HardenedPlate = 20, VoidiumShard = 10 },
		FireRate = 0.7, BaseDamage = 55, -- less damage than the regular launcher, per the spec
		Explosion = {
			Radius = 20,
			MinMultiplier = 0.4,
			Penetration = 8,
			-- "Makes the enemy sticky, where they stick to each other and get slowed": Slow is the
			-- status, and PullStuds drags everything caught toward the blast so the group is
			-- physically bunched for whatever you fire next. Together those are the whole gimmick,
			-- and neither is sticky-specific code.
			Status = { Key = "Slow" },
			PullStuds = 10,
		},
	},

	Trailblazer = {
		DisplayName = "Trailblazer",
		Description = "Draws a burning line from muzzle to impact. Anything crossing it bleeds.",
		Projectile = "Trailblazer",
		Family = "Snipers",
		Tier = 4,
		Cost = { SteelPlating = 50, GoldContacts = 30, HardenedPlate = 15 },
		FireRate = 0.5, BaseDamage = 62, -- less than the Longshot, per the spec; the trail makes it up
		HeadshotMultiplier = 1,
		Penetration = 10,
		Behavior = "BleedTrail",
		BehaviorParams = {
			MaxLength = 100, -- the spec's own number
			Radius = 3,
			Duration = 6,
			TickInterval = 1,
		},
	},

	Hellfire = {
		DisplayName = "Hellfire",
		Description = "Four shots, then one straight up — and whatever comes back down is not yours to aim.",
		Projectile = "Sniper",
		Family = "Snipers",
		Tier = 5,
		Cost = { GoldContacts = 45, VoidiumShard = 15, HardenedPlate = 20 },
		FireRate = 0.6, BaseDamage = 80,
		HeadshotMultiplier = 1,
		Penetration = 10,
		Behavior = "Hellfire",
		BehaviorParams = {
			EveryNthShot = 5,
			MissileCount = 6,
			ScatterRadius = 28,
			BurstHeight = 60,
			MissileRadius = 10,
			DamageFraction = 0.55, -- per missile, so a full barrage is worth roughly three ordinary shots
		},
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
