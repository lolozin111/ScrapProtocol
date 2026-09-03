--[[
	RaidClient.client.lua
	Client for the instanced Raid Rooms system (RaidRoomService.lua/RaidConfig.lua) — a "Start Raid"
	button, the docked Sector Map, and a small in-room status panel for whichever node type is
	currently active.

	THE MAP IS NO LONGER THE CONTROL. It began as a centred overlay you clicked a circle on to pick
	the next room ("not pretty pretty, but like smth with circles... and those lines path connecting
	each other"). Choosing a path is a physical act in the world now — a cleared room unlocks
	ExitDoor Parts and you walk through the one you want (RaidConfig.ExitDoorName,
	RaidRoomService.unlockExitDoors) — so the map became a permanent read-only readout docked to the
	right: where you are, where you have been, what is reachable. It still accepts a click in exactly
	one case, when the server sets AllowNodeClick because a room did not have enough doors built for
	the branches it owed; that is the never-strand-a-run fallback.

	Deliberately its OWN ScreenGui/file rather than bolted onto MainHud.client.lua — that file is
	already a large, single-purpose debug HUD for the base-building loop; this is a separate system
	end to end (own remotes, own server file, own state), so it gets its own small client too. Same
	undecorated, Instance.new-through-Rojo style MainHud.client.lua itself calls out in its header.
	The Sector Map is the one part of this file that HAS had its reskin: it is on HudKit's angular
	plate with a backdrop art slot, since it is now on screen for the whole raid rather than for the
	few seconds a choice was open.

	Still no per-node icons (per the design ask — "for now just text to describe what will the next
	one be"). Node type is carried by colour plus the legend, and only the current node and the ones
	reachable from it are labelled — at minimap scale, labelling all ~18 would be a wall of
	overlapping type, and the map is for orienting rather than for reciting the graph.

	Maps chapter now (RaidRoomService.onMapCleared) — reaching a map's dead end regenerates a fresh
	one instead of ending the raid, so an Extract button (bottom-right, above Abandon) is the actual
	"leave and bank everything" action, enabled only after the first chapter's cleared. Ambush nodes
	reuse the same Combat sub-panel, just labeled with a Wave X/Y prefix (see AmbushStart/Tick/End/
	WaveCleared below) since they're several RunRaidCombat calls back to back instead of one.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RaidConfig = require(ReplicatedStorage.Shared.RaidConfig)
local Hud = require(script.Parent.HudKit) -- the Start Raid button (see its own comment), plus the
	-- Sector Map's angular shell (plate/accentCap/CORNER_CUT), its backdrop lookup (applyIcon) and
	-- darken(). Still NOT a general migration: this file keeps its own COLOR/new/corner/stroke
	-- helpers, and the room panel and toasts are untouched — HudKit is reached for where the map
	-- would otherwise have hand-rolled a second copy of chrome the rest of the HUD already has.

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestStartRaid = Remotes.RequestStartRaid
local RaidMapUpdate = Remotes.RaidMapUpdate
local ChooseRaidNode = Remotes.ChooseRaidNode
local RaidRoomUpdate = Remotes.RaidRoomUpdate
local RaidRoomAction = Remotes.RaidRoomAction
local AbandonRaid = Remotes.AbandonRaid
local RequestExtractRaid = Remotes.RequestExtractRaid

local LocalPlayer = Players.LocalPlayer

-- Same rust/gunmetal family MainHud.client.lua uses, so this reads as the same game even though
-- it's a separate file — see that file's own COLOR table.
local COLOR = {
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

----------------------------------------------------------------------
-- Small UI helpers — same shape as MainHud.client.lua's (duplicated, not shared, since these two
-- files are meant to stay independently readable — see this file's header)
----------------------------------------------------------------------

local function new(className, props, children)
	local inst = Instance.new(className)
	for key, value in pairs(props or {}) do
		inst[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	return inst
end

local function corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

local function circleCorner()
	return new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

local function stroke(color, thickness)
	return new("UIStroke", { Color = color or COLOR.Line, Thickness = thickness or 1 })
end

----------------------------------------------------------------------
-- Screen setup
----------------------------------------------------------------------

local screenGui = new("ScreenGui", {
	Name = "RaidGui",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = LocalPlayer:WaitForChild("PlayerGui"),
})

----------------------------------------------------------------------
-- Start Raid button (top-right) — the only physical/UI entry point for now, no world portal built
-- yet (per the design ask, "for now just make it that the player teleports somewhere"). Hidden
-- once a raid is active; reappears the moment the raid ends, one way or another.
----------------------------------------------------------------------

-- variant = "secondary", not "primary": Start Defense (MainHud's action row) is the one loud
-- accent-filled action on screen, and two competing orange buttons in opposite corners would read
-- as two equally primary choices. This is the LAST rounded, feedback-less button left in the HUD
-- (confirmed by a Studio screenshot) — everything else has already moved to HudKit's angular
-- 9-slice + hover/press treatment, so this one button is pulled onto it now even though the rest
-- of this file deliberately has not (see the header: the raid loop gets reskinned wholesale later).
-- Still parented to THIS file's own screenGui, not Hud.screenGui — the two ScreenGuis are kept
-- separate on purpose (see header) and this button's layering is against the raid map GUI below,
-- not MainHud's panels.
local startButton = Hud.button({
	text = "Start Raid",
	variant = "secondary",
	position = UDim2.new(1, -16, 0, 16),
	anchorPoint = Vector2.new(1, 0),
	size = UDim2.new(0, 150, 0, 40),
	parent = screenGui,
	onClick = function()
		RequestStartRaid:FireServer()
	end,
})
startButton.Name = "StartRaidButton"

----------------------------------------------------------------------
-- "Scraps Collected" panel (top-left) — this RAID's own live currency pool, visible only while a
-- raid is active. "Have a thing called on the GUI only when the raid is being run, called scraps
-- collected, so on the shop you are only able to purchase stuff with the scraps collected through
-- the entire run, instead of the scraps that you currently have as a player, in your base." Updated
-- from RaidRoomUpdate's "RunCurrencyUpdate" status (see below) — reset to 0/0 display on every
-- fresh "Entered" of a Start node (a new raid beginning) so a stale number from a previous raid
-- never briefly shows.
----------------------------------------------------------------------

local runCurrencyLabel = new("TextLabel", {
	Name = "RunCurrencyPanel",
	BackgroundColor3 = COLOR.Panel,
	Position = UDim2.new(0, 16, 0, 16),
	Size = UDim2.new(0, 220, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Visible = false,
	Font = Enum.Font.SourceSans,
	Text = "Scraps Collected: 0",
	TextColor3 = COLOR.Text,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
	Parent = screenGui,
}, { corner(6), stroke(), new("UIPadding", {
	PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
}) })

local function updateRunCurrencyLabel(runCurrencyCollected)
	local scrap = (runCurrencyCollected and runCurrencyCollected.Scrap) or 0
	local cores = (runCurrencyCollected and runCurrencyCollected.Cores) or 0
	if cores > 0 then
		runCurrencyLabel.Text = ("Scraps Collected: %d\nCores Collected: %d"):format(scrap, cores)
	else
		runCurrencyLabel.Text = ("Scraps Collected: %d"):format(scrap)
	end
end

----------------------------------------------------------------------
-- Toast — a small auto-dismissing message for one-off events (no energy, defeated, extracted,
-- abandoned) that don't need a persistent panel of their own.
----------------------------------------------------------------------

local toastLabel = new("TextLabel", {
	Name = "Toast",
	BackgroundColor3 = COLOR.Panel,
	Position = UDim2.new(0.5, 0, 0, 70),
	AnchorPoint = Vector2.new(0.5, 0),
	Size = UDim2.new(0, 420, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Visible = false,
	Font = Enum.Font.SourceSans,
	Text = "",
	TextColor3 = COLOR.Text,
	TextSize = 16,
	TextWrapped = true,
	Parent = screenGui,
}, { corner(6), stroke(), new("UIPadding", {
	PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
}) })

local toastToken = 0
local function showToast(text: string, seconds: number?)
	toastToken += 1
	local myToken = toastToken
	toastLabel.Text = text
	toastLabel.Visible = true
	task.delay(seconds or 4, function()
		if toastToken == myToken then
			toastLabel.Visible = false
		end
	end)
end

----------------------------------------------------------------------
-- "Go Back To Base" button (top-center) — a renamed, repositioned Abandon Raid: visible ONLY while
-- the branching map GUI (mapFrame) is actually open, not just "whenever a raid is active and not
-- mid-Combat" like it used to be. That's deliberate, not just cosmetic — "make sure that in the map
-- there is button that says back to home... but only when the node map is open, so they cant just
-- quit while doing a raid": with this gate, there's no way to bail out mid-Heal/mid-Shop/mid-Combat
-- at all anymore, only at the exact moment a map choice is showing. Sits outside mapFrame itself
-- ("doesnt need to be inside the map GUI, just a button that appears on the top of the screen") so
-- it stays visually distinct from the map panel's own contents.
--
-- Extract Raid button keeps its original bottom-right spot and its original visibility rule
-- (visible whenever a raid is active and not mid-Combat, once state.ExtractUnlocked flips true) —
-- unlike Go Back To Base, extracting isn't the "quit early and lose this chapter's progress" action
-- the user was worried about, so it wasn't restricted to map-open-only.
----------------------------------------------------------------------

local backToBaseButton = new("TextButton", {
	Name = "BackToBaseButton",
	BackgroundColor3 = COLOR.Bad,
	Position = UDim2.new(0.5, 0, 0, 16),
	AnchorPoint = Vector2.new(0.5, 0),
	Size = UDim2.new(0, 190, 0, 36),
	Font = Enum.Font.SourceSansBold,
	Text = "Go Back To Base",
	TextColor3 = COLOR.Text,
	TextSize = 16,
	Visible = false,
	Parent = screenGui,
}, { corner(6) })

backToBaseButton.MouseButton1Click:Connect(function()
	AbandonRaid:FireServer()
end)

local extractButton = new("TextButton", {
	Name = "ExtractRaidButton",
	BackgroundColor3 = COLOR.Good,
	Position = UDim2.new(1, -16, 1, -16),
	AnchorPoint = Vector2.new(1, 1),
	Size = UDim2.new(0, 150, 0, 36),
	Font = Enum.Font.SourceSansBold,
	Text = "Extract",
	TextColor3 = COLOR.Text,
	TextSize = 16,
	Visible = false,
	Parent = screenGui,
}, { corner(6) })

extractButton.MouseButton1Click:Connect(function()
	RequestExtractRaid:FireServer()
end)

----------------------------------------------------------------------
-- Room panel (top-center) — status for whichever node the player is currently standing in.
-- Rebuilt (children cleared, re-added) every time its content genuinely changes shape (e.g.
-- switching from Heal's Continue button to Shop's catalog) rather than kept as one fixed layout,
-- since different node types need different controls.
----------------------------------------------------------------------

local roomFrame = new("Frame", {
	Name = "RoomPanel",
	BackgroundColor3 = COLOR.Panel,
	Position = UDim2.new(0.5, 0, 0, 70),
	AnchorPoint = Vector2.new(0.5, 0),
	Size = UDim2.new(0, 340, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Visible = false,
	Parent = screenGui,
}, { corner(8), stroke(), new("UIPadding", {
	PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
}), new("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 8),
}) })

local roomTitle = new("TextLabel", {
	Name = "Title",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 22),
	LayoutOrder = 1,
	Font = Enum.Font.SourceSansBold,
	Text = "",
	TextColor3 = COLOR.Text,
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = roomFrame,
})

-- A generic vertical body the per-type builders below fill in fresh each time — cleared via
-- ClearAllChildren() rather than tracked piecemeal, since the whole point is different node types
-- show completely different controls here.
local roomBody = new("Frame", {
	Name = "Body",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	LayoutOrder = 2,
	Parent = roomFrame,
}, { new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }) })

-- roomBody:ClearAllChildren() also destroys its own UIListLayout — that Layout is a CHILD of
-- roomBody, same as everything else added to it, so a plain ClearAllChildren() wipes it out right
-- along with the old content. Every rebuild after the very first one was then left with no layout
-- at all, so every caption/bar/button just stacked on top of each other at (0,0) instead of
-- flowing top-to-bottom — this is what read as "text overlapping." Route every clear through this
-- instead, which re-adds a fresh UIListLayout right after clearing.
local function clearRoomBody()
	roomBody:ClearAllChildren()
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }).Parent = roomBody
end

local function progressBar(order: number, label: string)
	local caption = new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = order,
		Font = Enum.Font.SourceSans,
		Text = label,
		TextColor3 = COLOR.Muted,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = roomBody,
	})
	local track = new("Frame", {
		BackgroundColor3 = COLOR.PanelLight,
		Size = UDim2.new(1, 0, 0, 10),
		LayoutOrder = order + 1,
		Parent = roomBody,
	}, { corner(4) })
	local fill = new("Frame", {
		BackgroundColor3 = COLOR.Good,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = track,
	}, { corner(4) })
	return caption, fill
end

local function actionButton(order: number, text: string, color: Color3, onClick: () -> ())
	local button = new("TextButton", {
		BackgroundColor3 = color,
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = order,
		Font = Enum.Font.SourceSansBold,
		Text = text,
		TextColor3 = COLOR.Text,
		TextSize = 16,
		Parent = roomBody,
	}, { corner(6) })
	button.MouseButton1Click:Connect(onClick)
	return button
end

-- Boss card-pick UI (RaidRoomService's "BossCleared" status carries the CardChoices RaidConfig
-- .RollCardChoices rolled). One button per card, colored by its Rarity (RaidConfig
-- .CardRarityColors) — "the cards have rarity, and the buff is connected to rarity." Placeholder
-- content only, same as the card system generally — see RaidConfig.lua's own comment.
local function renderCardChoices(order: number, cardChoices, onChoose: (string) -> ())
	for _, card in ipairs(cardChoices or {}) do
		local color = RaidConfig.CardRarityColors[card.Rarity] or COLOR.PanelLight
		order += 1
		local button = new("TextButton", {
			BackgroundColor3 = COLOR.PanelLight,
			Size = UDim2.new(1, 0, 0, 48),
			LayoutOrder = order,
			Font = Enum.Font.SourceSansBold,
			Text = "",
			Parent = roomBody,
		}, { corner(6), stroke(color, 2), new("UIPadding", {
			PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
		}) })
		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0, 4),
			Size = UDim2.new(1, 0, 0, 18),
			Font = Enum.Font.SourceSansBold,
			Text = ("%s — %s"):format(card.DisplayName, card.Rarity),
			TextColor3 = color,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = button,
		})
		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0, 24),
			Size = UDim2.new(1, 0, 0, 18),
			Font = Enum.Font.SourceSans,
			Text = card.Description or "",
			TextColor3 = COLOR.Muted,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = button,
		})
		button.MouseButton1Click:Connect(function()
			onChoose(card.Key)
		end)
	end
end

-- Forward-declared: redrawMap's per-node click handler below calls this (so Go Back To Base hides
-- the instant the map closes), but the actual definition lives further down alongside the other
-- button-visibility state (inRaid/inCombat/extractUnlocked) — same "declare early, define/assign
-- later" pattern RaidRoomService.lua's own `enterNode` forward-declaration uses, needed here because
-- Lua locals are only in scope from their declaration onward, not backward into earlier functions.
local updateRaidButtons

----------------------------------------------------------------------
-- Sector map — the raid's PERSISTENT minimap, docked right.
--
-- This used to be the raid's control surface: a big centred overlay that opened when a room
-- cleared, and you clicked a circle to pick where to go. That input moved into the world (see
-- RaidConfig.ExitDoorName and RaidRoomService.unlockExitDoors — a cleared room unlocks physical
-- doors and you walk through one), so this panel's whole job changed. It is now a READ-ONLY
-- orientation display that stays up for the entire raid: where you are, where you have been, what
-- is reachable from here, how deep the chapter goes.
--
-- It stays clickable in exactly ONE case: the server sets AllowNodeClick when a room did not have
-- enough ExitDoor Parts for the branches it needed to offer. That is the never-strand-a-run
-- fallback, and it is the reason this file still holds a ChooseRaidNode call at all.
--
-- The tree draws TOP-TO-BOTTOM here, not left-to-right like the old overlay: stage is Y and lane
-- is X. A docked panel is tall and narrow, and a map that can reach 14 stages deep has room to
-- descend but not to run sideways. The dendrogram's crossing-free guarantee is topological, not
-- axis-dependent, so swapping the two axes keeps it intact.
----------------------------------------------------------------------

local MAP_PANEL_SIZE = Vector2.new(384, 556)
local MAP_CANVAS_SIZE = Vector2.new(346, 424)

-- Node circles and spacing are computed fresh per map from however many stages/lanes THIS map
-- actually has, then clamped between these bounds — a short map fills the canvas, a deep one
-- shrinks to fit. Both sets are much tighter than the old centred overlay's, because 346x424 of
-- docked panel has to hold what 1050x460 of screen-filling overlay used to.
local MIN_STAGE_SPACING = 26
local MAX_STAGE_SPACING = 58
local MIN_LANE_SPACING = 32
local MAX_LANE_SPACING = 74
local MIN_NODE_DIAMETER = 14
local MAX_NODE_DIAMETER = 28
local CANVAS_MARGIN_X = 26
local CANVAS_MARGIN_Y = 24

-- Type here uses HudKit.FONT's tokens but NOT HudKit.TEXTSIZE's scale (13/16/20). That scale was
-- retuned upward for panels read at play distance; this is a docked minimap whose whole job is to
-- fit a 14-stage tree into 346x424, and at Body/16 the node labels overlap each other. Sizes below
-- are deliberately a step under the scale — the faces still match the rest of the HUD.
local MAP_HEADER_HEIGHT = 34
local MAP_BANNER_HEIGHT = 26
local MAP_LEGEND_HEIGHT = 22

-- Map-only palette. Kept local rather than pushed into COLOR above because every entry here is
-- about drawing a CHART — ink on a survey sheet — and none of it is reused by the room panel or
-- the buttons, which are ordinary HUD chrome.
local MAP = {
	Ground = Color3.fromRGB(22, 20, 18),
	Grid = Color3.fromRGB(52, 46, 40),
	Edge = Color3.fromRGB(84, 76, 66),
	EdgeWalked = Color3.fromRGB(196, 150, 96),
	Tick = Color3.fromRGB(120, 106, 90),
	Unvisited = Color3.fromRGB(96, 88, 78),
}

-- NOTE THE ORDER: HudKit.plate returns (surface, shell), surface first — the thing you parent
-- content into is what a caller almost always wants, and the shell is only needed afterwards to
-- move/resize/hide the panel as a whole. `props` above is applied to the SHELL.
local mapSurface, mapFrame = Hud.plate({
	Name = "SectorMap",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.5, -24),
	Size = UDim2.new(0, MAP_PANEL_SIZE.X, 0, MAP_PANEL_SIZE.Y),
	Visible = false,
	Parent = screenGui,
})

-- Inset by CORNER_CUT, not full-bleed. HudKit.plate's shell is a 9-sliced angular frame whose
-- top-right corner is cut at 45 degrees, so a bar drawn to the full width runs straight past the
-- diagonal and out of the panel — the exact bug the case-reveal round found in panelHeader, and
-- ClipsDescendants does not fix it because Roblox clips to the RECTANGLE, not to the sliced shape.
local mapAccent = Hud.accentCap(mapSurface, COLOR.AccentDark)
mapAccent.ZIndex = 4

local mapHeader = new("Frame", {
	Name = "Header",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 14, 0, 8),
	Size = UDim2.new(1, -28 - Hud.CORNER_CUT, 0, MAP_HEADER_HEIGHT),
	Parent = mapSurface,
})

new("TextLabel", {
	Name = "Title",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -76, 1, 0),
	Font = Hud.FONT.Display,
	Text = "SECTOR MAP",
	TextColor3 = COLOR.Text,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = mapHeader,
})

-- Chapter counter. The raid regenerates a whole new map each time one is cleared (see
-- RaidRoomService.onMapCleared), and without this the map silently reshuffling itself under the
-- player reads as a glitch rather than as progress.
local chapterChip = new("TextLabel", {
	Name = "Chapter",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -30, 0.5, 0),
	Size = UDim2.new(0, 44, 0, 18),
	BackgroundColor3 = COLOR.PanelLight,
	Font = Hud.FONT.Display,
	Text = "CH 1",
	TextColor3 = COLOR.Accent,
	TextSize = 11,
	Parent = mapHeader,
}, { corner(4), stroke(COLOR.Line, 1) })

local collapsed = false
local collapseButton = new("TextButton", {
	Name = "Collapse",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.new(0, 22, 0, 22),
	BackgroundColor3 = COLOR.PanelLight,
	AutoButtonColor = true,
	Font = Hud.FONT.Display,
	Text = "—",
	TextColor3 = COLOR.Muted,
	TextSize = 14,
	Parent = mapHeader,
}, { corner(4), stroke(COLOR.Line, 1) })

-- The choice banner. Doors are the actual control now, so this exists to answer "why is nothing
-- happening" — it is the one place the map says the room is waiting on the player rather than the
-- other way round.
local mapBanner = new("Frame", {
	Name = "Banner",
	BackgroundColor3 = COLOR.AccentDark,
	BackgroundTransparency = 0.25,
	Position = UDim2.new(0, 14, 0, 8 + MAP_HEADER_HEIGHT),
	Size = UDim2.new(1, -28 - Hud.CORNER_CUT, 0, MAP_BANNER_HEIGHT),
	Parent = mapSurface,
}, { corner(4) })

local mapBannerLabel = new("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -16, 1, 0),
	Position = UDim2.new(0, 8, 0, 0),
	Font = Hud.FONT.DisplayMedium,
	Text = "",
	TextColor3 = COLOR.Text,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = mapBanner,
})

local mapCanvas = new("Frame", {
	Name = "Canvas",
	BackgroundColor3 = MAP.Ground,
	Position = UDim2.new(0, 14, 0, 8 + MAP_HEADER_HEIGHT + MAP_BANNER_HEIGHT + 6),
	Size = UDim2.new(0, MAP_CANVAS_SIZE.X, 0, MAP_CANVAS_SIZE.Y),
	ClipsDescendants = true,
	Parent = mapSurface,
}, { corner(5), stroke(COLOR.Line, 1) })

-- Backdrop art slot. `raid_map_backdrop` is deliberately the only non-glyph entry in
-- UiIconConfig.Icons: a full-bleed background rather than a button icon. It is scrimmed hard
-- (ImageTransparency plus the gradient below) because whatever art lands here has to sit UNDER a
-- node tree that must stay readable — a backdrop that competes with the chart wins and the map
-- stops working. Missing art never breaks the loop: at 0 this resolves to nothing, the ImageLabel
-- stays fully transparent, and the procedural grid underneath is what you see.
local mapBackdrop = new("ImageLabel", {
	Name = "Backdrop",
	BackgroundTransparency = 1,
	Image = "",
	ImageTransparency = 1,
	ScaleType = Enum.ScaleType.Crop,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 0,
	Parent = mapCanvas,
})

if Hud.applyIcon(mapBackdrop, "raid_map_backdrop") then
	mapBackdrop.ImageTransparency = 0.72
	-- Darkens the bottom of the art more than the top so the legend strip and the deepest stages
	-- (which is where the tree is busiest) keep their contrast.
	new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 0.6),
		}),
		Rotation = 90,
		Parent = mapBackdrop,
	})
end

-- Procedural grid + corner ticks: the survey-sheet treatment, drawn in code for the same reason
-- HudKit.ring and HudKit.dashedLine are — there is no tiling asset in this project and inventing
-- one would put the look behind art that does not exist. Built ONCE at startup into its own
-- holder, not per redraw: redrawMap clears the node layer every update and this never changes.
local mapGridLayer = new("Frame", {
	Name = "Grid",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 1,
	Parent = mapCanvas,
})

local GRID_STEP = 38
for x = GRID_STEP, MAP_CANVAS_SIZE.X - 1, GRID_STEP do
	new("Frame", {
		BackgroundColor3 = MAP.Grid,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Position = UDim2.new(0, x, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
		ZIndex = 1,
		Parent = mapGridLayer,
	})
end
for y = GRID_STEP, MAP_CANVAS_SIZE.Y - 1, GRID_STEP do
	new("Frame", {
		BackgroundColor3 = MAP.Grid,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, y),
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 1,
		Parent = mapGridLayer,
	})
end

-- Registration ticks in the corners. Cheap, and they do the most of any single detail here to stop
-- the canvas reading as an empty grey box on a map with only a few nodes in it.
for _, spec in ipairs({
	{ ax = 0, ay = 0, dx = 1, dy = 1 },
	{ ax = 1, ay = 0, dx = -1, dy = 1 },
	{ ax = 0, ay = 1, dx = 1, dy = -1 },
	{ ax = 1, ay = 1, dx = -1, dy = -1 },
}) do
	local TICK = 12
	new("Frame", {
		BackgroundColor3 = MAP.Tick,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(spec.ax, spec.ay),
		Position = UDim2.new(spec.ax, spec.dx * 6, spec.ay, spec.dy * 6),
		Size = UDim2.new(0, TICK, 0, 1),
		ZIndex = 2,
		Parent = mapGridLayer,
	})
	new("Frame", {
		BackgroundColor3 = MAP.Tick,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(spec.ax, spec.ay),
		Position = UDim2.new(spec.ax, spec.dx * 6, spec.ay, spec.dy * 6),
		Size = UDim2.new(0, 1, 0, TICK),
		ZIndex = 2,
		Parent = mapGridLayer,
	})
end

-- Everything redrawMap builds goes in here, so a redraw clears ONLY the tree and leaves the
-- backdrop and grid alone.
local mapNodeLayer = new("Frame", {
	Name = "Nodes",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 3,
	Parent = mapCanvas,
})

-- Legend. The ORDER is hand-written (roughly threat-ascending, then the two safe rooms) because
-- there is no ordering to derive from — but every colour and name is read out of
-- RaidConfig.NodeTypes, so a retint or a rename there lands here with no edit, and the map, the
-- legend and the unlocked doors can never disagree about what colour a Combat room is.
local mapLegend = new("Frame", {
	Name = "Legend",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 14, 0, 8 + MAP_HEADER_HEIGHT + MAP_BANNER_HEIGHT + 6 + MAP_CANVAS_SIZE.Y + 6),
	Size = UDim2.new(1, -28 - Hud.CORNER_CUT, 0, MAP_LEGEND_HEIGHT),
	Parent = mapSurface,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local LEGEND_ORDER = { "Combat", "Ambush", "Boss", "Heal", "Shop" }
for order, typeKey in ipairs(LEGEND_ORDER) do
	local typeConfig = RaidConfig.NodeTypes[typeKey]
	if typeConfig then
		local entry = new("Frame", {
			Name = typeKey,
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 60, 1, 0),
			LayoutOrder = order,
			Parent = mapLegend,
		})
		new("Frame", {
			BackgroundColor3 = typeConfig.Color,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(0, 8, 0, 8),
			Parent = entry,
		}, { circleCorner() })
		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 0),
			Size = UDim2.new(1, -12, 1, 0),
			Font = Hud.FONT.Body,
			Text = typeConfig.DisplayName,
			TextColor3 = COLOR.Muted,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = entry,
		})
	end
end

collapseButton.MouseButton1Click:Connect(function()
	collapsed = not collapsed
	mapCanvas.Visible = not collapsed
	mapLegend.Visible = not collapsed
	mapBanner.Visible = not collapsed
	collapseButton.Text = collapsed and "+" or "—"
	mapFrame.Size = collapsed
		and UDim2.new(0, MAP_PANEL_SIZE.X, 0, MAP_HEADER_HEIGHT + 22)
		or UDim2.new(0, MAP_PANEL_SIZE.X, 0, MAP_PANEL_SIZE.Y)
end)

-- Draws a connector between two canvas-local points using a rotated Frame — Roblox GUI has no line
-- primitive. Unchanged in principle from the old overlay's version; it just takes a colour and a
-- weight now so a traversed edge can read differently from one never taken.
local function drawEdge(pointA: Vector2, pointB: Vector2, color: Color3, transparency: number, thickness: number)
	local delta = pointB - pointA
	local length = delta.Magnitude
	local midpoint = (pointA + pointB) / 2

	new("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, midpoint.X, 0, midpoint.Y),
		Size = UDim2.new(0, length, 0, thickness),
		Rotation = math.deg(math.atan2(delta.Y, delta.X)),
		ZIndex = 3,
		Parent = mapNodeLayer,
	})
end

local currentReachableIds = {} :: { number }
local allowNodeClick = false
local choicePending = false

-- The player's trail through the CURRENT chapter. Reset whenever the map's StartNodeId changes,
-- which is exactly when onMapCleared has generated a fresh one — a visited node from the previous
-- chapter has nothing to say about this one, and ids are reused between generations.
local visitedIds = {} :: { [number]: boolean }
local lastStartNodeId: number? = nil

-- One looping tween, held so it can be cancelled. Every animated thing in this HUD needs an
-- explicit teardown or it leaks for the rest of the session with nothing in Output to say so (see
-- the Smelting dial and the case reel). A Cancel-then-recreate is used rather than a Heartbeat
-- loop precisely so there is no per-frame connection to forget about.
local bannerTween: Tween? = nil

local function setBanner(pending: boolean, text: string)
	if bannerTween then
		bannerTween:Cancel()
		bannerTween = nil
	end
	mapBannerLabel.Text = text
	mapBanner.BackgroundColor3 = pending and COLOR.AccentDark or COLOR.PanelLight
	mapBannerLabel.TextColor3 = pending and COLOR.Text or COLOR.Muted
	mapBanner.BackgroundTransparency = pending and 0.25 or 0.55
	if pending then
		bannerTween = TweenService:Create(
			mapBanner,
			TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = 0.6 }
		)
		bannerTween:Play()
	end
end

local function redrawMap(payload)
	mapNodeLayer:ClearAllChildren()
	currentReachableIds = payload.ReachableIds or {}
	allowNodeClick = payload.AllowNodeClick == true
	choicePending = payload.ChoicePending == true

	local reachableSet = {}
	for _, id in ipairs(currentReachableIds) do
		reachableSet[id] = true
	end

	if payload.StartNodeId ~= lastStartNodeId then
		lastStartNodeId = payload.StartNodeId
		visitedIds = {}
	end
	if payload.CurrentNodeId then
		visitedIds[payload.CurrentNodeId] = true
	end

	-- Tree layout ("dendrogram"): RaidConfig.GenerateMap builds a real tree — every node has exactly
	-- one parent, so a node's own Connections list IS its children. Walk it depth-first from Start,
	-- handing each LEAF the next sequential lane in left-to-right visiting order; every internal
	-- node's lane is the average of its own children's lanes, computed on the way back up. Because
	-- this is a genuine tree, connecting lines are GUARANTEED never to cross, by construction —
	-- and that guarantee survives this panel drawing stages down the Y axis instead of across X,
	-- since it is a property of the graph rather than of which way it is pointed.
	local laneOf = {}
	local nextLeafLane = 0

	local function assignLanes(id)
		local node = payload.Nodes[id]
		if not node then
			return 0
		end
		if #node.Connections == 0 then
			local lane = nextLeafLane
			nextLeafLane += 1
			laneOf[id] = lane
			return lane
		end
		local sum = 0
		for _, childId in ipairs(node.Connections) do
			sum += assignLanes(childId)
		end
		local lane = sum / #node.Connections
		laneOf[id] = lane
		return lane
	end
	assignLanes(payload.StartNodeId)

	local maxStage = 0
	local nodeTotal = 0
	local visitedCount = 0
	for id, node in pairs(payload.Nodes) do
		if node.StageIndex > maxStage then
			maxStage = node.StageIndex
		end
		nodeTotal += 1
		if visitedIds[id] then
			visitedCount += 1
		end
	end
	local laneCount = math.max(nextLeafLane, 1)

	-- Stage runs down Y, lane runs across X — the axis swap described in this section's header.
	local stageSpacingY = maxStage > 0
		and math.clamp((MAP_CANVAS_SIZE.Y - CANVAS_MARGIN_Y * 2) / maxStage, MIN_STAGE_SPACING, MAX_STAGE_SPACING)
		or MIN_STAGE_SPACING
	local laneSpacingX = math.clamp((MAP_CANVAS_SIZE.X - CANVAS_MARGIN_X * 2) / laneCount, MIN_LANE_SPACING, MAX_LANE_SPACING)
	local nodeDiameter = math.clamp(laneSpacingX * 0.42, MIN_NODE_DIAMETER, MAX_NODE_DIAMETER)

	local yOffset = math.max(CANVAS_MARGIN_Y, (MAP_CANVAS_SIZE.Y - maxStage * stageSpacingY) / 2)
	local xOffset = math.max(0, (MAP_CANVAS_SIZE.X - laneCount * laneSpacingX) / 2)

	local nodeCanvasPos = {}
	for id, node in pairs(payload.Nodes) do
		nodeCanvasPos[id] = Vector2.new(
			xOffset + (laneOf[id] + 0.5) * laneSpacingX,
			yOffset + node.StageIndex * stageSpacingY
		)
	end

	-- Edges first so every circle draws on top of them. An edge whose BOTH ends have been visited is
	-- a route actually walked, and is drawn solid and warm; everything else is faint. That is the
	-- trail, and it is the single thing this panel does that the old overlay could not.
	for id, node in pairs(payload.Nodes) do
		local fromPos = nodeCanvasPos[id]
		if fromPos then
			for _, toId in ipairs(node.Connections) do
				local toPos = nodeCanvasPos[toId]
				if toPos then
					local walked = visitedIds[id] and visitedIds[toId]
					if walked then
						drawEdge(fromPos, toPos, MAP.EdgeWalked, 0.15, 2)
					else
						drawEdge(fromPos, toPos, MAP.Edge, 0.45, 1)
					end
				end
			end
		end
	end

	for id, node in pairs(payload.Nodes) do
		local pos = nodeCanvasPos[id]
		if pos then
			local typeConfig = RaidConfig.NodeTypes[node.Type]
			local typeColor = (typeConfig and typeConfig.Color) or Color3.fromRGB(120, 120, 120)
			local isCurrent = id == payload.CurrentNodeId
			local isReachable = reachableSet[id] == true
			local isVisited = visitedIds[id] == true

			-- Three states, and they are genuinely different questions: where I am (ringed, largest),
			-- where I can go next (full colour, accented edge), and everything else (a dot — visited
			-- ones filled, unseen ones hollow). Only the first two carry a text label; at this size
			-- labelling all ~18 nodes would be a wall of overlapping type, and the map is for
			-- orienting, not for reciting the graph.
			local diameter = isCurrent and (nodeDiameter + 8) or (isReachable and (nodeDiameter + 3) or nodeDiameter)
			local circle = new("TextButton", {
				Name = "Node" .. id,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, pos.X, 0, pos.Y),
				Size = UDim2.new(0, diameter, 0, diameter),
				BackgroundColor3 = typeColor,
				BackgroundTransparency = (isCurrent or isReachable or isVisited) and 0 or 0.72,
				AutoButtonColor = allowNodeClick and isReachable,
				Text = "",
				ZIndex = 4,
				Parent = mapNodeLayer,
			}, {
				circleCorner(),
				isCurrent and stroke(COLOR.Text, 2)
					or (isReachable and stroke(COLOR.Accent, 2))
					or (isVisited and stroke(Hud.darken(typeColor, 0.35), 1))
					or stroke(MAP.Unvisited, 1),
			})

			-- The "you are here" halo. A plain ring Frame rather than HudKit.ring: that helper builds
			-- 90 rotated Frames for a progress ARC, and this is a full circle with nothing to sweep.
			if isCurrent then
				new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0, pos.X, 0, pos.Y),
					Size = UDim2.new(0, diameter + 10, 0, diameter + 10),
					BackgroundTransparency = 1,
					ZIndex = 3,
					Parent = mapNodeLayer,
				}, { circleCorner(), stroke(COLOR.Text, 1) })
			end

			if isCurrent or isReachable then
				local labelText = typeConfig and typeConfig.DisplayName or node.Type
				if node.Tier then
					labelText = ("%s · T%d"):format(labelText, node.Tier)
				end
				-- Labels sit to the RIGHT of their node, except near the right edge where they would
				-- be clipped by the canvas — those flip to the left and right-align instead. With
				-- stages running down the panel there is no room below a node for a label; the next
				-- stage is already there.
				local flip = pos.X > MAP_CANVAS_SIZE.X * 0.58
				new("TextLabel", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(flip and 1 or 0, 0.5),
					Position = UDim2.new(0, pos.X + (flip and -(diameter / 2 + 6) or (diameter / 2 + 6)), 0, pos.Y),
					Size = UDim2.new(0, 108, 0, 16),
					Font = isCurrent and Hud.FONT.Display or Hud.FONT.Body,
					Text = labelText,
					TextColor3 = isCurrent and COLOR.Text or COLOR.Accent,
					TextSize = 11,
					TextXAlignment = flip and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					ZIndex = 5,
					Parent = mapNodeLayer,
				})
			end

			-- Clickable ONLY in the too-few-ExitDoors fallback. Normally the doors in the room are
			-- the control and this panel is a readout, so wiring the click unconditionally would put
			-- two competing ways to leave a room on screen at once.
			if allowNodeClick and isReachable then
				circle.MouseButton1Click:Connect(function()
					ChooseRaidNode:FireServer(id)
				end)
			end
		end
	end

	chapterChip.Text = ("CH %d"):format((payload.MapsCleared or 0) + 1)

	local currentNode = payload.Nodes[payload.CurrentNodeId]
	local currentTypeConfig = currentNode and RaidConfig.NodeTypes[currentNode.Type]
	local currentName = (currentTypeConfig and currentTypeConfig.DisplayName)
		or (currentNode and currentNode.Type)
		or "Unknown"

	if choicePending then
		setBanner(true, allowNodeClick and "PICK A NODE ON THE MAP" or "CHOOSE AN EXIT — WALK THROUGH A DOOR")
	else
		setBanner(false, ("%s  ·  %d / %d mapped"):format(string.upper(currentName), visitedCount, nodeTotal))
	end
end

-- The one teardown funnel for the map: raid over, however it ended. Cancels the banner's looping
-- tween as well as hiding the panel — a RepeatCount = -1 tween keeps running on a hidden Frame
-- forever otherwise, which is the same silent leak the Smelting dial and the case reel each carry
-- a guard against.
local function hideSectorMap()
	if bannerTween then
		bannerTween:Cancel()
		bannerTween = nil
	end
	choicePending = false
	allowNodeClick = false
	visitedIds = {}
	lastStartNodeId = nil
	mapFrame.Visible = false
end


----------------------------------------------------------------------
-- Remote handlers
----------------------------------------------------------------------

local inRaid = false
local inCombat = false
local extractUnlocked = false -- true once RaidRoomService reports the raid's first map chapter
	-- cleared (the "MapCleared" status below) — see Extract button's own comment above

-- Direct reference to the Combat sub-panel's Enemies bar, set fresh each "CombatStart" — kept as
-- an upvalue rather than re-derived from roomBody:GetChildren() on every "CombatTick" (GetChildren
-- order isn't a documented guarantee, just usually-true, and this arrives every BROADCAST_INTERVAL
-- during a fight — not worth relying on it holding up over many ticks). No player-health bar here
-- on purpose — direct feedback was it read as illegible clutter; your own HP is already visible on
-- the normal Roblox health bar, this panel only needs to say what's happening in THIS room.
local combatEnemyLabel, combatEnemyFill = nil, nil

-- Keeps the Start button, Go Back To Base, and Extract mutually consistent with current state —
-- Start only makes sense when not already raiding; Extract only while raiding, not mid-Combat (see
-- RaidRoomService's own comment on why Combat blocks it), and only once extractUnlocked.
--
-- Go Back To Base gates on `choicePending`, NOT on the map being visible. It used to read
-- mapFrame.Visible, which worked only because the map was an overlay that opened exactly when a
-- choice was offered — the map is a permanent panel now, so that test would leave the button up for
-- the whole raid and undo the rule it exists for ("so they cant just quit while doing a raid").
-- The server sets ChoicePending only while a choice is genuinely live, which is the same moment the
-- old overlay used to appear.
updateRaidButtons = function()
	startButton.Visible = not inRaid
	backToBaseButton.Visible = inRaid and choicePending
	extractButton.Visible = inRaid and not inCombat and extractUnlocked
	runCurrencyLabel.Visible = inRaid
end

-- Arrives on EVERY node entry now, not only when a choice opens — the map is a persistent readout,
-- so it has to learn where the player is the moment they arrive, mid-fight included. The payload's
-- ChoicePending says whether a choice is actually live; redrawMap stores that for updateRaidButtons.
--
-- roomFrame is no longer hidden here. The two panels are in different places on screen (room panel
-- top-centre, map docked right) and both are now legitimately visible at once; hiding the room panel
-- on a map update would blank the description of the room the player is standing in.
RaidMapUpdate.OnClientEvent:Connect(function(payload)
	if not payload or not payload.Active then
		hideSectorMap()
		updateRaidButtons() -- the choice just went away — Go Back To Base needs to hide too
		return
	end
	inRaid = true
	-- Only on a real choice, not on the entry-time position update. A choice being offered means
	-- the room's encounter is definitively over, which is what the old overlay-era handler relied on
	-- to bring the Extract button back; the position update fires mid-room and must not claim that.
	if payload.ChoicePending then
		inCombat = false
	end
	redrawMap(payload)
	mapFrame.Visible = true
	-- Called AFTER redrawMap, not before: Go Back To Base's visibility reads `choicePending`, which
	-- redrawMap is what sets from the payload.
	updateRaidButtons()
end)

RaidRoomUpdate.OnClientEvent:Connect(function(payload)
	payload = payload or {}
	local status = payload.Status

	if status == "Entered" then
		inRaid = true
		inCombat = false
		-- The map is NOT hidden here any more. It is a permanent panel for the whole raid now, and
		-- RaidMapUpdate has already moved the "you are here" marker into this room.
		clearRoomBody()
		local typeConfig = RaidConfig.NodeTypes[payload.Type]
		roomTitle.Text = payload.DisplayName or payload.Type
		if payload.Tier then
			roomTitle.Text ..= (" · Tier %d"):format(payload.Tier)
		end
		if typeConfig then
			new("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 18),
				LayoutOrder = 0,
				Font = Enum.Font.SourceSans,
				Text = typeConfig.Description,
				TextColor3 = COLOR.Muted,
				TextSize = 13,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = roomBody,
			})
		end
		roomFrame.Visible = true
		updateRaidButtons()

	elseif status == "RunCurrencyUpdate" then
		updateRunCurrencyLabel(payload.RunCurrencyCollected)

	elseif status == "AwaitingInteraction" then
		-- Heal/Shop now wait for a Part interaction before actually triggering — see
		-- RaidRoomService.beginInteractGated. Appends a hint to the room panel's existing
		-- title/description (does NOT clearRoomBody — that would wipe them) rather than a whole
		-- new screen, since this is just "not yet" not a different kind of room.
		new("TextLabel", {
			Name = "InteractHint",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = 1,
			Font = Enum.Font.SourceSansItalic,
			Text = ("Find the %s point to continue."):format(payload.ActionText or "interact"),
			TextColor3 = COLOR.Accent,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = roomBody,
		})

	elseif status == "HealApplied" then
		clearRoomBody()
		new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = 1,
			Font = Enum.Font.SourceSans,
			Text = "Fully healed.",
			TextColor3 = COLOR.Good,
			TextSize = 14,
			Parent = roomBody,
		})
		actionButton(2, "Continue", COLOR.AccentDark, function()
			RaidRoomAction:FireServer("Continue")
		end)

	elseif status == "ShopCatalog" then
		clearRoomBody()
		local order = 1
		local catalog = payload.Catalog or {}
		local keys = {}
		for itemKey in pairs(catalog) do
			table.insert(keys, itemKey)
		end
		table.sort(keys)
		for _, itemKey in ipairs(keys) do
			local item = catalog[itemKey]
			order += 1
			actionButton(order, ("%s — %d %s"):format(item.DisplayName, item.CostAmount, item.CostCurrency), COLOR.PanelLight, function()
				RaidRoomAction:FireServer("Buy", itemKey)
			end)
		end
		order += 1
		actionButton(order, "Continue", COLOR.AccentDark, function()
			RaidRoomAction:FireServer("Continue")
		end)

	elseif status == "ShopResult" then
		showToast(payload.Success and "Purchased." or ("Couldn't buy that — " .. (payload.Reason or "")), 2.5)

	elseif status == "CombatStart" then
		inCombat = true
		updateRaidButtons()
		clearRoomBody()
		combatEnemyLabel, combatEnemyFill = progressBar(1, "Enemies")

	elseif status == "CombatTick" then
		if combatEnemyLabel then
			combatEnemyLabel.Text = ("Enemies remaining: %d / %d"):format(payload.EnemiesRemaining or 0, payload.EnemiesTotal or 0)
		end
		if combatEnemyFill and payload.EnemiesTotal and payload.EnemiesTotal > 0 then
			combatEnemyFill.Size = UDim2.new(math.clamp((payload.EnemiesRemaining or 0) / payload.EnemiesTotal, 0, 1), 0, 1, 0)
		end

	elseif status == "CombatEnd" then
		inCombat = false
		updateRaidButtons()

	-- Ambush — same shape as Combat's Start/Tick/End, just labeled separately (see
	-- RaidRoomService.beginAmbush) and carrying Wave/WaveTotal so the panel can show progress
	-- through the whole multi-wave sequence, not just the current wave's own enemy count.
	elseif status == "AmbushStart" then
		inCombat = true
		updateRaidButtons()
		clearRoomBody()
		combatEnemyLabel, combatEnemyFill = progressBar(1, "Enemies")

	elseif status == "AmbushTick" then
		if combatEnemyLabel then
			combatEnemyLabel.Text = ("Wave %d/%d — Enemies remaining: %d / %d"):format(
				payload.Wave or 1, payload.WaveTotal or 1, payload.EnemiesRemaining or 0, payload.EnemiesTotal or 0)
		end
		if combatEnemyFill and payload.EnemiesTotal and payload.EnemiesTotal > 0 then
			combatEnemyFill.Size = UDim2.new(math.clamp((payload.EnemiesRemaining or 0) / payload.EnemiesTotal, 0, 1), 0, 1, 0)
		end

	elseif status == "AmbushEnd" then
		-- Intentionally no inCombat/button change here — state.InCombat server-side stays true for
		-- the WHOLE Ambush node (every wave plus the short breather between them), only clearing
		-- once the last wave resolves (or the raid ends) — see AmbushWaveCleared below. Toggling
		-- inCombat off at the end of each individual wave would flash Abandon/Extract back on
		-- between waves just to have the server reject the click a moment later.

	elseif status == "AmbushWaveCleared" then
		local lootParts = {}
		for _, entry in ipairs(payload.Loot or {}) do
			table.insert(lootParts, ("%d %s"):format(entry.Amount, entry.Key))
		end
		local waveText = ("Wave %d/%d cleared!"):format(payload.Wave or 1, payload.WaveTotal or 1)
		showToast(#lootParts > 0 and (waveText .. " Found: " .. table.concat(lootParts, ", ")) or waveText, 3)
		if payload.Wave and payload.WaveTotal and payload.Wave >= payload.WaveTotal then
			inCombat = false
			updateRaidButtons()
			roomFrame.Visible = false
		end

	-- Boss — same shape as Combat's Start/Tick/End (a single tougher encounter, no Wave prefix
	-- needed). See RaidRoomService.beginBoss.
	elseif status == "BossStart" then
		inCombat = true
		updateRaidButtons()
		clearRoomBody()
		combatEnemyLabel, combatEnemyFill = progressBar(1, "Enemies")

	elseif status == "BossTick" then
		if combatEnemyLabel then
			combatEnemyLabel.Text = ("Enemies remaining: %d / %d"):format(payload.EnemiesRemaining or 0, payload.EnemiesTotal or 0)
		end
		if combatEnemyFill and payload.EnemiesTotal and payload.EnemiesTotal > 0 then
			combatEnemyFill.Size = UDim2.new(math.clamp((payload.EnemiesRemaining or 0) / payload.EnemiesTotal, 0, 1), 0, 1, 0)
		end

	elseif status == "BossEnd" then
		inCombat = false
		updateRaidButtons()

	elseif status == "BossCleared" then
		-- Full heal + a rarity-weighted card pick, BEFORE the map moves on — "once the boss fight
		-- clears, you get healed, and you roll some cards with buffs... pretty roguelike." The
		-- player has to actually pick one (renderCardChoices' buttons fire "ChooseCard") — there's
		-- no "Continue" here, choosing IS what advances.
		clearRoomBody()
		local lootParts = {}
		for _, entry in ipairs(payload.Loot or {}) do
			table.insert(lootParts, ("%d %s"):format(entry.Amount, entry.Key))
		end
		new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = 1,
			Font = Enum.Font.SourceSans,
			Text = "Boss defeated! Healed to full." .. (#lootParts > 0 and (" Found: " .. table.concat(lootParts, ", ")) or ""),
			TextColor3 = COLOR.Good,
			TextSize = 14,
			TextWrapped = true,
			Parent = roomBody,
		})
		new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = 2,
			Font = Enum.Font.SourceSansBold,
			Text = "Choose one:",
			TextColor3 = COLOR.Text,
			TextSize = 15,
			Parent = roomBody,
		})
		renderCardChoices(2, payload.CardChoices, function(cardKey)
			RaidRoomAction:FireServer("ChooseCard", cardKey)
		end)

	elseif status == "CardChosen" then
		local card = payload.Card
		showToast(card and ("Picked: " .. card.DisplayName .. " (" .. card.Rarity .. ")") or "Card picked.", 3)
		roomFrame.Visible = false

	elseif status == "Cleared" then
		local lootParts = {}
		for _, entry in ipairs(payload.Loot or {}) do
			table.insert(lootParts, ("%d %s"):format(entry.Amount, entry.Key))
		end
		showToast(#lootParts > 0 and ("Room cleared! Found: " .. table.concat(lootParts, ", ")) or "Room cleared!", 3)
		roomFrame.Visible = false

	elseif status == "MapCleared" then
		-- Fires whenever this map chapter's dead-end node is reached — RaidRoomService always
		-- regenerates and keeps going right after this (see its onMapCleared), so this is just a
		-- heads-up + (on the very first one) unlocking Extract, not something the player responds to.
		if payload.ExtractUnlocked then
			extractUnlocked = true
		end
		updateRaidButtons()
		showToast(payload.JustUnlocked and "Map cleared! Extract is now available whenever you're ready."
			or "Map cleared — moving to a new area.", payload.JustUnlocked and 4 or 3)

	elseif status == "Defeated" then
		inRaid = false
		inCombat = false
		extractUnlocked = false
		roomFrame.Visible = false
		hideSectorMap()
		updateRaidButtons()
		showToast("Raid failed — " .. (payload.Reason or "you went down.") .. " Back to base.", 5)

	elseif status == "Extracted" then
		inRaid = false
		inCombat = false
		extractUnlocked = false
		roomFrame.Visible = false
		hideSectorMap()
		updateRaidButtons()
		showToast("Extracted! Made it out clean.", 5)

	elseif status == "Abandoned" then
		inRaid = false
		inCombat = false
		extractUnlocked = false
		roomFrame.Visible = false
		hideSectorMap()
		updateRaidButtons()
		showToast("Raid abandoned.", 3)

	elseif status == "NoEnergy" then
		showToast("Not enough Energy to start a raid.", 3)

	elseif status == "NoSlotsFree" then
		showToast("The raid area is full right now — try again shortly.", 3)

	elseif status == "Busy" then
		-- Already defending the base or in an outpost fight — a raid would fight the same
		-- CombatEncounterService slot out from under it, so the server refuses. See
		-- PlayerActivityService.
		showToast(payload.Reason or "You're busy with something else right now.", 3)
	end
end)
