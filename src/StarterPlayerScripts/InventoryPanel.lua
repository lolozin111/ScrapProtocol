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

	local TILE_SIZE = 76

	-- One table instead of 15 separate top-level locals: Luau caps a function scope at 200
	-- locals and this file's main chunk hit that ceiling. Grouping UI element references costs
	-- nothing at runtime and buys back a register per element.
	local inv = {}
	inv.frame = Hud.new("Frame", {
		Name = "Inventory",
		BackgroundColor3 = Hud.COLOR.Panel,
		Position = UDim2.new(0.5, -320, 0.5, -200),
		Size = UDim2.new(0, 640, 0, 400),
		Visible = false,
		Parent = Hud.screenGui,
	}, { Hud.corner(10), Hud.stroke() })

	Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 10),
		Size = UDim2.new(1, -60, 0, 22),
		Font = Enum.Font.SourceSansBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Hud.COLOR.Text,
		TextSize = 18,
		Text = "Inventory",
		Parent = inv.frame,
	})

	-- Instance only — connected at the very bottom of this section, once closeInvDetail exists.
	inv.closeButton = Hud.new("TextButton", {
		BackgroundColor3 = Hud.COLOR.PanelLight,
		Position = UDim2.new(1, -40, 0, 8),
		Size = UDim2.new(0, 28, 0, 28),
		Font = Enum.Font.SourceSansBold,
		TextColor3 = Hud.COLOR.Text,
		TextSize = 16,
		Text = "X",
		Parent = inv.frame,
	}, { Hud.corner(6) })

	inv.tabRow = Hud.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 40),
		Size = UDim2.new(1, -24, 0, 32),
		Parent = inv.frame,
	}, { Hud.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }) })

	inv.listFrame = Hud.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 80),
		Size = UDim2.new(1, -24, 1, -92),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = inv.frame,
	}, { Hud.new("UIGridLayout", { CellSize = UDim2.new(0, TILE_SIZE, 0, TILE_SIZE), CellPadding = UDim2.new(0, 8, 0, 8) }) })

	-- Overlays inv.listFrame's area with a plain message when the current tab has nothing to show —
	-- UIGridLayout forces every child to CellSize, so a full-width "nothing here" message can't be a
	-- grid child without looking cramped; this sits outside the grid instead and is only ever shown
	-- when the grid has zero tiles in it, so the two never actually overlap in practice.
	inv.emptyLabel = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 80),
		Size = UDim2.new(1, -24, 1, -92),
		Font = Enum.Font.SourceSansItalic,
		TextColor3 = Hud.COLOR.Muted,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
		Text = "",
		Parent = inv.frame,
	})

	----------------------------------------------------------------------
	-- Detail panel — sits just right of the Inventory, populated by clicking a tile. Shared by all
	-- four tabs; which parts are visible (mod slots, the action button) depends on the category.
	----------------------------------------------------------------------

	inv.detailFrame = Hud.new("Frame", {
		Name = "InventoryDetail",
		BackgroundColor3 = Hud.COLOR.Panel,
		Position = UDim2.new(0.5, 330, 0.5, -200),
		Size = UDim2.new(0, 260, 0, 400),
		Visible = false,
		Parent = Hud.screenGui,
	}, { Hud.corner(10), Hud.stroke() })

	inv.detailTitle = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 8),
		Size = UDim2.new(1, -50, 0, 24),
		Font = Enum.Font.SourceSansBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Hud.COLOR.Text,
		TextSize = 17,
		TextWrapped = true,
		Text = "",
		Parent = inv.detailFrame,
	})

	-- Instance only — connected once closeInvDetail exists, just below.
	inv.detailCloseButton = Hud.new("TextButton", {
		BackgroundColor3 = Hud.COLOR.PanelLight,
		Position = UDim2.new(1, -36, 0, 8),
		Size = UDim2.new(0, 28, 0, 28),
		Font = Enum.Font.SourceSansBold,
		TextColor3 = Hud.COLOR.Text,
		TextSize = 16,
		Text = "X",
		Parent = inv.detailFrame,
	}, { Hud.corner(6) })

	inv.detailImage = Hud.new("ImageLabel", {
		BackgroundColor3 = Hud.COLOR.PanelLight,
		Position = UDim2.new(0, 10, 0, 42),
		Size = UDim2.new(1, -20, 0, 140),
		ScaleType = Enum.ScaleType.Fit,
		Image = "",
		Parent = inv.detailFrame,
	}, { Hud.corner(8) })

	inv.detailStats = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 190),
		Size = UDim2.new(1, -20, 0, 36),
		Font = Enum.Font.Code,
		TextColor3 = Hud.COLOR.Muted,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		Parent = inv.detailFrame,
	})

	inv.detailDescription = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 230),
		Size = UDim2.new(1, -20, 0, 70),
		Font = Enum.Font.SourceSans,
		TextColor3 = Hud.COLOR.Text,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		Parent = inv.detailFrame,
	})

	-- Weapons/Robots only — same slot-button idea as makeEquipmentRow's slotRow, just rebuilt for
	-- whichever item the detail panel currently shows instead of being baked into a row.
	inv.detailSlotRow = Hud.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 306),
		Size = UDim2.new(1, -20, 0, 30),
		Visible = false,
		Parent = inv.detailFrame,
	}, { Hud.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })

	-- Weapons/Robots only — Equip, or Deploy/Undeploy. Hidden for Mods/Materials (nothing to toggle).
	-- Connected further down, once inv.detailState/deployedCountForRobot are in scope.
	inv.detailButton = Hud.new("TextButton", {
		BackgroundColor3 = Hud.COLOR.Accent,
		Position = UDim2.new(0, 10, 1, -42),
		Size = UDim2.new(1, -20, 0, 32),
		Font = Enum.Font.SourceSansBold,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 15,
		Visible = false,
		Text = "",
		Parent = inv.detailFrame,
	}, { Hud.corner(6) })

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
			local slotButton = Hud.new("TextButton", {
				BackgroundColor3 = mod and Hud.COLOR.AccentDark or Hud.COLOR.Panel,
				Size = UDim2.new(0, slotWidth, 1, 0),
				Font = Enum.Font.Code,
				TextColor3 = Hud.COLOR.Text,
				TextSize = 11,
				TextWrapped = true,
				Text = mod and mod.DisplayName or ("Slot %d"):format(slotIndex),
				Parent = inv.detailSlotRow,
			}, { Hud.corner(4), Hud.stroke() })
			slotButton.MouseButton1Click:Connect(function()
				ModPicker.openModPicker(tree, itemKey, slotIndex)
			end)
		end

		if showUltimate then
			local equippedUltimate = (Hud.profile.EquippedUltimate or {})[itemKey]
			local data = equippedUltimate and UltimateConfig.Mods[equippedUltimate]
			local rarity = ModConfig.Rarities[UltimateConfig.Rarity] or {}
			local ultButton = Hud.new("TextButton", {
				-- Tinted with the Mythical colour whether filled or empty, so the slot reads as a
				-- different KIND of slot at a glance rather than a fourth ordinary one.
				BackgroundColor3 = data and (rarity.Color or Hud.COLOR.AccentDark) or Hud.COLOR.Panel,
				Size = UDim2.new(0, slotWidth, 1, 0),
				Font = Enum.Font.Code,
				TextColor3 = data and Color3.new(1, 1, 1) or (rarity.Color or Hud.COLOR.Muted),
				TextSize = 11,
				TextWrapped = true,
				Text = data and data.DisplayName or UltimateConfig.SlotLabel,
				Parent = inv.detailSlotRow,
			}, { Hud.corner(4), Hud.stroke() })
			ultButton.MouseButton1Click:Connect(function()
				openUltPicker(itemKey)
			end)
		end

		inv.detailSlotRow.Visible = true
	end

	local function closeInvDetail()
		inv.detailFrame.Visible = false
		inv.detailState.category = nil
		inv.detailState.key = nil
	end
	inv.detailCloseButton.MouseButton1Click:Connect(closeInvDetail)

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

	----------------------------------------------------------------------
	-- Grid tiles — one per tab, built fresh every render
	----------------------------------------------------------------------

	local function makeItemTile(key: string, displayName: string, badgeText: string?, highlighted: boolean, onSelect)
		local icon = Hud.getItemIcon(key)
		local tile = Hud.new("ImageButton", {
			BackgroundColor3 = highlighted and Hud.COLOR.AccentDark or Hud.COLOR.PanelLight,
			AutoButtonColor = false,
			Image = icon or "",
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.new(0, TILE_SIZE, 0, TILE_SIZE),
		}, { Hud.corner(8), Hud.stroke() })

		if not icon then
			Hud.new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 3, 0, 3),
				Size = UDim2.new(1, -6, 1, -6),
				Font = Enum.Font.SourceSansBold,
				TextColor3 = Hud.COLOR.Muted,
				TextSize = 12,
				TextWrapped = true,
				Text = displayName,
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
				Parent = tile,
			}, { Hud.corner(4) })
		end

		tile.MouseButton1Click:Connect(onSelect)
		return tile
	end

	local currentInvTab = "Weapons"

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
			-- Icon lookup key is instance.WeaponKey (the TYPE, icons aren't per-roll), but selecting
			-- the tile opens the detail panel on this specific instance.Id.
			makeItemTile(instance.WeaponKey, recipe.DisplayName, rarityData and rarityData.Badge or "?", equipped, function()
				showInvDetail("Weapons", instance.Id)
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
			makeItemTile(key, recipe.DisplayName, ("x%d"):format(Hud.profile.CraftedRobots[key]), deployed > 0, function()
				showInvDetail("Robots", key)
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
			makeItemTile(key, mod.DisplayName, nil, false, function()
				showInvDetail("Mods", key)
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
		makeItemTile("Scrap", "Scrap", nil, false, function()
			showInvDetail("Materials", "Scrap")
		end).Parent = inv.listFrame
		makeItemTile("Cores", "Cores", nil, false, function()
			showInvDetail("Materials", "Cores")
		end).Parent = inv.listFrame
		for _, oreKey in ipairs(ORE_DISPLAY_ORDER) do
			local displayName = OreConfig.Ores[oreKey].DisplayName
			makeItemTile(oreKey, displayName, nil, false, function()
				showInvDetail("Materials", oreKey)
			end).Parent = inv.listFrame
		end
		for _, refineData in pairs(RefinedOreConfig.Ores) do
			local owned = (Hud.profile.RefinedOreCounts or {})[refineData.RefinedKey] or 0
			if owned > 0 then
				makeItemTile(refineData.RefinedKey, refineData.DisplayName, ("x%d"):format(owned), false, function()
					showInvDetail("Materials", refineData.RefinedKey)
				end).Parent = inv.listFrame
			end
		end
	end

	local function renderInvList()
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

	local function selectInvTab(name: string)
		currentInvTab = name
		for _, sibling in ipairs(inv.tabRow:GetChildren()) do
			if sibling:IsA("TextButton") then
				sibling.BackgroundColor3 = sibling.Text == name and Hud.COLOR.Accent or Hud.COLOR.PanelLight
			end
		end
		closeInvDetail() -- a Mods-tab selection doesn't make sense once you've switched to Weapons, etc.
		renderInvList()
	end

	local function makeInvTabButton(name: string)
		local button = Hud.new("TextButton", {
			BackgroundColor3 = currentInvTab == name and Hud.COLOR.Accent or Hud.COLOR.PanelLight,
			Size = UDim2.new(0, 140, 1, 0),
			Font = Enum.Font.SourceSansBold,
			TextColor3 = Hud.COLOR.Text,
			TextSize = 15,
			Text = name,
			Parent = inv.tabRow,
		}, { Hud.corner(6) })
		button.MouseButton1Click:Connect(function()
			selectInvTab(name)
		end)
		return button
	end

	-- Unlike the Workbench's tab row (which rebuilds per-station), the Inventory's tabs never
	-- change — every filter is always available no matter where you are, since viewing is unrestricted.
	makeInvTabButton("Weapons")
	makeInvTabButton("Robots")
	makeInvTabButton("Mods")
	makeInvTabButton("Materials")

	local function openInventory()
		inv.frame.Visible = true
		closeInvDetail()
		renderInvList()
	end

	inv.closeButton.MouseButton1Click:Connect(function()
		inv.frame.Visible = false
		closeInvDetail()
		ModPicker.closeModPicker() -- don't leave the mod picker orphaned open behind a closed Inventory
	end)

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
