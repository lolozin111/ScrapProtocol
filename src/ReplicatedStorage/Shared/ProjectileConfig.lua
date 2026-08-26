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
	  Pellets  projectiles per trigger pull. >1 makes the weapon a spray. The shot's damage is
	           DIVIDED across them, so this buys consistency at close range, never extra damage.
	  SpreadDegrees  half-angle of the cone the pellets scatter into. Ignored when Pellets is 1.
	  Bounce   reflections off geometry (and enemies) before it finally stops. Grenades.
	  BounceDamping  fraction of speed kept per bounce (default 0.6).
	  FuseSeconds    stops the projectile this long after firing, wherever it happens to be.
	  NoContactDamage  true for weapons whose damage is entirely in an OnExpire payload.

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

	-- Explosive and stringed arrows. No pierce on either: both weapons care about WHICH enemy an
	-- arrow ended up in — one banks damage per body, the other pairs two of them — and a pass-through
	-- would make "in that enemy" ambiguous.
	ExplosiveArrow = {
		Speed = 155, Gravity = 55, Range = 420, Radius = 0.34, Pierce = 0,
		Color = Color3.fromRGB(255, 140, 90),
	},

	StringedArrow = {
		Speed = 165, Gravity = 50, Range = 440, Radius = 0.3, Pierce = 0,
		Color = Color3.fromRGB(190, 160, 255),
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

	-- Trailblazer: the most pierce in the game, because the trail it leaves is drawn from muzzle to
	-- FINAL impact — the further the round gets, the longer the hazard it leaves behind.
	Trailblazer = {
		Speed = 800, Gravity = 0, Range = 1100, Radius = 0.32, Pierce = 5,
		Color = Color3.fromRGB(255, 120, 120),
	},

	----------------------------------------------------------------------
	-- Minigun. Small, fast, short-ranged and slightly scattered by the fire rate alone — twelve of
	-- these a second reads as a hose, which is the entire point.
	----------------------------------------------------------------------

	Minigun = {
		Speed = 260, Gravity = 0, Range = 260, Radius = 0.16, Pierce = 0,
		Color = Color3.fromRGB(255, 200, 140),
	},

	----------------------------------------------------------------------
	-- Flamethrowers. Not a special weapon type — a very short-ranged gun firing a lot of slow fat
	-- pellets into a wide cone, very fast. Range is the balancing lever for the whole family: at 55
	-- studs you have to be close enough to be in real danger, which is what pays for the DoT.
	--
	-- Pierce is high because a flame jet passing through the first enemy to reach the one behind is
	-- the entire appeal of a cone weapon in a wave-defense game.
	----------------------------------------------------------------------

	Flame = {
		Speed = 95, Gravity = 6, Range = 55, Radius = 0.75, Pierce = 4,
		Pellets = 6, SpreadDegrees = 9,
		Color = Color3.fromRGB(255, 140, 40),
	},

	-- Slower and shorter: ice does less damage per second than fire by design, so its range is a
	-- little tighter too and the payoff is entirely in the slow and the frostbite stacks.
	IceFlame = {
		Speed = 85, Gravity = 4, Range = 48, Radius = 0.8, Pierce = 4,
		Pellets = 6, SpreadDegrees = 10,
		Color = Color3.fromRGB(150, 225, 255),
	},

	-- Widest and slowest of the three. Gravity is deliberately the highest in the family so the
	-- stream visibly droops toward the floor — which is where its puddles end up.
	PoisonFlame = {
		Speed = 80, Gravity = 14, Range = 50, Radius = 0.8, Pierce = 4,
		Pellets = 5, SpreadDegrees = 11,
		Color = Color3.fromRGB(150, 230, 90),
	},

	----------------------------------------------------------------------
	-- Grenade launchers. Lobbed hard, bounces off everything including enemies, and goes off on its
	-- own fuse rather than on contact — so where it ENDS UP matters more than what you aimed at.
	-- All the damage is in the blast (NoContactDamage), which is what stops a grenade from being a
	-- slow bullet that also explodes.
	----------------------------------------------------------------------

	Grenade = {
		Speed = 110, Gravity = 80, Range = 400, Radius = 0.55, Pierce = 0,
		Bounce = 4, BounceDamping = 0.55, FuseSeconds = 1.6, NoContactDamage = true,
		Color = Color3.fromRGB(190, 190, 90),
	},

	-- Flatter and further, per the spec's "a bit more range", and a longer fuse so it travels far
	-- enough to use it. Bounces less: sticky ordnance that skittered as freely as a frag would land
	-- nowhere near what you tagged.
	StickyGrenade = {
		Speed = 135, Gravity = 60, Range = 500, Radius = 0.5, Pierce = 0,
		Bounce = 2, BounceDamping = 0.35, FuseSeconds = 2.2, NoContactDamage = true,
		Color = Color3.fromRGB(140, 200, 130),
	},
}

function ProjectileConfig.Get(name: string?)
	return (name and ProjectileConfig.Profiles[name]) or ProjectileConfig.Default
end

return ProjectileConfig
