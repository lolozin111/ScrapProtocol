--[[
	DashService.lua
	Owns the real dash-charge count. The dash MOVEMENT is client-side (see DashClient.client.lua —
	a character is simulated on its own client, so the server can't drive its velocity smoothly),
	but the server is the only thing that decides whether a charge exists to spend, exactly like
	MiningService owns "is this swing legal" while the swing animation itself is cosmetic.

	=== MODEL ===
	Per player: `Charges` (0..DashConfig.MaxCharges) and `RechargeStartedAt` (os.clock() when the
	currently-refilling charge began, nil while full). Recharge is computed LAZILY from that
	timestamp whenever something reads or spends a charge (`settle`) rather than ticked by a
	per-player loop — nothing needs to know the count is current except at the moment it's used.

	RequestDash takes no client arguments: a dash never has anything for the client to lie about,
	since the only server-owned fact is "may this player spend one more charge right now."
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DashConfig = require(ReplicatedStorage.Shared.DashConfig)
local RateLimiter = require(script.Parent.RateLimiter)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
-- FindFirstChild, NEVER WaitForChild. This module is required near the top of Main.server.lua's boot
-- list, so a yield here stalls every service after it. That happened on first test: Rojo was still
-- running from before these remotes were added to default.project.json (it only reads that file on
-- start), WaitForChild yielded forever, and PlotService/BaseService never loaded, so the player
-- didn't even spawn on their base. A missing remote now costs the dash, not the whole server.
local RequestDash = Remotes:FindFirstChild("RequestDash")
local StaminaUpdate = Remotes:FindFirstChild("StaminaUpdate")
if not (RequestDash and StaminaUpdate) then
	warn("[DashService] ReplicatedStorage.Remotes is missing RequestDash and/or StaminaUpdate — dashing is DISABLED. They're declared in default.project.json: restart `rojo serve` and reconnect the Studio plugin so Rojo picks them up.")
	return {
		GetCharges = function(_player: Player): number
			return DashConfig.MaxCharges
		end,
	}
end

local DashService = {}

type DashState = {
	Charges: number,
	RechargeStartedAt: number?,
}

-- Keyed by UserId (not Player) so PlayerRemoving cleanup and a lookup after a rejoin both need
-- nothing but the number — same reasoning as RateLimiter's own table, scoped to this module only.
local states: { [number]: DashState } = {}

local function newState(): DashState
	return { Charges = DashConfig.MaxCharges, RechargeStartedAt = nil }
end

local function getState(player: Player): DashState
	local state = states[player.UserId]
	if not state then
		state = newState()
		states[player.UserId] = state
	end
	return state
end

-- Credits every whole RechargeSeconds elapsed since RechargeStartedAt, carrying the leftover
-- fraction forward rather than resetting the clock to `now` — otherwise a player who checks in
-- exactly on a recharge tick would lose the partial progress toward the NEXT one every time.
local function settle(state: DashState, now: number)
	if state.Charges >= DashConfig.MaxCharges then
		state.RechargeStartedAt = nil
		return
	end
	if not state.RechargeStartedAt then
		state.RechargeStartedAt = now
		return
	end

	local elapsed = now - state.RechargeStartedAt
	local gained = math.floor(elapsed / DashConfig.RechargeSeconds)
	if gained <= 0 then
		return
	end

	state.Charges = math.min(DashConfig.MaxCharges, state.Charges + gained)
	if state.Charges >= DashConfig.MaxCharges then
		state.RechargeStartedAt = nil
	else
		state.RechargeStartedAt += gained * DashConfig.RechargeSeconds
	end
end

local function rechargeRemaining(state: DashState, now: number): number
	if state.Charges >= DashConfig.MaxCharges or not state.RechargeStartedAt then
		return 0
	end
	return math.max(0, DashConfig.RechargeSeconds - (now - state.RechargeStartedAt))
end

local function pushUpdate(player: Player, state: DashState, now: number)
	StaminaUpdate:FireClient(player, {
		Charges = state.Charges,
		MaxCharges = DashConfig.MaxCharges,
		-- Seconds remaining, not a clock reading, so the client never needs to reconcile its clock
		-- against the server's — it just counts this number down locally between updates.
		RechargeRemaining = rechargeRemaining(state, now),
		RechargeSeconds = DashConfig.RechargeSeconds,
	})
end

-- For any future system that wants to know "does this player have stamina left" without going
-- through a remote (an upgrade gate, a perk check, etc.).
function DashService.GetCharges(player: Player): number
	local state = states[player.UserId]
	if not state then
		return DashConfig.MaxCharges
	end
	settle(state, os.clock())
	return state.Charges
end

-- I-FRAMES. A Player Attribute (DashConfig.IFrameSeconds' comment — 2026-09-22, "some iframes
-- during the dash") rather than a private table here, for the same reason DepthUpdate's Depth
-- Attribute lives on the block instead of a lookup table: combat code (DamagePipeline et al.) needs
-- to read this, and an Attribute replicates/reads for free without this module having to expose a
-- bespoke getter that every caller has to remember exists. IsInvulnerable below IS that getter
-- anyway — named so combat code reads "DashService.IsInvulnerable(player)" instead of the raw
-- attribute string, but it's just a thin wrapper, not the source of truth.
local DASH_INVULNERABLE_ATTRIBUTE = "DashInvulnerableUntil"

-- Reads the attribute stamped by the grant below. False once IFrameSeconds elapses OR while it's
-- configured to 0 (DashConfig.IFrameSeconds' comment: "Set to 0 to turn i-frames off entirely") —
-- covers both "never stamped" (attribute nil) and "stamped, but in the past" with the same check.
function DashService.IsInvulnerable(player: Player): boolean
	local until_ = player:GetAttribute(DASH_INVULNERABLE_ATTRIBUTE)
	return typeof(until_) == "number" and os.clock() < until_
end

RequestDash.OnServerEvent:Connect(function(player: Player, ...: any)
	-- Deliberately ignores every argument the client sent — see the header. Anything past `player`
	-- here is a modified client trying to pass something; there's nothing legitimate to read.

	-- A slightly SHORTER window than DashConfig.Cooldown (ServerCooldownFactor) so two honest,
	-- back-to-back dashes separated by ordinary network jitter are never the ones rejected here —
	-- the client's own Cooldown already paces the common case.
	local now = os.clock()
	if not RateLimiter.Check(player, "Dash", DashConfig.Cooldown * DashConfig.ServerCooldownFactor) then
		-- Rate-limited, not out of charges: still correct the client's prediction (it may have
		-- mispredicted for an unrelated reason) but this is normal spammed-input traffic, not
		-- something worth a warn() — see the no-charges branch below for the same reasoning.
		local state = getState(player)
		settle(state, now)
		pushUpdate(player, state, now)
		return
	end

	local state = getState(player)
	settle(state, now)

	if state.Charges < 1 then
		-- Spamming the dash key with an empty tank is ordinary play, not a bug report — the
		-- corrective StaminaUpdate below IS the player-visible feedback (their cells read 0/3), so
		-- no toast/warn here would add anything a fully-drained bar doesn't already say.
		pushUpdate(player, state, now)
		return
	end

	local wasFull = state.Charges >= DashConfig.MaxCharges
	state.Charges -= 1
	if wasFull then
		-- The recharge timer only starts once there's a hole to fill; a full bar has nothing
		-- ticking (see `settle`'s early-return), so spending the first charge is what starts it.
		state.RechargeStartedAt = now
	end

	-- The dash is granted at this point (a charge was actually spent) — stamp the i-frame window
	-- now, not earlier: the rate-limit and empty-tank branches above both return before here, and
	-- neither of those should extend/refresh invulnerability for a dash that didn't happen. 0
	-- clears rather than sets a past-dated attribute, matching the config's "set to 0 to turn
	-- i-frames off entirely" — `player:SetAttribute(_, nil)` would just leave whatever was already
	-- there (see InventoryUpdate's own "nil vanishes" idiom elsewhere in this codebase), so an
	-- explicit `or false`-shaped branch is used instead of relying on a bare nil to clear it.
	if DashConfig.IFrameSeconds > 0 then
		player:SetAttribute(DASH_INVULNERABLE_ATTRIBUTE, now + DashConfig.IFrameSeconds)
	else
		player:SetAttribute(DASH_INVULNERABLE_ATTRIBUTE, false)
	end

	pushUpdate(player, state, now)
end)

-- Fresh charges on spawn/respawn (when RefillOnRespawn is true) and always a StaminaUpdate, so the
-- HUD's cells are correct the instant a character loads instead of holding over stale state from a
-- previous life. task.spawn mirrors PlayerSpeed.lua's `track` — not because anything here yields,
-- but so a future change that needs to (e.g. WaitForChild on the Humanoid) doesn't have to remember
-- to add it, and CharacterAdded handlers stay uniform across services.
local function onCharacterAdded(player: Player)
	if DashConfig.RefillOnRespawn then
		states[player.UserId] = newState()
	end
	local state = getState(player)
	local now = os.clock()
	settle(state, now)
	pushUpdate(player, state, now)
end

local function track(player: Player)
	player.CharacterAdded:Connect(function()
		task.spawn(onCharacterAdded, player)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player)
	end
end

Players.PlayerAdded:Connect(track)

-- Anyone already in the server when this module first loads (Studio routinely has the local
-- player present by the time ServerScriptService finishes booting) — same reasoning as
-- PlayerSpeed.lua's identical loop.
for _, player in ipairs(Players:GetPlayers()) do
	track(player)
end

Players.PlayerRemoving:Connect(function(player)
	states[player.UserId] = nil
end)

return DashService
