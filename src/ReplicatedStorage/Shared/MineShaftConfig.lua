--[[
	MineShaftConfig.lua
	Tuning for the dig-down mine — a real, honest 3D voxel grid (MineShaftConfig.GridWidth x
	GridLength cells wide, MaxDepth cells deep) starting from a Part tagged "MineShaftStart".
	Place that Part somewhere with genuinely open air underneath it — up on a platform, not on
	your map's real ground — since the whole mine is built directly in real world space right
	below it, no tricks. See MineShaftService.lua's header comment for the full history of why
	that matters (short version: two earlier attempts tried to make digging work through real,
	unknown ground geometry and both broke; a third tried relocating the dig to a hidden "pocket"
	elsewhere in the world and that turned out needlessly complicated AND had its own bugs. This
	is the actually-simple version: just give it clear real space and let gravity do the work).

	Only the very first layer (depth 0, directly under the anchor) is generated up front, filling
	the whole GridWidth x GridLength footprint — that's the floor of the quarry you walk in on.
	Everything past that is generated on demand: destroy a block and its immediate neighbors (down,
	up, and the 4 sideways directions — see RevealNeighborOffsets) each get checked, and any that
	are still totally unexplored get a new block spawned in them. Since depth 0 starts completely
	full, mining a depth-0 block only ever reveals the block directly below it (its sideways
	neighbors are already filled in from generation) — but once you're a level down, sideways
	neighbors ARE still unexplored, so digging sideways down there opens up real, connected
	tunnels, not just a single isolated straight shaft. This is what actually makes it feel like
	one big quarry you're carving into, instead of a set of independent one-block-wide holes.

	Most cells are Rock filler (destroys for nothing — it's there to make ore feel like something
	you actually have to dig for, not just stand next to). Some cells are Ore (an actual resource,
	same OreConfig.lua ore keys as everywhere else). A few, past a certain depth, are Lava — mine
	one through and it bursts for real damage instead of a reward. All three get more or less
	common with depth (MineShaftConfig.KindWeightBands): Ore and Lava both get more frequent the
	deeper you go, but Rock is floored so filler never fully disappears, even very deep.

	See MineShaftService.lua for how these get used.
]]

local MineShaftConfig = {}

----------------------------------------------------------------------
-- Grid shape
----------------------------------------------------------------------

MineShaftConfig.GridWidth = 16            -- cells across, X — 16x16 = 256 blocks for the first
                                          -- layer. Halved from 32 (was 32x32/1,024, itself dropped
                                          -- from an original 128x128/16,384) alongside doubling
                                          -- CellSize below, for the "chunky, Minecraft-ish" block
                                          -- pass — same 192x192-stud footprint (16 * 12 = 192,
                                          -- same as the old 32 * 6), just built out of fewer,
                                          -- bigger cells. Nothing else about the design depends on
                                          -- this specific number.
MineShaftConfig.GridLength = 16           -- cells across, Z
MineShaftConfig.CellSize = 12             -- studs per cell, both horizontal and vertical — a
                                          -- block's top face always lines up with the surface or
                                          -- the level above it, so digging never leaves a gap or
                                          -- an overlap. Doubled from 6 for the chunky-block pass;
                                          -- GridWidth/GridLength were halved in the same change so
                                          -- the total footprint (GridWidth * CellSize) is
                                          -- unchanged — see their comments.
MineShaftConfig.MaxDepth = 200           -- a cell hits unmineable Bedrock past this depth. Left
                                          -- unchanged by the chunky-block pass on purpose: this
                                          -- number paces "how many blocks you've dug," not studs,
                                          -- and mining one block still takes the same time it
                                          -- always did — so the dig-time pacing is identical, the
                                          -- mine is just now physically 2,400 studs down (200 * 12)
                                          -- instead of 1,200 (200 * 6). Was bumped way up from an
                                          -- original 40 so the KindWeightBands / OreWeightBands /
                                          -- HazardTypes zones below (each now spaced 40+ levels
                                          -- apart, on purpose — see their comments) actually have
                                          -- room to breathe instead of all being crammed into the
                                          -- first 15-ish levels.
MineShaftConfig.ForwardOffset = 6        -- studs in front of the MineShaftStart anchor before the
                                          -- grid's near edge starts, so it doesn't clip the anchor.
                                          -- Deliberately left unscaled by the chunky-block pass:
                                          -- this clears the anchor Part's own physical size, not
                                          -- the grid's cell size, and it also fixes the footprint's
                                          -- POSITION relative to the anchor — changing it would
                                          -- shift where the 192x192 hole needs to be cut for no
                                          -- reason anyone asked for.

-- The 6 face-adjacent neighbors checked every time a block gets destroyed — down, up, and the 4
-- sideways directions, in the block's own local space (X = anchor's right, Z = anchor's forward).
-- "Up" only ever matters right at depth 0 mining into an already-occupied cell (blocked, so it's
-- a no-op there) or deeper down where the level above hasn't been fully explored — it's here for
-- correctness, not because you're expected to dig upward much. Each of these gets checked for
-- bounds and for whether that cell has ever been touched before spawning anything new there — see
-- MineShaftService.revealNeighbors.
MineShaftConfig.RevealNeighborOffsets = {
	{ 0, 1, 0 },  -- down (Depth increases downward)
	{ 0, -1, 0 }, -- up
	{ 1, 0, 0 },  -- +X
	{ -1, 0, 0 }, -- -X
	{ 0, 0, 1 },  -- +Z
	{ 0, 0, -1 }, -- -Z
}

MineShaftConfig.WallThickness = 4        -- thickness of the low guard rail around the depth-0
                                          -- footprint's edge (see below) — not a full wall, just
                                          -- enough to stop casually walking off the quarry's edge.
                                          -- Doubled from 2 alongside CellSize so the rail keeps the
                                          -- same proportion to a block (was 1/3 of a 6-stud cell,
                                          -- now 1/3 of a 12-stud one) — it sits outside the
                                          -- 192x192 footprint either way, so this doesn't touch the
                                          -- footprint's size or position, just how far the rail
                                          -- pokes onto the surrounding ground.
MineShaftConfig.SurfaceGuardHeight = 2   -- studs the guard rail rises above the surface. NOT scaled
                                          -- with CellSize, and deliberately so: this was briefly 8
                                          -- (2/3 of a 12-stud cell, for proportion) and the user hit
                                          -- the real problem immediately — "rn u gotta jump in order
                                          -- to get into the mines and i dont want that". A Roblox
                                          -- character steps over about 2 studs without jumping, so
                                          -- that is the ceiling here whatever the blocks measure. The
                                          -- rail's job is to read as a rim, not to be a barrier.
MineShaftConfig.WallColor = Color3.fromRGB(66, 52, 38) -- was (58, 50, 44); pushed from ~24% to ~42%
                                          -- saturation — a bit more gunmetal-brown so it doesn't
                                          -- read as flat grey, but still darker and less saturated
                                          -- than every ore color below so it stays background

----------------------------------------------------------------------
-- Block kind by depth — Rock (filler) / Ore (resource) / Hazard (Lava)
----------------------------------------------------------------------

-- Weights don't need to sum to 100 — they're normalized at roll time — but keeping them that way
-- makes them easy to read at a glance. Rock has a floor (38 even in the deepest band, staying in
-- the 30-40 range on purpose) so filler never fully disappears; Ore and Hazard both climb with
-- depth. The shallowest band was tuned down from an earlier 60/40 split — that felt like too much
-- ore too early — to 80% Rock / 20% Ore total, which combined with the 75/25 split in
-- OreWeightBands below works out to roughly 15% of all shallow blocks being Iron Ore and 5%
-- being Copper Ore.
--
-- Zone boundaries (MaxDepth) are spaced 40 levels apart on purpose — an earlier version had them
-- only 4-5 levels apart, which meant the ore mix and the rest of the mine's whole "feel" shifted
-- within just a few blocks of digging, way too fast to actually notice. Spacing zones out like
-- this (and MaxDepth above being bumped to 200 to give the last one room) is what makes the mine
-- read as one big, gradually-changing cave instead of several tiny ones stacked on top of each
-- other.
MineShaftConfig.KindWeightBands = {
	{ MaxDepth = 40, Rock = 80, Ore = 20, Hazard = 0 },
	{ MaxDepth = 80, Rock = 50, Ore = 45, Hazard = 5 },
	{ MaxDepth = 120, Rock = 42, Ore = 50, Hazard = 8 },
	{ MaxDepth = math.huge, Rock = 38, Ore = 52, Hazard = 10 },
}

-- Once a cell rolls "Ore", which ore key it actually is — same shape/idea as the old
-- ResourceZoneConfig.OreWeightBands, just keyed by depth instead of distance. Does NOT override
-- OreConfig's MinToolTier/MinWaveUnlock gates — a deep cell can roll ore you can't mine yet,
-- which is the point: a concrete reason to come back once you've upgraded. The shallowest band is
-- Iron Ore / Copper Ore only (no Gold Ore yet) — see the KindWeightBands comment above for
-- how this 75/25 split combines with that band's 20% overall Ore rate. Same MaxDepth boundaries as
-- KindWeightBands above, so the "what kind of ore" shift and the "how much ore at all" shift both
-- land on the same checkpoints as you dig.
MineShaftConfig.OreWeightBands = {
	{ MaxDepth = 40, Weights = { IronOre = 75, CopperOre = 25 } },
	{ MaxDepth = 80, Weights = { IronOre = 25, CopperOre = 30, GoldOre = 35, PlatinumOre = 10 } },
	{ MaxDepth = 120, Weights = { IronOre = 10, CopperOre = 20, GoldOre = 30, PlatinumOre = 30, VoidiumShard = 10 } },
	{ MaxDepth = math.huge, Weights = { IronOre = 5, CopperOre = 10, GoldOre = 20, PlatinumOre = 35, VoidiumShard = 30 } },
}

MineShaftConfig.RockMaxHits = 3          -- filler is quick to clear — it's an obstacle, not a resource
MineShaftConfig.RockColor = Color3.fromRGB(100, 86, 66) -- was (90, 84, 78); pushed from ~13% to
                                          -- ~34% saturation — enough to look like actual rust-brown
                                          -- rock instead of flat grey, but still the least
                                          -- saturated block in the mine on purpose, so every ore
                                          -- color below reads as clearly more valuable next to it

MineShaftConfig.LavaMaxHits = 2          -- fast AND risky — you find out what it is right before it hurts
MineShaftConfig.LavaColor = Color3.fromRGB(224, 54, 20) -- was (196, 76, 34); pushed from ~83% to
                                          -- ~91% saturation and shifted redder or it started
                                          -- reading too close to CopperOre's orange below — Lava
                                          -- also renders Neon (see MineShaftService's buildBlock),
                                          -- so the glow does most of the "this is dangerous, not
                                          -- an ore" work; this just keeps the base color from
                                          -- fighting that at a glance before it's lit up
MineShaftConfig.LavaDamage = 18          -- big burst dealt the instant a Lava block breaks through —
                                          -- this is "you dug into an active pocket"
MineShaftConfig.LavaTouchDamage = 3      -- small damage from just standing in/against a live Lava
                                          -- block (before it's mined) — this is "you're touching
                                          -- something hot," a much smaller ongoing risk than the
                                          -- burst you get for actually breaking one open
MineShaftConfig.LavaTouchIntervalSeconds = 1 -- minimum gap between touch-damage ticks per player,
                                          -- so standing against a Lava block doesn't deal damage
                                          -- every single physics step

MineShaftConfig.BedrockColor = Color3.fromRGB(26, 20, 14) -- was (20, 18, 16); pushed from ~20% to
                                          -- ~46% saturation with a slightly warmer, more charcoal
                                          -- tone — still reads as near-black/unmineable, this only
                                          -- keeps it in the same warm family as Rock/Wall instead
                                          -- of a neutral grey-black

-- Cosmetic only — same ore keys the old ring zone had, kept here directly rather than reused from
-- ResourceZoneConfig since that file is retired (see DESIGN_NOTES.md). Colors below were
-- redesigned together (not just individually saturated) so all five stay distinguishable from
-- each other even when several can spawn in the same depth band (see OreWeightBands — Iron,
-- Copper, Gold, Platinum, and Voidium Shard all overlap in the 80-120 band): Iron went cool
-- (steel blue) specifically so the two shallow-band ores (Iron/Copper) split on hue, not just
-- shade, and Platinum went bright cyan rather than another warm tone so it doesn't collide with
-- Gold. GoldOre in particular was flat wrong before — (140, 148, 155) is a grey, almost certainly
-- a leftover from before the ore was renamed to Gold, and it read exactly like rock at a glance.
MineShaftConfig.OreColors = {
	IronOre = Color3.fromRGB(90, 128, 162),      -- was (150, 138, 120), a beige barely distinct
	                                              -- from Rock/CopperOre. Now a saturated steel
	                                              -- blue (~44% sat) — cool where every other block
	                                              -- in the mine is warm, so it pops even though
	                                              -- Iron is the most common, least-special ore
	CopperOre = Color3.fromRGB(214, 110, 36),    -- was (184, 115, 51); pushed from ~72% to ~83%
	                                              -- saturation, a more vivid copper-penny orange
	GoldOre = Color3.fromRGB(255, 196, 40),      -- was (140, 148, 155) — a grey that read as rock,
	                                              -- not gold; replaced outright with an actual
	                                              -- saturated gold-yellow (~84% sat) rather than
	                                              -- just re-saturating a broken starting color
	PlatinumOre = Color3.fromRGB(150, 225, 235), -- was (212, 175, 55), a warm gold-tan that
	                                              -- collided with GoldOre's fixed color above. Now
	                                              -- a bright cool cyan (~36% sat) so the two read
	                                              -- as different metals, not two shades of gold
	VoidiumShard = Color3.fromRGB(150, 45, 230), -- was (120, 70, 190); pushed from ~63% to ~80%
	                                              -- saturation, a more vivid violet — this is the
	                                              -- rarest ore, it should look it
}

----------------------------------------------------------------------
-- Environmental hazards (ambient, by depth — separate from the discrete Lava block kind above)
----------------------------------------------------------------------

-- Checked on a shared interval loop (see MineShaftService) against whichever block a player is
-- currently standing on. This is separate from (and stacks with) the discrete Lava block kind
-- above — ambient hazard is "the air down here is dangerous," Lava is "you dug into an active
-- pocket," two different risks. Damage-per-tick numbers below are tuned around this interval —
-- shrinking it without also lowering the Tier damages would make hazards hit harder overall, not
-- just tick faster.
MineShaftConfig.HazardCheckIntervalSeconds = 2

-- Separate, much faster interval just for reporting the player's current depth to their own HUD
-- (the top-right depth panel and the Recall button's visibility) — deliberately decoupled from
-- HazardCheckIntervalSeconds above so making the HUD feel responsive doesn't also speed up
-- hazard damage ticks.
MineShaftConfig.DepthReportIntervalSeconds = 0.5

-- Each hazard type escalates through 3 depth Tiers of its own, damage roughly doubling Tier to
-- Tier (Heat: 4 -> 8 -> 16, Toxic Air: 7 -> 14 -> 28) — the deeper you dig, the worse THAT
-- specific hazard gets. Unlike the old single-threshold version, Heat and Toxic Air now apply
-- independently and can both tick in the same interval once you're deep enough for both (you can
-- genuinely be overheating AND choking on bad air at once) — see MineShaftService for the actual
-- per-tick resolution. Gear doesn't just flip a hazard off once you hit some required tier
-- anymore either — each SuitTier's `Protection` table below knocks a hazard DOWN by that many
-- Tiers instead (see SuitTiers' comment): if you're standing in Tier 2 Heat and your suit
-- protects Heat by 1, you take Tier 1's damage, not Tier 2's — "Tier 2 becomes the new Tier 1."
-- Only when the reduction brings the effective Tier to 0 or below does the hazard stop dealing
-- damage entirely.
--
-- Heat's own 3 Tiers start at Depth 25, then 60, then 95 — tuned again after the first pass still
-- felt too cramped (Tier 1 kicking in at Depth 10 was right under the surface, and the gap to
-- Tier 2 wasn't much of a "this is manageable for a while" stretch). Toxic Air's Tiers are always
-- exactly 1.5x Heat's corresponding Tier depth (e.g. Heat Tier 1 at 25 -> Toxic Air Tier 1 at
-- 37.5, rounded to 38) — keeps Toxic Air reliably "the second hazard you run into, always a good
-- while after Heat," however Heat's own numbers get retuned later, instead of two independently
-- hand-picked schedules that could drift apart. 3 Tiers is the hard cap for both — don't add a
-- Tier 4 to either without also deciding what SuitTiers' Protection should do about it.
MineShaftConfig.HazardTypes = {
	{
		Key = "Heat",
		Name = "Heat",
		Tiers = {
			{ MinDepth = 25, BaseDamage = 4 },
			{ MinDepth = 60, BaseDamage = 8 },
			{ MinDepth = 95, BaseDamage = 16 },
		},
	},
	{
		Key = "ToxicAir",
		Name = "Toxic Air",
		Tiers = {
			{ MinDepth = 38, BaseDamage = 7 },  -- 25 * 1.5 = 37.5, rounded up
			{ MinDepth = 90, BaseDamage = 14 }, -- 60 * 1.5 = 90
			{ MinDepth = 143, BaseDamage = 28 }, -- 95 * 1.5 = 142.5, rounded up
		},
	},
}

-- Suit tiers: a sequential upgrade track exactly like OreConfig.ToolTiers/ToolTierCosts, purchased
-- the same way (Workbench -> Suit). Lives here instead of OreConfig because it's specifically
-- about surviving THIS zone's hazards, not about mining speed/yield.
--
-- `Protection[hazardKey]` is how many Tiers that hazard gets knocked down by (see HazardTypes'
-- comment above) — NOT a hard on/off gate anymore. Scrap Coveralls protects nothing. Thermal
-- Liner knocks Heat down by 1 Tier (so it's still the "get this to actually survive Heat" item,
-- same as before) but does nothing for Toxic Air. Rebreather Rig keeps that same 1-Tier Heat
-- reduction AND adds a 1-Tier Toxic Air reduction on top — this is the highest gear available
-- right now, so it never fully zeroes out the deepest Tier of either hazard on its own; that's
-- intentional, going deep should always cost something even fully geared up. If a dedicated
-- separate gear track (e.g. its own gas-mask progression just for Toxic Air) gets added later,
-- give it its own `Protection.ToxicAir` numbers the same way.
MineShaftConfig.SuitTiers = {
	{ Name = "Scrap Coveralls", ProtectsAgainst = "Nothing yet", Protection = { Heat = 0, ToxicAir = 0 } },
	{ Name = "Thermal Liner", ProtectsAgainst = "Heat (-1 Tier)", Protection = { Heat = 1, ToxicAir = 0 } },
	{ Name = "Rebreather Rig", ProtectsAgainst = "Heat (-1 Tier) + Toxic Air (-1 Tier)", Protection = { Heat = 1, ToxicAir = 1 } },
}
MineShaftConfig.SuitTierCosts = {
	[2] = { Scrap = 250, IronOre = 20 },
	[3] = { Scrap = 600, CopperOre = 30, GoldOre = 15 },
}

----------------------------------------------------------------------
-- Full mine reset — the grid tears down and rebuilds from scratch periodically, and also
-- immediately once enough of it has been dug out. Keeps the mine from turning into an endless
-- swiss-cheese sprawl of old tunnels, and gives everyone a reason to come back to a fresh one.
----------------------------------------------------------------------

MineShaftConfig.ResetIntervalSeconds = 30 * 60 -- full reset every 30 minutes, regardless of how
                                          -- much has been dug
MineShaftConfig.ResetBlockThreshold = 5000 -- ALSO reset immediately, whenever the timer hasn't
                                          -- already fired, once this many blocks have been mined
                                          -- out since the last reset. Was 20,000; scaled down 4x
                                          -- (matching the 4x drop in blocks-per-layer from the
                                          -- chunky-block pass: 16x16=256 vs the old 32x32=1,024) so
                                          -- a reset still lands after roughly the same amount of
                                          -- actual digging — this counts blocks, not studs, and a
                                          -- block still takes the same time to mine either way, so
                                          -- leaving it at 20,000 would have meant grinding through
                                          -- 4x as much of the (now physically bigger) mine before
                                          -- the early-reset path ever triggered. ResetIntervalSeconds
                                          -- below is unaffected — it is a wall-clock cap, not a
                                          -- block count, so nothing about it depended on grid scale.
MineShaftConfig.ResetLockSeconds = 5     -- how long the mine stays locked (no mining) while
                                          -- everyone's being cleared out and it rebuilds — "a few
                                          -- seconds," not instant, so a reset actually reads as an
                                          -- event rather than blocks silently swapping underfoot

----------------------------------------------------------------------
-- Recall
----------------------------------------------------------------------

-- Recall respawns the player at full health (MineShaftService's RecallFromMine handler), which
-- makes it a heal as much as an exit. Tuned as a real escape hatch, not a panic button: long
-- enough that it can't be leaned on to out-heal the depth hazards while you keep digging, short
-- enough that genuinely getting stuck never means waiting around. The handler also refuses
-- outright unless the player is actually down in the mine — this only paces the legitimate use.
MineShaftConfig.RecallCooldownSeconds = 30

return MineShaftConfig
