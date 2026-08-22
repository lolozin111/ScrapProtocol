--[[
	MainHud.client.lua
	A plain-code debug HUD — currency readout, a craft menu (Weapons/Robots tabs), and a
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

local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)
local OreConfig = require(ReplicatedStorage.Shared.OreConfig)
local NodeConfig = require(ReplicatedStorage.Shared.NodeConfig)
local AutoMinerConfig = require(ReplicatedStorage.Shared.AutoMinerConfig)
local RaidEnergyConfig = require(ReplicatedStorage.Shared.RaidEnergyConfig)
local MineShaftConfig = require(ReplicatedStorage.Shared.MineShaftConfig)
local ModConfig = require(ReplicatedStorage.Shared.ModConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LocalPlayer = Players.LocalPlayer

-- Palette: same rust/gunmetal family as the design doc, translated to Color3.
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

local profile = {
	Scrap = 0, Cores = 0,
	OreCounts = {}, CraftedWeapons = {}, CraftedRobots = {}, DeployedRobots = {},
	CraftedStructures = {}, OwnedGamePasses = {},
	CraftedMods = {}, EquippedMods = {},
	HighestWave = 0,
	Energy = RaidEnergyConfig.MaxEnergy,
	SuitTier = 1,
}
local runActive = false

----------------------------------------------------------------------
-- Small UI helpers
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

local function stroke()
	return new("UIStroke", { Color = COLOR.Line, Thickness = 1 })
end

----------------------------------------------------------------------
-- Screen setup
----------------------------------------------------------------------

local screenGui = new("ScreenGui", {
	Name = "SalvageHUD",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = LocalPlayer:WaitForChild("PlayerGui"),
})

----------------------------------------------------------------------
-- Currency readout (top-left)
----------------------------------------------------------------------

local currencyFrame = new("Frame", {
	Name = "Currency",
	BackgroundColor3 = COLOR.Panel,
	Position = UDim2.new(0, 16, 0, 16),
	Size = UDim2.new(0, 220, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Parent = screenGui,
}, {
	corner(8),
	stroke(),
	new("UIListLayout", { Padding = UDim.new(0, 2) }),
	new("UIPadding", {
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
	}),
})

local function makeStatLabel(color)
	return new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		TextSize = 15,
		Text = "",
		Parent = currencyFrame,
	})
end

local scrapLabel = makeStatLabel(COLOR.Accent)
local coresLabel = makeStatLabel(COLOR.Good)
local energyLabel = makeStatLabel(COLOR.Good)

new("Frame", { -- thin divider between currency and ore inventory
	BackgroundColor3 = COLOR.Line,
	Size = UDim2.new(1, 0, 0, 1),
	Parent = currencyFrame,
})

-- One label per MVP-mineable ore, in the same order as the design doc's tier table.
local ORE_DISPLAY_ORDER = { "ScrapIron", "CopperWire", "SteelPlating", "GoldContacts" }
local oreLabels = {}
for _, oreKey in ipairs(ORE_DISPLAY_ORDER) do
	oreLabels[oreKey] = makeStatLabel(COLOR.Muted)
end

local function refreshCurrency()
	scrapLabel.Text = ("Scrap: %d"):format(profile.Scrap or 0)
	coresLabel.Text = ("Cores: %d"):format(profile.Cores or 0)
	-- Energy can briefly read above MaxEnergy right after an Energy Drink (see
	-- RaidEnergyConfig.OverflowCap) — that's intentional, not a bug, it just drains back down to
	-- the normal cap as raids are spent rather than being topped up further by passive regen.
	energyLabel.Text = ("Energy: %d/%d"):format(profile.Energy or 0, RaidEnergyConfig.MaxEnergy)
	for _, oreKey in ipairs(ORE_DISPLAY_ORDER) do
		local displayName = OreConfig.Ores[oreKey].DisplayName
		local count = (profile.OreCounts or {})[oreKey] or 0
		oreLabels[oreKey].Text = ("%s: %d"):format(displayName, count)
	end
end

----------------------------------------------------------------------
-- Craft menu (center, toggled)
----------------------------------------------------------------------

local craftFrame = new("Frame", {
	Name = "CraftMenu",
	BackgroundColor3 = COLOR.Panel,
	Position = UDim2.new(0.5, -320, 0.5, -200),
	Size = UDim2.new(0, 640, 0, 400), -- widened/heightened to fit 6 tabs (added Mods) and the
	                                  -- taller equipment rows mod slots need
	Visible = false,
	Parent = screenGui,
}, { corner(10), stroke() })

local tabRow = new("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 12),
	Size = UDim2.new(1, -24, 0, 32),
	Parent = craftFrame,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }) })

local listFrame = new("ScrollingFrame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 52),
	Size = UDim2.new(1, -24, 1, -64),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	Parent = craftFrame,
}, { new("UIListLayout", { Padding = UDim.new(0, 6) }) })

local function costString(cost)
	local parts = {}
	for key, amount in pairs(cost) do
		local displayName
		if key == "Scrap" or key == "Cores" then
			displayName = key
		else
			displayName = (OreConfig.Ores[key] and OreConfig.Ores[key].DisplayName) or key
		end
		table.insert(parts, ("%d %s"):format(amount, displayName))
	end
	return table.concat(parts, ", ")
end

local function makeRow(displayName, subtitle, buttonText, onClick)
	local row = new("Frame", {
		BackgroundColor3 = COLOR.PanelLight,
		Size = UDim2.new(1, 0, 0, 52),
	}, { corner(6) })

	new("TextLabel", {
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

	new("TextLabel", {
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

	local button = new("TextButton", {
		BackgroundColor3 = COLOR.Accent,
		Position = UDim2.new(1, -96, 0.5, -16),
		Size = UDim2.new(0, 86, 0, 32),
		Font = Enum.Font.SourceSansBold,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 14,
		Text = buttonText,
		Parent = row,
	}, { corner(6) })
	button.MouseButton1Click:Connect(onClick)

	return row
end

local currentTab = "Weapons"

-- Tool tier isn't a recipe table either — it's one sequential upgrade track — so it gets its
-- own row-builder too. This is the ONLY way ToolTier (and therefore access to Steel Plating and
-- above, see OreConfig.Ores[key].MinToolTier) ever goes up.
local function renderToolRow()
	local currentTier = profile.ToolTier or 1
	local currentToolData = OreConfig.ToolTiers[currentTier]
	local nextTier = currentTier + 1
	local nextToolData = OreConfig.ToolTiers[nextTier]

	if not nextToolData then
		makeRow(
			currentToolData and currentToolData.Name or "Tool",
			"Max tier reached",
			"Maxed",
			function() end
		).Parent = listFrame
		return
	end

	local cost = OreConfig.ToolTierCosts[nextTier]
	makeRow(
		("%s -> %s"):format(currentToolData and currentToolData.Name or "?", nextToolData.Name),
		cost and costString(cost) or "Not configured",
		"Upgrade",
		function()
			local result = Remotes.UpgradeTool:InvokeServer()
			if not result.Success then
				warn("[HUD] Upgrade failed:", result.Reason)
			end
		end
	).Parent = listFrame
end

-- Auto-Miner isn't a recipe table like Weapons/Robots — it's a single fixed structure — so it
-- gets its own row-builder instead of going through the generic recipes loop below.
local function renderAutoMinerRow()
	local owned = profile.CraftedStructures and profile.CraftedStructures.AutoMiner
	local hasPass = profile.OwnedGamePasses and profile.OwnedGamePasses.AutoMiner
	local rate = AutoMinerConfig.BaseYieldPerTick * (hasPass and AutoMinerConfig.GamePassMultiplier or 1)
	local oreDisplayName = (OreConfig.Ores[AutoMinerConfig.OreKey] and OreConfig.Ores[AutoMinerConfig.OreKey].DisplayName)
		or AutoMinerConfig.OreKey

	local subtitle
	if owned then
		subtitle = ("Built · +%d %s every %ds%s"):format(
			rate, oreDisplayName, AutoMinerConfig.TickSeconds, hasPass and " (pass applied)" or "")
	else
		subtitle = costString(AutoMinerConfig.Cost)
	end

	makeRow(
		"Mini Particle Accelerator",
		subtitle,
		owned and "Built" or "Build",
		function()
			if owned then return end
			local result = Remotes.CraftAutoMiner:InvokeServer()
			if not result.Success then
				warn("[HUD] Build failed:", result.Reason)
			end
		end
	).Parent = listFrame
end

-- Suit tier is the mine shaft's version of ToolTier — same sequential-upgrade-track shape as
-- renderToolRow above, just backed by MineShaftConfig.SuitTiers/SuitTierCosts and the UpgradeSuit
-- remote instead. Each tier knocks Heat/Toxic Air damage down by however many Tiers its
-- Protection table specifies (see MineShaftConfig.HazardTypes) rather than fully blocking a
-- hazard outright.
local function renderSuitRow()
	local currentTier = profile.SuitTier or 1
	local currentSuitData = MineShaftConfig.SuitTiers[currentTier]
	local nextTier = currentTier + 1
	local nextSuitData = MineShaftConfig.SuitTiers[nextTier]

	if not nextSuitData then
		makeRow(
			currentSuitData and currentSuitData.Name or "Suit",
			"Max tier reached — protects against everything the mine shaft throws at you",
			"Maxed",
			function() end
		).Parent = listFrame
		return
	end

	local cost = MineShaftConfig.SuitTierCosts[nextTier]
	makeRow(
		("%s -> %s"):format(currentSuitData and currentSuitData.Name or "?", nextSuitData.Name),
		("Protects: %s · %s"):format(nextSuitData.ProtectsAgainst, cost and costString(cost) or "Not configured"),
		"Upgrade",
		function()
			local result = Remotes.UpgradeSuit:InvokeServer()
			if not result.Success then
				warn("[HUD] Suit upgrade failed:", result.Reason)
			end
		end
	).Parent = listFrame
end

----------------------------------------------------------------------
-- Mods tab + per-item mod slots — see ModConfig.lua's header comment for the design
-- (3 slots per weapon/robot TYPE, applied multiplicatively via CombatMath.GetEffectiveStats).
----------------------------------------------------------------------

local MOD_SLOT_WIDTH = 96

local function renderModsRow()
	local keys = {}
	for key in pairs(ModConfig.Mods) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return ModConfig.Mods[a].DisplayName < ModConfig.Mods[b].DisplayName
	end)

	for _, key in ipairs(keys) do
		local mod = ModConfig.Mods[key]
		local owned = profile.CraftedMods and profile.CraftedMods[key]
		makeRow(
			mod.DisplayName,
			owned and mod.Description or ("%s · %s"):format(mod.Description, costString(mod.Cost)),
			owned and "Owned" or "Craft",
			function()
				if owned then return end
				local result = Remotes.CraftItem:InvokeServer("Mods", key)
				if not result.Success then
					warn("[HUD] Craft failed:", result.Reason)
				end
			end
		).Parent = listFrame
	end
end

local function equippedModKeyForSlot(itemKey: string, slotIndex: number)
	local equipped = profile.EquippedMods and profile.EquippedMods[itemKey]
	return equipped and equipped[slotIndex]
end

-- Sorted so the picker list reads consistently instead of hash-order.
local function ownedModKeysSorted()
	local keys = {}
	for key, owned in pairs(profile.CraftedMods or {}) do
		if owned then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a, b)
		return ModConfig.Mods[a].DisplayName < ModConfig.Mods[b].DisplayName
	end)
	return keys
end

----------------------------------------------------------------------
-- Mod picker popup — clicking a mod slot button on an owned weapon/robot's equipment row opens
-- this listing every mod the player currently owns (plus a "None" option to clear the slot).
-- Clicking an entry equips it and closes the popup.
----------------------------------------------------------------------

local modPickerFrame = new("Frame", {
	Name = "ModPicker",
	BackgroundColor3 = COLOR.Panel,
	Position = UDim2.new(0.5, -170, 0.5, -180),
	Size = UDim2.new(0, 340, 0, 360),
	Visible = false,
	ZIndex = 5,
	Parent = screenGui,
}, { corner(10), stroke() })

new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 10),
	Size = UDim2.new(1, -60, 0, 24),
	Font = Enum.Font.SourceSansBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = COLOR.Text,
	TextSize = 18,
	Text = "Choose a Mod",
	Parent = modPickerFrame,
})

local modPickerClose = new("TextButton", {
	BackgroundColor3 = COLOR.PanelLight,
	Position = UDim2.new(1, -40, 0, 8),
	Size = UDim2.new(0, 28, 0, 28),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = COLOR.Text,
	TextSize = 16,
	Text = "X",
	Parent = modPickerFrame,
}, { corner(6) })

local modPickerList = new("ScrollingFrame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 44),
	Size = UDim2.new(1, -24, 1, -56),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	Parent = modPickerFrame,
}, { new("UIListLayout", { Padding = UDim.new(0, 6) }) })

-- Which slot the popup is currently open for — cleared whenever it closes.
local modPickerState = { tree = nil, itemKey = nil, slotIndex = nil }

local function closeModPicker()
	modPickerFrame.Visible = false
	modPickerState.tree = nil
	modPickerState.itemKey = nil
	modPickerState.slotIndex = nil
end
modPickerClose.MouseButton1Click:Connect(closeModPicker)

-- No manual craft-list re-render here — EquipMod's server handler fires InventoryUpdate with the
-- new EquippedMods table, and that listener already re-renders the craft list while it's open
-- (the same pattern the Craft/Deploy buttons elsewhere in this file rely on).
local function selectMod(modKey: string?)
	local tree, itemKey, slotIndex = modPickerState.tree, modPickerState.itemKey, modPickerState.slotIndex
	closeModPicker() -- close first so a slow round trip doesn't leave a stale popup hanging open
	local result = Remotes.EquipMod:InvokeServer(tree, itemKey, slotIndex, modKey)
	if not result.Success then
		warn("[HUD] Equip mod failed:", result.Reason)
	end
end

local function renderModPickerList()
	for _, child in ipairs(modPickerList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local currentModKey = equippedModKeyForSlot(modPickerState.itemKey, modPickerState.slotIndex)

	makeRow(
		"None",
		"Clear this slot",
		(currentModKey == nil) and "Selected" or "Select",
		function()
			selectMod(nil)
		end
	).Parent = modPickerList

	for _, modKey in ipairs(ownedModKeysSorted()) do
		local mod = ModConfig.Mods[modKey]
		local rarityData = ModConfig.Rarities[mod.Rarity]
		local rarityName = rarityData and rarityData.DisplayName or mod.Rarity
		makeRow(
			("[%s] %s"):format(rarityName, mod.DisplayName),
			mod.Description,
			(modKey == currentModKey) and "Selected" or "Select",
			function()
				selectMod(modKey)
			end
		).Parent = modPickerList
	end
end

local function openModPicker(tree: string, itemKey: string, slotIndex: number)
	modPickerState.tree = tree
	modPickerState.itemKey = itemKey
	modPickerState.slotIndex = slotIndex
	renderModPickerList()
	modPickerFrame.Visible = true
end

-- Taller than makeRow's fixed 52px — same title/subtitle/button layout up top, plus a row of
-- ModConfig.SlotsPerItem slot buttons underneath for owned weapons/robots. Clicking a slot opens
-- the mod picker popup (see openModPicker above) instead of cycling in place.
local function makeEquipmentRow(tree: string, itemKey: string, titleText: string, statsText: string, buttonText: string, onClick)
	local row = new("Frame", {
		BackgroundColor3 = COLOR.PanelLight,
		Size = UDim2.new(1, 0, 0, 90),
	}, { corner(6) })

	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 4),
		Size = UDim2.new(1, -110, 0, 20),
		Font = Enum.Font.SourceSansBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR.Text,
		TextSize = 16,
		Text = titleText,
		Parent = row,
	})

	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 24),
		Size = UDim2.new(1, -110, 0, 20),
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR.Muted,
		TextSize = 13,
		Text = statsText,
		Parent = row,
	})

	local button = new("TextButton", {
		BackgroundColor3 = COLOR.Accent,
		Position = UDim2.new(1, -96, 0, 4),
		Size = UDim2.new(0, 86, 0, 32),
		Font = Enum.Font.SourceSansBold,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 14,
		Text = buttonText,
		Parent = row,
	}, { corner(6) })
	button.MouseButton1Click:Connect(onClick)

	local slotRow = new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 50),
		Size = UDim2.new(1, -20, 0, 32),
		Parent = row,
	}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })

	for slotIndex = 1, ModConfig.SlotsPerItem do
		local equippedKey = equippedModKeyForSlot(itemKey, slotIndex)
		local mod = equippedKey and ModConfig.Mods[equippedKey]
		local slotButton = new("TextButton", {
			BackgroundColor3 = mod and COLOR.AccentDark or COLOR.Panel,
			Size = UDim2.new(0, MOD_SLOT_WIDTH, 1, 0),
			Font = Enum.Font.Code,
			TextColor3 = COLOR.Text,
			TextSize = 12,
			TextWrapped = true,
			Text = mod and mod.DisplayName or ("Slot %d: Empty"):format(slotIndex),
			Parent = slotRow,
		}, { corner(4), stroke() })
		slotButton.MouseButton1Click:Connect(function()
			openModPicker(tree, itemKey, slotIndex)
		end)
	end

	return row
end

local function renderCraftList()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	if currentTab == "Auto-Miner" then
		renderAutoMinerRow()
		return
	elseif currentTab == "Tools" then
		renderToolRow()
		return
	elseif currentTab == "Suit" then
		renderSuitRow()
		return
	elseif currentTab == "Mods" then
		renderModsRow()
		return
	end

	local recipes = currentTab == "Weapons" and CraftingRecipes.Weapons or CraftingRecipes.Robots

	-- Sort by tier so the list reads as a progression, not a random bag.
	local keys = {}
	for key in pairs(recipes) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return recipes[a].Tier < recipes[b].Tier
	end)

	for _, key in ipairs(keys) do
		local recipe = recipes[key]
		if currentTab == "Weapons" then
			local owned = profile.CraftedWeapons[key]
			if owned then
				makeEquipmentRow(
					"Weapons", key,
					("T%d  %s (Owned)"):format(recipe.Tier, recipe.DisplayName),
					("Base: %.1f dmg x %.1f/s"):format(recipe.BaseDamage, recipe.FireRate),
					"Owned",
					function() end
				).Parent = listFrame
			else
				makeRow(
					("T%d  %s"):format(recipe.Tier, recipe.DisplayName),
					costString(recipe.Cost),
					"Craft",
					function()
						local result = Remotes.CraftItem:InvokeServer("Weapons", key)
						if not result.Success then
							warn("[HUD] Craft failed:", result.Reason)
						end
					end
				).Parent = listFrame
			end
		else
			local ownedCount = profile.CraftedRobots[key] or 0
			if ownedCount > 0 then
				makeEquipmentRow(
					"Robots", key,
					("T%d  %s (owned %d)"):format(recipe.Tier, recipe.DisplayName, ownedCount),
					("Base: %.1f dmg x %.1f/s · %d HP"):format(recipe.BaseDamage, recipe.FireRate, recipe.HP),
					"Deploy",
					function()
						local result = Remotes.DeployRobot:InvokeServer(key)
						if not result.Success then
							warn("[HUD] Deploy failed:", result.Reason)
						end
					end
				).Parent = listFrame
			else
				makeRow(
					("T%d  %s"):format(recipe.Tier, recipe.DisplayName),
					costString(recipe.Cost),
					"Craft",
					function()
						local result = Remotes.CraftItem:InvokeServer("Robots", key)
						if not result.Success then
							warn("[HUD] Craft failed:", result.Reason)
						end
					end
				).Parent = listFrame
			end
		end
	end
end

-- Shared by the tab buttons below and by the base stations further down (clicking a Workbench/
-- Welding Station in the world jumps straight to that station's tab via the same path).
local function selectTab(name: string)
	currentTab = name
	for _, sibling in ipairs(tabRow:GetChildren()) do
		if sibling:IsA("TextButton") then
			sibling.BackgroundColor3 = sibling.Text == name and COLOR.Accent or COLOR.PanelLight
		end
	end
	renderCraftList()
end

local function makeTabButton(name)
	local button = new("TextButton", {
		BackgroundColor3 = currentTab == name and COLOR.Accent or COLOR.PanelLight,
		Size = UDim2.new(0, 90, 1, 0), -- shrunk from 100 to fit 6 tabs (added Mods) in the same row width
		Font = Enum.Font.SourceSansBold,
		TextColor3 = COLOR.Text,
		TextSize = 15,
		Text = name,
		Parent = tabRow,
	}, { corner(6) })
	button.MouseButton1Click:Connect(function()
		selectTab(name)
	end)
	return button
end

makeTabButton("Weapons")
makeTabButton("Robots")
makeTabButton("Mods")
makeTabButton("Tools")
makeTabButton("Auto-Miner")
makeTabButton("Suit")

----------------------------------------------------------------------
-- Wave panel (bottom-center)
----------------------------------------------------------------------

local wavePanel = new("Frame", {
	Name = "WavePanel",
	BackgroundColor3 = COLOR.Panel,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -90),
	Size = UDim2.new(0, 360, 0, 118),
	Visible = false,
	Parent = screenGui,
}, { corner(8), stroke() })

local waveLabel = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 8),
	Size = UDim2.new(1, -24, 0, 18),
	Font = Enum.Font.SourceSansBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = COLOR.Text,
	TextSize = 15,
	Text = "Wave —",
	Parent = wavePanel,
})

-- Each bar gets its own numeric readout above it — a thin color bar alone was too easy
-- to mistake for "nothing is happening" when it's actually just low-contrast.
local function makeBar(yOffset, fillColor, initialText)
	local caption = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, yOffset),
		Size = UDim2.new(1, -24, 0, 16),
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR.Muted,
		TextSize = 13,
		Text = initialText,
		Parent = wavePanel,
	})
	local track = new("Frame", {
		BackgroundColor3 = COLOR.PanelLight,
		Position = UDim2.new(0, 12, 0, yOffset + 18),
		Size = UDim2.new(1, -24, 0, 12),
		Parent = wavePanel,
	}, { corner(4) })
	local fill = new("Frame", {
		BackgroundColor3 = fillColor,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = track,
	}, { corner(4) })
	return caption, fill
end

local objCaption, objFill = makeBar(30, COLOR.Good, "Objective: — / —")
local enemyCaption, enemyFill = makeBar(72, COLOR.Bad, "Enemies: —")

----------------------------------------------------------------------
-- Raid panel (bottom-right) — separate from the base-defense panel above since
-- you could, in principle, have just returned from one and be about to start the other.
----------------------------------------------------------------------

local raidPanel = new("Frame", {
	Name = "RaidPanel",
	BackgroundColor3 = COLOR.Panel,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.new(0, 300, 0, 130),
	Visible = false,
	Parent = screenGui,
}, { corner(8), stroke() })

local raidLabel = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 8),
	Size = UDim2.new(1, -24, 0, 18),
	Font = Enum.Font.SourceSansBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = COLOR.Text,
	TextSize = 15,
	Text = "Outpost —",
	Parent = raidPanel,
})

local function makeRaidBar(yOffset, fillColor, initialText)
	local caption = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, yOffset),
		Size = UDim2.new(1, -24, 0, 16),
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR.Muted,
		TextSize = 13,
		Text = initialText,
		Parent = raidPanel,
	})
	local track = new("Frame", {
		BackgroundColor3 = COLOR.PanelLight,
		Position = UDim2.new(0, 12, 0, yOffset + 18),
		Size = UDim2.new(1, -24, 0, 12),
		Parent = raidPanel,
	}, { corner(4) })
	local fill = new("Frame", {
		BackgroundColor3 = fillColor,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = track,
	}, { corner(4) })
	return caption, fill
end

local raidEnemyCaption, raidEnemyFill = makeRaidBar(30, COLOR.Bad, "Enemies: —")
local raidHealthCaption, raidHealthFill = makeRaidBar(72, COLOR.Good, "Your HP: —")

----------------------------------------------------------------------
-- Mine shaft depth panel (top-right) — only visible while MineShaftService's hazard loop reports
-- the player is actually standing above a live shaft block (see DepthUpdate below). Shows current
-- depth plus whichever hazard band applies there, colored red if the player's Suit doesn't cover
-- it yet (matching MineShaftService's own worst-band-only logic, computed here too so the HUD
-- doesn't have to wait on a server round trip beyond the DepthUpdate that already fired).
----------------------------------------------------------------------

local depthPanel = new("Frame", {
	Name = "DepthPanel",
	BackgroundColor3 = COLOR.Panel,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 16),
	Size = UDim2.new(0, 230, 0, 70), -- tall enough for Depth + 2 independent hazard lines (Heat, Toxic Air)
	Visible = false,
	Parent = screenGui,
}, { corner(8), stroke() })

local depthLabel = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 6),
	Size = UDim2.new(1, -24, 0, 18),
	Font = Enum.Font.SourceSansBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = COLOR.Text,
	TextSize = 15,
	Text = "Depth —",
	Parent = depthPanel,
})

-- Heat and Toxic Air are now independent hazards that can both apply at once (see
-- MineShaftConfig.HazardTypes) rather than only the single "worst" one showing — so this panel
-- gets one line per hazard type instead of one combined line.
local hazardLabel = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 27),
	Size = UDim2.new(1, -24, 0, 18),
	Font = Enum.Font.Code,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = COLOR.Muted,
	TextSize = 13,
	Text = "",
	Parent = depthPanel,
})

local hazardLabel2 = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 46),
	Size = UDim2.new(1, -24, 0, 18),
	Font = Enum.Font.Code,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = COLOR.Muted,
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
		return ("%s T%d — protected"):format(hazardType.Name, tier), COLOR.Good
	end

	local damage = hazardType.Tiers[effectiveTier].BaseDamage
	return ("%s T%d — %d dmg/tick"):format(hazardType.Name, tier, damage), COLOR.Bad
end

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
	raidHealthFill.Size = UDim2.new(pct, 0, 1, 0)
	raidHealthCaption.Text = ("Your HP: %d / %d"):format(math.ceil(humanoid.Health), math.ceil(playerMaxHealth))
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
-- Shop panel (opened only by standing at a Shop node — see node setup below)
----------------------------------------------------------------------

local shopFrame = new("Frame", {
	Name = "ShopMenu",
	BackgroundColor3 = COLOR.Panel,
	Position = UDim2.new(0.5, -200, 0.5, -190),
	Size = UDim2.new(0, 400, 0, 388),
	Visible = false,
	Parent = screenGui,
}, { corner(10), stroke() })

new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 10),
	Size = UDim2.new(1, -60, 0, 24),
	Font = Enum.Font.SourceSansBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = COLOR.Text,
	TextSize = 18,
	Text = "Outpost Shop",
	Parent = shopFrame,
})

local shopCloseButton = new("TextButton", {
	BackgroundColor3 = COLOR.PanelLight,
	Position = UDim2.new(1, -40, 0, 8),
	Size = UDim2.new(0, 28, 0, 28),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = COLOR.Text,
	TextSize = 16,
	Text = "X",
	Parent = shopFrame,
}, { corner(6) })
shopCloseButton.MouseButton1Click:Connect(function()
	shopFrame.Visible = false
end)

local shopListFrame = new("ScrollingFrame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 44),
	Size = UDim2.new(1, -24, 1, -100),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	Parent = shopFrame,
}, { new("UIListLayout", { Padding = UDim.new(0, 6) }) })

-- Expedition Shop nodes are one-time — if you can't (or don't want to) buy anything, Skip
-- destroys the node outright and lets the queue move on rather than leaving you stuck standing
-- in front of a shop you can't use.
local shopSkipButton = new("TextButton", {
	BackgroundColor3 = COLOR.PanelLight,
	Position = UDim2.new(0, 12, 1, -40),
	Size = UDim2.new(1, -24, 0, 32),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = COLOR.Text,
	TextSize = 15,
	Text = "Skip — move to the next node",
	Parent = shopFrame,
}, { corner(6) })

local currentShopNode = nil -- set right before the Shop panel opens, see node setup below
local shopNodeDestroyingConn = nil -- auto-closes the panel if the node vanishes out from under it (bought, skipped, or otherwise)

local function renderShopList()
	for _, child in ipairs(shopListFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for itemKey, item in pairs(NodeConfig.ShopCatalog) do
		makeRow(
			item.DisplayName,
			("%d %s"):format(item.CostAmount, item.CostCurrency),
			"Buy",
			function()
				local result = Remotes.BuyOutpostItem:InvokeServer(currentShopNode, itemKey)
				if not result.Success then
					warn("[HUD] Purchase failed:", result.Reason)
				else
					shopFrame.Visible = false -- expedition shop nodes are consumed on purchase — nothing left to browse
				end
			end
		).Parent = shopListFrame
	end
end

shopSkipButton.MouseButton1Click:Connect(function()
	if currentShopNode then
		Remotes.SkipNode:FireServer(currentShopNode)
	end
	shopFrame.Visible = false
end)

----------------------------------------------------------------------
-- Bottom action buttons
----------------------------------------------------------------------

local actionRow = new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.new(0, 570, 0, 44), -- widened from 450 to also fit the Recall button
	Parent = screenGui,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center }) })

local craftToggleButton = new("TextButton", {
	BackgroundColor3 = COLOR.PanelLight,
	Size = UDim2.new(0, 140, 1, 0),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = COLOR.Text,
	TextSize = 16,
	Text = "Workbench",
	Parent = actionRow,
}, { corner(8), stroke() })
craftToggleButton.MouseButton1Click:Connect(function()
	craftFrame.Visible = not craftFrame.Visible
	if craftFrame.Visible then
		renderCraftList()
	else
		closeModPicker() -- don't leave the mod picker orphaned open behind a closed Workbench
	end
end)

local defendButton = new("TextButton", {
	BackgroundColor3 = COLOR.Accent,
	Size = UDim2.new(0, 140, 1, 0),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 16,
	Text = "Start Defense",
	Parent = actionRow,
}, { corner(8) })
defendButton.MouseButton1Click:Connect(function()
	if runActive then return end
	Remotes.StartWave:FireServer()
end)

-- Only shown while an expedition is actually active (see the CurrentSlotId watcher below) —
-- ends the run for everyone on the shared queue, heals you to full, and keeps whatever you've
-- already looted (rewards are granted the instant each node resolves, not saved up for an
-- "end of run" payout, so there's nothing separate to preserve here).
local returnHomeButton = new("TextButton", {
	BackgroundColor3 = COLOR.Bad,
	Size = UDim2.new(0, 130, 1, 0),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 15,
	Text = "Return to Base",
	Visible = false,
	Parent = actionRow,
}, { corner(8) })
returnHomeButton.MouseButton1Click:Connect(function()
	Remotes.EndExpedition:FireServer()
end)

-- Only shown while DepthUpdate (fired from MineShaftService's hazard loop) reports the player is
-- at least one level down in the quarry — there's no climb-out mechanic, so once you're a few
-- levels down this is the only way back short of finding a wall to walk into. Respawns at a
-- normal SpawnLocation, full health, same as Return to Base — see RecallFromMine's comment.
local recallButton = new("TextButton", {
	BackgroundColor3 = COLOR.Bad,
	Size = UDim2.new(0, 100, 1, 0),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 15,
	Text = "Recall",
	Visible = false,
	Parent = actionRow,
}, { corner(8) })
recallButton.MouseButton1Click:Connect(function()
	Remotes.RecallFromMine:FireServer()
end)

-- ExpeditionService replicates "which row is frontmost" via CurrentSlotId on the Expedition
-- folder (-1 = no expedition active — see that file's comment). Reused here just to know
-- whether to show the Return to Base button at all.
task.spawn(function()
	local expeditionFolder = Workspace:WaitForChild("Expedition", 10)
	if not expeditionFolder then
		return
	end

	local function syncVisibility()
		returnHomeButton.Visible = (expeditionFolder:GetAttribute("CurrentSlotId") or -1) ~= -1
	end

	syncVisibility()
	expeditionFolder:GetAttributeChangedSignal("CurrentSlotId"):Connect(syncVisibility)
end)

----------------------------------------------------------------------
-- Remote listeners
----------------------------------------------------------------------

Remotes.InventoryUpdate.OnClientEvent:Connect(function(patch)
	for key, value in pairs(patch) do
		profile[key] = value
	end
	refreshCurrency()
	if craftFrame.Visible then
		renderCraftList()
	end
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
		recallButton.Visible = false
		return
	end

	depthPanel.Visible = true
	-- Visible any time you're anywhere in the mine, including right at the Depth-0 surface floor
	-- — not just once you've actually descended. It's the one guaranteed way back to base, so it
	-- should be there the moment you're in the mine at all, not gated behind digging first.
	recallButton.Visible = true
	depthLabel.Text = ("Mine Shaft — Depth %d"):format(depth)

	local suitTier = profile.SuitTier or 1
	local heatText, heatColor = hazardStatusLine(findHazardType("Heat"), depth, suitTier)
	local toxicText, toxicColor = hazardStatusLine(findHazardType("ToxicAir"), depth, suitTier)

	if not heatText and not toxicText then
		hazardLabel.TextColor3 = COLOR.Muted
		hazardLabel.Text = "No hazards at this depth"
		hazardLabel2.Text = ""
	else
		hazardLabel.TextColor3 = heatColor or COLOR.Muted
		hazardLabel.Text = heatText or ""
		hazardLabel2.TextColor3 = toxicColor or COLOR.Muted
		hazardLabel2.Text = toxicText or ""
	end
end)

local objectiveMaxHP = 500  -- overwritten from the server's WaveStart payload below
local enemyHPPool = 1       -- ditto; guarded at 1 so an early Tick can't divide by zero

Remotes.WaveUpdate.OnClientEvent:Connect(function(update)
	if update.Status == "NoGear" or update.Status == "NotInBase" then
		warn("[HUD]", update.Message)
		return
	end

	wavePanel.Visible = true

	if update.Status == "WaveStart" then
		runActive = true
		objectiveMaxHP = update.ObjectiveMaxHP or objectiveMaxHP
		enemyHPPool = update.EnemyHPPool or 1
		defendButton.Text = "In progress…"
		waveLabel.Text = ("Wave %d%s"):format(update.Wave, update.IsElite and "  (ELITE)" or "")
		objCaption.Text = ("Objective: %d / %d"):format(update.ObjectiveHP, objectiveMaxHP)
		enemyCaption.Text = ("Enemies: %d"):format(update.EnemyCount)
		objFill.Size = UDim2.new(1, 0, 1, 0)
		enemyFill.Size = UDim2.new(1, 0, 1, 0)
	elseif update.Status == "Tick" then
		local objPct = math.clamp(update.ObjectiveHP / objectiveMaxHP, 0, 1)
		objFill.Size = UDim2.new(objPct, 0, 1, 0)
		objCaption.Text = ("Objective: %d / %d"):format(update.ObjectiveHP, objectiveMaxHP)

		local enemyPct = math.clamp(update.RemainingEnemyHP / enemyHPPool, 0, 1)
		enemyFill.Size = UDim2.new(enemyPct, 0, 1, 0)
		enemyCaption.Text = ("Enemies: ~%d remaining"):format(update.RemainingEnemyCount or 0)
	elseif update.Status == "WaveCleared" then
		waveLabel.Text = ("Wave %d cleared! +%d Scrap, +%d Cores"):format(update.Wave, update.ScrapReward, update.CoresReward)
		enemyCaption.Text = "Enemies: 0 remaining"
	elseif update.Status == "Revived" then
		waveLabel.Text = "Revived — objective restored"
		objCaption.Text = ("Objective: %d / %d"):format(objectiveMaxHP, objectiveMaxHP)
	elseif update.Status == "RunEnded" then
		runActive = false
		defendButton.Text = "Start Defense"
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
		warn("[HUD]", update.Message)
		return
	elseif update.Status == "OnCooldown" then
		warn("[HUD] This outpost is still recovering — try again shortly.")
		return
	elseif update.Status == "Locked" then
		warn("[HUD] Clear the node in front of you before this one opens up.")
		return
	elseif update.Status == "NoEnergy" then
		warn("[HUD] Not enough Energy to raid — wait for it to regen or find an Energy Drink while mining.")
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

	local highlight = new("Highlight", {
		Enabled = false,
		FillTransparency = 1,
		OutlineColor = COLOR.Accent,
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
				warn("[HUD] That node is further down the queue — clear the one in front of you first.")
				return
			end
			local result = Remotes.InteractHeal:InvokeServer(node)
			if not result.Success then
				if result.Reason == "On cooldown" then
					warn(("[HUD] Heal Station recovering (%ds left)."):format(result.SecondsLeft or 0))
				else
					warn("[HUD] Heal failed:", result.Reason)
				end
			end
		end)
	elseif nodeType == "Combat" then
		clickDetector.MouseClick:Connect(function(player)
			if player ~= LocalPlayer then return end
			if not isNodeCurrentlyAccessible(node) then
				warn("[HUD] That node is further down the queue — clear the one in front of you first.")
				return
			end
			Remotes.StartOutpostRaid:FireServer(node)
		end)
	elseif nodeType == "Shop" then
		clickDetector.MouseClick:Connect(function(player)
			if player ~= LocalPlayer then return end
			if not isNodeCurrentlyAccessible(node) then
				warn("[HUD] That node is further down the queue — clear the one in front of you first.")
				return
			end
			if raidInProgress then
				warn("[HUD] Finish your raid before visiting the shop.")
				return
			end
			currentShopNode = node
			shopFrame.Visible = true
			renderShopList()

			if shopNodeDestroyingConn then
				shopNodeDestroyingConn:Disconnect()
			end
			shopNodeDestroyingConn = node.Destroying:Connect(function()
				if currentShopNode == node then
					shopFrame.Visible = false
				end
			end)
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
-- Base stations — Workbench / Welding Station / (Forge, later) props inside a player's base.
-- Tag a Part or Model "Station" (StationConfig.Tag) with a child StringValue "StationType"
-- matching a key in StationConfig.Types. Clicking one jumps the Workbench menu straight to that
-- station's tab — pure convenience; the actual gate (must be standing near the right station,
-- not just anywhere in your plot) is enforced server-side by StationService.lua independently of
-- whatever this does. A station with no DefaultTab (the Forge, for now) has no menu to jump to
-- yet — clicking it just prints a "not built yet" notice instead of opening anything.
----------------------------------------------------------------------

local STATION_TAG = StationConfig.Tag

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

	local highlight = new("Highlight", {
		Enabled = false,
		FillTransparency = 1,
		OutlineColor = COLOR.Accent,
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
			warn(("[HUD] %s doesn't do anything yet — check back later."):format(stationData.DisplayName))
			return
		end
		craftFrame.Visible = true
		selectTab(stationData.DefaultTab)
	end)
end

for _, station in ipairs(CollectionService:GetTagged(STATION_TAG)) do
	setupStation(station)
end
CollectionService:GetInstanceAddedSignal(STATION_TAG):Connect(setupStation)

----------------------------------------------------------------------
-- Initial load
----------------------------------------------------------------------

task.spawn(function()
	local initial = Remotes.GetProfile:InvokeServer()
	if initial then
		for key, value in pairs(initial) do
			profile[key] = value
		end
		refreshCurrency()
	end
end)
