--[[
	UiIconConfig.lua
	Asset IDs for the HUD's icon set. Read by HudKit's icon resolver.

	HOW TO FILL THIS IN: upload each PNG to Roblox (Asset Manager -> Images), then replace the 0
	next to its name with the number Roblox gives you back. Just the number — the resolver adds the
	"rbxassetid://" prefix itself. A full "rbxassetid://123" string works too if you paste one.

	A 0 means "not uploaded yet" and is not an error: the resolver treats it as missing, and every
	call site falls back to its text label rather than rendering an empty square. So this can be
	filled in a few at a time and each icon starts appearing as soon as its number lands here —
	same "missing art never breaks the loop" rule the rest of the project follows.

	WHY A CONFIG RATHER THAN A FOLDER OF ImageLabels: ReplicatedStorage.UiIcons still works and is
	checked as a fallback (see HudKit.resolveIcon), matching the ItemIcons convention. But that
	folder is hand-built in Studio, so it lives only in the saved place file, is invisible to git,
	and has to be rebuilt by hand if the place is ever lost or forked. Item icons are content that
	changes often and belongs in Studio; the HUD's own chrome is code, and belongs here where Rojo
	syncs it and a diff shows what changed.

	NAMING: `<key>` is the rest state, `<key>_hover` is the hover state. HudKit.button swaps to the
	_hover entry on MouseEnter and back on MouseLeave, and silently keeps the rest icon when no
	_hover entry is set — so hover art is optional per icon, not all-or-nothing.
]]

local UiIconConfig = {}

UiIconConfig.Icons = {
	-- Wallet readout (top-left). Static display — never hovered, so hover entries are optional.
	scrap = 94296006655680,
	cores = 112359366159478,
	energy = 85520253556045,

	-- Action row (bottom-centre). `defense` is the big Start Defense shield.
	inventory = 104907654078136,
	inventory_hover = 	140560506379845,
	defense = 81881363230776,
	defense_hover = 74378692449291,
	recall = 96674040688372,
	recall_hover = 91724933512363,

	-- Panel chrome.
	close = 	119986196809007,
	close_hover = 	72963123949945,
	chevron = 	123710429964857,
	chevron_hover = 	127322593699450,

	-- Inventory tabs.
	weapons = 74069286452743,
	weapons_hover = 116400364993597,
	robots = 	94437238830206,
	robots_hover = 106784062422552,
	mods = 	134432346461059,
	mods_hover = 98324493109733,
	materials = 137045467867215,
	materials_hover = 137045467867215,

	-- Robot rig silhouettes for the Welding Station's rig diagram — one line drawing per robot, in
	-- the same 180x230 proportion the design mockup used. NONE of these are uploaded yet, and that is
	-- not a blocker: MainHud draws each rig out of Frames (an outline chassis, per robot) and only
	-- swaps in the image once its ID lands here, so the tab is complete-looking either way. Same
	-- "missing art never breaks the loop" rule as everything else in this table.
	rig_Scrapbot = 0,
	rig_SentryDrone = 0,
	rig_IronGuardian = 0,
	rig_ArcTurret = 0,
	-- Drawn for a robot key with no rig_<key> entry at all (a Tier 5 added to CraftingRecipes before
	-- its art exists). Also unset, which just falls through to the drawn generic chassis.
	rig_generic = 0,

	-- The 9-sliced panel shape: square top-left and bottom-right, 45-degree cut top-right and
	-- bottom-left. White, tinted per element at runtime, so this one asset is every angular panel,
	-- button and tile in the HUD. See HudKit.plate for the SliceCenter it is drawn with.
	panelframe = 	107592152687673,
}

-- Normalizes whatever is in the table above into an Image string, or nil when unset.
-- Accepts a bare number (the common case — paste the ID Roblox gave you) or an already-complete
-- "rbxassetid://..." string, so neither form is a mistake.
function UiIconConfig.Get(key: string): string?
	local value = UiIconConfig.Icons[key]
	if value == nil or value == 0 or value == "" then
		return nil
	end
	if type(value) == "number" then
		return ("rbxassetid://%d"):format(value)
	end
	return tostring(value)
end

return UiIconConfig
