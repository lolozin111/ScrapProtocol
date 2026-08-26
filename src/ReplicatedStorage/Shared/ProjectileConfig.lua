--[[
	ProjectileConfig.lua
	How each weapon's shot flies. Guns fire real travelling projectiles now rather than resolving
	instantly — see ProjectileService.lua for why.

	A weapon picks its profile by name (CraftingRecipes.Weapons[key].Projectile). Anything without
	one falls back to Default, so a weapon added without thinking about ballistics still fires.

	FIELDS
	  Speed    studs/second. This is the single biggest lever on how a gun FEELS. 200+ reads as a
	           bullet, 90-140 as something you can watch and lead, below 80 as lobbed.
	  Gravity  studs/s² of drop. 0 flies dead straight. Non-zero gives an arc, which is what a bow
	           or a grenade launcher wants.
	  Range    studs before it gives up and disappears.
	  Radius   visual size of the projectile part. Purely cosmetic — hit detection is the raycast
	           along its path, not this sphere.
	  Pierce   how many enemies it passes THROUGH before stopping. 0 = stops at the first thing hit.
	  Color    tracer colour.

	=== THIS IS WHERE GUN VARIANTS PLUG IN ===
	Flamethrowers, bows, snipers, grenade launchers and miniguns differ mostly in these numbers plus
	their fire pattern. Slow arcing high-gravity = bow. Fast, flat, high pierce = sniper. Slow, heavy
	gravity, big radius = grenade. The patterns that need genuinely new behaviour (a cone rather than
	a line, bouncing, exploding on impact) are additions to ProjectileService, not new systems.
]]

local ProjectileConfig = {}

-- Used by any weapon that does not name a profile. Deliberately fast and flat, so an unconfigured
-- gun behaves like the hitscan it replaced rather than surprising anyone with arcing rounds.
ProjectileConfig.Default = {
	Speed = 260,
	Gravity = 0,
	Range = 400,
	Radius = 0.35,
	Pierce = 0,
	Color = Color3.fromRGB(255, 214, 130),
}

ProjectileConfig.Profiles = {
	-- Starter sidearm: quick, flat, unremarkable on purpose.
	Pistol = {
		Speed = 240, Gravity = 0, Range = 350, Radius = 0.3, Pierce = 0,
		Color = Color3.fromRGB(255, 214, 130),
	},

	-- Sprayed, so slightly slower and smaller — a wall of small tracers reads as automatic fire in
	-- a way that a few fast ones does not.
	SMG = {
		Speed = 220, Gravity = 0, Range = 280, Radius = 0.22, Pierce = 0,
		Color = Color3.fromRGB(255, 230, 170),
	},

	-- Electromagnetic rail: the fastest thing in the game, and punches through a body.
	Rail = {
		Speed = 420, Gravity = 0, Range = 600, Radius = 0.28, Pierce = 2,
		Color = Color3.fromRGB(180, 255, 200),
	},

	-- Overcharged capacitors: a big slow visible orb. Slow enough to actually watch travel, which
	-- is what makes a heavy weapon feel heavy.
	Arc = {
		Speed = 130, Gravity = 0, Range = 300, Radius = 0.9, Pierce = 1,
		Color = Color3.fromRGB(150, 220, 255),
	},

	----------------------------------------------------------------------
	-- Bows. Gravity is the family's whole identity — an arrow that flew flat would just be a slow
	-- bullet. Slow enough to watch, so leading a moving target is a skill rather than a coin flip.
	----------------------------------------------------------------------

	Bow = {
		Speed = 150, Gravity = 55, Range = 420, Radius = 0.28, Pierce = 1,
		Color = Color3.fromRGB(200, 180, 120),
	},

	-- Heavier draw: flatter (more speed against the same gravity) and it keeps going through bodies.
	Longbow = {
		Speed = 190, Gravity = 45, Range = 550, Radius = 0.38, Pierce = 4,
		Color = Color3.fromRGB(225, 200, 130),
	},

	----------------------------------------------------------------------
	-- Snipers. Fast and dead flat, so where you point is where it lands with no lead at all — the
	-- opposite of a bow on purpose, since both families are otherwise "slow, high damage".
	----------------------------------------------------------------------

	Sniper = {
		Speed = 900, Gravity = 0, Range = 1200, Radius = 0.3, Pierce = 3,
		Color = Color3.fromRGB(255, 245, 210),
	},

	QuickSniper = {
		Speed = 700, Gravity = 0, Range = 900, Radius = 0.24, Pierce = 2,
		Color = Color3.fromRGB(255, 235, 190),
	},

	----------------------------------------------------------------------
	-- Minigun. Small, fast, short-ranged and slightly scattered by the fire rate alone — twelve of
	-- these a second reads as a hose, which is the entire point.
	----------------------------------------------------------------------

	Minigun = {
		Speed = 260, Gravity = 0, Range = 260, Radius = 0.16, Pierce = 0,
		Color = Color3.fromRGB(255, 200, 140),
	},
}

function ProjectileConfig.Get(name: string?)
	return (name and ProjectileConfig.Profiles[name]) or ProjectileConfig.Default
end

return ProjectileConfig
