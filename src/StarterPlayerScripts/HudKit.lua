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
	Panel = Color3.fromRGB(30, 26, 23),
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
	-- Config first, same order as getUiIcon. A configured icon carries no template instance, so
	-- there are no rect properties to copy — that only applies to the folder path, where the
	-- template is a real ImageLabel that can be pointed at a slice of a sprite atlas.
	if not folderName then
		local configured = UiIconConfig.Get(key)
		if configured then
			imageLabel.Image = configured
			return true
		end
	end

	local folder = if folderName then ReplicatedStorage:FindFirstChild(folderName) else UiIcons
	local inst, image = resolveIcon(folder, key)
	if not inst or not image then
		return false
	end
	imageLabel.Image = image
	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
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

-- The standard list row: title, subtitle, and one action button. Used by every panel, which is why
-- it lives here rather than in whichever one happened to define it first.
function HudKit.makeRow(displayName: string, subtitle: string, buttonText: string, onClick)
	local row = HudKit.new("Frame", {
		BackgroundColor3 = COLOR.PanelLight,
		Size = UDim2.new(1, 0, 0, 52),
	}, { HudKit.corner(6) })

	HudKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 4),
		Size = UDim2.new(1, -110, 0, 20),
		Font = Enum.Font.SourceSansBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR.Text,
		TextSize = 16,
		Text = displayName,
		Parent = row,
	})

	HudKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 24),
		Size = UDim2.new(1, -110, 0, 20),
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR.Muted,
		TextSize = 13,
		Text = subtitle,
		Parent = row,
	})

	local button = HudKit.new("TextButton", {
		BackgroundColor3 = COLOR.Accent,
		Position = UDim2.new(1, -96, 0.5, -16),
		Size = UDim2.new(0, 86, 0, 32),
		Font = Enum.Font.SourceSansBold,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 14,
		Text = buttonText,
		Parent = row,
	}, { HudKit.corner(6) })
	button.MouseButton1Click:Connect(onClick)

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

-- Fraction of the button's own height, not a fixed pixel count: a 20px icon read as tiny on a
-- 108x72 hero button and identically-sized on a 56x56 secondary one, so the hero action never read
-- as one. 0.55 was picked by eye against the design's Start Defense button.
local BUTTON_ICON_SCALE_DEFAULT = 0.55
-- Pixels between the button's left edge and an icon-with-text layout. Kept as its own named constant
-- (rather than inlined into the Position/padding math below) because both of those need to agree on
-- it, and the icon-only (centred) layout does not use it at all.
local BUTTON_ICON_LEFT_INSET = 8

-- Base fill/text per variant. Hover/press shades are DERIVED from `fill` via lighten()/darken() at
-- button-build time rather than listed here, so this table is the only place a variant's color is
-- ever spelled out.
local BUTTON_VARIANTS = {
	-- The one loud action on screen: Accent fill, dark text so it reads as a solid, confident button
	-- rather than colored outline text.
	primary = { fill = COLOR.Accent, text = COLOR.Panel, stroke = false },
	-- Everything else: matches the existing PanelLight/Line look used by rows and most panel chrome.
	secondary = { fill = COLOR.PanelLight, text = COLOR.Text, stroke = true },
	-- Destructive actions (unequip, scrap, abandon...): Bad fill, light text for contrast.
	danger = { fill = COLOR.Bad, text = COLOR.Text, stroke = false },
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
	iconFolder: string?,
	iconScale: number?, -- fraction of the button's height the icon occupies; defaults to
		-- BUTTON_ICON_SCALE_DEFAULT below. Override for a button that wants a stockier or daintier
		-- icon than the default without forcing every other button's icon to follow.
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
	-- path they took. Offsets only (not Scale) because restSize.Y.Offset is already the load-bearing
	-- "actual button height in pixels" assumption pressPos/hoverSize/the icon padding above all make.
	local panelFrameImage = UiIconConfig.Get("panelframe")
	local isSliceable = panelFrameImage ~= nil
		and restSize.X.Offset >= BUTTON_MIN_SLICE_SIZE
		and restSize.Y.Offset >= BUTTON_MIN_SLICE_SIZE

	local btn = HudKit.new("TextButton", {
		-- Only actually visible on the fallback (non-sliceable) path below; the sliceable path hides
		-- this via BackgroundTransparency and paints the fill on the background ImageLabel's
		-- ImageColor3 instead. Set unconditionally anyway, same "only one path shows it" convention
		-- plate() already uses for its own BackgroundColor3/ImageColor3 split.
		BackgroundColor3 = restColor,
		BackgroundTransparency = if isSliceable then 1 else 0,
		Position = restPos,
		AnchorPoint = opts.anchorPoint or Vector2.new(0, 0),
		Size = restSize,
		LayoutOrder = opts.layoutOrder or 0,
		AutoButtonColor = false, -- we drive every visual state ourselves via TweenService below
		Font = HudKit.FONT.BodyBold,
		TextColor3 = variant.text,
		TextSize = HudKit.TEXTSIZE.Body,
		Text = opts.text or "",
		Parent = opts.parent,
	}, if isSliceable then {} else { HudKit.corner(HudKit.RADIUS.Button), buttonFillGradient() })
	-- No UICorner on the sliceable path: the shape comes from the image's own cut corners, and
	-- rounding on top of a sliced image would just clip the cut back into a plain rounded rect --
	-- same reasoning as plate()'s shell/surface branch. The gradient here fills `btn` itself (its
	-- BackgroundColor3 is the visible fill on this path); the sliceable path parents the same helper
	-- onto backgroundLabel instead, since ImageColor3 is what's visible there. See buttonFillGradient
	-- above for why it's a fresh instance per call rather than one shared UIGradient.

	if variant.stroke then
		HudKit.stroke().Parent = btn
	end

	-- The angular background: a child ImageLabel filling the button, sized/positioned to track it
	-- automatically (1,0,1,0 relative to `btn`, so no separate Size/Position tween is ever needed
	-- for it — only its ImageColor3 changes on hover/press, via tweenFill below).
	--
	-- ZIndex = 0 keeps it below the icon and caption (siblings, ZIndex 1 and 2 respectively — see
	-- below): two children of the same GuiObject DO respect ZIndex ordering against each other.
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
	local backgroundLabel: ImageLabel? = nil
	local captionLabel: TextLabel? = nil
	if isSliceable then
		backgroundLabel = HudKit.new("ImageLabel", {
			BackgroundTransparency = 1,
			Image = panelFrameImage,
			ImageColor3 = restColor,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = PANEL_FRAME_SLICE_CENTER,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 0,
			Parent = btn,
		}, { buttonFillGradient() })

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
			ZIndex = 2, -- above the background (0) and the icon (1)
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
	-- ImageColor3 when sliced, or the button's own BackgroundColor3 on the fallback path (unchanged
	-- from before this background existed). Every hover/press/setButtonFill call goes through this
	-- pair instead of hardcoding BackgroundColor3, which is the fix for the "sliced buttons never
	-- recolor" regression a naive port of the old tweens would have shipped silently.
	local fillTarget: Instance = backgroundLabel or btn
	local fillProperty = if backgroundLabel then "ImageColor3" else "BackgroundColor3"

	-- Icon is optional and additive: a missing key must fall back to the text label alone, never an
	-- empty square, per this project's "missing art never breaks the loop" rule. `iconLabel` and the
	-- two image strings are locals closed over by the hover handlers further down, not stored in
	-- `state` (unlike the colors) — nothing outside this function ever needs to recolor an icon the
	-- way setButtonFill recolors a fill, so there's no case for exposing them the same way.
	local iconLabel: ImageLabel? = nil
	local iconRestImage: string? = nil
	local iconHoverImage: string? = nil
	if opts.icon then
		local hasText = opts.text ~= nil and opts.text ~= ""
		local iconScale = opts.iconScale or BUTTON_ICON_SCALE_DEFAULT
		local label = HudKit.new("ImageLabel", {
			BackgroundTransparency = 1,
			-- Icon+text: pinned to the left edge, text alone (below) padded clear of it so the two
			-- don't overlap in the middle. Icon-only: centred, since there's no text to share the
			-- button with.
			AnchorPoint = if hasText then Vector2.new(0, 0.5) else Vector2.new(0.5, 0.5),
			Position = if hasText then UDim2.new(0, BUTTON_ICON_LEFT_INSET, 0.5, 0) else UDim2.new(0.5, 0, 0.5, 0),
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
			ZIndex = 1,
			Parent = btn,
		})
		if HudKit.applyIcon(label, opts.icon, opts.iconFolder) then
			iconLabel = label
			iconRestImage = label.Image
			-- Hover art is optional per icon (see UiIconConfig's header comment on the `_hover`
			-- naming convention) — a missing entry just leaves this nil, and swapIcon() below treats
			-- nil as "leave it alone" rather than disabling anything.
			iconHoverImage = UiIconConfig.Get(opts.icon .. "_hover")
			if hasText then
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
	-- without re-deriving which path (sliced vs. fallback) it took at build time.
	local state = {
		restColor = restColor,
		hoverColor = hoverColor,
		pressColor = pressColor,
		fillTarget = fillTarget,
		fillProperty = fillProperty,
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

local PLATE_GRADIENT_LIGHTEN = 0.62 -- top edge: COLOR.Line lightened. Pushed well up from 0.35
-- after a Studio screenshot: at 2-3px against a bright outdoor scene, a mid-grey bevel is
-- technically correct and visually invisible. The bevel only earns its cost if it reads in game.
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

-- The 4px full-width accent bar across the top of a panel. Returns it so a caller can recolor a
-- specific panel later (a raid warning panel accenting Bad instead of Accent, say) without this
-- function needing a per-panel-type color lookup of its own.
function HudKit.accentCap(surface: Frame, color: Color3?): Frame
	return HudKit.new("Frame", {
		BackgroundColor3 = color or COLOR.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 4),
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
		-- this; text = "X" stays as the fallback HudKit.button already falls back to whenever the
		-- "close" key is missing from UiIconConfig/UiIcons (see its icon-resolution branch), so a
		-- place without that art still gets a legible, clickable close control instead of a blank one.
		HudKit.button({
			variant = "secondary",
			icon = "close",
			text = "X",
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

return HudKit
