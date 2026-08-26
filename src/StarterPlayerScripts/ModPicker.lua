--[[
	ModPicker.lua
	The "choose a mod for this slot" popup, shared by the two places that show mod slots: the
	Welding Station's owned-item rows and the Inventory panel's detail view.

	Extracted from MainHud.client.lua as part of breaking that file up — it had grown past Luau's
	200-locals-per-scope ceiling. This one comes out before the panels that use it, since both of
	them depend on it and neither can move until it has somewhere to depend on.

	Mods apply per item TYPE, not per instance — see ModConfig.lua's header for why — so `itemKey`
	here is a weaponKey or robotKey, never a Forged weapon's unique Id.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModConfig = require(ReplicatedStorage.Shared.ModConfig)

local Hud = require(script.Parent.HudKit)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local ModPicker = {}

function ModPicker.equippedModKeyForSlot(itemKey: string, slotIndex: number)
	local equipped = Hud.profile.EquippedMods and Hud.profile.EquippedMods[itemKey]
	return equipped and equipped[slotIndex]
end

-- Sorted so the picker list reads consistently instead of hash-order.
function ModPicker.ownedModKeysSorted()
	local keys = {}
	for key, owned in pairs(Hud.profile.CraftedMods or {}) do
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

local modPickerFrame = Hud.new("Frame", {
	Name = "ModPicker",
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
	Text = "Choose a Mod",
	Parent = modPickerFrame,
})

local modPickerClose = Hud.new("TextButton", {
	BackgroundColor3 = Hud.COLOR.PanelLight,
	Position = UDim2.new(1, -40, 0, 8),
	Size = UDim2.new(0, 28, 0, 28),
	Font = Enum.Font.SourceSansBold,
	TextColor3 = Hud.COLOR.Text,
	TextSize = 16,
	Text = "X",
	Parent = modPickerFrame,
}, { Hud.corner(6) })

local modPickerList = Hud.new("ScrollingFrame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 44),
	Size = UDim2.new(1, -24, 1, -56),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	Parent = modPickerFrame,
}, { Hud.new("UIListLayout", { Padding = UDim.new(0, 6) }) })

-- Which slot the popup is currently open for — cleared whenever it closes.
local modPickerState = { tree = nil, itemKey = nil, slotIndex = nil }

function ModPicker.closeModPicker()
	modPickerFrame.Visible = false
	modPickerState.tree = nil
	modPickerState.itemKey = nil
	modPickerState.slotIndex = nil
end
modPickerClose.MouseButton1Click:Connect(ModPicker.closeModPicker)

-- No manual craft-list re-render here — EquipMod's server handler fires InventoryUpdate with the
-- new EquippedMods table, and that listener already re-renders the craft list while it's open
-- (the same pattern the Craft/Deploy buttons elsewhere in this file rely on).
local function selectMod(modKey: string?)
	local tree, itemKey, slotIndex = modPickerState.tree, modPickerState.itemKey, modPickerState.slotIndex
	ModPicker.closeModPicker() -- close first so a slow round trip doesn't leave a stale popup hanging open
	local result = Remotes.EquipMod:InvokeServer(tree, itemKey, slotIndex, modKey)
	if not result.Success then
		Hud.showFailure("Equip mod failed", result.Reason)
	end
end

local function renderModPickerList()
	for _, child in ipairs(modPickerList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local currentModKey = ModPicker.equippedModKeyForSlot(modPickerState.itemKey, modPickerState.slotIndex)

	Hud.makeRow(
		"None",
		"Clear this slot",
		(currentModKey == nil) and "Selected" or "Select",
		function()
			selectMod(nil)
		end
	).Parent = modPickerList

	for _, modKey in ipairs(ModPicker.ownedModKeysSorted()) do
		local mod = ModConfig.Mods[modKey]
		local rarityData = ModConfig.Rarities[mod.Rarity]
		local rarityName = rarityData and rarityData.DisplayName or mod.Rarity
		Hud.makeRow(
			("[%s] %s"):format(rarityName, mod.DisplayName),
			mod.Description,
			(modKey == currentModKey) and "Selected" or "Select",
			function()
				selectMod(modKey)
			end
		).Parent = modPickerList
	end
end

function ModPicker.openModPicker(tree: string, itemKey: string, slotIndex: number)
	modPickerState.tree = tree
	modPickerState.itemKey = itemKey
	modPickerState.slotIndex = slotIndex
	renderModPickerList()
	modPickerFrame.Visible = true
end

return ModPicker
