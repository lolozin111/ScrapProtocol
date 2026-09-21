--[[
	EnemyMovement.lua
	The walking layer every AI pattern delegates to instead of calling Humanoid:MoveTo itself —
	same "shared utility, not a service" precedent as CombatMath.lua/DamagePipeline.lua: no remotes,
	not in Main.server.lua's require list, required directly by its consumers (EnemyAI.lua,
	EnemyAnimation.lua). See EnemyMovementConfig.lua for what every tunable below means and why;
	this file is only the mechanism, the numbers live there.

	=== WHY THIS EXISTS ===
	Before this file, all three walking call sites did the identical thing: throttle on a timer, aim
	a Humanoid:MoveTo at a point on the boundary-circle around the target, and hope. No
	PathfindingService anywhere, and the enemies' own collision group (CombatEncounterService's
	ENEMY_COLLISION_GROUP) deliberately turns off enemy-vs-enemy collision so a crowd can't jam a
	doorway — which is also why, with nothing else keeping them apart, they used to stack completely
	on top of each other. This file adds three things on top of the same MoveTo primitive: pathing
	around obstacles the straight line can't see past, noticing and escaping a wedge the pathing
	itself doesn't fix, and steering separation to replace the personal space physics won't provide.

	=== SHAPE ===
	Called every tick FROM inside an AI pattern's own tick function — WalkTo while it wants to walk,
	Hold while it's in range and not walking, Stop for a stun or anything that must not move at all —
	same "called once per tick per enemy, does one tick's worth of thinking, not itself a loop"
	convention as EnemyAI.lua/EnemyAnimation.lua. Per-enemy state lives lazily on `enemy.Movement`,
	created the first time any of the three functions below sees this enemy — nothing here is a
	field CombatEncounterService's spawnEnemy has to know to initialize, the same "the record grows
	the fields it needs" pattern EnemyAI.lua's own Slam fields already use.

	NEVER yields inside WalkTo/Hold/Stop themselves. PathfindingService:ComputeAsync is a real yield
	(an engine round trip), so it only ever runs inside a task.spawn'd, pcall'd coroutine off to the
	side; WalkTo just reads back whatever that coroutine last wrote into the enemy's own state table.
	Running it inline would stall RunWave/RunRaidCombat's entire shared tick loop — every other
	enemy, every robot, every turret — behind however long one enemy's pathfinding takes to answer.

	Every dynamic/optional read here is guarded (context.Enemies possibly nil, a peer's Model/
	PrimaryPart possibly gone, a path result possibly stale) for the same reason EnemyAI.lua's own
	pattern-dispatch guard exists: this runs inside the tick loop, and an unguarded nil anywhere in
	it throws, kills the encounter coroutine, and strands activeRuns/activeEncounters — see that
	file's header for what that actually costs a player.

	Must never require EnemyAI or EnemyAnimation — this sits BELOW both of them (they require this
	file, not the other way around), so either can require it with no cycle.
]]

local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyMovementConfig = require(ReplicatedStorage.Shared.EnemyMovementConfig)

local Pathing = EnemyMovementConfig.Pathing
local Stuck = EnemyMovementConfig.Stuck
local Separation = EnemyMovementConfig.Separation

-- Mirrors CombatEncounterService's own ENEMY_COLLISION_GROUP literal — duplicated rather than
-- required, since requiring CombatEncounterService from here would cycle right back through
-- EnemyAI (CombatEncounterService requires EnemyAI, EnemyAI requires this file). Used only to make
-- the line-of-sight Spherecast below ignore OTHER enemies (they don't collide with this group
-- anyway) without ignoring real geometry — if that collision group's name ever changes, change it
-- here too.
local ENEMY_COLLISION_GROUP = "CombatEnemies"

local EnemyMovement = {}

----------------------------------------------------------------------
-- Path request budget — a server-wide token bucket, not a per-enemy one. Path computation is the
-- expensive part of all this; an enemy denied a token just keeps walking straight and asks again
-- next check, so hitting this cap degrades gracefully (worse pathing for a moment) instead of
-- stalling anything. Refilled continuously against a timestamp rather than reset once a second, so
-- a burst of requests right as a wave spawns doesn't get a free full bucket at tick zero and then
-- starve for the rest of that first second.
----------------------------------------------------------------------

local computeTokens = Pathing.MaxComputesPerSecond
local lastTokenRefill = os.clock()

local function tryTakeToken(): boolean
	local now = os.clock()
	local elapsed = now - lastTokenRefill
	lastTokenRefill = now
	computeTokens = math.min(Pathing.MaxComputesPerSecond, computeTokens + elapsed * Pathing.MaxComputesPerSecond)
	if computeTokens >= 1 then
		computeTokens -= 1
		return true
	end
	return false
end

-- Warn-once-PER-TYPE (not per enemy) when ComputeAsync can't find a path — this runs inside the
-- tick loop's own request callbacks, and a per-enemy warn would flood Output for a whole wave of
-- the same broken type instead of saying it once.
local warnedNoPath: { [string]: boolean } = {}

local function warnPathFailure(enemy, reason: string)
	local typeKey = tostring(enemy.TypeKey)
	if warnedNoPath[typeKey] then
		return
	end
	warnedNoPath[typeKey] = true
	warn(("[EnemyMovement] %s failed to compute a path (%s) — it will keep walking straight at its goal and re-check line of sight normally instead. This warns once per enemy TYPE, not per enemy."):format(
		typeKey, reason))
end

-- Incrementing per-request id, so a ComputeAsync result that comes back after something newer
-- superseded it gets dropped instead of overwriting fresher state. Deliberately NOT using
-- `path.Blocked` for any of this — that connection outlives the enemy it was made for (nothing
-- above ever disconnects it), so it would leak a live connection per enemy for the rest of the
-- server's life. Stuck detection and the goal-drift recompute below already cover the same ground
-- `path.Blocked` exists for, without needing a connection that has to be torn down by hand.
local nextRequestId = 0

----------------------------------------------------------------------
-- Agent size — measured once per enemy and cached on its Movement state, never re-measured.
----------------------------------------------------------------------

local function measureAgentSize(enemy): (number, number)
	local typeData = enemy.TypeData
	local configRadius = typeData and typeData.AgentRadius
	local configHeight = typeData and typeData.AgentHeight
	if configRadius and configHeight then
		return math.clamp(configRadius, 1.5, 8), math.clamp(configHeight, 3, 20)
	end

	-- Falls back to measuring the rig itself: cheap corner-sampling of every BasePart's OBB into one
	-- overall bounding box, good enough for an agent-size estimate since this only runs once per
	-- enemy rather than per tick. Explicitly SKIPS any part named "Hitbox" — spawnEnemy
	-- (CombatEncounterService) welds an oversized, query-only hitbox onto some types (VoidwakenHulk's
	-- is 26x18x30, well past its actual body) that has nothing to do with the rig's real footprint;
	-- measuring it in would make this enemy path and steer like it's twice its actual size.
	local model = enemy.Model
	local minX, maxX, minY, maxY, minZ, maxZ
	local ok = model and pcall(function()
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "Hitbox" then
				local half = part.Size * 0.5
				local cframe = part.CFrame
				for _, sx in ipairs({ -1, 1 }) do
					for _, sy in ipairs({ -1, 1 }) do
						for _, sz in ipairs({ -1, 1 }) do
							local corner = cframe * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
							minX = minX and math.min(minX, corner.X) or corner.X
							maxX = maxX and math.max(maxX, corner.X) or corner.X
							minY = minY and math.min(minY, corner.Y) or corner.Y
							maxY = maxY and math.max(maxY, corner.Y) or corner.Y
							minZ = minZ and math.min(minZ, corner.Z) or corner.Z
							maxZ = maxZ and math.max(maxZ, corner.Z) or corner.Z
						end
					end
				end
			end
		end
	end)

	if not ok or not minX then
		return Pathing.DefaultAgentRadius, Pathing.DefaultAgentHeight
	end

	local radius = math.max(maxX - minX, maxZ - minZ) * 0.5
	local height = maxY - minY
	return math.clamp(radius, 1.5, 8), math.clamp(height, 3, 20)
end

local function ensureState(enemy)
	local state = enemy.Movement
	if not state then
		state = {}
		enemy.Movement = state
	end
	if not state.Radius then
		state.Radius, state.Height = measureAgentSize(enemy)
		-- First LOS check staggered by a random fraction of the interval, so a wave that spawns
		-- together doesn't keep raycasting together forever after (EnemyMovementConfig's own comment
		-- on LineOfSightInterval).
		state.NextLosCheckAt = os.clock() + math.random() * Pathing.LineOfSightInterval
	end
	return state
end

----------------------------------------------------------------------
-- Separation — horizontal-only steering so a crowd that physically can't collide (see this file's
-- header) still keeps personal space while travelling, and relaxes to "just don't overlap" once
-- close enough to the target that spreading out would mean not actually attacking.
----------------------------------------------------------------------

local function randomHorizontalUnit(): Vector3
	local angle = math.random() * math.pi * 2
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

local function separationSpace(enemy, rootPos, context): number
	local targetPosition = context and context.TargetPosition
	if targetPosition and (rootPos - targetPosition).Magnitude <= (enemy.ContactRange or 0) + Separation.NearTargetBand then
		return Separation.NearTargetSpace
	end
	return Separation.PersonalSpace
end

local function computeSeparationOffset(enemy, state, rootPos, context): Vector3
	local others = context and context.Enemies
	if not others then
		return Vector3.new(0, 0, 0)
	end

	local rSelf = state.Radius
	local space = separationSpace(enemy, rootPos, context)
	local total = Vector3.new(0, 0, 0)

	for _, other in ipairs(others) do
		if other ~= enemy then
			local otherHumanoid = other.Humanoid
			local otherModel = other.Model
			local otherRoot = otherModel and otherModel.PrimaryPart
			if otherHumanoid and otherHumanoid.Health > 0 and otherRoot then
				local otherPos = otherRoot.Position
				local delta = Vector3.new(rootPos.X - otherPos.X, 0, rootPos.Z - otherPos.Z)
				local d = delta.Magnitude
				local rOther = (other.Movement and other.Movement.Radius) or Pathing.DefaultAgentRadius
				local minDist = (rSelf + rOther) * space
				if d < minDist then
					local away = d < 0.01 and randomHorizontalUnit() or (delta / d)
					total += away * (minDist - d)
				end
			end
		end
	end

	total *= Separation.Strength
	if total.Magnitude > Separation.MaxOffset then
		total = total.Unit * Separation.MaxOffset
	end
	return total
end

----------------------------------------------------------------------
-- Stuck detection — an enemy can be actively trying to walk and still cover almost no ground: wedged
-- on a lip, a thin part the navmesh missed, jostled into a corner by Separation itself. A clear
-- line-of-sight ray doesn't catch any of that, since none of it is "something in the way," it's
-- "something underfoot" — this is the check that catches it instead.
----------------------------------------------------------------------

local function updateStuckTracking(enemy, state, rootPos, now)
	if not state.LastStuckCheckAt then
		state.LastStuckCheckAt = now
		state.LastStuckPos = rootPos
		state.StuckCount = 0
		return
	end
	if now - state.LastStuckCheckAt < Stuck.CheckInterval then
		return
	end

	local moved = (rootPos - state.LastStuckPos).Magnitude
	state.LastStuckCheckAt = now
	state.LastStuckPos = rootPos

	if moved >= Stuck.MinDisplacement then
		state.StuckCount = 0
		return
	end

	state.StuckCount = (state.StuckCount or 0) + 1
	-- Force a fresh path on the very next opportunity, bypassing the LOS check entirely (see WalkTo's
	-- ForceRepath branch) — a straight ray to the goal can read perfectly clear from root height while
	-- the enemy is physically stuck on something a raycast doesn't measure. Clear whatever path is
	-- "working" first: the fix is a path computed from where the enemy ACTUALLY is right now, not a
	-- continuation of one that was already failing.
	state.Waypoints = nil
	state.WaypointIndex = nil
	state.ForceRepath = true

	if state.StuckCount >= Stuck.HopAfterChecks then
		-- The path isn't helping either — hop and sidestep instead of just re-requesting the same kind
		-- of route again. WalkTo picks this flag up and does the actual sidestepping (it needs `goal`,
		-- which this function isn't passed).
		state.StuckCount = 0
		if enemy.Humanoid then
			enemy.Humanoid.Jump = true
		end
		state.StartSidestep = true
	end
end

local function startSidestep(state, rootPos, goal, now)
	local toGoal = Vector3.new(goal.X - rootPos.X, 0, goal.Z - rootPos.Z)
	local axis
	if toGoal.Magnitude < 0.1 then
		axis = randomHorizontalUnit()
	else
		local unit = toGoal.Unit
		axis = Vector3.new(-unit.Z, 0, unit.X) -- 90 degrees around Y from the goal direction
	end
	local side = (math.random(0, 1) == 0) and 1 or -1
	state.SidestepPoint = rootPos + axis * side * Stuck.SidestepDistance
	state.SidestepUntil = now + 0.5
end

local function resetStuckTracker(state)
	state.LastStuckCheckAt = nil
	state.LastStuckPos = nil
	state.StuckCount = 0
	state.ForceRepath = nil
	state.StartSidestep = nil
	state.SidestepUntil = nil
	state.SidestepPoint = nil
end

----------------------------------------------------------------------
-- Path requests — the only place this file yields, and only ever inside a task.spawn'd coroutine.
----------------------------------------------------------------------

-- Returns true when a path request is (or is already) in flight for this enemy, false only when
-- nothing is happening at all (no token available and none pending) — used by WalkTo's ForceRepath
-- branch to know whether it can stop insisting yet. See that branch for why the distinction matters.
local function requestPath(enemy, state, rootPart, goal, now): boolean
	if state.PendingRequestId then
		return true -- one request in flight per enemy; let it land before asking again
	end
	if not tryTakeToken() then
		return false
	end

	if not state.PathObject then
		local ok, path = pcall(function()
			return PathfindingService:CreatePath({
				AgentRadius = state.Radius,
				AgentHeight = state.Height,
				AgentCanJump = Pathing.AgentCanJump,
				WaypointSpacing = Pathing.WaypointSpacing,
			})
		end)
		if not ok or not path then
			return false
		end
		state.PathObject = path
	end

	nextRequestId += 1
	local requestId = nextRequestId
	state.PendingRequestId = requestId
	state.PathRequestedAt = now
	state.RecomputeJitter = math.random() * Pathing.RecomputeJitter

	local path = state.PathObject
	local model = enemy.Model
	local startPos = rootPart.Position

	-- ComputeAsync yields for real (an engine round trip) — must never run on the tick loop's own
	-- coroutine, or RunWave/RunRaidCombat's ENTIRE shared loop (every enemy, every robot, every
	-- turret) stalls behind however long this one enemy's pathfinding takes to answer.
	task.spawn(function()
		local ok, err = pcall(function()
			path:ComputeAsync(startPos, goal)
		end)

		-- Drop a stale/late result outright: a newer request has since superseded this one, or the
		-- enemy died / its Model was torn down (encounter ended, corpse cleanup) while this yielded.
		if state.PendingRequestId ~= requestId then
			return
		end
		state.PendingRequestId = nil

		local humanoid = enemy.Humanoid
		if not humanoid or humanoid.Health <= 0 or not model or not model.Parent then
			return
		end

		-- A goal with no route to it (inside geometry, across a gap) fails the SAME way every time.
		-- Without a back-off, every LOS check that reads blocked would ask again, spending the shared
		-- budget on one unreachable point over and over; this makes it wait before trying again.
		if not ok then
			warnPathFailure(enemy, tostring(err))
			state.PathRetryAt = os.clock() + Pathing.RecomputeInterval * 2
			return
		end

		if path.Status == Enum.PathStatus.Success then
			-- Waypoint 1 is the agent's own current position (already there); following starts at 2.
			state.Waypoints = path:GetWaypoints()
			state.WaypointIndex = 2
			state.PathGoal = goal
		else
			warnPathFailure(enemy, tostring(path.Status))
			state.PathRetryAt = os.clock() + Pathing.RecomputeInterval * 2
		end
	end)

	return true
end

----------------------------------------------------------------------
-- Line of sight — "can this enemy walk straight at its goal right now." A Spherecast rather than a
-- Raycast so a wide agent doesn't thread a gap only its exact center point could fit through.
----------------------------------------------------------------------

local function checkLineOfSight(enemy, rootPart, goal, radius): boolean
	-- FLAT, at the enemy's own root height — never aimed at the goal's actual Y. The goal is often
	-- lower than the root (a wave's goal sits at the plot anchor's height, near the floor), and a cast
	-- angled down toward it hits the FLOOR partway there: every enemy would read "blocked" on open
	-- ground every check, and spend the whole server's path budget walking across a flat field.
	-- Terrain that genuinely rises in the way still hits a flat cast, which is the case that matters.
	local origin = rootPart.Position
	local direction = Vector3.new(goal.X - origin.X, 0, goal.Z - origin.Z)
	if direction.Magnitude < 0.01 then
		return true
	end
	local flatGoal = Vector3.new(goal.X, origin.Y, goal.Z)

	local params = RaycastParams.new()
	-- Cast AS the enemy collision group, not just excluding the enemy's own Model — CombatEnemies
	-- doesn't collide with itself (CombatEncounterService's own comment on why), so casting with this
	-- group ignores every OTHER enemy too. Separation is what keeps enemies apart; this check only
	-- cares about real geometry in the way.
	params.CollisionGroup = ENEMY_COLLISION_GROUP
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { enemy.Model }

	-- Sphere capped at 1.5 studs: a big enemy's full radius would let the sphere reach down past its
	-- own feet, and a shapecast IGNORES anything it overlaps at its starting point — so an oversized
	-- sphere would silently stop seeing whatever it began touching (terrain, a floor that becomes a
	-- wall). Width for big enemies is the navmesh's job once a path is computed (AgentRadius), not this.
	local ok, result = pcall(function()
		return Workspace:Spherecast(origin, math.min(radius * 0.75, 1.5), direction, params)
	end)
	if not ok or not result then
		return true
	end

	-- A cast that clips something within a few studs OF the goal itself still counts as clear — the
	-- goal is very often right up against something solid (the base's own edge), see
	-- EnemyMovementConfig's GoalHitTolerance comment. Measured flat, like the cast itself.
	if (Vector3.new(result.Position.X, origin.Y, result.Position.Z) - flatGoal).Magnitude <= Pathing.GoalHitTolerance then
		return true
	end

	-- A character (a player, another enemy that somehow wasn't filtered) is not a wall.
	local hitModel = result.Instance and result.Instance:FindFirstAncestorOfClass("Model")
	if hitModel and hitModel:FindFirstChildOfClass("Humanoid") then
		return true
	end

	return false
end

----------------------------------------------------------------------
-- Waypoint following
----------------------------------------------------------------------

-- Advances the index past every waypoint already reached, returns the position to walk toward next,
-- or nil if the path just finished (state.Waypoints is cleared before returning in that case).
local function advanceWaypoints(state, rootPos, humanoid): Vector3?
	local waypoints = state.Waypoints
	local index = state.WaypointIndex
	local arriveDistance = Pathing.WaypointArriveDistance + state.Radius * 0.5

	while index <= #waypoints do
		local waypoint = waypoints[index]
		local flatDelta = Vector3.new(waypoint.Position.X - rootPos.X, 0, waypoint.Position.Z - rootPos.Z)
		if flatDelta.Magnitude >= arriveDistance then
			break
		end
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		index += 1
	end
	state.WaypointIndex = index

	if index > #waypoints then
		state.Waypoints = nil
		state.WaypointIndex = nil
		state.PathGoal = nil
		return nil
	end
	return waypoints[index].Position
end

----------------------------------------------------------------------
-- Issuing the actual MoveTo — throttled so this file doesn't spam it (and the physics work behind
-- it) every single 0.15s tick when nothing about the target point has meaningfully changed.
----------------------------------------------------------------------

local function issueMoveTo(humanoid, state, point, now)
	local last = state.LastMoveToPoint
	-- MoveTo self-cancels after 8s if never refreshed, so the 0.5s half of this OR also keeps the
	-- separation offset (which moves every tick even when the walk target itself hasn't) from ever
	-- going stale for more than half a second.
	if last and (point - last).Magnitude <= 1 and state.LastMoveToAt and now - state.LastMoveToAt < 0.5 then
		return
	end
	humanoid:MoveTo(point)
	state.LastMoveToPoint = point
	state.LastMoveToAt = now
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

-- Call every tick an enemy wants to walk toward `goal`. Throttles its own MoveTo issuance and its
-- own path (re)computation internally — the caller just calls this every tick without needing to
-- know either cadence, the same way the old MOVE_THINK_INTERVAL callers didn't need to know
-- Humanoid:MoveTo's own arrival tolerance.
function EnemyMovement.WalkTo(enemy, goal: Vector3, context)
	local model = enemy.Model
	local humanoid = enemy.Humanoid
	local rootPart = model and model.PrimaryPart
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	local state = ensureState(enemy)
	local now = os.clock()
	local rootPos = rootPart.Position

	updateStuckTracking(enemy, state, rootPos, now)
	if state.StartSidestep then
		state.StartSidestep = nil
		startSidestep(state, rootPos, goal, now)
	end

	local separationOffset = computeSeparationOffset(enemy, state, rootPos, context)

	-- Sidestepping overrides everything else this tick — the whole point is a short, deliberate
	-- detour away from wherever the enemy is wedged, not another attempt at the same walk that just
	-- failed to make progress.
	if state.SidestepUntil then
		if now < state.SidestepUntil then
			issueMoveTo(humanoid, state, state.SidestepPoint + separationOffset, now)
			return
		end
		state.SidestepUntil = nil
	end

	if not state.Waypoints then
		if state.ForceRepath then
			-- Bypass the LOS check entirely and trust the stuck detector over the raycast — see
			-- updateStuckTracking's own comment on why a clear ray doesn't rule out being wedged.
			-- Retries every tick (not gated by NextLosCheckAt) until a request actually gets a token,
			-- since a token miss here means nothing was even attempted yet.
			if requestPath(enemy, state, rootPart, goal, now) then
				state.ForceRepath = nil
			end
		elseif now >= (state.NextLosCheckAt or 0) then
			state.NextLosCheckAt = now + Pathing.LineOfSightInterval
			if now >= (state.PathRetryAt or 0) and not checkLineOfSight(enemy, rootPart, goal, state.Radius) then
				requestPath(enemy, state, rootPart, goal, now)
			end
		end
	else
		-- Following a path: recompute once the goal has drifted far enough to matter (a raid player
		-- who ran somewhere else) AND enough time has passed since the last request — the jitter on
		-- top keeps a crowd that all drifted together from all recomputing on the same tick.
		if state.PathGoal and (goal - state.PathGoal).Magnitude > Pathing.GoalDrift
			and now >= (state.PathRequestedAt or 0) + Pathing.RecomputeInterval + (state.RecomputeJitter or 0) then
			requestPath(enemy, state, rootPart, goal, now)
		end
	end

	local point = goal
	if state.Waypoints then
		local waypointPosition = advanceWaypoints(state, rootPos, humanoid)
		if waypointPosition then
			point = waypointPosition
		end
		-- else: the path just finished on this very call (advanceWaypoints already cleared it) — fall
		-- through and walk straight at the raw goal for the rest of this tick; the next tick's mode
		-- decision above starts clean from "not following a path."
	end

	issueMoveTo(humanoid, state, point + separationOffset, now)
end

-- Call every tick an enemy is in attack range and NOT walking. Doesn't hold perfectly still if it's
-- overlapping a peer — the user's own rule, "keep a distance unless necessary," and being in attack
-- range is exactly the "necessary" case, so this only pushes apart on DEEP overlap (a fraction of the
-- radius sum, Separation.HoldOverlapStart), then settles — not the wider personal-space multiplier
-- WalkTo's Separation uses.
function EnemyMovement.Hold(enemy, context)
	local model = enemy.Model
	local humanoid = enemy.Humanoid
	local rootPart = model and model.PrimaryPart
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	local state = ensureState(enemy)
	-- Holding isn't being stuck — an enemy sitting at its attack range legitimately doesn't move for
	-- long stretches, and leaving the stuck tracker running would fire a pointless hop the instant it
	-- next starts walking, counting time spent correctly standing still as time spent failing to move.
	resetStuckTracker(state)

	local rootPos = rootPart.Position
	local rSelf = state.Radius
	local overlap = Vector3.new(0, 0, 0)
	local others = context and context.Enemies
	if others then
		for _, other in ipairs(others) do
			if other ~= enemy then
				local otherHumanoid = other.Humanoid
				local otherModel = other.Model
				local otherRoot = otherModel and otherModel.PrimaryPart
				if otherHumanoid and otherHumanoid.Health > 0 and otherRoot then
					local otherPos = otherRoot.Position
					local delta = Vector3.new(rootPos.X - otherPos.X, 0, rootPos.Z - otherPos.Z)
					local d = delta.Magnitude
					local rOther = (other.Movement and other.Movement.Radius) or Pathing.DefaultAgentRadius
					local contact = rSelf + rOther -- contact only, not personal space (see header)
					-- Only DEEP overlap counts while holding — see EnemyMovementConfig's
					-- HoldOverlapStart for the endless-shuffle bug a plain-contact trigger caused.
					if d < contact * Separation.HoldOverlapStart then
						local away = d < 0.01 and randomHorizontalUnit() or (delta / d)
						overlap += away * (contact - d)
					end
				end
			end
		end
	end

	-- One short nudge, then a settle period (HoldNudgeCooldown) standing still no matter what — a pair
	-- that bumps once finishes apart instead of trading pushes every tick.
	local now = os.clock()
	local settling = state.LastHoldMoveAt and now - state.LastHoldMoveAt < Separation.HoldNudgeCooldown
	if overlap.Magnitude > 0.01 and not settling then
		state.LastHoldMoveAt = now
		local step = math.min(overlap.Magnitude + 0.5, 3)
		humanoid:MoveTo(rootPos + overlap.Unit * step)
	elseif not settling or (state.LastHoldMoveAt and now - state.LastHoldMoveAt >= 0.4) then
		-- Let the nudge itself play out (~0.4s) before braking; after that, hold still.
		humanoid:Move(Vector3.new(0, 0, 0))
	end
end

-- Call for a stun, a wind-up, or anything else that means "must not move at all" this tick. Clears
-- whatever path was in progress and resets the stuck tracker — standing still on command is never
-- "stuck," and resuming afterward should re-evaluate line of sight fresh rather than blindly
-- continuing whatever path was computed before the interrupt.
function EnemyMovement.Stop(enemy)
	local humanoid = enemy.Humanoid
	if humanoid then
		humanoid:Move(Vector3.new(0, 0, 0))
	end

	local state = enemy.Movement
	if not state then
		return
	end
	state.Waypoints = nil
	state.WaypointIndex = nil
	state.PathGoal = nil
	-- Orphan any request still in flight: its result would otherwise land AFTER this stop and hand the
	-- enemy a path computed from wherever it was before the stun/wind-up, to a goal that may have moved.
	-- The id check in requestPath's callback drops a result whose id no longer matches.
	state.PendingRequestId = nil
	resetStuckTracker(state)
end

return EnemyMovement
