--[[
	ShopPanel.lua
	The Outpost Shop popup, opened only by standing at (and clicking) a Shop-type expedition
	node — see the node setup in MainHud.client.lua for the ClickDetector wiring that calls
	into this module.

	Extracted from MainHud.client.lua as part of breaking that file up — it had grown past
	Luau's 200-locals-per-scope ceiling. `currentShopNode` moves in here with the rest of the
	panel state rather than staying a MainHud local, since nothing outside the panel touches it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NodeConfig = require(ReplicatedStorage.Shared.NodeConfig)

local Hud = require(script.Parent.HudKit)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local ShopPanel = {}

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

local currentShopNode = nil -- set right before the Shop panel opens
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

-- Called from the Shop-node ClickDetector in MainHud.client.lua once it's already verified the
-- node is accessible and no raid is in progress.
function ShopPanel.Open(node: Instance)
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
end

function ShopPanel.Close()
	shopUI.frame.Visible = false
end

return ShopPanel
