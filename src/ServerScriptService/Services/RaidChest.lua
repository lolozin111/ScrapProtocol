--[[
	RaidChest.lua
	Lootable chests in raid Combat rooms — the user's spec (DESIGN_NOTES, "Raid chests", 2026-09-22);
	every number lives in Shared/RaidChestConfig.lua. A shared utility driven by RaidRoomService's
	beginCombat, not a service: no remotes of its own, not in Main.server.lua's list.

	Four jobs, in the order a Combat room uses them:
	  TryPlace   — find a clear, flat, WALKABLE spot and put the chest there. Runs before any enemy
	               spawns (the user: "spawn the chest first before enemies"). Yields (pathfinding), so
	               it's called from beginCombat's own task.spawn, never on a tick loop.
	  GuardSpawns — 1-2 guard entries in RunRaidCombat's explicitSpawns shape, ringed round the chest,
	               each carrying a GuardPoint so EnemyAwareness keeps it wandering near the chest.
	  Arm        — the 3-second hold prompt, validated server-side, one open per chest.
	  RollLoot   — 1-5 different items; pure, so it's easy to reason about the odds in isolation.

	The chest itself doesn't grant anything: Arm hands the rolled loot to RaidRoomService's callback,
	which pays it through addRunReward — the same run-loot path every other raid drop takes, so a chest
	can never follow different keep-on-death rules than the room around it.

	Missing art never breaks the loop: with no ServerStorage.RaidProps.Chest model, a plain crate is
	built and Output says so once.
]]

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local RaidChestConfig = require(ReplicatedStorage.Shared.RaidChestConfig)

local RaidChest = {}

local warnedNoModel = false
local warnedNoSpot: { [string]: boolean } = {}

----------------------------------------------------------------------
-- Weighted helpers
----------------------------------------------------------------------

-- Picks a key from { [key] = weight }. nil only when every weight is zero.
local function weightedPick(weights: { [any]: number })
	local total = 0
	for _, weight in pairs(weights) do
		total += math.max(weight, 0)
	end
	if total <= 0 then
		return nil
	end
	local roll = math.random() * total
	for key, weight in pairs(weights) do
		roll -= math.max(weight, 0)
		if roll <= 0 then
			return key
		end
	end
	return next(weights) -- float rounding at the very top of the range
end

----------------------------------------------------------------------
-- Loot
----------------------------------------------------------------------

-- Returns a list of { Kind, Key, Amount, RunLocked } — the shape addRunReward and the client's loot
-- toast already use. Each item is DIFFERENT: the pool is built flat (every possible item with its
-- per-draw weight) and drawn from without replacement.
--
-- bonusCount (optional): Scavenger's Lens Lv5's "every chest drops one extra item" — added straight
-- onto the rolled count before the draw loop below, which already stops early
-- ("fewer distinct items exist than the count rolled") once the pool runs out, so this is
-- automatically capped by the pool size with no extra bookkeeping.
function RaidChest.RollLoot(bonusCount: number?)
	local categoryWeights = RaidChestConfig.CategoryWeights

	-- The ore share is split across the ore table in proportion, so "Ore = 40" really does mean 40%
	-- of a draw goes to SOME ore, however many ores are listed.
	local oreTotal = 0
	for _, weight in pairs(RaidChestConfig.OreWeights) do
		oreTotal += weight
	end

	local pool = {} -- itemId -> weight; itemId encodes category + key
	local items = {}
	local function add(category: string, kind: string, key: string, weight: number)
		if weight > 0 then
			local id = category .. ":" .. key
			pool[id] = weight
			items[id] = { Category = category, Kind = kind, Key = key }
		end
	end
	add("Currency", "Currency", "Scrap", categoryWeights.Currency or 0)
	add("Cores", "Currency", "Cores", categoryWeights.Cores or 0)
	add("Contraband", "Currency", "Contraband", categoryWeights.Contraband or 0)
	if oreTotal > 0 then
		for oreKey, weight in pairs(RaidChestConfig.OreWeights) do
			add("Ore", "Ore", oreKey, (categoryWeights.Ore or 0) * weight / oreTotal)
		end
	end

	local count = (weightedPick(RaidChestConfig.ItemCountWeights) or 1) + (bonusCount or 0)
	local loot = {}
	for _ = 1, count do
		local id = weightedPick(pool)
		if not id then
			break -- fewer distinct items exist than the count rolled; give what there is
		end
		pool[id] = nil
		local item = items[id]
		local range = RaidChestConfig.Amounts[item.Category]
		local amount = range and math.random(range.Min, range.Max) or 1
		table.insert(loot, {
			Kind = item.Kind,
			Key = item.Key,
			Amount = amount,
			RunLocked = RaidChestConfig.RunLocked[item.Category] == true,
		})
	end
	return loot
end

----------------------------------------------------------------------
-- The chest model
----------------------------------------------------------------------

local function buildPlaceholder(): Model
	local model = Instance.new("Model")
	model.Name = "Chest"
	local size = RaidChestConfig.PlaceholderSize
	local lidHeight = math.min(0.8, size.Y * 0.3)

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(size.X, size.Y - lidHeight, size.Z)
	base.Color = Color3.fromRGB(110, 78, 48)
	base.Material = Enum.Material.WoodPlanks
	base.Anchored = true
	base.CFrame = CFrame.new(0, base.Size.Y / 2, 0)
	base.Parent = model

	local lid = Instance.new("Part")
	lid.Name = RaidChestConfig.LidName
	lid.Size = Vector3.new(size.X, lidHeight, size.Z)
	lid.Color = Color3.fromRGB(178, 76, 24) -- the HUD's rust accent, so it reads as "loot" at a glance
	lid.Material = Enum.Material.Metal
	lid.Anchored = true
	lid.CFrame = CFrame.new(0, base.Size.Y + lidHeight / 2, 0)
	lid.Parent = model

	model.PrimaryPart = base
	return model
end

local function newChestModel(): Model
	local folder = ServerStorage:FindFirstChild(RaidChestConfig.ModelFolder)
	local template = folder and folder:FindFirstChild(RaidChestConfig.ModelName)
	if template and template:IsA("Model") and template.PrimaryPart then
		local model = template:Clone()
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true -- a prop that can be shoved around is a prop that ends up in a wall
			end
		end
		return model
	end
	if not warnedNoModel then
		warnedNoModel = true
		warn(("[RaidChest] No ServerStorage.%s.%s Model (with a PrimaryPart) — using a plain crate. Build one there to replace it; a part named %q inside tips back when it's opened."):format(
			RaidChestConfig.ModelFolder, RaidChestConfig.ModelName, RaidChestConfig.LidName))
	end
	return buildPlaceholder()
end

----------------------------------------------------------------------
-- Placement
----------------------------------------------------------------------

-- A spot counts when ALL of these hold, cheapest first:
--   1. A collidable, near-flat surface under it (non-collidable markers and decoration are ignored).
--   2. Far enough from where the player came in.
--   3. Nothing collidable overlapping the chest's own box sitting on that surface — "make sure it aint
--      inside anything".
--   4. A path WALKS there from the entry with no jumping — which is what rules out shelf tops, roofs
--      and sealed-off pockets that pass the first three. Only this one yields, so it runs last and on
--      as few candidates as possible.
function RaidChest.TryPlace(roomModel: Model?, roomCenter: Vector3, entryPosition: Vector3?, parent: Instance, ignore: { Instance }?): (Model?, Vector3?)
	local chest = newChestModel()
	local _, chestSize = chest:GetBoundingBox()

	local boundsCFrame, boundsSize
	if roomModel then
		local ok, cf, size = pcall(function()
			return roomModel:GetBoundingBox()
		end)
		if ok then
			boundsCFrame, boundsSize = cf, size
		end
	end
	if not boundsCFrame then
		boundsCFrame, boundsSize = CFrame.new(roomCenter), Vector3.new(120, 40, 120)
	end

	local rayParams = RaycastParams.new()
	rayParams.RespectCanCollide = true
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignore or {}

	local overlapParams = OverlapParams.new()
	overlapParams.RespectCanCollide = true
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = ignore or {}

	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
	local pathChecksLeft = 6 -- each one yields; the cheap checks above filter most candidates first
	local top = boundsSize.Y / 2 + 5

	for _ = 1, RaidChestConfig.PlacementAttempts do
		-- Kept a chest-width inside the room's edges so it never straddles a wall.
		local halfX = math.max(boundsSize.X / 2 - chestSize.X, 1)
		local halfZ = math.max(boundsSize.Z / 2 - chestSize.Z, 1)
		local origin = boundsCFrame * Vector3.new((math.random() * 2 - 1) * halfX, top, (math.random() * 2 - 1) * halfZ)
		local hit = Workspace:Raycast(origin, Vector3.new(0, -(boundsSize.Y + 20), 0), rayParams)

		if hit and hit.Normal.Y >= 0.9 then
			local floor = hit.Position
			local farEnough = not entryPosition
				or Vector2.new(floor.X - entryPosition.X, floor.Z - entryPosition.Z).Magnitude >= RaidChestConfig.MinDistanceFromEntry
			if farEnough then
				local boxCFrame = CFrame.new(floor + Vector3.new(0, chestSize.Y / 2 + 0.2, 0))
				local overlapping = Workspace:GetPartBoundsInBox(boxCFrame, chestSize + Vector3.new(1, 0, 1), overlapParams)
				if #overlapping == 0 then
					local reachable = true
					if entryPosition then
						if pathChecksLeft <= 0 then
							break
						end
						pathChecksLeft -= 1
						local ok = pcall(function()
							path:ComputeAsync(entryPosition, floor)
						end)
						reachable = ok and path.Status == Enum.PathStatus.Success
					end
					if reachable then
						-- Faces the room's centre, so its front (and prompt) points into the play space.
						local look = Vector3.new(roomCenter.X, floor.Y, roomCenter.Z)
						local facing = (look - floor).Magnitude > 0.1 and CFrame.lookAt(floor, look) or CFrame.new(floor)
						chest:PivotTo(facing)
						-- Sit the model's actual bottom on the floor, whatever its pivot is.
						local cf, size = chest:GetBoundingBox()
						chest:PivotTo(chest:GetPivot() + Vector3.new(0, floor.Y - (cf.Position.Y - size.Y / 2), 0))
						chest.Parent = parent
						return chest, floor
					end
				end
			end
		end
	end

	local roomName = roomModel and roomModel.Name or "the fallback room"
	if not warnedNoSpot[roomName] then
		warnedNoSpot[roomName] = true
		warn(("[RaidChest] Couldn't find a clear, walkable spot for a chest in %s after %d tries — no chest this time. If this room should hold one, it may be too cluttered or its floor too far from PlayerSpawn's reachable area."):format(
			roomName, RaidChestConfig.PlacementAttempts))
	end
	chest:Destroy()
	return nil, nil
end

----------------------------------------------------------------------
-- Guards
----------------------------------------------------------------------

-- RunRaidCombat's explicitSpawns shape ({ Position, TypeKey }) plus GuardPoint / GuardWanderRadius,
-- which CombatEncounterService copies onto the spawned record for EnemyAwareness. Each guard's spot is
-- pulled in toward the chest if a wall is in the way, so a guard never spawns inside geometry.
function RaidChest.GuardSpawns(chestFloor: Vector3, ignore: { Instance }?)
	local params = RaycastParams.new()
	params.RespectCanCollide = true
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}

	local spawns = {}
	local count = math.random(RaidChestConfig.GuardCountMin, RaidChestConfig.GuardCountMax)
	local eye = chestFloor + Vector3.new(0, 3, 0)
	for _ = 1, count do
		local typeKey = weightedPick(RaidChestConfig.GuardTypeWeights)
		if typeKey then
			local angle = math.random() * math.pi * 2
			local distance = RaidChestConfig.GuardRingMin + math.random() * (RaidChestConfig.GuardRingMax - RaidChestConfig.GuardRingMin)
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local hit = Workspace:Raycast(eye, direction * distance, params)
			if hit then
				distance = math.max(hit.Distance - 2, 2)
			end
			table.insert(spawns, {
				Position = eye + direction * distance,
				TypeKey = typeKey,
				GuardPoint = chestFloor,
				GuardWanderRadius = RaidChestConfig.GuardWanderRadius,
			})
		end
	end
	return spawns
end

----------------------------------------------------------------------
-- Opening
----------------------------------------------------------------------

local function openLid(chest: Model)
	local lid = chest:FindFirstChild(RaidChestConfig.LidName, true)
	if lid and lid:IsA("BasePart") then
		TweenService:Create(lid, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			CFrame = lid.CFrame * CFrame.new(0, lid.Size.Y * 1.5, 0) * CFrame.Angles(math.rad(-65), 0, 0),
		}):Play()
	end
end

-- opts: { Player: Player, IsCurrent: () -> boolean, OnOpened: (loot) -> (), HoldSeconds: number?,
--         BonusItems: number? }
-- IsCurrent is RaidRoomService's check that this raid and this room are still the live ones — the same
-- stale-prompt guard the Heal/Shop InteractPoint uses. Opens once, for the raid's own player only.
-- HoldSeconds/BonusItems are Scavenger's Lens' Lv4/Lv5 params (RunBuffService.ChestHoldSeconds/
-- ChestBonusItems) — both optional, falling back to the base config numbers/no bonus for a player who
-- doesn't have the perk (or isn't in a raid run at all, e.g. a future non-Salvage-Run caller).
function RaidChest.Arm(chest: Model, opts)
	local anchor = chest.PrimaryPart
	if not anchor then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChestPrompt"
	prompt.ActionText = RaidChestConfig.ActionText
	prompt.ObjectText = RaidChestConfig.ObjectText
	prompt.HoldDuration = opts.HoldSeconds or RaidChestConfig.HoldSeconds
	prompt.MaxActivationDistance = RaidChestConfig.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	local opened = false
	prompt.Triggered:Connect(function(triggeringPlayer)
		if opened or triggeringPlayer ~= opts.Player then
			return
		end
		if opts.IsCurrent and not opts.IsCurrent() then
			return
		end
		opened = true
		prompt:Destroy()
		openLid(chest)
		opts.OnOpened(RaidChest.RollLoot(opts.BonusItems))
	end)
end

return RaidChest
