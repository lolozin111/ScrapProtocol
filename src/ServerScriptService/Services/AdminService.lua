--[[
	AdminService.lua
	Chat commands for whoever AdminConfig.IsAdmin() already applies to — the place's owner by
	default, plus anyone listed in AdminConfig.AdminUserIds.

	Two jobs:

	1. Toggling the always-on dev shortcuts off, so you can test what a NORMAL player experiences
	   (Energy costs, real timed combat) without editing code every time:
	     /admin off | /admin on | /admin      (toggle)

	2. Granting yourself resources, so testing a downstream system doesn't require grinding the
	   upstream one first. The concrete case this was added for: turret placement can't be tested
	   at all without owning a turret, turrets only come from Hub Shop blueprints, blueprints cost
	   40-150 Cores, and Cores only drop from base-defense boss waves (every 5th). That's a long
	   way to walk to click one button.
	     /give <what> [amount]     Scrap, Cores, any OreConfig.Ores key, or any RewardTables core
	                               key (CoreT1...). Case-insensitive. Defaults to 100.
	     /giveturret [TypeKey]     Mints an unplaced turret straight into storage, skipping the
	                               shop entirely. Defaults to the first TurretConfig.Types key.
	     /setwave <n>              Sets HighestWave, which is what gates ore behind MinWaveUnlock.
	     /help                     Lists all of this in the Output window.

	EVERYTHING here is gated on AdminConfig.IsAdmin and silently ignored for anyone else — a normal
	player typing /give sees nothing happen and gets no hint the command exists. Note that /admin
	off ALSO disables these grants, since IsAdmin is what they check: that's deliberate, so
	"pretend to be a normal player" really means it.

	Session-only in the sense that admin status resets on rejoin; the resources granted are real
	and persist, same as any other profile write.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminConfig = require(ReplicatedStorage.Shared.AdminConfig)
local OreConfig = require(ReplicatedStorage.Shared.OreConfig)
local RefinedOreConfig = require(ReplicatedStorage.Shared.RefinedOreConfig)
local TurretConfig = require(ReplicatedStorage.Shared.TurretConfig)
local UltimateConfig = require(ReplicatedStorage.Shared.UltimateConfig)
local CaseConfig = require(ReplicatedStorage.Shared.CaseConfig)
local WeaponFamilyConfig = require(ReplicatedStorage.Shared.WeaponFamilyConfig)
local ToolModConfig = require(ReplicatedStorage.Shared.ToolModConfig)
local DroneConfig = require(ReplicatedStorage.Shared.DroneConfig)
local RunBuffConfig = require(ReplicatedStorage.Shared.RunBuffConfig)
local DataService = require(script.Parent.DataService)
local TurretService = require(script.Parent.TurretService)
local TrainingDummyService = require(script.Parent.TrainingDummyService)
local RateLimiter = require(script.Parent.RateLimiter)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local AdminService = {}

local DEFAULT_GIVE_AMOUNT = 100

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function tell(player: Player, message: string)
	-- Output window only. There's no admin-facing UI and building one for a dev tool isn't worth
	-- it; the HUD's own toast is reserved for things a real player is meant to see.
	print(("[Admin] %s — %s"):format(player.Name, message))
end

-- Case-insensitive lookup of whatever the player typed against a set of real keys, so /give cores
-- and /give Cores both work. Returns the CANONICAL key, since that's what the profile is keyed by.
-- Resolves a typed fragment to one key. Three passes, narrowest first: exact, then prefix, then
-- substring. Exact HAS to win outright — "scrap" must mean the Scrap currency and not fall through
-- to a prefix/substring match against some other key that happens to start the same way.
--
-- Returns (key) on a clean match, or (nil, candidates) when a fragment matched several things, so
-- the caller can say which rather than "unknown". Typing the full CamelCase key for every material
-- is the kind of friction that makes a dev command not get used.
local function resolveKey(input: string, candidates: { string }): (string?, { string }?)
	local lowered = input:lower()

	for _, key in ipairs(candidates) do
		if key:lower() == lowered then
			return key
		end
	end

	local matches = {}
	for _, key in ipairs(candidates) do
		if key:lower():sub(1, #lowered) == lowered then
			table.insert(matches, key)
		end
	end

	-- Only falls back to substring when nothing started with the fragment, so "gold" still prefers
	-- GoldOre over matching in the middle of something else.
	if #matches == 0 then
		for _, key in ipairs(candidates) do
			if key:lower():find(lowered, 1, true) then
				table.insert(matches, key)
			end
		end
	end

	if #matches == 1 then
		return matches[1]
	end
	return nil, (#matches > 0 and matches or nil)
end

local function oreKeys(): { string }
	local keys = {}
	for key in pairs(OreConfig.Ores) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function refinedKeys(): { string }
	local keys = {}
	for _, data in pairs(RefinedOreConfig.Ores) do
		table.insert(keys, data.RefinedKey)
	end
	table.sort(keys)
	return keys
end

local function ultimateKeys(): { string }
	return UltimateConfig.SortedKeys()
end

local function turretKeys(): { string }
	local keys = {}
	for key in pairs(TurretConfig.Types) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- One broadcast shape for every grant below — the HUD merges whatever keys it's handed (see
-- MainHud's InventoryUpdate listener), so sending the whole relevant set keeps this simple rather
-- than tailoring a minimal patch per command.
local function pushProfile(player: Player, profile)
	Remotes.InventoryUpdate:FireClient(player, {
		Scrap = profile.Scrap,
		Cores = profile.Cores,
		Contraband = profile.Contraband,
		OreCounts = profile.OreCounts,
		RefinedOreCounts = profile.RefinedOreCounts,
		CoreItems = profile.CoreItems,
		Turrets = profile.Turrets,
		HighestWave = profile.HighestWave,
	})
end

----------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------

local function commandGive(player: Player, profile, args: { string })
	local what = args[2]
	if not what then
		tell(player, "usage: /give <Scrap|Cores|Contraband|OreKey|RefinedKey|CoreT1..> [amount] — partial names work, e.g. /give copper. Or /givemats for everything at once.")
		return
	end

	local amount = tonumber(args[3]) or DEFAULT_GIVE_AMOUNT
	amount = math.floor(amount)
	if amount <= 0 then
		tell(player, "amount must be a positive number")
		return
	end

	-- Currencies first, then ores, then CoreItems. CoreItems aren't validated against a fixed list
	-- because RewardTables mints keys by milestone (CoreT1, CoreT2, ...) and there's no canonical
	-- enumeration of them — anything starting "Core" that isn't the Cores currency is treated as
	-- one, which is good enough for a dev command.
	-- Every candidate in one list, so an ambiguous fragment can name everything it matched across
	-- all four categories rather than only the one that happened to be checked first.
	local everything = { "Scrap", "Cores", "Contraband" }
	for _, key in ipairs(oreKeys()) do
		table.insert(everything, key)
	end
	for _, key in ipairs(refinedKeys()) do
		table.insert(everything, key)
	end
	local _, ambiguous = resolveKey(what, everything)
	if ambiguous then
		tell(player, ("'%s' matches %d things — be more specific: %s"):format(
			what, #ambiguous, table.concat(ambiguous, ", ")))
		return
	end

	local currencyKey = resolveKey(what, { "Scrap", "Cores", "Contraband" })
	if currencyKey then
		DataService.AddCurrency(player, currencyKey, amount)
		pushProfile(player, profile)
		tell(player, ("+%d %s"):format(amount, currencyKey))
		return
	end

	local oreKey = resolveKey(what, oreKeys())
	if oreKey then
		DataService.AddOre(player, oreKey, amount)
		pushProfile(player, profile)
		tell(player, ("+%d %s"):format(amount, oreKey))
		return
	end

	-- Refined materials (SteelIngot, CopperCoil, ...) — checked after raw ore so the two never
	-- collide, and included because turret crafts and Research tiers now cost them, which makes
	-- them untestable without either this or a real smelting run per attempt.
	local refinedKey = resolveKey(what, refinedKeys())
	if refinedKey then
		DataService.AddRefinedOre(player, refinedKey, amount)
		pushProfile(player, profile)
		tell(player, ("+%d %s"):format(amount, refinedKey))
		return
	end

	if what:lower():sub(1, 4) == "core" then
		local coreKey = "CoreT" .. (what:match("%d+") or "1")
		DataService.AddCoreItem(player, coreKey, amount)
		pushProfile(player, profile)
		tell(player, ("+%d %s"):format(amount, coreKey))
		return
	end

	tell(player, ("unknown '%s' — try Scrap, Cores, Contraband, CoreT1, %s, or %s"):format(
		what, table.concat(oreKeys(), ", "), table.concat(refinedKeys(), ", ")))
end

----------------------------------------------------------------------
-- /givemats — everything a craft could possibly ask for, in one command.
--
-- Exists because getting kitted out to test one recipe otherwise means a dozen separate /give
-- calls, and you have to remember every key. Amounts are scaled per category rather than flat: a
-- Research tier costs Scrap in the thousands and refined materials in the tens, so one number
-- handed to all of them would be either uselessly small or absurd.
----------------------------------------------------------------------

local function commandGiveMats(player: Player, profile, args: { string })
	local base = math.floor(tonumber(args[2]) or 500)
	if base <= 0 then
		tell(player, "amount must be a positive number")
		return
	end

	-- x40 on Scrap: it is the bulk currency and the top Research tier alone wants 12,000 of it, so
	-- the default of 500 has to land well clear of that.
	DataService.AddCurrency(player, "Scrap", base * 40)
	DataService.AddCurrency(player, "Cores", base)
	DataService.AddCurrency(player, "Contraband", math.max(1, math.floor(base / 5)))

	for _, key in ipairs(oreKeys()) do
		DataService.AddOre(player, key, base)
	end
	for _, key in ipairs(refinedKeys()) do
		DataService.AddRefinedOre(player, key, base)
	end

	-- Boss-wave Cores, one tier per Research step. Small counts because each tier needs exactly one
	-- and there is nothing else to spend them on.
	for tier = 1, 5 do
		DataService.AddCoreItem(player, "CoreT" .. tier, 10)
	end

	pushProfile(player, profile)
	tell(player, ("+%d Scrap, %d Cores, %d of every ore and refined material, 10 of each boss Core"):format(
		base * 40, base, base))
end

local function commandGiveTurret(player: Player, profile, args: { string })
	local requested = args[2]
	local typeKey
	if requested then
		typeKey = resolveKey(requested, turretKeys())
		if not typeKey then
			tell(player, ("unknown turret '%s' — try one of: %s"):format(requested, table.concat(turretKeys(), ", ")))
			return
		end
	else
		typeKey = turretKeys()[1]
	end

	-- Goes through the same TurretService.MintTurret every other acquisition path uses, so a turret
	-- granted this way is indistinguishable from a crafted one downstream. Also unlocks the
	-- blueprint, so you can go on to craft more of the type normally after being handed one.
	profile.UnlockedTurretBlueprints[typeKey] = true
	local instance = TurretService.MintTurret(profile, typeKey)

	Remotes.InventoryUpdate:FireClient(player, {
		Turrets = profile.Turrets,
		UnlockedTurretBlueprints = profile.UnlockedTurretBlueprints,
		NextTurretId = profile.NextTurretId,
	})
	tell(player, ("granted %s (%s) — unplaced, click a slot pad at your base to place it"):format(typeKey, instance.Id))
end

-- Ultimates only drop from Black Market cases, which do not exist yet — so without this there is
-- no way at all to test the Ultimate slot or its combat hooks.
local function commandGiveUltimate(player: Player, profile, args: { string })
	local requested = args[2]
	local key
	if requested then
		key = resolveKey(requested, ultimateKeys())
		if not key then
			tell(player, ("unknown Ultimate '%s' — try one of: %s"):format(requested, table.concat(ultimateKeys(), ", ")))
			return
		end
	else
		key = ultimateKeys()[1]
	end

	profile.OwnedUltimates[key] = true
	Remotes.InventoryUpdate:FireClient(player, { OwnedUltimates = profile.OwnedUltimates })
	tell(player, ("granted Ultimate %s — equip it from the Inventory's weapon detail panel"):format(key))
end

-- Cases are the Black Market's whole delivery mechanism, so handing one over without grinding the
-- currency first is what makes the decode flow testable at all.
local function caseKeys(): { string }
	local keys = {}
	for key in pairs(CaseConfig.Cases) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function commandGiveCase(player: Player, profile, args: { string })
	local requested = args[2]
	local key
	if requested then
		key = resolveKey(requested, caseKeys())
		if not key then
			tell(player, ("unknown case '%s' — try one of: %s"):format(requested, table.concat(caseKeys(), ", ")))
			return
		end
	else
		key = caseKeys()[1]
	end

	local amount = math.max(1, math.floor(tonumber(args[3]) or 1))
	profile.Cases[key] = (profile.Cases[key] or 0) + amount
	Remotes.InventoryUpdate:FireClient(player, { Cases = profile.Cases })
	tell(player, ("+%d %s — decode it at the Hacker Machine"):format(amount, key))
end

-- Gun families are otherwise a Legendary case roll, which is far too rare to test a gun through.
-- No argument unlocks the lot, which is what you almost always want while checking a new variant.
local function commandGiveFamily(player: Player, profile, args: { string })
	local keys = WeaponFamilyConfig.Order
	profile.UnlockedWeaponFamilies = profile.UnlockedWeaponFamilies or {}

	local requested = args[2]
	if not requested then
		for _, key in ipairs(keys) do
			profile.UnlockedWeaponFamilies[key] = true
		end
		Remotes.InventoryUpdate:FireClient(player, {
			UnlockedWeaponFamilies = profile.UnlockedWeaponFamilies,
		})
		tell(player, "unlocked every weapon family — all Forge tabs are open")
		return
	end

	local key = resolveKey(requested, keys)
	if not key then
		tell(player, ("unknown family '%s' — try one of: %s"):format(requested, table.concat(keys, ", ")))
		return
	end

	profile.UnlockedWeaponFamilies[key] = true
	Remotes.InventoryUpdate:FireClient(player, {
		UnlockedWeaponFamilies = profile.UnlockedWeaponFamilies,
	})
	tell(player, ("unlocked %s — Forge them at the Forge's Weapons tab"):format(
		WeaponFamilyConfig.Families[key].DisplayName))
end

-- Pickaxes are an Epic case roll — common enough to get eventually, far too slow to test through.
local function commandGiveTool(player: Player, profile, args: { string })
	local keys = ToolModConfig.Order
	profile.OwnedTools = profile.OwnedTools or {}

	local requested = args[2]
	if not requested then
		for _, key in ipairs(keys) do
			profile.OwnedTools[key] = true
		end
		Remotes.InventoryUpdate:FireClient(player, { OwnedTools = profile.OwnedTools })
		tell(player, "granted every special pickaxe — equip one at a Workbench's Tools tab")
		return
	end

	local key = resolveKey(requested, keys)
	if not key then
		tell(player, ("unknown pickaxe '%s' — try one of: %s"):format(requested, table.concat(keys, ", ")))
		return
	end

	profile.OwnedTools[key] = true
	Remotes.InventoryUpdate:FireClient(player, { OwnedTools = profile.OwnedTools })
	tell(player, ("granted %s"):format(ToolModConfig.Tools[key].DisplayName))
end

-- Drone Cores are half crafted and half Epic case rolls, and the drone itself needs Research
-- Tier 3 — three separate gates to walk through before you can look at one.
local function commandGiveDrone(player: Player, profile, args: { string })
	local keys = DroneConfig.Order
	profile.OwnedDroneCores = profile.OwnedDroneCores or {}

	local requested = args[2]
	if requested then
		local key = resolveKey(requested, keys)
		if not key then
			tell(player, ("unknown Core '%s' — try one of: %s"):format(requested, table.concat(keys, ", ")))
			return
		end
		profile.OwnedDroneCores[key] = true
	else
		for _, key in ipairs(keys) do
			profile.OwnedDroneCores[key] = true
		end
	end

	Remotes.InventoryUpdate:FireClient(player, { OwnedDroneCores = profile.OwnedDroneCores })

	-- Says so rather than leaving you wondering why the Welding Station refuses to equip it.
	if not DroneConfig.IsUnlocked(profile) then
		tell(player, ("granted — but the drone itself needs Research Tier %d and you are on %d, so nothing will appear yet."):format(
			DroneConfig.UnlockResearchTier, profile.ResearchTier or 1))
	else
		tell(player, "granted — slot one at the Welding Station's Drones tab")
	end
end

local function commandDummy(player: Player)
	if TrainingDummyService.SpawnNear(player) then
		tell(player, "spawned a training dummy in front of you")
	else
		tell(player, "could not spawn — no character")
	end
end

local function commandSetWave(player: Player, profile, args: { string })
	local wave = tonumber(args[2])
	if not wave or wave < 0 then
		tell(player, "usage: /setwave <n>")
		return
	end
	-- Written directly rather than through DataService.SetHighestWave, which only ever raises it —
	-- being able to drop it back down is the whole point when you're testing an ore's
	-- MinWaveUnlock gate from below.
	profile.HighestWave = math.floor(wave)
	pushProfile(player, profile)
	tell(player, ("HighestWave = %d"):format(profile.HighestWave))
end

-- /giverunscrap [amount] — tops up the RUN's Scrap, the only currency a raid Shop accepts.
--
-- `/give Scrap` writes the PROFILE, and a raid Shop deliberately cannot spend that ("you are only
-- able to purchase stuff with the scraps collected through the entire run"), so it buys nothing in
-- there. Without this, testing the shop meant grinding rooms for it.
--
-- Takes no `profile` argument, unlike every other command here, because it doesn't touch the
-- profile at all — the pile lives on the raid's in-memory run state and vanishes with the run.
local function commandGiveRunScrap(player: Player, args: { string })
	local amount = args[2] and tonumber(args[2]) or 1000
	if not amount or amount ~= amount or amount == math.huge or amount == -math.huge then
		tell(player, "usage: /giverunscrap [amount]  (default 1000)")
		return
	end
	amount = math.floor(amount)

	-- Required lazily, on purpose. A top-level require would pull RaidRoomService — and with it
	-- CombatEncounterService, RunBuffService, BlackMarketService and the rest of its tree — forward
	-- from position 39 in Main.server.lua's ordered require list to position 25, where AdminService
	-- sits. Reordering the whole combat half of the boot for a dev command is not a trade worth
	-- making; by the time anyone can type this, everything is long since loaded.
	local RaidRoomService = require(script.Parent.RaidRoomService)
	if not RaidRoomService.DevAddRunScrap(player, amount) then
		tell(player, "not in a raid — this tops up the run's own Scrap, so start a raid first")
		return
	end
	tell(player, ("run Scrap %+d — spendable at a raid Shop node"):format(amount))
end

-- Groups RunBuffConfig.Items by Kind (Perk/Gear/Escape) for /giverunbuff's usage listing — read
-- straight off the config rather than hard-coded, so a new item shows up here automatically instead
-- of silently missing from the help text.
local function runBuffKeysByKind(kind: string): { string }
	local keys = {}
	for key, item in pairs(RunBuffConfig.Items) do
		if item.Kind == kind then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return keys
end

local function allRunBuffKeys(): { string }
	local keys = {}
	for key in pairs(RunBuffConfig.Items) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function runBuffUsage(player: Player)
	tell(player, "usage: /giverunbuff [Key|all] [Rarity] [Level]  — rarity defaults to the item's highest, level to that rarity's cap. Must be in a raid.")
	tell(player, ("perks: %s"):format(table.concat(runBuffKeysByKind("Perk"), ", ")))
	tell(player, ("gear: %s"):format(table.concat(runBuffKeysByKind("Gear"), ", ")))
	tell(player, ("escape: %s"):format(table.concat(runBuffKeysByKind("Escape"), ", ")))
end

-- /giverunbuff [Key|all] [Rarity] [Level] — grants a raid run upgrade (a RunBuffService Owned/
-- Escape entry) directly, so testing the SHOP'S EFFECTS doesn't mean walking the shop and grinding
-- the run's own Scrap for every item. See RunBuffService.DevGrant's own comment for the one
-- deliberate difference from a real Buy: this skips the rarity-up/level-up pacing entirely and can
-- jump straight to the top — that's the point of the command.
--
-- Takes no `profile` argument, same reason as /giverunscrap: it only touches the raid's in-memory
-- run state, which vanishes with the run.
local function commandGiveRunBuff(player: Player, args: { string })
	local requested = args[2]
	if not requested then
		runBuffUsage(player)
		return
	end

	-- Required lazily — same reasoning as /giverunscrap just above: a top-level require would pull
	-- RaidRoomService, and with it the rest of its combat-tree dependency chain, forward to
	-- AdminService's spot in Main.server.lua's require order for a dev command's sake.
	local RaidRoomService = require(script.Parent.RaidRoomService)

	local function reportFailure(reason: string?)
		if reason == "NotInRaid" then
			tell(player, "not in a raid — start one first")
		elseif reason == "SlotsFull" then
			tell(player, ("all %d slots are full — name a key you already own to level it up instead"):format(RunBuffConfig.Slots))
		else
			-- UnknownItem / BadRarity
			runBuffUsage(player)
		end
	end

	if requested:lower() == "all" then
		-- Escape first (no slot cost), then Gear, then Perk, each alphabetical for a stable order.
		-- Gear leads the slotted groups because it's the visual half of the shop rework — the thing
		-- you most often actually want to look at while testing.
		local groups = {
			runBuffKeysByKind("Escape"),
			runBuffKeysByKind("Gear"),
			runBuffKeysByKind("Perk"),
		}
		local granted, skipped = {}, {}
		for _, keys in ipairs(groups) do
			for _, key in ipairs(keys) do
				local ok, reason = RaidRoomService.DevGrantRunBuff(player, key)
				if ok then
					table.insert(granted, key)
				elseif reason == "SlotsFull" then
					table.insert(skipped, key)
				else
					-- NotInRaid applies to every remaining key too — say it once and stop instead of
					-- repeating the same failure down the whole list.
					reportFailure(reason)
					return
				end
			end
		end
		tell(player, ("granted: %s"):format(#granted > 0 and table.concat(granted, ", ") or "none"))
		if #skipped > 0 then
			tell(player, ("skipped (slots full): %s"):format(table.concat(skipped, ", ")))
		end
		return
	end

	local key = resolveKey(requested, allRunBuffKeys())
	if not key then
		runBuffUsage(player)
		return
	end

	local item = RunBuffConfig.Items[key]
	local ok, reason = RaidRoomService.DevGrantRunBuff(player, key, args[3], tonumber(args[4]))
	if not ok then
		reportFailure(reason)
		return
	end

	if item.Kind == "Escape" then
		tell(player, ("granted Escape item %s — one-use, takes no slot"):format(key))
		return
	end

	-- Rarity/level are guaranteed valid here since DevGrantRunBuff just succeeded with them —
	-- recompute the same defaults it applied so the report names what actually landed, not just
	-- what was typed (args[3]/args[4] are often nil, relying on those defaults).
	local rarity = args[3] or item.Rarities[#item.Rarities]
	local cap = RunBuffConfig.RarityCaps[rarity]
	local level = math.clamp(tonumber(args[4]) or cap, 1, cap)
	tell(player, ("granted %s — %s Lv%d"):format(key, rarity, level))
end

local function commandHelp(player: Player)
	tell(player, "commands: /admin [on|off] · /give <what> [amount] · /givemats [n] · /giveturret [TypeKey] · /giveultimate [Key] · /dummy · /givecase [Key] [n] · /givefamily [Key] · /givetool [Key] · /givedrone [Key] · /giverunscrap [amount] · /giverunbuff [Key|all] [Rarity] [Level] · /setwave <n>")
	tell(player, "/giverunscrap tops up the RUN's Scrap (what a raid Shop spends) — /give Scrap writes the profile, which a raid Shop can't touch. Must be in a raid.")
	tell(player, "/giverunbuff grants a raid run upgrade (perk/gear/Escape item) straight onto the run, skipping the Shop's walk-and-grind entirely. Must be in a raid.")
	tell(player, ("givable: Scrap, Cores, CoreT1.., %s, %s"):format(table.concat(oreKeys(), ", "), table.concat(refinedKeys(), ", ")))
	tell(player, ("turrets: %s"):format(table.concat(turretKeys(), ", ")))
	tell(player, ("ultimates: %s"):format(table.concat(ultimateKeys(), ", ")))
	tell(player, ("cases: %s"):format(table.concat(caseKeys(), ", ")))
	tell(player, ("families: %s (no argument unlocks all)"):format(
		table.concat(WeaponFamilyConfig.Order, ", ")))
	tell(player, ("pickaxes: %s (no argument grants all)"):format(
		table.concat(ToolModConfig.Order, ", ")))
	tell(player, ("drone cores: %s (no argument grants all)"):format(
		table.concat(DroneConfig.Order, ", ")))
end

----------------------------------------------------------------------
-- Player Test Mode — an admin rejoins with a brand-new throwaway profile so they can see the
-- game from the beginning, then flips it back off to return to their real save. Deliberately
-- takes effect on rejoin only, never mid-session: swapping the profile a live session is reading
-- and writing out from under it is how you corrupt a save, not preview one.
----------------------------------------------------------------------

Remotes.GetTestMode.OnServerInvoke = function(player: Player)
	if not AdminConfig.IsAdmin(player) then
		-- Honest empty answer, not an error — the client only calls this to decide whether to
		-- build the button at all, so a non-admin should see nothing rather than a failure.
		return { IsAdmin = false, On = false, InTestSession = false }
	end

	return {
		IsAdmin = true,
		On = DataService.IsTestModeEnabled(player.UserId),
		InTestSession = DataService.IsTestSession(player),
	}
end

Remotes.ToggleTestMode.OnServerInvoke = function(player: Player)
	if not AdminConfig.IsAdmin(player) then
		return { Success = false, Reason = "Not authorized." }
	end

	if not RateLimiter.Check(player, "ToggleTestMode", 1) then
		return { Success = false, Reason = "Slow down." }
	end

	local current = DataService.IsTestModeEnabled(player.UserId)
	local landed = DataService.SetTestModeEnabled(player.UserId, not current)
	if not landed then
		-- Never report success on a write that didn't happen — the caller would otherwise believe
		-- their next rejoin loads a fresh profile when it's actually still pointed at the old flag.
		return { Success = false, Reason = "Save failed — try again." }
	end

	return { Success = true, On = not current, InTestSession = DataService.IsTestSession(player) }
end

----------------------------------------------------------------------
-- Dispatch
----------------------------------------------------------------------

local function handleChatted(player: Player, message: string)
	if message:sub(1, 1) ~= "/" then
		return
	end

	-- Split on whitespace: args[1] is the command itself, the rest are its parameters.
	local args = {}
	for word in message:gmatch("%S+") do
		table.insert(args, word)
	end
	local command = args[1]:lower()

	-- /admin is handled first and separately because it's the ONE command that has to work while
	-- admin shortcuts are muted — otherwise "/admin off" would be a one-way door with no way back
	-- short of rejoining. It has its own base-admin check inside AdminConfig.SetOverride.
	if command == "/admin" then
		local mode = args[2] and args[2]:lower()
		if mode == "off" then
			AdminConfig.SetOverride(player, false)
		elseif mode == "on" then
			AdminConfig.SetOverride(player, true)
		elseif mode == nil then
			AdminConfig.SetOverride(player, not AdminConfig.IsAdmin(player))
		else
			return -- "/admin something-else" isn't a command; ignore rather than guessing
		end
		print(("[AdminService] Admin shortcuts are now %s for %s (this session only)."):format(
			AdminConfig.IsAdmin(player) and "ON" or "OFF", player.Name))
		return
	end

	if command ~= "/give" and command ~= "/giveturret" and command ~= "/giveultimate"
		and command ~= "/dummy" and command ~= "/givecase" and command ~= "/givefamily" and command ~= "/givetool" and command ~= "/givedrone" and command ~= "/givemats"
		and command ~= "/giverunscrap" and command ~= "/giverunbuff"
		and command ~= "/setwave" and command ~= "/help" then
		return
	end

	-- Silently ignored for non-admins — no error, no hint the command exists. Checked AFTER the
	-- command is recognized so a normal player's ordinary chat never reaches this at all.
	if not AdminConfig.IsAdmin(player) then
		return
	end

	local profile = DataService.Get(player)
	if not profile then
		tell(player, "profile not loaded yet — try again in a moment")
		return
	end

	if command == "/givemats" then
		commandGiveMats(player, profile, args)
	elseif command == "/give" then
		commandGive(player, profile, args)
	elseif command == "/giveturret" then
		commandGiveTurret(player, profile, args)
	elseif command == "/giveultimate" then
		commandGiveUltimate(player, profile, args)
	elseif command == "/dummy" then
		commandDummy(player)
	elseif command == "/givecase" then
		commandGiveCase(player, profile, args)
	elseif command == "/givefamily" then
		commandGiveFamily(player, profile, args)
	elseif command == "/givetool" then
		commandGiveTool(player, profile, args)
	elseif command == "/givedrone" then
		commandGiveDrone(player, profile, args)
	elseif command == "/giverunscrap" then
		commandGiveRunScrap(player, args)
	elseif command == "/giverunbuff" then
		commandGiveRunBuff(player, args)
	elseif command == "/setwave" then
		commandSetWave(player, profile, args)
	elseif command == "/help" then
		commandHelp(player)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		handleChatted(player, message)
	end)
end)

return AdminService
