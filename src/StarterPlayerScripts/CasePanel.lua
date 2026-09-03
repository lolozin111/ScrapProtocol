--[[
	CasePanel.lua
	The Hacker Machine's Decode tab, and the case-opening reveal it raises.

	THE FLOW CHANGED, and the reveal is the reason. Decoding used to roll the case, grant its
	contents, and fire a toast, all at the moment the timer elapsed — which could be while the player
	was down a mine shaft or mid-raid. The payoff of the entire Black Market system was a line of text
	somebody might not be looking at.

	So finishing a decode now leaves the case CRACKED BUT UNOPENED (`profile.DecodedCase`), and
	opening it is its own deliberate act. The contents are rolled by HackerService's OpenCase remote
	at that moment, not before. That is what lets the animation exist at all: it can only ever run
	while somebody is watching it.

	The tab therefore has four states, in the order you meet them:

	  1. nothing decoding      — what you own, and a Decode button per case
	  2. decoding              — countdown, plus the two Rush paths
	  3. decoded, unopened     — one big OPEN control. The machine has finished; the case has not.
	  4. opening               — the reveal, below

	THE REVEAL IS THE A/B HYBRID from the design round (DESIGN_NOTES section C's picks table), which
	was a direct request rather than a designer's pick:

	  Popups A, "the panel body becomes the reveal" — while the roll is running, the tab's own body
	  turns into the stage. A 2px accent line down the dead centre is the ticker marker, and a strip
	  of cards scrolls past it and eases to a stop with the winner under the marker. Nothing floats
	  free, nothing dims the world. This is the part you watch.

	  Popups B, "full takeover" — the moment it lands, a plate lifts over a scrim: a diamond backdrop,
	  the prize on a glowing card bordered in its own rarity colour, its rarity and name, and Claim.
	  This is the part that interrupts.

	WHY THE STRIP IS FAKE AND THAT IS FINE. The server rolled the reward before the first frame of
	animation; the strip is built backwards from the answer, with the winner planted at a known index
	and everything else filled in with plausible rarities weighted by that case's own Odds. Every
	case-opening animation in every game works this way. What matters is that the client cannot
	change the outcome, and it cannot: OpenCase granted it already.

	DUPLICATES REFUND, they do not consolation-prize. A unique reward you already own (an Ultimate, a
	weapon-family blueprint, a special pickaxe, a Drone Core) pays back half of what the case cost, in
	the currency it cost — see CaseConfig.DuplicateRefund. The takeover says so on the card rather
	than burying it in a toast, because "you already own this" is the outcome most in need of an
	explanation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CaseConfig = require(ReplicatedStorage.Shared.CaseConfig)
local DroneConfig = require(ReplicatedStorage.Shared.DroneConfig)
local ModConfig = require(ReplicatedStorage.Shared.ModConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local ToolModConfig = require(ReplicatedStorage.Shared.ToolModConfig)
local UltimateConfig = require(ReplicatedStorage.Shared.UltimateConfig)
local Wallet = require(ReplicatedStorage.Shared.Wallet)
local WeaponFamilyConfig = require(ReplicatedStorage.Shared.WeaponFamilyConfig)

local Hud = require(script.Parent.HudKit)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local CasePanel = {}

----------------------------------------------------------------------
-- Geometry
----------------------------------------------------------------------
-- Derived from the station's configured panel size, same as every other phase-3 panel: 116 is
-- MainHud's header/tab stack above `listFrame`, 12 the bottom margin, 6 the plate's bevel per side,
-- 24 listFrame's own margins.
local PANEL_SIZE = StationConfig.Types.Hacker.PanelSize or StationConfig.DefaultPanelSize

local BODY_HEIGHT = PANEL_SIZE.Y - 116 - 12
local BODY_WIDTH = PANEL_SIZE.X - 6 - 24

-- The reel. CARD_PERIOD is the pitch between card centres, so the maths below only ever has to think
-- in whole cards.
local CARD_WIDTH = 56
local CARD_HEIGHT = 72
local CARD_GAP = 8
local CARD_PERIOD = CARD_WIDTH + CARD_GAP

-- How many cards the strip holds and which one is the winner. The winner sits far enough in that the
-- reel travels a satisfying distance, and far enough from the end that cards are still visible to its
-- right when it stops — a reel that lands on the last card looks like it ran out rather than stopped.
local STRIP_CARDS = 34
local WINNER_INDEX = 27

local REEL_SECONDS = 2.4
local POP_SECONDS = 0.28
local LANDED_HOLD_SECONDS = 0.45 -- the beat between the reel stopping and the takeover lifting

local TAKEOVER_WIDTH = 440
local PRIZE_CARD = Vector2.new(74, 92)

-- A square rotated 45 degrees occupies side * sqrt(2) in BOTH axes, so the side has to come DOWN
-- from the space available, not up from a number that looked right in a drawing — the mockup's 300
-- would have occupied 424x424 inside a 440-wide plate and hung out of it on every side.
--
-- Derived from the SMALLER budget, which is the height: the plate is as tall as its contents make it
-- (the stage below is AutomaticSize), so there is no exact number to divide, and the conservative
-- floor below is what keeps this honest rather than relying on the surface clip to hide a diamond
-- that does not actually fit.
local TAKEOVER_MIN_HEIGHT = 300 -- the shortest this plate gets with the shortest reward text
local DIAMOND_SIDE = math.floor(
	(math.min(TAKEOVER_WIDTH, TAKEOVER_MIN_HEIGHT) - Hud.CORNER_CUT * 2) / math.sqrt(2)
)

-- How much wider the landed card gets. Every card left of the winner slides half of this to the
-- left and every card right of it slides half to the right, so the reel opens up around the winner
-- instead of the winner growing over its neighbours.
local WINNER_GROW_X = 14
local WINNER_GROW_Y = 18

----------------------------------------------------------------------
-- Reward presentation
----------------------------------------------------------------------

local function rarityColor(rarityKey: string?): Color3
	local data = rarityKey and ModConfig.Rarities[rarityKey]
	return data and data.Color or Hud.COLOR.Muted
end

-- What to call the thing that came out. Every Kind names itself differently — a currency is a wallet
-- key, an Ultimate is a config entry, a weapon family is a blueprint — and the server already
-- resolves some of them onto `reward.DisplayName`, so that wins where it exists.
local function rewardName(reward): string
	if reward.DisplayName then
		return reward.DisplayName
	end
	if reward.Kind == "Ultimate" then
		local data = UltimateConfig.Mods[reward.Key]
		return data and data.DisplayName or reward.Key
	end
	if reward.Kind == "DroneCore" then
		local core = DroneConfig.Cores[reward.Key]
		return core and core.DisplayName or reward.Key
	end
	if reward.Kind == "Tool" then
		local tool = ToolModConfig.Tools[reward.Key]
		return tool and tool.DisplayName or reward.Key
	end
	if reward.Kind == "WeaponFamily" then
		return WeaponFamilyConfig.BlueprintName(reward.Key)
	end
	return Wallet.DisplayName(reward.Key)
end

-- The line under the name: how many you got, or — for a permanent unlock — where to go and use it.
-- A reward you cannot immediately find is one the player assumes is broken, so each unlock names its
-- own destination rather than leaving them to hunt.
local function rewardDetail(reward): string
	if reward.Duplicate then
		local parts = {}
		for key, amount in pairs(reward.Refund or {}) do
			table.insert(parts, ("%d %s"):format(amount, Wallet.DisplayName(key)))
		end
		table.sort(parts)
		return #parts > 0
			and ("Already owned — refunded %s"):format(table.concat(parts, ", "))
			or "Already owned"
	end
	if reward.Kind == "Ultimate" then
		return "Equip it in the Inventory's Ultimate slot."
	end
	if reward.Kind == "DroneCore" then
		if reward.LockedUntilTier then
			return ("Slot it at the Welding Station once you reach Research Tier %d."):format(reward.LockedUntilTier)
		end
		return "Slot it at the Welding Station's Drones tab."
	end
	if reward.Kind == "Tool" then
		return "Equip it at a Workbench's Tools tab."
	end
	if reward.Kind == "WeaponFamily" then
		return "Forge them at the Forge's Weapons tab."
	end
	return ("x%d"):format(reward.Amount or 1)
end

----------------------------------------------------------------------
-- Panel
----------------------------------------------------------------------

export type CasePanelContext = {
	listFrame: Instance,
	refresh: () -> (),
}

function CasePanel.new(context: CasePanelContext)
	local listFrame = context.listFrame
	local refresh = context.refresh

	-- The reveal in flight. nil when idle; otherwise the reward being shown and the os.clock() the
	-- reel started at. Client-only, and deliberately NOT cleared by a re-render: an InventoryUpdate
	-- lands mid-animation (OpenCase grants before the reel finishes) and must not cut it short.
	local reveal: { reward: any, caseKey: string, startedAt: number }? = nil

	------------------------------------------------------------------
	-- Popups B — the full takeover
	------------------------------------------------------------------

	local function openTakeover(reward, caseKey: string)
		local color = rarityColor(reward.Rarity)

		local modal = Hud.modal({
			kind = "reveal",
			capColor = color, -- the cap IS the rarity; that is what `reveal` exists for
			width = TAKEOVER_WIDTH,
			actions = { {
				text = "Claim",
				onClick = function()
					reveal = nil
					refresh()
				end,
			} },
			onClose = function()
				-- Dismissed some other way (Escape, a future scrim click) — the reward is already
				-- granted, so this only has to put the tab back to a sane state.
				reveal = nil
				refresh()
			end,
		})

		-- Backstop for the straight edges. It does NOT save the 45-degree corners — Roblox clips to the
		-- rectangle, not to the sliced shape — which is why the backdrop below is sized to fit rather
		-- than relying on this.
		modal.surface.ClipsDescendants = true

		-- The diamond: a square rotated 45 degrees behind everything, as drawn.
		--
		-- SIZED TO FIT, not drawn at the mockup's 300. A rotated square's bounding box is side * sqrt2,
		-- so a 300 diamond occupies 424x424 — larger than the plate in both axes, and it hung out of
		-- the panel on every side. DIAMOND_SIDE is derived from the plate's width less both corner
		-- cuts, so it stays inside the angular silhouette at any TAKEOVER_WIDTH.
		Hud.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = 45,
			Size = UDim2.fromOffset(DIAMOND_SIDE, DIAMOND_SIDE),
			ZIndex = 0,
			Parent = modal.surface,
		}, { Hud.new("UIStroke", { Color = Hud.darken(color, 0.55), Thickness = 1 }) })

		-- The warm pool behind the prize. Roblox has no radial gradient, so this is a graded
		-- transparency on a rarity-tinted band — the same substitution the Forge's chamber makes.
		-- Inset by a corner cut at each side so the band stops where the diagonals begin. At full width
		-- its own square corners ran out past them.
		Hud.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -Hud.CORNER_CUT * 2, 0.7, 0),
			ZIndex = 0,
			Parent = modal.surface,
		}, { Hud.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.86),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}) })

		-- Everything below parents into the modal's content column at LayoutOrder 2, the slot its
		-- `body` would have taken — this reveal has no body text, it has a prize.
		-- AutomaticSize.Y, not a fixed height: the halo, the rarity, the name and the detail line add up
		-- to more than any number written here would stay right about, and a fixed 210 had the detail
		-- line spilling out through the bottom of the plate. The column above it is already
		-- layout-driven, so growing is free.
		local stage = Hud.new("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			Parent = modal.content,
		}, { Hud.new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, Hud.SPACE.S),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}) })

		-- The glow. Roblox has no bloom on a Frame, so it is three concentric plates fading outward —
		-- cheap, needs no art, and reads as light rather than as a thick border.
		local halo = Hud.new("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Size = UDim2.fromOffset(PRIZE_CARD.X + 36, PRIZE_CARD.Y + 36),
			Parent = stage,
		})

		for ring = 3, 1, -1 do
			Hud.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = color,
				BackgroundTransparency = 0.82 + ring * 0.05,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(PRIZE_CARD.X + ring * 12, PRIZE_CARD.Y + ring * 12),
				Parent = halo,
			}, { Hud.corner(Hud.RADIUS.Button) })
		end

		local card = Hud.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Hud.darken(Hud.COLOR.Panel, 0.1),
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(PRIZE_CARD.X, PRIZE_CARD.Y),
			Parent = halo,
		}, {
			Hud.corner(Hud.RADIUS.Button),
			Hud.new("UIStroke", { Color = color, Thickness = 2 }),
		})

		local icon = Hud.getItemIcon(reward.Key)
		if icon then
			Hud.new("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Image = icon,
				Position = UDim2.fromScale(0.5, 0.5),
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromOffset(40, 40),
				Parent = card,
			})
		else
			-- No art for this key yet: the rarity's own initial is a better centrepiece than an empty
			-- box, and it is still unmistakably keyed to what you won.
			Hud.new("TextLabel", {
				BackgroundTransparency = 1,
				Font = Hud.FONT.Display,
				Size = UDim2.fromScale(1, 1),
				Text = (ModConfig.Rarities[reward.Rarity] or {}).Badge or "?",
				TextColor3 = color,
				TextSize = 30,
				Parent = card,
			})
		end

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 20),
			Text = (reward.Rarity or ""):upper(),
			TextColor3 = color,
			TextSize = 15,
			Parent = stage,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Body,
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 20),
			Text = rewardName(reward),
			TextColor3 = Hud.COLOR.Text,
			TextSize = 16,
			Parent = stage,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Body,
			LayoutOrder = 4,
			Size = UDim2.new(1, 0, 0, 34),
			Text = rewardDetail(reward),
			TextColor3 = reward.Duplicate and Hud.COLOR.Good or Hud.COLOR.Muted,
			TextSize = 13,
			TextWrapped = true,
			Parent = stage,
		})

		-- The prize lands rather than appearing: a short scale-up from nothing, which is the only
		-- moving part the takeover needs once the reel has done the work of building tension.
		card.Size = UDim2.fromOffset(0, 0)
		TweenService:Create(
			card,
			TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(PRIZE_CARD.X, PRIZE_CARD.Y) }
		):Play()
	end

	------------------------------------------------------------------
	-- Popups A — the in-panel reel
	------------------------------------------------------------------

	-- A plausible rarity for a filler card, weighted by the case's own Odds so the reel looks like it
	-- belongs to the case you actually opened rather than to a generic one.
	local function fillerRarity(caseKey: string): string
		local case = CaseConfig.Cases[caseKey]
		local odds = case and case.Odds or nil
		if not odds then
			return "Common"
		end

		local total = 0
		for _, weight in pairs(odds) do
			total += weight
		end
		if total <= 0 then
			return "Common"
		end

		local roll = math.random() * total
		local cumulative = 0
		for _, rarityKey in ipairs(CaseConfig.RarityOrder) do
			cumulative += odds[rarityKey] or 0
			if roll <= cumulative then
				return rarityKey
			end
		end
		return "Common"
	end

	local function drawReel(body: Instance, reward, caseKey: string)
		local stage = Hud.new("Frame", {
			BackgroundColor3 = Hud.darken(Hud.COLOR.Panel, 0.35),
			BorderSizePixel = 0,
			ClipsDescendants = true, -- the strip is far wider than the panel; this is what makes it a reel
			Size = UDim2.fromOffset(BODY_WIDTH, BODY_HEIGHT),
			Parent = body,
		}, { Hud.corner(Hud.RADIUS.Panel), Hud.stroke() })

		-- The warm pool the cards ride through, same graded-transparency substitution as the takeover.
		Hud.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Hud.COLOR.AccentDark,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.55),
			Size = UDim2.new(1, -Hud.CORNER_CUT, 0.6, 0),
			Parent = stage,
		}, { Hud.corner(Hud.RADIUS.Panel), Hud.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.8),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}) })

		local strip = Hud.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0.5, -6),
			Size = UDim2.fromOffset(STRIP_CARDS * CARD_PERIOD, CARD_HEIGHT),
			Parent = stage,
		})

		-- Cards are anchored at their CENTRES, not their left edges. That is what lets the winner grow
		-- symmetrically about its own middle while it stays parked under the marker — anchored left, it
		-- grew rightwards and swallowed its neighbour.
		local cards = {}
		local winnerCard
		for index = 1, STRIP_CARDS do
			local isWinner = index == WINNER_INDEX
			local color = isWinner and rarityColor(reward.Rarity) or rarityColor(fillerRarity(caseKey))

			local cardFrame = Hud.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Hud.darken(Hud.COLOR.Panel, 0.15),
				BorderSizePixel = 0,
				Position = UDim2.new(0, (index - 1) * CARD_PERIOD + CARD_WIDTH / 2, 0.5, 0),
				Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
				Parent = strip,
			}, {
				Hud.corner(Hud.RADIUS.Button),
				-- Every card carries a rarity edge, the winner included: a card that looked different
				-- on the way past would give the result away before the reel stopped.
				Hud.new("UIStroke", { Color = color, Thickness = 1 }),
			})

			cards[index] = cardFrame
			if isWinner then
				winnerCard = cardFrame
			end
		end

		-- The ticker marker, over the cards.
		Hud.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Hud.COLOR.Accent,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 2, 1, 0),
			ZIndex = 3,
			Parent = stage,
		})

		local caption = Hud.new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.fromOffset(BODY_WIDTH - 40, 18),
			Text = "OPENING",
			TextColor3 = Hud.COLOR.Accent,
			TextSize = 12,
			ZIndex = 2,
			Parent = stage,
		})

		-- Where the strip has to end up for the winner's centre to sit under the marker.
		local centreX = BODY_WIDTH / 2
		local restX = centreX - ((WINNER_INDEX - 1) * CARD_PERIOD + CARD_WIDTH / 2)
		local startX = centreX - (CARD_WIDTH / 2) -- card 1 under the marker

		strip.Position = UDim2.new(0, startX, 0.5, -6)

		-- Elapsed rather than "start from zero": an InventoryUpdate re-renders this tab while the reel
		-- is running (OpenCase granted the reward before the first frame), and restarting the spin
		-- every time one arrives would make it stutter or never finish. Resuming from the phase the
		-- reveal actually started at makes a re-render invisible.
		local elapsed = math.clamp(os.clock() - reveal.startedAt, 0, REEL_SECONDS)
		local remaining = REEL_SECONDS - elapsed

		if remaining <= 0 then
			strip.Position = UDim2.new(0, restX, 0.5, -6)
			return
		end

		-- Quint ease-out: fast enough at the start to be a blur, slow enough at the end that the last
		-- two or three cards are readable as they crawl past. That deceleration IS the tension.
		local travelled = startX + (restX - startX) * (elapsed / REEL_SECONDS)
		strip.Position = UDim2.new(0, travelled, 0.5, -6)

		local spin = TweenService:Create(
			strip,
			TweenInfo.new(remaining, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0, restX, 0.5, -6) }
		)
		spin:Play()

		spin.Completed:Connect(function()
			-- The panel can be gone by now (tab switched, menu closed) — every step below has to
			-- tolerate that rather than erroring inside a tween callback where nothing would surface.
			if not stage.Parent or not reveal then
				return
			end

			caption.Text = (reward.Rarity or ""):upper()
			caption.TextColor3 = rarityColor(reward.Rarity)

			if winnerCard then
				-- The marker highlights whatever stopped under it: the landed card grows and takes a
				-- heavier edge. Doing this on ARRIVAL rather than at build time is what keeps the winner
				-- from being spottable while the reel is still moving.
				local stroke = winnerCard:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Thickness = 2
				end

				local pop = TweenInfo.new(POP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

				TweenService:Create(winnerCard, pop, {
					Size = UDim2.fromOffset(CARD_WIDTH + WINNER_GROW_X, CARD_HEIGHT + WINNER_GROW_Y),
				}):Play()

				-- The reel OPENS UP around the winner rather than the winner growing over the top of
				-- its neighbours. It takes WINNER_GROW_X more width, half of that on each side, so
				-- everything to its left slides half a growth left and everything to its right slides
				-- half a growth right — which keeps every gap in the strip exactly as it was.
				local shift = WINNER_GROW_X / 2
				for index, cardFrame in ipairs(cards) do
					if index ~= WINNER_INDEX then
						local direction = index < WINNER_INDEX and -1 or 1
						TweenService:Create(cardFrame, pop, {
							Position = cardFrame.Position + UDim2.fromOffset(direction * shift, 0),
						}):Play()
					end
				end
			end

			task.delay(LANDED_HOLD_SECONDS, function()
				if reveal and reveal.reward == reward then
					openTakeover(reward, caseKey)
				end
			end)
		end)
	end

	------------------------------------------------------------------
	-- States 1-3
	------------------------------------------------------------------

	local function formatClock(seconds: number): string
		seconds = math.max(math.floor(seconds), 0)
		if seconds >= 3600 then
			return ("%dh %02dm"):format(seconds // 3600, (seconds % 3600) // 60)
		end
		return ("%d:%02d"):format(seconds // 60, seconds % 60)
	end

	-- The decoded-but-unopened state: one control, deliberately oversized. Everything the tab could
	-- say at this point is noise next to the only thing you want to do.
	local function drawReadyToOpen(body: Instance, caseKey: string)
		local case = CaseConfig.Cases[caseKey]

		local stage = Hud.new("Frame", {
			BackgroundColor3 = Hud.darken(Hud.COLOR.Panel, 0.25),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(BODY_WIDTH, BODY_HEIGHT),
			Parent = body,
		}, { Hud.corner(Hud.RADIUS.Panel), Hud.new("UIStroke", { Color = Hud.COLOR.Accent, Thickness = 1 }) })

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.fromOffset(0, 46),
			Size = UDim2.new(1, 0, 0, 16),
			Text = "DECODED",
			TextColor3 = Hud.COLOR.Good,
			TextSize = 12,
			Parent = stage,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.fromOffset(0, 70),
			Size = UDim2.new(1, 0, 0, 28),
			Text = case and case.DisplayName or caseKey,
			TextColor3 = Hud.COLOR.Text,
			TextSize = Hud.TEXTSIZE.Title,
			Parent = stage,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Body,
			Position = UDim2.fromOffset(40, 104),
			Size = UDim2.new(1, -80, 0, 34),
			Text = "The machine is done. Nothing is rolled until you open it.",
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 13,
			TextWrapped = true,
			Parent = stage,
		})

		Hud.button({
			variant = "primary",
			text = "Open it",
			anchorPoint = Vector2.new(0.5, 0),
			position = UDim2.new(0.5, 0, 0, 152),
			size = UDim2.fromOffset(200, 52),
			parent = stage,
			onClick = function()
				local result = Remotes.OpenCase:InvokeServer()
				if not result.Success then
					Hud.showFailure("Couldn't open it", result.Reason)
					refresh() -- the tab's state may have moved on underneath us
					return
				end
				reveal = { reward = result.Reward, caseKey = result.CaseKey, startedAt = os.clock() }
				refresh()
			end,
		})
	end

	-- States 1 and 2, lifted VERBATIM out of MainHud's renderDecodeRow — same strings, same rows, same
	-- rejection texts. They are a list of cases and a countdown, which is what rows are for; the
	-- reveal is the part that needed to stop being a list.
	local function drawDecoding(body: Instance, job)
		local remaining = job.FinishTime - os.time()
		local case = CaseConfig.Cases[job.CaseKey]

		if remaining > 0 then
			Hud.makeRow(
				("Decoding: %s"):format(case and case.DisplayName or job.CaseKey),
				("Ready in %s"):format(formatClock(remaining)),
				"Working",
				function() end
			).Parent = body

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
					refresh()
				end
			).Parent = body

			Hud.makeRow(
				"Clean bypass — Robux",
				"Instant, no risk of corruption",
				"Robux",
				function()
					Hud.showFailure("Not set up", "The instant decode needs its product id filled into ShopConfig.lua first.")
				end
			).Parent = body
			return
		end

		-- The background loop resolves within a couple of seconds of the timer hitting zero — and it
		-- now hands over to the DECODED state rather than paying out, so this gap is the moment before
		-- the Open button appears.
		Hud.makeRow(
			("Decoding: %s"):format(case and case.DisplayName or job.CaseKey),
			"Finishing up...",
			"Wait",
			function() end
		).Parent = body
	end

	local function drawIdle(body: Instance)
		local cases = Hud.profile.Cases or {}
		local any = false

		local keys = {}
		for key in pairs(CaseConfig.Cases) do
			table.insert(keys, key)
		end
		table.sort(keys)

		for _, caseKey in ipairs(keys) do
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
						refresh()
					end
				).Parent = body
			end
		end

		if not any then
			Hud.makeRow(
				"Nothing to decode",
				"Buy a sealed case at the Black Market first",
				"OK",
				function() end
			).Parent = body
		end
	end

	------------------------------------------------------------------
	-- Render
	------------------------------------------------------------------

	local function render()
		-- State 4 wins over everything: once a reveal is running, the tab IS the reveal.
		if reveal then
			local body = Hud.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, BODY_HEIGHT),
				Parent = listFrame,
			})
			drawReel(body, reveal.reward, reveal.caseKey)
			return
		end

		local decoded = Hud.profile.DecodedCase
		if decoded and decoded.CaseKey then
			local body = Hud.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, BODY_HEIGHT),
				Parent = listFrame,
			})
			drawReadyToOpen(body, decoded.CaseKey)
			return
		end

		local job = Hud.profile.DecodeJob
		if job and job.FinishTime then
			drawDecoding(listFrame, job)
			return
		end

		drawIdle(listFrame)
	end

	return {
		render = render,
		-- True while the reel or the takeover is up. MainHud's once-a-second Decode refresh asks
		-- before re-rendering: a re-render is survivable mid-reel (the phase is recomputed from
		-- `startedAt`) but a needless one every second is churn nobody benefits from.
		isRevealing = function(): boolean
			return reveal ~= nil
		end,
	}
end

return CasePanel
