--[[
	RaidShopPanel.lua
	The Salvage Run raid shop — DESIGN_NOTES.md's "Raid shop rework — BUILD CONTRACT", step 4
	(client). The user approved a mockup and asked to be "100% loyal" to it: this file is a literal
	pixel translation of `design/raid-shop/Card.dc.html` (one card, 240x392) and
	`design/raid-shop/Main.dc.html` (the 1120-wide shop screen + equipment-slot bar), with
	`SlotsFull.dc.html` covering the "4/4 slots" state. Every size/color/font/border below has a
	comment pointing at the CSS rule it came from — if a number here looks odd, that's the reason
	before assuming it's a typo.

	THE CARD ITSELF now lives in RunCard.lua, not here. It was extracted so the post-boss reward
	pick (RaidClient.client.lua) could reuse the exact same 240x392 card the user approved, instead
	of drifting into a second hand-rolled design next to it. This file kept its own fonts/colors/
	rarityLook/scrap-glyph LOCAL NAMES (`FONT`, `COLOR_TEXT`, `rarityLook`, `buildScrapGlyph`, ...)
	by aliasing them straight to `RunCard`'s exports at the top of each section below, so nothing in
	the shell code (header readouts, the equipment-slot bar, the escape-item chips) needed to be
	retyped — only the card-building functions themselves actually left.

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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RunBuffConfig = require(ReplicatedStorage.Shared.RunBuffConfig)

local Hud = require(script.Parent.HudKit)
local RunCard = require(script.Parent.RunCard) -- the 240x392 card itself, and the fonts/colors/
	-- rarityLook/scrap-glyph it carries out with it — see this file's header.

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

-- Aliased from RunCard rather than redefined — see this file's header. Everything below this line
-- refers to these exactly as it always has.
local colorHex = RunCard.colorHex
local rarityLook = RunCard.rarityLook
local buildScrapGlyph = RunCard.buildScrapGlyph
local FONT = RunCard.FONT

local COLOR_PANEL_BG = RunCard.COLOR_PANEL_BG
local COLOR_CARD_BG = RunCard.COLOR_CARD_BG
local COLOR_LINE = RunCard.COLOR_LINE
local COLOR_TEXT = RunCard.COLOR_TEXT
local COLOR_MUTED = RunCard.COLOR_MUTED
local COLOR_ACCENT = RunCard.COLOR_ACCENT
local COLOR_GOOD = RunCard.COLOR_GOOD
local COLOR_BAD = RunCard.COLOR_BAD
local COLOR_BUTTON_DARK = RunCard.COLOR_BUTTON_DARK

local CARD_HEIGHT = RunCard.CARD_HEIGHT

----------------------------------------------------------------------
-- The card wrapper — resolves a shop OFFER (offer.ItemKey/Rarity/Price + the run's owned/escape
-- state) into RunCard.build's generic opts shape. All the RunBuffConfig-specific logic (what's
-- owned, what a purchase would grant, whether it's affordable) stays here; RunCard itself never
-- sees an `offer` or a `run`, only plain strings/numbers/callbacks.
----------------------------------------------------------------------

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

	local badge = nil
	if preview.RarityUp then
		badge = "RARITY UP"
	elseif preview.IsNew and item.Kind ~= "Escape" then
		badge = "NEW"
	end

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

	-- Escape items show a bold ONE USE/UNTIL THE RUN ENDS caption + their description where a
	-- leveled item shows its level row + 5 pips — see RunCard.build's FootNote/Description vs.
	-- Pips/LevelText/CapText branch.
	local pips, levelText, capText, footNote, description = nil, nil, nil, nil, nil
	if item.Kind == "Escape" then
		footNote = item.OneUse and "ONE USE" or "UNTIL THE RUN ENDS"
		description = card_.Description or ""
	else
		pips = { FromLv = preview.FromLv, ToLv = preview.ToLv, PrevCap = preview.PrevCap, Cap = preview.NewCap }
		if preview.RarityUp then
			levelText = ("LV %d KEPT"):format(preview.ToLv)
		elseif preview.FromLv == 0 then
			levelText = "LV 1"
		else
			levelText = ("LV %d \226\134\146 %d"):format(preview.FromLv, preview.ToLv) -- "LV x → y"
		end
		capText = if preview.RarityUp
			then ("MAX %d \226\134\146 %d"):format(preview.PrevCap, preview.NewCap)
			else ("MAX LV %d"):format(preview.NewCap)
	end

	local slotsFull = preview.Blocked == "SlotsFull"
	local affordable = (run.Scrap or 0) >= offer.Price
	local isBuyable = affordable and not slotsFull and not preview.Blocked
	local buttonText = if slotsFull then "SLOTS FULL" elseif affordable then ("BUY  %d"):format(offer.Price) else ("NEED %d"):format(offer.Price)

	RunCard.build({
		Name = item.DisplayName,
		Kind = item.Kind,
		Rarity = offer.Rarity,
		IconKey = item.Icon,
		EffectLabel = effectLabel,
		EffectFrom = effectFrom,
		EffectTo = effectTo,
		Badge = badge,
		Pips = pips,
		LevelText = levelText,
		CapText = capText,
		FootNote = footNote,
		Description = description,
		LayoutOrder = layoutOrder,
		Parent = cardsRow,
		Button = {
			Text = buttonText,
			Variant = isBuyable and "buy" or "broke",
			Icon = (not slotsFull) and "RunScrap" or nil,
			OnClick = isBuyable and function()
				RaidRoomAction:FireServer("Buy", offer.OfferId)
			end or nil,
		},
	})
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
-- These are the equipment-slot bar's OWN 3-state pip ramp (Main.dc.html's `slot()` helper) — a
-- different chart with a different state count from the card's 5-state ramp, so it stays here
-- rather than moving into RunCard with the card.
----------------------------------------------------------------------

local SLOT_PIP_HEIGHT = 4
local SLOT_PIP_GAP = 4

local SLOT_TILE_WIDTH, SLOT_TILE_HEIGHT = 240, 60
local SLOT_LEFT_WIDTH = SLOT_TILE_WIDTH - 12 - 8 - 10 - 60 -- pad-left, pad-right, gap, SELL button
local SLOT_PIP_WIDTH = (SLOT_LEFT_WIDTH - SLOT_PIP_GAP * 4) / 5

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

-- Pool for both slot shapes (buildEmptySlot/buildFilledSlot below), reused in place instead of
-- destroyed-and-rebuilt on every render — renderAll() runs on every ShopResult/RunBuffs update,
-- which fires whenever ANY run value moves (Scrap, ore-at-risk, a mid-detour chest), so most calls
-- into renderSlots() don't actually change which slots are filled at all. Keyed "Filled:<itemKey>"
-- (an owned item's own natural identity) or "Empty:<gridPosition>" (empty slots have no identity of
-- their own, so a position-keyed slot is reused whenever that position is empty again — the common
-- case, since Buy/Sell only shifts empty-slot positions at the moment the filled count itself
-- changes, not on every render). A hide-sweep at the top of renderSlots() below hides whichever of
-- these aren't used this pass instead of destroying them.
local slotPool = {}

-- Rebuilds this filled slot's 5-pip row only when the owned Level or Rarity actually changed since
-- last render — buildSlotPip's solid/outlined/dashed ramp depends on nothing else, so every other
-- pass (LayoutOrder churn, a DIFFERENT item's Buy/Sell) leaves these 5 pip Frames untouched instead
-- of tearing down Hud.dashedBox's dash children for no reason.
local function refreshSlotPips(handle, owned, rarityColor: Color3, borderTr: number, cap: number)
	if handle.pipsLevel == owned.Level and handle.pipsRarity == owned.Rarity then
		return
	end
	for _, child in ipairs(handle.pipsRow:GetChildren()) do
		child:Destroy()
	end
	for i = 1, 5 do
		buildSlotPip(handle.pipsRow, SLOT_PIP_WIDTH, i, i, owned.Level, cap, rarityColor, borderTr)
	end
	handle.pipsLevel = owned.Level
	handle.pipsRarity = owned.Rarity
end

local function buildEmptySlot(order: number)
	local poolKey = "Empty:" .. order
	local handle = slotPool[poolKey]
	if not handle then
		-- Every property below is fixed content (no run data feeds this shape at all) — nothing here
		-- ever needs an update pass, only LayoutOrder/Visible on reuse (set unconditionally below).
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
		handle = { tile = tile }
		slotPool[poolKey] = handle
	end
	handle.tile.LayoutOrder = order
	handle.tile.Visible = true
end

local function buildFilledSlot(order: number, itemKey: string, owned)
	local item = RunBuffConfig.Items[itemKey]
	if not item then
		return
	end
	local rarityColor, _fillTr, borderTr, cap = rarityLook(owned.Rarity)
	local poolKey = "Filled:" .. itemKey
	local handle = slotPool[poolKey]

	if not handle then
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
		local rarityLevelLabel = new("TextLabel", {
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
		local refundLabel = new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			FontFace = FONT.InconsolataBold,
			Text = "+" .. tostring(refund),
			TextColor3 = COLOR_GOOD,
			TextSize = 12,
			LayoutOrder = 2,
			Parent = sellButton,
		})
		-- itemKey is fixed for the life of this poolKey (it's baked into the key itself), so this
		-- closure never needs to be reconnected on reuse — same reasoning as InventoryPanel's
		-- makeItemTile onSelect note.
		sellButton.MouseEnter:Connect(function()
			sellButton.BackgroundColor3 = Hud.lighten(COLOR_BUTTON_DARK, 0.08)
		end)
		sellButton.MouseLeave:Connect(function()
			sellButton.BackgroundColor3 = COLOR_BUTTON_DARK
		end)
		sellButton.MouseButton1Click:Connect(function()
			RaidRoomAction:FireServer("Sell", itemKey)
		end)

		handle = {
			tile = tile,
			outline = outline,
			rarityLevelLabel = rarityLevelLabel,
			pipsRow = pipsRow,
			refundLabel = refundLabel,
			pipsLevel = owned.Level,
			pipsRarity = owned.Rarity,
		}
		slotPool[poolKey] = handle
	else
		-- Reused: rarity/level can move out from under this itemKey on a RarityUp purchase, so every
		-- PER-RENDER value the creation branch above set gets reasserted here — item.DisplayName is
		-- the one exception, left untouched, because RunBuffConfig.Items[itemKey] is fixed config and
		-- itemKey itself is fixed by poolKey, so it can never actually change for this handle.
		handle.outline.Color = rarityColor
		handle.outline.Transparency = borderTr
		handle.rarityLevelLabel.Text = ("%s \194\183 LV %d"):format(owned.Rarity:upper(), owned.Level)
		handle.rarityLevelLabel.TextColor3 = rarityColor
		local refund = math.floor((owned.Paid or 0) * RunBuffConfig.SellRefund)
		handle.refundLabel.Text = "+" .. tostring(refund)
		refreshSlotPips(handle, owned, rarityColor, borderTr, cap)
	end

	-- Set on EVERY pass, create or reuse — see buildEmptySlot's matching comment above and
	-- InventoryPanel.makeItemTile's LayoutOrder note: a reused tile otherwise keeps stale ordering.
	handle.tile.LayoutOrder = order
	handle.tile.Visible = true
end

----------------------------------------------------------------------
-- Escape chips ("NO SLOT" row) — one per held Escape item. Only Epic-rarity items can be Escape
-- (RunBuffConfig.Items' Rarities), so `item.Rarities[1]` is always "Epic" here — read off the
-- config rather than hardcoded, so a future non-Epic escape item colors itself correctly for free.
----------------------------------------------------------------------

-- Pool keyed on itemKey alone (no prefix needed — separate table from slotPool). Every property a
-- chip shows (rarity dot color, display name, status caption) is derived purely from
-- RunBuffConfig.Items[itemKey], which never changes at runtime, so a pooled chip needs NOTHING
-- reasserted on reuse except LayoutOrder/Visible — see the `layoutOrder` param this gained below:
-- the original destroy-and-rebuild version never set LayoutOrder at all (escapeChipsRow's
-- UIListLayout ties on LayoutOrder=0 and falls back to insertion order, which happened to already
-- match sorted order because the whole row was torn down and reparented in that order every render).
-- Pooling breaks that implicit ordering — a reused chip's insertion position is wherever it was
-- FIRST built, not necessarily where the sorted list wants it this pass — so this now sets an
-- explicit LayoutOrder to keep the same left-to-right sorted result.
local escapeChipPool = {}

local function buildEscapeChip(itemKey: string, layoutOrder: number)
	local item = RunBuffConfig.Items[itemKey]
	if not item then
		return
	end
	local handle = escapeChipPool[itemKey]
	if not handle then
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
		handle = { chip = chip }
		escapeChipPool[itemKey] = handle
	end
	handle.chip.LayoutOrder = layoutOrder
	handle.chip.Visible = true
end

----------------------------------------------------------------------
-- Render — refreshes every dynamic piece from the module's current (offers, run) state. Runs on
-- every ShopResult/RunBuffs update (RaidShopPanel.Update below), which fires whenever ANY run value
-- moves, not just when THIS piece's data changed — so renderSlots/renderEscapeChips pool and reuse
-- their rows (see slotPool/escapeChipPool above) rather than tearing the whole grid down every tick.
-- renderCards still clears + rebuilds, same convention as RaidClient.client.lua's clearRoomBody() —
-- see its own comment just above for why that one stayed unpooled.
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

-- NOT pooled, unlike renderSlots/renderEscapeChips below — left destroying-and-rebuilding on
-- purpose. RunCard.build (RunCard.lua) is a single monolithic constructor with several conditional
-- STRUCTURAL branches (Badge present or not, Pips vs. FootNote/Description, an icon image vs. the
-- tinted-initials fallback, an active vs. "broke" footer button) and no handle/update API of its
-- own — giving it one, safely, without risking the pixel-exact card the user approved, would mean
-- restructuring the shared builder itself. That builder is also called directly by
-- RaidClient.client.lua's boss-pick screen, so a mistake here would silently break a second, unrelated
-- caller. That's a materially bigger and riskier change than this pass's brief, and cards refresh at
-- most 4-wide per shop visit — the cost renderSlots/renderEscapeChips actually needed to fix (a
-- whole grid destroyed on every Scrap/ore/slot tick) is far smaller here.
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
	for _, handle in pairs(slotPool) do
		handle.tile.Visible = false
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
	for _, handle in pairs(escapeChipPool) do
		handle.chip.Visible = false
	end
	local keys = {}
	for itemKey, held in pairs(currentRun.Escape or {}) do
		if held then
			table.insert(keys, itemKey)
		end
	end
	table.sort(keys)
	for index, itemKey in ipairs(keys) do
		buildEscapeChip(itemKey, index)
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
