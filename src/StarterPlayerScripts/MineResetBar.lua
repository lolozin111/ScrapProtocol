--[[
	MineResetBar.lua
	A slim top-centre progress bar for the dig-down mine's block-count reset (see
	MineShaftConfig.ResetBlockThreshold / MineShaftService.performReset) — "a 'loading' thing on the
	top ... how many blocks until the next reset," requested in exactly those terms.

	Self-booting (own top-level code, same precedent as ModPicker/ShopPanel/TurretPanel), but unlike
	BossBar.lua it does NOT own a dedicated ScreenGui/LAYER slot: it parents straight into
	Hud.screenGui (LAYER.Hud). This is ordinary HUD chrome, not a distinct game mode's overlay, and
	it must sit BELOW every panel (LAYER.Panel/Modal) instead of fighting them for a layer of its
	own — the same reasoning the mine's existing top-right depth panel already follows.

	Required from MineShaftController.client.lua (the other mine-shaft-specific client script)
	purely for the require side effect, exactly like that file already does for HudKit.

	VISIBILITY: only while the player is actually inside the mine, reusing MineShaftService's
	existing DepthUpdate signal (nil payload = not currently above a live shaft block) rather than
	inventing a second one — MainHud.client.lua's own `inMineShaft` flag is derived from that exact
	same event; this just listens to it independently instead of reaching into MainHud's locals.

	DATA: MineShaftService fires MineResetUpdate (new remote, declared in default.project.json)
	with { MinedCount, Threshold, Locked }, throttled to about once a second plus immediately on the
	two state transitions that actually matter (the reset lock starting, and the rebuilt mine coming
	back online) — see that file's broadcastResetProgress/RESET_PROGRESS_INTERVAL.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Hud = require(script.Parent.HudKit)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
-- Direct index, not WaitForChild — same convention MineShaftController.client.lua already uses for
-- MineShaftHit/MineFailed: by the time a client script runs, the Remotes folder (declared in
-- default.project.json) is already populated, and this is a client script, so a missing remote here
-- costs only this one panel rather than stalling server boot order the way DashService's
-- FindFirstChild guard protects against.
local DepthUpdate = Remotes.DepthUpdate
local MineResetUpdate = Remotes.MineResetUpdate

local MineResetBar = {}

----------------------------------------------------------------------
-- Layout — same top-centre plate()/accentCap() shape BossBar.lua uses for its bar, minus the
-- CanvasGroup drain/hold/fade sequence that one needs and this doesn't: visibility here is a plain
-- in-mine on/off toggle, not a multi-second death animation.
----------------------------------------------------------------------

local WIDTH_SCALE = 0.34 -- fraction of screen width; MAX_WIDTH caps it on a wide monitor
local MAX_WIDTH = 420
local REST_POSITION = UDim2.new(0.5, 0, 0, 16) -- same top-centre dock BossBar rests at; the two
	-- never show at once (no boss fight happens inside the mine shaft), so there's nothing to collide with
local TRACK_HEIGHT = 10

local FILL_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local root = Hud.new("Frame", {
	Name = "MineResetBar",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = REST_POSITION,
	Size = UDim2.new(WIDTH_SCALE, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Visible = false,
	Parent = Hud.screenGui,
})
Hud.new("UISizeConstraint", { MaxSize = Vector2.new(MAX_WIDTH, math.huge) }).Parent = root

local surface = Hud.plate({
	Name = "Plate",
	Size = UDim2.new(1, 0, 0, 0),
	automaticSize = true,
	Parent = root,
})

local accentBar = Hud.accentCap(surface, Hud.COLOR.Accent)

local body = Hud.new("Frame", {
	Name = "Body",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, Hud.SPACE.M, 0, accentBar.Size.Y.Offset + Hud.SPACE.S),
	Size = UDim2.new(1, -(Hud.SPACE.M * 2 + Hud.CORNER_CUT), 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Parent = surface,
}, {
	Hud.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, Hud.SPACE.XS) }),
	Hud.new("UIPadding", { PaddingBottom = UDim.new(0, Hud.SPACE.M) }),
})

local header = Hud.new("Frame", {
	Name = "Header",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 1,
	Parent = body,
})

Hud.new("TextLabel", {
	Name = "Tag",
	BackgroundTransparency = 1,
	Size = UDim2.new(0.5, 0, 1, 0),
	Font = Hud.FONT.BodyBold,
	Text = "MINE RESET",
	TextColor3 = Hud.COLOR.Accent,
	TextSize = Hud.TEXTSIZE.Label,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = header,
})

local readout = Hud.new("TextLabel", {
	Name = "Readout",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.new(0.7, 0, 1, 0),
	Font = Hud.FONT.Mono,
	Text = "",
	TextColor3 = Hud.COLOR.Text,
	TextSize = Hud.TEXTSIZE.Label,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = header,
})

local track = Hud.new("Frame", {
	Name = "Track",
	BackgroundColor3 = Hud.COLOR.Panel,
	Size = UDim2.new(1, 0, 0, TRACK_HEIGHT),
	LayoutOrder = 2,
	Parent = body,
}, { Hud.corner(Hud.RADIUS.Button) })

local fill = Hud.new("Frame", {
	Name = "Fill",
	BackgroundColor3 = Hud.COLOR.Accent,
	Size = UDim2.new(0, 0, 1, 0),
	Parent = track,
}, { Hud.corner(Hud.RADIUS.Button) })

----------------------------------------------------------------------
-- Number formatting — "5000" reads as a threshold you have to count digits on; "5,000" reads at a
-- glance. No existing shared helper does this anywhere in HudKit or the other panels (checked
-- before writing this), so it stays local here rather than adding a HudKit export for one caller.
----------------------------------------------------------------------

local function withCommas(value: number): string
	local text = tostring(math.floor(value))
	while true do
		local replaced, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		text = replaced
		if count == 0 then
			break
		end
	end
	return text
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------

local inMine = false
local latest: { MinedCount: number, Threshold: number, Locked: boolean }? = nil
local fillTween: Tween? = nil
local showing = false

function MineResetBar.IsShowing(): boolean
	return showing
end

local function setFillFraction(fraction: number)
	fraction = math.clamp(fraction, 0, 1)
	if fillTween then
		fillTween:Cancel()
	end
	fillTween = TweenService:Create(fill, FILL_TWEEN_INFO, { Size = UDim2.new(fraction, 0, 1, 0) })
	fillTween:Play()
end

local function refresh()
	showing = inMine and latest ~= nil
	root.Visible = showing
	if not showing then
		return
	end

	if (latest :: any).Locked then
		-- Mid-reset: the count itself is about to zero out, so a frozen/stale number would read as
		-- broken. Same "wait it out" message MineFailed's own resetting toast gives the click that
		-- gets rejected, just persistent instead of one-shot.
		readout.Text = "RESETTING…"
		accentBar.BackgroundColor3 = Hud.COLOR.Bad
		fill.BackgroundColor3 = Hud.COLOR.Bad
		setFillFraction(1)
		return
	end

	local threshold = math.max(1, (latest :: any).Threshold)
	local mined = math.clamp((latest :: any).MinedCount, 0, threshold)
	readout.Text = ("%s / %s BLOCKS"):format(withCommas(mined), withCommas(threshold))
	accentBar.BackgroundColor3 = Hud.COLOR.Accent
	fill.BackgroundColor3 = Hud.COLOR.Accent
	setFillFraction(mined / threshold)
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------

DepthUpdate.OnClientEvent:Connect(function(depth: number?)
	inMine = depth ~= nil
	refresh()
end)

MineResetUpdate.OnClientEvent:Connect(function(state: any)
	if typeof(state) ~= "table" then
		return
	end
	latest = state
	refresh()
end)

return MineResetBar
