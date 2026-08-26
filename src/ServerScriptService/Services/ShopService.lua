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

-- Grants the product AND records its PurchaseId, then persists both in a single save. Recording
-- the id in the same save as the grant is the whole point — if they were saved separately, a
-- crash between them would leave a granted-but-unrecorded purchase that gets granted a second
-- time on the next redelivery.
local function grantDeveloperProduct(player: Player, key: string, purchaseId: string)
	local data = ShopConfig.DeveloperProducts[key]
	if not data then
		return false
	end

	if data.Grant then
		DataService.AddCurrency(player, data.Grant.Currency, data.Grant.Amount)
	end
	DataService.MarkPurchaseHandled(player, purchaseId)

	-- Only report success if the write actually landed. DataService.Save can now legitimately
	-- refuse (this server's session lock was stolen, so its copy is stale) — acknowledging the
	-- receipt anyway would mean the player paid and received nothing, with Roblox considering the
	-- purchase closed. Returning false instead leaves it NotProcessedYet, so it is re-delivered to
	-- whichever server actually owns the session.
	return DataService.Save(player)
end

-- Roblox re-delivers a receipt until it's acknowledged with PurchaseGranted, so the same
-- PurchaseId can (and eventually will) arrive more than once: an acknowledgement lost to a crash,
-- a network blip, or the player leaving mid-purchase all replay it, sometimes in a later session
-- entirely. Granting is therefore guarded by profile.HandledPurchaseIds (see DataService) rather
-- than assumed to happen once.
--
-- Note the asymmetry between the two "already handled" and "profile missing" paths below — both
-- are the safe answer for their case:
--   already handled -> PurchaseGranted, WITHOUT granting again. The player has their item; the
--     only thing that failed last time was telling Roblox so. Returning NotProcessedYet here
--     would put the receipt in an infinite redelivery loop.
--   profile missing -> NotProcessedYet. Nothing was granted and nothing was recorded, so letting
--     Roblox retry is exactly right; the player keeps their Robux until it lands.
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

	local purchaseId = tostring(receiptInfo.PurchaseId)

	-- The profile has to be loaded before either half of this can be trusted — HasHandledPurchase
	-- returns false on a missing profile, which would read as "not yet granted" and re-grant.
	if not DataService.Get(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if DataService.HasHandledPurchase(player, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local ok = grantDeveloperProduct(player, key, purchaseId)
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
	-- Polls for the profile rather than sleeping a flat second and hoping. A slow DataStore read
	-- meant syncGamePasses ran against a nil profile and silently skipped — the player kept their
	-- passes but the game did not know about them until their next rejoin. Same waitForProfile
	-- shape BaseService/TurretService/WeaponToolService already use.
	task.spawn(function()
		local attempts = 0
		while not DataService.Get(player) and attempts < 50 and player.Parent do
			task.wait(0.1)
			attempts += 1
		end
		if player.Parent then
			syncGamePasses(player)
		end
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
