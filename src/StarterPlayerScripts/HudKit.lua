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

-- Montserrat for anything that should read as a heading/display number (chosen because it's a real
-- Roblox enum font AND is what the design mockups use); SourceSans/-Bold for body copy; Code for
-- numeric readouts (ore counts, timers) where a monospaced look reads as "instrument panel".
HudKit.FONT = {
	Display = Enum.Font.Montserrat,
	Body = Enum.Font.SourceSans,
	BodyBold = Enum.Font.SourceSansBold,
	Mono = Enum.Font.Code,
}

-- Small type scale, pulled from sizes already scattered across the file (13/14/16 body text, 18-ish
-- headings) rather than invented fresh — so adopting these in a panel is a no-visual-diff change.
HudKit.TEXTSIZE = {
	Label = 11,
	Body = 15,
	Title = 18,
	Readout = 17,
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
function HudKit.getUiIcon(key: string): string?
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
-- Buttons: variants + hover/press feedback
----------------------------------------------------------------------
-- There was not one TweenService call anywhere in the HUD before this, and no hover/press state on
-- any button — which is most of why buttons here don't read as clickable beyond the cursor icon
-- changing on top of them. HudKit.button() is additive: existing call sites building their own
-- TextButton by hand (makeRow's included) are untouched and keep working exactly as before.

local BUTTON_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BUTTON_HOVER_LIGHTEN = 0.12
local BUTTON_PRESS_DARKEN = 0.18

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
-- `state` holds the tween AND the button's rest/hover/press colors (see `buttonState` above) so
-- HudKit.setButtonFill can both cancel an in-flight tween and update the very colors this function
-- reads on the next MouseEnter/Leave -- there is no closed-over color left to go stale.
local function makeTweener(btn: TextButton, state)
	return function(goal: { [string]: any })
		if not btn.Parent then
			return
		end
		if state.activeTween then
			state.activeTween:Cancel()
		end
		state.activeTween = TweenService:Create(btn, BUTTON_TWEEN_INFO, goal)
		state.activeTween:Play()
	end
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

	local btn = HudKit.new("TextButton", {
		BackgroundColor3 = restColor,
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
	}, { HudKit.corner(HudKit.RADIUS.Button) })

	if variant.stroke then
		HudKit.stroke().Parent = btn
	end

	-- Icon is optional and additive: a missing key must fall back to the text label alone, never an
	-- empty square, per this project's "missing art never breaks the loop" rule.
	if opts.icon then
		local iconLabel = HudKit.new("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.new(0, 20, 0, 20),
			Parent = btn,
		})
		if not HudKit.applyIcon(iconLabel, opts.icon, opts.iconFolder) then
			iconLabel:Destroy()
		end
	end

	-- Colors live in `state`, not as closed-over locals, so HudKit.setButtonFill can rewrite them
	-- later and have every handler below see the new values on the very next hover/press -- this
	-- table IS the fix for the button-recolors-then-reverts-on-MouseLeave bug.
	local state = { restColor = restColor, hoverColor = hoverColor, pressColor = pressColor }
	buttonState[btn] = state

	local tween = makeTweener(btn, state)

	btn.MouseEnter:Connect(function()
		tween({ BackgroundColor3 = state.hoverColor, Size = hoverSize })
	end)
	btn.MouseLeave:Connect(function()
		tween({ BackgroundColor3 = state.restColor, Size = restSize, Position = restPos })
	end)
	btn.MouseButton1Down:Connect(function()
		tween({ BackgroundColor3 = state.pressColor, Position = pressPos })
	end)
	btn.MouseButton1Up:Connect(function()
		tween({ BackgroundColor3 = state.hoverColor, Position = restPos, Size = hoverSize })
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
-- Also cancels any in-flight tween before applying the new rest color directly: without this, a
-- MouseLeave tween already mid-flight (queued before this call, animating toward the OLD rest
-- color it captured when it started) would finish and visually overwrite the color this function
-- just set, a moment later and for no visible reason.
function HudKit.setButtonFill(button: TextButton, color: Color3)
	local state = buttonState[button]
	if not state then
		return -- not a HudKit.button()-built button (or already GC'd); nothing to update
	end
	state.restColor = color
	state.hoverColor = HudKit.lighten(color, BUTTON_HOVER_LIGHTEN)
	state.pressColor = HudKit.darken(color, BUTTON_PRESS_DARKEN)
	if state.activeTween then
		state.activeTween:Cancel()
		state.activeTween = nil
	end
	if button.Parent then -- same destroyed-instance guard as makeTweener; a destroyed button can't be recolored
		button.BackgroundColor3 = state.restColor
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

local PLATE_GRADIENT_LIGHTEN = 0.35 -- top edge: COLOR.Line lightened, reads as a lit bevel
local PLATE_GRADIENT_DARKEN = 0.85 -- bottom edge: COLOR.Line darkened toward near-black
local PLATE_SURFACE_INSET = 2 -- pixels of shell visible as a border once the surface sits on top

-- Returns (surface, shell) in that order: surface is what a caller almost always wants right away
-- (to parent content into), shell is only needed afterward to move/resize the whole panel — hence
-- `props` (Position, Size, Parent, AnchorPoint, LayoutOrder, ZIndex, ...) is applied to the shell,
-- since that's the outer box actually being placed in the screen.
--
-- KNOWN LIMITATION: the mockup's corners are angular/clipped (faceted cut-steel), which UICorner
-- cannot reproduce — Roblox has no clip-path equivalent. Rounded corners are the interim look, not
-- the final one. Swapping to a 9-slice ImageLabel border later is a change entirely inside this
-- function, which is the whole reason panels should route through plate() rather than hand-rolling
-- the shell Frame per panel.
function HudKit.plate(props: { [string]: any }?): (Frame, Frame)
	local shellProps: { [string]: any } = {
		BackgroundColor3 = Color3.new(1, 1, 1), -- overpainted by the UIGradient below; this fill is
			-- never actually seen, but a Frame with Transparency and a UIGradient renders nothing
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
	-- throw the moment the shell Frame is constructed below.
	local automaticSize = shellProps.automaticSize
	shellProps.automaticSize = nil

	local shell = HudKit.new("Frame", shellProps, {
		HudKit.corner(HudKit.RADIUS.Panel),
		HudKit.new("UIGradient", {
			Rotation = 90, -- 0 is left-to-right; 90 turns the same left->right stops top-to-bottom
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, HudKit.lighten(COLOR.Line, PLATE_GRADIENT_LIGHTEN)),
				ColorSequenceKeypoint.new(1, HudKit.darken(COLOR.Line, PLATE_GRADIENT_DARKEN)),
			}),
		}),
	})

	if automaticSize then
		-- Base height is just the two 2px insets (top + bottom bevel) so the surface, once it grows
		-- to its content, overflows evenly on both edges rather than the shell starting undersized.
		-- Width is left exactly as the caller set it via props.Size (or the Frame default) — only Y
		-- becomes automatic, so callers keep setting an explicit width the normal way.
		shell.Size = UDim2.new(shell.Size.X.Scale, shell.Size.X.Offset, 0, PLATE_SURFACE_INSET * 2)
		shell.AutomaticSize = Enum.AutomaticSize.Y
	end

	local surface = HudKit.new("Frame", {
		BackgroundColor3 = COLOR.Panel,
		Position = UDim2.fromOffset(PLATE_SURFACE_INSET, PLATE_SURFACE_INSET),
		-- Non-auto: unchanged, scale-relative to the shell. Auto: offset-only base (no scale
		-- component means no dependency on the shell's still-being-computed height) plus
		-- AutomaticSize.Y so it grows to whatever's parented into it.
		Size = automaticSize and UDim2.new(1, -PLATE_SURFACE_INSET * 2, 0, 0)
			or UDim2.new(1, -PLATE_SURFACE_INSET * 2, 1, -PLATE_SURFACE_INSET * 2),
		AutomaticSize = automaticSize and Enum.AutomaticSize.Y or nil,
		Parent = shell,
		-- slightly smaller radius than the shell's, concentric with it, so the visible bevel reads
		-- as an even-width border all the way around rather than looking mitred at the corners
	}, { HudKit.corner(math.max(HudKit.RADIUS.Panel - PLATE_SURFACE_INSET, 0)) })

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

local PANEL_HEADER_HEIGHT = 48
local PANEL_HEADER_DARKEN = 0.4 -- one shade darker than the surface, so the header reads as chrome
local PANEL_HEADER_TICK_WIDTH = 4
local PANEL_HEADER_BORDER = 2
local PANEL_HEADER_CLOSE_SIZE = 28

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
		-- button in an otherwise responsive panel.
		HudKit.button({
			variant = "secondary",
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
