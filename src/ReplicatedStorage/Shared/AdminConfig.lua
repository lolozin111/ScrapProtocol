--[[
	AdminConfig.lua
	Tiny admin/owner check used to gate developer-only shortcuts (right now: instantly winning
	Combat raids with no Energy cost instead of playing out the timed simulation — see
	NodeService.lua's runRaid).

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
