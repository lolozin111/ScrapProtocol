--[[
	HudKit.lua
	The shared foundation every HUD panel is built out of: the palette, the Instance.new helpers,
	the ScreenGui, the client's mirror of the player's profile, the toast, and the row/tile builders.

	WHY THIS EXISTS: MainHud.client.lua grew to ~3,800 lines in a single chunk and hit Luau's hard
	limit of 200 locals per function scope — past which the script does not compile AT ALL, so the
	entire HUD was dead on join with only a cryptic "Out of local registers" to go on. Every panel
	added to that file spent more registers from the same budget.

	Moving shared pieces into ModuleScripts fixes that structurally: each module gets its own scope
	and its own 200, and a consumer spends ONE local (`local Hud = require(...)`) instead of one per
	helper. The point is only served if callers use `Hud.new` / `Hud.COLOR` directly rather than
	re-binding them to locals at the top of their file — that would just move the problem.

	`Hud.profile` is SHARED MUTABLE STATE and deliberately so: it is the client's mirror of the
	server profile, and every panel reads it. It must only ever be MUTATED (assigning into its
	fields), never REASSIGNED — every module holds a reference to the same table, so replacing it
	would leave them all pointed at a stale copy. Hud.MergeProfile is the only thing that writes it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RaidEnergyConfig = require(ReplicatedStorage.Shared.RaidEnergyConfig)
local Wallet = require(ReplicatedStorage.Shared.Wallet)

local LocalPlayer = Players.LocalPlayer

local HudKit = {}

HudKit.Remotes = ReplicatedStorage:WaitForChild("Remotes")
HudKit.LocalPlayer = LocalPlayer

----------------------------------------------------------------------
-- Palette
----------------------------------------------------------------------

-- Same rust/gunmetal family as the design doc, translated to Color3.
HudKit.COLOR = {
	Panel = Color3.fromRGB(30, 26, 23),
	PanelLight = Color3.fromRGB(40, 35, 31),
	Line = Color3.fromRGB(60, 53, 47),
	Text = Color3.fromRGB(237, 231, 220),
	Muted = Color3.fromRGB(167, 156, 140),
	Accent = Color3.fromRGB(224, 122, 59),
	AccentDark = Color3.fromRGB(178, 76, 24),
	Good = Color3.fromRGB(95, 160, 130),
	Bad = Color3.fromRGB(190, 90, 75),
}

local COLOR = HudKit.COLOR

----------------------------------------------------------------------
-- Instance helpers
----------------------------------------------------------------------

function HudKit.new(className: string, props, children)
	local inst = Instance.new(className)
	for key, value in pairs(props or {}) do
		inst[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	return inst
end

function HudKit.corner(radius: number?)
	return HudKit.new("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

function HudKit.stroke()
	return HudKit.new("UIStroke", { Color = COLOR.Line, Thickness = 1 })
end

HudKit.screenGui = HudKit.new("ScreenGui", {
	Name = "SalvageHUD",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = LocalPlayer:WaitForChild("PlayerGui"),
})

----------------------------------------------------------------------
-- Profile mirror
----------------------------------------------------------------------

-- Defaults matter: panels render before the first GetProfile/InventoryUpdate arrives, and reading
-- nil out of these would error rather than showing an empty state.
--
-- Fields that are legitimately absent most of the time (EquippedWeaponId, SmeltJob) are omitted on
-- purpose — nil reads correctly as "not set" whether the key is present-and-nil or missing, and the
-- server only ever sends them as `value or false` so a clear survives the wire.
HudKit.profile = {
	Scrap = 0, Cores = 0,
	OreCounts = {}, CraftedRobots = {}, DeployedRobots = {},
	CraftedStructures = {}, OwnedGamePasses = {},
	CraftedMods = {}, EquippedMods = {},
	Turrets = {}, UnlockedTurretBlueprints = {},
	Weapons = {}, ForgeTier = 1, LuckPotions = 0, ForgePityCounter = 0,
	RefinedOreCounts = {}, CoreItems = {},
	HighestWave = 0,
	Energy = RaidEnergyConfig.MaxEnergy,
	SuitTier = 1,
	ResearchTier = 1,
}

-- Applies an InventoryUpdate patch (or a full GetProfile snapshot). MUTATES in place — see this
-- file's header on why the table is never replaced.
function HudKit.MergeProfile(patch)
	for key, value in pairs(patch or {}) do
		HudKit.profile[key] = value
	end
end

----------------------------------------------------------------------
-- Toast
----------------------------------------------------------------------

-- Every failure path used to be a bare warn(), which writes to the Studio OUTPUT WINDOW and is
-- invisible to someone actually playing — so a refused action looked identical to a dead button.
local toastLabel = HudKit.new("TextLabel", {
	Name = "Toast",
	BackgroundColor3 = COLOR.Panel,
	Position = UDim2.new(0.5, 0, 0, 70),
	AnchorPoint = Vector2.new(0.5, 0),
	Size = UDim2.new(0, 420, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Visible = false,
	ZIndex = 20, -- above the craft/inventory panels, which is exactly when these fire
	Font = Enum.Font.SourceSans,
	Text = "",
	TextColor3 = COLOR.Text,
	TextSize = 16,
	TextWrapped = true,
	Parent = HudKit.screenGui,
}, { HudKit.corner(6), HudKit.stroke(), HudKit.new("UIPadding", {
	PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
}) })

-- The token guard means a newer toast always wins, rather than an older one's timer hiding it early.
local toastToken = 0

function HudKit.showToast(text: string, seconds: number?)
	toastToken += 1
	local myToken = toastToken
	toastLabel.Text = text
	toastLabel.Visible = true
	task.delay(seconds or 3.5, function()
		if toastToken == myToken then
			toastLabel.Visible = false
		end
	end)
end

-- Use for every rejected action instead of a bare warn(). Keeps the Output line (useful in Studio,
-- and it carries the context prefix) while ALSO telling the player something in-game. `reason`
-- comes straight from the server's { Success = false, Reason = ... } payload.
function HudKit.showFailure(context: string, reason: string?)
	local text = reason or "That didn't work."
	warn(("[HUD] %s: %s"):format(context, text))
	HudKit.showToast(text)
end

----------------------------------------------------------------------
-- Shared builders
----------------------------------------------------------------------

-- Optional icons: add an ImageLabel/ImageButton/Decal to ReplicatedStorage.ItemIcons named exactly
-- like the item key. FindFirstChild, never WaitForChild — a missing icon must fall back to the
-- text tile immediately rather than yielding the whole render.
local ItemIcons = ReplicatedStorage:FindFirstChild("ItemIcons")

function HudKit.getItemIcon(key: string): string?
	local inst = ItemIcons and ItemIcons:FindFirstChild(key)
	if not inst then
		return nil
	end
	if (inst:IsA("ImageLabel") or inst:IsA("ImageButton")) and inst.Image ~= "" then
		return inst.Image
	elseif inst:IsA("Decal") and inst.Texture ~= "" then
		return inst.Texture
	end
	return nil
end

-- Names and orders a cost table exactly the way the server resolves it — including refined
-- materials and CoreItems, which the HUD's own formatter used to render as raw keys.
function HudKit.costString(cost): string
	return Wallet.CostString(cost)
end

-- The standard list row: title, subtitle, and one action button. Used by every panel, which is why
-- it lives here rather than in whichever one happened to define it first.
function HudKit.makeRow(displayName: string, subtitle: string, buttonText: string, onClick)
	local row = HudKit.new("Frame", {
		BackgroundColor3 = COLOR.PanelLight,
		Size = UDim2.new(1, 0, 0, 52),
	}, { HudKit.corner(6) })

	HudKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 4),
		Size = UDim2.new(1, -110, 0, 20),
		Font = Enum.Font.SourceSansBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR.Text,
		TextSize = 16,
		Text = displayName,
		Parent = row,
	})

	HudKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 24),
		Size = UDim2.new(1, -110, 0, 20),
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR.Muted,
		TextSize = 13,
		Text = subtitle,
		Parent = row,
	})

	local button = HudKit.new("TextButton", {
		BackgroundColor3 = COLOR.Accent,
		Position = UDim2.new(1, -96, 0.5, -16),
		Size = UDim2.new(0, 86, 0, 32),
		Font = Enum.Font.SourceSansBold,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 14,
		Text = buttonText,
		Parent = row,
	}, { HudKit.corner(6) })
	button.MouseButton1Click:Connect(onClick)

	return row
end

return HudKit
