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

local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)
local OreConfig = require(ReplicatedStorage.Shared.OreConfig)
local NodeConfig = require(ReplicatedStorage.Shared.NodeConfig)
local AutoMinerConfig = require(ReplicatedStorage.Shared.AutoMinerConfig)
local RaidEnergyConfig = require(ReplicatedStorage.Shared.RaidEnergyConfig)
local MineShaftConfig = require(ReplicatedStorage.Shared.MineShaftConfig)
local ModConfig = require(ReplicatedStorage.Shared.ModConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local ForgeConfig = require(ReplicatedStorage.Shared.ForgeConfig)
local WeaponFamilyConfig = require(ReplicatedStorage.Shared.WeaponFamilyConfig)
local RefinedOreConfig = require(ReplicatedStorage.Shared.RefinedOreConfig)
local BaseConfig = require(ReplicatedStorage.Shared.BaseConfig)
local ResearchConfig = require(ReplicatedStorage.Shared.ResearchConfig)
local UltimateConfig = require(ReplicatedStorage.Shared.UltimateConfig)
local CaseConfig = require(ReplicatedStorage.Shared.CaseConfig)
local Wallet = require(ReplicatedStorage.Shared.Wallet)
local TurretConfig = require(ReplicatedStorage.Shared.TurretConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LocalPlayer = Players.LocalPlayer

-- Shared HUD foundation: palette, Instance.new helpers, the ScreenGui, the client's profile
-- mirror, the toast, and makeRow. Referenced as Hud.X throughout rather than re-bound to
-- locals here — re-binding would hand every register straight back, which is the entire
-- reason this module exists (see HudKit.lua's header).
local Hud = require(script.Parent.HudKit)
local ModPicker = require(script.Parent.ModPicker)


local runActive = false

----------------------------------------------------------------------
-- Small UI helpers
----------------------------------------------------------------------


----------------------------------------------------------------------
-- Screen setup
----------------------------------------------------------------------


----------------------------------------------------------------------
-- Currency readout (top-left)
----------------------------------------------------------------------

local currencyFrame = Hud.new("Frame", {
	Name = "Currency",
	BackgroundColor3 = Hud.COLOR.Panel,
	Position = UDim2.new(0, 16, 0, 16),
	Size = UDim2.new(0, 220, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Parent = Hud.screenGui,
}, {
	Hud.corner(8),
	Hud.stroke(),
	Hud.new("UIListLayout", { Padding = UDim.new(0, 2) }),
	Hud.new("UIPadding", {
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
	}),
})

local function makeStatLabel(color)
	return Hud.new("TextLabel", {
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

local scrapLabel = makeStatLabel(Hud.COLOR.Accent)
local coresLabel = makeStatLabel(Hud.COLOR.Good)
local energyLabel = makeStatLabel(Hud.COLOR.Good)

-- Ore/material counts used to live here too (one label per ore plus a divider), but that made
-- this corner unreadable fast — it's trimmed down to just the three numbers worth a glance during
-- normal play now. The full breakdown (plus Scrap/Cores again for a complete picture) lives in
-- the Inventory panel's Materials tab instead — see that section further down. ORE_DISPLAY_ORDER
-- itself is kept here since the Materials tab still needs it.
local ORE_DISPLAY_ORDER = { "ScrapIron", "CopperWire", "SteelPlating", "GoldContacts" }

local function refreshCurrency()
	scrapLabel.Text = ("Scrap: %d"):format(Hud.profile.Scrap or 0)
	coresLabel.Text = ("Cores: %d"):format(Hud.profile.Cores or 0)
	-- Energy can briefly read above MaxEnergy right after an Energy Drink (see
	-- RaidEnergyConfig.OverflowCap) — that's intentional, not a bug, it just drains back down to
	-- the normal cap as raids are spent rather than being topped up further by passive regen.
	energyLabel.Text = ("Energy: %d/%d"):format(Hud.profile.Energy or 0, RaidEnergyConfig.MaxEnergy)
end

----------------------------------------------------------------------
-- Craft menu (center, toggled)
----------------------------------------------------------------------

local craftFrame = Hud.new("Frame", {
	Name = "CraftMenu",
	BackgroundColor3 = Hud.COLOR.Panel,
	Position = UDim2.new(0.5, -320, 0.5, -200),
	Size = UDim2.new(0, 640, 0, 400), -- widened/heightened to fit up to 3 tabs at once and the
	                                  -- taller equipment rows mod slots need
	Visible = false,
	Parent = Hud.screenGui,
}, { Hud.corner(10), Hud.stroke() })

-- There's no standalone "Workbench" button anymore — this menu only ever opens FROM a physical
-- station now (see openStationMenu / setupStation further down), so the title doubles as a
-- reminder of which one is currently open. Instances only; the click handler for
-- craftCloseButton is wired up later, alongside closeModPicker's definition.
local craftTitleLabel = Hud.new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 10),
	Size = UDim2.new(1, -60, 0, 22),
	Font = Enum.Font.SourceSansBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 18,
	Text = "Workbench",
	Parent = craftFrame,
})

local craftCloseButton = Hud.new("TextButton", {
	BackgroundColor3 = Hud.COLOR.PanelLight,
	Position = UDim2.new(1, -40, 0, 8),
	Size = UDim2.new(0, 28, 0, 28),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 16,
	Text = "X",
	Parent = craftFrame,
}, { Hud.corner(6) })

local tabRow = Hud.new("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 40),
	Size = UDim2.new(1, -24, 0, 32),
	Parent = craftFrame,
}, { Hud.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }) })

local listFrame = Hud.new("ScrollingFrame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 80),
	Size = UDim2.new(1, -24, 1, -92),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	Parent = craftFrame,
}, { Hud.new("UIListLayout", { Padding = UDim.new(0, 6) }) })

-- Delegates to Wallet so the HUD names and orders cost keys exactly the way the server resolves
-- them — including refined materials, which this used to render as their raw key ("SteelIngot")
-- because it only knew about Scrap/Cores and OreConfig.


local currentTab = "Weapons"

-- Tool tier isn't a recipe table either — it's one sequential upgrade track — so it gets its
-- own row-builder too. This is the ONLY way ToolTier (and therefore access to Steel Plating and
-- above, see OreConfig.Ores[key].MinToolTier) ever goes up.
local function renderToolRow()
	local currentTier = Hud.profile.ToolTier or 1
	local currentToolData = OreConfig.ToolTiers[currentTier]
	local nextTier = currentTier + 1
	local nextToolData = OreConfig.ToolTiers[nextTier]

	if not nextToolData then
		Hud.makeRow(
			currentToolData and currentToolData.Name or "Tool",
			"Max tier reached",
			"Maxed",
			function() end
		).Parent = listFrame
		return
	end

	local cost = OreConfig.ToolTierCosts[nextTier]
	Hud.makeRow(
		("%s -> %s"):format(currentToolData and currentToolData.Name or "?", nextToolData.Name),
		cost and Hud.costString(cost) or "Not configured",
		"Upgrade",
		function()
			local result = Remotes.UpgradeTool:InvokeServer()
			if not result.Success then
				Hud.showFailure("Upgrade failed", result.Reason)
			end
		end
	).Parent = listFrame
end

-- Auto-Miner isn't a recipe table like Weapons/Robots — it's a single fixed structure — so it
-- gets its own row-builder instead of going through the generic recipes loop below.
local function renderAutoMinerRow()
	local owned = Hud.profile.CraftedStructures and Hud.profile.CraftedStructures.AutoMiner
	local hasPass = Hud.profile.OwnedGamePasses and Hud.profile.OwnedGamePasses.AutoMiner
	local rate = AutoMinerConfig.BaseYieldPerTick * (hasPass and AutoMinerConfig.GamePassMultiplier or 1)
	local oreDisplayName = (OreConfig.Ores[AutoMinerConfig.OreKey] and OreConfig.Ores[AutoMinerConfig.OreKey].DisplayName)
		or AutoMinerConfig.OreKey

	local subtitle
	if owned then
		subtitle = ("Built · +%d %s every %ds%s"):format(
			rate, oreDisplayName, AutoMinerConfig.TickSeconds, hasPass and " (pass applied)" or "")
	else
		subtitle = Hud.costString(AutoMinerConfig.Cost)
	end

	Hud.makeRow(
		"Mini Particle Accelerator",
		subtitle,
		owned and "Built" or "Build",
		function()
			if owned then return end
			local result = Remotes.CraftAutoMiner:InvokeServer()
			if not result.Success then
				Hud.showFailure("Build failed", result.Reason)
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
	local currentTier = Hud.profile.SuitTier or 1
	local currentSuitData = MineShaftConfig.SuitTiers[currentTier]
	local nextTier = currentTier + 1
	local nextSuitData = MineShaftConfig.SuitTiers[nextTier]

	if not nextSuitData then
		Hud.makeRow(
			currentSuitData and currentSuitData.Name or "Suit",
			"Max tier reached — protects against everything the mine shaft throws at you",
			"Maxed",
			function() end
		).Parent = listFrame
		return
	end

	local cost = MineShaftConfig.SuitTierCosts[nextTier]
	Hud.makeRow(
		("%s -> %s"):format(currentSuitData and currentSuitData.Name or "?", nextSuitData.Name),
		("Protects: %s · %s"):format(nextSuitData.ProtectsAgainst, cost and Hud.costString(cost) or "Not configured"),
		"Upgrade",
		function()
			local result = Remotes.UpgradeSuit:InvokeServer()
			if not result.Success then
				Hud.showFailure("Suit upgrade failed", result.Reason)
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
		local owned = Hud.profile.CraftedMods and Hud.profile.CraftedMods[key]
		Hud.makeRow(
			mod.DisplayName,
			owned and mod.Description or ("%s · %s"):format(mod.Description, Hud.costString(mod.Cost)),
			owned and "Owned" or "Craft",
			function()
				if owned then return end
				local result = Remotes.CraftItem:InvokeServer("Mods", key)
				if not result.Success then
					Hud.showFailure("Craft failed", result.Reason)
				end
			end
		).Parent = listFrame
	end
end


----------------------------------------------------------------------
-- Turret slot panel — opened by clicking a turret slot out in the world (the blue pad for an
-- empty one, or the turret itself for an occupied one), NOT from a tab in the Workbench.
--
-- Placement used to live as a wall of rows in the Workbench's Base tab: one row per slot, a
-- separate Unplace row under each occupied one, and a "Storage" list whose Place button silently
-- auto-picked the first open slot for you. That meant choosing WHERE a turret went wasn't really
-- a choice, and managing turrets happened nowhere near the turrets. Now the slot in the world is
-- the interaction point — click it, see what you own, pick one.
--
-- Same popup shape as the mod picker directly above (frame, title, X, scrolling list of makeRows)
-- because it's the same interaction: "this slot is empty, here's what you own that fits."
----------------------------------------------------------------------

-- One table instead of 5 separate top-level locals: Luau caps a function scope at 200
-- locals and this file's main chunk hit that ceiling. Grouping UI element references costs
-- nothing at runtime and buys back a register per element.
local turretPanel = {}
turretPanel.frame = Hud.new("Frame", {
	Name = "TurretSlotPanel",
	BackgroundColor3 = Hud.COLOR.Panel,
	Position = UDim2.new(0.5, -190, 0.5, -190),
	Size = UDim2.new(0, 380, 0, 380),
	Visible = false,
	ZIndex = 5,
	Parent = Hud.screenGui,
}, { Hud.corner(10), Hud.stroke() })

turretPanel.title = Hud.new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 10),
	Size = UDim2.new(1, -60, 0, 24),
	Font = Enum.Font.SourceSansBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 18,
	Text = "Turret Slot",
	Parent = turretPanel.frame,
})

turretPanel.close = Hud.new("TextButton", {
	BackgroundColor3 = Hud.COLOR.PanelLight,
	Position = UDim2.new(1, -40, 0, 8),
	Size = UDim2.new(0, 28, 0, 28),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 16,
	Text = "X",
	Parent = turretPanel.frame,
}, { Hud.corner(6) })

turretPanel.list = Hud.new("ScrollingFrame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 44),
	Size = UDim2.new(1, -24, 1, -56),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	Parent = turretPanel.frame,
}, { Hud.new("UIListLayout", { Padding = UDim.new(0, 6) }) })

-- Which slot the panel is currently open for, so an InventoryUpdate arriving while it's open can
-- re-render it in place (a placed/upgraded/unplaced turret changes what this panel should show).
turretPanel.state = { slotIndex = nil :: number? }

local function closeTurretPanel()
	turretPanel.frame.Visible = false
	turretPanel.state.slotIndex = nil
end
turretPanel.close.MouseButton1Click:Connect(closeTurretPanel)

local renderTurretPanel -- forward-declared: the row callbacks below re-render through it

-- Formats one turret instance's live stats line, shared by the occupied-slot view and the
-- storage list so a turret reads the same in both places.
local function turretStatsLine(turret): string
	local stats = TurretConfig.GetTurretEffectiveStats(turret.TypeKey, turret.Level or 1)
	if not stats then
		return "Unknown turret type"
	end
	return ("%.0f dmg · %.0f range · %.1f shots/s · %d AOE"):format(
		stats.Damage, stats.Range, stats.FireRate, stats.AOE)
end

renderTurretPanel = function()
	local slotIndex = turretPanel.state.slotIndex
	if not slotIndex then
		return
	end

	for _, child in ipairs(turretPanel.list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Re-derived from the live Hud.profile every render rather than captured when the panel opened —
	-- placing or unplacing fires InventoryUpdate, which re-renders this, and the slot's occupancy
	-- has changed by then.
	local occupant = nil
	local unplaced = {}
	for _, turret in ipairs(Hud.profile.Turrets or {}) do
		if turret.SlotIndex == slotIndex then
			occupant = turret
		elseif not turret.SlotIndex then
			table.insert(unplaced, turret)
		end
	end

	turretPanel.title.Text = ("Turret Slot %d"):format(slotIndex)

	if occupant then
		local typeData = TurretConfig.Types[occupant.TypeKey]
		local level = occupant.Level or 1
		local stats = TurretConfig.GetTurretEffectiveStats(occupant.TypeKey, level)
		local researchTier = Hud.profile.ResearchTier or 1
		local nextTurretTier = TurretConfig.GetTurretTier(level + 1)
		-- Crossing into a new Tier needs Research to have caught up — a deliberate skeleton gate
		-- until the Research system ships (the confirmed next roadmap step), not a bug.
		local tierLocked = stats and nextTurretTier > stats.Tier and researchTier < nextTurretTier
		local upgradeCost = TurretConfig.GetTurretUpgradeCost(level)

		Hud.makeRow(
			("%s — Level %d (Tier %d)"):format(
				typeData and typeData.DisplayName or occupant.TypeKey, level, stats and stats.Tier or 1),
			turretStatsLine(occupant),
			tierLocked and ("Needs Research T%d"):format(nextTurretTier)
				or ("Upgrade (%d %s)"):format(upgradeCost, TurretConfig.UpgradeCurrency),
			function()
				if tierLocked then
					Hud.showFailure("Locked", ("Level %d needs Research Tier %d — that system isn't built yet."):format(level + 1, nextTurretTier))
					return
				end
				local result = Remotes.UpgradeTurret:InvokeServer(occupant.Id)
				if not result.Success then
					Hud.showFailure("Upgrade turret failed", result.Reason)
				end
			end
		).Parent = turretPanel.list

		Hud.makeRow(
			"Remove from this slot",
			"Sends it back to storage — still owned, just not defending",
			"Unplace",
			function()
				local result = Remotes.UnplaceTurret:InvokeServer(occupant.Id)
				if not result.Success then
					Hud.showFailure("Unplace turret failed", result.Reason)
					return
				end
				closeTurretPanel() -- the turret you were managing isn't here anymore
			end
		).Parent = turretPanel.list
		return
	end

	-- Empty slot — this is the "turret inventory" view: everything you own that isn't already
	-- placed somewhere, each one placeable into THIS slot.
	if #unplaced == 0 then
		Hud.makeRow(
			"Nothing to place",
			"Buy a turret blueprint at the Hub Shop — each purchase mints a turret into storage",
			"OK",
			function() end
		).Parent = turretPanel.list
		return
	end

	for _, turret in ipairs(unplaced) do
		local typeData = TurretConfig.Types[turret.TypeKey]
		Hud.makeRow(
			("%s (Level %d)"):format(typeData and typeData.DisplayName or turret.TypeKey, turret.Level or 1),
			turretStatsLine(turret),
			"Place here",
			function()
				local result = Remotes.PlaceTurretInSlot:InvokeServer(turret.Id, slotIndex)
				if not result.Success then
					Hud.showFailure("Place turret failed", result.Reason)
					return
				end
				closeTurretPanel() -- it's placed; the slot is now what you can see in the world
			end
		).Parent = turretPanel.list
	end
end

local function openTurretPanel(slotIndex: number)
	turretPanel.state.slotIndex = slotIndex
	renderTurretPanel()
	turretPanel.frame.Visible = true
end

-- Taller than makeRow's fixed 52px — same title/subtitle/button layout up top, plus a row of
-- ModConfig.SlotsPerItem slot buttons underneath for owned weapons/robots. Clicking a slot opens
-- the mod picker popup (see openModPicker above) instead of cycling in place.
local function makeEquipmentRow(tree: string, itemKey: string, titleText: string, statsText: string, buttonText: string, onClick)
	local row = Hud.new("Frame", {
		BackgroundColor3 = Hud.COLOR.PanelLight,
		Size = UDim2.new(1, 0, 0, 90),
	}, { Hud.corner(6) })

	Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 4),
		Size = UDim2.new(1, -110, 0, 20),
		Font = Enum.Font.SourceSansBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Hud.COLOR.Text,
		TextSize = 16,
		Text = titleText,
		Parent = row,
	})

	Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 24),
		Size = UDim2.new(1, -110, 0, 20),
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Hud.COLOR.Muted,
		TextSize = 13,
		Text = statsText,
		Parent = row,
	})

	local button = Hud.new("TextButton", {
		BackgroundColor3 = Hud.COLOR.Accent,
		Position = UDim2.new(1, -96, 0, 4),
		Size = UDim2.new(0, 86, 0, 32),
		Font = Enum.Font.SourceSansBold,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 14,
		Text = buttonText,
		Parent = row,
	}, { Hud.corner(6) })
	button.MouseButton1Click:Connect(onClick)

	local slotRow = Hud.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 50),
		Size = UDim2.new(1, -20, 0, 32),
		Parent = row,
	}, { Hud.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })

	for slotIndex = 1, ModConfig.SlotsPerItem do
		local equippedKey = ModPicker.equippedModKeyForSlot(itemKey, slotIndex)
		local mod = equippedKey and ModConfig.Mods[equippedKey]
		local slotButton = Hud.new("TextButton", {
			BackgroundColor3 = mod and Hud.COLOR.AccentDark or Hud.COLOR.Panel,
			Size = UDim2.new(0, MOD_SLOT_WIDTH, 1, 0),
			Font = Enum.Font.Code,
			TextColor3 = Hud.COLOR.Text,
			TextSize = 12,
			TextWrapped = true,
			Text = mod and mod.DisplayName or ("Slot %d: Empty"):format(slotIndex),
			Parent = slotRow,
		}, { Hud.corner(4), Hud.stroke() })
		slotButton.MouseButton1Click:Connect(function()
			ModPicker.openModPicker(tree, itemKey, slotIndex)
		end)
	end

	return row
end

-- How many currently-deployed instances of a given robotKey there are (DeployedRobots can hold
-- the same key more than once — a player owning 3 Sentry Bots can deploy all 3). Shared by
-- makeRobotRow below and the Inventory panel's Robots tab.
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

-- One owned robot's row. The Forge's Weapons tab has no equivalent anymore (it's craft-only now —
-- see the Forge tab section below); owning/equipping a Forged weapon instance is Inventory-only.
-- The button here toggles Deploy/Undeploy instead of always being "Deploy": once every owned copy
-- is on defense duty there's nothing left to deploy, so the only sensible action left is pulling
-- one back off (UndeployRobot, see CraftingService.lua) — a single button can express that
-- unambiguously without needing two.
local function makeRobotRow(key: string)
	local recipe = CraftingRecipes.Robots[key]
	local owned = Hud.profile.CraftedRobots[key] or 0
	local deployed = deployedCountForRobot(key)
	local canDeployMore = deployed < owned
	return makeEquipmentRow(
		"Robots", key,
		("T%d  %s (owned %d, deployed %d)"):format(recipe.Tier, recipe.DisplayName, owned, deployed),
		("Base: %.1f dmg x %.1f/s · %d HP"):format(recipe.BaseDamage, recipe.FireRate, recipe.HP),
		canDeployMore and "Deploy" or "Undeploy",
		function()
			if canDeployMore then
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
	)
end

----------------------------------------------------------------------
-- Forge tab — replaces the old flat "craft one of each weapon type" list. Every weapon in the
-- game is Forged now: rolling the same weapon type twice mints two independent instances, each
-- with its own random Rarity (ModConfig.Rarities) and Affixes (ForgeConfig.AffixPool). Luck (both
-- your Forge's own permanent ForgeTier and the consumable LuckPotion) bends the rarity odds, and
-- Pity guarantees a floor after a long enough unlucky streak — see ForgeService.rollRarity/
-- ForgeWeapon server-side for the actual math this UI is just presenting.
--
-- This tab is craft-only, deliberately — equipping, mod slots, and browsing what you already own
-- all live in the Inventory panel instead (see that section further down). Rolling a weapon here
-- used to also drop a full owned-instance list with Equip buttons right below the roll buttons,
-- which just duplicated the Inventory and made "click Forge" and "click Equip" easy to fumble
-- together. All this tab shows now is your Luck/Pity status and the roll buttons themselves, plus
-- a small "last result" readout so a roll doesn't feel like it vanished into the void.
----------------------------------------------------------------------

-- Whether the player's NEXT Forge click should burn one Luck Potion. Client-side-only toggle —
-- ForgeWeapon re-validates Potion ownership server-side regardless, so this can never desync into
-- spending a Potion the player doesn't have.
local forgeUsePotion = false

-- What the last successful Forge roll produced, purely for the "last result" readout below — not
-- server state, just cleared back to nil on a fresh HUD load. { WeaponKey, Rarity, Affixes }.
local lastForgedResult = nil

-- Which family's guns the Forge is currently listing. nil = the family picker itself, which is
-- what the tab opens on. A flat list of every weapon was fine at four and unreadable at
-- eighteen — see WeaponFamilyConfig.
local forgeFamily = nil

-- Forward-declared, same reason as renderCraftList below: the Forge roll button (defined here,
-- earlier in the file) needs to refresh the persistent pity bar / potion button (defined later,
-- in the "Forge status HUD" section, since the potion button needs getItemIcon which isn't
-- available yet at this point in the script) the instant a roll lands, not just whenever the next
-- InventoryUpdate patch happens to arrive.
local refreshPityBar
local refreshPotionButton

-- Forward-declared: setForgeWidgetsVisible (assigned in the "Forge status HUD" section) hides the
-- bottom action row (Inventory/Start Defense/etc.) while the Forge-docked pity bar and Potion
-- button are showing — on shorter viewports the docked row sits low enough to overlap the action
-- row otherwise (see the screenshot that prompted this). actionRow itself isn't created until much
-- later in the file (down by the other bottom-of-screen panels), hence the forward declaration.
local actionRow

-- Forward-declared: renderCraftList's "Smelting" branch (below) needs to call this, but the real
-- definition lives in the "Ore Smelting" section much further down — it needs makeItemTile/
-- getItemIcon/showInvDetail (Inventory panel helpers) and a popup frame of its own, same ordering
-- constraint as refreshPityBar/refreshPotionButton above.
local renderSmeltingTab

-- Forward-declared: renderForgeWeapons' Potion-toggle button needs to re-render the list it's
-- sitting in, but renderCraftList (below) is what dispatches TO renderForgeWeapons in the first
-- place — a genuine circular reference. Declaring the local up here (assigned further down with
-- `renderCraftList = function() ... end`, no `local` keyword there) lets renderForgeWeapons
-- capture the right upvalue.
local renderCraftList

local function renderForgeWeapons()
	local forgeTier = Hud.profile.ForgeTier or 1
	local forgeTierData = ForgeConfig.ForgeTiers[forgeTier]
	local nextForgeTierData = ForgeConfig.ForgeTiers[forgeTier + 1]

	if nextForgeTierData then
		local cost = ForgeConfig.ForgeTierCosts[forgeTier + 1]
		Hud.makeRow(
			("Forge: %s -> %s"):format(forgeTierData and forgeTierData.Name or "?", nextForgeTierData.Name),
			("Currently +%d luck · %s"):format(forgeTierData and forgeTierData.Bonus or 0, cost and Hud.costString(cost) or "Not configured"),
			"Upgrade",
			function()
				local result = Remotes.UpgradeForgeTier:InvokeServer()
				if not result.Success then
					Hud.showFailure("Forge upgrade failed", result.Reason)
				end
			end
		).Parent = listFrame
	else
		Hud.makeRow(
			forgeTierData and forgeTierData.Name or "Forge",
			("+%d luck · max tier reached"):format(forgeTierData and forgeTierData.Bonus or 0),
			"Maxed",
			function() end
		).Parent = listFrame
	end

	Hud.makeRow(
		("Luck Potion (%d owned)"):format(Hud.profile.LuckPotions or 0),
		("%s · +%d luck, consumed on your next roll"):format(Hud.costString(ForgeConfig.LuckPotion.Cost), ForgeConfig.LuckPotion.Bonus),
		"Craft",
		function()
			local result = Remotes.CraftLuckPotion:InvokeServer()
			if not result.Success then
				Hud.showFailure("Craft Luck Potion failed", result.Reason)
			end
		end
	).Parent = listFrame

	-- The "use a Potion on next roll" toggle and the Pity progress readout both moved OUT of this
	-- list per direct feedback — see the "Forge status HUD" section further down for the persistent
	-- pity bar and Luck Potion button that replaced them (positioned under the top-left currency
	-- readout, always visible, not just while this menu happens to be open).

	if lastForgedResult then
		local recipe = CraftingRecipes.Weapons[lastForgedResult.WeaponKey]
		local rarityData = ModConfig.Rarities[lastForgedResult.Rarity]
		local rarityName = rarityData and rarityData.DisplayName or lastForgedResult.Rarity
		Hud.makeRow(
			("Last Forged: [%s] %s"):format(rarityName, recipe and recipe.DisplayName or lastForgedResult.WeaponKey),
			affixSummary(lastForgedResult.Affixes),
			"OK",
			function() end
		).Parent = listFrame
	end

	----------------------------------------------------------------------
	-- Family picker. Locked families are still SHOWN, greyed, naming the blueprint that opens them —
	-- a player who can't see what they're missing has no reason to chase a case. Locked rows just
	-- don't navigate anywhere.
	----------------------------------------------------------------------

	if not forgeFamily then
		for _, familyKey in ipairs(WeaponFamilyConfig.Order) do
			local family = WeaponFamilyConfig.Families[familyKey]
			local unlocked = WeaponFamilyConfig.IsUnlocked(Hud.profile, familyKey)

			local count = 0
			for _, recipe in pairs(CraftingRecipes.Weapons) do
				if recipe.Family == familyKey then
					count += 1
				end
			end

			Hud.makeRow(
				family.DisplayName,
				unlocked
					and ("%d weapon%s · %s"):format(count, count == 1 and "" or "s", family.Description)
					or ("LOCKED · find the %s in a Black Market case"):format(
						WeaponFamilyConfig.BlueprintName(familyKey)),
				unlocked and "Open" or "Locked",
				function()
					if not unlocked then
						Hud.showFailure(
							("%s is locked"):format(family.DisplayName),
							("Its blueprint (%s) drops from Legendary rolls at the Black Market."):format(
								WeaponFamilyConfig.BlueprintName(familyKey)))
						return
					end
					forgeFamily = familyKey
					renderCraftList()
				end
			).Parent = listFrame
		end
		return
	end

	----------------------------------------------------------------------
	-- One family's roll rows. Unlike the old flat-craft list there's no "already own it" gate —
	-- every click mints a brand-new independent instance.
	----------------------------------------------------------------------

	local familyData = WeaponFamilyConfig.Families[forgeFamily]
	Hud.makeRow(
		"< Back to families",
		familyData and familyData.Description or "",
		"Back",
		function()
			forgeFamily = nil
			renderCraftList()
		end
	).Parent = listFrame

	local keys = {}
	for key, recipe in pairs(CraftingRecipes.Weapons) do
		if recipe.Family == forgeFamily then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a, b)
		return CraftingRecipes.Weapons[a].Tier < CraftingRecipes.Weapons[b].Tier
	end)
	for _, key in ipairs(keys) do
		local recipe = CraftingRecipes.Weapons[key]

		-- Two stat lines are worth surfacing because they change how a gun is USED, not just how hard
		-- it hits: a headshot bonus tells you to aim high, a wield penalty tells you it costs mobility.
		local notes = ("%s · Base %.1f dmg x %.1f/s"):format(
			Hud.costString(recipe.Cost), recipe.BaseDamage, recipe.FireRate)
		if recipe.HeadshotMultiplier and recipe.HeadshotMultiplier > 1 then
			notes ..= ("  ·  x%.1f headshots"):format(recipe.HeadshotMultiplier)
		end
		if recipe.WieldSpeedMultiplier then
			notes ..= ("  ·  %d%% move speed while held"):format(
				math.floor(recipe.WieldSpeedMultiplier * 100 + 0.5))
		end

		Hud.makeRow(
			("T%d  %s"):format(recipe.Tier, recipe.DisplayName),
			notes,
			"Forge",
			function()
				local usePotion = forgeUsePotion and (Hud.profile.LuckPotions or 0) > 0
				local result = Remotes.ForgeWeapon:InvokeServer(key, usePotion)
				if not result.Success then
					Hud.showFailure("Forge failed", result.Reason)
				else
					forgeUsePotion = false -- one-shot regardless of whether a Potion actually got spent
					lastForgedResult = result.Weapon
					refreshPotionButton() -- reflects both the reset toggle and the (likely) spent Potion
					refreshPityBar() -- snappier than waiting on the InventoryUpdate patch that follows
					renderCraftList()
				end
			end
		).Parent = listFrame
	end
end

----------------------------------------------------------------------
-- Base tab (Workbench) — now a thin summary plus the Research claim, because the two things that
-- used to fill it both moved somewhere better:
--   * turret placement moved into the world (click a slot pad — see openTurretPanel)
--   * the base-tier upgrade became the Research claim, which lives on the always-visible status
--     panel bottom-left so you can see progress without standing at a station
-- What is left here is the CLAIM itself, which is station-gated server-side, plus a readout of what
-- the current tier actually gives you.
----------------------------------------------------------------------

local function renderBaseRow()
	local currentTier, currentIndex = ResearchConfig.GetTier(Hud.profile.ResearchTier or 1)
	local slotCount = TurretConfig.GetSlotCount(currentIndex)

	Hud.makeRow(
		("Research Tier %d — %s"):format(currentIndex, currentTier.Name),
		("Wall %d HP · %d turret slots · %d-stud base footprint"):format(
			currentTier.WallHP, slotCount, currentTier.FootprintHalfSize.X * 2),
		"Current",
		function() end
	).Parent = listFrame

	local req = ResearchConfig.GetNextTierRequirements(Hud.profile)
	if not req then
		Hud.makeRow(
			"Fully researched",
			"You are at the highest tier there is.",
			"Maxed",
			function() end
		).Parent = listFrame
	else
		local nextTier = ResearchConfig.Tiers[req.TierIndex]
		-- Summarises what is still missing rather than just saying no — the full breakdown lives in
		-- the status panel's Research popup, which this points at.
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

		Hud.makeRow(
			("Research Tier %d — %s"):format(req.TierIndex, req.Name),
			#missing > 0
				and ("Still need: %s"):format(table.concat(missing, ", "))
				or ("Wall %d HP · %d turret slots · ready to claim"):format(
					nextTier.WallHP, TurretConfig.GetSlotCount(req.TierIndex)),
			req.CanClaim and "Claim" or "Locked",
			function()
				local result = Remotes.UpgradeResearch:InvokeServer()
				if not result.Success then
					Hud.showFailure("Research failed", result.Reason)
				else
					Hud.showToast(("Research Tier %d — your base has been rebuilt."):format(result.ResearchTier), 4)
					renderCraftList()
				end
			end
		).Parent = listFrame
	end

	-- Turrets are placed by clicking a slot pad in the world now, not from here.
	local placedCount, storedCount = 0, 0
	for _, turret in ipairs(Hud.profile.Turrets or {}) do
		if turret.SlotIndex then
			placedCount += 1
		else
			storedCount += 1
		end
	end

	Hud.makeRow(
		("Turrets — %d placed of %d slots, %d in storage"):format(placedCount, slotCount, storedCount),
		storedCount > 0
			and "Walk to a blue slot pad at your base and click it to place one"
			or "Buy a blueprint at the Hub Shop, build it at the Welding Station, then click a slot pad",
		"OK",
		function() end
	).Parent = listFrame
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

local function renderDecodeRow()
	local job = Hud.profile.DecodeJob

	if job and job.FinishTime then
		local remaining = job.FinishTime - os.time()
		local case = CaseConfig.Cases[job.CaseKey]

		if remaining > 0 then
			Hud.makeRow(
				("Decoding: %s"):format(case and case.DisplayName or job.CaseKey),
				("Ready in %s"):format(formatClock(remaining)),
				"Working",
				function() end
			).Parent = listFrame

			-- The two rush paths, side by side, so the risk asymmetry is visible at the moment of
			-- choosing rather than buried in a description somewhere.
			Hud.makeRow(
				("Force it — %d Cores"):format(CaseConfig.Rush.CoresCost),
				("%d%% chance the case corrupts and you lose it"):format(math.floor(CaseConfig.Rush.CorruptChance * 100)),
				"Rush",
				function()
					local result = Remotes.RushDecode:InvokeServer()
					if not result.Success then
						Hud.showFailure("Rush failed", result.Reason)
					elseif result.Corrupted then
						Hud.showToast(result.Reason or "The case corrupted. Nothing recoverable.", 5)
					end
					renderCraftList()
				end
			).Parent = listFrame

			Hud.makeRow(
				"Clean bypass — Robux",
				"Instant, no risk of corruption",
				"Robux",
				function()
					Hud.showFailure("Not set up", "The instant decode needs its product id filled into ShopConfig.lua first.")
				end
			).Parent = listFrame
		else
			-- The background loop resolves within a couple of seconds of the timer hitting zero.
			Hud.makeRow(
				("Decoding: %s"):format(case and case.DisplayName or job.CaseKey),
				"Finishing up...",
				"Wait",
				function() end
			).Parent = listFrame
		end
		return
	end

	local cases = Hud.profile.Cases or {}
	local any = false
	for _, caseKey in ipairs((function()
		local keys = {}
		for key in pairs(CaseConfig.Cases) do
			table.insert(keys, key)
		end
		table.sort(keys)
		return keys
	end)()) do
		local owned = cases[caseKey] or 0
		if owned > 0 then
			any = true
			local case = CaseConfig.Cases[caseKey]
			Hud.makeRow(
				("%s (x%d)"):format(case.DisplayName, owned),
				("%s · takes %s"):format(case.Description, formatClock(case.DecodeSeconds)),
				"Decode",
				function()
					local result = Remotes.StartDecode:InvokeServer(caseKey)
					if not result.Success then
						Hud.showFailure("Decode failed", result.Reason)
					else
						Hud.showToast(("Decoding a %s..."):format(case.DisplayName), 3)
					end
					renderCraftList()
				end
			).Parent = listFrame
		end
	end

	if not any then
		Hud.makeRow(
			"Nothing to decode",
			"Buy a sealed case at the Black Market first",
			"OK",
			function() end
		).Parent = listFrame
	end
end

local function renderTurretsRow()
	local unlocked = Hud.profile.UnlockedTurretBlueprints or {}

	-- Sorted by craft cost so the list reads as a progression rather than a hash order.
	local keys = {}
	for key in pairs(TurretConfig.Types) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return (TurretConfig.Types[a].BlueprintCost.Scrap or 0) < (TurretConfig.Types[b].BlueprintCost.Scrap or 0)
	end)

	local knownCount = 0
	for _, key in ipairs(keys) do
		if unlocked[key] then
			knownCount += 1
		end
	end

	if knownCount == 0 then
		Hud.makeRow(
			"No blueprints yet",
			"Buy one at the Hub Shop, then come back here to build the turret with Scrap and ore",
			"OK",
			function() end
		).Parent = listFrame
	end

	for _, key in ipairs(keys) do
		local typeData = TurretConfig.Types[key]
		local known = unlocked[key] == true
		local stats = TurretConfig.GetTurretEffectiveStats(key, 1)
		Hud.makeRow(
			known and typeData.DisplayName or ("%s (locked)"):format(typeData.DisplayName),
			known
				and ("%s · %s"):format(
					stats and ("%.0f dmg · %.0f range · %.1f/s · %d AOE"):format(stats.Damage, stats.Range, stats.FireRate, stats.AOE) or typeData.Description,
					Hud.costString(typeData.CraftCost))
				or ("%s · blueprint not owned — buy it at the Hub Shop"):format(typeData.Description),
			known and "Build" or "Locked",
			function()
				if not known then
					Hud.showFailure("Locked", ("You need the %s blueprint — buy it at the Hub Shop."):format(typeData.DisplayName))
					return
				end
				-- Reuses the shared CraftItem remote with a "Turrets" tree — same plot/station gate
				-- and cost validation Robots and Mods already go through. See CraftingService.
				local result = Remotes.CraftItem:InvokeServer("Turrets", key)
				if not result.Success then
					Hud.showFailure("Build failed", result.Reason)
				else
					Hud.showToast(("Built a %s — click a slot pad at your base to place it."):format(typeData.DisplayName), 4)
					renderCraftList()
				end
			end
		).Parent = listFrame
	end
end

renderCraftList = function()
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
	elseif currentTab == "Base" then
		renderBaseRow()
		return
	elseif currentTab == "Blueprints" then
		renderBlueprintsRow()
		return
	elseif currentTab == "Turrets" then
		renderTurretsRow()
		return
	elseif currentTab == "Cases" then
		renderCasesRow()
		return
	elseif currentTab == "Decode" then
		renderDecodeRow()
		return
	elseif currentTab == "Mods" then
		renderModsRow()
		return
	elseif currentTab == "Weapons" then
		renderForgeWeapons()
		return
	elseif currentTab == "Smelting" then
		renderSmeltingTab()
		return
	end

	-- Only Robots ever reaches here now — Weapons moved to the Forge above.
	local recipes = CraftingRecipes.Robots

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
		local ownedCount = Hud.profile.CraftedRobots[key] or 0
		if ownedCount > 0 then
			makeRobotRow(key).Parent = listFrame
		else
			Hud.makeRow(
				("T%d  %s"):format(recipe.Tier, recipe.DisplayName),
				Hud.costString(recipe.Cost),
				"Craft",
				function()
					local result = Remotes.CraftItem:InvokeServer("Robots", key)
					if not result.Success then
						Hud.showFailure("Craft failed", result.Reason)
					end
				end
			).Parent = listFrame
		end
	end
end

-- Shared by the tab buttons below and by the base stations further down (clicking a Workbench/
-- Welding Station in the world jumps straight to that station's tab via the same path).
local function selectTab(name: string)
	currentTab = name
	for _, sibling in ipairs(tabRow:GetChildren()) do
		if sibling:IsA("TextButton") then
			sibling.BackgroundColor3 = sibling.Text == name and Hud.COLOR.Accent or Hud.COLOR.PanelLight
		end
	end
	renderCraftList()
end

local function makeTabButton(name)
	local button = Hud.new("TextButton", {
		BackgroundColor3 = currentTab == name and Hud.COLOR.Accent or Hud.COLOR.PanelLight,
		Size = UDim2.new(0, 90, 1, 0), -- shrunk from 100 to fit 6 tabs (added Mods) in the same row width
		Font = Enum.Font.SourceSansBold,
		TextColor3 = Hud.COLOR.Text,
		TextSize = 15,
		Text = name,
		Parent = tabRow,
	}, { Hud.corner(6) })
	button.MouseButton1Click:Connect(function()
		selectTab(name)
	end)
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
	for _, name in ipairs(tabNames) do
		makeTabButton(name)
	end
end

----------------------------------------------------------------------
-- Inventory panel — a personal "what do I own, what's equipped, how much do I have" screen.
-- Unlike the Workbench (which only opens from a physical station and is for crafting NEW
-- things), this is viewable from anywhere — it's just a window onto data already sitting in
-- `Hud.profile`. The Equip/Deploy/Undeploy buttons inside it call the same remotes as everywhere
-- else (EquipWeapon, DeployRobot, UndeployRobot, EquipMod via the shared mod picker). Per direct
-- player feedback, none of those four are plot/station gated anymore — changing your loadout
-- works from anywhere in the world, not just standing at the right station. Only actually
-- CRAFTING a new item (CraftItem, ForgeWeapon, and the Forge's other station actions) still
-- requires being physically at the right prop — see ForgeService.lua/CraftingService.lua's own
-- header comments. Also replaces the old cluttered top-left ore breakdown — see the Materials tab below
-- and the trimmed-down currencyFrame near the top of this file.
--
-- Presentation: an icon grid (one square tile per owned item/material) instead of the Workbench's
-- rows — clicking a tile opens a detail panel beside the Inventory showing a bigger image,
-- description, stats, and (for Weapons/Robots) an Equip/Deploy button and mod slots. The
-- Welding Station's own Robots tab is untouched and still uses the row layout (makeRobotRow) —
-- crafting NEW items needs cost text that doesn't fit this tile format, so that stays row-based;
-- only browsing OWNED items here got the icon-grid treatment. The Forge's Weapons tab has no row
-- equivalent at all anymore — it's craft-only (see that section's own header comment); Weapons
-- ownership/equipping lives here in the Inventory exclusively now.
--
-- Icons: drop an ImageLabel, ImageButton, or Decal into ReplicatedStorage.ItemIcons (a plain
-- Folder, see default.project.json), named EXACTLY like the item's key — a weaponKey/robotKey/
-- modKey from CraftingRecipes.lua/ModConfig.lua, or an oreKey from OreConfig.lua (plus the literal
-- names "Scrap"/"Cores" for the two currencies). Only its Image (or Texture, for a Decal) property
-- is read — every other property on that instance is ignored, so it doesn't matter how it's
-- sized/positioned; just get the image onto it via Studio's normal asset picker and name it right.
-- No matching instance yet? The tile falls back to a plain colored square with the item's name in
-- text — "functional before art," same as everywhere else in this project. No code changes needed
-- either way; getItemIcon below just looks the key up fresh every time a tile is built.
--
-- Descriptions live in code, next to each item's other data — CraftingRecipes.lua's
-- Weapons/Robots entries and OreConfig.lua's Ores entries each got a `Description` field this
-- session (ModConfig.lua's mods already had one). Scrap/Cores aren't real "ore" entries anywhere,
-- so their descriptions are just inlined in showInvDetail below instead of a shared config.
----------------------------------------------------------------------

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

ultPicker.close = Hud.new("TextButton", {
	BackgroundColor3 = Hud.COLOR.PanelLight,
	Position = UDim2.new(1, -40, 0, 8),
	Size = UDim2.new(0, 28, 0, 28),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 16,
	Text = "X",
	Parent = ultPicker.frame,
}, { Hud.corner(6) })

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

----------------------------------------------------------------------
-- Forge status HUD — a pity progress bar and a Luck Potion button, both pulled out of the Forge's
-- own Weapons tab per direct feedback. First pass put them in a permanent column under the
-- top-left currency readout; second pass ("currently the pity and all that appears even when the
-- forge UI is not open, please only have the pity appear when the forge UI is open, and make it
-- under the forge GUI please for some cool layout thing, and make the potion close to the forge UI
-- too") moved both to dock directly under `craftFrame` instead, as one row spanning its width, and
-- made them Forge-only — they show up exactly when the Forge's Weapons tab is what's open, hidden
-- for the Workbench/Welding Station and hidden again the moment the menu closes. See
-- `setForgeWidgetsVisible` below (called from `openStationMenu` and `craftCloseButton`).
----------------------------------------------------------------------

local POTION_BUTTON_SIZE = 64

-- Docked under craftFrame's bottom edge (Position 0.5,-200 + Size 0,400 -> bottom sits at
-- One table instead of 4 separate top-level locals: Luau caps a function scope at 200
-- locals and this file's main chunk hit that ceiling. Grouping UI element references costs
-- nothing at runtime and buys back a register per element.
local pity = {}
-- 0.5,+200), 10px gap. potionButton is a fixed 64-wide square on the left; pity.barFrame fills the
-- remaining width to craftFrame's own right edge (0.5,+320) — together they span exactly as wide
-- as the Forge menu above them, not just huddled off to one side of it.
pity.barFrame = Hud.new("Frame", {
	Name = "ForgePity",
	BackgroundColor3 = Hud.COLOR.Panel,
	Position = UDim2.new(0.5, -320 + POTION_BUTTON_SIZE + 10, 0.5, 220),
	Size = UDim2.new(0, 640 - POTION_BUTTON_SIZE - 10, 0, 44),
	Visible = false,
	Parent = Hud.screenGui,
}, { Hud.corner(8), Hud.stroke() })

pity.caption = Hud.new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 10, 0, 4),
	Size = UDim2.new(1, -20, 0, 16),
	Font = Enum.Font.Code,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Hud.COLOR.Muted,
	TextSize = 13,
	Text = "Forge Pity: 0 / 0",
	Parent = pity.barFrame,
})

pity.track = Hud.new("Frame", {
	BackgroundColor3 = Hud.COLOR.PanelLight,
	Position = UDim2.new(0, 10, 0, 24),
	Size = UDim2.new(1, -20, 0, 12),
	Parent = pity.barFrame,
}, { Hud.corner(4) })

pity.fill = Hud.new("Frame", {
	BackgroundColor3 = Hud.COLOR.Accent,
	Size = UDim2.new(0, 0, 1, 0),
	Parent = pity.track,
}, { Hud.corner(4) })

-- Assigns into the `local refreshPityBar` forward-declared up in the Forge tab section, so the
-- Forge roll button (defined earlier in the file) can call this the instant a roll lands rather
-- than waiting on the next InventoryUpdate patch — see that section's comment for why the forward
-- declaration exists at all.
refreshPityBar = function()
	local counter = Hud.profile.ForgePityCounter or 0
	local threshold = ForgeConfig.Pity.Threshold
	pity.caption.Text = ("Forge Pity: %d / %d (%s+)"):format(counter, threshold, ForgeConfig.Pity.MinRarity)
	local ratio = threshold > 0 and math.clamp(counter / threshold, 0, 1) or 0
	pity.fill.Size = UDim2.new(ratio, 0, 1, 0)
end
refreshPityBar()

local potionButton = Hud.new("ImageButton", {
	Name = "LuckPotionButton",
	BackgroundColor3 = Hud.COLOR.PanelLight,
	AutoButtonColor = false,
	Image = "",
	ScaleType = Enum.ScaleType.Fit,
	Position = UDim2.new(0.5, -320, 0.5, 210),
	Size = UDim2.new(0, POTION_BUTTON_SIZE, 0, POTION_BUTTON_SIZE),
	Visible = false,
	Parent = Hud.screenGui,
}, { Hud.corner(8), Hud.stroke() })

-- Same "no icon yet? fall back to plain text" pattern as makeItemTile's placeholder — looked up
-- via Hud.getItemIcon("LuckPotion"), so dropping an ImageLabel/ImageButton/Decal named exactly
-- "LuckPotion" into ReplicatedStorage.ItemIcons picks it up automatically, same convention as
-- every other icon in this project.
local potionPlaceholderLabel = Hud.new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 3, 0, 3),
	Size = UDim2.new(1, -6, 1, -6),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Hud.COLOR.Muted,
	TextSize = 12,
	TextWrapped = true,
	Text = "Luck\nPotion",
	Parent = potionButton,
})

local potionBadge = Hud.new("TextLabel", {
	BackgroundColor3 = Hud.COLOR.Panel,
	Position = UDim2.new(1, -24, 1, -18),
	Size = UDim2.new(0, 22, 0, 16),
	Font = Enum.Font.Code,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 11,
	Text = "0",
	Parent = potionButton,
}, { Hud.corner(4) })

-- Assigns into the `local refreshPotionButton` forward-declared up in the Forge tab section, same
-- reason as refreshPityBar above.
refreshPotionButton = function()
	local icon = Hud.getItemIcon("LuckPotion")
	potionButton.Image = icon or ""
	potionPlaceholderLabel.Visible = not icon
	potionBadge.Text = tostring(Hud.profile.LuckPotions or 0)
	potionButton.BackgroundColor3 = forgeUsePotion and Hud.COLOR.AccentDark or Hud.COLOR.PanelLight
end
refreshPotionButton()

potionButton.MouseButton1Click:Connect(function()
	if (Hud.profile.LuckPotions or 0) <= 0 then
		return
	end
	forgeUsePotion = not forgeUsePotion
	refreshPotionButton() -- the button's own highlight is the only thing that needs to react to this
end)

-- Shows/hides both widgets together — called from openStationMenu (true only when the station
-- just opened is specifically the Forge, false for Workbench/Welding) and from craftCloseButton's
-- handler (always false, whichever menu was open). Kept as one function so the two widgets can
-- never end up toggled independently by a future edit that only remembers to update one of them.
local function setForgeWidgetsVisible(visible: boolean)
	pity.barFrame.Visible = visible
	potionButton.Visible = visible
	-- The docked row can sit low enough (on shorter viewports) to overlap the bottom action row
	-- (Inventory/Start Defense/etc.) — hide that row while the Forge ones are up, restore it the
	-- moment they're hidden again, so the two never visually collide.
	actionRow.Visible = not visible
end

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

-- Same Hud.screenGui-sibling popup pattern as ModPicker.lua's, just a grid of ore tiles (reusing
-- makeItemTile/getItemIcon from the Inventory panel section) instead of a list of makeRow entries —
-- this IS "a GUI directly into your ore inventory," per the ask.
local orePickerFrame = Hud.new("Frame", {
	Name = "OrePicker",
	BackgroundColor3 = Hud.COLOR.Panel,
	Position = UDim2.new(0.5, -170, 0.5, -180),
	Size = UDim2.new(0, 340, 0, 360),
	Visible = false,
	ZIndex = 5,
	Parent = Hud.screenGui,
}, { Hud.corner(10), Hud.stroke() })

Hud.new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 10),
	Size = UDim2.new(1, -60, 0, 24),
	Font = Enum.Font.SourceSansBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 18,
	Text = "Select Ore",
	Parent = orePickerFrame,
})

local orePickerClose = Hud.new("TextButton", {
	BackgroundColor3 = Hud.COLOR.PanelLight,
	Position = UDim2.new(1, -40, 0, 8),
	Size = UDim2.new(0, 28, 0, 28),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 16,
	Text = "X",
	Parent = orePickerFrame,
}, { Hud.corner(6) })

local orePickerList = Hud.new("ScrollingFrame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 44),
	Size = UDim2.new(1, -24, 1, -56),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	Parent = orePickerFrame,
}, { Hud.new("UIGridLayout", { CellSize = UDim2.new(0, TILE_SIZE, 0, TILE_SIZE), CellPadding = UDim2.new(0, 8, 0, 8) }) })

local function closeOrePicker()
	orePickerFrame.Visible = false
end
orePickerClose.MouseButton1Click:Connect(closeOrePicker)

local function selectOreForSmelt(oreKey: string)
	local oreData = RefinedOreConfig.Ores[oreKey]
	smeltSelectedOreKey = oreKey
	smeltQuantity = oreData.RefineRatio -- smallest legal batch to start with
	closeOrePicker()
	renderCraftList()
end

-- Only lists ores you actually own AT LEAST one legal batch of (owned >= RefineRatio) — picking
-- one you can't afford a single unit of would just land you straight back on an empty stepper.
local function renderOrePickerList()
	for _, child in ipairs(orePickerList:GetChildren()) do
		if child:IsA("ImageButton") then
			child:Destroy()
		end
	end
	for _, oreKey in ipairs(SMELT_ORE_ORDER) do
		local oreData = RefinedOreConfig.Ores[oreKey]
		local owned = (Hud.profile.OreCounts or {})[oreKey] or 0
		if owned >= oreData.RefineRatio then
			local oreDisplayName = OreConfig.Ores[oreKey].DisplayName
			makeItemTile(oreKey, oreDisplayName, ("x%d"):format(owned), oreKey == smeltSelectedOreKey, function()
				selectOreForSmelt(oreKey)
			end).Parent = orePickerList
		end
	end
end

local function openOrePicker()
	renderOrePickerList()
	orePickerFrame.Visible = true
end

local SMELT_SQUARE_SIZE = 260

-- Assigns into the `local renderSmeltingTab` forward-declared up in the Forge tab section — see
-- that comment for why. Builds one square panel (per the exact "background that is like a square"
-- ask) as the Smelting tab's only listFrame child; state picked by Hud.profile.SmeltJob (server-
-- authoritative, wins over everything) then smeltSelectedOreKey (client-only, pending a click).
renderSmeltingTab = function()
	local outer = Hud.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, SMELT_SQUARE_SIZE + 20),
		Parent = listFrame,
	})

	local square = Hud.new("Frame", {
		BackgroundColor3 = Hud.COLOR.PanelLight,
		Position = UDim2.new(0.5, -SMELT_SQUARE_SIZE / 2, 0, 0),
		Size = UDim2.new(0, SMELT_SQUARE_SIZE, 0, SMELT_SQUARE_SIZE),
		Parent = outer,
	}, { Hud.corner(10), Hud.stroke() })

	local job = Hud.profile.SmeltJob

	if job then
		local oreDisplayName = (OreConfig.Ores[job.OreKey] and OreConfig.Ores[job.OreKey].DisplayName) or job.OreKey
		local refinedInfo = RefinedOreConfig.ByRefinedKey[job.RefinedKey]
		local refinedDisplayName = refinedInfo and refinedInfo.DisplayName or job.RefinedKey

		Hud.new("ImageLabel", {
			BackgroundTransparency = 1,
			Image = Hud.getItemIcon(job.RefinedKey) or Hud.getItemIcon(job.OreKey) or "",
			ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.new(0.5, -40, 0, 16),
			Size = UDim2.new(0, 80, 0, 80),
			Parent = square,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 104),
			Size = UDim2.new(1, -24, 0, 20),
			Font = Enum.Font.SourceSansBold,
			TextColor3 = Hud.COLOR.Text,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = ("Smelting %d %s"):format(job.Quantity, oreDisplayName),
			Parent = square,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 126),
			Size = UDim2.new(1, -24, 0, 18),
			Font = Enum.Font.Code,
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = ("-> %d %s"):format(job.RefinedAmount, refinedDisplayName),
			Parent = square,
		})

		-- Re-derives the batch's original duration from the same shared formula rather than storing
		-- it separately on the job — remaining/duration then gives a 0..1 progress ratio directly.
		local duration = math.max(RefinedOreConfig.ComputeSmeltSeconds(job.Quantity), 1)
		local remaining = job.FinishTime - os.time()
		local ratio = math.clamp(1 - (remaining / duration), 0, 1)

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 152),
			Size = UDim2.new(1, -24, 0, 20),
			Font = Enum.Font.Code,
			TextColor3 = Hud.COLOR.Text,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = remaining > 0 and ("Ready in " .. formatDuration(remaining)) or "Finishing up...",
			Parent = square,
		})

		local track = Hud.new("Frame", {
			BackgroundColor3 = Hud.COLOR.Panel,
			Position = UDim2.new(0, 12, 0, 176),
			Size = UDim2.new(1, -24, 0, 12),
			Parent = square,
		}, { Hud.corner(4) })
		Hud.new("Frame", {
			BackgroundColor3 = Hud.COLOR.Accent,
			Size = UDim2.new(ratio, 0, 1, 0),
			Parent = track,
		}, { Hud.corner(4) })

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 200),
			Size = UDim2.new(1, -24, 0, 40),
			Font = Enum.Font.Code,
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "One smelt at a time — the next batch can start the moment this one finishes.",
			Parent = square,
		})
	elseif smeltSelectedOreKey then
		local oreData = RefinedOreConfig.Ores[smeltSelectedOreKey]
		local refinedInfo = RefinedOreConfig.ByRefinedKey[oreData.RefinedKey]
		local oreDisplayName = OreConfig.Ores[smeltSelectedOreKey].DisplayName
		local owned = (Hud.profile.OreCounts or {})[smeltSelectedOreKey] or 0
		local maxQuantity = math.max(math.floor(owned / oreData.RefineRatio) * oreData.RefineRatio, oreData.RefineRatio)
		smeltQuantity = math.clamp(smeltQuantity, oreData.RefineRatio, maxQuantity)

		local iconButton = Hud.new("ImageButton", {
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Image = Hud.getItemIcon(smeltSelectedOreKey) or "",
			ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.new(0.5, -32, 0, 8),
			Size = UDim2.new(0, 64, 0, 64),
			Parent = square,
		})
		iconButton.MouseButton1Click:Connect(openOrePicker) -- click the icon again to change ore

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 76),
			Size = UDim2.new(1, -24, 0, 18),
			Font = Enum.Font.SourceSansBold,
			TextColor3 = Hud.COLOR.Text,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = ("%s (owned %d)"):format(oreDisplayName, owned),
			Parent = square,
		})

		-- Quantity readout on the left, a small Reset (back down to one batch) on the right, sharing
		-- one row so the four bulk-add buttons below get their own row instead of fighting for space.
		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 96),
			Size = UDim2.new(0, 130, 0, 22),
			Font = Enum.Font.Code,
			TextColor3 = Hud.COLOR.Text,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = ("%d ore"):format(smeltQuantity),
			Parent = square,
		})

		local resetButton = Hud.new("TextButton", {
			BackgroundColor3 = Hud.COLOR.PanelLight,
			Position = UDim2.new(1, -78, 0, 97),
			Size = UDim2.new(0, 66, 0, 20),
			Font = Enum.Font.Code,
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 12,
			Text = "Reset",
			Parent = square,
		}, { Hud.corner(4) })
		resetButton.MouseButton1Click:Connect(function()
			smeltQuantity = oreData.RefineRatio
			renderCraftList()
		end)

		-- Bulk-add row — "+1"/"+10"/"+100"/"MAX" ADD BATCHES (RefineRatio-sized steps), not raw ore
		-- 1-at-a-time, so the quantity landed on is always a legal multiple without any rounding —
		-- e.g. "+10" on a 3:1 ore adds 30 raw ore (10 batches), not 10 raw ore. Much faster than the
		-- old lone +/- stepper for stocking up a big batch.
		local stepButtonsRow = Hud.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 122),
			Size = UDim2.new(1, -24, 0, 28),
			Parent = square,
		}, { Hud.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}) })

		local function makeBulkAddButton(label: string, batches: number?)
			local button = Hud.new("TextButton", {
				BackgroundColor3 = Hud.COLOR.PanelLight,
				Size = UDim2.new(0, 52, 1, 0),
				Font = Enum.Font.SourceSansBold,
				TextColor3 = Hud.COLOR.Text,
				TextSize = 14,
				Text = label,
				Parent = stepButtonsRow,
			}, { Hud.corner(6) })
			button.MouseButton1Click:Connect(function()
				if batches then
					smeltQuantity = math.min(smeltQuantity + batches * oreData.RefineRatio, maxQuantity)
				else
					smeltQuantity = maxQuantity -- MAX
				end
				renderCraftList()
			end)
			return button
		end

		makeBulkAddButton("+1", 1)
		makeBulkAddButton("+10", 10)
		makeBulkAddButton("+100", 100)
		makeBulkAddButton("MAX", nil)

		local estSeconds = RefinedOreConfig.ComputeSmeltSeconds(smeltQuantity)
		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 154),
			Size = UDim2.new(1, -24, 0, 18),
			Font = Enum.Font.Code,
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = ("-> %d %s · %s"):format(
				smeltQuantity / oreData.RefineRatio,
				refinedInfo.DisplayName,
				formatDuration(estSeconds)
			),
			Parent = square,
		})

		-- The "button [that] would allow you to smelt the ore" — only ever appears once an ore is
		-- actually selected, per the ask.
		local smeltButton = Hud.new("TextButton", {
			BackgroundColor3 = Hud.COLOR.Accent,
			Position = UDim2.new(0.5, -60, 0, 180),
			Size = UDim2.new(0, 120, 0, 36),
			Font = Enum.Font.SourceSansBold,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 15,
			Text = "Smelt",
			Parent = square,
		}, { Hud.corner(6) })
		smeltButton.MouseButton1Click:Connect(function()
			local oreKey, quantity = smeltSelectedOreKey, smeltQuantity
			local result = Remotes.StartSmelt:InvokeServer(oreKey, quantity)
			if not result.Success then
				Hud.showFailure("Start smelt failed", result.Reason)
			else
				smeltSelectedOreKey = nil
				smeltQuantity = 0
				renderCraftList()
			end
		end)
	else
		-- State 1: nothing picked yet — "on the middle of it you would have a clickable icon where
		-- it would [open] a gui directly into your ore inventory."
		local icon = Hud.getItemIcon("Smelting")
		local iconButton = Hud.new("ImageButton", {
			BackgroundColor3 = Hud.COLOR.Panel,
			AutoButtonColor = false,
			Image = icon or "",
			ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.new(0.5, -48, 0, 60),
			Size = UDim2.new(0, 96, 0, 96),
			Parent = square,
		}, { Hud.corner(8), Hud.stroke() })

		if not icon then
			Hud.new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 4, 0, 4),
				Size = UDim2.new(1, -8, 1, -8),
				Font = Enum.Font.SourceSansBold,
				TextColor3 = Hud.COLOR.Muted,
				TextSize = 13,
				TextWrapped = true,
				Text = "Select\nOre",
				Parent = iconButton,
			})
		end
		iconButton.MouseButton1Click:Connect(openOrePicker)

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 168),
			Size = UDim2.new(1, -24, 0, 20),
			Font = Enum.Font.SourceSansBold,
			TextColor3 = Hud.COLOR.Text,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "Select Ore to Smelt",
			Parent = square,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 190),
			Size = UDim2.new(1, -24, 0, 40),
			Font = Enum.Font.Code,
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "Click the icon to open your ore inventory and pick something to refine.",
			Parent = square,
		})
	end
end

-- Keeps the countdown/progress bar live while the Smelting tab is actually open and a job is
-- running — InventoryUpdate patches only arrive when a job starts or finishes, not every second
-- in between, so without this the bar would sit frozen until the next patch happened to land.
task.spawn(function()
	while true do
		task.wait(1)
		-- Decode counts down in real time like smelting does; InventoryUpdate only arrives when a
		-- job starts or finishes, not every second.
		if craftFrame.Visible and currentTab == "Decode" and Hud.profile.DecodeJob then
			renderCraftList()
		end
		if craftFrame.Visible and currentTab == "Smelting" and Hud.profile.SmeltJob then
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
-- top-left currency readout (what they own) and the wave panel (how the current fight is going).
--
-- Health lived only inside the raid panel before this, so outside a raid there was no HP readout at
-- all — despite mine hazards, lava and outpost fights all being able to kill you.
--
-- The Research row is a button: clicking it opens the requirements popup below. That is the answer
-- to "what do I need for the next tier" — the one number that gates base size, station tier, turret
-- slots and turret levels (see ResearchConfig.lua).
----------------------------------------------------------------------

local statusPanel = Hud.new("Frame", {
	Name = "Status",
	BackgroundColor3 = Hud.COLOR.Panel,
	Position = UDim2.new(0, 16, 1, -16),
	AnchorPoint = Vector2.new(0, 1),
	Size = UDim2.new(0, 240, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Parent = Hud.screenGui,
}, {
	Hud.corner(8), Hud.stroke(),
	Hud.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	Hud.new("UIPadding", {
		PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
	}),
})

-- Small labelled bar, reused for Health and Stamina so the two stay visually identical.
local function makeStatusBar(order: number, label: string, fillColor: Color3, dimmed: boolean?)
	local holder = Hud.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = order,
		Parent = statusPanel,
	})
	local caption = Hud.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 14),
		Font = Enum.Font.SourceSansBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = dimmed and Hud.COLOR.Muted or Hud.COLOR.Text,
		TextSize = 13,
		Text = label,
		Parent = holder,
	})
	local track = Hud.new("Frame", {
		BackgroundColor3 = Hud.COLOR.PanelLight,
		Position = UDim2.new(0, 0, 0, 16),
		Size = UDim2.new(1, 0, 0, 12),
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

local statusHealthCaption, statusHealthFill = makeStatusBar(1, "Health", Hud.COLOR.Good)

-- Stamina is a PLACEHOLDER. There is no stamina or dash system in this codebase yet — no input
-- handling, no regen loop, no server validation — so this is a reserved, visibly-disabled slot
-- rather than a bar that lies about a stat nothing drives. Wire it up when dashing is built.
local _staminaCaption, _staminaFill = makeStatusBar(2, "Stamina — not built yet", Hud.COLOR.Muted, true)

-- One table instead of 5 separate top-level locals: Luau caps a function scope at 200
-- locals and this file's main chunk hit that ceiling. Grouping UI element references costs
-- nothing at runtime and buys back a register per element.
local research = {}
research.button = Hud.new("TextButton", {
	BackgroundColor3 = Hud.COLOR.PanelLight,
	Size = UDim2.new(1, 0, 0, 30),
	LayoutOrder = 3,
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Hud.COLOR.Accent,
	TextSize = 14,
	Text = "Research Tier 1",
	Parent = statusPanel,
}, { Hud.corner(6) })

----------------------------------------------------------------------
-- Research requirements popup — what the next tier needs, and which parts you already have.
--
-- Rendered from ResearchConfig.GetNextTierRequirements, the SAME function BaseService's
-- UpgradeResearch handler uses to decide whether to allow the claim — so what is shown here and
-- what is actually enforced can never drift apart.
----------------------------------------------------------------------

research.frame = Hud.new("Frame", {
	Name = "ResearchPanel",
	BackgroundColor3 = Hud.COLOR.Panel,
	Position = UDim2.new(0, 16, 1, -160),
	AnchorPoint = Vector2.new(0, 1),
	Size = UDim2.new(0, 360, 0, 340),
	Visible = false,
	ZIndex = 6,
	Parent = Hud.screenGui,
}, { Hud.corner(10), Hud.stroke() })

research.title = Hud.new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 10),
	Size = UDim2.new(1, -60, 0, 24),
	Font = Enum.Font.SourceSansBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 18,
	Text = "Research",
	Parent = research.frame,
})

research.close = Hud.new("TextButton", {
	BackgroundColor3 = Hud.COLOR.PanelLight,
	Position = UDim2.new(1, -40, 0, 8),
	Size = UDim2.new(0, 28, 0, 28),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 16,
	Text = "X",
	Parent = research.frame,
}, { Hud.corner(6) })

research.list = Hud.new("ScrollingFrame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 44),
	Size = UDim2.new(1, -24, 1, -56),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	Parent = research.frame,
}, { Hud.new("UIListLayout", { Padding = UDim.new(0, 6) }) })

research.close.MouseButton1Click:Connect(function()
	research.frame.Visible = false
end)

local refreshResearchButton -- forward-declared; renderResearchPanel refreshes it after a claim

-- Kept current by the InventoryUpdate listener, so the panel updates live as you gather materials
-- rather than going stale the moment you opened it.
local function renderResearchPanel()
	for _, child in ipairs(research.list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local currentTier, currentIndex = ResearchConfig.GetTier(Hud.profile.ResearchTier or 1)
	research.title.Text = ("Research Tier %d"):format(currentIndex)

	Hud.makeRow(
		currentTier.Name,
		("Wall %d HP · %d turret slots · %d-stud base"):format(
			currentTier.WallHP,
			TurretConfig.GetSlotCount(currentIndex),
			currentTier.FootprintHalfSize.X * 2),
		"Current",
		function() end
	).Parent = research.list

	local req = ResearchConfig.GetNextTierRequirements(Hud.profile)
	if not req then
		Hud.makeRow("Fully researched", "You are at the highest tier there is.", "Max", function() end).Parent = research.list
		return
	end

	local nextTier = ResearchConfig.Tiers[req.TierIndex]
	Hud.makeRow(
		("Next: %s (Tier %d)"):format(req.Name, req.TierIndex),
		("Wall %d HP · %d turret slots · %d-stud base"):format(
			nextTier.WallHP,
			TurretConfig.GetSlotCount(req.TierIndex),
			nextTier.FootprintHalfSize.X * 2),
		req.CanClaim and "Claim" or "Locked",
		function()
			-- Claimed at the Workbench (server-side gate), so this can legitimately fail even when
			-- every requirement is met — showFailure explains which.
			local result = Remotes.UpgradeResearch:InvokeServer()
			if not result.Success then
				Hud.showFailure("Research failed", result.Reason)
			else
				Hud.showToast(("Research Tier %d — your base has been rebuilt."):format(result.ResearchTier), 4)
				renderResearchPanel()
				refreshResearchButton()
			end
		end
	).Parent = research.list

	-- One row per requirement, each showing have-vs-needed, so it is obvious WHICH part is missing
	-- rather than a flat "not enough resources".
	Hud.makeRow(
		("Clear Wave %d"):format(req.RequiredWave),
		("Best wave so far: %d"):format(req.HighestWave),
		req.WaveMet and "Done" or "Missing",
		function() end
	).Parent = research.list

	if req.CoreRequirement then
		local core = req.CoreRequirement
		Hud.makeRow(
			("%s x%d"):format(core.Key, core.Needed),
			("You have %d — drops from base-defense boss waves"):format(core.Have),
			core.Met and "Done" or "Missing",
			function() end
		).Parent = research.list
	end

	for _, entry in ipairs(req.Cost) do
		local displayName = Wallet.DisplayName(entry.Key)
		Hud.makeRow(
			("%s x%d"):format(displayName, entry.Needed),
			("You have %d"):format(entry.Have),
			entry.Met and "Done" or "Missing",
			function() end
		).Parent = research.list
	end
end

research.button.MouseButton1Click:Connect(function()
	research.frame.Visible = not research.frame.Visible
	if research.frame.Visible then
		renderResearchPanel()
	end
end)

-- Shows the tier on the button itself, and flags when a tier is actually claimable so the player
-- does not have to open the panel to find out.
refreshResearchButton = function()
	local currentTier, currentIndex = ResearchConfig.GetTier(Hud.profile.ResearchTier or 1)
	local req = ResearchConfig.GetNextTierRequirements(Hud.profile)
	if req and req.CanClaim then
		research.button.Text = ("Research T%d — UPGRADE READY"):format(currentIndex)
		research.button.TextColor3 = Hud.COLOR.Good
	else
		research.button.Text = ("Research T%d — %s"):format(currentIndex, currentTier.Name)
		research.button.TextColor3 = Hud.COLOR.Accent
	end
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
	-- Two readouts, one source: the raid panel's bar (visible only mid-raid) and the always-on
	-- status panel's. Health replicates on its own, so both are driven straight off the Humanoid
	-- rather than from any remote payload.
	raidHealthFill.Size = UDim2.new(pct, 0, 1, 0)
	raidHealthCaption.Text = ("Your HP: %d / %d"):format(math.ceil(humanoid.Health), math.ceil(playerMaxHealth))
	statusHealthFill.Size = UDim2.new(pct, 0, 1, 0)
	statusHealthFill.BackgroundColor3 = (pct <= 0.3) and Hud.COLOR.Bad or Hud.COLOR.Good
	statusHealthCaption.Text = ("Health  %d / %d"):format(math.ceil(humanoid.Health), math.ceil(playerMaxHealth))
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

-- One table instead of 5 separate top-level locals: Luau caps a function scope at 200
-- locals and this file's main chunk hit that ceiling. Grouping UI element references costs
-- nothing at runtime and buys back a register per element.
local shopUI = {}
shopUI.frame = Hud.new("Frame", {
	Name = "ShopMenu",
	BackgroundColor3 = Hud.COLOR.Panel,
	Position = UDim2.new(0.5, -200, 0.5, -190),
	Size = UDim2.new(0, 400, 0, 388),
	Visible = false,
	Parent = Hud.screenGui,
}, { Hud.corner(10), Hud.stroke() })

Hud.new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 10),
	Size = UDim2.new(1, -60, 0, 24),
	Font = Enum.Font.SourceSansBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 18,
	Text = "Outpost Shop",
	Parent = shopUI.frame,
})

shopUI.closeButton = Hud.new("TextButton", {
	BackgroundColor3 = Hud.COLOR.PanelLight,
	Position = UDim2.new(1, -40, 0, 8),
	Size = UDim2.new(0, 28, 0, 28),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 16,
	Text = "X",
	Parent = shopUI.frame,
}, { Hud.corner(6) })
shopUI.closeButton.MouseButton1Click:Connect(function()
	shopUI.frame.Visible = false
end)

shopUI.listFrame = Hud.new("ScrollingFrame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 44),
	Size = UDim2.new(1, -24, 1, -100),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	Parent = shopUI.frame,
}, { Hud.new("UIListLayout", { Padding = UDim.new(0, 6) }) })

-- Expedition Shop nodes are one-time — if you can't (or don't want to) buy anything, Skip
-- destroys the node outright and lets the queue move on rather than leaving you stuck standing
-- in front of a shop you can't use.
shopUI.skipButton = Hud.new("TextButton", {
	BackgroundColor3 = Hud.COLOR.PanelLight,
	Position = UDim2.new(0, 12, 1, -40),
	Size = UDim2.new(1, -24, 0, 32),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 15,
	Text = "Skip — move to the next node",
	Parent = shopUI.frame,
}, { Hud.corner(6) })

local currentShopNode = nil -- set right before the Shop panel opens, see node setup below
shopUI.nodeDestroyingConn = nil -- auto-closes the panel if the node vanishes out from under it (bought, skipped, or otherwise)

local function renderShopList()
	for _, child in ipairs(shopUI.listFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for itemKey, item in pairs(NodeConfig.ShopCatalog) do
		Hud.makeRow(
			item.DisplayName,
			("%d %s"):format(item.CostAmount, item.CostCurrency),
			"Buy",
			function()
				local result = Remotes.BuyOutpostItem:InvokeServer(currentShopNode, itemKey)
				if not result.Success then
					Hud.showFailure("Purchase failed", result.Reason)
				else
					shopUI.frame.Visible = false -- expedition shop nodes are consumed on purchase — nothing left to browse
				end
			end
		).Parent = shopUI.listFrame
	end
end

shopUI.skipButton.MouseButton1Click:Connect(function()
	if currentShopNode then
		Remotes.SkipNode:FireServer(currentShopNode)
	end
	shopUI.frame.Visible = false
end)

----------------------------------------------------------------------
-- Bottom action buttons
----------------------------------------------------------------------

-- Assigns into the `local actionRow` forward-declared up in the Forge tab section — see that
-- comment for why setForgeWidgetsVisible needs to reach this row before it technically exists yet.
actionRow = Hud.new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.new(0, 550, 0, 44), -- Inventory + Defend + Return to Base + Recall, at most
	Parent = Hud.screenGui,
}, { Hud.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center }) })

-- No standalone "Workbench" toggle button anymore — per-station gating (openStationMenu, near
-- the base-station setup further down) is the only way this menu opens now, so there's nothing
-- generic left to toggle from here. craftCloseButton (declared alongside craftFrame above) is the
-- only way to close it.
craftCloseButton.MouseButton1Click:Connect(function()
	craftFrame.Visible = false
	setForgeWidgetsVisible(false) -- no-op if a non-Forge station was open, harmless either way
	ModPicker.closeModPicker() -- don't leave the mod picker orphaned open behind a closed Workbench
end)

-- Inventory, unlike the Workbench, isn't gated to a physical station — it's just a view onto
-- `Hud.profile` — so it gets a normal always-available button here instead.
inv.openButton = Hud.new("TextButton", {
	BackgroundColor3 = Hud.COLOR.PanelLight,
	Size = UDim2.new(0, 130, 1, 0),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 16,
	Text = "Inventory",
	Parent = actionRow,
}, { Hud.corner(8), Hud.stroke() })
inv.openButton.MouseButton1Click:Connect(openInventory)

local defendButton = Hud.new("TextButton", {
	BackgroundColor3 = Hud.COLOR.Accent,
	Size = UDim2.new(0, 140, 1, 0),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 16,
	Text = "Start Defense",
	Parent = actionRow,
}, { Hud.corner(8) })
-- Doubles as the stop button rather than adding a second one — the action row is already tight
-- (and gets hidden wholesale while the Forge is open). Before StopWave existed this just no-op'd
-- while a run was active, so there was no way to end a run short of losing or resetting your
-- character; that's also what turned an unkillable enemy into an unrecoverable hang.
defendButton.MouseButton1Click:Connect(function()
	if runActive then
		Remotes.StopWave:FireServer()
	else
		Remotes.StartWave:FireServer()
	end
end)

-- Only shown while an expedition is actually active (see the CurrentSlotId watcher below) —
-- ends the run for everyone on the shared queue, heals you to full, and keeps whatever you've
-- already looted (rewards are granted the instant each node resolves, not saved up for an
-- "end of run" payout, so there's nothing separate to preserve here).
local returnHomeButton = Hud.new("TextButton", {
	BackgroundColor3 = Hud.COLOR.Bad,
	Size = UDim2.new(0, 130, 1, 0),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 15,
	Text = "Return to Base",
	Visible = false,
	Parent = actionRow,
}, { Hud.corner(8) })
returnHomeButton.MouseButton1Click:Connect(function()
	Remotes.EndExpedition:FireServer()
end)

-- Only shown while DepthUpdate (fired from MineShaftService's hazard loop) reports the player is
-- at least one level down in the quarry — there's no climb-out mechanic, so once you're a few
-- levels down this is the only way back short of finding a wall to walk into. Respawns at a
-- normal SpawnLocation, full health, same as Return to Base — see RecallFromMine's comment.
local recallButton = Hud.new("TextButton", {
	BackgroundColor3 = Hud.COLOR.Bad,
	Size = UDim2.new(0, 100, 1, 0),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 15,
	Text = "Recall",
	Visible = false,
	Parent = actionRow,
}, { Hud.corner(8) })
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
	Hud.MergeProfile(patch)
	refreshCurrency()
	refreshPityBar()
	refreshPotionButton()
	if craftFrame.Visible then
		renderCraftList()
	end
	if inv.frame.Visible then
		renderInvList()
		refreshInvDetailIfShowing()
	end
	-- Keeps an open turret slot panel current: upgrading a turret changes its level/stats, and the
	-- Cores spent change what the next upgrade costs. Place/Unplace close the panel themselves
	-- (the slot's contents moved), so this is really about Upgrade re-rendering in place.
	if turretPanel.frame.Visible then
		renderTurretPanel()
	end
	if ultPicker.frame.Visible then
		renderUltPickerList()
	end
	-- The Research claim depends on Scrap/ore/Cores/HighestWave, all of which arrive through this
	-- same patch — so the button's "UPGRADE READY" state and the open requirements popup both have
	-- to re-evaluate here rather than only when reopened.
	refreshResearchButton()
	if research.frame.Visible then
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

-- What came out of a case. Its own remote rather than a generic toast so the rarity can be
-- announced properly — the moment a case opens is the whole payoff of the system.
Remotes.CaseOpened.OnClientEvent:Connect(function(caseKey: string, reward)
	if not reward then
		return
	end
	local name = Wallet.DisplayName(reward.Key)
	if reward.Kind == "Ultimate" then
		local data = UltimateConfig.Mods[reward.Key]
		name = data and data.DisplayName or reward.Key
		if reward.Duplicate then
			Hud.showToast(("MYTHICAL — %s (already owned) · +%d Contraband instead"):format(
				name, reward.ConsolationContraband or 0), 6)
			return
		end
		Hud.showToast(("MYTHICAL — %s unlocked! Equip it in the Inventory's Ultimate slot."):format(name), 7)
		return
	end
	if reward.Kind == "WeaponFamily" then
		local family = WeaponFamilyConfig.Families[reward.Key]
		name = family and family.DisplayName or reward.Key
		if reward.Duplicate then
			Hud.showToast(("LEGENDARY — %s blueprint (already unlocked) · +%d Contraband instead"):format(
				name, reward.ConsolationContraband or 0), 6)
			return
		end
		-- Names the station, because the reward is not an item you can go and look at: it is a tab
		-- that has quietly appeared somewhere else entirely.
		Hud.showToast(("LEGENDARY — %s unlocked! Forge them at the Forge's Weapons tab."):format(name), 7)
		return
	end
	Hud.showToast(("%s — %d %s"):format(reward.Rarity, reward.Amount or 1, name), 5)
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
		recallButton.Visible = false
		return
	end

	depthPanel.Visible = true
	-- Visible any time you're anywhere in the mine, including right at the Depth-0 surface floor
	-- — not just once you've actually descended. It's the one guaranteed way back to base, so it
	-- should be there the moment you're in the mine at all, not gated behind digging first.
	recallButton.Visible = true
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
		-- The button is a toggle now, so it has to say what CLICKING it does, not what's happening.
		defendButton.Text = "Stop Defense"
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
		defendButton.Text = "Stopping…"
		waveLabel.Text = "Stopping after this wave…"
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
			currentShopNode = node
			shopUI.frame.Visible = true
			renderShopList()

			if shopUI.nodeDestroyingConn then
				shopUI.nodeDestroyingConn:Disconnect()
			end
			shopUI.nodeDestroyingConn = node.Destroying:Connect(function()
				if currentShopNode == node then
					shopUI.frame.Visible = false
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
	rebuildTabs(stationData.Tabs)
	craftTitleLabel.Text = stationData.DisplayName
	craftFrame.Visible = true
	selectTab(stationData.DefaultTab)
	setForgeWidgetsVisible(stationData == StationConfig.Types.Forge)
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
-- Turret slots — clicking one in the world opens the turret panel (see openTurretPanel). Tagged
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
		openTurretPanel(slotIndex)
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
		refreshPityBar()
		refreshPotionButton()
		refreshResearchButton()
	end
end)
