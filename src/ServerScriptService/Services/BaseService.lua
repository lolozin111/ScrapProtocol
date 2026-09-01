--[[
	BaseService.lua
	Physically builds each player's base once PlotService assigns them a plot: clones a Model from
	ReplicatedStorage.BaseTemplates onto the plot's anchor CFrame, picking WHICH tier's Model from
	profile.ResearchTier — the single merged progression ladder, see ResearchConfig.lua. Also owns
	the UpgradeResearch remote that raises it.

	The cloned Model carries its OWN stations: a BaseTier{n} Model is expected to contain its tier's
	Crafting/Welding/Forge stations as tagged descendants, and tagStationOwnership below stamps
	ownership onto them automatically. So upgrading swaps shell and stations together and a Tier 3
	base can never end up wearing Tier 1 stations.

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
local ResearchConfig = require(ReplicatedStorage.Shared.ResearchConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StationService = require(script.Parent.StationService)
local TurretService = require(script.Parent.TurretService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Matches Tier 1's real platform (48 studs across, thin floor) on purpose. This is not just
-- cosmetic: CombatEncounterService.getWallAttackRange measures the ACTUAL built model's bounding
-- box, so a placeholder that lies about the base's size makes enemies stop at a boundary that
-- doesn't match anything visible — the exact bug documented further down this file, back when this
-- was 40x2x40 while the footprint claimed 80 studs across.
local FALLBACK_FLOOR_SIZE = Vector3.new(48, 0.6, 48)
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


-- Floating "whose base is this, and how far along are they" sign. Deliberately a separate Model
-- parented alongside the base rather than inside it, so RebuildPlayerBase can tear the base down
-- and re-clone it on every tier upgrade without having to preserve or recreate the sign's state.
local playerBaseSign: { [Player]: Model } = {}

local SIGN_HEIGHT_ABOVE_BASE = 14

local function refreshBaseSign(player: Player, plot: Instance, tier, tierIndex: number)
	local existing = playerBaseSign[player]
	if existing then
		existing:Destroy()
	end

	local anchorPart = Instance.new("Part")
	anchorPart.Name = "SignAnchor"
	anchorPart.Size = Vector3.new(1, 1, 1)
	anchorPart.Transparency = 1
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false -- purely a label mount; must never eat a click meant for the base
	anchorPart.CFrame = plot.CFrame * CFrame.new(0, SIGN_HEIGHT_ABOVE_BASE, 0)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BaseSign"
	billboard.Size = UDim2.new(0, 220, 0, 56)
	billboard.AlwaysOnTop = false -- reads as a thing in the world, not a HUD element
	billboard.MaxDistance = 250
	billboard.Parent = anchorPart

	local owner = Instance.new("TextLabel")
	owner.BackgroundTransparency = 1
	owner.Size = UDim2.new(1, 0, 0.55, 0)
	owner.Font = Enum.Font.SourceSansBold
	owner.TextColor3 = Color3.fromRGB(237, 231, 220)
	owner.TextStrokeTransparency = 0.4
	owner.TextScaled = true
	owner.Text = ("%s's Base"):format(player.DisplayName)
	owner.Parent = billboard

	local tierLabel = Instance.new("TextLabel")
	tierLabel.BackgroundTransparency = 1
	tierLabel.Position = UDim2.new(0, 0, 0.55, 0)
	tierLabel.Size = UDim2.new(1, 0, 0.45, 0)
	tierLabel.Font = Enum.Font.SourceSans
	tierLabel.TextColor3 = Color3.fromRGB(224, 122, 59)
	tierLabel.TextStrokeTransparency = 0.5
	tierLabel.TextScaled = true
	tierLabel.Text = ("Research Tier %d — %s"):format(tierIndex, tier.Name)
	tierLabel.Parent = billboard

	local model = Instance.new("Model")
	model.Name = ("%s_BaseSign"):format(player.Name)
	model.PrimaryPart = anchorPart
	anchorPart.Parent = model
	model.Parent = Workspace
	playerBaseSign[player] = model
end

-- Destroys whatever base Model is currently built for this player (if any) and clones/positions
-- the one matching their current profile.ResearchTier in its place.
function BaseService.RebuildPlayerBase(player: Player, plot: Instance)
	-- Put SOMETHING solid under the plot immediately, before the profile wait below.
	--
	-- PlotService teleports the character to plot.CFrame + SpawnHeightOffset and THEN fires
	-- PlotAssigned, which lands here inside a task.spawn that can yield for up to 5 seconds in
	-- waitForProfile. The Plot anchor itself is forced non-collidable (it's a marker, not a floor),
	-- so for that whole window the player was standing on nothing and simply fell.
	--
	-- The fallback floor needs no profile data — only the plot's CFrame — so it can be built right
	-- now and swapped for the real tier Model once the profile arrives. On a fast load this is
	-- invisible; on a slow one it's the difference between spawning on a floor and falling into
	-- the void. Only for a FIRST build: a rebuild (tier upgrade, turret change) already has a base
	-- standing, and tearing it down for a placeholder mid-session would look like a glitch.
	local hadBase = playerBaseModel[player] ~= nil
	if not hadBase then
		local placeholder = buildFallbackBase(player, plot)
		placeholder.Name = ("%s_Base_Bootstrap"):format(player.Name)
		placeholder.Parent = Workspace
		playerBaseModel[player] = placeholder
	end

	local profile = waitForProfile(player)
	if not profile then
		warn(("[BaseService] Profile never loaded for %s — base not built."):format(player.Name))
		return -- the bootstrap floor above stays; better to stand on a placeholder than on nothing
	end

	local tier, tierIndex = ResearchConfig.GetTier(profile.ResearchTier or 1)
	local templateFolder = ReplicatedStorage:FindFirstChild(ResearchConfig.TemplateFolderName)
	local template = templateFolder and templateFolder:FindFirstChild(tier.ModelName)

	local baseModel
	if template and template:IsA("Model") then
		baseModel = template:Clone()
		baseModel.Name = ("%s_Base"):format(player.Name)
		baseModel:PivotTo(plot.CFrame)
	else
		warn(("[BaseService] No %q Model found in ReplicatedStorage.%s — using a plain placeholder floor. Build the real base Model in Studio to replace this."):format(
			tier.ModelName, ResearchConfig.TemplateFolderName))
		baseModel = buildFallbackBase(player, plot)
	end

	tagStationOwnership(baseModel, player)

	local existing = playerBaseModel[player]
	if existing then
		existing:Destroy()
	end

	baseModel.Parent = Workspace
	playerBaseModel[player] = baseModel

	refreshBaseSign(player, plot, tier, tierIndex)
end

-- Exposes the actual currently-built base Model (real BaseTier art, or the fallback floor if none
-- exists yet) so other systems can measure its REAL size instead of guessing. Added for
-- CombatEncounterService.lua's wall-defense boundary — see that file's getWallAttackRange — after
-- a hardcoded BaseConfig.WallAttackRange guess (tuned against the since-removed PlotConfig.FootprintHalfSize, the
-- max CLAIMED plot area) turned out much bigger than FALLBACK_FLOOR_SIZE (the actual placeholder
-- floor most testing uses today), so enemies were "stopping at the wall" well past the visible
-- platform's real edge — nowhere close to a wall, right in the middle. Returns nil if the base
-- hasn't finished building yet (RebuildPlayerBase yields on the profile load).
function BaseService.GetPlayerBaseModel(player: Player): Model?
	return playerBaseModel[player]
end

-- UpgradeResearch: claims the next tier on the merged progression ladder (ResearchConfig).
-- Replaces the old UpgradeBase remote — see ResearchConfig's header for why BaseTier and
-- ResearchTier became one number.
--
-- Three gates, checked in this order and all READ-ONLY before anything is spent, so a rejected
-- claim never leaves the player out resources:
--   1. wave milestone  — RequiredWave vs profile.HighestWave. This is what ties progression to
--                        wave defense; the boss wave that unlocks a tier is also the only source
--                        of the CoreItem it costs.
--   2. CoreItem        — from a boss wave, not purchasable.
--   3. Cost            — Scrap + ore.
--
-- Still gated at the Workbench (Crafting station), same as Tool/Suit upgrades: it's a "how my base
-- is laid out" decision, and it visibly rebuilds the base around you.
Remotes.UpgradeResearch.OnServerInvoke = function(player: Player)
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

	-- ONE source of truth for what the next tier needs — the same function the HUD calls to render
	-- the requirements list, so what's shown and what's enforced can never disagree.
	local requirements = ResearchConfig.GetNextTierRequirements(profile)
	if not requirements then
		return { Success = false, Reason = "Already at the highest Research Tier" }
	end
	if not requirements.WaveMet then
		return { Success = false, Reason = ("Reach Wave %d in base defense first (best so far: %d)"):format(
			requirements.RequiredWave, requirements.HighestWave) }
	end
	if requirements.CoreRequirement and not requirements.CoreRequirement.Met then
		return { Success = false, Reason = ("Needs %d x %s from a base-defense boss wave"):format(
			requirements.CoreRequirement.Needed, requirements.CoreRequirement.Key) }
	end

	local nextTier = ResearchConfig.Tiers[requirements.TierIndex]
	if nextTier.Cost and not DataService.TrySpend(player, nextTier.Cost) then
		return { Success = false, Reason = "Not enough resources" }
	end
	if nextTier.CoreRequirement then
		DataService.TrySpendCoreItem(player, nextTier.CoreRequirement.Key, nextTier.CoreRequirement.Amount)
	end

	profile.ResearchTier = requirements.TierIndex

	local plot = PlotService.GetPlayerPlot(player)
	if plot then
		-- Rebuilds the base Model (bigger shell, its own tier's stations) and, separately, the
		-- turret ring — the new tier both widens the footprint the ring is derived from AND unlocks
		-- more slots, so the pads have to be laid out again.
		BaseService.RebuildPlayerBase(player, plot)
		TurretService.RebuildPlayerTurrets(player)
	end

	Remotes.InventoryUpdate:FireClient(player, { ResearchTier = profile.ResearchTier })
	DataService.PushWallet(player)

	return { Success = true, ResearchTier = profile.ResearchTier }
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

	local sign = playerBaseSign[player]
	if sign then
		sign:Destroy()
	end
	playerBaseSign[player] = nil
end)

return BaseService
