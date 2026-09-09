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

local AdminConfig = require(ReplicatedStorage.Shared.AdminConfig)
local RaidEnergyConfig = require(ReplicatedStorage.Shared.RaidEnergyConfig)
local DataService = require(script.Parent.DataService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RaidEnergyService = {}

-- Infinite Energy for admins, EXCEPT while they're in a Player Test Session — the whole point of
-- test mode is to see the game the way a new player does, and a resource ceiling you can't hit is
-- exactly the kind of thing that would hide a pacing problem. So the shortcut is deliberately the
-- one thing test mode turns back off.
--
-- Lives here rather than at each call site so every spend path honours it identically. It used to
-- be an `AdminConfig.IsAdmin(player) and` guard inline in ExpeditionService's lever handler, which
-- (a) didn't apply to raid rooms and (b) stayed on inside a test session.
function RaidEnergyService.HasInfiniteEnergy(player: Player): boolean
	return AdminConfig.IsAdmin(player) and not DataService.IsTestSession(player)
end

-- Snaps an infinite-Energy player back to full and tells their HUD. Without this the number in
-- the currency strip would just sit at whatever it was when the shortcut kicked in — technically
-- harmless, since nothing is ever deducted, but it reads as broken.
local function refill(player: Player, profile): boolean
	if profile.Energy >= RaidEnergyConfig.MaxEnergy then
		return false
	end
	profile.Energy = RaidEnergyConfig.MaxEnergy
	Remotes.InventoryUpdate:FireClient(player, { Energy = profile.Energy })
	return true
end

function RaidEnergyService.TrySpendEnergy(player: Player, amount: number?): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	if RaidEnergyService.HasInfiniteEnergy(player) then
		refill(player, profile)
		return true
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
--
-- Ticks far more often than RegenIntervalSeconds so an infinite-Energy admin's display catches up
-- promptly (joining, or flipping /admin back on mid-session, would otherwise leave them reading a
-- stale low number for minutes). Ordinary regen still only lands every RegenIntervalSeconds — the
-- accumulator below is what keeps the two rates independent.
local REGEN_POLL_SECONDS = 2

task.spawn(function()
	local sinceRegen = 0
	while true do
		local dt = task.wait(REGEN_POLL_SECONDS)
		sinceRegen += dt
		local regenTick = sinceRegen >= RaidEnergyConfig.RegenIntervalSeconds
		if regenTick then
			sinceRegen = 0
		end

		for _, player in ipairs(Players:GetPlayers()) do
			local profile = DataService.Get(player)
			if profile then
				if RaidEnergyService.HasInfiniteEnergy(player) then
					refill(player, profile)
				elseif regenTick and profile.Energy < RaidEnergyConfig.MaxEnergy then
					profile.Energy += 1
					Remotes.InventoryUpdate:FireClient(player, { Energy = profile.Energy })
				end
			end
		end
	end
end)

return RaidEnergyService
