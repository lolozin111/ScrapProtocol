--[[
	WaveConfig.lua
	Wave-defense scaling formulas. Matches "Wave defense" table in the design doc.
	These are the two levers to retune during playtesting — change numbers here,
	never inline in WaveService.
]]

local WaveConfig = {}

WaveConfig.EliteWaveInterval = 5      -- every 5th wave is a BOSS wave (see IsEliteWave/
                                       -- BossMilestoneIndex below) — the field name stayed "Elite"
                                       -- (the WaveUpdate wire payload's IsElite key, read by
                                       -- MainHud.client.lua, didn't need a rename) even though the
                                       -- Base Defense & Turrets phase round 2 turned this cadence
                                       -- into full boss-wave rewards — see RewardTables.lua.
WaveConfig.RewardPayoutCap = 30       -- waves beyond this still count for the leaderboard; kept
                                       -- for whatever future pacing mechanic wants a "past this
                                       -- point, stop scaling" cap, same as before.

WaveConfig.EnemyTypes = { "Raider", "Scavenger", "Brute" }

function WaveConfig.GetEnemyCount(waveNumber: number): number
	return 5 + math.floor(waveNumber * 1.5)
end

function WaveConfig.GetEnemyMultiplier(waveNumber: number): number
	return 1 + (waveNumber - 1) * 0.12
end

-- NO LONGER CALLED by WaveService — base defense stopped granting Scrap/Cores entirely (see
-- RewardTables.lua's own header, direct instruction). Left defined, not deleted, in case some
-- future pacing mechanic wants a smooth per-wave currency curve again; harmless to leave unused.
function WaveConfig.GetScrapReward(waveNumber: number): number
	local n = math.min(waveNumber, WaveConfig.RewardPayoutCap)
	return 10 + n * 4
end

function WaveConfig.GetCoresReward(waveNumber: number): number
	local n = math.min(waveNumber, WaveConfig.RewardPayoutCap)
	return math.max(0, n - 4)
end

function WaveConfig.IsEliteWave(waveNumber: number): boolean
	return waveNumber % WaveConfig.EliteWaveInterval == 0
end

-- Which boss milestone this wave is (1 for wave 5, 2 for wave 10, 3 for wave 15, ...) — feeds
-- RewardTables.CoreKeyForMilestone. Only meaningful when IsEliteWave(waveNumber) is true; callers
-- should check that first, same as everywhere else this cadence is used.
function WaveConfig.BossMilestoneIndex(waveNumber: number): number
	return math.floor(waveNumber / WaveConfig.EliteWaveInterval)
end

return WaveConfig
