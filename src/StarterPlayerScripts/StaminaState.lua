--[[
	StaminaState.lua
	The client's PREDICTED mirror of DashService's charge count, shared between DashClient (which
	writes it, on both a local spend and every server StaminaUpdate) and MainHud (which only reads
	it, to draw the stamina cells). A BindableEvent would work too, but a small shared module needs
	no extra plumbing to hand a getter to a panel that already `require`s things by path — same
	shape as PlayerSpeed.lua being the one owner server-side, just for predicted rather than
	authoritative state.

	Recharge is computed the same lazy way DashService computes it, so the HUD's countdown matches
	what the server will actually decide when the next dash is attempted — see DashConfig's header
	on why these numbers are shared instead of duplicated.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DashConfig = require(ReplicatedStorage.Shared.DashConfig)

local StaminaState = {}

-- Fired with no arguments whenever Charges/RechargeStartedAt changes, so a listener just re-reads
-- the getters below rather than being handed a payload to keep in sync itself.
StaminaState.Changed = Instance.new("BindableEvent")

StaminaState.Charges = DashConfig.MaxCharges
StaminaState.MaxCharges = DashConfig.MaxCharges
StaminaState.RechargeSeconds = DashConfig.RechargeSeconds

-- os.clock() the currently-refilling charge began, nil while full — same shape as DashService's
-- server-side state, deliberately, so `RechargeRemaining` below is one formula on both sides.
local rechargeStartedAt: number? = nil

-- Wholesale-replaced by every StaminaUpdate (see DashClient), which is the correction for any
-- local misprediction — this is not merged into the existing state, it REPLACES it.
function StaminaState.ApplyServerUpdate(charges: number, maxCharges: number, rechargeRemaining: number, rechargeSeconds: number)
	StaminaState.Charges = charges
	StaminaState.MaxCharges = maxCharges
	StaminaState.RechargeSeconds = rechargeSeconds
	if rechargeRemaining > 0 then
		rechargeStartedAt = os.clock() - (rechargeSeconds - rechargeRemaining)
	else
		rechargeStartedAt = nil
	end
	StaminaState.Changed:Fire()
end

-- Called by DashClient the instant it locally predicts a spend, so the HUD dims a cell on the
-- same frame as the dash rather than waiting a round trip for StaminaUpdate to confirm it.
function StaminaState.PredictSpend()
	local wasFull = StaminaState.Charges >= StaminaState.MaxCharges
	StaminaState.Charges = math.max(0, StaminaState.Charges - 1)
	if wasFull then
		rechargeStartedAt = os.clock()
	end
	StaminaState.Changed:Fire()
end

-- Advances the local mirror the same way DashService's `settle` advances the server's, so charges
-- climb back in smoothly between StaminaUpdates instead of jumping only when a correction arrives.
-- Callers (DashClient's render loop, MainHud's) call this before reading Charges/RechargeRemaining.
function StaminaState.Settle()
	if StaminaState.Charges >= StaminaState.MaxCharges then
		rechargeStartedAt = nil
		return
	end
	if not rechargeStartedAt then
		rechargeStartedAt = os.clock()
		return
	end

	local elapsed = os.clock() - rechargeStartedAt
	local gained = math.floor(elapsed / StaminaState.RechargeSeconds)
	if gained <= 0 then
		return
	end

	StaminaState.Charges = math.min(StaminaState.MaxCharges, StaminaState.Charges + gained)
	if StaminaState.Charges >= StaminaState.MaxCharges then
		rechargeStartedAt = nil
	else
		rechargeStartedAt += gained * StaminaState.RechargeSeconds
	end
	StaminaState.Changed:Fire()
end

function StaminaState.RechargeRemaining(): number
	if StaminaState.Charges >= StaminaState.MaxCharges or not rechargeStartedAt then
		return 0
	end
	return math.max(0, StaminaState.RechargeSeconds - (os.clock() - rechargeStartedAt))
end

return StaminaState
