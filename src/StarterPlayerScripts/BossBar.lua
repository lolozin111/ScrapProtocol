--[[
	BossBar.lua
	A top-centre boss health bar for the Raid Rooms Boss node (RaidRoomService.beginBoss /
	CombatEncounterService.spawnEnemy). Self-booting, own ScreenGui — same precedent as
	ShopPanel/TurretPanel/ModPicker (build everything as top-level code on first require).

	HOW IT FINDS THE FIGHT: CombatEncounterService tags a boss's Model "Boss" and sets a
	"BossName" string Attribute BEFORE parenting it (see that file's spawnEnemy — its own comment
	literally names this file as the reader). Health/MaxHealth replicate for free off the
	Humanoid, so this needs no remote of its own: watch the tag, read the Humanoid.

	TAGGED-BEFORE-PARENTED IS LOAD-BEARING FOR THE TRACKING LOGIC: CollectionService's Added
	signal fires the instant the tag is applied, which is BEFORE model.Parent is set to Workspace.
	A naive "is this under Workspace" check at that exact moment would read false and silently
	drop the only boss in the fight. tryTrack instead waits on AncestryChanged for a tagged model
	that isn't under Workspace yet, rather than assuming the tag and the parent always land in the
	same signal.

	If several bosses are ever tagged at once, only the first live one found is tracked — the bar
	is one boss's health, not an aggregate.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Hud = require(script.Parent.HudKit)

local LocalPlayer = Players.LocalPlayer

local BossBar = {}
BossBar.VisibilityChanged = Instance.new("BindableEvent") -- fires (isShowing: boolean); RaidClient
	-- uses this to hide/restore its own room panel, which would otherwise sit redundantly on top
	-- of this bar with its own "Enemies remaining 1/1".

----------------------------------------------------------------------
-- Layout constants
----------------------------------------------------------------------

local BAR_WIDTH_SCALE = 0.6 -- fraction of screen width; MAX_WIDTH below caps it on a wide monitor
local MAX_WIDTH = 560
local REST_POSITION = UDim2.new(0.5, 0, 0, 16)
local ENTER_START_POSITION = UDim2.new(0.5, 0, 0, 0) -- 16px above rest; the slide-in distance

local HEADER_HEIGHT = 26
local TAG_RESERVE = 60 -- width reserved for the "BOSS" tag before the name starts
local READOUT_RESERVE = 140 -- width reserved on the right for "612 / 884" before the name truncates
local HP_BAR_HEIGHT = 18

local FADE_TWEEN_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local REAL_FILL_TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TRAIL_EASE_TWEEN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TRAIL_HOLD_SECONDS = 0.4 -- how long the lighter "damage taken" fill lingers before easing down
local DEATH_HOLD_SECONDS = 1 -- pause at 0 HP before fading the whole bar out

----------------------------------------------------------------------
-- Shell
----------------------------------------------------------------------

local screenGui = Hud.new("ScreenGui", {
	Name = "BossBarGui",
	DisplayOrder = Hud.LAYER.Boss, -- named layer table, HudKit.lua — previously the Roblox default
		-- (0), which ties with several other HUD ScreenGuis and leaves their paint order undefined
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = LocalPlayer:WaitForChild("PlayerGui"),
})

-- CanvasGroup, not a plain Frame, specifically so ONE GroupTransparency tween fades the whole
-- bar (shell art, both text labels, both bar fills) together. Fading each of those individually
-- would mean five-plus separate transparency tweens that have to agree on timing, which is
-- exactly the kind of drift this project's style guide calls out elsewhere (see HudKit's button
-- gradient comment on "one shared function or two implementations that drift"). Position/
-- AnchorPoint live HERE, not on the plate below — CanvasGroup composites its children into a
-- buffer sized to itself, so sliding a CHILD's Position within a fixed-size group would just
-- clip it against the group's own bounds instead of visibly moving.
local root = Hud.new("CanvasGroup", {
	Name = "Root",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = ENTER_START_POSITION,
	Size = UDim2.new(BAR_WIDTH_SCALE, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	GroupTransparency = 1,
	Visible = false,
	Parent = screenGui,
})
Hud.new("UISizeConstraint", { MaxSize = Vector2.new(MAX_WIDTH, math.huge) }).Parent = root

-- Same angular plate() shell the Sector Map uses, so a boss fight's HUD reads as the same house
-- style as everything else in the raid. Full width of `root` (which is already the scale+cap
-- combo), height automatic to its own content.
local surface, shell = Hud.plate({
	Name = "BossBar",
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
	Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
	LayoutOrder = 1,
	Parent = body,
})

Hud.new("TextLabel", {
	Name = "Tag",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 0, 0.5, 0),
	Size = UDim2.new(0, TAG_RESERVE, 1, 0),
	Font = Hud.FONT.BodyBold,
	Text = "BOSS",
	TextColor3 = Hud.COLOR.Accent,
	TextSize = Hud.TEXTSIZE.Label,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = header,
})

local nameLabel = Hud.new("TextLabel", {
	Name = "BossName",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, TAG_RESERVE, 0.5, 0),
	Size = UDim2.new(1, -(TAG_RESERVE + READOUT_RESERVE), 1, 0),
	Font = Hud.FONT.Display,
	Text = "",
	TextColor3 = Hud.COLOR.Text,
	TextSize = Hud.TEXTSIZE.Title,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = header,
})

local hpReadout = Hud.new("TextLabel", {
	Name = "HpReadout",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.new(0, READOUT_RESERVE, 1, 0),
	Font = Hud.FONT.Mono,
	Text = "",
	TextColor3 = Hud.COLOR.Text,
	TextSize = Hud.TEXTSIZE.Readout,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = header,
})

local barTrack = Hud.new("Frame", {
	Name = "HpTrack",
	BackgroundColor3 = Hud.COLOR.Panel,
	Size = UDim2.new(1, 0, 0, HP_BAR_HEIGHT),
	LayoutOrder = 2,
	Parent = body,
}, { Hud.corner(Hud.RADIUS.Button) })

-- Damage trail: a lighter copy of the fill, BEHIND the real fill (lower ZIndex), left at the
-- pre-hit width for TRAIL_HOLD_SECONDS so a big chunk of damage visibly reads as a chunk before
-- both bars agree again.
local trailFill = Hud.new("Frame", {
	Name = "DamageTrail",
	BackgroundColor3 = Hud.lighten(Hud.COLOR.Bad, 0.25),
	Size = UDim2.new(0, 0, 1, 0),
	ZIndex = 1,
	Parent = barTrack,
}, { Hud.corner(Hud.RADIUS.Button) })

local realFill = Hud.new("Frame", {
	Name = "Fill",
	BackgroundColor3 = Hud.COLOR.Bad,
	Size = UDim2.new(0, 0, 1, 0),
	ZIndex = 2,
	Parent = barTrack,
}, { Hud.corner(Hud.RADIUS.Button) })

----------------------------------------------------------------------
-- Tracking state
----------------------------------------------------------------------

local trackedBoss: Model? = nil
local trackedHumanoid: Humanoid? = nil
local connections: { RBXScriptConnection } = {}
local exiting = false -- true from the moment a drain/hold/fade-out sequence has started
local showing = false

local realTween: Tween? = nil
local trailTween: Tween? = nil
local trailHoldToken = 0 -- bumped on every hit so a stale delayed trail-ease never fires late
local sequenceToken = 0 -- bumped every time a NEW boss starts tracking; guards a delayed
	-- exit-sequence callback from acting after a different boss has already taken over the bar

local function setShowing(value: boolean)
	if showing == value then
		return
	end
	showing = value
	BossBar.VisibilityChanged:Fire(showing)
end

function BossBar.IsShowing(): boolean
	return showing
end

local function cancelTweens()
	if realTween then
		realTween:Cancel()
		realTween = nil
	end
	if trailTween then
		trailTween:Cancel()
		trailTween = nil
	end
end

local function disconnectAll()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	connections = {}
end

local function setBarFraction(fraction: number)
	fraction = math.clamp(fraction, 0, 1)
	realFill.Size = UDim2.new(fraction, 0, 1, 0)
	trailFill.Size = UDim2.new(fraction, 0, 1, 0)
end

local function updateReadout(health: number, maxHealth: number)
	-- Rounded up, never negative — a boss visually alive at 1 HP should never read "0 / X", and a
	-- dying tick should never flash a negative number before the death sequence takes over.
	local shownHealth = math.max(0, math.ceil(health))
	local shownMax = math.max(0, math.floor(maxHealth))
	hpReadout.Text = ("%d / %d"):format(shownHealth, shownMax)
end

-- `instant` snaps both fills straight to the new fraction (used on first show and on a MaxHealth
-- change) instead of running the hit-trail animation, which only makes sense for an actual loss
-- of health during the fight.
local function refreshHealth(instant: boolean?)
	if not trackedHumanoid then
		return
	end
	local health = math.max(0, trackedHumanoid.Health)
	local maxHealth = math.max(1, trackedHumanoid.MaxHealth)
	local fraction = health / maxHealth
	updateReadout(health, maxHealth)

	local previousFraction = realFill.Size.X.Scale
	if instant or fraction >= previousFraction then
		-- Heal, reset, or the very first frame: nothing to trail, snap both fills together.
		trailHoldToken += 1
		cancelTweens()
		setBarFraction(fraction)
		return
	end

	if realTween then
		realTween:Cancel()
	end
	realTween = TweenService:Create(realFill, REAL_FILL_TWEEN_INFO, { Size = UDim2.new(fraction, 0, 1, 0) })
	realTween:Play()

	trailHoldToken += 1
	local myTrailToken = trailHoldToken
	task.delay(TRAIL_HOLD_SECONDS, function()
		if myTrailToken ~= trailHoldToken or not trackedHumanoid then
			return -- superseded by a later hit (or the fight is already over)
		end
		if trailTween then
			trailTween:Cancel()
		end
		trailTween = TweenService:Create(trailFill, TRAIL_EASE_TWEEN_INFO, { Size = UDim2.new(fraction, 0, 1, 0) })
		trailTween:Play()
	end)
end

-- Forward-declared: beginExitSequence (right below) calls checkForNextBoss from inside a delayed
-- callback, before checkForNextBoss's own definition (which needs tryTrack/beginTrackingBoss,
-- defined further down still) — same declare-early/assign-later shape RaidClient.client.lua's own
-- `updateRaidButtons` uses, needed here for the same reason: Lua locals are only in scope from
-- their declaration onward, not backward into an earlier function.
local checkForNextBoss
local beginTrackingBoss
local tryTrack

-- The one teardown path for "this boss is gone", whether that's Health hitting 0 or the model
-- being untagged/destroyed (RaidRoomService destroys the model outright when the fight ends,
-- which may arrive before or without a HealthChanged tick ever reading exactly 0). Drains both
-- fills to 0, holds, fades the whole bar out, then hides and looks for another tagged boss.
local function beginExitSequence()
	cancelTweens()
	realTween = TweenService:Create(realFill, REAL_FILL_TWEEN_INFO, { Size = UDim2.new(0, 0, 1, 0) })
	realTween:Play()
	trailTween = TweenService:Create(trailFill, REAL_FILL_TWEEN_INFO, { Size = UDim2.new(0, 0, 1, 0) })
	trailTween:Play()
	updateReadout(0, trackedHumanoid and trackedHumanoid.MaxHealth or 0)

	local myToken = sequenceToken
	task.delay(DEATH_HOLD_SECONDS, function()
		if myToken ~= sequenceToken then
			return -- a new boss already took over the bar; don't fade it out from under them
		end
		local fadeOut = TweenService:Create(root, FADE_TWEEN_INFO, { GroupTransparency = 1 })
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			if myToken ~= sequenceToken then
				return
			end
			root.Visible = false
			root.Position = ENTER_START_POSITION
			root.GroupTransparency = 1
			trackedBoss = nil
			trackedHumanoid = nil
			setShowing(false)
			checkForNextBoss()
		end)
	end)
end

-- Only a genuinely live, in-world Model is trackable: `humanoid.Health > 0` filters out a boss
-- that's tagged but has already died in the instant before RaidRoomService destroys its model.
local function isLiveCandidate(inst: Instance): boolean
	if not inst:IsA("Model") then
		return false
	end
	local humanoid = inst:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

beginTrackingBoss = function(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[BossBar] Boss model '" .. model.Name .. "' has no Humanoid — skipping.")
		return
	end

	trackedBoss = model
	trackedHumanoid = humanoid
	exiting = false
	sequenceToken += 1

	local bossName = model:GetAttribute("BossName")
	nameLabel.Text = (typeof(bossName) == "string" and bossName ~= "" and bossName or model.Name):upper()

	cancelTweens()
	refreshHealth(true) -- snap to current HP before the bar is ever seen, no stale-value flash

	root.Visible = true
	root.Position = ENTER_START_POSITION
	root.GroupTransparency = 1
	TweenService:Create(root, FADE_TWEEN_INFO, { GroupTransparency = 0, Position = REST_POSITION }):Play()
	setShowing(true)

	table.insert(connections, humanoid.HealthChanged:Connect(function()
		if exiting or not trackedHumanoid then
			return
		end
		if trackedHumanoid.Health <= 0 then
			exiting = true
			disconnectAll()
			beginExitSequence()
			return
		end
		refreshHealth(false)
	end))
	table.insert(connections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		if not exiting then
			refreshHealth(true) -- a MaxHealth change isn't damage taken; snap, don't trail
		end
	end))
end

-- Returns true if `inst` ends up tracked (either immediately or once it lands under Workspace),
-- so checkForNextBoss can stop at the first one that takes.
tryTrack = function(inst: Instance): boolean
	if trackedBoss or not isLiveCandidate(inst) then
		return false
	end
	local model = inst :: Model
	if model:IsDescendantOf(Workspace) then
		beginTrackingBoss(model)
		return true
	end
	-- Tagged before parenting (see this file's header) — wait for it to actually land under
	-- Workspace instead of dropping it here forever. Also bails out cleanly if the model is
	-- destroyed/unparented before ever reaching Workspace.
	local conn
	conn = model.AncestryChanged:Connect(function()
		if trackedBoss then
			conn:Disconnect()
			return
		end
		if model:IsDescendantOf(Workspace) then
			conn:Disconnect()
			beginTrackingBoss(model)
		elseif not model.Parent then
			conn:Disconnect()
		end
	end)
	return true -- claimed asynchronously; checkForNextBoss should not also try the next candidate
end

checkForNextBoss = function()
	for _, inst in ipairs(CollectionService:GetTagged("Boss")) do
		if tryTrack(inst) then
			return
		end
	end
end

local function onBossRemoved(inst: Instance)
	if inst ~= trackedBoss or exiting then
		return -- not the tracked boss, or already mid drain/hold/fade from Health hitting 0
	end
	exiting = true
	disconnectAll()
	beginExitSequence()
end

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------

for _, inst in ipairs(CollectionService:GetTagged("Boss")) do
	if tryTrack(inst) then
		break
	end
end

CollectionService:GetInstanceAddedSignal("Boss"):Connect(tryTrack)
CollectionService:GetInstanceRemovedSignal("Boss"):Connect(onBossRemoved)

return BossBar
