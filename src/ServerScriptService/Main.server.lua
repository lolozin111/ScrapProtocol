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
-- Testing aid: punching bags that behave as real enemies. Required last so it registers its
-- fallback encounter provider after everything it depends on is live.
require(Services.TrainingDummyService)
-- ResourceZoneService (the old scattered-ring ore layout) is no longer required — it's been
-- replaced by the dig-down MineShaftService above. The file's still on disk for reference; see
-- DESIGN_NOTES.md for why it was retired instead of tuned further.

----------------------------------------------------------------------
-- Boot check: every service module must actually be loaded.
--
-- A service that's never required never runs its top-level code, so the remote handlers it owns
-- are never registered. That's the worst failure mode in this codebase because it produces NO
-- symptom: invoking a RemoteFunction with no OnServerInvoke doesn't error, the client thread just
-- yields forever. No error, no Output line, no timeout — the button simply does nothing, and every
-- obvious explanation (wrong cost, wrong station, failed validation) sends you looking in entirely
-- the wrong place. A missing `require(Services.TurretShopService)` did exactly that to the Hub
-- Shop's Buy button, and cost real time to find.
--
-- Checking the SERVICES rather than the remotes is deliberate. The obvious version of this check —
-- looking for RemoteFunctions whose OnServerInvoke is nil — is impossible: Roblox callback members
-- are write-only, and merely READING `remote.OnServerInvoke` throws "you can only set the callback
-- value, get is not available." Services are introspectable, and an unloaded service is the actual
-- root cause anyway, so this catches the same bug one level up.
----------------------------------------------------------------------

do
	-- Modules deliberately NOT required, with why. Anything here is intentional; anything missing
	-- from both this list and the requires above is a bug this check exists to shout about.
	local INTENTIONALLY_UNLOADED = {
		ResourceZoneService = "retired — replaced by MineShaftService, kept for reference",
	}

	local loaded = {}
	for _, name in ipairs({
		"DataService", "RateLimiter", "PlayerActivityService", "PlotService", "BaseService",
		"StationService", "AdminService", "RaidEnergyService", "MiningService", "CraftingService",
		"ForgeService", "SmeltService", "WaveService", "ShopService", "NodeService",
		"ExpeditionService", "AutoMinerService", "MineShaftService", "RaidRoomService",
		"TurretShopService", "TurretService", "TrainingDummyService",
	}) do
		loaded[name] = true
	end
	-- Required transitively by the list above rather than directly — still genuinely loaded, so
	-- not a bug, just not visible in the require list.
	for _, name in ipairs({ "CombatEncounterService", "CombatMath", "DamagePipeline", "EnemyAI", "RobotBehaviors", "WeaponToolService", "OreGate", "UltimateEffects", "StatusEffects" }) do
		loaded[name] = true
	end

	local unloaded = {}
	for _, module in ipairs(Services:GetChildren()) do
		if module:IsA("ModuleScript") and not loaded[module.Name] and not INTENTIONALLY_UNLOADED[module.Name] then
			table.insert(unloaded, module.Name)
		end
	end

	if #unloaded > 0 then
		table.sort(unloaded)
		warn(("[Salvage Protocol] %d service module(s) exist but are NEVER required, so their remote handlers are not registered — calling those remotes from the client will hang silently: %s. Add them to the require list above."):format(
			#unloaded, table.concat(unloaded, ", ")))
	end
end

print("[Salvage Protocol] Server services online.")
