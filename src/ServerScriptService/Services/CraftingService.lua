--[[
	CraftingService.lua
	Validates and resolves craft requests for Robots and Mods. Client calls the CraftItem
	RemoteFunction with a tree ("Robots" or "Mods") and a recipe key; server checks the recipe
	exists, tries to spend the cost via DataService, and grants the item on success.

	Weapons are NOT crafted here anymore — every weapon in the game is Forged (a unique rolled
	instance with its own Rarity/Affixes) rather than flat-crafted, so weapon creation moved
	entirely to ForgeService.lua/ForgeWeapon. CraftItem rejects tree == "Weapons" outright so an
	out-of-date client can't slip a request through.

	Also owns EquipMod — swapping which mod (if any) sits in one of a weapon/robot TYPE's
	ModConfig.SlotsPerItem slots. See ModConfig.lua's header comment for why mods apply per item
	type rather than per robot/weapon instance. Weapon mod-slots are still keyed by weaponKey
	(the TYPE), even though individual weapons are now per-instance via the Forge — equipping
	Speed Coil on "PipePistol" affects every Pipe Pistol instance you own at once, same simplified
	design as robots always had.

	And owns UndeployRobot (the missing other half of DeployRobot — was craftable/deployable but
	never un-deployable until the Inventory panel needed it). DeployRobot/UndeployRobot/EquipMod are
	NOT plot/station gated — direct player feedback was that changing your loadout (equipping,
	deploying, un-deploying) should work from anywhere; only actually CRAFTING a new item
	(CraftItem below) still requires being at the right station. This matches EquipWeapon's own
	gate removal in ForgeService.lua — see that file's header comment for the same reasoning.
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
	if tree == "Robots" then
		return CraftingRecipes.Robots[key]
	elseif tree == "Mods" then
		return ModConfig.Mods[key]
	end
	return nil
end

CraftItem.OnServerInvoke = function(player: Player, tree: string, key: string)
	if tree == "Weapons" then
		return { Success = false, Reason = "Weapons are Forged now — visit your Forge, not the Welding Station." }
	end

	if not PlotService.IsPlayerInOwnPlot(player) then
		return { Success = false, Reason = PlotConfig.NotInBaseMessage }
	end
	-- Robots/Mods are still assembled at the Welding Station — see StationConfig.Types.
	if (tree == "Robots" or tree == "Mods") and not StationService.IsPlayerNearStation(player, "Welding") then
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

	if tree == "Mods" and profile.CraftedMods[key] then
		return { Success = false, Reason = "Already own this mod" }
	end

	local spent = DataService.TrySpend(player, recipe.Cost)
	if not spent then
		return { Success = false, Reason = "Not enough resources" }
	end

	if tree == "Robots" then
		profile.CraftedRobots[key] = (profile.CraftedRobots[key] or 0) + 1
	else -- Mods
		profile.CraftedMods[key] = true
	end

	Remotes.InventoryUpdate:FireClient(player, {
		OreCounts = profile.OreCounts,
		CraftedRobots = profile.CraftedRobots,
		CraftedMods = profile.CraftedMods,
	})

	return { Success = true }
end

-- DeployRobot: separate RemoteFunction so a robot can be crafted once and deployed/
-- undeployed freely, capped at CraftingRecipes.BaseMaxDeployedRobots (+ pass bonus). Not
-- plot/station gated — see this file's header comment.
Remotes.DeployRobot.OnServerInvoke = function(player: Player, robotKey: string)
	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end
	if not profile.CraftedRobots[robotKey] or profile.CraftedRobots[robotKey] <= 0 then
		return { Success = false, Reason = "You don't own this robot" }
	end

	-- Deploying doesn't consume the owned copy (it's still "yours," just on/off defense duty), so
	-- this has to count how many of THIS key are already in DeployedRobots itself rather than
	-- checking CraftedRobots against zero — otherwise the same one owned copy could be deployed
	-- into every free slot at once, which is what the Inventory panel's Deploy/Undeploy toggle
	-- surfaced when it started showing "owned N, deployed M" side by side.
	local alreadyDeployed = 0
	for _, key in ipairs(profile.DeployedRobots) do
		if key == robotKey then
			alreadyDeployed += 1
		end
	end
	if alreadyDeployed >= profile.CraftedRobots[robotKey] then
		return { Success = false, Reason = "All owned copies of this robot are already deployed" }
	end

	local maxSlots = CraftingRecipes.BaseMaxDeployedRobots
	if profile.OwnedGamePasses.ExtraRobotSlot then
		maxSlots += 1
	end

	if #profile.DeployedRobots >= maxSlots then
		return { Success = false, Reason = "No free defense slots" }
	end

	table.insert(profile.DeployedRobots, robotKey)

	-- The client never merged the old return value's DeployedRobots into its local profile mirror
	-- (nothing displayed a deployed count before the Inventory panel needed one) — broadcasting
	-- through InventoryUpdate instead means the existing generic listener picks it up for free,
	-- same as every other loadout remote here.
	Remotes.InventoryUpdate:FireClient(player, {
		DeployedRobots = profile.DeployedRobots,
	})

	return { Success = true, DeployedRobots = profile.DeployedRobots }
end

-- UndeployRobot: the other half of DeployRobot — pulls ONE instance of robotKey off defense duty
-- (if more than one copy is deployed, only the first match found is removed; which physical
-- instance doesn't matter since they're identical). Doesn't touch CraftedRobots — undeploying
-- never destroys the robot, it just stops counting toward combat DPS. Not plot/station gated —
-- see this file's header comment.
Remotes.UndeployRobot.OnServerInvoke = function(player: Player, robotKey: string)
	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	local index
	for i, key in ipairs(profile.DeployedRobots) do
		if key == robotKey then
			index = i
			break
		end
	end
	if not index then
		return { Success = false, Reason = "That robot isn't currently deployed" }
	end

	table.remove(profile.DeployedRobots, index)

	Remotes.InventoryUpdate:FireClient(player, {
		DeployedRobots = profile.DeployedRobots,
	})

	return { Success = true, DeployedRobots = profile.DeployedRobots }
end

-- EquipMod: swaps whichever mod (or nil for "none") sits in one slot of a weapon/robot TYPE's
-- loadout. modKey=nil clears the slot. Rejects equipping the same mod into two slots of the same
-- item at once (would just double-apply one multiplier for no reason) and validates ownership of
-- both the item and the mod before writing anything. Not plot/station gated — see this file's
-- header comment.
Remotes.EquipMod.OnServerInvoke = function(player: Player, tree: string, itemKey: string, slotIndex: number, modKey: string?)
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
	-- idiom breaks the moment X can itself be false/nil. Weapon ownership is now "do I own ANY
	-- Forged instance of this type" (itemKey is a weaponKey, not an instance Id — mod slots are
	-- still per TYPE, see this file's header comment) rather than the old flat CraftedWeapons check.
	local owned
	if tree == "Weapons" then
		owned = false
		for _, weaponInstance in ipairs(profile.Weapons) do
			if weaponInstance.WeaponKey == itemKey then
				owned = true
				break
			end
		end
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

-- EquipWeapon moved to ForgeService.lua — it now operates on a Forged instance Id rather than a
-- weaponKey, since every weapon is a unique instance now. See ForgeService.EquipWeapon.

return CraftingService
