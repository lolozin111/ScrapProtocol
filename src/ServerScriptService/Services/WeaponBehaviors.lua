--[[
	WeaponBehaviors.lua
	The behaviours behind exotic weapons, looked up by name (CraftingRecipes.Weapons[key].Behavior).

	Same flat-table-of-named-strategies shape as UltimateEffects, EnemyAI.Patterns and
	RobotBehaviors, for the same reason: a new exotic weapon is one function here plus a config
	entry pointing at its name, never an engine change.

	=== WHY THIS IS SEPARATE FROM UltimateEffects ===
	They look alike and do different jobs. An Ultimate is a MOD — one passive, moved between weapons,
	owned independently of any of them. A behaviour is what a specific gun IS: the ExplosiveBow
	without its delayed detonation is a worse Scrap Bow. Merging them would mean a config table where
	half the entries can be equipped and half cannot, which is exactly the kind of "two things sharing
	a shape but not a meaning" that gets one of them broken by a change meant for the other.

	They also compose: an ExplosiveBow can carry Ricochet. Both fire at the same impact, from the
	same place, on separate hooks.

	=== HOOKS ===
	  OnFire  — the trigger was pulled, BEFORE any projectile exists. Return true to suppress the
	            normal shot; the behaviour is then responsible for firing whatever it wants instead.
	  OnHit   — a shot from this weapon landed and damage was applied.

	=== CONTEXT ===
	Everything a behaviour may touch arrives on `ctx`, so none of them reach into the encounter:

	  ctx.Params       the recipe's own BehaviorParams table
	  ctx.Player       who fired
	  ctx.ShotNumber   how many shots this player has fired with this weapon (1-based, persistent
	                   across encounters — a "every 5th shot" gun must not reset when a wave ends)
	  ctx.Origin       muzzle position
	  ctx.Direction    unit aim direction
	  ctx.Spec         the shot spec that is about to be (or just was) fired
	  ctx.FireProjectile(origin, direction, overrides)   fires an extra projectile
	  ctx.Target       OnHit only: the enemy record that was hit
	  ctx.Damage       OnHit only: damage actually dealt, post-pipeline
	  ctx.HitPosition  OnHit only
	  ctx.DealDamage(record, amount, kind)     routes through the normal damage pipeline
	  ctx.ApplyStatus(record, key, overrides)
	  ctx.SpawnGroundEffect(options)           see GroundEffectService.Spawn
	  ctx.Detonate(at, damage, config)         area damage, same as a grenade's blast
	  ctx.Pull(record, toPosition, studs)      drag an enemy toward a point

	WHY ctx.DealDamage RATHER THAN TOUCHING HUMANOIDS: same as UltimateEffects — secondary damage
	still has to run the DamagePipeline, or an exotic would quietly bypass Defense mitigation.

	A missing behaviour name warns once and does nothing, so one bad config entry costs that weapon
	its gimmick rather than the encounter.
]]

local WeaponBehaviors = {}

WeaponBehaviors.OnFire = {}
WeaponBehaviors.OnHit = {}

----------------------------------------------------------------------
-- ExplosiveBow
--
-- "Shoot explosive arrows where it does base damage, and then after some time the arrow explodes and
-- does more damage. The explosion damage scales as more arrows are in enemy before exploding. If one
-- arrow explodes, all other arrows on the enemy explode at the same time, but those explosions do
-- not damage other enemies nearby."
--
-- Deliberately single-target: `Detonate` is not used here, because the spec is explicit that the
-- blast does not splash. What this actually is, mechanically, is a delayed damage bank that pays out
-- superlinearly — so the skill is landing several arrows inside one fuse window rather than spreading
-- them out. Two arrows are worth more than twice one arrow; that is the whole weapon.
----------------------------------------------------------------------

WeaponBehaviors.OnHit.ExplosiveArrow = function(ctx)
	local record = ctx.Target
	local fuse = ctx.Params.FuseSeconds or 2.5

	record.StuckArrows = (record.StuckArrows or 0) + 1

	-- Only the FIRST arrow schedules a detonation. Every later one joins the pending batch, which is
	-- what makes "if one arrow explodes, all other arrows on the enemy explode at the same time" fall
	-- out for free rather than needing to cancel and reschedule timers.
	if record.ArrowFuseRunning then
		return
	end
	record.ArrowFuseRunning = true

	local perArrow = ctx.Damage * (ctx.Params.DamageFraction or 0.9)

	task.delay(fuse, function()
		local count = record.StuckArrows or 0
		record.StuckArrows = 0
		record.ArrowFuseRunning = false

		if count <= 0 then
			return
		end

		-- Superlinear in the arrow count: each arrow past the first adds a bonus fraction to ALL of
		-- them. Three arrows at +40% each is 3 x 1.8, not 3 x 1 — which is what makes stacking them
		-- inside one window worth the risk of the target dying first.
		local scaling = 1 + (count - 1) * (ctx.Params.PerArrowBonus or 0.4)
		ctx.DealDamage(record, perArrow * count * scaling, "Explosion")
	end)
end

----------------------------------------------------------------------
-- StringedBow
--
-- "A bow where the 3rd shot and 4th shot are stringed arrows, where when the 3rd and 4th shots land
-- on different enemies, they will be pulled together into the same place and do bonus damage to each
-- other."
--
-- The pairing is deliberately loose: the 3rd shot remembers its target, and the 4th completes the
-- string if it lands on somebody else. Missing with either simply means no string, which is a clean
-- failure the player can see and understand.
----------------------------------------------------------------------

WeaponBehaviors.OnHit.StringedArrow = function(ctx)
	local first = ctx.Params.FirstShot or 3
	local second = ctx.Params.SecondShot or 4
	local phase = ctx.ShotNumber % (ctx.Params.CycleLength or 4)

	-- Modulo, so the pattern repeats every cycle rather than only working on literal shots 3 and 4.
	if phase == first % (ctx.Params.CycleLength or 4) then
		ctx.SetWeaponState("StringAnchor", ctx.Target)
		return
	end

	if phase ~= second % (ctx.Params.CycleLength or 4) then
		return
	end

	local anchor = ctx.GetWeaponState("StringAnchor")
	ctx.SetWeaponState("StringAnchor", nil)

	-- Same enemy twice is not a string. Neither is a dead or missing anchor — the first arrow's
	-- target may well have died in between.
	if not anchor or anchor == ctx.Target or not ctx.IsAlive(anchor) then
		return
	end

	local anchorPart = anchor.Model and anchor.Model.PrimaryPart
	local targetPart = ctx.Target.Model and ctx.Target.Model.PrimaryPart
	if not anchorPart or not targetPart then
		return
	end

	-- Both dragged to the midpoint, so neither "wins" the tug and the pair ends up somewhere the
	-- player can actually follow up on.
	local midpoint = (anchorPart.Position + targetPart.Position) * 0.5
	ctx.Pull(anchor, midpoint, math.huge)
	ctx.Pull(ctx.Target, midpoint, math.huge)

	-- "Do bonus damage to each other" — each takes the hit, so a string is worth roughly two extra
	-- arrows, and it is worth setting up rather than just firing four shots at one target.
	local bonus = ctx.Damage * (ctx.Params.BonusFraction or 1.5)
	ctx.DealDamage(anchor, bonus, "Explosion")
	ctx.DealDamage(ctx.Target, bonus, "Explosion")
end

----------------------------------------------------------------------
-- Trailblazer
--
-- "When shot it leaves a trail (a line) from the tip of the gun all the way to where it landed
-- (max 100 magnitude), and the line does bleeding damage when touched by enemies."
--
-- Fired on HIT rather than on fire, because the trail has to end where the shot actually stopped —
-- which is not known until it stops. That is only possible at all because projectiles have travel
-- time; under the old hitscan model there was no "where it landed" separate from "where you aimed".
----------------------------------------------------------------------

WeaponBehaviors.OnHit.BleedTrail = function(ctx)
	local maxLength = ctx.Params.MaxLength or 100
	local span = ctx.HitPosition - ctx.Origin

	-- Clamped rather than skipped past the limit: a long shot still gets its first 100 studs of
	-- trail, which is far less surprising than the trail vanishing entirely on exactly the long-range
	-- shots a sniper is for.
	local finish = span.Magnitude > maxLength and (ctx.Origin + span.Unit * maxLength) or ctx.HitPosition

	ctx.SpawnGroundEffect({
		Shape = "Line",
		From = ctx.Origin,
		To = finish,
		Radius = ctx.Params.Radius or 3,
		Duration = ctx.Params.Duration or 6,
		TickInterval = ctx.Params.TickInterval or 1,
		Status = { Key = "Bleed" },
		Color = Color3.fromRGB(220, 60, 60),
	})
end

----------------------------------------------------------------------
-- Hellfire
--
-- "Every 5th shot will be shot upwards where a cartridge will be shot and it will release in the air
-- mini missiles that will fall randomly on the floor, doing AOE damage."
--
-- OnFire and it SUPPRESSES the normal shot (returns true) — the 5th trigger pull is not a bullet
-- plus a cartridge, it is a cartridge instead of a bullet. That is what makes the rhythm readable:
-- four ordinary sniper shots, then one that visibly does something else.
----------------------------------------------------------------------

WeaponBehaviors.OnFire.Hellfire = function(ctx)
	local every = ctx.Params.EveryNthShot or 5
	if ctx.ShotNumber % every ~= 0 then
		return false -- ordinary shot; let the normal path fire it
	end

	local missiles = ctx.Params.MissileCount or 6
	local scatter = ctx.Params.ScatterRadius or 28
	local climb = ctx.Params.BurstHeight or 60
	local damage = (ctx.Spec.Damage or 0) * (ctx.Params.DamageFraction or 0.55)

	-- The cartridge itself: straight up, no contact damage, and a fuse that is its whole purpose.
	-- Fired forward-and-up rather than dead vertical so it visibly leaves the barrel in the direction
	-- you were aiming, which is what connects the burst to the shot for the player.
	local up = (Vector3.new(0, 1, 0) * 3 + ctx.Direction).Unit
	local burstAt = ctx.Origin + up * climb

	ctx.FireProjectile(ctx.Origin, up, {
		Damage = 0,
		OnHitStatus = nil,
		Projectile = {
			Speed = 140, Gravity = 0, Range = climb + 10, Radius = 0.6, Pierce = 0,
			FuseSeconds = climb / 140, NoContactDamage = true,
			Color = Color3.fromRGB(255, 120, 60),
		},
		OnExpire = function(player)
			-- Each missile lands somewhere random inside the scatter, dropped from the burst point.
			-- Independent random offsets rather than a ring: a predictable pattern would let a player
			-- learn exactly where to stand, which is the opposite of "fall randomly".
			for _ = 1, missiles do
				local angle = math.random() * 2 * math.pi
				local distance = scatter * math.sqrt(math.random())
				local landing = burstAt + Vector3.new(
					math.cos(angle) * distance,
					-climb,
					math.sin(angle) * distance)

				ctx.FireProjectile(burstAt, (landing - burstAt).Unit, {
					Damage = damage,
					Projectile = {
						Speed = 120, Gravity = 30, Range = climb * 2, Radius = 0.45, Pierce = 0,
						NoContactDamage = true,
						Color = Color3.fromRGB(255, 90, 40),
					},
					OnExpire = function(missilePlayer, at, spec)
						ctx.Detonate(at, spec.Damage or damage, {
							Radius = ctx.Params.MissileRadius or 10,
							MinMultiplier = 0.4,
						}, missilePlayer)
					end,
				}, player)
			end
		end,
	})

	return true -- suppress the ordinary shot
end

----------------------------------------------------------------------
-- Dispatch
----------------------------------------------------------------------

local warnedMissing: { [string]: boolean } = {}

-- Runs `behaviorName` for `hook` if it exists. Returns whatever the behaviour returned, which for
-- OnFire is "did you already handle the shot" — so a missing or erroring behaviour falls through to
-- the ordinary shot rather than leaving the player unable to fire at all.
function WeaponBehaviors.Fire(hook: string, behaviorName: string?, ctx): boolean
	if not behaviorName then
		return false
	end
	local table_ = WeaponBehaviors[hook]
	local fn = table_ and table_[behaviorName]
	if not fn then
		local id = hook .. "." .. tostring(behaviorName)
		if not warnedMissing[id] then
			warnedMissing[id] = true
			warn(("[WeaponBehaviors] No %q behaviour named %q — that weapon fires as an ordinary gun. Add it here or fix the Behavior name in CraftingRecipes."):format(hook, tostring(behaviorName)))
		end
		return false
	end

	-- pcall'd for the same reason UltimateEffects is: this is content-shaped code that gets edited
	-- often, and a bad one should cost its own gimmick, not the player's shot.
	local ok, result = pcall(fn, ctx)
	if not ok then
		warn(("[WeaponBehaviors] %s errored: %s"):format(behaviorName, tostring(result)))
		return false
	end
	return result == true
end

return WeaponBehaviors
