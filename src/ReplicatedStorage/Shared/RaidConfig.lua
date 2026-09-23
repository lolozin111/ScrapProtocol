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
	ServerStorage.EnemyModels / ReplicatedStorage.BaseTemplates. That entry may also be a FOLDER of
	Models, in which case one is picked at random per node (see RoomModelsFolderName below). No Model
	built yet for a type? A
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

-- Folder in ServerStorage holding one entry per node type above, named to match RoomFolder exactly
-- (e.g. ServerStorage.RaidRoomModels.Combat) — same "one named thing per key, no code changes
-- needed" convention as ReplicatedStorage.BaseTemplates. Missing folder, or a type with no Model
-- built yet — falls back to FallbackRoomSize, same "functional before art" spirit as everywhere
-- else in this project.
--
-- That entry may be EITHER a Model (used directly) OR a Folder of Models, in which case it is a
-- VARIANT SET and one child is picked at random per node — so a fifteen-node map stops walking
-- through the identical box a dozen times, and adding variety becomes another small Studio job
-- rather than one big one. Purely additive: a single Model entry behaves exactly as it always has.
-- Every variant still needs its own PrimaryPart; ones without are skipped and warned about by name
-- (RaidRoomService.pickRoomTemplate) rather than intermittently dropping a run into the placeholder.
RaidConfig.RoomModelsFolderName = "RaidRoomModels"
-- Sized generously (260x260, up from an original 50x50) — "make the area much bigger" — since it's
-- the ONLY thing standing in for a real Combat/Ambush/Shop/Heal map today, and a cramped fallback
-- made multi-enemy fights feel like a closet. Independent of RunRaidCombat's own spawn-ring
-- constants (CombatEncounterService.RAID_SPAWN_RADIUS_MIN/MAX) — those are tuned around the player,
-- not the room's walls, so they didn't need to grow just because the floor did.
RaidConfig.FallbackRoomSize = Vector3.new(260, 1, 260)
RaidConfig.FallbackRoomColor = Color3.fromRGB(80, 80, 88)

-- Player spawn marker — build a Part named exactly this in a Room Model and the player is placed
-- there on entering that room, pivoted to the Part's full CFrame — so it sets FACING DIRECTION as
-- well as position, which the previous behaviour could not express at all. Absent, the player
-- falls back to origin + RoomSpawnHeightOffset on Y, i.e. the model's own pivot, dead centre —
-- unchanged, so every room already built keeps working. That pivot-centre default was invisible
-- while every room was the 260x260 placeholder square, but rooms are constrained on X only
-- (600-stud slot spacing) and therefore grow long on Z, at which point "dead centre" drops the
-- player in the middle of the level with half of it behind them. Only the first one found is
-- used; more than one warns.
RaidConfig.PlayerSpawnName = "PlayerSpawn"

-- Room-authored enemy placement — build a Combat/Ambush Room Model in Studio with Parts named
-- exactly SpawnPointName, each carrying a string Attribute named SpawnPointEnemyAttribute set to an
-- enemy type key (one of EnemyConfig.Types/EliteTypes/BossTypes' keys, e.g. "Raider", "Brute",
-- "ScrapCrawler"). RaidRoomService.beginCombat looks for these first and spawns exactly what's
-- placed, at the exact positions placed, instead of its own random composition — a room with none
-- falls back to that original procedural roll unchanged. A SpawnPoint with a missing or
-- unrecognized EnemyType attribute spawns nothing there and warns instead of guessing — "if not
-- found then spawn nothing and throw a warning."
RaidConfig.SpawnPointName = "SpawnPoint"
RaidConfig.SpawnPointEnemyAttribute = "EnemyType"

-- Room-authored spawn volumes — build a Part named exactly SpawnZoneName in a Room Model and it
-- defines a VOLUME, not a point: the Part's own Size and CFrame describe a box, and enemies appear
-- at random points inside it. Because placement works in the part's OBJECT space, a rotated zone
-- works exactly as drawn. SpawnZoneWeightAttribute is an optional NUMBER attribute on the zone
-- (absent, or non-positive, means 1) giving that zone's share of the room's spawns — a big arena at
-- 3 catches three times what a side alcove at 1 does. Weight is the one thing the geometry knows
-- that config cannot. A zone deliberately says WHERE, never WHAT. There is no per-zone enemy-type
-- filter, and that was decided rather than skipped: putting composition in this table AND in every
-- room model is the two-places-that-drift failure this codebase keeps having (OreGate,
-- ModConfig.ApplyMods and CraftingRecipes.MaxDeployedRobots all exist because of it). Zones and
-- SpawnPoints COEXIST in one room: authored points spawn first and count against the room's enemy
-- budget, zones fill whatever remains. That is what lets one pinned set piece sit inside a rolled
-- encounter without a second system. Boss rooms use POINTS ONLY: beginBoss calls collectSpawnPoints
-- directly rather than resolveEnemyPlacements, because a zone-filled enemy there would inherit
-- BossComposition.Multiplier and every zone-added body would be an elite one. A SpawnZone in a Boss
-- room is therefore inert by design until the escort build lands.
-- SpawnZoneMinPlayerDistance (studs) keeps an enemy from materialising in the player's face;
-- SpawnZoneFloorOffset (studs) is how far above the floor the raycast result is nudged so nothing
-- spawns embedded in geometry; SpawnZoneMaxPlacementAttempts is how many times one enemy's
-- placement is retried before it is skipped with a warn; SpawnZoneRaycastExtraDepth (studs) is how
-- far BELOW the zone's own bottom face the downward floor raycast keeps searching, so a zone
-- floating above a stepped floor still finds ground. Note that RaidRoomService force-sets
-- Transparency 1 / CanCollide false / CanQuery false on every zone at build time, so the author
-- leaves it bright and visible in Studio and it disappears in game — and CanQuery false is not
-- cosmetic: an invisible query-able volume in front of the player is exactly the "I click and
-- nothing happens" bug CLAUDE.md documents, and it also conveniently keeps zones out of the floor
-- raycast. A Combat/Ambush room with neither a SpawnZone nor a SpawnPoint warns (naming the room)
-- and falls back to the original procedural circle-around-centre spawn, unchanged — the fallback
-- keeps the run alive, the warn is what makes a half-authored room findable instead of quietly
-- wrong.
RaidConfig.SpawnZoneName = "SpawnZone"
RaidConfig.SpawnZoneWeightAttribute = "Weight"
RaidConfig.SpawnZoneMinPlayerDistance = 25
RaidConfig.SpawnZoneFloorOffset = 3
RaidConfig.SpawnZoneMaxPlacementAttempts = 12
RaidConfig.SpawnZoneRaycastExtraDepth = 200
-- Boss escort, Decision 5: when placing escort minions, a candidate must also be at least this far
-- from every spawn already placed in the room (the boss's SpawnPoint and earlier minions), so a
-- zone overlapping the arena can't drop a minion inside the boss, and minions don't pile up.
RaidConfig.SpawnZoneMinSpawnDistance = 20

-- Heal/Shop interaction — build a Heal or Shop Room Model in Studio with a Part named exactly this
-- (a ProximityPrompt is created on it automatically if it doesn't already have one) — the player
-- now has to actually walk up and interact with it before the Heal/Shop-catalog logic fires,
-- instead of it firing the instant the room is entered — "make it that the player gotta interact
-- with a part... so later on I can put an actual NPC in there or a model in there and make it
-- usable." RaidRoomService.buildFallbackRoom drops in its own small stand-in Part named this way
-- for Heal/Shop specifically, so the gate applies even before a real Room Model exists — swap it
-- out for an NPC/real machine later by putting a BasePart named this way in an authored Room Model
-- at the NPC's feet (Transparency 1 / CanCollide false if the visual is the NPC itself). It must be
-- a BASEPART and a DIRECT CHILD of the Room Model: beginInteractGated uses FindFirstChild plus an
-- IsA("BasePart") test, NOT the GetDescendants sweep SpawnPointName/SpawnZoneName/PlayerSpawnName
-- all use — so a Model named this, or a Part nested one Folder deep, is not found and the room
-- fires immediately with no warn. An authored room that genuinely doesn't have one yet falls back
-- to firing immediately too, so
-- a work-in-progress room is never blocked on art that isn't built. One shared name for both node
-- types since they use the exact same mechanic; RaidRoomService already knows which action a given
-- room is for from its own node.Type.
RaidConfig.InteractPointName = "InteractPoint"

-- Exit doors — the PHYSICAL replacement for clicking a circle on the map GUI. A cleared room
-- unlocks one door per branch out of the current node; walking through one fires the same
-- ChooseRaidNode remote the map circles used to fire, so the server-side legality check
-- (is this node actually a child of where I am?) is completely unchanged — only the input moved.
--
-- HOW TO BUILD ONE: put Parts named exactly ExitDoorName in the Room Model, one per branch the
-- room could offer. Two is enough for every map RaidConfig.GenerateMap can produce today (a fork
-- splits in two and never more), but building three is harmless — extras stay sealed.
--
-- ORDERING is what decides which door leads where. Set a NUMBER attribute named
-- ExitDoorIndexAttribute on each (1, 2, 3...) and doors sort by it. Leave them all unset and they
-- sort by world X instead, so a plain left/right pair needs no attributes at all — the leftmost
-- door is branch 1. Mixed (some set, some not) puts the numbered ones first, in order.
--
-- TOO FEW DOORS for the branches on offer is NOT an error the player ever sees: RaidRoomService
-- warns and re-opens the clickable map GUI for that one node instead. Same missing-art rule
-- the rest of the project follows, applied to geometry — a half-built room must never be able to
-- strand a run with no way forward. (Moot while ExitDoorsEnabled is false, since the map is then
-- the input for every node, but it is the safety net the moment doors are switched back on.)
RaidConfig.ExitDoorName = "ExitDoor"
RaidConfig.ExitDoorIndexAttribute = "ExitIndex"

-- MASTER SWITCH for the whole physical-door mechanic, and currently OFF (user's call, 2026-09-09).
--
-- Navigation went back to picking the next room on the Sector Map — the map reads better and fits
-- the flow of the game — which reverses "Decision 2 — the map choice comes off the screen" in
-- DESIGN_NOTES. Everything the door path needs is still here and still correct; this flag is the
-- only thing standing between the two designs, so going back is a one-word edit rather than a
-- rewrite. That is why unlockExitDoors and its label/prompt/Touched machinery were left intact in
-- RaidRoomService rather than deleted.
--
-- With this false, RaidRoomService.showMapChoice skips unlockExitDoors entirely and always sends
-- AllowNodeClick = true, so the map circles are the input. Doors authored into a room Model are NOT
-- removed and NOT ignored — sealExitDoors still runs on every node entry, which leaves them solid
-- but invisible (ExitDoorSealedTransparency). Solid matters: a doorway that stopped blocking would
-- let a player walk out of a room mid-fight into open sky. So an authored room keeps its geometry
-- and simply never shows a door as a usable exit.
RaidConfig.ExitDoorsEnabled = false

-- Walk through, don't press a button — "to choose where to go is gonna be a physical thing." A
-- sealed door is solid; an unlocked one drops CanCollide and you pass straight through it. Flip
-- ExitDoorUseProximityPrompt to true if playtesting says a walk-through triggers too easily (a
-- door placed near an authored room's spawn point is the risk) — RaidRoomService implements both
-- paths, so this is a config flip rather than a code change.
RaidConfig.ExitDoorUseProximityPrompt = false
RaidConfig.ExitDoorPromptDistance = 12

-- Sealed vs. unlocked appearance. An unlocked door takes its DESTINATION node type's own
-- NodeTypes.Color (so a Combat door is the same orange as the Combat circle on the map, and the
-- player learns one colour language for both), goes Neon and semi-transparent, and floats a label
-- with that type's DisplayName. A sealed one is inert dark metal with no label at all.
RaidConfig.ExitDoorSealedColor = Color3.fromRGB(28, 26, 24)

-- A sealed door is INVISIBLE by default, not a dark slab — "only make the doors appear once the room
-- is done and the player can actually go somewhere else." It stays SOLID while invisible, which is
-- the point: a door you could walk through mid-fight would drop you out of the room into open sky at
-- Y = 800. So during combat the doorway reads as an opening you cannot pass, and the moment the
-- encounter resolves the door lights up in its destination's colour.
--
-- Set this back to 0 to restore the original dark-slate slab — ExitDoorSealedColor and the Slate
-- material are still applied underneath, so that is a one-number revert rather than a code change.
-- Anything between (0.85, say) gives a faint hint of a door instead of nothing at all, if playtesting
-- says an invisible blocker reads as a bug. Note a room is free to build its own visible shutter
-- geometry in the frame either way: only the Part NAMED ExitDoorName is ever restyled by
-- RaidRoomService, so a sibling model beside it is left completely alone.
RaidConfig.ExitDoorSealedTransparency = 1
RaidConfig.ExitDoorUnlockedTransparency = 0.4
RaidConfig.ExitDoorLabelHeightOffset = 4 -- studs above the door's top face the label floats

-- Doors the fallback room grows for itself, exactly like the InteractPoint stand-in above, so
-- physical exits work before a single Room Model has been built in Studio. Three of them, evenly
-- spread along one edge, inset from the guard rail — one more than any map can currently use, so
-- the "extras stay sealed" path gets exercised every raid rather than only in authored rooms.
RaidConfig.FallbackExitDoorCount = 3
RaidConfig.FallbackExitDoorSize = Vector3.new(16, 18, 2)
RaidConfig.FallbackExitDoorInset = 10 -- studs in from the room edge, clear of the guard rail

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
--
-- EliteChance is the per-ROOM probability that one of the rolled enemies is swapped for an
-- EnemyConfig.EliteTypes pick (RaidRoomService.pickRaidSpawnKeys) rather than a normal-roster one.
-- Three things about it are deliberate:
--
--   1. It SUBSTITUTES, it does not add. Base defense's elite wave adds one extra unit on top of the
--      normal count (CombatEncounterService.pickSpawnKeys) because a wave is 8+ enemies and one more
--      barely moves the count. A raid room is 2-5, so adding a 140 HP / 45 Defense slam unit on top
--      would be a far bigger spike than the same line of code means in a wave. Substituting keeps
--      `count` honest as the room's enemy budget — which resolveEnemyPlacements also relies on to
--      know how many zone-filled positions to top authored SpawnPoints up to.
--   2. At most one per room, by construction — it is a single roll that replaces a single slot.
--   3. Tier 1 is zero. The first two stages of a map should stay legible while a player is still
--      reading the room, and GetCombatTierForStage puts stages 1-2 in Tier 1.
--
-- Rooms that author their own composition via SpawnPointName Parts are untouched by this: they
-- already say exactly what they want, elites included (see SpawnPointEnemyAttribute above, which
-- accepts EliteTypes keys). Ambush nodes deliberately pass 0 — see beginAmbush.
--
-- Numbers are a first guess, unplaytested.
RaidConfig.CombatTierComposition = {
	[1] = { EnemyCountMin = 2, EnemyCountMax = 3, Multiplier = 1.0, EliteChance = 0 },
	[2] = { EnemyCountMin = 3, EnemyCountMax = 4, Multiplier = 1.4, EliteChance = 0.20 },
	[3] = { EnemyCountMin = 4, EnemyCountMax = 5, Multiplier = 1.9, EliteChance = 0.35 },
}

-- Boss composition — deliberately its own tiny table, not reused from CombatTierComposition above.
-- A Boss room is meant to be one or two genuinely tough BossTypes enemies (see
-- RaidRoomService.pickBossSpawnKeys, drawing from EnemyConfig.BossTypes, which is boss-only and
-- read from nowhere else), not just "more of the regular enemies."
-- Exactly one since the Boss escort build (DESIGN_NOTES "Boss escort", Decision 2): the boss is a
-- single set-piece, authored as ONE SpawnPoint, and extra bodies come from the escort below instead.
RaidConfig.BossComposition = { EnemyCountMin = 1, EnemyCountMax = 1, Multiplier = 2.6 }

-- Boss escort ("Boss escort" Decisions 3-4). Minions stand in the Boss room's SpawnZones:
--   minions = max(0, floor(combatCount * BossMinionFraction) - 1)
-- combatCount is a Combat room's enemy roll at the boss node's tier (CombatTierComposition), standing
-- in for the unbuilt depth-based quantity curve. The -1 is STRUCTURAL (it's what gives shallow boss
-- rooms no escort once a real curve exists), not a knob. Minions draw from the normal roster with no
-- elites, at that Combat tier's strength, never the boss's 2.6x. This fraction is the one number to
-- move in playtesting. At Tier 3 (4-5 enemies) it currently gives 1-2 minions.
RaidConfig.BossMinionFraction = 0.6

RaidConfig.AmbushChance = 0.16 -- flat probability a non-forced-Heal, non-Shop regular node is an
	-- Ambush (multi-wave fight) instead of a single Combat encounter — rarer than Combat since it's
	-- the tougher variant, "throw in some" per the design ask. First guess, worth a playtest.

RaidConfig.AmbushWaveMin = 2
RaidConfig.AmbushWaveMax = 8 -- soft cap on how deep a run can push Ambush length (user's call,
	-- 2026-09-09). RollAmbushWaveCount climbs toward this with run depth and never exceeds it.

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

-- Ceiling on the ladder above: 250 nodes visited, a 2.2x run multiplier. Added 2026-09-23 after the
-- exploit review found this ladder uncapped, which let a raid that never ends pay without limit.
-- The cap belongs on the MULTIPLIER rather than on the run's length because the run is meant to be
-- open-ended — "pushing deeper stays survivable" — it just must not keep paying more forever.
-- Step 10 is already far past any honest run.
RaidConfig.RunProgressionMaxStep = 10

function RaidConfig.GetRunProgressionStep(totalNodesVisited: number): number
	return math.min(
		RaidConfig.RunProgressionMaxStep,
		math.floor(totalNodesVisited / RaidConfig.RunProgressionNodesPerStep))
end

function RaidConfig.GetRunProgressionMultiplier(totalNodesVisited: number): number
	return 1 + RaidConfig.GetRunProgressionStep(totalNodesVisited) * RaidConfig.RunProgressionMultiplierPerStep
end

-- Extra ENEMIES a Combat room adds on top of its Tier's own count, as the run goes deeper.
--
-- The complaint this answers is on record in DESIGN_NOTES ("deep raids are five enemies with
-- ever-larger health bars"): CombatTierComposition tops count out at 5 forever, keyed off a node's
-- within-map Tier, which resets every map chapter — so the only thing that ever grew was how much
-- health each of those five had. A strength multiplier alone makes that worse, not better.
--
-- Deliberately smaller and flatter than the strength ladder: +1 enemy every two progression steps
-- (50 nodes), capped at +3, so a very deep Tier 3 room is 7-8 enemies rather than 4-5. This is the
-- modest version of the spawn-ZONE proposal in DESIGN_NOTES, not that proposal — it reuses the
-- existing count roll instead of replacing fixed spawn points with volumes. A room authored with
-- SpawnZones picks the extra bodies up automatically (resolveEnemyPlacements tops authored
-- SpawnPoints up to `count` from its zones); a room built with ONLY fixed SpawnPoints and no zone
-- still can't grow, which is exactly the limitation that redesign exists to remove.
RaidConfig.RunProgressionCountPerStep = 0.5
RaidConfig.RunProgressionMaxExtraEnemies = 3

----------------------------------------------------------------------
-- AUTO-ADVANCE — a fork with only one branch isn't a choice
--
-- When the current node leads to exactly one next node, opening the Sector Map to ask "which of
-- these one things do you want" is a click that carries no decision. The run moves on by itself
-- instead, after a beat long enough to read as travelling rather than teleporting.
--
-- BlockedTypes are the rooms you must be allowed to LEAVE on your own terms. A Shop is somewhere
-- you stand and think, and being yanked out of it the moment you press Continue is the opposite of
-- what that room is for; a Heal has the same shape. Both already wait on an explicit Continue, so
-- honouring that and then still showing the map keeps leaving a deliberate act. Every other room
-- type resolves on its own and has nothing left to hold you there.
----------------------------------------------------------------------

RaidConfig.AutoAdvanceSeconds = 1.2 -- how long the travel transition holds before the next room
	-- builds. Long enough to register as a move; short enough that a corridor of single-exit rooms
	-- doesn't turn into a slideshow. The client plays its wipe over exactly this window, so the two
	-- read this same number rather than each keeping their own copy.
RaidConfig.AutoAdvanceBlockedTypes = { Shop = true, Heal = true }

-- Which room type every first-pickable node becomes for a player holding the dev shortcuts, so a
-- room you want to test is one raid away instead of however many the map RNG takes to hand you one.
-- Any key of NodeTypes; set it to nil to leave the generated map alone. It was hard-coded to "Boss"
-- when this shortcut only existed to reach the boss card pick — a config key now, because the
-- answer to "which room am I testing today" changes more often than the code around it does.
-- Applied at raid start only, NOT when a cleared map regenerates: the point is a fast way IN to a
-- room type, not a run made entirely of it.
RaidConfig.DevFirstNodeType = "Shop"

-- How long a clean Extract will hold the player in the raid room waiting for them to dismiss the
-- end-of-run summary before sending them home anyway. Purely a safety net — the Continue button is
-- the intended exit — but without it an alt-tabbed or disconnected-looking player would sit in a
-- finished raid forever, still holding their activity and an instance slot. Generous on purpose:
-- reading your own run's numbers is the reward, and nobody should be hurried through it.
RaidConfig.SummaryTimeoutSeconds = 180

function RaidConfig.GetRunProgressionCountBonus(totalNodesVisited: number): number
	return math.min(
		RaidConfig.RunProgressionMaxExtraEnemies,
		math.floor(RaidConfig.GetRunProgressionStep(totalNodesVisited) * RaidConfig.RunProgressionCountPerStep))
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

----------------------------------------------------------------------
-- EXTRACTION REWARDS — what a raid is actually FOR (2026-09-15, settled with the user; see
-- DESIGN_NOTES.md's "SETTLED for step 4"). "You can get some quick resources and stuff, but its the
-- main way to get contraband and some cores, but we only reward those after a player finishes a map
-- node and then the game gotta make a new one so the player can continue, and also in boss nodes."
--
-- The shape, and why:
--   * Scrap and Ore still drop room by room and are still always kept. Those are the "quick
--     resources" — the raid must still pay for itself even on a run that ends badly.
--   * Contraband and Cores come ONLY from clearing a map and from beating a Boss, and they are HELD
--     (RaidRoomService's state.PendingRewards) rather than banked as they're earned. A Defeat or an
--     Abandon loses the lot. That is the whole stakes layer: pushing into one more map risks
--     everything already earned, and Extract is the decision that keeps it.
--   * Each clear pays more than the last (MapGrowthPerClear), so depth is worth the risk.
--   * Extracting MULTIPLIES the held pile by how many BOSSES were beaten — "make it multiply based
--     on the number of bosses defeated, so it encourages players on doing bosses nodes". Bosses sit
--     on 1-2 random nodes per map at BossMinStageIndex or deeper, so most maps CAN be finished
--     without fighting one, which is what makes choosing to fight one a real decision.
--
-- Growth and the boss multiplier stack, which is why both start modest and the multiplier is
-- capped. All placeholder amounts — tune here, never in the service.
----------------------------------------------------------------------

RaidConfig.ExtractionRewards = {
	-- Paid when a map's last node is cleared (RaidRoomService.onMapCleared).
	MapClear = { ContrabandMin = 2, ContrabandMax = 4, CoresMin = 3, CoresMax = 6 },
	-- Paid on top of the Boss room's own loot table (NodeConfig.BossLoot, Scrap/Ore only now).
	Boss = { ContrabandMin = 3, ContrabandMax = 6, CoresMin = 5, CoresMax = 10 },

	-- Each map already cleared adds this fraction of the base payout to the next one: the first
	-- clear pays 1x, the second 1.35x, the third 1.7x, and so on — up to MapGrowthCap.
	MapGrowthPerClear = 0.35,
	-- The ceiling on that growth, reached at the 10th clear. Uncapped until 2026-09-23, on the
	-- reasoning that "a run that deep has already survived everything the multiplier is asking it
	-- to risk" — which is true of the DIFFICULTY, except the difficulty curve now stops climbing
	-- (RunProgressionMaxStep) and a regenerated map's enemies reset to their tier baseline anyway.
	-- So the risk being priced flattened out while this kept rising. Both curves end now.
	MapGrowthCap = 4.0,

	-- Extract multiplier: 1 + this per boss beaten, capped. 0 bosses x1, 1 boss x1.25, 4+ x2.
	MultiplierPerBoss = 0.25,
	MultiplierCap = 2.0,
}

-- Rolled payout for finishing a map, grown by how many were already finished. `mapsCleared` is the
-- count INCLUDING the one just cleared (1 on the first), so the first clear gets the flat base.
function RaidConfig.RollMapClearReward(mapsCleared: number): (number, number)
	local rules = RaidConfig.ExtractionRewards
	local growth = math.min(
		rules.MapGrowthCap,
		1 + rules.MapGrowthPerClear * math.max(0, mapsCleared - 1))
	local contraband = math.floor(math.random(rules.MapClear.ContrabandMin, rules.MapClear.ContrabandMax) * growth + 0.5)
	local cores = math.floor(math.random(rules.MapClear.CoresMin, rules.MapClear.CoresMax) * growth + 0.5)
	return contraband, cores
end

-- Rolled payout for beating a Boss node. Flat: a boss already pays twice, once here and again
-- through the extract multiplier below.
function RaidConfig.RollBossReward(): (number, number)
	local boss = RaidConfig.ExtractionRewards.Boss
	return math.random(boss.ContrabandMin, boss.ContrabandMax), math.random(boss.CoresMin, boss.CoresMax)
end

-- What a clean Extract multiplies the held pile by. Shared (not server-only) so the raid HUD can
-- show the player what extracting is currently worth without inventing its own arithmetic.
function RaidConfig.ExtractMultiplier(bossesDefeated: number): number
	local rules = RaidConfig.ExtractionRewards
	return math.min(rules.MultiplierCap, 1 + rules.MultiplierPerBoss * math.max(0, bossesDefeated or 0))
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
-- `rules` (optional): a RaidConfig.Modes[...].Map table. Any field it doesn't set falls back to the
-- module-wide constant, so a nil `rules` is exactly the pre-modes behaviour.
local function placeBossNodes(map, rules)
	rules = rules or {}
	local bossMinPerMap = rules.BossMinPerMap or RaidConfig.BossMinPerMap
	local bossMaxPerMap = rules.BossMaxPerMap or RaidConfig.BossMaxPerMap
	local bossMinStageIndex = rules.BossMinStageIndex or RaidConfig.BossMinStageIndex
	local candidates = {}
	for id, node in pairs(map.Nodes) do
		if node.Type ~= "Start" and node.StageIndex >= bossMinStageIndex then
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

	local bossCount = math.min(#candidates, math.random(bossMinPerMap, bossMaxPerMap))
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
-- `rules` (optional): the raid mode's Map rules (RaidConfig.Modes[key].Map), handed to placeBossNodes.
function RaidConfig.GenerateMap(rules)
	local best = nil
	local bestCount = -1
	for _ = 1, RaidConfig.MaxGenerateAttempts do
		local map = generateOnce()
		local count = 0
		for _ in pairs(map.Nodes) do
			count += 1
		end
		if count >= RaidConfig.MinMapNodes then
			placeBossNodes(map, rules)
			return map
		end
		if count > bestCount then
			best = map
			bestCount = count
		end
	end
	if best then
		placeBossNodes(best, rules)
	end
	return best
end

----------------------------------------------------------------------
-- Card system — the post-Boss reward pick. "You get healed, and you roll some cards with buffs,
-- and the cards have rarity, and the buff is connected to rarity, and you can only pick one, pretty
-- roguelike." Real cards, wired in as part of the Raid shop rework (DESIGN_NOTES.md, "Round 2
-- answers, same day": "Boss cards: wire them in THIS rework... reuse the shop's run-buff system,
-- stack WITHOUT limit and take NO slots"). Each card's `Stats` table uses the SAME stat keys
-- `RunBuffConfig.Items[*].PerLevel`/`Lv4`/`Lv5` use (DamagePct, FireRatePct, MaxHpPct, LootPct,
-- CritChance) so `RunBuffConfig.Aggregate(owned, pickedCards)` can sum shop perks and boss cards
-- into one flat total without special-casing either source. Small, rarity-scaled, no cap — a boss
-- card never competes with a shop item for one of the 4 equipment slots.
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

-- One card per (stat, rarity) pair. Values are placeholders per the design doc but the ladder shape
-- is deliberate: each rarity step is roughly a 1.5-1.6x jump over the last, same feel across stats.
-- `Icon` reuses the run-buff icons already uploaded for the shop side of this rework (UiIconConfig)
-- instead of commissioning boss-card-specific art — see CARD_STAT_ICONS below for the mapping.
-- `Description` stays the sub-line text; the effect line itself (label + formatted value, e.g.
-- "Damage +5%") is DERIVED from `Stats` via RaidConfig.CardEffect() below, not stored per entry, so
-- retuning a Stats value can't leave a stale hand-typed Effect string behind.
-- These cards stack WITHOUT limit and take NO equipment slot (unlike shop items, which cap at 4
-- slots) — the new card UI prints that fact where the shop card prints its level pips.
RaidConfig.CardPool = {
	-- Damage
	{ Key = "DamagePct_Common", DisplayName = "Overcharged Rounds", Rarity = "Common", Description = "+3% damage for the rest of this raid.", Icon = "RunOverclockChip", Stats = { DamagePct = 0.03 } },
	{ Key = "DamagePct_Rare", DisplayName = "Overcharged Rounds", Rarity = "Rare", Description = "+5% damage for the rest of this raid.", Icon = "RunOverclockChip", Stats = { DamagePct = 0.05 } },
	{ Key = "DamagePct_Epic", DisplayName = "Overcharged Rounds", Rarity = "Epic", Description = "+8% damage for the rest of this raid.", Icon = "RunOverclockChip", Stats = { DamagePct = 0.08 } },
	{ Key = "DamagePct_Legendary", DisplayName = "Overcharged Rounds", Rarity = "Legendary", Description = "+12% damage for the rest of this raid.", Icon = "RunOverclockChip", Stats = { DamagePct = 0.12 } },

	-- Fire rate
	{ Key = "FireRatePct_Common", DisplayName = "Combat Stims", Rarity = "Common", Description = "+3% fire rate for the rest of this raid.", Icon = "RunRapidFeeder", Stats = { FireRatePct = 0.03 } },
	{ Key = "FireRatePct_Rare", DisplayName = "Combat Stims", Rarity = "Rare", Description = "+5% fire rate for the rest of this raid.", Icon = "RunRapidFeeder", Stats = { FireRatePct = 0.05 } },
	{ Key = "FireRatePct_Epic", DisplayName = "Combat Stims", Rarity = "Epic", Description = "+8% fire rate for the rest of this raid.", Icon = "RunRapidFeeder", Stats = { FireRatePct = 0.08 } },
	{ Key = "FireRatePct_Legendary", DisplayName = "Combat Stims", Rarity = "Legendary", Description = "+12% fire rate for the rest of this raid.", Icon = "RunRapidFeeder", Stats = { FireRatePct = 0.12 } },

	-- Max HP
	{ Key = "MaxHpPct_Common", DisplayName = "Reinforced Plating", Rarity = "Common", Description = "+5% max HP for the rest of this raid.", Icon = "RunPlatedVest", Stats = { MaxHpPct = 0.05 } },
	{ Key = "MaxHpPct_Rare", DisplayName = "Reinforced Plating", Rarity = "Rare", Description = "+8% max HP for the rest of this raid.", Icon = "RunPlatedVest", Stats = { MaxHpPct = 0.08 } },
	{ Key = "MaxHpPct_Epic", DisplayName = "Reinforced Plating", Rarity = "Epic", Description = "+12% max HP for the rest of this raid.", Icon = "RunPlatedVest", Stats = { MaxHpPct = 0.12 } },
	{ Key = "MaxHpPct_Legendary", DisplayName = "Reinforced Plating", Rarity = "Legendary", Description = "+18% max HP for the rest of this raid.", Icon = "RunPlatedVest", Stats = { MaxHpPct = 0.18 } },

	-- Loot
	{ Key = "LootPct_Common", DisplayName = "Scavenger's Instinct", Rarity = "Common", Description = "+5% ore and Scrap from drops for the rest of this raid.", Icon = "RunScavengersLens", Stats = { LootPct = 0.05 } },
	{ Key = "LootPct_Rare", DisplayName = "Scavenger's Instinct", Rarity = "Rare", Description = "+8% ore and Scrap from drops for the rest of this raid.", Icon = "RunScavengersLens", Stats = { LootPct = 0.08 } },
	{ Key = "LootPct_Epic", DisplayName = "Scavenger's Instinct", Rarity = "Epic", Description = "+12% ore and Scrap from drops for the rest of this raid.", Icon = "RunScavengersLens", Stats = { LootPct = 0.12 } },
	{ Key = "LootPct_Legendary", DisplayName = "Scavenger's Instinct", Rarity = "Legendary", Description = "+18% ore and Scrap from drops for the rest of this raid.", Icon = "RunScavengersLens", Stats = { LootPct = 0.18 } },

	-- Crit chance. No shop item rolls CritChance, so there's no RunBuffConfig icon for it either —
	-- borrows the damage chip (RunOverclockChip) until dedicated crit art exists.
	{ Key = "CritChance_Common", DisplayName = "Weak Point Sense", Rarity = "Common", Description = "+2% crit chance for the rest of this raid.", Icon = "RunOverclockChip", Stats = { CritChance = 0.02 } },
	{ Key = "CritChance_Rare", DisplayName = "Weak Point Sense", Rarity = "Rare", Description = "+4% crit chance for the rest of this raid.", Icon = "RunOverclockChip", Stats = { CritChance = 0.04 } },
	{ Key = "CritChance_Epic", DisplayName = "Weak Point Sense", Rarity = "Epic", Description = "+6% crit chance for the rest of this raid.", Icon = "RunOverclockChip", Stats = { CritChance = 0.06 } },
	{ Key = "CritChance_Legendary", DisplayName = "Weak Point Sense", Rarity = "Legendary", Description = "+10% crit chance for the rest of this raid.", Icon = "RunOverclockChip", Stats = { CritChance = 0.10 } },
}

-- Stat key -> display label, matching the wording RunBuffConfig.Items' own `Card.Label` uses for
-- the same stat key (DamagePct/FireRatePct/MaxHpPct/LootPct) so the boss-card UI and the shop-card
-- UI never call the same stat two different names. CritChance has no RunBuffConfig equivalent (no
-- shop item rolls it) — "Crit Chance" here is boss-card-only wording, not borrowed from anywhere.
local CARD_STAT_LABELS = {
	DamagePct = "Damage",
	FireRatePct = "Fire Rate",
	MaxHpPct = "Max HP",
	LootPct = "Loot Bonus",
	CritChance = "Crit Chance",
}

-- Returns (label, formattedValue) for a CardPool entry's effect line, e.g. ("Damage", "+5%") —
-- computed FROM card.Stats (today, always exactly one stat per card) rather than stored as a
-- separate field, so the printed value can never drift from the actual effect the card grants.
-- Every CardPool stat today is a plain percent; formatting mirrors RunBuffConfig.CardValue's
-- "Percent" branch. Add a Format lookup here (same shape as RunBuffConfig.Items[*].Card.Format) if
-- a non-percent boss-card stat is ever introduced.
function RaidConfig.CardEffect(card)
	local statKey, value = next(card.Stats)
	local label = CARD_STAT_LABELS[statKey] or statKey
	local formatted = string.format("+%d%%", math.floor(value * 100 + 0.5))
	return label, formatted
end

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

----------------------------------------------------------------------
-- Raid modes — Phase 00 step 3, "mode plumbing" (DESIGN_NOTES "Road to release"). BUILT 2026-09-15.
----------------------------------------------------------------------
-- A raid is started IN a mode (state.RaidMode, fixed for the whole run) and the rules below are read
-- off that mode wherever a raid behaves differently per mode. Flat table of named strategies, the
-- project's standard shape: a future mode is a new entry here plus content, not new branches through
-- the raid state, loot settlement and map generator.
--
-- ONE entry on purpose (the v1 scope cut: Gauntlet and Contract are post-launch). `Standard` is
-- today's raid exactly, a hack-and-slash run for special items like Contraband in the user's words,
-- so every rule points at the value raids already used. Changing nothing about how a raid plays was
-- the point of this step; whether this entry becomes step 4's "Salvage Run" is an open design call.
--
-- Rules, and where each is read:
--   DisplayName  — sent to the client in the map payload (Mode/ModeName) for a future mode picker.
--   EnergyCost   — RequestStartRaid's Energy spend.
--   Map          — handed to GenerateMap, both at raid start and when a cleared chapter regenerates.
--                  Any field left out falls back to the module constant (BossMinPerMap etc.).
--   ShopCatalog  — NAME of the NodeConfig table a Shop node sells from (a name, not the table, so this
--                  file never requires NodeConfig). Read by the reveal and by the Buy handler.
--   CardsEnabled — whether a Boss clear offers the card pick. false skips straight to the next choice.
--
-- NOT mode rules yet, deliberately: enemy composition (CombatTierComposition/BossComposition) and the
-- depth curves both belong to the unbuilt curve work, and RunLocked tagging is step 4.
RaidConfig.Modes = {
	Standard = {
		DisplayName = "Raid",
		EnergyCost = RaidConfig.EnergyCost,
		Map = {
			BossMinPerMap = RaidConfig.BossMinPerMap,
			BossMaxPerMap = RaidConfig.BossMaxPerMap,
			BossMinStageIndex = RaidConfig.BossMinStageIndex,
		},
		ShopCatalog = "ShopCatalog",
		CardsEnabled = true,
	},
}

-- The mode a raid starts in when the client asks for none (every client today: there's no picker).
RaidConfig.DefaultMode = "Standard"

return RaidConfig
