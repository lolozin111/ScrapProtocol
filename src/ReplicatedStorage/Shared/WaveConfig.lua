--[[
	WaveConfig.lua
	Wave-defense scaling formulas. Matches "Wave defense" table in the design doc.
	These are the two levers to retune during playtesting — change numbers here,
	never inline in WaveService.
]]

local WaveConfig = {}

WaveConfig.EliteWaveInterval = 5      -- every 5th wave spawns a mini-boss
WaveConfig.RewardPayoutCap = 30       -- waves beyond this still count for the leaderboard,
                                       -- but reward payout stops climbing past this point

WaveConfig.EnemyTypes = { "Raider", "Scavenger", "Brute" }

function WaveConfig.GetEnemyCount(waveNumber: number): number
	return 5 + math.floor(waveNumber * 1.5)
end

function WaveConfig.GetEnemyMultiplier(waveNumber: number): number
	return 1 + (waveNumber - 1) * 0.12
end

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

return WaveConfig
