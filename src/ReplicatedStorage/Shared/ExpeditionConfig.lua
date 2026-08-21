--[[
	ExpeditionConfig.lua
	Tuning for the procedurally-generated Expedition path: how many node slots, how far apart,
	how likely each slot is to actually hold a node, and where the forks (path choices) land.
]]

local ExpeditionConfig = {}

ExpeditionConfig.PathLengthMin = 5
ExpeditionConfig.PathLengthMax = 8

ExpeditionConfig.SlotSpacing = 12      -- studs between consecutive slots along the path — kept short so the whole path stays close to base
ExpeditionConfig.ForkInterval = 3      -- every Nth slot is a two-way choice instead of a single slot
ExpeditionConfig.ForkLateralOffset = 5 -- how far apart the two fork options sit, side to side

-- Regular (non-fork) slots roll this chance to actually contain a node at all — the rest are
-- just open path, so a run's node count varies and no two expeditions look identical. Fork
-- slots are exempt: a choice with only one real option isn't a choice, so both branches always
-- get a node.
ExpeditionConfig.NodeSpawnChance = 0.3

-- Hard floor/ceiling applied AFTER the random rolls above, so short/unlucky rolls never leave
-- you with a near-empty path and lucky rolls never flood it with fights.
ExpeditionConfig.MinTotalNodes = 5     -- if RNG rolls fewer nodes than this, extra ones are forced into open slots
ExpeditionConfig.MaxCombatNodes = 4    -- Combat nodes stop being rolled once a path already has this many

-- Weighted random node type (weights don't need to sum to 100, they're relative).
ExpeditionConfig.NodeTypeWeights = {
	Combat = 60,
	Shop = 25,
	Heal = 15,
}

-- Combat tier scales with how deep into the path a node sits — the far end of an expedition
-- should feel meaningfully riskier than the first couple of slots.
ExpeditionConfig.TierBySlotIndex = {
	{ MaxIndex = 2, Tier = 1 },
	{ MaxIndex = 5, Tier = 2 },
	{ MaxIndex = math.huge, Tier = 3 },
}

function ExpeditionConfig.GetTierForSlot(slotIndex: number): number
	for _, band in ipairs(ExpeditionConfig.TierBySlotIndex) do
		if slotIndex <= band.MaxIndex then
			return band.Tier
		end
	end
	return 1
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
