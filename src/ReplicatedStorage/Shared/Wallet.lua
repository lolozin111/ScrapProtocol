--[[
	Wallet.lua
	One answer to "where does this cost key live on a profile, how much do I have, and what is it
	called" — for every kind of thing a price can be quoted in.

	A player's spendable stuff is spread across four buckets on the profile:
	  profile.Scrap / profile.Cores       flat currencies
	  profile.OreCounts[key]              raw ore (OreConfig.Ores)
	  profile.RefinedOreCounts[key]       smelted materials (RefinedOreConfig, keyed by RefinedKey)
	  profile.CoreItems[key]              boss-wave drops (CoreT1, CoreT2, ...)

	That routing used to be written out by hand in four places — twice inside DataService.TrySpend,
	again in ResearchConfig's requirements check, and again in the HUD's cost formatter — and NONE
	of them knew about RefinedOreCounts. Which is exactly why smelting produced a material that
	could not be spent on anything: there was no way to write a price in it that any of those four
	would have understood.

	Shared (not server-only) on purpose: the client needs the same answers to render a cost line and
	grey out what you can't afford, and having it compute those differently from the server is how
	"the UI says I can afford it but the server disagrees" bugs happen.

	This module only READS and formats. Deducting stays in DataService, which owns the profile.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OreConfig = require(ReplicatedStorage.Shared.OreConfig)
local RefinedOreConfig = require(ReplicatedStorage.Shared.RefinedOreConfig)

local Wallet = {}

-- Which profile bucket a cost key belongs to. Order matters: the flat currencies are checked by
-- name first, then refined keys (RefinedOreConfig.ByRefinedKey is the reverse index built at load),
-- then CoreItems by prefix, and anything left is assumed to be raw ore — which keeps the common
-- case (an ore key) free of any lookup at all.
--
-- Returns one of "Currency" | "Refined" | "Core" | "Ore".
function Wallet.BucketFor(key: string): string
	if key == "Scrap" or key == "Cores" then
		return "Currency"
	end
	if RefinedOreConfig.ByRefinedKey[key] then
		return "Refined"
	end
	-- CoreItems are minted per boss milestone (CoreT1, CoreT2, ...) rather than enumerated in a
	-- config, so there's no table to check against — the name shape is the only signal available.
	-- Guarded against matching the "Cores" currency, which is already handled above.
	if key:match("^CoreT%d+$") then
		return "Core"
	end
	return "Ore"
end

-- How much of `key` this profile currently holds. Works on the server's real profile and on the
-- client's mirrored copy — it only touches fields both have.
function Wallet.GetAmount(profile, key: string): number
	local bucket = Wallet.BucketFor(key)
	if bucket == "Currency" then
		return profile[key] or 0
	elseif bucket == "Refined" then
		return (profile.RefinedOreCounts or {})[key] or 0
	elseif bucket == "Core" then
		return (profile.CoreItems or {})[key] or 0
	end
	return (profile.OreCounts or {})[key] or 0
end

-- Player-facing name for a cost key — "Steel Ingot", not "SteelIngot". Falls back to the raw key
-- for anything unrecognised (a CoreItem, or a key added to a cost table before its config entry
-- exists) so a price is never rendered blank.
function Wallet.DisplayName(key: string): string
	local bucket = Wallet.BucketFor(key)
	if bucket == "Currency" or bucket == "Core" then
		return key
	elseif bucket == "Refined" then
		local data = RefinedOreConfig.ByRefinedKey[key]
		return (data and data.DisplayName) or key
	end
	local ore = OreConfig.Ores[key]
	return (ore and ore.DisplayName) or key
end

-- Formats a whole cost table as "120 Scrap, 40 Scrap Iron, 5 Steel Ingot".
--
-- Sorted rather than left in pairs() order: an unordered cost line reshuffles between renders,
-- which reads as a flicker/bug in a list that refreshes as often as the craft menus do.
function Wallet.CostString(costTable): string
	local keys = {}
	for key in pairs(costTable or {}) do
		table.insert(keys, key)
	end
	table.sort(keys)

	local parts = {}
	for _, key in ipairs(keys) do
		table.insert(parts, ("%d %s"):format(costTable[key], Wallet.DisplayName(key)))
	end
	return table.concat(parts, ", ")
end

-- True if the profile can cover the whole cost table. Read-only — DataService.TrySpend does its
-- own check before deducting, since only it can guarantee nothing changed in between.
function Wallet.CanAfford(profile, costTable): boolean
	for key, amount in pairs(costTable or {}) do
		if Wallet.GetAmount(profile, key) < amount then
			return false
		end
	end
	return true
end

return Wallet
