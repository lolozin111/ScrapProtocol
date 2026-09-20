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
	Scrap = 94296006655680,
	Cores = 112359366159478,
	Contraband = 83278330654841,
	LuckPotion = 117643038304020,

	-- Raw ore (OreConfig.Ores). Mined, sold, and smelted into the refined list below.
	IronOre = 93412131112952,
	CopperOre = 0,
	GoldOre = 79184251806902,
	PlatinumOre = 101320439587900,
	VoidiumShard = 135353466504716,

	-- Refined materials (RefinedOreConfig) — the Smelting rail's output, and most crafting costs.
	SteelIngot = 118765781238221,
	CopperCoil = 106020406435504,
	GoldBar = 119198566934318,
	PlatinumBar = 115430615912577,
	VoidiumCore = 76150916501622,

	-- Deployable robots (CraftingRecipes.Robots). The INVENTORY tile art; the Welding Station's big
	-- rig diagram is a separate line drawing, and those live in UiIconConfig as rig_<key>.
	Scrapbot = 102477920812341,
	SentryDrone = 109098921492966,
	IronGuardian = 138938029222788,
	ArcTurret = 93802162807649,

	-- Weapon/robot mods (ModConfig).
	SpeedCoil = 95018408400407,
	HeavyRounds = 118578059777869,
	Stabilizer = 120322266291020,
	ScavengedCapacitor = 89278132498090,
	ReinforcedPlating = 112762556871409,
	OverclockedCore = 111832355581983,

	-- Drone cores (DroneConfig) — the companion drone's four behaviours.
	Combat = 114414690706617,
	Support = 127238503541479,
	Scavenger = 89221173773308,
	Recon = 107442837326483,

	-- Pickaxe mods (ToolModConfig).
	SplitHead = 138268515877940,
	Featherweight = 127133505619462,
	Prospector = 95297940356655,

	-- Ultimates (UltimateConfig) — the on-hit/on-kill behaviours a weapon can roll.
	Detonator = 83733029314978,
	Ricochet = 79322061675508,
	LegBreaker = 135952806007558,
	HundredMil = 77017514152988,
	SharkBullet = 114022558608828,
	AimBot = 129598034747489,

	-- Cases (CaseConfig) — the Hacker Machine's Decode tab.
	Scavenged = 105995421751094,
	Encrypted = 131773440130726,
	Blackline = 110854142045135,
	Prototype = 116713673700457,

	-- Weapon FAMILIES, not individual weapons: six entries cover all 18 guns, because
	-- HudKit.getItemIcon falls back from a weapon key to its CraftingRecipes.Weapons[key].Family.
	-- Adding an exact per-weapon key here still wins over its family — the exact lookup runs first —
	-- so this is a floor, not a ceiling.
	Salvage = 76057469149445,
	Flamethrowers = 71609958807421,
	Bows = 88493101033878,
	Snipers = 119659829314346,
	GrenadeLaunchers = 86740195590783,
	Miniguns = 119937448797007,

	-- The one per-weapon icon so far, drawn separately from its Salvage family art. Uploaded as
	-- "SMGIcon"; the asset's own name doesn't matter, only the key it is listed under here.
	ScrapSMG = 97224766216636,
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
