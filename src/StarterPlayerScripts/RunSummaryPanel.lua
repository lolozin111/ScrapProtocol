--[[
	RunSummaryPanel.lua
	The end-of-run screen: what your raid was worth, counted out one line at a time.

	"whenever a run ends... in sequence the run number pop up, like total scrap collected, total ore,
	time on the run, how many nodes defeated and all, all those cool stats so the player can check it
	out, like in the sonic videogames when a level is done it show your stats, and then on the end it
	adds the multiplier, it gives the player a dopamine boost."

	THE SEQUENCE IS THE POINT. A table of numbers that appears all at once is a receipt; the same
	numbers arriving one after another, each with its own little arrival, is a payoff. So every row
	starts invisible and is revealed on a stagger, the payout block lands after the stats, and the
	multiplier stamps on last — because the multiplier is the only line that turns one number into a
	bigger number, and it should be the thing you are watching when it does.

	Impatience is designed for rather than punished: clicking anywhere during the reveal finishes it
	instantly. Nobody should have to sit through a nine-line stagger on their fortieth run, and a
	skip that works is what makes a slow reveal acceptable in the first place.

	WHERE IT SITS IN THE FLOW. A clean Extract holds the player in the raid room while this is up —
	the server waits on a "CloseSummary" action before tearing the raid down (see RaidRoomService's
	completeRaid), so Continue is what actually sends you home. A Defeat or an Abandon has already
	torn down by the time this appears, and Continue just dismisses it; there is nothing left to wait
	for and holding a corpse in a finished room would only fight Roblox's respawn timer.

	Self-booting, like ModPicker/ShopPanel/TurretPanel: everything it builds parents into
	Hud.screenGui and it needs nothing from MainHud, so there is no constructor to thread.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Hud = require(script.Parent.HudKit)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RaidRoomAction = Remotes:WaitForChild("RaidRoomAction")

local COLOR, FONT, TEXTSIZE, SPACE = Hud.COLOR, Hud.FONT, Hud.TEXTSIZE, Hud.SPACE
local new = Hud.new

local RunSummaryPanel = {}

-- Reveal pacing. Deliberately quick per row — the drama is in the accumulation, not in any one
-- line, and a stagger slow enough to feel ceremonial on run one is unbearable by run ten.
local ROW_STAGGER = 0.11
local ROW_TWEEN = 0.18
local PAYOUT_GAP = 0.35 -- a held beat between the last stat and the money, so the money reads apart
local MULTIPLIER_GAP = 0.45 -- the longest pause in the sequence, right before the only line that multiplies

local OUTCOMES = {
	Extracted = { Title = "EXTRACTION COMPLETE", Color = COLOR.Good, Payout = "BANKED" },
	Defeated = { Title = "RUN FAILED", Color = COLOR.Bad, Payout = "LOST" },
	Abandoned = { Title = "RUN ABANDONED", Color = COLOR.Muted, Payout = "LEFT BEHIND" },
}

-- 1234567 -> "1,234,567". Damage totals across a long run get big enough that an unseparated run of
-- digits stops being readable at a glance, which defeats the purpose of showing it.
local function comma(value: number): string
	local text = tostring(math.floor(value + 0.5))
	local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function clock(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(math.floor(whole / 60), whole % 60)
end

----------------------------------------------------------------------
-- Build (once, at require time)
----------------------------------------------------------------------

local root = new("Frame", {
	Name = "RunSummary",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 420, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Visible = false,
	Parent = Hud.screenGui,
})

local shell, surface = Hud.plate({
	Size = UDim2.fromScale(1, 0),
	automaticSize = true,
	Parent = root,
})
shell.Name = "Plate"

new("UIPadding", {
	PaddingTop = UDim.new(0, SPACE.XL),
	PaddingBottom = UDim.new(0, SPACE.XL),
	PaddingLeft = UDim.new(0, SPACE.XL),
	PaddingRight = UDim.new(0, SPACE.XL),
	Parent = surface,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, SPACE.S),
	Parent = surface,
})

local titleLabel = new("TextLabel", {
	Name = "Title",
	LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
	Font = FONT.Display,
	Text = "",
	TextColor3 = COLOR.Text,
	TextSize = 26,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = surface,
})

local subtitleLabel = new("TextLabel", {
	Name = "Subtitle",
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 16),
	BackgroundTransparency = 1,
	Font = FONT.Body,
	Text = "",
	TextColor3 = COLOR.Muted,
	TextSize = TEXTSIZE.Label,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = surface,
})

-- Holds the staggered stat rows. Cleared and rebuilt per run rather than pooled: this screen is
-- shown once at the end of a raid, so there is nothing here worth the complexity of reuse.
local rowsFrame = new("Frame", {
	Name = "Rows",
	LayoutOrder = 3,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = surface,
})
new("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, SPACE.XS),
	Parent = rowsFrame,
})
new("UIPadding", { PaddingTop = UDim.new(0, SPACE.M), Parent = rowsFrame })

local continueButton = Hud.button({
	variant = "primary",
	text = "CONTINUE",
	size = UDim2.new(1, 0, 0, 40),
	onClick = function()
		RunSummaryPanel.Close()
	end,
})
continueButton.Name = "Continue"
continueButton.LayoutOrder = 4
continueButton.Parent = surface

-- Every reveal run carries a token. A second Show (or a Close mid-sequence) bumps it, and the
-- scheduled steps of the previous run all see a stale token and stop — otherwise a panel closed
-- half-way through would keep quietly fading rows in behind the scrim for another second.
local revealToken = 0
local revealing = false
local holdsForContinue = false

local function fadeIn(instance: Instance, targetTransparency: number, property: string)
	TweenService:Create(
		instance,
		TweenInfo.new(ROW_TWEEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ [property] = targetTransparency }
	):Play()
end

-- One stat line: label left, value right. `emphasis` promotes it to the payout treatment (accent
-- colour, display font, bigger) — used for the multiplier and the final total, which are the two
-- lines the whole sequence is building toward.
local function addRow(order: number, label: string, value: string, opts)
	opts = opts or {}
	local row = new("Frame", {
		Name = label,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, opts.emphasis and 30 or 22),
		BackgroundTransparency = 1,
		Parent = rowsFrame,
	}, {
		new("TextLabel", {
			Name = "Label",
			Size = UDim2.new(0.6, 0, 1, 0),
			BackgroundTransparency = 1,
			Font = opts.emphasis and FONT.DisplayMedium or FONT.Body,
			Text = label,
			TextColor3 = opts.labelColor or COLOR.Muted,
			TextSize = opts.emphasis and TEXTSIZE.Body or TEXTSIZE.Label,
			TextTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		new("TextLabel", {
			Name = "Value",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.4, 0, 1, 0),
			BackgroundTransparency = 1,
			-- Mono for the numbers: they are a readout, and a proportional font makes a column of
			-- them jitter as the digits change width.
			Font = opts.emphasis and FONT.Display or FONT.Mono,
			Text = value,
			TextColor3 = opts.valueColor or COLOR.Text,
			TextSize = opts.emphasis and TEXTSIZE.Readout + 4 or TEXTSIZE.Body,
			TextTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
	})
	return row
end

local function revealRow(row: Frame)
	fadeIn(row.Label, 0, "TextTransparency")
	fadeIn(row.Value, 0, "TextTransparency")
end

-- Show everything immediately, wherever the stagger had got to. Bumping the token first is what
-- stops the in-flight schedule from re-revealing rows underneath this.
local function finishReveal()
	revealToken += 1
	revealing = false
	for _, row in ipairs(rowsFrame:GetChildren()) do
		if row:IsA("Frame") then
			row.Label.TextTransparency = 0
			row.Value.TextTransparency = 0
		end
	end
end

----------------------------------------------------------------------
-- Show / Close
----------------------------------------------------------------------

function RunSummaryPanel.Show(summary)
	summary = summary or {}
	local outcome = OUTCOMES[summary.Outcome] or OUTCOMES.Abandoned
	holdsForContinue = summary.Outcome == "Extracted"

	for _, child in ipairs(rowsFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	titleLabel.Text = outcome.Title
	titleLabel.TextColor3 = outcome.Color
	subtitleLabel.Text = summary.Reason
		or ("%d node%s · %d map%s"):format(
			summary.NodesVisited or 0,
			(summary.NodesVisited == 1) and "" or "s",
			summary.MapsCleared or 0,
			(summary.MapsCleared == 1) and "" or "s")

	-- Order matters and is not alphabetical: time and ground covered first (what the run WAS), then
	-- what you did in it, then what you carried out. The money is last because the multiplier only
	-- lands as a payoff if everything it is multiplying has already been counted.
	local rows = {
		{ "TIME", clock(summary.Seconds or 0) },
		{ "NODES CLEARED", comma(summary.NodesVisited or 0) },
		{ "MAPS CLEARED", comma(summary.MapsCleared or 0) },
		{ "BOSSES DOWNED", comma(summary.BossesDefeated or 0) },
		{ "ENEMIES KILLED", comma(summary.Kills or 0) },
		{ "DAMAGE DEALT", comma(summary.DamageDealt or 0) },
		{ "BEST ROOM", comma(summary.BestRoomDamage or 0) },
		{ "SCRAP COLLECTED", comma(summary.ScrapCollected or 0) },
		{ "ORE RECOVERED", comma(summary.OreCollected or 0) },
		{ "CARDS TAKEN", comma(summary.CardsTaken or 0) },
	}

	local built = {}
	for index, entry in ipairs(rows) do
		table.insert(built, addRow(index, entry[1], entry[2]))
	end

	-- The payout tail. On a clean extract this is held -> multiplier -> banked, revealed in that
	-- order so the multiplier visibly acts on a number already on screen. On a loss there is no
	-- multiplier to show and the same pile is reported as what it cost.
	local payoutRows = {}
	local order = #rows
	if holdsForContinue then
		order += 1
		table.insert(payoutRows, addRow(order, "HELD", ("%d CB · %d Cores"):format(
			summary.HeldContraband or 0, summary.HeldCores or 0)))
		if (summary.Multiplier or 1) > 1 then
			order += 1
			table.insert(payoutRows, addRow(order, "BOSS MULTIPLIER", ("x%.2f"):format(summary.Multiplier),
				{ emphasis = true, valueColor = COLOR.Accent, labelColor = COLOR.Accent }))
		end
		order += 1
		table.insert(payoutRows, addRow(order, outcome.Payout, ("%d CB · %d Cores"):format(
			summary.Contraband or 0, summary.Cores or 0),
			{ emphasis = true, valueColor = COLOR.Good }))
	else
		order += 1
		table.insert(payoutRows, addRow(order, outcome.Payout, ("%d CB · %d Cores"):format(
			summary.HeldContraband or 0, summary.HeldCores or 0),
			{ emphasis = true, valueColor = COLOR.Bad }))
	end

	Hud.openPanel(root, { onClose = function()
		RunSummaryPanel.Close()
	end })
	root.Visible = true

	revealToken += 1
	local token = revealToken
	revealing = true

	task.spawn(function()
		for _, row in ipairs(built) do
			if revealToken ~= token then
				return
			end
			revealRow(row)
			task.wait(ROW_STAGGER)
		end
		task.wait(PAYOUT_GAP)
		for index, row in ipairs(payoutRows) do
			if revealToken ~= token then
				return
			end
			revealRow(row)
			-- The long pause sits BEFORE the multiplier and the total, not between every payout row.
			task.wait(index == 1 and MULTIPLIER_GAP or ROW_STAGGER)
		end
		if revealToken == token then
			revealing = false
		end
	end)
end

function RunSummaryPanel.Close()
	-- First click during the stagger skips it rather than closing. The button is the same button
	-- either way, so an impatient player presses it twice and gets exactly what they wanted both
	-- times: everything on screen, then gone.
	if revealing then
		finishReveal()
		return
	end

	revealToken += 1
	root.Visible = false
	Hud.closePanel(root)

	if holdsForContinue then
		-- The raid is still standing and the server is waiting on this to tear it down and send the
		-- player home. Cleared first so a double-click can't fire it twice; the server ignores a
		-- second one anyway (the state is gone), but not relying on that is cheaper than relying on it.
		holdsForContinue = false
		RaidRoomAction:FireServer("CloseSummary")
	end
end

return RunSummaryPanel
