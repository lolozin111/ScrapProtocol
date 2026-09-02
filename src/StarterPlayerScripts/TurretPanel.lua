--[[
	TurretPanel.lua
	The turret slot panel — opened by clicking a turret slot out in the world (the blue pad for an
	empty one, or the turret itself for an occupied one), NOT from a tab in the Workbench.

	Placement used to live as a wall of rows in the Workbench's Base tab: one row per slot, a
	separate Unplace row under each occupied one, and a "Storage" list whose Place button silently
	auto-picked the first open slot for you. That meant choosing WHERE a turret went wasn't really
	a choice, and managing turrets happened nowhere near the turrets. Now the slot in the world is
	the interaction point — click it, see what you own, pick one.

	Same popup shape as the mod picker (frame, title, X, scrolling list of makeRows) because it's
	the same interaction: "this slot is empty, here's what you own that fits."

	Extracted from MainHud.client.lua as part of breaking that file up — it had grown past Luau's
	200-locals-per-scope ceiling.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TurretConfig = require(ReplicatedStorage.Shared.TurretConfig)

local Hud = require(script.Parent.HudKit)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local TurretPanel = {}

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

local function renderTurretPanel()
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

-- Called from the turret-slot ClickDetector in MainHud.client.lua.
function TurretPanel.Open(slotIndex: number)
	turretPanel.state.slotIndex = slotIndex
	renderTurretPanel()
	turretPanel.frame.Visible = true
end

-- Called from the InventoryUpdate handler to keep an open panel current — upgrading a turret
-- changes its level/stats, and the Cores spent change what the next upgrade costs. Place/Unplace
-- close the panel themselves (the slot's contents moved), so this is really about Upgrade
-- re-rendering in place.
function TurretPanel.Render()
	renderTurretPanel()
end

function TurretPanel.IsVisible(): boolean
	return turretPanel.frame.Visible
end

return TurretPanel
