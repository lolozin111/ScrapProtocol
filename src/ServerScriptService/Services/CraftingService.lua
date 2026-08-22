--[[
	CraftingService.lua
	Validates and resolves craft requests for all three trees. Client calls the CraftItem
	RemoteFunction with a tree ("Weapons", "Robots", or "Mods") and a recipe key; server checks the
	recipe exists, tries to spend the cost via DataService, and grants the item on success.

	Also owns EquipMod — swapping which mod (if any) sits in one of a weapon/robot TYPE's
	ModConfig.SlotsPerItem slots. See ModConfig.lua's header comment for why mods apply per item
	type rather than per robot instance.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)
local ModConfig = require(ReplicatedStorage.Shared.ModConfig)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StationService = require(script.Parent.StationService)

local Remotes = ReplicatedStorage.Remotes
local CraftItem = Remotes.CraftItem

local CraftingService = {}

local function getRecipe(tree: string, key: string)
	if tree == "Weapons" then
		return CraftingRecipes.Weapons[key]
	elseif tree == "Robots" then
		return CraftingRecipes.Robots[key]
	elseif tree == "Mods" then
		return ModConfig.Mods[key]
	end
	return nil
end

CraftItem.OnServerInvoke = function(player: Player, tree: string, key: string)
	if not PlotService.IsPlayerInOwnPlot(player) then
		return { Success = false, Reason = PlotConfig.NotInBaseMessage }
	end
	-- Weapons/Robots/Mods are all assembled at the Welding Station — see StationConfig.Types.
	if (tree == "Weapons" or tree == "Robots" or tree == "Mods") and not StationService.IsPlayerNearStation(player, "Welding") then
		return { Success = false, Reason = StationConfig.Types.Welding.NotThereMessage }
	end

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
	if tree == "Mods" and profile.CraftedMods[key] then
		return { Success = false, Reason = "Already own this mod" }
	end

	local spent = DataService.TrySpend(player, recipe.Cost)
	if not spent then
		return { Success = false, Reason = "Not enough resources" }
	end

	if tree == "Weapons" then
		profile.CraftedWeapons[key] = true
	elseif tree == "Robots" then
		profile.CraftedRobots[key] = (profile.CraftedRobots[key] or 0) + 1
	else -- Mods
		profile.CraftedMods[key] = true
	end

	Remotes.InventoryUpdate:FireClient(player, {
		OreCounts = profile.OreCounts,
		CraftedWeapons = profile.CraftedWeapons,
		CraftedRobots = profile.CraftedRobots,
		CraftedMods = profile.CraftedMods,
	})

	return { Success = true }
end

-- DeployRobot: separate RemoteFunction so a robot can be crafted once and deployed/
-- undeployed freely, capped at CraftingRecipes.BaseMaxDeployedRobots (+ pass bonus).
Remotes.DeployRobot.OnServerInvoke = function(player: Player, robotKey: string)
	if not PlotService.IsPlayerInOwnPlot(player) then
		return { Success = false, Reason = PlotConfig.NotInBaseMessage }
	end
	if not StationService.IsPlayerNearStation(player, "Welding") then
		return { Success = false, Reason = StationConfig.Types.Welding.NotThereMessage }
	end

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

-- EquipMod: swaps whichever mod (or nil for "none") sits in one slot of a weapon/robot TYPE's
-- loadout. modKey=nil clears the slot. Rejects equipping the same mod into two slots of the same
-- item at once (would just double-apply one multiplier for no reason) and validates ownership of
-- both the item and the mod before writing anything.
Remotes.EquipMod.OnServerInvoke = function(player: Player, tree: string, itemKey: string, slotIndex: number, modKey: string?)
	if not PlotService.IsPlayerInOwnPlot(player) then
		return { Success = false, Reason = PlotConfig.NotInBaseMessage }
	end
	if not StationService.IsPlayerNearStation(player, "Welding") then
		return { Success = false, Reason = StationConfig.Types.Welding.NotThereMessage }
	end
	if tree ~= "Weapons" and tree ~= "Robots" then
		return { Success = false, Reason = "Unknown tree" }
	end
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > ModConfig.SlotsPerItem then
		return { Success = false, Reason = "Invalid slot" }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	-- NOTE: written as an explicit if/else, not `tree == "Weapons" and X or Y` — that ternary
	-- idiom breaks the moment X can itself be false/nil, which profile.CraftedWeapons[itemKey]
	-- (a boolean-or-nil field) very much can be.
	local owned
	if tree == "Weapons" then
		owned = profile.CraftedWeapons[itemKey] == true
	else
		owned = (profile.CraftedRobots[itemKey] or 0) > 0
	end
	if not owned then
		return { Success = false, Reason = "You don't own this item" }
	end

	if modKey ~= nil then
		if not ModConfig.Mods[modKey] then
			return { Success = false, Reason = "Unknown mod" }
		end
		if not profile.CraftedMods[modKey] then
			return { Success = false, Reason = "You don't own this mod" }
		end
	end

	profile.EquippedMods[itemKey] = profile.EquippedMods[itemKey] or {}

	if modKey ~= nil then
		for slot, existingKey in pairs(profile.EquippedMods[itemKey]) do
			if existingKey == modKey and slot ~= slotIndex then
				return { Success = false, Reason = "Already equipped in another slot" }
			end
		end
	end

	profile.EquippedMods[itemKey][slotIndex] = modKey

	Remotes.InventoryUpdate:FireClient(player, {
		EquippedMods = profile.EquippedMods,
	})

	return { Success = true, EquippedMods = profile.EquippedMods[itemKey] }
end

return CraftingService
