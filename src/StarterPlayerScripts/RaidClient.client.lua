--[[
	RaidClient.client.lua
	Client for the instanced Raid Rooms system (RaidRoomService.lua/RaidConfig.lua) — a "Start Raid"
	button, the branching map GUI (circles + connecting lines, per the design ask — "not pretty
	pretty, but like smth with circles... and those lines path connecting each other"), and a small
	in-room status panel for whichever node type is currently active.

	Deliberately its OWN ScreenGui/file rather than bolted onto MainHud.client.lua — that file is
	already a large, single-purpose debug HUD for the base-building loop; this is a separate system
	end to end (own remotes, own server file, own state), so it gets its own small client too. Same
	undecorated, no-animation, Instance.new-through-Rojo style MainHud.client.lua itself calls out
	in its header — reskin later, once the loop feels good.

	No logos/icons yet (per the design ask — "for now just text to describe what will the next
	one be") — each node just shows its RaidConfig.NodeTypes[type].DisplayName as a text label.

	Maps chapter now (RaidRoomService.onMapCleared) — reaching a map's dead end regenerates a fresh
	one instead of ending the raid, so an Extract button (bottom-right, above Abandon) is the actual
	"leave and bank everything" action, enabled only after the first chapter's cleared. Ambush nodes
	reuse the same Combat sub-panel, just labeled with a Wave X/Y prefix (see AmbushStart/Tick/End/
	WaveCleared below) since they're several RunRaidCombat calls back to back instead of one.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RaidConfig = require(ReplicatedStorage.Shared.RaidConfig)

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
	MapLine = Color3.fromRGB(90, 82, 72),
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

local startButton = new("TextButton", {
	Name = "StartRaidButton",
	BackgroundColor3 = COLOR.AccentDark,
	Position = UDim2.new(1, -16, 0, 16),
	AnchorPoint = Vector2.new(1, 0),
	Size = UDim2.new(0, 150, 0, 40),
	Font = Enum.Font.SourceSansBold,
	Text = "Start Raid",
	TextColor3 = COLOR.Text,
	TextSize = 18,
	Parent = screenGui,
}, { corner(6) })

startButton.MouseButton1Click:Connect(function()
	RequestStartRaid:FireServer()
end)

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
-- Map panel (full-ish overlay, centered) — circles for nodes, lines for connections. Redrawn from
-- scratch on every RaidMapUpdate rather than diffed, since the shape of the graph never changes
-- mid-raid (only which nodes are reachable/current does), so a full rebuild is simple and cheap at
-- this scale (a handful of nodes per raid).
----------------------------------------------------------------------

-- The canvas itself is a fixed size, but the SPACING between stages/lanes and the node circles'
-- own diameter are now computed fresh per map (see redrawMap below) from however many stages/lanes
-- THIS particular map actually has, then clamped between the bounds below — a small map (near
-- RaidConfig.MinMapNodes) fills the panel with generously-sized nodes instead of huddling in one
-- corner, and a large one (deep forks, SegmentLengthMax every segment) shrinks to fit instead of
-- overflowing. "Make sure that nodes map fits the GUI properly... they are a bit too small."
local MAP_CANVAS_SIZE = Vector2.new(1050, 460)
local MIN_STAGE_SPACING = 60
local MAX_STAGE_SPACING = 140
local MIN_LANE_SPACING = 46
local MAX_LANE_SPACING = 90
local MIN_NODE_DIAMETER = 34
local MAX_NODE_DIAMETER = 56
local CANVAS_MARGIN_X = 30 -- breathing room left of the first / right of the last stage column
local CANVAS_MARGIN_Y = 20 -- breathing room above the first / below the last lane row

local mapFrame = new("Frame", {
	Name = "MapPanel",
	BackgroundColor3 = COLOR.Panel,
	Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.new(0, MAP_CANVAS_SIZE.X + 32, 0, MAP_CANVAS_SIZE.Y + 70),
	Visible = false,
	Parent = screenGui,
}, { corner(10), stroke() })

new("TextLabel", {
	Name = "Title",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 12),
	Size = UDim2.new(1, -32, 0, 24),
	Font = Enum.Font.SourceSansBold,
	Text = "Raid Map — choose your next room",
	TextColor3 = COLOR.Text,
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = mapFrame,
})

local mapCanvas = new("Frame", {
	Name = "Canvas",
	BackgroundColor3 = COLOR.PanelLight,
	Position = UDim2.new(0, 16, 0, 46),
	Size = UDim2.new(0, MAP_CANVAS_SIZE.X, 0, MAP_CANVAS_SIZE.Y),
	ClipsDescendants = true,
	Parent = mapFrame,
}, { corner(6) })

-- Draws a thin line between two canvas-local points using a rotated Frame — the standard "line via
-- rotated rectangle" trick, since Roblox GUI has no native line primitive.
local function drawLine(pointA: Vector2, pointB: Vector2)
	local delta = pointB - pointA
	local length = delta.Magnitude
	local angle = math.deg(math.atan2(delta.Y, delta.X))
	local midpoint = (pointA + pointB) / 2

	new("Frame", {
		BackgroundColor3 = COLOR.MapLine,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, midpoint.X, 0, midpoint.Y),
		Size = UDim2.new(0, length, 0, 2),
		Rotation = angle,
		ZIndex = 1,
		Parent = mapCanvas,
	})
end

local currentReachableIds = {} :: { number }

local function redrawMap(payload)
	mapCanvas:ClearAllChildren()
	currentReachableIds = payload.ReachableIds or {}
	local reachableSet = {}
	for _, id in ipairs(currentReachableIds) do
		reachableSet[id] = true
	end

	-- Tree layout ("dendrogram"): RaidConfig.GenerateMap now builds a real tree — every node has
	-- exactly one parent, so a node's own Connections list IS its children. Walk it depth-first from
	-- Start, handing each LEAF the next sequential lane in left-to-right visiting order; every
	-- internal node's lane is then just the average of its own children's lanes (computed on the
	-- way back up the recursion). Column (X) is just StageIndex, same as before. Because this is a
	-- genuine tree — unlike the old fork-and-merge diamond, which only ever approximated a
	-- crossing-free layout — connecting lines are GUARANTEED to never cross, by construction.
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

	-- How wide/tall THIS map's tree actually is — feeds the dynamic spacing below so a small map
	-- fills the panel and a large one shrinks to fit, instead of both using the same fixed spacing.
	local maxStage = 0
	for _, node in pairs(payload.Nodes) do
		if node.StageIndex > maxStage then
			maxStage = node.StageIndex
		end
	end
	local laneCount = math.max(nextLeafLane, 1)

	local stageSpacingX = maxStage > 0
		and math.clamp((MAP_CANVAS_SIZE.X - CANVAS_MARGIN_X * 2) / maxStage, MIN_STAGE_SPACING, MAX_STAGE_SPACING)
		or MIN_STAGE_SPACING
	local laneSpacingY = math.clamp((MAP_CANVAS_SIZE.Y - CANVAS_MARGIN_Y * 2) / laneCount, MIN_LANE_SPACING, MAX_LANE_SPACING)
	local nodeDiameter = math.clamp(laneSpacingY * 0.72, MIN_NODE_DIAMETER, MAX_NODE_DIAMETER)

	-- Centers the actual content (however wide/tall it ends up after clamping) within the fixed
	-- canvas, rather than always hugging the top-left corner.
	local xOffset = math.max(CANVAS_MARGIN_X, (MAP_CANVAS_SIZE.X - maxStage * stageSpacingX) / 2)
	local yOffset = math.max(0, (MAP_CANVAS_SIZE.Y - laneCount * laneSpacingY) / 2)

	local nodeCanvasPos = {} -- id -> Vector2, filled in below, read back for line-drawing
	for id, node in pairs(payload.Nodes) do
		local x = xOffset + node.StageIndex * stageSpacingX
		local y = yOffset + (laneOf[id] + 0.5) * laneSpacingY
		nodeCanvasPos[id] = Vector2.new(x, y)
	end

	-- Lines first so every circle draws on top of them.
	for id, node in pairs(payload.Nodes) do
		local fromPos = nodeCanvasPos[id]
		if fromPos then
			for _, toId in ipairs(node.Connections) do
				local toPos = nodeCanvasPos[toId]
				if toPos then
					drawLine(fromPos, toPos)
				end
			end
		end
	end

	for id, node in pairs(payload.Nodes) do
		local pos = nodeCanvasPos[id]
		if pos then
			local typeConfig = RaidConfig.NodeTypes[node.Type]
			local isCurrent = id == payload.CurrentNodeId
			local isReachable = reachableSet[id] == true
			local dim = not isCurrent and not isReachable

			local circle = new("TextButton", {
				Name = "Node" .. id,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, pos.X, 0, pos.Y),
				Size = UDim2.new(0, nodeDiameter, 0, nodeDiameter),
				BackgroundColor3 = (typeConfig and typeConfig.Color) or Color3.fromRGB(120, 120, 120),
				BackgroundTransparency = dim and 0.55 or 0,
				AutoButtonColor = isReachable,
				Text = "",
				ZIndex = 2,
				Parent = mapCanvas,
			}, { circleCorner(), isCurrent and stroke(COLOR.Text, 3) or (isReachable and stroke(COLOR.Text, 2) or nil) })

			local labelText = typeConfig and typeConfig.DisplayName or node.Type
			if node.Tier then
				labelText = ("%s · T%d"):format(labelText, node.Tier)
			end
			new("TextLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0, pos.X, 0, pos.Y + nodeDiameter / 2 + 4),
				Size = UDim2.new(0, 100, 0, 28),
				Font = Enum.Font.SourceSans,
				Text = labelText,
				TextColor3 = dim and COLOR.Muted or COLOR.Text,
				TextSize = 13,
				TextWrapped = true,
				ZIndex = 2,
				Parent = mapCanvas,
			})

			if isReachable then
				circle.MouseButton1Click:Connect(function()
					mapFrame.Visible = false
					updateRaidButtons() -- Go Back To Base hides the instant the map closes
					ChooseRaidNode:FireServer(id)
				end)
			end
		end
	end
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
-- Start only makes sense when not already raiding; Go Back To Base only while the map GUI is
-- actually open (see that button's own comment on why — mapFrame.Visible, NOT just "in a raid and
-- not mid-Combat" like it used to be); Extract only while raiding, not mid-Combat (see
-- RaidRoomService's own comment on why Combat blocks it), and only once extractUnlocked.
updateRaidButtons = function()
	startButton.Visible = not inRaid
	backToBaseButton.Visible = mapFrame.Visible
	extractButton.Visible = inRaid and not inCombat and extractUnlocked
	runCurrencyLabel.Visible = inRaid
end

RaidMapUpdate.OnClientEvent:Connect(function(payload)
	if not payload or not payload.Active then
		mapFrame.Visible = false
		updateRaidButtons() -- mapFrame just closed — Go Back To Base needs to hide too
		return
	end
	inRaid = true
	inCombat = false
	roomFrame.Visible = false
	redrawMap(payload)
	mapFrame.Visible = true
	-- Called AFTER mapFrame.Visible flips true, not before — Go Back To Base's visibility reads
	-- mapFrame.Visible directly (see updateRaidButtons), so calling this any earlier would leave it
	-- hidden for the first frame the map is actually showing.
	updateRaidButtons()
end)

RaidRoomUpdate.OnClientEvent:Connect(function(payload)
	payload = payload or {}
	local status = payload.Status

	if status == "Entered" then
		inRaid = true
		inCombat = false
		mapFrame.Visible = false
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
		mapFrame.Visible = false
		updateRaidButtons()
		showToast("Raid failed — " .. (payload.Reason or "you went down.") .. " Back to base.", 5)

	elseif status == "Extracted" then
		inRaid = false
		inCombat = false
		extractUnlocked = false
		roomFrame.Visible = false
		mapFrame.Visible = false
		updateRaidButtons()
		showToast("Extracted! Made it out clean.", 5)

	elseif status == "Abandoned" then
		inRaid = false
		inCombat = false
		extractUnlocked = false
		roomFrame.Visible = false
		mapFrame.Visible = false
		updateRaidButtons()
		showToast("Raid abandoned.", 3)

	elseif status == "NoEnergy" then
		showToast("Not enough Energy to start a raid.", 3)

	elseif status == "NoSlotsFree" then
		showToast("The raid area is full right now — try again shortly.", 3)
	end
end)
