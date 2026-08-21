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
local DataService = require(script.Parent.DataService)
local CombatMath = require(script.Parent.CombatMath)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local InteractHeal = Remotes.InteractHeal
local BuyOutpostItem = Remotes.BuyOutpostItem
local StartOutpostRaid = Remotes.StartOutpostRaid
local OutpostUpdate = Remotes.OutpostUpdate

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

----------------------------------------------------------------------
-- Heal Station
----------------------------------------------------------------------

local healCooldowns: { [number]: number } = {} -- userId -> os.time() they can next heal

InteractHeal.OnServerInvoke = function(player: Player, node: Instance?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return { Success = false, Reason = "No character" }
	end

	local now = os.time()
	local readyAt = healCooldowns[player.UserId] or 0
	if now < readyAt then
		return { Success = false, Reason = "On cooldown", SecondsLeft = readyAt - now }
	end

	humanoid.Health = humanoid.MaxHealth
	healCooldowns[player.UserId] = now + NodeConfig.HealCooldownSeconds

	if typeof(node) == "Instance" and getNodeType(node) == "Heal" then
		commitFork(node)
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
	end

	pushInventory(player, profile)
	return { Success = true }
end

----------------------------------------------------------------------
-- Combat Outposts
----------------------------------------------------------------------

local activeRaids: { [number]: boolean } = {}                     -- userId -> true while raiding
local raidCooldowns: { [number]: { [Instance]: number } } = {}    -- userId -> node -> os.time() ready

local function runRaid(player: Player, node: Instance, tier: number)
	local userId = player.UserId
	local tierData = NodeConfig.CombatTiers[tier]
	local profile = DataService.Get(player)

	if not tierData or not profile then
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
		node:Destroy() -- expedition camps are one-time; the permanent base ones aren't
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

	local tierValue = node:FindFirstChild("Tier")
	local tier = (tierValue and tierValue:IsA("NumberValue")) and tierValue.Value or 1

	activeRaids[player.UserId] = true
	task.spawn(runRaid, player, node, tier)
end)

game.Players.PlayerRemoving:Connect(function(player)
	activeRaids[player.UserId] = nil
	healCooldowns[player.UserId] = nil
	raidCooldowns[player.UserId] = nil
end)

return NodeService
