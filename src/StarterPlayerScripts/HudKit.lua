--[[
	HudKit.lua
	The shared foundation every HUD panel is built out of: the palette, the Instance.new helpers,
	the ScreenGui, the client's mirror of the player's profile, the toast, and the row/tile builders.

	WHY THIS EXISTS: MainHud.client.lua grew to ~3,800 lines in a single chunk and hit Luau's hard
	limit of 200 locals per function scope — past which the script does not compile AT ALL, so the
	entire HUD was dead on join with only a cryptic "Out of local registers" to go on. Every panel
	added to that file spent more registers from the same budget.

	Moving shared pieces into ModuleScripts fixes that structurally: each module gets its own scope
	and its own 200, and a consumer spends ONE local (`local Hud = require(...)`) instead of one per
	helper. The point is only served if callers use `Hud.new` / `Hud.COLOR` directly rather than
	re-binding them to locals at the top of their file — that would just move the problem.

	`Hud.profile` is SHARED MUTABLE STATE and deliberately so: it is the client's mirror of the
	server profile, and every panel reads it. It must only ever be MUTATED (assigning into its
	fields), never REASSIGNED — every module holds a reference to the same table, so replacing it
	would leave them all pointed at a stale copy. Hud.MergeProfile is the only thing that writes it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RaidEnergyConfig = require(ReplicatedStorage.Shared.RaidEnergyConfig)
local UiIconConfig = require(ReplicatedStorage.Shared.UiIconConfig)
local Wallet = require(ReplicatedStorage.Shared.Wallet)

local LocalPlayer = Players.LocalPlayer

local HudKit = {}

HudKit.Remotes = ReplicatedStorage:WaitForChild("Remotes")
HudKit.LocalPlayer = LocalPlayer

----------------------------------------------------------------------
-- Palette
----------------------------------------------------------------------

-- Same rust/gunmetal family as the design doc, translated to Color3.
HudKit.COLOR = {
	-- Was (30, 26, 23); a Studio screenshot next to the design reference read flat/light where the
	-- reference reads bold/cool — panels needed to sit deeper against the world. Same hue ratio,
	-- each channel pulled down by 8, so it stays recognisably the same rust/gunmetal Panel, just
	-- denser, rather than a re-theme.
	Panel = Color3.fromRGB(22, 18, 15),
	PanelLight = Color3.fromRGB(40, 35, 31),
	Line = Color3.fromRGB(60, 53, 47),
	Text = Color3.fromRGB(237, 231, 220),
	Muted = Color3.fromRGB(167, 156, 140),
	Accent = Color3.fromRGB(224, 122, 59),
	AccentDark = Color3.fromRGB(178, 76, 24),
	Good = Color3.fromRGB(95, 160, 130),
	Bad = Color3.fromRGB(190, 90, 75),
}

local COLOR = HudKit.COLOR

----------------------------------------------------------------------
-- Design tokens
----------------------------------------------------------------------
-- Additive, sibling to COLOR: named roles instead of every panel picking its own font/size/gap by
-- eyeballing whatever the panel next to it used, which is how the file ended up with a dozen
-- near-identical-but-not-quite text sizes.

-- Enum.Font membership for a specific weight isn't as stable across Roblox versions/forks as the
-- ancient standbys (SourceSans/SourceSansBold have been there for years); indexing a name that
-- doesn't exist THROWS immediately, and unlike every other "missing art" fallback in this file
-- (icons, panelframe), there is no nil-and-continue here — a bad guess would fail the moment this
-- module is required, which is before any panel exists to show a warning in. Resolve defensively:
-- pcall the lookup by name and fall back to a long-stable Gotham weight (present in Roblox's
-- original font set) rather than assume the newer name is spelled/available exactly as expected.
local function resolveFont(name: string, fallback: Enum.Font): Enum.Font
	local ok, value = pcall(function()
		return (Enum.Font :: any)[name]
	end)
	if ok and typeof(value) == "EnumItem" then
		return value
	end
	warn(("[HudKit] Enum.Font.%s not available on this Roblox version; falling back to %s"):format(name, fallback.Name))
	return fallback
end

-- Montserrat for anything that should read as a heading/display number (chosen because it's a real
-- Roblox enum font AND is what the design mockups use); SourceSans/-Bold for body copy; Code for
-- numeric readouts (ore counts, timers) where a monospaced look reads as "instrument panel".
--
-- Display was Enum.Font.Montserrat (the REGULAR weight) and rendered thin/papery next to the
-- mockup's heavy, solid headings — MontserratBold is the fix. DisplayMedium is additive: a lighter
-- display weight for anywhere Bold is too heavy, without forcing a caller down to Body's SourceSans
-- look. Both fall back to a Gotham weight (see resolveFont above) if the exact enum name isn't
-- present; falling back to a MATCHING family for both keeps a fallback HUD internally consistent
-- rather than pairing a heavy Gotham heading with a Montserrat subheading.
HudKit.FONT = {
	Display = resolveFont("MontserratBold", Enum.Font.GothamBold),
	DisplayMedium = resolveFont("MontserratMedium", Enum.Font.GothamMedium),
	Body = Enum.Font.SourceSans,
	BodyBold = Enum.Font.SourceSansBold,
	Mono = Enum.Font.Code,
}

-- Small type scale, pulled from sizes already scattered across the file (13/14/16 body text, 18-ish
-- headings) rather than invented fresh — so adopting these in a panel is a no-visual-diff change.
-- Bumped from the original 11/15/18/17 after a Studio screenshot showed everything reading too
-- small at actual play distance. Readout gets the biggest jump of the four (17 -> 20, proportionally
-- more than Title's 18 -> 20) because the wallet numbers it sizes are the single most-glanced value
-- on screen and were sitting at literal body-copy size before this.
HudKit.TEXTSIZE = {
	Label = 13,
	Body = 16,
	Title = 20,
	Readout = 20,
}

-- Spacing scale. Panels currently hardcode padding/gaps as raw numbers; this exists so new panels
-- (and, eventually, migrated old ones) can express intent ("M gap between rows") instead of "12".
HudKit.SPACE = {
	XS = 4,
	S = 8,
	M = 12,
	L = 16,
	XL = 24,
}

-- Matches corner()'s existing default (6) and the panel radius already used around the HUD, named
-- so a caller doesn't have to remember which raw number means which thing.
HudKit.RADIUS = {
	Button = 6,
	Panel = 10,
}

-- Lerp a color toward white/black by `amount` (0-1). Hover/press states are DERIVED from these
-- rather than a second hardcoded palette, so editing a COLOR.* value (say, retuning Accent) keeps
-- every button variant's hover/press shade in sync automatically instead of needing a matching edit
-- somewhere else that's easy to forget.
function HudKit.lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

function HudKit.darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

----------------------------------------------------------------------
-- Instance helpers
----------------------------------------------------------------------

function HudKit.new(className: string, props, children)
	local inst = Instance.new(className)
	for key, value in pairs(props or {}) do
		inst[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	return inst
end

function HudKit.corner(radius: number?)
	return HudKit.new("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

function HudKit.stroke()
	return HudKit.new("UIStroke", { Color = COLOR.Line, Thickness = 1 })
end

HudKit.screenGui = HudKit.new("ScreenGui", {
	Name = "SalvageHUD",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = LocalPlayer:WaitForChild("PlayerGui"),
})

----------------------------------------------------------------------
-- Profile mirror
----------------------------------------------------------------------

-- Defaults matter: panels render before the first GetProfile/InventoryUpdate arrives, and reading
-- nil out of these would error rather than showing an empty state.
--
-- Fields that are legitimately absent most of the time (EquippedWeaponId, SmeltJob) are omitted on
-- purpose — nil reads correctly as "not set" whether the key is present-and-nil or missing, and the
-- server only ever sends them as `value or false` so a clear survives the wire.
HudKit.profile = {
	Scrap = 0, Cores = 0,
	OreCounts = {}, CraftedRobots = {}, DeployedRobots = {},
	CraftedStructures = {}, OwnedGamePasses = {},
	CraftedMods = {}, EquippedMods = {},
	Turrets = {}, UnlockedTurretBlueprints = {},
	Weapons = {}, ForgeTier = 1, LuckPotions = 0, ForgePityCounter = 0,
	RefinedOreCounts = {}, CoreItems = {},
	HighestWave = 0,
	Energy = RaidEnergyConfig.MaxEnergy,
	SuitTier = 1,
	ResearchTier = 1,
}

-- Applies an InventoryUpdate patch (or a full GetProfile snapshot). MUTATES in place — see this
-- file's header on why the table is never replaced.
function HudKit.MergeProfile(patch)
	for key, value in pairs(patch or {}) do
		HudKit.profile[key] = value
	end
end

----------------------------------------------------------------------
-- Toast
----------------------------------------------------------------------

-- Every failure path used to be a bare warn(), which writes to the Studio OUTPUT WINDOW and is
-- invisible to someone actually playing — so a refused action looked identical to a dead button.
local toastLabel = HudKit.new("TextLabel", {
	Name = "Toast",
	BackgroundColor3 = COLOR.Panel,
	Position = UDim2.new(0.5, 0, 0, 70),
	AnchorPoint = Vector2.new(0.5, 0),
	Size = UDim2.new(0, 420, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Visible = false,
	ZIndex = 20, -- above the craft/inventory panels, which is exactly when these fire
	Font = Enum.Font.SourceSans,
	Text = "",
	TextColor3 = COLOR.Text,
	TextSize = 16,
	TextWrapped = true,
	Parent = HudKit.screenGui,
}, { HudKit.corner(6), HudKit.stroke(), HudKit.new("UIPadding", {
	PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
}) })

-- The token guard means a newer toast always wins, rather than an older one's timer hiding it early.
local toastToken = 0

function HudKit.showToast(text: string, seconds: number?)
	toastToken += 1
	local myToken = toastToken
	toastLabel.Text = text
	toastLabel.Visible = true
	task.delay(seconds or 3.5, function()
		if toastToken == myToken then
			toastLabel.Visible = false
		end
	end)
end

-- Use for every rejected action instead of a bare warn(). Keeps the Output line (useful in Studio,
-- and it carries the context prefix) while ALSO telling the player something in-game. `reason`
-- comes straight from the server's { Success = false, Reason = ... } payload.
function HudKit.showFailure(context: string, reason: string?)
	local text = reason or "That didn't work."
	warn(("[HUD] %s: %s"):format(context, text))
	HudKit.showToast(text)
end

----------------------------------------------------------------------
-- Shared builders
----------------------------------------------------------------------

-- Optional icons: add an ImageLabel/ImageButton/Decal to ReplicatedStorage.ItemIcons (or UiIcons,
-- below) named exactly like the item/UI key. FindFirstChild, never WaitForChild — a missing icon
-- must fall back to the text tile immediately rather than yielding the whole render.
local ItemIcons = ReplicatedStorage:FindFirstChild("ItemIcons")
local UiIcons = ReplicatedStorage:FindFirstChild("UiIcons")

-- The one place that actually walks a folder looking for a key. getItemIcon/getUiIcon/applyIcon
-- all call this instead of each re-implementing the FindFirstChild-never-WaitForChild rule and the
-- Decal/ImageLabel/ImageButton branching — those two had already drifted slightly before this was
-- pulled out (one checked `~= ""`, the other didn't), which is exactly the kind of silent
-- inconsistency this project's style guide calls out.
--
-- Returns the template instance itself (not just the image string) so applyIcon can also read
-- ImageRectOffset/ImageRectSize off of it.
local function resolveIcon(folder: Instance?, key: string): (Instance?, string?)
	local inst = folder and folder:FindFirstChild(key)
	if not inst then
		return nil, nil
	end
	if (inst:IsA("ImageLabel") or inst:IsA("ImageButton")) and inst.Image ~= "" then
		return inst, inst.Image
	elseif inst:IsA("Decal") and inst.Texture ~= "" then
		return inst, inst.Texture
	end
	return nil, nil
end

function HudKit.getItemIcon(key: string): string?
	local _, image = resolveIcon(ItemIcons, key)
	return image
end

-- Same lookup, against ReplicatedStorage.UiIcons instead of ItemIcons — for chrome/buttons/panel
-- glyphs rather than inventory items, so the two sets can be populated and organized independently
-- in Studio without one folder's naming colliding with the other's.
-- UiIconConfig first, the UiIcons folder second. The config is the intended home for the HUD's own
-- chrome (it is Rojo-synced, diffable, and survives losing the place file); the folder stays
-- supported so the ItemIcons convention still works for anyone who prefers building icons in
-- Studio, and so a value set in either place is honoured rather than one silently winning.
function HudKit.getUiIcon(key: string): string?
	local configured = UiIconConfig.Get(key)
	if configured then
		return configured
	end
	local _, image = resolveIcon(UiIcons, key)
	return image
end

-- Same resolution applyIcon uses (config first when there's no folderName override, else the
-- folder walk), but returns the raw (image, template) pair instead of writing into a label —
-- pulled out so a caller can find out WHETHER an icon will resolve before it has an ImageLabel to
-- hand to applyIcon yet. HudKit.button() needs exactly that: it has to decide whether the caption
-- is a real `text` or an `iconFallbackText` before it builds anything, and applyIcon can only ever
-- report success by actually mutating a label it doesn't have at that point in the build.
local function resolveIconImage(key: string, folderName: string?): (string?, Instance?)
	if not folderName then
		local configured = UiIconConfig.Get(key)
		if configured then
			return configured, nil -- no template instance for a config-sourced icon; see applyIcon
		end
	end
	local folder = if folderName then ReplicatedStorage:FindFirstChild(folderName) else UiIcons
	local inst, image = resolveIcon(folder, key)
	if not inst or not image then
		return nil, nil
	end
	return image, inst
end

-- Sets Image on `imageLabel` AND copies ImageRectOffset/ImageRectSize from the template instance
-- when it carries them. Defaults to the UiIcons folder; pass folderName = "ItemIcons" to point at
-- the other one instead.
--
-- WHY THE RECT COPY MATTERS: because the icon folders hold real ImageLabel instances rather than
-- bare image IDs, a template can already carry rect properties today — which means a future move
-- from a dozen separate image assets to one sprite atlas needs ZERO code changes anywhere that
-- calls applyIcon. You set the rect on the template in Studio and every caller already honors it.
--
-- Returns false and leaves `imageLabel` untouched when the icon is missing — per this project's
-- rule that missing art must never break the loop, a caller must be able to treat that as "render
-- the fallback" rather than a special case to check for separately.
function HudKit.applyIcon(imageLabel: ImageLabel, key: string, folderName: string?): boolean
	local image, inst = resolveIconImage(key, folderName)
	if not image then
		return false
	end
	imageLabel.Image = image
	-- inst is nil for a config-sourced icon (no template to copy rect properties from — see
	-- resolveIconImage above), so this must check inst before IsA, not just its class.
	if inst and (inst:IsA("ImageLabel") or inst:IsA("ImageButton")) then
		imageLabel.ImageRectOffset = inst.ImageRectOffset
		imageLabel.ImageRectSize = inst.ImageRectSize
	end
	return true
end

-- Names and orders a cost table exactly the way the server resolves it — including refined
-- materials and CoreItems, which the HUD's own formatter used to render as raw keys.
function HudKit.costString(cost): string
	return Wallet.CostString(cost)
end

-- Row geometry, named rather than inlined below: the button's own height has to clear
-- BUTTON_MIN_SLICE_SIZE (see that constant's comment further down) or HudKit.button() silently
-- drops it onto the plain rounded-corner fallback instead of the angular 9-slice frame — which
-- was the whole point of routing this row's button through HudKit.button() at all. 40 is that
-- floor exactly. ROW_HEIGHT grew from the old flat 52 to fit TEXTSIZE.Title (20, up from a
-- hardcoded 16) over TEXTSIZE.Label (13) stacked with SPACE.XS between them, plus enough vertical
-- padding on both edges for a 40px button to sit centered without touching the row's top/bottom.
local ROW_BUTTON_WIDTH = 110
local ROW_BUTTON_HEIGHT = 40
local ROW_HEIGHT = 64
local ROW_TITLE_HEIGHT = 24
local ROW_SUBTITLE_HEIGHT = 18
-- Width reserved on the right for the button plus a gap, subtracted from both text labels so
-- neither one can run under it.
local ROW_TEXT_RIGHT_RESERVE = ROW_BUTTON_WIDTH + HudKit.SPACE.L

-- The standard list row: title, subtitle, and one action button. Used by every panel, which is why
-- it lives here rather than in whichever one happened to define it first.
--
-- SIGNATURE AND RETURN SHAPE ARE UNCHANGED: still (displayName, subtitle, buttonText, onClick) ->
-- Frame. At least five files call this and every one of them either does
-- `HudKit.makeRow(...).Parent = someList` or calls it as a bare statement — none of them keeps a
-- reference to reach inside it, and several (ModPicker, ShopPanel, TurretPanel, ResearchPanel,
-- MainHud) rebuild their lists by destroying every `child:IsA("Frame")`, so the return must stay a
-- real Frame, not some other GuiObject subclass.
--
-- displayName/subtitle are CALLER-SUPPLIED item/recipe/ore names and must reach the labels
-- byte-for-byte — no case transform. buttonText is the row's own chrome (Equip/Craft/Locked/...),
-- so it's the one piece uppercased here, matching the UPPERCASE + FONT.Display treatment already
-- used for section labels elsewhere in the HUD.
-- `variant` is an OPTIONAL 5th argument, defaulting to "primary". Added because a row's button is
-- usually the affirmative action (Equip/Craft/Claim) but not always: "Unequip" is destructive and
-- "Maxed"/"Locked"/"Known" are dead ends, and painting all three in the same accent fill tells the
-- player they are the same kind of action. Optional and last, so every existing 4-argument call
-- site keeps working untouched. Deliberately NOT inferred from buttonText — matching on label
-- strings would silently mis-colour the first time someone reworded one.
function HudKit.makeRow(displayName: string, subtitle: string, buttonText: string, onClick, variant: string?)
	local row = HudKit.new("Frame", {
		BackgroundColor3 = COLOR.PanelLight,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
	}, { HudKit.corner(HudKit.RADIUS.Button) })

	HudKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, HudKit.SPACE.M, 0, HudKit.SPACE.S),
		Size = UDim2.new(1, -(ROW_TEXT_RIGHT_RESERVE + HudKit.SPACE.M), 0, ROW_TITLE_HEIGHT),
		Font = HudKit.FONT.Display,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR.Text,
		TextSize = HudKit.TEXTSIZE.Title,
		Text = displayName,
		Parent = row,
	})

	HudKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, HudKit.SPACE.M, 0, HudKit.SPACE.S + ROW_TITLE_HEIGHT + HudKit.SPACE.XS),
		Size = UDim2.new(1, -(ROW_TEXT_RIGHT_RESERVE + HudKit.SPACE.M), 0, ROW_SUBTITLE_HEIGHT),
		Font = HudKit.FONT.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR.Muted,
		TextSize = HudKit.TEXTSIZE.Label,
		Text = subtitle,
		Parent = row,
	})

	-- Routed through HudKit.button() instead of a hand-rolled TextButton: this is the one bit of
	-- HudKit that had no hover/press feedback and no outline at all, since it predates button()
	-- entirely. `primary` because a row's action is almost always the affirmative one on that row
	-- (Equip/Craft/Upgrade/Claim/Decode/...); a handful of call sites use it for a disabled-looking
	-- state instead (Maxed/Locked/Known) or a destructive one (Unequip), but the signature has no
	-- room for a caller-chosen variant, and those rows still read fine solid-accent-colored — this
	-- is a one-look-fits-all row action, not a status indicator.
	HudKit.button({
		variant = variant or "primary",
		text = buttonText:upper(),
		size = UDim2.new(0, ROW_BUTTON_WIDTH, 0, ROW_BUTTON_HEIGHT),
		position = UDim2.new(1, -HudKit.SPACE.M, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		parent = row,
		onClick = onClick,
	})

	return row
end

----------------------------------------------------------------------
-- Shared 9-slice panel asset
----------------------------------------------------------------------
-- panelframe is a 64x64 white PNG: square top-left/bottom-right corners, a 45-degree 16px cut
-- top-right and bottom-left. SliceCenter's margins land just past that cut on every edge, so the
-- corner regions (which must stay unstretched to keep the cut crisp) are exactly the drawn art and
-- only the centre strip between them tiles/stretches to fill whatever size the element is.
--
-- Shared between HudKit.button() (right below) and HudKit.plate() (further down): both need the
-- exact same slice geometry to look cut from the same sheet metal, and a future retune of the
-- asset only has one Rect to touch instead of two that can silently drift apart.
--
-- MINIMUM SIZE: a 9-slice needs an element at least twice the slice inset per axis (roughly 40x40
-- here) or the corner regions overlap and the cut renders wrong. plate()'s shell/surface are always
-- far bigger than that so it never has to check; HudKit.button() DOES check, via
-- BUTTON_MIN_SLICE_SIZE below, because any button under that size (panelHeader's close button used
-- to be a concrete example, at 28px, before it grew to 40 specifically to clear this floor) would
-- render broken and needs the plain rounded HudKit.corner() path instead.
local PANEL_FRAME_SLICE_CENTER = Rect.new(20, 20, 44, 44)

-- The pixel size of that 45-degree cut itself, in the 64px source (matches SliceCenter's margins:
-- 64 - 44 = 20, minus the 4px of unstretched corner art past the cut = 16). Named so anything that
-- needs to stay clear of the diagonal — currently just HudKit.accentCap below — reads its intent
-- off one shared number instead of a bare 16 that looks unrelated to PANEL_FRAME_SLICE_CENTER at
-- a glance and could drift from it on a future asset retune.
local PANEL_FRAME_CORNER_CUT = 16

----------------------------------------------------------------------
-- Buttons: variants + hover/press feedback
----------------------------------------------------------------------
-- There was not one TweenService call anywhere in the HUD before this, and no hover/press state on
-- any button — which is most of why buttons here don't read as clickable beyond the cursor icon
-- changing on top of them. HudKit.button() is additive: existing call sites building their own
-- TextButton by hand (makeRow's included) are untouched and keep working exactly as before.

local BUTTON_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BUTTON_HOVER_LIGHTEN = 0.12
local BUTTON_PRESS_DARKEN = 0.18
-- Below this (on either axis), a button falls back to the plain rounded-corner path instead of the
-- 9-slice — see PANEL_FRAME_SLICE_CENTER's MINIMUM SIZE note above for why. panelHeader's close
-- button used to be the concrete case this existed for, at 28px; it's now 40 (exactly this floor)
-- specifically so it clears it and gets the sliced/angular frame instead.
local BUTTON_MIN_SLICE_SIZE = 40

-- BUG THIS FIXES: isSliceable used to compare restSize.X.Offset/.Y.Offset straight against
-- BUTTON_MIN_SLICE_SIZE, which only means anything for an Offset-sized axis. The inventory
-- category tabs are UDim2.new(0, 91, 1, 0) — height is 1 Scale / 0 Offset — so
-- restSize.Y.Offset read as 0, failed the floor, and every scale-sized button silently fell back
-- to the plain rounded HudKit.corner() path no matter how tall it actually rendered. A caller
-- raising that row's height had zero effect on this check, because the UDim2 never carried a
-- pixel number for this to read in the first place.
--
-- A Scale-based axis has no knowable pixel size at BUILD time (AbsoluteSize is still 0 before the
-- first layout pass runs), so there is no correct number to compare here. Assume it clears the
-- floor: a scale-sized button living inside an already-laid-out row is essentially always well
-- past 40px, and guessing "too small" is the worse failure of the two — it would silently round
-- off a button that should be angular, with nothing in Output to explain why.
local function axisClears(dim: UDim, minPx: number): boolean
	if dim.Scale > 0 then
		return true
	end
	return dim.Offset >= minPx
end

-- Fraction of the button's own height, not a fixed pixel count: a 20px icon read as tiny on a
-- 108x72 hero button and identically-sized on a 56x56 secondary one, so the hero action never read
-- as one. 0.55 was picked by eye against the design's Start Defense button.
local BUTTON_ICON_SCALE_DEFAULT = 0.55
-- Pixels between the button's left edge and an icon-with-text layout. Kept as its own named constant
-- (rather than inlined into the Position/padding math below) because both of those need to agree on
-- it, and the icon-only (centred) layout does not use it at all.
local BUTTON_ICON_LEFT_INSET = 8

-- Every variant gets a UIStroke now — buttons were reading flat against the world without one.
-- BUG THIS FIXES: primary/danger originally derived their edge via darken(restColor, ...) — a
-- DARKER edge on a fill that's already dark relative to this HUD's near-black panels/world
-- backdrop is functionally invisible, which is exactly why "outlines were added" and the user
-- still reported seeing no outline at all. Every variant now derives its stroke by LIGHTENING
-- restColor instead, so the rim reads brighter than the fill against both a dark panel and the
-- game world behind it, regardless of variant. Deriving from whatever fill is ACTUALLY in play
-- (variant default or an opts.fill override) means a custom-tinted button — a rarity color, an
-- equipped mod's own color — still gets a correctly-toned edge instead of the wrong variant's
-- baked-in one.
--
-- 0.28: enough to clearly separate the edge from the fill at a glance (0.12's hover-lighten was
-- tried first and read as barely-there once actually screenshotted) without lerping so far toward
-- white that the stroke reads as its own bright border rather than an edge on the button. Secondary
-- used to get a fixed COLOR.Line stroke instead of a derived one; COLOR.Line (60, 53, 47) is dimmer
-- than lighten(PanelLight, 0.28) lands, which would make secondary the one washed-out-looking
-- variant next to primary/danger's new edges — so secondary now derives the same way as the other
-- two instead of keeping its own fixed color.
-- The outline is NOT a UIStroke. Three attempts at one rendered nothing: a UIStroke has no
-- background edge to trace on a transparent GuiObject, and `btn` is transparent whenever its fill
-- lives on a child. This is the technique plate() already uses for its bevel (and the reason the
-- status panel reads correctly): a slightly LARGER copy of the same shape sitting behind the
-- button, in a lighter shade of its own fill, so only its edges show around the button's rim.
-- OUTLINE_EXPAND is per-side, so the visible rim is that many pixels thick.
-- Rim thickness in pixels. 3 reads clearly at normal UI scale without eating into the fill; the
-- inventory tabs sit 8px apart, so a thicker rim would start closing that gap visually.
local BUTTON_OUTLINE_EXPAND = 3
local BUTTON_OUTLINE_LIGHTEN = 0.35
-- Hard offset shadow (HudButtonOptions.dropShadow), an ALTERNATIVE to the gradient above, not a
-- second layer on top of it — the reference draws tab buttons with a flat fill and a dropped-out
-- duplicate shape beneath, never both a gradient AND a shadow on the same button.
local BUTTON_DROPSHADOW_OFFSET = 2 -- matches the reference's literal `box-shadow: 0 2px 0 <darker>`:
	-- no blur, no horizontal offset, just the same shape nudged straight down — the closest Roblox
	-- (no box-shadow primitive at all) gets to that CSS effect.
local BUTTON_DROPSHADOW_DARKEN = 0.35 -- deliberately steeper than the gradient's 0.72-bottom ramp:
	-- this has to read as one hard step down, not a soft fade, or it just looks like a second gradient.

-- Base fill/text per variant. Hover/press shades are DERIVED from `fill` via lighten()/darken() at
-- button-build time rather than listed here, so this table is the only place a variant's color is
-- ever spelled out.
-- No `stroke` field any more: every button gets the outline layer unconditionally (see
-- BUTTON_OUTLINE_EXPAND above), so there is nothing left for a variant to opt in or out of.
local BUTTON_VARIANTS = {
	-- The one loud action on screen: Accent fill, dark text so it reads as a solid, confident button
	-- rather than colored outline text.
	primary = { fill = COLOR.Accent, text = COLOR.Panel },
	-- Everything else: matches the existing PanelLight/Line look used by rows and most panel chrome.
	secondary = { fill = COLOR.PanelLight, text = COLOR.Text },
	-- Destructive actions (unequip, scrap, abandon...): Bad fill, light text for contrast.
	danger = { fill = COLOR.Bad, text = COLOR.Text },
}

export type HudButtonOptions = {
	variant: string?, -- "primary" | "secondary" | "danger", defaults to "secondary"
	fill: Color3?, -- overrides the variant's rest color at build time; hover/press are still
		-- DERIVED from it via lighten()/darken(), same as a variant's fill. For the buttons whose
		-- fill is a per-render computed color (a rarity tint, an equipped mod's own color) that
		-- maps to none of the three named variants -- those used to have to be hand-rolled outside
		-- HudKit.button() entirely, missing the hover/press feedback everything else here gets.
	text: string?,
	icon: string?, -- optional key into UiIcons (or `iconFolder`); falls back to text-only if missing
	-- Shown ONLY when `icon` fails to resolve — never alongside a resolved icon. This is the fix for
	-- a real bug: `icon = "close", text = "X"` used to render the close glyph AND a literal "X"
	-- caption side by side once "close" actually resolved, which read as two close buttons stacked
	-- on one control. A caller that wants an icon-only button with a text fallback for missing art
	-- must use iconFallbackText, not text — `text` alongside `icon` is for a button that genuinely
	-- wants a label beside its icon (unaffected by this option; still rendered every time).
	iconFallbackText: string?,
	iconFolder: string?,
	-- Hard 90-degree corners: skips BOTH the panelframe 9-slice and corner() rounding. A deliberate
	-- SHAPE contrast, not an oversight — the panel close button uses it so it reads as a distinct
	-- square against a HUD where everything else is cut. Don't "fix" it to match its neighbours.
	square: boolean?,
	iconScale: number?, -- fraction of the button's height the icon occupies; defaults to
		-- BUTTON_ICON_SCALE_DEFAULT below. Override for a button that wants a stockier or daintier
		-- icon than the default without forcing every other button's icon to follow.
	dropShadow: boolean?, -- hard offset shadow instead of the top-to-bottom gradient (see
		-- BUTTON_DROPSHADOW_OFFSET/_DARKEN above) — an alternative treatment, not an addition; true
		-- also suppresses the gradient on this button so the two never stack and look muddy together.
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	parent: Instance?,
	onClick: (() -> ())?,
}

-- Per-button mutable color state, keyed by the button instance itself. HudKit.setButtonFill/
-- setButtonVariant (below) need somewhere outside the button() closure to write a new rest color
-- so the hover/press handlers pick it up, and this is that somewhere.
--
-- WEAK KEYS ON PURPOSE: panels in this HUD are created and destroyed constantly (MainHud rebuilds
-- whole panels on refresh), and every one of those buttons would otherwise sit in this table
-- forever just because it was once colored via setButtonFill -- a strong table here is a slow,
-- silent memory leak that nothing in Studio would ever surface. `__mode = "k"` lets a destroyed
-- button (once nothing else references it) be collected along with its entry.
local buttonState = setmetatable({}, { __mode = "k" })

-- Wraps a TextButton so every MouseEnter/Leave/Down/Up tween goes through one Cancel-then-Play,
-- rather than stacking competing tweens when a player mashes a button or mouses in and out fast.
--
-- GUARD: panels in this HUD are created and destroyed repeatedly (MainHud rebuilds whole panels on
-- refresh), so a MouseLeave/Up can fire after `btn` is already destroyed and parented to nil.
-- Playing a Tween on a destroyed instance throws, so every call here bails out on `not btn.Parent`
-- instead of assuming the button is still mounted.
--
-- `state` holds the tweens AND the button's rest/hover/press colors (see `buttonState` above) so
-- HudKit.setButtonFill can both cancel an in-flight tween and update the very colors this function
-- reads on the next MouseEnter/Leave -- there is no closed-over color left to go stale.
--
-- TWO INDEPENDENT SLOTS, not one: a hover/press event now animates the button's own Size/Position
-- (`tween`, using `key`) AND the visible fill color (`tweenFill`, using a different key) in the same
-- breath, and those can land on the SAME instance (the plain-rounded fallback path, where the fill
-- IS the button's own BackgroundColor3) or DIFFERENT instances (the 9-slice path, where the fill is
-- a child ImageLabel's ImageColor3 -- see HudKit.button's isSliceable branch). Sharing one slot
-- would make the second tween() call of the pair cancel the first before it ever plays, since
-- makeTweener unconditionally cancels whatever already occupies that slot. `target` and `state`'s
-- Parent-guard both key off `btn` specifically (not `target`) because a 9-slice fill target is a
-- child of `btn` and is torn down along with it -- checking the child's own .Parent would work too,
-- but checking `btn` once here matches every other destroyed-instance guard in this file.
local function makeTweener(btn: TextButton, target: Instance, state, key: string)
	return function(goal: { [string]: any })
		if not btn.Parent then
			return
		end
		if state[key] then
			state[key]:Cancel()
		end
		state[key] = TweenService:Create(target, BUTTON_TWEEN_INFO, goal)
		state[key]:Play()
	end
end

-- Light-to-dark contrast on every button's fill, requested after a Studio screenshot next to the
-- reference showed this HUD's buttons reading flat by comparison.
--
-- WHITE-TO-GREY, NOT A REAL COLOR, AND THAT IS LOAD-BEARING: a UIGradient MULTIPLIES the color of
-- whatever it's parented to (ImageColor3 on the sliceable path, BackgroundColor3 on the fallback
-- path) rather than replacing it — the same mechanism plate()'s bevel gradient above relies on.
-- Hover/press tween exactly that same property (see tweenFill in HudKit.button below) to the
-- variant's hover/press shade every time the mouse moves. Because the gradient only multiplies,
-- whatever color the tween lands on keeps shining through underneath it, so every variant AND every
-- hover/press shade of every variant gets identical relative top-to-bottom shading for free, with
-- zero coordination between this gradient and the tweens. A future edit that puts a real hue in
-- here instead of a white/grey ramp would multiply that hue into every fill color in the HUD and
-- silently break every hover/press state's color — don't.
local BUTTON_GRADIENT_TOP = Color3.new(1, 1, 1)
local BUTTON_GRADIENT_BOTTOM = Color3.new(0.72, 0.72, 0.72)

local function buttonFillGradient(): UIGradient
	return HudKit.new("UIGradient", {
		Rotation = 90, -- 0 is left-to-right; 90 turns it top-to-bottom, darkening toward the bottom
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, BUTTON_GRADIENT_TOP),
			ColorSequenceKeypoint.new(1, BUTTON_GRADIENT_BOTTOM),
		}),
	})
end

-- Builds a variant-styled TextButton with real hover/press feedback. Additive alongside makeRow's
-- inline button and any hand-rolled TextButton elsewhere — nothing existing is changed to use this.
function HudKit.button(opts: HudButtonOptions): TextButton
	local variantName = opts.variant or "secondary"
	local variant = BUTTON_VARIANTS[variantName] or BUTTON_VARIANTS.secondary

	local restColor = opts.fill or variant.fill
	local hoverColor = HudKit.lighten(restColor, BUTTON_HOVER_LIGHTEN)
	local pressColor = HudKit.darken(restColor, BUTTON_PRESS_DARKEN)

	local restPos = opts.position or UDim2.new()
	local pressPos = UDim2.new(restPos.X.Scale, restPos.X.Offset, restPos.Y.Scale, restPos.Y.Offset + 2)

	local restSize = opts.size or UDim2.new(0, 120, 0, 36)
	-- Primary is the one loud action on screen, so it's the only variant that also grows on hover;
	-- secondary/danger only reshade, which keeps a whole row of secondary buttons from jittering.
	local hoverSize = if variantName == "primary"
		then UDim2.new(restSize.X.Scale, restSize.X.Offset + 4, restSize.Y.Scale, restSize.Y.Offset + 2)
		else restSize

	-- Same 9-slice plate() panels use, so buttons carry the mockup's angular cut-steel corners
	-- instead of HudKit.corner()'s rounded ones. Guarded by BUTTON_MIN_SLICE_SIZE (see its comment
	-- above) so a button smaller than that degrades to the rounded fallback instead of rendering
	-- with overlapping/broken corners -- panelHeader's close button was the concrete case this
	-- existed for until it grew to 40px specifically to clear this floor. Read fresh per call,
	-- same reasoning as plate()'s panelFrameImage local: the two must never disagree about which
	-- path they took. Goes through axisClears (see its header comment above), NOT a bare
	-- restSize.*.Offset compare -- an Offset-only check reads 0 for a Scale-sized axis (the
	-- inventory category tabs are UDim2.new(0, 91, 1, 0): height is pure Scale) and silently
	-- fails every such button onto the rounded fallback regardless of its real rendered size.
	local panelFrameImage = UiIconConfig.Get("panelframe")
	-- `square` opts out of the angular frame entirely (see the option's comment on the type above).
	-- Checked FIRST so the size floor below can never quietly route a square button somewhere else.
	local isSliceable = not opts.square
		and panelFrameImage ~= nil
		and axisClears(restSize.X, BUTTON_MIN_SLICE_SIZE)
		and axisClears(restSize.Y, BUTTON_MIN_SLICE_SIZE)

	-- A drop shadow needs a real background CHILD to hide behind — see the shadow block below for
	-- why it can never just be a lower-ZIndex sibling of `btn` itself. So `dropShadow` pushes even an
	-- otherwise-plain (non-sliceable) button onto the "fill lives on a child, not on `btn` directly"
	-- path that used to be exclusive to isSliceable; below the slice-size floor that child is a plain
	-- UICorner'd Frame instead of the angular ImageLabel, but either way `btn` itself goes fully
	-- transparent and the real fill moves onto `backgroundLabel`.
	-- ALWAYS true now, not just for sliced/shadowed buttons. The outline layer below has to sit
	-- BEHIND the button's visible fill, and under ZIndexBehavior.Sibling a child is unconditionally
	-- drawn in front of its parent — so an outline child of `btn` would cover `btn`'s own background
	-- rather than peek out around it. Moving the fill onto a child too makes the outline and the fill
	-- siblings, which is the only arrangement ZIndex can actually order.
	local needsBackgroundChild = true

	-- Resolved BEFORE `btn` exists (see resolveIconImage's header comment for why applyIcon itself
	-- can't answer this yet): whether the caption actually shown is a real `text`, an
	-- `iconFallbackText` standing in for a missing icon, or nothing at all (icon resolved, no real
	-- text supplied). `hasRealText` also drives the icon's own left-vs-centred layout further down —
	-- iconFallbackText never counts as "real text" there, because by the time it's the thing being
	-- shown the icon has already failed to resolve and isn't on screen to share the button with.
	local hasRealText = opts.text ~= nil and opts.text ~= ""
	local iconImage: string? = if opts.icon then (resolveIconImage(opts.icon, opts.iconFolder)) else nil
	local iconResolved = iconImage ~= nil
	local resolvedText = if hasRealText then opts.text
		elseif opts.icon and not iconResolved and opts.iconFallbackText then opts.iconFallbackText
		else opts.text or ""

	local btn = HudKit.new("TextButton", {
		-- Only actually visible when there's no background child (see needsBackgroundChild above);
		-- every other path hides this via BackgroundTransparency and paints the fill on the
		-- background child's own color property instead. Set unconditionally anyway, same "only one
		-- path shows it" convention plate() already uses for its own BackgroundColor3/ImageColor3
		-- split.
		BackgroundColor3 = restColor,
		BackgroundTransparency = if needsBackgroundChild then 1 else 0,
		Position = restPos,
		AnchorPoint = opts.anchorPoint or Vector2.new(0, 0),
		Size = restSize,
		LayoutOrder = opts.layoutOrder or 0,
		AutoButtonColor = false, -- we drive every visual state ourselves via TweenService below
		Font = HudKit.FONT.BodyBold,
		TextColor3 = variant.text,
		TextSize = HudKit.TEXTSIZE.Body,
		Text = resolvedText,
		Parent = opts.parent,
	}, if needsBackgroundChild then {} elseif opts.square then { buttonFillGradient() } else { HudKit.corner(HudKit.RADIUS.Button), buttonFillGradient() })
	-- No UICorner AND no gradient here when there's a background child: the shape/shading move onto
	-- that child instead (angular cut corners for the sliceable image, plain corner() for the
	-- plain-Frame fallback below) — same reasoning as plate()'s shell/surface branch. A dropShadow
	-- button additionally skips the gradient ON THAT CHILD TOO (see the background-child block
	-- below): the gradient and the hard shadow are ALTERNATIVE treatments in the design reference,
	-- never both at once, since stacking them is what makes a button look muddy. See
	-- buttonFillGradient above for why it's built fresh per call rather than one shared UIGradient.

	-- The angular (or, dropShadow-on-a-too-small-to-slice button, plain-rounded) background: a child
	-- filling the button, sized/positioned to track it automatically (1,0,1,0 relative to `btn`, so
	-- no separate Size/Position tween is ever needed for it — only its fill color changes on
	-- hover/press, via tweenFill below).
	--
	-- ZIndex = 0 keeps it below the icon and caption (siblings, ZIndex 1 and 2 respectively — see
	-- below) and ABOVE the drop shadow (ZIndex -1, built just below when requested): all three are
	-- ordinary sibling children of `btn` and DO get ordered by ZIndex against each other.
	--
	-- THIS WAS PREVIOUSLY DOCUMENTED BACKWARDS, AND THAT IS WHAT SHIPPED THE BUG: the comment here
	-- used to claim "a TextButton's native Text always paints on top of every child regardless of
	-- ZIndex," which is false. This ScreenGui runs ZIndexBehavior.Sibling (see HudKit.screenGui
	-- above), under which a GuiObject's CHILDREN are UNCONDITIONALLY drawn in front of their parent —
	-- ZIndex only orders siblings against each other, it never lets a parent's own rendering (which is
	-- all `btn`'s native Text ever was) win against a child. So an opaque, full-covering background
	-- child does swallow the button's native Text, every time, with no ZIndex able to fix it. Icon-only
	-- buttons looked fine only because the icon is ALSO a child and simply never had to compete with
	-- the background for the same pixels the text needed.
	--
	-- The fix is captionLabel below: a child TextLabel that mirrors `btn`'s Text, which — being a
	-- sibling of the background, not the parent's own rendering — CAN be given a higher ZIndex and
	-- actually win.
	local backgroundLabel: GuiObject? = nil
	local captionLabel: TextLabel? = nil
	local shadowTarget: GuiObject? = nil
	local shadowProperty: string? = nil
	local outlineTarget: GuiObject? = nil
	local outlineProperty: string? = nil

	if opts.dropShadow then
		-- Built BEFORE backgroundLabel so it's visually behind it (ZIndex -1 vs 0) once both exist.
		-- This MUST be a sibling of backgroundLabel (both children of `btn`), not a sibling of `btn`
		-- itself: `btn` is fully transparent whenever a background child exists (needsBackgroundChild
		-- above), so there is no visible layer on `btn` left to hide behind — the actual visible face
		-- is backgroundLabel, and ZIndex only orders SIBLINGS against each other, never a parent
		-- against its own children (see the long ZIndex note above). Same size as the background,
		-- offset down BUTTON_DROPSHADOW_OFFSET px, filled with a darkened copy of restColor — the
		-- hard `0 2px 0 <darker>` shape from the design reference, not a blur.
		local shadowColor = HudKit.darken(restColor, BUTTON_DROPSHADOW_DARKEN)
		if isSliceable then
			local shadow = HudKit.new("ImageLabel", {
				BackgroundTransparency = 1,
				Image = panelFrameImage,
				ImageColor3 = shadowColor,
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = PANEL_FRAME_SLICE_CENTER,
				Size = UDim2.new(1, 0, 1, 0),
				Position = UDim2.new(0, 0, 0, BUTTON_DROPSHADOW_OFFSET),
				ZIndex = 0,
				Parent = btn,
			})
			shadowTarget, shadowProperty = shadow, "ImageColor3"
		else
			local shadow = HudKit.new("Frame", {
				BackgroundColor3 = shadowColor,
				Size = UDim2.new(1, 0, 1, 0),
				Position = UDim2.new(0, 0, 0, BUTTON_DROPSHADOW_OFFSET),
				ZIndex = 0,
				Parent = btn,
			}, if opts.square then {} else { HudKit.corner(HudKit.RADIUS.Button) })
			shadowTarget, shadowProperty = shadow, "BackgroundColor3"
		end
	end

	-- THE OUTLINE — built exactly the way plate() builds its bevel, because that one demonstrably
	-- works (it is why the status panel reads with a rim and the buttons did not).
	--
	-- The rim is NOT a stroke and NOT an oversized layer reaching outside the button. It is a
	-- full-size shape whose FILL sits INSET inside it, so the outline shows around the fill's edge.
	-- Everything stays inside the button's own bounds.
	--
	-- Crucially the fill is a CHILD of the outline, not a sibling: under ZIndexBehavior.Sibling a
	-- child is unconditionally drawn in front of its parent, so nesting GUARANTEES the order with no
	-- ZIndex involved at all. Three previous attempts leaned on ZIndex (including negative values)
	-- to put a layer behind another and none of them ever appeared on screen. Nesting cannot fail
	-- the same way. Do not "flatten" these back into siblings.
	-- THE OUTLINE — the same construction plate() uses for its bevel, which is what finally made a
	-- rim appear on buttons after a UIStroke and three ZIndex-layered attempts all produced nothing.
	--
	-- It is a full-size shape filling the button, with the FILL nested INSIDE it and inset by
	-- BUTTON_OUTLINE_EXPAND, so the outline shows as a rim around the fill's edge. Nothing reaches
	-- outside the button's own bounds.
	--
	-- The fill being a CHILD of the outline rather than a sibling is load-bearing: under
	-- ZIndexBehavior.Sibling a child is unconditionally drawn in front of its parent, so nesting
	-- guarantees the order structurally with no ZIndex involved. Every earlier attempt tried to put
	-- one sibling behind another via ZIndex and none of them ever rendered. Do not flatten these.
	--
	-- On the sliced path the rim is the same panelframe image, so it follows the 45-degree cut
	-- corners exactly instead of boxing a rectangle around them — the thing a UIStroke could not do.
	-- It carries the same gradient as the fill so the rim shades with the button rather than reading
	-- as a flat sticker behind a shaded face.
	local outlineHost: GuiObject
	do
		local outlineColor = HudKit.lighten(restColor, BUTTON_OUTLINE_LIGHTEN)
		if isSliceable then
			local outline = HudKit.new("ImageLabel", {
				BackgroundTransparency = 1,
				Image = panelFrameImage,
				ImageColor3 = outlineColor,
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = PANEL_FRAME_SLICE_CENTER,
				Size = UDim2.new(1, 0, 1, 0),
				Parent = btn,
			}, { buttonFillGradient() })
			outlineTarget, outlineProperty = outline, "ImageColor3"
			outlineHost = outline
		else
			-- Square and rounded-fallback buttons, same idea in plain Frame form. The rounded case bumps
			-- its radius by the rim width so the rim stays an even thickness around the curve rather
			-- than pinching at the corners.
			local outline = HudKit.new("Frame", {
				BackgroundColor3 = outlineColor,
				Size = UDim2.new(1, 0, 1, 0),
				Parent = btn,
			}, if opts.square
				then { buttonFillGradient() }
				else { HudKit.corner(HudKit.RADIUS.Button + BUTTON_OUTLINE_EXPAND), buttonFillGradient() })
			outlineTarget, outlineProperty = outline, "BackgroundColor3"
			outlineHost = outline
		end
	end

	if needsBackgroundChild then
		if isSliceable then
			backgroundLabel = HudKit.new("ImageLabel", {
				BackgroundTransparency = 1,
				Image = panelFrameImage,
				ImageColor3 = restColor,
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = PANEL_FRAME_SLICE_CENTER,
				-- Inset inside outlineHost, which is what leaves its rim showing. Parented to the
				-- outline, not to `btn` — see the outline block above for why nesting rather than ZIndex.
				Size = UDim2.new(1, -BUTTON_OUTLINE_EXPAND * 2, 1, -BUTTON_OUTLINE_EXPAND * 2),
				Position = UDim2.fromOffset(BUTTON_OUTLINE_EXPAND, BUTTON_OUTLINE_EXPAND),
				Parent = outlineHost,
			}, if opts.dropShadow then {} else { buttonFillGradient() })
		else
			-- Plain-fallback shape, just moved onto a child (instead of `btn` itself) so the drop
			-- shadow above has a background face to sit behind; a too-small-to-slice button (the
			-- close button before it grew to 40px was the concrete case) never used to reach this
			-- branch at all before dropShadow existed.
			backgroundLabel = HudKit.new("Frame", {
				BackgroundColor3 = restColor,
				-- Inset inside outlineHost; see the outline block above.
				Size = UDim2.new(1, -BUTTON_OUTLINE_EXPAND * 2, 1, -BUTTON_OUTLINE_EXPAND * 2),
				Position = UDim2.fromOffset(BUTTON_OUTLINE_EXPAND, BUTTON_OUTLINE_EXPAND),
				Parent = outlineHost,
			}, if opts.square then {} else { HudKit.corner(HudKit.RADIUS.Button) })
		end

		-- `btn`'s native Text is now invisible (TextTransparency = 1) rather than removed: callers
		-- across this HUD assign `button.Text = ...` / `button.TextColor3 = ...` directly as an
		-- ongoing pattern (equip/deploy toggles, the detail panel's action button, ...), and that must
		-- keep working with zero call-site changes. captionLabel is the thing actually seen; it starts
		-- as a copy of btn's current Text/Font/TextColor3/TextSize and is kept in sync for the two
		-- properties callers actually mutate afterward (Text, TextColor3) via the signals below. It is
		-- sized to fill `btn` with Scale, so the same UIPadding instance that insets `btn`'s own native
		-- text away from an icon (added further down, when both icon and text are present) insets this
		-- label identically — UIPadding affects every direct Scale-sized child, not just the one
		-- text a caller happens to be picturing.
		btn.TextTransparency = 1
		captionLabel = HudKit.new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Font = btn.Font,
			TextColor3 = btn.TextColor3,
			TextSize = btn.TextSize,
			Text = btn.Text,
			ZIndex = 4,
			Parent = btn,
		})
		btn:GetPropertyChangedSignal("Text"):Connect(function()
			(captionLabel :: TextLabel).Text = btn.Text
		end)
		btn:GetPropertyChangedSignal("TextColor3"):Connect(function()
			(captionLabel :: TextLabel).TextColor3 = btn.TextColor3
		end)
	end

	-- Whichever instance/property actually carries the visible fill: the background ImageLabel's
	-- ImageColor3 when sliced, or BackgroundColor3 everywhere else — the plain-fallback background
	-- child (dropShadow on a too-small-to-slice button) and `btn` itself (no background child at all)
	-- both happen to use that same property name, so isSliceable alone decides it. Every
	-- hover/press/setButtonFill call goes through this pair instead of hardcoding BackgroundColor3,
	-- which is the fix for the "sliced buttons never recolor" regression a naive port of the old
	-- tweens would have shipped silently.
	local fillTarget: Instance = backgroundLabel or btn
	local fillProperty = if isSliceable then "ImageColor3" else "BackgroundColor3"


	-- Icon is optional and additive: a missing key must fall back to the text label alone, never an
	-- empty square, per this project's "missing art never breaks the loop" rule. `iconLabel` and the
	-- two image strings are locals closed over by the hover handlers further down, not stored in
	-- `state` (unlike the colors) — nothing outside this function ever needs to recolor an icon the
	-- way setButtonFill recolors a fill, so there's no case for exposing them the same way.
	local iconLabel: ImageLabel? = nil
	local iconRestImage: string? = nil
	local iconHoverImage: string? = nil
	if opts.icon then
		-- hasRealText, not "is there any caption at all": iconFallbackText only ever shows once this
		-- icon has already failed to resolve (see resolvedText above), at which point this whole
		-- ImageLabel gets destroyed a few lines down and its layout never mattered anyway. Using it
		-- here would wrongly leave a RESOLVED icon pinned left-of-centre, reserving dead space for a
		-- fallback caption that isn't being shown.
		local iconScale = opts.iconScale or BUTTON_ICON_SCALE_DEFAULT
		local label = HudKit.new("ImageLabel", {
			BackgroundTransparency = 1,
			-- Icon+text: pinned to the left edge, text alone (below) padded clear of it so the two
			-- don't overlap in the middle. Icon-only (including the icon-resolved/fallback-text-moot
			-- case): centred, since there's no real text to share the button with.
			AnchorPoint = if hasRealText then Vector2.new(0, 0.5) else Vector2.new(0.5, 0.5),
			Position = if hasRealText then UDim2.new(0, BUTTON_ICON_LEFT_INSET, 0.5, 0) else UDim2.new(0.5, 0, 0.5, 0),
			-- Scale of the button's height, NOT a fixed pixel size — see BUTTON_ICON_SCALE_DEFAULT
			-- above for why a fixed number made the hero button and a tiny secondary button get an
			-- identical icon. SizeConstraint.RelativeYY ties BOTH the X and Y scale components to the
			-- parent's (the button's) AbsoluteSize.Y specifically, which is what keeps the icon square
			-- on a wide-but-short button — fromScale alone resolves X against AbsoluteSize.X, so a
			-- 108x72 button would stretch it into an oblong. Do not "simplify" this back to a bare
			-- fromScale; that silently distorts every non-square button's icon.
			Size = UDim2.fromScale(iconScale, iconScale),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			-- Explicit, not relying on the instance default (which happens to also be 1): must stay
			-- above the background ImageLabel's ZIndex = 0 above, since those two ARE ordinary
			-- sibling children and DO get ordered by ZIndex against each other.
			ZIndex = 3,
			Parent = btn,
		})
		if HudKit.applyIcon(label, opts.icon, opts.iconFolder) then
			iconLabel = label
			iconRestImage = label.Image
			-- Hover art is optional per icon (see UiIconConfig's header comment on the `_hover`
			-- naming convention) — a missing entry just leaves this nil, and swapIcon() below treats
			-- nil as "leave it alone" rather than disabling anything.
			iconHoverImage = UiIconConfig.Get(opts.icon .. "_hover")
			if hasRealText then
				-- The caption needs pushing clear of the icon; PaddingLeft reserves the icon's ACTUAL
				-- footprint (inset + icon pixels + one XS gap), not the old fixed 20px, so a bigger
				-- icon doesn't crowd the text and a smaller one doesn't strand it with dead space.
				-- restSize.Y.Offset is the same offset-based-height assumption pressPos/hoverSize
				-- above already make about how this function's callers size their buttons, so this
				-- pixel math and the icon's live RelativeYY size agree.
				--
				-- One UIPadding, parented to `btn`, covers BOTH renderings of the caption: `btn`'s own
				-- native Text (invisible on the sliceable path, but still the visible one on the
				-- fallback path) AND captionLabel (a Scale-sized direct child on the sliceable path).
				-- UIPadding insets a GuiObject's own text bounds as well as every direct child sized
				-- with Scale, not just children under a UIListLayout, so both stay in sync without
				-- needing two separate padding instances.
				local iconPixels = restSize.Y.Offset * iconScale
				HudKit.new("UIPadding", {
					PaddingLeft = UDim.new(0, BUTTON_ICON_LEFT_INSET + iconPixels + HudKit.SPACE.XS),
					Parent = btn,
				})
			end
		else
			label:Destroy() -- missing art -> fall back to the text label alone, never an empty square
		end
	end

	-- Colors live in `state`, not as closed-over locals, so HudKit.setButtonFill can rewrite them
	-- later and have every handler below see the new values on the very next hover/press -- this
	-- table IS the fix for the button-recolors-then-reverts-on-MouseLeave bug. fillTarget/fillProperty
	-- ride along too so setButtonFill/setButtonVariant (below) can recolor a built button correctly
	-- without re-deriving which path (sliced vs. fallback) it took at build time. shadowTarget/
	-- shadowProperty are nil unless dropShadow was requested; setButtonFill checks for that before
	-- touching them, since a recolored button would otherwise carry a shadow tinted from its OLD fill.
	local state = {
		restColor = restColor,
		hoverColor = hoverColor,
		pressColor = pressColor,
		fillTarget = fillTarget,
		fillProperty = fillProperty,
		shadowTarget = shadowTarget,
		shadowProperty = shadowProperty,
		-- Derived from restColor like the fill and the shadow, so a recolour must re-derive these too
		-- or the button keeps an edge from its previous colour.
		outlineTarget = outlineTarget,
		outlineProperty = outlineProperty,
	}
	buttonState[btn] = state

	-- Two tweeners, not one: `tween` drives `btn`'s own Size/Position, `tweenFill` drives whichever
	-- instance/property carries the visible fill (see fillTarget/fillProperty above). See
	-- makeTweener's header comment for why these need separate state slots rather than sharing one.
	local tween = makeTweener(btn, btn, state, "activeTween")
	local tweenFill = makeTweener(btn, fillTarget, state, "activeFillTween")

	-- Same destroyed-instance guard as makeTweener above, and for the same reason: panels rebuild
	-- constantly, so a MouseLeave can fire after `btn` (and `iconLabel`, parented under it) is
	-- already torn down. `image == nil` also no-ops here, which is what makes a missing `_hover`
	-- entry "silently keep the rest icon" rather than something every caller has to check for.
	local function swapIcon(image: string?)
		if not image or not btn.Parent or not iconLabel then
			return
		end
		iconLabel.Image = image
	end

	-- Size/Position (via `tween`, on `btn`) and the visible fill color (via `tweenFill`, on
	-- fillTarget/fillProperty) are now two separate TweenService:Create calls instead of one combined
	-- goal table -- both fired with the same BUTTON_TWEEN_INFO, so they start and ease together and
	-- look identical to one tween. They MUST stay separate: on the fallback path they'd target the
	-- same instance but still need independent cancel-tracking (see makeTweener's header comment),
	-- and on the sliceable path they target different instances entirely.
	btn.MouseEnter:Connect(function()
		tween({ Size = hoverSize })
		tweenFill({ [fillProperty] = state.hoverColor })
		swapIcon(iconHoverImage)
	end)
	btn.MouseLeave:Connect(function()
		tween({ Size = restSize, Position = restPos })
		tweenFill({ [fillProperty] = state.restColor })
		swapIcon(iconRestImage)
	end)
	btn.MouseButton1Down:Connect(function()
		tween({ Position = pressPos })
		tweenFill({ [fillProperty] = state.pressColor })
	end)
	btn.MouseButton1Up:Connect(function()
		tween({ Position = restPos, Size = hoverSize })
		tweenFill({ [fillProperty] = state.hoverColor })
	end)

	if opts.onClick then
		btn.MouseButton1Click:Connect(opts.onClick)
	end

	return btn
end

-- Changes a built button's REST color in place, with hover/press re-derived from it the same way
-- HudKit.button() derives them at build time, so all three stay consistent.
--
-- BUG THIS FIXES: HudKit.button() used to bake rest/hover/press colors into upvalues closed over
-- by the MouseEnter/Leave/Down/Up handlers at build time. A caller that recolored a button
-- afterward to show STATE -- an "equipped" AccentDark fill, the Start/Stop Defense toggle, the
-- admin Test Mode ON/OFF button -- was only ever changing BackgroundColor3 directly, which the
-- very next MouseLeave tween would silently stomp back to the variant's original color, because
-- the handler never knew it had changed. One consumer worked around this by destroying and
-- rebuilding an entire row just to change a button's color, which is a symptom of this gap, not a
-- separate problem. This writes into the same `state` table the handlers read from every time
-- (see `buttonState` above), so there is nothing left to go stale.
--
-- Also cancels any in-flight fill tween before applying the new rest color directly: without this, a
-- MouseLeave tween already mid-flight (queued before this call, animating toward the OLD rest
-- color it captured when it started) would finish and visually overwrite the color this function
-- just set, a moment later and for no visible reason. Only the FILL tween slot is cancelled, not
-- the Size/Position one (`state.activeTween`) -- those two were split into independent slots
-- specifically so a color change like this one no longer has to interrupt an in-flight hover-grow
-- animation just to touch a color it doesn't own.
--
-- RETARGETED for the 9-slice background: the visible fill used to always be `button.BackgroundColor3`
-- directly; a sliceable button's fill is its background ImageLabel's ImageColor3 instead (that
-- Frame's own BackgroundColor3 is transparent on that path and would silently do nothing). state.
-- fillTarget/fillProperty were captured once at HudKit.button() build time so this function doesn't
-- need to re-derive which path a given button took.
-- ALSO RE-DERIVES THE DROP SHADOW: state.shadowTarget is only set when the button was built with
-- dropShadow = true (see HudKit.button above); a recolored button that skips this would keep
-- shining its OLD fill's shadow underneath its NEW fill forever, since nothing else ever touches it
-- after build time.
function HudKit.setButtonFill(button: TextButton, color: Color3)
	local state = buttonState[button]
	if not state then
		return -- not a HudKit.button()-built button (or already GC'd); nothing to update
	end
	state.restColor = color
	state.hoverColor = HudKit.lighten(color, BUTTON_HOVER_LIGHTEN)
	state.pressColor = HudKit.darken(color, BUTTON_PRESS_DARKEN)
	if state.activeFillTween then
		state.activeFillTween:Cancel()
		state.activeFillTween = nil
	end
	if button.Parent then -- same destroyed-instance guard as makeTweener; a destroyed button can't be recolored
		(state.fillTarget :: any)[state.fillProperty] = state.restColor
		if state.shadowTarget then
			(state.shadowTarget :: any)[state.shadowProperty] = HudKit.darken(color, BUTTON_DROPSHADOW_DARKEN)
		end
		if state.outlineTarget then
			(state.outlineTarget :: any)[state.outlineProperty] = HudKit.lighten(color, BUTTON_OUTLINE_LIGHTEN)
		end
	end
end

-- Named-variant version of HudKit.setButtonFill, for the "honest state flip" case (secondary ->
-- danger to arm a confirm-delete, say) rather than an arbitrary computed color. Also swaps the
-- text color to match the variant, since primary's dark-on-Accent text would otherwise look wrong
-- painted onto a danger/secondary fill.
function HudKit.setButtonVariant(button: TextButton, variantName: string)
	local variant = BUTTON_VARIANTS[variantName] or BUTTON_VARIANTS.secondary
	if button.Parent then
		button.TextColor3 = variant.text
	end
	HudKit.setButtonFill(button, variant.fill)
end

----------------------------------------------------------------------
-- Forged Rig: bevelled steel plate panel shell
----------------------------------------------------------------------
-- A chosen design direction: panels read as bevelled steel plate rather than flat fills. The
-- mockup does this in CSS as an outer shell with a top-to-bottom gradient (light edge at top,
-- near-black at the bottom) with the real content surface inset 2px inside it — the gradient
-- sliver that peeks out around the surface reads as a lit bevel. One function builds both pieces
-- so every panel that adopts the look shares a single place to retune the bevel from, instead of
-- five copies of Frame+UIGradient+Frame drifting apart the way makeRow's inline button already has
-- from HudKit.button.

-- top edge: COLOR.Line lightened. Pushed up from 0.35 to 0.62 after an earlier Studio screenshot
-- showed a mid-grey bevel reading as technically-correct-but-invisible at 2-3px against a bright
-- outdoor scene. 0.62 overcorrected: lerped that far toward white, COLOR.Line's (60, 53, 47) lands
-- around (181, 178, 176) -- functionally white, not "lightened grey" -- which at PLATE_SURFACE_INSET's
-- full 3px reads as a glowing rim and washes out the whole panel edge along with COLOR.Panel's own
-- new depth (see COLOR.Panel above). 0.4 keeps the bevel legibly lighter than COLOR.Line without
-- blowing past "grey" into "white."
local PLATE_GRADIENT_LIGHTEN = 0.4
local PLATE_GRADIENT_DARKEN = 0.85 -- bottom edge: COLOR.Line darkened toward near-black
local PLATE_SURFACE_INSET = 3 -- pixels of shell visible as a border once the surface sits on top.

-- Slice geometry: PANEL_FRAME_SLICE_CENTER, defined once above the Buttons section since
-- HudKit.button() shares this exact asset/geometry for its own angular background.

-- Returns (surface, shell) in that order: surface is what a caller almost always wants right away
-- (to parent content into), shell is only needed afterward to move/resize the whole panel — hence
-- `props` (Position, Size, Parent, AnchorPoint, LayoutOrder, ZIndex, ...) is applied to the shell,
-- since that's the outer box actually being placed in the screen.
--
-- SHAPE: when UiIconConfig.Get("panelframe") resolves, both shell and surface render as that
-- 9-sliced image instead of a plain Frame, giving the mockup's angular cut-steel corners that
-- UICorner can never reproduce (Roblox has no clip-path equivalent). When it doesn't resolve — the
-- asset ID is still 0, or this repo was forked without it — both fall back to the original rounded
-- Frame + UICorner path, so a missing asset degrades to "less pretty" rather than "invisible HUD",
-- per this project's "missing art never breaks the loop" rule.
function HudKit.plate(props: { [string]: any }?): (Frame, Frame)
	-- Read once per call, not once per shell/surface build below: the pair must always agree on
	-- which path they're taking, and re-reading twice only invites them drifting apart if this
	-- value ever became read-write instead of a static config lookup.
	local panelFrameImage = UiIconConfig.Get("panelframe")

	local shellProps: { [string]: any } = {
		BackgroundColor3 = Color3.new(1, 1, 1), -- overpainted by the UIGradient below; this fill is
			-- never actually seen, but a Frame with Transparency and a UIGradient renders nothing.
			-- Only read on the fallback path — the slice path below sets BackgroundTransparency = 1
			-- and tints ImageColor3 instead, so this key just goes unused rather than being fought
			-- over between the two branches.
	}
	for key, value in pairs(props or {}) do
		shellProps[key] = value
	end

	-- Opt-in growth-to-content. The surface's normal Size (`1, -4, 1, -4`) is scale-relative to the
	-- shell, so a shell that AutomaticSizes to its content while its content sizes itself relative
	-- to the shell is circular — AutomaticSize silently no-ops, which is exactly what happened to
	-- the currency readout and status panel when they moved to plate(): they'd used
	-- AutomaticSize.Y before, lost it here, and got hardcoded pixel heights instead. That's a
	-- silent-clip bug waiting for the next currency row or status line, with no error to find it by.
	-- `automaticSize = true` breaks the circularity: the surface gets an offset-only height (grows
	-- to its own children, independent of the shell's size) and the shell then AutomaticSizes to
	-- the surface — a direction that genuinely works, since the shell no longer depends on itself.
	-- Popped out of shellProps rather than left in it: `HudKit.new` does `inst[key] = value` for
	-- every entry, and "automaticSize" is not a real Instance property, so leaving it in would
	-- throw the moment the shell instance is constructed below.
	local automaticSize = shellProps.automaticSize
	shellProps.automaticSize = nil

	-- The bevel gradient is identical either way: UIGradient recolors whichever of
	-- BackgroundColor3/ImageColor3 is actually visible on the GuiObject it's parented to, so parking
	-- it on a Frame or an ImageLabel needs no branching of its own.
	local gradient = HudKit.new("UIGradient", {
		Rotation = 90, -- 0 is left-to-right; 90 turns the same left->right stops top-to-bottom
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, HudKit.lighten(COLOR.Line, PLATE_GRADIENT_LIGHTEN)),
			ColorSequenceKeypoint.new(1, HudKit.darken(COLOR.Line, PLATE_GRADIENT_DARKEN)),
		}),
	})

	local shell
	if panelFrameImage then
		shellProps.BackgroundTransparency = 1
		shellProps.Image = panelFrameImage
		shellProps.ImageColor3 = Color3.new(1, 1, 1) -- overpainted by the gradient, same convention
			-- as the fallback's BackgroundColor3 above
		shellProps.ScaleType = Enum.ScaleType.Slice
		shellProps.SliceCenter = PANEL_FRAME_SLICE_CENTER
		-- No UICorner here: the shape now comes from the image's own cut corners, and rounding on
		-- top of a sliced image would just clip the cut back into a plain rounded rect.
		shell = HudKit.new("ImageLabel", shellProps, { gradient })
	else
		shell = HudKit.new("Frame", shellProps, { HudKit.corner(HudKit.RADIUS.Panel), gradient })
	end

	-- `automaticSize` accepts `true` (height only, the original behaviour and still what most panels
	-- want) or an Enum.AutomaticSize for the axes to automate. X exists because a fixed-width panel
	-- whose contents are laid out horizontally silently OVERFLOWS rather than clipping: the wallet
	-- strip's last group rendered outside the plate, on top of the game world, with nothing in
	-- Output to say so. A row of content should size to its content.
	local autoAxis = if automaticSize == true
		then Enum.AutomaticSize.Y
		elseif automaticSize then automaticSize
		else nil
	local autoX = autoAxis == Enum.AutomaticSize.X or autoAxis == Enum.AutomaticSize.XY
	local autoY = autoAxis == Enum.AutomaticSize.Y or autoAxis == Enum.AutomaticSize.XY

	if autoAxis then
		-- Base size on an automated axis is just the two insets (the bevel on both edges), so the
		-- surface growing to its content overflows evenly rather than the shell starting undersized.
		-- An axis left manual keeps exactly what the caller set via props.Size.
		local inset = PLATE_SURFACE_INSET * 2
		shell.Size = UDim2.new(
			if autoX then 0 else shell.Size.X.Scale,
			if autoX then inset else shell.Size.X.Offset,
			if autoY then 0 else shell.Size.Y.Scale,
			if autoY then inset else shell.Size.Y.Offset
		)
		shell.AutomaticSize = autoAxis
	end

	local surfaceProps: { [string]: any } = {
		Position = UDim2.fromOffset(PLATE_SURFACE_INSET, PLATE_SURFACE_INSET),
		-- Non-auto: unchanged, scale-relative to the shell. Auto: offset-only base (no scale
		-- component means no dependency on the shell's still-being-computed height) plus
		-- AutomaticSize.Y so it grows to whatever's parented into it.
		-- An automated axis gets an offset-only base (no scale component, so it carries no dependency
		-- on the shell's still-being-computed size — that circularity is what silently collapses a
		-- nested AutomaticSize). A manual axis stays scale-relative to the shell exactly as before.
		Size = UDim2.new(
			if autoX then 0 else 1,
			if autoX then 0 else -PLATE_SURFACE_INSET * 2,
			if autoY then 0 else 1,
			if autoY then 0 else -PLATE_SURFACE_INSET * 2
		),
		AutomaticSize = autoAxis,
		Parent = shell,
	}

	local surface
	if panelFrameImage then
		surfaceProps.BackgroundTransparency = 1
		surfaceProps.Image = panelFrameImage
		surfaceProps.ImageColor3 = COLOR.Panel
		surfaceProps.ScaleType = Enum.ScaleType.Slice
		surfaceProps.SliceCenter = PANEL_FRAME_SLICE_CENTER
		surface = HudKit.new("ImageLabel", surfaceProps) -- no UICorner; see the shell branch above
	else
		surfaceProps.BackgroundColor3 = COLOR.Panel
		-- slightly smaller radius than the shell's, concentric with it, so the visible bevel reads
		-- as an even-width border all the way around rather than looking mitred at the corners
		surface = HudKit.new("Frame", surfaceProps, { HudKit.corner(math.max(HudKit.RADIUS.Panel - PLATE_SURFACE_INSET, 0)) })
	end

	return surface, shell
end

-- The 4px accent bar across the top of a panel. Returns it so a caller can recolor a specific
-- panel later (a raid warning panel accenting Bad instead of Accent, say) without this function
-- needing a per-panel-type color lookup of its own.
--
-- BUG THIS FIXES: a plain full-width `UDim2.new(1, 0, 0, 4)` bar runs straight past the top-right
-- corner's 45-degree cut on a sliced `surface` (panelframe's square corner is top-LEFT only — see
-- PANEL_FRAME_SLICE_CENTER's header comment) and juts out over the diagonal, clearly visible on
-- the wallet strip. Inset the right edge by PANEL_FRAME_CORNER_CUT so the bar stops exactly where
-- the cut begins instead of overrunning it; the left edge stays flush at x=0 since that corner is
-- square and has nothing to clear.
--
-- GATED on the same panelframe availability every other slice-aware path in this file checks:
-- on the rounded fallback (no panelframe asset) `surface` has no diagonal to clear at all, so an
-- inset there would just read as an unexplained gap on the right, not a fix.
function HudKit.accentCap(surface: Frame, color: Color3?): Frame
	local panelFrameImage = UiIconConfig.Get("panelframe")
	return HudKit.new("Frame", {
		BackgroundColor3 = color or COLOR.Accent,
		BorderSizePixel = 0,
		Size = if panelFrameImage
			then UDim2.new(1, -PANEL_FRAME_CORNER_CUT, 0, 4)
			else UDim2.new(1, 0, 0, 4),
		Parent = surface,
	})
end

-- Left at 48, deliberately, even though the close button below grew to 40: (48 - 40) / 2 = 4px of
-- top/bottom clearance, which is exactly HudKit.SPACE.XS — a real token in this design system, not
-- an eyeballed cramped number. Growing this further was considered (see the close button's own
-- comment below) but INVENTORY/SHOP/TURRET/RESEARCH panels each hardcode "48" for where their body
-- content starts beneath the header (see their own PANEL_HEADER_HEIGHT-referencing comments) — those
-- four files are out of scope here, so bumping this constant would silently reopen a 1:1 overlap gap
-- in every one of them for no visual gain this file's owner can verify.
local PANEL_HEADER_HEIGHT = 48
local PANEL_HEADER_DARKEN = 0.4 -- one shade darker than the surface, so the header reads as chrome
local PANEL_HEADER_TICK_WIDTH = 4
local PANEL_HEADER_BORDER = 2
-- Grown from 28 to 40 so the close button clears BUTTON_MIN_SLICE_SIZE and gets the same angular
-- 9-sliced frame as every other button, instead of being the one HUD control still using the plain
-- rounded HudKit.corner() fallback. See PANEL_HEADER_HEIGHT above for why the header itself stayed
-- at 48 rather than growing to match.
local PANEL_HEADER_CLOSE_SIZE = 40

-- The heavy panel header from the design: a darkened bar with an accent tick on the left, the
-- title, and — only when the caller actually wants one — a close button on the right. `onClose`
-- being optional matters: some panels in this HUD are permanently docked (no way to dismiss them),
-- and forcing every caller to pass a no-op would just move the "is this closable" decision into a
-- worse place than an `if onClose then`.
function HudKit.panelHeader(surface: Frame, title: string, onClose: (() -> ())?): Frame
	local closeReserve = if onClose then PANEL_HEADER_CLOSE_SIZE + HudKit.SPACE.S else 0

	local header = HudKit.new("Frame", {
		BackgroundColor3 = HudKit.darken(COLOR.Panel, PANEL_HEADER_DARKEN),
		Size = UDim2.new(1, 0, 0, PANEL_HEADER_HEIGHT),
		Parent = surface,
	}, {
		-- Bottom seam only: a UIStroke would wrap all four sides, but the design calls for a border
		-- separating the header from the body beneath it, not a boxed-in header.
		HudKit.new("Frame", {
			BackgroundColor3 = COLOR.Line,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, PANEL_HEADER_BORDER),
		}),
		HudKit.new("Frame", {
			BackgroundColor3 = COLOR.Accent,
			BorderSizePixel = 0,
			Size = UDim2.new(0, PANEL_HEADER_TICK_WIDTH, 1, 0),
		}),
		HudKit.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, PANEL_HEADER_TICK_WIDTH + HudKit.SPACE.M, 0, 0),
			Size = UDim2.new(1, -(PANEL_HEADER_TICK_WIDTH + HudKit.SPACE.M + closeReserve), 1, 0),
			Font = HudKit.FONT.Display,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = COLOR.Text,
			TextSize = HudKit.TEXTSIZE.Title,
			Text = title,
		}),
	})

	if onClose then
		-- Routed through HudKit.button rather than a bare TextButton so the close control gets the
		-- same hover/press feedback as everything else, instead of being the one dead-looking
		-- button in an otherwise responsive panel. icon = "close" is the glyph actually authored for
		-- this; iconFallbackText = "X" is what actually shows if "close" is missing from
		-- UiIconConfig/UiIcons, so a place without that art still gets a legible, clickable close
		-- control instead of a blank one.
		--
		-- BUG THIS PREVENTS: this used to pass `text = "X"` alongside `icon = "close"`. HudKit.button
		-- renders icon AND text together whenever both are supplied, so once "close" started
		-- resolving, this rendered the close glyph WITH a literal "X" beside it — reported as "two
		-- close buttons at once." `text` is for a caption meant to sit beside a resolved icon;
		-- iconFallbackText is for a caption that only exists because the icon didn't resolve. Do not
		-- swap this back to `text = "X"`.
		--
		-- fill IS EXPLICIT, not left to secondary's default: this control's one job is to read as a
		-- distinct square against the header bar (HudKit.darken(COLOR.Panel, PANEL_HEADER_DARKEN),
		-- always the darkest thing behind it), so it can't be left implicitly coupled to whatever
		-- secondary's rest color happens to be tuned to elsewhere — a future retune of that variant
		-- for unrelated buttons must not silently make this one blend back into the header again.
		HudKit.button({
			variant = "secondary",
			fill = COLOR.PanelLight,
			icon = "close",
			iconFallbackText = "X",
			-- Deliberately the one SQUARE control in a HUD where every other button carries panelframe's
			-- 45-degree cut. It reads as variety rather than as a missed migration; see `square` on
			-- HudButtonOptions. Do not "correct" this to match its neighbours.
			square = true,
			size = UDim2.new(0, PANEL_HEADER_CLOSE_SIZE, 0, PANEL_HEADER_CLOSE_SIZE),
			position = UDim2.new(1, -(PANEL_HEADER_CLOSE_SIZE + HudKit.SPACE.S), 0.5, -PANEL_HEADER_CLOSE_SIZE / 2),
			parent = header,
			onClick = onClose,
		})
	end

	return header
end

local SEGMENT_GAP = HudKit.SPACE.XS
local SEGMENT_TRACK_HEIGHT = 16
local SEGMENT_TRACK_DARKEN = 0.5
local SEGMENT_INSET = HudKit.SPACE.XS

-- The segmented integrity bar from the design: `segments` equal-width cells in a row, on a dark
-- inset track. Cell sizing uses the standard "N equal flex cells with (N-1) fixed-pixel gaps" UDim2
-- trick (Scale carries the 1/N division, Offset carries the per-cell gap correction) instead of a
-- UIListLayout — a ListLayout sizes items and gaps independently, so it either overflows the track
-- or leaves the last cell an odd width; the UDim2 math stays exact at any track width.
--
-- Returns the cells themselves rather than taking a health value, because the caller (this bar
-- today, a shield/stamina readout tomorrow) is the one that knows what "filled" means for its own
-- state and what color that should be — baking a health-shaped API in here would make it useless
-- for anything else.
function HudKit.segmentBar(parent: Instance, segments: number): { Frame }
	local track = HudKit.new("Frame", {
		BackgroundColor3 = HudKit.darken(COLOR.Panel, SEGMENT_TRACK_DARKEN),
		Size = UDim2.new(1, 0, 0, SEGMENT_TRACK_HEIGHT),
		Parent = parent,
	}, { HudKit.corner(4) })

	local inner = HudKit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(SEGMENT_INSET, SEGMENT_INSET),
		Size = UDim2.new(1, -SEGMENT_INSET * 2, 1, -SEGMENT_INSET * 2),
		Parent = track,
	})

	local cells = {}
	for i = 0, segments - 1 do
		cells[i + 1] = HudKit.new("Frame", {
			BackgroundColor3 = COLOR.Line, -- caller overwrites per-cell: filled vs. empty
			BorderSizePixel = 0,
			Position = UDim2.new(i / segments, i * SEGMENT_GAP / segments, 0, 0),
			Size = UDim2.new(1 / segments, -SEGMENT_GAP * (segments - 1) / segments, 1, 0),
			Parent = inner,
		})
	end

	return cells
end

----------------------------------------------------------------------
-- Ring gauge
----------------------------------------------------------------------
-- A circular progress arc, for the Smelting dial and (next) the Forge chamber's odds ring.
--
-- WHY SEGMENTS AND NOT A REAL ARC. Roblox has no arc primitive. The two ways to draw a true solid
-- sweep are a radial-fill image (this project has no such asset, and inventing one would put the
-- gauge behind art that does not exist yet) or the nested half-disc clipping trick, which needs
-- two ClipsDescendants layers with a rotated disc inside each and is fiddly enough that getting it
-- subtly wrong reads as a rendering bug. A ring of thin rotated Frames whose widths OVERLAP reads
-- as a continuous arc, needs no art, and cannot half-work: either the segments are there or they
-- are not.
--
-- RING_SEGMENTS is the granularity of the arc. 90 puts each step at 1.1% — fine enough that the
-- fill reads as sweeping rather than stepping, which was the specific complaint about doing this
-- with segmentBar's 20 cells.
local RING_SEGMENTS = 90
local RING_THICKNESS_DEFAULT = 10

export type HudRingOptions = {
	size: number, -- outer diameter in px
	thickness: number?,
	color: Color3?, -- filled arc; defaults to Accent
	trackColor: Color3?, -- unfilled remainder; defaults to Line
	segments: number?,
}

-- Returns `{ setProgress(alpha) }`. Build it once and drive it — do NOT rebuild the ring to change
-- its value: 90 Frames per update is exactly the kind of churn that turns a once-a-second
-- re-render into visible stutter.
function HudKit.ring(parent: Instance, opts: HudRingOptions)
	local diameter = opts.size
	local thickness = opts.thickness or RING_THICKNESS_DEFAULT
	local segments = opts.segments or RING_SEGMENTS
	local color = opts.color or COLOR.Accent
	local trackColor = opts.trackColor or COLOR.Line
	local radius = (diameter - thickness) / 2

	local holder = HudKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(diameter, diameter),
		Parent = parent,
	})

	-- +2 rather than exact: adjacent segments have to OVERLAP or the ring renders as a dotted line
	-- of hairline gaps, which is worse than either a solid ring or honest ticks.
	local segmentWidth = math.ceil((2 * math.pi * radius) / segments) + 2

	local cells = table.create(segments)
	for index = 1, segments do
		-- -90 so the arc starts at the top of the circle and sweeps clockwise, which is what every
		-- timer gauge does and therefore what a player reads without being told.
		local degrees = (index - 1) / segments * 360 - 90
		local radians = math.rad(degrees)

		cells[index] = HudKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = trackColor,
			BorderSizePixel = 0,
			Position = UDim2.new(
				0.5,
				math.cos(radians) * radius,
				0.5,
				math.sin(radians) * radius
			),
			Rotation = degrees + 90, -- tangent to the circle, so the segment lies along the arc
			Size = UDim2.fromOffset(segmentWidth, thickness),
			Parent = holder,
		})
	end

	local function setProgress(alpha: number)
		local filled = math.clamp(alpha, 0, 1) * segments
		for index, cell in ipairs(cells) do
			cell.BackgroundColor3 = index <= filled and color or trackColor
		end
	end

	setProgress(0)

	return { holder = holder, setProgress = setProgress }
end

----------------------------------------------------------------------
-- Modal — the shared popup plate
----------------------------------------------------------------------
-- HUD phase 3, section D ("Popups B — lifted slabs"): every popup is its own plate on a scrim, with
-- a shadow and an accent cap coloured by what KIND of popup it is. Built here rather than in each
-- caller for the same reason HudKit.button exists: the toast, the mod picker, the ultimate picker
-- and the case-opening flow had four separate hand-rolled treatments, and the moment one of them
-- gained a behaviour (input blocking, say) the other three silently didn't.
--
-- WHY ITS OWN ScreenGui. HudKit.screenGui and MainHud's walletGui are BOTH DisplayOrder 0, and
-- ordering between two ScreenGuis at the same DisplayOrder is not defined by tree order the way
-- sibling frames inside one GUI are. A scrim parented to either one would cover the HUD but leave
-- the other GUI's contents punched through it — the wallet strip floating on top of a dimmed screen.
-- A third ScreenGui at a higher DisplayOrder is the only arrangement that reliably covers both.
-- Created lazily so a session that never raises a popup never builds it.
local modalGui: ScreenGui? = nil

local MODAL_DISPLAY_ORDER = 10 -- above HudKit.screenGui and walletGui, both of which are 0
-- Must match the bar HudKit.accentCap actually builds (its Size's Y offset). Duplicated as a named
-- constant rather than read off the returned Frame because the content column is positioned before
-- a layout pass has run, when AbsoluteSize is still zero.
local MODAL_CAP_HEIGHT = 4
local MODAL_SCRIM_TRANSPARENCY = 0.35
local MODAL_WIDTH_DEFAULT = 320
local MODAL_RISE = 10 -- px the plate travels upward as it fades in; a lift, not a slide
local MODAL_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Cap colour per kind. `reveal` deliberately resolves to Accent rather than a gold of its own: a
-- reveal's cap is meant to be the RARITY's colour (ModConfig.Rarities[x].Color), which only the
-- caller knows, so it passes `capColor`. Accent is the coherent fallback for a caller that forgets,
-- rather than a missing colour or a new palette token invented for one popup.
local MODAL_KIND_CAP = {
	choice = COLOR.Accent,
	danger = COLOR.Bad,
	reveal = COLOR.Accent,
}

export type HudModalAction = {
	text: string,
	variant: string?, -- passed straight to HudKit.button; defaults to "secondary" there
	onClick: (() -> ())?,
	-- Actions close the modal after running, because that is what pressing a button on a modal
	-- means. `keepOpen` is for the exception — an action that mutates the modal's own contents
	-- (re-rolling a preview, toggling an option) rather than answering it.
	keepOpen: boolean?,
}

export type HudModalOptions = {
	title: string,
	body: string?,
	kind: string?, -- "choice" | "danger" | "reveal"; defaults to "choice"
	capColor: Color3?, -- overrides the kind's cap colour (see MODAL_KIND_CAP)
	width: number?,
	actions: { HudModalAction }?,
	-- Clicking the scrim dismisses. Defaults to FALSE: a modal is raised to make someone answer
	-- something, and the popups this was built for (discard an Epic roll, end an expedition for
	-- everyone) are exactly the ones where a stray click outside must not count as an answer.
	dismissOnScrim: boolean?,
	onClose: (() -> ())?,
}

-- Returns a handle: `close()` tears the modal down (safe to call twice, and safe to call from
-- inside an action's own onClick). `content` is the padded column holding the title, body and
-- action row — parent into it to add a row of your own between them, using LayoutOrder 1/2/3 as the
-- reference points. `surface` is the whole plate surface, cap included, for a caller that needs to
-- draw outside that column: the case-opening reveal animates its own contents across the full plate
-- rather than being forced through the title/body/actions shape.
function HudKit.modal(opts: HudModalOptions)
	if not modalGui then
		modalGui = HudKit.new("ScreenGui", {
			Name = "SalvageModals",
			DisplayOrder = MODAL_DISPLAY_ORDER,
			IgnoreGuiInset = true, -- the scrim has to reach the very top of the screen, under
				-- Roblox's own top bar, or a dimmed screen shows an undimmed strip along the top
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling, -- matches the other two GUIs, same
				-- reasoning: sibling sub-trees would otherwise fight over z-order in an undefined way
			Parent = LocalPlayer:WaitForChild("PlayerGui"),
		})
	end

	-- A TextButton, not a Frame: it both swallows clicks aimed at the HUD underneath (which is the
	-- whole point of a scrim) and gives dismissOnScrim somewhere to hang without a second instance.
	-- AutoButtonColor off so it never flashes lighter under the cursor — it is a backdrop, not a
	-- control, even when it happens to be clickable.
	local scrim = HudKit.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = HudKit.darken(COLOR.Panel, 0.55),
		BackgroundTransparency = 1, -- tweened to MODAL_SCRIM_TRANSPARENCY on open
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Parent = modalGui,
	})

	local surface, shell = HudKit.plate({
		Name = "Modal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, MODAL_RISE), -- tweened up to centre on open
		Size = UDim2.fromOffset(opts.width or MODAL_WIDTH_DEFAULT, 0),
		automaticSize = true, -- height follows the content; see plate()'s own comment for why this
			-- has to be opt-in rather than the default
		Parent = modalGui,
	})

	-- The cap IS the modal's kind signal, so it has to be the thing you see. Deliberately NOT paired
	-- with HudKit.panelHeader: the header is also positioned at Y=0, and under ZIndexBehavior.Sibling
	-- a tie is broken by tree order, so a header built after the cap covers it completely — an
	-- invisible cap with nothing in Output to explain it. The header would fight it on colour too
	-- (its accent tick is hardcoded COLOR.Accent, so a `danger` modal would show a red cap beside an
	-- orange tick). The design's slabs have no header bar anyway: cap, title, body, actions.
	HudKit.accentCap(surface, opts.capColor or MODAL_KIND_CAP[opts.kind or "choice"] or COLOR.Accent)

	local closed = false
	local close
	close = function()
		if closed then
			return
		end
		closed = true

		-- Tween out, then destroy. Both tweens are started before the wait so they run together
		-- rather than in sequence, and the instances are destroyed rather than hidden so a modal
		-- raised a hundred times over a session doesn't leave a hundred plates parked off-screen.
		TweenService:Create(scrim, MODAL_TWEEN, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(shell, MODAL_TWEEN, {
			Position = UDim2.new(0.5, 0, 0.5, MODAL_RISE),
		}):Play()

		task.delay(MODAL_TWEEN.Time, function()
			scrim:Destroy()
			shell:Destroy()
		end)

		if opts.onClose then
			opts.onClose()
		end
	end

	if opts.dismissOnScrim then
		scrim.Activated:Connect(close)
	end

	-- Content column, starting below the cap. Offset-only sizes throughout, deliberately: the
	-- surface is AutomaticSize'd (see plate()'s comment), and a scale-height child inside an
	-- AutomaticSize parent is the circular case that makes AutomaticSize silently no-op.
	local content = HudKit.new("Frame", {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, MODAL_CAP_HEIGHT),
		Size = UDim2.new(1, 0, 0, 0),
		Parent = surface,
	}, {
		HudKit.new("UIListLayout", {
			Padding = UDim.new(0, HudKit.SPACE.M),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		HudKit.new("UIPadding", {
			PaddingTop = UDim.new(0, HudKit.SPACE.M),
			PaddingBottom = UDim.new(0, HudKit.SPACE.M),
			PaddingLeft = UDim.new(0, HudKit.SPACE.M),
			PaddingRight = UDim.new(0, HudKit.SPACE.M),
		}),
	})

	HudKit.new("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = HudKit.FONT.Display,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 0),
		Text = opts.title,
		TextColor3 = COLOR.Text,
		TextSize = HudKit.TEXTSIZE.Title,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})

	if opts.body then
		HudKit.new("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Font = HudKit.FONT.Body,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			Text = opts.body,
			TextColor3 = COLOR.Muted,
			TextSize = HudKit.TEXTSIZE.Body,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = content,
		})
	end

	if opts.actions and #opts.actions > 0 then
		local row = HudKit.new("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, BUTTON_MIN_SLICE_SIZE),
			Parent = content,
		}, {
			HudKit.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				Padding = UDim.new(0, HudKit.SPACE.S),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
		})

		-- Even widths rather than shrink-to-text: two actions on a modal are a PAIR of answers to
		-- one question, and a wide "Collect" beside a narrow "Trash" reads as a recommendation the
		-- design isn't making. The gaps come out of the row, so N buttons still fill it exactly.
		local count = #opts.actions
		local gaps = HudKit.SPACE.S * (count - 1)

		for index, action in ipairs(opts.actions) do
			HudKit.button({
				text = action.text,
				variant = action.variant,
				layoutOrder = index,
				size = UDim2.new(1 / count, -gaps / count, 1, 0),
				parent = row,
				onClick = function()
					-- Run the caller's handler BEFORE closing: a handler that reads the modal's own
					-- contents (which button was picked, what the surface currently shows) would
					-- otherwise be reading instances this same click has already destroyed.
					if action.onClick then
						action.onClick()
					end
					if not action.keepOpen then
						close()
					end
				end,
			})
		end
	end

	TweenService:Create(scrim, MODAL_TWEEN, {
		BackgroundTransparency = MODAL_SCRIM_TRANSPARENCY,
	}):Play()
	TweenService:Create(shell, MODAL_TWEEN, { Position = UDim2.fromScale(0.5, 0.5) }):Play()

	return { close = close, surface = surface, shell = shell, content = content }
end

return HudKit
