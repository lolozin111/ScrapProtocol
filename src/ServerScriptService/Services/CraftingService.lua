--[[
	CraftingService.lua
	Validates and resolves craft requests for both trees. Client calls the CraftItem
	RemoteFunction with a tree ("Weapons" or "Robots") and a recipe key; server checks the
	recipe exists, tries to spend the cost via DataService, and grants the item on success.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)
local DataService = require(script.Parent.DataService)

local Remotes = ReplicatedStorage.Remotes
local CraftItem = Remotes.CraftItem

local CraftingService = {}

local function getRecipe(tree: string, key: string)
	if tree == "Weapons" then
		return CraftingRecipes.Weapons[key]
	elseif tree == "Robots" then
		return CraftingRecipes.Robots[key]
	end
	return nil
end

CraftItem.OnServerInvoke = function(player: Player, tree: string, key: string)
	local recipe = getRecipe(tree, key)
	if not recipe then
		return { Success = false, Reason = "Unknown recipe" }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	if tree == "Weapons" and profile.CraftedWeapons[key] then
		return { Success = false, Reason = "Already own this weapon" }
	end

	local spent = DataService.TrySpend(player, recipe.Cost)
	if not spent then
		return { Success = false, Reason = "Not enough resources" }
	end

	if tree == "Weapons" then
		profile.CraftedWeapons[key] = true
	else
		profile.CraftedRobots[key] = (profile.CraftedRobots[key] or 0) + 1
	end

	Remotes.InventoryUpdate:FireClient(player, {
		OreCounts = profile.OreCounts,
		CraftedWeapons = profile.CraftedWeapons,
		CraftedRobots = profile.CraftedRobots,
	})

	return { Success = true }
end

-- DeployRobot: separate RemoteFunction so a robot can be crafted once and deployed/
-- undeployed freely, capped at CraftingRecipes.BaseMaxDeployedRobots (+ pass bonus).
Remotes.DeployRobot.OnServerInvoke = function(player: Player, robotKey: string)
	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end
	if not profile.CraftedRobots[robotKey] or profile.CraftedRobots[robotKey] <= 0 then
		return { Success = false, Reason = "You don't own this robot" }
	end

	local maxSlots = CraftingRecipes.BaseMaxDeployedRobots
	if profile.OwnedGamePasses.ExtraRobotSlot then
		maxSlots += 1
	end

	if #profile.DeployedRobots >= maxSlots then
		return { Success = false, Reason = "No free defense slots" }
	end

	table.insert(profile.DeployedRobots, robotKey)
	return { Success = true, DeployedRobots = profile.DeployedRobots }
end

return CraftingService
