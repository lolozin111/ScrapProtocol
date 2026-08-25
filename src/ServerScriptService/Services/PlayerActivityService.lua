--[[
	PlayerActivityService.lua
	One authoritative answer to "what is this player doing right now," so two systems can never
	both think they own the same player at the same time.

	WHY this exists: before this, five separate systems each kept their own private busy-flag
	keyed by UserId — WaveService.activeRuns, RaidRoomService.activeRaids, NodeService.activeRaids,
	CombatClient's combatActive, and RaidRoomService's per-run state.InCombat — with no arbitration
	between any of them. Each one correctly stopped ITS OWN system from starting twice, and none of
	them knew the others existed.

	The concrete failure that motivated this: CombatEncounterService.activeEncounters is a single
	slot per UserId, written by both RunWave (base defense) and RunRaidCombat (raid rooms) and
	cleared to nil by whichever finishes first. Starting a raid during a wave meant the raid
	overwrote the wave's encounter (so RequestFireWeapon resolved hits against the wrong enemy
	set), and whichever fight ended first nil'd the survivor's entry (so the other became
	unshootable) — while the abandoned wave loop kept ticking, enemies chewing the base wall, with
	the player 800 studs up in a raid instance.

	Fixing that inside either system would just have been a sixth private flag. This is the shared
	piece instead: acquire before you start, release when you finish, and the conflict is
	impossible rather than merely unlikely.

	Deliberately NOT a lock with a timeout or a queue — an activity is held until its owner
	explicitly releases it or the player leaves. That means a missed Release() soft-locks the
	player out of that activity for the rest of their session, so every exit path of every caller
	must release, including the error/interrupted ones. That tradeoff is on purpose: a silent
	auto-expiry would paper over exactly the kind of leaked-state bug this file exists to prevent.
]]

local Players = game:GetService("Players")

local PlayerActivityService = {}

-- The set of things a player can be doing. Only one at a time. Anything not listed here isn't an
-- "activity" — mining, crafting, and browsing the Inventory are all things you can do freely
-- while idle, and none of them own the player's combat state or position.
-- These three are exactly the things that take exclusive ownership of the player's combat state
-- (they all route through CombatEncounterService.activeEncounters, or in the Outpost's case its
-- own damage loop). The Expedition conveyor is deliberately NOT here: it's a shared world queue
-- rather than a per-player run, and a player can walk away from it at any time, so it never
-- conflicts with anything.
PlayerActivityService.Activities = {
	Wave = "Wave",               -- base defense (WaveService.StartWave)
	Raid = "Raid",               -- instanced Raid Rooms (RaidRoomService.RequestStartRaid)
	OutpostRaid = "OutpostRaid", -- the older world Combat Outpost fight (NodeService.StartOutpostRaid)
}

-- Human-readable name per activity, used to build the rejection reason a player actually sees —
-- "You're already in a raid" reads better than "OutpostRaid".
local DISPLAY_NAME = {
	Wave = "defending your base",
	Raid = "in a raid",
	OutpostRaid = "in a fight",
}

local current: { [number]: string } = {} -- userId -> activity key, or nil when idle

-- Tries to claim `activity` for this player. Returns true if it was claimed, or false plus a
-- player-facing reason if they're already busy with something else.
--
-- Re-acquiring an activity the player ALREADY holds fails rather than succeeding silently: every
-- caller already guards against starting its own system twice, so a second acquire means two
-- copies of the same run are being started, which is a bug worth surfacing rather than allowing.
function PlayerActivityService.TryAcquire(player: Player, activity: string): (boolean, string?)
	local held = current[player.UserId]
	if held then
		local what = DISPLAY_NAME[held] or held
		return false, ("You're already %s — finish that first."):format(what)
	end
	current[player.UserId] = activity
	return true
end

-- Releases `activity`, but only if this player is actually the one holding it. Scoping the
-- release to the expected activity (rather than clearing whatever's there) means a stale cleanup
-- path from an already-finished run can't cancel a DIFFERENT activity the player has since
-- started — which matters because several callers release from multiple exit branches, some of
-- which can fire late.
--
-- Safe to call when nothing is held, or when a different activity is held: both are no-ops.
function PlayerActivityService.Release(player: Player, activity: string)
	if current[player.UserId] == activity then
		current[player.UserId] = nil
	end
end

-- What the player is doing right now, or nil if idle.
function PlayerActivityService.Get(player: Player): string?
	return current[player.UserId]
end

-- Convenience for the common "is this player specifically doing X" check.
function PlayerActivityService.Is(player: Player, activity: string): boolean
	return current[player.UserId] == activity
end

Players.PlayerRemoving:Connect(function(player)
	current[player.UserId] = nil
end)

return PlayerActivityService
