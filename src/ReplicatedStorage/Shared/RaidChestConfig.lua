--[[
	RaidChestConfig.lua
	Lootable chests in raid Combat rooms — the user's spec (DESIGN_NOTES, "Raid chests", 2026-09-22).
	Read by RaidChest.lua. Every number here is the user's or derived from their words; the comments
	say which.

	The shape of it: about half of all Combat rooms get ONE chest, placed by the game somewhere clear
	and reachable BEFORE any enemy spawns, with 1-2 guards standing by it. Hold the prompt for 3
	seconds to open it. It pays 1-5 different items through the same run-loot path every other raid
	drop uses, so whatever rules raid loot follows (what's kept on death), chest loot follows too.
]]

local RaidChestConfig = {}

-- The user's answer to "how often": about half of Combat rooms.
RaidChestConfig.ChancePerCombatRoom = 0.5

----------------------------------------------------------------------
-- Loot
----------------------------------------------------------------------

-- How many DIFFERENT items one chest gives. The user: 1-5, "the chance of having more items other
-- than 1 decreases in chance exponentially, where to get 5 different loot from the same chest is
-- around a 10% chance". Each step is ~0.74x the one before — that ratio is what lands 5 on 10%.
-- Weights, not percentages: they don't have to sum to 100.
RaidChestConfig.ItemCountWeights = {
	[1] = 33.4,
	[2] = 24.7,
	[3] = 18.3,
	[4] = 13.5,
	[5] = 10.0,
}

-- Which item each draw lands on, before amounts. Every draw is a DIFFERENT item (sampled without
-- replacement), so a 5-item chest is five distinct things. Weights per draw:
--   Scrap — "currency more than not": over half of any single draw.
--   Ores  — split by their own table below; Voidium "hella rare".
--   Cores — "really rarely".
--   Contraband — "even more rare".
-- Per single draw that comes out roughly: Scrap 55%, any ore 40%, Cores 4%, Contraband 1%, and
-- Voidium ~1.2% (40% ore x 3% of the ore table). A bigger chest draws more times, so it naturally has
-- a better shot at the rare ones — which is what a bigger chest should feel like.
RaidChestConfig.CategoryWeights = {
	Currency = 55,
	Ore = 40,
	Cores = 4,
	Contraband = 1,
}

-- "for the ores even then they will have a loottable to see which ores to give you". Keys must match
-- OreConfig.Ores exactly.
RaidChestConfig.OreWeights = {
	IronOre = 40,
	CopperOre = 30,
	GoldOre = 17,
	PlatinumOre = 10,
	VoidiumShard = 3, -- "hella rare"
}

-- Amount per item, inclusive. The user's numbers: "currency ... 70-200, rare currency ... 2-5, ores
-- 5-20". Deliberately NOT scaled by raid difficulty — these ranges are the spec.
RaidChestConfig.Amounts = {
	Currency = { Min = 70, Max = 200 }, -- Scrap
	Cores = { Min = 2, Max = 5 },
	Contraband = { Min = 2, Max = 5 },
	Ore = { Min = 5, Max = 20 },
}

-- Whether each category is LOST on a Defeat/Abandon (RaidRoomService.settleRunLoot's RunLocked tag).
-- All false today to MATCH every other raid drop — nothing in NodeConfig's loot tables is RunLocked
-- yet, and a chest that followed stricter rules than the room around it would be an odd exception.
-- When Salvage Run's "ore is lost if you die" stake is switched on, flip Ore here with it. (Scrap and
-- Cores are exempt from RunLocked regardless — see RaidRoomService.addRunReward.)
RaidChestConfig.RunLocked = {
	Ore = false,
	Contraband = false,
}

----------------------------------------------------------------------
-- Opening
----------------------------------------------------------------------

RaidChestConfig.HoldSeconds = 3 -- the user: "hold a button for 3 seconds"
RaidChestConfig.PromptDistance = 10
RaidChestConfig.ActionText = "Open"
RaidChestConfig.ObjectText = "Supply Chest"

----------------------------------------------------------------------
-- Placement — "game decides but just make sure it aint inside anything"
----------------------------------------------------------------------

-- The model: ServerStorage.RaidProps.Chest (a Model with a PrimaryPart). Optional — without it a
-- plain crate is built instead and Output says so once. If the model has a part named "Lid", opening
-- tips it back; anything else about the model is up to the art.
RaidChestConfig.ModelFolder = "RaidProps"
RaidChestConfig.ModelName = "Chest"
RaidChestConfig.LidName = "Lid"

-- The footprint the clearance check reserves (studs). Matches the placeholder crate; a real model
-- is measured instead.
RaidChestConfig.PlaceholderSize = Vector3.new(4, 3, 3)

-- Not right at the door: at least this far from the room's PlayerSpawn, so a chest is something you
-- go to, not something you trip over on entry.
RaidChestConfig.MinDistanceFromEntry = 30

-- How many random spots to try before giving up on a chest for this room. Each has to pass: a flat
-- surface under it, nothing overlapping the chest's box, and a WALKABLE path from the entry (so it
-- can't end up on a shelf, on a roof, or inside a sealed-off prop). Giving up just means no chest in
-- this room; it warns in Output so a room that can never fit one is findable.
RaidChestConfig.PlacementAttempts = 25

----------------------------------------------------------------------
-- Guards
----------------------------------------------------------------------

-- The user's answer to "how many": 1-2, on top of the room's normal enemies.
RaidChestConfig.GuardCountMin = 1
RaidChestConfig.GuardCountMax = 2

-- "make brute do it or has a chance of having any other npc around it" — and NOT the Siegebreaker,
-- "an elite unit i dont want to pop around every single time". Keys are EnemyConfig.Types keys.
RaidChestConfig.GuardTypeWeights = {
	Brute = 60,
	Raider = 20,
	Scavenger = 20,
}

-- Guards spawn in a ring this far from the chest (studs), and while unaware they only wander within
-- GuardWanderRadius of it — a Brute's normal 90-stud roam would walk it straight off its post.
RaidChestConfig.GuardRingMin = 5
RaidChestConfig.GuardRingMax = 9
RaidChestConfig.GuardWanderRadius = 8

return RaidChestConfig
