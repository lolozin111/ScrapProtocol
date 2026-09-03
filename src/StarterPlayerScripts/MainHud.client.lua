--[[
	MainHud.client.lua
	A plain-code debug HUD — a trimmed currency readout, a Workbench menu (opened only from a
	physical station, see the Base stations section), an Inventory panel (viewable anywhere —
	equip/deploy/undeploy your gear and see everything you own, including raw materials), and a
	wave-defense panel. Everything here is Instance.new'd rather than a Studio-built ScreenGui
	so the whole UI ships through Rojo as text, same as the rest of this project.

	This is intentionally undecorated: flat panels, no icons, no animation. It exists so the
	full loop is genuinely visible and testable — mine, see currency go up, craft, see it
	deducted, deploy, start a wave, watch the bars move. Reskin it once the loop feels good;
	don't reskin it before you know the loop feels good.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
-- Both added for the Smelting tab's dial: RunService drives the ring's per-frame sweep (a
-- once-a-second re-render makes it visibly step instead of move), and UserInputService carries the
-- quantity slider's drag, which has to keep tracking after the pointer leaves the track itself.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local OreConfig = require(ReplicatedStorage.Shared.OreConfig)
local NodeConfig = require(ReplicatedStorage.Shared.NodeConfig)
local AutoMinerConfig = require(ReplicatedStorage.Shared.AutoMinerConfig)
local RaidEnergyConfig = require(ReplicatedStorage.Shared.RaidEnergyConfig)
local MineShaftConfig = require(ReplicatedStorage.Shared.MineShaftConfig)
local ModConfig = require(ReplicatedStorage.Shared.ModConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local ToolModConfig = require(ReplicatedStorage.Shared.ToolModConfig)
local RefinedOreConfig = require(ReplicatedStorage.Shared.RefinedOreConfig)
local BaseConfig = require(ReplicatedStorage.Shared.BaseConfig)
local ResearchConfig = require(ReplicatedStorage.Shared.ResearchConfig)
local UltimateConfig = require(ReplicatedStorage.Shared.UltimateConfig)
local CaseConfig = require(ReplicatedStorage.Shared.CaseConfig)
local TurretConfig = require(ReplicatedStorage.Shared.TurretConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LocalPlayer = Players.LocalPlayer

-- Shared HUD foundation: palette, Instance.new helpers, the ScreenGui, the client's profile
-- mirror, the toast, and makeRow. Referenced as Hud.X throughout rather than re-bound to
-- locals here — re-binding would hand every register straight back, which is the entire
-- reason this module exists (see HudKit.lua's header).
local Hud = require(script.Parent.HudKit)
local ModPicker = require(script.Parent.ModPicker)
local ShopPanel = require(script.Parent.ShopPanel)
local TurretPanel = require(script.Parent.TurretPanel)
local ResearchPanel = require(script.Parent.ResearchPanel)
local InventoryPanel = require(script.Parent.InventoryPanel)
local WeldingPanel = require(script.Parent.WeldingPanel)
local ForgePanel = require(script.Parent.ForgePanel)
local CasePanel = require(script.Parent.CasePanel)


local runActive = false

----------------------------------------------------------------------
-- Small UI helpers
----------------------------------------------------------------------


----------------------------------------------------------------------
-- Screen setup
----------------------------------------------------------------------


----------------------------------------------------------------------
-- Currency readout (top-centre, flush against the top edge)
----------------------------------------------------------------------

-- Only the surface is bound (Hud.plate's second return, the shell, is discarded) — nothing else
-- ever needs to reposition/hide this panel, only parent labels into it.
--
-- automaticSize = true restores the original AutomaticSize.Y behavior: plate's inner surface is
-- normally sized as a SCALE of the shell (see Hud.plate's PLATE_SURFACE_INSET), which is circular
-- with AutomaticSize and silently no-ops — this panel had been given a literal pixel height
-- instead, which clipped silently the moment a currency row or status line was added and nobody
-- remembered to recompute the magic number. Hud.plate's automaticSize option breaks that
-- circularity on the shell/surface pair; currencyList below has to do the equivalent for itself
-- to actually benefit from it (see its own comment).
-- Used to be a hand-summed fixed 400 width (icon 18 + gaps + labels + fixed-width values) — that
-- guess was already wrong before the icon/text scale-up in this pass made every group wider, and
-- a too-narrow surface clips silently (Frames don't clip children by default) rather than erroring:
-- the last group's value rendered outside the plate entirely, on top of the game world. XY instead
-- of the plain Y every other plate() caller uses sizes the surface to its actual content on BOTH
-- axes, so the strip grows to fit groups/text as they change instead of guessing again.
--
-- Top-CENTRE, flush against the very top edge of the screen (AnchorPoint 0.5,0 + Position
-- 0.5,0,0,0 — no offset on either axis, on purpose: this was moved off the top-left corner and
-- explicitly asked to sit flush, no inset). With a 0.5 AnchorPoint the strip grows outward from
-- its own centre on both sides as groups/text change width, so it stays centred without any
-- offset math to compensate — same idea as the old top-left/grows-rightward pairing, just
-- centred instead of corner-anchored.
--
-- "Flush against the very top edge" turned out to mean the top of Hud.screenGui's content area,
-- not the physical top of the screen — Hud.screenGui leaves IgnoreGuiInset at its default false,
-- so Roblox shifts that whole GUI's y=0 down by its own top bar's height (~36px) automatically.
-- Fixing that on Hud.screenGui itself would drag every panel on it down/up together, including
-- everything anchored to the BOTTOM of the screen, and HudKit.lua isn't this change's file to
-- touch — so the wallet strip gets its OWN ScreenGui instead, with IgnoreGuiInset = true, isolating
-- the fix to just this one element. Roblox's top bar only occupies the top-left corner (and the
-- corners generally); top-centre, where this strip is anchored, is clear of it.
local walletGui = Hud.new("ScreenGui", {
	Name = "WalletGui",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, -- matches Hud.screenGui's, same reasoning as that
		-- one: sibling GUIs would otherwise fight over descendant z-order in an undefined way.
	Parent = LocalPlayer:WaitForChild("PlayerGui"),
})

local currencyFrame = Hud.plate({
	Name = "Currency",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(0, 0, 0, 0), -- both placeholders; automaticSize below drives the real size
	automaticSize = Enum.AutomaticSize.XY,
	Parent = walletGui,
})
Hud.accentCap(currencyFrame) -- full-width, parented straight onto the surface (not into
	-- currencyList below) so it sits flush at the top edge, unaffected by currencyList's own
	-- UIPadding — that padding only insets the labels beneath the cap.

-- The old UIListLayout/UIPadding/labels all lived directly on currencyFrame; now they're one level
-- down, in their own frame below the accent cap, so the cap can span edge-to-edge while the labels
-- keep their original padding untouched.
--
-- Size/AutomaticSize here mirror the same fix Hud.plate applies to its own shell/surface pair:
-- neither axis carries a Scale component (both offset-only zeroes), so this frame's size never
-- depends on currencyFrame's own still-being-computed automatic size, and AutomaticSize.XY then
-- grows it to fit its UIListLayout'd row on both axes. X used to be Scale (`1, 0`), which was
-- harmless while currencyFrame's width was a fixed 400 — now that currencyFrame is AutomaticSize.XY
-- too (see its own comment: the fixed-400 plate is what overflowed), a Scale-X child here would be
-- circular against that and quietly collapse instead of erroring, the same failure mode the Y-axis
-- comment above already describes. accentCap below stays Scale-width on purpose: it's a passive
-- follower with no content of its own to drive a size from, so it just resolves to whatever this
-- frame (the actual driver) ends up computing.
--
-- Now a single horizontal row (direction C / the "Forged Rig" hybrid) instead of three stacked
-- lines — FillDirection/VerticalAlignment replace the old vertical Padding-only layout.
local currencyList = Hud.new("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 4),
	Size = UDim2.new(0, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.XY,
	Parent = currencyFrame,
}, {
	Hud.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}),
	Hud.new("UIPadding", {
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
	}),
})

-- Icon slot + short muted label shared by every group. UiIconConfig now has real asset IDs for
-- "scrap"/"cores"/"energy", so these render for real — but the fallback stays live: if a key's ID
-- is ever zeroed out again, Hud.applyIcon returns false, the ImageLabel hides itself, and the
-- muted label alone carries the meaning, per this project's "missing art never breaks the loop"
-- rule rather than rendering an empty square.
--
-- Group's own height is a fixed offset (28, up from 24 to fit the bigger icon below), never a
-- Scale, for the same circularity reason currencyFrame/currencyList call out above: currencyList
-- AutomaticSizes its Y from this row's height, so this row's height can't in turn depend on
-- currencyList's.
-- Every group's slots carry an explicit LayoutOrder (1 = icon, 2 = label, 3 = the value the caller
-- appends after this returns) rather than relying on insertion order. UIListLayout's default
-- SortOrder (LayoutOrder) breaks ties between equal LayoutOrder values by instance Name, not by
-- parenting order — and icon/label/value aren't always the same ClassName (the energy group's
-- value slot is a plain Frame wrapping current+max, not a TextLabel), so their Roblox-default
-- Names differ too ("Frame" < "ImageLabel" < "TextLabel" alphabetically). That's exactly why the
-- energy group rendered as value/icon/label while Scrap/Cores (icon/label/value, with label and
-- value both untouched-Name TextLabels tying and falling back to a stable insertion-order sort)
-- looked fine — a Studio screenshot caught the strip reading asymmetric. Explicit LayoutOrder on
-- every slot makes render order independent of ClassName again.
local function makeCurrencyGroupShell(iconKey: string, labelText: string): Frame
	local group = Hud.new("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 28),
		Parent = currencyList,
	}, {
		Hud.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 5),
		}),
	})

	-- 18x18 -> 24x24 (Studio screenshot: too small to read next to the larger readout text below).
	local icon = Hud.new("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(24, 24),
		LayoutOrder = 1,
		Parent = group,
	})
	if not Hud.applyIcon(icon, iconKey) then
		icon.Visible = false
	end

	-- Uppercase + Hud.FONT.Display, same display treatment as every other label in this file —
	-- TextLabel has no letter-spacing property, so this is the whole treatment (no inserted spaces
	-- to fake tracking, which would break AutomaticSize.X right above).
	Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 20),
		Font = Hud.FONT.Display,
		TextColor3 = Hud.COLOR.Muted,
		TextSize = Hud.TEXTSIZE.Label,
		Text = labelText:upper(),
		LayoutOrder = 2,
		Parent = group,
	})

	return group
end

-- 1px vertical rules between groups, in Hud.COLOR.Line — offset-sized for the same
-- non-Scale-under-AutomaticSize reason as the group shells above.
local function makeCurrencyDivider()
	Hud.new("Frame", {
		BackgroundColor3 = Hud.COLOR.Line,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 1, 0, 22), -- 18 -> 22, matching the group row's growth to 28 tall
		Parent = currencyList,
	})
end

-- Fixed-width, right-aligned, Hud.FONT.Mono: Scrap/Cores change constantly during play, and a
-- left-aligned or AutomaticSize-width value would jitter sideways every time a digit is added or
-- dropped. A fixed box with right alignment keeps the ones-digit anchored in place; the number
-- grows leftward into its own reserved space instead of shoving the divider/next group over.
-- layoutOrder is optional and deliberately not defaulted to 3: this same helper builds the
-- current-energy label nested inside energyValue below, where it must NOT get an explicit
-- LayoutOrder — it and energyMax are both plain TextLabels, so they already tie and fall back to a
-- stable insertion-order sort (current, then max), and forcing one of them to a fixed LayoutOrder
-- while leaving the other at the 0 default would reorder them instead of fixing anything. Only the
-- Scrap/Cores callers, where this return value IS the group's third (value) slot, pass 3.
local function makeCurrencyValue(parent: Frame, color: Color3, width: number, layoutOrder: number?): TextLabel
	return Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, width, 0, 24),
		Font = Hud.FONT.Mono,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = color,
		TextSize = Hud.TEXTSIZE.Readout,
		Text = "",
		LayoutOrder = layoutOrder,
		Parent = parent,
	})
end

-- Grouped into one table (rather than one local per label) to stay under Luau's 200-local cap —
-- see this file's header note on that budget. refreshCurrency below addresses these by field name.
local currencyStrip = {}
currencyStrip.scrap = makeCurrencyValue(makeCurrencyGroupShell("scrap", "Scrap"), Hud.COLOR.Accent, 64, 3)
makeCurrencyDivider()
currencyStrip.cores = makeCurrencyValue(makeCurrencyGroupShell("cores", "Cores"), Hud.COLOR.Good, 64, 3)
makeCurrencyDivider()

-- Energy gets a second, Muted "/max" segment instead of one combined string — RichText would also
-- get two colors in one label, but needs a Color3->hex helper this project doesn't have yet, and
-- MaxEnergy is a session constant (never changes at runtime), so this segment is set once here and
-- never touched by refreshCurrency — only the current-energy segment needs the anti-jitter
-- fixed-width treatment makeCurrencyValue gives it.
--
-- BUG FIX: energyCurrent/energyMax used to be two direct children of energyGroup, so energyGroup's
-- own UIListLayout put its normal 5px inter-item Padding between them too (the same padding it puts
-- between the icon and the label) — that's what a Studio screenshot caught rendering as "5 /5"
-- instead of "5/10". They're nested in their own zero-padding frame instead: the outer group still
-- gives that frame one 5px gap after the label, same as any other item, but nothing separates the
-- two labels inside it, so the value reads as one tight "5/10".
local energyGroup = makeCurrencyGroupShell("energy", "Energy")
local energyValue = Hud.new("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(0, 0, 0, 24),
	AutomaticSize = Enum.AutomaticSize.X,
	LayoutOrder = 3, -- this Frame IS the energy group's value slot; see makeCurrencyGroupShell's
		-- header comment for why that has to be explicit instead of relying on insertion order.
	Parent = energyGroup,
}, {
	Hud.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 0),
	}),
})
currencyStrip.energyCurrent = makeCurrencyValue(energyValue, Hud.COLOR.Text, 32)
currencyStrip.energyMax = Hud.new("TextLabel", {
	BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.new(0, 0, 0, 24),
	Font = Hud.FONT.Mono,
	TextColor3 = Hud.COLOR.Muted,
	TextSize = Hud.TEXTSIZE.Readout,
	Text = ("/%d"):format(RaidEnergyConfig.MaxEnergy),
	Parent = energyValue,
})

-- Ore/material counts used to live here too (one label per ore plus a divider), but that made
-- this corner unreadable fast — it's trimmed down to just the three numbers worth a glance during
-- normal play now. The full breakdown (plus Scrap/Cores again for a complete picture) lives in
-- the Inventory panel's Materials tab instead — see InventoryPanel.lua. ORE_DISPLAY_ORDER itself
-- is kept here (and passed into InventoryPanel.new's context) since the Materials tab still needs it.
local ORE_DISPLAY_ORDER = { "ScrapIron", "CopperWire", "SteelPlating", "GoldContacts" }

local function refreshCurrency()
	currencyStrip.scrap.Text = tostring(Hud.profile.Scrap or 0)
	currencyStrip.cores.Text = tostring(Hud.profile.Cores or 0)
	-- Energy can briefly read above MaxEnergy right after an Energy Drink (see
	-- RaidEnergyConfig.OverflowCap) — that's intentional, not a bug, it just drains back down to
	-- the normal cap as raids are spent rather than being topped up further by passive regen.
	-- energyMax's "/N" text is set once at construction above, not here — MaxEnergy is constant.
	currencyStrip.energyCurrent.Text = tostring(Hud.profile.Energy or 0)
end

----------------------------------------------------------------------
-- Craft menu (center, toggled)
----------------------------------------------------------------------

-- craftFrame is the plate's SHELL (the outer, positioned/sized/Visible-toggled frame) so every
-- existing `craftFrame.Visible = ...` read/write elsewhere in this file keeps working unchanged;
-- craftSurface is the inset content surface everything below parents into instead.
--
-- VERTICAL STACK, re-derived now that this panel adopts Hud.panelHeader (previously skipped
-- specifically because the header's fixed height would have pushed the tab row down, and layout
-- changes were out of scope at the time -- they aren't any more):
--   Header:         Hud.panelHeader is a fixed 48px tall (PANEL_HEADER_HEIGHT in HudKit.lua).
--   Gap:            Hud.SPACE.S (8px) below it -- the same "8px gap below the thing above it"
--                   convention InventoryPanel.lua's tab row already uses under its own header.
--   Tab row Y:      48 + 8 = 56.
--   Tab row height: 40, grown from the previous 32. These tabs now carry dropShadow (see
--                   makeTabButton below), and BUTTON_MIN_SLICE_SIZE (40) is a PHYSICAL floor that
--                   a Scale-height button's axisClears check cannot actually enforce -- it assumes
--                   any Scale-sized axis clears regardless of the parent's real pixel height (see
--                   axisClears's own comment in HudKit.lua) -- so the row itself has to genuinely
--                   be >= 40px or the tabs render with broken/overlapping corners with nothing in
--                   Output to explain why. InventoryPanel.lua grew its own tab row for this exact
--                   reason.
--   Gap:            another Hud.SPACE.S below the tab row.
--   List Y:         56 + 40 + 8 = 104 -- identical numbers to InventoryPanel's own
--                   INV_TAB_ROW_Y/INV_TAB_HEIGHT/INV_LIST_Y stack; not a coincidence, just the
--                   same shape of panel solved the same way.
--   List height:    surface height minus 104, minus the same fixed 12px bottom margin this
--                   surface's other edges already use (so Size's Y offset is -(104+12) = -116).
--   Panel height:   400 -> 424 (+24), so the visible list keeps its original 308px
--                   (400 - 80 - 12, before this change) instead of quietly losing it to the
--                   taller stack above: the header+gap now taking 56px where the old title/close
--                   row took 40 accounts for 16 of that, the tab row's 32 -> 40 growth accounts
--                   for the other 8. Position's Y offset is -212, exactly half of the new 424
--                   height, so the panel stays centered.
-- AnchorPoint-centred rather than the old `Position = (0.5, -320, 0.5, -212)` half-size offsets.
-- That form hardcoded half of 640x424 into the POSITION, so the panel only stayed centred at
-- exactly that size — and openStationMenu now resizes it per station (StationConfig.PanelSize), at
-- which point those offsets would have parked every non-640x424 station's menu off-centre by half
-- the difference. Anchoring at the middle makes centring survive any size, and deletes two magic
-- numbers that had to be kept in sync with the Size line by hand.
local craftSurface, craftFrame = Hud.plate({
	Name = "CraftMenu",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(
		StationConfig.DefaultPanelSize.X,
		StationConfig.DefaultPanelSize.Y -- see the vertical-stack comment above for how 424 was derived
	),
	Visible = false,
	Parent = Hud.screenGui,
})

-- craftClose is forward-declared (no value yet) so the header's onClose closure just below can
-- capture it as an upvalue now and see the real function once it's assigned much further down --
-- the same "capture now, assign later" pattern InventoryPanel.lua uses for closeInvDetail. It is
-- assigned down with the bottom action row rather than here because that is where it has always
-- lived; nothing in its body needs anything from down there any more, now that the Forge's docked
-- widgets are gone.
local craftClose

-- There's no standalone "Workbench" button anymore — this menu only ever opens FROM a physical
-- station now (see openStationMenu / setupStation further down), so the title doubles as a
-- reminder of which one is currently open. Uppercased for the static-chrome Display treatment
-- Hud.panelHeader applies to every panel title this pass; openStationMenu (further down)
-- reassigns this same label's Text per station, uppercased there too — StationConfig's
-- DisplayName strings ("Workbench", "Forge", ...) are short authored config chrome, not
-- player/server-generated content, so they get the same treatment as everything else here.
-- The header FRAME is kept, not just its title label: the Welding Station's Robots tab parks its
-- "DEPLOYED 2 / 3" readout in this bar (a station-wide fact, so it belongs in the chrome rather than
-- inside the tab body), and WeldingPanel needs somewhere to parent it. Nothing else writes to it.
local craftHeader = Hud.panelHeader(craftSurface, "WORKBENCH", function()
	craftClose()
end)
local craftTitleLabel = craftHeader:FindFirstChildOfClass("TextLabel")

-- Tab row height is 40, not a free choice — see the vertical-stack comment above craftFrame for
-- why (BUTTON_MIN_SLICE_SIZE's physical floor). Position Y (56) is header (48) + Hud.SPACE.S (8).
local tabRow = Hud.new("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 56),
	Size = UDim2.new(1, -24, 0, 40),
	Parent = craftSurface,
}, { Hud.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, Hud.SPACE.S) }) })

-- Y = tab row's bottom (56 + 40 = 96) + the same Hud.SPACE.S gap = 104. Size's -116 offset is
-- that same 104 plus the fixed 12px bottom margin this surface's other edges already use.
local listFrame = Hud.new("ScrollingFrame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 104),
	Size = UDim2.new(1, -24, 1, -116),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	Parent = craftSurface,
}, { Hud.new("UIListLayout", { Padding = UDim.new(0, 6) }) })

-- Delegates to Wallet so the HUD names and orders cost keys exactly the way the server resolves
-- them — including refined materials, which this used to render as their raw key ("SteelIngot")
-- because it only knew about Scrap/Cores and OreConfig.


local currentTab = "Weapons"

-- Tool tier isn't a recipe table either — it's one sequential upgrade track — so it gets its
-- own row-builder too. This is the ONLY way ToolTier (and therefore access to Steel Plating and
-- above, see OreConfig.Ores[key].MinToolTier) ever goes up.
-- Forward-declared, and deliberately this high up: several row-builders below need to re-render the
-- list they are sitting in after an action, but renderCraftList (far below) is what dispatches TO
-- them in the first place — a genuine circular reference. Declaring the local here (assigned later
-- with `renderCraftList = function() ... end`, no `local` keyword) lets every one of them capture
-- the right upvalue. Declared below any of its users, it would silently compile as a nil GLOBAL and
-- only fail when a button was actually clicked.
local renderCraftList

-- The Workbench's four tabs, rebuilt as HUD phase 3's "Spec Sheet" (design round, section C).
--
-- WHAT CHANGED AND WHY. All four were makeRow lists whose subtitle stated a COST but never what you
-- got for it: "Laser Cutter -> Plasma Drill, 60 steel plating · 20 gold contacts · 12 steel ingot"
-- tells you the price of a thing you cannot evaluate. The shape below always answers both halves —
-- what you have now, in real numbers, and what those same numbers become — because the before/after
-- is the actual decision and it was the one thing missing.
--
-- One builder rather than four layouts: these tabs differ in their DATA, not their shape (a thing
-- you own, its stats, what it cannot do yet, and one step you can buy). Four hand-built versions is
-- how the old rows drifted into stating costs four slightly different ways.
local SPEC_HERO_HEIGHT = 76
local SPEC_CARD_HEIGHT = 88
local SPEC_NEXT_HEIGHT = 92

-- `stats` renders right-aligned value/label pairs in the hero, `cards` is one or two supporting
-- panels, and `nextStep` is the buy row. nextStep = nil means maxed/owned, which draws nothing
-- rather than a disabled button: a row you can never press is noise once it is permanent.
type SpecStat = { value: string, label: string }
type SpecDelta = { label: string, from: string, to: string }
type SpecCard = { heading: string, body: string, accent: Color3? }
type SpecNext = {
	label: string,
	deltas: { SpecDelta }?,
	cost: string?,
	buttonText: string,
	blocked: boolean?, -- draws secondary + refuses with a toast instead of primary
	blockedReason: string?,
	onClick: (() -> ())?,
}

local function makeSpecSheet(opts: {
	eyebrow: string,
	title: string,
	badge: string?,
	stats: { SpecStat }?,
	cards: { SpecCard }?,
	nextStep: SpecNext?,
	extra: ((parent: Instance, y: number) -> ())?,
})
	local body = Hud.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, SPEC_HERO_HEIGHT + SPEC_CARD_HEIGHT + SPEC_NEXT_HEIGHT + Hud.SPACE.S * 2),
		Parent = listFrame,
	})

	local hero = Hud.new("Frame", {
		BackgroundColor3 = Hud.COLOR.PanelLight,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, SPEC_HERO_HEIGHT),
		Parent = body,
	}, { Hud.corner(Hud.RADIUS.Panel), Hud.stroke() })

	-- A tier badge rather than an item icon. There is no icon asset for a pickaxe tier, a suit tier
	-- or a base tier, and inventing three would put this screen behind art that does not exist —
	-- the project's "missing art never breaks the loop" rule pushed the other way here: draw
	-- something real out of type instead of reserving a hole for a picture.
	if opts.badge then
		Hud.new("TextLabel", {
			BackgroundColor3 = Hud.COLOR.Accent,
			BorderSizePixel = 0,
			Font = Hud.FONT.Display,
			Position = UDim2.new(0, Hud.SPACE.M, 0.5, -20),
			Size = UDim2.fromOffset(40, 40),
			Text = opts.badge,
			TextColor3 = Hud.COLOR.Panel,
			TextSize = Hud.TEXTSIZE.Title,
			Parent = hero,
		}, { Hud.corner(Hud.RADIUS.Button) })
	end

	local textX = opts.badge and (Hud.SPACE.M + 40 + Hud.SPACE.M) or Hud.SPACE.M

	Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Hud.FONT.Display,
		Position = UDim2.new(0, textX, 0, 14),
		Size = UDim2.new(0.55, -textX, 0, 14),
		Text = opts.eyebrow:upper(),
		TextColor3 = Hud.COLOR.Muted,
		TextSize = Hud.TEXTSIZE.Label,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = hero,
	})

	Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Hud.FONT.Display,
		Position = UDim2.new(0, textX, 0, 32),
		Size = UDim2.new(0.55, -textX, 0, 28),
		Text = opts.title,
		TextColor3 = Hud.COLOR.Text,
		TextSize = Hud.TEXTSIZE.Title,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = hero,
	})

	-- Stats lay out right-to-left from the hero's right edge, so a tab with two stats and one with
	-- three both stay flush to the same edge instead of needing per-tab positions.
	local statWidth = 84
	for index, stat in ipairs(opts.stats or {}) do
		local right = -(Hud.SPACE.M + statWidth * (index - 1))
		local column = Hud.new("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, right, 0.5, 0),
			Size = UDim2.fromOffset(statWidth, 44),
			Parent = hero,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.new(0, 0, 0, 2),
			Size = UDim2.new(1, 0, 0, 22),
			Text = stat.value,
			TextColor3 = Hud.COLOR.Text,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = column,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.new(0, 0, 0, 24),
			Size = UDim2.new(1, 0, 0, 14),
			Text = stat.label:upper(),
			TextColor3 = Hud.COLOR.Muted,
			TextSize = Hud.TEXTSIZE.Label,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = column,
		})
	end

	local cardsY = SPEC_HERO_HEIGHT + Hud.SPACE.S
	local cards = opts.cards or {}
	for index, card in ipairs(cards) do
		local width = 1 / math.max(#cards, 1)
		local gap = Hud.SPACE.S * (#cards - 1) / math.max(#cards, 1)

		local panel = Hud.new("Frame", {
			BackgroundColor3 = Hud.COLOR.Panel,
			BorderSizePixel = 0,
			Position = UDim2.new(width * (index - 1), Hud.SPACE.S * (index - 1), 0, cardsY),
			Size = UDim2.new(width, -gap, 0, SPEC_CARD_HEIGHT),
			Parent = body,
		}, { Hud.corner(Hud.RADIUS.Panel), Hud.stroke() })

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.new(0, Hud.SPACE.M, 0, 10),
			Size = UDim2.new(1, -Hud.SPACE.M * 2, 0, 14),
			Text = card.heading:upper(),
			TextColor3 = Hud.COLOR.Muted,
			TextSize = Hud.TEXTSIZE.Label,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = panel,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Body,
			Position = UDim2.new(0, Hud.SPACE.M, 0, 28),
			Size = UDim2.new(1, -Hud.SPACE.M * 2, 0, SPEC_CARD_HEIGHT - 38),
			Text = card.body,
			TextColor3 = card.accent or Hud.COLOR.Text,
			TextSize = Hud.TEXTSIZE.Body,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = panel,
		})

		if index == #cards and opts.extra then
			opts.extra(panel, 0)
		end
	end

	local nextStep = opts.nextStep
	if not nextStep then
		return body
	end

	local nextY = cardsY + (#cards > 0 and SPEC_CARD_HEIGHT + Hud.SPACE.S or 0)
	-- Its own UIStroke rather than Hud.stroke() plus a second one: a GuiObject honours ONE UIStroke,
	-- so adding the accent outline on top of the default Line one would leave whichever Roblox
	-- happens to pick — silently the wrong colour half the time. The buyable step is the only thing
	-- on this screen outlined in Accent, which is what makes it read as the action.
	local panel = Hud.new("Frame", {
		BackgroundColor3 = Hud.COLOR.Panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, nextY),
		Size = UDim2.new(1, 0, 0, SPEC_NEXT_HEIGHT),
		Parent = body,
	}, {
		Hud.corner(Hud.RADIUS.Panel),
		Hud.new("UIStroke", {
			Color = nextStep.blocked and Hud.COLOR.Line or Hud.COLOR.Accent,
			Thickness = 1,
		}),
	})

	Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Hud.FONT.Display,
		Position = UDim2.new(0, Hud.SPACE.M, 0, 12),
		Size = UDim2.new(1, -180, 0, 14),
		Text = nextStep.label:upper(),
		TextColor3 = nextStep.blocked and Hud.COLOR.Muted or Hud.COLOR.Accent,
		TextSize = Hud.TEXTSIZE.Label,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})

	-- The before/after row. Rendered as "0.5s -> 0.3s" per stat rather than as a single sentence so
	-- the eye can compare columns; Good on the right-hand value because every delta here is an
	-- improvement you are being asked to pay for.
	local deltaX = Hud.SPACE.M
	for _, delta in ipairs(nextStep.deltas or {}) do
		local group = Hud.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, deltaX, 0, 30),
			Size = UDim2.fromOffset(150, 34),
			Parent = panel,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Size = UDim2.new(1, 0, 0, 12),
			Text = delta.label:upper(),
			TextColor3 = Hud.COLOR.Muted,
			TextSize = Hud.TEXTSIZE.Label,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = group,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.new(0, 0, 0, 14),
			RichText = true,
			Size = UDim2.new(1, 0, 0, 18),
			-- Derived from the palette rather than pasted as a hex literal: RichText needs a string,
			-- and a literal here is exactly the kind of copy that stops matching COLOR.Good the
			-- first time the palette is retuned, with nothing to catch it.
			Text = ("%s  →  <font color=\"#%s\">%s</font>"):format(
				delta.from,
				Hud.COLOR.Good:ToHex(),
				delta.to
			),
			TextColor3 = Hud.COLOR.Muted,
			TextSize = Hud.TEXTSIZE.Body,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = group,
		})

		deltaX += 156
	end

	if nextStep.cost then
		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.new(0, Hud.SPACE.M, 1, -24),
			Size = UDim2.new(1, -180, 0, 18),
			Text = nextStep.cost,
			TextColor3 = nextStep.blocked and Hud.COLOR.Bad or Hud.COLOR.Text,
			TextSize = Hud.TEXTSIZE.Label,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = panel,
		})
	end

	Hud.button({
		variant = nextStep.blocked and "secondary" or "primary",
		dropShadow = not nextStep.blocked,
		text = nextStep.buttonText,
		anchorPoint = Vector2.new(1, 0.5),
		position = UDim2.new(1, -Hud.SPACE.M, 0.5, 0),
		size = UDim2.fromOffset(148, 48),
		parent = panel,
		onClick = function()
			-- A blocked step still RESPONDS. Silent rejection is the failure mode this project keeps
			-- paying for, and "why is this button dead" is exactly that in slow motion.
			if nextStep.blocked then
				Hud.showFailure(nextStep.label, nextStep.blockedReason or "You can't do that yet.")
				return
			end
			if nextStep.onClick then
				nextStep.onClick()
			end
		end,
	})

	return body
end

-- Which ores a given tool tier is the gate for — real data out of OreConfig rather than a hardcoded
-- sentence, so adding an ore with a MinToolTier automatically shows up as a reason to upgrade.
local function oresUnlockedAtToolTier(tier: number): string?
	local names = {}
	for key, ore in pairs(OreConfig.Ores) do
		if ore.MinToolTier == tier then
			table.insert(names, ore.DisplayName or key)
		end
	end
	if #names == 0 then
		return nil
	end
	table.sort(names)
	return table.concat(names, ", ")
end

local function renderToolRow()
	local currentTier = Hud.profile.ToolTier or 1
	local currentToolData = OreConfig.ToolTiers[currentTier]
	local nextTier = currentTier + 1
	local nextToolData = OreConfig.ToolTiers[nextTier]
	local maxTier = #OreConfig.ToolTiers

	-- Special pickaxes are a DIFFERENT KIND of thing from the tier ladder — sideways choices you
	-- hold one of, dropped by Epic rolls in Black Market cases, not bought here — so they share the
	-- tab (both are "what am I mining with") but sit in their own card rather than in the ladder.
	local owned = Hud.profile.OwnedTools or {}
	local equipped = Hud.profile.EquippedTool
	local equippedData = equipped and ToolModConfig.Tools[equipped]

	local anyOwned = false
	for _, key in ipairs(ToolModConfig.Order) do
		if owned[key] then
			anyOwned = true
			break
		end
	end

	local pickaxeBody
	if not anyOwned then
		pickaxeBody = "None yet — they drop from Epic rolls in Black Market cases."
	elseif equippedData then
		pickaxeBody = equippedData.DisplayName
	else
		pickaxeBody = "None equipped"
	end

	local gatedBy = nextToolData and oresUnlockedAtToolTier(nextTier)

	local nextStep = nil
	if nextToolData then
		local cost = OreConfig.ToolTierCosts[nextTier]
		nextStep = {
			label = ("Next — %s"):format(nextToolData.Name),
			deltas = {
				{ label = "Swing", from = ("%.2fs"):format(currentToolData.SwingTime), to = ("%.2fs"):format(nextToolData.SwingTime) },
				{ label = "Yield", from = ("%.2fx"):format(currentToolData.YieldMultiplier), to = ("%.2fx"):format(nextToolData.YieldMultiplier) },
			},
			cost = cost and Hud.costString(cost) or "Not configured",
			buttonText = "Upgrade",
			onClick = function()
				local result = Remotes.UpgradeTool:InvokeServer()
				if not result.Success then
					Hud.showFailure("Upgrade failed", result.Reason)
				end
			end,
		}
	end

	makeSpecSheet({
		badge = ("T%d"):format(currentTier),
		eyebrow = ("Tier %d of %d · equipped"):format(currentTier, maxTier),
		title = currentToolData and currentToolData.Name or "Tool",
		stats = {
			{ value = ("%.2fx"):format(currentToolData and currentToolData.YieldMultiplier or 1), label = "Yield" },
			{ value = ("%.2fs"):format(currentToolData and currentToolData.SwingTime or 0), label = "Swing" },
		},
		cards = {
			{
				heading = nextToolData and ("Unlocks at tier %d"):format(nextTier) or "Fully upgraded",
				body = gatedBy or (nextToolData and "Nothing new — just faster and richer." or "Nothing left to mine that this cannot break."),
				accent = gatedBy and Hud.COLOR.Text or Hud.COLOR.Muted,
			},
			{
				heading = "Special pickaxe",
				body = pickaxeBody,
				accent = equippedData and Hud.COLOR.Text or Hud.COLOR.Muted,
			},
		},
		nextStep = nextStep,
		-- Equip chips go inside the pickaxe card, which is the last one — one chip per OWNED
		-- pickaxe, so the card is a picker when there is something to pick and a plain readout
		-- when there is not.
		extra = function(panel)
			if not anyOwned then
				return
			end
			local row = Hud.new("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, Hud.SPACE.M, 1, -34),
				Size = UDim2.new(1, -Hud.SPACE.M * 2, 0, 26),
				Parent = panel,
			}, { Hud.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, Hud.SPACE.XS),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}) })

			local order = 0
			for _, key in ipairs(ToolModConfig.Order) do
				if owned[key] then
					order += 1
					local tool = ToolModConfig.Tools[key]
					local isEquipped = equipped == key
					Hud.button({
						variant = isEquipped and "primary" or "secondary",
						text = tool.DisplayName:gsub("%s.*$", ""), -- first word; the card states the full name
						layoutOrder = order,
						size = UDim2.fromOffset(84, 26),
						parent = row,
						onClick = function()
							-- nil unequips. NOT `isEquipped and nil or key`: in Lua that collapses,
							-- since `true and nil` is nil and `nil or key` is key, so the unequip
							-- branch would silently re-send the same key and nothing would ever come
							-- off. Same trap as the `Field = value or false` idiom this codebase
							-- already documents — an explicit local is the only safe way to pass a
							-- deliberate nil.
							local desired: string? = nil
							if not isEquipped then
								desired = key
							end
							local result = Remotes.EquipToolMod:InvokeServer(desired)
							if not result.Success then
								Hud.showFailure("Couldn't equip that pickaxe", result.Reason)
							else
								renderCraftList()
							end
						end,
					})
				end
			end
		end,
	})
end

-- The Auto-Miner is NOT a tier track — it is one structure you either own or do not
-- (AutoMinerConfig.MaxOwned is 1). So this tab's spec sheet has a built/not-built eyebrow and a
-- single Build step that disappears once it exists, rather than a ladder.
local function renderAutoMinerRow()
	local owned = Hud.profile.CraftedStructures and Hud.profile.CraftedStructures.AutoMiner
	local hasPass = Hud.profile.OwnedGamePasses and Hud.profile.OwnedGamePasses.AutoMiner
	local rate = AutoMinerConfig.BaseYieldPerTick * (hasPass and AutoMinerConfig.GamePassMultiplier or 1)
	local oreDisplayName = (OreConfig.Ores[AutoMinerConfig.OreKey] and OreConfig.Ores[AutoMinerConfig.OreKey].DisplayName)
		or AutoMinerConfig.OreKey

	local nextStep = nil
	if not owned then
		nextStep = {
			label = "Build it",
			deltas = {
				{ label = "Passive income", from = "none", to = ("%d %s / %ds"):format(
					AutoMinerConfig.BaseYieldPerTick, oreDisplayName, AutoMinerConfig.TickSeconds) },
			},
			cost = Hud.costString(AutoMinerConfig.Cost),
			buttonText = "Build",
			onClick = function()
				local result = Remotes.CraftAutoMiner:InvokeServer()
				if not result.Success then
					Hud.showFailure("Build failed", result.Reason)
				end
			end,
		}
	end

	makeSpecSheet({
		badge = owned and "ON" or "—",
		eyebrow = owned and "Built · running" or "Not built yet",
		title = "Mini Particle Accelerator",
		stats = owned and {
			{ value = ("%ds"):format(AutoMinerConfig.TickSeconds), label = "Every" },
			{ value = ("+%d"):format(rate), label = oreDisplayName },
		} or nil,
		cards = {
			{
				heading = "What it does",
				body = ("Drips out %s on its own, so there is always some progress happening while you are elsewhere. Deliberately modest — it is not meant to replace mining."):format(oreDisplayName),
				accent = Hud.COLOR.Muted,
			},
			{
				heading = "Game pass",
				body = hasPass
					and ("Applied — %d per tick instead of %d."):format(rate, AutoMinerConfig.BaseYieldPerTick)
					or ("The Auto-Miner pass would double this to %d per tick."):format(
						AutoMinerConfig.BaseYieldPerTick * AutoMinerConfig.GamePassMultiplier),
				accent = hasPass and Hud.COLOR.Good or Hud.COLOR.Muted,
			},
		},
		nextStep = nextStep,
	})
end

-- Suit tier is the mine shaft's version of ToolTier — same sequential track, backed by
-- MineShaftConfig.SuitTiers/SuitTierCosts and the UpgradeSuit remote. Each tier knocks Heat/Toxic
-- Air damage down by however many Tiers its Protection table specifies (see
-- MineShaftConfig.HazardTypes) rather than blocking a hazard outright.
local function renderSuitRow()
	local currentTier = Hud.profile.SuitTier or 1
	local currentSuitData = MineShaftConfig.SuitTiers[currentTier]
	local nextTier = currentTier + 1
	local nextSuitData = MineShaftConfig.SuitTiers[nextTier]
	local maxTier = #MineShaftConfig.SuitTiers

	local nextStep = nil
	if nextSuitData then
		local cost = MineShaftConfig.SuitTierCosts[nextTier]
		nextStep = {
			label = ("Next — %s"):format(nextSuitData.Name),
			deltas = {
				{
					label = "Heat",
					from = ("-%d tier"):format(currentSuitData.Protection.Heat),
					to = ("-%d tier"):format(nextSuitData.Protection.Heat),
				},
				{
					label = "Toxic air",
					from = ("-%d tier"):format(currentSuitData.Protection.ToxicAir),
					to = ("-%d tier"):format(nextSuitData.Protection.ToxicAir),
				},
			},
			cost = cost and Hud.costString(cost) or "Not configured",
			buttonText = "Upgrade",
			onClick = function()
				local result = Remotes.UpgradeSuit:InvokeServer()
				if not result.Success then
					Hud.showFailure("Suit upgrade failed", result.Reason)
				end
			end,
		}
	end

	makeSpecSheet({
		badge = ("T%d"):format(currentTier),
		eyebrow = ("Tier %d of %d · worn"):format(currentTier, maxTier),
		title = currentSuitData and currentSuitData.Name or "Suit",
		stats = {
			{ value = ("-%d"):format(currentSuitData and currentSuitData.Protection.ToxicAir or 0), label = "Toxic air" },
			{ value = ("-%d"):format(currentSuitData and currentSuitData.Protection.Heat or 0), label = "Heat" },
		},
		cards = {
			{
				heading = "Protects against",
				body = currentSuitData and currentSuitData.ProtectsAgainst or "Nothing yet",
				accent = Hud.COLOR.Text,
			},
			{
				heading = "How protection works",
				body = "A hazard tier is reduced, not blocked. Standing in Tier 2 Heat with -1 protection means you take Tier 1's damage.",
				accent = Hud.COLOR.Muted,
			},
		},
		nextStep = nextStep,
	})
end

----------------------------------------------------------------------
-- Shared item helpers — small readouts several tabs and panels need. (The "Turret slot panel"
-- banner that used to head this section went with the last of its code: the panel itself moved to
-- TurretPanel.lua a while back, and makeEquipmentRow — the only thing still sitting under the
-- orphaned heading — has now moved to WeldingPanel.lua.)
----------------------------------------------------------------------

-- How many currently-deployed instances of a given robotKey there are (DeployedRobots can hold
-- the same key more than once — a player owning 3 Sentry Bots can deploy all 3). Shared by
-- WeldingPanel's rig footer and the Inventory panel's Robots tab.
local function deployedCountForRobot(key: string): number
	local count = 0
	for _, deployedKey in ipairs(Hud.profile.DeployedRobots or {}) do
		if deployedKey == key then
			count += 1
		end
	end
	return count
end

-- Plain-English summary of a Forged weapon instance's rolled affixes, e.g.
-- "Sharpened +18% Damage, Hair-Trigger +32% Fire Rate" — or a placeholder if it rolled none
-- (every Common weapon, and any unlucky roll on a rarity that could've gotten more).
local function affixSummary(affixes)
	if not affixes or #affixes == 0 then
		return "No bonus affixes"
	end
	local parts = {}
	for _, affix in ipairs(affixes) do
		local statName = affix.Stat == "FireRateMultiplier" and "Fire Rate" or "Damage"
		table.insert(parts, ("%s +%d%% %s"):format(affix.Label, math.floor(affix.Magnitude * 100 + 0.5), statName))
	end
	return table.concat(parts, ", ")
end

-- All four of the Welding Station's tabs. Everything that used to be here — makeEquipmentRow (the
-- 90px title/stats/button row with three mod-slot buttons stapled underneath), makeRobotRow, the
-- MOD_SLOT_WIDTH those slot buttons were sized with, plus renderModsRow / renderTurretsRow /
-- renderDroneRows — moved into WeldingPanel.lua for HUD phase 3 (design round section C). See that
-- file's header for what each tab became and why; nothing else in this file used any of them.
--
-- Constructed HERE rather than up with the other panels because it needs deployedCountForRobot,
-- declared just above. `refresh` is wrapped in a closure rather than passed directly because
-- renderCraftList is forward-declared and still nil at this point in the chunk — a closure captures
-- the upvalue and sees the real function once it is assigned further down.
-- DERIVED from StationConfig rather than written out, so adding a tab to the Welding Station is
-- still a one-entry change: a new name routes here automatically and WeldingPanel.render warns that
-- it has no renderer for it, instead of falling through to MainHud's own dispatch chain and drawing
-- a blank panel. These four names are declared by no other station, so matching on the name alone
-- is unambiguous.
local WELDING_TABS: { [string]: boolean } = {}
for _, tabName in ipairs(StationConfig.Types.Welding.Tabs) do
	WELDING_TABS[tabName] = true
end

local weldingPanel = WeldingPanel.new({
	listFrame = listFrame,
	craftHeader = craftHeader,
	deployedCountForRobot = deployedCountForRobot,
	refresh = function()
		renderCraftList()
	end,
})

-- The Forge's Weapons tab — the Crucible (HUD phase 3, design round section C). Its Smelting tab is
-- the Batch Dial and stays in this file. Constructed alongside the Welding panel because it takes
-- the same three things and has the same `refresh` forward-reference constraint.
local forgePanel = ForgePanel.new({
	listFrame = listFrame,
	craftHeader = craftHeader,
	refresh = function()
		renderCraftList()
	end,
})

-- The Hacker Machine's Decode tab, and the case-opening reveal it raises. Constructed once here
-- rather than rebuilt per render because it owns animation state that has to survive a re-render --
-- an InventoryUpdate lands mid-reel, since OpenCase grants before the animation finishes.
local casePanel = CasePanel.new({
	listFrame = listFrame,
	refresh = function()
		renderCraftList()
	end,
})

-- Both station panels park a readout in the shared plate header, which renderCraftList's sweep
-- deliberately does not clear (it only empties listFrame). Hiding ALL of them up front and letting
-- whichever panel is about to draw show its own is the only arrangement where a readout cannot be
-- left over on a tab that does not own it — one-by-one hiding at each branch is a rule someone
-- forgets the next time a panel is added.
local function hideHeaderReadouts()
	weldingPanel.hideReadout()
	forgePanel.hideReadout()
end

----------------------------------------------------------------------
-- Base tab (Workbench). The two things that used to fill it both moved somewhere better — turret
-- placement went into the world (click a slot pad; see TurretPanel.lua) and the per-turret detail
-- went with it — so what is left is the base's own spec sheet plus the Research claim.
--
-- BaseTier and ResearchTier were merged into one progression number, so everything
-- here comes out of ResearchConfig.Tiers (six of them, Scrap Workbench through Foundry) rather than
-- BaseConfig, and the turret slot count is derived — TurretConfig.GetSlotCount, not a stored field.
--
-- This is the one Workbench tab whose next step can be blocked for reasons that are not money: a
-- wave milestone and a boss-wave CoreItem gate each tier as well as its cost. GetNextTierRequirements
-- already reports all three with per-entry Met flags, so the spec sheet states what is actually
-- missing instead of a flat "Locked".
local function renderBaseRow()
	local currentTier, currentIndex = ResearchConfig.GetTier(Hud.profile.ResearchTier or 1)
	local slotCount = TurretConfig.GetSlotCount(currentIndex)
	local maxTier = #ResearchConfig.Tiers

	local placedCount, storedCount = 0, 0
	for _, turret in ipairs(Hud.profile.Turrets or {}) do
		if turret.SlotIndex then
			placedCount += 1
		else
			storedCount += 1
		end
	end

	local req = ResearchConfig.GetNextTierRequirements(Hud.profile)
	local nextStep = nil

	if req then
		local nextTier = ResearchConfig.Tiers[req.TierIndex]
		local nextSlots = TurretConfig.GetSlotCount(req.TierIndex)

		-- Summarises what is still missing rather than only saying no. The full breakdown lives in
		-- the status panel's Research popup; this is the one-line version that tells you which of
		-- the three kinds of gate you are actually stuck behind.
		local missing = {}
		if not req.WaveMet then
			table.insert(missing, ("Wave %d"):format(req.RequiredWave))
		end
		if req.CoreRequirement and not req.CoreRequirement.Met then
			table.insert(missing, req.CoreRequirement.Key)
		end
		for _, entry in ipairs(req.Cost) do
			if not entry.Met then
				table.insert(missing, entry.Key)
			end
		end

		nextStep = {
			label = ("Next — Tier %d, %s"):format(req.TierIndex, req.Name),
			deltas = {
				{ label = "Wall", from = ("%d hp"):format(currentTier.WallHP), to = ("%d hp"):format(nextTier.WallHP) },
				{ label = "Turret slots", from = ("%d"):format(slotCount), to = ("%d"):format(nextSlots) },
			},
			cost = #missing > 0
				and ("Still need: %s"):format(table.concat(missing, ", "))
				or "Everything is ready — claiming rebuilds your base.",
			buttonText = req.CanClaim and "Claim" or "Locked",
			blocked = not req.CanClaim,
			blockedReason = #missing > 0
				and ("Still missing: %s."):format(table.concat(missing, ", "))
				or "Not claimable yet.",
			onClick = function()
				local result = Remotes.UpgradeResearch:InvokeServer()
				if not result.Success then
					Hud.showFailure("Research failed", result.Reason)
				else
					Hud.showToast(("Research Tier %d — your base has been rebuilt."):format(result.ResearchTier), 4)
					renderCraftList()
				end
			end,
		}
	end

	makeSpecSheet({
		badge = ("T%d"):format(currentIndex),
		eyebrow = ("Tier %d of %d · built"):format(currentIndex, maxTier),
		title = currentTier.Name,
		stats = {
			{ value = ("%d"):format(currentTier.FootprintHalfSize.X * 2), label = "Footprint" },
			{ value = ("%d"):format(slotCount), label = "Slots" },
			{ value = ("%d"):format(currentTier.WallHP), label = "Wall hp" },
		},
		cards = {
			{
				heading = "Turrets",
				body = ("%d placed of %d slots, %d in storage.\n\n%s"):format(
					placedCount,
					slotCount,
					storedCount,
					storedCount > 0
						and "Walk to a blue slot pad at your base and click it to place one."
						or "Buy a blueprint at the Hub Shop, build it at the Welding Station, then click a slot pad."
				),
				accent = Hud.COLOR.Muted,
			},
			{
				heading = req and "Gated by" or "Fully researched",
				body = req
					and ("Wave %d, a %s, and the materials. Each tier rebuilds the base and its stations."):format(
						req.RequiredWave,
						req.CoreRequirement and req.CoreRequirement.Key or "core item"
					)
					or "You are at the highest tier there is.",
				accent = Hud.COLOR.Muted,
			},
		},
		nextStep = nextStep,
	})
end

----------------------------------------------------------------------
-- Blueprints tab (Hub Shop) — StationConfig.Types.Shop's only tab. Lists today's rotating stock
-- (TurretConfig.GetRotatingStock, the same pure time-based function TurretShopService re-derives
-- server-side to validate the purchase) with a Buy button per type. Buying doesn't remove it from
-- the visible stock — nothing stops a player owning more than one of the same turret type, since
-- each purchase mints an independent instance (see TurretShopService.lua).
----------------------------------------------------------------------

local function renderBlueprintsRow()
	local stock = TurretConfig.GetRotatingStock(os.time())

	Hud.makeRow(
		"Hub Shop",
		("Stock rotates every %d hours · a blueprint unlocks the RECIPE permanently — build the turret itself at your Welding Station"):format(TurretConfig.ShopRotationPeriodSeconds / 3600),
		"OK",
		function() end
	).Parent = listFrame

	for _, typeKey in ipairs(stock) do
		local typeData = TurretConfig.Types[typeKey]
		if typeData then
			-- Already-owned blueprints stay listed rather than disappearing from the stock: seeing
			-- "Known" is clearer than a type silently vanishing, and the rotation is short enough
			-- that a missing row would read as a bug.
			local known = (Hud.profile.UnlockedTurretBlueprints or {})[typeKey] == true
			Hud.makeRow(
				typeData.DisplayName,
				known
					and ("%s · blueprint owned — craft it at your Welding Station"):format(typeData.Description)
					or ("%s · blueprint %s · then craft for %s"):format(
						typeData.Description, Hud.costString(typeData.BlueprintCost), Hud.costString(typeData.CraftCost)),
				known and "Known" or "Buy",
				function()
					if known then
						return
					end
					local result = Remotes.BuyTurretBlueprint:InvokeServer(typeKey)
					if not result.Success then
						Hud.showFailure("Buy blueprint failed", result.Reason)
					else
						Hud.showToast(("%s blueprint learned — build it at your Welding Station."):format(typeData.DisplayName), 4)
						renderCraftList()
					end
				end
			).Parent = listFrame
		end
	end
end

----------------------------------------------------------------------
-- Turrets tab (Welding Station) — assembling a turret from a blueprint you've bought.
--
-- Buying a blueprint used to hand you a finished turret outright, which meant one currency bought
-- base defense outright and skipped the game's actual loop. Now the shop sells the RECIPE and this
-- is where the turret gets built, out of Scrap + raw ore — so a turret costs you a raid AND a
-- mining run, same as everything else worth having.
----------------------------------------------------------------------

-- Formats seconds as M:SS / H:MM, for decode countdowns and the restock timer.
local function formatClock(seconds: number): string
	seconds = math.max(math.floor(seconds), 0)
	if seconds >= 3600 then
		return ("%dh %02dm"):format(seconds // 3600, (seconds % 3600) // 60)
	end
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

----------------------------------------------------------------------
-- Cases tab (Black Market dealer) — rotating stock of sealed cases.
--
-- Odds are shown per case rather than hidden. A sealed-case system that conceals its own rates is
-- both worse to play against and, once real money touches it, a policy problem — see the
-- randomized-rewards note in DESIGN_NOTES' superseded Main shop section.
----------------------------------------------------------------------

local function renderCasesRow()
	Hud.makeRow(
		"Black Market",
		("Stock rotates in %s · decode what you buy at the Hacker Machine"):format(
			formatClock(CaseConfig.SecondsUntilRestock(os.time()))),
		"OK",
		function() end
	).Parent = listFrame

	for _, caseKey in ipairs(CaseConfig.GetRotatingStock(os.time())) do
		local case = CaseConfig.Cases[caseKey]
		if case then
			local owned = (Hud.profile.Cases or {})[caseKey] or 0

			-- Rendered highest-rarity-first so the interesting odds lead, rather than in the
			-- RarityOrder walk where Common always comes first and buries them.
			local parts = {}
			for i = #CaseConfig.RarityOrder, 1, -1 do
				local rarity = CaseConfig.RarityOrder[i]
				local weight = case.Odds[rarity]
				if weight then
					local total = 0
					for _, w in pairs(case.Odds) do
						total += w
					end
					table.insert(parts, ("%s %.0f%%"):format(rarity, weight / total * 100))
				end
			end

			local costText = case.RobuxProductKey and "Robux" or Hud.costString(case.Cost)
			Hud.makeRow(
				("%s%s"):format(case.DisplayName, owned > 0 and (" (x%d owned)"):format(owned) or ""),
				("%s · %s · decode %s"):format(costText, table.concat(parts, ", "), formatClock(case.DecodeSeconds)),
				case.RobuxProductKey and "Robux" or "Buy",
				function()
					if case.RobuxProductKey then
						-- The Robux path needs a real developer product id in ShopConfig; every id is
						-- still 0, so this cannot work until those are created in the Creator
						-- Dashboard. Says so rather than failing silently.
						Hud.showFailure("Not set up", "Robux cases need their product id filled into ShopConfig.lua first.")
						return
					end
					local result = Remotes.BuyCase:InvokeServer(caseKey)
					if not result.Success then
						Hud.showFailure("Buy failed", result.Reason)
					else
						Hud.showToast(("Bought a %s. Decode it at the Hacker Machine."):format(case.DisplayName), 4)
						renderCraftList()
					end
				end
			).Parent = listFrame
		end
	end
end

----------------------------------------------------------------------
-- Decode tab (Hacker Machine) — one job at a time, with the two rush paths.
----------------------------------------------------------------------

renderCraftList = function()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- All four Welding Station tabs live in WeldingPanel.lua — Robots, Mods, Turrets and Drones are
	-- declared by no other station (see StationConfig.Types), so the tab name alone routes them.
	hideHeaderReadouts()

	if WELDING_TABS[currentTab] then
		weldingPanel.render(currentTab)
		return
	end

	if currentTab == "Auto-Miner" then
		renderAutoMinerRow()
		return
	elseif currentTab == "Tools" then
		-- One call, not two: the special pickaxes used to be their own list of rows under the tier
		-- ladder, and are now a card inside the tool's own spec sheet (see renderToolRow's `extra`).
		renderToolRow()
		return
	elseif currentTab == "Suit" then
		renderSuitRow()
		return
	elseif currentTab == "Base" then
		renderBaseRow()
		return
	elseif currentTab == "Blueprints" then
		renderBlueprintsRow()
		return
	elseif currentTab == "Cases" then
		renderCasesRow()
		return
	elseif currentTab == "Decode" then
		casePanel.render()
		return
	elseif currentTab == "Weapons" then
		forgePanel.render()
		return
	elseif currentTab == "Smelting" then
		renderSmeltingTab()
		return
	end

	-- Nothing falls through anymore: every tab any station declares has a branch above. A tab name
	-- that reaches here is a StationConfig entry with no renderer, which used to present as an empty
	-- panel and nothing in Output — the exact silent failure this project keeps getting bitten by.
	warn(("[MainHud] no renderer for craft tab %q"):format(tostring(currentTab)))
end

-- Keyed by tab NAME, not creation order/index — rebuildTabs destroys and recreates these every
-- time a different station's menu opens, so an index captured in a closure would end up pointing
-- at whatever tab happens to occupy that slot in the NEW row, not the one it was built for.
local tabButtons: { [string]: TextButton } = {}

-- Shared by the tab buttons below and by the base stations further down (clicking a Workbench/
-- Welding Station in the world jumps straight to that station's tab via the same path).
--
-- Routed through Hud.setButtonVariant rather than writing BackgroundColor3 directly, now that it
-- exists: it rewrites the button's REST color (what hover/press are derived from) as well as the
-- fill, so a hover-out after selecting a tab tweens back to the newly-selected color instead of
-- whatever stale fill the button was built with — see setButtonVariant's own comment in HudKit.
local function selectTab(name: string)
	currentTab = name
	for tabName, button in pairs(tabButtons) do
		Hud.setButtonVariant(button, tabName == name and "primary" or "secondary")
	end
	renderCraftList()
end

local function makeTabButton(name: string)
	local button = Hud.button({
		variant = currentTab == name and "primary" or "secondary",
		text = name:upper(), -- static chrome uppercase treatment, same as every other panel's tabs
		size = UDim2.new(0, 90, 1, 0), -- shrunk from 100 to fit 6 tabs (added Mods) in the same row width
		-- Hard offset shadow instead of the default bevel gradient, for consistency with
		-- InventoryPanel's tabs (see that file's makeTabButton) — solid squares with a drop shadow
		-- under them, not a gradient-filled pill.
		dropShadow = true,
		parent = tabRow,
		onClick = function()
			selectTab(name)
		end,
	})
	-- HudKit.button() defaults every button to FONT.BodyBold/TEXTSIZE.Body — overridden here to the
	-- small-uppercase-label treatment every other panel's tabs use. TextSize 11, not
	-- Hud.TEXTSIZE.Label (13): same width budget as InventoryPanel's tabs (90px here vs. its 91px),
	-- and this row's longest label ("Auto-Miner", 10 uppercase characters) sits at the same kerning
	-- risk "MATERIALS" (9 characters) hit at 13 there — see InventoryPanel.lua's makeTabButton for
	-- the full per-character estimate this mirrors.
	button.Font = Hud.FONT.Display
	button.TextSize = 11
	tabButtons[name] = button
	return button
end

-- Rebuilds the tab row down to exactly the tabs one station's menu should offer — e.g. a Welding
-- Station's row only ever gets Weapons/Robots/Mods, never Tools/Auto-Miner/Suit. Called by
-- openStationMenu every time the menu is (re)opened, since a different station can be clicked
-- next without the HUD ever needing a page reload. No tabs are created at startup — the menu
-- starts empty because there's nothing to show until a station opens it for the first time.
local function rebuildTabs(tabNames: { string })
	for _, child in ipairs(tabRow:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	table.clear(tabButtons) -- old entries would otherwise point at now-destroyed buttons forever;
		-- harmless (setButtonVariant/setButtonFill both guard on button.Parent) but an unbounded leak
	for _, name in ipairs(tabNames) do
		makeTabButton(name)
	end
end

-- Inventory panel — extracted to InventoryPanel.lua; constructed below, after the Ultimate
-- picker it depends on (openUltPicker) exists. See InventoryPanel.lua's header for the full
-- rationale and for why makeItemTile/TILE_SIZE come back out of it for the Smelting tab to reuse.

----------------------------------------------------------------------
-- Ultimate picker — the fourth, exclusive weapon slot (see UltimateConfig.lua).
--
-- Deliberately its own popup rather than a mode on ModPicker: the two pools are mutually
-- exclusive by design, and sharing one picker would mean a filter flag whose only job is to make
-- sure the wrong kind never shows up. Two small pickers cannot mix them at all.
----------------------------------------------------------------------

local ultPicker = {}
ultPicker.itemKey = nil

ultPicker.frame = Hud.new("Frame", {
	Name = "UltimatePicker",
	BackgroundColor3 = Hud.COLOR.Panel,
	Position = UDim2.new(0.5, -180, 0.5, -190),
	Size = UDim2.new(0, 360, 0, 380),
	Visible = false,
	ZIndex = 7,
	Parent = Hud.screenGui,
}, { Hud.corner(10), Hud.stroke() })

Hud.new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 10),
	Size = UDim2.new(1, -60, 0, 24),
	Font = Enum.Font.SourceSansBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = (ModConfig.Rarities[UltimateConfig.Rarity] or {}).Color or Hud.COLOR.Text,
	TextSize = 18,
	Text = "Ultimate Slot",
	Parent = ultPicker.frame,
})

ultPicker.close = Hud.button({
	variant = "secondary",
	text = "X",
	size = UDim2.new(0, 28, 0, 28),
	position = UDim2.new(1, -40, 0, 8),
	parent = ultPicker.frame,
})

ultPicker.list = Hud.new("ScrollingFrame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 44),
	Size = UDim2.new(1, -24, 1, -56),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	Parent = ultPicker.frame,
}, { Hud.new("UIListLayout", { Padding = UDim.new(0, 6) }) })

local function closeUltPicker()
	ultPicker.frame.Visible = false
	ultPicker.itemKey = nil
end
ultPicker.close.MouseButton1Click:Connect(closeUltPicker)

local function selectUltimate(ultimateKey: string?)
	local itemKey = ultPicker.itemKey
	closeUltPicker() -- close first so a slow round trip can't leave a stale popup open
	local result = Remotes.EquipUltimate:InvokeServer(itemKey, ultimateKey)
	if not result.Success then
		Hud.showFailure("Equip Ultimate failed", result.Reason)
	end
end

local function renderUltPickerList()
	for _, child in ipairs(ultPicker.list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local current = (Hud.profile.EquippedUltimate or {})[ultPicker.itemKey]

	Hud.makeRow("None", "Leave the Ultimate slot empty",
		(current == nil) and "Selected" or "Select",
		function() selectUltimate(nil) end
	).Parent = ultPicker.list

	local owned = Hud.profile.OwnedUltimates or {}
	local any = false
	for _, key in ipairs(UltimateConfig.SortedKeys()) do
		if owned[key] then
			any = true
			local data = UltimateConfig.Mods[key]
			Hud.makeRow(
				("[%s] %s"):format((ModConfig.Rarities[UltimateConfig.Rarity] or {}).Badge or "M", data.DisplayName),
				data.Description,
				(key == current) and "Selected" or "Select",
				function() selectUltimate(key) end
			).Parent = ultPicker.list
		end
	end

	if not any then
		Hud.makeRow("No Ultimates yet",
			"They only come from Black Market cases — not craftable.",
			"OK", function() end
		).Parent = ultPicker.list
	end
end

local function openUltPicker(itemKey: string)
	ultPicker.itemKey = itemKey
	renderUltPickerList()
	ultPicker.frame.Visible = true
end

-- The rest of the Inventory panel (detail popup, grid tiles, tabs, openInventory) is built by
-- InventoryPanel.new below, once openUltPicker above exists — it needs to hand that function in.
local inventoryPanel = InventoryPanel.new({
	deployedCountForRobot = deployedCountForRobot,
	affixSummary = affixSummary,
	openUltPicker = openUltPicker,
	ORE_DISPLAY_ORDER = ORE_DISPLAY_ORDER,
})
local openInventory = inventoryPanel.openInventory
local renderInvList = inventoryPanel.renderInvList
local refreshInvDetailIfShowing = inventoryPanel.refreshInvDetailIfShowing
-- The Smelting tab's ore-picker popup (further down) reuses these rather than keeping its own copy.
local makeItemTile = inventoryPanel.makeItemTile
local TILE_SIZE = inventoryPanel.TILE_SIZE

----------------------------------------------------------------------
-- Ore Smelting — the Forge's second mechanic, alongside rolling weapons (see RefinedOreConfig.lua
-- /SmeltService.lua). A single square panel inside the Forge's "Smelting" tab with three states:
-- (1) nothing picked yet — one big centered icon that opens a popup grid into your raw ore
-- inventory; (2) an ore picked but not started — a quantity stepper (in RefineRatio-sized steps)
-- plus a "Smelt" button that appears once something's actually pickable; (3) a job running
-- server-side — a live countdown/progress bar, re-rendered once a second by the task.spawn loop
-- at the bottom of this section (InventoryUpdate patches only arrive on start/finish, not every
-- tick in between).
----------------------------------------------------------------------

-- All 5 raw ores can be smelted — unlike ORE_DISPLAY_ORDER (trimmed for the old currency readout,
-- see that variable's own comment), this includes VoidiumShard.
local SMELT_ORE_ORDER = { "ScrapIron", "CopperWire", "SteelPlating", "GoldContacts", "VoidiumShard" }

-- Which raw ore is picked but not yet started (nil = nothing picked, showing the "click to pick"
-- icon instead) and how much of it. Purely client-side UI state until StartSmelt actually
-- succeeds — reset back to nil/0 the instant it does, since Hud.profile.SmeltJob being truthy takes
-- over the panel from there (state 3 above always wins over state 2 in renderSmeltingTab below).
local smeltSelectedOreKey = nil
local smeltQuantity = 0

local function formatDuration(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return ("%d:%02d"):format(minutes, secs)
end

-- Smelting, rebuilt as HUD phase 3's "Batch Dial" (design round, section C).
--
-- WHAT CHANGED AND WHY. The old shape was a 260px square that started blank, plus a popup grid
-- covering the HUD to pick an ore. Two problems the redesign fixes. The popup hid the very
-- inventory numbers you were choosing between — you picked an ore, then had to close the thing to
-- see how much of it you had. And nothing on screen ever said that RefinedOreConfig's batch time is
-- LOGARITHMIC: a bigger batch is strictly cheaper per ore, which is the only real decision this tab
-- has, and it was completely invisible.
--
-- So the ore list is now a permanent left rail (the popup and openOrePicker are deleted outright,
-- not hidden), and the right side is one large batch-time readout with the per-ore cost spelled out
-- directly beneath it, next to what that same ore cost at the smallest batch.
--
-- THE ARC IS A REAL RING. The design draws batch time as a ring filling clockwise, and it is one —
-- see HudKit.ring for how it is drawn without an arc primitive or any art. It was briefly a
-- straight segmentBar underneath the dial instead, which was wrong on both counts: it was not the
-- agreed layout, and at 20 cells refreshed once a second it visibly stepped rather than swept.
-- The ring drives itself on Heartbeat off os.clock(), so it moves continuously between the
-- whole-second FinishTime values the server actually sends.
--
-- QUANTITY IS ALWAYS A LEGAL MULTIPLE. Every path that sets smeltQuantity below snaps it to a
-- whole number of RefineRatio-sized batches. This is not cosmetic: SmeltService.StartSmelt rejects
-- a quantity that is not a positive multiple of the ore's ratio, so a free-dragging slider that
-- could land on 91 Scrap Iron would produce a rejection the player cannot interpret. The old
-- bulk-add buttons got this right by adding BATCHES rather than raw ore; the track below keeps that
-- guarantee by snapping every click.
local smelt = {
	railWidth = 176,
	dialSize = 168,
	-- The tab's body fills the plate rather than scrolling: listFrame's own height is the plate
	-- height minus the header/tab stack (116) — see craftFrame's vertical-stack comment — and this
	-- is that, less the 12px bottom margin the surface's other edges use. Derived from the Forge's
	-- configured size rather than written out, for the same reason ForgePanel's and WeldingPanel's
	-- are: the
	-- plate is sized per station now, and a constant here would silently stop filling it.
	height = (StationConfig.Types.Forge.PanelSize or StationConfig.DefaultPanelSize).Y - 116 - 12,
}

-- Snap a raw-ore quantity down to a whole number of batches, never below one batch. Every setter
-- goes through this — see the section comment above for why an unsnapped quantity is a bug, not a
-- rounding detail.
local function snapSmeltQuantity(quantity: number, refineRatio: number): number
	local batches = math.max(math.floor(quantity / refineRatio), 1)
	return batches * refineRatio
end

-- How many raw ore of this key can actually be committed right now, snapped. Zero means the player
-- cannot smelt this ore at all yet (they hold less than one batch of it).
local function maxSmeltQuantity(oreKey: string): number
	local oreData = RefinedOreConfig.Ores[oreKey]
	local owned = (Hud.profile.OreCounts or {})[oreKey] or 0
	if owned < oreData.RefineRatio then
		return 0
	end
	return math.floor(owned / oreData.RefineRatio) * oreData.RefineRatio
end

-- One row of the left rail. A TextButton rather than a Frame so the whole row is the hit target,
-- not just an icon — the old popup's tiles were 64px squares and this is a 28px-tall row, so
-- anything smaller than the full row would be a fiddly target.
local function makeSmeltOreRow(oreKey: string, order: number, parent: Instance)
	local oreData = RefinedOreConfig.Ores[oreKey]
	local displayName = (OreConfig.Ores[oreKey] and OreConfig.Ores[oreKey].DisplayName) or oreKey
	local owned = (Hud.profile.OreCounts or {})[oreKey] or 0
	local usable = maxSmeltQuantity(oreKey) > 0
	local selected = smeltSelectedOreKey == oreKey

	local row = Hud.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = selected and Hud.COLOR.PanelLight or Hud.COLOR.Panel,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 44),
		Text = "",
		Parent = parent,
	})

	-- Selection reads as an accent edge on the left, matching the design's rail and the same
	-- language ResearchPanel's active row uses — not a fill swap, which at this size would fight
	-- the plate behind it.
	Hud.new("Frame", {
		BackgroundColor3 = selected and Hud.COLOR.Accent or Hud.COLOR.Line,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 3, 1, 0),
		Parent = row,
	})

	local icon = Hud.new("ImageLabel", {
		BackgroundTransparency = 1,
		Image = Hud.getItemIcon(oreKey) or "",
		ImageColor3 = usable and Color3.new(1, 1, 1) or Hud.COLOR.Muted,
		Position = UDim2.new(0, 11, 0.5, -11),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(22, 22),
		Parent = row,
	})

	Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Hud.FONT.Body,
		Position = UDim2.new(0, 41, 0, 5),
		Size = UDim2.new(1, -49, 0, 18),
		Text = displayName,
		TextColor3 = usable and Hud.COLOR.Text or Hud.COLOR.Muted,
		TextSize = Hud.TEXTSIZE.Body,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	-- Owned count and refine ratio share the second line: the ratio is what turns "412" into "how
	-- many ingots is that", and hiding it behind a tooltip would put the arithmetic back on the
	-- player. Muted throughout because the row's job is selection, not readout.
	Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Hud.FONT.Mono,
		Position = UDim2.new(0, 41, 0, 22),
		Size = UDim2.new(1, -49, 0, 16),
		Text = ("%d  ·  %d:1"):format(owned, oreData.RefineRatio),
		TextColor3 = Hud.COLOR.Muted,
		TextSize = Hud.TEXTSIZE.Label,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	if not usable then
		-- Deliberately still VISIBLE rather than filtered out of the rail: an ore you cannot yet
		-- smelt is information ("this exists, go mine it"), and a rail whose contents change length
		-- as your inventory does is harder to build a habit around than a fixed list of five.
		icon.ImageTransparency = 0.4
		return row
	end

	row.MouseButton1Click:Connect(function()
		smeltSelectedOreKey = oreKey
		-- Re-snap against the NEW ore's ratio rather than carrying the old quantity across: 90 is a
		-- legal Scrap Iron batch (3:1) but not a legal Voidium one (1:1 — legal, but 90 of them is
		-- not something the player asked for). Starting each ore at one batch is the honest default.
		smeltQuantity = oreData.RefineRatio
		renderCraftList()
	end)

	return row
end

-- Assigns into the `local renderSmeltingTab` forward-declared up in the Forge tab section — see
-- that comment for why. State is picked by Hud.profile.SmeltJob (server-authoritative, always
-- wins) and then smeltSelectedOreKey (client-only, pending a click).
renderSmeltingTab = function()
	local body = Hud.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, smelt.height),
		Parent = listFrame,
	})

	local rail = Hud.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, smelt.railWidth, 1, 0),
		Parent = body,
	}, { Hud.new("UIListLayout", {
		Padding = UDim.new(0, Hud.SPACE.XS),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}) })

	for order, oreKey in ipairs(SMELT_ORE_ORDER) do
		makeSmeltOreRow(oreKey, order, rail)
	end

	local stage = Hud.new("Frame", {
		BackgroundColor3 = Hud.COLOR.Panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0, smelt.railWidth + Hud.SPACE.M, 0, 0),
		Size = UDim2.new(1, -(smelt.railWidth + Hud.SPACE.M), 1, 0),
		Parent = body,
	}, { Hud.corner(Hud.RADIUS.Panel), Hud.stroke() })

	-- The circular readout. UICorner at scale 0.5 makes a Frame a circle; see the section comment
	-- for why this is a plate rather than the design's filling ring.
	local dial = Hud.new("Frame", {
		BackgroundColor3 = Hud.darken(Hud.COLOR.Panel, 0.25),
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, -smelt.dialSize / 2, 0, Hud.SPACE.L),
		Size = UDim2.fromOffset(smelt.dialSize, smelt.dialSize),
		Parent = stage,
	}, { Hud.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Hud.stroke() })

	local dialValue = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Hud.FONT.Mono,
		Position = UDim2.new(0, 0, 0.5, -26),
		Size = UDim2.new(1, 0, 0, 34),
		TextColor3 = Hud.COLOR.Text,
		TextSize = 30,
		Parent = dial,
	})

	local dialCaption = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Hud.FONT.Display,
		Position = UDim2.new(0, 0, 0.5, 10),
		Size = UDim2.new(1, 0, 0, 16),
		TextColor3 = Hud.COLOR.Muted,
		TextSize = Hud.TEXTSIZE.Label,
		Parent = dial,
	})

	local job = Hud.profile.SmeltJob

	if job then
		local oreDisplayName = (OreConfig.Ores[job.OreKey] and OreConfig.Ores[job.OreKey].DisplayName)
			or job.OreKey
		local refinedInfo = RefinedOreConfig.ByRefinedKey[job.RefinedKey]
		local refinedDisplayName = refinedInfo and refinedInfo.DisplayName or job.RefinedKey

		-- Re-derives the batch's original duration from the same shared formula rather than storing
		-- it on the job, so remaining/duration gives a 0..1 progress ratio directly.
		local duration = math.max(RefinedOreConfig.ComputeSmeltSeconds(job.Quantity), 1)

		-- The arc sweeps on Heartbeat rather than on the tab's once-a-second re-render. os.time()
		-- has whole-second resolution, so a per-second update can only ever step the ring 1/duration
		-- at a time — visibly jumping, which is exactly what this replaces. os.clock() is
		-- monotonic and sub-millisecond, so the remaining fraction is interpolated between the
		-- whole seconds the server actually gave us.
		local ring = Hud.ring(dial, { size = smelt.dialSize, thickness = 10 })
		local anchorClock = os.clock()
		local anchorRemaining = job.FinishTime - os.time()

		local sweep
		sweep = RunService.Heartbeat:Connect(function()
			-- The tab re-renders (and destroys this dial) on every InventoryUpdate, so the
			-- connection has to end with the instance it drives or it leaks one Heartbeat handler
			-- per render for the rest of the session.
			if not dial.Parent then
				sweep:Disconnect()
				return
			end

			local remaining = anchorRemaining - (os.clock() - anchorClock)
			ring.setProgress(math.clamp(1 - (remaining / duration), 0, 1))

			-- SmeltService's completion loop only sweeps every RefinedOreConfig.SmeltTime
			-- .TickSeconds (2s), so the countdown genuinely reaches zero a moment before the ore is
			-- granted. Saying "finishing" is the honest reading of that gap — a frozen 0:00 reads
			-- as a hung job.
			dialValue.Text = remaining > 0 and formatDuration(remaining) or "··"
			dialCaption.Text = remaining > 0 and "REMAINING" or "FINISHING"
		end)

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Body,
			Position = UDim2.new(0, Hud.SPACE.L, 0, smelt.dialSize + Hud.SPACE.XL),
			Size = UDim2.new(1, -Hud.SPACE.L * 2, 0, 22),
			Text = ("Smelting %d %s"):format(job.Quantity, oreDisplayName),
			TextColor3 = Hud.COLOR.Text,
			TextSize = Hud.TEXTSIZE.Body,
			Parent = stage,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.new(0, Hud.SPACE.L, 0, smelt.dialSize + Hud.SPACE.XL + 22),
			Size = UDim2.new(1, -Hud.SPACE.L * 2, 0, 20),
			Text = ("→  %d %s"):format(job.RefinedAmount, refinedDisplayName),
			TextColor3 = Hud.COLOR.Good,
			TextSize = Hud.TEXTSIZE.Body,
			Parent = stage,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Body,
			Position = UDim2.new(0, Hud.SPACE.L, 1, -44),
			Size = UDim2.new(1, -Hud.SPACE.L * 2, 0, 34),
			Text = "One smelt at a time — the next batch can start the moment this one finishes.",
			TextColor3 = Hud.COLOR.Muted,
			TextSize = Hud.TEXTSIZE.Label,
			TextWrapped = true,
			Parent = stage,
		})

		return
	end

	if not smeltSelectedOreKey then
		dialValue.Text = "—"
		dialCaption.Text = "BATCH TIME"

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Body,
			Position = UDim2.new(0, Hud.SPACE.L, 0, smelt.dialSize + Hud.SPACE.XL),
			Size = UDim2.new(1, -Hud.SPACE.L * 2, 0, 40),
			Text = "Pick an ore on the left. Bigger batches cost less time per ore, so it pays to hold out for a full load.",
			TextColor3 = Hud.COLOR.Muted,
			TextSize = Hud.TEXTSIZE.Body,
			TextWrapped = true,
			Parent = stage,
		})

		return
	end

	local oreKey = smeltSelectedOreKey
	local oreData = RefinedOreConfig.Ores[oreKey]
	local refinedInfo = RefinedOreConfig.ByRefinedKey[oreData.RefinedKey]
	local refinedDisplayName = refinedInfo and refinedInfo.DisplayName or oreData.RefinedKey
	local oreDisplayName = (OreConfig.Ores[oreKey] and OreConfig.Ores[oreKey].DisplayName) or oreKey
	local maxQuantity = maxSmeltQuantity(oreKey)

	smeltQuantity = math.clamp(
		snapSmeltQuantity(smeltQuantity, oreData.RefineRatio),
		oreData.RefineRatio,
		math.max(maxQuantity, oreData.RefineRatio)
	)

	local ratioLabel = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Hud.FONT.Body,
		Position = UDim2.new(0, Hud.SPACE.L, 0, smelt.dialSize + Hud.SPACE.L),
		Size = UDim2.new(1, -Hud.SPACE.L * 2, 0, 24),
		RichText = true,
		TextColor3 = Hud.COLOR.Text,
		TextSize = Hud.TEXTSIZE.Body,
		Parent = stage,
	})

	-- THE POINT OF THIS SCREEN. ComputeSmeltSeconds is BaseSeconds + LogSecondsPerOre * ln(qty), so
	-- seconds-per-ore falls the whole way up the range — 20 + 24*ln(3) at one Scrap Iron batch is
	-- ~8.8s per ore, and at 90 it is ~1.4s. Nothing in the old UI said so, so nobody could act on it.
	local perOreLabel = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Hud.FONT.Mono,
		Position = UDim2.new(0, Hud.SPACE.L, 0, smelt.dialSize + Hud.SPACE.L + 24),
		Size = UDim2.new(1, -Hud.SPACE.L * 2, 0, 20),
		TextColor3 = Hud.COLOR.Muted,
		TextSize = Hud.TEXTSIZE.Label,
		Parent = stage,
	})

	local trackY = smelt.dialSize + Hud.SPACE.L + 56

	local track = Hud.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Hud.darken(Hud.COLOR.Panel, 0.3),
		BorderSizePixel = 0,
		Position = UDim2.new(0, Hud.SPACE.L, 0, trackY),
		Size = UDim2.new(1, -Hud.SPACE.L * 2, 0, 18),
		Text = "",
		Parent = stage,
	})

	local fill = Hud.new("Frame", {
		BackgroundColor3 = Hud.COLOR.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = track,
	})

	local handle = Hud.new("Frame", {
		BackgroundColor3 = Hud.COLOR.Text,
		BorderSizePixel = 0,
		Position = UDim2.new(0, -2, 0, -3),
		Size = UDim2.fromOffset(4, 24),
		Parent = track,
	})

	-- Everything the quantity drives, updated IN PLACE. This is not a tidiness choice: dragging has
	-- to repaint on every mouse move, and repainting by calling renderCraftList would destroy the
	-- very track the pointer is holding, ending the drag on its first frame. The old click-only
	-- handler got away with a re-render precisely because a click is over before the rebuild lands.
	local function applySmeltQuantity(quantity: number)
		smeltQuantity = math.clamp(
			snapSmeltQuantity(quantity, oreData.RefineRatio),
			oreData.RefineRatio,
			math.max(maxQuantity, oreData.RefineRatio)
		)

		local seconds = RefinedOreConfig.ComputeSmeltSeconds(smeltQuantity)
		dialValue.Text = formatDuration(seconds)

		ratioLabel.Text = ("<b>%d</b> %s  →  <b>%d</b> %s"):format(
			smeltQuantity,
			oreDisplayName,
			smeltQuantity / oreData.RefineRatio,
			refinedDisplayName
		)

		local perOre = seconds / smeltQuantity
		local smallestBatch = oreData.RefineRatio
		local perOreAtSmallest = RefinedOreConfig.ComputeSmeltSeconds(smallestBatch) / smallestBatch
		perOreLabel.Text = ("%.1fs per ore  ·  %.1fs at one batch"):format(perOre, perOreAtSmallest)
		perOreLabel.TextColor3 = perOre < perOreAtSmallest and Hud.COLOR.Good or Hud.COLOR.Muted

		local alpha = if maxQuantity > oreData.RefineRatio
			then (smeltQuantity - oreData.RefineRatio) / (maxQuantity - oreData.RefineRatio)
			else 1
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		handle.Position = UDim2.new(alpha, -2, 0, -3)
	end

	dialCaption.Text = "BATCH TIME"
	applySmeltQuantity(smeltQuantity)

	if maxQuantity > oreData.RefineRatio then
		-- Drag, not just click. The pointer routinely leaves the 18px-tall track while dragging
		-- along it, so the move and release handlers live on UserInputService rather than on the
		-- track itself — a track-local InputChanged stops firing the moment the cursor strays
		-- vertically, which reads as the slider randomly sticking.
		local dragging = false
		local moveConn, endConn

		local function quantityAt(positionX: number): number
			-- AbsolutePosition/AbsoluteSize rather than any click offset: MouseButton1Click carries
			-- no position at all, and this is the same arithmetic that maps a screen point onto a
			-- value everywhere else in this HUD.
			local width = track.AbsoluteSize.X
			if width <= 0 then
				return smeltQuantity
			end
			local alpha = math.clamp((positionX - track.AbsolutePosition.X) / width, 0, 1)
			return oreData.RefineRatio + alpha * (maxQuantity - oreData.RefineRatio)
		end

		local function stopDragging()
			dragging = false
			if moveConn then
				moveConn:Disconnect()
				moveConn = nil
			end
			if endConn then
				endConn:Disconnect()
				endConn = nil
			end
		end

		track.InputBegan:Connect(function(input)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end

			dragging = true
			applySmeltQuantity(quantityAt(input.Position.X))

			moveConn = UserInputService.InputChanged:Connect(function(moved)
				if not dragging then
					return
				end
				-- The tab can re-render underneath a live drag (an InventoryUpdate landing while
				-- the button is held), which destroys this track. Without this the handler would
				-- keep running against a destroyed instance whose AbsoluteSize is 0 for the rest
				-- of the session.
				if not track.Parent then
					stopDragging()
					return
				end
				if
					moved.UserInputType == Enum.UserInputType.MouseMovement
					or moved.UserInputType == Enum.UserInputType.Touch
				then
					applySmeltQuantity(quantityAt(moved.Position.X))
				end
			end)

			endConn = UserInputService.InputEnded:Connect(function(ended)
				if ended.UserInputType == input.UserInputType then
					stopDragging()
				end
			end)
		end)
	end

	Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Hud.FONT.Mono,
		Position = UDim2.new(0, Hud.SPACE.L, 0, trackY + 22),
		Size = UDim2.new(1, -Hud.SPACE.L * 2, 0, 16),
		Text = ("%d"):format(oreData.RefineRatio),
		TextColor3 = Hud.COLOR.Muted,
		TextSize = Hud.TEXTSIZE.Label,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = stage,
	})

	Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Hud.FONT.Mono,
		Position = UDim2.new(0, Hud.SPACE.L, 0, trackY + 22),
		Size = UDim2.new(1, -Hud.SPACE.L * 2, 0, 16),
		Text = maxQuantity > 0 and ("%d all"):format(maxQuantity) or "none",
		TextColor3 = Hud.COLOR.Muted,
		TextSize = Hud.TEXTSIZE.Label,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = stage,
	})

	if maxQuantity <= 0 then
		Hud.button({
			variant = "secondary",
			text = ("Need %d %s"):format(oreData.RefineRatio, oreDisplayName),
			position = UDim2.new(0, Hud.SPACE.L, 1, -56),
			size = UDim2.new(1, -Hud.SPACE.L * 2, 0, 44),
			parent = stage,
			onClick = function()
				Hud.showFailure("Not enough ore", ("A batch needs at least %d %s."):format(oreData.RefineRatio, oreDisplayName))
			end,
		})
		return
	end

	Hud.button({
		variant = "primary",
		text = "Start pour",
		dropShadow = true,
		position = UDim2.new(0, Hud.SPACE.L, 1, -56),
		size = UDim2.new(1, -Hud.SPACE.L * 2, 0, 44),
		parent = stage,
		onClick = function()
			local result = Remotes.StartSmelt:InvokeServer(oreKey, smeltQuantity)
			if not result.Success then
				Hud.showFailure("Smelt failed", result.Reason)
				return
			end
			-- Clear the client-only pending selection the instant the server takes over: from here
			-- Hud.profile.SmeltJob is truthy and the job state above wins every render.
			smeltSelectedOreKey = nil
			smeltQuantity = 0
			renderCraftList()
		end,
	})
end

-- Keeps the Decode countdown live while that tab is open — InventoryUpdate patches only arrive
-- when a job starts or finishes, not every second in between, so without this it would sit frozen
-- until the next patch happened to land.
--
-- SMELTING IS DELIBERATELY NOT IN HERE ANY MORE. Its dial now drives itself on Heartbeat (see the
-- ring in renderSmeltingTab), which is both smoother — os.time() has whole-second resolution, so a
-- once-a-second re-render can only step the arc, which is what it looked like — and far cheaper:
-- re-rendering the tab rebuilds the ring's 90 segment Frames every second and resets the sweep's
-- own timing anchor while it is at it. The start and finish transitions still arrive through
-- InventoryUpdate's renderCraftList above, which is what actually swaps the tab between states.
task.spawn(function()
	while true do
		task.wait(1)
		-- `not casePanel.isRevealing()` is belt-and-braces rather than strictly needed today (a reveal
		-- only runs once DecodeJob is already nil, so this condition is false anyway) — but a re-render
		-- mid-reel destroys and rebuilds the strip every second, and that is a bad enough failure to
		-- guard against explicitly rather than to leave resting on the ordering of two other fields.
		if craftFrame.Visible and currentTab == "Decode" and Hud.profile.DecodeJob
			and not casePanel.isRevealing() then
			renderCraftList()
		end
	end
end)

----------------------------------------------------------------------
-- Wave panel (bottom-center)
----------------------------------------------------------------------

local wavePanel = Hud.new("Frame", {
	Name = "WavePanel",
	BackgroundColor3 = Hud.COLOR.Panel,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -90),
	Size = UDim2.new(0, 360, 0, 118),
	Visible = false,
	Parent = Hud.screenGui,
}, { Hud.corner(8), Hud.stroke() })

local waveLabel = Hud.new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 8),
	Size = UDim2.new(1, -24, 0, 18),
	Font = Enum.Font.SourceSansBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 15,
	Text = "Wave —",
	Parent = wavePanel,
})

-- Each bar gets its own numeric readout above it — a thin color bar alone was too easy
-- to mistake for "nothing is happening" when it's actually just low-contrast.
local function makeBar(yOffset, fillColor, initialText)
	local caption = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, yOffset),
		Size = UDim2.new(1, -24, 0, 16),
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Hud.COLOR.Muted,
		TextSize = 13,
		Text = initialText,
		Parent = wavePanel,
	})
	local track = Hud.new("Frame", {
		BackgroundColor3 = Hud.COLOR.PanelLight,
		Position = UDim2.new(0, 12, 0, yOffset + 18),
		Size = UDim2.new(1, -24, 0, 12),
		Parent = wavePanel,
	}, { Hud.corner(4) })
	local fill = Hud.new("Frame", {
		BackgroundColor3 = fillColor,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = track,
	}, { Hud.corner(4) })
	return caption, fill
end

local wallCaption, wallFill = makeBar(30, Hud.COLOR.Good, "Wall: — / —")
local enemyCaption, enemyFill = makeBar(72, Hud.COLOR.Bad, "Enemies: —")

----------------------------------------------------------------------
-- Raid panel (bottom-right) — separate from the base-defense panel above since
-- you could, in principle, have just returned from one and be about to start the other.
----------------------------------------------------------------------

local raidPanel = Hud.new("Frame", {
	Name = "RaidPanel",
	BackgroundColor3 = Hud.COLOR.Panel,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.new(0, 300, 0, 130),
	Visible = false,
	Parent = Hud.screenGui,
}, { Hud.corner(8), Hud.stroke() })

local raidLabel = Hud.new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 8),
	Size = UDim2.new(1, -24, 0, 18),
	Font = Enum.Font.SourceSansBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 15,
	Text = "Outpost —",
	Parent = raidPanel,
})

local function makeRaidBar(yOffset, fillColor, initialText)
	local caption = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, yOffset),
		Size = UDim2.new(1, -24, 0, 16),
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Hud.COLOR.Muted,
		TextSize = 13,
		Text = initialText,
		Parent = raidPanel,
	})
	local track = Hud.new("Frame", {
		BackgroundColor3 = Hud.COLOR.PanelLight,
		Position = UDim2.new(0, 12, 0, yOffset + 18),
		Size = UDim2.new(1, -24, 0, 12),
		Parent = raidPanel,
	}, { Hud.corner(4) })
	local fill = Hud.new("Frame", {
		BackgroundColor3 = fillColor,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = track,
	}, { Hud.corner(4) })
	return caption, fill
end

local raidEnemyCaption, raidEnemyFill = makeRaidBar(30, Hud.COLOR.Bad, "Enemies: —")
local raidHealthCaption, raidHealthFill = makeRaidBar(72, Hud.COLOR.Good, "Your HP: —")

----------------------------------------------------------------------
-- Mine shaft depth panel (top-right) — only visible while MineShaftService's hazard loop reports
-- the player is actually standing above a live shaft block (see DepthUpdate below). Shows current
-- depth plus whichever hazard band applies there, colored red if the player's Suit doesn't cover
-- it yet (matching MineShaftService's own worst-band-only logic, computed here too so the HUD
-- doesn't have to wait on a server round trip beyond the DepthUpdate that already fired).
----------------------------------------------------------------------

local depthPanel = Hud.new("Frame", {
	Name = "DepthPanel",
	BackgroundColor3 = Hud.COLOR.Panel,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 16),
	Size = UDim2.new(0, 230, 0, 70), -- tall enough for Depth + 2 independent hazard lines (Heat, Toxic Air)
	Visible = false,
	Parent = Hud.screenGui,
}, { Hud.corner(8), Hud.stroke() })

local depthLabel = Hud.new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 6),
	Size = UDim2.new(1, -24, 0, 18),
	Font = Enum.Font.SourceSansBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 15,
	Text = "Depth —",
	Parent = depthPanel,
})

-- Heat and Toxic Air are now independent hazards that can both apply at once (see
-- MineShaftConfig.HazardTypes) rather than only the single "worst" one showing — so this panel
-- gets one line per hazard type instead of one combined line.
local hazardLabel = Hud.new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 27),
	Size = UDim2.new(1, -24, 0, 18),
	Font = Enum.Font.Code,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Hud.COLOR.Muted,
	TextSize = 13,
	Text = "",
	Parent = depthPanel,
})

local hazardLabel2 = Hud.new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 46),
	Size = UDim2.new(1, -24, 0, 18),
	Font = Enum.Font.Code,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Hud.COLOR.Muted,
	TextSize = 13,
	Text = "",
	Parent = depthPanel,
})

local function findHazardType(key: string)
	for _, hazardType in ipairs(MineShaftConfig.HazardTypes) do
		if hazardType.Key == key then
			return hazardType
		end
	end
	return nil
end

-- Which raw Tier (1-3) of `hazardType` applies at `depth`, or 0 if too shallow for even Tier 1 —
-- mirrors MineShaftService.rawHazardTier so the HUD can show this without a server round trip.
local function rawHazardTier(hazardType, depth: number): number
	local tier = 0
	for i, tierData in ipairs(hazardType.Tiers) do
		if depth >= tierData.MinDepth then
			tier = i
		end
	end
	return tier
end

-- Mirrors MineShaftService.resolveHazardDamage's Tier-reduction math (see MineShaftConfig
-- .SuitTiers' comment) purely for display — returns (text, color), or nil if this hazard doesn't
-- apply at the given depth at all.
local function hazardStatusLine(hazardType, depth: number, suitTier: number): (string?, Color3?)
	local tier = rawHazardTier(hazardType, depth)
	if tier == 0 then
		return nil
	end

	local suitData = MineShaftConfig.SuitTiers[suitTier]
	local protection = (suitData and suitData.Protection and suitData.Protection[hazardType.Key]) or 0
	local effectiveTier = tier - protection

	if effectiveTier <= 0 then
		return ("%s T%d — protected"):format(hazardType.Name, tier), Hud.COLOR.Good
	end

	local damage = hazardType.Tiers[effectiveTier].BaseDamage
	return ("%s T%d — %d dmg/tick"):format(hazardType.Name, tier, damage), Hud.COLOR.Bad
end

----------------------------------------------------------------------
-- Status panel (bottom-left) — the always-on readout of how the PLAYER is doing, as opposed to the
-- top-centre currency readout (what they own) and the wave panel (how the current fight is going).
--
-- Health lived only inside the raid panel before this, so outside a raid there was no HP readout at
-- all — despite mine hazards, lava and outpost fights all being able to kill you.
--
-- The Research row is a button: clicking it opens the requirements popup below. That is the answer
-- to "what do I need for the next tier" — the one number that gates base size, station tier, turret
-- slots and turret levels (see ResearchConfig.lua).
----------------------------------------------------------------------

-- Only the surface is bound (same reasoning as currencyFrame above) — nothing else needs the
-- shell, only to parent rows into the panel.
--
-- automaticSize = true restores AutomaticSize.Y here too (see currencyFrame's comment for why
-- plate's surface needs the opt-in rather than just setting AutomaticSize directly). Unlike
-- currencyList above, every row parented straight into statusPanel (Health/Stamina/the Research
-- button) already sizes itself with an offset-only Y — UDim2.new(1, 0, 0, 30) and friends — so
-- there's no second circularity to fix here; the UIListLayout/UIPadding below just work once the
-- surface itself can grow.
local statusPanel = Hud.plate({
	Name = "Status",
	Position = UDim2.new(0, 16, 1, -16),
	AnchorPoint = Vector2.new(0, 1),
	Size = UDim2.new(0, 240, 0, 0), -- Y is a placeholder; automaticSize below drives the real height
	automaticSize = true,
	Parent = Hud.screenGui,
})
Hud.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = statusPanel })
Hud.new("UIPadding", {
	PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
	Parent = statusPanel,
})

-- Small labelled bar, reused for Health and Stamina so the two stay visually identical.
-- Uppercased at the caller via :upper() rather than requiring every caller to remember to shout —
-- this is a section label, not dynamic content, so the display treatment (Hud.FONT.Display +
-- uppercase; TextLabel has no letter-spacing property, so that's the whole treatment) always
-- applies here.
local function makeStatusBar(order: number, label: string, fillColor: Color3, dimmed: boolean?)
	local holder = Hud.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 32), -- 30 -> 32 to fit the track's 12 -> 14 bump below
		LayoutOrder = order,
		Parent = statusPanel,
	})
	local caption = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 14),
		Font = Hud.FONT.Display,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = dimmed and Hud.COLOR.Muted or Hud.COLOR.Text,
		TextSize = Hud.TEXTSIZE.Label,
		Text = label:upper(),
		Parent = holder,
	})
	-- 12 -> 14: kept in step with the segmented Integrity bar's own bump below, so Stamina's
	-- placeholder slot doesn't look thinner/lower-effort than its neighbour once that one grows.
	local track = Hud.new("Frame", {
		BackgroundColor3 = Hud.COLOR.PanelLight,
		Position = UDim2.new(0, 0, 0, 16),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = holder,
	}, { Hud.corner(4) })
	local fill = Hud.new("Frame", {
		BackgroundColor3 = fillColor,
		Size = UDim2.new(dimmed and 0 or 1, 0, 1, 0),
		BorderSizePixel = 0,
		Parent = track,
	}, { Hud.corner(4) })
	return caption, fill
end

-- Health is the segmented bar from the design (10 cells) rather than a plain fill — built by hand
-- instead of through makeStatusBar (which stays plain-fill for Stamina below) since segmentBar's
-- shape (a list of cells to colour) doesn't fit makeStatusBar's (caption, fill) return signature.
-- Scoped in a do-block so `holder` doesn't cost a permanent top-level local in a file already near
-- Luau's 200-local ceiling — only the two things refreshHealthBar actually needs escape the block.
local statusHealthCaption, statusHealthCells
do
	local holder = Hud.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 36), -- grown from 32 to fit statusHealthTrack's height override
			-- below (20, up from segmentBar's own fixed 16) at the same 16px caption-to-bar offset
		LayoutOrder = 1,
		Parent = statusPanel,
	})
	statusHealthCaption = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 14),
		Font = Hud.FONT.Display,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Hud.COLOR.Text,
		TextSize = Hud.TEXTSIZE.Label,
		Text = "INTEGRITY", -- renamed from "Health" to match the design; overwritten with the live
			-- HP readout by refreshHealthBar below the instant a Humanoid binds
		Parent = holder,
	})
	statusHealthCells = Hud.segmentBar(holder, 10)
	-- segmentBar parents its track directly into `holder` at (0,0) — nudge it down to sit below the
	-- caption, matching makeStatusBar's original 16px offset.
	local statusHealthTrack = statusHealthCells[1].Parent.Parent
	statusHealthTrack.Position = UDim2.fromOffset(0, 16)
	-- HudKit.segmentBar's track height is a fixed internal constant (16px, sized before the
	-- Studio-screenshot text bump that prompted this pass) with no parameter to override it — and
	-- HudKit.lua is out of scope for this change, so it's grown here instead by reaching into the
	-- plain Frame instance segmentBar handed back. inner/cells below the track are Scale-sized
	-- relative to it (see segmentBar's own SEGMENT_INSET math), so bumping just the track's Size.Y
	-- grows the whole bar proportionately with no further changes needed.
	statusHealthTrack.Size = UDim2.new(1, 0, 0, 20)
end

-- Stamina is a PLACEHOLDER. There is no stamina or dash system in this codebase yet — no input
-- handling, no regen loop, no server validation — so this is a reserved, visibly-disabled slot
-- rather than a bar that lies about a stat nothing drives. Wire it up when dashing is built.
local _staminaCaption, _staminaFill = makeStatusBar(2, "Stamina — not built yet", Hud.COLOR.Muted, true)

-- Research button + requirements popup — extracted to ResearchPanel.lua. The button is a child
-- of statusPanel (built above), so the panel is constructed here rather than at require-time.
local researchPanel = ResearchPanel.new(statusPanel)
local renderResearchPanel = researchPanel.renderResearchPanel
local refreshResearchButton = researchPanel.refreshResearchButton

----------------------------------------------------------------------
-- Player HP tracking — driven locally by the Humanoid, not by remote payloads,
-- since Health already replicates on its own and this avoids a second source of truth.
----------------------------------------------------------------------

local playerMaxHealth = 100

local function refreshHealthBar()
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	playerMaxHealth = humanoid.MaxHealth
	local pct = math.clamp(humanoid.Health / playerMaxHealth, 0, 1)
	-- Two readouts, one source: the raid panel's bar (visible only mid-raid) and the always-on
	-- status panel's. Health replicates on its own, so both are driven straight off the Humanoid
	-- rather than from any remote payload.
	raidHealthFill.Size = UDim2.new(pct, 0, 1, 0)
	raidHealthCaption.Text = ("Your HP: %d / %d"):format(math.ceil(humanoid.Health), math.ceil(playerMaxHealth))
	-- Segmented instead of a plain fill: colour the first N of 10 cells solid, leave the rest at
	-- segmentBar's default COLOR.Line (empty). Same <=30% low-health color swap as before, just
	-- applied per-cell instead of to one fill Frame.
	local filledColor = (pct <= 0.3) and Hud.COLOR.Bad or Hud.COLOR.Good
	local filledCount = math.ceil(pct * #statusHealthCells)
	for i, cell in ipairs(statusHealthCells) do
		cell.BackgroundColor3 = (i <= filledCount) and filledColor or Hud.COLOR.Line
	end
	statusHealthCaption.Text = ("INTEGRITY  %d / %d"):format(math.ceil(humanoid.Health), math.ceil(playerMaxHealth))
end

local function bindHealth(character: Model)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.HealthChanged:Connect(refreshHealthBar)
	refreshHealthBar()
end

if LocalPlayer.Character then
	bindHealth(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(bindHealth)

----------------------------------------------------------------------
-- Shop panel (opened only by standing at a Shop node — see node setup below) — extracted to
-- ShopPanel.lua; ShopPanel.Open(node) does everything the click handler below needs.
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Bottom action buttons
----------------------------------------------------------------------

-- Assigns into the `local actionRow` forward-declared much further up — see that comment for why
-- it needs a name before it exists.
--
-- Icon-led layout: Inventory/Start Defense/Recall are now square icon buttons with a caption
-- underneath (see makeActionColumn below), so the row is taller than a single button row and grows
-- upward from a bottom anchor. AutomaticSize on both axes replaces the old fixed 550x44 — the row's
-- width also varies with which of Return to Base/Recall/Test Mode happen to be visible right now.
-- VerticalAlignment = Bottom keeps every column (and the plain text buttons that have no caption)
-- sitting on the same baseline instead of top-aligned, since Start Defense's column is taller than
-- its neighbours by design.
actionRow = Hud.new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.new(0, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.XY,
	Parent = Hud.screenGui,
}, { Hud.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 10),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
}) })

-- No standalone "Workbench" toggle button anymore — per-station gating (openStationMenu, near
-- the base-station setup further down) is the only way this menu opens now, so there's nothing
-- generic left to toggle from here. craftClose (forward-declared alongside craftFrame above, and
-- already wired into the panel's Hud.panelHeader close button there) is the only way to close it.
--
-- The station panels' header readouts need no hiding here: they are parented INSIDE the plate, so
-- they go with it.
craftClose = function()
	craftFrame.Visible = false
	ModPicker.closeModPicker() -- don't leave the mod picker orphaned open behind a closed Workbench
end

-- Builds one icon-button + caption column (button on top, small uppercase caption below, both
-- centred) and parents it into actionRow. Returns the button, the caption label, AND the column
-- itself — a caller that needs to hide the whole action (Recall, conditionally) has to toggle the
-- COLUMN, not just the button, or the caption would be left floating with no icon above it once the
-- button's Visible flips off.
--
-- UPPERCASE + Hud.FONT.Display is the whole display treatment for the caption: TextLabel has no
-- letter-spacing property, so this deliberately does NOT try to fake the reference mockup's wide
-- tracking by inserting spaces between the letters — that breaks text measurement, wrapping, and
-- AutomaticSize for anyone who touches this later.
local function makeActionColumn(buttonOpts, captionText: string, captionColor: Color3)
	local column = Hud.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, buttonOpts.size.X.Offset, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = actionRow,
	}, { Hud.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 4),
	}) })

	buttonOpts.parent = column
	local button = Hud.button(buttonOpts)

	local caption = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 14),
		Font = Hud.FONT.Display,
		TextColor3 = captionColor,
		TextSize = Hud.TEXTSIZE.Label,
		Text = captionText:upper(),
		Parent = column,
	})

	return button, caption, column
end

-- Grouped into one table rather than a local per button/caption — this file sits right at Luau's
-- 200-local ceiling for a function scope, and this row alone would otherwise cost six.
local mainActions = {}

-- Inventory, unlike the Workbench, isn't gated to a physical station — it's just a view onto
-- `Hud.profile` — so it gets a normal always-available button here instead.
mainActions.inventoryButton, mainActions.inventoryCaption = makeActionColumn({
	variant = "secondary",
	icon = "inventory",
	size = UDim2.new(0, 64, 0, 64), -- 56x56 -> 72x72 (Studio screenshot: everything read too small)
		-- -> 64x64: 72 overshot, per later feedback ("read a little too large now").
	onClick = openInventory,
}, "Inventory", Hud.COLOR.Muted)

-- The hero action: bigger than its neighbours (now 126x84 vs 64x64) and the only caption painted in
-- Accent rather than Muted, so it reads as the one loud thing on screen, per the approved design.
-- Doubles as the stop button rather than adding a second one — the action row is already tight
-- (and gets hidden wholesale while the Forge is open). Before StopWave existed this just no-op'd
-- while a run was active, so there was no way to end a run short of losing or resetting your
-- character; that's also what turned an unkillable enemy into an unrecoverable hang.
mainActions.defendButton, mainActions.defendCaption = makeActionColumn({
	variant = "primary",
	icon = "defense",
	size = UDim2.new(0, 126, 0, 84), -- 108x72 -> 144x96 (kept at the same 3:2 ratio so it's still
		-- unmistakably the largest, most hero-shaped thing in the row after the scale-up) -> 126x84:
		-- 144x96 overshot, per later feedback ("read a little too large now") — 3:2 preserved again.
}, "Start Defense", Hud.COLOR.Accent)
mainActions.defendButton.MouseButton1Click:Connect(function()
	if runActive then
		Remotes.StopWave:FireServer()
	else
		Remotes.StartWave:FireServer()
	end
end)

-- Recall and Return to Base share ONE column slot, on the right, mirroring Inventory's on the
-- left — they're both "get me out of here" actions and, per the precedence rule below, never
-- actually shown at the same time. Recall is built first because it's the one that OWNS the
-- column (via makeActionColumn); Return to Base is then parented straight into that same column
-- a few lines down instead of getting a slot of its own, so the row always has exactly three
-- top-level children — Inventory / Start Defense / this one — no matter which of the two exit
-- actions happens to be relevant right now.
--
-- ALWAYS visible: Recall means "bring me back to base", wherever the player is, not "climb out of
-- the mine". It is `secondary` rather than `danger` for the same reason — it is an ordinary
-- navigation action that follows the palette, not a destructive one.
--
-- Two server paths behind one button, because they are genuinely different operations:
--   * In the mine -> RecallFromMine (MineShaftService), which respawns via LoadCharacter and tears
--     down mine state. Left exactly as it is; its guard is deliberately tight.
--   * Anywhere else -> ReturnToBase (PlotService), which PivotTos the character and never touches
--     health. That distinction is a security boundary, not a style choice: LoadCharacter respawns
--     at FULL HEALTH, and a heal-on-demand that worked anywhere is precisely the exploit
--     RecallFromMine's guard exists to close. See that handler's comment.
-- The server re-checks either way — `inMineShaft` below is a client hint for choosing the path,
-- and a client hint is never a permission.
local inMineShaft = false
mainActions.recallButton, mainActions.recallCaption, mainActions.recallColumn = makeActionColumn({
	variant = "secondary",
	icon = "recall",
	size = UDim2.new(0, 64, 0, 64), -- 56x56 -> 72x72 -> 64x64, matching Inventory's sizing exactly
		-- at every step (see that column's own comment for the reason behind each change).
	onClick = function()
		if inMineShaft then
			Remotes.RecallFromMine:FireServer()
			return
		end
		local ok, result = pcall(function()
			return Remotes.ReturnToBase:InvokeServer()
		end)
		if not ok or not result or not result.Success then
			Hud.showFailure("Recall", (result and result.Reason) or "You can't do that right now.")
		end
	end,
}, "Recall", Hud.COLOR.Muted)

-- Recall's column is deliberately NEVER hidden — only its contents are (Recall's own button and
-- caption here, and Return to Base right below). actionRow's UIListLayout skips fully-invisible
-- children entirely when it lays out the row, so toggling recallColumn.Visible (the old behaviour)
-- removed its slot from the row the instant you surfaced, which re-centred everything and
-- knocked Start Defense off dead-centre. The column's own width is a fixed offset (see
-- makeActionColumn: Size.X is buttonOpts.size.X.Offset, never AutomaticSize), so leaving it
-- Visible = true always reserves exactly 64px in the row regardless of what's showing inside it —
-- Inventory and this column stay equal-width bookends and a centred layout keeps Start Defense
-- pinned to screen centre in every state. Hiding the buttons/captions inside it instead still
-- fully blocks input (an invisible TextButton doesn't receive clicks) and still hides them
-- visually, so nothing about the player-facing behaviour changes.


-- Ends the run for everyone on the shared queue, heals you to full, and keeps whatever you've
-- already looted (rewards are granted the instant each node resolves, not saved up for an
-- "end of run" payout, so there's nothing separate to preserve here). No icon in the set for this
-- action — stays a plain text button rather than inventing a mapping, per the icon design's own
-- rule that a wrong icon is worse than a text button. Parented into recallColumn (built just
-- above), NOT actionRow — that's the whole trick that makes it share Recall's reserved slot
-- instead of adding a fourth, variable-width item to the row. It's wider (130px) than the 64px
-- slot it's sharing, but that only makes it overflow the column's edges, symmetrically, since
-- recallColumn's own UIListLayout centers its children — the ROW's layout only ever measures the
-- column Frame's fixed Size, never what overflows out of its children, so Start Defense's
-- centring is unaffected either way.
local returnHomeButton = Hud.button({
	variant = "danger",
	text = "Return to Base",
	-- Height matches Recall's own button (72 -> 64, see that column's comment) so the two read as
	-- the same weight of control when swapped in the same slot; width (130) is untouched — it was
	-- always wider than the 72px/64px slot it overflows symmetrically out of (see the comment
	-- above), and the shrink doesn't change that relationship.
	size = UDim2.new(0, 130, 0, 44),
	-- OUT of the action row entirely. It used to share Recall's column because the two were
	-- effectively exclusive, but Recall is permanent now, so they would collide. It also is not a
	-- peer of the three main actions: it ENDS THE SHARED EXPEDITION for every player on the queue,
	-- which is situational and consequential, so it sits with the other situational controls in the
	-- top-right rather than competing with Start Defense for the eye.
	anchorPoint = Vector2.new(1, 0),
	position = UDim2.new(1, -16, 0, 144),
	parent = Hud.screenGui,
})
returnHomeButton.Visible = false
returnHomeButton.MouseButton1Click:Connect(function()
	Remotes.EndExpedition:FireServer()
end)

-- Recall and Return to Base CAN both be "relevant" at the same time. CurrentSlotId is a
-- server-wide flag — ExpeditionService's own header notes this drives ONE shared queue for the
-- whole server, not a per-player/party instance — while DepthUpdate is purely about where THIS
-- player is standing. So a player can be down in the mine shaft while somebody else is running
-- the expedition queue elsewhere in the base, making both true for them personally at once.
--
-- Recall wins when that happens: there's no climb-out mechanic (see above), so while you're
-- underground it is your ONLY way back, and hiding it in favour of Return to Base would strand
-- you. This never actually loses the Return to Base action, though — it ends the run for EVERY
-- player on the shared queue, so anyone not currently underground can still fire it, and this
-- player gets their own button back the instant they Recall out.
local expeditionActive = false
local function syncExitButtons()
	-- No longer suppressed by Recall. The two shared a slot while they were exclusive; Recall is
	-- permanent now and lives in the action row, while this sits top-right, so the only question left
	-- is whether an expedition is running at all.
	returnHomeButton.Visible = expeditionActive
end

-- ExpeditionService replicates "which row is frontmost" via CurrentSlotId on the Expedition
-- folder (-1 = no expedition active — see that file's comment). Reused here just to know whether
-- Return to Base is even a candidate to show — syncExitButtons above has the final say once
-- Recall's own state is factored in.
task.spawn(function()
	local expeditionFolder = Workspace:WaitForChild("Expedition", 10)
	if not expeditionFolder then
		return
	end

	local function syncVisibility()
		expeditionActive = (expeditionFolder:GetAttribute("CurrentSlotId") or -1) ~= -1
		syncExitButtons()
	end

	syncVisibility()
	expeditionFolder:GetAttributeChangedSignal("CurrentSlotId"):Connect(syncVisibility)
end)

----------------------------------------------------------------------
-- Player Test Mode — admin-only. Toggles a persisted flag that only takes effect on the NEXT
-- join (a fresh throwaway profile vs. the real one); the current session never changes. One
-- grouped table rather than a local per element, same reason as turretPanel above — this file
-- sits right at Luau's 200-local ceiling for a function scope.
--
-- Top-right, anchored directly to Hud.screenGui rather than living in actionRow: it's an admin
-- debug control, not a gameplay action, and it used to hang off the row as a fourth, variable-
-- width button — which is exactly what broke the row's centring in the first place (see actionRow's
-- own comments). RaidClient.client.lua's "Start Raid" button anchors to this same corner (its own
-- ScreenGui, AnchorPoint (1,0), Position (1,-16,0,16), 40px tall), so Y = 64 (16 + 40 + 8px gap)
-- sits just below it without needing to reach into that file/GUI to measure it exactly.
----------------------------------------------------------------------

-- Assigns into the `local testMode` forward-declared up in the Forge tab section — see that
-- comment for why this table needs a name before it technically exists yet, same pattern as
-- actionRow just above it there.
testMode = {}

-- Built (or not) once at startup from the server's honest answer, rather than assumed from
-- AdminConfig client-side (there isn't one) — a non-admin gets no button and no hint one exists,
-- same convention as the /admin chat commands.
task.spawn(function()
	local ok, result = pcall(function()
		return Remotes.GetTestMode:InvokeServer()
	end)
	if not ok or not result or not result.IsAdmin then
		return
	end

	testMode.on = result.On

	local function labelFor()
		local text = testMode.on and "TEST MODE: ON" or "TEST MODE: OFF"
		if result.InTestSession then
			-- A throwaway session must never be mistaken for the real save — Tier 1 and an empty
			-- inventory should read as "expected", not "did I just lose my progress".
			text ..= " (ACTIVE)"
		end
		return text
	end

	-- Secondary (a plain, muted fill) when OFF, danger only when ON, where the loudness is actually
	-- the point — an admin debug toggle should read as subordinate to the primary action beside it
	-- except in the one state (test data live) where standing out is the whole point of the color.
	-- Was previously a wide, always-red-or-bright slab (a manual BackgroundColor3 poke on every
	-- toggle, bypassing the variant's text/stroke) — routed through Hud.setButtonVariant below
	-- instead, same as the tab-switcher elsewhere in this file, which also fixes the old KNOWN QUIRK
	-- where hovering after a toggle could flash back to the button's ORIGINAL construction-time
	-- color: setButtonVariant rewrites the state the hover tween itself reads from, so there's
	-- nothing left to flash back to.
	-- Size/position only (reposition, not a redesign — see the section header comment above for
	-- where 64 comes from): no longer parented to actionRow, so its old "matches the icon buttons'
	-- height so the row bottom-aligns" reasoning no longer applies, but the size itself is untouched.
	testMode.button = Hud.button({
		variant = testMode.on and "danger" or "secondary",
		text = labelFor(),
		size = UDim2.new(0, 150, 0, 72),
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -16, 0, 64),
		parent = Hud.screenGui,
	})

	testMode.button.MouseButton1Click:Connect(function()
		local toggleResult = Remotes.ToggleTestMode:InvokeServer()
		if not toggleResult.Success then
			Hud.showFailure("Test Mode", toggleResult.Reason)
			return
		end

		testMode.on = toggleResult.On
		result.InTestSession = toggleResult.InTestSession
		Hud.setButtonVariant(testMode.button, testMode.on and "danger" or "secondary")
		testMode.button.Text = labelFor()

		-- The single thing most likely to confuse: the label already shows the NEW flag, but this
		-- session is still running on whatever profile it started with. Say so every time.
		if testMode.on then
			Hud.showToast("Test Mode ON — rejoin to load a fresh save.", 5)
		else
			Hud.showToast("Test Mode OFF — rejoin to return to your real save.", 5)
		end
	end)
end)

----------------------------------------------------------------------
-- Remote listeners
----------------------------------------------------------------------

Remotes.InventoryUpdate.OnClientEvent:Connect(function(patch)
	Hud.MergeProfile(patch)
	refreshCurrency()
	if craftFrame.Visible then
		renderCraftList()
	end
	if inventoryPanel.isVisible() then
		renderInvList()
		refreshInvDetailIfShowing()
	end
	-- Keeps an open turret slot panel current: upgrading a turret changes its level/stats, and the
	-- Cores spent change what the next upgrade costs. Place/Unplace close the panel themselves
	-- (the slot's contents moved), so this is really about Upgrade re-rendering in place.
	if TurretPanel.IsVisible() then
		TurretPanel.Render()
	end
	if ultPicker.frame.Visible then
		renderUltPickerList()
	end
	-- The Research claim depends on Scrap/ore/Cores/HighestWave, all of which arrive through this
	-- same patch — so the button's "UPGRADE READY" state and the open requirements popup both have
	-- to re-evaluate here rather than only when reopened.
	refreshResearchButton()
	if researchPanel.isVisible() then
		renderResearchPanel()
	end
end)

-- MineFailed is fired by BOTH MiningService (ore nodes) and MineShaftService (mine blocks), and is
-- already listened to by MiningController/MineShaftController — which only warn() to Output. A
-- RemoteEvent supports any number of client listeners, so this adds an on-screen toast without
-- either of those files needing to know the HUD exists.
--
-- This matters most for the mine shaft: blocks are click-based with no client-side pacing, so
-- server-side swing pacing rejecting a too-fast click would otherwise look like the block simply
-- ignoring you.
Remotes.MineFailed.OnClientEvent:Connect(function(reason: string)
	Hud.showToast(reason, 2.5) -- short: these fire often and shouldn't linger over the next swing
end)


-- Anything the drone wants to say — currently only the Scavenger Core's bonus haul. Its own remote
-- rather than a generic toast so the drone can stay chatty without anything else having to know it
-- exists.
Remotes.DroneEvent.OnClientEvent:Connect(function(message: string)
	Hud.showToast(message, 3)
end)

Remotes.ContrabandAwarded.OnClientEvent:Connect(function(amount: number, reason: string)
	Hud.showToast(("+%d Contraband%s"):format(amount, reason ~= "" and (" · " .. reason) or ""), 3)
end)

Remotes.EnergyDrinkFound.OnClientEvent:Connect(function()
	print(("[HUD] Found an Energy Drink! +%d Energy"):format(RaidEnergyConfig.EnergyDrinkBonus))
end)

-- Fires every MineShaftConfig.DepthReportIntervalSeconds from MineShaftService's fast depth-report
-- loop — nil means "not currently above a live shaft block" (surface, mid-fall, or standing on
-- the safety rail), which hides the panel entirely rather than showing a stale depth.
Remotes.DepthUpdate.OnClientEvent:Connect(function(depth: number?)
	if not depth then
		depthPanel.Visible = false
		-- Button/caption only, never the column — see the comment where recallColumn is built:
		-- hiding the column itself would drop its reserved 72px from actionRow's centred layout and
		-- knock Start Defense off-centre the moment you surface.
		inMineShaft = false
		-- Surfacing may hand the shared slot back to Return to Base, if the expedition queue is
		-- still active elsewhere — see syncExitButtons' precedence comment above.
		syncExitButtons()
		return
	end

	depthPanel.Visible = true
	-- Visible any time you're anywhere in the mine, including right at the Depth-0 surface floor
	-- — not just once you've actually descended. It's the one guaranteed way back to base, so it
	-- should be there the moment you're in the mine at all, not gated behind digging first.
	inMineShaft = true
	-- Recall now takes the shared slot away from Return to Base, if it happened to be showing —
	-- see syncExitButtons' precedence comment above for why Recall always wins.
	syncExitButtons()
	depthLabel.Text = ("Mine Shaft — Depth %d"):format(depth)

	local suitTier = Hud.profile.SuitTier or 1
	local heatText, heatColor = hazardStatusLine(findHazardType("Heat"), depth, suitTier)
	local toxicText, toxicColor = hazardStatusLine(findHazardType("ToxicAir"), depth, suitTier)

	if not heatText and not toxicText then
		hazardLabel.TextColor3 = Hud.COLOR.Muted
		hazardLabel.Text = "No hazards at this depth"
		hazardLabel2.Text = ""
	else
		hazardLabel.TextColor3 = heatColor or Hud.COLOR.Muted
		hazardLabel.Text = heatText or ""
		hazardLabel2.TextColor3 = toxicColor or Hud.COLOR.Muted
		hazardLabel2.Text = toxicText or ""
	end
end)

-- CombatEncounterService now owns the real numbers (real WallHP, real enemy counts) and reports
-- them on "Tick" roughly once a second. Base defense is about defending the BASE now, not the
-- player's own Humanoid — see CombatEncounterService.lua's header for the reasoning. WaveStart
-- fires BEFORE any enemy exists yet, so it can't hand us a max wall HP or enemy total — this just
-- resets the panel to a neutral "waiting for the first Tick" state and lets that Tick fill in real
-- numbers moments later.
local wallMaxHP = 150  -- guarded default so an early divide can't blow up; overwritten by Tick

Remotes.WaveUpdate.OnClientEvent:Connect(function(update)
	-- "Busy" = the player is already in a raid or an outpost fight, so a wave can't start (see
	-- PlayerActivityService). Grouped with the other pre-flight refusals: all three carry a
	-- Message and none of them should open the wave panel.
	if update.Status == "NoGear" or update.Status == "NotInBase" or update.Status == "Busy" then
		Hud.showFailure("Refused", update.Message)
		return
	end

	wavePanel.Visible = true

	if update.Status == "WaveStart" then
		runActive = true
		-- The button itself is icon-only now (see makeActionColumn) — the caption underneath is
		-- what has to say what CLICKING it does, not what's happening, same toggle-label contract
		-- as before. Uppercase to match the display treatment everywhere else in the row.
		mainActions.defendCaption.Text = "STOP DEFENSE"
		waveLabel.Text = ("Wave %d%s"):format(update.Wave, update.IsElite and "  (BOSS WAVE)" or "")
		wallCaption.Text = "Wall: — / —"
		enemyCaption.Text = "Enemies: —"
		wallFill.Size = UDim2.new(1, 0, 1, 0)
		enemyFill.Size = UDim2.new(1, 0, 1, 0)
	elseif update.Status == "Tick" then
		wallMaxHP = update.WallMaxHP or wallMaxHP
		local wallPct = math.clamp(update.WallHP / wallMaxHP, 0, 1)
		wallFill.Size = UDim2.new(wallPct, 0, 1, 0)
		if update.Shield and update.Shield > 0 then
			wallCaption.Text = ("Wall: %d / %d  (+%d Shield)"):format(update.WallHP, wallMaxHP, update.Shield)
		else
			wallCaption.Text = ("Wall: %d / %d"):format(update.WallHP, wallMaxHP)
		end

		local enemyPct = update.EnemiesTotal and update.EnemiesTotal > 0
			and math.clamp(update.EnemiesRemaining / update.EnemiesTotal, 0, 1)
			or 0
		enemyFill.Size = UDim2.new(enemyPct, 0, 1, 0)
		enemyCaption.Text = ("Enemies: %d / %d remaining"):format(update.EnemiesRemaining or 0, update.EnemiesTotal or 0)
	elseif update.Status == "WaveCleared" then
		-- No more Scrap/Cores from base defense — boss waves (update.CoreGrant) drop the real prize
		-- now, see WaveService.lua/RewardTables.lua.
		if update.CoreGrant then
			waveLabel.Text = ("Wave %d cleared! Boss down — +%d %s"):format(update.Wave, update.CoreGrant.Amount, update.CoreGrant.Key)
		else
			waveLabel.Text = ("Wave %d cleared!"):format(update.Wave)
		end
		enemyCaption.Text = "Enemies: 0 remaining"
		enemyFill.Size = UDim2.new(0, 0, 1, 0)
		if update.BonusLoot then
			waveLabel.Text = waveLabel.Text .. "  (+bonus item!)"
		end
	elseif update.Status == "Revived" then
		waveLabel.Text = "Revived — wall repaired"
		wallCaption.Text = ("Wall: %d / %d"):format(wallMaxHP, wallMaxHP)
		wallFill.Size = UDim2.new(1, 0, 1, 0)
	elseif update.Status == "Stopping" then
		-- StopWave clears the server's activeRuns flag, but the wave already in progress still has
		-- to resolve before the loop notices — so this is an acknowledgement, not the end. RunEnded
		-- follows and does the real reset.
		mainActions.defendCaption.Text = "STOPPING…"
		waveLabel.Text = "Stopping after this wave…"
	elseif update.Status == "RunEnded" then
		runActive = false
		mainActions.defendCaption.Text = "START DEFENSE"
		waveLabel.Text = ("Run ended — best wave %d"):format(update.HighestWave)
		task.delay(5, function()
			if not runActive then -- don't hide it if a new run started in the meantime
				wavePanel.Visible = false
			end
		end)
	end
end)

local raidEnemyHPPool = 1

local function lootSummary(loot)
	if #loot == 0 then
		return "nothing this time"
	end
	local parts = {}
	for _, entry in ipairs(loot) do
		local name = entry.Kind == "Ore" and OreConfig.Ores[entry.Key].DisplayName or entry.Key
		table.insert(parts, ("+%d %s"):format(entry.Amount, name))
	end
	return table.concat(parts, ", ")
end

local raidInProgress = false

local function hideRaidPanelSoon()
	task.delay(5, function()
		if not raidInProgress then -- don't hide it if a new raid started in the meantime
			raidPanel.Visible = false
		end
	end)
end

Remotes.OutpostUpdate.OnClientEvent:Connect(function(update)
	if update.Status == "NoGear" then
		Hud.showFailure("Refused", update.Message)
		return
	elseif update.Status == "OnCooldown" then
		Hud.showFailure("Outpost", "This outpost is still recovering — try again shortly.")
		return
	elseif update.Status == "Locked" then
		Hud.showFailure("Locked", "Clear the node in front of you before this one opens up.")
		return
	elseif update.Status == "NoEnergy" then
		Hud.showFailure("No Energy", "Not enough Energy to raid — wait for it to regen, or find an Energy Drink while mining.")
		return
	elseif update.Status == "Busy" then
		-- Already in a base-defense wave or an instanced raid — see PlayerActivityService.
		Hud.showFailure("Refused", update.Message)
		return
	elseif update.Status == "RaidCancelled" then
		-- The node this raid was fighting got wiped out from under it (e.g. Return to Base
		-- mid-fight) — close immediately rather than lingering like a normal cleared/failed raid.
		raidInProgress = false
		raidPanel.Visible = false
		return
	end

	raidPanel.Visible = true

	if update.Status == "RaidStart" then
		raidInProgress = true
		raidEnemyHPPool = update.EnemyHP
		raidLabel.Text = ("%s (Tier %d)"):format(update.NodeName, update.Tier)
		raidEnemyCaption.Text = ("Enemies: %d HP"):format(update.EnemyHP)
		raidEnemyFill.Size = UDim2.new(1, 0, 1, 0)
	elseif update.Status == "Tick" then
		local pct = math.clamp(update.RemainingEnemyHP / raidEnemyHPPool, 0, 1)
		raidEnemyFill.Size = UDim2.new(pct, 0, 1, 0)
		raidEnemyCaption.Text = ("Enemies: %d HP left"):format(math.floor(update.RemainingEnemyHP))
	elseif update.Status == "RaidCleared" then
		raidInProgress = false
		raidLabel.Text = "Raid cleared!"
		raidEnemyCaption.Text = "Looted: " .. lootSummary(update.Loot)
		hideRaidPanelSoon()
	elseif update.Status == "RaidFailed" then
		raidInProgress = false
		raidLabel.Text = "Raid failed — you went down"
		raidEnemyCaption.Text = "No loot this time. Heal up and try again."
		hideRaidPanelSoon()
	end
end)

----------------------------------------------------------------------
-- Expedition nodes — Heal Station, Shop, and Combat Outpost prompts.
-- Every node is tagged "Node" (CollectionService) with a child StringValue "NodeType"
-- ("Heal" / "Shop" / "Combat"); Combat nodes additionally need a NumberValue "Tier".
-- See the README for exact setup steps.
----------------------------------------------------------------------

local NODE_TAG = "Node"

-- Nodes are click-to-interact rather than hold-to-use: a ClickDetector handles both the range
-- check (MaxActivationDistance) and the click itself, and its MouseClick event fires on this
-- client without needing a separate prompt UI — which also sidesteps the old problem of two
-- fork options' prompts crowding each other when they sit close together. A Highlight toggles
-- on hover so it's still obvious a node is clickable.
local NODE_CLICK_DISTANCE = 50

-- ExpeditionService mirrors "which row is currently frontmost" onto an Attribute on the
-- Expedition folder (Attributes replicate to clients automatically, no remote needed). A node's
-- own SlotIndex attribute also replicates. Comparing the two locally means a node several slots
-- back in the queue — well within the 50-stud click range — can be recognized as locked and
-- rejected right here, instead of opening its UI and only finding out it's locked after a
-- server round trip.
local function isNodeCurrentlyAccessible(node: Instance): boolean
	local slotIndex = node:GetAttribute("SlotIndex")
	if slotIndex == nil then
		return true -- not an expedition node (e.g. a permanent hand-placed one) — never gated
	end
	local expeditionFolder = Workspace:FindFirstChild("Expedition")
	local currentSlotId = expeditionFolder and expeditionFolder:GetAttribute("CurrentSlotId")
	return currentSlotId == slotIndex
end

local function setupNode(node: Instance)
	if node:FindFirstChildOfClass("ClickDetector") then
		return
	end
	local nodeTypeValue = node:FindFirstChild("NodeType")
	local nodeType = nodeTypeValue and nodeTypeValue:IsA("StringValue") and nodeTypeValue.Value
	if not nodeType then
		return
	end

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = NODE_CLICK_DISTANCE
	clickDetector.CursorIcon = ""
	clickDetector.Parent = node

	local highlight = Hud.new("Highlight", {
		Enabled = false,
		FillTransparency = 1,
		OutlineColor = Hud.COLOR.Accent,
		OutlineTransparency = 0,
		Parent = node,
	})
	clickDetector.MouseHoverEnter:Connect(function(player)
		if player == LocalPlayer then
			highlight.Enabled = true
		end
	end)
	clickDetector.MouseHoverLeave:Connect(function(player)
		if player == LocalPlayer then
			highlight.Enabled = false
		end
	end)

	if nodeType == "Heal" then
		clickDetector.MouseClick:Connect(function(player)
			if player ~= LocalPlayer then return end
			if not isNodeCurrentlyAccessible(node) then
				Hud.showFailure("Locked", "That node is further down the queue — clear the one in front of you first.")
				return
			end
			local result = Remotes.InteractHeal:InvokeServer(node)
			if not result.Success then
				if result.Reason == "On cooldown" then
					Hud.showFailure("Cooldown", ("Heal Station recovering — %ds left."):format(result.SecondsLeft or 0))
				else
					Hud.showFailure("Heal failed", result.Reason)
				end
			end
		end)
	elseif nodeType == "Combat" then
		clickDetector.MouseClick:Connect(function(player)
			if player ~= LocalPlayer then return end
			if not isNodeCurrentlyAccessible(node) then
				Hud.showFailure("Locked", "That node is further down the queue — clear the one in front of you first.")
				return
			end
			Remotes.StartOutpostRaid:FireServer(node)
		end)
	elseif nodeType == "Shop" then
		clickDetector.MouseClick:Connect(function(player)
			if player ~= LocalPlayer then return end
			if not isNodeCurrentlyAccessible(node) then
				Hud.showFailure("Locked", "That node is further down the queue — clear the one in front of you first.")
				return
			end
			if raidInProgress then
				Hud.showFailure("Busy", "Finish your raid before visiting the shop.")
				return
			end
			ShopPanel.Open(node)
		end)
	end
end

----------------------------------------------------------------------
-- Expedition lever — regenerates the whole procedural node path on demand.
-- Tag a Part "ExpeditionLever" (separate from the "Node" tag; it's not a resource/utility
-- stop, it's a meta-control).
----------------------------------------------------------------------

local LEVER_TAG = "ExpeditionLever"

local function setupLever(lever: Instance)
	if lever:FindFirstChildOfClass("ProximityPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Regenerate"
	prompt.ObjectText = "Expedition Path"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.Parent = lever
	prompt.Triggered:Connect(function(player)
		if player ~= LocalPlayer then return end
		Remotes.RegenerateExpedition:FireServer(lever)
	end)
end

for _, lever in ipairs(CollectionService:GetTagged(LEVER_TAG)) do
	setupLever(lever)
end
CollectionService:GetInstanceAddedSignal(LEVER_TAG):Connect(setupLever)

for _, node in ipairs(CollectionService:GetTagged(NODE_TAG)) do
	setupNode(node)
end
CollectionService:GetInstanceAddedSignal(NODE_TAG):Connect(setupNode)

----------------------------------------------------------------------
-- Base stations — Workbench / Welding Station / Forge props inside a player's base. Tag a Part or
-- Model "Station" (StationConfig.Tag) with a child StringValue "StationType" matching a key in
-- StationConfig.Types. Clicking one is now the ONLY way to open the Workbench menu at all (the old
-- standalone toggle button is gone), and it opens scoped to just that station's own tabs
-- (StationConfig.Types[x].Tabs) — a Welding Station's menu physically cannot show you the Suit
-- tab, not just "doesn't default to it." This is more than convenience: the actual gate (must be
-- standing near the right station, not just anywhere in your plot) is still enforced independently
-- server-side by StationService.lua, but the client no longer even offers an action it knows will
-- be rejected. A station with no DefaultTab has no menu to open yet — clicking it just prints a
-- "not built yet" notice instead (every current station type has one now that the Forge is live).
----------------------------------------------------------------------

local STATION_TAG = StationConfig.Tag

-- Opens the Workbench menu scoped to exactly this station's role: rebuilds the tab row down to
-- stationData.Tabs, labels the header with stationData.DisplayName, and selects DefaultTab.
-- stationData is one of the literal tables in StationConfig.Types (identity, not a copy) — the
-- Forge-only pity bar / Luck Potion button use that identity to tell whether THIS station is
-- specifically the Forge, since StationConfig doesn't otherwise hand back a type key here.
local function openStationMenu(stationData)
	-- Resize BEFORE rebuilding the tabs and selecting one: selectTab renders that tab's contents,
	-- and several of them size themselves against the plate they're sitting in. Resizing afterwards
	-- would lay them out against the previous station's width and leave them stretched or clipped
	-- until the next re-render — the kind of thing that looks like a rendering bug rather than an
	-- ordering one. See StationConfig.DefaultPanelSize for why this is per station, not per tab.
	local panelSize = stationData.PanelSize or StationConfig.DefaultPanelSize
	craftFrame.Size = UDim2.fromOffset(panelSize.X, panelSize.Y)

	rebuildTabs(stationData.Tabs)
	craftTitleLabel.Text = stationData.DisplayName:upper() -- static chrome; see craftTitleLabel's own comment
	craftFrame.Visible = true
	selectTab(stationData.DefaultTab)
end

local function setupStation(station: Instance)
	if station:FindFirstChildOfClass("ClickDetector") then
		return
	end
	local marker = station:FindFirstChild("StationType")
	local stationType = marker and marker:IsA("StringValue") and marker.Value
	local stationData = stationType and StationConfig.Types[stationType]
	if not stationData then
		return
	end

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = StationConfig.InteractDistance
	clickDetector.CursorIcon = ""
	clickDetector.Parent = station

	local highlight = Hud.new("Highlight", {
		Enabled = false,
		FillTransparency = 1,
		OutlineColor = Hud.COLOR.Accent,
		OutlineTransparency = 0,
		Parent = station,
	})
	clickDetector.MouseHoverEnter:Connect(function(player)
		if player == LocalPlayer then
			highlight.Enabled = true
		end
	end)
	clickDetector.MouseHoverLeave:Connect(function(player)
		if player == LocalPlayer then
			highlight.Enabled = false
		end
	end)

	clickDetector.MouseClick:Connect(function(player)
		if player ~= LocalPlayer then return end
		if not stationData.DefaultTab then
			Hud.showFailure("Nothing here yet", ("%s doesn't do anything yet — check back later."):format(stationData.DisplayName))
			return
		end
		openStationMenu(stationData)
	end)
end

for _, station in ipairs(CollectionService:GetTagged(STATION_TAG)) do
	setupStation(station)
end
CollectionService:GetInstanceAddedSignal(STATION_TAG):Connect(setupStation)

----------------------------------------------------------------------
-- Turret slots — clicking one in the world opens the turret panel (see TurretPanel.Open). Tagged
-- and given a ClickDetector server-side by TurretService.makeSlotInteractive, so this only has to
-- add the hover highlight and the click handler, same as setupNode/setupStation above.
--
-- TurretService fully rebuilds a player's turret folder on every place/unplace/upgrade, so these
-- instances are destroyed and recreated constantly and the tag-added signal re-runs this each
-- time. Nothing here holds state across a rebuild, which is what makes that safe.
----------------------------------------------------------------------

local TURRET_SLOT_TAG = "TurretSlot"

local function setupTurretSlot(slot: Instance)
	-- Bounded WaitForChild, not FindFirstChildOfClass: the tag can reach the client a moment
	-- before the model's children finish replicating, and a plain Find would silently return nil
	-- and leave this slot permanently dead. The timeout (rather than an unbounded wait) means a
	-- genuinely malformed slot logs nothing worse than doing nothing.
	local clickDetector = slot:WaitForChild("SlotClick", 10)
	if not clickDetector then
		return
	end

	-- Checked AFTER the wait — everything else in this base's folder replicates alongside the
	-- ClickDetector, so by here the attribute is reliably present. Other players' bases carry
	-- tagged slots too (one shared Workspace), so scope to our own; same OwnerUserId check
	-- StationService already does server-side for stations.
	if slot:GetAttribute("OwnerUserId") ~= LocalPlayer.UserId then
		return
	end

	local highlight = Hud.new("Highlight", {
		Enabled = false,
		FillTransparency = 1,
		OutlineColor = Hud.COLOR.Accent,
		OutlineTransparency = 0,
		Parent = slot,
	})
	-- An EMPTY slot carries an invisible body-height ClickVolume above its pad (see
	-- TurretService.buildSlotMarker) so the thin ground plate is actually hittable. Highlight
	-- outlines every part of its adornee regardless of transparency, so left alone it would draw a
	-- floating box in mid-air on hover. Adorning the visible pad specifically keeps the hover
	-- looking like the pad lighting up. Placed turrets have no ClickVolume and stay whole-model.
	if slot:FindFirstChild("ClickVolume") and slot:IsA("Model") and slot.PrimaryPart then
		highlight.Adornee = slot.PrimaryPart
	end

	clickDetector.MouseHoverEnter:Connect(function(player)
		if player == LocalPlayer then
			highlight.Enabled = true
		end
	end)
	clickDetector.MouseHoverLeave:Connect(function(player)
		if player == LocalPlayer then
			highlight.Enabled = false
		end
	end)

	clickDetector.MouseClick:Connect(function(player)
		if player ~= LocalPlayer then return end
		local slotIndex = slot:GetAttribute("SlotIndex")
		if type(slotIndex) ~= "number" then
			return
		end
		TurretPanel.Open(slotIndex)
	end)
end

-- task.spawn'd because setupTurretSlot yields on WaitForChild: run inline, a slow-replicating
-- slot would block every slot behind it in this loop for up to its full timeout.
for _, slot in ipairs(CollectionService:GetTagged(TURRET_SLOT_TAG)) do
	task.spawn(setupTurretSlot, slot)
end
CollectionService:GetInstanceAddedSignal(TURRET_SLOT_TAG):Connect(function(slot)
	task.spawn(setupTurretSlot, slot)
end)

----------------------------------------------------------------------
-- Initial load
----------------------------------------------------------------------

task.spawn(function()
	local initial = Remotes.GetProfile:InvokeServer()
	if initial then
		Hud.MergeProfile(initial)
		refreshCurrency()
		refreshResearchButton()
	end
end)
