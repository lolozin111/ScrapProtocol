--[[
	TrainingDummyService.lua
	Punching bags that behave like real enemies, so combat can be tested deliberately instead of
	inferred from a chaotic wave.

	WHY: reported directly — "the mods seemed to half work, I couldn't tell half of the time".
	Testing an Ultimate mod during a live wave means watching a dozen enemies, moving, dying to
	several damage sources at once, and trying to spot whether a passive fired. A dummy that stands
	still and shows a running damage total makes each passive individually verifiable.

	Dummies are REAL enemy records — the same shape CombatEncounterService.spawnEnemy produces — so
	everything downstream treats them normally: the damage pipeline, status effects, Ultimate hooks,
	damage numbers. They are not a parallel code path with its own rules, which is the whole point;
	a test rig that behaves differently from the real thing proves nothing.

	What they DON'T do is move or attack. They have no AIPattern, and nothing ticks EnemyAI for them.

	=== HOW THEY ARE REACHABLE OUTSIDE A WAVE ===
	RequestFireWeapon normally requires an active encounter. Dummies register a FALLBACK encounter
	with CombatEncounterService, used only when the player has no real one — so shooting a dummy
	mid-wave is impossible (the real encounter wins), and shooting one while idle works.

	Each player gets their own fallback encounter object wrapping the SHARED dummy records, so the
	per-encounter shot counter that "every Nth shot" passives read is per player rather than a
	global that two testers would interleave.

	=== SETUP ===
	Tag any Part or Model "TrainingDummy" in Studio, or type /dummy in chat as an admin to drop one
	in front of you. The chat command exists so this needs no Studio work to use at all.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local StatusEffects = require(script.Parent.StatusEffects)
local CombatEncounterService = require(script.Parent.CombatEncounterService)

local TrainingDummyService = {}

local DUMMY_TAG = "TrainingDummy"

-- High enough that you can pour damage in and read a meaningful total, low enough that a strong
-- weapon still gets the satisfaction of killing it (and fires OnKill passives like Detonator).
local DUMMY_MAX_HEALTH = 2000
local DUMMY_DEFENSE = 10       -- non-zero on purpose, so armour-shred passives are observable
local REVIVE_SECONDS = 3
local DAMAGE_RESET_SECONDS = 5 -- accumulated total clears after this long without a hit
local TICK_SECONDS = 0.2

local dummyFolder = Workspace:FindFirstChild("TrainingDummies")
if not dummyFolder then
	dummyFolder = Instance.new("Folder")
	dummyFolder.Name = "TrainingDummies"
	dummyFolder.Parent = Workspace
end

-- Shared across players: model -> record. Same shape as a spawned enemy's record.
local dummyRecords: { [Instance]: any } = {}

-- Per-player wrapper so PlayerState (and therefore the shot counter) is not shared between testers.
local fallbackEncounters: { [number]: any } = {}

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------

local function buildLabel(model: Model, part: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageTotal"
	billboard.Size = UDim2.new(0, 200, 0, 60)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local total = Instance.new("TextLabel")
	total.Name = "Total"
	total.BackgroundTransparency = 1
	total.Size = UDim2.new(1, 0, 0.6, 0)
	total.Font = Enum.Font.SourceSansBold
	total.TextColor3 = Color3.fromRGB(255, 235, 180)
	total.TextStrokeTransparency = 0.3
	total.TextScaled = true
	total.Text = "0"
	total.Parent = billboard

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.new(0, 0, 0.6, 0)
	sub.Size = UDim2.new(1, 0, 0.4, 0)
	sub.Font = Enum.Font.SourceSans
	sub.TextColor3 = Color3.fromRGB(167, 156, 140)
	sub.TextStrokeTransparency = 0.5
	sub.TextScaled = true
	sub.Text = "Training Dummy"
	sub.Parent = billboard

	return total, sub
end

-- Tagged instance -> the Model we built for it. Keyed by the TAGGED instance, not by the model,
-- which matters: when a loose Part is tagged we wrap it in a new Model, so keying the guard by the
-- model meant the "already registered" check could never match and every signal built another
-- wrapper. That was one half of a re-entrancy crash.
local registeredFor: { [Instance]: Model } = {}

-- Turns a tagged instance into a live dummy record. Accepts a bare Part as well as a Model, since
-- "tag any part" is the lowest-friction setup and matches how every other tag in this game works.
local function registerDummy(instance: Instance)
	-- Claimed BEFORE any reparenting below. CollectionService fires its added/removed signals when
	-- a tagged instance enters or leaves the DataModel, not just when the tag changes — so moving a
	-- tagged Part re-enters this function, and the guard has to already be set by then.
	if registeredFor[instance] then
		return
	end

	local model: Model
	local part: BasePart

	if instance:IsA("BasePart") then
		model = Instance.new("Model")
		model.Name = "TrainingDummy"
		instance.Anchored = true

		-- ORDER MATTERS. Parent the wrapper into the world FIRST, then move the part into it, so the
		-- part goes straight from one in-tree parent to another and never leaves the DataModel.
		-- Doing it the other way round (part into an unparented model, then model into the world)
		-- briefly pulls the tagged part out of the tree, which fires InstanceRemoved followed by
		-- InstanceAdded — re-entering this function and, with the broken guard above, recursing
		-- until Roblox killed it with "Maximum event re-entrancy depth exceeded".
		model.Parent = dummyFolder
		registeredFor[instance] = model
		instance.Parent = model
		model.PrimaryPart = instance
		part = instance
	elseif instance:IsA("Model") then
		model = instance
		part = instance.PrimaryPart
		if not part then
			warn(("[TrainingDummyService] %s has no PrimaryPart — set one, or tag a plain Part instead."):format(instance:GetFullName()))
			return
		end
		registeredFor[instance] = model
	else
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
	end
	humanoid.MaxHealth = DUMMY_MAX_HEALTH
	humanoid.Health = DUMMY_MAX_HEALTH
	-- Dummies never walk. Set to 0 rather than relying on nothing ticking their AI, so a stray
	-- Move() from anywhere cannot budge them.
	humanoid.WalkSpeed = 0

	local totalLabel, subLabel = buildLabel(model, part)

	dummyRecords[model] = {
		Model = model,
		Humanoid = humanoid,
		TypeKey = "TrainingDummy",
		-- Same fields spawnEnemy sets, so nothing downstream has to special-case a dummy.
		ContactDamage = 0,
		ContactRange = 0,
		AttackCooldown = math.huge,
		Defense = DUMMY_DEFENSE,
		MoveSpeed = 0,
		AIPattern = nil, -- never ticked; dummies do not act
		SpawnTime = os.clock(),
		LastAttackTime = 0,
		LastMoveThink = 0,
		-- Dummy-only bookkeeping
		IsDummy = true,
		AccumulatedDamage = 0,
		LastDamageAt = 0,
		TotalLabel = totalLabel,
		SubLabel = subLabel,
		ReviveAt = nil,
	}
end

-- Looks the model up through registeredFor rather than assuming the tagged instance IS the model —
-- the same key mismatch that broke the register guard also meant untagging a wrapped Part removed
-- nothing at all.
local function unregisterDummy(instance: Instance)
	local model = registeredFor[instance]
	registeredFor[instance] = nil
	if model then
		dummyRecords[model] = nil
	end
	dummyRecords[instance] = nil -- harmless if it was a directly-tagged Model
end

----------------------------------------------------------------------
-- The fallback encounter
----------------------------------------------------------------------

-- Only consulted when the player has NO real encounter, so a dummy can never steal a shot meant
-- for a wave. Built lazily per player and reused, because PlayerState.ShotCount has to persist
-- across shots for "every Nth shot" passives to count correctly.
local function getFallbackEncounter(player: Player)
	if not next(dummyRecords) then
		return nil
	end
	local existing = fallbackEncounters[player.UserId]
	if not existing then
		existing = {
			Player = player,
			EnemyByModel = dummyRecords,
			PlayerState = { ShotCount = 0, Shield = 0 },
			DamageTarget = function() end, -- nothing to damage back; dummies never attack
		}
		fallbackEncounters[player.UserId] = existing
	end
	return existing
end

CombatEncounterService.SetFallbackEncounterProvider(getFallbackEncounter)

-- Called by CombatEncounterService every time damage lands on a dummy, so the running total is
-- driven by the SAME number the damage pipeline produced rather than re-deriving it here.
function TrainingDummyService.NoteDamage(record, amount: number)
	if not record.IsDummy then
		return
	end
	record.AccumulatedDamage += amount
	record.LastDamageAt = os.clock()
end

----------------------------------------------------------------------
-- Tick: labels, damage-total reset, status effects, revival
----------------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(TICK_SECONDS)
		local now = os.clock()

		for model, record in pairs(dummyRecords) do
			if not model.Parent then
				dummyRecords[model] = nil
			else
				-- Statuses tick here rather than in an encounter loop, since a dummy is usually being
				-- shot while no encounter is running at all. Damage routes through the same public
				-- apply function everything else uses, so a bleed on a dummy is a bleed.
				StatusEffects.Tick(record, now, function(target, amount)
					local at = target.Model.PrimaryPart and target.Model.PrimaryPart.Position
					if at then
						CombatEncounterService.ApplyDamageTo(target, amount, at, record.LastAttacker, "Status")
					end
				end)

				if record.Humanoid.Health <= 0 then
					if not record.ReviveAt then
						record.ReviveAt = now + REVIVE_SECONDS
						record.SubLabel.Text = "Down — reviving..."
					elseif now >= record.ReviveAt then
						record.Humanoid.Health = record.Humanoid.MaxHealth
						record.ReviveAt = nil
						record.Status = nil -- a fresh dummy carries no leftover bleeds
						record.HitsTaken = 0
						record.AccumulatedDamage = 0
						record.SubLabel.Text = "Training Dummy"
						record.TotalLabel.Text = "0"
					end
				else
					-- Reset the running total after a quiet spell, so each burst reads on its own
					-- instead of every test since the server booted piling into one number.
					if record.AccumulatedDamage > 0 and (now - record.LastDamageAt) >= DAMAGE_RESET_SECONDS then
						record.AccumulatedDamage = 0
						record.HitsTaken = 0
						record.Status = nil
					end

					record.TotalLabel.Text = tostring(math.floor(record.AccumulatedDamage + 0.5))
					local hp = math.ceil(record.Humanoid.Health)
					local shred = StatusEffects.GetDefenseMultiplier(record)
					record.SubLabel.Text = ("HP %d  ·  DEF %d%%%s"):format(
						hp,
						math.floor(shred * 100 + 0.5),
						StatusEffects.IsStunned(record) and "  ·  STUNNED" or "")
				end
			end
		end
	end
end)

----------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------

-- Spawns one in front of `player`. Exists so testing needs no Studio work at all — see
-- AdminService's /dummy command.
function TrainingDummyService.SpawnNear(player: Player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false
	end

	-- Builds a FINISHED Model and tags that, rather than tagging a loose Part and letting
	-- registerDummy wrap it. The wrap path still exists for hand-tagged Parts, but the command that
	-- gets used constantly should not take the more delicate route through it.
	local part = Instance.new("Part")
	part.Name = "Body"
	part.Size = Vector3.new(4, 6, 2)
	part.Anchored = true
	part.CanCollide = true
	part.Material = Enum.Material.WoodPlanks
	part.Color = Color3.fromRGB(150, 120, 80)
	part.CFrame = rootPart.CFrame * CFrame.new(0, 0, -14)

	local model = Instance.new("Model")
	model.Name = "TrainingDummy"
	part.Parent = model
	model.PrimaryPart = part
	model.Parent = dummyFolder

	-- Tagged last, once the model is complete and already in the world — so the added signal fires
	-- exactly once, against something registerDummy can use as-is.
	CollectionService:AddTag(model, DUMMY_TAG)
	return true
end

for _, instance in ipairs(CollectionService:GetTagged(DUMMY_TAG)) do
	registerDummy(instance)
end
CollectionService:GetInstanceAddedSignal(DUMMY_TAG):Connect(registerDummy)
CollectionService:GetInstanceRemovedSignal(DUMMY_TAG):Connect(unregisterDummy)

Players.PlayerRemoving:Connect(function(player)
	fallbackEncounters[player.UserId] = nil
end)

return TrainingDummyService
