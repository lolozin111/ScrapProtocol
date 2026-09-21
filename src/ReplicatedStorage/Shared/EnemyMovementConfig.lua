--[[
	EnemyMovementConfig.lua
	Tunables for EnemyMovement.lua — how every enemy walks toward whatever it is after, in base
	defense waves AND raid rooms. Three jobs, one section each:

	  Pathing    — walk straight when the way is clear, path around walls when it isn't.
	  Stuck      — notice an enemy that is trying to move but going nowhere, and unstick it.
	  Separation — keep enemies from stacking inside each other.

	Why these exist at all: before EnemyMovement, every enemy walked a straight Humanoid:MoveTo line
	at its target with no pathfinding anywhere in the game, so they ground into walls and wedged on
	corners. And they are in a collision group that does not collide with itself (CombatEnemies, set
	up in CombatEncounterService — deliberate, so a crowd can't physically jam a doorway), which is why
	they used to overlap completely. Separation is the steering that replaces what physics won't do.
]]

local EnemyMovementConfig = {}

EnemyMovementConfig.Pathing = {
	-- How often (seconds) an enemy re-checks whether it can walk straight at its goal. Between
	-- checks it keeps doing whatever it decided last. Each enemy's first check is offset by a random
	-- fraction of this, so a wave that spawns together doesn't raycast together forever after.
	LineOfSightInterval = 0.5,

	-- A clear-path check that hits something within this many studs OF THE GOAL still counts as
	-- clear. Needed because the goal is often right up against something solid — the edge of the
	-- base an enemy is attacking — and a ray aimed at it clips that geometry just before arriving.
	GoalHitTolerance = 4,

	-- Once following a path: recompute when the goal has drifted this far (studs) from where the
	-- path was aimed, e.g. a raid player who has run somewhere else.
	GoalDrift = 6,

	-- ...but never more often than this (seconds) per enemy, plus a random 0..Jitter on top so
	-- enemies drift out of step with each other instead of recomputing on the same frame.
	RecomputeInterval = 1.0,
	RecomputeJitter = 0.5,

	-- Server-wide cap on how many new paths may START per second, across every enemy of every player.
	-- Path computation is the expensive part; an enemy denied a slot just keeps walking straight
	-- and asks again next check, so hitting this cap degrades gracefully rather than stalling.
	MaxComputesPerSecond = 15,

	-- Passed straight to PathfindingService:CreatePath. WaypointSpacing is studs between points on
	-- a computed path; smaller follows corners more tightly but gives more points to walk.
	WaypointSpacing = 4,
	AgentCanJump = true,

	-- A waypoint counts as reached within this many studs (horizontal), plus half the enemy's
	-- own radius so big enemies don't have to put their centre exactly on each point.
	WaypointArriveDistance = 3,

	-- Used when an EnemyConfig entry doesn't set its own AgentRadius/AgentHeight. Measured from the
	-- model's own size when possible (see EnemyMovement), so these are only the last resort.
	DefaultAgentRadius = 2,
	DefaultAgentHeight = 5,
}

EnemyMovementConfig.Stuck = {
	-- Every this-many seconds, compare where a walking enemy is now against where it was.
	CheckInterval = 1.0,

	-- Covered less ground than this (studs) across one check while trying to walk = stuck. The
	-- fix is a fresh path from where it actually is, whether or not it could "see" the goal.
	MinDisplacement = 1.5,

	-- Stuck this many checks IN A ROW = the path isn't helping either (wedged on a lip, a thin
	-- part the navmesh missed). Hop and sidestep, then carry on.
	HopAfterChecks = 2,
	SidestepDistance = 5,
}

EnemyMovementConfig.Separation = {
	-- Two enemies try to keep their centres this many times their combined radii apart while
	-- travelling. 1 would be exactly touching; above 1 gives them visible personal space.
	PersonalSpace = 1.6,

	-- Close to the target (within ContactRange + this many studs) personal space relaxes to just
	-- "don't overlap" — the user's rule: keep a distance "unless necessary", and closing in to
	-- attack is exactly when it's necessary. Without this, a crowd around a player could never
	-- surround them.
	NearTargetBand = 8,
	NearTargetSpace = 1.0,

	-- How hard the push is, and the most it may shift a walk goal (studs) in one think, so a
	-- tight crowd shuffles apart rather than flinging members sideways.
	Strength = 1.0,
	MaxOffset = 6,

	-- HOLDING (in attack range, standing still). The first build nudged apart at plain contact on
	-- every 0.3s tick, and a crowd ringing the player can't all fit without touching — so each nudge
	-- pushed one enemy into the next, which nudged back, forever. The user saw it as a Brute that
	-- "keeps moving and never stops" (the biggest body overlaps the most). Two brakes:
	--   HoldOverlapStart — only nudge once the overlap is DEEP: centres closer than this fraction of
	--   plain contact. Touching, or lightly overlapping, is accepted as settled.
	--   HoldNudgeCooldown — after a nudge, stand still at least this long (seconds) before another,
	--   so a pair that bumps once settles instead of trading pushes every tick.
	HoldOverlapStart = 0.6,
	HoldNudgeCooldown = 1.5,
}

return EnemyMovementConfig
