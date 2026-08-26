--[[
	GroundEffectService.lua
	Areas of the world that hurt. A puddle of poison, a burning patch, a line of caltrops — anything
	that sits somewhere for a while and does something to enemies standing in it.

	=== WHY THIS IS SHARED ===
	Three specced weapons want the same thing in three shapes: the PoisonThrower leaves puddles, the
	Trailblazer leaves a damaging line from muzzle to impact, and Hellfire's airburst scatters
	patches. Building each into its own gun would mean three implementations of "check who is inside
	me on a timer", each with its own idea of how often to tick and whether it stacks — which is
	exactly the mess StatusEffects was created to avoid one layer up.

	So: one spawner, two shapes, and the damage/status contribution left entirely to the caller.

	=== HOW IT FINDS TARGETS ===
	Through the player's own encounter (CombatEncounterService.LiveEnemiesNear), not by touch events
	or region queries. That means a puddle only ever affects enemies from the fight it belongs to,
	it costs nothing when nothing is nearby, and it reuses the one definition of "alive" the combat
	code already agrees on.

	It also means a ground effect belongs to a PLAYER. Two players' puddles do not interact, and one
	ending their fight does not leave the other's effects orphaned.

	=== SHAPES ===
	  Sphere  a radius around one point. Puddles, blast residue.
	  Line    a capsule between two points. The Trailblazer's trail.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local StatusEffects = require(script.Parent.StatusEffects)

local GroundEffectService = {}

-- Set by CombatEncounterService at load, for the same reason ProjectileService's hit resolver is:
-- that file already requires plenty, and this only needs one entry point out of it.
local liveEnemiesNear: ((Player, Vector3, number) -> { any })? = nil

function GroundEffectService.SetEnemyQuery(fn)
	liveEnemiesNear = fn
end

local effectFolder = Workspace:FindFirstChild("GroundEffects")
if not effectFolder then
	effectFolder = Instance.new("Folder")
	effectFolder.Name = "GroundEffects"
	effectFolder.Parent = Workspace
end

local live: { any } = {}

-- Distance from `point` to the segment a-b. A line effect is a capsule, not a box: an enemy stepping
-- over the middle of a trail should be hit exactly as hard as one at its end.
local function distanceToSegment(point: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local lengthSquared = ab:Dot(ab)
	if lengthSquared < 0.001 then
		return (point - a).Magnitude
	end
	local t = math.clamp((point - a):Dot(ab) / lengthSquared, 0, 1)
	return (point - (a + ab * t)).Magnitude
end

local function buildVisual(effect)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false  -- must never stop a projectile, including the one that created it
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Transparency = 0.6
	part.Color = effect.Color

	if effect.Shape == "Line" then
		local span = effect.To - effect.From
		part.Size = Vector3.new(effect.Radius * 2, 0.2, span.Magnitude)
		-- LookAt down the span, so the part's Z axis (its length) runs along the line.
		part.CFrame = CFrame.lookAt(effect.From + span * 0.5, effect.To)
	else
		part.Shape = Enum.PartType.Cylinder
		-- A Cylinder's height is its X axis, so it has to be laid on its side to sit flat.
		part.Size = Vector3.new(0.2, effect.Radius * 2, effect.Radius * 2)
		part.CFrame = CFrame.new(effect.Position) * CFrame.Angles(0, 0, math.rad(90))
	end

	part.Parent = effectFolder
	return part
end

--[[
	Spawn one effect.

	  Player    whose fight this belongs to (required)
	  Shape     "Sphere" (default) or "Line"
	  Position  centre, for Sphere
	  From, To  endpoints, for Line
	  Radius    studs
	  Duration  seconds before it disappears
	  TickInterval    seconds between applications (default 1)
	  DamagePerTick   optional flat damage per tick
	  Status    optional { Key = "Poison", Overrides = {...} } applied on each tick
	  Color     visual tint
	  Kind      damage-number colour key (default "Status")
]]
function GroundEffectService.Spawn(options)
	if not options.Player then
		warn("[GroundEffectService] Spawn called with no Player — ignored.")
		return
	end

	local effect = {
		Player = options.Player,
		Shape = options.Shape or "Sphere",
		Position = options.Position,
		From = options.From,
		To = options.To,
		Radius = options.Radius or 8,
		ExpiresAt = os.clock() + (options.Duration or 5),
		TickInterval = options.TickInterval or 1,
		NextTick = os.clock() + (options.TickInterval or 1),
		DamagePerTick = options.DamagePerTick,
		Status = options.Status,
		Color = options.Color or Color3.fromRGB(150, 230, 90),
		Kind = options.Kind or "Status",
	}

	effect.Part = buildVisual(effect)
	table.insert(live, effect)
	return effect
end

-- Everything a player owns, dropped at once. Called when a fight ends, so a puddle cannot outlive
-- the encounter it was querying against.
function GroundEffectService.ClearFor(player: Player)
	for index = #live, 1, -1 do
		if live[index].Player == player then
			if live[index].Part then
				live[index].Part:Destroy()
			end
			table.remove(live, index)
		end
	end
end

local function centreOf(effect): Vector3
	if effect.Shape == "Line" then
		return (effect.From + effect.To) * 0.5
	end
	return effect.Position
end

-- Broad enough to reach any enemy that could possibly be inside, then narrowed exactly below. One
-- query per effect per tick rather than per enemy, which is what keeps this cheap with several
-- puddles down at once.
local function queryRadius(effect): number
	if effect.Shape == "Line" then
		return (effect.To - effect.From).Magnitude * 0.5 + effect.Radius
	end
	return effect.Radius
end

local function contains(effect, position: Vector3): boolean
	if effect.Shape == "Line" then
		return distanceToSegment(position, effect.From, effect.To) <= effect.Radius
	end
	return (position - effect.Position).Magnitude <= effect.Radius
end

-- One shared loop, same convention as ProjectileService's Heartbeat and the encounter tick. Stepped
-- on Heartbeat but gated by each effect's own NextTick, so a 1-second puddle does not run its
-- damage sixty times a second.
RunService.Heartbeat:Connect(function()
	local now = os.clock()

	for index = #live, 1, -1 do
		local effect = live[index]

		if now >= effect.ExpiresAt then
			if effect.Part then
				effect.Part:Destroy()
			end
			table.remove(live, index)
		elseif now >= effect.NextTick then
			effect.NextTick = now + effect.TickInterval

			if liveEnemiesNear then
				for _, record in ipairs(liveEnemiesNear(effect.Player, centreOf(effect), queryRadius(effect))) do
					local part = record.Model and record.Model.PrimaryPart
					if part and contains(effect, part.Position) then
						if effect.Status then
							StatusEffects.Apply(record, effect.Status.Key, effect.Status.Overrides)
						end
						if effect.DamagePerTick and effect.DamagePerTick > 0 then
							GroundEffectService.DealDamage(effect, record, part.Position)
						end
					end
				end
			end
		end
	end
end)

-- Assigned by CombatEncounterService alongside SetEnemyQuery. Separated so this file never has to
-- require the combat engine, which requires half the game.
function GroundEffectService.SetDamageHandler(fn)
	GroundEffectService.DealDamage = function(effect, record, at)
		fn(effect.Player, record, effect.DamagePerTick, at, effect.Kind)
	end
end

-- Until the handler is installed, a damaging effect is inert rather than an error.
GroundEffectService.DealDamage = function() end

return GroundEffectService
