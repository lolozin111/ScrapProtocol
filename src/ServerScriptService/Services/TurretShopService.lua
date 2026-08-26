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

	-- Buying a blueprint you already own would silently charge you again for nothing — the unlock
	-- is a permanent boolean, so there's nothing a second purchase could add.
	if profile.UnlockedTurretBlueprints[typeKey] then
		return { Success = false, Reason = ("You already know how to build the %s."):format(typeData.DisplayName) }
	end

	if not DataService.TrySpend(player, typeData.BlueprintCost) then
		return { Success = false, Reason = "Not enough Scrap" }
	end

	-- Unlocks the RECIPE ONLY — it does NOT mint a turret. Buying used to hand you a finished
	-- turret outright, which meant Cores alone bought base defense and skipped the game's actual
	-- loop entirely. Now the blueprint is knowledge and the materials are the real gate: craft it
	-- at the Welding Station with Scrap + ore (see CraftingService's "Turrets" tree and
	-- TurretConfig.CraftCost). This is also what finally gives UnlockedTurretBlueprints a job —
	-- until now it was written on purchase and never read by anything.
	profile.UnlockedTurretBlueprints[typeKey] = true

	Remotes.InventoryUpdate:FireClient(player, {
		UnlockedTurretBlueprints = profile.UnlockedTurretBlueprints,
	})
	DataService.PushWallet(player) -- the Scrap spent above; see DataService.PushWallet

	return { Success = true, TypeKey = typeKey }
end

return TurretShopService
