--[[
	SellService.lua
	Owns the Shop station's sell side: raw ore and refined material, for Scrap. Buying at the Shop
	(NodeConfig.ShopCatalog) already existed; this is the other half of that economy — tier
	upgrades are Scrap-priced (OreConfig.ToolTierCosts) and there was previously no way to turn a
	stockpile of ore you'll never smelt into the Scrap those upgrades cost.

	Prices live in config, never here: OreConfig.Ores[key].SellPrice for raw ore,
	RefinedOreConfig.Ores[oreKey].SellPrice for that ore's refined material (looked up via
	RefinedOreConfig.ByRefinedKey, the same reverse index the Inventory panel's Materials tab uses).
	The client sends an item key and an amount — intent only. Every other number here (which bucket
	the key lives in, whether it's actually sellable, how much the player holds, the payout) is
	re-derived server-side, because a client-supplied price or total would just be a free-Scrap
	exploit waiting to be found.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OreConfig = require(ReplicatedStorage.Shared.OreConfig)
local RefinedOreConfig = require(ReplicatedStorage.Shared.RefinedOreConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local DataService = require(script.Parent.DataService)
local StationService = require(script.Parent.StationService)
local RateLimiter = require(script.Parent.RateLimiter)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local SellService = {}

-- Resolves an item key to what it takes to sell it: which count bucket it lives in on the
-- profile, and its Scrap-per-unit price. Returns nil (unresolved) for anything that isn't a real
-- OreConfig/RefinedOreConfig entry, or that is but has no SellPrice configured — both cases are a
-- flat rejection at the call site, never a fallback price.
local function resolveSellable(itemKey: string)
	local oreData = OreConfig.Ores[itemKey]
	if oreData then
		if not oreData.SellPrice then
			return nil
		end
		return { CountsField = "OreCounts", SellPrice = oreData.SellPrice }
	end

	local refinedLookup = RefinedOreConfig.ByRefinedKey[itemKey]
	if refinedLookup then
		local refinedData = RefinedOreConfig.Ores[refinedLookup.OreKey]
		if not refinedData or not refinedData.SellPrice then
			return nil
		end
		return { CountsField = "RefinedOreCounts", SellPrice = refinedData.SellPrice }
	end

	return nil
end

-- SellOre: sells `amount` units of `itemKey` (a raw OreConfig key or a refined RefinedOreConfig
-- key) for Scrap. Station-gated to the Shop, same as the buying side — see StationConfig for the
-- NotThereMessage this hands back.
Remotes.SellOre.OnServerInvoke = function(player: Player, itemKey: any, amount: any)
	if not RateLimiter.Check(player, "SellOre", 1) then
		return { Success = false, Reason = "You're selling too fast — wait a moment." }
	end

	if not StationService.IsPlayerNearStation(player, "Shop") then
		return { Success = false, Reason = StationConfig.Types.Shop.NotThereMessage }
	end

	if typeof(itemKey) ~= "string" then
		warn(("[SellService] %s sent a non-string item key (%s) to SellOre"):format(player.Name, typeof(itemKey)))
		return { Success = false, Reason = "Invalid item" }
	end

	local sellable = resolveSellable(itemKey)
	if not sellable then
		return { Success = false, Reason = "That isn't sellable here" }
	end

	-- Reject malformed amounts outright rather than coercing them (math.floor, math.clamp, etc.) —
	-- a clamped/coerced value silently reinterprets a bad request as a different, "valid" one,
	-- which is exactly the kind of silent handling this codebase avoids. NaN fails every ordering
	-- comparison, which is why the `amount < 1` check alone won't catch it; the explicit
	-- self-inequality check does.
	if typeof(amount) ~= "number"
		or amount ~= amount -- NaN
		or amount == math.huge or amount == -math.huge
		or amount < 1
		or amount ~= math.floor(amount)
	then
		warn(("[SellService] %s sent an invalid amount (%s) to SellOre"):format(player.Name, tostring(amount)))
		return { Success = false, Reason = "Invalid amount" }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	local countsTable = profile[sellable.CountsField]
	local owned = countsTable[itemKey] or 0
	if owned < amount then
		return { Success = false, Reason = "You don't have that many" }
	end

	local payout = sellable.SellPrice * amount

	countsTable[itemKey] = owned - amount
	DataService.AddCurrency(player, "Scrap", payout)

	-- PushWallet after every currency change, unconditionally — see DataService.PushWallet's own
	-- comment for why a handler that spends/grants currency but only broadcasts its own domain
	-- field leaves the client's wallet mirror stale (the change looks like it never happened).
	DataService.PushWallet(player)

	-- `[sellable.CountsField] = countsTable` rather than listing OreCounts/RefinedOreCounts by
	-- name: whichever bucket this sale touched is the one that changed, and PushWallet above
	-- already re-sent both in full, so this patch only needs to be a normal partial update — no
	-- `or false` clearing needed here, since a counts TABLE is never nil'd out, only a bucket key
	-- an amount within it that goes to 0 (which stays a real key with a real value, not a hole).
	Remotes.InventoryUpdate:FireClient(player, {
		[sellable.CountsField] = countsTable,
	})

	return { Success = true, Payout = payout, ItemKey = itemKey, Amount = amount, Remaining = countsTable[itemKey] }
end

return SellService
