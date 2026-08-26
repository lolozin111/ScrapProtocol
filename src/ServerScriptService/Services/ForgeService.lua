--[[
	ForgeService.lua
	Owns the Forge station's whole loadout: rolling brand-new unique weapon instances
	(ForgeWeapon), choosing which one counts for combat (EquipWeapon — moved here from
	CraftingService.lua since it now targets an instance Id, not a shared weaponKey), and the two
	ways to push your luck (CraftLuckPotion, UpgradeForgeTier). See ForgeConfig.lua for every
	tunable number behind rarity odds, affix rolls, Luck, and Pity.

	Every weapon in the game comes from here now — CraftingService.lua's CraftItem explicitly
	rejects tree == "Weapons" and points players at this station instead.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)
local WeaponFamilyConfig = require(ReplicatedStorage.Shared.WeaponFamilyConfig)
local ForgeConfig = require(ReplicatedStorage.Shared.ForgeConfig)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StationService = require(script.Parent.StationService)
local WeaponToolService = require(script.Parent.WeaponToolService)

local Remotes = ReplicatedStorage.Remotes

local ForgeService = {}

-- Index of a rarity key within ForgeConfig.RarityOrder (1 = Common ... 5 = Legendary). Used both
-- to floor a pity-forced roll at Pity.MinRarity and to check whether a roll landed at or above it.
local function rarityIndex(rarityKey: string): number
	for i, key in ipairs(ForgeConfig.RarityOrder) do
		if key == rarityKey then
			return i
		end
	end
	return 1
end

-- Weighted rarity roll. Every non-Common tier's weight scales up by (1 + luckPoints/100) — Common
-- itself never moves, so more luck just means the non-Common slice of the total pie keeps growing
-- relative to it. luckPoints is your Forge's ForgeTiers Bonus plus, if the player opted to burn a
-- Luck Potion on this roll, LuckPotion.Bonus on top — see ForgeWeapon below.
--
-- floorIndex (default 1 = no floor) restricts the roll to ForgeConfig.RarityOrder[floorIndex..] —
-- this is how a pity-forced roll guarantees at least Pity.MinRarity: the weighted math is
-- identical, it's just never allowed to consider anything below the floor.
local function rollRarity(luckPoints: number, floorIndex: number?): string
	local floor = floorIndex or 1
	local weights = {}
	local totalWeight = 0
	for i, rarityKey in ipairs(ForgeConfig.RarityOrder) do
		if i >= floor then
			local base = ForgeConfig.BaseWeights[rarityKey] or 0
			local weight = (rarityKey == "Common") and base or (base * (1 + luckPoints / 100))
			weights[rarityKey] = weight
			totalWeight += weight
		end
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for i, rarityKey in ipairs(ForgeConfig.RarityOrder) do
		if i >= floor then
			cumulative += weights[rarityKey]
			if roll <= cumulative then
				return rarityKey
			end
		end
	end
	return ForgeConfig.RarityOrder[floor] -- unreachable in practice; guards float rounding at the tail
end

-- Rolls AffixCountByRarity[rarity] distinct affixes (deduped by Key, not Stat — two different
-- Damage-boosting affixes CAN both land on the same weapon, see ForgeConfig.AffixPool's comment)
-- each with an independently rolled Min..Max magnitude.
local function rollAffixes(rarity: string)
	local count = ForgeConfig.AffixCountByRarity[rarity] or 0
	local affixes = {}
	local usedKeys = {}
	local attempts = 0
	while #affixes < count and attempts < 20 do
		attempts += 1
		local entry = ForgeConfig.AffixPool[math.random(1, #ForgeConfig.AffixPool)]
		if not usedKeys[entry.Key] then
			usedKeys[entry.Key] = true
			local magnitude = entry.Min + math.random() * (entry.Max - entry.Min)
			table.insert(affixes, {
				AffixKey = entry.Key,
				Stat = entry.Stat,
				Label = entry.Label,
				Magnitude = magnitude,
			})
		end
	end
	return affixes
end

-- ForgeWeapon: spends the recipe's normal Cost (same CraftingRecipes.Weapons table as the old
-- flat-craft system used) and mints a brand-new unique instance — never upgrades or replaces one
-- you already own, every roll is its own item. usePotion=true additionally requires (and consumes)
-- one Luck Potion for a one-time luck boost on just this roll; checked and validated BEFORE the
-- recipe cost is spent, so a failed potion check never leaves the player out resources for nothing.
--
-- Pity: profile.ForgePityCounter increments on every roll and resets to 0 the moment a roll (forced
-- or not) lands ForgeConfig.Pity.MinRarity or better. Once the counter reaches Pity.Threshold, THIS
-- roll is forced to at least MinRarity (still randomized/luck-weighted among MinRarity and up, not
-- a flat guarantee of exactly MinRarity) — a genuinely unlucky streak always pays off eventually.
Remotes.ForgeWeapon.OnServerInvoke = function(player: Player, weaponKey: string, usePotion: boolean?)
	if not PlotService.IsPlayerInOwnPlot(player) then
		return { Success = false, Reason = PlotConfig.NotInBaseMessage }
	end
	if not StationService.IsPlayerNearStation(player, "Forge") then
		return { Success = false, Reason = StationConfig.Types.Forge.NotThereMessage }
	end

	local recipe = CraftingRecipes.Weapons[weaponKey]
	if not recipe then
		return { Success = false, Reason = "Unknown weapon" }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	-- Family gate. The Forge UI already hides locked families, but that is a convenience: a client
	-- can invoke this remote with any weapon key it likes, so the real check has to be here. Without
	-- it every Black Market gun blueprint would be decorative.
	if not WeaponFamilyConfig.IsUnlocked(profile, recipe.Family) then
		local family = WeaponFamilyConfig.Families[recipe.Family]
		return {
			Success = false,
			Reason = family
				and ("You haven't unlocked %s yet — its blueprint (%s) comes from a Black Market case."):format(
					family.DisplayName, WeaponFamilyConfig.BlueprintName(recipe.Family))
				or ("%s isn't in a valid weapon family — check CraftingRecipes."):format(weaponKey),
		}
	end

	if usePotion and (profile.LuckPotions or 0) <= 0 then
		return { Success = false, Reason = "No Luck Potions to use" }
	end

	local spent = DataService.TrySpend(player, recipe.Cost)
	if not spent then
		return { Success = false, Reason = "Not enough resources" }
	end

	if usePotion then
		profile.LuckPotions -= 1
	end

	local forgeTierData = ForgeConfig.ForgeTiers[profile.ForgeTier or 1]
	local luckPoints = (forgeTierData and forgeTierData.Bonus or 0) + (usePotion and ForgeConfig.LuckPotion.Bonus or 0)

	-- Pity is evaluated on the counter BEFORE this roll increments it, so Threshold rolls without a
	-- Rare+ forces the roll AFTER them — which is what ForgeConfig and the README both describe
	-- ("Threshold rolls in a row without landing MinRarity forces the NEXT roll"). Incrementing
	-- first made it fire one roll early: the 15th roll was forced rather than the 16th.
	local pityFloorIndex = rarityIndex(ForgeConfig.Pity.MinRarity)
	local pityForced = (profile.ForgePityCounter or 0) >= ForgeConfig.Pity.Threshold
	profile.ForgePityCounter = (profile.ForgePityCounter or 0) + 1

	local rarity = rollRarity(luckPoints, pityForced and pityFloorIndex or nil)
	if rarityIndex(rarity) >= pityFloorIndex then
		profile.ForgePityCounter = 0
	end

	local affixes = rollAffixes(rarity)

	local id = "w" .. profile.NextWeaponId
	profile.NextWeaponId += 1

	local instance = {
		Id = id,
		WeaponKey = weaponKey,
		Rarity = rarity,
		Affixes = affixes,
	}
	table.insert(profile.Weapons, instance)

	-- First weapon ever Forged auto-equips — nothing worse than rolling your very first gun and
	-- having no idea it isn't actually in your hand yet. Every roll after that stays an explicit
	-- choice made via EquipWeapon (now in the Inventory panel, not this station's own tab).
	if not profile.EquippedWeaponId and #profile.Weapons == 1 then
		profile.EquippedWeaponId = id
		WeaponToolService.SyncEquippedTool(player, instance)
	end

	Remotes.InventoryUpdate:FireClient(player, {
		OreCounts = profile.OreCounts,
		Weapons = profile.Weapons,
		LuckPotions = profile.LuckPotions,
		ForgePityCounter = profile.ForgePityCounter,
		EquippedWeaponId = profile.EquippedWeaponId or false,
	})

	return { Success = true, Weapon = instance }
end

-- EquipWeapon: sets which single owned weapon INSTANCE actually counts toward combat DPS (see
-- CombatMath.GetPlayerCombatDPS) AND syncs the physical gun Tool into the player's hotbar (see
-- WeaponToolService.lua) — the two always change together, there's no path where EquippedWeaponId
-- and "what Tool is in your Backpack" can drift apart. weaponInstanceId=nil clears the explicit
-- choice AND empties the hotbar of any gun Tool, falling back to CombatMath's "auto-pick best owned
-- instance" behavior for the DPS number even though nothing physical is equipped to fire it with.
-- Rejects equipping an instance not owned; otherwise this never fails on its own merit.
--
-- Deliberately NOT gated behind plot/station anymore — direct player feedback was that browsing
-- and changing your loadout should work from anywhere, only the Forge/Welding Station's own
-- CRAFTING actions (ForgeWeapon, CraftItem, etc.) should require standing at the right prop. Moved
-- here from CraftingService.lua now that it targets a per-instance Id instead of a shared
-- weaponKey, and the Forge (not the Welding Station) is where weapons live. Called from the
-- Inventory panel now, not this station's own Weapons tab — the Forge tab itself is craft-only.
Remotes.EquipWeapon.OnServerInvoke = function(player: Player, weaponInstanceId: string?)
	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	local matchedInstance = nil
	if weaponInstanceId ~= nil then
		for _, weaponInstance in ipairs(profile.Weapons) do
			if weaponInstance.Id == weaponInstanceId then
				matchedInstance = weaponInstance
				break
			end
		end
		if not matchedInstance then
			return { Success = false, Reason = "You don't own this weapon" }
		end
	end

	profile.EquippedWeaponId = weaponInstanceId
	WeaponToolService.SyncEquippedTool(player, matchedInstance)

	-- `weaponInstanceId or false`, same reasoning as every other nil-able field this codebase
	-- broadcasts: a Lua table constructor drops a field entirely when its value is nil, so clearing
	-- the equip would silently vanish from this patch before it even reached the network. false is
	-- falsy everywhere this gets compared, so it's a safe stand-in that actually survives the
	-- table literal.
	Remotes.InventoryUpdate:FireClient(player, {
		EquippedWeaponId = weaponInstanceId or false,
	})

	return { Success = true, EquippedWeaponId = profile.EquippedWeaponId }
end

-- CraftLuckPotion: a flat-craftable consumable with no ownership cap — hold as many Potions as you
-- can afford, each burned individually via ForgeWeapon's usePotion parameter.
Remotes.CraftLuckPotion.OnServerInvoke = function(player: Player)
	if not PlotService.IsPlayerInOwnPlot(player) then
		return { Success = false, Reason = PlotConfig.NotInBaseMessage }
	end
	if not StationService.IsPlayerNearStation(player, "Forge") then
		return { Success = false, Reason = StationConfig.Types.Forge.NotThereMessage }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	local spent = DataService.TrySpend(player, ForgeConfig.LuckPotion.Cost)
	if not spent then
		return { Success = false, Reason = "Not enough resources" }
	end

	profile.LuckPotions = (profile.LuckPotions or 0) + 1

	Remotes.InventoryUpdate:FireClient(player, {
		OreCounts = profile.OreCounts,
		LuckPotions = profile.LuckPotions,
	})

	return { Success = true, LuckPotions = profile.LuckPotions }
end

-- UpgradeForgeTier: sequential permanent tier upgrade on the Forge itself, same pattern as
-- MiningService.UpgradeTool / MineShaftService.UpgradeSuit — always the next tier up from whatever
-- the player currently has, costed by ForgeConfig.ForgeTierCosts. Every tier's Bonus feeds straight
-- into every future roll's luck (see ForgeWeapon above) — there's no separate "Luck" stat to buy.
Remotes.UpgradeForgeTier.OnServerInvoke = function(player: Player)
	if not PlotService.IsPlayerInOwnPlot(player) then
		return { Success = false, Reason = PlotConfig.NotInBaseMessage }
	end
	if not StationService.IsPlayerNearStation(player, "Forge") then
		return { Success = false, Reason = StationConfig.Types.Forge.NotThereMessage }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	local nextTier = (profile.ForgeTier or 1) + 1
	local nextForgeTierData = ForgeConfig.ForgeTiers[nextTier]
	if not nextForgeTierData then
		return { Success = false, Reason = "Already at the max Forge tier" }
	end

	local cost = ForgeConfig.ForgeTierCosts[nextTier]
	if not cost then
		return { Success = false, Reason = "No cost configured for this tier — add one to ForgeConfig.ForgeTierCosts" }
	end

	local spent = DataService.TrySpend(player, cost)
	if not spent then
		return { Success = false, Reason = "Not enough resources" }
	end

	profile.ForgeTier = nextTier

	Remotes.InventoryUpdate:FireClient(player, {
		OreCounts = profile.OreCounts,
		ForgeTier = profile.ForgeTier,
	})

	return { Success = true, ForgeTier = profile.ForgeTier }
end

return ForgeService
