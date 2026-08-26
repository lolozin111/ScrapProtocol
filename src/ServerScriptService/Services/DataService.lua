--[[
	DataService.lua
	Owns all player save data. Every other service reads/writes through this module —
	nothing else is allowed to touch DataStoreService directly.

	SESSION LOCKING (added — this used to be the file's one known production hazard).

	The old version used GetAsync to load and SetAsync to save. Those are two separate,
	non-atomic operations with no notion of ownership, which meant two servers could hold the same
	player's profile at once. The concrete way that loses data: you leave server A and join server B
	before A has finished saving. B loads the pre-A state, you play, then A's save lands and
	overwrites it — or B's does, and A's session is gone. Nothing errors; progress just silently
	rewinds. It is the single worst class of bug a game like this can ship with, because the player
	experiences it as "the game ate my stuff" and there is no log of it happening.

	The fix is a lock stored alongside the data, taken and released through UpdateAsync — which IS
	atomic per key, so two servers racing to claim the same profile cannot both win:

	  load   -> UpdateAsync: if another server holds a LIVE lock, abort and retry; otherwise stamp
	            our own JobId + timestamp and take the data.
	  hold   -> every save refreshes the lock's heartbeat, proving this server is still alive.
	  release-> UpdateAsync clears the lock after the final save, so the next server gets it instantly.
	  steal  -> a lock whose heartbeat is older than LOCK_STALE_SECONDS is assumed dead (the server
	            holding it crashed) and can be taken. Without this, a crash would lock a player out
	            of their own save permanently.

	If the lock genuinely cannot be acquired (another server is alive and holding it), the player is
	KICKED with an explanation rather than being let in with an unsaveable profile. That is a real
	behaviour change and it is deliberate: letting them play a session that cannot be saved is worse
	than a clear "try again in a moment".

	STORAGE SHAPE: the DataStore value is now an envelope, { Data = <profile>, Lock = {...} },
	rather than the bare profile. Saves written before this change are bare profiles; readEnvelope
	below detects and wraps them, so existing saves load untouched.

	ProfileService (loleris) remains the more battle-tested option and does more than this (release
	handoff, global updates, mock stores). This implementation deliberately covers only the failure
	mode above, in ~100 lines that can be read in one sitting, with no external dependency to vendor.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RaidEnergyConfig = require(ReplicatedStorage.Shared.RaidEnergyConfig)
local Wallet = require(ReplicatedStorage.Shared.Wallet)

local PlayerDataStore = DataStoreService:GetDataStore("SalvageProtocol_PlayerData_v1")

local DataService = {}

local cache: { [number]: any } = {}

-- Also the lock heartbeat interval: every save refreshes the lock's timestamp, so one mechanism
-- both persists data and proves this server is still alive. Lowered from 120s when locking was
-- added — the heartbeat has to be comfortably more frequent than LOCK_STALE_SECONDS or a live
-- server's own lock would go stale underneath it.
local AUTOSAVE_INTERVAL = 60

-- How old a lock's heartbeat must be before another server may steal it. Must be a healthy
-- multiple of AUTOSAVE_INTERVAL: too low and a server that merely hiccups loses locks it is still
-- using (the exact data race this exists to prevent); too high and a genuine crash locks the
-- player out of their own save for that long. 3x the heartbeat is the usual compromise.
local LOCK_STALE_SECONDS = 180

-- How long to keep retrying a contested lock before giving up and kicking. Covers the normal case
-- this is designed for: the player's PREVIOUS server still finishing its save-and-release, which
-- takes a second or two, not minutes.
local LOCK_ACQUIRE_ATTEMPTS = 6
local LOCK_RETRY_SECONDS = 2

local LOCK_FAILED_MESSAGE =
	"Your save is still being written by another server. Please rejoin in a few seconds — this "
	.. "protects your progress from being overwritten."

-- Identifies THIS server. game.JobId is empty in Studio, where there is only ever one server, so
-- a stand-in keeps the lock logic exercised in testing instead of silently short-circuiting.
local SERVER_ID = (game.JobId ~= "" and game.JobId) or "studio-local"

-- How many granted PurchaseIds to remember per player (see profile.HandledPurchaseIds). Roblox
-- only re-delivers receipts that haven't been acknowledged yet, so the window that actually
-- needs covering is "the last few purchases," not "everything ever bought" — and this list is
-- saved with the profile, so it can't be allowed to grow forever. Oldest entries are dropped
-- once the list passes this length.
local MAX_HANDLED_PURCHASES = 50

local function defaultProfile()
	return {
		Scrap = 0,
		Cores = 0,
		Contraband = 0,       -- Black Market premium currency. Earned from raid extracts and boss
			-- waves (see BlackMarketService.Income), or bought with Robux as a grind skip. Buys the
			-- premium-odds case lines — see CaseConfig. Routed by Wallet like any other currency.
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
		BaseTier = 1,           -- LEGACY. Superseded by ResearchTier below, which is now the single
		                        -- progression ladder (see ResearchConfig.lua). Kept only as the
		                        -- migration source for saves written before the merge — see
		                        -- migrateBaseTierToResearch. Nothing writes a new value here.
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
		DeployedRobots = {},    -- list of robotKeys currently on defense duty — STILL abstract,
			-- still used by RunRaidCombat's own DPS support. No longer doubles as "turrets" — see
			-- the dedicated Turret system below (profile.Turrets and friends).
		ResearchTier = 1,       -- THE progression ladder — see ResearchConfig.lua. Drives which base
			-- Model (and the stations inside it) gets built, the plot's claimed footprint size, WallHP
			-- in defense, how many turret slots exist, and how far a turret can be levelled. Raised by
			-- the UpgradeResearch remote (BaseService.lua): a wave milestone unlocks each tier, then
			-- Scrap + ore + a boss-wave CoreItem pays for it.
		CoreItems = {},         -- [coreKey] = amount owned (e.g. CoreItems.CoreT1) — the "boss
			-- wave" reward currency (see WaveService.lua/RewardTables.lua), spent by
			-- BaseService.UpgradeResearch's ResearchConfig CoreRequirement gate. Placeholder names
			-- (CoreT1/CoreT2/...) until real flavor names get picked.
		UnlockedTurretBlueprints = {}, -- [turretTypeKey] = true — bought at the Hub's rotating Shop
			-- station (TurretShopService.lua). A PERMANENT recipe unlock: buying it does not mint a
			-- turret, it makes the type craftable at the Welding Station (CraftingService's "Turrets"
			-- tree, cost in TurretConfig.CraftCost). Read by that handler as the gate.
		Turrets = {},           -- list of turret instances: { Id, TypeKey, Level, SlotIndex }.
			-- SlotIndex is nil while the turret sits in storage (bought but not currently placed in a
			-- base slot) — see TurretService.lua for placement/leveling. Level starts at 1;
			-- TurretConfig.GetTurretTier(Level) derives which Tier that maps to (every 10 levels).
		NextTurretId = 1,       -- incrementing counter minting each Turrets instance's Id ("t1",
			-- "t2", ...), same convention as NextWeaponId above — never reused.
		Cases = {},             -- [caseKey] = count of UNOPENED cases. A count rather than instances:
			-- a sealed case has no identity beyond its type, and its contents are not rolled until it
			-- is decoded (see BlackMarketService.RollCase).
			-- DecodeJob (table?) is deliberately NOT listed here, same reasoning as SmeltJob and
			-- EquippedWeaponId: pairs() skips nil-valued entries so a `= nil` line would be a no-op,
			-- and nil reads correctly as "nothing decoding". Shape when active:
			-- { CaseKey, FinishTime } — see HackerService, always broadcast as `DecodeJob or false`.
		RobuxCasesToday = {},   -- [caseKey] = count bought today; paired with RobuxCaseDay below to
			-- enforce CaseConfig's DailyLimit on the Robux case. Reset when the day rolls over.
		RobuxCaseDay = 0,       -- os.time() day number the counts above belong to.
		OwnedUltimates = {},    -- [ultimateKey] = true — Mythical passives, see UltimateConfig.lua. NOT
			-- craftable: they only come out of Black Market cases (and the admin grant, for testing).
		EquippedUltimate = {},  -- [weaponKey] = ultimateKey — the weapon's FOURTH, exclusive slot.
			-- Deliberately a separate field from EquippedMods rather than slot index 4 in it: keeping
			-- the two pools in different tables is what makes it structurally impossible for a regular
			-- mod to land in the Ultimate slot (or the reverse) through an off-by-one, and it keeps
			-- CombatMath's multiplier walk from ever seeing an Ultimate, which is a behaviour rather
			-- than a stat multiplier and would otherwise need special-casing there.
		CraftedMods = {},       -- [modKey] = true (permanent unlock, same shape as CraftedWeapons) — see ModConfig
		EquippedMods = {},      -- [itemKey][slotIndex] = modKey — itemKey is a weaponKey or robotKey,
		                        -- slotIndex runs 1..ModConfig.SlotsPerItem. Applies per item TYPE, not
		                        -- per robot instance — see ModConfig.lua's header comment.
		HighestWave = 0,
		InstantCraftTokens = 0,
		WaveReviveTokens = 0,
		HandledPurchaseIds = {}, -- ordered list of receiptInfo.PurchaseId strings already granted —
			-- see ShopService.ProcessReceipt and DataService.HasHandledPurchase below. Roblox
			-- re-delivers a receipt until it's acknowledged with PurchaseGranted (on retry, and
			-- again on rejoin), so without this a network hiccup between the grant and the
			-- acknowledgement double-grants the product. Bounded FIFO — see MAX_HANDLED_PURCHASES.
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

-- One-time merge of the old two-ladder progression into one. profile.BaseTier and
-- profile.ResearchTier both used to mean "how developed is my base" — BaseTier bought and driving
-- the physical Model, ResearchTier hardcoded to 1 and driving turret slots. ResearchTier is the
-- survivor (see ResearchConfig.lua), so a save from before the merge has to carry its BaseTier
-- progress across or the player silently loses every base upgrade they paid for.
--
-- Takes the MAX rather than overwriting: on a pre-merge save ResearchTier is always 1 and BaseTier
-- holds the real progress, but taking the max means running this twice — or on a save that somehow
-- has both — can never move a player backwards. Idempotent by construction: after the first pass
-- ResearchTier is already >= BaseTier, so every later pass is a no-op.
local function migrateBaseTierToResearch(profile)
	local baseTier = profile.BaseTier or 1
	local researchTier = profile.ResearchTier or 1
	if baseTier > researchTier then
		profile.ResearchTier = baseTier
	end
	return profile
end

local function storeKey(userId: number): string
	return "Player_" .. userId
end

-- Normalizes whatever came out of the DataStore into { Data = profile, Lock = lock? }.
--
-- Saves written before session locking existed are BARE profiles rather than envelopes, so this
-- detects that (a real profile always has Scrap; an envelope never does at the top level) and wraps
-- them. That is the whole migration — no separate pass, no version field, and a save only ever gets
-- rewritten in the new shape once it is next saved.
local function readEnvelope(raw)
	if type(raw) ~= "table" then
		return { Data = nil, Lock = nil }
	end
	if raw.Data ~= nil or raw.Lock ~= nil then
		return { Data = raw.Data, Lock = raw.Lock }
	end
	return { Data = raw, Lock = nil } -- legacy bare profile
end

-- True if `lock` belongs to a server that is (as far as we can tell) still alive and using it.
-- Our own lock never counts as foreign: re-taking a lock this server already holds is what happens
-- when a player rejoins the same server, and blocking that would be a self-inflicted lockout.
local function isForeignLiveLock(lock): boolean
	if type(lock) ~= "table" or lock.ServerId == nil then
		return false
	end
	if lock.ServerId == SERVER_ID then
		return false
	end
	return (os.time() - (lock.Heartbeat or 0)) < LOCK_STALE_SECONDS
end

-- Claims the lock and returns the profile, or nil if another live server holds it.
--
-- UpdateAsync rather than GetAsync+SetAsync because it is ATOMIC for the key: the check and the
-- claim happen inside one transform, so two servers calling this simultaneously cannot both come
-- away believing they won. Returning nil from the transform aborts the write entirely, leaving the
-- other server's lock untouched.
local function tryAcquireProfile(userId: number)
	local acquired = nil
	local blocked = false

	local ok, err = pcall(function()
		PlayerDataStore:UpdateAsync(storeKey(userId), function(raw)
			local envelope = readEnvelope(raw)

			if isForeignLiveLock(envelope.Lock) then
				blocked = true
				return nil -- abort: do not touch another live server's lock
			end

			local profile = backfillMissingFields(envelope.Data or defaultProfile())
			profile = migrateLegacyWeapons(profile)
			profile = migrateBaseTierToResearch(profile)
			acquired = profile

			return { Data = profile, Lock = { ServerId = SERVER_ID, Heartbeat = os.time() } }
		end)
	end)

	if not ok then
		warn("[DataService] UpdateAsync failed acquiring", userId, err)
		return nil, false
	end
	return acquired, blocked
end

-- Retries a contested lock a few times before giving up. The normal contested case is the player's
-- previous server still finishing its save-and-release, which resolves in seconds.
local function loadProfile(userId: number)
	for attempt = 1, LOCK_ACQUIRE_ATTEMPTS do
		local profile, blocked = tryAcquireProfile(userId)
		if profile then
			return profile
		end
		if not blocked then
			-- A DataStore error rather than contention. Retrying is still right (transient outages
			-- are common) but there is nothing to wait for a lock holder to finish.
			warn(("[DataService] load attempt %d/%d failed for %d"):format(attempt, LOCK_ACQUIRE_ATTEMPTS, userId))
		end
		if attempt < LOCK_ACQUIRE_ATTEMPTS then
			task.wait(LOCK_RETRY_SECONDS)
		end
	end
	return nil
end

-- Writes the profile and refreshes the lock heartbeat in one operation. `release` clears the lock
-- instead of refreshing it, handing the profile straight to whichever server wants it next.
--
-- Still UpdateAsync, not SetAsync: this checks the lock is STILL ours before writing. If another
-- server legitimately stole it (this one hung long enough to look dead), writing anyway would
-- clobber a session that is actively being played — the very thing locking exists to prevent. In
-- that case we drop our write and say so, because our copy is the stale one.
local function saveProfile(userId: number, release: boolean?): boolean
	local profile = cache[userId]
	if not profile then
		return false
	end

	local lost = false
	local ok, err = pcall(function()
		PlayerDataStore:UpdateAsync(storeKey(userId), function(raw)
			local envelope = readEnvelope(raw)
			if isForeignLiveLock(envelope.Lock) then
				lost = true
				return nil -- someone else owns this now; our data is stale, discard it
			end
			return {
				Data = profile,
				Lock = release and nil or { ServerId = SERVER_ID, Heartbeat = os.time() },
			}
		end)
	end)

	if lost then
		warn(("[DataService] Lock for %d was taken by another server — discarding this server's save to avoid clobbering the live session."):format(userId))
		return false
	elseif not ok then
		warn("[DataService] UpdateAsync failed saving", userId, err)
		return false
	end
	return true
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

-- coreKey is a RewardTables.BossCoreForMilestone value (e.g. "CoreT1") — see WaveService.lua's
-- boss-wave payout. Same shape as AddOre/AddRefinedOre, just backed by profile.CoreItems instead.
function DataService.AddCoreItem(player: Player, coreKey: string, amount: number)
	local profile = cache[player.UserId]
	if not profile then
		return
	end
	profile.CoreItems[coreKey] = (profile.CoreItems[coreKey] or 0) + amount
end

-- Single-item version of TrySpend, for ResearchConfig's per-tier CoreRequirement — a plain cost TABLE
-- doesn't fit CoreItems since TrySpend's Scrap/Cores-vs-OreCounts branching has no CoreItems case,
-- and a base-tier upgrade only ever needs exactly one CoreItem key anyway. Returns true and
-- deducts, or false and deducts nothing, same contract as TrySpend.
function DataService.TrySpendCoreItem(player: Player, coreKey: string, amount: number): boolean
	local profile = cache[player.UserId]
	if not profile then
		return false
	end
	local available = profile.CoreItems[coreKey] or 0
	if available < amount then
		return false
	end
	profile.CoreItems[coreKey] = available - amount
	return true
end

-- costTable example: { Scrap = 120, ScrapIron = 25, SteelIngot = 5 }. Keys may be "Scrap"/"Cores",
-- a raw ore key, a REFINED material key (RefinedOreConfig, e.g. "SteelIngot"), or a CoreItem key
-- ("CoreT1") — Wallet.BucketFor works out which profile field each one lives in.
--
-- Refined materials were previously unspendable: this function only knew about Scrap/Cores and
-- OreCounts, so a price quoted in SteelIngot silently read as "you have 0 of this ore" and every
-- purchase failed. Smelting produced a resource nothing could charge for.
--
-- Returns true and deducts everything atomically, or false and deducts nothing. The two passes
-- matter: check EVERYTHING first, then deduct, so a cost the player can only half-afford leaves
-- them with all of it rather than partially charged.
function DataService.TrySpend(player: Player, costTable: { [string]: number }): boolean
	local profile = cache[player.UserId]
	if not profile then
		return false
	end

	for key, amount in pairs(costTable) do
		if Wallet.GetAmount(profile, key) < amount then
			return false
		end
	end

	for key, amount in pairs(costTable) do
		local bucket = Wallet.BucketFor(key)
		if bucket == "Currency" then
			profile[key] -= amount
		elseif bucket == "Refined" then
			profile.RefinedOreCounts[key] -= amount
		elseif bucket == "Core" then
			profile.CoreItems[key] -= amount
		else
			profile.OreCounts[key] -= amount
		end
	end

	return true
end

-- Receipt de-duplication for developer-product purchases (ShopService.ProcessReceipt).
--
-- Roblox keeps re-delivering a receipt until the game acknowledges it with PurchaseGranted, and
-- that acknowledgement can be lost — a crash, a network blip, or the player leaving mid-purchase
-- all result in the same receipt arriving again, sometimes on a later session entirely. The
-- purchase must be granted exactly once, so the PurchaseId is recorded alongside the grant and
-- checked on every subsequent delivery.
--
-- Stored as an ordered LIST rather than a set keyed by PurchaseId, specifically so the oldest can
-- be trimmed: a plain [purchaseId] = true table has no order to trim by and would grow with every
-- purchase the player ever makes, inside a value that gets serialized to the DataStore on every
-- save. Linear scan over <= MAX_HANDLED_PURCHASES entries is nothing next to that.
function DataService.HasHandledPurchase(player: Player, purchaseId: string): boolean
	local profile = cache[player.UserId]
	if not profile then
		return false
	end
	return table.find(profile.HandledPurchaseIds, purchaseId) ~= nil
end

-- Records a PurchaseId as granted. Caller must persist with DataService.Save before reporting
-- PurchaseGranted back to Roblox — see ShopService.
function DataService.MarkPurchaseHandled(player: Player, purchaseId: string)
	local profile = cache[player.UserId]
	if not profile then
		return
	end
	table.insert(profile.HandledPurchaseIds, purchaseId)
	while #profile.HandledPurchaseIds > MAX_HANDLED_PURCHASES do
		table.remove(profile.HandledPurchaseIds, 1)
	end
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

-- Force an immediate save. Use this right after granting a real-money purchase — Roblox requires
-- the grant to be persisted before you report PurchaseGranted, otherwise a crash between grant and
-- autosave loses the player's purchase.
--
-- Returns whether the write actually landed. Callers handling real money MUST check it: since
-- session locking was added a save can legitimately be refused (this server's lock was stolen, so
-- its copy is stale), and reporting PurchaseGranted on a write that never happened is exactly how
-- a player pays and receives nothing.
function DataService.Save(player: Player): boolean
	return saveProfile(player.UserId)
end

Players.PlayerAdded:Connect(function(player)
	local profile = loadProfile(player.UserId)
	if not profile then
		-- Could not take the lock. Kicking is the honest outcome: the alternative is letting them
		-- play a session whose saves would be discarded, which looks fine right up until everything
		-- they did that session vanishes.
		warn(("[DataService] Could not acquire session lock for %s — kicking."):format(player.Name))
		player:Kick(LOCK_FAILED_MESSAGE)
		return
	end
	cache[player.UserId] = profile
end)

-- Fires immediately before a player's profile is saved and dropped from the cache, giving other
-- services a last chance to write to it. Connect to THIS, never to Players.PlayerRemoving, if you
-- need to persist something on disconnect.
--
-- WHY this exists: Players.PlayerRemoving handlers fire in CONNECTION order, and a service
-- connects its handler the first time it's require()d — so Main.server.lua's require list is
-- effectively the teardown order. DataService is required first, which means its handler (the one
-- below) ran before every other service's. Anything that tried to write profile data on
-- disconnect therefore called DataService.Get on an already-cleared cache, got nil, and silently
-- discarded the write. RaidRoomService lost an entire raid's collected loot to exactly this.
--
-- Reordering the require list would have "fixed" it for that one caller while leaving the trap
-- fully armed for the next one, since nothing about the ordering is visible from the calling
-- side. A hook that runs at a guaranteed point instead makes the correct thing the easy thing.
--
-- Handlers run SYNCHRONOUSLY here, before the save: a handler that yields delays the save, which
-- is the right tradeoff (a slow save beats a lost one), but keep them short — Roblox does not
-- wait indefinitely for PlayerRemoving to finish. Same BindableEvent pattern as
-- PlotService.PlotAssigned.
local playerSavingSignal = Instance.new("BindableEvent")
DataService.PlayerSaving = playerSavingSignal.Event -- (player: Player)

Players.PlayerRemoving:Connect(function(player)
	playerSavingSignal:Fire(player)
	saveProfile(player.UserId, true) -- release: hand the lock straight to the next server
	cache[player.UserId] = nil
end)

game:BindToClose(function()
	-- Same last-write-in ordering as the per-player path above. The cache is deliberately NOT
	-- cleared here — the server is going down anyway, and clearing it would only risk a
	-- concurrently-running handler seeing a half-torn-down state.
	for _, player in ipairs(Players:GetPlayers()) do
		playerSavingSignal:Fire(player)
		saveProfile(player.UserId, true) -- release too: the server is going away, so holding the
			-- lock would strand every one of these players behind a stale-lock timeout on rejoin.
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

-- Broadcasts everything a player can SPEND, in one call. Use this after any TrySpend/
-- TrySpendCoreItem rather than hand-listing currency keys in a handler's own InventoryUpdate
-- payload.
--
-- WHY: InventoryUpdate is a partial patch — the client merges only the keys it's handed (see
-- MainHud's listener). So a handler that spends Cores but broadcasts only its own domain fields
-- leaves the client's mirrored Cores stale, and the top-left readout keeps showing the old
-- number. The spend really happened; it just looks like it didn't, which is indistinguishable
-- from a bug and much harder to diagnose than one. Three handlers had drifted this way
-- (UpgradeTurret, BuyTurretBlueprint, UpgradeBase) — each spent correctly and under-reported.
--
-- Sending the whole wallet every time is deliberately blunt: it's a handful of numbers, and
-- "remembered to list exactly the right keys" is precisely the thing that keeps going wrong.
function DataService.PushWallet(player: Player)
	local profile = cache[player.UserId]
	if not profile then
		return
	end
	Remotes.InventoryUpdate:FireClient(player, {
		Scrap = profile.Scrap,
		Cores = profile.Cores,
		OreCounts = profile.OreCounts,
		CoreItems = profile.CoreItems,
		RefinedOreCounts = profile.RefinedOreCounts,
		Contraband = profile.Contraband,
	})
end

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
