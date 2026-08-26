--[[
	ExpeditionConfig.lua
	Tuning for the Expedition queue: 5-8 node "rows" sitting at fixed slots near the
	ExpeditionStart anchor. Every Nth row is a two-way fork instead of a single node. Rows only
	ever move in response to the player — clearing the frontmost row shifts every other row down
	one slot and spawns a fresh one at the back. Nothing moves on a timer.
]]

local ExpeditionConfig = {}

ExpeditionConfig.PathLengthMin = 5     -- how many node rows stay active in the conveyor at once (min)
ExpeditionConfig.PathLengthMax = 8     -- how many node rows stay active in the conveyor at once (max) — picked once when the conveyor (re)starts

ExpeditionConfig.SlotSpacing = 8       -- studs between consecutive rows in the queue
ExpeditionConfig.ForkInterval = 3      -- every Nth spawned row is a two-way choice instead of a single node
ExpeditionConfig.ForkLateralOffset = 7 -- how far apart the two fork options sit, side to side (must clear the node size below so they don't crowd each other)

ExpeditionConfig.ShiftDuration = 0.5   -- seconds the "everyone moves down one slot" animation takes when the front row is cleared — this is the ONLY time anything moves; there's no time-based drift

-- "Return to Base" (the EndExpedition remote) full-heals the requesting player and wipes the
-- shared queue, so it's gated on actually being at the expedition rather than callable from
-- anywhere. EndRangePadding is slack added past the far end of the lane (SlotSpacing *
-- targetRowCount) before a player counts as "not on the run" — generous on purpose, since the
-- point is only to stop it being used as a heal button from across the map, not to police exactly
-- where you're standing on your own lane.
-- How close you must stand to actually pull the ExpeditionLever. The lever is a ProximityPrompt
-- client-side, but that is presentation — this is what the server enforces.
ExpeditionConfig.LeverInteractDistance = 20

ExpeditionConfig.EndRangePadding = 60
ExpeditionConfig.EndCooldownSeconds = 3 -- paces the wipe; it resets the queue for EVERY player on it

ExpeditionConfig.MaxCombatNodes = 4    -- Combat nodes stop being rolled once this many are simultaneously active in the queue
ExpeditionConfig.MinCombatNodes = 1    -- the queue is never allowed to have FEWER than this many Combat nodes active at once — the moment a
                                        -- freshly-spawned row's count would still be under this, that row is forced to include a Combat node
                                        -- instead of rolling normally (still respects MaxCombatNodes above). Raise this (e.g. to 2) for combat
                                        -- to show up noticeably more often; it must stay <= MaxCombatNodes or the forcing can never satisfy it.

-- Weighted random node type (weights don't need to sum to 100, they're relative).
ExpeditionConfig.NodeTypeWeights = {
	Combat = 60,
	Shop = 25,
	Heal = 15,
}

-- Combat tier is a WEIGHTED ROLL (not a hard cutoff) that shifts toward harder tiers the more
-- rows have spawned so far this run — a rough stand-in for "the player is presumably stronger/
-- further along by now" since this is one shared queue, not something scoped to a single
-- player's gear. Early on it's mostly Tier 1 with Tier 2 showing up here and there; by the late
-- band Tier 3 dominates. Tune the weights per band, or add more bands for a smoother ramp.
ExpeditionConfig.TierWeightBands = {
	{ MaxIndex = 5, Weights = { [1] = 70, [2] = 25, [3] = 5 } },
	{ MaxIndex = 12, Weights = { [1] = 40, [2] = 40, [3] = 20 } },
	{ MaxIndex = math.huge, Weights = { [1] = 15, [2] = 40, [3] = 45 } },
}

function ExpeditionConfig.GetTierForSlot(slotIndex: number): number
	local weights = ExpeditionConfig.TierWeightBands[#ExpeditionConfig.TierWeightBands].Weights
	for _, band in ipairs(ExpeditionConfig.TierWeightBands) do
		if slotIndex <= band.MaxIndex then
			weights = band.Weights
			break
		end
	end

	local total = 0
	for _, weight in pairs(weights) do
		total += weight
	end
	local roll = math.random() * total
	local cumulative = 0
	for tier, weight in pairs(weights) do
		cumulative += weight
		if roll <= cumulative then
			return tier
		end
	end
	return 1 -- fallback, should be unreachable
end

function ExpeditionConfig.RollNodeType(): string
	local total = 0
	for _, weight in pairs(ExpeditionConfig.NodeTypeWeights) do
		total += weight
	end
	local roll = math.random() * total
	local cumulative = 0
	for nodeType, weight in pairs(ExpeditionConfig.NodeTypeWeights) do
		cumulative += weight
		if roll <= cumulative then
			return nodeType
		end
	end
	return "Combat" -- fallback, should be unreachable
end

return ExpeditionConfig
