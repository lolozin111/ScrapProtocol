--[[
	DevShortcuts.lua
	One question, asked from several places: "should this player get developer shortcuts right now?"

	A shared utility, not a service — no remotes, no state, required by consumers, following the
	RateLimiter/OreGate precedent. It exists for the reason every module on that list exists: the
	same two-part test had already been written out by hand in more than one file, and this codebase
	keeps learning that hand-copied predicates drift.

	The test is AdminConfig.IsAdmin AND NOT DataService.IsTestSession. The second half is the
	interesting one: Player Test Mode gives an admin a throwaway profile so they can see the game the
	way a new player does, and a shortcut that stayed on inside it would hide exactly the pacing and
	difficulty problems the mode exists to surface. So a shortcut gated on this is automatically
	correct in a test session without every call site remembering to think about it.

	NOT every admin power belongs behind this. The chat commands in AdminService (/give and friends)
	deliberately check AdminConfig.IsAdmin alone, because they are how you SET UP a test rather than
	something that would distort one. Use this for shortcuts that change how the game plays; use
	AdminConfig.IsAdmin directly for tools that change what you have.

	Current consumers:
	  RaidEnergyService.HasInfiniteEnergy  — Energy never drains.
	  RaidRoomService  (beginCombat/beginAmbush) — every raid fight is forced to include an elite.
	  CombatEncounterService.RunWave       — every defense wave is forced to include an elite.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminConfig = require(ReplicatedStorage.Shared.AdminConfig)
local DataService = require(script.Parent.DataService)

local DevShortcuts = {}

-- Last answer announced per userId, so the log below fires on CHANGE rather than on every call.
-- Every call would be thousands of lines (this is asked per raid room and per wave); once per
-- session would miss "/admin off", which legitimately flips the answer mid-session.
local lastAnnounced = {}

-- Says out loud whether shortcuts are on, and WHICH half of the test turned them off.
--
-- Added because the silence was the problem: a shortcut gated on this simply does nothing when the
-- answer is false, and "nothing happened" is identical whether you are not an admin, you typed
-- /admin off, or Player Test Mode is on — three different fixes behind one symptom. This is the
-- same reason Main.server.lua shouts about unloaded services rather than letting a dead
-- OnServerInvoke yield forever.
local function announce(player: Player, isAdmin: boolean, testSession: boolean, active: boolean)
	if lastAnnounced[player.UserId] == active then
		return
	end
	lastAnnounced[player.UserId] = active

	if active then
		print(("[DevShortcuts] %s — ON. Infinite Energy, forced elites in every fight."):format(player.Name))
	elseif not isAdmin then
		print(("[DevShortcuts] %s — OFF: not counting as an admin right now (AdminConfig.IsAdmin is false; did you type /admin off?)."):format(player.Name))
	elseif testSession then
		print(("[DevShortcuts] %s — OFF: you are in a Player Test Session. That is deliberate — turn TEST MODE off and rejoin to get shortcuts back."):format(player.Name))
	end
end

function DevShortcuts.Active(player: Player): boolean
	if not player then
		return false
	end
	local isAdmin = AdminConfig.IsAdmin(player)
	local testSession = DataService.IsTestSession(player)
	local active = isAdmin and not testSession
	announce(player, isAdmin, testSession, active)
	return active
end

Players.PlayerRemoving:Connect(function(player)
	lastAnnounced[player.UserId] = nil
end)

return DevShortcuts
