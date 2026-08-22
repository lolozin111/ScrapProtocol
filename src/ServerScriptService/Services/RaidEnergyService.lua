--[[
	RaidEnergyService.lua
	Owns the raid Energy stat: a shared regen loop (mirrors AutoMinerService's pattern — one
	loop for every connected player rather than a per-player timer) plus two functions other
	services call into directly, since this isn't something the client ever requests on its own:

	  RaidEnergyService.TrySpendEnergy(player) — called by ExpeditionService right before an
	  exploration run (re)generates, i.e. when the lever is pulled. Returns false (and spends
	  nothing) if the player doesn't have enough.

	  RaidEnergyService.GrantEnergyDrink(player) — called by MiningService on the rare roll that
	  finds one while mining. Can push Energy above MaxEnergy, capped at OverflowCap.

	NOTE: like AutoMinerService, this is real-time-only — Energy does NOT catch up for time
	spent offline, it only regenerates while the player is actually connected. Real offline
	catch-up would need a stored last-regen timestamp compared at login; deliberately deferred
	for the same reason AutoMinerService defers it (see that file's comment) — keep it simple
	until there's a reason not to.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RaidEnergyConfig = require(ReplicatedStorage.Shared.RaidEnergyConfig)
local DataService = require(script.Parent.DataService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RaidEnergyService = {}

function RaidEnergyService.TrySpendEnergy(player: Player, amount: number?): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	local cost = amount or RaidEnergyConfig.EnergyPerExpedition
	if profile.Energy < cost then
		return false
	end

	profile.Energy -= cost
	Remotes.InventoryUpdate:FireClient(player, { Energy = profile.Energy })
	return true
end

function RaidEnergyService.GrantEnergyDrink(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	profile.Energy = math.min(profile.Energy + RaidEnergyConfig.EnergyDrinkBonus, RaidEnergyConfig.OverflowCap)
	Remotes.InventoryUpdate:FireClient(player, { Energy = profile.Energy })
	Remotes.EnergyDrinkFound:FireClient(player)
end

-- Shared regen loop. Only tops players up to MaxEnergy — anything above that (from a drink) just
-- sits there until spent, it doesn't get topped up further by this.
task.spawn(function()
	while true do
		task.wait(RaidEnergyConfig.RegenIntervalSeconds)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = DataService.Get(player)
			if profile and profile.Energy < RaidEnergyConfig.MaxEnergy then
				profile.Energy += 1
				Remotes.InventoryUpdate:FireClient(player, { Energy = profile.Energy })
			end
		end
	end
end)

return RaidEnergyService
