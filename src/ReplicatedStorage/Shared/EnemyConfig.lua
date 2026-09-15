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
		MoveSpeed = 10,
		-- Seconds from the END of one attack animation to when the next may start.
		AttackCooldown = 1.6,
		Defense = 28,
		ModelName = "VoidwakenHulk",
		-- The stand-off ring he walks to (horizontal studs from the player). Kept inside every
		-- attack's TriggerRange so arriving means he can swing.
		ContactRange = 15,

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

		-- Which attack he plays is a weighted pick among the ones whose TriggerRange (horizontal studs,
		-- his root to the player) covers the current distance. The damage an attack deals is decided by
		-- which markers its animation contains, not by anything here.
		Attacks = {
			{ Name = "RockArmCombo", AnimationId = "rbxassetid://137947497885396", TriggerRange = 30, Weight = 1 },
			{ Name = "LeftSweep", AnimationId = "rbxassetid://105875185230848", TriggerRange = 30, Weight = 1 },
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

		-- Degrees added to "face the player" when an attack starts, in case the rig's front isn't the
		-- root's LookVector. Tune in Studio if he swings sideways.
		FacingYawOffset = 0,

		-- Studio aid: draws each hit's reach sphere at the fist and prints hit/miss distances to Output.
		-- Use it to check the server sees the ANIMATED fist, not the rest pose. Leave false when shipping.
		DebugHitboxes = false,
	}),
}

return EnemyConfig
