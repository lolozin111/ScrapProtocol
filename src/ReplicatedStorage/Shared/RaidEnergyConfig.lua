--[[
	RaidEnergyConfig.lua
	Tuning for the raid Energy system: starting an exploration (pulling the Expedition lever) costs
	Energy, which regenerates slowly over real time, plus a rare "Energy Drink" find while mining
	that grants a burst of bonus Energy. The point is to put a real ceiling on how many exploration
	runs you can chain back to back, without making the player wait around doing nothing — see
	RaidEnergyService.lua for how these get used.

	NOTE: Energy gates starting a whole exploration run, not each individual Combat node inside
	one — a run with three Combat rows only costs 1 Energy total, not 3. See ExpeditionService's
	RegenerateExpedition handler for where this actually gets spent.
]]

local RaidEnergyConfig = {}

RaidEnergyConfig.MaxEnergy = 5                 -- normal cap; passive regen never goes above this
RaidEnergyConfig.OverflowCap = 8               -- an Energy Drink CAN push you above MaxEnergy, but never past this
RaidEnergyConfig.EnergyPerExpedition = 1       -- cost to start an exploration run — charged once, when the lever is
                                                -- pulled and the queue (re)generates, win or lose on whatever's inside
RaidEnergyConfig.RegenIntervalSeconds = 240    -- how often you passively regain 1 Energy (~20 min empty -> full at MaxEnergy)

RaidEnergyConfig.EnergyDrinkBonus = 2          -- Energy granted when you find one
RaidEnergyConfig.EnergyDrinkFindChance = 0.03  -- per successful mining hit, chance to also find one — deliberately rare,
                                                -- per the design ask ("gotta find it, not be so common")

return RaidEnergyConfig
