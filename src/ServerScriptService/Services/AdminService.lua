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
local DataService = require(script.Parent.DataService)
local TurretService = require(script.Parent.TurretService)
local TrainingDummyService = require(script.Parent.TrainingDummyService)

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
-- substring. Exact HAS to win outright — "scrap" must mean the Scrap currency and not be treated as
-- an ambiguous prefix of ScrapIron.
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
	-- GoldContacts over matching in the middle of something else.
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

local function commandHelp(player: Player)
	tell(player, "commands: /admin [on|off] · /give <what> [amount] · /givemats [n] · /giveturret [TypeKey] · /giveultimate [Key] · /dummy · /givecase [Key] [n] · /givefamily [Key] · /givetool [Key] · /givedrone [Key] · /setwave <n>")
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
