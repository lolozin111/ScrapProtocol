--[[
	TurretShopService.lua
	The Hub's rotating Shop station (StationConfig.Types.Shop) — sells Turret blueprints. Buying one
	mints a brand-new Turret instance straight into profile.Turrets (unplaced, Level 1); there's no
	separate "craft with raw materials" step the way Robots/Weapons work — the blueprint purchase
	IS how you get the turret. See TurretConfig.lua's own header for the reasoning, and
	TurretService.lua for what happens once the player actually places it into a base slot.

	Deliberately NOT gated behind PlotService.IsPlayerInOwnPlot — the Hub is a shared world
	location, not part of any player's base. See StationConfig.Types.Shop's own comment.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TurretConfig = require(ReplicatedStorage.Shared.TurretConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local DataService = require(script.Parent.DataService)
local StationService = require(script.Parent.StationService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local TurretShopService = {}

Remotes.BuyTurretBlueprint.OnServerInvoke = function(player: Player, typeKey: string)
	if not StationService.IsPlayerNearStation(player, "Shop") then
		return { Success = false, Reason = StationConfig.Types.Shop.NotThereMessage }
	end

	local typeData = TurretConfig.Types[typeKey]
	if not typeData then
		return { Success = false, Reason = "Unknown turret type" }
	end

	-- Re-derives today's stock server-side rather than trusting whatever the client claims it saw —
	-- see TurretConfig.GetRotatingStock's own header on why this is safe to recompute independently
	-- (pure function of time, no persisted state to disagree about beyond the rotation-window edge
	-- case that comment already covers).
	local stock = TurretConfig.GetRotatingStock(os.time())
	local inStock = false
	for _, key in ipairs(stock) do
		if key == typeKey then
			inStock = true
			break
		end
	end
	if not inStock then
		return { Success = false, Reason = "Not in today's stock" }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	if not DataService.TrySpend(player, typeData.BlueprintCost) then
		return { Success = false, Reason = "Not enough Cores" }
	end

	profile.UnlockedTurretBlueprints[typeKey] = true

	local id = ("t%d"):format(profile.NextTurretId)
	profile.NextTurretId += 1
	local instance = { Id = id, TypeKey = typeKey, Level = 1 } -- SlotIndex omitted = unplaced/storage
	table.insert(profile.Turrets, instance)

	Remotes.InventoryUpdate:FireClient(player, {
		Turrets = profile.Turrets,
		UnlockedTurretBlueprints = profile.UnlockedTurretBlueprints,
		NextTurretId = profile.NextTurretId,
	})

	return { Success = true, Turret = instance }
end

return TurretShopService
