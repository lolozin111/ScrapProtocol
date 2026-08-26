--[[
	HackerService.lua
	The Hacker Machine: opens sealed cases, slowly.

	Deliberately modelled on SmeltService, which already solved this exact shape — one job at a time
	per player, timestamp-based so it finishes whether or not you were online, cleared by a shared
	background loop rather than a timer per player. Copying a working pattern beats inventing a
	second one that behaves subtly differently.

	=== WHY THE TIMER MATTERS ===
	The wait IS the mechanic. It is the "check back later" hook the design wanted, and it is what
	the two rush paths are priced against. Remove the wait and Contraband, the Cores rush and the
	Robux rush all lose their point simultaneously.

	=== RUSHING (two paths, deliberately different risk) ===
	  Robux  instant, no risk. The paid path buys certainty.
	  Cores  instant, but CaseConfig.Rush.CorruptChance to destroy the case outright.
	The asymmetry is the design: a player who pays gets a guarantee, a player who grinds gets a
	gamble. Without it the Cores rush would simply be the better option and the Robux one would be
	pointless.

	CONTENTS ARE ROLLED AT COMPLETION, not at purchase — see BlackMarketService.RollCase. So a case
	bought before a content update opens with the new pools, and there is nothing stored to
	desynchronise if the pools change under it.

	Studio setup: tag a Part or Model "Station" with a child StringValue "StationType" set to
	"Hacker".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CaseConfig = require(ReplicatedStorage.Shared.CaseConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local DataService = require(script.Parent.DataService)
local StationService = require(script.Parent.StationService)
local BlackMarketService = require(script.Parent.BlackMarketService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local HackerService = {}

local TICK_SECONDS = 2

-- Rolls the case, grants it, clears the job, and tells the client what came out. One place, so the
-- natural completion below and both rush paths cannot pay out differently.
local function completeDecode(player: Player, profile)
	local job = profile.DecodeJob
	if not job then
		return
	end

	local reward = BlackMarketService.RollCase(job.CaseKey)
	profile.DecodeJob = nil

	if not reward then
		-- Config problem rather than a player one — hand the case back rather than eating it.
		profile.Cases[job.CaseKey] = (profile.Cases[job.CaseKey] or 0) + 1
		Remotes.InventoryUpdate:FireClient(player, {
			DecodeJob = false,
			Cases = profile.Cases,
		})
		return
	end

	BlackMarketService.GrantReward(player, reward)

	Remotes.InventoryUpdate:FireClient(player, {
		-- `or false`, same nil-drop reasoning as every other optional field this codebase
		-- broadcasts: a bare nil vanishes from the table literal before it reaches the wire, so the
		-- client would never learn the job ended.
		DecodeJob = false,
	})
	Remotes.CaseOpened:FireClient(player, job.CaseKey, reward)
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------

Remotes.StartDecode.OnServerInvoke = function(player: Player, caseKey: string)
	if not StationService.IsPlayerNearStation(player, "Hacker") then
		return { Success = false, Reason = StationConfig.Types.Hacker.NotThereMessage }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	if profile.DecodeJob then
		return { Success = false, Reason = "The machine is already working on something." }
	end

	local case = CaseConfig.Cases[caseKey]
	if not case then
		return { Success = false, Reason = "Unknown case" }
	end
	if (profile.Cases[caseKey] or 0) <= 0 then
		return { Success = false, Reason = "You don't have one of those." }
	end

	-- Consumed up front, same "pay before you get" shape as every other spend in this codebase. It
	-- is handed back if the decode cannot be completed for a config reason (see completeDecode).
	profile.Cases[caseKey] -= 1

	local job = {
		CaseKey = caseKey,
		FinishTime = os.time() + case.DecodeSeconds,
	}
	profile.DecodeJob = job

	Remotes.InventoryUpdate:FireClient(player, {
		Cases = profile.Cases,
		DecodeJob = job,
	})

	return { Success = true, DecodeJob = job }
end

----------------------------------------------------------------------
-- Rush
----------------------------------------------------------------------

-- The Cores path. The Robux path is a developer product and goes through ShopService's
-- ProcessReceipt instead, which then calls HackerService.RushWithoutRisk below.
Remotes.RushDecode.OnServerInvoke = function(player: Player)
	if not StationService.IsPlayerNearStation(player, "Hacker") then
		return { Success = false, Reason = StationConfig.Types.Hacker.NotThereMessage }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end
	if not profile.DecodeJob then
		return { Success = false, Reason = "Nothing is decoding." }
	end

	if not DataService.TrySpend(player, { Cores = CaseConfig.Rush.CoresCost }) then
		return { Success = false, Reason = ("Rushing costs %d Cores."):format(CaseConfig.Rush.CoresCost) }
	end

	-- The gamble. Rolled AFTER the Cores are spent, so a corrupted case still costs — that is what
	-- makes it a risk rather than a free re-roll.
	if math.random() < CaseConfig.Rush.CorruptChance then
		local lost = profile.DecodeJob.CaseKey
		profile.DecodeJob = nil
		Remotes.InventoryUpdate:FireClient(player, { DecodeJob = false })
		DataService.PushWallet(player)
		return {
			Success = true,
			Corrupted = true,
			CaseKey = lost,
			Reason = "The case corrupted under the load. Nothing recoverable.",
		}
	end

	completeDecode(player, profile)
	DataService.PushWallet(player)
	return { Success = true, Corrupted = false }
end

-- The Robux path: instant and safe. Called by ShopService once a real purchase is confirmed, never
-- reachable from the client directly — which is why it is a module function rather than a remote.
function HackerService.RushWithoutRisk(player: Player): boolean
	local profile = DataService.Get(player)
	if not profile or not profile.DecodeJob then
		return false
	end
	completeDecode(player, profile)
	return true
end

----------------------------------------------------------------------
-- Completion loop
----------------------------------------------------------------------

-- One shared loop for every connected player, same pattern as SmeltService and AutoMinerService.
-- Timestamp-based, so a decode started before logging off finishes the moment the player is next
-- seen past its FinishTime.
task.spawn(function()
	while true do
		task.wait(TICK_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = DataService.Get(player)
			local job = profile and profile.DecodeJob
			if job and os.time() >= job.FinishTime then
				completeDecode(player, profile)
			end
		end
	end
end)

return HackerService
