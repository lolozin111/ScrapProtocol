--[[
	PlayerSpeed.lua
	One authoritative owner of a player's WalkSpeed, so two systems can slow or hasten the same
	player without erasing each other.

	=== WHY ===
	Before this, WalkSpeed was written directly in several places. That works fine while exactly one
	system touches it — and the moment a second one does, the last writer wins and the first effect
	silently disappears. The Longshot Rifle is exactly that second system: it slows you while it's
	held, which has to survive a Speed Boost robot firing off mid-wave, and has to come back when the
	boost expires rather than being clobbered by the boost's own restore.

	The same shape as RateLimiter and PlayerActivityService: a small shared module that exists because
	the alternative is the same bug re-solved locally, differently, several times.

	=== MODEL ===
	A base speed per player plus named multipliers, multiplied together. Order of application does
	not matter and nothing needs to know what else is active:

	  PlayerSpeed.Set(player, "Wield", 0.55)   -- carrying something heavy
	  PlayerSpeed.Set(player, "SpeedBoost", 1.4)
	  -- net: base * 0.55 * 1.4
	  PlayerSpeed.Set(player, "Wield", nil)    -- put the rifle away; the boost survives

	Keys are just strings. Use one per SYSTEM, not one per event — a system that sets its key twice
	should overwrite its own value, which is what you want and what this does.
]]

local Players = game:GetService("Players")

local PlayerSpeed = {}

-- Roblox's own default, used only until a character actually loads and tells us otherwise.
local FALLBACK_BASE = 16

local base: { [number]: number } = {}
local modifiers: { [number]: { [string]: number } } = {}

local function humanoidFor(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

function PlayerSpeed.GetBase(player: Player): number
	return base[player.UserId] or FALLBACK_BASE
end

-- Recomputes and writes. Safe to call when the character is missing (during a respawn, say) — the
-- modifiers stay recorded and are re-applied by the CharacterAdded hook below.
function PlayerSpeed.Apply(player: Player)
	local humanoid = humanoidFor(player)
	if not humanoid then
		return
	end

	local speed = PlayerSpeed.GetBase(player)
	for _, multiplier in pairs(modifiers[player.UserId] or {}) do
		speed *= multiplier
	end

	-- Clamped above zero: a multiplier of 0 (or a stack of them rounding there) would leave the
	-- player unable to move with no on-screen explanation, which reads as a freeze, not a debuff.
	humanoid.WalkSpeed = math.max(speed, 1)
end

-- `multiplier = nil` removes this system's contribution entirely.
function PlayerSpeed.Set(player: Player, key: string, multiplier: number?)
	local userId = player.UserId
	if multiplier == nil then
		if modifiers[userId] then
			modifiers[userId][key] = nil
		end
	else
		modifiers[userId] = modifiers[userId] or {}
		modifiers[userId][key] = multiplier
	end
	PlayerSpeed.Apply(player)
end

function PlayerSpeed.Get(player: Player, key: string): number?
	return (modifiers[player.UserId] or {})[key]
end

-- Drops every modifier. For a hard reset (leaving a raid, say); ordinary cleanup should clear its
-- own key so it cannot cancel another system's effect as a side effect.
function PlayerSpeed.ClearAll(player: Player)
	modifiers[player.UserId] = nil
	PlayerSpeed.Apply(player)
end

-- The base is re-read from each fresh Humanoid rather than remembered across lives, so a change to
-- StarterPlayer.CharacterWalkSpeed takes effect on the next respawn instead of being pinned to
-- whatever the value was when the player first joined. Modifiers deliberately DO survive: a rifle
-- still in your hands after a respawn is still heavy.
local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	base[player.UserId] = humanoid.WalkSpeed
	PlayerSpeed.Apply(player)
end

-- Spawned, never called inline: onCharacter yields on WaitForChild, and this module is required
-- from Main.server.lua's boot list. Blocking here would stall every service loaded after it.
local function track(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(onCharacter, player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

Players.PlayerAdded:Connect(track)

-- Anyone who joined before this module was first required. In a live server that is nobody, but in
-- Studio the local player routinely exists by the time ServerScriptService finishes booting — and a
-- player never tracked here would have no base speed, so every modifier would compute against the
-- 16-stud fallback instead of their real one.
for _, player in ipairs(Players:GetPlayers()) do
	track(player)
end

Players.PlayerRemoving:Connect(function(player)
	base[player.UserId] = nil
	modifiers[player.UserId] = nil
end)

return PlayerSpeed
