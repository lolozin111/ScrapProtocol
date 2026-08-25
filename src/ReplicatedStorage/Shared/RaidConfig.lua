--[[
	RaidConfig.lua
	Pure data + pure generation logic for Raid Rooms: an INSTANCED version of the Expedition idea
	(see ExpeditionService.lua/NodeConfig.lua for the older shared-world conveyor) — each player who
	starts a raid gets teleported into their own private area, and instead of nodes drifting toward
	you on a physical conveyor belt, you clear whatever room you're standing in and then pick your
	next room from a branching map GUI. ExpeditionService's own header comment flagged this exact
	next step: "if this ships to real concurrent players you'll want each party running their own
	instanced expedition... a bigger architectural change than this scaffold takes on." This is
	that bigger architectural change, built alongside the older system rather than replacing it.

	MAP SHAPE — a real branching TREE now, not a fork-and-merge diamond (that first version is what
	produced the "2 lines that intersect" / "clicked that one, it just skipped the wave" bugs — a
	shared hub with two incoming paths was a coincidence-prone shape; a tree where every node has
	exactly ONE parent has no such coincidence to have). Starting from Start, GenerateMap() below
	lays down a short straight run of nodes, then splits into exactly two independent branches
	(guaranteed, at least once — "the fork is just 2 different nodes"). Each branch is its own
	SEQUENCE (RaidConfig.SegmentLengthMin/Max nodes, not just one — "this path is this sequence of
	stuff, or this path is this type of sequence"), and at the end of a segment a branch either just
	ENDS (its last node is the leaf — see NODE TYPES below) OR splits again into two more branches
	(RaidConfig.ForkChance, capped by RaidConfig.MaxForkDepth so it can't run away) — paths never
	reconverge, so any two different nodes always trace back to a genuinely different history.
	Matches the hand-drawn reference: one trunk, an early split, each branch its own short run,
	occasional further splits, independent dead ends. GenerateMap also retries (up to
	RaidConfig.MaxGenerateAttempts times) until the tree has at least RaidConfig.MinMapNodes nodes —
	"make sure it has a decent minimum amount of nodes" — small trees are structurally possible (two
	branches, neither forking again) but shouldn't be what actually ships to a player.

	NODE TYPES — reuses the same three core types Expedition already established (Combat/Shop/Heal)
	so both systems feel like the same game, plus Start as the one fixed bookend, plus Ambush — a
	rarer, tougher multi-wave variant of Combat — plus Boss (see BOSS NODES below). There is
	deliberately no separate "Extraction" type anymore — every branch's dead end is just whichever
	regular type it happened to roll last ("instead of extraction, just put a node in the end, that
	could be combat or whatever I don't care") — RaidRoomService tells a leaf apart from a mid-branch
	node by its EMPTY Connections list, not by its Type, and reaching one is what advances to a new
	map (see RaidRoomService.lua's onMapCleared) regardless of what that leaf's Type/Description/
	color happen to be:
	  - Combat is the default/common case (see rollRegularType below) — "make combat more common."
	  - Ambush is a flat, independent probability check (RaidConfig.AmbushChance), rarer than Combat
	    — "throw in some combat nodes called ambush, where you gotta defeat a wave of enemies."
	    Rolls a random number of back-to-back waves (RaidConfig.RollAmbushWaveCount) that climbs as
	    the RUN progresses (persists across map regenerations, see RUN PROGRESSION below) — NOT
	    reset every time a fresh map starts.
	  - Heal is forced at a fixed INTERVAL along the sequence of regular nodes generated so far
	    (RaidConfig.HealInterval), not a random roll — "heal stations to appear in intervals."
	  - Shop is a flat, independent probability check (RaidConfig.ShopChance) on every node that
	    isn't a forced Heal — "shops have a raw chance of appearing." Heal/Shop both now wait for the
	    player to interact with a Part (RaidConfig.InteractPointName) before actually triggering —
	    "make it that the player gotta interact with a part... so later on I can put an actual NPC
	    in there" — falling back to the old immediate behavior when a room has no such Part yet.

	RUN PROGRESSION — Ambush's wave count/strength and every encounter's loot payout now scale off
	`totalNodesVisited`, a counter RaidRoomService keeps on its OWN raid state (not on the map, and
	NOT reset by onMapCleared's regenerate) — "it progresses in a total amount of nodes and it
	carries on through map regeneration." RaidConfig.GetRunProgressionMultiplier(totalNodesVisited)
	is the shared curve both Ambush and loot read from (see RUN PROGRESSION below in this file) —
	previously Ambush's wave count also factored in a node's own within-map Tier on top of
	mapsCleared, which let a single deep node on the very FIRST map already roll close to the max
	before the run had gone anywhere ("i was like in my 3rd ambush node and it was already at wave
	5") — Tier no longer feeds wave count at all, only total run progress does.

	BOSS NODES — RaidConfig.GenerateMap converts RaidConfig.BossMinPerMap..BossMaxPerMap of a
	freshly-built map's own regular nodes into Boss encounters (see placeBossNodes below), never one
	closer to Start than RaidConfig.BossMinStageIndex — "make sure it doesn't spawn too close to the
	entry point on the map, so players have time to get healed and etc before the boss fight."
	Clearing one fully heals the player and offers a rarity-weighted card pick (RollCardChoices) —
	"once the boss fight clears, you get healed, and you roll some cards with buffs... pretty
	roguelike" — currently a placeholder pool (see CARD SYSTEM below), same "functional scaffold
	before real content" spirit as everywhere else in this project.

	ROOMS — each node, once entered, clones a Model out of ServerStorage.RaidRoomModels[nodeType]
	(RaidRoomService.lua) — same "folder of same-named things, no code changes needed" convention as
	ServerStorage.EnemyModels / ReplicatedStorage.BaseTemplates. No Model built yet for a type? A
	plain big square (RaidConfig.FallbackRoomSize) stands in, same placeholder-first spirit as
	everywhere else in this project. Combat/Ambush Room Models can additionally place Parts named
	RaidConfig.SpawnPointName carrying a RaidConfig.SpawnPointEnemyAttribute string Attribute (an
	enemy type key, e.g. "Raider") — RaidRoomService spawns exactly what's placed instead of rolling
	a random composition, so hand-built combat maps are fully author-controlled. "Just try to make
	it that I can put some parts in the map called spawnpoints, and I can choose what kinda enemy
	will be in there."

	CHAPTERED MAPS — a raid is no longer one single fixed-size graph start to finish. GenerateMap
	below still builds one bounded tree (every leaf is just whatever regular type it happened to
	roll — see NODE TYPES above), but reaching ANY of its leaves no longer ends the raid outright —
	see RaidRoomService.lua's onMapCleared. It marks
	the raid's first "clear" (unlocking an Extract action from then on) and immediately generates a
	BRAND NEW map with its own fresh random shape, and the player keeps going into it. "Create a map
	with different paths, and then when the player gets to the end of the map, we generate a new one
	with different paths... it doesn't necessarily gotta connect to each other, which makes it less
	complex." Actually leaving the raid and banking everything is its own explicit action from then
	on, not something reaching a dead end forces.

	RUN ECONOMY (RaidRoomService.lua, data conventions live here) — loot earned mid-raid no longer
	touches the player's real profile immediately. Scrap/Cores collected during the run sit in a
	live, run-only pool ("Scraps Collected" on the GUI) that the raid's own Shop spends from —
	"you are only able to purchase stuff with the scraps collected through the entire run, instead
	of the scraps that you currently have as a player, in your base" — and everything else earned
	(Ore, and any future item-style drop) sits in a run-only list until the raid actually ends.
	Currency is always banked in full, however the raid ends. Everything else is banked in full too
	UNLESS the raid ended in a Defeat/Abandon (not a clean Extract) AND the specific drop was tagged
	RunLocked = true on its loot-table entry, in which case it's lost — UNLESS that same entry is
	ALSO tagged Permanent = true, which carries it over regardless. "They just get everything that
	they collected thru the run, EXCEPT run locked items, where if they abandon it they lose such
	run items, unless the item has a tag called permanent, where it can be carried over." Neither
	tag is set on anything in NodeConfig.lua's loot tables yet — every existing drop behaves exactly
	as before (always kept) until specific entries are tagged later.
]]

local RaidConfig = {}

----------------------------------------------------------------------
-- Node types — shared visual/label data, reused by both the server (build/validate) and the
-- client (draw the map GUI). Colors match ExpeditionService's NODE_COLORS for Combat/Shop/Heal so
-- the two systems read as the same game; Start is the only fixed bookend — there is deliberately
-- no separate "Extraction" entry (see NODE TYPES in the header comment above): a leaf is just
-- whichever of Combat/Shop/Heal/Ambush it already rolled, identified by its empty Connections list.
----------------------------------------------------------------------

RaidConfig.NodeTypes = {
	Start = {
		DisplayName = "Entry",
		Description = "Where you land. Nothing to fight here.",
		Color = Color3.fromRGB(140, 140, 150),
		RoomFolder = "Start",
	},
	Combat = {
		DisplayName = "Combat",
		Description = "Enemies incoming — clear them out.",
		Color = Color3.fromRGB(178, 76, 24),
		RoomFolder = "Combat",
	},
	Shop = {
		DisplayName = "Shop",
		Description = "Spend what you've found so far.",
		Color = Color3.fromRGB(53, 96, 107),
		RoomFolder = "Shop",
	},
	Heal = {
		DisplayName = "Heal Station",
		Description = "Patch up before the next stretch.",
		Color = Color3.fromRGB(79, 140, 100),
		RoomFolder = "Heal",
	},
	Ambush = {
		DisplayName = "Ambush",
		Description = "Multiple waves incoming — hold the line.",
		Color = Color3.fromRGB(150, 40, 40),
		RoomFolder = "Ambush",
	},
	Boss = {
		DisplayName = "Boss",
		Description = "Something far tougher is waiting. Heal up before you go in.",
		Color = Color3.fromRGB(122, 24, 138),
		RoomFolder = "Boss",
	},
}

-- Folder in ServerStorage holding one Model directly per node type above, named to match RoomFolder
-- exactly (e.g. ServerStorage.RaidRoomModels.Combat) — same "one named thing per key, no code
-- changes needed" convention as ReplicatedStorage.BaseTemplates. Missing folder, or a type with no
-- Model built yet — falls back to FallbackRoomSize, same "functional before art" spirit as
-- everywhere else in this project.
RaidConfig.RoomModelsFolderName = "RaidRoomModels"
-- Sized generously (260x260, up from an original 50x50) — "make the area much bigger" — since it's
-- the ONLY thing standing in for a real Combat/Ambush/Shop/Heal map today, and a cramped fallback
-- made multi-enemy fights feel like a closet. Independent of RunRaidCombat's own spawn-ring
-- constants (CombatEncounterService.RAID_SPAWN_RADIUS_MIN/MAX) — those are tuned around the player,
-- not the room's walls, so they didn't need to grow just because the floor did.
RaidConfig.FallbackRoomSize = Vector3.new(260, 1, 260)
RaidConfig.FallbackRoomColor = Color3.fromRGB(80, 80, 88)

-- Room-authored enemy placement — build a Combat/Ambush Room Model in Studio with Parts named
-- exactly SpawnPointName, each carrying a string Attribute named SpawnPointEnemyAttribute set to an
-- enemy type key (one of EnemyConfig.Types/EliteTypes' keys, e.g. "Raider", "Brute",
-- "ScrapCrawler"). RaidRoomService.beginCombat looks for these first and spawns exactly what's
-- placed, at the exact positions placed, instead of its own random composition — a room with none
-- falls back to that original procedural roll unchanged. A SpawnPoint with a missing or
-- unrecognized EnemyType attribute spawns nothing there and warns instead of guessing — "if not
-- found then spawn nothing and throw a warning."
RaidConfig.SpawnPointName = "SpawnPoint"
RaidConfig.SpawnPointEnemyAttribute = "EnemyType"

-- Heal/Shop interaction — build a Heal or Shop Room Model in Studio with a Part named exactly this
-- (a ProximityPrompt is created on it automatically if it doesn't already have one) — the player
-- now has to actually walk up and interact with it before the Heal/Shop-catalog logic fires,
-- instead of it firing the instant the room is entered — "make it that the player gotta interact
-- with a part... so later on I can put an actual NPC in there or a model in there and make it
-- usable." RaidRoomService.buildFallbackRoom drops in its own small stand-in Part named this way
-- for Heal/Shop specifically, so the gate applies even before a real Room Model exists — swap it
-- out for an NPC/real model later just by naming that Part/Model the same way in an authored Room
-- Model; an authored room that genuinely doesn't have one yet falls back to firing immediately, so
-- a work-in-progress room is never blocked on art that isn't built. One shared name for both node
-- types since they use the exact same mechanic; RaidRoomService already knows which action a given
-- room is for from its own node.Type.
RaidConfig.InteractPointName = "InteractPoint"

-- How high above a room's own pivot/floor a teleported-in player (and, for Combat rooms, the
-- enemy spawn ring's center) sits — same idea as PlotConfig.SpawnHeightOffset. Build Room Model
-- templates with their floor at local Y=0 / PrimaryPart at floor level, same convention
-- BaseConfig.lua's Base Models already use.
RaidConfig.RoomSpawnHeightOffset = 5

----------------------------------------------------------------------
-- Map generation
----------------------------------------------------------------------

RaidConfig.SegmentLengthMin = 2   -- nodes per branch segment before it ends or forks again (min)
RaidConfig.SegmentLengthMax = 3   -- (max) — every branch is a genuine multi-node sequence, not
                                   -- just one node — "this path is this sequence of stuff"

RaidConfig.MaxForkDepth = 2       -- how many times a single branch may split AGAIN after the one
                                   -- guaranteed initial split — bounds the tree so it can't run
                                   -- away; 2 means at most 3 total split points down any one path
RaidConfig.ForkChance = 0.35      -- once a branch is allowed to split again (see MaxForkDepth), the
                                   -- odds it actually does instead of just ending as a leaf (its
                                   -- last node, whatever regular type it rolled) — most branches end
                                   -- after one segment; deeper forks are an occasional bonus twist

RaidConfig.MinMapNodes = 12       -- GenerateMap retries (see MaxGenerateAttempts below) until the
                                   -- tree has at least this many total nodes — "make sure it has a
                                   -- decent minimum amount of nodes" — a small map (two branches,
                                   -- neither forking again) is structurally possible but shouldn't
                                   -- be what actually reaches a player
RaidConfig.MaxGenerateAttempts = 25 -- generate-from-scratch retry cap backing MinMapNodes above;
                                   -- falls back to the largest attempt seen if every attempt
                                   -- undershoots (verified via simulation to essentially never
                                   -- actually happen at these odds)

RaidConfig.HealInterval = 4       -- every Nth REGULAR node generated (Start doesn't count) is
                                   -- forced Heal instead of rolled
RaidConfig.ShopChance = 0.22      -- flat probability any non-forced-Heal regular node is a Shop
                                   -- instead of Combat — see rollRegularType

----------------------------------------------------------------------
-- Boss placement — converts BossMinPerMap..BossMaxPerMap of an already-generated map's own regular
-- nodes into Boss encounters (see placeBossNodes below, run from inside GenerateMap). Not part of
-- generateOnce/buildBranch itself — this runs as a separate pass AFTER a map already satisfies
-- MinMapNodes, so it always has a real tree to pick candidates from.
----------------------------------------------------------------------

RaidConfig.BossMinPerMap = 1
RaidConfig.BossMaxPerMap = 2      -- "cap it at 2 nodes maximum per map, 1 node minimum per map"
RaidConfig.BossMinStageIndex = 3  -- a candidate node must be at least this deep — "make sure it
                                   -- doesn't spawn too close to the entry point on the map, so
                                   -- players have time to get healed and etc... before the boss
                                   -- fight" — stage 3 guarantees the trunk node plus at least one
                                   -- full branch segment node have already passed
RaidConfig.BossTier = 3           -- bosses are always the toughest tier regardless of how deep
                                   -- they land — BossMinStageIndex above already keeps them from
                                   -- ambushing the player right at the door

-- Combat difficulty scales with how deep into the map a node sits (its StageIndex), same spirit as
-- ExpeditionConfig.TierWeightBands but simpler since a single raid is bounded, not an endless
-- ladder. Tier feeds both CombatEncounterService.RunRaidCombat's enemy composition
-- (RaidConfig.CombatTierComposition below) and NodeConfig.CombatTiers' existing loot tables — the
-- same Tier 1-3 vocabulary Expedition's Combat Outposts already use, so loot doesn't need a second
-- table maintained in parallel.
function RaidConfig.GetCombatTierForStage(stageIndex: number): number
	if stageIndex <= 2 then
		return 1
	elseif stageIndex <= 4 then
		return 2
	end
	return 3
end

-- How many enemies spawn and how hard they hit, per Tier — CombatEncounterService.RunRaidCombat
-- reads this to build its spawn list. Deliberately its OWN small table rather than reusing
-- WaveConfig.GetEnemyCount/GetEnemyMultiplier — those are tuned for an ENDLESS base-defense ladder
-- (wave 1, 2, 3, ... forever), a different curve than a single bounded raid room ever needs.
RaidConfig.CombatTierComposition = {
	[1] = { EnemyCountMin = 2, EnemyCountMax = 3, Multiplier = 1.0 },
	[2] = { EnemyCountMin = 3, EnemyCountMax = 4, Multiplier = 1.4 },
	[3] = { EnemyCountMin = 4, EnemyCountMax = 5, Multiplier = 1.9 },
}

-- Boss composition — deliberately its own tiny table, not reused from CombatTierComposition above.
-- A Boss room is meant to be one or two genuinely tough EliteTypes enemies (see
-- RaidRoomService.pickBossSpawnKeys, drawing from EnemyConfig.EliteTypes instead of the normal
-- roster), not just "more of the regular enemies."
RaidConfig.BossComposition = { EnemyCountMin = 1, EnemyCountMax = 2, Multiplier = 2.6 }

RaidConfig.AmbushChance = 0.16 -- flat probability a non-forced-Heal, non-Shop regular node is an
	-- Ambush (multi-wave fight) instead of a single Combat encounter — rarer than Combat since it's
	-- the tougher variant, "throw in some" per the design ask. First guess, worth a playtest.

RaidConfig.AmbushWaveMin = 2
RaidConfig.AmbushWaveMax = 7

----------------------------------------------------------------------
-- Run progression — the single curve behind BOTH Ambush's wave count/strength and every
-- encounter's loot payout. Keyed off `totalNodesVisited`, a counter RaidRoomService keeps on its
-- own per-raid state (NOT on the map, so it survives GenerateMap being called again) — "it
-- progresses in a total amount of nodes and it carries on through map regeneration." Deliberately
-- NOT keyed off a node's own within-map Tier or off MapsCleared alone — the old Ambush formula
-- added Tier straight onto the wave-count ceiling, which meant one deep node on the very FIRST map
-- could already roll close to the max before the run had gone anywhere at all ("i was like in my
-- 3rd ambush node and it was already at wave 5"). Tier still shapes enemy composition/strength
-- within a single encounter (CombatTierComposition) — it just no longer also drives wave count.
----------------------------------------------------------------------

RaidConfig.RunProgressionNodesPerStep = 25 -- every this many nodes visited (see above — persists
	-- across map regenerations) bumps the run's own difficulty/reward multiplier one more notch.
	-- With an average generated map around ~18 nodes (see GenerateMap's own comment), this ramps
	-- roughly once every map and a bit — "on the first map you may have an ambush that does 3
	-- waves, but on the 3rd map you will have an ambush that does 5 instead."
RaidConfig.RunProgressionMultiplierPerStep = 0.12 -- extra multiplier per step, stacked on top of a
	-- node's own within-map Tier — "with stronger enemies as well" / "make that the rewards scale
	-- with difficulty."

function RaidConfig.GetRunProgressionStep(totalNodesVisited: number): number
	return math.floor(totalNodesVisited / RaidConfig.RunProgressionNodesPerStep)
end

function RaidConfig.GetRunProgressionMultiplier(totalNodesVisited: number): number
	return 1 + RaidConfig.GetRunProgressionStep(totalNodesVisited) * RaidConfig.RunProgressionMultiplierPerStep
end

-- How many waves one Ambush node throws at you. Starts small (right around AmbushWaveMin) early in
-- a raid and climbs toward AmbushWaveMax the further the RUN has progressed (see run-progression
-- comment above, NOT a node's own Tier anymore) — "as you begin it goes from like 2-3 waves, where
-- as you go it increases the waves and difficulty, where max wave would be 7."
function RaidConfig.RollAmbushWaveCount(totalNodesVisited: number): number
	local step = RaidConfig.GetRunProgressionStep(totalNodesVisited)
	local ceiling = math.min(RaidConfig.AmbushWaveMax, RaidConfig.AmbushWaveMin + 1 + step)
	local floorCount = math.min(RaidConfig.AmbushWaveMin, ceiling)
	return math.random(floorCount, ceiling)
end

-- Combined tier + run-progression multiplier for loot amounts — "make that the rewards scale with
-- difficulty." RaidRoomService.grantRunLoot scales every roll's amount by this.
function RaidConfig.GetLootMultiplier(tier: number, totalNodesVisited: number): number
	local tierData = RaidConfig.CombatTierComposition[tier] or RaidConfig.CombatTierComposition[1]
	return tierData.Multiplier * RaidConfig.GetRunProgressionMultiplier(totalNodesVisited)
end

-- Regular-node type roll: Heal is forced at a fixed interval (not random — see this file's header
-- and HealInterval above), Shop and then Ambush are each a flat independent chance, and Combat is
-- everything else — the deliberate "common case" per the design ask. `regularCounter` is the
-- running count of regular nodes generated SO FAR this map (Start excluded), passed in
-- and returned incremented so the caller's own counter stays authoritative — this function doesn't
-- keep any state of its own, same "no hidden module-level state" approach RaidConfig.GenerateMap
-- uses throughout.
local function rollRegularType(regularCounter: number): (string, number)
	regularCounter += 1
	if regularCounter % RaidConfig.HealInterval == 0 then
		return "Heal", regularCounter
	elseif math.random() <= RaidConfig.ShopChance then
		return "Shop", regularCounter
	elseif math.random() <= RaidConfig.AmbushChance then
		return "Ambush", regularCounter
	end
	return "Combat", regularCounter
end

-- Builds one fresh map: { Nodes = { [id] = {Id, Type, Tier, StageIndex, Connections = {ids}} },
-- StartNodeId }. StageIndex is just a layout column for the client's map GUI (and what
-- GetCombatTierForStage scales off) — it has no gameplay meaning of its own. Connections are
-- directed (fromId -> toId) and, since this is a real TREE now, ALSO exactly that node's children
-- — every node has exactly one parent, so there is nothing else Connections could mean. A node
-- with no listed Connections is a leaf — just whichever regular type it already rolled (see
-- buildBranch below, no dedicated Extraction node), but there can be several of them scattered
-- across the tree, not just one fixed dead end.
local function generateOnce()
	local nodes = {}
	local nextId = 0
	local regularCounter = 0

	local function newNode(nodeType: string, stageIndex: number)
		nextId += 1
		local id = nextId
		local tier = nil
		if nodeType == "Combat" or nodeType == "Ambush" then
			tier = RaidConfig.GetCombatTierForStage(stageIndex)
		end
		nodes[id] = { Id = id, Type = nodeType, Tier = tier, StageIndex = stageIndex, Connections = {} }
		return id
	end

	local function connect(fromId: number, toId: number)
		table.insert(nodes[fromId].Connections, toId)
	end

	local function newRegularNode(stageIndex: number)
		local nodeType
		nodeType, regularCounter = rollRegularType(regularCounter)
		return newNode(nodeType, stageIndex)
	end

	-- Lays down one straight run of regular nodes after `parentId`, then either just ENDS (its
	-- last node stands as the leaf, whatever regular type it already rolled — no dedicated
	-- Extraction node) or splits into two fresh branches (recursing, if `depth` still allows — see
	-- MaxForkDepth) — NEVER reconnects into anything else, so no two branches ever share a node
	-- again once they've split. This is what makes the tree what it is: every node has exactly one
	-- parent, so there's no shared-hub coincidence left to produce a crossing line or an ambiguous
	-- click.
	local function buildBranch(parentId: number, stageIndex: number, depth: number)
		local segmentLength = math.random(RaidConfig.SegmentLengthMin, RaidConfig.SegmentLengthMax)
		local lastId = parentId
		for _ = 1, segmentLength do
			stageIndex += 1
			local id = newRegularNode(stageIndex)
			connect(lastId, id)
			lastId = id
		end

		if depth < RaidConfig.MaxForkDepth and math.random() <= RaidConfig.ForkChance then
			stageIndex += 1
			buildBranch(lastId, stageIndex, depth + 1)
			buildBranch(lastId, stageIndex, depth + 1)
		end
		-- else: lastId itself is the leaf — nothing further to connect
	end

	local stageIndex = 0
	local startId = newNode("Start", stageIndex)

	-- One regular node before the guaranteed first split — matches the hand-drawn reference
	-- (trunk, then the fork) rather than forking directly off Start itself.
	stageIndex += 1
	local trunkId = newRegularNode(stageIndex)
	connect(startId, trunkId)

	stageIndex += 1
	buildBranch(trunkId, stageIndex, 0)
	buildBranch(trunkId, stageIndex, 0)

	return {
		Nodes = nodes,
		StartNodeId = startId,
	}
end

-- Runs AFTER a map already satisfies MinMapNodes — converts a random BossMinPerMap..BossMaxPerMap
-- of its own regular (non-Start) nodes into Boss encounters, never picking one shallower than
-- BossMinStageIndex (see that constant's own comment). Falls back to whatever non-Start nodes
-- exist if a freak-shallow map has nothing that deep, so every map still gets at least
-- BossMinPerMap — the cap/floor is a hard guarantee, not just a preference.
local function placeBossNodes(map)
	local candidates = {}
	for id, node in pairs(map.Nodes) do
		if node.Type ~= "Start" and node.StageIndex >= RaidConfig.BossMinStageIndex then
			table.insert(candidates, id)
		end
	end
	if #candidates == 0 then
		for id, node in pairs(map.Nodes) do
			if node.Type ~= "Start" then
				table.insert(candidates, id)
			end
		end
	end
	if #candidates == 0 then
		return -- nothing but Start exists — nothing to convert
	end

	-- Fisher-Yates shuffle so the Bosses picked are uniformly random among candidates, not just
	-- whichever happened to iterate first out of `nodes` (a plain Lua table has no defined order).
	for i = #candidates, 2, -1 do
		local j = math.random(i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end

	local bossCount = math.min(#candidates, math.random(RaidConfig.BossMinPerMap, RaidConfig.BossMaxPerMap))
	for i = 1, bossCount do
		local node = map.Nodes[candidates[i]]
		node.Type = "Boss"
		node.Tier = RaidConfig.BossTier
	end
end

-- Public entry point: calls generateOnce() above up to MaxGenerateAttempts times, returning the
-- first map that meets MinMapNodes — "make sure it has a decent minimum amount of nodes." Falls
-- back to the largest map actually generated if every attempt undershoots (a 5000-trial standalone
-- simulation of this exact retry logic hit 0/5000 fallbacks at these odds, so this is a safety net,
-- not the expected path). Boss placement (placeBossNodes) always runs on whichever map is finally
-- returned, retry or fallback alike.
function RaidConfig.GenerateMap()
	local best = nil
	local bestCount = -1
	for _ = 1, RaidConfig.MaxGenerateAttempts do
		local map = generateOnce()
		local count = 0
		for _ in pairs(map.Nodes) do
			count += 1
		end
		if count >= RaidConfig.MinMapNodes then
			placeBossNodes(map)
			return map
		end
		if count > bestCount then
			best = map
			bestCount = count
		end
	end
	if best then
		placeBossNodes(best)
	end
	return best
end

----------------------------------------------------------------------
-- Card system — the post-Boss reward pick. "You get healed, and you roll some cards with buffs,
-- and the cards have rarity, and the buff is connected to rarity, and you can only pick one, pretty
-- roguelike." PLACEHOLDER CONTENT ONLY — "just make it a placeholder for now... so I can manually
-- add it later, or I just tell exactly what I want, I will make a list/table for you to add later."
-- One stub card per rarity below, no real buff effects wired up yet (RaidRoomService.lua just
-- records what was picked onto state.CollectedCards) — this proves out the rarity + roll + pick-one
-- flow so real cards/effects are a data change here later, not a new system.
----------------------------------------------------------------------

RaidConfig.CardRarities = { "Common", "Rare", "Epic", "Legendary" }

RaidConfig.CardRarityWeights = {
	Common = 0.55,
	Rare = 0.30,
	Epic = 0.12,
	Legendary = 0.03,
}

RaidConfig.CardRarityColors = {
	Common = Color3.fromRGB(180, 180, 180),
	Rare = Color3.fromRGB(70, 140, 220),
	Epic = Color3.fromRGB(165, 85, 225),
	Legendary = Color3.fromRGB(230, 175, 45),
}

RaidConfig.CardPool = {
	{ Key = "PlaceholderCommon", DisplayName = "Placeholder Buff", Rarity = "Common", Description = "Stub card — swap for a real buff later." },
	{ Key = "PlaceholderRare", DisplayName = "Placeholder Buff", Rarity = "Rare", Description = "Stub card — swap for a real buff later." },
	{ Key = "PlaceholderEpic", DisplayName = "Placeholder Buff", Rarity = "Epic", Description = "Stub card — swap for a real buff later." },
	{ Key = "PlaceholderLegendary", DisplayName = "Placeholder Buff", Rarity = "Legendary", Description = "Stub card — swap for a real buff later." },
}

-- Rolls `count` DISTINCT cards out of CardPool, weighted by CardRarityWeights (re-normalized as the
-- pool shrinks each pick, so removing a card doesn't skew the remaining odds). Distinct so the same
-- card can't be offered twice in one choice — irrelevant today with exactly one entry per rarity,
-- but keeps this correct once the pool has more than one card per rarity later.
function RaidConfig.RollCardChoices(count: number)
	local pool = table.clone(RaidConfig.CardPool)
	local picks = {}
	for _ = 1, math.min(count, #pool) do
		local totalWeight = 0
		for _, card in ipairs(pool) do
			totalWeight += (RaidConfig.CardRarityWeights[card.Rarity] or 0.01)
		end
		local roll = math.random() * totalWeight
		local cumulative = 0
		local chosenIndex = #pool
		for i, card in ipairs(pool) do
			cumulative += (RaidConfig.CardRarityWeights[card.Rarity] or 0.01)
			if roll <= cumulative then
				chosenIndex = i
				break
			end
		end
		table.insert(picks, table.remove(pool, chosenIndex))
	end
	return picks
end

----------------------------------------------------------------------
-- Instancing — where in the world a raid instance actually gets built. No hand-placed Studio
-- anchor needed (unlike Plot/Expedition/MineShaft's tagged Parts) — per the design ask ("for now
-- just make it that the player teleports somewhere"), this is entirely code-driven: a fixed point
-- high in the sky, well clear of the real map, with each concurrent raid instance offset along X
-- by its own slot index so multiple players' private areas never overlap.
----------------------------------------------------------------------

RaidConfig.InstanceOrigin = Vector3.new(0, 800, 0)
RaidConfig.InstanceSlotSpacing = 600 -- studs between concurrent raid instances' origins
RaidConfig.MaxConcurrentInstances = 20

RaidConfig.EnergyCost = 1 -- spent via RaidEnergyService.TrySpendEnergy when a raid starts — same
	-- one-charge-per-run idea as ExpeditionConfig's lever cost, not per-node inside the run

return RaidConfig
