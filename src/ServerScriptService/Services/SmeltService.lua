--[[
	SmeltService.lua
	Owns the Forge's Ore Smelting mechanic — the second thing the Forge does besides rolling
	weapons (see ForgeService.lua). One job at a time per player: pick a raw ore you own, pick a
	quantity (a positive multiple of that ore's RefineRatio — see RefinedOreConfig.lua), and the
	Forge produces refined material after a duration computed by RefinedOreConfig
	.ComputeSmeltSeconds (an actual logarithm — bigger batches cost less time per raw ore, not just
	proportionally more total time).

	Timestamp-based completion (FinishTime = os.time() + duration), not tick-accumulation — mirrors
	AutoMinerService.lua's one-shared-loop-for-all-players pattern, but a job finishes exactly when
	its FinishTime passes regardless of whether the player was online for the whole wait, same
	reasoning DataService's autosave loop doesn't care whether you were AFK for it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local RefinedOreConfig = require(ReplicatedStorage.Shared.RefinedOreConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StationService = require(script.Parent.StationService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local SmeltService = {}

-- StartSmelt: begins a new smelting job. Rejects if a job is already running (one at a time —
-- see profile.SmeltJob), if the ore key isn't a real ore, if quantity isn't a positive multiple
-- of that ore's RefineRatio, or if the player doesn't own enough of it. Deducts the raw ore
-- immediately (same "pay up front" pattern as every other spend in this codebase); the refined
-- material itself is only granted once the background loop below sees FinishTime pass.
Remotes.StartSmelt.OnServerInvoke = function(player: Player, oreKey: string, quantity: number)
	if not PlotService.IsPlayerInOwnPlot(player) then
		return { Success = false, Reason = PlotConfig.NotInBaseMessage }
	end
	if not StationService.IsPlayerNearStation(player, "Forge") then
		return { Success = false, Reason = StationConfig.Types.Forge.NotThereMessage }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	if profile.SmeltJob then
		return { Success = false, Reason = "A smelting job is already in progress" }
	end

	local oreData = RefinedOreConfig.Ores[oreKey]
	if not oreData then
		return { Success = false, Reason = "Unknown ore" }
	end

	quantity = math.floor(quantity or 0)
	if quantity <= 0 or quantity % oreData.RefineRatio ~= 0 then
		return { Success = false, Reason = ("Quantity must be a positive multiple of %d"):format(oreData.RefineRatio) }
	end

	local owned = profile.OreCounts[oreKey] or 0
	if owned < quantity then
		return { Success = false, Reason = "Not enough ore" }
	end

	profile.OreCounts[oreKey] = owned - quantity

	-- Hook point for a future "Smelt Speed" gamepass/upgrade: multiply `duration` here (e.g.
	-- `* 0.5` for a gamepass owner) — RefinedOreConfig.ComputeSmeltSeconds itself should stay the
	-- single shared source of the base formula, same reasoning as AutoMinerService applying
	-- AutoMinerConfig.GamePassMultiplier AFTER computing the base yield, not baking it into the
	-- config's base numbers.
	local duration = RefinedOreConfig.ComputeSmeltSeconds(quantity)
	local job = {
		OreKey = oreKey,
		Quantity = quantity,
		RefinedKey = oreData.RefinedKey,
		RefinedAmount = quantity / oreData.RefineRatio,
		FinishTime = os.time() + duration,
	}
	profile.SmeltJob = job

	Remotes.InventoryUpdate:FireClient(player, {
		OreCounts = profile.OreCounts,
		SmeltJob = job,
	})

	return { Success = true, SmeltJob = job }
end

-- One shared loop for every connected player, same pattern as AutoMinerService.lua — just
-- timestamp-based instead of tick-accumulation-based, so a job started right before a player logs
-- off still finishes (and gets granted) the moment they're next seen past its FinishTime.
task.spawn(function()
	while true do
		task.wait(RefinedOreConfig.SmeltTime.TickSeconds)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = DataService.Get(player)
			local job = profile and profile.SmeltJob
			if job and os.time() >= job.FinishTime then
				DataService.AddRefinedOre(player, job.RefinedKey, job.RefinedAmount)
				profile.SmeltJob = nil
				Remotes.InventoryUpdate:FireClient(player, {
					RefinedOreCounts = profile.RefinedOreCounts,
					-- `or false`, same reasoning as every other nil-able field this codebase
					-- broadcasts — see ForgeService.EquipWeapon's comment. A bare `SmeltJob = nil`
					-- in this table literal would just vanish before the patch ever reached the wire.
					SmeltJob = false,
				})
			end
		end
	end
end)

return SmeltService
