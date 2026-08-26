--[[
	ResearchConfig.lua
	THE progression ladder. One tier number drives everything about how developed a player's base
	is, and it's the one number the HUD shows.

	MERGED from what used to be two parallel ladders that meant the same thing:
	  - profile.BaseTier      bought with Scrap + ore + a CoreItem; picked the base Model and WallHP
	  - profile.ResearchTier  hardcoded to 1, never raisable; gated turret slots and turret tiers
	Both were gated on boss-wave drops, both meant "my base got better," and a player would have had
	to track two numbers. profile.ResearchTier is now the survivor; profile.BaseTier is legacy and
	migrated forward on load (see DataService.migrateBaseTierToResearch).

	One tier now decides:
	  - which BaseTemplates Model gets cloned (ModelName) — INCLUDING its stations, see below
	  - how big the plot's claimed footprint is (FootprintHalfSize)
	  - the base's WallHP in defense (WallHP)
	  - how many turret slots exist (TurretConfig.GetSlotCount)
	  - how far a turret can be levelled (TurretConfig.GetTurretTier's gate)

	HOW IT'S EARNED: reaching RequiredWave unlocks the option; claiming it then costs Cost plus one
	CoreRequirement item. The milestone gates it, the resources pay for it — so wave defense sets the
	pace while mining and raiding fund it, which is the loop this game is built around.

	STUDIO SETUP — stations live INSIDE the base Model, not in a separate folder:
	  ReplicatedStorage/BaseTemplates/
	    BaseTier1/   <- the whole base: shell, floor, AND its Crafting/Welding/Forge stations
	    BaseTier2/   <- a bigger shell with bigger stations
	    ...
	Each station inside is just a Part/Model tagged "Station" with a child StringValue "StationType"
	(Crafting / Welding / Forge), exactly as a loose one would be. BaseService.tagStationOwnership
	already walks every descendant of a cloned base and stamps OwnerUserId on anything tagged, so
	per-tier stations need no new code at all — and upgrading swaps shell and stations together, so
	a Tier 3 base can never end up wearing Tier 1 stations.

	Build each Model with its floor at local Y=0 (PrimaryPart on the floor piece), same convention
	as before — BaseService positions it with model:PivotTo(plot.CFrame).

	!! PLOT SPACING !!  FootprintHalfSize grows with tier, and the top tier below claims a 200x200
	stud area. Hand-placed Plot anchors need to be at least that far apart or two maxed bases will
	physically overlap. Space plots for the LAST tier, not the first.
]]

local Wallet = require(script.Parent.Wallet)

local ResearchConfig = {}

ResearchConfig.TemplateFolderName = "BaseTemplates"

-- RequiredWave is checked against profile.HighestWave. Tier 1 is where everyone starts, so it has
-- no requirement, no cost, and no CoreRequirement.
--
-- The wave gates land on multiples of WaveConfig.EliteWaveInterval (5) on purpose: those are the
-- boss waves, and boss waves are the only source of the CoreItem each tier also needs. So the wave
-- that unlocks a tier is the same wave that can drop the Core to pay for it.
--
-- Tier 3 and up also cost REFINED materials (RefinedOreConfig), which means running the ore through
-- the Forge's Smelting tab first. That is deliberate: it puts a finished-but-unused system on the
-- critical path instead of leaving smelting as a sink with no output, and it makes the late tiers
-- cost time as well as quantity — a Voidium Core is 1:1 with a shard, but you still have to smelt
-- it. Costs quoted in refined keys work because DataService.TrySpend routes them through Wallet.
--
-- FootprintHalfSize is the region PlotService.IsPlayerInOwnPlot treats as "your base", and
-- BaseConfig.TurretRingRadiusFraction derives the turret ring from it — so widening the footprint
-- automatically spreads the growing slot count out instead of cramming more pads into a fixed ring.
-- Y is generous relative to X/Z so standing on an upper floor still counts as being at your base.
ResearchConfig.Tiers = {
	{
		Name = "Scrap Workbench",
		ModelName = "BaseTier1",
		RequiredWave = 0,
		WallHP = 150,
		FootprintHalfSize = Vector3.new(40, 30, 40),
	},
	{
		Name = "Reinforced Workshop",
		ModelName = "BaseTier2",
		RequiredWave = 5,
		WallHP = 300,
		FootprintHalfSize = Vector3.new(50, 34, 50),
		Cost = { Scrap = 400, ScrapIron = 100, CopperWire = 50 },
		CoreRequirement = { Key = "CoreT1", Amount = 1 },
	},
	{
		Name = "Fortified Bunker",
		ModelName = "BaseTier3",
		RequiredWave = 10,
		WallHP = 550,
		FootprintHalfSize = Vector3.new(62, 38, 62),
		Cost = { Scrap = 1200, SteelPlating = 150, CopperWire = 80, SteelIngot = 20 },
		CoreRequirement = { Key = "CoreT2", Amount = 1 },
	},
	{
		Name = "Bastion",
		ModelName = "BaseTier4",
		RequiredWave = 15,
		WallHP = 900,
		FootprintHalfSize = Vector3.new(75, 42, 75),
		Cost = { Scrap = 3000, GoldContacts = 60, HardenedPlate = 30 },
		CoreRequirement = { Key = "CoreT3", Amount = 1 },
	},
	{
		Name = "Citadel",
		ModelName = "BaseTier5",
		RequiredWave = 20,
		WallHP = 1400,
		FootprintHalfSize = Vector3.new(88, 46, 88),
		Cost = { Scrap = 6500, GoldContacts = 150, GoldBar = 25 },
		CoreRequirement = { Key = "CoreT4", Amount = 1 },
	},
	{
		Name = "Foundry",
		ModelName = "BaseTier6",
		RequiredWave = 25,
		WallHP = 2100,
		FootprintHalfSize = Vector3.new(100, 50, 100),
		Cost = { Scrap = 12000, VoidiumShard = 40, VoidiumCore = 15 },
		CoreRequirement = { Key = "CoreT5", Amount = 1 },
	},
	-- Add more tiers here and the ladder extends with no code changes — but build the matching
	-- BaseTemplates Model, and re-check plot spacing against the new FootprintHalfSize.
}

ResearchConfig.MaxTier = #ResearchConfig.Tiers

-- Clamped rather than nil-returning: every caller wants "the tier this player is at", and a saved
-- value outside the table (an old save, a config that shrank) should degrade to a sane tier rather
-- than erroring deep inside whatever was reading it.
function ResearchConfig.GetTier(tierIndex: number?)
	local index = math.clamp(math.floor(tierIndex or 1), 1, ResearchConfig.MaxTier)
	return ResearchConfig.Tiers[index], index
end

function ResearchConfig.GetWallMaxHP(tierIndex: number?): number
	local tier = ResearchConfig.GetTier(tierIndex)
	return tier.WallHP
end

function ResearchConfig.GetFootprintHalfSize(tierIndex: number?): Vector3
	local tier = ResearchConfig.GetTier(tierIndex)
	return tier.FootprintHalfSize
end

-- Everything the client needs to render "what do I need for the next tier", and everything the
-- server needs to decide whether to allow it — deliberately ONE function so the requirements shown
-- and the requirements enforced can never disagree.
--
-- Returns nil when already at max tier. Otherwise: the next tier's data, plus a per-requirement
-- breakdown of what's met. `profile` may be the client's mirrored copy or the real server one;
-- this only reads fields both have.
function ResearchConfig.GetNextTierRequirements(profile)
	local currentIndex = math.clamp(math.floor(profile.ResearchTier or 1), 1, ResearchConfig.MaxTier)
	local nextIndex = currentIndex + 1
	local nextTier = ResearchConfig.Tiers[nextIndex]
	if not nextTier then
		return nil
	end

	local highestWave = profile.HighestWave or 0
	local waveMet = highestWave >= (nextTier.RequiredWave or 0)

	local costEntries = {}
	local costMet = true
	for key, amount in pairs(nextTier.Cost or {}) do
		-- Wallet routes the key to whichever profile bucket it lives in (currency / ore / refined /
		-- core), so a tier cost can be quoted in any of them without this needing to know which.
		local have = Wallet.GetAmount(profile, key)
		local met = have >= amount
		costMet = costMet and met
		table.insert(costEntries, { Key = key, Needed = amount, Have = have, Met = met })
	end
	-- Stable order so the requirements list doesn't reshuffle between renders (pairs() over a cost
	-- table is unordered, and a list that jumps around every refresh reads as broken).
	table.sort(costEntries, function(a, b)
		return a.Key < b.Key
	end)

	local coreEntry = nil
	local coreMet = true
	if nextTier.CoreRequirement then
		local have = (profile.CoreItems or {})[nextTier.CoreRequirement.Key] or 0
		coreMet = have >= nextTier.CoreRequirement.Amount
		coreEntry = {
			Key = nextTier.CoreRequirement.Key,
			Needed = nextTier.CoreRequirement.Amount,
			Have = have,
			Met = coreMet,
		}
	end

	return {
		TierIndex = nextIndex,
		Name = nextTier.Name,
		RequiredWave = nextTier.RequiredWave or 0,
		HighestWave = highestWave,
		WaveMet = waveMet,
		Cost = costEntries,
		CoreRequirement = coreEntry,
		CanAfford = costMet and coreMet,
		CanClaim = waveMet and costMet and coreMet,
	}
end

return ResearchConfig
