--[[
	CombatMath.lua
	Shared combat math used by both WaveService (home-base defense) and NodeService
	(outpost raids), so the two systems can never drift out of sync on how DPS is derived.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)

local CombatMath = {}

-- Best owned weapon's DPS (you only ever wield one at a time) plus every currently
-- deployed robot's DPS. Replace this once real gun-firing/hit-detection exists —
-- see the note at the top of WaveService.lua for the intended swap-out point.
function CombatMath.GetPlayerCombatDPS(profile): number
	local weaponDPS = 0
	for weaponKey in pairs(profile.CraftedWeapons) do
		local recipe = CraftingRecipes.Weapons[weaponKey]
		if recipe and recipe.DPS > weaponDPS then
			weaponDPS = recipe.DPS
		end
	end

	local robotDPS = 0
	for _, robotKey in ipairs(profile.DeployedRobots) do
		local recipe = CraftingRecipes.Robots[robotKey]
		if recipe then
			robotDPS += recipe.DPS
		end
	end

	return weaponDPS + robotDPS
end

return CombatMath
