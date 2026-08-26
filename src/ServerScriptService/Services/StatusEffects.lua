--[[
	StatusEffects.lua
	Applies, ticks and answers questions about status effects on enemies. See StatusConfig.lua for
	the definitions and for why this is one shared system rather than seven half-implementations.

	State lives on the enemy RECORD (record.Status), not on the Humanoid or as attributes:
	  - records are already the per-encounter mutable thing CombatEncounterService owns
	  - they die with the encounter, so nothing leaks into the next wave
	  - it costs no replication, and no client needs to know

	Shape:
	  record.Status = {
	      Bleed = { Stacks = 2, ExpiresAt = <os.clock>, NextTickAt = <os.clock> },
	      Stun  = { Stacks = 1, ExpiresAt = <os.clock> },
	  }

	Tick() is called once per enemy per encounter tick, from the same loop that drives EnemyAI —
	one clock, one place, so a status can never tick at a different rate in raids than in base
	defense.

	DAMAGE FROM STATUSES is dealt through a caller-supplied `dealDamage` rather than
	Humanoid:TakeDamage directly, so damage-over-time still runs the normal DamagePipeline. A bleed
	that bypassed mitigation would be strictly better than a bullet against armoured targets, which
	is not what "bleed" is supposed to mean.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StatusConfig = require(ReplicatedStorage.Shared.StatusConfig)

local StatusEffects = {}

local function ensure(record)
	if not record.Status then
		record.Status = {}
	end
	return record.Status
end

-- Applies (or refreshes/stacks) `key` on `record`.
--
-- `overrides` may carry Duration and Stacks, so one status definition can be applied with
-- different intensity by different sources — Leg Breaker's 5-second stun and Frostbite's
-- 2-second escalation stun are the same status, applied for different lengths.
function StatusEffects.Apply(record, key: string, overrides)
	local def = StatusConfig.Get(key)
	if not def then
		return
	end
	overrides = overrides or {}

	local statuses = ensure(record)
	local now = os.clock()
	local existing = statuses[key]

	local addStacks = overrides.Stacks or 1
	local maxStacks = def.MaxStacks or 1
	local duration = overrides.Duration or def.Duration or 0

	if existing then
		local wasAtCap = existing.Stacks >= maxStacks
		existing.Stacks = math.min(existing.Stacks + addStacks, maxStacks)
		-- Re-applying at cap only extends the timer when the status says so. Without this a status
		-- could be held forever by one early hit, which defeats the "it runs off if you stop
		-- applying it" design the stacking statuses are built around.
		if def.RefreshOnStack or not wasAtCap then
			existing.ExpiresAt = now + duration
		end
	else
		statuses[key] = {
			Stacks = math.min(addStacks, maxStacks),
			ExpiresAt = now + duration,
			NextTickAt = def.TickInterval and (now + def.TickInterval) or nil,
		}
	end

	-- Escalation: a status that turns into a different one at full stacks (Frostbite -> Stun). Done
	-- here rather than in whatever applied it, so every source of Frostbite escalates identically.
	local current = statuses[key]
	if def.EscalatesTo and def.EscalatesAtStacks and current.Stacks >= def.EscalatesAtStacks then
		current.Stacks = 0 -- consumed by the escalation; the status itself falls off
		current.ExpiresAt = 0
		StatusEffects.Apply(record, def.EscalatesTo, { Duration = def.EscalateDuration })
	end
end

-- Advances every status on `record`: expires what's over, and deals damage-over-time through
-- `dealDamage(record, amount)`.
function StatusEffects.Tick(record, now: number, dealDamage)
	local statuses = record.Status
	if not statuses then
		return
	end

	for key, state in pairs(statuses) do
		if now >= state.ExpiresAt or state.Stacks <= 0 then
			statuses[key] = nil
		else
			local def = StatusConfig.Get(key)
			if def and def.TickInterval and def.DamagePerStackPerTick and state.NextTickAt and now >= state.NextTickAt then
				state.NextTickAt = now + def.TickInterval

				-- Flat per stack, plus an optional compounding bonus so a status can be designed to
				-- reward maintaining stacks rather than scaling linearly (see Poison).
				local perStack = def.DamagePerStackPerTick
				local bonus = def.StackDamageBonus or 0
				local damage = perStack * state.Stacks * (1 + bonus * math.max(state.Stacks - 1, 0))
				if damage > 0 and dealDamage then
					dealDamage(record, damage)
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Queries — everything that reads status state goes through these rather than poking record.Status
-- directly, so the storage shape stays this file's business.
----------------------------------------------------------------------

function StatusEffects.Has(record, key: string): boolean
	local state = record.Status and record.Status[key]
	return state ~= nil and state.Stacks > 0 and os.clock() < state.ExpiresAt
end

function StatusEffects.StackCount(record, key: string): number
	local state = record.Status and record.Status[key]
	if not state or os.clock() >= state.ExpiresAt then
		return 0
	end
	return state.Stacks
end

-- True if this enemy can neither move nor attack. Checked by EnemyAI before it does either.
function StatusEffects.IsStunned(record): boolean
	if not record.Status then
		return false
	end
	for key, state in pairs(record.Status) do
		local def = StatusConfig.Get(key)
		if def and def.PreventsAction and state.Stacks > 0 and os.clock() < state.ExpiresAt then
			return true
		end
	end
	return false
end

-- Combined movement multiplier from every slowing status. Multiplicative, so two slows compound
-- rather than the larger simply winning.
function StatusEffects.GetSpeedMultiplier(record): number
	if not record.Status then
		return 1
	end
	local multiplier = 1
	local now = os.clock()
	for key, state in pairs(record.Status) do
		local def = StatusConfig.Get(key)
		if def and def.SpeedMultiplier and state.Stacks > 0 and now < state.ExpiresAt then
			multiplier *= def.SpeedMultiplier
		end
	end
	return multiplier
end

-- Combined defence multiplier from armour-shredding statuses. Each stack multiplies, so "loses 50%
-- of their defense" twice leaves 25%, and a full strip is expressible as a multiplier of 0 rather
-- than needing its own flag.
function StatusEffects.GetDefenseMultiplier(record): number
	if not record.Status then
		return 1
	end
	local multiplier = 1
	local now = os.clock()
	for key, state in pairs(record.Status) do
		local def = StatusConfig.Get(key)
		if def and def.DefenseMultiplierPerStack and state.Stacks > 0 and now < state.ExpiresAt then
			multiplier *= (def.DefenseMultiplierPerStack ^ state.Stacks)
		end
	end
	return multiplier
end

return StatusEffects
