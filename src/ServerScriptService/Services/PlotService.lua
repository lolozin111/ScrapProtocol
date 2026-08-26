--[[
	PlotService.lua
	Assigns each player a personal base plot on join, picked randomly from whatever Parts are
	tagged PlotConfig.Tag ("Plot") in Workspace — place one anywhere per plot in Studio, no code
	changes needed to add more. Frees the plot back to the pool when the player leaves.

	A Plot Part is just an invisible ANCHOR — the moment this service sees the tag (at boot, or
	later via CollectionService's added signal) it forces the Part transparent/non-collidable/
	non-queryable, regardless of how it was built in Studio. It exists purely to give a CFrame for
	BaseService.lua to clone an actual Base Model onto (see that file — and BaseConfig.lua — for
	what the player actually sees and stands on) and for IsPlayerInOwnPlot below to check against.

	Also owns IsPlayerInOwnPlot, which every Workbench/Start Defense remote handler (CraftingService,
	MiningService, AutoMinerService, MineShaftService, WaveService) calls to reject those actions
	when the player isn't standing at their own base. See PlotConfig.FootprintHalfSize for the
	region that check uses.

	Respawning: rather than fighting Roblox's own SpawnLocation/team logic (multiple enabled
	SpawnLocations pick randomly among themselves, which would let a player materialize on ANY
	plot, not just their assigned one), this manually repositions the character on every
	CharacterAdded, so tagged Plot parts can be plain, ordinary anchored Parts — no SpawnLocation
	class required. This also means every other respawn path already in this codebase (Recall,
	End Expedition, the mine's full-reset eviction — all of which call player:LoadCharacter())
	now lands the player back at their own base automatically, for free.

	PlotAssigned (an Event, see below) is how BaseService finds out a plot exists to build on —
	kept as a signal rather than BaseService polling/guessing connection order, since Roblox does
	not guarantee two separate Players.PlayerAdded listeners fire in the order they were connected
	relative to each other's yields.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local ResearchConfig = require(ReplicatedStorage.Shared.ResearchConfig)
local DataService = require(script.Parent.DataService)

local PlotService = {}

local plotAssignedSignal = Instance.new("BindableEvent")
PlotService.PlotAssigned = plotAssignedSignal.Event -- (player: Player, plot: BasePart)

local plotOwner: { [Instance]: Player } = {} -- plot Part -> assigned Player
local playerPlot: { [Player]: Instance } = {} -- Player -> assigned plot Part
-- One CharacterAdded connection per player, kept so releasePlot can disconnect it. Without this
-- the connection outlived the player it was made for on every leave.
local characterConn: { [Player]: RBXScriptConnection } = {}

-- Forces every Plot-tagged Part into "invisible anchor" shape, no matter how it was built in
-- Studio — this way placing one is as simple as tagging literally any Part.
local function sanitizePlot(plot: Instance)
	if not plot:IsA("BasePart") then
		return
	end
	plot.Transparency = 1
	plot.CanCollide = false
	plot.CanQuery = false
	plot.CanTouch = false
end

local function getUnclaimedPlots(): { Instance }
	local candidates = {}
	for _, inst in ipairs(CollectionService:GetTagged(PlotConfig.Tag)) do
		if inst:IsA("BasePart") and not plotOwner[inst] then
			table.insert(candidates, inst)
		end
	end
	return candidates
end

local function teleportToPlot(character: Model, plot: Instance)
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end
	character:PivotTo(plot.CFrame + Vector3.new(0, PlotConfig.SpawnHeightOffset, 0))
end

local function onCharacterAdded(player: Player, character: Model)
	local plot = playerPlot[player]
	if not plot then
		return -- player never got a plot (none available) — nothing to teleport to
	end
	character:WaitForChild("HumanoidRootPart", 5)
	teleportToPlot(character, plot)
end

local function assignPlot(player: Player)
	local candidates = getUnclaimedPlots()
	if #candidates == 0 then
		warn(("[PlotService] %s — %s"):format(player.Name, PlotConfig.NoPlotMessage))
		return
	end

	local plot = candidates[math.random(1, #candidates)]
	plotOwner[plot] = player
	playerPlot[player] = plot
	plot:SetAttribute("OwnerUserId", player.UserId)
	plot:SetAttribute("OwnerName", player.Name)

	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	characterConn[player] = player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	plotAssignedSignal:Fire(player, plot)
end

local function releasePlot(player: Player)
	local plot = playerPlot[player]
	if not plot then
		return
	end
	plotOwner[plot] = nil
	playerPlot[player] = nil

	local conn = characterConn[player]
	if conn then
		conn:Disconnect()
	end
	characterConn[player] = nil
	plot:SetAttribute("OwnerUserId", nil)
	plot:SetAttribute("OwnerName", nil)
end

function PlotService.GetPlayerPlot(player: Player): Instance?
	return playerPlot[player]
end

-- Box-contains check against the plot anchor's own CFrame (so a rotated anchor still works) and
-- PlotConfig.FootprintHalfSize — deliberately NOT the anchor Part's own Size, since the anchor is
-- just a small marker and the real base footprint is configured separately. Generous enough that
-- standing anywhere on/above your own base counts, without also counting a player who's merely
-- walking past a neighboring one.
function PlotService.IsPlayerInOwnPlot(player: Player): boolean
	local plot = playerPlot[player]
	if not plot then
		return false
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false
	end

	local localPosition = plot.CFrame:PointToObjectSpace(rootPart.Position)
	-- Per-tier, not fixed: the base Model physically grows with ResearchTier (see
	-- ResearchConfig.Tiers), so a Tier 4 player standing at the far edge of their own much larger
	-- base has to still count as being in it. Falls back to Tier 1's footprint if the profile
	-- isn't loaded yet, which is the smallest and therefore the safest guess.
	local profile = DataService.Get(player)
	local half = ResearchConfig.GetFootprintHalfSize(profile and profile.ResearchTier or 1)

	if math.abs(localPosition.X) > half.X then
		return false
	end
	if math.abs(localPosition.Z) > half.Z then
		return false
	end
	if localPosition.Y < -half.Y or localPosition.Y > half.Y then
		return false
	end

	return true
end

for _, plot in ipairs(CollectionService:GetTagged(PlotConfig.Tag)) do
	sanitizePlot(plot)
end
CollectionService:GetInstanceAddedSignal(PlotConfig.Tag):Connect(sanitizePlot)

Players.PlayerAdded:Connect(assignPlot)
Players.PlayerRemoving:Connect(releasePlot)

-- Defensive only — Main.server.lua requires every service exactly once at boot, well before any
-- player can join, so this loop should never actually find anyone. Costs nothing to have it.
for _, player in ipairs(Players:GetPlayers()) do
	if not playerPlot[player] then
		assignPlot(player)
	end
end

return PlotService
