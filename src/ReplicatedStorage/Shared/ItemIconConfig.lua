--[[
	ItemIconConfig.lua
	Asset IDs for inventory ITEM art — ore, refined materials, robots, mods, drone cores, pickaxes,
	ultimates, cases and weapon families. Read by HudKit.getItemIcon.

	The chrome/glyph half of the icon set lives in UiIconConfig.lua instead. Two files, matching the
	two Studio folders they back up (ItemIcons vs UiIcons), so an item key and a button key can never
	collide.

	HOW TO FILL THIS IN: upload each PNG to Roblox (Studio -> View -> Asset Manager -> Images), then
	replace the 0 next to its name with the number Roblox gives you back. Just the number — Get()
	adds the "rbxassetid://" prefix itself. A full "rbxassetid://123" string works too.

	A 0 means "not uploaded yet" and is NOT an error: every call site falls back to its text tile, so
	this can be filled a few at a time and each icon appears the moment its number lands here.

	LOOKUP ORDER (HudKit.getItemIcon): this file first, then the hand-built Studio folder
	ReplicatedStorage.ItemIcons, and on a miss the weapon's Family is tried the same way. So the
	folder convention still works exactly as it did — a value in either place is honoured, and
	nothing already built in Studio has to be moved here. This file is the preferred home only
	because Rojo syncs it: it is in git, it diffs, and it survives losing the place file, where the
	folder lives in the saved place alone.

	KEYS ARE LITERAL. Each one must match its config table's key character for character
	(OreConfig.Ores, RefinedOreConfig, CraftingRecipes.Robots, ModConfig, DroneConfig, ToolModConfig,
	UltimateConfig, CaseConfig, and the Family field on CraftingRecipes.Weapons). A near miss fails
	silently to the placeholder tile. Adding an entry to one of those configs means adding its key
	here too — or leaving it out and letting it draw the text tile, which is also fine.
]]

local ItemIconConfig = {}

ItemIconConfig.Icons = {
	-- Currencies and consumables. Scrap/Cores/Contraband are the wallet (see Shared/Wallet.lua);
	-- the wallet READOUT top-left uses its own lowercase UiIconConfig entries, while these are the
	-- ones drawn on cost lines and inventory tiles.
	Scrap = 0,
	Cores = 0,
	Contraband = 0,
	LuckPotion = 0,

	-- Raw ore (OreConfig.Ores). Mined, sold, and smelted into the refined list below.
	IronOre = 0,
	CopperOre = 0,
	GoldOre = 0,
	PlatinumOre = 0,
	VoidiumShard = 0,

	-- Refined materials (RefinedOreConfig) — the Smelting rail's output, and most crafting costs.
	SteelIngot = 0,
	CopperCoil = 0,
	GoldBar = 0,
	PlatinumBar = 0,
	VoidiumCore = 0,

	-- Deployable robots (CraftingRecipes.Robots). The INVENTORY tile art; the Welding Station's big
	-- rig diagram is a separate line drawing, and those live in UiIconConfig as rig_<key>.
	Scrapbot = 0,
	SentryDrone = 0,
	IronGuardian = 0,
	ArcTurret = 0,

	-- Weapon/robot mods (ModConfig).
	SpeedCoil = 0,
	HeavyRounds = 0,
	Stabilizer = 0,
	ScavengedCapacitor = 0,
	ReinforcedPlating = 0,
	OverclockedCore = 0,

	-- Drone cores (DroneConfig) — the companion drone's four behaviours.
	Combat = 0,
	Support = 0,
	Scavenger = 0,
	Recon = 0,

	-- Pickaxe mods (ToolModConfig).
	SplitHead = 0,
	Featherweight = 0,
	Prospector = 0,

	-- Ultimates (UltimateConfig) — the on-hit/on-kill behaviours a weapon can roll.
	Detonator = 0,
	Ricochet = 0,
	LegBreaker = 0,
	HundredMil = 0,
	SharkBullet = 0,
	AimBot = 0,

	-- Cases (CaseConfig) — the Hacker Machine's Decode tab.
	Scavenged = 0,
	Encrypted = 0,
	Blackline = 0,
	Prototype = 0,

	-- Weapon FAMILIES, not individual weapons: six entries cover all 18 guns, because
	-- HudKit.getItemIcon falls back from a weapon key to its CraftingRecipes.Weapons[key].Family.
	-- Adding an exact per-weapon key here still wins over its family — the exact lookup runs first —
	-- so this is a floor, not a ceiling.
	Salvage = 0,
	Flamethrowers = 0,
	Bows = 0,
	Snipers = 0,
	GrenadeLaunchers = 0,
	Miniguns = 0,
}

-- Normalizes whatever is in the table above into an Image string, or nil when unset. Accepts a bare
-- number (the common case) or an already-complete "rbxassetid://..." string, so neither is a
-- mistake. Deliberately identical to UiIconConfig.Get — the two tables are filled in the same way
-- and a difference between them would only ever be a trap.
function ItemIconConfig.Get(key: string): string?
	local value = ItemIconConfig.Icons[key]
	if value == nil or value == 0 or value == "" then
		return nil
	end
	if type(value) == "number" then
		return ("rbxassetid://%d"):format(value)
	end
	return tostring(value)
end

return ItemIconConfig
