--[[
	ExpeditionService.lua
	A queue of Node instances (Heal/Shop/Combat — same NodeService handles them regardless of how
	they were created) that sits at fixed slots near a hand-placed anchor and shifts forward by
	exactly one slot each time the front one is cleared. This is the "nodes come to you, but only
	when you make progress" mechanic — nothing here moves on a timer; it only moves in response
	to the player.

	How it works:
	  1. Find the Part tagged "ExpeditionStart" — its position and facing (-Z / LookVector)
	     define the lane. Every node sits at a fixed slot along that local -Z axis; a node's
	     local Y (height) and rotation never change, and its local X (lateral, only nonzero for
	     the two options in a fork) is fixed at spawn too. The only thing that ever changes is
	     which slot number a row currently occupies.
	  2. A target queue size (5-8, ExpeditionConfig.PathLengthMin/Max) is picked once when the
	     queue (re)starts, and that many rows fill slots 1..targetRowCount (slot 1 = nearest the
	     anchor). Every ExpeditionConfig.ForkInterval-th spawned row is a FORK (two node options
	     side by side, each independently rolled); every other row is a single node. Every slot
	     always holds something — there's no "empty slot" chance. Node type is normally a weighted
	     roll (ExpeditionConfig.NodeTypeWeights), but the live queue is never allowed to drop below
	     ExpeditionConfig.MinCombatNodes Combat nodes — every time a new row is about to spawn, if
	     the current count is under that floor, the roll is skipped and Combat is forced instead
	     (still capped by MaxCombatNodes), so the map can't end up all Shop/Heal.
	  3. Only the row in slot 1 is ever interactable — NodeService checks
	     ExpeditionService.CanAccessSlot before letting a Heal/Shop/Combat interaction go
	     through, so you can't reach past the current row to one still further back.
	  4. The moment slot 1's last node is destroyed (a completed heal, a shop purchase, or a
	     cleared raid — expedition nodes are one-time and get destroyed on success, unlike the
	     permanent hand-placed base nodes), every remaining row shifts down by exactly one slot
	     (animated with a short tween, not instant) and a brand new row fills the now-empty back
	     slot. That's the ENTIRE movement model: nothing drifts, nothing moves on a clock, and
	     the queue can never wander outside its fixed slot range because there are only
	     targetRowCount slots and rows only ever occupy them.

	A Part tagged "ExpeditionLever" resets the whole queue on demand — wipes every active row and
	node and starts a fresh queue from scratch.

	NOTE: this drives ONE shared queue in the world, not a separate instance per player/party,
	and the "only slot 1 is accessible" gate is shared by everyone too. That's fine for
	prototyping the mechanic solo, but if this ships to real concurrent players you'll want each
	party running their own instanced expedition so they aren't fighting over the same queue — a
	bigger architectural change than this scaffold takes on.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ExpeditionConfig = require(ReplicatedStorage.Shared.ExpeditionConfig)
local AdminConfig = require(ReplicatedStorage.Shared.AdminConfig)
local RaidEnergyService = require(script.Parent.RaidEnergyService)
local RateLimiter = require(script.Parent.RateLimiter)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local START_TAG = "ExpeditionStart"
local LEVER_TAG = "ExpeditionLever"
local NODE_TAG = "Node"

local NODE_COLORS = {
	Combat = Color3.fromRGB(178, 76, 24),
	Shop = Color3.fromRGB(53, 96, 107),
	Heal = Color3.fromRGB(79, 140, 100),
}

local ExpeditionService = {}

local expeditionFolder = Workspace:FindFirstChild("Expedition")
if not expeditionFolder then
	expeditionFolder = Instance.new("Folder")
	expeditionFolder.Name = "Expedition"
	expeditionFolder.Parent = Workspace
end
-- -1 means "no expedition active" — set immediately so clients that load before anyone has
-- pulled the lever see the correct inactive state right away, not just a stale default.
expeditionFolder:SetAttribute("CurrentSlotId", -1)

----------------------------------------------------------------------
-- Node construction
----------------------------------------------------------------------

local function buildNode(nodeType: string, tier: number?, cframe: CFrame, slotIndex: number): Part
	local part = Instance.new("Part")
	part.Name = nodeType .. "Node"
	part.Size = Vector3.new(4, 4, 4)
	part.Anchored = true
	part.CanCollide = true
	part.Color = NODE_COLORS[nodeType] or Color3.fromRGB(120, 120, 120)
	part.Material = Enum.Material.Metal
	part.CFrame = cframe
	part:SetAttribute("IsExpeditionNode", true)
	part:SetAttribute("SlotIndex", slotIndex) -- this row's id; drives the "only slot 1" gating in NodeService

	local nodeTypeValue = Instance.new("StringValue")
	nodeTypeValue.Name = "NodeType"
	nodeTypeValue.Value = nodeType
	nodeTypeValue.Parent = part

	if nodeType == "Combat" then
		local tierValue = Instance.new("NumberValue")
		tierValue.Name = "Tier"
		tierValue.Value = tier or 1
		tierValue.Parent = part
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.new(0, 140, 0, 36)
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.SourceSansBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextSize = 18
	label.Text = tier and ("%s · T%d"):format(nodeType, tier) or nodeType
	label.Parent = billboard

	part.Parent = expeditionFolder
	CollectionService:AddTag(part, NODE_TAG)

	return part
end

local function linkSiblings(a: Part, b: Part)
	local aRef = Instance.new("ObjectValue")
	aRef.Name = "SiblingNode"
	aRef.Value = b
	aRef.Parent = a

	local bRef = Instance.new("ObjectValue")
	bRef.Name = "SiblingNode"
	bRef.Value = a
	bRef.Parent = b
end

-- Rolls a node type but refuses to hand out any more Combat nodes once the queue has already
-- hit ExpeditionConfig.MaxCombatNodes — falls back to Shop if it keeps rolling Combat anyway.
-- If forceCombat is true (the live queue is currently under ExpeditionConfig.MinCombatNodes) and
-- there's still room under the cap, skips the random roll entirely and hands out Combat directly
-- — this is what guarantees the queue never goes stretches with zero (or too few) Combat nodes.
local function rollNodeTypeCapped(combatCount: number, forceCombat: boolean?): string
	if forceCombat and combatCount < ExpeditionConfig.MaxCombatNodes then
		return "Combat"
	end
	for _ = 1, 8 do
		local nodeType = ExpeditionConfig.RollNodeType()
		if nodeType ~= "Combat" or combatCount < ExpeditionConfig.MaxCombatNodes then
			return nodeType
		end
	end
	return "Shop"
end

-- Fixed-length lane strip covering exactly the slot range (1..targetRowCount) rows ever occupy
-- — it never needs to change size or position after this, since rows never go past slot
-- targetRowCount or before slot 1.
local function buildLane(length: number, anchorCFrame: CFrame)
	local lane = Instance.new("Part")
	lane.Name = "ConveyorLane"
	lane.Size = Vector3.new(ExpeditionConfig.ForkLateralOffset * 2 + 10, 0.2, length)
	lane.Anchored = true
	lane.CanCollide = false
	lane.Material = Enum.Material.Ground
	lane.Color = Color3.fromRGB(96, 84, 68)
	lane.CFrame = anchorCFrame * CFrame.new(0, 0, -length / 2)
	lane.Parent = expeditionFolder
end

----------------------------------------------------------------------
-- Queue state
----------------------------------------------------------------------
-- activeRows is ordered frontmost-first (index 1 = slot 1 = nearest the anchor). Rows are only
-- ever appended at the back (slot targetRowCount) and removed from the front — a row that
-- empties out is guaranteed to be activeRows[1], because nodes are only ever
-- reachable/destroyable while their row IS activeRows[1] (see CanAccessSlot). That invariant is
-- what lets CanAccessSlot be a simple "is this activeRows[1]?" check with no per-player state,
-- and what keeps every row's Distance permanently inside [SlotSpacing, targetRowCount *
-- SlotSpacing] — there is no way for anything to end up outside that fixed range.

local activeRows = {}
local anchorCFrame: CFrame? = nil
local rowSpawnCounter = 0
local targetRowCount = 0

-- Every node's Destroying connection, keyed by the node itself — see clearExpedition() for why
-- this exists. A row's own onNodeDestroying still runs normally through it during ordinary
-- gameplay (a node resolving, a fork sibling getting destroyed by NodeService); this table is
-- only ever proactively emptied during a full wipe.
local nodeConnections: { [Instance]: RBXScriptConnection } = {}

local spawnRow
local onNodeDestroying
local advanceQueue

local function slotDistance(slotNumber: number): number
	return slotNumber * ExpeditionConfig.SlotSpacing
end

-- Recomputed from the actual live nodes every time, rather than tracked as a running tally —
-- a tally that increments on spawn and decrements on destroy is one more thing that can quietly
-- drift out of sync (a missed decrement anywhere silently caps Combat out forever with no way to
-- recover). At 5-8 active rows this is a trivial scan, so there's no real cost to always being
-- exactly right instead of "should be right if every code path remembered to update it."
local function countLiveCombat(): number
	local count = 0
	for _, row in ipairs(activeRows) do
		for _, node in ipairs(row.Nodes) do
			local typeValue = node:FindFirstChild("NodeType")
			if typeValue and typeValue.Value == "Combat" then
				count += 1
			end
		end
	end
	return count
end

local function tweenNodeTo(node: Instance, distance: number, lateral: number)
	if not node.Parent or not anchorCFrame then
		return
	end
	local targetCFrame = anchorCFrame * CFrame.new(lateral, 0, -distance)
	local tween = TweenService:Create(
		node,
		TweenInfo.new(ExpeditionConfig.ShiftDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ CFrame = targetCFrame }
	)
	tween:Play()
end

onNodeDestroying = function(node: Instance, row)
	nodeConnections[node] = nil
	row.Lateral[node] = nil
	local idx = table.find(row.Nodes, node)
	if idx then
		table.remove(row.Nodes, idx)
	end

	if #row.Nodes == 0 then
		local rowIdx = table.find(activeRows, row)
		if rowIdx then
			table.remove(activeRows, rowIdx)
		end
		advanceQueue()
	end
end

spawnRow = function(distance: number)
	if not anchorCFrame then
		return
	end

	rowSpawnCounter += 1
	local id = rowSpawnCounter
	local isFork = id % ExpeditionConfig.ForkInterval == 0
	local tier = ExpeditionConfig.GetTierForSlot(id)
	local row = { Id = id, Distance = distance, IsFork = isFork, Nodes = {}, Lateral = {} }

	-- Seeded from the real count, then tracked locally just for the (at most two) rolls in this
	-- one row — this row isn't in activeRows yet, so countLiveCombat() alone can't see a node
	-- this same call already placed a moment ago (relevant for a fork's 2nd roll). This same
	-- running count is also what the MinCombatNodes floor below checks, freshly, before every
	-- single roll — so it's re-evaluated after the fork's left node lands, not just once up front.
	local runningCombatCount = countLiveCombat()

	local function place(nodeType: string, lateral: number)
		local cframe = anchorCFrame * CFrame.new(lateral, 0, -distance)
		local node = buildNode(nodeType, nodeType == "Combat" and tier or nil, cframe, id)
		table.insert(row.Nodes, node)
		row.Lateral[node] = lateral
		if nodeType == "Combat" then
			runningCombatCount += 1
		end
		nodeConnections[node] = node.Destroying:Connect(function()
			onNodeDestroying(node, row)
		end)
		return node
	end

	if isFork then
		local leftType = rollNodeTypeCapped(runningCombatCount, runningCombatCount < ExpeditionConfig.MinCombatNodes)
		local leftNode = place(leftType, -ExpeditionConfig.ForkLateralOffset)
		-- Re-check after the left node: if it already covered the shortage, the right side just
		-- rolls normally instead of also being forced.
		local rightType = rollNodeTypeCapped(runningCombatCount, runningCombatCount < ExpeditionConfig.MinCombatNodes)
		local rightNode = place(rightType, ExpeditionConfig.ForkLateralOffset)
		linkSiblings(leftNode, rightNode)
	else
		local nodeType = rollNodeTypeCapped(runningCombatCount, runningCombatCount < ExpeditionConfig.MinCombatNodes)
		place(nodeType, 0)
	end

	table.insert(activeRows, row)

	print(("[ExpeditionService] spawned slot=%d fork=%s liveCombat=%d/%d (min %d)"):format(
		id, tostring(isFork), countLiveCombat(), ExpeditionConfig.MaxCombatNodes, ExpeditionConfig.MinCombatNodes))

	return row
end

-- Mirrors "which row is currently frontmost" onto an Attribute on the Expedition folder, which
-- replicates to every client automatically (Attributes always do — no RemoteEvent needed). This
-- is what lets MainHud.client.lua tell a locked node apart from an unlocked one and skip opening
-- UI for a node that's still further back in the queue, instead of only finding out it's locked
-- after the fact from a failed server call.
local function updateCurrentSlotAttribute()
	expeditionFolder:SetAttribute("CurrentSlotId", activeRows[1] and activeRows[1].Id or -1)
end

-- Called exactly once per cleared front row: every remaining row moves down one slot (a short
-- animated shift, not a teleport), and a fresh row fills the vacated back slot. This is the
-- ONLY thing that ever moves a node — there is no time-based movement anywhere in this file.
advanceQueue = function()
	for _, row in ipairs(activeRows) do
		row.Distance -= ExpeditionConfig.SlotSpacing
		for _, node in ipairs(row.Nodes) do
			tweenNodeTo(node, row.Distance, row.Lateral[node] or 0)
		end
	end
	spawnRow(slotDistance(targetRowCount))
	updateCurrentSlotAttribute()
end

----------------------------------------------------------------------
-- Gating — only slot 1 is interactable
----------------------------------------------------------------------

function ExpeditionService.CanAccessSlot(slotIndex: number?): boolean
	if typeof(slotIndex) ~= "number" then
		return true -- not an expedition node (no SlotIndex attribute) — never gated
	end
	return activeRows[1] ~= nil and activeRows[1].Id == slotIndex
end

----------------------------------------------------------------------
-- Queue (re)start
----------------------------------------------------------------------

-- Wipes every node in one pass. An earlier version of this guarded against the cascade below with
-- a simple "isWiping" boolean set true/false around the destroy loop — that looked right on paper
-- but didn't actually work, because Roblox's SignalBehavior can run .Destroying handlers in
-- DEFERRED mode: the handler doesn't fire synchronously inside :Destroy(), it's queued to run at
-- the end of the current resumption cycle. isWiping was already back to false (reset synchronously
-- right after this loop) by the time a deferred handler actually ran, so it caught nothing —
-- exactly what caused the lever/Return-to-Base "creates more nodes instead of clearing" bug even
-- though the flag logic was correct. Disconnecting every node's own connection BEFORE destroying
-- it sidesteps the whole timing question: a disconnected handler cannot fire, deferred or not.
local function clearExpedition()
	for _, connection in pairs(nodeConnections) do
		connection:Disconnect()
	end
	nodeConnections = {}

	for _, child in ipairs(expeditionFolder:GetChildren()) do
		child:Destroy()
	end
end

local function resetConveyor()
	local anchor = CollectionService:GetTagged(START_TAG)[1]
	if not anchor then
		warn("[ExpeditionService] No Part tagged '" .. START_TAG .. "' found — skipping generation. See the README.")
		return
	end

	clearExpedition()

	anchorCFrame = anchor.CFrame
	activeRows = {}
	rowSpawnCounter = 0
	targetRowCount = math.random(ExpeditionConfig.PathLengthMin, ExpeditionConfig.PathLengthMax)

	buildLane(slotDistance(targetRowCount) + 20, anchorCFrame)

	for slotNumber = 1, targetRowCount do
		spawnRow(slotDistance(slotNumber))
	end

	updateCurrentSlotAttribute()
end

----------------------------------------------------------------------
-- Lever + start/end
----------------------------------------------------------------------

-- No auto-start: the queue used to populate itself the moment the server booted, so an
-- expedition was just sitting there before anyone ever chose to begin one. Now nothing spawns
-- until a player pulls the ExpeditionLever — that IS "starting" an expedition for now. A later
-- pass can replace this with an actual teleport-to-a-separate-area flow; this is the minimal
-- fix that gives the run a real, deliberate start.
-- Energy is spent HERE — once, when the lever is pulled and a fresh queue actually generates —
-- not per Combat node inside the run (see NodeService's StartOutpostRaid, which no longer touches
-- Energy at all). Pulling the lever IS "starting an exploration," so this is the one true charge
-- point; whatever Combat/Shop/Heal rows end up in that run are already paid for. Admins skip the
-- cost same as everywhere else (see AdminConfig.lua).
Remotes.RegenerateExpedition.OnServerEvent:Connect(function(player: Player, lever: Instance)
	if typeof(lever) ~= "Instance" or not CollectionService:HasTag(lever, LEVER_TAG) then
		return
	end

	-- Distance check. The tag check above only proved the client named A lever, not that the player
	-- is anywhere near it — so an expedition could be started (and everyone else's queue wiped and
	-- regenerated) from across the map. It costs Energy either way, which bounded the abuse but did
	-- not make it correct.
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local leverPart = lever:IsA("BasePart") and lever or nil
	if not rootPart or not leverPart then
		return
	end
	if (rootPart.Position - leverPart.Position).Magnitude > ExpeditionConfig.LeverInteractDistance then
		Remotes.OutpostUpdate:FireClient(player, {
			Status = "Busy",
			Message = "Walk up to the expedition lever to start a run.",
		})
		return
	end

	if not AdminConfig.IsAdmin(player) and not RaidEnergyService.TrySpendEnergy(player) then
		Remotes.OutpostUpdate:FireClient(player, { Status = "NoEnergy" })
		return
	end

	resetConveyor()
end)

-- The other half of "a real start" is a real END: previously there was no way to stop an
-- expedition once begun short of wiping it via the lever (which doesn't heal you or feel like
-- an intentional exit). This is that exit — heals the requesting player to full and wipes the
-- queue back to the same inactive (CurrentSlotId = -1) state a fresh server starts in. Whatever
-- was looted along the way is already banked (Heal/Shop/Combat all grant rewards the instant a
-- node resolves, not at some later "end of run" step), so there's nothing to separately "keep."
-- NOTE: this is still the one shared queue every player sees (see the big comment up top) — one
-- player ending it wipes it for everyone on it, same caveat as the lever always had.
Remotes.EndExpedition.OnServerEvent:Connect(function(player: Player)
	-- This remote had NO validation whatsoever, which made it two exploits at once: a free
	-- full-heal callable from anywhere at any time (bind it to a key and you're unkillable,
	-- including mid-raid while NodeService.runRaid ticks damage at you), and a griefing tool,
	-- since ending the run wipes the ONE shared queue every player is using.
	--
	-- Gated on three things now: a run has to actually be in progress, the player has to be at
	-- the expedition itself rather than anywhere in the world, and it's paced.
	if #activeRows == 0 then
		Remotes.OutpostUpdate:FireClient(player, {
			Status = "Busy",
			Message = "There's no expedition running to return from.",
		})
		return
	end

	-- Must be at the expedition to leave it. Measured against the ExpeditionStart anchor rather
	-- than any particular node, because the whole lane counts as "on the run" — and generously,
	-- since the lane extends SlotSpacing * targetRowCount studs out from that anchor.
	local anchor = CollectionService:GetTagged(START_TAG)[1]
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not anchor or not rootPart then
		return
	end
	local laneLength = slotDistance(targetRowCount) + ExpeditionConfig.EndRangePadding
	if (rootPart.Position - anchor.Position).Magnitude > laneLength then
		Remotes.OutpostUpdate:FireClient(player, {
			Status = "Busy",
			Message = "You're not on the expedition — walk back to it to return to base.",
		})
		return
	end

	if not RateLimiter.Check(player, "EndExpedition", ExpeditionConfig.EndCooldownSeconds) then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end

	clearExpedition()
	activeRows = {}
	updateCurrentSlotAttribute()
end)

return ExpeditionService
