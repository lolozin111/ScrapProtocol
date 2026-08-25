--[[
	BaseService.lua
	Physically builds each player's base once PlotService assigns them a plot: clones a Model from
	ReplicatedStorage.BaseTemplates onto the plot's anchor CFrame, picking WHICH tier's Model from
	profile.BaseTier (a saved field, same shape as ToolTier/SuitTier — currently always 1, no
	purchase flow wired up yet, see BaseConfig.lua's header comment).

	Split out from PlotService on purpose: PlotService only owns WHERE a player's base lives
	(picking/assigning/freeing a Plot anchor and moving the character there) and knows nothing
	about what gets built there. BaseService owns WHAT gets built, keyed off save data — different
	players (or the same player after a future base upgrade) can have completely different
	physical structures sitting in the exact same spot, without PlotService needing to change at
	all. RebuildPlayerBase is exposed and safe to call again later — swapping a player's base tier
	once an upgrade remote exists is just calling this a second time.

	No template Model yet for the player's tier? Rather than leave them standing on an invisible,
	non-collidable Plot anchor (a guaranteed fall into the void), this clones a single plain
	placeholder floor instead and warns in Output — same "functional before art" approach used
	everywhere else in this project (see MineShaftService's plain colored blocks, WaveService's
	headless combat sim, etc.). Replace it by building the real Model in Studio; no code changes
	needed once it exists.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BaseConfig = require(ReplicatedStorage.Shared.BaseConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StationService = require(script.Parent.StationService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local FALLBACK_FLOOR_SIZE = Vector3.new(40, 2, 40)
local FALLBACK_FLOOR_COLOR = Color3.fromRGB(90, 80, 70)

local BaseService = {}

local playerBaseModel: { [Player]: Model } = {} -- currently-built base Model per player

-- DataService's own PlayerAdded handler loads the profile asynchronously (a yielding DataStore
-- call), and Roblox doesn't guarantee that finishes before PlotService's separately-connected
-- PlayerAdded handler assigns a plot and fires PlotAssigned — so this may run before the profile
-- is cached. Same defensive polling pattern Remotes.GetProfile.OnServerInvoke already uses.
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

local function tierData(tierIndex: number)
	return BaseConfig.Tiers[tierIndex] or BaseConfig.Tiers[1]
end

-- Stamps every Station-tagged descendant of a player's freshly-built base with WHO it belongs to.
-- StationService checks this attribute so a station only works for its owner — other players
-- standing right next to it get turned away, same as if no station were there at all. A station
-- with no OwnerUserId attribute (e.g. a loose testing block not part of any base Model yet) is
-- left open to everyone on purpose, so placeholder-block testing keeps working with zero setup.
local function tagStationOwnership(baseModel: Model, player: Player)
	for _, inst in ipairs(baseModel:GetDescendants()) do
		if CollectionService:HasTag(inst, StationConfig.Tag) then
			inst:SetAttribute("OwnerUserId", player.UserId)
		end
	end
end

-- Top surface sits exactly at the plot anchor's own height, matching the convention a real Base
-- Model template should follow (floor at local Y=0 relative to the anchor).
local function buildFallbackBase(player: Player, plot: Instance): Model
	local floor = Instance.new("Part")
	floor.Name = "FallbackFloor"
	floor.Size = FALLBACK_FLOOR_SIZE
	floor.Anchored = true
	floor.CanCollide = true
	floor.Material = Enum.Material.Concrete
	floor.Color = FALLBACK_FLOOR_COLOR
	floor.CFrame = plot.CFrame * CFrame.new(0, -FALLBACK_FLOOR_SIZE.Y / 2, 0)

	local model = Instance.new("Model")
	model.Name = ("%s_Base_Fallback"):format(player.Name)
	model.PrimaryPart = floor
	floor.Parent = model

	return model
end

-- Destroys whatever base Model is currently built for this player (if any) and clones/positions
-- the one matching their current profile.BaseTier in its place.
function BaseService.RebuildPlayerBase(player: Player, plot: Instance)
	local profile = waitForProfile(player)
	if not profile then
		warn(("[BaseService] Profile never loaded for %s — base not built."):format(player.Name))
		return
	end

	local tier = tierData(profile.BaseTier or 1)
	local templateFolder = ReplicatedStorage:FindFirstChild(BaseConfig.TemplateFolderName)
	local template = templateFolder and templateFolder:FindFirstChild(tier.ModelName)

	local baseModel
	if template and template:IsA("Model") then
		baseModel = template:Clone()
		baseModel.Name = ("%s_Base"):format(player.Name)
		baseModel:PivotTo(plot.CFrame)
	else
		warn(("[BaseService] No %q Model found in ReplicatedStorage.%s — using a plain placeholder floor. Build the real base Model in Studio to replace this."):format(
			tier.ModelName, BaseConfig.TemplateFolderName))
		baseModel = buildFallbackBase(player, plot)
	end

	tagStationOwnership(baseModel, player)

	local existing = playerBaseModel[player]
	if existing then
		existing:Destroy()
	end

	baseModel.Parent = Workspace
	playerBaseModel[player] = baseModel
end

-- Exposes the actual currently-built base Model (real BaseTier art, or the fallback floor if none
-- exists yet) so other systems can measure its REAL size instead of guessing. Added for
-- CombatEncounterService.lua's wall-defense boundary — see that file's getWallAttackRange — after
-- a hardcoded BaseConfig.WallAttackRange guess (tuned against PlotConfig.FootprintHalfSize, the
-- max CLAIMED plot area) turned out much bigger than FALLBACK_FLOOR_SIZE (the actual placeholder
-- floor most testing uses today), so enemies were "stopping at the wall" well past the visible
-- platform's real edge — nowhere close to a wall, right in the middle. Returns nil if the base
-- hasn't finished building yet (RebuildPlayerBase yields on the profile load).
function BaseService.GetPlayerBaseModel(player: Player): Model?
	return playerBaseModel[player]
end

-- UpgradeBase: spends BaseConfig.BaseTierCosts[nextTier], bumps profile.BaseTier, and rebuilds the
-- physical base Model in place — same shape as UpgradeTool/UpgradeSuit (MiningService.lua/
-- MineShaftService.lua), gated at the same "Crafting" (Workbench) station those use, since
-- upgrading your base is exactly the same kind of general equipment/utility decision as those.
Remotes.UpgradeBase.OnServerInvoke = function(player: Player)
	if not PlotService.IsPlayerInOwnPlot(player) then
		return { Success = false, Reason = PlotConfig.NotInBaseMessage }
	end
	if not StationService.IsPlayerNearStation(player, "Crafting") then
		return { Success = false, Reason = StationConfig.Types.Crafting.NotThereMessage }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	local nextTier = (profile.BaseTier or 1) + 1
	local nextTierData = BaseConfig.Tiers[nextTier]
	if not nextTierData then
		return { Success = false, Reason = "Max tier reached" }
	end

	local cost = BaseConfig.BaseTierCosts[nextTier]
	if not cost then
		return { Success = false, Reason = "Not configured" }
	end

	-- CoreItem gate (see BaseConfig.BaseTierCoreRequirement's own comment) — checked READ-ONLY
	-- before either spend commits anything, so a missing core rejects the whole upgrade without
	-- silently burning the resource cost. Nothing yields between this check and TrySpendCoreItem
	-- below, so there's no window for another call to spend the same CoreItems out from under us.
	local coreRequirement = BaseConfig.BaseTierCoreRequirement[nextTier]
	if coreRequirement and (profile.CoreItems[coreRequirement.Key] or 0) < coreRequirement.Amount then
		return { Success = false, Reason = ("Requires %d x %s from a base-defense boss wave"):format(
			coreRequirement.Amount, coreRequirement.Key) }
	end

	if not DataService.TrySpend(player, cost) then
		return { Success = false, Reason = "Not enough resources" }
	end
	if coreRequirement then
		DataService.TrySpendCoreItem(player, coreRequirement.Key, coreRequirement.Amount)
	end

	profile.BaseTier = nextTier

	local plot = PlotService.GetPlayerPlot(player)
	if plot then
		-- Yields on the profile (already loaded here, so effectively instant) — safe to call inline
		-- rather than task.spawn, since the remote's own caller is already waiting on a response.
		BaseService.RebuildPlayerBase(player, plot)
	end

	Remotes.InventoryUpdate:FireClient(player, { BaseTier = profile.BaseTier, CoreItems = profile.CoreItems })

	return { Success = true, BaseTier = profile.BaseTier }
end

PlotService.PlotAssigned:Connect(function(player, plot)
	task.spawn(BaseService.RebuildPlayerBase, player, plot)
end)

Players.PlayerRemoving:Connect(function(player)
	local existing = playerBaseModel[player]
	if existing then
		existing:Destroy()
	end
	playerBaseModel[player] = nil
end)

return BaseService
