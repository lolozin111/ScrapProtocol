--[[
	EnemyConfig.lua
	Static data for every hostile enemy type the combat engine (CombatEncounterService.lua) can
	spawn. Two factions, matching the world's own lore instead of a generic zombie/monster theme:

	- Construct — scavenged security drones and automation gone haywire. The nastier ones are
	  Voidium-corrupted (same Voidium Shard the Forge already treats as "not from around here,
	  handle carefully" — this gives it a second job besides a smelting ingredient). Slow, tanky,
	  hits hard, small MoveSpeed spread between types.
	- Rebel — Mad-Max-style raiders/scavengers, not related to the Constructs at all. Faster, more
	  erratic, lower HP per unit but come at you quicker.

	Every enemy TYPE below is built with a small helper (defineEnemy) that layers its own table on
	top of one of the two faction base templates via a metatable's __index — ask for a field an
	entry doesn't define itself (say, MoveSpeed) and Lua falls through to the faction default
	automatically. This is the "metatable of enemies" pattern: add a new Construct variant by only
	writing the 3-4 fields that make it different, not by repeating every shared stat.

	HP/ContactDamage here are BASE values at wave 1 — CombatEncounterService scales them by
	WaveConfig.GetEnemyMultiplier(waveNumber) at spawn time, the same multiplier the old headless
	sim already used, so difficulty scaling doesn't get reinvented alongside the real combat swap.

	ModelName is looked up in ServerStorage.EnemyModels (same "drop a same-named thing into a
	folder, no code changes needed" convention as ReplicatedStorage.ItemIcons — see
	MainHud.client.lua's getItemIcon comment) — build a simple R15 dummy/rig Model there named
	exactly this, any size/shape/proportions work for testing, same as every other placeholder in
	this project so far. AIPattern is a name looked up in EnemyAI.lua's pattern table.
]]

local EnemyConfig = {}

----------------------------------------------------------------------
-- Faction base templates
----------------------------------------------------------------------

-- Fields every enemy of a faction has UNLESS its own entry overrides them. Defense is a flat
-- stat consumed by DamagePipeline.lua's ratio-based mitigation formula (100/(100+Defense)) — see
-- that file for why ratio was chosen over flat subtraction (never lets a weak weapon get
-- reduced all the way to 0 against a heavily-defended target).
local ConstructBase = {
	Faction = "Construct",
	MoveSpeed = 12,
	ContactDamage = 8,
	ContactRange = 6,      -- studs; how close it needs to be to land a hit
	AttackCooldown = 1.4,  -- seconds between contact hits
	Defense = 12,
	AIPattern = "Chaser",
}

local RebelBase = {
	Faction = "Rebel",
	-- Was 16 — exactly a default Roblox Humanoid's WalkSpeed (nothing in this codebase changes the
	-- player's own WalkSpeed, so that's the real baseline), meaning Scavenger/Raider (both use this
	-- default, unmodified) could keep pace with the player indefinitely instead of ever falling
	-- behind. Dropped a little below it — "make enemies a little slower than the player, just a
	-- little bit" — same 14 ScrapCrawler's own explicit override already uses.
	MoveSpeed = 14,
	ContactDamage = 6,
	ContactRange = 5,
	AttackCooldown = 0.9,
	Defense = 4,
	AIPattern = "Chaser",
}

-- Layers `overrides` on top of `base` via __index — overrides wins on any field it actually sets,
-- everything else falls through to the faction template. `overrides` becomes the live table (with
-- the metatable attached), so it's cheap and there's nothing to keep in sync by hand.
local function defineEnemy(base, overrides)
	return setmetatable(overrides, { __index = base })
end

----------------------------------------------------------------------
-- Enemy types
----------------------------------------------------------------------
-- WaveConfig.EnemyTypes lists the keys eligible for normal (non-elite) waves; elite waves (every
-- WaveConfig.EliteWaveInterval-th, see WaveConfig.IsEliteWave) additionally pull from
-- EnemyConfig.EliteTypes below. HP/ContactDamage are BASE (wave-1) numbers — see this file's
-- header comment on where the wave multiplier gets applied.

EnemyConfig.Types = {
	-- Rebels — matches WaveConfig.EnemyTypes' existing placeholder names, now with real stats.
	Scavenger = defineEnemy(RebelBase, {
		DisplayName = "Scavenger",
		Description = "Underequipped and outnumbered on their own — the danger is never one Scavenger.",
		HP = 18,
		ModelName = "Scavenger",
		-- Idle/Move/Death animation ids, played by EnemyAnimation.Locomotion for a Chaser. Leave a slot
		-- out to skip it. The model's Humanoid needs an Animator child, or nothing plays (one warn).
		-- Optional MoveAnimationSpeed (1 = as published) works here the same as on the Hulk.
		Animations = {
			Move = "rbxassetid://80963801870849",
		},
	}),
	Raider = defineEnemy(RebelBase, {
		DisplayName = "Raider",
		Description = "Better-armed than a Scavenger and knows it.",
		HP = 30,
		ContactDamage = 9,
		ModelName = "Raider",
	}),
	Brute = defineEnemy(RebelBase, {
		DisplayName = "Brute",
		Description = "Wades in slow and takes a beating before it goes down.",
		HP = 70,
		ContactDamage = 12,
		MoveSpeed = 11, -- slower than the RebelBase default — bulk over speed
		AttackCooldown = 1.2,
		Defense = 10,
		ModelName = "Brute",
	}),

	-- Constructs.
	ScrapCrawler = defineEnemy(ConstructBase, {
		DisplayName = "Scrap Crawler",
		Description = "A maintenance drone with its safety governor long since fried. Erratic, not smart.",
		HP = 22,
		ContactDamage = 6,
		MoveSpeed = 14, -- faster than the ConstructBase default — small and skittish
		Defense = 8,
		ModelName = "ScrapCrawler",
	}),
	SentinelDrone = defineEnemy(ConstructBase, {
		DisplayName = "Sentinel Drone",
		Description = "Old perimeter security, still running its last-given order: don't let anyone through.",
		HP = 45,
		ContactDamage = 10,
		ModelName = "SentinelDrone",
	}),
}

-- Elite-only pool, spawned on top of the normal pool on elite waves (see WaveConfig
--.IsEliteWave/EliteWaveInterval) — noticeably tougher, not just a bigger number of normal
-- enemies.
--
-- This pool USED to hold VoidwakenHulk, which meant the raid's terminal encounter was also a
-- routine wave spawn every fifth wave: one table was serving two pickers
-- (CombatEncounterService's elite pick and RaidRoomService.pickBossSpawnKeys). Bosses now live in
-- EnemyConfig.BossTypes below and the two pickers read one table each, so a boss can never leak
-- into a wave again.
--
-- Siegebreaker's identity is ARMOUR, not mass — Defense 45 against a Construct base of 12 and the
-- Hulk's own 28 makes it the most heavily defended thing in the game, so a player watches their
-- damage numbers drop and has to change weapon or target. The Hulk out-bulks it on raw HP instead.
-- That split is deliberate: elite = armour, boss = mass.
EnemyConfig.EliteTypes = {
	Siegebreaker = defineEnemy(ConstructBase, {
		DisplayName = "Siegebreaker",
		Description = "Built to walk into a wall until the wall stops being one.",
		HP = 140,
		-- Zero on purpose: the Slam pattern below replaces contact damage rather than stacking on
		-- top of it. One telegraphed hit on a long cycle is readable; a heavy hit layered over a
		-- normal contact cooldown just reads as unfair damage from something standing next to you.
		ContactDamage = 0,
		MoveSpeed = 9,       -- slow enough that a raid player can always walk out of the slam radius
		ContactRange = 8,    -- bulkier reach than the Construct default 6
		Defense = 45,
		ModelName = "Siegebreaker",

		-- Selects EnemyAI.Patterns.Slam. Every other type in this file uses the faction default
		-- "Chaser"; this is the second pattern the game has ever had.
		AIPattern = "Slam",

		-- Slam cycle. SlamCooldown is measured from IMPACT, not from the start of the wind-up, so
		-- the visible tell can never be compressed by wave scaling.
		SlamWindup = 0.9,    -- seconds of telegraph before the hit lands
		SlamDamage = 42,     -- base; scaled by the wave/run multiplier like ContactDamage would be
		SlamRadius = 14,     -- studs. Only discriminates in raids — see below.
		SlamCooldown = 3.5,  -- seconds from impact to the next wind-up
	}),
}

-- Boss-only pool. Read by RaidRoomService.pickBossSpawnKeys and by nothing else — a key in here
-- will NEVER appear in a wave. Stats are base numbers: the raid applies
-- RaidConfig.BossComposition.Multiplier (2.6) on top of the run multiplier, so treat these as
-- considerably smaller than what a player actually meets in a Boss room.
--
-- VoidwakenHulk's flavor plants the seed for a future "boss-only drop" reward hook (see
-- DESIGN_NOTES.md's Base Defense / Research Level notes) — that drop itself isn't built yet,
-- deliberately deferred to whenever Research Level ships.
EnemyConfig.BossTypes = {
	VoidwakenHulk = defineEnemy(ConstructBase, {
		DisplayName = "Voidwaken Hulk",
		Description = "Whatever Voidium did to this one, it didn't make it slower.",
		HP = 340,
		-- FALLBACK ONLY. The Animated pattern replaces contact damage with the named hits below; this
		-- is used only if the animations can't load and he drops back to plain Chaser.
		ContactDamage = 22,
		-- Was 10, then 13, then 15; user: still "too slow", asked for +10. Now FASTER than a player's 16,
		-- which drops the original "his slows are balanced by his low speed" premise — watch for a
		-- slowed player being unable to ever get out of his AttackRadius.
		MoveSpeed = 21, -- user: 25 was right once movement was fixed, "4 less to make it perfect"
		-- Seconds from the END of one attack animation to when the next may start.
		AttackCooldown = 1.6,
		Defense = 28,
		ModelName = "VoidwakenHulk",
		-- Inside AttackRadius (horizontal studs from the player) he holds his ground and attacks; he
		-- only walks once the player leaves it, and then walks until they're within ContactRange.
		-- Keep ContactRange below AttackRadius (the gap stops him flicking between walk and stop at
		-- the edge) and AttackRadius within every attack's TriggerRange (so holding ground means he
		-- can still swing).
		AttackRadius = 50, -- was 70 for a while; user moved it back once the escort and bursts landed
		ContactRange = 40,
		-- Every so often while he's WALKING after a player, he surges: speed x Multiplier for Duration
		-- seconds, then a random CooldownMin..CooldownMax before the next one. Lets a slow crawler
		-- actually close on a player who keeps backing off, without raising his everyday speed.
		SpeedBurst = { Multiplier = 1.8, Duration = 1.5, CooldownMin = 5, CooldownMax = 9 },
		-- Humanoid.HipHeight, applied at spawn so it can't drift from a hand-edited Studio copy. His
		-- root sits inside a lying-down body, so the Roblox default buries him. Raise it if he sinks
		-- into the floor, lower it if he floats.
		HipHeight = 12,
		-- None of his parts collide, so his big root block can't snag on props or room walls. The
		-- Humanoid still holds him above the floor at HipHeight. (He can now crawl through walls.)
		NoCollide = true,
		-- What player shots can hit (see spawnEnemy). His body mesh only registers hits in its standing
		-- rest pose, not the lying pose you see, so without this only his root block took damage.
		-- Size/Offset are studs relative to his HumanoidRootPart, whose axes are turned 90° from his
		-- body (see FacingYawOffset). Sized live in a playtest (2026-09-15) via the model's HitboxSize /
		-- HitboxOffset Attributes; re-tune the same way.
		Hitbox = { Size = Vector3.new(26, 18, 30), Offset = Vector3.new(-18, -6, -5) },

		-- Selects EnemyAI.Patterns.Animated (see EnemyAnimation.lua): his attacks are Studio
		-- animations, and damage lands on the animation's own event markers, measured from a fist
		-- Attachment rather than from his root.
		AIPattern = "Animated",

		-- An empty string means "not animated yet" — that slot is skipped (with one warn), never an error.
		Animations = {
			Idle = "rbxassetid://113796712422007",
			Move = "rbxassetid://103708147649106",
			Death = "",
		},
		-- Playback speed of the Move animation (1 = as published). Lower = slower crawl.
		-- Scaled with MoveSpeed (0.7 at 10, 0.9 at 13, 1.05 at 15) so the crawl keeps pace instead of sliding.
		MoveAnimationSpeed = 1.45,

		-- Which attack he plays is a weighted pick among the ones whose TriggerRange (horizontal studs,
		-- his root to the player) covers the current distance. The damage an attack deals is decided by
		-- which markers its animation contains, not by anything here.
		Attacks = {
			{ Name = "RockArmCombo", AnimationId = "rbxassetid://137947497885396", TriggerRange = 50, Weight = 1 },
			{ Name = "LeftSweep", AnimationId = "rbxassetid://105875185230848", TriggerRange = 50, Weight = 1 },
		},

		-- Keyed by animation event NAME (exact, case-sensitive — the names typed in the Animation Editor).
		--   Kind "Impact": one check the instant the marker named <key> is reached.
		--   Kind "Sweep":  markers <key>Start and <key>End open and close a window; the fist is checked
		--                  every frame between them, and each target can be hit at most once per swing.
		-- Attachment: the Attachment inside the model the hit measures from. Reach: studs from it.
		-- Damage: base, scaled by the run/boss multiplier like ContactDamage.
		-- SlowMultiplier: the player's speed multiplier while slowed (0.6 = 40% slower).
		-- A new hit on a slowed player REFRESHES the slow to the new hit's values; slows never stack.
		AnimationHits = {
			ImpactR = { Kind = "Impact", Attachment = "FistR", Damage = 12, Reach = 20, SlowMultiplier = 0.6, SlowSeconds = 1.5 },
			ImpactRFinal = { Kind = "Impact", Attachment = "FistR", Damage = 30, Reach = 28, SlowMultiplier = 0.3, SlowSeconds = 2.5 },
			SweepL = { Kind = "Sweep", Attachment = "FistL", Damage = 8, Reach = 15, SlowMultiplier = 0.6, SlowSeconds = 1.5 },
		},

		-- Degrees added to "face the player", because the rig's front isn't the root's LookVector.
		-- Found live in a playtest (a FacingYawOffset number Attribute on the live Model overrides this).
		FacingYawOffset = -90,
		-- How fast he turns toward the player, in degrees per second. Low on purpose: a slow boss.
		TurnSpeed = 90,
		-- What he turns around: a Bone or Attachment name. His root isn't the middle of his lying body.
		TurnPivot = "Torso",
		-- He only starts an attack once he's within this many degrees of facing the player, so
		-- getting behind him buys time instead of being met by an instant snap-and-swing.
		AttackFacingTolerance = 30,

		-- Studio aid: draws each hit's reach sphere at the fist and prints hit/miss distances to Output.
		-- Use it to check the server sees the ANIMATED fist, not the rest pose. Leave false when shipping.
		DebugHitboxes = false,
	}),
}

return EnemyConfig
