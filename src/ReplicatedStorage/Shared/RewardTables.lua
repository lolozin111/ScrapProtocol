--[[
	RewardTables.lua
	Base-defense wave rewards. REWORKED (Base Defense & Turrets phase round 2, direct instruction):
	"this wave defense system will not reward the player with scraps or stuff like that, it will
	only reward the core stuff, and maybe some utility items here and there." WaveConfig
	.GetScrapReward/GetCoresReward are no longer called by anything — base defense grants NO
	Scrap/Cores at all now, only CoreItems (profile.CoreItems, see DataService.lua) and, on a
	chance, a small utility item.

	Every 5th wave (WaveConfig.EliteWaveInterval, unchanged cadence) is now a full BOSS wave rather
	than "one elite unit joins the regular crowd" in spirit — the underlying spawn mechanism didn't
	need to change (see WaveService.lua's own comment on why), just what clearing it pays out.
	Clearing a boss wave GUARANTEES one CoreItem (CoreKeyForMilestone below) plus a good chance at a
	utility item; clearing a REGULAR wave grants nothing guaranteed, just a small chance at a
	utility item — "some utility items here and there."

	Get(stageKey)/Roll(stageKey) keep the exact same pure-lookup/pure-roll shape they always had —
	only the TABLES themselves changed, plus the entries now use Type = "Utility" (routed by
	WaveService via DataService.AddCurrency, same generic profile-field-incrementer ShopService
	already uses for InstantCraftTokens/WaveReviveTokens) instead of "Currency"/"Ore". CoreItems are
	NOT rolled through this table at all — they're a guaranteed grant, not a chance-based drop, see
	CoreKeyForMilestone below.
]]

local RewardTables = {}

-- entry shape: { Type = "Utility", Key = <profile field, e.g. "WaveReviveTokens">, Amount, Chance
-- (0..1, default 1.0) }. Chance is evaluated independently per entry, so a table can grant more
-- than one thing per roll (or nothing at all, if every entry's Chance misses).
RewardTables.Tables = {
	BossUtility = {
		{ Type = "Utility", Key = "WaveReviveTokens", Amount = 1, Chance = 0.35 },
		{ Type = "Utility", Key = "InstantCraftTokens", Amount = 1, Chance = 0.35 },
	},
	RegularUtility = {
		{ Type = "Utility", Key = "WaveReviveTokens", Amount = 1, Chance = 0.08 },
		{ Type = "Utility", Key = "InstantCraftTokens", Amount = 1, Chance = 0.08 },
	},
}

-- Pure lookup — the table itself, or nil if `stageKey` isn't configured. No rolling, no mutation.
function RewardTables.Get(stageKey: string)
	return RewardTables.Tables[stageKey]
end

-- Resolves a stage's table into what actually got granted this roll: a list of
-- { Type, Key, Amount }. Returns nil (with a warn()) if the stage has no table — callers should
-- treat nil as "nothing extra this time," not a reason to fail the whole reward payout.
function RewardTables.Roll(stageKey: string)
	local table_ = RewardTables.Get(stageKey)
	if not table_ then
		warn("[RewardTables] No reward table configured for stage:", stageKey)
		return nil
	end

	local granted = {}
	for _, entry in ipairs(table_) do
		if math.random() <= (entry.Chance or 1.0) then
			local amount = entry.Min and math.random(entry.Min, entry.Max) or entry.Amount
			table.insert(granted, { Type = entry.Type, Key = entry.Key, Amount = amount })
		end
	end
	return granted
end

-- Which CoreItem key a boss-wave milestone guarantees (milestoneIndex = which 5th-wave this is —
-- 1 for wave 5, 2 for wave 10, 3 for wave 15, ... see WaveConfig.BossMilestoneIndex). Feeds
-- BaseConfig.BaseTierCoreRequirement's own tier mapping directly: wave-5's CoreT1 is what
-- BaseTier 2 requires, wave-10's CoreT2 is what BaseTier 3 requires, and so on. Placeholder names
-- until real flavor names get picked, per direct instruction.
RewardTables.BossCoreForMilestone = {
	[1] = "CoreT1",
	[2] = "CoreT2",
	[3] = "CoreT3",
}

-- Clamped to the highest configured milestone — a very long run (wave 20+) keeps dropping that
-- same top-tier core rather than erroring or dropping nothing once there's no higher BaseTier left
-- to gate.
function RewardTables.CoreKeyForMilestone(milestoneIndex: number): string
	local highestConfigured = 0
	for index in pairs(RewardTables.BossCoreForMilestone) do
		if index > highestConfigured then
			highestConfigured = index
		end
	end
	local clampedIndex = math.clamp(milestoneIndex, 1, math.max(highestConfigured, 1))
	return RewardTables.BossCoreForMilestone[clampedIndex]
end

return RewardTables
