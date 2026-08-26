--[[
	MineShaftController.client.lua
	Input handling for the dig-down mine — a ClickDetector per block, with a hover Highlight, same
	interaction model NodeService's Heal/Shop/Combat nodes already use (see MainHud.client.lua's
	setupNode) rather than a ProximityPrompt.

	ProximityPrompt was the original choice here (mirroring MiningController.client.lua's ore
	nodes), but it doesn't work for a block the player is standing directly ON TOP OF:
	ProximityPrompt requires line of sight from the camera to its attach point by default, and a
	player's own character standing on the block routinely blocks that line of sight to the
	prompt sitting right underneath them — the prompt just never triggers. That's exactly what
	"I can't mine anything" was: not a server-side rejection (which would have shown a MineFailed
	warning), the client-side prompt itself was silently never firing. A ClickDetector doesn't
	have that problem — it only needs the block visible on screen, not an unobstructed camera ray
	to a point that's now under the player's feet.

	Every block that spawns (all ~1,000 of the Depth-0 floor, and every new one revealed after
	that) gets this same ClickDetector setup via the tag-added signal below — no per-block wiring
	needed anywhere else. Mining still takes multiple hits same as before — each click is one hit,
	same as each ProximityPrompt hold used to be.

	Also owns the ONE reusable hover label (a single BillboardGui, re-Adornee'd to whichever block
	is currently hovered) instead of MineShaftService giving every block its own permanent
	BillboardGui — with a grid this size (32x32 = ~1,000 blocks just for the surface layer, and it
	only grows as you dig),
	one persistent GUI instance per block would be a real client-side performance cost for
	something only ever useful for the one block you're actually looking at. Kind/Depth/
	HitsRemaining/MaxHits/OreKey are ordinary replicated Attributes on the block itself, so this
	reads them straight off whatever's hovered rather than needing a remote round-trip.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local MineShaftHit = ReplicatedStorage.Remotes.MineShaftHit
local MineFailed = ReplicatedStorage.Remotes.MineFailed -- shared with MiningService's failures, same UX
local OreConfig = require(ReplicatedStorage.Shared.OreConfig)

local BLOCK_TAG = "ShaftBlock"
local CLICK_DISTANCE = 12 -- studs; matches MineShaftService's MAX_MINING_DISTANCE server-side check

local LocalPlayer = Players.LocalPlayer

MineFailed.OnClientEvent:Connect(function(reason: string)
	warn("[MineShaft]", reason)
end)

----------------------------------------------------------------------
-- One reusable hover label — see header comment for why this replaced a per-block BillboardGui.
----------------------------------------------------------------------

local hoverBillboard = Instance.new("BillboardGui")
hoverBillboard.Name = "MineShaftHoverLabel"
hoverBillboard.Size = UDim2.new(0, 160, 0, 32)
hoverBillboard.StudsOffset = Vector3.new(0, 4, 0)
hoverBillboard.AlwaysOnTop = true
hoverBillboard.Enabled = false
hoverBillboard.Parent = LocalPlayer:WaitForChild("PlayerGui")

local hoverLabel = Instance.new("TextLabel")
hoverLabel.BackgroundTransparency = 1
hoverLabel.Size = UDim2.new(1, 0, 1, 0)
hoverLabel.Font = Enum.Font.SourceSansBold
hoverLabel.TextColor3 = Color3.new(1, 1, 1)
hoverLabel.TextStrokeTransparency = 0.3
hoverLabel.TextSize = 16
hoverLabel.Parent = hoverBillboard

-- Single source of truth for the label text, driven entirely off the hovered block's own
-- Attributes — mirrors what MineShaftService used to compute server-side for each block's own
-- BillboardGui, just done here now for whichever one block is actually being looked at.
local function refreshHoverLabel(block: Instance)
	local kind = block:GetAttribute("Kind")
	local depth = block:GetAttribute("Depth")

	if kind == "Bedrock" then
		hoverLabel.Text = ("Bedrock · Depth %d"):format(depth)
		return
	end

	local displayName
	if kind == "Rock" then
		displayName = "Rock"
	elseif kind == "Hazard" then
		displayName = "??? (unstable)" -- deliberately doesn't announce it's Lava until it's too late
	else
		local oreData = OreConfig.Ores[block:GetAttribute("OreKey")]
		displayName = oreData and oreData.DisplayName or "Ore"
	end

	hoverLabel.Text = ("%s · Depth %d (%d/%d)"):format(
		displayName, depth, block:GetAttribute("HitsRemaining"), block:GetAttribute("MaxHits"))
end

local function setupBlock(block: Instance)
	if block:FindFirstChildOfClass("ClickDetector") then
		return
	end

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = CLICK_DISTANCE
	clickDetector.CursorIcon = ""
	clickDetector.Parent = block

	-- Same accent color MainHud.client.lua uses for expedition node hover highlights, so
	-- clickable-and-glowing reads the same way everywhere in the game.
	local highlight = Instance.new("Highlight")
	highlight.Enabled = false
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(224, 122, 59)
	highlight.OutlineTransparency = 0
	highlight.Parent = block

	local attributeChangedConnection: RBXScriptConnection? = nil

	clickDetector.MouseHoverEnter:Connect(function(player)
		if player ~= LocalPlayer then
			return
		end
		highlight.Enabled = true
		refreshHoverLabel(block)
		hoverBillboard.Adornee = block
		hoverBillboard.Enabled = true
		-- Keeps the hit-counter live while you keep clicking without moving the mouse off the
		-- block — HitsRemaining is a replicated Attribute, so the server's decrement shows up
		-- here automatically.
		attributeChangedConnection = block.AttributeChanged:Connect(function()
			if hoverBillboard.Adornee == block then
				refreshHoverLabel(block)
			end
		end)
	end)
	clickDetector.MouseHoverLeave:Connect(function(player)
		if player ~= LocalPlayer then
			return
		end
		highlight.Enabled = false
		if hoverBillboard.Adornee == block then
			hoverBillboard.Enabled = false
			hoverBillboard.Adornee = nil
		end
		if attributeChangedConnection then
			attributeChangedConnection:Disconnect()
			attributeChangedConnection = nil
		end
	end)

	clickDetector.MouseClick:Connect(function(player)
		if player == LocalPlayer then
			MineShaftHit:FireServer(block)
		end
	end)
end

for _, block in ipairs(CollectionService:GetTagged(BLOCK_TAG)) do
	setupBlock(block)
end
CollectionService:GetInstanceAddedSignal(BLOCK_TAG):Connect(setupBlock)
