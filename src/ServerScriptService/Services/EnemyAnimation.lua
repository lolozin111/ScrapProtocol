--[[
	EnemyAnimation.lua
	EnemyAI.Patterns.Animated's actual brain (see that pattern in EnemyAI.lua, and
	EnemyConfig.BossTypes.VoidwakenHulk for the config shape this file reads).

	=== WHY MARKER-TIMED, FIST-MEASURED DAMAGE ===
	Every other AI pattern in EnemyAI.lua decides "did this land" from a single number: the horizontal
	distance between two roots (Chaser's ContactRange, Slam's SlamRadius). That works because those
	hits are either an even ring around the enemy or a ground-based AoE — the root itself IS the
	meaningful point. A boss swinging an actual fist is a different shape of problem: the Hulk's
	HumanoidRootPart sits roughly 20 studs above where a standing player's feet are, so a check against
	his ROOT distance can never connect at any range that looks like a punch actually landing — the
	root is nowhere near the fist. The animation itself already knows exactly when the fist is at its
	furthest reach; an animation marker just tells this file the instant to look, and a fist Attachment
	tells it where to look FROM. Nothing here invents timing or reach math independent of the artist's
	own animation — it reads the animation's own opinion about both.

	Kind "Impact" is a single instant: reached the marker, check the fist-to-target distance once.
	Kind "Sweep" is a window: reached <key>Start, keep checking every Heartbeat frame, stop at
	<key>End — for an attack whose fist stays dangerous across a swing's arc rather than at one frame,
	same idea as a melee weapon's swing window elsewhere in games with real hitboxes. Both kinds are
	read from EnemyConfig's AnimationHits, keyed by the exact marker name typed into the Animation
	Editor — get that string wrong and the marker never reaches this file, which is exactly the failure
	mode onAttackStopped's own warn (see below) exists to catch.

	Markers are a property of the PUBLISHED animation asset, not of anything in this repo — they live
	on the Roblox asset itself, set in Studio's Animation Editor. This matters because a re-import from
	Blender (a new export replacing the existing published animation) does NOT carry markers over; they
	have to be re-added by hand afterward, in Studio, every time. If a Hulk attack suddenly stops
	dealing damage after an animation update, check for exactly that before suspecting this file.

	=== SHAPE ===
	Called once per tick per enemy from EnemyAI.Patterns.Animated, same "one loop iterates every live
	thing" convention as everywhere else in this codebase — this function does one tick's worth of
	thinking and returns, it is not itself a loop. `context` is CombatEncounterService's aiContext (see
	EnemyAI.lua's header); this file specifically needs the two RAID-ONLY fields, TargetPart and
	TargetPlayer, because its own damage doesn't resolve from this loop's polling — it resolves from
	animation marker signals, which fire ASYNCHRONOUSLY, between ticks. By the time one fires,
	context.TargetPosition is however-stale a snapshot from whichever tick last ran; TargetPart is a
	live Instance a marker callback can read at the actual instant it fires. AIPattern = "Animated"
	only ever spawns in a raid (see EnemyConfig's BossTypes comment), so this is safe to lean on, but
	every read below still checks Parent first exactly like resolveAndApplyDamage's own guards do,
	rather than assuming a raid-only field is always live.

	Must NEVER require EnemyAI — that file requires this one, and Lua's own module cache would just
	hand back a half-initialized table on the reverse edge, silently breaking whichever module happened
	to load second. `EnemyAI.Patterns.Animated` passes its OWN Chaser function in as `fallbackPattern`
	instead, so this file never needs to know EnemyAI.Patterns exists at all.

	=== MISSING ART NEVER BREAKS THE LOOP ===
	Same project-wide rule as everywhere else that clones optional content: an empty AnimationId, a
	failed LoadAnimation, a missing Animator, a missing Attachment, or an EnemyConfig entry with no
	AnimationHits at all degrade gracefully — one warn() each, the FIRST time, keyed so a tick loop
	calling this dozens of times a second can't flood Output — and this enemy type falls back to plain
	EnemyAI.Patterns.Chaser (still a working, if less interesting, enemy) rather than throwing from
	inside the tick loop and stranding the whole encounter the way an unguarded pattern lookup would.
]]

local RunService = game:GetService("RunService")

local StatusEffects = require(script.Parent.StatusEffects)
local PlayerSpeed = require(script.Parent.PlayerSpeed)

local EnemyAnimation = {}

-- Mirrors EnemyAI.lua's own MOVE_THINK_INTERVAL / SPAWN_GRACE_SECONDS exactly — kept as a separate
-- copy rather than shared, because EnemyAI's are private locals in a module this file must never
-- require (see header). If either tuning number changes there, change it here too.
local MOVE_THINK_INTERVAL = 0.5
local SPAWN_GRACE_SECONDS = 1

-- The PlayerSpeed key every animation-hit slow is filed under. One key, not one per attack, per
-- PlayerSpeed's own "one per SYSTEM, not one per event" rule — a second hit while the first slow is
-- still ticking REPLACES it rather than stacking (see applySlow below), which is what "one key"
-- buys for free.
local SLOW_KEY = "EnemyHitSlow"

-- Warn-once buckets, all keyed so a tick loop calling this many times a second can't flood Output.
-- Keyed by TypeKey alone where the failure is type-wide (every Hulk shares one EnemyConfig entry);
-- keyed by "TypeKey/slot" or "TypeKey/name" where a type could plausibly have more than one thing
-- go wrong independently (several empty animation slots, several missing attachments).
local warnedSlot = {}
local warnedFallback = {}
local warnedMissingAttachment = {}
local warnedUnknownKind = {}
local warnedMarkerMismatch = {}

-- Per-player token for applySlow's "latest hit wins, never stacks" cleanup below.
local slowTokens = {}

local function warnOnce(bucket: { [string]: boolean }, key: string, message: string)
	if bucket[key] then
		return
	end
	bucket[key] = true
	warn(message)
end

-- The animated fist's CURRENT world position — not its rest pose. A plain Attachment's WorldPosition
-- follows wherever the rig is standing right now, which is the T-pose/idle pose whenever nothing is
-- reading it mid-swing; a Bone's TransformedWorldCFrame is the pose AFTER the currently-playing
-- animation has moved it, which is the whole reason this file measures from a fist Attachment at all
-- (see this file's header). Attachment.Parent is the Bone here per the boss rig's own setup (FistR
-- parented under Lower_Arm.R, FistL under Hand.L) — a plain BasePart-parented attachment (no bones at
-- all) falls through to WorldPosition instead, which is already correct for that case.
local function fistWorldPosition(enemy, attachment: Attachment?): Vector3
	if not attachment or not attachment.Parent then
		local rootPart = enemy.Model and enemy.Model.PrimaryPart
		return rootPart and rootPart.Position or Vector3.new()
	end
	local parent = attachment.Parent
	if parent:IsA("Bone") then
		return (parent.TransformedWorldCFrame * attachment.CFrame).Position
	end
	return attachment.WorldPosition
end

-- The live equivalent of context.TargetPosition — see this file's header on why marker callbacks
-- need it. Falls back to the plain snapshot when there's no live part to read (a wave's context has
-- neither TargetPart nor TargetPlayer at all, and this pattern is boss-only besides, but every read
-- still checks rather than assuming).
local function resolveTargetPosition(context): Vector3?
	if context.TargetPart and context.TargetPart.Parent then
		return context.TargetPart.Position
	end
	return context.TargetPosition
end

-- Refresh, never stack — a second hit while the first slow is still counting down REPLACES it with
-- the new hit's own multiplier/duration outright, per EnemyConfig's own comment on AnimationHits.
-- Stacking would let a combo that lands every hit pin the player at the harshest slow for the full
-- duration of every hit added together, chaining for as long as the combo does; refreshing means the
-- slow's length is always "however long since the LAST hit landed," which is the intended read of a
-- boss that's actively beating on you versus one that tagged you once and moved on.
local function applySlow(player: Player, multiplier: number, seconds: number)
	local userId = player.UserId
	local token = (slowTokens[userId] or 0) + 1
	slowTokens[userId] = token
	PlayerSpeed.Set(player, SLOW_KEY, multiplier)
	task.delay(seconds, function()
		-- Only clear if nothing re-slowed the player since this delay was scheduled — otherwise an
		-- earlier hit's expiry would fire AFTER a later hit's and erase the later slow prematurely.
		if slowTokens[userId] == token then
			PlayerSpeed.Set(player, SLOW_KEY, nil)
			slowTokens[userId] = nil
		end
	end)
end

-- The one place an AnimationHits entry actually deals damage — routes through context.DamageTarget
-- exactly like every other pattern in EnemyAI.lua, never Humanoid:TakeDamage directly, so a Shield
-- still absorbs these hits first like it does contact damage and Slam's impact.
local function applyHit(enemy, spec, context)
	context.DamageTarget(spec.Damage * (enemy.DamageMultiplier or 1))
	if context.TargetPlayer and spec.SlowMultiplier and spec.SlowSeconds then
		applySlow(context.TargetPlayer, spec.SlowMultiplier, spec.SlowSeconds)
	end
end

----------------------------------------------------------------------
-- DebugHitboxes visuals — Studio-only aid (EnemyConfig's own comment: "leave false when shipping"),
-- same "missing art never breaks the loop, and neither does present debug art" spirit: none of this
-- can throw the tick loop, it only ever draws a sphere and prints to Output.
----------------------------------------------------------------------

local function debugColor(landed: boolean): Color3
	return landed and Color3.fromRGB(220, 60, 60) or Color3.fromRGB(255, 255, 255)
end

local function newDebugPart(position: Vector3, reach: number, landed: boolean): BasePart
	local part = Instance.new("Part")
	part.Name = "EnemyAnimationDebugHit"
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Transparency = 0.8
	part.Color = debugColor(landed)
	part.Size = Vector3.new(reach * 2, reach * 2, reach * 2)
	part.CFrame = CFrame.new(position)
	part.Parent = workspace
	return part
end

-- Impact: one throwaway sphere per marker — there's no window object to hang its lifetime off like
-- Sweep has below, so a timer is the only teardown available.
local function debugImpact(position: Vector3, reach: number, landed: boolean)
	local part = newDebugPart(position, reach, landed)
	task.delay(0.3, function()
		if part.Parent then
			part:Destroy()
		end
	end)
end

-- Sweep: ONE part reused for the whole window, moved every frame, instead of one per frame — a
-- Heartbeat-rate stream of throwaway Parts would flood the workspace for however long the window
-- stays open. Destroyed by closeWindow below, alongside the window itself.
local function updateSweepDebugPart(window, position: Vector3, reach: number, landed: boolean)
	if not window.DebugPart then
		window.DebugPart = newDebugPart(position, reach, landed)
	else
		window.DebugPart.CFrame = CFrame.new(position)
		window.DebugPart.Color = debugColor(landed)
		window.DebugPart.Size = Vector3.new(reach * 2, reach * 2, reach * 2)
	end
end

----------------------------------------------------------------------
-- Sweep windows — a Heartbeat connection between <key>Start and <key>End that checks the fist every
-- frame, so a swing that stays dangerous across an arc (not just one instant) can catch a target
-- anywhere along it, while HitTargets below still guarantees at most one hit per target per window.
----------------------------------------------------------------------

local function closeWindow(anim, key: string)
	local window = anim.OpenWindows[key]
	if not window then
		return
	end
	if window.Connection then
		window.Connection:Disconnect()
	end
	if window.DebugPart and window.DebugPart.Parent then
		window.DebugPart:Destroy()
	end
	anim.OpenWindows[key] = nil
	if anim.DebugHitboxes then
		-- Deliberately not printed every frame (see this file's header on print volume) — only the
		-- moment a swing's window actually closes, alongside the per-hit print in sweepStep below.
		print(("[EnemyAnimation] %s %s window closed"):format(tostring(anim.TypeKey), key))
	end
end

-- Safe to call while iterating anim.OpenWindows with pairs(): closeWindow only ever clears the
-- CURRENT key, never adds one, and clearing the current key mid-pairs()-iteration is the one mutation
-- Lua's own semantics guarantee is safe.
local function closeAllWindows(anim)
	for key in pairs(anim.OpenWindows) do
		closeWindow(anim, key)
	end
end

local function sweepStep(enemy, anim, key: string, hit, window)
	if not enemy.Model or not enemy.Model.Parent or not enemy.Humanoid or enemy.Humanoid.Health <= 0 then
		-- The enemy died mid-swing. Nothing else in this file polls for that (unlike EnemyAI's own
		-- patterns, which just stop being called once isEnemyAlive drops the record) because this
		-- Heartbeat connection keeps firing on its own schedule regardless — so it has to notice and
		-- tear itself down here instead of leaking a connection that outlives its enemy forever.
		closeWindow(anim, key)
		return
	end
	local context = anim.Context
	if not context then
		return
	end
	local targetPosition = resolveTargetPosition(context)
	if not targetPosition then
		return
	end

	local fistPosition = fistWorldPosition(enemy, hit.Attachment)
	local distance = (fistPosition - targetPosition).Magnitude
	local landed = distance <= hit.Spec.Reach

	-- Keyed by the live target Instance itself (falling back to a fixed string when there's none —
	-- a wave's context carries no TargetPart) so THIS target can't be hit twice by one swing no
	-- matter how many consecutive frames it stays inside Reach, while a hypothetical second target
	-- (not reachable today — raids are solo — but keeps this correct if that ever changes) still could
	-- be, independently.
	local targetKey = context.TargetPart or "target"
	if landed and not window.HitTargets[targetKey] then
		window.HitTargets[targetKey] = true
		applyHit(enemy, hit.Spec, context)
		if anim.DebugHitboxes then
			print(("[EnemyAnimation] %s %s dist=%.1f reach=%d HIT"):format(tostring(enemy.TypeKey), key, distance, hit.Spec.Reach))
		end
	end

	if anim.DebugHitboxes then
		updateSweepDebugPart(window, fistPosition, hit.Spec.Reach, landed)
	end
end

local function onSweepStart(enemy, anim, key: string, hit)
	-- A second Start while this window's already open (duplicate markers in the animation, or a
	-- re-triggered play) just resets it — same window, fresh HitTargets — rather than layering a
	-- second Heartbeat connection checking the same fist twice.
	closeWindow(anim, key)
	local window = { HitTargets = {} }
	anim.OpenWindows[key] = window
	window.Connection = RunService.Heartbeat:Connect(function()
		sweepStep(enemy, anim, key, hit, window)
	end)
end

local function onSweepEnd(anim, key: string)
	closeWindow(anim, key)
end

local function onImpactMarker(enemy, anim, key: string, hit)
	local context = anim.Context
	if not context or not enemy.Model or not enemy.Model.Parent then
		-- The enemy died/despawned between the marker firing and this callback actually running —
		-- marker signals are queued events, not synchronous calls, so this gap is real.
		return
	end
	local targetPosition = resolveTargetPosition(context)
	if not targetPosition then
		return
	end

	local fistPosition = fistWorldPosition(enemy, hit.Attachment)
	local distance = (fistPosition - targetPosition).Magnitude
	local landed = distance <= hit.Spec.Reach
	if landed then
		applyHit(enemy, hit.Spec, context)
	end
	if anim.DebugHitboxes then
		debugImpact(fistPosition, hit.Spec.Reach, landed)
		print(("[EnemyAnimation] %s %s dist=%.1f reach=%d %s"):format(
			tostring(enemy.TypeKey), key, distance, hit.Spec.Reach, landed and "HIT" or "miss"))
	end
end

----------------------------------------------------------------------
-- Setup — lazy, once per enemy INSTANCE (not once per type), on the first Tick. Builds enemy.Anim.
----------------------------------------------------------------------

local function stopAllTracks(anim)
	if anim.IdleTrack and anim.IdleTrack.IsPlaying then
		anim.IdleTrack:Stop()
	end
	if anim.MoveTrack and anim.MoveTrack.IsPlaying then
		anim.MoveTrack:Stop()
	end
	if anim.CurrentAttack and anim.CurrentAttack.Track.IsPlaying then
		anim.CurrentAttack.Track:Stop()
	end
	anim.CurrentAttack = nil
end

-- The guaranteed teardown: RunRaidCombat destroys the whole enemy folder when a raid ends regardless
-- of how the encounter finished, so Destroying is the one event this file can rely on firing no
-- matter what — unlike Died, which never fires if the encounter is torn down out from under a still-
-- alive boss (a player disconnecting mid-raid, say).
local function teardownAnim(anim)
	closeAllWindows(anim)
	for _, connection in ipairs(anim.Connections) do
		connection:Disconnect()
	end
	anim.Connections = {}
end

-- Builds the "marker names we expected but didn't see" list once at setup, for onAttackStopped's
-- own warn below — a Sweep entry expects BOTH <key>Start and <key>End, an Impact entry just <key>.
local function expectedMarkerNamesList(typeData): string
	local names = {}
	for key, spec in pairs(typeData.AnimationHits) do
		if spec.Kind == "Sweep" then
			table.insert(names, key .. "Start")
			table.insert(names, key .. "End")
		else
			table.insert(names, key)
		end
	end
	table.sort(names)
	return table.concat(names, ", ")
end

-- Connected once per attack track at load (see setupAnim below), fires whenever that track stops for
-- ANY reason — a clean finish, the stun branch's explicit :Stop(), or Destroy.
local function onAttackStopped(enemy, anim, loadedAttack)
	closeAllWindows(anim)
	-- Only the attack CURRENTLY recorded as active gets to stamp cooldown / clear itself. Since only
	-- one attack track is ever playing at a time, a Stopped signal from a track that ISN'T the one
	-- anim.CurrentAttack points at can only be a late/duplicate signal from something that already
	-- handed off — acting on it would re-stamp NextAttackAt or clear a newer attack that's already
	-- started playing.
	if anim.CurrentAttack ~= loadedAttack then
		return
	end
	local now = (anim.Context and anim.Context.Now) or os.clock()
	anim.CurrentAttack = nil
	enemy.NextAttackAt = now + (enemy.AttackCooldown or 0)

	-- The "nothing happens" guard for this whole system: if the animation played start-to-finish and
	-- never reached a single marker this file was listening for, the swing dealt zero damage and
	-- nothing above would ever have said why. Almost always a typo between the marker name typed into
	-- the Animation Editor and the AnimationHits key in EnemyConfig (case-sensitive).
	if loadedAttack.MarkerCount == 0 then
		warnOnce(warnedMarkerMismatch, enemy.TypeKey .. "/" .. loadedAttack.Name,
			("[EnemyAnimation] %s's attack %q played without reaching any of its expected markers (%s) — check the Animation Editor's marker names match those exactly, case-sensitive."):format(
				tostring(enemy.TypeKey), tostring(loadedAttack.Name), anim.ExpectedMarkerNames))
	end
end

-- Empty id or a failed LoadAnimation both just skip the slot — see this file's header on missing
-- art never breaking the loop. pcall'd because LoadAnimation can throw on a malformed/deleted
-- asset id, not just return nil. Shared by setupAnim (the "Animated" pattern) and setupLocomotion
-- (a Chaser's Idle/Move) so the two can't disagree about priority or looping.
local function loadTrack(animator: Animator, typeKey: string, slotName: string, id: string?, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack?
	if not id or id == "" then
		warnOnce(warnedSlot, typeKey .. "/" .. slotName,
			("[EnemyAnimation] %s has no %s animation set — that slot is skipped."):format(tostring(typeKey), slotName))
		return nil
	end
	local asset = Instance.new("Animation")
	asset.AnimationId = id
	local ok, trackOrErr = pcall(function()
		return animator:LoadAnimation(asset)
	end)
	if not ok or not trackOrErr then
		warnOnce(warnedSlot, typeKey .. "/" .. slotName,
			("[EnemyAnimation] %s's %s animation (%s) failed to load — that slot is skipped."):format(tostring(typeKey), slotName, tostring(id)))
		return nil
	end
	trackOrErr.Looped = looped
	-- Forced here rather than trusted from the Animation Editor. Blending only lets a track override
	-- Idle if its Priority is HIGHER, and a walk published at the editor's default priority sits
	-- level with (or under) Idle, so it plays at full weight yet never shows. That is invisible from
	-- the Studio side, so the slot decides the priority, not whatever was picked at publish time.
	trackOrErr.Priority = priority
	return trackOrErr
end

local function setupAnim(enemy)
	local typeKey = enemy.TypeKey
	local typeData = enemy.TypeData
	local model = enemy.Model
	local humanoid = enemy.Humanoid

	local anim = {
		Ready = false,
		TypeKey = typeKey,
		FacingYawOffset = (typeData and typeData.FacingYawOffset) or 0,
		DebugHitboxes = (typeData and typeData.DebugHitboxes) or false,
		UsableAttacks = {},
		Hits = {},
		OpenWindows = {},
		Connections = {},
	}

	if not typeData or not typeData.AnimationHits then
		warnOnce(warnedFallback, typeKey,
			("[EnemyAnimation] %s uses AIPattern \"Animated\" but its EnemyConfig entry has no AnimationHits table — every instance of this type falls back to Chaser."):format(tostring(typeKey)))
		return anim
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		warnOnce(warnedFallback, typeKey,
			("[EnemyAnimation] %s's Humanoid has no Animator child — every instance of this type falls back to Chaser."):format(tostring(typeKey)))
		return anim
	end

	anim.ExpectedMarkerNames = expectedMarkerNamesList(typeData)

	-- Resolved ONCE here rather than re-searched on every hit — a marker can fire many times a
	-- second during a Sweep window, and FindFirstChild(_, true) walks the whole model tree.
	for key, spec in pairs(typeData.AnimationHits) do
		local attachment: Attachment? = nil
		if spec.Kind ~= "Impact" and spec.Kind ~= "Sweep" then
			warnOnce(warnedUnknownKind, typeKey .. "/" .. key,
				("[EnemyAnimation] %s: AnimationHits[%q] has unknown Kind %q — ignoring it."):format(tostring(typeKey), key, tostring(spec.Kind)))
		elseif spec.Attachment then
			local found = model:FindFirstChild(spec.Attachment, true)
			if found and found:IsA("Attachment") then
				attachment = found
			else
				warnOnce(warnedMissingAttachment, typeKey .. "/" .. spec.Attachment,
					("[EnemyAnimation] %s: AnimationHits[%q] names Attachment %q, not found (or not an Attachment) on the model — that hit measures from the root instead."):format(
						tostring(typeKey), key, tostring(spec.Attachment)))
			end
		end
		anim.Hits[key] = { Spec = spec, Attachment = attachment }
	end

	local animations = typeData.Animations or {}

	local function loadSlot(slotName: string, id: string?, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack?
		return loadTrack(animator, typeKey, slotName, id, looped, priority)
	end

	anim.IdleTrack = loadSlot("Idle", animations.Idle, true, Enum.AnimationPriority.Idle)
	if anim.IdleTrack then
		-- Plays immediately and keeps looping underneath everything else; Move/attack tracks load at a
		-- higher Priority (see loadSlot), which is what lets Roblox's own blending override Idle without
		-- this file ever stopping it itself.
		anim.IdleTrack:Play()
	end
	anim.MoveTrack = loadSlot("Move", animations.Move, true, Enum.AnimationPriority.Movement)
	anim.DeathTrack = loadSlot("Death", animations.Death, false, Enum.AnimationPriority.Action)

	for _, attackSpec in ipairs(typeData.Attacks or {}) do
		local track = loadSlot("Attack " .. tostring(attackSpec.Name), attackSpec.AnimationId, false, Enum.AnimationPriority.Action)
		if track then
			local loadedAttack = {
				Name = attackSpec.Name,
				TriggerRange = attackSpec.TriggerRange,
				Weight = attackSpec.Weight,
				Track = track,
				MarkerCount = 0,
			}
			table.insert(anim.UsableAttacks, loadedAttack)

			-- Connected ONCE here, at load time — NOT re-connected every time this attack plays.
			-- GetMarkerReachedSignal fires for every future play of this same AnimationTrack object,
			-- so wiring it per-play would stack one more duplicate connection onto this track with
			-- every single swing for as long as the enemy lives.
			for key, hit in pairs(anim.Hits) do
				if hit.Spec.Kind == "Impact" then
					table.insert(anim.Connections, track:GetMarkerReachedSignal(key):Connect(function()
						loadedAttack.MarkerCount += 1
						onImpactMarker(enemy, anim, key, hit)
					end))
				elseif hit.Spec.Kind == "Sweep" then
					table.insert(anim.Connections, track:GetMarkerReachedSignal(key .. "Start"):Connect(function()
						loadedAttack.MarkerCount += 1
						onSweepStart(enemy, anim, key, hit)
					end))
					table.insert(anim.Connections, track:GetMarkerReachedSignal(key .. "End"):Connect(function()
						onSweepEnd(anim, key)
					end))
				end
				-- Kind already warned about above (once, at Hits-resolution time) if it's unrecognized
				-- — nothing to connect for it here, silently skipped.
			end

			table.insert(anim.Connections, track.Stopped:Connect(function()
				onAttackStopped(enemy, anim, loadedAttack)
			end))
		end
	end

	if #anim.UsableAttacks == 0 then
		warnOnce(warnedFallback, typeKey,
			("[EnemyAnimation] %s has no usable attack animations (every AnimationId empty or failed to load) — every instance of this type falls back to Chaser."):format(tostring(typeKey)))
		return anim
	end

	table.insert(anim.Connections, humanoid.Died:Connect(function()
		closeAllWindows(anim)
		stopAllTracks(anim)
		if anim.DeathTrack then
			anim.DeathTrack:Play()
		end
	end))

	table.insert(anim.Connections, model.Destroying:Connect(function()
		teardownAnim(anim)
	end))

	anim.Ready = true
	return anim
end

----------------------------------------------------------------------
-- EnemyAnimation.Tick — called once per tick per enemy from EnemyAI.Patterns.Animated.
----------------------------------------------------------------------

-- `fallbackPattern` is EnemyAI.Patterns.Chaser, passed in by the caller rather than looked up here —
-- see this file's header on why this module can never require EnemyAI back.
-- A "FacingYawOffset" number Attribute on the live Model wins over the config value, so the right
-- offset can be found by editing it mid-playtest (server view) and watching him turn, instead of a
-- config edit and a restart per guess. Copy the number that works into EnemyConfig afterwards.
local function facingOffset(enemy, anim): number
	local override = enemy.Model and enemy.Model:GetAttribute("FacingYawOffset")
	if typeof(override) == "number" then
		return override
	end
	return anim.FacingYawOffset
end

----------------------------------------------------------------------
-- Turning. His facing is owned here, not by Humanoid.AutoRotate: AutoRotate points the
-- HumanoidRootPart's LookVector along the walk, and this rig's root front isn't the mesh's front, so
-- he crawled backwards (FacingYawOffset corrects that). The turn itself is an AlignOrientation (see
-- startTurning): smooth between AI ticks, and it doesn't fight the Humanoid's walking the way
-- per-frame CFrame writes did. TypeData.TurnPivot (a Bone or Attachment, e.g. "Torso") is where he
-- AIMS from; where he physically ROTATES about is his centre of mass, which the Hitbox provides.
----------------------------------------------------------------------

local warnedTurnPivot: { [string]: boolean } = {}

local function turnPivotPosition(enemy, anim, rootPart: BasePart): Vector3
	local pivot = anim.TurnPivot
	if pivot and pivot.Parent then
		if pivot:IsA("Bone") then
			return pivot.TransformedWorldCFrame.Position
		end
		return fistWorldPosition(enemy, pivot)
	end
	return rootPart.Position
end

-- Signed radians from where he faces to where he should (the target, seen from the pivot), plus his
-- current yaw so the caller doesn't read it twice.
local function yawError(enemy, anim, rootPart: BasePart, targetPosition: Vector3): (number, number)
	local _, currentYaw = rootPart.CFrame:ToEulerAnglesYXZ()
	local pivot = turnPivotPosition(enemy, anim, rootPart)
	local flatTo = Vector3.new(targetPosition.X - pivot.X, 0, targetPosition.Z - pivot.Z)
	if flatTo.Magnitude < 0.01 then
		return 0, currentYaw
	end
	local _, desiredYaw = (CFrame.lookAt(Vector3.zero, flatTo) * CFrame.Angles(0, math.rad(facingOffset(enemy, anim)), 0)):ToEulerAnglesYXZ()
	return (desiredYaw - currentYaw + math.pi) % (2 * math.pi) - math.pi, currentYaw
end

-- Points the AlignOrientation (see startTurning) at the target. Called from the AI tick; physics does
-- the actual turning smoothly between ticks, capped at TurnSpeed by MaxAngularVelocity.
local function aimTurn(enemy, anim, rootPart: BasePart, targetPosition: Vector3)
	local align = anim.TurnAlign
	if not align then
		return
	end
	local diff, currentYaw = yawError(enemy, anim, rootPart, targetPosition)
	align.CFrame = CFrame.fromEulerAnglesYXZ(0, currentYaw + diff, 0)
end

local function startTurning(enemy, anim)
	-- The server must own his physics. Left on automatic, Roblox hands an unanchored NPC's simulation
	-- to whichever player is nearest, and then that client's physics fights the server's MoveTo and
	-- the per-frame turn below: he stutters, stops, and starts again. pcall because SetNetworkOwner
	-- throws on an anchored assembly.
	local rootPart = enemy.Model.PrimaryPart
	if rootPart then
		pcall(function()
			rootPart:SetNetworkOwner(nil)
		end)
	end

	local pivotName = enemy.TypeData and enemy.TypeData.TurnPivot
	if pivotName then
		local found = enemy.Model:FindFirstChild(pivotName, true)
		if found and found:IsA("Attachment") then -- a Bone is an Attachment too
			anim.TurnPivot = found
		else
			warnOnce(warnedTurnPivot, tostring(enemy.TypeKey), ("[EnemyAnimation] %s's TurnPivot %q isn't a Bone or Attachment in the model — turning around his root instead."):format(
				tostring(enemy.TypeKey), tostring(pivotName)))
		end
	end
	-- Turning is done by physics (an AlignOrientation on the root), NOT by writing rootPart.CFrame.
	-- The first version wrote the root's CFrame every Heartbeat, and those writes fought the Humanoid's
	-- movement controller: he barely covered ground, and raising WalkSpeed changed nothing. A
	-- constraint turns him about his assembly's centre of mass, which is why the Hitbox carries his
	-- mass (see spawnEnemy): the turn centres on his visible body instead of on the root block.
	if rootPart then
		local attachment = Instance.new("Attachment")
		attachment.Name = "TurnAttachment"
		attachment.Parent = rootPart

		local align = Instance.new("AlignOrientation")
		align.Name = "TurnAlign"
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.Attachment0 = attachment
		align.MaxTorque = math.huge
		align.Responsiveness = 25
		align.MaxAngularVelocity = math.rad((enemy.TypeData and enemy.TypeData.TurnSpeed) or 90)
		-- Hold his spawn facing until the first tick aims him, rather than snapping to world-forward.
		local _, spawnYaw = rootPart.CFrame:ToEulerAnglesYXZ()
		align.CFrame = CFrame.fromEulerAnglesYXZ(0, spawnYaw, 0)
		align.Parent = rootPart
		anim.TurnAlign = align
	end
	anim.TurnStarted = true
end

function EnemyAnimation.Tick(enemy, context, fallbackPattern)
	local model = enemy.Model
	local humanoid = enemy.Humanoid
	local rootPart = model and model.PrimaryPart
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	if not enemy.Anim then
		enemy.Anim = setupAnim(enemy)
	end
	local anim = enemy.Anim

	if not anim.Ready then
		fallbackPattern(enemy, context)
		return
	end

	-- Read by the async marker/window callbacks above, which fire BETWEEN ticks off an animation
	-- event rather than this loop's own polling — they always want the latest context, not whichever
	-- tick's context was current when their track started playing.
	anim.Context = context

	-- This file owns his facing (see the turn step in the walking branch below), so the Humanoid's own
	-- AutoRotate must not fight it.
	if humanoid.AutoRotate then
		humanoid.AutoRotate = false
	end
	if not anim.TurnStarted then
		startTurning(enemy, anim)
	end

	-- Same interrupt as Chaser/Slam: a stun neither moves nor attacks. Unlike a simple cooldown, an
	-- in-progress swing gets STOPPED outright rather than just paused — Stop() fires this track's own
	-- Stopped signal, so onAttackStopped still closes any open Sweep window and stamps the cooldown
	-- exactly like a normal finish would, instead of leaving a window open forever.
	if StatusEffects.IsStunned(enemy) then
		humanoid:Move(Vector3.new(0, 0, 0))
		if anim.CurrentAttack and anim.CurrentAttack.Track.IsPlaying then
			anim.CurrentAttack.Track:Stop()
		end
		if anim.MoveTrack and anim.MoveTrack.IsPlaying then
			anim.MoveTrack:Stop()
		end
		return
	end

	-- Same recompute-every-think convention as Chaser/Slam — see EnemyAI.lua's own comment on why
	-- this is scaled from the RECORD's MoveSpeed rather than read back from WalkSpeed.
	-- Speed bursts (TypeData.SpeedBurst): a timed surge that only STARTS while he's walking after the
	-- target, so a player who keeps backing off gets caught now and then. anim.Walking is last tick's
	-- decision (it's recomputed further down), which is fine at a 0.15s tick.
	local burst = enemy.TypeData and enemy.TypeData.SpeedBurst
	anim.BurstMultiplier = 1
	if burst then
		local now = context.Now
		anim.NextBurstAt = anim.NextBurstAt or (now + burst.CooldownMin + math.random() * (burst.CooldownMax - burst.CooldownMin))
		if anim.BurstUntil and now < anim.BurstUntil then
			anim.BurstMultiplier = burst.Multiplier
		elseif anim.Walking and now >= anim.NextBurstAt then
			anim.BurstUntil = now + burst.Duration
			anim.NextBurstAt = anim.BurstUntil + burst.CooldownMin + math.random() * (burst.CooldownMax - burst.CooldownMin)
			anim.BurstMultiplier = burst.Multiplier
		end
	end

	local desiredSpeed = (enemy.MoveSpeed or humanoid.WalkSpeed) * StatusEffects.GetSpeedMultiplier(enemy) * anim.BurstMultiplier
	if math.abs(humanoid.WalkSpeed - desiredSpeed) > 0.01 then
		humanoid.WalkSpeed = desiredSpeed
	end

	-- Mid-swing: hold still, let the animation and its markers do the rest. No re-targeting, no
	-- distance check, nothing — same "an attack in progress owns the enemy completely" rule Slam's
	-- wind-up enforces for the identical reason.
	if anim.CurrentAttack and anim.CurrentAttack.Track.IsPlaying then
		humanoid:Move(Vector3.new(0, 0, 0))
		return
	end

	local targetPosition = resolveTargetPosition(context)
	if not targetPosition then
		return
	end

	-- Horizontal distance only, throughout this function — the Hulk's root sits well above where a
	-- standing player's feet actually are (see this file's header), so a raw 3D distance would read
	-- him as farther from an adjacent player than he really is and could stall both the walk-in and
	-- the attack trigger below.
	local flat = Vector3.new(rootPart.Position.X - targetPosition.X, 0, rootPart.Position.Z - targetPosition.Z)
	local distance = flat.Magnitude
	local now = context.Now

	-- Aim every tick he isn't swinging or stunned (both returned above); physics turns him in between.
	aimTurn(enemy, anim, rootPart, targetPosition)

	-- `not anim.Walking`: once he has set off after a player who left AttackRadius, he finishes the walk
	-- to the ContactRange ring before swinging. Otherwise he'd take one step back inside the radius,
	-- stop to attack, fall behind again, and repeat, which reads as stop-start stutter.
	if not anim.Walking and now >= (enemy.NextAttackAt or 0) and now - enemy.SpawnTime >= SPAWN_GRACE_SECONDS then
		-- Which attack plays is a weighted pick among whichever ones this distance is inside the
		-- TriggerRange of — NOT gated by ContactRange the way Chaser/Slam gate their single attack.
		-- EnemyConfig's own comment on ContactRange explains why: it's the ring he walks to, kept
		-- inside every attack's TriggerRange so ARRIVING guarantees he can swing, not the only range
		-- he's allowed to swing FROM — a longer-reaching attack can still fire from farther out.
		local usable = {}
		local totalWeight = 0
		for _, attack in ipairs(anim.UsableAttacks) do
			local triggerRange = attack.TriggerRange or math.huge
			if triggerRange >= distance then
				table.insert(usable, attack)
				totalWeight += (attack.Weight or 1)
			end
		end

		-- No snap-to-face on commit: he only swings once the turn (aimTurn) has actually brought him round to
		-- within AttackFacingTolerance degrees, so getting behind a slow boss buys real time.
		local tolerance = math.rad((enemy.TypeData and enemy.TypeData.AttackFacingTolerance) or 30)
		local facingError = yawError(enemy, anim, rootPart, targetPosition)
		if #usable > 0 and math.abs(facingError) <= tolerance then
			local roll = math.random() * totalWeight
			local acc = 0
			local chosen = usable[1]
			for _, attack in ipairs(usable) do
				acc += (attack.Weight or 1)
				if roll <= acc then
					chosen = attack
					break
				end
			end

			humanoid:Move(Vector3.new(0, 0, 0))
			if anim.MoveTrack and anim.MoveTrack.IsPlaying then
				anim.MoveTrack:Stop()
			end

			chosen.MarkerCount = 0
			anim.CurrentAttack = chosen
			chosen.Track:Play()
			return
		end
	end

	-- Walking: same boundary-circle MoveTo convention as Chaser/Slam (see EnemyAI.lua's own comment
	-- on why) — aim at a point ON the ContactRange ring along the current bearing, never past it, so
	-- Roblox's own arrival tolerance stops him right at the ring instead of relying on a per-tick
	-- Move(zero) backstop to catch him after the fact.
	-- AttackRadius (optional): inside it he holds his ground, turning and swinging but not walking. He
	-- only starts walking once the target leaves it, then walks until they're back inside the
	-- ContactRange ring. The gap between the two is deliberate: with one threshold, a player standing
	-- on the line would flick him between walking and stopping every tick.
	local attackRadius = enemy.TypeData and enemy.TypeData.AttackRadius
	if not attackRadius or distance > attackRadius then
		anim.Walking = true
	elseif distance <= enemy.ContactRange then
		anim.Walking = false
	end

	if not anim.Walking then
		humanoid:Move(Vector3.new(0, 0, 0))
	elseif now - (enemy.LastMoveThink or 0) >= MOVE_THINK_INTERVAL then
		enemy.LastMoveThink = now
		local direction = distance > 0 and (flat / distance) or Vector3.new(1, 0, 0)
		local standPoint = targetPosition + direction * enemy.ContactRange
		humanoid:MoveTo(standPoint)
	end

	if anim.MoveTrack then
		-- Driven by the walking decision above, not by measured motion. humanoid.MoveDirection is not
		-- reliably set for a server-driven MoveTo walker, and velocity dips below any threshold for a
		-- frame or two mid-crawl, which started and stopped the animation over and over.
		if anim.Walking then
			-- Playback speed scales the published crawl without a re-export from Blender, and follows a
			-- speed burst so his limbs keep pace with the surge instead of sliding.
			local moveAnimSpeed = ((enemy.TypeData and enemy.TypeData.MoveAnimationSpeed) or 1) * (anim.BurstMultiplier or 1)
			if not anim.MoveTrack.IsPlaying then
				anim.MoveTrack:Play(0.1, 1, moveAnimSpeed)
			elseif math.abs(anim.MoveTrack.Speed - moveAnimSpeed) > 0.01 then
				anim.MoveTrack:AdjustSpeed(moveAnimSpeed)
			end
		elseif anim.MoveTrack.IsPlaying then
			anim.MoveTrack:Stop()
		end
	end
end

----------------------------------------------------------------------
-- Locomotion — Idle/Move/Death animations for an enemy that is NOT "Animated" (EnemyAI.Patterns.Chaser
-- calls this every tick). Just the looks: no markers, no turning, no damage, which all stay with the
-- pattern. A type opts in by setting `Animations` on its EnemyConfig entry; a type without one costs a
-- single table lookup and stays silent, since that is still most enemies. Only the slots the entry
-- actually lists are loaded, so leaving Idle out is a choice, not a warning.
----------------------------------------------------------------------

local function setupLocomotion(enemy)
	local loco = {}
	local typeKey = tostring(enemy.TypeKey)
	local animations = enemy.TypeData and enemy.TypeData.Animations
	local humanoid = enemy.Humanoid
	if not animations or not humanoid then
		return loco
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		warnOnce(warnedFallback, typeKey .. "/Locomotion",
			("[EnemyAnimation] %s has Animations set but its model's Humanoid has no Animator child — it moves unanimated. Add an Animator inside the Humanoid of ServerStorage.EnemyModels.%s."):format(typeKey, tostring(enemy.TypeData.ModelName)))
		return loco
	end

	if animations.Idle then
		loco.IdleTrack = loadTrack(animator, typeKey, "Idle", animations.Idle, true, Enum.AnimationPriority.Idle)
		if loco.IdleTrack then
			loco.IdleTrack:Play()
		end
	end
	if animations.Move then
		loco.MoveTrack = loadTrack(animator, typeKey, "Move", animations.Move, true, Enum.AnimationPriority.Movement)
	end
	if animations.Death then
		loco.DeathTrack = loadTrack(animator, typeKey, "Death", animations.Death, false, Enum.AnimationPriority.Action)
	end
	if animations.Attack then
		-- Action priority so it plays over the walk, and unlooped so one hit is one swing. Cosmetic:
		-- the damage is still the pattern's own ContactDamage on its own cooldown, NOT marker-timed off
		-- this animation (that is what AIPattern "Animated" is for, see the top of this file). Keep the
		-- animation no longer than the type's AttackCooldown, or a hit that lands mid-swing gets no swing
		-- of its own (PlayAttack warns once if it is longer).
		loco.AttackTrack = loadTrack(animator, typeKey, "Attack", animations.Attack, false, Enum.AnimationPriority.Action)
	end


	-- The pattern stops ticking a dead enemy, so the loops would otherwise keep playing on the corpse.
	-- Disconnected with the Humanoid when the encounter destroys the model.
	humanoid.Died:Connect(function()
		if loco.IdleTrack then
			loco.IdleTrack:Stop()
		end
		if loco.MoveTrack then
			loco.MoveTrack:Stop()
		end
		if loco.AttackTrack then
			loco.AttackTrack:Stop() -- a swing held on its last pose would otherwise sit over the Death animation
		end
		if loco.DeathTrack then
			loco.DeathTrack:Play()
		end
	end)
	return loco
end

-- `walking` is the pattern's own decision (out of attack range and not stunned), not measured motion,
-- for the same reason Tick's Move block gives.
-- One swing, played by the pattern at the moment it lands a contact hit. Silent no-op for a type with
-- no Attack animation, which is most of them.
--
-- A swing that ends while the enemy is standing still is frozen just before its last frame instead of
-- ending, and held until the next swing or until it walks off. Without an Idle animation there is
-- nothing underneath the swing, so letting it end snapped the rig straight back to its rest T-pose
-- between hits, which also chopped the tail off the swing itself.
local ATTACK_HOLD_LEAD = 0.05 -- seconds before the natural end that the swing is frozen

function EnemyAnimation.PlayAttack(enemy)
	if enemy.Anim then
		return -- an "Animated" enemy picks and plays its own attacks, marker-timed
	end
	if not enemy.Loco then
		enemy.Loco = setupLocomotion(enemy)
	end
	local loco = enemy.Loco
	local track = loco.AttackTrack
	if not track or (track.IsPlaying and track.Speed > 0) then
		return -- no Attack animation, or still mid-swing
	end

	loco.AttackPlayId = (loco.AttackPlayId or 0) + 1
	local playId = loco.AttackPlayId
	if track.IsPlaying then
		-- Held on its last pose from the previous swing: restart it rather than blend it into itself.
		track.TimePosition = 0
		track:AdjustSpeed(1)
	else
		track:Play(0.1)
	end

	task.spawn(function()
		-- Length reads 0 until the asset has loaded, which can still be true on the very first swing.
		while track.Length == 0 and track.IsPlaying and loco.AttackPlayId == playId do
			task.wait()
		end
		if track.Length > 0 and enemy.AttackCooldown and track.Length > enemy.AttackCooldown then
			warnOnce(warnedSlot, tostring(enemy.TypeKey) .. "/AttackLength",
				("[EnemyAnimation] %s's Attack animation is %.2fs but its AttackCooldown is %.2fs — hits that land mid-swing get no swing of their own. Shorten the animation or raise AttackCooldown in EnemyConfig."):format(tostring(enemy.TypeKey), track.Length, enemy.AttackCooldown))
		end
		task.wait(math.max(track.Length - track.TimePosition - ATTACK_HOLD_LEAD, 0))
		if loco.AttackPlayId ~= playId or not track.IsPlaying then
			return -- restarted by a newer swing, or stopped (death, despawn)
		end
		if loco.Walking then
			track:Stop(0.2)
		else
			track:AdjustSpeed(0)
		end
	end)
end

function EnemyAnimation.Locomotion(enemy, walking: boolean)
	if enemy.Anim then
		return -- an "Animated" enemy falling back to Chaser: Tick already loaded and owns its tracks
	end
	if not enemy.Loco then
		enemy.Loco = setupLocomotion(enemy)
	end

	enemy.Loco.Walking = walking
	local attackTrack = enemy.Loco.AttackTrack
	if walking and attackTrack and attackTrack.IsPlaying and attackTrack.Speed == 0 then
		attackTrack:Stop(0.2) -- release a held swing pose (see PlayAttack) now that it is walking again
	end

	local moveTrack = enemy.Loco.MoveTrack
	if not moveTrack or not enemy.Humanoid or enemy.Humanoid.Health <= 0 then
		return
	end
	if walking then
		local speed = (enemy.TypeData and enemy.TypeData.MoveAnimationSpeed) or 1
		if not moveTrack.IsPlaying then
			moveTrack:Play(0.1, 1, speed)
		elseif math.abs(moveTrack.Speed - speed) > 0.01 then
			moveTrack:AdjustSpeed(speed)
		end
	elseif moveTrack.IsPlaying then
		moveTrack:Stop(0.15)
	end
end

return EnemyAnimation
