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
	scrap = 0,
	scrap_hover = 0,
	cores = 0,
	cores_hover = 0,
	energy = 0,
	energy_hover = 0,

	-- Action row (bottom-centre). `defense` is the big Start Defense shield.
	inventory = 0,
	inventory_hover = 0,
	defense = 0,
	defense_hover = 0,
	recall = 0,
	recall_hover = 0,

	-- Panel chrome.
	close = 0,
	close_hover = 0,
	chevron = 0,
	chevron_hover = 0,

	-- Inventory tabs.
	weapons = 0,
	weapons_hover = 0,
	robots = 0,
	robots_hover = 0,
	mods = 0,
	mods_hover = 0,
	materials = 0,
	materials_hover = 0,

	-- The 9-sliced panel shape: square top-left and bottom-right, 45-degree cut top-right and
	-- bottom-left. White, tinted per element at runtime, so this one asset is every angular panel,
	-- button and tile in the HUD. See HudKit.plate for the SliceCenter it is drawn with.
	panelframe = 0,
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
