--[[
	InventoryPanel.lua
	The Inventory panel — a personal "what do I own, what's equipped, how much do I have" screen.
	Unlike the Workbench (which only opens from a physical station and is for crafting NEW
	things), this is viewable from anywhere — it's just a window onto data already sitting in
	`Hud.profile`. The Equip/Deploy/Undeploy buttons inside it call the same remotes as everywhere
	else (EquipWeapon, DeployRobot, UndeployRobot, EquipMod via the shared mod picker). Per direct
	player feedback, none of those four are plot/station gated anymore — changing your loadout
	works from anywhere in the world, not just standing at the right station. Only actually
	CRAFTING a new item (CraftItem, ForgeWeapon, and the Forge's other station actions) still
	requires being physically at the right prop — see ForgeService.lua/CraftingService.lua's own
	header comments. Also replaces the old cluttered top-left ore breakdown — see the Materials tab below
	and the trimmed-down currencyFrame near the top of MainHud.client.lua.

	Presentation: an icon grid (one square tile per owned item/material) instead of the Workbench's
	rows — clicking a tile opens a detail panel beside the Inventory showing a bigger image,
	description, stats, and (for Weapons/Robots) an Equip/Deploy button and mod slots. The
	Welding Station's own Robots tab is untouched and still uses the row layout (makeRobotRow) —
	crafting NEW items needs cost text that doesn't fit this tile format, so that stays row-based;
	only browsing OWNED items here got the icon-grid treatment. The Forge's Weapons tab has no row
	equivalent at all anymore — it's craft-only (see that section's own header comment); Weapons
	ownership/equipping lives here in the Inventory exclusively now.

	Icons: drop an ImageLabel, ImageButton, or Decal into ReplicatedStorage.ItemIcons (a plain
	Folder, see default.project.json), named EXACTLY like the item's key — a weaponKey/robotKey/
	modKey from CraftingRecipes.lua/ModConfig.lua, or an oreKey from OreConfig.lua (plus the literal
	names "Scrap"/"Cores" for the two currencies). Only its Image (or Texture, for a Decal) property
	is read — every other property on that instance is ignored, so it doesn't matter how it's
	sized/positioned; just get the image onto it via Studio's normal asset picker and name it right.
	No matching instance yet? The tile falls back to a plain colored square with the item's name in
	text — "functional before art," same as everywhere else in this project. No code changes needed
	either way; getItemIcon below just looks the key up fresh every time a tile is built.

	Descriptions live in code, next to each item's other data — CraftingRecipes.lua's
	Weapons/Robots entries and OreConfig.lua's Ores entries each got a `Description` field this
	session (ModConfig.lua's mods already had one). Scrap/Cores aren't real "ore" entries anywhere,
	so their descriptions are just inlined in showInvDetail below instead of a shared config.

	Extracted from MainHud.client.lua as part of breaking that file up — it had grown past Luau's
	200-locals-per-scope ceiling. Three things this module needs are NOT extracted alongside it and
	stay in MainHud instead, passed in through `context`:

	- `deployedCountForRobot` and `affixSummary` — small helpers also used by the Welding/Forge
	  station tabs (makeRobotRow, the Forge result readout), so they can't move here without those
	  tabs losing their only copy.
	- `openUltPicker` — the Ultimate-slot popup lives physically between the two halves of this
	  panel's original code (it shares the same "click a slot, pick from a list" shape as the mod
	  picker), but it's its own, separate popup, not part of the Inventory itself.

	Two things this module owns are, in turn, needed by code that stays behind in MainHud: the
	Smelting tab's ore-picker popup builds its tiles with the same `makeItemTile` this panel's tabs
	use, sized to the same `TILE_SIZE` — MainHud.client.lua's own comments had already documented
	that cross-dependency ("needs makeItemTile ... (Inventory panel helpers)") before this file
	existed. Both are exposed on the table `InventoryPanel.new` returns rather than duplicated.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)
local OreConfig = require(ReplicatedStorage.Shared.OreConfig)
local RefinedOreConfig = require(ReplicatedStorage.Shared.RefinedOreConfig)
local ModConfig = require(ReplicatedStorage.Shared.ModConfig)
local UltimateConfig = require(ReplicatedStorage.Shared.UltimateConfig)
-- Same asset HudKit.plate()/HudKit.button() 9-slice against — read directly (not through
-- Hud.getUiIcon) because makeItemTile also needs the exact SliceCenter geometry those two use,
-- and that Rect isn't exposed off HudKit itself (it's a local there). See makeItemTile below.
local UiIconConfig = require(ReplicatedStorage.Shared.UiIconConfig)

local Hud = require(script.Parent.HudKit)
local ModPicker = require(script.Parent.ModPicker)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local InventoryPanel = {}

-- Built once from MainHud.client.lua, after deployedCountForRobot/affixSummary/openUltPicker all
-- exist there. See this file's header for why those three stay put instead of moving in.
function InventoryPanel.new(context)
	local deployedCountForRobot = context.deployedCountForRobot
	local affixSummary = context.affixSummary
	local openUltPicker = context.openUltPicker
	local ORE_DISPLAY_ORDER = context.ORE_DISPLAY_ORDER

	-- FindFirstChild, NOT WaitForChild — this whole panel has to work with zero icons ever added (the
	-- "functional before art" default), and WaitForChild yields forever if ReplicatedStorage.ItemIcons
	-- never shows up at all (e.g. Studio hasn't been resynced since this folder was added to
	-- default.project.json yet), which was freezing the rest of this script past this point. Missing
	-- folder now behaves exactly like a missing icon inside it: getItemIcon just returns nil and every
	-- tile/detail panel falls back to its plain placeholder square, same as before.

	-- Bumped from 76 to 84 (a Studio screenshot showed the whole HUD reading too small) — items read
	-- more clearly at this size. NOTE: MainHud.client.lua's Smelting ore-picker popup also builds its
	-- grid with this exact constant (see this file's header comment on that cross-dependency), so that
	-- grid grows to match too — intended, not a side effect to "fix".
	local TILE_SIZE = 84

	-- One table instead of 15 separate top-level locals: Luau caps a function scope at 200
	-- locals and this file's main chunk hit that ceiling. Grouping UI element references costs
	-- nothing at runtime and buys back a register per element.
	local inv = {}

	-- closeInvDetail is defined further down (it needs inv.detailFrame/inv.detailState to exist
	-- first), but the main panel's header wants to call it as part of ITS close button — forward
	-- declare so the header's onClose closure can capture the upvalue now and see the real
	-- function by the time a player actually clicks it.
	local closeInvDetail

	-- inv.frame is the plate's SHELL (the outer, positioned frame) so every existing
	-- `inv.frame.Visible = ...` toggle keeps hiding/showing the whole panel; inv.surface is the
	-- inset content surface the header/tabs/grid all parent into.
	-- Docked to the right edge instead of floating center-screen — a 640x400 plate with one line
	-- of text in the middle of the viewport read as an empty black rectangle dominating the screen.
	-- Narrower (420, down from 640) and anchored/positioned flush against the right edge,
	-- vertically centered, so sparse content reads as a compact sidebar instead of barren.
	-- 488 tall (up from 480 — grown by exactly the 8px INV_TAB_HEIGHT gained, see that constant's
	-- comment for why the tab row needed to grow at all). No content below the tab row depends on
	-- this exact number: the list/empty-label both size themselves relative to INV_LIST_Y and the
	-- shell's own bottom edge, so this just controls how much visible list height the shell gives
	-- them — growing the shell by the same 8px the tabs took keeps that visible list height exactly
	-- where it was (366px, still a comfortable 4 full 84px rows + 6px spare) instead of quietly
	-- losing it to the taller tab row.
	inv.surface, inv.frame = Hud.plate({
		Name = "Inventory",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 420, 0, 488),
		Visible = false,
		Parent = Hud.screenGui,
	})

	-- Static chrome only (per this session's uppercase-Display treatment) — Hud.panelHeader already
	-- sets the title's Font to Hud.FONT.Display; the caller just needs to pass the text upper-cased,
	-- same as every other panel/tab-label change in this pass. Never do this to dynamic content
	-- (item/weapon/ore names) — those stay exactly as the server/config spells them.
	Hud.panelHeader(inv.surface, "INVENTORY", function()
		inv.frame.Visible = false
		closeInvDetail()
		ModPicker.closeModPicker() -- don't leave the mod picker orphaned open behind a closed Inventory
	end)

	-- REVERTED THIS PASS: tabs went icon-over-caption for one session, then back to plain text per the
	-- approved design reference (plain uppercase labels in pill buttons, no icons at all). Text-only
	-- tabs don't need the extra height that stacking an icon above a caption required.
	-- Position is unaffected by this (see the math below): it was never about the tab height, only
	-- about clearing the header.
	--
	-- Position 56: Hud.panelHeader is a fixed 48px (PANEL_HEADER_HEIGHT in HudKit.lua) tall, so this
	-- row sits 48 (header) + 8 (Hud.SPACE.S gap) below it — the same "8px gap below the thing above
	-- it" convention the listFrame below already uses. (A previous version of this row sat at Y=40,
	-- 8px INSIDE the header, and quietly drew over the header's own bottom edge — kept here as
	-- history since the same header-overlap mistake is easy to reintroduce if this ever moves again.)
	--
	-- HEIGHT IS 40, NOT A FREE CHOICE: HudKit.button() only cuts the angular 9-slice frame (the
	-- "solid square with a drop shadow" look these tabs are asking for) when BOTH dimensions are
	-- >= BUTTON_MIN_SLICE_SIZE (40, see HudKit.lua). dropShadow=true does NOT bypass that — it only
	-- swaps the gradient for a shadow on whichever background shape the size check already picked, so
	-- a tab under 40px tall renders as a ROUNDED pill with a shadow, not a square one. 40 is the
	-- minimum that clears the threshold; going lower silently regresses back to rounded corners with
	-- no error anywhere. See INV_LIST_Y just below for how the 8px grown height propagates.
	local INV_TAB_HEIGHT = 40
	local INV_TAB_ROW_Y = 56

	-- HorizontalAlignment = Center (not the UIListLayout default of Left): the four tab widths plus
	-- their gaps land 2px under this row's own usable width (see INV_TAB_WIDTH's arithmetic below),
	-- and Left alignment would dump that whole 2px slack on the right edge — Center splits it evenly
	-- instead, so the row reads as centred rather than "very slightly left-heavy."
	inv.tabRow = Hud.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, INV_TAB_ROW_Y),
		Size = UDim2.new(1, -24, 0, INV_TAB_HEIGHT),
		Parent = inv.surface,
	}, { Hud.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, Hud.SPACE.S),
	}) })

	-- Y = tab row's bottom (56 + 40 = 96) + the same 8px gap = 104.
	local INV_LIST_Y = INV_TAB_ROW_Y + INV_TAB_HEIGHT + Hud.SPACE.S

	inv.listFrame = Hud.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, INV_LIST_Y),
		-- Offset of -(INV_LIST_Y + 12): the trailing -12 is the same fixed bottom margin the original
		-- -92 (at Y=80) always encoded (80 + (surfaceHeight-92) = surfaceHeight-12) — preserved here
		-- so the list's bottom edge sits exactly where it always has, regardless of how the top moved.
		Size = UDim2.new(1, -24, 1, -(INV_LIST_Y + 12)),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = inv.surface,
	}, {
		-- Panel narrowed from 640 to 420 to dock against the right edge (see inv.frame below) — the
		-- old 6-column grid no longer fits. FillDirectionMaxCells pins the column count at 4
		-- explicitly rather than leaving it to whatever the width happens to divide into (which
		-- would silently drift back toward 5-6 if the panel's width ever changes again). Horizontal
		-- CellPadding recomputed for the TILE_SIZE bump (76 -> 84): 4 * 84 = 336 against the same
		-- ~390px-wide list frame (see INV_TAB_WIDTH's comment below for where 390 comes from) leaves
		-- 54px for 3 gaps = 18px each — an exact fit, not an estimate. Vertical padding is left at
		-- Hud.SPACE.S to keep row spacing exactly as it was.
		-- SYMMETRY CHECK: 4*84 + 3*18 = 390, exactly equal to this listFrame's own width (surface 414
		-- minus this frame's 12px-each-side inset = 390) — the grid fills its row with zero leftover
		-- pixels, so a full row is already centred with equal margins on both sides without needing a
		-- HorizontalAlignment override the way the shorter tab row above does. Only the last, partial
		-- row (whatever tab has a non-multiple-of-4 item count) sits left-aligned within that row —
		-- ordinary grid behaviour, not an asymmetry bug to chase.
		Hud.new("UIGridLayout", {
			CellSize = UDim2.new(0, TILE_SIZE, 0, TILE_SIZE),
			CellPadding = UDim2.new(0, 18, 0, Hud.SPACE.S),
			FillDirectionMaxCells = 4,
		}),
	})

	-- Overlays inv.listFrame's area with a plain message when the current tab has nothing to show —
	-- UIGridLayout forces every child to CellSize, so a full-width "nothing here" message can't be a
	-- grid child without looking cramped; this sits outside the grid instead and is only ever shown
	-- when the grid has zero tiles in it, so the two never actually overlap in practice.
	-- Centered both axes (was Left/Top, which read as hugging the top-left corner of a mostly-empty
	-- 390px-wide area) — an empty-state message reads as a deliberate placeholder when it sits in the
	-- middle of the space it's describing, not tucked into a corner of it.
	inv.emptyLabel = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, INV_LIST_Y),
		Size = UDim2.new(1, -24, 1, -(INV_LIST_Y + 12)),
		Font = Enum.Font.SourceSansItalic,
		TextColor3 = Hud.COLOR.Muted,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Visible = false,
		Text = "",
		Parent = inv.surface,
	})

	----------------------------------------------------------------------
	-- Detail panel — sits just left of the Inventory (see the docking comment just below), populated
	-- by clicking a tile. Shared by all four tabs; which parts are visible (mod slots, the action
	-- button) depends on the category.
	----------------------------------------------------------------------

	-- inv.detailFrame is the plate's SHELL (the outer, positioned frame) so every existing
	-- `inv.detailFrame.Visible = ...` toggle keeps working unchanged; inv.detailSurface is the
	-- inset content surface the header and every detail element parent into.
	-- The main panel now docks flush against the right screen edge (see inv.frame above) instead of
	-- floating center-screen, so "just right of it" would render off-screen entirely — this got
	-- flipped to sit just LEFT of it instead. Anchored the same way (right edge, vertical center) so
	-- it tracks the main panel's edge with one offset rather than duplicating its absolute position:
	-- the main panel's left edge sits at screen-right minus its own 420 width, and this frame's own
	-- right edge sits Hud.SPACE.M further left than that, i.e. at -(420 + Hud.SPACE.M) from the
	-- screen edge. Size (260x400) is unchanged, and sharing the same vertical anchor/position keeps
	-- it vertically centered on the same line as the main panel above.
	inv.detailSurface, inv.detailFrame = Hud.plate({
		Name = "InventoryDetail",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(420 + Hud.SPACE.M), 0.5, 0),
		Size = UDim2.new(0, 260, 0, 400),
		Visible = false,
		Parent = Hud.screenGui,
	})

	-- panelHeader owns the header Frame's construction, but showInvDetail() still needs to rewrite
	-- the title text per selected item — pull the TextLabel back out rather than hand-building a
	-- second one alongside it. onClose is closeInvDetail itself (forward-declared above), same as
	-- the original inv.detailCloseButton's connection.
	inv.detailHeader = Hud.panelHeader(inv.detailSurface, "", function()
		closeInvDetail()
	end)
	inv.detailTitle = inv.detailHeader:FindFirstChildOfClass("TextLabel")

	-- Position shifted +6 (42 -> 48) from where it originally sat: Hud.panelHeader is a fixed 48px
	-- tall, so 42 was 6px INSIDE it — the same class of header-overlap bug as inv.tabRow above, just
	-- with a smaller magnitude. Every element below is shifted the same +6 to preserve their existing
	-- gaps exactly (detailButton is unaffected — it's anchored to the panel's BOTTOM, not chained off
	-- these).
	inv.detailImage = Hud.new("ImageLabel", {
		BackgroundColor3 = Hud.COLOR.PanelLight,
		Position = UDim2.new(0, 10, 0, 48),
		Size = UDim2.new(1, -20, 0, 140),
		ScaleType = Enum.ScaleType.Fit,
		Image = "",
		Parent = inv.detailSurface,
	}, { Hud.corner(8) })

	inv.detailStats = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 196),
		Size = UDim2.new(1, -20, 0, 36),
		Font = Enum.Font.Code,
		TextColor3 = Hud.COLOR.Muted,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		Parent = inv.detailSurface,
	})

	inv.detailDescription = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 236),
		Size = UDim2.new(1, -20, 0, 70),
		Font = Enum.Font.SourceSans,
		TextColor3 = Hud.COLOR.Text,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		Parent = inv.detailSurface,
	})

	-- Weapons/Robots only — same slot-button idea as makeEquipmentRow's slotRow, just rebuilt for
	-- whichever item the detail panel currently shows instead of being baked into a row.
	--
	-- The slot buttons built inside (see rebuildInvDetailSlots below) go through Hud.button's `fill`
	-- option: their color is a per-render computed value (an equipped mod's AccentDark, an
	-- Ultimate's rarity tint) that maps to none of the three named variants, which `fill` exists
	-- specifically to cover — so these are among the most-clicked controls in the HUD and, until
	-- now, the only ones with no hover/press feedback at all.
	inv.detailSlotRow = Hud.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 312),
		Size = UDim2.new(1, -20, 0, 30),
		Visible = false,
		Parent = inv.detailSurface,
	}, { Hud.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })

	-- Weapons/Robots only — Equip, or Deploy/Undeploy. Hidden for Mods/Materials (nothing to toggle).
	-- Connected further down, once inv.detailState/deployedCountForRobot are in scope.
	--
	-- showInvDetail's Weapons branch still directly recolors this to AccentDark when the shown
	-- weapon is already equipped (see below) — that mutation is left intact per this migration's
	-- rules, even though a later hover-out will tween it back to primary's rest Accent shade; the
	-- color gets reasserted on the next render anyway (equip state changes always re-run
	-- showInvDetail via refreshInvDetailIfShowing).
	inv.detailButton = Hud.button({
		variant = "primary",
		size = UDim2.new(1, -20, 0, 32),
		position = UDim2.new(0, 10, 1, -42),
		parent = inv.detailSurface,
	})
	inv.detailButton.Visible = false

	inv.detailState = { category = nil :: string?, key = nil :: string? }

	inv.detailButton.MouseButton1Click:Connect(function()
		local category, key = inv.detailState.category, inv.detailState.key
		if not category or not key then
			return
		end
		if category == "Weapons" then
			-- key here is the Forged instance's Id (see showInvDetail's Weapons branch) — not a
			-- weaponKey — since equipping now targets one specific rolled instance.
			if Hud.profile.EquippedWeaponId == key then
				return
			end
			local result = Remotes.EquipWeapon:InvokeServer(key)
			if not result.Success then
				Hud.showFailure("Equip weapon failed", result.Reason)
			end
		elseif category == "Robots" then
			local owned = Hud.profile.CraftedRobots[key] or 0
			local deployed = deployedCountForRobot(key)
			if deployed < owned then
				local result = Remotes.DeployRobot:InvokeServer(key)
				if not result.Success then
					Hud.showFailure("Deploy failed", result.Reason)
				end
			else
				local result = Remotes.UndeployRobot:InvokeServer(key)
				if not result.Success then
					Hud.showFailure("Undeploy failed", result.Reason)
				end
			end
		end
	end)

	local function rebuildInvDetailSlots(tree: string, itemKey: string)
		for _, child in ipairs(inv.detailSlotRow:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		-- Weapons get a fourth ULTIMATE slot on the end; robots do not (Ultimates are weapon-only).
		-- Width is divided by the real button count so the row still fits either way.
		local showUltimate = (tree == "Weapons")
		local slotCount = ModConfig.SlotsPerItem + (showUltimate and 1 or 0)
		local slotWidth = math.floor((260 - 20 - 6 * (slotCount - 1)) / slotCount)
		for slotIndex = 1, ModConfig.SlotsPerItem do
			local equippedKey = ModPicker.equippedModKeyForSlot(itemKey, slotIndex)
			local mod = equippedKey and ModConfig.Mods[equippedKey]
			local slotButton = Hud.button({
				-- Computed per-render (an equipped mod's own AccentDark, or the empty-slot Panel
				-- shade) — `fill` is exactly the escape hatch for a color that isn't one of the
				-- three named variants; hover/press are still derived from it same as any variant.
				fill = mod and Hud.COLOR.AccentDark or Hud.COLOR.Panel,
				size = UDim2.new(0, slotWidth, 1, 0),
				text = mod and mod.DisplayName or ("Slot %d"):format(slotIndex),
				parent = inv.detailSlotRow,
				onClick = function()
					ModPicker.openModPicker(tree, itemKey, slotIndex)
				end,
			})
			-- Overridden after building, not exposed by HudButtonOptions: these cells are much
			-- narrower than a standard button, and Body-size unwrapped text would truncate a longer
			-- mod DisplayName instead of wrapping across the two lines the cell has room for.
			slotButton.Font = Enum.Font.Code
			slotButton.TextSize = 11
			slotButton.TextWrapped = true
		end

		if showUltimate then
			local equippedUltimate = (Hud.profile.EquippedUltimate or {})[itemKey]
			local data = equippedUltimate and UltimateConfig.Mods[equippedUltimate]
			local rarity = ModConfig.Rarities[UltimateConfig.Rarity] or {}
			local ultButton = Hud.button({
				-- Tinted with the Mythical colour whether filled or empty, so the slot reads as a
				-- different KIND of slot at a glance rather than a fourth ordinary one.
				fill = data and (rarity.Color or Hud.COLOR.AccentDark) or Hud.COLOR.Panel,
				text = data and data.DisplayName or UltimateConfig.SlotLabel,
				size = UDim2.new(0, slotWidth, 1, 0),
				parent = inv.detailSlotRow,
				onClick = function()
					openUltPicker(itemKey)
				end,
			})
			ultButton.Font = Enum.Font.Code
			ultButton.TextSize = 11
			ultButton.TextWrapped = true
			-- HudButtonOptions has no per-render text-color override (only the variant's fixed
			-- `text` shade) — reasserted here same as before conversion, since the empty/filled
			-- distinction needs white-on-fill vs. a rarity-tinted "empty slot" label, not either of
			-- HudKit.button()'s two fixed text colors.
			ultButton.TextColor3 = data and Color3.new(1, 1, 1) or (rarity.Color or Hud.COLOR.Muted)
		end

		inv.detailSlotRow.Visible = true
	end

	-- Assigns into the forward-declared upvalue (no `local`) — the main panel's header, and the
	-- detail panel's own header, both already captured `closeInvDetail` as a closure before this
	-- function existed.
	closeInvDetail = function()
		inv.detailFrame.Visible = false
		inv.detailState.category = nil
		inv.detailState.key = nil
	end

	local function showInvDetail(category: string, key: string)
		inv.detailState.category = category
		inv.detailState.key = key

		-- Icon lookup key differs from the selection key for Weapons only: `key` there is the Forged
		-- instance's unique Id (see renderInvWeapons below), but icons are per weapon TYPE (see this
		-- section's header comment on the ItemIcons convention) — so iconKey gets overridden to
		-- instance.WeaponKey inside that branch below, before it's actually used.
		local iconKey = key

		if category == "Weapons" then
			local instance
			for _, w in ipairs(Hud.profile.Weapons or {}) do
				if w.Id == key then
					instance = w
					break
				end
			end
			if not instance then
				-- Stale selection (e.g. this exact instance can't happen today — weapons are never
				-- destroyed — but guard anyway rather than indexing into a nil recipe below).
				closeInvDetail()
				return
			end
			iconKey = instance.WeaponKey
			local recipe = CraftingRecipes.Weapons[instance.WeaponKey]
			local rarityData = ModConfig.Rarities[instance.Rarity]
			local rarityName = rarityData and rarityData.DisplayName or instance.Rarity
			local equipped = Hud.profile.EquippedWeaponId == instance.Id
			inv.detailTitle.Text = ("[%s] T%d  %s"):format(rarityName, recipe.Tier, recipe.DisplayName)
			inv.detailStats.Text = ("Base: %.1f dmg x %.1f/s"):format(recipe.BaseDamage, recipe.FireRate)
			inv.detailDescription.Text = ("%s\n\n%s"):format(recipe.Description or "", affixSummary(instance.Affixes))
			rebuildInvDetailSlots("Weapons", instance.WeaponKey)
			inv.detailButton.Visible = true
			inv.detailButton.Text = equipped and "Equipped" or "Equip"
			inv.detailButton.BackgroundColor3 = equipped and Hud.COLOR.AccentDark or Hud.COLOR.Accent
		elseif category == "Robots" then
			local recipe = CraftingRecipes.Robots[key]
			local owned = Hud.profile.CraftedRobots[key] or 0
			local deployed = deployedCountForRobot(key)
			inv.detailTitle.Text = ("T%d  %s"):format(recipe.Tier, recipe.DisplayName)
			inv.detailStats.Text = ("Base: %.1f dmg x %.1f/s · %d HP · owned %d, deployed %d"):format(
				recipe.BaseDamage, recipe.FireRate, recipe.HP, owned, deployed)
			inv.detailDescription.Text = recipe.Description or ""
			rebuildInvDetailSlots("Robots", key)
			inv.detailButton.Visible = true
			inv.detailButton.Text = (deployed < owned) and "Deploy" or "Undeploy"
			inv.detailButton.BackgroundColor3 = Hud.COLOR.Accent
		elseif category == "Mods" then
			local mod = ModConfig.Mods[key]
			local rarityData = ModConfig.Rarities[mod.Rarity]
			local rarityName = rarityData and rarityData.DisplayName or mod.Rarity
			inv.detailTitle.Text = ("[%s] %s"):format(rarityName, mod.DisplayName)
			inv.detailStats.Text = "Equip from a Weapon/Robot's own mod slots"
			inv.detailDescription.Text = mod.Description or ""
			inv.detailSlotRow.Visible = false
			inv.detailButton.Visible = false
		elseif category == "Materials" then
			local displayName, description, count
			if key == "Scrap" then
				displayName = "Scrap"
				description = "General scavenged currency — spent on higher-tier gear and materials."
				count = Hud.profile.Scrap or 0
			elseif key == "Cores" then
				displayName = "Cores"
				description = "Rare salvaged currency — spent on premium purchases."
				count = Hud.profile.Cores or 0
			elseif OreConfig.Ores[key] then
				local oreData = OreConfig.Ores[key]
				displayName = oreData.DisplayName
				description = oreData.Description or ""
				count = (Hud.profile.OreCounts or {})[key] or 0
			else
				-- Not a raw ore key — must be a refined material's RefinedKey (see
				-- RefinedOreConfig.ByRefinedKey, the reverse lookup built for exactly this).
				local refinedInfo = RefinedOreConfig.ByRefinedKey[key]
				displayName = refinedInfo and refinedInfo.DisplayName or key
				description = refinedInfo and refinedInfo.Description or ""
				count = (Hud.profile.RefinedOreCounts or {})[key] or 0
			end
			inv.detailTitle.Text = displayName
			inv.detailStats.Text = ("You have: %d"):format(count)
			inv.detailDescription.Text = description
			inv.detailSlotRow.Visible = false
			inv.detailButton.Visible = false
		end

		inv.detailImage.Image = Hud.getItemIcon(iconKey) or ""
		inv.detailFrame.Visible = true
	end

	-- Called whenever InventoryUpdate patches Hud.profile — keeps the detail panel's Equip/Deploy button
	-- and stats in sync with a change made from anywhere (including the Workbench's own tabs) without
	-- needing the player to re-click the tile.
	local function refreshInvDetailIfShowing()
		if inv.detailFrame.Visible and inv.detailState.category and inv.detailState.key then
			showInvDetail(inv.detailState.category, inv.detailState.key)
		end
	end

	-- Is this tile the one currently open in the detail panel? Compared against inv.detailState
	-- (the same category/key pair showInvDetail stamps on selection) rather than duplicating that
	-- bookkeeping — every renderInv* function below ORs this into whatever `highlighted` already
	-- meant for that tab (equipped/deployed/owned), so clicking a tile still shows an accent OUTLINE
	-- (see makeItemTile's isSliceable branch) even when nothing about equip/deploy status changed.
	-- Previously nothing fed a "this is the open one" signal into makeItemTile at all — Materials/Mods
	-- always passed a hardcoded `false`, and Weapons/Robots passed equip/deploy status instead, so no
	-- tile ever visibly reflected "you clicked this one," which is exactly what was reported missing.
	local function isInvSelected(category: string, key: string): boolean
		return inv.detailState.category == category and inv.detailState.key == key
	end

	----------------------------------------------------------------------
	-- Grid tiles — one per tab, built fresh every render
	----------------------------------------------------------------------

	-- Same 9-slice cut-steel frame as HudKit.plate()/HudKit.button() (see PANEL_FRAME_SLICE_CENTER's
	-- header comment in HudKit.lua for the asset geometry) — tiles used to be plain rounded rects,
	-- which read flat and generic next to every other angular panel in this HUD. Read fresh per tile,
	-- same as `icon` right below it: this section's header already documents "look the key up fresh
	-- every time a tile is built" for icons, and the panelframe asset should honor a Studio change
	-- the same way rather than being cached once at panel-construction time.
	--
	-- The outer ImageButton no longer carries the item icon as its own .Image — with a frame behind
	-- it, the icon has to be a separate child layered on top (ZIndex 1) instead of replacing the
	-- frame (ZIndex 0). This is the one structural change here; everything else is the same
	-- click-handling ImageButton it always was.
	--
	-- `highlighted` is whatever the caller wants this ONE accent cue to mean — every renderInv*
	-- function below ORs its own status flag (equipped/deployed) together with "is this the tile
	-- currently open in the detail panel" (isInvSelected) rather than adding a second visual for the
	-- latter, so a tile can't end up needing two different accent treatments at once.
	local function makeItemTile(key: string, displayName: string, badgeText: string?, highlighted: boolean, onSelect)
		local icon = Hud.getItemIcon(key)
		local panelFrameImage = UiIconConfig.Get("panelframe")
		local isSliceable = panelFrameImage ~= nil

		local tile = Hud.new("ImageButton", {
			-- Only visible on the fallback (non-sliceable) path below — the sliceable path hides this
			-- via BackgroundTransparency and paints the fill on the frame ImageLabel's ImageColor3
			-- instead, same split HudKit.button() uses for its own sliced/fallback background.
			BackgroundColor3 = highlighted and Hud.COLOR.AccentDark or Hud.COLOR.PanelLight,
			BackgroundTransparency = if isSliceable then 1 else 0,
			AutoButtonColor = false,
			Image = "",
			Size = UDim2.new(0, TILE_SIZE, 0, TILE_SIZE),
		}, if isSliceable then {} else { Hud.corner(8), Hud.stroke() })
		-- No UICorner/stroke on the sliceable path: the shape and outline both come from the image's
		-- own cut corners and baked edge, same reasoning as HudKit.plate()'s shell/surface branch.

		if isSliceable then
			-- The selected tile is OUTLINED in accent, not filled — the reference shows the selected
			-- slot as an accent-tinted frame around an otherwise normal dark interior, not a solid
			-- accent block. Retinting this one ImageLabel (frame tint doubles as the fill, since the
			-- slice image covers the whole tile) is the smallest change that gets there, rather than
			-- adding a second filled layer underneath just for the unselected case.
			Hud.new("ImageLabel", {
				BackgroundTransparency = 1,
				Image = panelFrameImage,
				ImageColor3 = highlighted and Hud.COLOR.Accent or Hud.COLOR.PanelLight,
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = Rect.new(20, 20, 44, 44),
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 0,
				Parent = tile,
			})
		end

		if icon then
			-- Inset 6px each side so the icon sits inside the frame's cut corners instead of
			-- overdrawing them — TILE_SIZE (84) clears the frame's own ~20px corner regions
			-- comfortably either way, this is purely so the icon doesn't visually collide with the
			-- frame's edge.
			Hud.new("ImageLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.new(1, -12, 1, -12),
				Image = icon,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 1,
				Parent = tile,
			})
		else
			Hud.new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 3, 0, 3),
				Size = UDim2.new(1, -6, 1, -6),
				Font = Enum.Font.SourceSansBold,
				TextColor3 = Hud.COLOR.Muted,
				TextSize = 12,
				TextWrapped = true,
				Text = displayName,
				ZIndex = 1,
				Parent = tile,
			})
		end

		if badgeText then
			Hud.new("TextLabel", {
				BackgroundColor3 = Hud.COLOR.Panel,
				Position = UDim2.new(1, -24, 1, -18),
				Size = UDim2.new(0, 22, 0, 16),
				Font = Enum.Font.Code,
				TextColor3 = Hud.COLOR.Text,
				TextSize = 11,
				Text = badgeText,
				ZIndex = 2,
				Parent = tile,
			}, { Hud.corner(4) })
		end

		tile.MouseButton1Click:Connect(onSelect)
		return tile
	end

	local currentInvTab = "Weapons"

	-- Forward-declared, same reasoning as closeInvDetail above: renderInvWeapons/Robots/Mods/
	-- Materials below all need to call this from their tiles' onSelect closures (to redraw the grid
	-- with the new selection outline immediately on click), but the real definition needs those
	-- render*Function names to already exist first. Without this forward declaration, those closures
	-- would close over a nonexistent local and silently resolve to a nil global at call time instead
	-- — no compile error, just "nothing happens" the first time a tile is clicked.
	local renderInvList

	local function renderInvWeapons()
		local instances = Hud.profile.Weapons or {}
		if #instances == 0 then
			inv.emptyLabel.Text = "No weapons owned yet — Forge one at your Forge station."
			inv.emptyLabel.Visible = true
			return
		end
		-- Copy before sorting — Hud.profile.Weapons is the live table, don't mutate its order.
		local sorted = {}
		for _, instance in ipairs(instances) do
			table.insert(sorted, instance)
		end
		table.sort(sorted, function(a, b)
			local tierA, tierB = CraftingRecipes.Weapons[a.WeaponKey].Tier, CraftingRecipes.Weapons[b.WeaponKey].Tier
			if tierA ~= tierB then
				return tierA < tierB
			end
			return a.Id < b.Id
		end)
		for _, instance in ipairs(sorted) do
			local recipe = CraftingRecipes.Weapons[instance.WeaponKey]
			local rarityData = ModConfig.Rarities[instance.Rarity]
			local equipped = Hud.profile.EquippedWeaponId == instance.Id
			-- ORed with isInvSelected, not replaced by it: equipped keeps its own accent cue, and
			-- clicking a non-equipped weapon still gets the selection outline on top of that.
			local highlighted = equipped or isInvSelected("Weapons", instance.Id)
			-- Icon lookup key is instance.WeaponKey (the TYPE, icons aren't per-roll), but selecting
			-- the tile opens the detail panel on this specific instance.Id.
			makeItemTile(instance.WeaponKey, recipe.DisplayName, rarityData and rarityData.Badge or "?", highlighted, function()
				showInvDetail("Weapons", instance.Id)
				-- Re-render so this tile's outline appears (and any previously-selected tile's
				-- disappears) right away — nothing else re-renders the grid on a plain click, only on
				-- the next InventoryUpdate patch, which may be a while for a weapon nobody re-equips.
				renderInvList()
			end).Parent = inv.listFrame
		end
	end

	local function renderInvRobots()
		local keys = {}
		for key, count in pairs(Hud.profile.CraftedRobots) do
			if count and count > 0 then
				table.insert(keys, key)
			end
		end
		if #keys == 0 then
			inv.emptyLabel.Text = "No robots owned yet — craft one at your Welding Station."
			inv.emptyLabel.Visible = true
			return
		end
		table.sort(keys, function(a, b)
			return CraftingRecipes.Robots[a].Tier < CraftingRecipes.Robots[b].Tier
		end)
		for _, key in ipairs(keys) do
			local recipe = CraftingRecipes.Robots[key]
			local deployed = deployedCountForRobot(key)
			local highlighted = (deployed > 0) or isInvSelected("Robots", key)
			makeItemTile(key, recipe.DisplayName, ("x%d"):format(Hud.profile.CraftedRobots[key]), highlighted, function()
				showInvDetail("Robots", key)
				renderInvList() -- see the matching comment in renderInvWeapons above
			end).Parent = inv.listFrame
		end
	end

	local function renderInvMods()
		local keys = ModPicker.ownedModKeysSorted()
		if #keys == 0 then
			inv.emptyLabel.Text = "No mods owned yet — craft one at your Welding Station."
			inv.emptyLabel.Visible = true
			return
		end
		for _, key in ipairs(keys) do
			local mod = ModConfig.Mods[key]
			makeItemTile(key, mod.DisplayName, nil, isInvSelected("Mods", key), function()
				showInvDetail("Mods", key)
				renderInvList() -- see the matching comment in renderInvWeapons above
			end).Parent = inv.listFrame
		end
	end

	-- Everything the old top-left readout used to show, in one filterable place, plus refined
	-- materials from the Forge's Smelting mechanic (see RefinedOreConfig.lua) tacked on at the end —
	-- exactly the "just need adding to this list, no new tab required" this function's comment always
	-- anticipated. Never shows the empty state — Scrap/Cores/every raw ore always gets a tile even at
	-- 0; refined materials only show once you've actually smelted at least one (there'd otherwise be
	-- 5 more permanently-zero tiles here before the player has ever touched the Forge's second tab).
	local function renderInvMaterials()
		makeItemTile("Scrap", "Scrap", nil, isInvSelected("Materials", "Scrap"), function()
			showInvDetail("Materials", "Scrap")
			renderInvList() -- see the matching comment in renderInvWeapons above
		end).Parent = inv.listFrame
		makeItemTile("Cores", "Cores", nil, isInvSelected("Materials", "Cores"), function()
			showInvDetail("Materials", "Cores")
			renderInvList()
		end).Parent = inv.listFrame
		for _, oreKey in ipairs(ORE_DISPLAY_ORDER) do
			local displayName = OreConfig.Ores[oreKey].DisplayName
			makeItemTile(oreKey, displayName, nil, isInvSelected("Materials", oreKey), function()
				showInvDetail("Materials", oreKey)
				renderInvList()
			end).Parent = inv.listFrame
		end
		for _, refineData in pairs(RefinedOreConfig.Ores) do
			local owned = (Hud.profile.RefinedOreCounts or {})[refineData.RefinedKey] or 0
			if owned > 0 then
				makeItemTile(refineData.RefinedKey, refineData.DisplayName, ("x%d"):format(owned), isInvSelected("Materials", refineData.RefinedKey), function()
					showInvDetail("Materials", refineData.RefinedKey)
					renderInvList()
				end).Parent = inv.listFrame
			end
		end
	end

	-- Assigns into the forward-declared upvalue above (no `local`) — same convention as
	-- closeInvDetail's assignment further up.
	renderInvList = function()
		for _, child in ipairs(inv.listFrame:GetChildren()) do
			if child:IsA("ImageButton") then
				child:Destroy()
			end
		end
		inv.emptyLabel.Visible = false

		if currentInvTab == "Weapons" then
			renderInvWeapons()
		elseif currentInvTab == "Robots" then
			renderInvRobots()
		elseif currentInvTab == "Mods" then
			renderInvMods()
		elseif currentInvTab == "Materials" then
			renderInvMaterials()
		end
	end

	-- Fixed left-to-right order the tab row builds in, once, below.
	local INV_TAB_NAMES = { "Weapons", "Robots", "Mods", "Materials" }

	-- BUG FIX (historical): the panel was re-docked from 640px wide to 420px (see inv.frame above)
	-- but this row kept the old 140px-per-button sizing, so the four buttons (560px) plus their 3 gaps
	-- (Hud.SPACE.S = 8 each, 24px) totalled 584px against a row that is actually only 390px wide —
	-- pushing the fourth tab, Materials, off the edge of the panel entirely. A player literally could
	-- not reach their ore. The width math below still targets that same 390px figure.
	--
	-- The 390px figure is not eyeballed: inv.surface is the plate's inset content surface, 6px
	-- narrower than the 420px shell (see Hud.plate's PLATE_SURFACE_INSET, 3px each side) = 414px, and
	-- inv.tabRow itself sits inset 12px each side of THAT (`Position/Size` just above) = 414 - 24 =
	-- 390px of actual usable width. (The listFrame's own UIGridLayout comment above already assumes
	-- this same 390px figure for the grid beneath it — this is the same row, so it has to agree.)
	--
	-- REVERTED THIS PASS: a brief icon-over-caption detour (each tab a stacked icon + label, needing
	-- the taller 56px row) is gone per the approved design reference — plain uppercase text in a pill
	-- button, no icons at all. That removed the icon-caption reason INV_TAB_HEIGHT was ever grown,
	-- and with it the whole hand-built icon+caption content frame this section used to describe —
	-- but INV_TAB_HEIGHT is grown again as of this pass, for an unrelated reason (clearing
	-- BUTTON_MIN_SLICE_SIZE for the squared drop-shadow look; see that constant's own comment). None
	-- of this section's width math (390px, INV_TAB_WIDTH) is affected either time — both height
	-- changes are vertical-only.
	local INV_TAB_GAP = Hud.SPACE.S -- unchanged from the row's existing UIListLayout Padding, below
	local INV_TAB_WIDTH = math.floor((390 - INV_TAB_GAP * (#INV_TAB_NAMES - 1)) / #INV_TAB_NAMES)
	-- INV_TAB_WIDTH = 91: 4 * 91 + 3 * 8 = 388px against 390px available — fits, 2px to spare. That
	-- 2px is what inv.tabRow's UIListLayout HorizontalAlignment = Center (set above) splits evenly
	-- across both edges instead of leaving it all on the right.

	local selectInvTab

	-- Built ONCE, then recolored in place via HudKit.setButtonVariant on every tab switch.
	-- HudKit.setButtonVariant already flips both the fill AND the button's own Text color to match
	-- the variant (see BUTTON_VARIANTS in HudKit.lua) — now that the caption IS the button's Text
	-- (not a hand-built child label, like the icon-over-caption version needed), there's no second
	-- color to keep in sync by hand, and no `inv.tabCaptions` table to maintain either. Keyed by name
	-- (not by loop index) so `selectInvTab` never has to reason about which slot in a list is
	-- "currently active" — just look up by name.
	inv.tabButtons = {}
	for index, name in ipairs(INV_TAB_NAMES) do
		local variantName = (currentInvTab == name) and "primary" or "secondary"
		local tabButton = Hud.button({
			variant = variantName,
			text = name:upper(),
			size = UDim2.new(0, INV_TAB_WIDTH, 1, 0),
			layoutOrder = index,
			parent = inv.tabRow,
			-- Hard offset shadow instead of the default bevel gradient — the reference's tabs read as
			-- solid squares with a drop shadow under them, not a gradient-filled pill. (HudKit.button
			-- is gaining this option alongside this change; once it lands, this is the only call site
			-- in this file that needs it — every other Hud.button() call here keeps the gradient.)
			dropShadow = true,
			onClick = function()
				selectInvTab(name)
			end,
		})
		-- HudKit.button() defaults every button to FONT.BodyBold/TEXTSIZE.Body — overridden here to
		-- the small-uppercase-label treatment the reference wants for tab captions specifically
		-- (Display font, Label size).
		--
		-- TextSize dropped to 11, NOT TEXTSIZE.Label (13): at 91px-wide tabs (see INV_TAB_WIDTH above)
		-- "WEAPONS" happened to look fine at 13 (7 uppercase GothamBold characters, roughly
		-- 7 * 0.6 * 13 =~ 55px — comfortable), but "MATERIALS" (9 characters, the same estimate puts
		-- it around 9 * 0.6 * 13 =~ 70px) was landing close enough to the 91px cap that kerning on
		-- wide glyphs (M, A, T) pushed actual rendering past it — this project has no TextService
		-- access outside Studio to get an exact number, so this is a per-character estimate, not a
		-- measured one; if it's still tight in Studio, drop this further before widening the tab or
		-- shrinking INV_TAB_GAP, since every other row's math (390px, both here and in the grid below)
		-- is keyed off the current 4-tabs-at-91px layout and would need re-deriving. At 11, the same
		-- estimate puts MATERIALS around 9 * 0.6 * 11 =~ 59px — comfortable headroom in 91px, same
		-- "override after building" pattern the detail-panel slot buttons a few sections up already
		-- use for their own non-default text styling.
		--
		-- INV_TAB_HEIGHT growing 32 -> 40 (see that constant's comment) does NOT change this: this
		-- estimate is entirely a function of tab WIDTH (91px, unchanged) and character count, not
		-- height. Text is vertically centered in the button by HudKit.button's own layout, so a
		-- taller box just adds equal padding above/below the same glyphs — it doesn't tighten or
		-- loosen the 91px horizontal fit at all. If 11px now reads too small against the taller,
		-- squared-off tab in Studio, that's a fresh visual call to make there, not a reason to bump
		-- this blindly — doing so would need re-verifying the same MATERIALS-fits-in-91px estimate
		-- above, this time at a bigger size where the margin is smaller.
		tabButton.Font = Hud.FONT.Display
		tabButton.TextSize = 11
		inv.tabButtons[name] = tabButton
	end

	selectInvTab = function(name: string)
		Hud.setButtonVariant(inv.tabButtons[currentInvTab], "secondary")
		currentInvTab = name
		Hud.setButtonVariant(inv.tabButtons[currentInvTab], "primary")
		closeInvDetail() -- a Mods-tab selection doesn't make sense once you've switched to Weapons, etc.
		renderInvList()
	end

	local function openInventory()
		inv.frame.Visible = true
		closeInvDetail()
		renderInvList()
	end

	-- The main panel's close button (built by Hud.panelHeader, up where inv.surface was created)
	-- already runs inv.frame.Visible = false / closeInvDetail() / ModPicker.closeModPicker() as its
	-- onClose callback — nothing left to wire up here.

	return {
		openInventory = openInventory,
		renderInvList = renderInvList,
		refreshInvDetailIfShowing = refreshInvDetailIfShowing,
		isVisible = function()
			return inv.frame.Visible
		end,
		-- Exposed for the Smelting tab's ore-picker popup in MainHud.client.lua — see this file's
		-- header comment on why that dependency runs this direction instead of the more usual one.
		TILE_SIZE = TILE_SIZE,
		makeItemTile = makeItemTile,
	}
end

return InventoryPanel
