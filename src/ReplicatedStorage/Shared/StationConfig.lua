--[[
	StationConfig.lua
	Pure data for physical base stations — the second layer of the base-area gate, on top of
	PlotService's "are you at your own base at all." Several Workbench actions now also require
	standing near the SPECIFIC station that does that job, not just anywhere in your plot.

	Studio setup: tag a Part or Model "Station" (StationConfig.Tag) anywhere inside a player's
	base footprint, and give it a child StringValue named "StationType" set to one of the keys in
	StationConfig.Types below (e.g. "Welding"). No code changes needed to add, move, or re-skin a
	station — StationService.lua finds it by tag/attribute alone.

	DefaultTab is which Workbench tab clicking that station jumps the HUD straight to (see
	MainHud.client.lua's setupStation) — nil means "no menu, this station doesn't have one yet"
	(the Forge, until a real smelting mechanic exists — see DESIGN_NOTES.md). This is convenience
	only: it does NOT hide the other tabs, and it is NOT what actually enforces the gate — that's
	StationService.IsPlayerNearStation, called independently by every gated remote handler
	(CraftingService/MiningService/AutoMinerService/MineShaftService).
]]

local StationConfig = {}

StationConfig.Tag = "Station"

StationConfig.InteractDistance = 12 -- studs; same ballpark as MiningService.MAX_MINING_DISTANCE

StationConfig.Types = {
	Crafting = {
		DisplayName = "Workbench",
		DefaultTab = "Tools", -- also covers Auto-Miner and Suit — general equipment/utility upgrades
		NotThereMessage = "You need to be at your Workbench to do that.",
	},
	Welding = {
		DisplayName = "Welding Station",
		DefaultTab = "Weapons", -- also covers Robots and Mods — building/equipping combat gear
		NotThereMessage = "You need to be at your Welding Station to do that.",
	},
	Forge = {
		DisplayName = "Forge",
		DefaultTab = nil, -- no real mechanic yet — smelting raw ore into refined material is a
		                   -- planned later addition, see DESIGN_NOTES.md's "Base" section
		NotThereMessage = "You need to be at your Forge to do that.",
	},
}

return StationConfig
