--[[
	StationConfig.lua
	Pure data for physical base stations — the second layer of the base-area gate, on top of
	PlotService's "are you at your own base at all." Several Workbench actions now also require
	standing near the SPECIFIC station that does that job, not just anywhere in your plot.

	Studio setup: tag a Part or Model "Station" (StationConfig.Tag) anywhere inside a player's
	base footprint, and give it a child StringValue named "StationType" set to one of the keys in
	StationConfig.Types below (e.g. "Welding"). No code changes needed to add, move, or re-skin a
	station — StationService.lua finds it by tag/attribute alone.

	Tabs is the full set of Workbench tabs that station's menu shows at all — the HUD rebuilds the
	tab row down to just these every time this station is opened, so a Welding Station literally
	cannot show you the Suit tab and vice versa. DefaultTab (must be one of Tabs) is which of those
	the menu opens on. Both nil means "no menu, this station doesn't have one yet." None of this is
	what actually enforces the gate, though — that's StationService.IsPlayerNearStation, called
	independently by every gated remote handler (CraftingService/ForgeService/MiningService/
	AutoMinerService/MineShaftService), same as before; Tabs just keeps the menu itself from ever
	offering something this station can't actually do.

	The Forge went live once weapon crafting became weapon ROLLING (see ForgeConfig.lua/
	ForgeService.lua) — every weapon in the game is now Forged, not flat-crafted at the Welding
	Station, so Weapons moved from Welding's Tabs to Forge's.
]]

local StationConfig = {}

StationConfig.Tag = "Station"

StationConfig.InteractDistance = 12 -- studs; same ballpark as MiningService.MAX_MINING_DISTANCE

StationConfig.Types = {
	Crafting = {
		DisplayName = "Workbench",
		Tabs = { "Tools", "Auto-Miner", "Suit", "Base" }, -- general equipment/utility upgrades —
			-- "Base" added for the Base Defense phase: upgrading BaseTier plus placing/repositioning
			-- physical Turrets (deployed robots given a real spot in the world) both live here, since
			-- both are "how my base itself is laid out" decisions, not combat loadout ones.
		DefaultTab = "Tools",
		NotThereMessage = "You need to be at your Workbench to do that.",
	},
	Welding = {
		DisplayName = "Welding Station",
		Tabs = { "Robots", "Mods", "Turrets", "Drones" }, -- building/equipping robots, mod-slot management, and
			-- assembling turrets from a blueprint bought at the Hub Shop (TurretConfig.CraftCost) —
			-- turrets are machines you build from Scrap + ore, same as robots, so they belong here
			-- rather than on the Workbench with the "how my base is laid out" upgrades.
		DefaultTab = "Robots",
		NotThereMessage = "You need to be at your Welding Station to do that.",
	},
	Forge = {
		DisplayName = "Forge",
		Tabs = { "Weapons", "Smelting" }, -- roll a unique weapon instance, upgrade Luck, craft Luck
			-- Potions; Smelting turns raw ore into refined materials — see SmeltService.lua/
			-- RefinedOreConfig.lua
		DefaultTab = "Weapons",
		NotThereMessage = "You need to be at your Forge to do that.",
	},
	BlackMarket = {
		DisplayName = "Black Market",
		Tabs = { "Cases" }, -- rotating stock of sealed cases — see CaseConfig/BlackMarketService
		DefaultTab = "Cases",
		NotThereMessage = "You need to be at the Black Market to do that.",
		-- Shared world location, not part of anyone's base — so like the Hub Shop, its handlers
		-- deliberately do NOT check PlotService.IsPlayerInOwnPlot. Place it outside BaseTemplates.
	},
	Hacker = {
		DisplayName = "Hacker Machine",
		Tabs = { "Decode" }, -- opens sealed cases over real time — see HackerService
		DefaultTab = "Decode",
		NotThereMessage = "You need to be at the Hacker Machine to do that.",
	},
	Shop = {
		DisplayName = "Hub Shop",
		Tabs = { "Blueprints" }, -- rotating Turret blueprint stock — see TurretConfig
			-- .GetRotatingStock/TurretShopService.lua.
		DefaultTab = "Blueprints",
		NotThereMessage = "You need to be at the Hub Shop to do that.",
		-- Deliberately NOT gated behind PlotService.IsPlayerInOwnPlot by any of its remote handlers
		-- (see TurretShopService.lua) — the Hub is its own shared location out in the world, not
		-- part of any player's base, same as a loose testing block with no OwnerUserId stays open
		-- to everyone (BaseService.tagStationOwnership only ever stamps ownership onto stations
		-- that are descendants of a cloned per-player base Model). Place the Shop's Station-tagged
		-- Part/Model directly in the world (e.g. a "Hub" area), NOT inside BaseTemplates.
	},
}

return StationConfig
