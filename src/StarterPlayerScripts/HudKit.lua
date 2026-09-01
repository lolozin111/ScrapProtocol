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

-- Wraps a TextButton so every MouseEnter/Leave/Down/Up tween goes through one Cancel-then-Play,
-- rather than stacking competing tweens when a player mashes a button or mouses in and out fast.
--
-- GUARD: panels in this HUD are created and destroyed repeatedly (MainHud rebuilds whole panels on
-- refresh), so a MouseLeave/Up can fire after `btn` is already destroyed and parented to nil.
-- Playing a Tween on a destroyed instance throws, so every call here bails out on `not btn.Parent`
-- instead of assuming the button is still mounted.
local function makeTweener(btn: TextButton)
	local activeTween: Tween? = nil
	return function(goal: { [string]: any })
		if not btn.Parent then
			return
		end
		if activeTween then
			activeTween:Cancel()
		end
		activeTween = TweenService:Create(btn, BUTTON_TWEEN_INFO, goal)
		activeTween:Play()
	end
end

-- Builds a variant-styled TextButton with real hover/press feedback. Additive alongside makeRow's
-- inline button and any hand-rolled TextButton elsewhere — nothing existing is changed to use this.
function HudKit.button(opts: HudButtonOptions): TextButton
	local variantName = opts.variant or "secondary"
	local variant = BUTTON_VARIANTS[variantName] or BUTTON_VARIANTS.secondary

	local restColor = variant.fill
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

	local tween = makeTweener(btn)

	btn.MouseEnter:Connect(function()
		tween({ BackgroundColor3 = hoverColor, Size = hoverSize })
	end)
	btn.MouseLeave:Connect(function()
		tween({ BackgroundColor3 = restColor, Size = restSize, Position = restPos })
	end)
	btn.MouseButton1Down:Connect(function()
		tween({ BackgroundColor3 = pressColor, Position = pressPos })
	end)
	btn.MouseButton1Up:Connect(function()
		tween({ BackgroundColor3 = hoverColor, Position = restPos, Size = hoverSize })
	end)

	if opts.onClick then
		btn.MouseButton1Click:Connect(opts.onClick)
	end

	return btn
end

return HudKit
