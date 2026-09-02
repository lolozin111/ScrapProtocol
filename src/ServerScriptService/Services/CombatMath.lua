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
-- profile.EquippedMods[itemKey]. The loop itself MOVED to ModConfig.ApplyMods (Shared) and this is
-- now a one-line delegate: the Welding Station's rig diagram needs the same mod-adjusted numbers
-- client-side, and this module lives in ServerScriptService where the HUD cannot reach it. See
-- ModConfig.ApplyMods's own comment for why a second copy was the wrong answer. Kept as a local
-- alias rather than inlining ModConfig.ApplyMods at both call sites below, so the name every
-- reader of this file already knows still resolves here.
local applyMods = ModConfig.ApplyMods

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

-- Returns the fully mod-AND-affix-adjusted stats for one Forged weapon instance (see
-- DataService.lua's profile.Weapons — { Id, WeaponKey, Rarity, Affixes }). Starts from the same
-- type-level mod multipliers GetEffectiveStats above applies (mods are still per weapon TYPE, not
-- per instance — see ModConfig.lua's header comment), then layers the instance's own Forge-rolled
-- Affixes on top. Each affix's Magnitude is stored as "+X%" (e.g. 0.23 = +23%), applied
-- multiplicatively and independently — two distinct affixes on the same Stat (e.g. Sharpened +
-- Overcharged both boosting Damage) compound as (1+m1)*(1+m2), not added together.
function CombatMath.GetEffectiveWeaponStats(weaponInstance, profile)
	local recipe = CraftingRecipes.Weapons[weaponInstance.WeaponKey]
	if not recipe then
		return nil
	end

	local fireRate, damage = applyMods(recipe.FireRate, recipe.BaseDamage, nil, weaponInstance.WeaponKey, profile)
	for _, affix in ipairs(weaponInstance.Affixes or {}) do
		if affix.Stat == "FireRateMultiplier" then
			fireRate *= (1 + affix.Magnitude)
		elseif affix.Stat == "DamageMultiplier" then
			damage *= (1 + affix.Magnitude)
		end
	end

	return {
		FireRate = fireRate,
		Damage = damage,
		DPS = fireRate * damage,
	}
end

-- One equipped weapon's DPS (you only ever wield one at a time) plus every currently deployed
-- robot's DPS, mods+affixes applied. Replace this once real gun-firing/hit-detection exists — see
-- the note at the top of WaveService.lua for the intended swap-out point.
--
-- profile.EquippedWeaponId (set via the EquipWeapon remote, see ForgeService.lua) is an explicit
-- player choice referencing one specific Forged instance's Id — if it's set AND that instance is
-- still owned, its DPS is what counts, full stop, even if a higher-DPS instance sits uncrafted-
-- equipped in the inventory. If it's nil (never equipped) or points at an instance no longer owned,
-- this falls back to auto-picking whichever owned instance currently has the highest DPS.
function CombatMath.GetPlayerCombatDPS(profile): number
	local weaponDPS = 0
	local equippedInstance = nil
	if profile.EquippedWeaponId then
		for _, weaponInstance in ipairs(profile.Weapons) do
			if weaponInstance.Id == profile.EquippedWeaponId then
				equippedInstance = weaponInstance
				break
			end
		end
	end

	if equippedInstance then
		local stats = CombatMath.GetEffectiveWeaponStats(equippedInstance, profile)
		weaponDPS = stats and stats.DPS or 0
	else
		for _, weaponInstance in ipairs(profile.Weapons) do
			local stats = CombatMath.GetEffectiveWeaponStats(weaponInstance, profile)
			if stats and stats.DPS > weaponDPS then
				weaponDPS = stats.DPS
			end
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
