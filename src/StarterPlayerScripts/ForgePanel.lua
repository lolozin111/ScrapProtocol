--[[
	ForgePanel.lua
	The Forge's Weapons tab, rebuilt as HUD phase 3's "Crucible" (design round, DESIGN_NOTES.md
	section C — the chosen direction is Forge A). The Forge's other tab, Smelting, is the Batch Dial
	and stays in MainHud.client.lua.

	WHAT CHANGED AND WHY. The tab was a stack of `makeRow`s: a tier-upgrade row, a potion-craft row,
	a "last forged" readout, then a family list, then a row per gun with a Forge button. Nothing on
	it looked like a machine, and the two numbers that actually govern a roll — your luck and your
	pity streak — had been evicted to a strip docked underneath the panel entirely.

	The player's own words started this direction: "the forge could have a slot where you put
	unprocessed ore in, it processes it, and you pick it up." So the tab is three columns —

	  INPUT BAY   what this roll consumes, per material, red where you are short; the family and
	              weapon you are rolling; and the Luck Potion as an ADDITIVE you slot in rather than
	              a button parked somewhere else on screen.
	  CHAMBER     the machine. A ring that sweeps while a roll resolves, the real odds underneath it
	              as a proportional bar, and pity redrawn as HEAT — a gauge on the machine that fills
	              as it runs cold and guarantees Rare+ at full.
	  OUTPUT TRAY what came out, and the choice of whether to keep it.

	THE TRAY IS REAL STATE, NOT PRESENTATION. `profile.ForgeOutput` holds one pending weapon and
	survives a relog; ForgeService's CollectForgeOutput moves it into your inventory and
	TrashForgeOutput drops it. That decision is in DESIGN_NOTES and it was made for the PILE, not for
	efficiency: players reroll the same weapon chasing a good one, and if every roll landed in the
	inventory they would drown in junk they then have to sort. The tray is what lets a roll be
	REFUSED.

	Rules that follow, all re-checked server-side:

	- No refund on trash. You paid for the roll, not for the gun.
	- Rolling with the tray occupied OVERWRITES it — except when what is in there is
	  ForgeConfig.DiscardConfirmMinRarity or better, which raises a confirmation first. Blocking the
	  roll outright was rejected: it taxes the common case (junk roll, instant reroll) to guard the
	  rare one, and the confirm already guards the rare one.
	- The confirm is client UX, so `ForgeWeapon` refuses an unconfirmed roll that would discard a
	  precious pending output regardless. A client that lies can only hurt itself.

	WHAT THE MOCKUP DID NOT SETTLE. It draws one dropdown, labelled Family, and no way to pick WHICH
	gun in that family you are rolling — but the input bay has to price a specific recipe, so the
	screen needs both. It gets two rows of the same drawn control, Family and Weapon. And it drew a
	single Collect button where DESIGN_NOTES had already decided on Collect and Trash side by side;
	the decision wins over the drawing.

	This also RETIRES the docked pity bar and Luck Potion button that used to hang under the plate
	(MainHud's `forgeDock` / `pity` / `potionButton` / `setForgeWidgetsVisible`, all deleted). Heat
	and the additive slot say the same two things in the place they belong, and the dock was the only
	reason the bottom action row had to hide itself whenever the Forge was open.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)
local ForgeConfig = require(ReplicatedStorage.Shared.ForgeConfig)
local ModConfig = require(ReplicatedStorage.Shared.ModConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local Wallet = require(ReplicatedStorage.Shared.Wallet)
local WeaponFamilyConfig = require(ReplicatedStorage.Shared.WeaponFamilyConfig)

local Hud = require(script.Parent.HudKit)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local ForgePanel = {}

----------------------------------------------------------------------
-- Geometry
----------------------------------------------------------------------
-- Derived from the station's configured panel size for the same reason WeldingPanel's and the
-- Smelting tab's are: the plate is sized per station now, and a hardcoded 760x520 would silently
-- stop filling the panel the day StationConfig is retuned. 116 is MainHud's header/tab stack above
-- `listFrame`, 12 the bottom margin, 6 the plate's 3px bevel per side, 24 listFrame's own margins.
local PANEL_SIZE = StationConfig.Types.Forge.PanelSize or StationConfig.DefaultPanelSize

local BODY_HEIGHT = PANEL_SIZE.Y - 116 - 12
local CONTENT_WIDTH = PANEL_SIZE.X - 6 - 24

local COL_GAP = Hud.SPACE.M
local LEFT_WIDTH = 196
local RIGHT_WIDTH = 196
local MID_WIDTH = CONTENT_WIDTH - LEFT_WIDTH - RIGHT_WIDTH - COL_GAP * 2
local MID_X = LEFT_WIDTH + COL_GAP
local RIGHT_X = MID_X + MID_WIDTH + COL_GAP

local LABEL_HEIGHT = 14
local PICKER_ROW_HEIGHT = 40

local CHAMBER_TOP = 20
local CHAMBER_HEIGHT = 218
local CHAMBER_DIAL = 168 -- the outer guide circle
local CHAMBER_RING = 132 -- the ring that sweeps while a roll resolves
local CHAMBER_GLYPH = 64

local ODDS_BAR_Y = CHAMBER_TOP + CHAMBER_HEIGHT + 10
local ODDS_BAR_HEIGHT = 6
local ODDS_CAPTION_Y = ODDS_BAR_Y + ODDS_BAR_HEIGHT + 6
local HEAT_Y = ODDS_CAPTION_Y + 26
local HEAT_BAR_HEIGHT = 8
local HEAT_CAPTION_Y = HEAT_Y + 20

local TRAY_TOP = 20
local TRAY_HEIGHT = 150
local TRAY_ACTION_Y = TRAY_TOP + TRAY_HEIGHT + 8
local TRAY_ACTION_HEIGHT = 40
local FORGE_BUTTON_HEIGHT = 52

-- How long the chamber's ring sweeps before the tray reveals what came out. The roll itself already
-- resolved server-side before this starts — the sweep is not waiting on anything, it is the beat
-- between committing and finding out, which is the whole reason anyone pulls the lever twice.
-- Anchored to a timestamp rather than a countdown so a re-render partway through (every
-- InventoryUpdate re-renders the open tab) resumes at the right phase instead of restarting.
local ROLL_SWEEP_SECONDS = 0.55

----------------------------------------------------------------------
-- Formatters
----------------------------------------------------------------------

local function rarityColor(rarityKey: string?): Color3
	local data = rarityKey and ModConfig.Rarities[rarityKey]
	return data and data.Color or Hud.COLOR.Muted
end

local function rarityName(rarityKey: string?): string
	local data = rarityKey and ModConfig.Rarities[rarityKey]
	return data and data.DisplayName or tostring(rarityKey)
end

-- "+22% dmg" / "+14% rate" — the compact form the tray's affix rows use. The Inventory panel's
-- affixSummary spells the same data out as a sentence; this has 80 pixels.
local function affixValue(affix): string
	local suffix = affix.Stat == "FireRateMultiplier" and "rate" or "dmg"
	return ("+%d%% %s"):format(math.floor(affix.Magnitude * 100 + 0.5), suffix)
end

----------------------------------------------------------------------
-- Panel
----------------------------------------------------------------------

export type ForgePanelContext = {
	listFrame: Instance, -- the craft plate's body; the tab renders one full-height Frame into it
	craftHeader: Instance, -- the plate's header bar, where the forge tier / luck readout sits
	refresh: () -> (), -- re-render the whole craft list (MainHud's renderCraftList)
}

function ForgePanel.new(context: ForgePanelContext)
	local listFrame = context.listFrame
	local refresh = context.refresh

	-- Client-only UI state, all of it surviving a re-render.
	local selectedFamily: string? = nil
	local selectedWeapon: string? = nil
	local usePotion = false -- whether the NEXT roll burns one; ForgeWeapon re-validates ownership
	local rollStartedAt: number? = nil -- os.clock() when the current sweep began, nil when idle

	------------------------------------------------------------------
	-- Header readout: the forge tier, its luck, and the upgrade
	------------------------------------------------------------------
	-- A station-wide fact, so it lives in the panel header rather than in the tab body — the same
	-- place (and for the same reason) the Welding Station puts its deploy count. Built once and
	-- relabelled per render; MainHud hides it when a tab this panel does not own is showing.

	local readout = Hud.new("Frame", {
		Name = "ForgeReadout",
		AnchorPoint = Vector2.new(1, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		-- Clear of the header's own 40px close button, plus a gap either side.
		Position = UDim2.new(1, -(40 + Hud.SPACE.S + Hud.SPACE.S), 0.5, 0),
		Size = UDim2.fromOffset(0, 28),
		Visible = false,
		Parent = context.craftHeader,
	}, { Hud.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Hud.SPACE.S),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}) })

	local tierLabel = Hud.new("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Hud.FONT.Display,
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 20),
		Text = "",
		TextColor3 = Hud.COLOR.Muted,
		TextSize = 11,
		Parent = readout,
	})

	local luckLabel = Hud.new("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Hud.FONT.Mono,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 20),
		Text = "",
		TextColor3 = Hud.COLOR.Good,
		TextSize = Hud.TEXTSIZE.Label,
		Parent = readout,
	})

	-- Built once, not per render: it lives in the header, which renderCraftList's sweep does not
	-- clear. Only its text and variant change.
	local upgradeButton = Hud.button({
		variant = "secondary",
		text = "Upgrade",
		layoutOrder = 3,
		size = UDim2.fromOffset(88, 28),
		parent = readout,
		onClick = function()
			local result = Remotes.UpgradeForgeTier:InvokeServer()
			if not result.Success then
				Hud.showFailure("Forge upgrade failed", result.Reason)
			end
		end,
	})

	local function refreshReadout()
		local tier = Hud.profile.ForgeTier or 1
		local tierData = ForgeConfig.ForgeTiers[tier]
		local nextTierData = ForgeConfig.ForgeTiers[tier + 1]

		tierLabel.Text = (tierData and tierData.Name or "Forge"):upper()
		-- The PERMANENT luck, not the potion-boosted figure: this is a property of the machine, and
		-- the potion's contribution belongs next to the potion. The odds bar shows the combined
		-- number's actual effect, which is the honest place for it.
		luckLabel.Text = ("+%d luck"):format(tierData and tierData.Bonus or 0)

		if nextTierData then
			local cost = ForgeConfig.ForgeTierCosts[tier + 1]
			upgradeButton.Text = "Upgrade"
			Hud.setButtonVariant(upgradeButton, cost and Wallet.CanAfford(Hud.profile, cost) and "primary" or "secondary")
		else
			upgradeButton.Text = "Maxed"
			Hud.setButtonVariant(upgradeButton, "secondary")
		end

		readout.Visible = true
	end

	------------------------------------------------------------------
	-- Selection
	------------------------------------------------------------------

	local function weaponsInFamily(familyKey: string?): { string }
		local keys = {}
		for key, recipe in pairs(CraftingRecipes.Weapons) do
			if recipe.Family == familyKey then
				table.insert(keys, key)
			end
		end
		table.sort(keys, function(a, b)
			return CraftingRecipes.Weapons[a].Tier < CraftingRecipes.Weapons[b].Tier
		end)
		return keys
	end

	-- Re-validated on every render rather than trusted: a family can become unlocked (or the config
	-- can change) between one render and the next, and a weapon key that no longer exists would take
	-- the whole panel down when the input bay tried to price it.
	local function resolveSelection()
		if selectedFamily and not WeaponFamilyConfig.IsUnlocked(Hud.profile, selectedFamily) then
			selectedFamily = nil
		end
		if not selectedFamily then
			for _, familyKey in ipairs(WeaponFamilyConfig.Order) do
				if WeaponFamilyConfig.IsUnlocked(Hud.profile, familyKey) then
					selectedFamily = familyKey
					break
				end
			end
			selectedWeapon = nil
		end

		local keys = weaponsInFamily(selectedFamily)
		if selectedWeapon then
			local recipe = CraftingRecipes.Weapons[selectedWeapon]
			if not recipe or recipe.Family ~= selectedFamily then
				selectedWeapon = nil
			end
		end
		selectedWeapon = selectedWeapon or keys[1]
	end

	------------------------------------------------------------------
	-- Pickers
	------------------------------------------------------------------
	-- Both dropdowns raise the shared HudKit.modal plate (Popups B) rather than an in-place
	-- expanding list: the left column has no room to grow, and a popup that matches its parent menu
	-- is the whole point of having built that plate.

	local function openPicker(title: string, entries: {
		{ label: string, detail: string, locked: boolean?, lockedReason: string?, onPick: () -> () }
	})
		local modal = Hud.modal({
			title = title,
			width = 380,
			actions = { { text = "Cancel" } },
			dismissOnScrim = true,
		})

		local list = Hud.new("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			ScrollBarThickness = 4,
			Size = UDim2.new(1, 0, 0, math.min(#entries * 52, 260)),
			Parent = modal.content,
		}, { Hud.new("UIListLayout", { Padding = UDim.new(0, Hud.SPACE.XS) }) })

		for _, entry in ipairs(entries) do
			local row = Hud.new("TextButton", {
				AutoButtonColor = false,
				BackgroundColor3 = Hud.darken(Hud.COLOR.Panel, 0.2),
				BorderSizePixel = 0,
				Size = UDim2.new(1, -4, 0, 48),
				Text = "",
				Parent = list,
			}, { Hud.corner(Hud.RADIUS.Button) })

			Hud.new("Frame", {
				BackgroundColor3 = entry.locked and Hud.COLOR.Line or Hud.COLOR.Accent,
				BorderSizePixel = 0,
				Size = UDim2.new(0, 3, 1, 0),
				Parent = row,
			})

			Hud.new("TextLabel", {
				BackgroundTransparency = 1,
				Font = Hud.FONT.Display,
				Position = UDim2.fromOffset(12, 7),
				Size = UDim2.new(1, -24, 0, 16),
				Text = entry.label,
				TextColor3 = entry.locked and Hud.COLOR.Muted or Hud.COLOR.Text,
				TextSize = 12,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = row,
			})

			Hud.new("TextLabel", {
				BackgroundTransparency = 1,
				Font = Hud.FONT.Mono,
				Position = UDim2.fromOffset(12, 25),
				Size = UDim2.new(1, -24, 0, 16),
				Text = entry.detail,
				TextColor3 = Hud.COLOR.Muted,
				TextSize = 11,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = row,
			})

			row.MouseButton1Click:Connect(function()
				if entry.locked then
					-- Locked entries stay LISTED and stay clickable, and say what opens them. A player
					-- who cannot see what they are missing has no reason to chase a case.
					Hud.showFailure(entry.label, entry.lockedReason or "Locked")
					return
				end
				modal.close()
				entry.onPick()
			end)
		end
	end

	local function openFamilyPicker()
		local entries = {}
		for _, familyKey in ipairs(WeaponFamilyConfig.Order) do
			local family = WeaponFamilyConfig.Families[familyKey]
			local unlocked = WeaponFamilyConfig.IsUnlocked(Hud.profile, familyKey)
			local count = #weaponsInFamily(familyKey)
			table.insert(entries, {
				label = family.DisplayName,
				detail = unlocked
					and ("%d weapon%s · %s"):format(count, count == 1 and "" or "s", family.Description)
					or ("LOCKED · %s"):format(WeaponFamilyConfig.BlueprintName(familyKey)),
				locked = not unlocked,
				lockedReason = ("Its blueprint (%s) drops from Legendary rolls at the Black Market."):format(
					WeaponFamilyConfig.BlueprintName(familyKey)),
				onPick = function()
					selectedFamily = familyKey
					selectedWeapon = nil
					refresh()
				end,
			})
		end
		openPicker("CHOOSE A FAMILY", entries)
	end

	local function openWeaponPicker()
		local entries = {}
		for _, key in ipairs(weaponsInFamily(selectedFamily)) do
			local recipe = CraftingRecipes.Weapons[key]
			table.insert(entries, {
				label = ("T%d  %s"):format(recipe.Tier, recipe.DisplayName),
				detail = ("%.1f dmg × %.1f/s  ·  %s"):format(
					recipe.BaseDamage, recipe.FireRate, Hud.costString(recipe.Cost)),
				onPick = function()
					selectedWeapon = key
					refresh()
				end,
			})
		end
		openPicker("CHOOSE A WEAPON", entries)
	end

	------------------------------------------------------------------
	-- Left column — the input bay
	------------------------------------------------------------------

	local function makeColumnLabel(parent: Instance, text: string, order: number)
		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, LABEL_HEIGHT),
			Text = text,
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = parent,
		})
	end

	-- One material line. Shows a bare owned count when you have enough and "have / need" in Bad when
	-- you do not — the shortfall is the only thing standing between you and the button, so it says
	-- exactly how short rather than just going red.
	local function makeCostLine(parent: Instance, costKey: string, needed: number, order: number)
		local owned = Wallet.GetAmount(Hud.profile, costKey)
		local short = owned < needed
		local color = short and Hud.COLOR.Bad or Hud.COLOR.Text

		local row = Hud.new("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 22),
			Parent = parent,
		})

		Hud.new("ImageLabel", {
			BackgroundTransparency = 1,
			Image = Hud.getItemIcon(costKey) or "",
			ImageColor3 = short and Hud.COLOR.Bad or Color3.new(1, 1, 1),
			Position = UDim2.fromOffset(0, 3),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(16, 16),
			Parent = row,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Body,
			Position = UDim2.fromOffset(24, 0),
			Size = UDim2.new(1, -94, 1, 0),
			Text = Wallet.DisplayName(costKey),
			TextColor3 = color,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})

		Hud.new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(66, 22),
			Text = short and ("%d / %d"):format(owned, needed) or tostring(needed),
			TextColor3 = color,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
	end

	-- The Family / Weapon dropdown, and the additive slot, are the same drawn control: a bordered
	-- row with a leading icon, a label, and a trailing affordance. `dashed` is the additive slot's
	-- empty treatment, matching what an unfitted mod slot looks like at the Welding Station.
	local function makePickerRow(parent: Instance, opts: {
		order: number,
		iconKey: string?,
		text: string,
		trailing: string,
		trailingColor: Color3?,
		dashed: boolean?,
		accent: boolean?,
		onClick: () -> (),
	})
		local row = Hud.new("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = opts.dashed and Hud.darken(Hud.COLOR.Panel, 0.2) or Hud.COLOR.PanelLight,
			BorderSizePixel = 0,
			LayoutOrder = opts.order,
			Size = UDim2.fromOffset(LEFT_WIDTH, PICKER_ROW_HEIGHT),
			Text = "",
			Parent = parent,
		}, { Hud.corner(Hud.RADIUS.Button) })

		if opts.dashed then
			Hud.dashedBox(row, {
				width = LEFT_WIDTH,
				height = PICKER_ROW_HEIGHT,
				color = Hud.COLOR.Line,
				cornerInset = Hud.RADIUS.Button,
			})
		else
			Hud.new("UIStroke", {
				Color = opts.accent and Hud.COLOR.Accent or Hud.COLOR.Line,
				Thickness = 1,
				Parent = row,
			})
		end

		local hasIcon = opts.iconKey and Hud.getItemIcon(opts.iconKey) ~= nil
		if hasIcon then
			Hud.new("ImageLabel", {
				BackgroundTransparency = 1,
				Image = Hud.getItemIcon(opts.iconKey :: string) :: string,
				Position = UDim2.fromOffset(10, 11),
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromOffset(18, 18),
				Parent = row,
			})
		end

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.fromOffset(hasIcon and 36 or 12, 0),
			Size = UDim2.new(1, -(hasIcon and 36 or 12) - 46, 1, 0),
			Text = opts.text,
			TextColor3 = opts.dashed and Hud.COLOR.Muted or Hud.COLOR.Text,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})

		Hud.new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(40, 20),
			Text = opts.trailing,
			TextColor3 = opts.trailingColor or Hud.COLOR.Muted,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})

		row.MouseButton1Click:Connect(opts.onClick)
		return row
	end

	local function drawInputBay(body: Instance)
		local column = Hud.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(0, LEFT_WIDTH, 1, 0),
			Parent = body,
		}, { Hud.new("UIListLayout", {
			Padding = UDim.new(0, Hud.SPACE.XS + 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}) })

		makeColumnLabel(column, "INPUT BAY", 1)

		local bay = Hud.new("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Hud.darken(Hud.COLOR.Panel, 0.2),
			BorderSizePixel = 0,
			LayoutOrder = 2,
			Size = UDim2.fromOffset(LEFT_WIDTH, 0),
			Parent = column,
		}, {
			Hud.corner(Hud.RADIUS.Button),
			Hud.stroke(),
			Hud.new("UIPadding", {
				PaddingTop = UDim.new(0, 9),
				PaddingBottom = UDim.new(0, 9),
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			}),
			Hud.new("UIListLayout", { Padding = UDim.new(0, Hud.SPACE.XS), SortOrder = Enum.SortOrder.LayoutOrder }),
		})

		local recipe = selectedWeapon and CraftingRecipes.Weapons[selectedWeapon]
		if recipe then
			-- Sorted, not pairs() order: this bay re-renders on every InventoryUpdate, and an
			-- unordered cost list reshuffles its own rows between renders — which reads as a flicker,
			-- not as data. Wallet.CostString sorts by key for exactly this reason; same order here so
			-- the bay and any cost string elsewhere on screen agree.
			local costKeys = {}
			for costKey in pairs(recipe.Cost) do
				table.insert(costKeys, costKey)
			end
			table.sort(costKeys)
			for order, costKey in ipairs(costKeys) do
				makeCostLine(bay, costKey, recipe.Cost[costKey], order)
			end
		else
			Hud.new("TextLabel", {
				BackgroundTransparency = 1,
				Font = Hud.FONT.Body,
				Size = UDim2.new(1, 0, 0, 22),
				Text = "Nothing selected",
				TextColor3 = Hud.COLOR.Muted,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = bay,
			})
		end

		local family = selectedFamily and WeaponFamilyConfig.Families[selectedFamily]
		makeColumnLabel(column, "FAMILY", 3)
		makePickerRow(column, {
			order = 4,
			text = family and family.DisplayName or "None unlocked",
			trailing = "▾",
			onClick = openFamilyPicker,
		})

		makeColumnLabel(column, "WEAPON", 5)
		makePickerRow(column, {
			order = 6,
			iconKey = selectedWeapon,
			text = recipe and recipe.DisplayName or "None",
			trailing = "▾",
			onClick = openWeaponPicker,
		})

		-- The potion as something you SLOT IN, not a button parked elsewhere on screen. Armed reads
		-- as a filled, accent-edged slot; unarmed as the same dashed empty socket an unfitted mod
		-- slot uses at the Welding Station.
		local potions = Hud.profile.LuckPotions or 0
		makeColumnLabel(column, "ADDITIVE SLOT", 7)
		makePickerRow(column, {
			order = 8,
			iconKey = "LuckPotion",
			text = usePotion and "Luck Potion — armed" or "Luck Potion",
			trailing = ("x%d"):format(potions),
			trailingColor = potions > 0 and Hud.COLOR.Good or Hud.COLOR.Muted,
			dashed = not usePotion,
			accent = usePotion,
			onClick = function()
				if potions <= 0 then
					Hud.showFailure(
						"No Luck Potions",
						("Craft one for %s — it adds +%d luck to a single roll."):format(
							Hud.costString(ForgeConfig.LuckPotion.Cost), ForgeConfig.LuckPotion.Bonus))
					return
				end
				usePotion = not usePotion
				refresh()
			end,
		})

		-- Crafting a potion is a secondary action and does not deserve a column slot of its own, so
		-- it hangs off the bottom of the bay where there is room.
		Hud.button({
			variant = Wallet.CanAfford(Hud.profile, ForgeConfig.LuckPotion.Cost) and "primary" or "secondary",
			text = "Craft Luck Potion",
			layoutOrder = 9,
			size = UDim2.fromOffset(LEFT_WIDTH, PICKER_ROW_HEIGHT),
			parent = column,
			onClick = function()
				local result = Remotes.CraftLuckPotion:InvokeServer()
				if not result.Success then
					Hud.showFailure("Craft Luck Potion failed", result.Reason)
				end
			end,
		})
	end

	------------------------------------------------------------------
	-- Middle column — the chamber
	------------------------------------------------------------------

	local function drawChamber(body: Instance)
		local column = Hud.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(MID_X, 0),
			Size = UDim2.fromOffset(MID_WIDTH, BODY_HEIGHT),
			Parent = body,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Size = UDim2.new(1, 0, 0, LABEL_HEIGHT),
			Text = "CHAMBER",
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = column,
		})

		local chamber = Hud.new("Frame", {
			BackgroundColor3 = Hud.darken(Hud.COLOR.Panel, 0.35),
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(0, CHAMBER_TOP),
			Size = UDim2.fromOffset(MID_WIDTH, CHAMBER_HEIGHT),
			Parent = column,
		}, { Hud.corner(Hud.RADIUS.Button), Hud.stroke() })

		-- Heat pooling in the bottom of the chamber. Roblox has no radial gradient, so the design's
		-- glow is a bottom band whose TRANSPARENCY is graded instead of its colour — same result,
		-- and it needs no art.
		-- Carries the chamber's own corner radius. ClipsDescendants on the chamber clips to its
		-- RECTANGLE, not to its rounded shape, so a square full-bleed band shows square corners poking
		-- through the rounded ones underneath it.
		Hud.new("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Hud.COLOR.AccentDark,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0.46, 0),
			Parent = chamber,
		}, { Hud.corner(Hud.RADIUS.Button), Hud.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0.67),
			}),
		}) })

		-- The outer guide circle: pure chrome, always the same, so the ring inside it reads as
		-- something that MOVES against something that does not.
		Hud.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(CHAMBER_DIAL, CHAMBER_DIAL),
			Parent = chamber,
		}, {
			Hud.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Hud.new("UIStroke", { Color = Hud.lighten(Hud.COLOR.Line, 0.15), Thickness = 1 }),
		})

		local ringHolder = Hud.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(CHAMBER_RING, CHAMBER_RING),
			Parent = chamber,
		})
		local ring = Hud.ring(ringHolder, { size = CHAMBER_RING, thickness = 3 })

		local recipe = selectedWeapon and CraftingRecipes.Weapons[selectedWeapon]
		local glyph = selectedWeapon and Hud.getItemIcon(selectedWeapon)

		if glyph then
			Hud.new("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Image = glyph,
				Position = UDim2.new(0.5, 0, 0.5, -10),
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromOffset(CHAMBER_GLYPH, CHAMBER_GLYPH),
				Parent = chamber,
			})
		else
			-- No icon uploaded for this gun yet: its NAME is a perfectly good thing to put in the
			-- middle of the chamber, and better than an empty circle. Missing art never breaks the loop.
			Hud.new("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Hud.FONT.Display,
				Position = UDim2.new(0.5, 0, 0.5, -10),
				Size = UDim2.fromOffset(CHAMBER_RING - 28, CHAMBER_GLYPH),
				Text = recipe and recipe.DisplayName or "—",
				TextColor3 = Hud.COLOR.Text,
				TextSize = 15,
				TextWrapped = true,
				Parent = chamber,
			})
		end

		local caption = Hud.new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.new(0.5, 0, 0.5, 34),
			Size = UDim2.fromOffset(CHAMBER_RING, 14),
			Text = "READY",
			TextColor3 = Hud.COLOR.Accent,
			TextSize = 11,
			Parent = chamber,
		})

		if rollStartedAt then
			caption.Text = "ROLLING"

			-- Driven on Heartbeat off os.clock() and anchored to rollStartedAt, so a re-render partway
			-- through (an InventoryUpdate lands mid-sweep) picks the arc up where it was rather than
			-- snapping back to zero. The connection dies with the instance it drives, or it leaks one
			-- handler per render for the rest of the session — the same rule the Smelting dial follows.
			local sweep
			sweep = RunService.Heartbeat:Connect(function()
				if not chamber.Parent then
					sweep:Disconnect()
					return
				end

				local elapsed = os.clock() - (rollStartedAt :: number)
				ring.setProgress(math.clamp(elapsed / ROLL_SWEEP_SECONDS, 0, 1))

				if elapsed >= ROLL_SWEEP_SECONDS then
					sweep:Disconnect()
					rollStartedAt = nil
					refresh() -- the reveal: the tray draws what came out
				end
			end)
		end

		------------------------------------------------------------------
		-- Odds
		------------------------------------------------------------------
		-- The REAL odds, from ForgeConfig.RollChances — the same weights ForgeService.rollRarity
		-- walks. A pity-forced roll passes the floor, so the bar collapses to the outcomes actually
		-- still possible rather than continuing to advertise a Common it can no longer produce.
		local pityForced = (Hud.profile.ForgePityCounter or 0) >= ForgeConfig.Pity.Threshold
		local luck = ForgeConfig.LuckPoints(Hud.profile, usePotion)
		local chances = ForgeConfig.RollChances(
			luck,
			pityForced and ForgeConfig.RarityIndex(ForgeConfig.Pity.MinRarity) or nil
		)

		local oddsBar = Hud.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, ODDS_BAR_Y),
			Size = UDim2.fromOffset(MID_WIDTH, ODDS_BAR_HEIGHT),
			Parent = column,
		})

		local parts = {}
		local cursor = 0
		for index, rarityKey in ipairs(ForgeConfig.RarityOrder) do
			local share = chances[index] or 0
			if share > 0 then
				Hud.new("Frame", {
					BackgroundColor3 = rarityColor(rarityKey),
					BorderSizePixel = 0,
					-- Scale positions with a small pixel inset per segment rather than a UIListLayout:
					-- a ListLayout sizes items and gaps independently and would either overflow the bar
					-- or leave the last slice an odd width. Same trick HudKit.segmentBar uses.
					Position = UDim2.fromScale(cursor, 0),
					Size = UDim2.new(share, -2, 1, 0),
					Parent = oddsBar,
				})
				cursor += share
			end
			table.insert(parts, ("%d"):format(math.floor(share * 100 + 0.5)))
		end

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.fromOffset(0, ODDS_CAPTION_Y),
			Size = UDim2.fromOffset(120, 14),
			Text = pityForced and "ODDS · FORCED" or "ODDS",
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 9,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = column,
		})

		Hud.new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.new(1, 0, 0, ODDS_CAPTION_Y),
			Size = UDim2.fromOffset(200, 14),
			Text = table.concat(parts, " / "),
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = column,
		})

		------------------------------------------------------------------
		-- Heat — pity, redrawn as a property of the machine
		------------------------------------------------------------------
		-- Same number profile.ForgePityCounter always held; the point of calling it heat is that a
		-- gauge on the machine is something a player reads without being told what pity means.
		local pityCount = math.min(Hud.profile.ForgePityCounter or 0, ForgeConfig.Pity.Threshold)
		local heatAlpha = pityCount / math.max(ForgeConfig.Pity.Threshold, 1)

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.fromOffset(0, HEAT_Y),
			Size = UDim2.fromOffset(34, 12),
			Text = "HEAT",
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 9,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = column,
		})

		local heatTrack = Hud.new("Frame", {
			BackgroundColor3 = Hud.darken(Hud.COLOR.Panel, 0.3),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(40, HEAT_Y + 2),
			Size = UDim2.fromOffset(MID_WIDTH - 40 - 48, HEAT_BAR_HEIGHT),
			Parent = column,
		})

		Hud.new("Frame", {
			BackgroundColor3 = heatAlpha >= 1 and Hud.COLOR.Good or Hud.COLOR.Accent,
			BorderSizePixel = 0,
			Size = UDim2.new(heatAlpha, 0, 1, 0),
			Parent = heatTrack,
		})

		Hud.new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.new(1, 0, 0, HEAT_Y),
			Size = UDim2.fromOffset(44, 12),
			Text = ("%d / %d"):format(pityCount, ForgeConfig.Pity.Threshold),
			TextColor3 = Hud.COLOR.Text,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = column,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Body,
			Position = UDim2.fromOffset(0, HEAT_CAPTION_Y),
			Size = UDim2.fromOffset(MID_WIDTH, 32),
			Text = pityForced
				and ("At full heat: this roll is guaranteed %s or better."):format(
					rarityName(ForgeConfig.Pity.MinRarity))
				or ("%s or better guaranteed at full heat."):format(rarityName(ForgeConfig.Pity.MinRarity)),
			TextColor3 = pityForced and Hud.COLOR.Good or Hud.COLOR.Muted,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = column,
		})
	end

	------------------------------------------------------------------
	-- Right column — the output tray
	------------------------------------------------------------------

	local function drawTray(body: Instance)
		local column = Hud.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(RIGHT_X, 0),
			Size = UDim2.fromOffset(RIGHT_WIDTH, BODY_HEIGHT),
			Parent = body,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Size = UDim2.new(1, 0, 0, LABEL_HEIGHT),
			Text = "OUTPUT TRAY",
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = column,
		})

		-- Held back while the chamber sweeps: the reveal is the point, and the server has already
		-- told us the answer by the time the animation starts.
		local pending = not rollStartedAt and Hud.profile.ForgeOutput or nil

		local card = Hud.new("Frame", {
			BackgroundColor3 = pending and Hud.darken(Hud.COLOR.Panel, 0.1) or Hud.darken(Hud.COLOR.Panel, 0.2),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, TRAY_TOP),
			Size = UDim2.fromOffset(RIGHT_WIDTH, TRAY_HEIGHT),
			Parent = column,
		}, { Hud.corner(Hud.RADIUS.Button) })

		if pending then
			-- Bordered in the ROLL'S OWN rarity colour, which is the fastest possible read on whether
			-- this one is worth keeping — before any text is parsed at all.
			Hud.new("UIStroke", { Color = rarityColor(pending.Rarity), Thickness = 1, Parent = card })
		else
			Hud.dashedBox(card, {
				width = RIGHT_WIDTH,
				height = TRAY_HEIGHT,
				color = Hud.COLOR.Line,
				cornerInset = Hud.RADIUS.Button,
			})
		end

		if not pending then
			Hud.new("TextLabel", {
				BackgroundTransparency = 1,
				Font = Hud.FONT.Display,
				Position = UDim2.fromOffset(12, 16),
				Size = UDim2.new(1, -24, 0, 18),
				Text = rollStartedAt and "···" or "EMPTY",
				TextColor3 = Hud.COLOR.Muted,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = card,
			})

			Hud.new("TextLabel", {
				BackgroundTransparency = 1,
				Font = Hud.FONT.Body,
				Position = UDim2.fromOffset(12, 40),
				Size = UDim2.new(1, -24, 0, 60),
				Text = rollStartedAt and "The chamber is still running."
					or "Your next roll lands here. Nothing is yours until you collect it.",
				TextColor3 = Hud.COLOR.Muted,
				TextSize = 12,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = card,
			})
		else
			local recipe = CraftingRecipes.Weapons[pending.WeaponKey]

			local badge = Hud.new("Frame", {
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = rarityColor(pending.Rarity),
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(10, 10),
				Size = UDim2.fromOffset(0, 16),
				Parent = card,
			}, { Hud.corner(3) })

			Hud.new("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				Font = Hud.FONT.Display,
				Size = UDim2.fromOffset(0, 16),
				Text = (" %s "):format(rarityName(pending.Rarity):upper()),
				-- Panel, not Text: the badge is a filled chip in a bright rarity colour, so its label
				-- has to be the DARK one to stay legible on Legendary gold.
				TextColor3 = Hud.COLOR.Panel,
				TextSize = 10,
				Parent = badge,
			})

			Hud.new("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Font = Hud.FONT.Mono,
				Position = UDim2.new(1, -10, 0, 11),
				Size = UDim2.fromOffset(40, 14),
				Text = recipe and ("t%d"):format(recipe.Tier) or "",
				TextColor3 = Hud.COLOR.Muted,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = card,
			})

			Hud.new("TextLabel", {
				BackgroundTransparency = 1,
				Font = Hud.FONT.Display,
				Position = UDim2.fromOffset(10, 34),
				Size = UDim2.new(1, -20, 0, 18),
				Text = recipe and recipe.DisplayName or pending.WeaponKey,
				TextColor3 = Hud.COLOR.Text,
				TextSize = 13,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = card,
			})

			Hud.new("Frame", {
				BackgroundColor3 = Hud.COLOR.Line,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(10, 58),
				Size = UDim2.fromOffset(RIGHT_WIDTH - 20, 1),
				Parent = card,
			})

			local affixes = pending.Affixes or {}
			if #affixes == 0 then
				-- Every Common rolls none by design (ForgeConfig.AffixCountByRarity), so this is a
				-- normal outcome, not a failure — say so rather than leaving the card half empty.
				Hud.new("TextLabel", {
					BackgroundTransparency = 1,
					Font = Hud.FONT.Body,
					Position = UDim2.fromOffset(10, 68),
					Size = UDim2.new(1, -20, 0, 34),
					Text = "No bonus affixes — base stats only.",
					TextColor3 = Hud.COLOR.Muted,
					TextSize = 12,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					Parent = card,
				})
			end

			for index, affix in ipairs(affixes) do
				local y = 68 + (index - 1) * 20
				Hud.new("TextLabel", {
					BackgroundTransparency = 1,
					Font = Hud.FONT.Body,
					Position = UDim2.fromOffset(10, y),
					Size = UDim2.fromOffset(RIGHT_WIDTH - 96, 18),
					Text = affix.Label,
					TextColor3 = Hud.COLOR.Accent,
					TextSize = 12,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = card,
				})

				Hud.new("TextLabel", {
					AnchorPoint = Vector2.new(1, 0),
					BackgroundTransparency = 1,
					Font = Hud.FONT.Mono,
					Position = UDim2.new(1, -10, 0, y),
					Size = UDim2.fromOffset(80, 18),
					Text = affixValue(affix),
					TextColor3 = Hud.COLOR.Text,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Right,
					Parent = card,
				})
			end
		end

		------------------------------------------------------------------
		-- Collect / Trash
		------------------------------------------------------------------
		-- Side by side, per DESIGN_NOTES — the mockup drew only Collect, but the tray exists so a
		-- roll can be REFUSED, and refusing needs a control. Both are dead-but-present when the tray
		-- is empty rather than hidden: a pair of buttons that appear and vanish under the cursor is
		-- worse than two that are visibly waiting for something to act on.
		local actionWidth = (RIGHT_WIDTH - Hud.SPACE.M) / 2

		Hud.button({
			variant = pending and "primary" or "secondary",
			text = "Collect",
			position = UDim2.fromOffset(0, TRAY_ACTION_Y),
			size = UDim2.fromOffset(actionWidth, TRAY_ACTION_HEIGHT),
			parent = column,
			onClick = function()
				local result = Remotes.CollectForgeOutput:InvokeServer()
				if not result.Success then
					Hud.showFailure("Collect failed", result.Reason)
				else
					local recipe = CraftingRecipes.Weapons[result.Weapon.WeaponKey]
					Hud.showToast(("Collected the %s %s."):format(
						rarityName(result.Weapon.Rarity),
						recipe and recipe.DisplayName or result.Weapon.WeaponKey), 3)
					refresh()
				end
			end,
		})

		Hud.button({
			variant = pending and "danger" or "secondary",
			text = "Trash",
			position = UDim2.fromOffset(actionWidth + Hud.SPACE.M, TRAY_ACTION_Y),
			size = UDim2.fromOffset(actionWidth, TRAY_ACTION_HEIGHT),
			parent = column,
			onClick = function()
				if not pending then
					Hud.showFailure("Nothing to trash", "The tray is empty.")
					return
				end
				local result = Remotes.TrashForgeOutput:InvokeServer()
				if not result.Success then
					Hud.showFailure("Trash failed", result.Reason)
				else
					refresh()
				end
			end,
		})
	end

	------------------------------------------------------------------
	-- The roll itself
	------------------------------------------------------------------

	local function doRoll(confirmDiscard: boolean?)
		local weaponKey = selectedWeapon
		if not weaponKey then
			Hud.showFailure("Nothing selected", "Pick a weapon in the input bay first.")
			return
		end

		-- Only claims a potion when one is actually owned: the toggle is client state and the count
		-- can have changed under it (spent on a previous roll, or the profile reloaded).
		local burnPotion = usePotion and (Hud.profile.LuckPotions or 0) > 0
		local result = Remotes.ForgeWeapon:InvokeServer(weaponKey, burnPotion, confirmDiscard)

		if result.Success then
			usePotion = false -- one-shot, whether or not a potion actually got spent
			rollStartedAt = os.clock()
			refresh()
			return
		end

		-- The one rejection that is a QUESTION rather than a refusal. Everything else toasts.
		if result.NeedsDiscardConfirm and result.Pending then
			local pendingRecipe = CraftingRecipes.Weapons[result.Pending.WeaponKey]
			Hud.modal({
				kind = "danger",
				capColor = rarityColor(result.Pending.Rarity),
				title = "DISCARD THIS ROLL?",
				body = ("The tray is holding a %s %s. Rolling again overwrites it, and there is no refund.")
					:format(
						rarityName(result.Pending.Rarity),
						pendingRecipe and pendingRecipe.DisplayName or result.Pending.WeaponKey),
				actions = {
					{ text = "Keep it" },
					{
						text = "Roll anyway",
						variant = "danger",
						onClick = function()
							doRoll(true)
						end,
					},
				},
			})
			return
		end

		Hud.showFailure("Forge failed", result.Reason)
	end

	------------------------------------------------------------------
	-- Render
	------------------------------------------------------------------

	local function render()
		resolveSelection()
		refreshReadout()

		local body = Hud.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, BODY_HEIGHT),
			Parent = listFrame,
		})

		drawInputBay(body)
		drawChamber(body)
		drawTray(body)

		-- The lever, pinned to the bottom of the tray column. Deliberately the largest control on
		-- the screen: everything else here exists to inform this one press.
		local recipe = selectedWeapon and CraftingRecipes.Weapons[selectedWeapon]
		local affordable = recipe and Wallet.CanAfford(Hud.profile, recipe.Cost)

		Hud.button({
			variant = (affordable and not rollStartedAt) and "primary" or "secondary",
			text = rollStartedAt and "Rolling…" or "Forge",
			anchorPoint = Vector2.new(1, 1),
			position = UDim2.new(0, RIGHT_X + RIGHT_WIDTH, 0, BODY_HEIGHT),
			size = UDim2.fromOffset(RIGHT_WIDTH, FORGE_BUTTON_HEIGHT),
			parent = body,
			onClick = function()
				-- Deliberately NOT gated client-side on affordability: ForgeWeapon re-checks the cost
				-- and names the material you are short of, which is more use than a dead button.
				if rollStartedAt then
					return
				end
				doRoll(false)
			end,
		})

		Hud.new("TextLabel", {
			AnchorPoint = Vector2.new(1, 1),
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.fromOffset(RIGHT_X + RIGHT_WIDTH, BODY_HEIGHT - FORGE_BUTTON_HEIGHT - 4),
			Size = UDim2.fromOffset(RIGHT_WIDTH, 14),
			Text = usePotion and "burns 1 potion" or "",
			TextColor3 = Hud.COLOR.Good,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = body,
		})
	end

	return {
		render = render,
		-- Called by renderCraftList before it renders a tab this panel does not own: the readout
		-- lives in the shared panel header, which that sweep does not clear.
		hideReadout = function()
			readout.Visible = false
		end,
	}
end

return ForgePanel
