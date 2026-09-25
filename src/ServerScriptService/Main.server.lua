--[[
	Main.server.lua
	Boots every service in dependency order. ModuleScripts only run their top-level code
	(which is where each service hooks up its RemoteEvents) the first time they're required —
	this script is what makes that first require happen.

	DataService must load first; everything else reads/writes through it.
]]

local Services = script.Parent.Services

-- Every require in this file goes through `load`, which stamps the name as it goes. The boot check
-- at the bottom then compares what ACTUALLY loaded against the Services folder, instead of against
-- a hand-typed copy of this list.
--
-- The copy is gone because it had drifted twice, and its two failure directions were not equally
-- visible. A name missing from the copy warns about a service that works (BaseLaserService did this
-- for months). A name PRESENT in the copy with no matching require produces SILENCE — which is
-- exactly the never-registered-handler bug the check exists to catch, so the check could be made to
-- lie about the one thing it is for. Deriving the set from the requires themselves removes that
-- direction entirely: you cannot get into LOADED without actually loading.
local LOADED = {}
local function load(name)
	local module = Services:FindFirstChild(name)
	if not module then
		-- Louder than the indexing error this replaces, and it names the caller's typo rather than
		-- reporting "attempt to index nil" from inside require.
		error(("[Salvage Protocol] Main.server.lua asked for Services.%s, which does not exist."):format(name), 0)
	end
	-- Stamped AFTER require returns, not before: a module whose top-level code throws did not
	-- register its handlers, so it has not "loaded" in the sense this check cares about.
	local result = require(module)
	LOADED[name] = true
	return result
end

load("DataService")
-- Shared cross-service state, required early and deliberately: both connect PlayerRemoving
-- handlers, and PlayerRemoving fires in CONNECTION order, which is this list's order. Requiring
-- them here (rather than letting whichever gameplay service happens to touch one first pull it
-- in) is what makes their teardown position predictable instead of an accident of require order.
load("RateLimiter")
load("PlayerActivityService")
load("PlayerSpeed")  -- owns WalkSpeed; must be loaded before anything that modifies it
load("DashService")
load("PlotService")
load("BaseService")
load("BaseLaserService")
load("StationService")
load("AdminService")
load("RaidEnergyService")
load("MiningService")
load("CraftingService")
load("ForgeService")
load("SmeltService")
load("WaveService")
load("ShopService")
load("NodeService")
load("SellService")  -- Shop station's sell side; reads OreConfig/RefinedOreConfig
	-- SellPrice fields, so it belongs near the other Shop-facing service (TurretShopService, below).
load("ExpeditionService")
load("AutoMinerService")
load("MineShaftService")
load("RaidRoomService")
-- TurretShopService was MISSING from this list entirely, which meant it never ran, which meant
-- Remotes.BuyTurretBlueprint.OnServerInvoke was never assigned. Invoking a RemoteFunction with no
-- OnServerInvoke doesn't error — the client thread just yields forever — so clicking Buy in the
-- Hub Shop did nothing at all, with nothing in the Output window to explain it. See the boot
-- check at the bottom of this file, added so this can never fail silently again.
load("TurretShopService")
-- TurretService was only ever loaded TRANSITIVELY (CombatEncounterService requires it, and
-- WaveService requires that). Its three remotes worked by luck of that chain; anything that broke
-- it would have killed turret placement the same silent way. Required explicitly now, same
-- reasoning as RateLimiter/PlayerActivityService above.
load("TurretService")
-- Testing aid: punching bags that behave as real enemies. Required last so it registers its
-- fallback encounter provider after everything it depends on is live.
load("BlackMarketService")
load("HackerService")
load("DroneService")
load("TrainingDummyService")
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
-- the wrong place. A missing require for TurretShopService did exactly that to the Hub
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
	for name in pairs(LOADED) do
		loaded[name] = true
	end
	-- Pulled in TRANSITIVELY by the modules above rather than required here — genuinely loaded, so
	-- not a bug, just invisible to LOADED, which only sees this file's own requires.
	--
	-- This list is the one hand-typed surface left, and it keeps the asymmetry the direct list
	-- used to have: a name added here without a real require goes quiet instead of warning. It
	-- stays hand-typed on purpose. The alternative — load() them all explicitly here so the set
	-- derives itself — would move WHEN each one loads, and load order in this file is load-bearing
	-- (PlayerRemoving fires in connection order, which is require order). Trading a documented
	-- hand-typed list for a silent change in teardown order is not a good trade in this file.
	for _, name in ipairs({ "CombatEncounterService", "CombatMath", "DamagePipeline", "EnemyAI", "EnemyAnimation", "RobotBehaviors", "WeaponToolService", "OreGate", "UltimateEffects", "StatusEffects", "ProjectileService", "GroundEffectService", "WeaponBehaviors", "DroneBehaviors", "DevShortcuts", "EnemyMovement", "EnemyAwareness", "RaidHealBudget", "RaidChest", "RunBuffService", "PlayerVitals" }) do
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
