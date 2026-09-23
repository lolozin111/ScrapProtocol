--[[
	PlayerVitals.lua
	The server's own copy of a player's HP, so "did this player die" stops being a question the
	client gets to answer.

	NOT a service in the usual sense — no remotes, nothing to boot. Same shape as RateLimiter.lua /
	CombatMath.lua / DamagePipeline.lua: a plain server-only utility module, required directly by
	whoever needs it.

	WHY this exists (2026-09-23 adversarial review, F3). Every combat system in this game resolved
	player death the same way: apply `humanoid:TakeDamage(...)` to the player's own character, then
	poll `humanoid.Health <= 0`. Nothing server-side kept its own copy and nothing cross-checked the
	Humanoid against one. But a player's Humanoid belongs to that player's client — Roblox replicates
	the owning client's Humanoid state — so the number every fight in the game was decided by is a
	number the client can write. That is the ordinary godmode surface, except here it does not just
	make you hard to kill: a Raid Room run holds its Contraband and Cores in `state.PendingRewards`
	and only ever loses them on a Defeat, and a Defeat is `Health <= 0`. Remove death and Extract
	becomes a formality, and the reward ladders pay for as long as you care to keep walking.

	THE RULE: while a player is in an activity (see PlayerActivityService), this module owns their
	HP. The Humanoid becomes a display of that number, not the record of it. Damage subtracts here,
	heals add here, and the death test reads here. A client that writes its own Health gets corrected
	on the very next tick that touches it, and is ignored by every decision in between.

	OUTSIDE an activity this module is a deliberate PASS-THROUGH: with no record for that player,
	every function below reads and writes the Humanoid directly, exactly as the old code did. That
	is what keeps mine lava, base security lasers, falling and idle healing behaving as they always
	have, and it means call sites never need an `if in a raid then ... else ...` branch. It also
	scopes the guarantee honestly: this closes "never die in a fight," not "never take a scratch
	anywhere in the world," because the fights are where the rewards are.

	Tracking is bracketed by PlayerActivityService.TryAcquire/Release rather than by each combat
	system, deliberately. Those two calls are already the single funnel every activity goes through,
	on every exit path including the error and disconnect ones — so "you are in an activity" and
	"your HP is authoritative" are the same statement, and there is no bracket left for a future
	system to forget.
]]

local Players = game:GetService("Players")

local PlayerVitals = {}

-- userId -> { Current, Max, Character }. Absent = not tracking = pass through to the Humanoid.
-- Character is kept so a respawn mid-activity can be noticed lazily (see recordFor) instead of
-- needing a CharacterAdded connection per tracked player that some exit path could leak.
local tracked: { [number]: { Current: number, Max: number, Character: Instance? } } = {}

-- Roblox inserts a Script named "Health" into every character, which regenerates 1% of MaxHealth
-- per second forever. That is invisible until something else owns the player's HP, at which point
-- the two fight: the regen adds a point, mirror() below puts it straight back, and a player at
-- 100 max watches their bar tick 56 -> 57 -> 56 once a second. Reported from testing as "the
-- Support Core isn't healing me", because a flicker is what a heal that gets reverted looks like.
--
-- DISABLED rather than destroyed, and only for as long as an activity holds the player, so this
-- changes nothing outside a fight: passive regen at base works exactly as it always has. Inside a
-- fight it was already being cancelled by the mirror, so switching it off is not a balance change
-- either — it only removes a phantom point that never actually landed. Roblox's own script is the
-- one thing that can re-enable itself cleanly, which is why this toggles `Disabled` instead of
-- deleting the instance and having nothing to put back.
local DEFAULT_REGEN_SCRIPT_NAME = "Health"

local function setDefaultRegenEnabled(character: Instance?, enabled: boolean)
	if not character then
		return
	end
	local regen = character:FindFirstChild(DEFAULT_REGEN_SCRIPT_NAME)
	if regen and regen:IsA("BaseScript") then
		regen.Disabled = not enabled
	end
end

local function humanoidOf(player: Player): (Humanoid?, Instance?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	return character:FindFirstChildOfClass("Humanoid"), character
end

-- A real, finite, non-negative amount. Every caller passes a server-computed number today, so this
-- is a guard against a future config typo (a nil field multiplying to NaN) reaching the arithmetic
-- below and poisoning Current permanently — NaN fails every comparison, so a NaN'd Current would
-- read as neither alive nor dead and strand the run.
local function sanitize(amount: any): number
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount == -math.huge then
		return 0
	end
	return math.max(0, amount)
end

-- The tracked record plus the live Humanoid, re-seeding from the character if it was replaced.
-- Returns nil for the record when this player isn't being tracked — that's the pass-through case.
local function recordFor(player: Player): (any?, Humanoid?)
	local record = tracked[player.UserId]
	local humanoid = humanoidOf(player)
	if not record then
		return nil, humanoid
	end

	local character = player.Character
	if humanoid and record.Character ~= character then
		-- Respawned inside an activity (the mine's reset eviction and a raid's own LoadCharacter
		-- both do this). The fresh body's numbers are the truth; nothing is carried over, which is
		-- what a respawn means everywhere else in this codebase too.
		record.Character = character
		record.Max = humanoid.MaxHealth
		record.Current = humanoid.Health
		-- The fresh body arrives with its own enabled regen script, so it has to be muted too or
		-- the flicker comes back the moment a player respawns mid-activity.
		setDefaultRegenEnabled(character, false)
	end

	return record, humanoid
end

-- Push the authoritative number onto the Humanoid. This is the line that corrects a client which
-- wrote its own Health: it runs on every mutation and every Get, so a tampered value survives only
-- until the next tick that looks at it. Writing an unchanged value is a no-op, so this costs
-- nothing on the overwhelmingly common honest path.
local function mirror(record, humanoid: Humanoid?)
	if not humanoid then
		return
	end
	if humanoid.MaxHealth ~= record.Max then
		humanoid.MaxHealth = record.Max
	end
	if humanoid.Health ~= record.Current then
		humanoid.Health = record.Current
	end
end

----------------------------------------------------------------------
-- Lifecycle — called only by PlayerActivityService, see this file's header
----------------------------------------------------------------------

-- Starts owning this player's HP. Seeds from the Humanoid, clamped to MaxHealth: the seed is the
-- one client-influenced number in the whole system, and clamping bounds it to a pool the player
-- could have reached honestly anyway by healing before they set off. Every raid sets MaxHealth
-- server-side at the same moment (RunBuffService.applyMaxHealth), so in the case that matters the
-- ceiling being clamped against is the server's own.
function PlayerVitals.Begin(player: Player)
	local humanoid, character = humanoidOf(player)
	if not humanoid then
		return
	end
	tracked[player.UserId] = {
		Max = humanoid.MaxHealth,
		Current = math.clamp(humanoid.Health, 0, humanoid.MaxHealth),
		Character = character,
	}
	setDefaultRegenEnabled(character, false)
end

-- Stops owning it. The Humanoid keeps whatever the last mirrored value was, so a player walks out
-- of a raid with the HP the raid left them on rather than being snapped anywhere.
function PlayerVitals.End(player: Player)
	local record = tracked[player.UserId]
	tracked[player.UserId] = nil
	-- Hand passive regen back. Both the character the activity STARTED on and the one the player is
	-- wearing now, because a death mid-raid replaces the body and only the live one would otherwise
	-- get its script re-enabled — leaving a player who died in a raid with no passive regen for the
	-- rest of the session, which is the kind of quiet, permanent-feeling bug this file exists to
	-- stop shipping.
	if record and record.Character then
		setDefaultRegenEnabled(record.Character, true)
	end
	setDefaultRegenEnabled(player.Character, true)
end

----------------------------------------------------------------------
-- Reads
----------------------------------------------------------------------

-- Current and Max. Use this for anything that BRANCHES on health, and for anything sent to a client
-- as a health readout — a HUD fed from the Humanoid would otherwise disagree with the server about
-- a fight the server is deciding.
function PlayerVitals.Get(player: Player): (number, number)
	local record, humanoid = recordFor(player)
	if not record then
		if not humanoid then
			return 0, 0
		end
		return humanoid.Health, humanoid.MaxHealth
	end
	mirror(record, humanoid)
	return record.Current, record.Max
end

function PlayerVitals.IsAlive(player: Player): boolean
	local current = PlayerVitals.Get(player)
	return current > 0
end

----------------------------------------------------------------------
-- Writes
----------------------------------------------------------------------

-- Subtract `amount`. Returns the resulting health. Replaces `humanoid:TakeDamage(amount)` at every
-- player-damage site — TakeDamage subtracts from whatever the Humanoid currently says, which is the
-- whole problem.
function PlayerVitals.Damage(player: Player, amount: number): number
	local record, humanoid = recordFor(player)
	amount = sanitize(amount)
	if not record then
		if humanoid then
			humanoid:TakeDamage(amount)
			return humanoid.Health
		end
		return 0
	end
	record.Current = math.max(0, record.Current - amount)
	mirror(record, humanoid)
	return record.Current
end

-- Add `amount`, capped at Max. Returns how much was ACTUALLY restored and the resulting health —
-- the healing systems here all need the former to charge it against a per-room/per-map budget.
function PlayerVitals.Heal(player: Player, amount: number): (number, number)
	local record, humanoid = recordFor(player)
	amount = sanitize(amount)
	if not record then
		if humanoid then
			local before = humanoid.Health
			humanoid.Health = math.min(humanoid.MaxHealth, before + amount)
			return humanoid.Health - before, humanoid.Health
		end
		return 0, 0
	end
	local before = record.Current
	record.Current = math.min(record.Max, before + amount)
	mirror(record, humanoid)
	return record.Current - before, record.Current
end

-- Straight to full. The shape every "Heal Station"/"room cleared" site wants.
function PlayerVitals.SetToMax(player: Player)
	local record, humanoid = recordFor(player)
	if not record then
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
		return
	end
	record.Current = record.Max
	mirror(record, humanoid)
end

-- Straight to dead, for the one site that kills outright rather than dealing damage
-- (BaseLaserService). Routed through here for the same reason as everything else: a kill the
-- server intends has to land on the number the server is deciding by.
function PlayerVitals.Kill(player: Player)
	local record, humanoid = recordFor(player)
	if not record then
		if humanoid then
			humanoid.Health = 0
		end
		return
	end
	record.Current = 0
	mirror(record, humanoid)
end

-- Change MaxHealth, carrying the current health across at the same FRACTION it was at. That ratio
-- behaviour is lifted from RunBuffService.applyMaxHealth, which is the only caller that changes a
-- player's Max — a raid buff that raises your ceiling shouldn't also be a heal, and losing it on
-- extract shouldn't be a wound.
function PlayerVitals.SetMax(player: Player, newMax: number)
	local record, humanoid = recordFor(player)
	newMax = sanitize(newMax)
	if newMax <= 0 then
		return
	end
	if not record then
		if humanoid then
			local ratio = humanoid.MaxHealth > 0 and (humanoid.Health / humanoid.MaxHealth) or 1
			humanoid.MaxHealth = newMax
			humanoid.Health = math.clamp(newMax * ratio, 0, newMax)
		end
		return
	end
	local ratio = record.Max > 0 and (record.Current / record.Max) or 1
	record.Max = newMax
	record.Current = math.clamp(newMax * ratio, 0, newMax)
	mirror(record, humanoid)
end

Players.PlayerRemoving:Connect(function(player)
	tracked[player.UserId] = nil
end)

return PlayerVitals
