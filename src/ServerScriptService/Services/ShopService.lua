--[[
	ShopService.lua
	Handles real-money purchases: MarketplaceService.ProcessReceipt for developer products,
	and game-pass ownership sync. Matches "Monetization" section of the design doc.

	Remember to actually create these Game Passes and Developer Products in the Creator
	Dashboard for THIS experience, then paste their ids into ShopConfig.lua — everything
	here reads from that table, nothing is hardcoded.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.ShopConfig)
local DataService = require(script.Parent.DataService)

local ShopService = {}

-- Build reverse lookups (Id -> key) once at startup so ProcessReceipt is O(1).
local productIdToKey = {}
for key, data in pairs(ShopConfig.DeveloperProducts) do
	if data.Id ~= 0 then
		productIdToKey[data.Id] = key
	end
end

local passIdToKey = {}
for key, data in pairs(ShopConfig.GamePasses) do
	if data.Id ~= 0 then
		passIdToKey[data.Id] = key
	end
end

local function grantDeveloperProduct(player: Player, key: string)
	local data = ShopConfig.DeveloperProducts[key]
	if not data then
		return false
	end

	if data.Grant then
		DataService.AddCurrency(player, data.Grant.Currency, data.Grant.Amount)
	end

	DataService.Save(player) -- persist immediately, see DataService.Save's comment
	return true
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local key = productIdToKey[receiptInfo.ProductId]
	if not key then
		warn("[ShopService] Unrecognized ProductId", receiptInfo.ProductId, "- add it to ShopConfig.lua")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok = grantDeveloperProduct(player, key)
	if not ok then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function syncGamePasses(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	for key, data in pairs(ShopConfig.GamePasses) do
		if data.Id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, data.Id)
			end)
			if ok and owns then
				profile.OwnedGamePasses[key] = true
			end
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	-- Give DataService's PlayerAdded handler a beat to load the profile first.
	task.defer(function()
		task.wait(1)
		syncGamePasses(player)
	end)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased then
		return
	end
	local key = passIdToKey[gamePassId]
	if not key then
		return
	end
	local profile = DataService.Get(player)
	if profile then
		profile.OwnedGamePasses[key] = true
		DataService.Save(player)
	end
end)

return ShopService
