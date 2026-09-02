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
	-- The docked status-panel button. Text is now a fixed-shape "RESEARCH T<n>" — tier number only,
	-- no station name, no status suffix — so it never reflows the button's width/corners the way
	-- "Research T3 — UPGRADE READY" used to. The station name lives in the popup body instead (the
	-- "Current" row in renderResearchPanel below already shows currentTier.Name), and "upgrade
	-- ready" is now signalled by swapping the button's whole colour variant (refreshResearchButton
	-- below calls Hud.setButtonVariant, primary when claimable, secondary otherwise) rather than by
	-- TextColor3 or a text suffix — variant swap also recolors the fill, which a bare TextColor3
	-- write never did.
	-- Height grown 34 -> 40: HudKit.button() only applies the angular 9-slice frame at
	-- BUTTON_MIN_SLICE_SIZE (40) or larger — below that it silently falls back to rounded corners,
	-- which is why this button still looked rounded while everything else on screen was cut steel.
	research.button = Hud.button({
		variant = "secondary",
		text = "RESEARCH T1",
		size = UDim2.new(1, 0, 0, 40),
		layoutOrder = 3,
		parent = statusPanel,
	})

	-- Chevron on the right edge, per the design — this button opens/closes a popup, and the chevron
	-- is what signals that. HudKit.button's own `icon` option always anchors LEFT of the text (or
	-- centers if there's no text at all — see its `hasText` branch), with no "icon on the right"
	-- mode, so a right-edge glyph has to be built by hand here rather than passed through `icon`.
	-- That's the only reason this doesn't just go through opts.icon like the Inventory tabs do.
	research.chevron = Hud.new("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0, 16, 0, 16),
		Image = "",
		Parent = research.button,
	})
	if Hud.applyIcon(research.chevron, "chevron") then
		-- Reserve the same footprint on the right that HudKit.button's own left-side icon padding
		-- uses (8px inset + icon size + one XS gap) — but MIRRORED on the left too. A right-only
		-- UIPadding insets HudKit.button's captionLabel (a Scale-sized child, per HudKit.button's own
		-- comment on why UIPadding hits it) asymmetrically: the text still centers itself within the
		-- now-narrower box, but that box's center sits left of the BUTTON's true center by half the
		-- reserved width, so the caption reads off-centre even though it's centered inside its own
		-- padded rect. This was the actual cause of the off-centre label reported from Studio, not a
		-- text-alignment property. Matching PaddingLeft keeps the reserved chevron gutter but makes
		-- the remaining box — and therefore the centered text inside it — symmetric about the
		-- button's real center again. The label is short and fixed now ("RESEARCH T1"), so the extra
		-- left inset costs nothing.
		local chevronGutter = UDim.new(0, 8 + 16 + Hud.SPACE.XS)
		Hud.new("UIPadding", { PaddingLeft = chevronGutter, PaddingRight = chevronGutter, Parent = research.button })
		-- Hover swap mirrors HudKit.button's own convention (rest/`_hover` pair), just wired by hand
		-- since this icon lives outside HudKit.button's own icon machinery. Both connections are
		-- additive to whatever HudKit.button already connected to MouseEnter/MouseLeave internally —
		-- Roblox events support multiple listeners, so this doesn't disturb its fill/size tweening.
		research.button.MouseEnter:Connect(function()
			Hud.applyIcon(research.chevron, "chevron_hover")
		end)
		research.button.MouseLeave:Connect(function()
			Hud.applyIcon(research.chevron, "chevron")
		end)
	else
		research.chevron:Destroy() -- missing art -> no chevron, per "missing art never breaks the loop"
		research.chevron = nil
	end

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
	-- rewrite the title text per tier ("RESEARCH TIER 3") — pull the TextLabel back out rather than
	-- hand-building a second one alongside it. Upper-cased for the Display-font chrome treatment,
	-- same as every other panel title in this pass; the tier NUMBER filled in below is the only
	-- dynamic part.
	research.header = Hud.panelHeader(research.surface, "RESEARCH", closeResearchPanel)
	research.title = research.header:FindFirstChildOfClass("TextLabel")

	-- Position moved 44 -> 52, Size's offset grown by the same 8 (-56 -> -64): Hud.panelHeader is a
	-- fixed 48px tall (PANEL_HEADER_HEIGHT in HudKit.lua), so 44 sat 4px INSIDE it — both are
	-- default-ZIndex siblings of a Sibling-ZIndexBehavior ScreenGui, so this list (added after the
	-- header) was quietly painting its first rows' top few pixels over the header's own bottom edge.
	-- The size offset grows by the same amount the position does, so the list's bottom edge doesn't move.
	research.list = Hud.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 52),
		Size = UDim2.new(1, -24, 1, -64),
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
		research.title.Text = ("RESEARCH TIER %d"):format(currentIndex)

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
	-- does not have to open the panel to find out. Text stays a fixed shape ("RESEARCH T<n>", tier
	-- number only) regardless of claimability — the station name and the "upgrade ready" state both
	-- used to be baked into this string, but a button whose text changes length reflows and looks
	-- unstable, and the long form overflowed the button's angular corners. The station name now
	-- lives in the popup body (renderResearchPanel's "Current" row already shows currentTier.Name);
	-- "upgrade ready" is now a colour swap via Hud.setButtonVariant, which recolors the fill AND the
	-- text together, instead of a manual TextColor3 write that only ever touched the text.
	refreshResearchButton = function()
		local _currentTier, currentIndex = ResearchConfig.GetTier(Hud.profile.ResearchTier or 1)
		local req = ResearchConfig.GetNextTierRequirements(Hud.profile)
		research.button.Text = ("RESEARCH T%d"):format(currentIndex)
		Hud.setButtonVariant(research.button, (req and req.CanClaim) and "primary" or "secondary")
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
