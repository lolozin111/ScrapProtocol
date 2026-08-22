--[[
	ResourceZoneConfig.lua
	Tuning for the procedural mining zone — a ring of ore nodes scattered around the base anchor
	(the same Part tagged "ExpeditionStart" that the Expedition queue and EnvironmentFX's
	distance fog already use as "the base"). Further from the anchor skews toward rarer,
	higher-tier ore — same "go further = better, but more remote" idea as everything else here.

	See ResourceZoneService.lua for how these get used.
]]

local ResourceZoneConfig = {}

-- Kept deliberately compact: this is a shared, multiplayer-synced zone (every node is one
-- server-wide Part, same as everything else in this project — if one player mines it, it's
-- mined for everybody until it respawns), so a huge sprawling area just means players spend
-- their time walking past each other instead of actually sharing the same handful of nodes.
ResourceZoneConfig.NodeCount = 14              -- how many ore nodes populate the zone
ResourceZoneConfig.MinRadius = 25              -- studs from the base anchor; keeps the area right around the base clear
ResourceZoneConfig.MaxRadius = 110             -- studs from the base anchor; the outer edge of the gathering zone
ResourceZoneConfig.MinNodeSpacing = 9          -- studs; nodes won't place closer together than this
ResourceZoneConfig.MaxPlacementAttempts = 30   -- per node, before giving up and skipping it
ResourceZoneConfig.RaycastHeight = 300         -- how high above the anchor to start the downward raycast that finds ground
ResourceZoneConfig.NodeSize = Vector3.new(3.5, 3.5, 3.5)

-- Keeps the zone from scattering nodes on top of the Expedition lane, which runs straight out
-- from the same anchor Part's -Z/LookVector direction — this excludes a cone this many degrees
-- wide (on either side) centered on that direction.
ResourceZoneConfig.LaneExcludeConeDegrees = 40

-- Distance-based ore weighting (same idea as ExpeditionConfig.TierWeightBands, but keyed by
-- physical distance from the base anchor instead of row index): close in, it's almost all
-- common ore; further out, rarer/higher-tier ore shows up more. This does NOT override
-- OreConfig's MinToolTier/MinWaveUnlock gates — a node can exist out there before a player is
-- actually able to mine it, which is the point (it gives you something to come back for).
ResourceZoneConfig.OreWeightBands = {
	{ MaxDistance = 55, Weights = { ScrapIron = 55, CopperWire = 30, SteelPlating = 15 } },
	{ MaxDistance = 85, Weights = { ScrapIron = 25, CopperWire = 25, SteelPlating = 30, GoldContacts = 20 } },
	{ MaxDistance = math.huge, Weights = { ScrapIron = 10, CopperWire = 15, SteelPlating = 25, GoldContacts = 30, VoidiumShard = 20 } },
}

-- Cosmetic only, so nodes are at least visually distinguishable while testing in Studio.
ResourceZoneConfig.NodeColors = {
	ScrapIron = Color3.fromRGB(150, 138, 120),
	CopperWire = Color3.fromRGB(184, 115, 51),
	SteelPlating = Color3.fromRGB(140, 148, 155),
	GoldContacts = Color3.fromRGB(212, 175, 55),
	VoidiumShard = Color3.fromRGB(120, 70, 190),
}

return ResourceZoneConfig
