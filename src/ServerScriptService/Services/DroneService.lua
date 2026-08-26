--[[
	DroneService.lua
	The drone companion: a real body that follows the player everywhere, running whichever Drone Core
	is slotted into it.

	See DroneConfig.lua for the Cores and how they are earned, DroneBehaviors.lua for what each one
	does, and DESIGN_NOTES.md's "Drone companion" section for the design.

	=== A REAL BODY, DELIBERATELY ===
	Deployed robots in this game are ABSTRACT — no model, no position, they just tick effects from
	wherever you are (see DESIGN_NOTES). That was the right call for robots, which are a defense
	loadout you set and forget. It would be the wrong call here: the entire appeal of a companion is
	that it is THERE. So the drone is a real anchored Part, stepped every frame, that visibly trails
	you and visibly tints to whichever Core is active.

	=== NO CIRCULAR REQUIRE ===
	Combat and Recon Cores need live enemies and the damage pipeline, both of which live in
	CombatEncounterService — which requires half the game and must not be required back. Same
	solution as GroundEffectService: CombatEncounterService injects the two functions it owns at
	load, and this file requires nothing from it.

	=== WHY ANCHORED AND SERVER-STEPPED ===
	An unanchored part with a BodyPosition would be simulated by whichever client owns it, so the
	drone would drift differently for everyone and could be shoved through walls by a physics prank.
	Anchored and CFramed by the server keeps one authoritative position, which matters because that
	position is what its Core actually acts from.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local DroneConfig = require(ReplicatedStorage.Shared.DroneConfig)
local OreConfig = require(ReplicatedStorage.Shared.OreConfig)
local DataService = require(script.Parent.DataService)
local DroneBehaviors = require(script.Parent.DroneBehaviors)
local StatusEffects = require(script.Parent.StatusEffects)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local DroneService = {}

-- Injected by CombatEncounterService at load — see the header. Both are nil until then, and every
-- use below tolerates that, so a Core equipped during boot does nothing for a frame rather than
-- erroring.
local liveEnemiesNear: ((Player, Vector3, number) -> { any })? = nil
local dealDamage: ((Player, any, number, Vector3, string) -> ())? = nil

function DroneService.SetEnemyQuery(fn)
	liveEnemiesNear = fn
end

function DroneService.SetDamageHandler(fn)
	dealDamage = fn
end

local droneFolder = Workspace:FindFirstChild("Drones")
if not droneFolder then
	droneFolder = Instance.new("Folder")
	droneFolder.Name = "Drones"
	droneFolder.Parent = Workspace
end

-- One record per player with a drone out.
local drones: { [number]: any } = {}

-- When each player last took damage, for the Support Core's suppression window. Tracked here rather
-- than on the encounter, because the drone follows you outside encounters too.
local lastDamagedAt: { [number]: number } = {}

----------------------------------------------------------------------
-- Body
----------------------------------------------------------------------

-- Missing art never breaks the loop (see CLAUDE.md): a real Model is used when one exists, and a
-- plain tinted box stands in when it does not, with a warn rather than an error.
local function buildBody(coreData): BasePart
	local models = ServerStorage:FindFirstChild("DroneModels")
	local template = models and models:FindFirstChild("Drone")
	if template and template:IsA("Model") and template.PrimaryPart then
		local clone = template:Clone()
		clone.Name = "DroneBody"
		for _, part in ipairs(clone:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false -- must never stop the player's own projectiles
			end
		end
		clone.Parent = droneFolder
		return clone.PrimaryPart
	end

	local part = Instance.new("Part")
	part.Name = "DroneBody"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.6, 1.6, 1.6)
	part.Material = Enum.Material.Neon
	part.Color = coreData and coreData.Color or Color3.fromRGB(200, 200, 210)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Parent = droneFolder
	return part
end

local function destroyDrone(userId: number)
	local drone = drones[userId]
	if not drone then
		return
	end
	-- The body may be a Model's PrimaryPart, so destroy the outermost thing we actually parented into
	-- the folder — destroying just the PrimaryPart would leave the rest of the model behind.
	local body = drone.Body
	if body then
		local model = body:FindFirstAncestorOfClass("Model")
		if model and model.Parent == droneFolder then
			model:Destroy()
		else
			body:Destroy()
		end
	end
	drones[userId] = nil
end

----------------------------------------------------------------------
-- Context handed to behaviours
----------------------------------------------------------------------

local function tickContext(player: Player, drone, coreData, profile)
	return {
		-- Scaled by Research Tier here, once, so every behaviour reads plain numbers and none of them
		-- has to know that scaling exists.
		Params = DroneConfig.ScaledParams(coreData, profile),
		Player = player,
		Position = drone.Position,
		Character = player.Character,
		Humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid"),

		EnemiesNear = function(radius: number)
			if not liveEnemiesNear then
				return {}
			end
			return liveEnemiesNear(player, drone.Position, radius)
		end,

		DealDamage = function(record, amount: number, kind: string?)
			local part = record and record.Model and record.Model.PrimaryPart
			if dealDamage and part and amount and amount > 0 then
				dealDamage(player, record, amount, part.Position, kind or "Drone")
			end
		end,

		ApplyStatus = function(record, key: string, overrides)
			if record then
				StatusEffects.Apply(record, key, overrides)
			end
		end,

		-- A Highlight rather than a status: being able to SEE a marked enemy through a wall is the
		-- point of Recon, and that is presentation, not a combat rule. Debris-cleaned so a marked
		-- enemy that walks out of range stops glowing on its own.
		Mark = function(record, duration: number)
			local model = record and record.Model
			if not model or model:FindFirstChild("DroneMark") then
				return -- already marked; re-adding would stack Highlights on one model
			end
			local highlight = Instance.new("Highlight")
			highlight.Name = "DroneMark"
			highlight.FillTransparency = 0.75
			highlight.FillColor = Color3.fromRGB(140, 190, 255)
			highlight.OutlineColor = Color3.fromRGB(200, 225, 255)
			highlight.Parent = model
			Debris:AddItem(highlight, duration)
		end,

		-- Turns the body toward whatever the Core is acting on. Cosmetic, but it is the difference
		-- between a ball that drifts near you and a companion that visibly picks a target — and a
		-- Combat Core you cannot see aiming is one you cannot tell is working.
		FaceTarget = function(record)
			local part = record and record.Model and record.Model.PrimaryPart
			if part then
				drone.LookAt = part.Position
				drone.LookAtUntil = os.clock() + 1.5
			end
		end,

		SecondsSinceDamaged = function(): number
			return os.clock() - (lastDamagedAt[player.UserId] or -math.huge)
		end,

		ShowHeal = function(amount: number)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and amount and amount >= 1 then
				-- Reuses the damage-number remote with its own kind, so healing is as visible as
				-- damage is. A Core whose whole job is a slowly rising health bar would otherwise be
				-- the least legible thing in the game.
				Remotes.DamageNumber:FireClient(player, root.Position, math.floor(amount + 0.5), "Heal")
			end
		end,

		Toast = function(message: string)
			Remotes.DroneEvent:FireClient(player, message)
		end,
	}
end

----------------------------------------------------------------------
-- Spawn / despawn
----------------------------------------------------------------------

-- Rebuilds the drone from the profile — the source of truth — rather than mutating whatever is
-- currently out. Called on equip, on unlock, on spawn, and on rejoin, so all four paths converge.
function DroneService.Sync(player: Player)
	local profile = DataService.Get(player)
	local coreData = profile and DroneConfig.Equipped(profile)

	if not profile or not coreData or not DroneConfig.IsUnlocked(profile) then
		destroyDrone(player.UserId)
		return
	end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		destroyDrone(player.UserId)
		return -- the CharacterAdded hook below re-syncs once there is something to follow
	end

	destroyDrone(player.UserId) -- simplest correct swap: never reuse a body across Cores
	local body = buildBody(coreData)
	body.Color = coreData.Color or body.Color

	drones[player.UserId] = {
		Player = player,
		Body = body,
		Position = root.Position,
		CoreKey = profile.EquippedDroneCore,
		Core = coreData,
		NextTick = os.clock() + (coreData.TickInterval or 1),
		Phase = math.random() * 10, -- so two players' drones do not bob in lockstep
	}
end

----------------------------------------------------------------------
-- Flight + ticking
----------------------------------------------------------------------

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()

	for userId, drone in pairs(drones) do
		local player = drone.Player
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if not root or not drone.Body or not drone.Body.Parent then
			-- Character gone (respawn, teleport between raid rooms). Drop the body; the
			-- CharacterAdded hook rebuilds it.
			destroyDrone(userId)
		else
			local follow = DroneConfig.Follow
			-- Offset in the PLAYER's own space, so the drone stays over your shoulder as you turn
			-- rather than swinging around you when you spin on the spot.
			local target = root.CFrame:PointToWorldSpace(follow.Offset)
			target += Vector3.new(0, math.sin((now + drone.Phase) * follow.BobSpeed) * follow.BobHeight, 0)

			local gap = target - drone.Position
			if gap.Magnitude > follow.TeleportDistance then
				drone.Position = target -- respawned, fell down a mine shaft, or teleported into a raid
			else
				-- Framerate-independent smoothing: the naive `+ gap * smoothing * dt` version closes
				-- a different fraction of the gap at 30fps than at 144, so the drone would visibly lag
				-- more on a slower machine.
				drone.Position += gap * (1 - math.exp(-follow.Smoothing * dt))
			end

			-- Faces whatever it last acted on, briefly, then goes back to looking where you look.
			-- Expiring rather than latching means it does not keep staring at a corpse.
			if drone.LookAtUntil and now >= drone.LookAtUntil then
				drone.LookAt = nil
			end
			local facing = drone.LookAt or (drone.Position + root.CFrame.LookVector * 10)
			drone.Body.CFrame = CFrame.lookAt(drone.Position, facing)

			local interval = drone.Core.TickInterval or 0
			if interval > 0 and now >= drone.NextTick then
				drone.NextTick = now + interval
				local ctx = tickContext(player, drone, drone.Core, DataService.Get(player))
				DroneBehaviors.Fire("Tick", drone.Core.Behavior, ctx)
			end
		end
	end
end)

----------------------------------------------------------------------
-- Mining hook — Scavenger
----------------------------------------------------------------------

-- Returns BONUS ore to grant on top of the normal yield, or 0. Called by MiningService and
-- MineShaftService; both hand over what they were about to grant, and neither needs to know which
-- Core (if any) is slotted.
function DroneService.BonusOreFor(player: Player, oreKey: string, yield: number): number
	local profile = DataService.Get(player)
	local coreData = profile and DroneConfig.Equipped(profile)
	if not coreData or not DroneConfig.IsUnlocked(profile) then
		return 0
	end
	if not DroneBehaviors.OnMine[coreData.Behavior] then
		return 0 -- a Combat Core has no mining hook; that is normal, not a misconfiguration
	end

	local ore = OreConfig.Ores[oreKey]
	local bonus = DroneBehaviors.Fire("OnMine", coreData.Behavior, {
		Params = DroneConfig.ScaledParams(coreData, profile),
		Player = player,
		Yield = yield,
		OreKey = oreKey,
		OreDisplayName = (ore and ore.DisplayName) or oreKey,
		Toast = function(message: string)
			Remotes.DroneEvent:FireClient(player, message)
		end,
	})

	return tonumber(bonus) or 0
end

-- Called by the combat code whenever the player takes a hit, so the Support Core knows to hold off.
function DroneService.NotePlayerDamaged(player: Player)
	lastDamagedAt[player.UserId] = os.clock()
end

----------------------------------------------------------------------
-- Equip
----------------------------------------------------------------------

Remotes.EquipDroneCore.OnServerInvoke = function(player: Player, coreKey: string?)
	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	if not DroneConfig.IsUnlocked(profile) then
		return {
			Success = false,
			Reason = ("Drones unlock at Research Tier %d."):format(DroneConfig.UnlockResearchTier),
		}
	end

	if coreKey == nil then
		profile.EquippedDroneCore = nil
		Remotes.InventoryUpdate:FireClient(player, { EquippedDroneCore = false })
		DroneService.Sync(player)
		return { Success = true }
	end

	if not DroneConfig.Cores[coreKey] then
		return { Success = false, Reason = "Unknown Drone Core" }
	end
	if not (profile.OwnedDroneCores or {})[coreKey] then
		return { Success = false, Reason = "You don't own that Core." }
	end

	profile.EquippedDroneCore = coreKey
	Remotes.InventoryUpdate:FireClient(player, { EquippedDroneCore = coreKey })
	DroneService.Sync(player)
	return { Success = true, EquippedDroneCore = coreKey }
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

local function trackCharacter(player: Player, character: Model)
	character:WaitForChild("HumanoidRootPart", 10)
	DroneService.Sync(player)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- HealthChanged is the one signal that catches every source of damage — enemies, lava,
		-- falling — without each of them having to remember to report it.
		local last = humanoid.Health
		humanoid.HealthChanged:Connect(function(health)
			if health < last then
				lastDamagedAt[player.UserId] = os.clock()
			end
			last = health
		end)
	end
end

local function track(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(trackCharacter, player, character)
	end)
	if player.Character then
		task.spawn(trackCharacter, player, player.Character)
	end
end

Players.PlayerAdded:Connect(track)
for _, player in ipairs(Players:GetPlayers()) do
	track(player)
end

Players.PlayerRemoving:Connect(function(player)
	destroyDrone(player.UserId)
	lastDamagedAt[player.UserId] = nil
end)

return DroneService
