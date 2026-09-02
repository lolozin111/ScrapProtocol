--[[
	ResearchPanel.lua
	The Research button (docked on the status panel) and the requirements popup it opens — what
	the next tier needs, and which parts you already have.

	Rendered from ResearchConfig.GetNextTierRequirements, the SAME function BaseService's
	UpgradeResearch handler uses to decide whether to allow the claim — so what is shown here and
	what is actually enforced can never drift apart.

	Extracted from MainHud.client.lua as part of breaking that file up — it had grown past Luau's
	200-locals-per-scope ceiling. Unlike ModPicker/ShopPanel/TurretPanel, the button itself has to be
	parented into the status panel (bottom-left, always-visible HUD), which is a MainHud local, not
	something this module owns — so this module exposes a constructor that takes it in, instead of
	building everything at require-time the way the others do.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ResearchConfig = require(ReplicatedStorage.Shared.ResearchConfig)
local TurretConfig = require(ReplicatedStorage.Shared.TurretConfig)
local Wallet = require(ReplicatedStorage.Shared.Wallet)

local Hud = require(script.Parent.HudKit)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local ResearchPanel = {}

-- Builds the button + popup and wires them up. Called once from MainHud.client.lua after the
-- status panel exists, since the button parents into it.
function ResearchPanel.new(statusPanel: Frame)
	-- One table instead of several separate top-level locals: Luau caps a function scope at 200
	-- locals and this file's main chunk hit that ceiling. Grouping UI element references costs
	-- nothing at runtime and buys back a register per element.
	local research = {}
	-- The docked status-panel button. TextColor3 keeps getting overwritten by
	-- refreshResearchButton() below (Accent vs. Good when a tier is claimable) — that still works
	-- on top of Hud.button's hover/press tweens, since those only ever touch
	-- BackgroundColor3/Size/Position, never TextColor3.
	research.button = Hud.button({
		variant = "secondary",
		text = "Research Tier 1",
		size = UDim2.new(1, 0, 0, 30),
		layoutOrder = 3,
		parent = statusPanel,
	})

	-- research.frame is the plate's SHELL (the outer, positioned frame) so existing
	-- `research.frame.Visible = ...` toggles keep working unchanged; research.surface is the inset
	-- content surface the header and list parent into.
	research.surface, research.frame = Hud.plate({
		Name = "ResearchPanel",
		Position = UDim2.new(0, 16, 1, -160),
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(0, 360, 0, 340),
		Visible = false,
		ZIndex = 6,
		Parent = Hud.screenGui,
	})

	local function closeResearchPanel()
		research.frame.Visible = false
	end

	-- panelHeader owns the header Frame's construction, but renderResearchPanel() still needs to
	-- rewrite the title text per tier ("Research Tier 3") — pull the TextLabel back out rather than
	-- hand-building a second one alongside it.
	research.header = Hud.panelHeader(research.surface, "Research", closeResearchPanel)
	research.title = research.header:FindFirstChildOfClass("TextLabel")

	research.list = Hud.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 44),
		Size = UDim2.new(1, -24, 1, -56),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = research.surface,
	}, { Hud.new("UIListLayout", { Padding = UDim.new(0, 6) }) })

	local refreshResearchButton -- forward-declared; renderResearchPanel refreshes it after a claim

	-- Kept current by the InventoryUpdate listener in MainHud, so the panel updates live as you
	-- gather materials rather than going stale the moment you opened it.
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

	return {
		renderResearchPanel = renderResearchPanel,
		refreshResearchButton = refreshResearchButton,
		isVisible = function()
			return research.frame.Visible
		end,
	}
end

return ResearchPanel
