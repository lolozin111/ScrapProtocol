--[[
	WaveService.lua
	Runs a player's wave-defense session. Matches "Wave defense" section of the design doc.

	IMPORTANT — this is a headless combat SIMULATION, not real spawned enemies. It exists so
	the full loop (mine -> craft -> deploy -> defend -> earn -> repeat) is playable and
	testable end to end from week one, without you first having to build enemy AI, gun
	firing, and hit detection. Total DPS (your best weapon + deployed robots) is compared
	against each wave's enemy HP pool once per second; the objective takes chip damage from
	however many enemies are still alive.

	Swap this out incrementally: keep StartRun/EndRun and the reward math, replace the
	`task.wait(1)` tick loop with real NPC spawns + damage events from your gun and robot
	scripts. The RemoteEvent contract (WaveUpdate payload shape) can stay the same so the
	HUD you build against this scaffold doesn't need to change later.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WaveConfig = require(ReplicatedStorage.Shared.WaveConfig)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local DataService = require(script.Parent.DataService)
local CombatMath = require(script.Parent.CombatMath)
local PlotService = require(script.Parent.PlotService)

local Remotes = ReplicatedStorage.Remotes
local StartWave = Remotes.StartWave
local WaveUpdate = Remotes.WaveUpdate

local OBJECTIVE_MAX_HP = 500
local ENEMY_HP_EACH = 10
local ENEMY_DPS_EACH = 2 -- damage a single live enemy deals to the objective per second

local WaveService = {}

local activeRuns: { [number]: boolean } = {} -- userId -> true while a run is in progress

local function runWaves(player: Player)
	local userId = player.UserId
	local profile = DataService.Get(player)
	if not profile then
		activeRuns[userId] = nil
		return
	end

	local totalDPS = CombatMath.GetPlayerCombatDPS(profile)
	if totalDPS <= 0 then
		WaveUpdate:FireClient(player, { Status = "NoGear", Message = "Craft a weapon or deploy a robot before starting a run." })
		activeRuns[userId] = nil
		return
	end

	local objectiveHP = OBJECTIVE_MAX_HP
	local wave = 1
	local usedRevive = false

	while activeRuns[userId] and player.Parent do
		local enemyCount = WaveConfig.GetEnemyCount(wave)
		local multiplier = WaveConfig.GetEnemyMultiplier(wave)
		local enemyHPPool = enemyCount * ENEMY_HP_EACH * multiplier
		local remainingEnemyHP = enemyHPPool

		WaveUpdate:FireClient(player, {
			Status = "WaveStart",
			Wave = wave,
			IsElite = WaveConfig.IsEliteWave(wave),
			EnemyCount = enemyCount,
			EnemyHPPool = enemyHPPool,
			ObjectiveHP = objectiveHP,
			ObjectiveMaxHP = OBJECTIVE_MAX_HP,
		})

		while remainingEnemyHP > 0 and activeRuns[userId] and player.Parent do
			task.wait(1)
			remainingEnemyHP -= totalDPS

			local remainingEnemyCount = math.max(0, math.ceil(remainingEnemyHP / (ENEMY_HP_EACH * multiplier)))
			objectiveHP -= remainingEnemyCount * ENEMY_DPS_EACH

			WaveUpdate:FireClient(player, {
				Status = "Tick",
				Wave = wave,
				RemainingEnemyHP = math.max(0, remainingEnemyHP),
				RemainingEnemyCount = remainingEnemyCount,
				ObjectiveHP = math.max(0, objectiveHP),
			})

			if objectiveHP <= 0 then
				break
			end
		end

		if objectiveHP <= 0 then
			if not usedRevive and profile.WaveReviveTokens > 0 then
				usedRevive = true
				profile.WaveReviveTokens -= 1
				objectiveHP = OBJECTIVE_MAX_HP
				WaveUpdate:FireClient(player, { Status = "Revived", Wave = wave })
				-- retry the same wave rather than advancing
			else
				break
			end
		else
			-- wave cleared
			local scrapReward = WaveConfig.GetScrapReward(wave)
			local coresReward = WaveConfig.GetCoresReward(wave)
			DataService.AddCurrency(player, "Scrap", scrapReward)
			DataService.AddCurrency(player, "Cores", coresReward)
			DataService.SetHighestWave(player, wave)

			WaveUpdate:FireClient(player, {
				Status = "WaveCleared",
				Wave = wave,
				ScrapReward = scrapReward,
				CoresReward = coresReward,
			})

			wave += 1
		end
	end

	WaveUpdate:FireClient(player, { Status = "RunEnded", HighestWave = math.max(profile.HighestWave, wave - 1) })
	activeRuns[userId] = nil
end

StartWave.OnServerEvent:Connect(function(player: Player)
	if activeRuns[player.UserId] then
		return -- already mid-run
	end
	if not PlotService.IsPlayerInOwnPlot(player) then
		WaveUpdate:FireClient(player, { Status = "NotInBase", Message = PlotConfig.NotInBaseMessage })
		return
	end
	activeRuns[player.UserId] = true
	task.spawn(runWaves, player)
end)

game.Players.PlayerRemoving:Connect(function(player)
	activeRuns[player.UserId] = nil
end)

return WaveService
