--[[
	CombatMath.lua
	Shared combat math used by both WaveService (home-base defense) and NodeService
	(outpost raids), so the two systems can never drift out of sync on how DPS is derived.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)
local ModConfig = require(ReplicatedStorage.Shared.ModConfig)

local CombatMath = {}

local function getRecipe(tree: string, key: string)
	if tree == "Weapons" then
		return CraftingRecipes.Weapons[key]
	elseif tree == "Robots" then
		return CraftingRecipes.Robots[key]
	end
	return nil
end

-- Multiplies a base recipe's FireRate/BaseDamage/HP by whatever mods currently sit in
-- profile.EquippedMods[itemKey] (a {[slotIndex]=modKey} table, may be nil or sparse). A mod that
-- doesn't touch a given stat simply has no multiplier field for it (see ModConfig.lua) — treated
-- as 1x/no-op here rather than needing special-casing per mod.
local function applyMods(fireRate: number, baseDamage: number, hp: number?, itemKey: string, profile)
	local equipped = profile.EquippedMods and profile.EquippedMods[itemKey]
	if not equipped then
		return fireRate, baseDamage, hp
	end
	for _, modKey in pairs(equipped) do
		local mod = modKey and ModConfig.Mods[modKey]
		if mod then
			if mod.FireRateMultiplier then
				fireRate *= mod.FireRateMultiplier
			end
			if mod.DamageMultiplier then
				baseDamage *= mod.DamageMultiplier
			end
			if hp and mod.HPMultiplier then
				hp *= mod.HPMultiplier
			end
		end
	end
	return fireRate, baseDamage, hp
end

-- Returns the fully mod-adjusted stats for one weapon/robot recipe, given a player's profile.
-- Used both by the HUD (to show live numbers) and internally by GetPlayerCombatDPS below.
-- Mods apply per item TYPE, not per robot instance — see ModConfig.lua's header comment for why.
function CombatMath.GetEffectiveStats(tree: string, key: string, profile)
	local recipe = getRecipe(tree, key)
	if not recipe then
		return nil
	end

	local fireRate, damage, hp = applyMods(recipe.FireRate, recipe.BaseDamage, recipe.HP, key, profile)
	return {
		FireRate = fireRate,
		Damage = damage,
		DPS = fireRate * damage,
		HP = hp,
	}
end

-- Best owned weapon's DPS (you only ever wield one at a time) plus every currently
-- deployed robot's DPS, mods applied. Replace this once real gun-firing/hit-detection exists —
-- see the note at the top of WaveService.lua for the intended swap-out point.
function CombatMath.GetPlayerCombatDPS(profile): number
	local weaponDPS = 0
	for weaponKey in pairs(profile.CraftedWeapons) do
		local stats = CombatMath.GetEffectiveStats("Weapons", weaponKey, profile)
		if stats and stats.DPS > weaponDPS then
			weaponDPS = stats.DPS
		end
	end

	local robotDPS = 0
	for _, robotKey in ipairs(profile.DeployedRobots) do
		local stats = CombatMath.GetEffectiveStats("Robots", robotKey, profile)
		if stats then
			robotDPS += stats.DPS
		end
	end

	return weaponDPS + robotDPS
end

return CombatMath
