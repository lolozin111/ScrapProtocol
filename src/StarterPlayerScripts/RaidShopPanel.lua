--[[
	RaidShopPanel.lua
	The Salvage Run raid shop — DESIGN_NOTES.md's "Raid shop rework — BUILD CONTRACT", step 4
	(client). The user approved a mockup and asked to be "100% loyal" to it: this file is a literal
	pixel translation of `design/raid-shop/Card.dc.html` (one card, 240x392) and
	`design/raid-shop/Main.dc.html` (the 1120-wide shop screen + equipment-slot bar), with
	`SlotsFull.dc.html` covering the "4/4 slots" state. Every size/color/font/border below has a
	comment pointing at the CSS rule it came from — if a number here looks odd, that's the reason
	before assuming it's a typo.

	Self-boots like ShopPanel.lua/TurretPanel.lua: it only ever parents into Hud.screenGui, nothing
	it builds needs to live inside a MainHud-owned instance, so there's no reason for a constructor.

	SHARED SOURCE OF TRUTH: every number that could disagree with the server (price, level, cap,
	rarity, the value a card advertises) comes from `RunBuffConfig` — the same module
	`RunBuffService`/`RaidRoomService` use server-side — via `PreviewOffer`/`CardValue`/`Cap`/
	`RarityColor`. This file only owns PRESENTATION: which pixel a number lands on, not what the
	number is.

	Public API: `Open(payload)` (a fresh "ShopOffers" status — shows the panel), `Update(payload)`
	(a "ShopResult" or "RunBuffs" status — refreshes it, or toasts a failure), `Close()`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RunBuffConfig = require(ReplicatedStorage.Shared.RunBuffConfig)

local Hud = require(script.Parent.HudKit)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RaidRoomAction = Remotes.RaidRoomAction

local RaidShopPanel = {}

----------------------------------------------------------------------
-- Instance helpers — same shape as every other panel file's local copy (RaidClient.client.lua's
-- own header explains why these stay duplicated per-file rather than shared: each panel file is
-- meant to stay independently readable).
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
-- below and the RichText spans in a card's effect line.
local function colorHex(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

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
-- tick, and a spammed Output window is as good as no warning at all.
local warnedIcons = {}
local function warnMissingIconOnce(key: string)
	if warnedIcons[key] then
		return
	end
	warnedIcons[key] = true
	warn(("[RaidShopPanel] no UiIcons entry for %q — using the tinted-initials fallback"):format(key))
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
	warn(("[RaidShopPanel] Font.new(%s, %s) failed; falling back to %s"):format(family, weight.Name, fallback.Name))
	return Font.fromEnum(fallback)
end

local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"
local INCONSOLATA = "rbxasset://fonts/families/Inconsolata.json"
local SOURCESANS = "rbxasset://fonts/families/SourceSansPro.json"

local FONT = {
	MontserratExtraBold = resolveCustomFont(MONTSERRAT, Enum.FontWeight.ExtraBold, Enum.Font.GothamBlack), -- 800
	MontserratBold = resolveCustomFont(MONTSERRAT, Enum.FontWeight.Bold, Enum.Font.GothamBold), -- 700
	InconsolataBold = resolveCustomFont(INCONSOLATA, Enum.FontWeight.Bold, Enum.Font.Code), -- 700
	InconsolataMedium = resolveCustomFont(INCONSOLATA, Enum.FontWeight.Medium, Enum.Font.Code), -- 500
	SourceSansRegular = resolveCustomFont(SOURCESANS, Enum.FontWeight.Regular, Enum.Font.SourceSans), -- 400
	SourceSansSemiBold = resolveCustomFont(SOURCESANS, Enum.FontWeight.SemiBold, Enum.Font.SourceSansBold), -- 600
	SourceSansBold = resolveCustomFont(SOURCESANS, Enum.FontWeight.Bold, Enum.Font.SourceSansBold), -- 700
}

-- Roblox TextLabels have no CSS `letter-spacing` equivalent — every `letter-spacing: 0.Xem` in the
-- mockup is dropped silently here, per the task's own instruction to omit rather than fake it.

----------------------------------------------------------------------
-- Colors — lifted straight from the mockups' hex literals. Several happen to equal an existing
-- HudKit.COLOR entry (noted below); those are named separately anyway rather than pointed at
-- HudKit.COLOR, because the ones that DON'T match (Good/Bad) would otherwise sit right next to
-- lookalike names that mean a different shade — a future edit to HudKit.COLOR.Good must not silently
-- retint this screen's arrows.
----------------------------------------------------------------------

local COLOR_PANEL_BG = Color3.fromRGB(22, 18, 15) -- #16120F — same value as HudKit.COLOR.Panel
local COLOR_CARD_BG = Color3.fromRGB(32, 27, 23) -- #201B17
local COLOR_LINE = Color3.fromRGB(60, 53, 47) -- #3C352F — same value as HudKit.COLOR.Line
local COLOR_TEXT = Color3.fromRGB(237, 231, 220) -- #EDE7DC — same value as HudKit.COLOR.Text
local COLOR_MUTED = Color3.fromRGB(167, 156, 140) -- #A79C8C — same value as HudKit.COLOR.Muted
local COLOR_ACCENT = Color3.fromRGB(224, 122, 59) -- #E07A3B — same value as HudKit.COLOR.Accent
local COLOR_GOOD = Color3.fromRGB(123, 192, 160) -- #7BC0A0 — NOT HudKit.COLOR.Good (95,160,130)
local COLOR_BAD = Color3.fromRGB(217, 119, 106) -- #D9776A — NOT HudKit.COLOR.Bad (190,90,75)
local COLOR_BUTTON_DARK = Color3.fromRGB(40, 35, 31) -- #28231F (SELL / LEAVE SHOP chrome)

-- Card.dc.html's RARITY table: color is exact-equal to ModConfig.Rarities[x].Color (verified against
-- source), which is why RunBuffConfig.RarityColor is used for it below instead of a 4th hardcoded
-- table — one source for "what color is Epic" instead of two that can drift. Only the ALPHA values
-- (tint 14%, border 55%/55%/70%) aren't in any config, since they're a pure presentation choice with
-- nothing server-side to agree with.
local RARITY_TINT_TRANSPARENCY = 1 - 0.14 -- rgba(...,0.14) tint washes
local RARITY_BORDER_ALPHA = { Rare = 0.55, Epic = 0.55, Legendary = 0.70 }

-- rarityColor, tint-BackgroundTransparency, border-UIStroke-Transparency, level cap — everything a
-- card/pip/chip needs to paint one rarity, in one call so nothing re-derives (or mis-derives) the
-- alpha table above per callsite.
local function rarityLook(rarity: string): (Color3, number, number, number)
	local color = RunBuffConfig.RarityColor(rarity) or COLOR_MUTED
	local borderTransparency = 1 - (RARITY_BORDER_ALPHA[rarity] or 0.55)
	return color, RARITY_TINT_TRANSPARENCY, borderTransparency, RunBuffConfig.Cap(rarity) or 0
end

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

-- The Scrap "nut" glyph next to every price. `color` lets one glyph serve the header readout
-- (Accent), the affordable button (dark, on the orange fill) and the broke button (Bad) without
-- three separate icon instances in UiIcons.
local function buildScrapGlyph(parent: Instance, size: number, color: Color3, layoutOrder: number?)
	local image = new("ImageLabel", {
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Image = "",
		ImageColor3 = color,
		LayoutOrder = layoutOrder or 0,
		Parent = parent,
	})
	if not Hud.applyIcon(image, "RunScrap") then
		image.Visible = false
		warnMissingIconOnce("RunScrap")
		new("TextLabel", {
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			FontFace = FONT.MontserratExtraBold,
			Text = "S",
			TextColor3 = color,
			TextSize = size,
			LayoutOrder = layoutOrder or 0,
			Parent = parent,
		})
	end
	return image
end

----------------------------------------------------------------------
-- Pips — two builders. Cards get the full 5-state ramp from Card.dc.html's `renderVals`; the
-- equipment-slot bar gets the simpler 3-state ramp from Main.dc.html's `slot()` helper. Kept
-- separate rather than one parameterized function, because the two truly don't share a state count.
----------------------------------------------------------------------

local CARD_PIP_HEIGHT = 8
local CARD_PIP_GAP = 6
local SLOT_PIP_HEIGHT = 4
local SLOT_PIP_GAP = 4

-- fromLv/toLv/prevCap/cap are PreviewOffer's own fields (renamed here only for readability):
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

-- i<=lv: filled solid. i<=cap: outlined at the rarity's (alpha) border color. else: dashed, beyond
-- this item's current cap.
local function buildSlotPip(parent: Instance, width: number, layoutOrder: number, index: number, level: number, cap: number, rarityColor: Color3, borderTr: number)
	local pip = new("Frame", {
		Size = UDim2.fromOffset(width, SLOT_PIP_HEIGHT),
		LayoutOrder = layoutOrder,
		BackgroundTransparency = 1,
		Parent = parent,
	}, { corner(1) })

	if index <= level then
		pip.BackgroundColor3 = rarityColor
		pip.BackgroundTransparency = 0
	elseif index <= cap then
		local s = stroke(rarityColor, 1)
		s.Transparency = borderTr
		s.Parent = pip
	else
		Hud.dashedBox(pip, { width = math.floor(width), height = SLOT_PIP_HEIGHT, color = COLOR_LINE, thickness = 1 })
	end
	return pip
end

----------------------------------------------------------------------
-- The card — 240x392, Card.dc.html translated top to bottom. Built fresh every render (see
-- renderCards below) rather than mutated in place, same "clear + rebuild" convention
-- RaidClient.client.lua's own roomBody uses, since a card's whole SHAPE changes between an
-- Escape/oneUse layout and a leveled Perk/Gear layout.
----------------------------------------------------------------------

local CARD_WIDTH, CARD_HEIGHT = 240, 392
local CARD_PAD_X = 14 -- the name/effect/level blocks' left+right padding
local CARD_CONTENT_WIDTH = CARD_WIDTH - CARD_PAD_X * 2
local CARD_PIP_WIDTH = (CARD_CONTENT_WIDTH - CARD_PIP_GAP * 4) / 5
local CARD_BUTTON_HEIGHT = 44

local function buildCardButton(parent: Instance, offer, preview, run)
	local slotsFull = preview.Blocked == "SlotsFull"
	local affordable = (run.Scrap or 0) >= offer.Price
	local isBuyable = affordable and not slotsFull and not preview.Blocked

	local wrapper = new("Frame", {
		Size = UDim2.new(1, 0, 0, CARD_BUTTON_HEIGHT + 24),
		BackgroundTransparency = 1,
		LayoutOrder = 6,
		Parent = parent,
	}, { new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }) })

	local btn = new("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		AutoButtonColor = false,
		BackgroundColor3 = isBuyable and COLOR_ACCENT or COLOR_PANEL_BG,
		Text = "",
		Active = isBuyable,
		Parent = wrapper,
	}, { corner(6) })
	if not isBuyable then
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

	local textColor = isBuyable and COLOR_PANEL_BG or COLOR_BAD
	local labelText = if slotsFull then "SLOTS FULL" elseif affordable then ("BUY  %d"):format(offer.Price) else ("NEED %d"):format(offer.Price)

	if not slotsFull then
		buildScrapGlyph(row, 20, textColor, 1)
	end
	new("TextLabel", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
		FontFace = FONT.MontserratExtraBold,
		Text = labelText,
		TextColor3 = textColor,
		TextSize = 14,
		Parent = row,
	})

	if isBuyable then
		local restColor = COLOR_ACCENT
		btn.MouseEnter:Connect(function()
			btn.BackgroundColor3 = Hud.lighten(restColor, 0.1)
		end)
		btn.MouseLeave:Connect(function()
			btn.BackgroundColor3 = restColor
		end)
		btn.MouseButton1Click:Connect(function()
			RaidRoomAction:FireServer("Buy", offer.OfferId)
		end)
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
		table.insert(parts, ("<font color=\"%s\"><b>%s</b></font>"):format(colorHex(COLOR_GOOD), toText))
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

local function buildLevelSection(parent: Instance, item, preview, rarityColor: Color3, fillTr: number, borderTr: number)
	local wrapper = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 4, -- between nameWrapper (3) and the fill-spacer (5) in buildCard — see its comment
		Parent = parent,
	}, {
		new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, CARD_PAD_X), PaddingRight = UDim.new(0, CARD_PAD_X) }),
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 7) }),
	})

	if item.Kind == "Escape" then
		new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 16),
			LayoutOrder = 1,
			FontFace = FONT.InconsolataBold,
			Text = item.OneUse and "ONE USE" or "UNTIL THE RUN ENDS",
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
			Text = (item.Card and item.Card.Description) or "",
			TextColor3 = COLOR_MUTED,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = wrapper,
		})
		return
	end

	local levelText
	if preview.RarityUp then
		levelText = ("LV %d KEPT"):format(preview.ToLv)
	elseif preview.FromLv == 0 then
		levelText = "LV 1"
	else
		levelText = ("LV %d \226\134\146 %d"):format(preview.FromLv, preview.ToLv) -- "LV x → y"
	end
	local capText = if preview.RarityUp
		then ("MAX %d \226\134\146 %d"):format(preview.PrevCap, preview.NewCap)
		else ("MAX LV %d"):format(preview.NewCap)

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
		Text = levelText,
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
		Text = capText,
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
		buildCardPip(pipsRow, CARD_PIP_WIDTH, i, i, preview.FromLv, preview.ToLv, preview.PrevCap, preview.NewCap, rarityColor, fillTr, borderTr)
	end
end

local function buildCard(cardsRow: Instance, layoutOrder: number, offer, run)
	local item = RunBuffConfig.Items[offer.ItemKey]
	if not item then
		warn(("[RaidShopPanel] shop offer names an unknown item key %q — skipping this card"):format(tostring(offer.ItemKey)))
		return
	end

	local ownedEntry
	if item.Kind == "Escape" then
		ownedEntry = run.Escape[offer.ItemKey] and true or nil
	else
		ownedEntry = run.Owned[offer.ItemKey]
	end
	local preview = RunBuffConfig.PreviewOffer(ownedEntry, offer, run.SlotsUsed)
	local rarityColor, fillTr, borderTr = rarityLook(offer.Rarity)

	local card = new("Frame", {
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		BackgroundColor3 = COLOR_CARD_BG,
		ClipsDescendants = true,
		LayoutOrder = layoutOrder,
		Parent = cardsRow,
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
		Text = offer.Rarity:upper(),
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
		Text = item.Kind:upper(),
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
	buildIconPlate(iconBox, item.DisplayName, item.Icon, rarityColor, fillTr, borderTr)

	if preview.RarityUp or (preview.IsNew and item.Kind ~= "Escape") then
		local badgeText = preview.RarityUp and "RARITY UP" or "NEW"
		local badgeColor = preview.RarityUp and rarityColor or COLOR_ACCENT
		new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 8),
			Size = UDim2.new(0, 0, 0, 18),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = badgeColor,
			FontFace = FONT.MontserratExtraBold,
			Text = "  " .. badgeText .. "  ",
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
		Text = item.DisplayName,
		TextColor3 = COLOR_TEXT,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = nameWrapper,
	})

	local card_ = item.Card or {}
	local effectLabel = card_.Label or ""
	local effectFrom, effectTo = nil, nil
	if item.Kind == "Escape" then
		effectFrom = nil
	elseif preview.IsNew then
		effectFrom = RunBuffConfig.CardValue(offer.ItemKey, 1)
	elseif preview.RarityUp then
		effectFrom = RunBuffConfig.CardValue(offer.ItemKey, preview.FromLv)
	else
		effectFrom = RunBuffConfig.CardValue(offer.ItemKey, preview.FromLv)
		effectTo = RunBuffConfig.CardValue(offer.ItemKey, preview.ToLv)
	end
	buildEffectLine(nameWrapper, 2, effectLabel, effectFrom, effectTo)

	buildLevelSection(card, item, preview, rarityColor, fillTr, borderTr)

	-- Spacer with UIFlexItem.Fill — the UIListLayout equivalent of the mockup's `margin-top: auto`,
	-- pushing the button to the card's bottom edge regardless of how tall the sections above it are.
	new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		Parent = card,
	}, { new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }) })

	buildCardButton(card, offer, preview, run)
end

----------------------------------------------------------------------
-- The shop screen shell — Main.dc.html: a 1120-wide panel (header readouts, the 4-card row, the
-- equipment-slot bar and its footer). Built ONCE at require time; renderAll() below refreshes its
-- contents on every Open/Update rather than rebuilding the shell.
----------------------------------------------------------------------

local STAGE_WIDTH, STAGE_HEIGHT = 1280, 800 -- Main.dc.html's own preview canvas
local PANEL_WIDTH = 1120
local FOOTER_WIDTH = 1032 -- Main.dc.html's slot-bar/footer rows are narrower than the panel itself

-- The whole screen is designed at 1280 wide; UIScale shrinks it (never grows past 1) to fit
-- whatever the real viewport is, so the shop reads identically on any window size instead of
-- clipping off-screen on a laptop or a split view.
local stage = new("Frame", {
	Name = "RaidShopPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.fromOffset(STAGE_WIDTH, STAGE_HEIGHT),
	BackgroundColor3 = Color3.fromRGB(11, 9, 8), -- #0B0908, Main.dc.html's own body background
	BackgroundTransparency = 0.35, -- a scrim, not a full takeover — the raid room stays visible
		-- behind it, same "raised, dimmed" treatment HudKit.modal uses for every other popup in the
		-- HUD; the mockup's own solid #0B0908 was drawn as a standalone design-tool canvas, not as an
		-- instruction to black out the game world entirely.
	Visible = false,
	ZIndex = 5,
	Parent = Hud.screenGui,
})
local stageScale = new("UIScale", { Scale = 1, Parent = stage })

local function updateStageScale()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(STAGE_WIDTH, STAGE_HEIGHT)
	stageScale.Scale = math.min(1, viewport.X / STAGE_WIDTH, viewport.Y / STAGE_HEIGHT)
end
updateStageScale()
local function hookCamera()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateStageScale)
	end
end
hookCamera()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	hookCamera()
	updateStageScale()
end)

local panel = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, PANEL_WIDTH, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = COLOR_PANEL_BG,
	Parent = stage,
}, {
	corner(10),
	stroke(COLOR_LINE, 1),
	new("UIPadding", { PaddingTop = UDim.new(0, 24), PaddingBottom = UDim.new(0, 24), PaddingLeft = UDim.new(0, 28), PaddingRight = UDim.new(0, 28) }),
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 18) }),
})

----------------------------------------------------------------------
-- Header — SALVAGE EXCHANGE title + subtitle left, ORE AT RISK / SCRAP readouts right.
----------------------------------------------------------------------

local header = new("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	LayoutOrder = 1,
	Parent = panel,
})

local headerLeft = new("Frame", {
	Size = UDim2.new(0.6, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = header,
}, { new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }) })

local eyebrowRow = new("Frame", {
	Size = UDim2.new(1, 0, 0, 12),
	BackgroundTransparency = 1,
	LayoutOrder = 1,
	Parent = headerLeft,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10) }) })
new("Frame", {
	Size = UDim2.fromOffset(8, 8),
	BackgroundColor3 = COLOR_ACCENT,
	LayoutOrder = 1,
	Parent = eyebrowRow,
}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
new("TextLabel", {
	Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	FontFace = FONT.InconsolataBold,
	Text = "SHOP NODE \194\183 STOCK ROLLED FOR THIS VISIT", -- "SHOP NODE · STOCK ROLLED FOR THIS VISIT"
	TextColor3 = COLOR_MUTED,
	TextSize = 12,
	LayoutOrder = 2,
	Parent = eyebrowRow,
})
new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundTransparency = 1,
	FontFace = FONT.MontserratExtraBold,
	Text = "SALVAGE EXCHANGE",
	TextColor3 = COLOR_TEXT,
	TextSize = 28,
	TextXAlignment = Enum.TextXAlignment.Left,
	LayoutOrder = 2,
	Parent = headerLeft,
})
new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 18),
	BackgroundTransparency = 1,
	FontFace = FONT.SourceSansRegular,
	Text = "Perks and gear last until this run ends.",
	TextColor3 = COLOR_MUTED,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	LayoutOrder = 3,
	Parent = headerLeft,
})

local headerRight = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.new(0, 0, 0, 46),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Parent = header,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) }) })

local function readoutBox(labelText: string, layoutOrder: number)
	local box = new("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = COLOR_CARD_BG,
		LayoutOrder = layoutOrder,
		Parent = headerRight,
	}, {
		corner(6),
		stroke(COLOR_LINE, 1),
		new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 2) }),
	})
	new("TextLabel", {
		Size = UDim2.new(0, 0, 0, 12),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = FONT.InconsolataBold,
		Text = labelText,
		TextColor3 = COLOR_MUTED,
		TextSize = 11,
		LayoutOrder = 1,
		Parent = box,
	})
	return box
end

local oreBox = readoutBox("ORE AT RISK", 1)
local oreValue = new("TextLabel", {
	Size = UDim2.new(0, 0, 0, 22),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	FontFace = FONT.InconsolataBold,
	Text = "0",
	TextColor3 = COLOR_BAD,
	TextSize = 20,
	LayoutOrder = 2,
	Parent = oreBox,
})

local scrapBox = readoutBox("SCRAP", 2)
local scrapRow = new("Frame", {
	Size = UDim2.new(0, 0, 0, 22),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	LayoutOrder = 2,
	Parent = scrapBox,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6) }) })
buildScrapGlyph(scrapRow, 20, COLOR_ACCENT, 1)
local scrapValue = new("TextLabel", {
	Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	FontFace = FONT.InconsolataBold,
	Text = "0",
	TextColor3 = COLOR_TEXT,
	TextSize = 20,
	LayoutOrder = 2,
	Parent = scrapRow,
})

----------------------------------------------------------------------
-- Cards row.
----------------------------------------------------------------------

local cardsRow = new("Frame", {
	Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
	BackgroundTransparency = 1,
	LayoutOrder = 2,
	Parent = panel,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 24) }) })

----------------------------------------------------------------------
-- Footer — a 1px top rule, then the equipment-slot bar + the NO SLOT escape row + LEAVE SHOP.
----------------------------------------------------------------------

local footerOuter = new("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	LayoutOrder = 3,
	Parent = panel,
}, { new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 0) }) })
new("Frame", {
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = COLOR_LINE,
	BorderSizePixel = 0,
	LayoutOrder = 1,
	Parent = footerOuter,
})
local footerInner = new("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	LayoutOrder = 2,
	Parent = footerOuter,
}, {
	new("UIPadding", { PaddingTop = UDim.new(0, 14) }),
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
})

local slotHeaderRow = new("Frame", {
	Size = UDim2.new(0, FOOTER_WIDTH, 0, 16),
	BackgroundTransparency = 1,
	LayoutOrder = 1,
	Parent = footerInner,
})
slotHeaderRow.AnchorPoint = Vector2.new(0.5, 0)
slotHeaderRow.Position = UDim2.new(0.5, 0, 0, 0)
local slotCountLabel = new("TextLabel", {
	Size = UDim2.new(0.6, 0, 1, 0),
	BackgroundTransparency = 1,
	RichText = true,
	FontFace = FONT.InconsolataBold,
	Text = "EQUIPMENT SLOTS 0/4",
	TextColor3 = COLOR_MUTED,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = slotHeaderRow,
})
new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.new(0.6, 0, 1, 0),
	BackgroundTransparency = 1,
	FontFace = FONT.InconsolataMedium,
	Text = ("SELL REFUNDS %d%% \194\183 ENDS WITH THE RUN"):format(math.floor(RunBuffConfig.SellRefund * 100 + 0.5)),
	TextColor3 = COLOR_MUTED,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = slotHeaderRow,
})

local slotsRow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(0, FOOTER_WIDTH, 0, 60),
	BackgroundTransparency = 1,
	LayoutOrder = 2,
	Parent = footerInner,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 24) }) })

local noSlotRow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(0, FOOTER_WIDTH, 0, 44),
	BackgroundTransparency = 1,
	LayoutOrder = 3,
	Parent = footerInner,
})
local noSlotLeft = new("Frame", {
	Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Parent = noSlotRow,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10) }) })
new("TextLabel", {
	Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	FontFace = FONT.InconsolataBold,
	Text = "NO SLOT",
	TextColor3 = COLOR_MUTED,
	TextSize = 12,
	LayoutOrder = 1,
	Parent = noSlotLeft,
})
local escapeChipsRow = new("Frame", {
	Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	LayoutOrder = 2,
	Parent = noSlotLeft,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }) })

local leaveShopButton = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.new(0, 0, 0, 44),
	AutomaticSize = Enum.AutomaticSize.X,
	AutoButtonColor = false,
	BackgroundColor3 = COLOR_BUTTON_DARK,
	Text = "",
	Parent = noSlotRow,
}, {
	corner(6),
	stroke(COLOR_LINE, 1),
	new("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) }),
})
new("TextLabel", {
	Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	FontFace = FONT.MontserratBold,
	Text = "LEAVE SHOP",
	TextColor3 = COLOR_TEXT,
	TextSize = 14,
	Parent = leaveShopButton,
})
leaveShopButton.MouseEnter:Connect(function()
	leaveShopButton.BackgroundColor3 = Hud.lighten(COLOR_BUTTON_DARK, 0.08)
end)
leaveShopButton.MouseLeave:Connect(function()
	leaveShopButton.BackgroundColor3 = COLOR_BUTTON_DARK
end)
leaveShopButton.MouseButton1Click:Connect(function()
	RaidRoomAction:FireServer("Continue")
	RaidShopPanel.Close()
end)

----------------------------------------------------------------------
-- Slot tiles — filled (name/rarity/level + pips + SELL) or the dashed EMPTY SLOT placeholder.
----------------------------------------------------------------------

local SLOT_TILE_WIDTH, SLOT_TILE_HEIGHT = 240, 60
local SLOT_LEFT_WIDTH = SLOT_TILE_WIDTH - 12 - 8 - 10 - 60 -- pad-left, pad-right, gap, SELL button
local SLOT_PIP_WIDTH = (SLOT_LEFT_WIDTH - SLOT_PIP_GAP * 4) / 5

local function buildEmptySlot(order: number)
	local tile = new("Frame", {
		Size = UDim2.fromOffset(SLOT_TILE_WIDTH, SLOT_TILE_HEIGHT),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = slotsRow,
	})
	Hud.dashedBox(tile, { width = SLOT_TILE_WIDTH, height = SLOT_TILE_HEIGHT, color = COLOR_LINE, thickness = 1, cornerInset = 8 })
	new("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		FontFace = FONT.InconsolataBold,
		Text = "EMPTY SLOT",
		TextColor3 = COLOR_MUTED,
		TextSize = 12,
		Parent = tile,
	})
end

local function buildFilledSlot(order: number, itemKey: string, owned)
	local item = RunBuffConfig.Items[itemKey]
	if not item then
		return
	end
	local rarityColor, _fillTr, borderTr, cap = rarityLook(owned.Rarity)

	local tile = new("Frame", {
		Size = UDim2.fromOffset(SLOT_TILE_WIDTH, SLOT_TILE_HEIGHT),
		BackgroundColor3 = COLOR_CARD_BG,
		LayoutOrder = order,
		Parent = slotsRow,
	}, {
		corner(8),
		new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 8) }),
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10) }),
	})
	local outline = stroke(rarityColor, 1)
	outline.Transparency = borderTr
	outline.Parent = tile

	local left = new("Frame", {
		Size = UDim2.new(1, -70, 1, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = tile,
	}, { new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5) }) })
	local nameRow = new("Frame", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = left,
	})
	new("TextLabel", {
		Size = UDim2.new(0.6, 0, 1, 0),
		BackgroundTransparency = 1,
		FontFace = FONT.MontserratBold,
		Text = item.DisplayName,
		TextColor3 = COLOR_TEXT,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = nameRow,
	})
	new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.4, 0, 1, 0),
		BackgroundTransparency = 1,
		FontFace = FONT.InconsolataBold,
		Text = ("%s \194\183 LV %d"):format(owned.Rarity:upper(), owned.Level), -- "RARITY · LV n"
		TextColor3 = rarityColor,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = nameRow,
	})
	local pipsRow = new("Frame", {
		Size = UDim2.new(1, 0, 0, SLOT_PIP_HEIGHT),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = left,
	}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, SLOT_PIP_GAP) }) })
	for i = 1, 5 do
		buildSlotPip(pipsRow, SLOT_PIP_WIDTH, i, i, owned.Level, cap, rarityColor, borderTr)
	end

	local refund = math.floor((owned.Paid or 0) * RunBuffConfig.SellRefund)
	local sellButton = new("TextButton", {
		Size = UDim2.fromOffset(60, 44),
		AutoButtonColor = false,
		BackgroundColor3 = COLOR_BUTTON_DARK,
		Text = "",
		LayoutOrder = 2,
		Parent = tile,
	}, { corner(6), stroke(COLOR_LINE, 1), new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 1) }) })
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		FontFace = FONT.MontserratBold,
		Text = "SELL",
		TextColor3 = COLOR_TEXT,
		TextSize = 11,
		LayoutOrder = 1,
		Parent = sellButton,
	})
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		FontFace = FONT.InconsolataBold,
		Text = "+" .. tostring(refund),
		TextColor3 = COLOR_GOOD,
		TextSize = 12,
		LayoutOrder = 2,
		Parent = sellButton,
	})
	sellButton.MouseEnter:Connect(function()
		sellButton.BackgroundColor3 = Hud.lighten(COLOR_BUTTON_DARK, 0.08)
	end)
	sellButton.MouseLeave:Connect(function()
		sellButton.BackgroundColor3 = COLOR_BUTTON_DARK
	end)
	sellButton.MouseButton1Click:Connect(function()
		RaidRoomAction:FireServer("Sell", itemKey)
	end)
end

----------------------------------------------------------------------
-- Escape chips ("NO SLOT" row) — one per held Escape item. Only Epic-rarity items can be Escape
-- (RunBuffConfig.Items' Rarities), so `item.Rarities[1]` is always "Epic" here — read off the
-- config rather than hardcoded, so a future non-Epic escape item colors itself correctly for free.
----------------------------------------------------------------------

local function buildEscapeChip(itemKey: string)
	local item = RunBuffConfig.Items[itemKey]
	if not item then
		return
	end
	local rarityColor = rarityLook(item.Rarities[1])
	local chip = new("Frame", {
		Size = UDim2.new(0, 0, 0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = COLOR_CARD_BG,
		Parent = escapeChipsRow,
	}, {
		corner(6),
		stroke(COLOR_LINE, 1),
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8) }),
	})
	new("Frame", {
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = rarityColor,
		LayoutOrder = 1,
		Parent = chip,
	}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	new("TextLabel", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = FONT.SourceSansSemiBold,
		Text = item.DisplayName,
		TextColor3 = COLOR_TEXT,
		TextSize = 14,
		LayoutOrder = 2,
		Parent = chip,
	})
	local statusText
	if itemKey == "SalvageInsurance" then
		statusText = ("KEEP %d%% ORE"):format(math.floor((item.KeepOrePct or 0) * 100 + 0.5))
	else
		statusText = "READY"
	end
	new("TextLabel", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = FONT.InconsolataBold,
		Text = statusText,
		TextColor3 = rarityColor,
		TextSize = 12,
		LayoutOrder = 3,
		Parent = chip,
	})
end

----------------------------------------------------------------------
-- Render — rebuilds every dynamic piece from the module's current (offers, run) state. Clear +
-- rebuild throughout, same convention as RaidClient.client.lua's clearRoomBody(): the shapes
-- involved (how many cards, which slots are filled, how many escape chips) change too much between
-- renders to make targeted mutation worth the bookkeeping.
----------------------------------------------------------------------

local currentOffers = {}
local currentRun = { Owned = {}, Escape = {}, SlotsUsed = 0, Slots = RunBuffConfig.Slots, Scrap = 0, OreAtRisk = 0 }

local function renderHeader()
	oreValue.Text = tostring(currentRun.OreAtRisk or 0)
	scrapValue.Text = tostring(currentRun.Scrap or 0)
	slotCountLabel.Text = ("EQUIPMENT SLOTS <font color=\"%s\">%d/%d</font>"):format(
		colorHex(COLOR_TEXT), currentRun.SlotsUsed or 0, currentRun.Slots or RunBuffConfig.Slots)
	slotCountLabel.RichText = true
end

local function renderCards()
	for _, child in ipairs(cardsRow:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, offer in ipairs(currentOffers) do
		buildCard(cardsRow, i, offer, currentRun)
	end
end

local function renderSlots()
	for _, child in ipairs(slotsRow:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local keys = {}
	for itemKey in pairs(currentRun.Owned or {}) do
		table.insert(keys, itemKey)
	end
	table.sort(keys) -- stable order run to run; the server doesn't track acquisition order to sort by
	local order = 0
	for _, itemKey in ipairs(keys) do
		order += 1
		buildFilledSlot(order, itemKey, currentRun.Owned[itemKey])
	end
	local totalSlots = currentRun.Slots or RunBuffConfig.Slots
	for _ = order + 1, totalSlots do
		order += 1
		buildEmptySlot(order)
	end
end

local function renderEscapeChips()
	for _, child in ipairs(escapeChipsRow:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local keys = {}
	for itemKey, held in pairs(currentRun.Escape or {}) do
		if held then
			table.insert(keys, itemKey)
		end
	end
	table.sort(keys)
	for _, itemKey in ipairs(keys) do
		buildEscapeChip(itemKey)
	end
	-- noSlotRow also carries LEAVE SHOP, which must stay up even with nothing held — only the NO
	-- SLOT label + chips half (noSlotLeft) hides when the player holds no Escape item.
	noSlotLeft.Visible = #keys > 0
end

local function renderAll()
	renderHeader()
	renderCards()
	renderSlots()
	renderEscapeChips()
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

-- A fresh "ShopOffers" status (RaidRoomService.revealShop) — first look at this node's rolled
-- stock, or a re-look if the player left the map open and came back (see RaidRoomService's own
-- comment on why re-entering the same Shop shows the same offers).
function RaidShopPanel.Open(payload)
	currentOffers = payload.Offers or {}
	currentRun = payload.Run or currentRun
	Hud.openPanel(stage, { onClose = RaidShopPanel.Close })
	renderAll()
end

-- A "ShopResult" (a Buy/Sell outcome) or "RunBuffs" (anything else that moved Scrap/ore-at-risk
-- while this node is open, e.g. a chest opened mid-detour) update. Re-renders only if the panel is
-- actually showing — `currentRun`/`currentOffers` are still kept fresh either way, so a re-open
-- later never shows stale numbers.
function RaidShopPanel.Update(payload)
	if payload.Status == "ShopResult" then
		if not payload.Success then
			Hud.showFailure("Raid Shop", payload.Reason)
			return
		end
		currentOffers = payload.Offers or currentOffers
		currentRun = payload.Run or currentRun
	elseif payload.Status == "RunBuffs" then
		currentRun = payload.Run or currentRun
	else
		return
	end
	if stage.Visible then
		renderAll()
	end
end

function RaidShopPanel.Close()
	Hud.closePanel(stage)
end

-- The latest Run snapshot this panel has seen, for RaidClient's own "USE BEACON" button (which must
-- work anywhere in the raid, not only while this panel is open) to read without RaidClient keeping a
-- second copy of the same state.
function RaidShopPanel.GetRun()
	return currentRun
end

return RaidShopPanel
