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
local DataService = require(script.Parent.DataService)
local TurretService = require(script.Parent.TurretService)

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
local function resolveKey(input: string, candidates: { string }): string?
	local lowered = input:lower()
	for _, key in ipairs(candidates) do
		if key:lower() == lowered then
			return key
		end
	end
	return nil
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
		tell(player, "usage: /give <Scrap|Cores|OreKey|CoreT1..> [amount]")
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
	local currencyKey = resolveKey(what, { "Scrap", "Cores" })
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

	tell(player, ("unknown '%s' — try Scrap, Cores, %s, or CoreT1"):format(what, table.concat(oreKeys(), ", ")))
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
	tell(player, "commands: /admin [on|off] · /give <what> [amount] · /giveturret [TypeKey] · /setwave <n>")
	tell(player, ("givable: Scrap, Cores, CoreT1.., %s, %s"):format(table.concat(oreKeys(), ", "), table.concat(refinedKeys(), ", ")))
	tell(player, ("turrets: %s"):format(table.concat(turretKeys(), ", ")))
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

	if command ~= "/give" and command ~= "/giveturret" and command ~= "/setwave" and command ~= "/help" then
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

	if command == "/give" then
		commandGive(player, profile, args)
	elseif command == "/giveturret" then
		commandGiveTurret(player, profile, args)
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
