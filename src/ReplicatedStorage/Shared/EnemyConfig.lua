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
-- enemies. VoidwakenHulk's flavor plants the seed for a future "boss-only drop" reward hook (see
-- DESIGN_NOTES.md's Base Defense / Research Level notes) — that drop itself isn't built yet,
-- deliberately deferred to whenever Research Level ships.
EnemyConfig.EliteTypes = {
	VoidwakenHulk = defineEnemy(ConstructBase, {
		DisplayName = "Voidwaken Hulk",
		Description = "Whatever Voidium did to this one, it didn't make it slower.",
		HP = 220,
		ContactDamage = 22,
		MoveSpeed = 10,
		AttackCooldown = 1.6,
		Defense = 28,
		ModelName = "VoidwakenHulk",
	}),
}

return EnemyConfig
