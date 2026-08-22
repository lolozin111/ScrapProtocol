--[[
	Main.server.lua
	Boots every service in dependency order. ModuleScripts only run their top-level code
	(which is where each service hooks up its RemoteEvents) the first time they're required —
	this script is what makes that first require happen.

	DataService must load first; everything else reads/writes through it.
]]

local Services = script.Parent.Services

require(Services.DataService)
require(Services.PlotService)
require(Services.BaseService)
require(Services.StationService)
require(Services.AdminService)
require(Services.RaidEnergyService)
require(Services.MiningService)
require(Services.CraftingService)
require(Services.WaveService)
require(Services.ShopService)
require(Services.NodeService)
require(Services.ExpeditionService)
require(Services.AutoMinerService)
require(Services.MineShaftService)
-- ResourceZoneService (the old scattered-ring ore layout) is no longer required — it's been
-- replaced by the dig-down MineShaftService above. The file's still on disk for reference; see
-- DESIGN_NOTES.md for why it was retired instead of tuned further.

print("[Salvage Protocol] Server services online.")
