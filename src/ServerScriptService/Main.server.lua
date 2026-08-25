--[[
	Main.server.lua
	Boots every service in dependency order. ModuleScripts only run their top-level code
	(which is where each service hooks up its RemoteEvents) the first time they're required —
	this script is what makes that first require happen.

	DataService must load first; everything else reads/writes through it.
]]

local Services = script.Parent.Services

require(Services.DataService)
-- Shared cross-service state, required early and deliberately: both connect PlayerRemoving
-- handlers, and PlayerRemoving fires in CONNECTION order, which is this list's order. Requiring
-- them here (rather than letting whichever gameplay service happens to touch one first pull it
-- in) is what makes their teardown position predictable instead of an accident of require order.
require(Services.RateLimiter)
require(Services.PlayerActivityService)
require(Services.PlotService)
require(Services.BaseService)
require(Services.StationService)
require(Services.AdminService)
require(Services.RaidEnergyService)
require(Services.MiningService)
require(Services.CraftingService)
require(Services.ForgeService)
require(Services.SmeltService)
require(Services.WaveService)
require(Services.ShopService)
require(Services.NodeService)
require(Services.ExpeditionService)
require(Services.AutoMinerService)
require(Services.MineShaftService)
require(Services.RaidRoomService)
-- TurretShopService was MISSING from this list entirely, which meant it never ran, which meant
-- Remotes.BuyTurretBlueprint.OnServerInvoke was never assigned. Invoking a RemoteFunction with no
-- OnServerInvoke doesn't error — the client thread just yields forever — so clicking Buy in the
-- Hub Shop did nothing at all, with nothing in the Output window to explain it. See the boot
-- check at the bottom of this file, added so this can never fail silently again.
require(Services.TurretShopService)
-- TurretService was only ever loaded TRANSITIVELY (CombatEncounterService requires it, and
-- WaveService requires that). Its three remotes worked by luck of that chain; anything that broke
-- it would have killed turret placement the same silent way. Required explicitly now, same
-- reasoning as RateLimiter/PlayerActivityService above.
require(Services.TurretService)
-- ResourceZoneService (the old scattered-ring ore layout) is no longer required — it's been
-- replaced by the dig-down MineShaftService above. The file's still on disk for reference; see
-- DESIGN_NOTES.md for why it was retired instead of tuned further.

----------------------------------------------------------------------
-- Boot check: every RemoteFunction must have a handler.
--
-- A RemoteFunction whose OnServerInvoke was never assigned is the worst failure mode in this
-- codebase, because it produces NO symptom: the client's InvokeServer simply yields forever. No
-- error, no Output line, no timeout — the button just does nothing, and every obvious explanation
-- (wrong cost, wrong station, bad validation) sends you looking in the wrong place. That's exactly
-- what a missing `require(Services.TurretShopService)` above did to the Hub Shop's Buy button.
--
-- One pass at boot turns that into a loud, specific line in the Output window instead.
--
-- RemoteEvents deliberately aren't checked: there's no way to introspect whether OnServerEvent has
-- listeners, and an unhandled RemoteEvent fails far more gracefully anyway (the client fires into
-- the void and carries on, rather than hanging a thread mid-click).
----------------------------------------------------------------------

task.defer(function()
	local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
	local missing = {}
	for _, remote in ipairs(Remotes:GetChildren()) do
		if remote:IsA("RemoteFunction") and remote.OnServerInvoke == nil then
			table.insert(missing, remote.Name)
		end
	end
	if #missing > 0 then
		table.sort(missing)
		warn(("[Salvage Protocol] %d RemoteFunction(s) have NO OnServerInvoke handler — calling these from the client will hang forever with no error: %s. The service that owns them is probably missing from Main.server.lua's require list."):format(
			#missing, table.concat(missing, ", ")))
	end
end)

print("[Salvage Protocol] Server services online.")
