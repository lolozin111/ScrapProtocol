--[[
	NodeService.lua
	Handles the three Expedition node types: Heal Station, Shop, and Combat Outpost.
	Every node in the world is a Part/Model tagged "Node" (CollectionService) with a child
	StringValue "NodeType" set to "Heal", "Shop", or "Combat" — Combat nodes additionally need
	a child NumberValue "Tier" matching a key in NodeConfig.CombatTiers. See the README for
	exact setup steps.

	Combat raids carry real risk: the player takes chip damage every second the fight isn't
	yet won (harder gear = faster win = less damage taken). Reaching 0 HP fails the raid with
	no loot — that's the actual strategic tension this system adds over just picking the
	"best" node every time.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NodeConfig = require(ReplicatedStorage.Shared.NodeConfig)
local AdminConfig = require(ReplicatedStorage.Shared.AdminConfig)
local DataService = require(script.Parent.DataService)
local CombatMath = require(script.Parent.CombatMath)
local ExpeditionService = require(script.Parent.ExpeditionService)
local PlayerActivityService = require(script.Parent.PlayerActivityService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local InteractHeal = Remotes.InteractHeal
local BuyOutpostItem = Remotes.BuyOutpostItem
local StartOutpostRaid = Remotes.StartOutpostRaid
local OutpostUpdate = Remotes.OutpostUpdate
local SkipNode = Remotes.SkipNode

local NODE_TAG = "Node"

local NodeService = {}

----------------------------------------------------------------------
-- Shared helpers
----------------------------------------------------------------------

local function getNodeType(node: Instance): string?
	if not CollectionService:HasTag(node, NODE_TAG) then
		return nil
	end
	local marker = node:FindFirstChild("NodeType")
	return marker and marker:IsA("StringValue") and marker.Value or nil
end

local function grantLoot(player: Player, lootTable)
	local granted = {}
	for _, entry in ipairs(lootTable) do
		if math.random() <= entry.Chance then
			local amount = math.random(entry.Min, entry.Max)
			if entry.Kind == "Ore" then
				DataService.AddOre(player, entry.OreKey, amount)
				table.insert(granted, { Kind = "Ore", Key = entry.OreKey, Amount = amount })
			elseif entry.Kind == "Currency" then
				DataService.AddCurrency(player, entry.CurrencyKey, amount)
				table.insert(granted, { Kind = "Currency", Key = entry.CurrencyKey, Amount = amount })
			end
		end
	end
	return granted
end

local function pushInventory(player: Player, profile)
	Remotes.InventoryUpdate:FireClient(player, {
		Scrap = profile.Scrap,
		Cores = profile.Cores,
		OreCounts = profile.OreCounts,
	})
end

-- Expedition fork nodes are linked in pairs via a "SiblingNode" ObjectValue (see
-- ExpeditionService). Engaging with either one commits the path: the other vanishes.
-- Permanent, hand-placed nodes never have this child, so this is a harmless no-op for them.
local function commitFork(node: Instance)
	local siblingRef = node:FindFirstChild("SiblingNode")
	if siblingRef and siblingRef.Value then
		siblingRef.Value:Destroy()
	end
end

-- Only the frontmost row of the expedition conveyor is reachable — you can't skip ahead to a
-- node still further back in the queue. Hand-placed permanent nodes have no SlotIndex
-- attribute and are never gated (CanAccessSlot returns true for a nil slot index).
local function checkSlotAccess(node: Instance): boolean
	return ExpeditionService.CanAccessSlot(node:GetAttribute("SlotIndex"))
end

-- Expedition nodes are one-time: once successfully used, they're destroyed outright (which also
-- triggers ExpeditionService to recycle that row and spawn a new one at the back of the queue).
-- Permanent, hand-placed nodes are never touched here.
local function destroyIfExpedition(node: Instance)
	if node:GetAttribute("IsExpeditionNode") then
		node:Destroy()
	end
end

----------------------------------------------------------------------
-- Heal Station
----------------------------------------------------------------------

local healCooldowns: { [number]: number } = {} -- userId -> os.time() they can next heal

-- Declared up here (rather than down by runRaid, where it's mainly used) so Heal/Shop can also
-- check it — a raid is the one interaction that takes real time, and a fork's two options share
-- a slot the whole time, so without this a player could raid one side of a fork while also
-- healing/shopping the other side mid-fight. Nothing else needs this: Heal/Shop resolve
-- instantly, so there's no equivalent window to exploit for them.
local activeRaids: { [number]: boolean } = {} -- userId -> true while raiding

InteractHeal.OnServerInvoke = function(player: Player, node: Instance?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return { Success = false, Reason = "No character" }
	end

	if activeRaids[player.UserId] then
		return { Success = false, Reason = "Busy — you're mid-raid" }
	end

	if typeof(node) == "Instance" and not checkSlotAccess(node) then
		return { Success = false, Reason = "Locked — clear the node in front of you first" }
	end

	-- Expedition Heal nodes are one-time (destroyed on use) so a cooldown on top of that would
	-- just be a redundant second gate — and worse, it used to silently block the destroy below,
	-- leaving a "used" node stuck in place until the shared cooldown happened to expire. Only
	-- the permanent hand-placed Heal Station (reusable forever) needs the cooldown.
	local isExpeditionHeal = typeof(node) == "Instance"
		and node:GetAttribute("IsExpeditionNode")
		and getNodeType(node) == "Heal"

	if not isExpeditionHeal then
		local now = os.time()
		local readyAt = healCooldowns[player.UserId] or 0
		if now < readyAt then
			return { Success = false, Reason = "On cooldown", SecondsLeft = readyAt - now }
		end
		healCooldowns[player.UserId] = now + NodeConfig.HealCooldownSeconds
	end

	humanoid.Health = humanoid.MaxHealth

	if isExpeditionHeal then
		commitFork(node)
		destroyIfExpedition(node)
	end

	return { Success = true }
end

----------------------------------------------------------------------
-- Shop
----------------------------------------------------------------------

BuyOutpostItem.OnServerInvoke = function(player: Player, node: Instance?, itemKey: string)
	local item = NodeConfig.ShopCatalog[itemKey]
	if not item then
		return { Success = false, Reason = "Unknown item" }
	end

	if activeRaids[player.UserId] then
		return { Success = false, Reason = "Busy — you're mid-raid" }
	end

	if typeof(node) == "Instance" and not checkSlotAccess(node) then
		return { Success = false, Reason = "Locked — clear the node in front of you first" }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	local spent = DataService.TrySpend(player, { [item.CostCurrency] = item.CostAmount })
	if not spent then
		return { Success = false, Reason = "Not enough " .. item.CostCurrency }
	end

	if item.Grant.Kind == "Ore" then
		DataService.AddOre(player, item.Grant.OreKey, item.Grant.Amount)
	else
		DataService.AddCurrency(player, item.Grant.CurrencyKey, item.Grant.Amount)
	end

	if typeof(node) == "Instance" and getNodeType(node) == "Shop" then
		commitFork(node)
		destroyIfExpedition(node)
	end

	pushInventory(player, profile)
	return { Success = true }
end

----------------------------------------------------------------------
-- Combat Outposts
----------------------------------------------------------------------

local raidCooldowns: { [number]: { [Instance]: number } } = {}    -- userId -> node -> os.time() ready
-- (activeRaids itself is declared up near InteractHeal — see the comment there for why)

local function runRaid(player: Player, node: Instance, tier: number)
	local userId = player.UserId
	local tierData = NodeConfig.CombatTiers[tier]
	local profile = DataService.Get(player)

	if not tierData or not profile then
		activeRaids[userId] = nil
		return
	end

	-- Admin fast-forward: skip gear checks, cooldowns, and the whole timed tick loop, resolve
	-- straight to a win. This is purely a dev-testing shortcut (see AdminConfig.lua) so you can
	-- get to loot/crafting/downstream systems without grinding combat every time.
	if AdminConfig.IsAdmin(player) then
		OutpostUpdate:FireClient(player, {
			Status = "RaidStart",
			NodeName = tierData.Name,
			Tier = tier,
			EnemyHP = tierData.EnemyHP,
		})

		local loot = grantLoot(player, tierData.Loot)
		pushInventory(player, profile)
		commitFork(node)

		if node:GetAttribute("IsExpeditionNode") then
			node:Destroy()
		end

		OutpostUpdate:FireClient(player, { Status = "RaidCleared", Loot = loot })
		activeRaids[userId] = nil
		return
	end

	local totalDPS = CombatMath.GetPlayerCombatDPS(profile)
	if totalDPS <= 0 then
		OutpostUpdate:FireClient(player, { Status = "NoGear", Message = "Craft a weapon or deploy a robot before raiding." })
		activeRaids[userId] = nil
		return
	end

	local nodeCooldowns = raidCooldowns[userId]
	if nodeCooldowns and (nodeCooldowns[node] or 0) > os.time() then
		OutpostUpdate:FireClient(player, { Status = "OnCooldown" })
		activeRaids[userId] = nil
		return
	end

	local remainingEnemyHP = tierData.EnemyHP

	OutpostUpdate:FireClient(player, {
		Status = "RaidStart",
		NodeName = tierData.Name,
		Tier = tier,
		EnemyHP = tierData.EnemyHP,
	})

	while remainingEnemyHP > 0 do
		task.wait(1)

		-- The node this raid is fighting can vanish out from under it — most notably, Return to
		-- Base wipes the whole expedition queue mid-fight. Without this check the loop just kept
		-- ticking forever against a node that no longer existed: still damaging the player, still
		-- holding activeRaids[userId] true (blocking Heal/Shop/new raids) long after the player
		-- thought they'd left. Treated as a clean cancellation, not a loss — no failure message,
		-- no penalty, it just stops.
		if not node.Parent then
			OutpostUpdate:FireClient(player, { Status = "RaidCancelled" })
			activeRaids[userId] = nil
			return
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not player.Parent or not humanoid or humanoid.Health <= 0 then
			OutpostUpdate:FireClient(player, { Status = "RaidFailed" })
			activeRaids[userId] = nil
			return
		end

		remainingEnemyHP -= totalDPS
		humanoid:TakeDamage(tierData.DamagePerSecond)

		OutpostUpdate:FireClient(player, {
			Status = "Tick",
			RemainingEnemyHP = math.max(0, remainingEnemyHP),
			PlayerHealth = humanoid.Health,
		})

		if humanoid.Health <= 0 then
			OutpostUpdate:FireClient(player, { Status = "RaidFailed" })
			activeRaids[userId] = nil
			return
		end
	end

	local loot = grantLoot(player, tierData.Loot)
	pushInventory(player, profile)

	commitFork(node)

	if node:GetAttribute("IsExpeditionNode") then
		node:Destroy() -- expedition camps are one-time; the permanent base ones aren't (also recycles this row via ExpeditionService)
	else
		nodeCooldowns = raidCooldowns[userId] or {}
		nodeCooldowns[node] = os.time() + tierData.CooldownSeconds
		raidCooldowns[userId] = nodeCooldowns
	end

	OutpostUpdate:FireClient(player, { Status = "RaidCleared", Loot = loot })
	activeRaids[userId] = nil
end

StartOutpostRaid.OnServerEvent:Connect(function(player: Player, node: Instance)
	if typeof(node) ~= "Instance" or getNodeType(node) ~= "Combat" then
		return
	end
	if activeRaids[player.UserId] then
		return -- already mid-raid
	end
	if not checkSlotAccess(node) then
		OutpostUpdate:FireClient(player, { Status = "Locked" })
		return
	end

	-- Energy is no longer spent here — engaging any one Combat node inside an expedition used to
	-- cost Energy every time, which meant a single exploration run with 3 Combat rows could burn
	-- 3 Energy. Energy is meant to gate starting an exploration, not each fight inside one — it's
	-- now charged exactly once, when the expedition itself starts (see ExpeditionService's
	-- RegenerateExpedition handler). Nothing to check or spend here anymore.

	local tierValue = node:FindFirstChild("Tier")
	local tier = (tierValue and tierValue:IsA("NumberValue")) and tierValue.Value or 1

	-- Claim the player's combat state (see PlayerActivityService) — an Outpost raid runs its own
	-- damage loop against the player's Humanoid, so it can't overlap a base-defense wave or an
	-- instanced Raid Room. activeRaids below stays as-is: it's the finer-grained mid-raid lockout
	-- that Heal/Shop/Skip check, a different question from "what is this player doing at all."
	local acquired, busyReason = PlayerActivityService.TryAcquire(player, PlayerActivityService.Activities.OutpostRaid)
	if not acquired then
		OutpostUpdate:FireClient(player, { Status = "Busy", Message = busyReason })
		return
	end

	activeRaids[player.UserId] = true

	-- runRaid has nine separate exit paths, each clearing activeRaids itself. Rather than adding a
	-- release to all nine (and every future one), release once here after it returns — and pcall it
	-- so an unexpected error inside the loop can't strand BOTH flags and lock the player out of
	-- fighting for the rest of the session, which is exactly the failure mode this whole activity
	-- system exists to prevent.
	task.spawn(function()
		local ok, err = pcall(runRaid, player, node, tier)
		if not ok then
			warn("[NodeService] runRaid errored:", err)
			activeRaids[player.UserId] = nil
			OutpostUpdate:FireClient(player, { Status = "RaidCancelled" })
		end
		PlayerActivityService.Release(player, PlayerActivityService.Activities.OutpostRaid)
	end)
end)

----------------------------------------------------------------------
-- Skip — abandon the current frontmost expedition node without engaging it (e.g. a Shop you
-- can't afford anything at). Works on any node type in principle; only the Shop panel exposes
-- a button for it right now. Blocked entirely while a raid is in progress — not just against
-- the Combat node itself, but its fork sibling too, since skipping the sibling would commitFork
-- and destroy the Combat node out from under the still-running runRaid loop, letting a player
-- dodge a losing fight for free.
----------------------------------------------------------------------

SkipNode.OnServerEvent:Connect(function(player: Player, node: Instance)
	if typeof(node) ~= "Instance" or not CollectionService:HasTag(node, NODE_TAG) then
		return
	end
	if activeRaids[player.UserId] then
		return
	end
	if not checkSlotAccess(node) then
		return -- not the frontmost node anyway — nothing to skip
	end

	commitFork(node)
	destroyIfExpedition(node)
end)

game.Players.PlayerRemoving:Connect(function(player)
	activeRaids[player.UserId] = nil
	healCooldowns[player.UserId] = nil
	raidCooldowns[player.UserId] = nil
end)

return NodeService
