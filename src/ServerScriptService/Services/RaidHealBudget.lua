--[[
	RaidHealBudget.lua
	How much the Support Core drone has already healed a player in the current raid ROOM and MAP — the
	bookkeeping half of the user's rule (2026-09-22): the drone may heal at most 15% of max health per
	room and 75% per map, "so heal places arent useless". The limits themselves are DroneConfig's
	(Support Params RaidRoomHealCap / RaidMapHealCap); this file only counts, so the numbers live in
	one place and this never has to know them.

	A shared utility, not a service (no remotes; the RateLimiter/OreGate precedent). RaidRoomService
	drives the lifecycle — Begin when a raid starts, NewNode on entering each node, NewMap when a map
	is cleared, End in cleanupRaid — and DroneBehaviors' Support tick reads and spends it.

	No active budget = not in a raid = no cap. That's the whole reason Get returns nil outside a raid:
	base-defense waves keep the drone exactly as it was.
]]

local Players = game:GetService("Players")

local RaidHealBudget = {}

local budgets: { [number]: {
	NodeHealed: number,
	MapHealed: number,
	ToastedNode: boolean,
	ToastedMap: boolean,
} } = {}

function RaidHealBudget.Begin(player: Player)
	budgets[player.UserId] = { NodeHealed = 0, MapHealed = 0, ToastedNode = false, ToastedMap = false }
end

-- Entering any node — the per-room allowance refills. The map allowance does not.
function RaidHealBudget.NewNode(player: Player)
	local budget = budgets[player.UserId]
	if budget then
		budget.NodeHealed = 0
		budget.ToastedNode = false
	end
end

-- A map was cleared — the next one starts with a full allowance (the user's call: pushing onto the
-- next map should stay survivable). Refills the room allowance too, for the same reason.
function RaidHealBudget.NewMap(player: Player)
	local budget = budgets[player.UserId]
	if budget then
		budget.NodeHealed = 0
		budget.MapHealed = 0
		budget.ToastedNode = false
		budget.ToastedMap = false
	end
end

function RaidHealBudget.End(player: Player)
	budgets[player.UserId] = nil
end

-- The live table (mutated by the caller as it spends), or nil when the player isn't in a raid.
function RaidHealBudget.Get(player: Player)
	return budgets[player.UserId]
end

-- cleanupRaid already calls End on the normal paths; this is the backstop for a disconnect that skips
-- them, so a leaver's entry can't linger for the rest of the server's life. No profile data is held
-- here, so PlayerRemoving is the right event (not DataService.PlayerSaving).
Players.PlayerRemoving:Connect(function(player)
	budgets[player.UserId] = nil
end)

return RaidHealBudget
