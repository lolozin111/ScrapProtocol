--[[
	AutoMinerService.lua
	Handles the Auto-Miner: a one-time-craftable structure (see AutoMinerConfig.lua) that
	passively drips out a small amount of ore on a timer for every player who owns one, whether
	or not they're actively playing right now. MVP-scoped as pure data — no physical structure
	to place in the world yet, same spirit as WaveService's headless combat sim: the mechanic is
	real and testable before the art/placement layer exists.

	The AutoMiner game pass (ShopConfig.GamePasses.AutoMiner) doubles the tick yield for anyone
	who owns it — see AutoMinerConfig for the exact numbers and the reasoning on why both the
	free and paid rates are kept deliberately modest (this should supplement active mining, not
	replace the reason to do it).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutoMinerConfig = require(ReplicatedStorage.Shared.AutoMinerConfig)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StationService = require(script.Parent.StationService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CraftAutoMiner = Remotes.CraftAutoMiner

local AutoMinerService = {}

CraftAutoMiner.OnServerInvoke = function(player: Player)
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

	if profile.CraftedStructures.AutoMiner then
		return { Success = false, Reason = "Already built" }
	end

	local spent = DataService.TrySpend(player, AutoMinerConfig.Cost)
	if not spent then
		return { Success = false, Reason = "Not enough resources" }
	end

	profile.CraftedStructures.AutoMiner = true

	Remotes.InventoryUpdate:FireClient(player, {
		OreCounts = profile.OreCounts,
		CraftedStructures = profile.CraftedStructures,
	})

	return { Success = true }
end

-- One shared loop for every connected player, rather than a per-player timer — mirrors
-- DataService's autosave loop. Only runs while a player is actually connected and their profile
-- is cached; this MVP doesn't grant "catch-up" ore for time spent offline (a reasonable later
-- addition if you want real idle-game behavior).
task.spawn(function()
	while true do
		task.wait(AutoMinerConfig.TickSeconds)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = DataService.Get(player)
			if profile and profile.CraftedStructures.AutoMiner then
				local yield = AutoMinerConfig.BaseYieldPerTick
				if profile.OwnedGamePasses.AutoMiner then
					yield *= AutoMinerConfig.GamePassMultiplier
				end
				DataService.AddOre(player, AutoMinerConfig.OreKey, yield)
				Remotes.InventoryUpdate:FireClient(player, { OreCounts = profile.OreCounts })
			end
		end
	end
end)

return AutoMinerService
