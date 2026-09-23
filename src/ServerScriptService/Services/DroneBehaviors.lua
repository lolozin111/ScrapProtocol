--[[
	DroneBehaviors.lua
	What each Drone Core actually does, looked up by name (DroneConfig.Cores[key].Behavior).

	Fourth file in this codebase with the flat-table-of-named-strategies shape, after
	EnemyAI.Patterns, RobotBehaviors, UltimateEffects and WeaponBehaviors — a new Core is one
	function here plus a config entry, never a change to DroneService.

	=== TWO KINDS OF BEHAVIOUR ===
	  Tick   runs on the Core's own TickInterval, wherever the player is
	  OnMine runs when the player successfully mines something
	A Core implements whichever it needs. Scavenger has no Tick at all (its TickInterval is 0);
	Combat, Support and Recon have no OnMine. Splitting by WHEN rather than lumping everything into
	one function keeps a mining Core from being asked to think about combat.

	=== CONTEXT ===
	  ctx.Params        the Core's own Params table
	  ctx.Player        who owns the drone
	  ctx.Position      where the drone currently is
	  ctx.Character / ctx.Humanoid   the player's, may be nil mid-respawn
	  ctx.EnemiesNear(radius)        live enemies near the drone, or {} outside a fight
	  ctx.DealDamage(record, amount, kind)
	  ctx.ApplyStatus(record, key, overrides)
	  ctx.Mark(record, duration)     highlight a target so it is visible through walls
	  ctx.FaceTarget(record)         turn the drone's body toward something, briefly
	  ctx.ShowHeal(amount)           a floating heal number over the owner
	  ctx.Toast(message)             a line on the owner's screen
	  ctx.SecondsSinceDamaged()      how long since the owner last took a hit

	Everything routes back through the normal pipelines, same rule as every other strategy table
	here: a drone must not be able to bypass DamagePipeline any more than an Ultimate can.
]]

-- The only require here: a pure bookkeeping module with no requires of its own, so it can't form a
-- cycle with DroneService (which requires this file).
local RaidHealBudget = require(script.Parent.RaidHealBudget)
-- The server's own copy of the player's HP; a pass-through to the Humanoid outside a raid. See
-- PlayerVitals.lua's header (2026-09-23 exploit review, F3).
local PlayerVitals = require(script.Parent.PlayerVitals)

local DroneBehaviors = {}

DroneBehaviors.Tick = {}
DroneBehaviors.OnMine = {}

----------------------------------------------------------------------
-- Combat
--
-- Picks the nearest live enemy and shoots it. Flat damage from Params rather than a fraction of the
-- player's weapon: a companion that scales off your gun is a damage multiplier in disguise, and
-- would make the Core mandatory on a strong weapon and pointless on a weak one — the opposite of a
-- sidegrade you choose.
----------------------------------------------------------------------

DroneBehaviors.Tick.Combat = function(ctx)
	local enemies = ctx.EnemiesNear(ctx.Params.Range or 90)
	if #enemies == 0 then
		return
	end

	-- Nearest, so it behaves predictably and visibly commits to a target the player can see it
	-- shooting, rather than appearing to fire at random into a crowd.
	local best, bestDistance = nil, math.huge
	for _, record in ipairs(enemies) do
		local part = record.Model and record.Model.PrimaryPart
		if part then
			local distance = (part.Position - ctx.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = record, distance
			end
		end
	end

	if best then
		ctx.FaceTarget(best)
		ctx.DealDamage(best, ctx.Params.Damage or 14, "Drone")
	end
end

----------------------------------------------------------------------
-- Support
--
-- Tops the player back up BETWEEN fights, not during one. Without the suppression window it would
-- quietly out-heal chip damage and make waves unlosable, which is a much worse outcome than being
-- slightly less convenient.
----------------------------------------------------------------------

DroneBehaviors.Tick.Support = function(ctx)
	local humanoid = ctx.Humanoid
	if not humanoid then
		return
	end
	-- Health numbers come from PlayerVitals, not the Humanoid: this heal is budgeted per room and
	-- per map inside a raid, and "how far below full am I" is what decides how much budget gets
	-- spent — so a client-written Health would buy real healing out of a fake deficit. Outside a
	-- raid PlayerVitals passes straight through to the Humanoid, so the drone's between-fights
	-- behaviour in the world is unchanged. ctx.Player can be nil on a stray tick, which is why the
	-- old Humanoid reads stay as the fallback rather than assuming a player is always there.
	local currentHealth, maxHealth
	if ctx.Player then
		currentHealth, maxHealth = PlayerVitals.Get(ctx.Player)
	else
		currentHealth, maxHealth = humanoid.Health, humanoid.MaxHealth
	end
	if currentHealth <= 0 then
		return
	end
	if currentHealth >= maxHealth then
		return -- nothing to do; skip the heal number so it isn't spamming "0" at full health
	end

	if ctx.SecondsSinceDamaged() < (ctx.Params.SuppressedForSeconds or 4) then
		return
	end

	local amount = maxHealth * (ctx.Params.HealFraction or 0.04)
	local healed = math.min(amount, maxHealth - currentHealth)

	-- In a raid, a hard budget on top (DroneConfig's RaidRoomHealCap / RaidMapHealCap, counted by
	-- RaidHealBudget) so the drone can't make Heal rooms pointless. nil outside a raid = no cap.
	local budget = ctx.Player and RaidHealBudget.Get(ctx.Player)
	if budget then
		local roomLeft = maxHealth * (ctx.Params.RaidRoomHealCap or 1) - budget.NodeHealed
		local mapLeft = maxHealth * (ctx.Params.RaidMapHealCap or 1) - budget.MapHealed
		local left = math.min(roomLeft, mapLeft)
		if left <= 0.01 then
			-- Said ONCE per room / once per map, not every tick: a drone that just stops healing with
			-- no explanation is indistinguishable from a broken one (the project's silent-failure rule).
			if mapLeft <= roomLeft and not budget.ToastedMap then
				budget.ToastedMap = true
				budget.ToastedNode = true
				ctx.Toast("Support Core spent for this map — find a Heal room")
			elseif not budget.ToastedNode then
				budget.ToastedNode = true
				ctx.Toast("Support Core spent for this room")
			end
			return
		end
		healed = math.min(healed, left)
		budget.NodeHealed += healed
		budget.MapHealed += healed
	end

	if ctx.Player then
		PlayerVitals.Heal(ctx.Player, healed)
	else
		humanoid.Health += healed
	end
	ctx.ShowHeal(healed)
end

----------------------------------------------------------------------
-- Recon
--
-- Marks everything nearby: visible through walls, and taking more damage from EVERY source rather
-- than just from you. A personal damage bonus would make this a worse Combat Core; a debuff on the
-- target makes it the Core you run when your turrets and robots are doing the work.
----------------------------------------------------------------------

DroneBehaviors.Tick.Recon = function(ctx)
	for _, record in ipairs(ctx.EnemiesNear(ctx.Params.Range or 120)) do
		ctx.ApplyStatus(record, "Marked")
		ctx.Mark(record, ctx.Params.MarkDuration or 4)
	end
end

----------------------------------------------------------------------
-- Scavenger
--
-- Event-driven rather than ticked: it reacts to mining, so a timer would either fire when nothing
-- had been mined or miss hits between ticks.
--
-- A CHANCE of doubling a haul, not a flat yield multiplier. A multiplier is invisible — you would
-- have no way to know it was working — where an occasional visible windfall is a moment you notice.
-- Same lesson the damage numbers taught: an effect nobody can see gets reported as broken.
----------------------------------------------------------------------

DroneBehaviors.OnMine.Scavenger = function(ctx)
	if math.random() >= (ctx.Params.Chance or 0.25) then
		return 0
	end

	local bonus = math.floor(ctx.Yield * (ctx.Params.BonusMultiplier or 1) + 0.5)
	if bonus > 0 then
		ctx.Toast(("Scavenger Core salvaged %d extra %s"):format(bonus, ctx.OreDisplayName))
	end
	return bonus
end

----------------------------------------------------------------------
-- Dispatch
----------------------------------------------------------------------

local warnedMissing: { [string]: boolean } = {}

-- Returns the behaviour's own return value (Scavenger's bonus yield), or nil if there was nothing
-- to run. A missing or erroring behaviour costs that Core its effect, never the drone or the mine.
function DroneBehaviors.Fire(hook: string, behaviorName: string?, ctx)
	if not behaviorName then
		return nil
	end
	local table_ = DroneBehaviors[hook]
	local fn = table_ and table_[behaviorName]
	if not fn then
		-- Only warned for a hook the Core was expected to implement. A Combat Core having no OnMine
		-- is normal, so DroneService only calls hooks it has a reason to.
		local id = hook .. "." .. tostring(behaviorName)
		if not warnedMissing[id] then
			warnedMissing[id] = true
			warn(("[DroneBehaviors] No %q behaviour named %q — that Drone Core does nothing on this hook. Add it here or fix the Behavior name in DroneConfig."):format(hook, tostring(behaviorName)))
		end
		return nil
	end

	local ok, result = pcall(fn, ctx)
	if not ok then
		warn(("[DroneBehaviors] %s errored: %s"):format(behaviorName, tostring(result)))
		return nil
	end
	return result
end

return DroneBehaviors
