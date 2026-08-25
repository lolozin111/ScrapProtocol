--[[
	RateLimiter.lua
	One shared per-player cooldown table, so every spammable remote can be paced the same way
	instead of each service hand-rolling its own debounce (or, more often, forgetting to).

	Not a service in the usual sense — no remotes of its own, nothing to boot. Same shape as
	CombatMath.lua/DamagePipeline.lua: a plain utility module that lives here because it's
	server-only logic, required directly by whoever needs it.

	WHY this exists: every OnServerEvent in this game is an entry point a client controls
	completely, and a fire-and-forget RemoteEvent with no cooldown can be called in a tight loop.
	MineNode and MineShaftHit both had only a distance check, so a modified client could drain a
	node — or the entire mine grid — as fast as it could send packets. RequestFireWeapon had
	always enforced a real cooldown (see CombatEncounterService); this generalizes that so the
	next remote gets it for free rather than repeating the pattern by hand a fourth time.

	Usage:
		if not RateLimiter.Check(player, "MineNode", swingTime) then
			Remotes.MineFailed:FireClient(player, "Too fast")
			return
		end

	Check() both TESTS and STAMPS in one call — there's no separate "commit" step, because every
	caller so far wants exactly "am I allowed, and if so start the clock." A caller that needs to
	test without consuming would need a separate function; none do yet.

	Keys are arbitrary strings, scoped per player, so one player's mining cooldown and their
	Recall cooldown never interfere. Use the remote's own name as the key by convention.
]]

local Players = game:GetService("Players")

local RateLimiter = {}

-- [player][key] = os.clock() of that key's last allowed call. Keyed by the Player instance
-- rather than UserId purely so PlayerRemoving cleanup is a single nil assignment; nothing here
-- needs to survive a rejoin (a fresh session starting with every cooldown expired is correct —
-- the point is pacing a live input stream, not persisting a penalty).
local stamps: { [Player]: { [string]: number } } = {}

-- Returns true and starts the cooldown if `player` may perform `key` right now; false if they're
-- still inside the previous call's `cooldownSeconds` window. A cooldownSeconds of 0 or less
-- always allows (and still stamps), so a caller can disable pacing by passing 0 without needing
-- a branch of its own.
function RateLimiter.Check(player: Player, key: string, cooldownSeconds: number): boolean
	local now = os.clock()
	local byKey = stamps[player]
	if not byKey then
		byKey = {}
		stamps[player] = byKey
	end

	local last = byKey[key]
	if last and now - last < cooldownSeconds then
		return false
	end

	byKey[key] = now
	return true
end

-- Drops one key's cooldown early. Not used by anything yet — here for the case where an action
-- gets cancelled after being stamped and shouldn't cost the player their next attempt.
function RateLimiter.Reset(player: Player, key: string)
	local byKey = stamps[player]
	if byKey then
		byKey[key] = nil
	end
end

Players.PlayerRemoving:Connect(function(player)
	stamps[player] = nil
end)

return RateLimiter
