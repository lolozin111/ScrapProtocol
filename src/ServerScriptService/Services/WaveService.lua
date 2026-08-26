--[[
	WaveService.lua
	Runs a player's wave-defense session. Matches "Wave defense" section of the design doc.

	Used to be a headless combat SIMULATION (compare total DPS against an abstract enemy HP pool
	once per second, chip an abstract "objective" HP down) — that scaffold's retired now.
	CombatEncounterService.lua spawns real enemies and resolves real damage through
	DamagePipeline.lua; this file keeps owning what it always owned — StartRun/EndRun, the Revive
	Token retry, and WaveConfig's per-wave reward math — and just hands each wave's actual fight
	off to RunWave.

	Loss condition, REWORKED again after playtest feedback: real enemies at first meant the
	player's own real Humanoid health was the loss condition — but direct feedback afterward was
	that base defense should be about defending the BASE, not the player personally. Every enemy
	now walks to and attacks the base's own position instead of the player, chipping down a WallHP
	pool (BaseConfig.GetWallMaxHP(profile.BaseTier)) that CombatEncounterService owns internally
	per-run. This file only ever sees the RESULT ("Cleared"/"Defeated"/"Interrupted") — it doesn't
	need to know WallHP exists at all, same as it never needed to know about the old ObjectiveHP
	internals either.

	WaveUpdate's payload shape changed alongside this: "WaveStart"/"WaveCleared"/"Revived"/
	"RunEnded"/"NoGear"/"NotInBase" are unchanged in spirit, but "Tick" now reports real numbers
	(WallHP/WallMaxHP/Shield/EnemiesRemaining/EnemiesTotal) fired by CombatEncounterService itself
	roughly once a second, instead of this file computing a fake HP-pool percentage.

	REWORKED AGAIN (Base Defense & Turrets phase round 2, direct instruction): base defense no
	longer grants Scrap or Cores at all — WaveConfig.GetScrapReward/GetCoresReward are defined but
	unused now. Every 5th wave (WaveConfig.EliteWaveInterval/IsEliteWave, cadence unchanged) is a
	BOSS wave that guarantees one CoreItem (profile.CoreItems — see RewardTables
	.CoreKeyForMilestone/DataService.AddCoreItem) plus a good chance at a small utility item;
	regular waves only get the small "here and there" chance. See RewardTables.lua's own header for
	the full reasoning — this file just calls it and applies whatever it rolls.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WaveConfig = require(ReplicatedStorage.Shared.WaveConfig)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local RewardTables = require(ReplicatedStorage.Shared.RewardTables)
local DataService = require(script.Parent.DataService)
local CombatMath = require(script.Parent.CombatMath)
local PlotService = require(script.Parent.PlotService)
local CombatEncounterService = require(script.Parent.CombatEncounterService)
local PlayerActivityService = require(script.Parent.PlayerActivityService)

local Remotes = ReplicatedStorage.Remotes
local StartWave = Remotes.StartWave
local StopWave = Remotes.StopWave
local WaveUpdate = Remotes.WaveUpdate

local WaveService = {}

local activeRuns: { [number]: boolean } = {} -- userId -> true while a run is in progress

-- Applies a RewardTables.Roll() result (a list of { Type, Key, Amount }) to the player's profile
-- and returns it unchanged for the caller to also relay to the HUD. nil in, nil out — a stage
-- with no bonus table configured just means no bonus this time, not an error worth surfacing.
-- Only "Utility" entries exist in base defense's own tables now (BossUtility/RegularUtility, see
-- RewardTables.lua) — DataService.AddCurrency is generic enough to increment ANY flat profile
-- field, not just Scrap/Cores (ShopService.lua already relies on the same thing for
-- InstantCraftTokens/WaveReviveTokens), so no new DataService helper was needed for this.
local function grantRolledLoot(player: Player, granted)
	if not granted then
		return nil
	end
	for _, entry in ipairs(granted) do
		if entry.Type == "Utility" then
			DataService.AddCurrency(player, entry.Key, entry.Amount)
		end
	end
	return granted
end

local function runWaves(player: Player)
	local userId = player.UserId
	local profile = DataService.Get(player)
	if not profile then
		activeRuns[userId] = nil
		return
	end

	-- Rough pre-flight only, same purpose the old totalDPS check always served: don't let a
	-- player with literally nothing to fight with walk into a wave they can't affect at all.
	-- Actual combat no longer uses this number — CombatEncounterService resolves real per-hit
	-- damage — but "no weapon and no robots" is still a real, cheap-to-check signal worth gating.
	if CombatMath.GetPlayerCombatDPS(profile) <= 0 then
		WaveUpdate:FireClient(player, { Status = "NoGear", Message = "Craft a weapon or deploy a robot before starting a run." })
		activeRuns[userId] = nil
		return
	end

	local wave = 1
	local usedRevive = false

	while activeRuns[userId] and player.Parent do
		local isElite = WaveConfig.IsEliteWave(wave)

		WaveUpdate:FireClient(player, {
			Status = "WaveStart",
			Wave = wave,
			IsElite = isElite,
		})

		local result = CombatEncounterService.RunWave(player, wave, { IsElite = isElite })

		if result == "Interrupted" then
			-- character/profile vanished mid-fight (disconnect, reset) — nothing left to retry.
			break
		elseif result == "Defeated" then
			if not usedRevive and profile.WaveReviveTokens > 0 then
				usedRevive = true
				profile.WaveReviveTokens -= 1
				-- No explicit heal needed here anymore — "Defeated" now means the WALL hit 0, and
				-- retrying just calls CombatEncounterService.RunWave again below, which always
				-- builds a brand-new WallHP pool from scratch at the top of the run. A revive is
				-- "redo this wave with a fresh wall," same as it was always "redo this wave" —
				-- only what gets reset changed.
				WaveUpdate:FireClient(player, { Status = "Revived", Wave = wave })
				-- retry the same wave rather than advancing
			else
				break
			end
		else
			-- wave cleared — NO Scrap/Cores anymore (direct instruction, see RewardTables.lua's own
			-- header). Boss waves (every EliteWaveInterval-th) guarantee one CoreItem plus a good
			-- chance at a utility item; regular waves only get the small "here and there" chance.
			DataService.SetHighestWave(player, wave)

			local coreGrant = nil
			local bonusLoot
			if isElite then
				local milestoneIndex = WaveConfig.BossMilestoneIndex(wave)
				local coreKey = RewardTables.CoreKeyForMilestone(milestoneIndex)
				DataService.AddCoreItem(player, coreKey, 1)
				coreGrant = { Key = coreKey, Amount = 1 }
				bonusLoot = grantRolledLoot(player, RewardTables.Roll("BossUtility"))
			else
				bonusLoot = grantRolledLoot(player, RewardTables.Roll("RegularUtility"))
			end

			WaveUpdate:FireClient(player, {
				Status = "WaveCleared",
				Wave = wave,
				IsElite = isElite, -- "boss wave" now, same field name as WaveStart's IsElite —
					-- see WaveConfig.lua's own comment on why the name itself stayed.
				CoreGrant = coreGrant or false, -- `or false`, same nil-drop reasoning as every other
					-- optional field this codebase broadcasts — see ForgeService's comment.
				BonusLoot = bonusLoot or false,
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

	-- Claim the player's combat state (see PlayerActivityService). CombatEncounterService keeps a
	-- SINGLE activeEncounters slot per UserId, shared by RunWave and RunRaidCombat — so before
	-- this, starting a raid mid-wave silently corrupted both fights. activeRuns above stays as the
	-- local "is a run already going" guard; this is the cross-system one.
	local acquired, busyReason = PlayerActivityService.TryAcquire(player, PlayerActivityService.Activities.Wave)
	if not acquired then
		WaveUpdate:FireClient(player, { Status = "Busy", Message = busyReason })
		return
	end

	activeRuns[player.UserId] = true

	-- Released once here rather than at runWaves' own exit, and pcall'd so an error inside the
	-- wave loop can't strand the activity and lock the player out of fighting for the session.
	task.spawn(function()
		local ok, err = pcall(runWaves, player)
		if not ok then
			warn("[WaveService] runWaves errored:", err)
			activeRuns[player.UserId] = nil
			WaveUpdate:FireClient(player, { Status = "RunEnded", HighestWave = 0 })
		end
		PlayerActivityService.Release(player, PlayerActivityService.Activities.Wave)
	end)
end)

-- StopWave: end a run on purpose. Before this there was NO way out of runWaves' loop except losing
-- or resetting your character — it ran until the wall fell or the character vanished. That's also
-- what made an unkillable enemy (see CombatEncounterService's isEnemyAlive) an unrecoverable hang
-- rather than an annoyance.
--
-- Clearing activeRuns is all that's needed: the loop re-checks it every iteration, so it exits
-- cleanly after the wave in progress resolves rather than being torn down mid-fight. The player
-- keeps whatever that wave already banked, and the "Wave" activity is released by the same
-- task.spawn wrapper that handles every other exit (see StartWave above).
StopWave.OnServerEvent:Connect(function(player: Player)
	if not activeRuns[player.UserId] then
		return -- nothing running; nothing to stop
	end
	activeRuns[player.UserId] = nil
	WaveUpdate:FireClient(player, { Status = "Stopping" })
end)

game.Players.PlayerRemoving:Connect(function(player)
	activeRuns[player.UserId] = nil
end)

return WaveService
