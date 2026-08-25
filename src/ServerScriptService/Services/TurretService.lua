--[[
	TurretService.lua
	Owns the physical/placement half of the dedicated Turret system (see TurretConfig.lua's own
	header for the full picture and TurretShopService.lua for how a player actually gets a Turret
	instance in the first place — buying a blueprint at the Hub). This file is what turns
	profile.Turrets entries into real, positioned Models in the world, and the three remotes that
	change that: PlaceTurretInSlot, UnplaceTurret, UpgradeTurret.

	SUPERSEDES this file's own first pass from last round entirely — that version gave every
	DEPLOYED ROBOT a freeform physical position ("stand anywhere, click place"). This version is a
	real slot-based placement system (TurretConfig.GetSlotCount(profile.ResearchTier) fixed,
	evenly-spaced positions per base) operating on dedicated Turret instances instead. Robots/
	DeployedRobots/RobotBehaviorConfig are completely untouched elsewhere — still real, still used
	for raid combat support — they just don't reuse this file's placement machinery anymore.

	Combat resolution itself does NOT live here — CombatEncounterService.RunWave reads
	TurretService.GetActiveTurretRecords(player) once at wave start and does its own range-checked
	targeting/firing/particle-emission every tick (see that file). This file only ever answers
	"where do the player's placed turrets physically stand, and what are their current stats" —
	same physical/combat split as the previous pass, just with real per-instance data behind it now.

	Rebuilds happen (full tear-down-and-reclone, never incremental) on: PlotAssigned, and on every
	successful PlaceTurretInSlot/UnplaceTurret/UpgradeTurret. Cheap enough at these slot counts that
	there's no reason to diff — same reasoning as BaseService.lua's own base-Model rebuild.

	Studio setup: drop a Model per TurretConfig.Types key into ServerStorage.TurretModels, named
	EXACTLY that key, floor at local Y=0, PrimaryPart set. Optionally include a child Attachment
	named "Muzzle" (anywhere in the Model, found via FindFirstChild(..., true)) for the fire-particle
	burst to spawn from with the right orientation — if omitted, one is created automatically on the
	PrimaryPart. No Model at all yet? Falls back to a small colored placeholder pedestal.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local BaseConfig = require(ReplicatedStorage.Shared.BaseConfig)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local TurretConfig = require(ReplicatedStorage.Shared.TurretConfig)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local TurretService = {}

local playerTurretFolder: { [Player]: Folder } = {}
-- [player] = list of { Id, TypeKey, Level, WorldPosition, Range, FireRate, Damage, AOE,
-- ParticleColor, Model, Muzzle, LastFireTime } — the SAME table objects CombatEncounterService
-- mutates LastFireTime on tick-to-tick during RunWave (see GetActiveTurretRecords's own comment).
local playerTurretRecords: { [Player]: { any } } = {}

local turretsRootFolder = Workspace:FindFirstChild("PlayerTurrets")
if not turretsRootFolder then
	turretsRootFolder = Instance.new("Folder")
	turretsRootFolder.Name = "PlayerTurrets"
	turretsRootFolder.Parent = Workspace
end

local warnedMissingModel: { [string]: boolean } = {}

-- Tag every slot in the world — empty marker pads AND placed turret models alike — so the client
-- can find them by tag and wire up its own ClickDetector handling, the same way it already does
-- for expedition Nodes and mine ShaftBlocks. Placement moved from a list of rows buried in the
-- Workbench's Base tab to clicking the actual slot in the world, per direct request ("when you
-- click the blue turret zone it opens up your turret inventory... not something that you change
-- on the base tab on the crafting table").
--
-- Attributes the client reads off each tagged instance:
--   SlotIndex   (number) — which ring position this is
--   OwnerUserId (number) — whose base it belongs to; the client ignores other people's slots
--
-- Deliberately NOT stamped: which turret currently occupies the slot. The client already has
-- profile.Turrets (kept current by InventoryUpdate) and derives occupancy from SlotIndex there,
-- so an attribute saying the same thing would be a second copy of the truth that a rebuild could
-- leave stale — and this codebase already has enough written-but-never-read fields.
local SLOT_TAG = "TurretSlot"

-- Same defensive polling pattern BaseService.lua's own waitForProfile uses — PlotAssigned can fire
-- before DataService's asynchronous profile load finishes, and a returning player may already have
-- placed turrets waiting to be rebuilt.
local function waitForProfile(player: Player)
	local profile = DataService.Get(player)
	local attempts = 0
	while not profile and attempts < 50 and player.Parent do
		task.wait(0.1)
		profile = DataService.Get(player)
		attempts += 1
	end
	return profile
end

-- Evenly-spaced ring position (plot-local X/Z offset) for the `index`-th (1-based) slot among
-- `total` slots — fixed positions, not random, so slot 3 is always the same spot every rebuild.
local function ringPosition(index: number, total: number): (number, number)
	local radius = math.min(PlotConfig.FootprintHalfSize.X, PlotConfig.FootprintHalfSize.Z) * BaseConfig.TurretRingRadiusFraction
	local angleStep = total > 0 and (math.pi * 2 / total) or 0
	local angle = (index - 1) * angleStep
	return math.cos(angle) * radius, math.sin(angle) * radius
end

local function buildFallbackModel(typeKey: string, typeData): Model
	if not warnedMissingModel[typeKey] then
		warnedMissingModel[typeKey] = true
		warn(("[TurretService] No %q Model found in ServerStorage.%s — using a plain placeholder pedestal. Build the real Turret Model in Studio to replace this."):format(
			typeKey, BaseConfig.TurretModelsFolderName))
	end

	local size = BaseConfig.TurretFallbackSize
	local part = Instance.new("Part")
	part.Name = "FallbackTurret"
	part.Size = size
	part.Anchored = true
	part.CanCollide = true
	part.Material = Enum.Material.Metal
	-- Muted version of the type's own particle color, so different types are at least visually
	-- distinct before real art exists without being as loud as the fire-particle burst itself.
	local c = typeData.ParticleColor
	part.Color = Color3.new(c.R * 0.5 + 0.15, c.G * 0.5 + 0.15, c.B * 0.5 + 0.15)

	local model = Instance.new("Model")
	model.Name = ("Turret_%s_Fallback"):format(typeKey)
	model.PrimaryPart = part
	part.Parent = model

	return model
end

-- Clones (or builds a fallback for) one turret type's Model, and makes sure it has a "Muzzle"
-- Attachment carrying a manual-emit ParticleEmitter tinted to the type's own ParticleColor —
-- CombatEncounterService calls :Emit() on this every time the turret actually fires. Returns both
-- so RebuildPlayerTurrets can stash the Attachment straight into this turret's combat record.
local function buildTurretModel(typeKey: string, typeData): (Model, Attachment)
	local templateFolder = ServerStorage:FindFirstChild(BaseConfig.TurretModelsFolderName)
	local template = templateFolder and templateFolder:FindFirstChild(typeKey)

	local model
	if template and template:IsA("Model") then
		model = template:Clone()
	else
		model = buildFallbackModel(typeKey, typeData)
	end

	local muzzle = model:FindFirstChild("Muzzle", true)
	if not muzzle or not muzzle:IsA("Attachment") then
		muzzle = Instance.new("Attachment")
		muzzle.Name = "Muzzle"
		muzzle.Parent = model.PrimaryPart
	end

	local emitter = muzzle:FindFirstChildOfClass("ParticleEmitter")
	if not emitter then
		emitter = Instance.new("ParticleEmitter")
		emitter.Name = "FireBurst"
		-- Texture deliberately left at its engine default rather than guessing an rbxasset path —
		-- the default is always valid; a made-up path risks silently rendering nothing.
		emitter.Lifetime = NumberRange.new(0.12, 0.25)
		emitter.Speed = NumberRange.new(10, 16)
		emitter.Rate = 0 -- manual :Emit() only, see CombatEncounterService's turret-fire tick
		emitter.Color = ColorSequence.new(typeData.ParticleColor)
		emitter.Size = NumberSequence.new(0.5)
		emitter.Parent = muzzle
	end

	return model, muzzle
end

-- Small translucent pad + floating label marking an EMPTY slot, so the player can see where
-- turrets can go before they place one — direct request ("make sure that the player is able to
-- see possible slots where they can put their turret").
local function buildSlotMarker(slotIndex: number): Model
	local part = Instance.new("Part")
	part.Name = "TurretSlotMarker"
	part.Size = Vector3.new(4, 0.2, 4)
	part.Anchored = true
	part.CanCollide = false
	-- MUST stay queryable. This was CanQuery = false back when the pad was purely decorative, and
	-- that single property is what made the whole slot unclickable once placement moved in-world:
	-- CanQuery = false means mouse/raycasts pass straight THROUGH the part, so the ClickDetector
	-- can never be hit and clicking it does nothing at all, silently.
	part.CanQuery = true
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(90, 200, 255)
	part.Transparency = 0.45

	local label = Instance.new("BillboardGui")
	label.Size = UDim2.new(0, 120, 0, 30)
	label.StudsOffset = Vector3.new(0, 2, 0)
	label.AlwaysOnTop = true
	label.Parent = part

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, 0, 1, 0)
	text.Font = Enum.Font.SourceSansBold
	text.TextColor3 = Color3.fromRGB(140, 220, 255)
	text.TextStrokeTransparency = 0.4
	text.TextSize = 14
	-- Says what to DO with it, not just what it is — this pad is the entry point to placement now,
	-- so the label has to advertise that it's clickable.
	text.Text = ("Turret Slot %d — Click to place"):format(slotIndex)
	text.Parent = label

	local model = Instance.new("Model")
	model.Name = ("TurretSlot_%d"):format(slotIndex)
	model.PrimaryPart = part
	part.Parent = model

	-- Invisible click volume standing on top of the pad. The pad itself is a 0.2-stud-thin plate
	-- lying flat on the ground, which is a genuinely awkward thing to hit with the mouse from a
	-- standing player's camera angle — you have to look almost straight down at it. This gives the
	-- slot a body-height target instead. Invisible and non-colliding, so it changes nothing about
	-- how the slot looks or how you walk through it; the ClickDetector lives on the Model, so a
	-- click on either part opens the same panel.
	local clickVolume = Instance.new("Part")
	clickVolume.Name = "ClickVolume"
	clickVolume.Size = Vector3.new(4, 6, 4)
	clickVolume.Anchored = true
	clickVolume.CanCollide = false
	clickVolume.CanQuery = true
	clickVolume.Transparency = 1
	clickVolume.CFrame = part.CFrame * CFrame.new(0, 3, 0)
	clickVolume.Parent = model

	return model
end

-- Makes one slot (empty marker or placed turret) clickable and identifiable to the client. The
-- ClickDetector is created server-side so it exists for everyone automatically; the OwnerUserId
-- attribute is what actually scopes it, exactly like BaseService stamps station ownership.
local function makeSlotInteractive(model: Model, slotIndex: number, player: Player)
	model:SetAttribute("SlotIndex", slotIndex)
	model:SetAttribute("OwnerUserId", player.UserId)

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.Name = "SlotClick" -- named, not left as the default, so the client can
		-- WaitForChild it by name rather than racing FindFirstChildOfClass against replication
	clickDetector.MaxActivationDistance = TurretConfig.SlotInteractDistance
	clickDetector.CursorIcon = ""
	clickDetector.Parent = model

	-- Tagged LAST, after the attributes and the ClickDetector are already parented, so that by the
	-- time the client's tag-added signal fires everything it needs to read is present on the model.
	CollectionService:AddTag(model, SLOT_TAG)
end

local function findTurret(profile, turretId: string)
	for _, turret in ipairs(profile.Turrets) do
		if turret.Id == turretId then
			return turret
		end
	end
	return nil
end

-- Tears down and rebuilds every physical turret Model AND empty-slot marker for `player`, reading
-- their current Turrets/ResearchTier straight from DataService. Safe to call as often as needed —
-- see this file's header on why a full rebuild (not a diff) is fine at these counts.
function TurretService.RebuildPlayerTurrets(player: Player)
	local profile = waitForProfile(player)
	local plot = PlotService.GetPlayerPlot(player)

	local existing = playerTurretFolder[player]
	if existing then
		existing:Destroy()
		playerTurretFolder[player] = nil
	end
	playerTurretRecords[player] = nil

	if not profile or not plot then
		return
	end

	local slotCount = TurretConfig.GetSlotCount(profile.ResearchTier)

	local folder = Instance.new("Folder")
	folder.Name = tostring(player.UserId)
	folder.Parent = turretsRootFolder
	playerTurretFolder[player] = folder

	local turretBySlot = {}
	for _, turret in ipairs(profile.Turrets) do
		if turret.SlotIndex then
			turretBySlot[turret.SlotIndex] = turret
		end
	end

	local records = {}

	for slotIndex = 1, slotCount do
		local offsetX, offsetZ = ringPosition(slotIndex, slotCount)
		local turret = turretBySlot[slotIndex]

		if turret and TurretConfig.Types[turret.TypeKey] then
			local typeData = TurretConfig.Types[turret.TypeKey]
			local model, muzzle = buildTurretModel(turret.TypeKey, typeData)
			local size = model.PrimaryPart and model.PrimaryPart.Size or BaseConfig.TurretFallbackSize
			local worldCFrame = plot.CFrame * CFrame.new(offsetX, size.Y / 2, offsetZ)
			if model.PrimaryPart then
				model:PivotTo(worldCFrame)
			end
			-- Clicking a PLACED turret opens the same slot panel, showing this turret's stats with
			-- Upgrade/Unplace instead of a list to place from — so managing a turret happens at the
			-- turret, not in a menu somewhere else.
			makeSlotInteractive(model, slotIndex, player)
			model.Parent = folder

			local effectiveStats = TurretConfig.GetTurretEffectiveStats(turret.TypeKey, turret.Level)
			table.insert(records, {
				Id = turret.Id,
				TypeKey = turret.TypeKey,
				Level = turret.Level,
				WorldPosition = worldCFrame.Position,
				Range = effectiveStats.Range,
				FireRate = effectiveStats.FireRate,
				Damage = effectiveStats.Damage,
				AOE = effectiveStats.AOE,
				ParticleColor = typeData.ParticleColor,
				Model = model,
				Muzzle = muzzle,
				LastFireTime = 0,
			})
		else
			local marker = buildSlotMarker(slotIndex)
			local worldCFrame = plot.CFrame * CFrame.new(offsetX, (marker.PrimaryPart :: BasePart).Size.Y / 2, offsetZ)
			marker:PivotTo(worldCFrame)
			makeSlotInteractive(marker, slotIndex, player)
			marker.Parent = folder
		end
	end

	playerTurretRecords[player] = records
end

-- Read by CombatEncounterService.RunWave ONCE at wave start — the returned tables are the SAME
-- references this file's own playerTurretRecords cache holds, so CombatEncounterService mutating
-- record.LastFireTime tick-to-tick during combat is really just updating this file's own cache in
-- place. Nothing else mutates these tables concurrently (rebuilds fully replace the list, they
-- never edit records in place), so this is safe without any extra locking.
function TurretService.GetActiveTurretRecords(player: Player): { any }
	return playerTurretRecords[player] or {}
end

-- PlaceTurretInSlot: moves (or first-places) one owned Turret instance into a specific slot.
-- Moving an already-placed turret to a different slot just overwrites SlotIndex — the slot it used
-- to occupy opens back up automatically on the next rebuild since turretBySlot above is recomputed
-- fresh from profile.Turrets every time, not tracked as separate state.
Remotes.PlaceTurretInSlot.OnServerInvoke = function(player: Player, turretId: string, slotIndex: number)
	if not PlotService.IsPlayerInOwnPlot(player) then
		return { Success = false, Reason = PlotConfig.NotInBaseMessage }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	local turret = findTurret(profile, turretId)
	if not turret then
		return { Success = false, Reason = "You don't own this turret" }
	end

	local slotCount = TurretConfig.GetSlotCount(profile.ResearchTier)
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > slotCount or slotIndex ~= math.floor(slotIndex) then
		return { Success = false, Reason = "Invalid slot" }
	end

	for _, other in ipairs(profile.Turrets) do
		if other ~= turret and other.SlotIndex == slotIndex then
			return { Success = false, Reason = "That slot is already occupied" }
		end
	end

	turret.SlotIndex = slotIndex
	TurretService.RebuildPlayerTurrets(player)
	Remotes.InventoryUpdate:FireClient(player, { Turrets = profile.Turrets })

	return { Success = true }
end

-- UnplaceTurret: sends a placed turret back to storage (still owned, just not defending right
-- now), freeing its slot.
Remotes.UnplaceTurret.OnServerInvoke = function(player: Player, turretId: string)
	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	local turret = findTurret(profile, turretId)
	if not turret then
		return { Success = false, Reason = "You don't own this turret" }
	end

	turret.SlotIndex = nil
	TurretService.RebuildPlayerTurrets(player)
	Remotes.InventoryUpdate:FireClient(player, { Turrets = profile.Turrets })

	return { Success = true }
end

-- UpgradeTurret: spends TurretConfig.GetTurretUpgradeCost(currentLevel) Cores to bump one turret
-- instance's Level by 1. Crossing into a new Tier (every TurretConfig.LevelsPerTier levels)
-- additionally requires profile.ResearchTier to have caught up — see TurretConfig.lua's own header
-- on why this is a deliberate skeleton gate, not a bug, until the real Research phase ships.
Remotes.UpgradeTurret.OnServerInvoke = function(player: Player, turretId: string)
	if not PlotService.IsPlayerInOwnPlot(player) then
		return { Success = false, Reason = PlotConfig.NotInBaseMessage }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	local turret = findTurret(profile, turretId)
	if not turret then
		return { Success = false, Reason = "You don't own this turret" }
	end

	local currentTier = TurretConfig.GetTurretTier(turret.Level)
	local newLevel = turret.Level + 1
	local newTier = TurretConfig.GetTurretTier(newLevel)

	if newTier > currentTier and (profile.ResearchTier or 1) < newTier then
		return { Success = false, Reason = ("Requires Research Tier %d (still a skeleton system — coming next)"):format(newTier) }
	end

	local cost = TurretConfig.GetTurretUpgradeCost(turret.Level)
	if not DataService.TrySpend(player, { [TurretConfig.UpgradeCurrency] = cost }) then
		return { Success = false, Reason = ("Not enough %s (need %d)"):format(TurretConfig.UpgradeCurrency, cost) }
	end

	turret.Level = newLevel
	if turret.SlotIndex then
		TurretService.RebuildPlayerTurrets(player)
	end
	-- PushWallet as well as the Turrets patch: the Cores spent above were deducted server-side but
	-- never broadcast, so the HUD's currency readout kept showing the pre-upgrade number and the
	-- upgrade looked free. See DataService.PushWallet.
	Remotes.InventoryUpdate:FireClient(player, { Turrets = profile.Turrets })
	DataService.PushWallet(player)

	return { Success = true, Level = turret.Level }
end

PlotService.PlotAssigned:Connect(function(player, _plot)
	task.spawn(TurretService.RebuildPlayerTurrets, player)
end)

Players.PlayerRemoving:Connect(function(player)
	local existing = playerTurretFolder[player]
	if existing then
		existing:Destroy()
	end
	playerTurretFolder[player] = nil
	playerTurretRecords[player] = nil
end)

return TurretService
