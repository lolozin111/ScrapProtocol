--[[
	RunCard.lua
	The 240x392 "run buff" card — Card.dc.html translated pixel-for-pixel — extracted out of
	RaidShopPanel.lua so the post-boss reward pick (RaidClient.client.lua's old renderCardChoices,
	plain coloured buttons) can be rebuilt on the exact same card look the user approved from the
	mockup, instead of drifting into a second hand-rolled card design. Every size/color/font/border
	below is unchanged from RaidShopPanel's own copy — this file is a MOVE, not a rewrite; see that
	file's own header for which CSS rule each number traces back to.

	Also carries the fonts/colors/icon-size constants and a couple of small builders
	(`rarityLook`, `buildScrapGlyph`, `colorHex`) that RaidShopPanel's own shell (header readouts,
	the equipment-slot bar, the escape-item chips) still needs after the card left — those are
	exported rather than duplicated so the shop and the card can never end up painted from two
	slightly different palettes. RaidShopPanel aliases them straight back to its old local names
	(`local FONT = RunCard.FONT`, etc.) so nothing in its own body needed to be retyped.

	Public API:
		RunCard.build(opts) -> Frame
			opts = {
				Name, Kind, Rarity, IconKey,        -- header band + icon plate + card title
				EffectLabel, EffectFrom, EffectTo?, -- the effect line under the name
				Badge?,                              -- "NEW" | "RARITY UP" | nil
				Pips?,                                -- { FromLv, ToLv, PrevCap, Cap } or nil
				LevelText?, CapText?,                -- shown above the pips, only when Pips ~= nil
				FootNote?, Description?,             -- shown INSTEAD of the pips when Pips == nil
				Button = { Text, Variant = "buy"|"broke"|"take", Icon?, OnClick? },
				Parent, LayoutOrder?,
			}
		RunCard.rarityLook(rarity) -> color, fillTransparency, borderTransparency, cap
		RunCard.buildScrapGlyph(parent, size, color, layoutOrder?, iconKey?, fallbackLetter?)
		RunCard.colorHex(color3) -> "#RRGGBB"
		RunCard.FONT, RunCard.COLOR_*, RunCard.CARD_WIDTH, RunCard.CARD_HEIGHT
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunBuffConfig = require(ReplicatedStorage.Shared.RunBuffConfig)

local Hud = require(script.Parent.HudKit)

local RunCard = {}

----------------------------------------------------------------------
-- Instance helpers — same shape as every other panel file's local copy (see RaidShopPanel.lua's own
-- header on why these stay duplicated per-file rather than shared).
----------------------------------------------------------------------

local function new(className: string, props, children)
	local inst = Instance.new(className)
	for key, value in pairs(props or {}) do
		inst[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	return inst
end

local function corner(radius: number?)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

local function stroke(color: Color3, thickness: number?)
	return new("UIStroke", { Color = color, Thickness = thickness or 1 })
end

-- Rich text values need a literal "#RRGGBB", and computing it FROM the Color3 (rather than a
-- second hand-typed hex table) means a rarity color can never drift between the plain-Frame uses
-- below and the RichText spans in a card's effect line. Exported: RaidShopPanel's header still
-- needs this for its own "EQUIPMENT SLOTS n/4" RichText label.
function RunCard.colorHex(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local colorHex = RunCard.colorHex

-- Up to the first two words' first letters, uppercased — the icon-plate fallback when a UiIcons
-- entry hasn't been uploaded yet ("Overclock Chip" -> "OC").
local function initials(name: string): string
	local letters = {}
	for word in name:gmatch("%S+") do
		table.insert(letters, word:sub(1, 1))
		if #letters >= 2 then
			break
		end
	end
	return table.concat(letters):upper()
end

-- One warn per missing icon key, not one per render — a card re-renders on every Buy/Sell/RunBuffs
-- tick (or every boss-pick screen open), and a spammed Output window is as good as no warning at all.
local warnedIcons = {}
local function warnMissingIconOnce(key: string)
	if warnedIcons[key] then
		return
	end
	warnedIcons[key] = true
	warn(("[RunCard] no UiIcons entry for %q — using the tinted-initials fallback"):format(key))
end

----------------------------------------------------------------------
-- Fonts — Font.new against the real font-family JSON rather than HudKit.FONT's Enum.Font members,
-- because the mockup calls out WEIGHTS (Montserrat 800/700, Inconsolata 700/500, Source Sans 3
-- 400/600/700) that HudKit's existing "MontserratBold"-style Enum lookups can't express (there is
-- no Enum.Font for "Montserrat ExtraBold"). Kept local to this file rather than added to HudKit.FONT
-- — this card's exact type ramp is this design's own, not a new house-wide token.
--
-- Font.new doesn't actually validate its family path at call time (a bad path just renders with
-- missing-glyph fallback later, silently) — but it's wrapped in pcall anyway, matching HudKit's own
-- resolveFont defensiveness, in case a future engine ever tightens that.
----------------------------------------------------------------------

local function resolveCustomFont(family: string, weight: Enum.FontWeight, fallback: Enum.Font): Font
	local ok, font = pcall(Font.new, family, weight)
	if ok and font then
		return font
	end
	warn(("[RunCard] Font.new(%s, %s) failed; falling back to %s"):format(family, weight.Name, fallback.Name))
	return Font.fromEnum(fallback)
end

local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"
local INCONSOLATA = "rbxasset://fonts/families/Inconsolata.json"
local SOURCESANS = "rbxasset://fonts/families/SourceSansPro.json"

-- Exported: RaidShopPanel's shell (header/footer/slot tiles/escape chips) still uses this same type
-- ramp for everything around the cards, and a second Font.new pass there would just be two identical
-- pcall'd lookups doing the same work.
RunCard.FONT = {
	MontserratExtraBold = resolveCustomFont(MONTSERRAT, Enum.FontWeight.ExtraBold, Enum.Font.GothamBlack), -- 800
	MontserratBold = resolveCustomFont(MONTSERRAT, Enum.FontWeight.Bold, Enum.Font.GothamBold), -- 700
	InconsolataBold = resolveCustomFont(INCONSOLATA, Enum.FontWeight.Bold, Enum.Font.Code), -- 700
	InconsolataMedium = resolveCustomFont(INCONSOLATA, Enum.FontWeight.Medium, Enum.Font.Code), -- 500
	SourceSansRegular = resolveCustomFont(SOURCESANS, Enum.FontWeight.Regular, Enum.Font.SourceSans), -- 400
	SourceSansSemiBold = resolveCustomFont(SOURCESANS, Enum.FontWeight.SemiBold, Enum.Font.SourceSansBold), -- 600
	SourceSansBold = resolveCustomFont(SOURCESANS, Enum.FontWeight.Bold, Enum.Font.SourceSansBold), -- 700
}
local FONT = RunCard.FONT

-- Roblox TextLabels have no CSS `letter-spacing` equivalent — every `letter-spacing: 0.Xem` in the
-- mockup is dropped silently here, per the task's own instruction to omit rather than fake it.

----------------------------------------------------------------------
-- Colors — lifted straight from the mockups' hex literals. Several happen to equal an existing
-- HudKit.COLOR entry (noted below); those are named separately anyway rather than pointed at
-- HudKit.COLOR, because the ones that DON'T match (Good/Bad) would otherwise sit right next to
-- lookalike names that mean a different shade — a future edit to HudKit.COLOR.Good must not silently
-- retint this screen's arrows. Exported for the same reason FONT is: RaidShopPanel's shell paints
-- from this exact palette too.
----------------------------------------------------------------------

RunCard.COLOR_PANEL_BG = Color3.fromRGB(22, 18, 15) -- #16120F — same value as HudKit.COLOR.Panel
RunCard.COLOR_CARD_BG = Color3.fromRGB(32, 27, 23) -- #201B17
RunCard.COLOR_LINE = Color3.fromRGB(60, 53, 47) -- #3C352F — same value as HudKit.COLOR.Line
RunCard.COLOR_TEXT = Color3.fromRGB(237, 231, 220) -- #EDE7DC — same value as HudKit.COLOR.Text
RunCard.COLOR_MUTED = Color3.fromRGB(167, 156, 140) -- #A79C8C — same value as HudKit.COLOR.Muted
RunCard.COLOR_ACCENT = Color3.fromRGB(224, 122, 59) -- #E07A3B — same value as HudKit.COLOR.Accent
RunCard.COLOR_GOOD = Color3.fromRGB(123, 192, 160) -- #7BC0A0 — NOT HudKit.COLOR.Good (95,160,130)
RunCard.COLOR_BAD = Color3.fromRGB(217, 119, 106) -- #D9776A — NOT HudKit.COLOR.Bad (190,90,75)
RunCard.COLOR_BUTTON_DARK = Color3.fromRGB(40, 35, 31) -- #28231F (SELL / LEAVE SHOP chrome)

local COLOR_PANEL_BG = RunCard.COLOR_PANEL_BG
local COLOR_CARD_BG = RunCard.COLOR_CARD_BG
local COLOR_LINE = RunCard.COLOR_LINE
local COLOR_TEXT = RunCard.COLOR_TEXT
local COLOR_MUTED = RunCard.COLOR_MUTED
local COLOR_ACCENT = RunCard.COLOR_ACCENT
local COLOR_BAD = RunCard.COLOR_BAD

-- Card.dc.html's RARITY table: color is exact-equal to ModConfig.Rarities[x].Color (verified against
-- source), which is why RunBuffConfig.RarityColor is used for it below instead of a 4th hardcoded
-- table — one source for "what color is Epic" instead of two that can drift. Only the ALPHA values
-- (tint 14%, border 55%/55%/70%) aren't in any config, since they're a pure presentation choice with
-- nothing server-side to agree with. Common/Uncommon (the boss-card pool's low end, which the shop
-- never rolls) fall through to the 0.55 default below rather than erroring — RunBuffConfig.RarityColor
-- and RunBuffConfig.Cap both already return nil/0 gracefully for a rarity they don't know either.
local RARITY_TINT_TRANSPARENCY = 1 - 0.14 -- rgba(...,0.14) tint washes
local RARITY_BORDER_ALPHA = { Rare = 0.55, Epic = 0.55, Legendary = 0.70 }

-- rarityColor, tint-BackgroundTransparency, border-UIStroke-Transparency, level cap — everything a
-- card/pip/chip needs to paint one rarity, in one call so nothing re-derives (or mis-derives) the
-- alpha table above per callsite. Exported: RaidShopPanel's equipment-slot tiles and escape-item
-- chips call this too.
function RunCard.rarityLook(rarity: string): (Color3, number, number, number)
	local color = RunBuffConfig.RarityColor(rarity) or COLOR_MUTED
	local borderTransparency = 1 - (RARITY_BORDER_ALPHA[rarity] or 0.55)
	return color, RARITY_TINT_TRANSPARENCY, borderTransparency, RunBuffConfig.Cap(rarity) or 0
end
local rarityLook = RunCard.rarityLook

----------------------------------------------------------------------
-- Icons — HudKit.applyIcon with no folder argument, so UiIconConfig's ids win and the hand-built
-- ReplicatedStorage.UiIcons folder stays a fallback (the project's stated convention: HUD chrome is
-- code, and belongs where Rojo syncs it). Falls back to a tinted circle with the item's initials —
-- "missing art never breaks the loop" (CLAUDE.md) — with exactly one warn per missing key.
----------------------------------------------------------------------

local ICON_PLATE_SIZE = 76 -- Card.dc.html's icon-plate: 76x76, radius 38 (a perfect circle)
-- The mockup's inline <svg> was 40 in a 76 plate, but that svg drew edge to edge; the uploaded PNGs
-- carry their own margin inside the square, so at 40 the glyph read visibly smaller than the
-- reference ("they a little small", 2026-09-22). 58 makes the drawn strokes land where the mockup's
-- did. Change this, not the plate, if a future icon set is redrawn tighter.
local ICON_GLYPH_SIZE = 58

local function buildIconPlate(parent: Instance, displayName: string, iconKey: string, rarityColor: Color3, fillTr: number, borderTr: number)
	local plate = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(ICON_PLATE_SIZE, ICON_PLATE_SIZE),
		BackgroundColor3 = rarityColor,
		BackgroundTransparency = fillTr,
		Parent = parent,
	}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local ring = stroke(rarityColor, 1)
	ring.Transparency = borderTr
	ring.Parent = plate

	local image = new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(ICON_GLYPH_SIZE, ICON_GLYPH_SIZE),
		BackgroundTransparency = 1,
		Image = "",
		Parent = plate,
	})
	if not Hud.applyIcon(image, iconKey) then
		image.Visible = false
		warnMissingIconOnce(iconKey)
		new("TextLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			FontFace = FONT.MontserratExtraBold,
			Text = initials(displayName),
			TextColor3 = rarityColor,
			TextSize = 22,
			Parent = plate,
		})
	end
	return plate
end

-- The Scrap "nut" glyph next to a price, generalized (iconKey/fallbackLetter default to "RunScrap"/
-- "S") so it still serves every existing call (the shop's header readout, the shop's buy button)
-- unchanged while staying reusable for any future card whose button needs a different currency
-- icon. `color` lets one glyph serve the header readout (Accent), the affordable button (dark, on
-- the orange fill) and the broke button (Bad) without three separate icon instances in UiIcons.
-- Exported: RaidShopPanel's header currency readout builds its own copy of this glyph too.
function RunCard.buildScrapGlyph(parent: Instance, size: number, color: Color3, layoutOrder: number?, iconKey: string?, fallbackLetter: string?)
	iconKey = iconKey or "RunScrap"
	fallbackLetter = fallbackLetter or "S"
	local image = new("ImageLabel", {
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Image = "",
		ImageColor3 = color,
		LayoutOrder = layoutOrder or 0,
		Parent = parent,
	})
	if not Hud.applyIcon(image, iconKey) then
		image.Visible = false
		warnMissingIconOnce(iconKey)
		new("TextLabel", {
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			FontFace = FONT.MontserratExtraBold,
			Text = fallbackLetter,
			TextColor3 = color,
			TextSize = size,
			LayoutOrder = layoutOrder or 0,
			Parent = parent,
		})
	end
	return image
end
local buildScrapGlyph = RunCard.buildScrapGlyph

----------------------------------------------------------------------
-- Card pips — the 5-state ramp from Card.dc.html's `renderVals`. (The equipment-slot bar's simpler
-- 3-state pip ramp stays in RaidShopPanel.lua — that's a different chart with a different state
-- count, not this card.)
----------------------------------------------------------------------

local CARD_PIP_HEIGHT = 8
local CARD_PIP_GAP = 6

-- fromLv/toLv/prevCap/cap (opts.Pips's own fields, see RunCard.build's doc comment):
-- i<=fromLv: already owned before this purchase (solid).
-- i<=toLv:   what THIS purchase grants (solid + white ring + a colored glow ring, Card.dc.html's
--            box-shadow 0 0 0 2px tint).
-- i<=cap and i>prevCap: reachable at this rarity but not bought yet (tint fill, colored border).
-- i<=cap:    reachable at a LOWER cap already passed, still not bought (transparent, colored border).
-- else:      beyond this rarity's cap entirely (dashed, per HudKit.dashedBox).
local function buildCardPip(parent: Instance, width: number, layoutOrder: number, index: number, fromLv: number, toLv: number, prevCap: number, cap: number, rarityColor: Color3, fillTr: number, borderTr: number)
	local pip = new("Frame", {
		Size = UDim2.fromOffset(width, CARD_PIP_HEIGHT),
		LayoutOrder = layoutOrder,
		BackgroundTransparency = 1,
		Parent = parent,
	}, { corner(2) })

	if index <= fromLv then
		pip.BackgroundColor3 = rarityColor
		pip.BackgroundTransparency = 0
		stroke(rarityColor, 1).Parent = pip
	elseif index <= toLv then
		pip.BackgroundColor3 = rarityColor
		pip.BackgroundTransparency = 0
		stroke(COLOR_TEXT, 1).Parent = pip
		local glow = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(1, 4, 1, 4),
			BackgroundTransparency = 1,
			Parent = pip,
		}, { corner(3) })
		local glowStroke = stroke(rarityColor, 2)
		glowStroke.Transparency = fillTr
		glowStroke.Parent = glow
	elseif index <= cap and index > prevCap then
		pip.BackgroundColor3 = rarityColor
		pip.BackgroundTransparency = fillTr
		stroke(rarityColor, 1).Parent = pip
	elseif index <= cap then
		local s = stroke(rarityColor, 1)
		s.Transparency = borderTr
		s.Parent = pip
	else
		pip.BackgroundColor3 = COLOR_PANEL_BG
		pip.BackgroundTransparency = 0
		Hud.dashedBox(pip, { width = math.floor(width), height = CARD_PIP_HEIGHT, color = COLOR_LINE, thickness = 1 })
	end
	return pip
end

----------------------------------------------------------------------
-- The card — 240x392, Card.dc.html translated top to bottom.
----------------------------------------------------------------------

RunCard.CARD_WIDTH, RunCard.CARD_HEIGHT = 240, 392
local CARD_WIDTH, CARD_HEIGHT = RunCard.CARD_WIDTH, RunCard.CARD_HEIGHT
local CARD_PAD_X = 14 -- the name/effect/level blocks' left+right padding
local CARD_CONTENT_WIDTH = CARD_WIDTH - CARD_PAD_X * 2
local CARD_PIP_WIDTH = (CARD_CONTENT_WIDTH - CARD_PIP_GAP * 4) / 5
local CARD_BUTTON_HEIGHT = 44

-- The footer button. `opts.Button.Variant` is "buy"/"take" (active — accent fill, dark text, hover
-- feedback, wired to OnClick) or "broke" (inactive — panel-color fill, a Line stroke, Bad-red text,
-- no click). "buy" and "take" render identically on purpose: a boss reward's TAKE is the same loud
-- affirmative action the shop's BUY is, just never blocked by afford/slot checks, so it never needs
-- the "broke" look. `opts.Button.Icon` is an optional UiIcons key shown before the label (the shop's
-- BUY/NEED states pass "RunScrap"; SLOTS FULL and the boss card's TAKE pass nothing).
local function buildFooterButton(parent: Instance, opts)
	local button = opts.Button or {}
	local active = button.Variant ~= "broke"

	local wrapper = new("Frame", {
		Size = UDim2.new(1, 0, 0, CARD_BUTTON_HEIGHT + 24),
		BackgroundTransparency = 1,
		LayoutOrder = 6,
		Parent = parent,
	}, { new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }) })

	local btn = new("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		AutoButtonColor = false,
		BackgroundColor3 = active and COLOR_ACCENT or COLOR_PANEL_BG,
		Text = "",
		Active = active,
		Parent = wrapper,
	}, { corner(6) })
	if not active then
		stroke(COLOR_LINE, 1).Parent = btn
	end

	local row = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = btn,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),
	})

	local textColor = active and COLOR_PANEL_BG or COLOR_BAD

	if button.Icon then
		buildScrapGlyph(row, 20, textColor, 1, button.Icon)
	end
	new("TextLabel", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
		FontFace = FONT.MontserratExtraBold,
		Text = button.Text or "",
		TextColor3 = textColor,
		TextSize = 14,
		Parent = row,
	})

	if active then
		local restColor = COLOR_ACCENT
		btn.MouseEnter:Connect(function()
			btn.BackgroundColor3 = Hud.lighten(restColor, 0.1)
		end)
		btn.MouseLeave:Connect(function()
			btn.BackgroundColor3 = restColor
		end)
		if button.OnClick then
			btn.MouseButton1Click:Connect(button.OnClick)
		end
	end
	return wrapper
end

local function buildEffectLine(parent: Instance, layoutOrder: number, label: string, fromText: string?, toText: string?)
	local parts = { label }
	if fromText and fromText ~= "" then
		table.insert(parts, ("<font color=\"%s\"><b>%s</b></font>"):format(colorHex(COLOR_TEXT), fromText))
	end
	if toText and toText ~= "" then
		table.insert(parts, ("<font color=\"%s\"> \226\134\146 </font>"):format(colorHex(COLOR_MUTED))) -- " → "
		table.insert(parts, ("<font color=\"%s\"><b>%s</b></font>"):format(colorHex(RunCard.COLOR_GOOD), toText))
	end
	new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = layoutOrder,
		RichText = true,
		FontFace = FONT.SourceSansRegular,
		TextColor3 = COLOR_MUTED,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Text = table.concat(parts, " "),
		Parent = parent,
	})
end

-- The level/footnote section between the name/effect block and the footer button. Two shapes:
-- a levelText/capText row + 5-pip bar (opts.Pips present — shop Perk/Gear offers, driven by
-- RunBuffConfig.PreviewOffer), or a single bold rarity-tinted caption plus a muted description line
-- (opts.Pips absent — shop Escape offers' "ONE USE"/"UNTIL THE RUN ENDS", and boss reward cards'
-- "STACKS · NO SLOT", both of which stack/expire outside the level+cap system so there is nothing
-- to put a pip bar under).
local function buildLevelSection(parent: Instance, opts, rarityColor: Color3, fillTr: number, borderTr: number)
	local wrapper = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 4, -- between nameWrapper (3) and the fill-spacer (5) in RunCard.build — see its comment
		Parent = parent,
	}, {
		new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, CARD_PAD_X), PaddingRight = UDim.new(0, CARD_PAD_X) }),
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 7) }),
	})

	if not opts.Pips then
		new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 16),
			LayoutOrder = 1,
			FontFace = FONT.InconsolataBold,
			Text = opts.FootNote or "",
			TextColor3 = rarityColor,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = wrapper,
		})
		new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			FontFace = FONT.SourceSansRegular,
			Text = opts.Description or "",
			TextColor3 = COLOR_MUTED,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = wrapper,
		})
		return
	end

	local row = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 1,
		Parent = wrapper,
	})
	new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.5, 0, 1, 0),
		FontFace = FONT.InconsolataBold,
		Text = opts.LevelText or "",
		TextColor3 = COLOR_TEXT,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.new(0.5, 0, 1, 0),
		FontFace = FONT.InconsolataMedium,
		Text = opts.CapText or "",
		TextColor3 = COLOR_MUTED,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local pipsRow = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, CARD_PIP_HEIGHT),
		LayoutOrder = 2,
		Parent = wrapper,
	}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, CARD_PIP_GAP) }) })
	for i = 1, 5 do
		buildCardPip(pipsRow, CARD_PIP_WIDTH, i, i, opts.Pips.FromLv, opts.Pips.ToLv, opts.Pips.PrevCap, opts.Pips.Cap, rarityColor, fillTr, borderTr)
	end
end

-- Builds one card and parents it into `opts.Parent`. See this file's header for the full opts shape.
-- Badge color: "RARITY UP" tints itself the card's own rarity color (Card.dc.html shows the NEW
-- rarity's color on that pill); "NEW" always uses Accent, matching the shop's own original behavior.
function RunCard.build(opts): Frame
	local rarityColor, fillTr, borderTr = rarityLook(opts.Rarity)

	local card = new("Frame", {
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		BackgroundColor3 = COLOR_CARD_BG,
		ClipsDescendants = true,
		LayoutOrder = opts.LayoutOrder or 0,
		Parent = opts.Parent,
	}, {
		corner(10),
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 0) }),
	})
	local outline = stroke(rarityColor, 1)
	outline.Transparency = borderTr
	outline.Parent = card

	-- Header band — rarity label left, kind tag right, tinted fill, a 1px bottom rule in the same
	-- border color/alpha as the card's own outline (Card.dc.html's border-bottom).
	local header = new("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = rarityColor,
		BackgroundTransparency = fillTr,
		LayoutOrder = 1,
		Parent = card,
	})
	local headerRule = new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = rarityColor,
		BackgroundTransparency = borderTr,
		BorderSizePixel = 0,
		Parent = header,
	})
	headerRule.Name = "Rule"
	new("TextLabel", {
		Position = UDim2.new(0, 12, 0, 0),
		Size = UDim2.new(0.6, 0, 1, 0),
		BackgroundTransparency = 1,
		FontFace = FONT.MontserratExtraBold,
		Text = (opts.Rarity or ""):upper(),
		TextColor3 = rarityColor,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.new(0.4, 0, 1, 0),
		BackgroundTransparency = 1,
		FontFace = FONT.InconsolataBold,
		Text = (opts.Kind or ""):upper(),
		TextColor3 = COLOR_MUTED,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = header,
	})

	-- Icon area — margin 12/12/0 around a 116-tall dark box, per Card.dc.html.
	local iconWrapper = new("Frame", {
		Size = UDim2.new(1, 0, 0, 128),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = card,
	}, {
		new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
	})
	local iconBox = new("Frame", {
		Size = UDim2.new(1, 0, 0, 116),
		BackgroundColor3 = COLOR_PANEL_BG,
		Parent = iconWrapper,
	}, { corner(8), stroke(COLOR_LINE, 1) })
	buildIconPlate(iconBox, opts.Name or "", opts.IconKey, rarityColor, fillTr, borderTr)

	if opts.Badge then
		local badgeColor = opts.Badge == "RARITY UP" and rarityColor or COLOR_ACCENT
		new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 8),
			Size = UDim2.new(0, 0, 0, 18),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = badgeColor,
			FontFace = FONT.MontserratExtraBold,
			Text = "  " .. opts.Badge .. "  ",
			TextColor3 = COLOR_PANEL_BG,
			TextSize = 10,
			Parent = iconBox,
		}, { corner(4) })
	end

	-- Name + effect line.
	local nameWrapper = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = card,
	}, {
		new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, CARD_PAD_X), PaddingRight = UDim.new(0, CARD_PAD_X) }),
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
	})
	new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 21),
		LayoutOrder = 1,
		FontFace = FONT.MontserratBold,
		Text = opts.Name or "",
		TextColor3 = COLOR_TEXT,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = nameWrapper,
	})
	buildEffectLine(nameWrapper, 2, opts.EffectLabel or "", opts.EffectFrom, opts.EffectTo)

	buildLevelSection(card, opts, rarityColor, fillTr, borderTr)

	-- Spacer with UIFlexItem.Fill — the UIListLayout equivalent of the mockup's `margin-top: auto`,
	-- pushing the button to the card's bottom edge regardless of how tall the sections above it are.
	new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		Parent = card,
	}, { new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }) })

	buildFooterButton(card, opts)

	return card
end

return RunCard
