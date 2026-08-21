--[[
	Main.server.lua
	Boots every service in dependency order. ModuleScripts only run their top-level code
	(which is where each service hooks up its RemoteEvents) the first time they're required —
	this script is what makes that first require happen.

	DataService must load first; everything else reads/writes through it.
]]

local Services = script.Parent.Services

require(Services.DataService)
require(Services.MiningService)
require(Services.CraftingService)
require(Services.WaveService)
require(Services.ShopService)
require(Services.NodeService)
require(Services.ExpeditionService)

print("[Salvage Protocol] Server services online.")
