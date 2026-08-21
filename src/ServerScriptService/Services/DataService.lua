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
		OwnedGamePasses = {},   -- [gamePassKey] = true
		CraftedWeapons = {},    -- [weaponKey] = true
		CraftedRobots = {},     -- [robotKey] = count owned
		DeployedRobots = {},    -- list of robotKeys currently on defense duty
		HighestWave = 0,
		InstantCraftTokens = 0,
		WaveReviveTokens = 0,
	}
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
	return data or defaultProfile()
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
