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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminConfig = require(ReplicatedStorage.Shared.AdminConfig)
local DataService = require(script.Parent.DataService)

local DevShortcuts = {}

function DevShortcuts.Active(player: Player): boolean
	if not player then
		return false
	end
	return AdminConfig.IsAdmin(player) and not DataService.IsTestSession(player)
end

return DevShortcuts
