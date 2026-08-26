--[[
	ToolModConfig.lua
	Special pickaxes — the Epic tier of the Black Market's case pools.

	=== HOW THESE DIFFER FROM ToolTier ===
	`OreConfig.ToolTiers` is a LADDER: a sequential upgrade track you buy your way up, one step at a
	time, and a higher tier is strictly better than a lower one. These are SIDEWAYS: you hold one at
	a time, they are not ordered, and picking one is a choice about how you want to mine rather than
	how far you have progressed.

	Keeping them separate matters because they multiply. A tool mod that raised ToolTier would also
	unlock ore it was never meant to gate (see OreConfig.Ores[key].MinToolTier) — so these never touch
	tier at all. They scale the numbers a tier produces, and nothing else.

	=== ONE AT A TIME ===
	`profile.EquippedTool`, same shape as EquippedUltimate: owning several is fine, one is active.
	Anything else makes the third one below ("more ore") strictly mandatory, since yield stacks
	multiplicatively with everything and there would be no reason not to wear it permanently.

	=== ADDING ONE ===
	An entry here plus a `{ Kind = "Tool", Key = "..." }` line in CaseConfig's Epic pool. The three
	effect fields are read in exactly two places (MiningService for ore nodes, MineShaftService for
	mine blocks), so anything expressible with them costs nothing; anything else needs code in both.
]]

local ToolModConfig = {}

-- Display order wherever these are listed. A plain list so there is one place to reorder.
ToolModConfig.Order = { "SplitHead", "Featherweight", "Prospector" }

--[[
	FIELDS (all optional; a mod may set any combination)
	  SwingTimeMultiplier  scales the tier's SwingTime. Below 1 is faster.
	  YieldMultiplier      scales the tier's YieldMultiplier.
	  BlastRadius          mine-shaft only: also breaks blocks within this many cells of the target.
]]
ToolModConfig.Tools = {
	SplitHead = {
		DisplayName = "Split-Head Pick",
		Description = "A forked head that shears three blocks loose at once. Useless on ore nodes.",
		-- The user's "mines 3 blocks at once". A radius of 1 in the voxel grid reaches the six
		-- face-adjacent cells, so this breaks the target plus whichever neighbours actually exist —
		-- typically two or three when you are inside a tunnel, one on an open face. That variability
		-- is the honest version of "3 blocks": a fixed count would have to invent blocks that are not
		-- there.
		BlastRadius = 1,
		-- Slower per swing, because breaking several blocks per swing is already a large throughput
		-- win and this would otherwise be strictly better than Featherweight at its own job.
		SwingTimeMultiplier = 1.25,
	},

	Featherweight = {
		DisplayName = "Featherweight Pick",
		Description = "Barely there. You swing it far faster than anything this size has any right to.",
		-- "Increases mining speed by a lot" — 45% off the swing timer, which at Plasma Drill's 0.3s
		-- is 0.165s, roughly six swings a second. Fast enough to feel obviously different without
		-- outrunning the click rate a player can actually produce.
		SwingTimeMultiplier = 0.55,
	},

	Prospector = {
		DisplayName = "Prospector's Pick",
		Description = "Finds more in the same rock. Nothing flashy — it just pays better.",
		-- "Increases the amount of ores you get (nothing too crazy for now)" — deliberately modest.
		-- Yield multiplies with the tier's own multiplier, so at Plasma Drill's 3.25x this is already
		-- 4.2x a starting player's take.
		YieldMultiplier = 1.3,
	},
}

-- The equipped mod's data, or nil. Tolerant of a profile that predates the field.
function ToolModConfig.Equipped(profile)
	local key = profile and profile.EquippedTool
	return key and ToolModConfig.Tools[key] or nil
end

-- Effective swing time for a profile, given its tier's base. One function so MiningService and
-- MineShaftService cannot drift apart on it — which is exactly what happened to the two ore gates
-- before OreGate existed.
function ToolModConfig.SwingTime(profile, baseSwingTime: number): number
	local mod = ToolModConfig.Equipped(profile)
	return baseSwingTime * ((mod and mod.SwingTimeMultiplier) or 1)
end

function ToolModConfig.YieldMultiplier(profile, baseMultiplier: number): number
	local mod = ToolModConfig.Equipped(profile)
	return baseMultiplier * ((mod and mod.YieldMultiplier) or 1)
end

function ToolModConfig.BlastRadius(profile): number
	local mod = ToolModConfig.Equipped(profile)
	return (mod and mod.BlastRadius) or 0
end

return ToolModConfig
