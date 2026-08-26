--[[
	BlackMarketService.lua
	The dealer: sells sealed cases from rotating stock, and owns what a case actually pays out.

	Split from HackerService on purpose — this file is "how you get a case and what is inside one",
	that one is "how you open it". Buying and decoding are separated by real time (minutes), so
	keeping them apart means neither has to know about the other's state.

	See CaseConfig.lua for the cases, pools and odds, and DESIGN_NOTES.md for the design.

	Studio setup: tag a Part or Model "Station" with a child StringValue "StationType" set to
	"BlackMarket". Deliberately NOT gated to a player's own plot — the dealer is a shared world
	location, same as the Hub Shop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CaseConfig = require(ReplicatedStorage.Shared.CaseConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local UltimateConfig = require(ReplicatedStorage.Shared.UltimateConfig)
local WeaponFamilyConfig = require(ReplicatedStorage.Shared.WeaponFamilyConfig)
local DataService = require(script.Parent.DataService)
local StationService = require(script.Parent.StationService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local BlackMarketService = {}

----------------------------------------------------------------------
-- Rolling
----------------------------------------------------------------------

-- Weighted pick over a rarity's Odds. Returns nil only if a case has no odds at all, which is a
-- config error rather than a runtime case.
local function rollRarity(case): string?
	local total = 0
	for _, weight in pairs(case.Odds) do
		total += weight
	end
	if total <= 0 then
		return nil
	end

	local roll = math.random() * total
	local cumulative = 0
	-- Walked in RarityOrder, not pairs(), so the same roll always lands on the same rarity — a
	-- pairs() walk over the odds table would make the mapping depend on hash order.
	for _, rarity in ipairs(CaseConfig.RarityOrder) do
		local weight = case.Odds[rarity]
		if weight then
			cumulative += weight
			if roll <= cumulative then
				return rarity
			end
		end
	end
	return nil
end

local function rollFromPool(pool)
	if not pool or #pool == 0 then
		return nil
	end
	local total = 0
	for _, entry in ipairs(pool) do
		total += (entry.Weight or 1)
	end
	local roll = math.random() * total
	local cumulative = 0
	for _, entry in ipairs(pool) do
		cumulative += (entry.Weight or 1)
		if roll <= cumulative then
			return entry
		end
	end
	return pool[#pool]
end

-- Decides what one case contains. Pure: rolls and returns, grants nothing. Called by HackerService
-- when a decode finishes, so the contents are decided at OPEN time rather than at purchase — which
-- matters because it means a case bought before a content update opens with the new pools.
function BlackMarketService.RollCase(caseKey: string)
	local case = CaseConfig.Cases[caseKey]
	if not case then
		return nil
	end

	local rarity = rollRarity(case)
	if not rarity then
		warn(("[BlackMarketService] %s has no usable Odds — check CaseConfig."):format(caseKey))
		return nil
	end

	local entry = rollFromPool(CaseConfig.Pools[rarity])
	if not entry then
		warn(("[BlackMarketService] %s rolled %s but that pool is empty — falling back to Common."):format(caseKey, rarity))
		rarity = "Common"
		entry = rollFromPool(CaseConfig.Pools.Common)
		if not entry then
			return nil
		end
	end

	local amount = 1
	if entry.Min and entry.Max then
		amount = math.random(entry.Min, entry.Max)
	end

	return { Rarity = rarity, Kind = entry.Kind, Key = entry.Key, Amount = amount }
end

-- Applies a rolled reward. The one place a case's contents become real, so adding a new Kind (Tool,
-- Weapon) is a branch here plus a pool entry — nothing else changes.
function BlackMarketService.GrantReward(player: Player, reward): boolean
	local profile = DataService.Get(player)
	if not profile or not reward then
		return false
	end

	if reward.Kind == "Currency" then
		DataService.AddCurrency(player, reward.Key, reward.Amount)
	elseif reward.Kind == "Ore" then
		DataService.AddOre(player, reward.Key, reward.Amount)
	elseif reward.Kind == "Refined" then
		DataService.AddRefinedOre(player, reward.Key, reward.Amount)
	elseif reward.Kind == "Core" then
		DataService.AddCoreItem(player, reward.Key, reward.Amount)
	elseif reward.Kind == "Ultimate" then
		-- Ultimates are a permanent unlock, not a count. Rolling a duplicate is not nothing: it is
		-- converted to Contraband below rather than silently vanishing, because "you got a thing you
		-- already own" is the most disappointing possible outcome of a premium case.
		if profile.OwnedUltimates[reward.Key] then
			local consolation = 6
			DataService.AddCurrency(player, "Contraband", consolation)
			reward.Duplicate = true
			reward.ConsolationContraband = consolation
		else
			profile.OwnedUltimates[reward.Key] = true
		end
		Remotes.InventoryUpdate:FireClient(player, { OwnedUltimates = profile.OwnedUltimates })
	elseif reward.Kind == "WeaponFamily" then
		-- Same permanent-unlock shape as an Ultimate, and the same duplicate handling for the same
		-- reason: a Legendary roll that lands a family you already own is the second most
		-- disappointing outcome a case has, so it pays Contraband instead of nothing. Set higher than
		-- the Ultimate consolation because a family unlock is the larger prize to have missed, and
		-- because there are only six of them — duplicates start happening early.
		profile.UnlockedWeaponFamilies = profile.UnlockedWeaponFamilies or {}
		if profile.UnlockedWeaponFamilies[reward.Key] then
			local consolation = 10
			DataService.AddCurrency(player, "Contraband", consolation)
			reward.Duplicate = true
			reward.ConsolationContraband = consolation
		else
			profile.UnlockedWeaponFamilies[reward.Key] = true
		end
		reward.DisplayName = WeaponFamilyConfig.BlueprintName(reward.Key)
		Remotes.InventoryUpdate:FireClient(player, {
			UnlockedWeaponFamilies = profile.UnlockedWeaponFamilies,
		})
	else
		-- Tool is declared in CaseConfig's pools but has no system behind it yet. No shipped case
		-- rolls one, so this is unreachable today — it exists so that adding one to a pool before
		-- wiring the grant fails loudly rather than silently paying out nothing.
		warn(("[BlackMarketService] Reward Kind %q is not grantable yet — see CaseConfig's TODOs."):format(tostring(reward.Kind)))
		return false
	end

	DataService.PushWallet(player)
	return true
end

----------------------------------------------------------------------
-- Buying
----------------------------------------------------------------------

-- Cases are stored as counts (profile.Cases[caseKey] = n) rather than instances: an unopened case
-- has no identity beyond its type, and its contents are not rolled until it is decoded.
Remotes.BuyCase.OnServerInvoke = function(player: Player, caseKey: string)
	if not StationService.IsPlayerNearStation(player, "BlackMarket") then
		return { Success = false, Reason = StationConfig.Types.BlackMarket.NotThereMessage }
	end

	local case = CaseConfig.Cases[caseKey]
	if not case then
		return { Success = false, Reason = "Unknown case" }
	end

	if case.RobuxProductKey then
		return { Success = false, Reason = "That one is a Robux purchase — use the buy prompt." }
	end

	-- Re-derived server-side rather than trusting what the client claims it saw, same as the Hub
	-- Shop's blueprint stock.
	local stock = CaseConfig.GetRotatingStock(os.time())
	local inStock = false
	for _, key in ipairs(stock) do
		if key == caseKey then
			inStock = true
			break
		end
	end
	if not inStock then
		return { Success = false, Reason = "Not in today's stock" }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	if not DataService.TrySpend(player, case.Cost) then
		return { Success = false, Reason = "Not enough to buy that" }
	end

	profile.Cases[caseKey] = (profile.Cases[caseKey] or 0) + 1

	Remotes.InventoryUpdate:FireClient(player, { Cases = profile.Cases })
	DataService.PushWallet(player)

	return { Success = true, CaseKey = caseKey }
end

----------------------------------------------------------------------
-- Contraband income
----------------------------------------------------------------------

-- Called by the systems that pay it out. Kept here rather than in each of them so the earn rates
-- sit next to the thing they are balanced against — the cost of a Blackline case.
--
-- PLACEHOLDER RATES. A Blackline case is 12 Contraband; a clean raid extract pays 3-6 and a boss
-- wave pays 2, so roughly two or three successful runs buys one premium case. Worth a playtest
-- before treating as final, and worth a daily cap if it turns out to be farmable.
BlackMarketService.Income = {
	RaidExtractMin = 3,
	RaidExtractMax = 6,
	BossWave = 2,
}

function BlackMarketService.AwardContraband(player: Player, amount: number, reason: string?)
	if amount <= 0 then
		return
	end
	DataService.AddCurrency(player, "Contraband", amount)
	DataService.PushWallet(player)
	Remotes.ContrabandAwarded:FireClient(player, amount, reason or "")
end

return BlackMarketService
