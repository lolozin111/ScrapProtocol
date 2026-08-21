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

local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)
local OreConfig = require(ReplicatedStorage.Shared.OreConfig)
local NodeConfig = require(ReplicatedStorage.Shared.NodeConfig)

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
	HighestWave = 0,
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
	Position = UDim2.new(0.5, -220, 0.5, -180),
	Size = UDim2.new(0, 440, 0, 360),
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

local function renderCraftList()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
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
			makeRow(
				("T%d  %s"):format(recipe.Tier, recipe.DisplayName),
				owned and "Owned" or costString(recipe.Cost),
				owned and "Owned" or "Craft",
				function()
					if owned then return end
					local result = Remotes.CraftItem:InvokeServer("Weapons", key)
					if not result.Success then
						warn("[HUD] Craft failed:", result.Reason)
					end
				end
			).Parent = listFrame
		else
			local ownedCount = profile.CraftedRobots[key] or 0
			makeRow(
				("T%d  %s"):format(recipe.Tier, recipe.DisplayName),
				("%s · owned %d"):format(costString(recipe.Cost), ownedCount),
				ownedCount > 0 and "Deploy" or "Craft",
				function()
					if ownedCount > 0 then
						local result = Remotes.DeployRobot:InvokeServer(key)
						if not result.Success then
							warn("[HUD] Deploy failed:", result.Reason)
						end
					else
						local result = Remotes.CraftItem:InvokeServer("Robots", key)
						if not result.Success then
							warn("[HUD] Craft failed:", result.Reason)
						end
					end
				end
			).Parent = listFrame
		end
	end
end

local function makeTabButton(name)
	local button = new("TextButton", {
		BackgroundColor3 = currentTab == name and COLOR.Accent or COLOR.PanelLight,
		Size = UDim2.new(0, 100, 1, 0),
		Font = Enum.Font.SourceSansBold,
		TextColor3 = COLOR.Text,
		TextSize = 15,
		Text = name,
		Parent = tabRow,
	}, { corner(6) })
	button.MouseButton1Click:Connect(function()
		currentTab = name
		for _, sibling in ipairs(tabRow:GetChildren()) do
			if sibling:IsA("TextButton") then
				sibling.BackgroundColor3 = sibling.Text == name and COLOR.Accent or COLOR.PanelLight
			end
		end
		renderCraftList()
	end)
	return button
end

makeTabButton("Weapons")
makeTabButton("Robots")

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
	Position = UDim2.new(0.5, -200, 0.5, -170),
	Size = UDim2.new(0, 400, 0, 340),
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
	Size = UDim2.new(1, -24, 1, -56),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	Parent = shopFrame,
}, { new("UIListLayout", { Padding = UDim.new(0, 6) }) })

local currentShopNode = nil -- set right before the Shop panel opens, see node setup below

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
				end
			end
		).Parent = shopListFrame
	end
end

----------------------------------------------------------------------
-- Bottom action buttons
----------------------------------------------------------------------

local actionRow = new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.new(0, 300, 0, 44),
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

local objectiveMaxHP = 500  -- overwritten from the server's WaveStart payload below
local enemyHPPool = 1       -- ditto; guarded at 1 so an early Tick can't divide by zero

Remotes.WaveUpdate.OnClientEvent:Connect(function(update)
	if update.Status == "NoGear" then
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

local function setupNode(node: Instance)
	if node:FindFirstChildOfClass("ProximityPrompt") then
		return
	end
	local nodeTypeValue = node:FindFirstChild("NodeType")
	local nodeType = nodeTypeValue and nodeTypeValue:IsA("StringValue") and nodeTypeValue.Value
	if not nodeType then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 12
	prompt.Parent = node

	if nodeType == "Heal" then
		prompt.ActionText = "Heal"
		prompt.ObjectText = "Heal Station"
		prompt.Triggered:Connect(function(player)
			if player ~= LocalPlayer then return end
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
		local tierValue = node:FindFirstChild("Tier")
		local tier = (tierValue and tierValue:IsA("NumberValue")) and tierValue.Value or 1
		local tierData = NodeConfig.CombatTiers[tier]
		prompt.ActionText = "Raid"
		prompt.ObjectText = tierData and tierData.Name or ("Outpost (Tier %d)"):format(tier)
		prompt.Triggered:Connect(function(player)
			if player ~= LocalPlayer then return end
			Remotes.StartOutpostRaid:FireServer(node)
		end)
	elseif nodeType == "Shop" then
		prompt.ActionText = "Trade"
		prompt.ObjectText = "Outpost Shop"
		prompt.Triggered:Connect(function(player)
			if player ~= LocalPlayer then return end
			currentShopNode = node
			shopFrame.Visible = true
			renderShopList()
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
