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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BaseConfig = require(ReplicatedStorage.Shared.BaseConfig)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

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

	local existing = playerBaseModel[player]
	if existing then
		existing:Destroy()
	end

	baseModel.Parent = Workspace
	playerBaseModel[player] = baseModel
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
