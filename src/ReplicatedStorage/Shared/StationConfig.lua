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
		Tabs = { "Tools", "Auto-Miner", "Suit" }, -- general equipment/utility upgrades
		DefaultTab = "Tools",
		NotThereMessage = "You need to be at your Workbench to do that.",
	},
	Welding = {
		DisplayName = "Welding Station",
		Tabs = { "Robots", "Mods" }, -- building/equipping robots + mod-slot management for everything
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
}

return StationConfig
