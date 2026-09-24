--[[
	RunBuffService.lua
	Per-player RUN STATE for the Salvage Run shop rework (DESIGN_NOTES.md, "Raid shop rework —
	SPEC SETTLED 2026-09-22" / "Round 2 answers" / "BUILD CONTRACT"). A shared utility, not a
	service — no remotes of its own, same shape as `RaidHealBudget.lua` (which this file sits right
	next to in both purpose and lifecycle): `RaidRoomService` drives Begin/NewRoom/NewMap/End, and
	whoever needs a run-buff number just calls in.

	Everything a raid perk/gear/boss-card can do lives here so combat code (owned by sp-combat-dev,
	off limits to this file) never has to know `RunBuffConfig`'s shape — it calls
	`RunBuffService.DamageMultiplier(player)` etc. and gets a NEUTRAL value (1, false, {}, nil — see
	each function's own comment) for a player who isn't mid-raid, exactly like `RaidHealBudget.Get`
	returning nil outside a raid. No active record = not in a raid = every buff is off.

	State per player (records[userId]):
	  Owned        — { [itemKey] = { Rarity, Level, Paid } }, perks/gear bought this run.
	  Escape       — { [itemKey] = true }, one-use Escape items held this run.
	  BossCards    — array of RaidConfig.CardPool entries picked this run (unlimited, no slot).
	  Stats        — RunBuffConfig.Aggregate(Owned, BossCards), recomputed on every change so every
	                 query below is a plain field read, never a live re-sum.
	  RoomHealed/MapHealed — fractions of max HP already healed through Heal() this room/map, capped
	                 by RunBuffConfig.ShopHealCap (separate from RaidHealBudget's drone cap).
	  ShotCount    — persists for the whole raid, not reset per room — Overclock Chip's "every 10th
	                 shot" reads as "every 10th shot fired this raid," which is the more legible rule.
	  FightStartClock/FrenzyUntil — Rapid Feeder's opening burst and kill-frenzy windows.
	  VestShieldUsedThisRoom — Plated Vest Lv5, once per room.
	  BarrierLastDamageClock — Kinetic Barrier Lv4's "hasn't been hit in N seconds" refill.
	  GearVisuals/GearState — per-gear-item Instances and runtime bookkeeping (blade angle, drone
	                 aim clock, per-enemy hit cooldowns), destroyed and rebuilt lazily — see TickGear.

	Gear visuals fall back to plain Neon placeholders when `ServerStorage.RunGearModels` doesn't have
	a matching model, same "missing art never breaks the loop" contract every other content-driven
	system in this codebase follows (see CLAUDE.md).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local RunBuffConfig = require(ReplicatedStorage.Shared.RunBuffConfig)
local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local StatusEffects = require(script.Parent.StatusEffects)
-- The server's own copy of the player's HP — every health read and write in this file goes through
-- it rather than the Humanoid. See PlayerVitals.lua's header (2026-09-23 exploit review, F3).
local PlayerVitals = require(script.Parent.PlayerVitals)

local RunBuffService = {}

local RUN_GEAR_MODEL_FOLDER = "RunGearModels"
local BASE_MAX_HEALTH_ATTRIBUTE = "RunBaseMaxHealth"
local FIRE_RATE_ATTRIBUTE = "RunFireRateMult"

local records: { [number]: any } = {}

----------------------------------------------------------------------
-- Small internal helpers
----------------------------------------------------------------------

local function slotsUsedFor(record): number
	local count = 0
	for _ in pairs(record.Owned) do
		count += 1
	end
	return count
end

local function recomputeStats(record)
	record.Stats = RunBuffConfig.Aggregate(record.Owned, record.BossCards)
end

-- Restamps MaxHealth off the player's captured pre-raid base (BASE_MAX_HEALTH_ATTRIBUTE), keeping
-- Health proportional rather than snapping it — a level-up mid-fight must never kill (ratio > 1 on
-- a max-health INCREASE can't drop Health) or overheal past the new cap (clamp below).
local function applyMaxHealth(player: Player, record)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local base = player:GetAttribute(BASE_MAX_HEALTH_ATTRIBUTE)
	if not base then
		base = humanoid.MaxHealth
		player:SetAttribute(BASE_MAX_HEALTH_ATTRIBUTE, base)
	end

	local newMax = base * (1 + (record.Stats.MaxHpPct or 0))
	-- Compared against the SERVER's current Max, not the Humanoid's. They track each other (every
	-- PlayerVitals write mirrors both numbers onto the Humanoid), but this is a guard that decides
	-- whether to write at all — reading the client-writable copy here would let a client hold its
	-- MaxHealth at the target value to make this return early and leave the server's Max stale.
	local _, currentMax = PlayerVitals.Get(player)
	if math.abs(newMax - currentMax) < 0.01 then
		return
	end

	-- PlayerVitals owns both numbers inside a raid and carries the health across at the same
	-- fraction, which is exactly what the two lines this replaced did — the difference is that the
	-- ratio is now computed from the server's copy instead of from a Humanoid the client can write.
	PlayerVitals.SetMax(player, newMax)
end

local function computeFireRateMultiplier(record): number
	local stats = record.Stats
	local mult = 1 + (stats.FireRatePct or 0)
	local now = os.clock()
	if stats.OpeningBurstPct and record.FightStartClock and (now - record.FightStartClock) <= (stats.OpeningBurstSeconds or 0) then
		mult += stats.OpeningBurstPct
	end
	if now < record.FrenzyUntil then
		mult += (stats.KillFrenzyPct or 0)
	end
	return mult
end

----------------------------------------------------------------------
-- Gear visuals — lazily created the first time TickGear runs with a real `ctx.Root`, destroyed on
-- Sell, on End, and on every NewRoom (no Root to hang them on between rooms, and a stale aura/blade/
-- drone left floating in a room the player already left would look like a bug, not a feature).
----------------------------------------------------------------------

local function buildPlaceholderGearVisual(itemKey: string): Model?
	if itemKey == "ScorchAura" then
		local model = Instance.new("Model")
		model.Name = "ScorchAura_Visual"
		local ring = Instance.new("Part")
		ring.Name = "AuraRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.3, 10, 10) -- resized to match radius every tick, see updateAuraVisual
		ring.Color = Color3.fromRGB(255, 110, 40)
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.55
		ring.Anchored = false -- welded to the wearer's root in ensureGearVisual; an Anchored part can't be welded
		ring.Parent = model
		model.PrimaryPart = ring
		return model
	elseif itemKey == "LaserDrone" then
		local model = Instance.new("Model")
		model.Name = "LaserDrone_Visual"
		local drone = Instance.new("Part")
		drone.Name = "Drone"
		drone.Shape = Enum.PartType.Ball
		drone.Size = Vector3.new(1, 1, 1)
		drone.Color = Color3.fromRGB(90, 210, 255)
		drone.Material = Enum.Material.Neon
		drone.Parent = model
		model.PrimaryPart = drone
		return model
	end
	warn(("[RunBuffService] No placeholder visual builder for gear item %q."):format(itemKey))
	return nil
end

local function sanitizeVisualParts(model: Model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
		end
	end
end

-- Generic single-model gear visual (ScorchAura ring, LaserDrone body) — NOT OrbitBlades, whose part
-- count varies with level and gets its own builder below.
local function ensureGearVisual(record, itemKey: string, root: BasePart): Model?
	local visual = record.GearVisuals[itemKey]
	if visual and visual.Parent then
		return visual
	end
	if visual then
		visual:Destroy()
	end

	local folder = ServerStorage:FindFirstChild(RUN_GEAR_MODEL_FOLDER)
	local template = folder and folder:FindFirstChild(itemKey)
	local model = (template and template:IsA("Model") and template:Clone()) or buildPlaceholderGearVisual(itemKey)
	if not model then
		return nil
	end
	sanitizeVisualParts(model)
	model.Parent = root.Parent or Workspace
	record.GearVisuals[itemKey] = model

	-- How the client finds this visual to drive it (see ScorchAuraVisual.client.lua). An attribute
	-- rather than the model's name, because a real model cloned from ServerStorage.RunGearModels
	-- keeps the TEMPLATE's name and only the placeholder builder's models are named "<Key>_Visual" --
	-- a name-based lookup would work right up until the art landed.
	model:SetAttribute("RunGearItem", itemKey)

	if itemKey == "ScorchAura" then
		-- The ring stays ANCHORED (sanitizeVisualParts already made it so) and the client positions
		-- it every RenderStepped. Both halves of that matter, and the history is worth keeping
		-- because two earlier attempts each fixed one half and broke the other:
		--
		-- It was originally Anchored and repositioned from a server Heartbeat, which runs after the
		-- frame the player is looking at AND has to cross the network before the client sees the
		-- move -- so the ring always chased where the player WAS. That was replication lag, not the
		-- CFrame maths (an absolute CFrame.new and a relative CFrame * CFrame arrive on the same
		-- schedule), which is what the first diagnosis got wrong.
		--
		-- Welding it to the root fixed the lag by handing position to the client's own physics, but
		-- a weld is RIGID: jumping carried the ring up into the air with you, so the thing drawn as
		-- a zone on the floor stopped being on the floor. Positioning it on the CLIENT gets both --
		-- the client's own frame, no round trip, and a Y that can be decoupled from the character's.
		--
		-- The server writes its CFrame exactly once, here, so the client's per-frame local writes
		-- are never fought or overwritten; without this one write it would sit visibly at the world
		-- origin for the frame before the client's first pass. The Z rotation (not X -- see
		-- updateAuraVisual for why Z is the axis that lays a Cylinder-shaped Part's disc flat) now
		-- lives in the client's CFrame instead of a weld's C0.
		local ring = model.PrimaryPart or model:FindFirstChild("AuraRing")
		if ring and ring:IsA("BasePart") then
			ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90))
		end
	end

	return model
end

-- Shared by the server (which decides what the blades cut) and OrbitBladesVisual.client.lua (which
-- draws them). Deriving the angle from Workspace:GetServerTimeNow() -- a clock synchronized between
-- server and clients -- rather than accumulating it per tick means both sides arrive at the same
-- answer from the same inputs, with no message passing and no drift to accumulate. That is what
-- makes it safe to let the client own position here: the blade you see IS the blade that hits.
--
-- It replaced `state.Angle += dt * 2`, which was fine as long as only the server cared, but an
-- accumulated angle is unreproducible by definition -- nothing the client could do would land on
-- the same value.
local function orbitBladeOffset(radius: number, index: number, count: number): Vector3
	local angle = Workspace:GetServerTimeNow() * RunBuffConfig.Items.OrbitBlades.Base.OrbitSpeed
		+ (index - 1) * (2 * math.pi / count)
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function ensureOrbitBladesVisual(record, root: BasePart, count: number, radius: number): Model?
	local visual = record.GearVisuals.OrbitBlades
	if visual and visual.Parent and visual:GetAttribute("BladeCount") == count then
		return visual
	end
	if visual then
		visual:Destroy()
	end

	local folder = ServerStorage:FindFirstChild(RUN_GEAR_MODEL_FOLDER)
	local template = folder and folder:FindFirstChild("OrbitBlades")

	local model = Instance.new("Model")
	model.Name = "OrbitBlades_Visual"
	model:SetAttribute("BladeCount", count)
	-- How OrbitBladesVisual.client.lua finds this, and how wide it knows to swing. Same attribute
	-- convention ensureGearVisual uses for the other gear visuals; OrbitBlades needs its own copy
	-- because this function builds it instead of that one. OrbitRadius is kept current by
	-- GearBehaviors.OrbitBlades, since a level-up changes the radius without changing the blade
	-- COUNT and so does not rebuild this model.
	model:SetAttribute("RunGearItem", "OrbitBlades")
	model:SetAttribute("OrbitRadius", radius)
	for i = 1, count do
		local blade
		if template and template:IsA("BasePart") then
			blade = template:Clone()
		else
			blade = Instance.new("WedgePart")
			blade.Size = Vector3.new(1, 0.4, 2)
			blade.Color = Color3.fromRGB(255, 90, 60)
			blade.Material = Enum.Material.Neon
		end
		blade.Name = "Blade" .. tostring(i)
		blade.Parent = model
	end
	sanitizeVisualParts(model)

	-- Positioned once, here, and never again by the server -- the client drives them every
	-- RenderStepped after this. Without this one write they would sit at the world origin for the
	-- frame before the client's first pass, which reads as the blades spawning across the map.
	for i = 1, count do
		local blade = model:FindFirstChild("Blade" .. tostring(i))
		if blade and blade:IsA("BasePart") then
			blade.CFrame = CFrame.new(root.Position + orbitBladeOffset(radius, i, count))
		end
	end

	model.Parent = root.Parent or Workspace
	record.GearVisuals.OrbitBlades = model
	return model
end

local function updateAuraVisual(visual: Model, radius: number)
	local ring = visual.PrimaryPart or visual:FindFirstChild("AuraRing")
	if ring and ring:IsA("BasePart") then
		-- Position is not this function's job -- ScorchAuraVisual.client.lua sets the ring's CFrame on
		-- the client, every RenderStepped, so it rides the player's own frame with no replication delay
		-- AND keeps its Y on the floor through a jump. Only the level-scaled radius needs a live
		-- server-side update, since size is not something the client has any business deciding.
		--
		-- A flat approximation is fine here — this is a placeholder, replaced wholesale by a real
		-- model the moment ServerStorage.RunGearModels.ScorchAura exists.
		--
		-- Rotated about Z, NOT X (this shaped the weld's C0 in ensureGearVisual too). A Part with
		-- Shape = Cylinder has its axis along LOCAL X — Size.X is the cylinder's thickness and
		-- Size.Y/Z are its diameter — so this disc's flat faces point along X and it stands upright
		-- by default, like a coin on its edge. Rotating about X spins it around its own axis and
		-- changes nothing you can see; it takes a rotation about Z to swing local X up to world Y
		-- and lay the disc flat on the ground. `CFrame.Angles(math.rad(90), 0, 0)` was therefore a
		-- no-op, and with the 3-stud drop it rendered as an upright disc half-buried in the floor —
		-- a dome standing beside the player rather than a ring around them.
		ring.Size = Vector3.new(0.3, radius * 2, radius * 2)
	end
end

local function drawBeam(visual: Model, targetPosition: Vector3)
	local drone = visual:FindFirstChild("Drone")
	if not (drone and drone:IsA("BasePart")) then
		return
	end
	local from = drone.Position
	local distance = (targetPosition - from).Magnitude
	if distance < 0.1 then
		return
	end
	local beam = Instance.new("Part")
	beam.Name = "Beam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Massless = true
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(90, 210, 255)
	beam.Size = Vector3.new(0.15, 0.15, distance)
	beam.CFrame = CFrame.new(from, targetPosition) * CFrame.new(0, 0, -distance / 2)
	beam.Parent = visual
	Debris:AddItem(beam, 0.12)
end

local function destroyGearVisual(record, itemKey: string)
	local visual = record.GearVisuals[itemKey]
	if visual then
		visual:Destroy()
		record.GearVisuals[itemKey] = nil
	end
	record.GearState[itemKey] = nil
end

----------------------------------------------------------------------
-- Gear behaviors — flat table of named strategies keyed by item key, the project's standard shape
-- (CLAUDE.md: EnemyAI.Patterns/RobotBehaviors precedent). TickGear below guards the lookup and warns
-- on a miss rather than erroring mid-encounter.
----------------------------------------------------------------------

local GearBehaviors = {}

GearBehaviors.ScorchAura = function(record, owned, dt: number, ctx)
	local item = RunBuffConfig.Items.ScorchAura
	local levelStats = RunBuffConfig.LevelStats("ScorchAura", owned.Level)
	local radius = item.Base.Radius * (1 + (levelStats.RadiusPct or 0))
	local tickSeconds = item.Base.TickSeconds
	local height = item.Base.Height
	local dps = levelStats.DamagePerSecond or 0

	local state = record.GearState.ScorchAura
	if not state then
		state = { NextTick = 0 }
		record.GearState.ScorchAura = state
	end

	if ctx.Root then
		local visual = ensureGearVisual(record, "ScorchAura", ctx.Root)
		if visual then
			updateAuraVisual(visual, radius)
		end
	end

	local now = os.clock()
	if now < state.NextTick or not ctx.Root or dps <= 0 then
		return
	end
	state.NextTick = now + tickSeconds

	local damage = dps * tickSeconds
	for _, enemyRecord in ipairs(ctx.Enemies or {}) do
		local part = enemyRecord.Model and enemyRecord.Model.PrimaryPart
		if part and enemyRecord.Humanoid and enemyRecord.Humanoid.Health > 0 then
			-- Measured on the FLOOR PLANE, not as a sphere around the root. The ring is drawn flat on
			-- the ground under you, so reach has to be the horizontal distance to match it -- a
			-- straight 3D magnitude from a root ~3 studs up meant that jumping tilted every enemy out
			-- of range at the rim while the ring on the floor still showed them inside it. Height
			-- bounds it vertically so this is a column, not an infinite one: an enemy on a gantry
			-- above you, or on the floor below a ledge you jumped off, is not standing in your ring.
			-- Both terms come off ctx.Root, whose X/Z is exactly the X/Z the client draws the ring at,
			-- so the horizontal half cannot drift from the visual at all.
			local offset = part.Position - ctx.Root.Position
			local horizontal = Vector2.new(offset.X, offset.Z).Magnitude
			if horizontal <= radius and math.abs(offset.Y) <= height then
				ctx.DealDamage(enemyRecord, damage, "ScorchAura")
				if levelStats.Status then
					ctx.ApplyStatus(enemyRecord, levelStats.Status)
				end
			end
		end
	end
end

GearBehaviors.OrbitBlades = function(record, owned, dt: number, ctx)
	local item = RunBuffConfig.Items.OrbitBlades
	local levelStats = RunBuffConfig.LevelStats("OrbitBlades", owned.Level)
	local bladeCount = item.Base.Blades + (levelStats.ExtraBlades or 0)
	-- Was item.Base.OrbitRadius flat: the blades were the one piece of gear whose reach never grew,
	-- at any level or rarity. Scaled the same way ScorchAura's ring already was, and from the same
	-- value the hit test below uses, so the blades can never be drawn wider than they actually cut.
	local radius = item.Base.OrbitRadius * (1 + (levelStats.OrbitRadiusPct or 0))
	local hitCooldown = item.Base.HitCooldown
	local damagePerHit = levelStats.DamagePerHit or 0
	local hitRadius = 3 -- studs; a blade "passes within ~3 studs" per the design ask, not worth a config entry

	if not ctx.Root then
		return
	end

	local state = record.GearState.OrbitBlades
	if not state then
		-- No Angle field any more: the orbit is a pure function of the synchronized clock (see
		-- orbitBladeOffset), not a value this service accumulates and owns. HitClocks stays, because
		-- per-blade-per-target cooldown genuinely is server state.
		state = { HitClocks = {} }
		record.GearState.OrbitBlades = state
	end

	local visual = ensureOrbitBladesVisual(record, ctx.Root, bladeCount, radius)
	if not visual then
		return
	end
	-- A level-up changes the radius without changing the blade COUNT, so it does not rebuild the
	-- model above — the attribute has to be refreshed here or the client keeps drawing the old
	-- orbit while the server cuts at the new one. Written only on a change: an attribute set every
	-- tick is a replicated property write every tick, which is the cost this whole change exists to
	-- remove.
	if visual:GetAttribute("OrbitRadius") ~= radius then
		visual:SetAttribute("OrbitRadius", radius)
	end

	local now = os.clock()
	for i = 1, bladeCount do
		-- The blade's position is COMPUTED, not read off the part. It has to be: the server no
		-- longer moves those parts (OrbitBladesVisual.client.lua does, on the client, which is the
		-- whole point), so `blade.Position` here would be whatever the last server write left behind
		-- — frozen at spawn. Reading the formula instead also makes the hit test independent of the
		-- visual existing at all, which is the right dependency direction for something
		-- server-authoritative.
		local bladePosition = ctx.Root.Position + orbitBladeOffset(radius, i, bladeCount)

		for _, enemyRecord in ipairs(ctx.Enemies or {}) do
			local part = enemyRecord.Model and enemyRecord.Model.PrimaryPart
			if part and enemyRecord.Humanoid and enemyRecord.Humanoid.Health > 0 then
				if (part.Position - bladePosition).Magnitude <= hitRadius then
					local key = tostring(enemyRecord.Model) .. "#" .. tostring(i)
					local last = state.HitClocks[key] or 0
					if now - last >= hitCooldown then
						state.HitClocks[key] = now
						ctx.DealDamage(enemyRecord, damagePerHit, "OrbitBlades")
						if levelStats.Status then
							ctx.ApplyStatus(enemyRecord, levelStats.Status)
						end
					end
				end
			end
		end
	end
end

GearBehaviors.LaserDrone = function(record, owned, dt: number, ctx)
	local item = RunBuffConfig.Items.LaserDrone
	local levelStats = RunBuffConfig.LevelStats("LaserDrone", owned.Level)
	local range = item.Base.Range
	local shotsPerSecond = item.Base.ShotsPerSecond * (1 + (levelStats.FireRatePct or 0))
	local damagePerShot = levelStats.DamagePerShot or 0
	local extraBeams = levelStats.ExtraBeams or 0

	if not ctx.Root then
		return
	end

	local state = record.GearState.LaserDrone
	if not state then
		state = { NextShot = 0 }
		record.GearState.LaserDrone = state
	end

	local visual = ensureGearVisual(record, "LaserDrone", ctx.Root)
	if visual and visual.PrimaryPart then
		visual.PrimaryPart.CFrame = ctx.Root.CFrame * CFrame.new(2, 3, 0)
	end

	local now = os.clock()
	if now < state.NextShot or shotsPerSecond <= 0 or damagePerShot <= 0 then
		return
	end

	local candidates = {}
	for _, enemyRecord in ipairs(ctx.Enemies or {}) do
		local part = enemyRecord.Model and enemyRecord.Model.PrimaryPart
		if part and enemyRecord.Humanoid and enemyRecord.Humanoid.Health > 0 then
			local distance = (part.Position - ctx.Root.Position).Magnitude
			if distance <= range then
				table.insert(candidates, { Record = enemyRecord, Part = part, Distance = distance })
			end
		end
	end
	if #candidates == 0 then
		return
	end
	table.sort(candidates, function(a, b)
		return a.Distance < b.Distance
	end)

	state.NextShot = now + 1 / shotsPerSecond
	local shots = math.min(1 + extraBeams, #candidates)
	for i = 1, shots do
		local target = candidates[i]
		ctx.DealDamage(target.Record, damagePerShot, "LaserDrone")
		if visual then
			drawBeam(visual, target.Part.Position)
		end
	end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function RunBuffService.Begin(player: Player)
	records[player.UserId] = {
		Player = player,
		Owned = {},
		Escape = {},
		BossCards = {},
		Stats = {},
		RoomHealed = 0,
		MapHealed = 0,
		ShotCount = 0, -- persists the whole raid, deliberately not reset per room — see header comment
		-- Run tallies for the end-of-run summary screen. They live on THIS record rather than on the
		-- raid state because everything that produces them already reaches RunBuffService: kills go
		-- through OnKill, which the damage funnel already calls on exactly the hits that count, and
		-- NewRoom below is already the per-room boundary BestRoomDamage needs. Putting them on the
		-- raid state instead would have meant a second hook alongside each of those.
		Kills = 0,
		DamageDealt = 0,
		RoomDamage = 0, -- current room only; folded into BestRoomDamage and reset by NewRoom
		BestRoomDamage = 0,
		FightStartClock = nil :: number?,
		FrenzyUntil = 0,
		VestShieldUsedThisRoom = false,
		BarrierLastDamageClock = os.clock(),
		GearVisuals = {},
		GearState = {},
	}
	player:SetAttribute(FIRE_RATE_ATTRIBUTE, 1)
	applyMaxHealth(player, records[player.UserId])
end

function RunBuffService.End(player: Player)
	local record = records[player.UserId]
	if record then
		for itemKey in pairs(record.GearVisuals) do
			destroyGearVisual(record, itemKey)
		end
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local base = player:GetAttribute(BASE_MAX_HEALTH_ATTRIBUTE)
	if humanoid and base then
		-- Same ratio-preserving restore as applyMaxHealth, same reason for going through
		-- PlayerVitals. Note this runs BEFORE PlayerActivityService.Release (cleanupRaid calls
		-- RunBuffService.End first), so the raid's tracking is still live here and the write lands
		-- on the server's copy rather than only on the Humanoid.
		PlayerVitals.SetMax(player, base)
	end
	player:SetAttribute(BASE_MAX_HEALTH_ATTRIBUTE, nil)
	player:SetAttribute(FIRE_RATE_ATTRIBUTE, nil)
	records[player.UserId] = nil
end

-- Every node entry (Start/Combat/Ambush/Heal/Shop/Boss alike), same as RaidHealBudget.NewNode — the
-- per-room heal allowance refills and one-per-room triggers (Vest Lv5) reset. Gear visuals are torn
-- down here too; TickGear rebuilds them lazily the moment the next combat encounter has a Root.
function RunBuffService.NewRoom(player: Player)
	local record = records[player.UserId]
	if not record then
		return
	end
	record.RoomHealed = 0
	record.VestShieldUsedThisRoom = false
	-- Close out the room that just ended before zeroing: this is the only boundary that knows where
	-- one room's damage stops, so "best room" is banked here rather than recomputed later.
	if record.RoomDamage > record.BestRoomDamage then
		record.BestRoomDamage = record.RoomDamage
	end
	record.RoomDamage = 0
	for itemKey in pairs(record.GearVisuals) do
		destroyGearVisual(record, itemKey)
	end
end

-- Run tallies for the end-of-run summary. Called from the one place every credited hit already
-- funnels through (CombatEncounterService.resolveAndApplyDamage), so nothing that can damage an
-- enemy on the player's behalf — guns, robots, gear, statuses, Ultimates, turrets — is missed.
-- No-ops outside a raid, same as every other entry point here.
function RunBuffService.RecordDamage(player: Player, amount: number)
	local record = records[player.UserId]
	if not record or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	record.DamageDealt += amount
	record.RoomDamage += amount
end

-- What the summary screen reports. Returns zeros rather than nil outside a raid so the caller never
-- has to branch. BestRoomDamage is max'd against the CURRENT room here because the run usually ends
-- inside a room rather than on a NewRoom boundary — without this, the room you extracted from (very
-- often the biggest one) would never be considered.
function RunBuffService.RunTallies(player: Player): (number, number, number)
	local record = records[player.UserId]
	if not record then
		return 0, 0, 0
	end
	return record.Kills, record.DamageDealt, math.max(record.BestRoomDamage, record.RoomDamage)
end

function RunBuffService.NewMap(player: Player)
	local record = records[player.UserId]
	if not record then
		return
	end
	record.RoomHealed = 0
	record.MapHealed = 0
	record.VestShieldUsedThisRoom = false
end

function RunBuffService.Get(player: Player)
	return records[player.UserId]
end

----------------------------------------------------------------------
-- Mutations
----------------------------------------------------------------------

-- offer: { ItemKey: string, Rarity: string, Price: number } — always server-built (RaidRoomService
-- looks it up by OfferId from its own rolled stock), never taken raw from the client.
function RunBuffService.Buy(player: Player, offer): (boolean, string?)
	local record = records[player.UserId]
	if not record then
		return false, "NotInRaid"
	end
	local item = RunBuffConfig.Items[offer.ItemKey]
	if not item then
		return false, "UnknownItem"
	end

	if item.Kind == "Escape" then
		local preview = RunBuffConfig.PreviewOffer(record.Escape[offer.ItemKey], offer, slotsUsedFor(record))
		if preview.Blocked then
			return false, preview.Blocked
		end
		record.Escape[offer.ItemKey] = true
		return true
	end

	local owned = record.Owned[offer.ItemKey]
	local preview = RunBuffConfig.PreviewOffer(owned, offer, slotsUsedFor(record))
	if preview.Blocked then
		return false, preview.Blocked
	end

	if preview.IsNew then
		record.Owned[offer.ItemKey] = { Rarity = offer.Rarity, Level = 1, Paid = offer.Price }
	elseif preview.RarityUp then
		owned.Rarity = offer.Rarity
		owned.Paid += offer.Price
	else
		owned.Level = preview.ToLv
		owned.Paid += offer.Price
	end

	recomputeStats(record)
	applyMaxHealth(player, record)
	return true
end

-- Dev tool — see AdminService's /giverunbuff. The ONE deliberate difference from Buy above: this
-- skips RunBuffConfig.PreviewOffer entirely, so it can jump straight to Legendary level 5 instead of
-- climbing one rarity-up or one level per purchase — that IS the point of the command. It still
-- honours RunBuffConfig.Slots, though: the HUD draws a fixed number of slot tiles, and a 5th owned
-- item would have nowhere to render.
function RunBuffService.DevGrant(player: Player, itemKey: string, rarity: string?, level: number?): (boolean, string?)
	local record = records[player.UserId]
	if not record then
		return false, "NotInRaid"
	end
	local item = RunBuffConfig.Items[itemKey]
	if not item then
		return false, "UnknownItem"
	end

	if item.Kind == "Escape" then
		-- No rarity, no level, no slot — same one-line grant Buy gives an Escape item.
		record.Escape[itemKey] = true
		return true
	end

	-- Defaults to the LAST entry of Rarities (the highest the item offers) — a dev asking for "just
	-- give me this" almost always means the best version.
	rarity = rarity or item.Rarities[#item.Rarities]
	local rarityValid = false
	for _, candidate in ipairs(item.Rarities) do
		if candidate == rarity then
			rarityValid = true
			break
		end
	end
	if not rarityValid then
		return false, "BadRarity"
	end

	-- Clamped, not rejected: a dev asking for level 9 obviously wants the maximum, not an error.
	local cap = RunBuffConfig.RarityCaps[rarity]
	level = math.clamp(level or cap, 1, cap)

	local owned = record.Owned[itemKey]
	if not owned and slotsUsedFor(record) >= RunBuffConfig.Slots then
		return false, "SlotsFull"
	end

	-- Preserve an existing entry's Paid so a later Sell still refunds what was genuinely paid for
	-- it — a dev grant itself counts as free.
	record.Owned[itemKey] = { Rarity = rarity, Level = level, Paid = owned and owned.Paid or 0 }

	recomputeStats(record)
	applyMaxHealth(player, record)
	return true
end

function RunBuffService.Sell(player: Player, itemKey: string): (boolean, number)
	local record = records[player.UserId]
	if not record then
		return false, 0
	end
	local owned = record.Owned[itemKey]
	if not owned then
		return false, 0
	end

	local refund = math.floor(owned.Paid * RunBuffConfig.SellRefund)
	record.Owned[itemKey] = nil
	destroyGearVisual(record, itemKey)
	recomputeStats(record)
	applyMaxHealth(player, record)
	return true, refund
end

function RunBuffService.AddBossCard(player: Player, card)
	local record = records[player.UserId]
	if not record then
		return
	end
	table.insert(record.BossCards, card)
	recomputeStats(record)
	applyMaxHealth(player, record)
end

function RunBuffService.ConsumeEscape(player: Player, itemKey: string): boolean
	local record = records[player.UserId]
	if not record or not record.Escape[itemKey] then
		return false
	end
	record.Escape[itemKey] = nil
	return true
end

function RunBuffService.SlotsUsed(player: Player): number
	local record = records[player.UserId]
	if not record then
		return 0
	end
	return slotsUsedFor(record)
end

----------------------------------------------------------------------
-- Combat queries — every one below is a neutral value (1 / false / 0 / nil, as noted) for a player
-- with no active record, so combat code never has to special-case "not in a raid" itself.
----------------------------------------------------------------------

function RunBuffService.DamageMultiplier(player: Player): number
	local record = records[player.UserId]
	if not record then
		return 1
	end
	return 1 + (record.Stats.DamagePct or 0)
end

-- Rolls a crit for one shot: increments the persistent shot counter (Overclock Chip Lv5's "every
-- Nth shot"), then a guaranteed crit check, then the flat CritChance roll (Lv4+). Returns
-- isCrit, mult — mult is always RunBuffConfig.CritMultiplier when isCrit, 1 otherwise, so a caller
-- can multiply unconditionally.
function RunBuffService.RollCrit(player: Player): (boolean, number)
	local record = records[player.UserId]
	if not record then
		return false, 1
	end
	record.ShotCount += 1
	local stats = record.Stats

	local every = stats.GuaranteedCritEvery
	if every and every > 0 and record.ShotCount % every == 0 then
		return true, RunBuffConfig.CritMultiplier
	end
	local chance = stats.CritChance or 0
	if chance > 0 and math.random() < chance then
		return true, RunBuffConfig.CritMultiplier
	end
	return false, 1
end

function RunBuffService.FireRateMultiplier(player: Player): number
	local record = records[player.UserId]
	if not record then
		return 1
	end
	local mult = computeFireRateMultiplier(record)
	player:SetAttribute(FIRE_RATE_ATTRIBUTE, mult)
	return mult
end

-- Elite/boss damage reduction (Plated Vest Lv4). `enemyRecord.TypeKey` is checked against BOTH
-- EnemyConfig.EliteTypes and BossTypes since either can hit a raid player — see EnemyConfig's own
-- comment on why the two pools are split but a raid Combat room can still roll an elite.
function RunBuffService.DamageTakenMultiplier(player: Player, enemyRecord): number
	local record = records[player.UserId]
	if not record or not enemyRecord then
		return 1
	end
	local pct = record.Stats.EliteBossDamageTakenPct
	if not pct then
		return 1
	end
	local typeKey = enemyRecord.TypeKey
	if typeKey and (EnemyConfig.EliteTypes[typeKey] or EnemyConfig.BossTypes[typeKey]) then
		return math.max(0, 1 + pct) -- pct is negative (e.g. -0.10); clamped so a future stack can't invert damage
	end
	return 1
end

function RunBuffService.LootMultiplier(player: Player): number
	local record = records[player.UserId]
	if not record then
		return 1
	end
	return 1 + (record.Stats.LootPct or 0)
end

function RunBuffService.ChestHoldSeconds(player: Player): number?
	local record = records[player.UserId]
	if not record then
		return nil
	end
	return record.Stats.ChestHoldSeconds
end

function RunBuffService.ChestBonusItems(player: Player): number
	local record = records[player.UserId]
	if not record then
		return 0
	end
	return record.Stats.ChestBonusItems or 0
end

----------------------------------------------------------------------
-- Combat hooks — called by CombatEncounterService/DamagePipeline (sp-combat-dev's files); this
-- module never calls into them.
----------------------------------------------------------------------

-- playerState: CombatEncounterService's per-encounter table (has a `.Shield` field the damage
-- pipeline already reads/writes — see that file's damageTarget). Stamps the fight-start clock
-- (Rapid Feeder's opening burst) and grants Kinetic Barrier's shield, topped up rather than
-- overwritten so a Barrier applied mid-fight (a card, say) never LOWERS an existing shield.
function RunBuffService.OnFightStart(player: Player, playerState)
	local record = records[player.UserId]
	if not record then
		return
	end
	record.FightStartClock = os.clock()
	record.FrenzyUntil = 0
	record.BarrierLastDamageClock = os.clock()
	-- Kept so OnRoomCleared (called from RaidRoomService, which has no playerState) can still land
	-- Nano Repair Lv5's overheal shield on the encounter that just ended.
	record.PlayerState = playerState

	local shieldPct = record.Stats.ShieldPctOfMaxHp
	if shieldPct and shieldPct > 0 and playerState then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local maxHealth = (humanoid and humanoid.MaxHealth) or 100
		playerState.Shield = math.max(playerState.Shield or 0, shieldPct * maxHealth)
	end

	RunBuffService.FireRateMultiplier(player) -- refresh the client attribute at the new fight's t=0
end

-- Marks the last-damage clock (Barrier Lv4's refill timer) and fires Plated Vest Lv5's once-per-room
-- low-HP shield. `humanoid` is passed in rather than re-resolved from `player.Character` because the
-- caller already has it mid-damage-pipeline.
function RunBuffService.OnPlayerDamaged(player: Player, playerState, humanoid: Humanoid?)
	local record = records[player.UserId]
	if not record then
		return
	end
	record.BarrierLastDamageClock = os.clock()

	local stats = record.Stats
	-- Server's numbers, not the Humanoid's: this is a buff that fires when you drop BELOW a
	-- threshold, so reading a client-written Health would let a client decide when to hand itself a
	-- free shield.
	local currentHealth, currentMax = PlayerVitals.Get(player)
	if stats.LowHpShieldThreshold and stats.LowHpShieldPct and not record.VestShieldUsedThisRoom
		and humanoid and currentMax > 0 then
		if (currentHealth / currentMax) < stats.LowHpShieldThreshold then
			record.VestShieldUsedThisRoom = true
			if playerState then
				playerState.Shield = (playerState.Shield or 0) + stats.LowHpShieldPct * currentMax
			end
		end
	end
end

-- Kinetic Barrier Lv5: the shield breaking knocks nearby enemies back. ctx = { Enemies, Root }.
-- Kept simple per the build contract — a velocity shove plus a brief Stun, not a full physics
-- impulse system.
function RunBuffService.OnShieldBroken(player: Player, ctx)
	local record = records[player.UserId]
	if not record or not ctx or not ctx.Root then
		return
	end
	local radius = record.Stats.BreakKnockbackRadius
	local force = record.Stats.BreakKnockbackForce
	if not radius or not force then
		return
	end

	for _, enemyRecord in ipairs(ctx.Enemies or {}) do
		local part = enemyRecord.Model and enemyRecord.Model.PrimaryPart
		if part and enemyRecord.Humanoid and enemyRecord.Humanoid.Health > 0 then
			local offset = part.Position - ctx.Root.Position
			local distance = offset.Magnitude
			if distance <= radius then
				local direction = distance > 0.1 and offset.Unit or Vector3.new(1, 0, 0)
				pcall(function()
					part.AssemblyLinearVelocity = direction * force + Vector3.new(0, force * 0.25, 0)
				end)
				StatusEffects.Apply(enemyRecord, "Stun", { Duration = 0.6 })
			end
		end
	end
end

-- Per-tick upkeep: refreshes the fire-rate attribute (so an opening burst/frenzy window's END shows
-- up on the client even between shots) and Kinetic Barrier Lv4's mid-room refill.
function RunBuffService.Tick(player: Player, dt: number, playerState)
	local record = records[player.UserId]
	if not record then
		return
	end
	RunBuffService.FireRateMultiplier(player)

	local stats = record.Stats
	if stats.RefillAfterSeconds and stats.ShieldPctOfMaxHp and playerState and (playerState.Shield or 0) <= 0 then
		local now = os.clock()
		if now - record.BarrierLastDamageClock >= stats.RefillAfterSeconds then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local maxHealth = (humanoid and humanoid.MaxHealth) or 100
			playerState.Shield = stats.ShieldPctOfMaxHp * maxHealth
			record.BarrierLastDamageClock = now -- don't re-refill every tick once topped up
		end
	end
end

function RunBuffService.OnKill(player: Player, enemyRecord)
	local record = records[player.UserId]
	if not record then
		return
	end
	-- Counted here rather than through a hook of its own: the damage funnel already calls this on
	-- exactly the hits that take an enemy from alive to dead and are credited to a player, which is
	-- the definition the summary screen wants anyway.
	record.Kills += 1
	local stats = record.Stats
	if stats.KillHealPct and stats.KillHealPct > 0 then
		RunBuffService.Heal(player, stats.KillHealPct)
	end
	if stats.KillFrenzyPct and stats.KillFrenzySeconds then
		record.FrenzyUntil = os.clock() + stats.KillFrenzySeconds
		RunBuffService.FireRateMultiplier(player)
	end
end

-- Nano Repair's room-clear heal. `playerState` is optional and only reachable from a call site
-- INSIDE CombatEncounterService's own cleared branch — RaidRoomService's call (Combat/Ambush/Boss
-- cleared) doesn't have one in scope, since RunRaidCombat's playerState is local to that function.
-- Without it, Lv5's overheal-to-shield simply doesn't trigger — it's a bonus on top of the heal, not
-- the heal itself, so skipping it there costs nothing but that one edge case.
function RunBuffService.OnRoomCleared(player: Player, playerState)
	local record = records[player.UserId]
	if not record then
		return
	end
	local stats = record.Stats
	if not (stats.RoomClearHealPct and stats.RoomClearHealPct > 0) then
		return
	end
	local _, overflow = RunBuffService.Heal(player, stats.RoomClearHealPct)
	-- Nano Repair Lv5: the part of the heal that had no missing HP to fill becomes shield instead of
	-- being wasted. Heal() already charged the budget for it, so the 25%/room cap still holds.
	playerState = playerState or record.PlayerState
	if stats.OverhealToShield and playerState and overflow > 0 then
		playerState.Shield = (playerState.Shield or 0) + overflow
	end
end

-- Heals `fraction` of max HP, clamped by RunBuffConfig.ShopHealCap's PerRoom/PerMap budgets (separate
-- pool from RaidHealBudget's drone cap — see this file's header). Returns the actual HP restored.
function RunBuffService.Heal(player: Player, fraction: number): (number, number)
	local record = records[player.UserId]
	if not record or fraction <= 0 then
		return 0, 0
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	-- All four health numbers below come from PlayerVitals rather than the Humanoid. They have to:
	-- this function both charges a per-room/per-map budget by how much actually landed AND decides
	-- whether you were hurt enough to heal at all, so a client-written Health would buy free budget.
	local currentHealth, maxHealth = PlayerVitals.Get(player)
	if not humanoid or currentHealth <= 0 or maxHealth <= 0 then
		return 0, 0
	end

	local roomRemaining = math.max(0, RunBuffConfig.ShopHealCap.PerRoom - record.RoomHealed)
	local mapRemaining = math.max(0, RunBuffConfig.ShopHealCap.PerMap - record.MapHealed)
	local allowedFraction = math.min(fraction, roomRemaining, mapRemaining)
	if allowedFraction <= 0 then
		return 0, 0
	end

	local allowedAmount = allowedFraction * maxHealth
	local actualAmount = PlayerVitals.Heal(player, allowedAmount)

	-- Only Nano Repair Lv5 turns the overflow into shield, and only then is it spent from the budget;
	-- everyone else is charged for what actually landed.
	local overflow = 0
	local chargedFraction = actualAmount / maxHealth
	if record.Stats.OverhealToShield then
		overflow = allowedAmount - actualAmount
		chargedFraction = allowedFraction
	end
	record.RoomHealed += chargedFraction
	record.MapHealed += chargedFraction
	return actualAmount, overflow
end

-- ctx = { Root: BasePart, Enemies: {enemyRecord,...}, DealDamage: (record, amount, sourceTag) -> (),
--         ApplyStatus: (record, statusKey) -> () }. Ticks every owned Gear item through
-- GearBehaviors, guarded + warned on a missing entry (CLAUDE.md's strategy-table convention).
function RunBuffService.TickGear(player: Player, dt: number, ctx)
	local record = records[player.UserId]
	if not record then
		return
	end
	for itemKey, owned in pairs(record.Owned) do
		local item = RunBuffConfig.Items[itemKey]
		if item and item.Kind == "Gear" then
			local behavior = GearBehaviors[itemKey]
			if behavior then
				behavior(record, owned, dt, ctx)
			else
				warn(("[RunBuffService] No GearBehaviors entry for gear item %q — it does nothing this tick."):format(itemKey))
			end
		end
	end
end

----------------------------------------------------------------------
-- Disconnect backstop — cleanupRaid's RaidRoomService.End(player) call already handles every normal
-- exit path (Extract/Defeat/Abandon/PlayerSaving-triggered teardown); this is the same redundant
-- safety net RaidHealBudget keeps for the same reason: nothing here should be able to outlive the
-- player instance itself.
----------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	if records[player.UserId] then
		RunBuffService.End(player)
	end
end)

return RunBuffService
