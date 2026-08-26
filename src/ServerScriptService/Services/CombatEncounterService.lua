--[[
	CombatEncounterService.lua
	The shared real-time combat engine — spawn enemies, resolve real damage through
	DamagePipeline, run deployed robots' behaviors, decide win/loss. Built once so both base
	defense (WaveService, wired up in this same pass) and, later, raid Combat rooms (once the
	Phase 2 room system exists to give them somewhere physical to spawn into) call the same
	engine instead of two copies quietly drifting apart. See DESIGN_NOTES.md for the roadmap this
	came from.

	SCOPE NOTE (deliberate, not an oversight): DEPLOYED ROBOTS (CraftingRecipes.Robots,
	profile.DeployedRobots) stay fully ABSTRACT here — no physical Model, no position,
	targeting/damage is nearest-to-player and instant, exactly as originally written. They're a
	separate system from TURRETS (TurretConfig.lua/TurretService.lua, Base Defense & Turrets phase
	round 2) — dedicated instances a player buys as blueprints and places into fixed base slots,
	with their own real range-checked targeting from their OWN physical position (see fireTurrets
	below, called from RunWave only). Turrets still don't take damage themselves and enemies still
	never target them (same reasoning as the player never being directly targeted — every enemy
	attacks the base/wall). Raids (RunRaidCombat below) get NEITHER layer — DeployedRobots stays
	purely abstract there same as always, and turrets don't exist in a raid room at all.

	SCOPE NOTE 2: only WaveService (base defense) calls into this in this pass. NodeService's
	Combat Outposts are untouched — they're still the older chip-damage-per-second placeholder,
	and rebuilding them properly belongs to the Raid Rooms phase, which will actually have physical
	spawn points to hand this engine. Wiring them to this engine now would just mean rebuilding
	that wiring again once rooms exist.

	Public API: CombatEncounterService.RunWave(player, waveNumber, opts) — BLOCKS (yields on
	task.wait internally) until the wave resolves, returns one of "Cleared" / "Defeated" /
	"Interrupted". opts: { IsElite: boolean }.

	WALL DEFENSE (reworked from the original player-HP version — see DESIGN_NOTES.md): the loss
	condition is no longer the player's own Humanoid dying. Every enemy now chases and attacks the
	player's PLOT — its own anchor position (PlotService.GetPlayerPlot), not the player — and deals
	damage to a per-run WallHP pool (ResearchConfig.GetWallMaxHP(profile.ResearchTier)) instead of the
	player's Humanoid. The player still fights back the same way (RequestFireWeapon), just to keep
	the wall standing rather than to keep themselves alive. The player's own Humanoid health is
	untouched by this system entirely now — dying to something unrelated just ends the run as
	"Interrupted" (character gone), not "Defeated".
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local WaveConfig = require(ReplicatedStorage.Shared.WaveConfig)
local RobotBehaviorConfig = require(ReplicatedStorage.Shared.RobotBehaviorConfig)
local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local BaseConfig = require(ReplicatedStorage.Shared.BaseConfig)
local ResearchConfig = require(ReplicatedStorage.Shared.ResearchConfig)
local DataService = require(script.Parent.DataService)
local CombatMath = require(script.Parent.CombatMath)
local DamagePipeline = require(script.Parent.DamagePipeline)
local EnemyAI = require(script.Parent.EnemyAI)
local RobotBehaviors = require(script.Parent.RobotBehaviors)
local PlotService = require(script.Parent.PlotService)
local BaseService = require(script.Parent.BaseService)
local TurretService = require(script.Parent.TurretService)
local UltimateConfig = require(ReplicatedStorage.Shared.UltimateConfig)
local UltimateEffects = require(script.Parent.UltimateEffects)
local PlayerSpeed = require(script.Parent.PlayerSpeed)
local StatusEffects = require(script.Parent.StatusEffects)
local ProjectileService = require(script.Parent.ProjectileService)
local GroundEffectService = require(script.Parent.GroundEffectService)
local ProjectileConfig = require(ReplicatedStorage.Shared.ProjectileConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestFireWeapon = Remotes.RequestFireWeapon
local WaveUpdate = Remotes.WaveUpdate
local DamageNumber = Remotes.DamageNumber

local EnemyModelsFolder = ServerStorage:WaitForChild("EnemyModels")

local TICK_SECONDS = 0.15

-- How often the HUD-facing "Tick" event actually fires — the tick loop itself runs much faster
-- (TICK_SECONDS) for AI/robot responsiveness, but the HUD only needs a number to move about once a
-- second. Module-scoped (not a local inside RunWave) since RunRaidCombat shares this same broadcast
-- cadence — it used to live only inside RunWave, which left RunRaidCombat reading an undefined
-- global (silently nil) the moment it was added as a sibling function.
local BROADCAST_INTERVAL = 1

-- Spawn ring sits OUTSIDE the wall-attack boundary by this much padding (studs), on top of
-- whatever getWallAttackRange() below actually measures — so enemies always visibly walk in from
-- beyond the wall rather than popping into "already attacking" range, regardless of how big the
-- real base footprint turns out to be.
local SPAWN_RADIUS_PADDING_MIN = 15
local SPAWN_RADIUS_PADDING_MAX = 40

-- Each enemy gets an evenly-spaced angle slot around the base (2*pi / spawn count) plus a small
-- random wiggle, instead of a fully independent random angle per enemy — a naive independent draw
-- let two enemies land right next to each other by chance, especially on later waves with bigger
-- spawn counts, which read as "enemies spawning in a clump." Evenly spacing the slots first
-- guarantees real separation between neighbors; the jitter just keeps the ring from looking like a
-- perfectly robotic formation.
local SPAWN_ANGLE_JITTER = math.rad(15)

-- Spawn ring for RunRaidCombat (raid rooms) — unlike base defense, there's no real base footprint
-- to measure, just a room built around an arbitrary center point, so this is a flat guess. Sized to
-- land enemies a real distance out — "enemies spawn at least on the first time they spawn on the
-- map, at 50-70 magnitude from the player" — rather than right on top of the player, while still
-- comfortably fitting inside RaidConfig.FallbackRoomSize's 260x260 (130-stud half-extent).
local RAID_SPAWN_RADIUS_MIN = 50
local RAID_SPAWN_RADIUS_MAX = 70

-- Extra breathing room (studs) added on top of the measured wall boundary before an enemy is
-- considered "close enough" — accounts for the enemy's own character width (the stop point below
-- is measured from the HumanoidRootPart, a single point, but the body has real radius) plus a
-- flat safety buffer, so enemies stop with their WHOLE body clear of the base footprint instead of
-- just their root point touching its edge.
local WALL_STOP_MARGIN = 6

local ORIGIN_SANITY_STUDS = 12 -- how far a client-claimed fire Origin may drift from the player's
	-- actual server-known position before the shot is rejected outright — not full anti-cheat,
	-- just enough to catch an obviously spoofed value. See RequestFireWeapon handler below.

local CombatEncounterService = {}

local activeEncounters: { [number]: any } = {} -- userId -> encounter state, ONLY while a wave is live

-- Optional provider consulted ONLY when a player has no real encounter — see
-- TrainingDummyService, which uses it to make dummies shootable while idle. Deliberately a
-- registration rather than a require: this file must not depend on a testing tool, and the
-- fallback can never take priority over a live wave because it is only reached when there isn't one.
local fallbackEncounterProvider: ((Player) -> any?)? = nil

function CombatEncounterService.SetFallbackEncounterProvider(provider)
	fallbackEncounterProvider = provider
end

-- One warn per unknown AIPattern name, not one per enemy per tick — see the guarded dispatch in
-- the encounter loops below. Without the dedupe a single mis-typed EnemyConfig entry would flood
-- the Output window several times a second for the whole wave.
local warnedMissingPattern: { [string]: boolean } = {}

local encounterFolder = Workspace:FindFirstChild("CombatEncounters")
if not encounterFolder then
	encounterFolder = Instance.new("Folder")
	encounterFolder.Name = "CombatEncounters"
	encounterFolder.Parent = Workspace
end

-- All spawned enemies share one CollisionGroup with enemy-vs-enemy collision turned OFF. Without
-- this, every enemy converging on the same small wall boundary from different angles ends up
-- physically shoving into each other as they arrive — Roblox's physics solver resolves those
-- overlaps with a hard separating impulse in a single frame, which reads exactly like "clipping
-- through" or "a little teleport" (reported directly after the wall-boundary fix, once enemies
-- were actually reaching and clustering around the wall instead of walking straight to the
-- player). They still collide normally with the world/floor (so they don't fall through) and with
-- the player (unchanged) — only enemy-on-enemy collision is disabled, so a crowd at the wall can
-- stand shoulder-to-shoulder without fighting the physics engine for space.
local ENEMY_COLLISION_GROUP = "CombatEnemies"
do
	local groups = PhysicsService:GetRegisteredCollisionGroups()
	local exists = false
	for _, group in ipairs(groups) do
		if group.name == ENEMY_COLLISION_GROUP then
			exists = true
			break
		end
	end
	if not exists then
		PhysicsService:RegisterCollisionGroup(ENEMY_COLLISION_GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(ENEMY_COLLISION_GROUP, ENEMY_COLLISION_GROUP, false)
end

----------------------------------------------------------------------
-- Spawning
----------------------------------------------------------------------

-- Picks which enemy type keys to spawn this wave: WaveConfig.GetEnemyCount(waveNumber) normal
-- types drawn from WaveConfig.EnemyTypes, plus exactly one EliteTypes pick on an elite wave (a
-- single tougher unit joining the crowd — "mini-boss," not "every enemy is now a mini-boss").
local function pickSpawnKeys(waveNumber: number, isElite: boolean): { string }
	local keys = {}
	local normalCount = WaveConfig.GetEnemyCount(waveNumber)
	for _ = 1, normalCount do
		local pick = WaveConfig.EnemyTypes[math.random(1, #WaveConfig.EnemyTypes)]
		if EnemyConfig.Types[pick] then
			table.insert(keys, pick)
		end
	end
	if isElite then
		local eliteKeys = {}
		for key in pairs(EnemyConfig.EliteTypes) do
			table.insert(eliteKeys, key)
		end
		if #eliteKeys > 0 then
			table.insert(keys, eliteKeys[math.random(1, #eliteKeys)])
		end
	end
	return keys
end

local function getEnemyTypeData(typeKey: string)
	return EnemyConfig.Types[typeKey] or EnemyConfig.EliteTypes[typeKey]
end

-- Exported so callers OUTSIDE this file (RaidRoomService, validating a room-authored SpawnPoint's
-- EnemyType Attribute before ever calling RunRaidCombat) can check a key without duplicating
-- getEnemyTypeData's own Types/EliteTypes lookup logic here and there.
function CombatEncounterService.IsValidEnemyType(typeKey: string): boolean
	return getEnemyTypeData(typeKey) ~= nil
end

-- Exported for the same reason as IsValidEnemyType above, but checking one step further: does this
-- type actually have a built Model in ServerStorage.EnemyModels right now? RaidRoomService's own
-- pickRaidSpawnKeys/pickBossSpawnKeys use this to filter their random draw down to types that can
-- actually spawn — without it, an unlucky run of picks landing on a not-yet-built type could spawn
-- NOTHING for an entire Combat/Ambush wave (spawnEnemy below just warns and skips), which reads to
-- the player as that wave being silently skipped even though nothing was actually broken, just
-- missing art.
function CombatEncounterService.HasModelFor(typeKey: string): boolean
	local typeData = getEnemyTypeData(typeKey)
	return typeData ~= nil and EnemyModelsFolder:FindFirstChild(typeData.ModelName) ~= nil
end

-- Clones the template named `typeData.ModelName` out of ServerStorage.EnemyModels (FindFirstChild,
-- never WaitForChild — a missing template should skip this one spawn, not freeze the whole wave;
-- same reasoning as MainHud.client.lua's getItemIcon avoiding the "Infinite yield" class of bug).
-- Returns nil (with a warn()) if the template doesn't exist yet — build one in Studio named
-- exactly `typeData.ModelName`, any size/rig/proportions, same placeholder-first convention as
-- every other system in this project.
local function spawnEnemy(typeKey: string, typeData, spawnPosition: Vector3, multiplier: number, parentFolder: Instance, contactRange: number)
	local template = EnemyModelsFolder:FindFirstChild(typeData.ModelName)
	if not template then
		warn("[CombatEncounterService] No enemy model found for", typeData.ModelName, "— add one to ServerStorage.EnemyModels")
		return nil
	end

	local model = template:Clone()

	-- A model with no PrimaryPart is rejected outright, exactly like one with no Humanoid below.
	-- This used to just skip the PivotTo and spawn the enemy anyway, which was far worse than it
	-- looks: the record came back alive, but every system that can DEAL damage iterates
	-- aliveEnemies (which requires PrimaryPart), while the loop's own "is anything still alive"
	-- test only checked Humanoid.Health. So the enemy was permanently alive, sitting unmoved at
	-- the template's original coordinates, untargetable and unkillable — and the wave never
	-- ended. See isEnemyAlive below, which now keeps those two questions from diverging again.
	-- Checked before parenting so a rejected clone never touches the workspace at all.
	if not model.PrimaryPart then
		warn("[CombatEncounterService] Enemy model", typeData.ModelName, "has no PrimaryPart set — skipping spawn. Set one in Studio (see README).")
		model:Destroy()
		return nil
	end

	model.Parent = parentFolder
	model:PivotTo(CFrame.new(spawnPosition))

	-- See ENEMY_COLLISION_GROUP's own comment above — every part of every spawned enemy joins the
	-- same group so they never physically shove each other while crowding the wall.
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = ENEMY_COLLISION_GROUP
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[CombatEncounterService] Enemy model", typeData.ModelName, "has no Humanoid — destroying spawn")
		model:Destroy()
		return nil
	end

	humanoid.WalkSpeed = typeData.MoveSpeed
	humanoid.MaxHealth = typeData.HP * multiplier
	humanoid.Health = humanoid.MaxHealth

	-- Housekeeping only, not gameplay logic — the tick loop still finds out about a death by
	-- polling Health each tick (see RunWave), same as everywhere else in this codebase avoids
	-- event-driven state in favor of simple polling. This just clears the corpse out a couple
	-- seconds later instead of leaving it sitting in the world for the rest of the wave.
	humanoid.Died:Connect(function()
		task.delay(2, function()
			if model.Parent then
				model:Destroy()
			end
		end)
	end)

	return {
		Model = model,
		Humanoid = humanoid,
		TypeKey = typeKey,
		SpawnTime = os.clock(), -- EnemyAI.lua's SPAWN_GRACE_SECONDS reads this — no damage in the
			-- first second after spawning, "so it avoid player feeling like the game is unfair"
		ContactDamage = typeData.ContactDamage * multiplier,
		-- Caller-supplied, not always the same meaning: base defense (RunWave) passes the REAL
		-- measured wall boundary (see getWallAttackRange below) since it's "close enough to attack
		-- the base," not the player — raid rooms (RunRaidCombat) pass typeData.ContactRange
		-- straight through instead, since there enemies really are chasing the player and should
		-- use their own natural per-type melee range.
		-- Kept on the record so slowing statuses have a stable base to scale FROM (see EnemyAI).
		MoveSpeed = typeData.MoveSpeed,
		ContactRange = contactRange,
		AttackCooldown = typeData.AttackCooldown,
		Defense = typeData.Defense * multiplier,
		AIPattern = typeData.AIPattern,
		LastAttackTime = 0,
		LastMoveThink = 0,
	}
end

-- Measures the REAL "close enough to attack the wall" boundary off the player's actual built base
-- Model (BaseService.GetPlayerBaseModel — real BaseTier art, or the small fallback floor most
-- testing uses today) instead of a fixed guess. A hardcoded BaseConfig.WallAttackRange tuned
-- against PlotConfig.FootprintHalfSize (the max CLAIMED plot area, 40 studs) turned out to be
-- roughly DOUBLE the actual placeholder floor's real half-extent (BaseService's
-- FALLBACK_FLOOR_SIZE is only 40x40, i.e. 20 studs center-to-edge) — so the whole visible platform
-- sat well inside the "attack range" circle, and enemies stopping there looked exactly like no
-- boundary existed at all, right in the middle next to the player. Using the model's own measured
-- footprint means this is automatically correct for the placeholder today AND for whatever size a
-- real BaseTier Model turns out to be later, with zero further tuning.
--
-- CIRCUMSCRIBED circle, not inscribed: this measures half the footprint's DIAGONAL
-- (Vector3.new(size.X, 0, size.Z).Magnitude / 2), not the smaller of X/Z. Using min(X,Z)/2
-- (the previous approach) is the circle INSCRIBED in the footprint rectangle — tangent to the
-- nearest edge at only four points, and strictly INSIDE the rectangle everywhere else, so enemies
-- stopping at that radius were still standing on the platform for most approach angles (that's
-- exactly what the "they cannot come inside the base" screenshots showed — enemies had stopped,
-- but still visibly on the base). The half-diagonal is the smallest radius that clears every point
-- of the rectangle, including its corners, on every bearing — plus WALL_STOP_MARGIN on top for the
-- enemy's own body width and a safety buffer, so the stop point sits fully outside, not just
-- touching the edge.
local function getWallAttackRange(player: Player): number
	local baseModel = BaseService.GetPlayerBaseModel(player)
	local halfExtent
	if baseModel then
		local ok, _, size = pcall(function()
			return baseModel:GetBoundingBox()
		end)
		if ok and size then
			halfExtent = Vector3.new(size.X, 0, size.Z).Magnitude / 2
		end
	end
	if not halfExtent or halfExtent <= 0 then
		halfExtent = BaseConfig.WallAttackRange -- fallback only — see that field's own comment
	end
	return halfExtent + WALL_STOP_MARGIN
end

-- The ONE definition of "this enemy still counts as a live participant," used by both the
-- encounter loops' exit test and the aliveEnemies list they build for AI/robots/turrets.
--
-- These were two separate inline conditions and they did not agree: the exit test checked only
-- Humanoid.Health > 0, while aliveEnemies additionally required Model.PrimaryPart. Any enemy
-- matching the first but not the second was immortal — nothing could target it, and the loop
-- would not exit while it lived. spawnEnemy now rejects PrimaryPart-less models up front, so
-- that gap is closed at the source too; this exists so a future change to either question is
-- forced to be a change to both.
local function isEnemyAlive(record): boolean
	return record.Humanoid.Health > 0 and record.Model.PrimaryPart ~= nil
end

----------------------------------------------------------------------
-- Damage application (shared by player fire and robot ticks)
----------------------------------------------------------------------

-- One place that actually runs DamagePipeline and applies the result to an enemy's Humanoid —
-- used both by RequestFireWeapon (player-sourced) and RobotBehaviors' context.DamageEnemy
-- (robot-sourced), so the two never resolve damage two different ways.
-- `feedbackPlayer` / `feedbackKind` drive the floating damage number (DamageNumbers.client.lua).
-- Optional and appended rather than woven in, so a caller that does not care is unchanged — but
-- every caller in this file passes them, because a damage source the player cannot see is a
-- damage source they cannot tell is broken.
local function resolveAndApplyDamage(enemyRecord, baseDamage: number, origin: Vector3, hitPosition: Vector3, rangeProfile, penetration: number?, feedbackPlayer: Player?, feedbackKind: string?)
	local finalDamage = DamagePipeline.Resolve({
		BaseDamage = baseDamage,
		Origin = origin,
		HitPosition = hitPosition,
		RangeProfile = rangeProfile,
		Penetration = penetration or 0,
		-- Armour-shredding statuses multiply this down (StatusEffects.GetDefenseMultiplier).
		-- Multiplicative rather than a strip flag, so "loses 50% of their defense" and "drops to 0"
		-- are the same mechanism at different strengths and two shredders compound instead of one
		-- overwriting the other. Statuses live on the record, so nothing leaks into a later wave.
		TargetDefense = enemyRecord.Defense * StatusEffects.GetDefenseMultiplier(enemyRecord),
	})
	enemyRecord.Humanoid:TakeDamage(finalDamage)

	-- Training dummies keep a running total on their head. Fed from the SAME number the pipeline
	-- just produced rather than re-derived, so what the dummy reports and what the enemy actually
	-- took can never disagree.
	if enemyRecord.IsDummy then
		enemyRecord.AccumulatedDamage = (enemyRecord.AccumulatedDamage or 0) + finalDamage
		enemyRecord.LastDamageAt = os.clock()
		enemyRecord.LastAttacker = feedbackPlayer or enemyRecord.LastAttacker
	end

	if feedbackPlayer and enemyRecord.Model and enemyRecord.Model.PrimaryPart then
		-- Fired at the responsible player only. Everyone's numbers on everyone's screen would be
		-- noise, and this is a personal readout rather than a shared one.
		DamageNumber:FireClient(
			feedbackPlayer,
			enemyRecord.Model.PrimaryPart.Position + Vector3.new(0, 3, 0),
			finalDamage,
			feedbackKind or "Normal")
	end

	return finalDamage
end

-- Public wrapper so systems outside this file (TrainingDummyService's status ticks) can deal
-- damage through the real pipeline instead of touching Humanoids directly — the same reasoning
-- behind ctx.DealDamage for Ultimate effects.
function CombatEncounterService.ApplyDamageTo(record, amount: number, at: Vector3, player: Player?, kind: string?)
	if not record or not amount or amount <= 0 then
		return 0
	end
	return resolveAndApplyDamage(record, amount, at, at, nil, 0, player, kind)
end

----------------------------------------------------------------------
-- Turret firing (base defense only — see TurretService.lua's own header on why raids don't get
-- this at all). Unlike robots, a turret's targeting is genuinely range-limited from its OWN
-- physical position, not "always hits whoever's nearest the player" — so this can't just reuse
-- RobotBehaviors' Cleave/SingleTarget, it needs its own nearest-to-the-TURRET-and-in-range pass.
----------------------------------------------------------------------

-- Reused per turret per tick — module-scoped so it isn't reallocated every single call.
local turretInRangeScratch = {}

-- turretOwner is threaded through purely so turret damage shows a number to the player whose
-- base it defends — turrets are the one damage source with no player action behind them, which
-- made them the hardest to tell apart from nothing happening at all.
local function fireTurrets(turretRecords, aliveEnemies, now: number, turretOwner: Player?)
	for _, turret in ipairs(turretRecords) do
		local cooldown = 1 / math.max(turret.FireRate, 0.01)
		if now - turret.LastFireTime >= cooldown then
			table.clear(turretInRangeScratch)
			for _, record in ipairs(aliveEnemies) do
				if record.Model.PrimaryPart then
					local distance = (record.Model.PrimaryPart.Position - turret.WorldPosition).Magnitude
					if distance <= turret.Range then
						table.insert(turretInRangeScratch, { Record = record, Distance = distance })
					end
				end
			end

			if #turretInRangeScratch > 0 then
				table.sort(turretInRangeScratch, function(a, b)
					return a.Distance < b.Distance
				end)
				turret.LastFireTime = now

				local hitCount = math.min(turret.AOE or 1, #turretInRangeScratch)
				for i = 1, hitCount do
					local targetRecord = turretInRangeScratch[i].Record
					resolveAndApplyDamage(
						targetRecord, turret.Damage, turret.WorldPosition,
						targetRecord.Model.PrimaryPart.Position, nil, 0, turretOwner, "Turret")
				end

				-- Visual only — "make sure turrets shoot a particle when they are shooting smth so
				-- it looks cool." Orienting the Muzzle Attachment toward the primary target first
				-- means the burst at least roughly points the right way even without a real
				-- projectile/tracer. Damage above is already fully resolved regardless of whether
				-- any of this succeeds — a torn-down/missing Muzzle just means no particle, never a
				-- missed or dropped hit.
				if turret.Muzzle and turret.Muzzle.Parent then
					local primaryTargetPosition = turretInRangeScratch[1].Record.Model.PrimaryPart.Position
					pcall(function()
						turret.Muzzle.WorldCFrame = CFrame.new(turret.Muzzle.WorldPosition, primaryTargetPosition)
					end)
					local emitter = turret.Muzzle:FindFirstChildOfClass("ParticleEmitter")
					if emitter then
						emitter:Emit(14)
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- RunWave
----------------------------------------------------------------------

function CombatEncounterService.RunWave(player: Player, waveNumber: number, opts): string
	local profile = DataService.Get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local plot = PlotService.GetPlayerPlot(player)
	if not profile or not humanoid or not rootPart or humanoid.Health <= 0 or not plot then
		return "Interrupted"
	end

	local isElite = opts and opts.IsElite or false
	local multiplier = WaveConfig.GetEnemyMultiplier(waveNumber)
	local spawnKeys = pickSpawnKeys(waveNumber, isElite)

	local playerFolder = Instance.new("Folder")
	playerFolder.Name = tostring(player.UserId)
	playerFolder.Parent = encounterFolder

	-- Every enemy chases/attacks the BASE now, not the player — see this file's header. Spawned
	-- (and later chased) relative to the plot's own anchor position, offset up by the same
	-- SpawnHeightOffset the player's own respawn uses, so enemies land roughly at floor height
	-- instead of half-buried at the anchor's exact Y.
	local basePosition = plot.Position + Vector3.new(0, PlotConfig.SpawnHeightOffset, 0)

	-- Measured off the player's REAL base Model this run, not a fixed guess — see
	-- getWallAttackRange's own comment on why that matters. Spawn ring sits this + a padding band
	-- further out, so enemies always visibly walk in from beyond wherever the real wall is.
	local wallAttackRange = getWallAttackRange(player)
	-- math.random(m, n) requires integer bounds in Luau — wallAttackRange comes from a measured
	-- bounding box (GetBoundingBox), almost never a whole number, so these get floored/ceiled
	-- rather than passed through raw (that would error at runtime the first time it wasn't an
	-- exact integer).
	local spawnRadiusMin = math.floor(wallAttackRange + SPAWN_RADIUS_PADDING_MIN)
	local spawnRadiusMax = math.ceil(wallAttackRange + SPAWN_RADIUS_PADDING_MAX)

	local enemyByModel = {}
	local spawnCount = #spawnKeys
	local angleStep = spawnCount > 0 and (math.pi * 2 / spawnCount) or 0
	for i, typeKey in ipairs(spawnKeys) do
		local typeData = getEnemyTypeData(typeKey)
		local jitter = (math.random() * 2 - 1) * SPAWN_ANGLE_JITTER
		local angle = (i - 1) * angleStep + jitter
		local radius = math.random(spawnRadiusMin, spawnRadiusMax)
		local spawnPosition = basePosition + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local record = spawnEnemy(typeKey, typeData, spawnPosition, multiplier, playerFolder, wallAttackRange)
		if record then
			enemyByModel[record.Model] = record
		end
	end

	local totalSpawned = 0
	for _ in pairs(enemyByModel) do
		totalSpawned += 1
	end

	-- Deployed robots stay abstract this pass — see this file's header. Each gets its own
	-- LastActionTime so behaviors' cooldowns are tracked per-robot, not shared.
	local robotRecords = {}
	for _, robotKey in ipairs(profile.DeployedRobots) do
		local behaviorConfig = RobotBehaviorConfig.Robots[robotKey]
		local effectiveStats = CombatMath.GetEffectiveStats("Robots", robotKey, profile)
		if behaviorConfig and effectiveStats then
			table.insert(robotRecords, {
				Key = robotKey,
				BehaviorConfig = behaviorConfig,
				EffectiveStats = effectiveStats,
				LastActionTime = 0,
			})
		end
	end

	-- Placed Turrets (TurretService.lua) are re-fetched every tick inside the loop below, NOT
	-- snapshotted here. This used to be a single snapshot taken at wave start, which quietly went
	-- stale: PlaceTurretInSlot/UnplaceTurret/UpgradeTurret all call RebuildPlayerTurrets, which
	-- replaces the record list and destroys the old Models — and all three are usable mid-wave,
	-- since they only require standing in your own plot, which is exactly where you fight. So an
	-- upgrade bought during a wave didn't apply until the next one, and a turret you unplaced kept
	-- firing from a model that no longer existed.
	--
	-- The fetch is just a table lookup, so doing it per tick costs nothing. One consequence worth
	-- knowing: a rebuild hands back fresh records with LastFireTime = 0, so placing or upgrading a
	-- turret mid-wave resets every turret's cooldown. That's a small, one-off free volley in the
	-- player's favor at the moment they spend resources — acceptable, and far better than the
	-- alternative of firing on behalf of destroyed models.
	--
	-- Base-defense only; RunRaidCombat never calls this, turrets have no presence in a raid room.

	local wallMaxHP = ResearchConfig.GetWallMaxHP(profile.ResearchTier)

	local playerState = {
		WallHP = wallMaxHP,
		WallMaxHP = wallMaxHP,
		Shield = 0, -- now absorbs incoming hits on the WALL's behalf, not the player's — see
			-- RobotBehaviors.lua's Utility.Shield header comment
		LastFireTime = 0,
		-- Read from PlayerSpeed, not the live Humanoid: reading the Humanoid mid-wield would
		-- capture the already-slowed speed as if it were the player's normal one.
		BaseWalkSpeed = PlayerSpeed.GetBase(player),
		SpeedBoostUntil = 0,
	}

	-- Drains Shield first, then the wall itself — same absorb-pool-before-real-health shape the
	-- old player-HP version used, just protecting WallHP instead of a Humanoid now.
	local function damageTarget(amount: number)
		if playerState.Shield > 0 then
			local absorbed = math.min(playerState.Shield, amount)
			playerState.Shield -= absorbed
			amount -= absorbed
		end
		if amount > 0 then
			playerState.WallHP -= amount
		end
	end

	-- Routed through PlayerSpeed rather than written straight onto the Humanoid, so a boost and a
	-- heavy weapon's wield penalty multiply instead of the last writer erasing the other. Clearing
	-- our own key below restores whatever else is still active, not a remembered absolute speed.
	local function grantSpeedBoost(multiplier_: number, duration: number)
		PlayerSpeed.Set(player, "SpeedBoost", multiplier_)
		playerState.SpeedBoostUntil = os.clock() + duration
	end

	local encounter = {
		Player = player,
		EnemyByModel = enemyByModel,
		PlayerState = playerState,
		DamageTarget = damageTarget,
	}
	-- Belt-and-braces. This slot is shared by RunWave and RunRaidCombat, and overwriting a live
	-- one used to be reachable (start a raid mid-wave) — it corrupted both fights, since
	-- RequestFireWeapon resolves against whichever encounter is in here and whichever fight ends
	-- first nils the survivor's entry. PlayerActivityService should now make that impossible at
	-- the two entry points; this catches it loudly if some future caller finds a third way in.
	if activeEncounters[player.UserId] then
		warn(("[CombatEncounterService] Overwriting a live encounter for %s — two combat systems think they own this player. See PlayerActivityService."):format(player.Name))
	end
	activeEncounters[player.UserId] = encounter

	local status = "Cleared"
	local lastBroadcast = 0

	while true do
		if #spawnKeys > 0 then
			-- only wait/tick if anything was actually spawned — an entirely-unconfigured
			-- EnemyModels folder (nothing built yet) shouldn't hang the run forever, see spawnEnemy.
			local anyAlive = false
			for _, record in pairs(enemyByModel) do
				if isEnemyAlive(record) then
					anyAlive = true
					break
				end
			end
			if not anyAlive then
				break
			end
		else
			break
		end

		character = player.Character
		humanoid = character and character:FindFirstChildOfClass("Humanoid")
		rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or not rootPart then
			status = "Interrupted"
			break
		end
		-- The player's own Humanoid dying is no longer the loss condition (see this file's
		-- header) — only their character/connection vanishing ends the run early, and that's
		-- "Interrupted" (nothing to retry), not "Defeated". The real loss condition is below.
		if playerState.WallHP <= 0 then
			status = "Defeated"
			break
		end

		local now = os.clock()
		if playerState.SpeedBoostUntil > 0 and now >= playerState.SpeedBoostUntil then
			PlayerSpeed.Set(player, "SpeedBoost", nil)
			playerState.SpeedBoostUntil = 0
		end

		-- Nearest-first so Combat robot behaviors (SingleTarget/Cleave) read as "focus the closest
		-- threat" for free — see RobotBehaviors.lua.
		local aliveEnemies = {}
		for _, record in pairs(enemyByModel) do
			if isEnemyAlive(record) then
				table.insert(aliveEnemies, record)
			end
		end
		table.sort(aliveEnemies, function(a, b)
			return (a.Model.PrimaryPart.Position - rootPart.Position).Magnitude
				< (b.Model.PrimaryPart.Position - rootPart.Position).Magnitude
		end)

		if now - lastBroadcast >= BROADCAST_INTERVAL then
			lastBroadcast = now
			WaveUpdate:FireClient(player, {
				Status = "Tick",
				Wave = waveNumber,
				WallHP = math.ceil(math.max(playerState.WallHP, 0)),
				WallMaxHP = playerState.WallMaxHP,
				Shield = math.ceil(playerState.Shield),
				EnemiesRemaining = #aliveEnemies,
				EnemiesTotal = totalSpawned,
			})
		end

		-- TargetPosition is the base's own anchor point, not the player — every enemy is chasing
		-- and attacking the wall now, see this file's header.
		local aiContext = {
			TargetPosition = basePosition,
			Now = now,
			DamageTarget = damageTarget,
		}
		-- Statuses tick from the same loop that drives the AI, so a bleed advances at the same
		-- rate in a raid room as in base defense. Damage routes through the normal pipeline —
		-- a damage-over-time that skipped mitigation would be strictly better than a bullet
		-- against armoured targets.
		for _, record in ipairs(aliveEnemies) do
			StatusEffects.Tick(record, now, function(target, amount)
				local at = target.Model.PrimaryPart.Position
				resolveAndApplyDamage(target, amount, at, at, nil, 0, player, "Status")
			end)
		end

		for _, record in ipairs(aliveEnemies) do
			-- Guarded like the RobotBehaviors dispatch below it. Unguarded, an EnemyConfig entry
			-- naming an AIPattern that doesn't exist in EnemyAI.Patterns (a typo, or a pattern
			-- planned but not written yet) threw from inside this tick loop — killing the whole
			-- encounter coroutine and stranding activeRuns/activeEncounters, which locked the
			-- player out of starting another run for the rest of the session. A missing pattern
			-- should cost one enemy its brain, not the entire run.
			local pattern = EnemyAI.Patterns[record.AIPattern]
			if pattern then
				pattern(record, aiContext)
			elseif not warnedMissingPattern[record.AIPattern] then
				warnedMissingPattern[record.AIPattern] = true
				warn(("[CombatEncounterService] No EnemyAI pattern named %q (used by enemy type %s) — that enemy will stand still. Add it to EnemyAI.Patterns."):format(
					tostring(record.AIPattern), tostring(record.TypeKey)))
			end
		end

		local robotContext = {
			AliveEnemies = aliveEnemies,
			Now = now,
			PlayerState = playerState,
			GrantSpeedBoost = grantSpeedBoost,
			DamageEnemy = function(enemyRecord, baseDamage)
				resolveAndApplyDamage(enemyRecord, baseDamage, rootPart.Position, rootPart.Position, nil, 0, player, "Robot")
			end,
		}
		for _, robot in ipairs(robotRecords) do
			local fn = RobotBehaviors[robot.BehaviorConfig.Mode][robot.BehaviorConfig.Behavior]
			if fn then
				fn(robot, robotContext)
			end
		end

		-- Live read, not a wave-start snapshot — see the comment where this used to be captured.
		fireTurrets(TurretService.GetActiveTurretRecords(player), aliveEnemies, now, player)

		task.wait(TICK_SECONDS)
	end

	if playerState.SpeedBoostUntil > 0 then
		PlayerSpeed.Set(player, "SpeedBoost", nil)
	end

	activeEncounters[player.UserId] = nil
	GroundEffectService.ClearFor(player)
	playerFolder:Destroy()

	return status
end

----------------------------------------------------------------------
-- RunRaidCombat — the Raid Rooms Combat node (RaidRoomService.lua). Same underlying engine as
-- RunWave (spawnEnemy, resolveAndApplyDamage, EnemyAI, RobotBehaviors, activeEncounters/
-- RequestFireWeapon), but enemies chase the PLAYER'S own live position instead of a fixed wall
-- anchor, and the loss condition is the player's own Humanoid health instead of a WallHP pool —
-- this file's header (SCOPE NOTE 2) and EnemyAI.lua's TargetPosition comment both called this out
-- as the intended next step once Raid Rooms had real physical spawn points to hand this engine to.
--
-- Deliberately takes an explicit spawnKeys list + multiplier rather than a "Tier" number: this file
-- has zero Raid-specific knowledge (no RaidConfig require) the same way it has zero base-defense-
-- specific knowledge beyond what RunWave itself needs. RaidRoomService resolves the actual
-- composition (RaidConfig.CombatTierComposition + WaveConfig.EnemyTypes) and hands it over already
-- decided — this file just spawns whatever list it's given.
--
-- onEvent(status, payload), if provided, fires at the same points RunWave fires WaveUpdate — a
-- plain callback instead of a hardcoded Remote, so this file doesn't need to know the raid system's
-- remote names either. RaidRoomService relays these into its own RaidRoomUpdate remote.
--
-- explicitSpawns (optional): a room-authored spawn list ({ {Position: Vector3, TypeKey: string} }),
-- straight from RaidConfig.SpawnPointName Parts placed in a hand-built Room Model. When given
-- (non-nil, non-empty) it's used INSTEAD of spawnKeys/the circle-around-arenaCenter placement below
-- — spawn exactly what the room says, exactly where it says — so spawnKeys is only ever consulted
-- when explicitSpawns is nil, same as before this parameter existed.
----------------------------------------------------------------------

function CombatEncounterService.RunRaidCombat(player: Player, arenaCenter: Vector3, spawnKeys: { string }, multiplier: number, onEvent: ((string, any) -> ())?, explicitSpawns: { { Position: Vector3, TypeKey: string } }?): string
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local profile = DataService.Get(player)
	if not profile or not humanoid or not rootPart or humanoid.Health <= 0 then
		return "Interrupted"
	end

	local playerFolder = Instance.new("Folder")
	playerFolder.Name = tostring(player.UserId) .. "_Raid"
	playerFolder.Parent = encounterFolder

	local enemyByModel = {}
	if explicitSpawns and #explicitSpawns > 0 then
		-- Room-authored spawn points — see this function's own header. Every entry here already
		-- passed RaidRoomService's own EnemyType validation (missing/unknown attributes are warned
		-- about and filtered out before this ever runs), so this just spawns exactly what's left.
		for _, spawnInfo in ipairs(explicitSpawns) do
			local typeData = getEnemyTypeData(spawnInfo.TypeKey)
			if typeData then
				local record = spawnEnemy(spawnInfo.TypeKey, typeData, spawnInfo.Position, multiplier, playerFolder, typeData.ContactRange)
				if record then
					enemyByModel[record.Model] = record
				end
			end
		end
	else
		local spawnCount = #spawnKeys
		local angleStep = spawnCount > 0 and (math.pi * 2 / spawnCount) or 0
		for i, typeKey in ipairs(spawnKeys) do
			local typeData = getEnemyTypeData(typeKey)
			if typeData then
				local jitter = (math.random() * 2 - 1) * SPAWN_ANGLE_JITTER
				local angle = (i - 1) * angleStep + jitter
				local radius = math.random(RAID_SPAWN_RADIUS_MIN, RAID_SPAWN_RADIUS_MAX)
				local spawnPosition = arenaCenter + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				-- typeData.ContactRange, not a measured boundary — see this function's own header.
				local record = spawnEnemy(typeKey, typeData, spawnPosition, multiplier, playerFolder, typeData.ContactRange)
				if record then
					enemyByModel[record.Model] = record
				end
			end
		end
	end

	local totalSpawned = 0
	for _ in pairs(enemyByModel) do
		totalSpawned += 1
	end

	if totalSpawned == 0 then
		-- No enemy models built yet for anything in spawnKeys (spawnEnemy warns per-type already) —
		-- don't hang the raid on a room that can never resolve; treat an empty room as cleared. This
		-- extra warn() names the actual keys that were attempted so a run of missing-model picks
		-- (see HasModelFor above, meant to prevent exactly this) is diagnosable from the log if it
		-- ever still happens — previously the only signal was spawnEnemy's per-type warns, easy to
		-- miss, and the encounter just silently resolved as an instant, unremarked "Cleared."
		warn(("[CombatEncounterService] RunRaidCombat spawned 0 enemies (attempted: %s) — treating as trivially cleared. Check ServerStorage.EnemyModels for missing templates."):format(
			#spawnKeys > 0 and table.concat(spawnKeys, ", ") or "explicitSpawns only, all invalid"))
		playerFolder:Destroy()
		if onEvent then
			-- Result (not Status) — the caller's onEvent wrapper typically stamps its own Status
			-- field on this payload before relaying it onward (see RaidRoomService), so this uses a
			-- different key to avoid that collision rather than getting silently overwritten.
			onEvent("End", { Result = "Cleared" })
		end
		return "Cleared"
	end

	local robotRecords = {}
	for _, robotKey in ipairs(profile.DeployedRobots) do
		local behaviorConfig = RobotBehaviorConfig.Robots[robotKey]
		local effectiveStats = CombatMath.GetEffectiveStats("Robots", robotKey, profile)
		if behaviorConfig and effectiveStats then
			table.insert(robotRecords, {
				Key = robotKey,
				BehaviorConfig = behaviorConfig,
				EffectiveStats = effectiveStats,
				LastActionTime = 0,
			})
		end
	end

	local playerState = {
		Shield = 0,
		LastFireTime = 0,
		-- Read from PlayerSpeed, not the live Humanoid: reading the Humanoid mid-wield would
		-- capture the already-slowed speed as if it were the player's normal one.
		BaseWalkSpeed = PlayerSpeed.GetBase(player),
		SpeedBoostUntil = 0,
	}

	-- Drains Shield first, then the player's own Humanoid directly — same absorb-then-real-health
	-- shape RunWave uses for WallHP, just protecting the player themselves since there's no wall
	-- to stand in for them here.
	local function damageTarget(amount: number)
		if playerState.Shield > 0 then
			local absorbed = math.min(playerState.Shield, amount)
			playerState.Shield -= absorbed
			amount -= absorbed
		end
		if amount > 0 then
			humanoid:TakeDamage(amount)
		end
	end

	-- Routed through PlayerSpeed rather than written straight onto the Humanoid, so a boost and a
	-- heavy weapon's wield penalty multiply instead of the last writer erasing the other. Clearing
	-- our own key below restores whatever else is still active, not a remembered absolute speed.
	local function grantSpeedBoost(multiplier_: number, duration: number)
		PlayerSpeed.Set(player, "SpeedBoost", multiplier_)
		playerState.SpeedBoostUntil = os.clock() + duration
	end

	local encounter = {
		Player = player,
		EnemyByModel = enemyByModel,
		PlayerState = playerState,
		DamageTarget = damageTarget,
	}
	-- Belt-and-braces. This slot is shared by RunWave and RunRaidCombat, and overwriting a live
	-- one used to be reachable (start a raid mid-wave) — it corrupted both fights, since
	-- RequestFireWeapon resolves against whichever encounter is in here and whichever fight ends
	-- first nils the survivor's entry. PlayerActivityService should now make that impossible at
	-- the two entry points; this catches it loudly if some future caller finds a third way in.
	if activeEncounters[player.UserId] then
		warn(("[CombatEncounterService] Overwriting a live encounter for %s — two combat systems think they own this player. See PlayerActivityService."):format(player.Name))
	end
	activeEncounters[player.UserId] = encounter

	local status = "Cleared"
	local lastBroadcast = 0

	if onEvent then
		onEvent("Start", { EnemiesTotal = totalSpawned })
	end

	while true do
		local anyAlive = false
		for _, record in pairs(enemyByModel) do
			if isEnemyAlive(record) then
				anyAlive = true
				break
			end
		end
		if not anyAlive then
			break
		end

		character = player.Character
		humanoid = character and character:FindFirstChildOfClass("Humanoid")
		rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or not rootPart then
			status = "Interrupted"
			break
		end
		if humanoid.Health <= 0 then
			status = "Defeated"
			break
		end

		local now = os.clock()
		if playerState.SpeedBoostUntil > 0 and now >= playerState.SpeedBoostUntil then
			PlayerSpeed.Set(player, "SpeedBoost", nil)
			playerState.SpeedBoostUntil = 0
		end

		local aliveEnemies = {}
		for _, record in pairs(enemyByModel) do
			if isEnemyAlive(record) then
				table.insert(aliveEnemies, record)
			end
		end
		table.sort(aliveEnemies, function(a, b)
			return (a.Model.PrimaryPart.Position - rootPart.Position).Magnitude
				< (b.Model.PrimaryPart.Position - rootPart.Position).Magnitude
		end)

		if now - lastBroadcast >= BROADCAST_INTERVAL then
			lastBroadcast = now
			if onEvent then
				onEvent("Tick", {
					PlayerHealth = math.ceil(math.max(humanoid.Health, 0)),
					PlayerMaxHealth = humanoid.MaxHealth,
					Shield = math.ceil(playerState.Shield),
					EnemiesRemaining = #aliveEnemies,
					EnemiesTotal = totalSpawned,
				})
			end
		end

		-- TargetPosition tracks the player's own LIVE position every tick, not a fixed point — see
		-- this function's own header and EnemyAI.lua's TargetPosition comment.
		local aiContext = {
			TargetPosition = rootPart.Position,
			Now = now,
			DamageTarget = damageTarget,
		}
		-- Statuses tick from the same loop that drives the AI, so a bleed advances at the same
		-- rate in a raid room as in base defense. Damage routes through the normal pipeline —
		-- a damage-over-time that skipped mitigation would be strictly better than a bullet
		-- against armoured targets.
		for _, record in ipairs(aliveEnemies) do
			StatusEffects.Tick(record, now, function(target, amount)
				local at = target.Model.PrimaryPart.Position
				resolveAndApplyDamage(target, amount, at, at, nil, 0, player, "Status")
			end)
		end

		for _, record in ipairs(aliveEnemies) do
			-- Guarded like the RobotBehaviors dispatch below it. Unguarded, an EnemyConfig entry
			-- naming an AIPattern that doesn't exist in EnemyAI.Patterns (a typo, or a pattern
			-- planned but not written yet) threw from inside this tick loop — killing the whole
			-- encounter coroutine and stranding activeRuns/activeEncounters, which locked the
			-- player out of starting another run for the rest of the session. A missing pattern
			-- should cost one enemy its brain, not the entire run.
			local pattern = EnemyAI.Patterns[record.AIPattern]
			if pattern then
				pattern(record, aiContext)
			elseif not warnedMissingPattern[record.AIPattern] then
				warnedMissingPattern[record.AIPattern] = true
				warn(("[CombatEncounterService] No EnemyAI pattern named %q (used by enemy type %s) — that enemy will stand still. Add it to EnemyAI.Patterns."):format(
					tostring(record.AIPattern), tostring(record.TypeKey)))
			end
		end

		local robotContext = {
			AliveEnemies = aliveEnemies,
			Now = now,
			PlayerState = playerState,
			GrantSpeedBoost = grantSpeedBoost,
			DamageEnemy = function(enemyRecord, baseDamage)
				resolveAndApplyDamage(enemyRecord, baseDamage, rootPart.Position, rootPart.Position, nil, 0, player, "Robot")
			end,
		}
		for _, robot in ipairs(robotRecords) do
			local fn = RobotBehaviors[robot.BehaviorConfig.Mode][robot.BehaviorConfig.Behavior]
			if fn then
				fn(robot, robotContext)
			end
		end

		task.wait(TICK_SECONDS)
	end

	if playerState.SpeedBoostUntil > 0 then
		PlayerSpeed.Set(player, "SpeedBoost", nil)
	end

	activeEncounters[player.UserId] = nil
	GroundEffectService.ClearFor(player)
	playerFolder:Destroy()

	if onEvent then
		onEvent("End", { Result = status }) -- Result, not Status — see the other onEvent("End", ...) call's comment above
	end

	return status
end

----------------------------------------------------------------------
-- Player weapon fire
----------------------------------------------------------------------

-- Client raycasts locally (instant visual feedback, see CombatClient.client.lua) and reports what
-- it thinks it hit — the actual damage number is entirely recomputed server-side from server-known
-- state (equipped weapon, player position, the target's real Defense). A spoofed client can at
-- worst claim a hit that the distance/encounter-membership checks below reject; it can never
-- inject its own damage number, since `baseDamage` always comes from CombatMath here, not from
-- anything the client sent.
-- Per-player fire cooldown. Moved OFF the encounter's PlayerState when guns became projectiles:
-- you can now fire with no encounter running at all (at a training dummy, or at nothing), so the
-- rate limit cannot live on a thing that may not exist.
local lastFireTime: { [number]: number } = {}

-- Forward-declared: the fire handler below references it, and it is defined between the two.
-- Declaring it here keeps it a local — assigning `function buildOnExpire()` without this would
-- silently create a GLOBAL, which works until something else in the game shadows it.
local buildOnExpire

-- Whichever fight this player is in, or the training-dummy fallback if they are in none. One
-- definition, so a projectile, a ground effect and an Ultimate all agree on what counts as "the
-- enemies near me right now".
local function encounterFor(player: Player)
	local encounter = activeEncounters[player.UserId]
	if not encounter and fallbackEncounterProvider then
		encounter = fallbackEncounterProvider(player)
	end
	return encounter
end

-- Live enemies within `radius` of a world point. Used by GroundEffectService, which needs targets
-- but must not require this file (it requires half the game) — so it is handed this instead.
function CombatEncounterService.LiveEnemiesNear(player: Player, position: Vector3, radius: number)
	local encounter = encounterFor(player)
	if not encounter then
		return {}
	end

	local found = {}
	for _, record in pairs(encounter.EnemyByModel) do
		if isEnemyAlive(record) then
			local part = record.Model.PrimaryPart
			if part and (part.Position - position).Magnitude <= radius then
				table.insert(found, record)
			end
		end
	end
	return found
end

-- Applies a weapon's on-contact status, if it has one.
--
-- IntervalSeconds is per TARGET, not per shot: a flamethrower lands sixty hits a second, so a status
-- applied on every one of them would hit max stacks instantly and the "takes a full 5 seconds to
-- apply one stack" the PoisonThrower is specced around would be meaningless. Tracking it on the
-- enemy record means walking out of the stream and back in does not reset your progress on it.
local function applyOnHitStatus(record, onHit)
	if not onHit or not onHit.Key then
		return
	end

	if onHit.IntervalSeconds then
		record.StatusAppliedAt = record.StatusAppliedAt or {}
		local now = os.clock()
		if now - (record.StatusAppliedAt[onHit.Key] or -math.huge) < onHit.IntervalSeconds then
			return
		end
		record.StatusAppliedAt[onHit.Key] = now
	end

	if onHit.Chance and math.random() >= onHit.Chance then
		return
	end

	StatusEffects.Apply(record, onHit.Key, onHit.Overrides)
end

-- Resolves ONE projectile impact against an enemy. Returns true if it hit something that counted,
-- which is what tells a piercing round whether to keep going.
--
-- Split out from the fire handler when shots gained travel time: firing and hitting are now two
-- separate moments, potentially seconds apart. Everything the shot needs is captured in `spec` at
-- fire time, so it resolves against the loadout that fired it even if the player has since swapped
-- weapons or unequipped the Ultimate.
function CombatEncounterService.ResolvePlayerHit(player: Player, hitInstance: Instance, origin: Vector3, hitPosition: Vector3, spec): boolean
	local encounter = encounterFor(player)
	if not encounter then
		return false -- nothing to hit; the bullet still stops on geometry, it just deals no damage
	end

	local model = hitInstance
	if model and not encounter.EnemyByModel[model] then
		model = model:FindFirstAncestorOfClass("Model")
	end
	local enemyRecord = model and encounter.EnemyByModel[model]
	if not enemyRecord or not isEnemyAlive(enemyRecord) then
		return false
	end

	-- Headshots. Only weapons that declare a HeadshotMultiplier care where they land — a
	-- flamethrower hitting a head is just a flamethrower. Roblox rigs name the part "Head", and
	-- since the projectile raycast returns the exact part it struck, this needs no extra hit test.
	--
	-- Until now the gold "Headshot" damage colour was only ever produced by the AimBot Ultimate,
	-- which made it a mod-specific flourish rather than a mechanic. Bows are built around it.
	local headshotMultiplier = spec.HeadshotMultiplier or 1
	local isHeadshot = headshotMultiplier > 1 and hitInstance ~= nil and hitInstance.Name == "Head"

	local dealt = resolveAndApplyDamage(
		enemyRecord, spec.Damage * (isHeadshot and headshotMultiplier or 1), origin, hitPosition,
		spec.RangeProfile, spec.Penetration, player, isHeadshot and "Headshot" or "Normal")

	-- Contact status (burn, frostbite, poison...). Applied AFTER damage so a status that kills has
	-- already had the bullet's own damage counted against the same target.
	applyOnHitStatus(enemyRecord, spec.OnHitStatus)

	----------------------------------------------------------------------
	-- Ultimate mod hooks. Fired here — the one place a player's shot LANDS — so they work
	-- identically in base defense, raid rooms and against training dummies without any of those
	-- knowing Ultimates exist.
	----------------------------------------------------------------------

	local ultimate = spec.UltimateKey and UltimateConfig.Mods[spec.UltimateKey]
	if not ultimate then
		return true
	end

	encounter.PlayerState.ShotCount = (encounter.PlayerState.ShotCount or 0) + 1
	local shotNumber = encounter.PlayerState.ShotCount
	enemyRecord.HitsTaken = (enemyRecord.HitsTaken or 0) + 1

	local ctx = {
		Params = ultimate.Params or {},
		Target = enemyRecord,
		Damage = dealt,
		Origin = origin,

		EveryNthShot = function(n: number): boolean
			return n > 0 and (shotNumber % n == 0)
		end,

		CountHitOn = function(record): number
			return record and record.HitsTaken or 0
		end,

		ApplyStatus = function(record, key: string, overrides)
			if record and isEnemyAlive(record) then
				StatusEffects.Apply(record, key, overrides)
			end
		end,

		-- Live enemies within `radius` of the target, nearest first.
		Nearby = function(radius: number, excludeTarget: boolean?, max: number?)
			local targetPart = enemyRecord.Model and enemyRecord.Model.PrimaryPart
			if not targetPart then
				return {}
			end
			local found = {}
			for _, record in pairs(encounter.EnemyByModel) do
				if isEnemyAlive(record) and not (excludeTarget and record == enemyRecord) then
					local distance = (record.Model.PrimaryPart.Position - targetPart.Position).Magnitude
					if distance <= radius then
						table.insert(found, { Record = record, Distance = distance })
					end
				end
			end
			table.sort(found, function(a, b)
				return a.Distance < b.Distance
			end)
			local out = {}
			for i, entry in ipairs(found) do
				if max and i > max then
					break
				end
				table.insert(out, entry.Record)
			end
			return out
		end,

		-- Nearest live enemy to some OTHER enemy, for chaining body to body (Ricochet).
		NearestTo = function(fromRecord, radius: number, exclude)
			local fromPart = fromRecord and fromRecord.Model and fromRecord.Model.PrimaryPart
			if not fromPart then
				return nil
			end
			local best, bestDistance = nil, math.huge
			for _, record in pairs(encounter.EnemyByModel) do
				if isEnemyAlive(record) and not (exclude and exclude[record]) then
					local distance = (record.Model.PrimaryPart.Position - fromPart.Position).Magnitude
					if distance <= radius and distance < bestDistance then
						best, bestDistance = record, distance
					end
				end
			end
			return best
		end,

		-- Tagged "Ultimate" so its numbers render in the Mythical colour — that is what makes a
		-- Ricochet bounce visibly distinct from the bullet that caused it.
		DealDamage = function(record, amount: number, kind: string?)
			if record and amount and amount > 0 and isEnemyAlive(record) then
				resolveAndApplyDamage(record, amount, origin, record.Model.PrimaryPart.Position, nil, 0, player, kind or "Ultimate")
			end
		end,
	}

	UltimateEffects.Fire("OnHit", ultimate.Effect, ctx)
	if enemyRecord.Humanoid.Health <= 0 then
		UltimateEffects.Fire("OnKill", ultimate.Effect, ctx)
	end

	return true
end

ProjectileService.SetHitResolver(CombatEncounterService.ResolvePlayerHit)
GroundEffectService.SetEnemyQuery(CombatEncounterService.LiveEnemiesNear)
GroundEffectService.SetDamageHandler(function(player, record, amount, at, kind)
	resolveAndApplyDamage(record, amount, at, at, nil, 0, player, kind)
end)

----------------------------------------------------------------------
-- Projectile payloads
--
-- Where a projectile STOPS is where its real work happens for anything that is not a plain bullet:
-- a grenade's blast, a poison puddle. Both are OnExpire hooks, so ProjectileService itself never
-- learns that explosions or puddles exist.
----------------------------------------------------------------------

-- Damage falls off linearly from the centre of a blast to its edge, floored at MinMultiplier — so
-- clipping the rim of a grenade still does something, and standing on it is meaningfully worse than
-- being near it. A flat blast makes radius the only stat that matters and positioning irrelevant.
local function explosionMultiplier(distance: number, radius: number, minimum: number): number
	if radius <= 0 then
		return 1
	end
	local t = math.clamp(distance / radius, 0, 1)
	return minimum + (1 - minimum) * (1 - t)
end

local function detonate(player: Player, at: Vector3, damage: number, config)
	local radius = config.Radius or 12
	local minimum = config.MinMultiplier or 0.35

	for _, record in ipairs(CombatEncounterService.LiveEnemiesNear(player, at, radius)) do
		local part = record.Model and record.Model.PrimaryPart
		if part then
			local distance = (part.Position - at).Magnitude
			local amount = damage * explosionMultiplier(distance, radius, minimum)

			-- Tagged "Explosion" so blast damage renders in its own colour. Without that, a grenade
			-- landing in a crowd is a wall of white numbers indistinguishable from gunfire, and there
			-- is no way to tell a blast that caught four enemies from one that caught one.
			resolveAndApplyDamage(record, amount, at, part.Position, nil, config.Penetration or 0, player, "Explosion")

			if config.Status then
				StatusEffects.Apply(record, config.Status.Key, config.Status.Overrides)
			end

			-- The Sticky variant's "they stick to each other": everything caught is dragged toward the
			-- blast centre, so a good throw bunches a group up for whatever you fire next. Applied as a
			-- pivot rather than a velocity because these enemies are Humanoid-driven and would simply
			-- walk the impulse off within a frame or two.
			if config.PullStuds and config.PullStuds > 0 and distance > 1 then
				local toCentre = (at - part.Position)
				local pull = math.min(config.PullStuds, distance - 1)
				record.Model:PivotTo(record.Model:GetPivot() + toCentre.Unit * pull)
			end
		end
	end
end

-- Builds the OnExpire callback for one recipe, composing whichever payloads it declares. Cached per
-- recipe: a weapon firing six pellets twelve times a second must not build seventy-two closures a
-- second for the same unchanging config. Weak-keyed so a removed recipe does not pin its closure.
local onExpireCallbacks = setmetatable({}, { __mode = "k" })

buildOnExpire = function(recipe)
	local existing = onExpireCallbacks[recipe]
	if existing then
		return existing
	end

	local explosion = recipe.Explosion
	local ground = recipe.GroundEffect

	local callback = function(player: Player, at: Vector3, spec)
		if explosion then
			-- spec.Damage is this pellet's share, which for a single-projectile grenade is the whole
			-- shot — so a grenade launcher's BaseDamage is read as its blast damage, and any equipped
			-- mods and affixes are already folded into it.
			detonate(player, at, spec.Damage or 0, explosion)
		end

		if ground then
			-- Chance is what stops a spray weapon from carpeting the floor: five pellets a shot at
			-- seven shots a second would otherwise leave dozens of puddles down every second.
			if ground.Chance and math.random() >= ground.Chance then
				return
			end
			GroundEffectService.Spawn({
				Player = player,
				Shape = "Sphere",
				Position = at,
				Radius = ground.Radius,
				Duration = ground.Duration,
				TickInterval = ground.TickInterval,
				DamagePerTick = ground.DamagePerTick,
				Status = ground.Status,
				Color = ground.Color,
			})
		end
	end

	onExpireCallbacks[recipe] = callback
	return callback
end

-- The client reports only where it fired from and which way it pointed — never what it hit. What
-- it hit is now decided by the projectile actually travelling and colliding, server-side.
--
-- Deliberately does NOT require an active encounter: you can fire at a training dummy, or at
-- nothing at all. A gun that silently refuses to shoot unless something killable is already under
-- the crosshair feels broken, which is exactly how the previous hitscan version was reported.
RequestFireWeapon.OnServerEvent:Connect(function(player: Player, claimedOrigin: Vector3, claimedDirection: Vector3)
	if typeof(claimedOrigin) ~= "Vector3" or typeof(claimedDirection) ~= "Vector3" then
		return
	end
	if claimedDirection.Magnitude < 0.001 then
		return -- a zero direction would make Unit below NaN
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end
	if (claimedOrigin - rootPart.Position).Magnitude > ORIGIN_SANITY_STUDS then
		return -- claimed firing position is too far from where the server knows the player is
	end

	local profile = DataService.Get(player)
	if not profile or not profile.EquippedWeaponId then
		return
	end
	local weaponInstance
	for _, w in ipairs(profile.Weapons) do
		if w.Id == profile.EquippedWeaponId then
			weaponInstance = w
			break
		end
	end
	if not weaponInstance then
		return
	end

	local stats = CombatMath.GetEffectiveWeaponStats(weaponInstance, profile)
	if not stats then
		return
	end

	-- Rate limit, server-side and authoritative. The client paces itself too, but only for feel.
	local cooldown = 1 / math.max(stats.FireRate, 0.01)
	local now = os.clock()
	if now - (lastFireTime[player.UserId] or 0) < cooldown then
		return
	end
	lastFireTime[player.UserId] = now

	local recipe = CraftingRecipes.Weapons[weaponInstance.WeaponKey]

	-- Everything the shot will need on impact, captured NOW — see ResolvePlayerHit's own comment on
	-- why a projectile resolves against the loadout that fired it.
	ProjectileService.Fire(player, claimedOrigin, claimedDirection, {
		Damage = stats.Damage,
		WeaponKey = weaponInstance.WeaponKey,
		UltimateKey = (profile.EquippedUltimate or {})[weaponInstance.WeaponKey],
		RangeProfile = recipe and recipe.RangeProfile,
		Penetration = recipe and recipe.Penetration,
		HeadshotMultiplier = recipe and recipe.HeadshotMultiplier,
		OnHitStatus = recipe and recipe.OnHitStatus,
		OnExpire = recipe and (recipe.Explosion or recipe.GroundEffect) and buildOnExpire(recipe),
		Projectile = ProjectileConfig.Get(recipe and recipe.Projectile),
	})
end)

Players.PlayerRemoving:Connect(function(player)
	activeEncounters[player.UserId] = nil
	lastFireTime[player.UserId] = nil
	GroundEffectService.ClearFor(player)
	-- Both folders: RunWave names its folder "<userId>" and RunRaidCombat names its "<userId>_Raid".
	-- Only the first was cleaned here, so a disconnect mid-raid left its spawned enemies standing in
	-- the world until the raid loop happened to notice on its next tick.
	for _, suffix in ipairs({ "", "_Raid" }) do
		local playerFolder = encounterFolder:FindFirstChild(tostring(player.UserId) .. suffix)
		if playerFolder then
			playerFolder:Destroy()
		end
	end
end)

return CombatEncounterService
