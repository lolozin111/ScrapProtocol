--[[
	AdminConfig.lua
	Tiny admin/owner check used to gate developer-only shortcuts. Right now:
	  • instantly winning Combat raids instead of playing out the timed simulation — NodeService's
	    runRaid, gated on IsAdmin alone.
	  • infinite Energy — RaidEnergyService.HasInfiniteEnergy.
	  • a guaranteed elite in every fight (raid Combat rooms, Ambush waves, and every defense wave
	    rather than every 5th) — RaidRoomService.beginCombat/beginAmbush and
	    CombatEncounterService.RunWave, so a newly-built elite Model can be seen without rerolling
	    a chance or clearing four waves first.

	The last two are ALSO conditioned on not being in a Player Test Session, and that combined test
	lives in Services/DevShortcuts.lua rather than being written out at each call site — see that
	file for why, and for which kind of admin power belongs behind it vs. behind IsAdmin alone.
	Test mode exists to see the game as a new player does, so a difficulty or pacing shortcut that
	stayed on inside it would hide the very problems the mode is there to surface.

	Two ways to count as admin:
	  1. You're testing in Studio (or any server) as the account that owns this place. Detected
	     automatically via game.CreatorId/CreatorType — nothing to configure, this just works as
	     long as the game is owned by a User (not a Group; see the note below).
	  2. Your UserId is listed in AdminUserIds below — add teammates here, or add yourself here
	     too if the game ends up owned by a Group instead of your personal account (Group-owned
	     places have no single "owner player" to auto-detect, so #1 can't cover that case).

	Since admin is otherwise always-on for whoever it applies to, there's no way to test what a
	normal player actually experiences (Energy costs, real combat) while playing as yourself —
	AdminService.lua's "/admin" chat command flips a session-only override via SetOverride below.
	The override can only ever MUTE admin for someone who already qualifies above, never grant it
	to someone who doesn't — see isBaseAdmin.
]]

local AdminConfig = {}

AdminConfig.AdminUserIds = {
	-- Add UserIds here, e.g.: 123456789,
}

-- Session-only manual override, keyed by UserId (true/false/nil — nil means "no override, use
-- the real check below"). Resets on rejoin/server restart, never persisted.
local sessionOverrides: { [number]: boolean } = {}

-- The real, non-overridable check.
local function isBaseAdmin(player: Player): boolean
	if table.find(AdminConfig.AdminUserIds, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return false
end

function AdminConfig.IsAdmin(player: Player): boolean
	if not isBaseAdmin(player) then
		return false
	end
	local override = sessionOverrides[player.UserId]
	if override ~= nil then
		return override
	end
	return true
end

-- No-ops for anyone isBaseAdmin doesn't already cover — this can only turn a real admin's
-- shortcuts off/on for testing, it can never grant admin to someone who isn't one.
function AdminConfig.SetOverride(player: Player, value: boolean?)
	if not isBaseAdmin(player) then
		return
	end
	sessionOverrides[player.UserId] = value
end

return AdminConfig
