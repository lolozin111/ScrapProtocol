--[[
	DataService.lua
	Owns all player save data. Every other service reads/writes through this module —
	nothing else is allowed to touch DataStoreService directly.

	This is a minimal-but-safe hand-rolled wrapper (retry-on-fail, autosave, save-on-leave,
	save-on-server-shutdown). It is NOT session-locked across servers, which is the one thing
	a real production simulator needs beyond this. Before you scale past a single test server,
	swap this for ProfileService (loleris) — same public API, much safer under real traffic.
	Search "ProfileService Roblox" — it's free and it's the de facto standard for this genre.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RaidEnergyConfig = require(ReplicatedStorage.Shared.RaidEnergyConfig)

local PlayerDataStore = DataStoreService:GetDataStore("SalvageProtocol_PlayerData_v1")

local DataService = {}

local cache: { [number]: any } = {}
local AUTOSAVE_INTERVAL = 120 -- seconds

local function defaultProfile()
	return {
		Scrap = 0,
		Cores = 0,
		OreCounts = {
			ScrapIron = 0,
			CopperWire = 0,
			SteelPlating = 0,
			GoldContacts = 0,
			VoidiumShard = 0,
		},
		ToolTier = 1,
		SuitTier = 1,           -- environmental protection for the mine shaft's depth hazards — see
		                        -- MineShaftConfig.SuitTiers/SuitTierCosts, purchased via Workbench -> Suit
		BaseTier = 1,           -- which BaseConfig.Tiers Model BaseService clones onto the player's
		                        -- plot — see BaseConfig.lua; no purchase flow yet, always 1 for now
		OwnedGamePasses = {},   -- [gamePassKey] = true
		CraftedWeapons = {},    -- [weaponKey] = true — LEGACY, superseded by Weapons below. Kept
			-- around only as the migration source for saves written before the Forge existed (see
			-- migrateLegacyWeapons); nothing ever writes a new true into this table anymore.
		Weapons = {},           -- list of unique weapon instances: { Id, WeaponKey, Rarity, Affixes }.
			-- Every weapon in the game is Forged (ForgeService.ForgeWeapon), not flat-crafted, so
			-- each one is its own instance with its own randomly rolled Rarity (see ModConfig
			-- .Rarities) and 0-3 Affixes (see ForgeConfig.AffixPool) layered on top of
			-- CraftingRecipes.Weapons' base stats — see CombatMath.GetEffectiveWeaponStats.
		NextWeaponId = 1,       -- incrementing counter that mints each new Weapons instance's Id
			-- ("w1", "w2", ...) — never reused, even across a weapon being lost/sold in the future.
			-- EquippedWeaponId (string?) is deliberately NOT listed here, same reasoning as the old
			-- EquippedWeapon field it replaces: pairs() skips nil-valued table entries, so a `= nil`
			-- line would be a no-op, and profile.EquippedWeaponId reads as nil identically whether
			-- the key is present-and-nil or simply absent. nil means "no explicit choice made yet" —
			-- CombatMath.GetPlayerCombatDPS falls back to auto-picking the best owned INSTANCE by DPS
			-- in that case. Set via the EquipWeapon remote (now on ForgeService.lua), same gate as
			-- EquipMod/DeployRobot but scoped to the Forge instead of the Welding Station.
		ForgeTier = 1,          -- your Forge's own permanent upgrade track — see ForgeConfig
			-- .ForgeTiers/ForgeTierCosts, purchased via the Forge's Weapons tab, same shape as
			-- SuitTier/ToolTier. A better Forge rolls luckier, full stop — no separate "Luck" stat.
		LuckPotions = 0,        -- consumable count — see ForgeConfig.LuckPotion, craftable at the
			-- Forge and burned on a single ForgeWeapon roll for a one-time luck boost.
		ForgePityCounter = 0,   -- rolls since your last Rare-or-better — see ForgeConfig.Pity and
			-- ForgeService.ForgeWeapon. Resets to 0 the moment a roll (forced or natural) lands
			-- Pity.MinRarity or better; forces the next roll to that floor once it hits Threshold.
		RefinedOreCounts = {},  -- [refinedKey] = amount owned — see RefinedOreConfig.lua/
			-- SmeltService.lua. Keyed by RefinedKey (e.g. "SteelIngot"), not the raw ore key it came
			-- from. Starts empty and fills in on demand, same convention as CraftedRobots below.
			-- SmeltJob (table?) is deliberately NOT listed here, same reasoning as EquippedWeaponId
			-- above: pairs() skips nil-valued entries, so a `= nil` line would be a no-op. nil means
			-- "no smelting job in progress right now." When active its shape is { OreKey, Quantity,
			-- RefinedKey, RefinedAmount, FinishTime } — set/cleared by SmeltService.lua, always
			-- broadcast as `profile.SmeltJob or false` so a clear actually survives the network (see
			-- that file's completion loop).
		CraftedRobots = {},     -- [robotKey] = count owned
		CraftedStructures = {}, -- [structureKey] = true (e.g. "AutoMiner" — see AutoMinerService)
		DeployedRobots = {},    -- list of robotKeys currently on defense duty
		CraftedMods = {},       -- [modKey] = true (permanent unlock, same shape as CraftedWeapons) — see ModConfig
		EquippedMods = {},      -- [itemKey][slotIndex] = modKey — itemKey is a weaponKey or robotKey,
		                        -- slotIndex runs 1..ModConfig.SlotsPerItem. Applies per item TYPE, not
		                        -- per robot instance — see ModConfig.lua's header comment.
		HighestWave = 0,
		InstantCraftTokens = 0,
		WaveReviveTokens = 0,
		Energy = RaidEnergyConfig.MaxEnergy, -- starts full so a fresh player isn't stuck waiting — see RaidEnergyService
	}
end

-- Backfills any fields added to defaultProfile() after a player's save was already written —
-- without this, an existing save loaded from before a field existed (e.g. CraftedStructures)
-- would be missing it entirely rather than getting the new default, and every service that
-- reads it would need its own nil-guard. One shallow pass here is simpler and covers every
-- field uniformly; only fills in what's actually missing, never touches existing values.
local function backfillMissingFields(profile)
	for key, defaultValue in pairs(defaultProfile()) do
		if profile[key] == nil then
			profile[key] = defaultValue
		end
	end
	return profile
end

-- One-time upgrade path from the old flat "own every copy of this type" weapon model to the
-- Forge's per-instance model (unique Id + Rarity + Affixes per weapon). Self-guarding: only
-- converts anything when there's legacy ownership AND it hasn't already been converted — once
-- profile.Weapons is non-empty this is a permanent no-op, even on a save where CraftedWeapons
-- still has old `true` entries sitting in it (they're just never looked at again after this).
-- Legacy weapons come back as Common-rarity, zero-affix instances — nothing is deleted or downgraded
-- in value, they just didn't exist under a rarity system when they were originally crafted.
local function migrateLegacyWeapons(profile)
	if #profile.Weapons > 0 then
		return profile
	end
	local hasLegacy = false
	for _, owned in pairs(profile.CraftedWeapons) do
		if owned then
			hasLegacy = true
			break
		end
	end
	if not hasLegacy then
		return profile
	end
	for weaponKey, owned in pairs(profile.CraftedWeapons) do
		if owned then
			local id = "w" .. profile.NextWeaponId
			profile.NextWeaponId += 1
			table.insert(profile.Weapons, {
				Id = id,
				WeaponKey = weaponKey,
				Rarity = "Common",
				Affixes = {},
			})
		end
	end
	return profile
end

local function loadProfile(userId: number)
	local key = "Player_" .. userId
	local data
	local ok, err = pcall(function()
		data = PlayerDataStore:GetAsync(key)
	end)
	if not ok then
		warn("[DataService] GetAsync failed for", userId, err)
	end
	local profile = backfillMissingFields(data or defaultProfile())
	profile = migrateLegacyWeapons(profile)
	return profile
end

local function saveProfile(userId: number)
	local profile = cache[userId]
	if not profile then
		return
	end
	local key = "Player_" .. userId
	local ok, err = pcall(function()
		PlayerDataStore:SetAsync(key, profile)
	end)
	if not ok then
		warn("[DataService] SetAsync failed for", userId, err)
	end
end

function DataService.Get(player: Player)
	return cache[player.UserId]
end

function DataService.AddCurrency(player: Player, currencyKey: string, amount: number)
	local profile = cache[player.UserId]
	if not profile then
		return
	end
	profile[currencyKey] = (profile[currencyKey] or 0) + amount
end

function DataService.AddOre(player: Player, oreKey: string, amount: number)
	local profile = cache[player.UserId]
	if not profile then
		return
	end
	profile.OreCounts[oreKey] = (profile.OreCounts[oreKey] or 0) + amount
end

-- refinedKey is a RefinedOreConfig.Ores[...].RefinedKey (e.g. "SteelIngot"), not a raw ore key —
-- see SmeltService.lua's completion loop, the only caller today.
function DataService.AddRefinedOre(player: Player, refinedKey: string, amount: number)
	local profile = cache[player.UserId]
	if not profile then
		return
	end
	profile.RefinedOreCounts[refinedKey] = (profile.RefinedOreCounts[refinedKey] or 0) + amount
end

-- costTable example: { ScrapIron = 25, CopperWire = 10 } — ore keys and/or "Scrap"/"Cores".
-- Returns true and deducts everything atomically, or false and deducts nothing.
function DataService.TrySpend(player: Player, costTable: { [string]: number }): boolean
	local profile = cache[player.UserId]
	if not profile then
		return false
	end

	for key, amount in pairs(costTable) do
		local available = (key == "Scrap" or key == "Cores")
			and (profile[key] or 0)
			or (profile.OreCounts[key] or 0)
		if available < amount then
			return false
		end
	end

	for key, amount in pairs(costTable) do
		if key == "Scrap" or key == "Cores" then
			profile[key] -= amount
		else
			profile.OreCounts[key] -= amount
		end
	end

	return true
end

function DataService.SetHighestWave(player: Player, wave: number)
	local profile = cache[player.UserId]
	if not profile then
		return
	end
	if wave > profile.HighestWave then
		profile.HighestWave = wave
	end
end

-- Force an immediate save. Use this right after granting a real-money purchase —
-- Roblox requires the grant to be persisted before you report PurchaseGranted,
-- otherwise a server crash between grant and autosave loses the player's purchase.
function DataService.Save(player: Player)
	saveProfile(player.UserId)
end

Players.PlayerAdded:Connect(function(player)
	cache[player.UserId] = loadProfile(player.UserId)
end)

Players.PlayerRemoving:Connect(function(player)
	saveProfile(player.UserId)
	cache[player.UserId] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveProfile(player.UserId)
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for userId in pairs(cache) do
			saveProfile(userId)
		end
	end
end)

-- GetProfile: lets the client pull a full snapshot on HUD startup (e.g. after
-- spawning) instead of waiting for the next push-based InventoryUpdate, which
-- avoids a race where the HUD builds before the first update ever fires.
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
Remotes.GetProfile.OnServerInvoke = function(player: Player)
	local profile = cache[player.UserId]
	local attempts = 0
	while not profile and attempts < 50 do -- profile may still be loading right after join
		task.wait(0.1)
		profile = cache[player.UserId]
		attempts += 1
	end
	return profile
end

return DataService
