--[[
	OreGate.lua
	The single answer to "is this player allowed to mine this ore right now, and if not, why?"

	Two systems mine ore and both need this check: MiningService (hand-placed OreNode parts, the
	ProximityPrompt flow) and MineShaftService (the dig-down voxel grid, the click flow). They used
	to carry a near-identical private copy each — same tool-tier check, same wave-unlock check, same
	message strings — with a comment in MineShaftService's header instructing whoever changed one to
	remember to change the other. That instruction is exactly the kind of thing that gets missed, so
	the two copies are now one function.

	Deliberately server-side (in Services/) rather than a Shared config module: it reads a player's
	live profile through DataService, which is server-only. Same shape as CombatMath.lua and
	DamagePipeline.lua — a plain utility module with no remotes of its own.

	The RULES themselves still live in OreConfig (MinToolTier, MinWaveUnlock) — this file only
	decides how those fields are enforced and worded, which is the part that was duplicated.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OreConfig = require(ReplicatedStorage.Shared.OreConfig)
local DataService = require(script.Parent.DataService)

local OreGate = {}

-- Returns true if the player may mine `oreKey`, or false plus a human-readable reason.
--
-- The reason is player-facing: both callers relay it straight to the MineFailed remote, which the
-- HUD now shows as an on-screen toast. A rejected mining attempt used to fail completely silently,
-- which is why every branch here explains itself and points at the fix ("upgrade in Workbench ->
-- Tools") rather than just saying no.
function OreGate.CanMine(player: Player, oreKey: string): (boolean, string?)
	local oreData = OreConfig.Ores[oreKey]
	if not oreData then
		return false, "Unknown ore type"
	end

	local profile = DataService.Get(player)
	if not profile then
		return false, "Profile not loaded"
	end

	if oreData.MinToolTier and profile.ToolTier < oreData.MinToolTier then
		local requiredTool = OreConfig.ToolTiers[oreData.MinToolTier]
		return false, ("Needs %s or better — upgrade in Workbench -> Tools"):format(
			requiredTool and requiredTool.Name or ("Tool Tier " .. oreData.MinToolTier))
	end

	if oreData.MinWaveUnlock and profile.HighestWave < oreData.MinWaveUnlock then
		return false, ("Locked until you clear Wave %d"):format(oreData.MinWaveUnlock)
	end

	return true
end

return OreGate
