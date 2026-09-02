--[[
	WeldingPanel.lua
	The Welding Station's Robots tab, rebuilt as HUD phase 3's "Rig Diagram" (design round,
	DESIGN_NOTES.md section C — the chosen direction is Welding A).

	WHAT CHANGED AND WHY. This tab used to be a flat list of `makeEquipmentRow`s: one 90px row per
	robot, with the three mod slots as three little buttons along the bottom of it. That layout said
	nothing about what a mod slot IS — three buttons in a row read as three more list items, not as
	three hardpoints on a machine. The brief for this phase was that the four station menus should
	stop being the same screen four times, and specifically that "Welding is about attaching mods to
	a weapon, so it wants the weapon and its slots on screen, not a list of mod names."

	So: the selected robot is drawn centre-stage as a line-drawing rig, its three mod slots are
	hardpoints ON that rig, and each hardpoint runs a dashed leader line out to a card naming what is
	fitted there. The list of robots survives as a left rail, split into what you have built and what
	you have not, because picking which robot you are looking at is still a list-shaped job.

	THE MOCKUP GOT ONE THING WRONG, DELIBERATELY NOT BUILT. It drew the third slot as "unlock 40
	cores". Robot mod slots are never locked: CraftingService's EquipMod only range-checks slotIndex
	against ModConfig.SlotsPerItem, so an empty slot means you have not fitted a mod, not that the
	slot needs buying. The empty card says "click to fit" instead. See DESIGN_NOTES.md's "Facts the
	mockups got wrong, corrected against the code" list.

	MODS ARE PER ROBOT TYPE, NOT PER DEPLOYED INSTANCE — see ModConfig.lua's header. Every deployed
	Scrapbot shares one loadout, which is why the rig shows one set of three slots however many
	copies you own, and why the stats footer is a per-robot number rather than a fleet total.

	NO NEW REMOTES. Everything here goes through what already existed: CraftItem("Robots", key),
	DeployRobot, UndeployRobot, and EquipMod via the shared ModPicker popup. The panel is pure
	presentation over Hud.profile, and every action it offers is re-checked server-side.

	ART. Each rig is DRAWN, out of stroked Frames, not loaded — see RIGS below. If a `rig_<robotKey>`
	entry ever lands in UiIconConfig, that image is used instead and the drawn chassis becomes the
	fallback, matching this project's "missing art never breaks the loop" rule.

	Extracted rather than added to MainHud.client.lua, for the reason that file's own header gives:
	it is back over 4,200 lines and its top-level local count has to leave room for the Forge rebuild
	that comes next. Constructor-shaped (not self-booting like ShopPanel/TurretPanel) because it
	renders into `listFrame`, which is and stays a MainHud local — the same reason InventoryPanel.new
	takes a context.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)
local ModConfig = require(ReplicatedStorage.Shared.ModConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local UiIconConfig = require(ReplicatedStorage.Shared.UiIconConfig)
local Wallet = require(ReplicatedStorage.Shared.Wallet)

local Hud = require(script.Parent.HudKit)
local ModPicker = require(script.Parent.ModPicker)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local WeldingPanel = {}

----------------------------------------------------------------------
-- Geometry
----------------------------------------------------------------------
-- Every number below is derived from the station's CONFIGURED panel size rather than written out,
-- for the same reason the Smelting tab's are: the plate is sized per station now
-- (StationConfig.PanelSize), and a hardcoded 760x520 here would silently stop filling the panel the
-- day that entry is retuned. The 116 is MainHud's header/tab stack above `listFrame` and the 12 is
-- the bottom margin the plate surface uses on its other edges — see craftFrame's vertical-stack
-- comment in MainHud.client.lua for where both come from. The 6 is the plate's 3px bevel on each
-- side; the 24 is listFrame's own left+right margins.
local PANEL_SIZE = StationConfig.Types.Welding.PanelSize or StationConfig.DefaultPanelSize

local RAIL_WIDTH = 186
local BODY_HEIGHT = PANEL_SIZE.Y - 116 - 12
local STAGE_WIDTH = PANEL_SIZE.X - 6 - 24 - RAIL_WIDTH - Hud.SPACE.M

-- The rig is drawn in a fixed 180x230 box, the same viewBox the design mockup's silhouettes use, so
-- every shape coordinate in RIGS below is transcribed rather than re-derived.
local RIG_WIDTH = 180
local RIG_HEIGHT = 230
local RIG_TOP = 56
local RIG_LEFT = math.floor((STAGE_WIDTH - RIG_WIDTH) / 2)
local RIG_RIGHT = RIG_LEFT + RIG_WIDTH

local CARD_WIDTH = 128
local CARD_HEIGHT = 68
local CARD_MARGIN = 10

-- Which side of the rig each slot's card sits on, and how far down. Slot 1 hangs off the left, 2 and
-- 3 stack down the right — the mockup's fan, which exists so three cards can point at three
-- hardpoints without any two leader lines crossing.
local CARD_LAYOUT = {
	{ side = "left", top = 158 },
	{ side = "right", top = 136 },
	{ side = "right", top = 222 },
}

local CARD_LEFT_X = CARD_MARGIN
local CARD_RIGHT_X = STAGE_WIDTH - CARD_MARGIN - CARD_WIDTH

-- Where a leader line turns the corner between its hardpoint and its card: halfway across the gap
-- between the rig box and the card, so the elbow always lands in empty space on both sides.
local BEND_LEFT = math.floor(((CARD_LEFT_X + CARD_WIDTH) + RIG_LEFT) / 2)
local BEND_RIGHT = math.floor((RIG_RIGHT + CARD_RIGHT_X) / 2)

local FOOTER_HEIGHT = 44
local FOOTER_TOP = BODY_HEIGHT - Hud.SPACE.M - FOOTER_HEIGHT

local RAIL_ROW_HEIGHT = 46
local RAIL_UNBUILT_ROW_HEIGHT = 54
local RAIL_BUILD_BUTTON_HEIGHT = 40

local RIG_STROKE = 2
local HARDPOINT_STROKE = 2

----------------------------------------------------------------------
-- Rig silhouettes
----------------------------------------------------------------------
-- One entry per robotKey in CraftingRecipes.Robots. `shapes` is a display list in the 180x230 box:
--   { "rect", x, y, w, h }        an outlined box (the chassis panels)
--   { "bar",  x, y, w, h, tint }  a solid bar (optic strips, mast, arc coils)
-- `hardpoints` is one { x, y, radius } per mod slot, in slot order. They are placed where the mod
-- would physically go on that chassis, which is the whole point of drawing the robot rather than
-- listing it: the arm mount, the chest core, the leg or turret mount.
--
-- WHY A DISPLAY LIST RATHER THAN A FUNCTION PER ROBOT: adding a Tier 5 rig should be one table
-- entry, the same way adding the robot itself is one CraftingRecipes entry — the flat-table-of-
-- named-strategies shape this project uses everywhere else. A key with no entry here falls through
-- to GENERIC_RIG rather than drawing nothing.
local RIGS = {
	Scrapbot = {
		shapes = {
			{ "bar", 86, 30, 3, 10, "line" }, -- bent antenna
			{ "rect", 68, 40, 40, 32 }, -- undersized head
			{ "bar", 80, 54, 8, 3, "optic" }, -- one eye; it only ever had the one
			{ "rect", 58, 78, 60, 62 }, -- torso
			{ "rect", 34, 88, 20, 38 }, -- a single arm, on the left
			{ "rect", 60, 140, 15, 44 },
			{ "rect", 100, 140, 15, 36 }, -- shorter right leg — this is the one that wobbles
		},
		hardpoints = { { 44, 107, 9 }, { 88, 104, 13 }, { 107, 158, 9 } },
	},
	SentryDrone = {
		shapes = {
			{ "rect", 36, 62, 22, 20 }, -- rotor housings, outboard and above the wing line
			{ "rect", 122, 62, 22, 20 },
			{ "rect", 26, 82, 42, 12 }, -- wings
			{ "rect", 112, 82, 42, 12 },
			{ "rect", 64, 104, 52, 44 }, -- body pod
			{ "bar", 76, 122, 10, 3, "optic" },
			{ "bar", 94, 122, 10, 3, "optic" },
			{ "rect", 78, 148, 24, 20 }, -- underslung sensor turret
			{ "bar", 88, 168, 4, 22, "line" }, -- barrel
		},
		hardpoints = { { 47, 88, 9 }, { 90, 126, 13 }, { 133, 88, 9 } },
	},
	-- Transcribed from the mockup's own SVG, coordinate for coordinate — this is the rig the design
	-- round actually drew, so it is the one that must not be reinterpreted.
	IronGuardian = {
		shapes = {
			{ "rect", 56, 34, 68, 46 }, -- head
			{ "bar", 74, 50, 10, 3, "optic" },
			{ "bar", 96, 50, 10, 3, "optic" },
			{ "rect", 48, 84, 84, 72 }, -- torso
			{ "rect", 30, 96, 18, 44 }, -- arms
			{ "rect", 132, 96, 18, 44 },
			{ "rect", 62, 156, 16, 42 }, -- legs
			{ "rect", 102, 156, 16, 42 },
		},
		hardpoints = { { 39, 118, 9 }, { 90, 110, 13 }, { 141, 118, 9 } },
	},
	ArcTurret = {
		shapes = {
			{ "rect", 40, 46, 16, 50 }, -- coil columns
			{ "rect", 124, 46, 16, 50 },
			{ "bar", 56, 52, 68, 3, "line" }, -- the arc jumping between them
			{ "bar", 56, 76, 68, 3, "line" },
			{ "rect", 52, 96, 76, 24 }, -- yoke
			{ "bar", 72, 106, 10, 3, "optic" },
			{ "bar", 98, 106, 10, 3, "optic" },
			{ "rect", 60, 120, 60, 56 }, -- housing
			{ "rect", 26, 176, 128, 36 }, -- base plinth — it does not walk anywhere
			{ "rect", 46, 212, 22, 12 },
			{ "rect", 112, 212, 22, 12 },
		},
		hardpoints = { { 48, 71, 9 }, { 90, 148, 13 }, { 132, 71, 9 } },
	},
}

-- Drawn for any robot with no RIGS entry. Deliberately a plain humanoid chassis rather than an empty
-- frame or a "?" tile: a Tier 5 robot added to CraftingRecipes before anyone draws its rig should
-- still get a usable Welding tab, per this project's missing-art rule.
local GENERIC_RIG = {
	shapes = {
		{ "rect", 60, 46, 60, 40 },
		{ "rect", 46, 96, 88, 76 },
		{ "rect", 26, 106, 20, 46 },
		{ "rect", 134, 106, 20, 46 },
		{ "rect", 62, 172, 18, 42 },
		{ "rect", 100, 172, 18, 42 },
	},
	hardpoints = { { 36, 129, 9 }, { 90, 124, 13 }, { 144, 129, 9 } },
}

----------------------------------------------------------------------
-- Small formatters
----------------------------------------------------------------------

-- "#E07A3B" for a Color3, so a RichText run can be tinted. Roblox's RichText color attribute takes a
-- hex string, not a Color3, and there is no built-in conversion.
local function hex(color: Color3): string
	return ("#%02X%02X%02X"):format(
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

-- A ModConfig multiplier as a signed percentage: 1.35 -> "+35%", 0.8 -> "-20%". Rounds away from
-- zero so a -0.4% never prints as "+0%".
local function signedPercent(multiplier: number): string
	local delta = (multiplier - 1) * 100
	return ("%+d%%"):format(delta >= 0 and math.floor(delta + 0.5) or math.ceil(delta - 0.5))
end

-- Compact "what this mod actually does" line for a slot card, e.g. "-30% dmg · +40% rate · -15% hp".
-- Built from the multipliers rather than the mod's authored Description because the Description is a
-- sentence ("+40% fire rate, -30% damage, -15% HP (HP penalty only matters on robots)") and this has
-- 110 pixels.
local function modEffectSummary(mod): string
	local parts = {}
	if mod.DamageMultiplier then
		table.insert(parts, signedPercent(mod.DamageMultiplier) .. " dmg")
	end
	if mod.FireRateMultiplier then
		table.insert(parts, signedPercent(mod.FireRateMultiplier) .. " rate")
	end
	if mod.HPMultiplier then
		table.insert(parts, signedPercent(mod.HPMultiplier) .. " hp")
	end
	if #parts == 0 then
		return "no stat change"
	end
	return table.concat(parts, " · ")
end

----------------------------------------------------------------------
-- Panel
----------------------------------------------------------------------

export type WeldingPanelContext = {
	listFrame: Instance, -- the craft plate's body; the tab renders one full-height Frame into it
	craftHeader: Instance, -- the plate's header bar, where the "DEPLOYED n / m" readout sits
	deployedCountForRobot: (string) -> number,
	refresh: () -> (), -- re-render the whole craft list (MainHud's renderCraftList)
}

function WeldingPanel.new(context: WeldingPanelContext)
	local listFrame = context.listFrame
	local deployedCountForRobot = context.deployedCountForRobot
	local refresh = context.refresh

	-- Which robot the stage is showing. Client-only UI state: it survives a re-render (every
	-- InventoryUpdate re-renders this tab) and is re-validated on each one in case the key stops
	-- existing.
	local selectedKey: string? = nil

	------------------------------------------------------------------
	-- Header readout: "DEPLOYED  2 / 3"
	------------------------------------------------------------------
	-- Lives in the panel HEADER rather than in the tab body because it is a station-wide fact, not a
	-- fact about the selected robot — the mockup puts it in the title bar for the same reason. Built
	-- once here and shown/hidden per tab rather than rebuilt per render: it is the only piece of this
	-- panel that outlives a renderCraftList sweep.
	local readout = Hud.new("Frame", {
		Name = "DeployedReadout",
		AnchorPoint = Vector2.new(1, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		-- Clear of the header's own 40px close button, plus a gap either side of this readout.
		Position = UDim2.new(1, -(40 + Hud.SPACE.S + Hud.SPACE.S), 0.5, 0),
		Size = UDim2.fromOffset(0, 20),
		Visible = false,
		Parent = context.craftHeader,
	}, { Hud.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Hud.SPACE.S),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}) })

	Hud.new("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Hud.FONT.Display,
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 20),
		Text = "DEPLOYED",
		TextColor3 = Hud.COLOR.Muted,
		TextSize = 11,
		Parent = readout,
	})

	local readoutValue = Hud.new("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Hud.FONT.Mono,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 20),
		Text = "",
		TextColor3 = Hud.COLOR.Good,
		TextSize = Hud.TEXTSIZE.Label,
		Parent = readout,
	})

	------------------------------------------------------------------
	-- Robot ordering and selection
	------------------------------------------------------------------

	local function ownedCount(key: string): number
		return (Hud.profile.CraftedRobots or {})[key] or 0
	end

	-- Built descending by tier (your best machine first, which is the one you came here to fit mods
	-- to) and not-built ascending (the cheapest next thing first, which is the one you can actually
	-- go and get). Two different questions, so two different sort orders.
	local function sortedKeys(): ({ string }, { string })
		local built, unbuilt = {}, {}
		for key in pairs(CraftingRecipes.Robots) do
			table.insert(ownedCount(key) > 0 and built or unbuilt, key)
		end
		table.sort(built, function(a, b)
			return CraftingRecipes.Robots[a].Tier > CraftingRecipes.Robots[b].Tier
		end)
		table.sort(unbuilt, function(a, b)
			return CraftingRecipes.Robots[a].Tier < CraftingRecipes.Robots[b].Tier
		end)
		return built, unbuilt
	end

	-- Mod-adjusted stats for one robot type. Goes through ModConfig.ApplyMods — the SAME function
	-- CombatMath.GetEffectiveStats calls server-side — rather than a second copy of the multiplier
	-- loop, so the number on this screen and the number WaveService fights with cannot drift.
	local function effectiveStats(key: string): (number, number, number)
		local recipe = CraftingRecipes.Robots[key]
		return ModConfig.ApplyMods(recipe.FireRate, recipe.BaseDamage, recipe.HP, key, Hud.profile)
	end

	------------------------------------------------------------------
	-- Rig drawing
	------------------------------------------------------------------

	-- One outlined box or solid bar from a RIGS display list. Outlines are a UIStroke on a
	-- transparent Frame (a line drawing, not a filled silhouette — that is what the mockup drew, and
	-- it is also what keeps a rig readable at this size).
	local function drawShape(parent: Instance, shape, lineColor: Color3, opticColor: Color3)
		local kind, x, y, w, h, tint = shape[1], shape[2], shape[3], shape[4], shape[5], shape[6]

		if kind == "bar" then
			Hud.new("Frame", {
				BackgroundColor3 = tint == "optic" and opticColor or lineColor,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(w, h),
				Parent = parent,
			})
			return
		end

		Hud.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			Parent = parent,
		}, { Hud.new("UIStroke", { Color = lineColor, Thickness = RIG_STROKE }) })
	end

	-- Draws the rig and returns its hardpoint centres in STAGE coordinates, so the leader lines
	-- (stage-level siblings, not rig children — they have to reach across into the cards) can start
	-- exactly on them.
	--
	-- `built` false draws the whole chassis in Line rather than Text: an unbuilt robot reads as a
	-- blueprint of itself, which is honest about it not existing yet without hiding what you would be
	-- getting for the cost on the rail.
	local function drawRig(stage: Instance, key: string, built: boolean): { Vector2 }
		local rig = RIGS[key] or GENERIC_RIG
		local lineColor = built and Hud.COLOR.Text or Hud.COLOR.Line
		local opticColor = built and Hud.COLOR.Good or Hud.COLOR.Line

		local holder = Hud.new("Frame", {
			Name = "Rig",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(RIG_LEFT, RIG_TOP),
			Size = UDim2.fromOffset(RIG_WIDTH, RIG_HEIGHT),
			Parent = stage,
		})

		-- If the silhouette art ever lands, it replaces the drawn chassis wholesale; the hardpoints
		-- below are drawn on top either way, since those are state (fitted / empty), not art.
		local image = UiIconConfig.Get("rig_" .. key) or UiIconConfig.Get("rig_generic")
		if image then
			Hud.new("ImageLabel", {
				BackgroundTransparency = 1,
				Image = image,
				ImageColor3 = lineColor,
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromScale(1, 1),
				Parent = holder,
			})
		else
			for _, shape in ipairs(rig.shapes) do
				drawShape(holder, shape, lineColor, opticColor)
			end
		end

		local centres = {}
		for slotIndex = 1, ModConfig.SlotsPerItem do
			-- A rig with fewer hardpoints than there are slots (a hand-written entry that fell behind
			-- a SlotsPerItem bump) borrows the generic rig's rather than dropping the slot silently —
			-- an unreachable mod slot is exactly the kind of quiet HUD failure this project keeps
			-- getting bitten by, so it warns rather than just vanishing.
			local point = rig.hardpoints[slotIndex] or GENERIC_RIG.hardpoints[slotIndex]
			if not point then
				warn(("[WeldingPanel] no hardpoint for slot %d on rig %s"):format(slotIndex, key))
				break
			end

			local filled = built and ModPicker.equippedModKeyForSlot(key, slotIndex) ~= nil
			local radius = point[3]

			Hud.new("Frame", {
				BackgroundColor3 = Hud.COLOR.Accent,
				BackgroundTransparency = filled and 0.82 or 1,
				Position = UDim2.fromOffset(point[1] - radius, point[2] - radius),
				Size = UDim2.fromOffset(radius * 2, radius * 2),
				Parent = holder,
			}, {
				Hud.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
				Hud.new("UIStroke", {
					Color = filled and Hud.COLOR.Accent or Hud.COLOR.Line,
					Thickness = HARDPOINT_STROKE,
				}),
			})

			centres[slotIndex] = Vector2.new(RIG_LEFT + point[1], RIG_TOP + point[2])
		end

		return centres
	end

	-- The dashed run from a hardpoint out to its card: out to the bend, up or down to the card's
	-- mid-height, then in to the card's near edge — collapsing to a single straight run when the
	-- hardpoint already sits at the card's height. Drawn at ZIndex 1 so the cards (2) sit over the
	-- line rather than the line crossing them.
	local function drawLeader(stage: Instance, from: Vector2, slotIndex: number)
		local layout = CARD_LAYOUT[slotIndex]
		local onLeft = layout.side == "left"
		local cardEdgeX = onLeft and (CARD_LEFT_X + CARD_WIDTH) or CARD_RIGHT_X
		local cardMidY = layout.top + CARD_HEIGHT / 2
		local bendX = onLeft and BEND_LEFT or BEND_RIGHT

		local function run(x1: number, x2: number, y: number)
			Hud.dashedLine(stage, {
				position = UDim2.fromOffset(math.min(x1, x2), y),
				length = math.abs(x2 - x1),
				axis = "X",
				zIndex = 1,
			})
		end

		if math.abs(from.Y - cardMidY) < 2 then
			run(from.X, cardEdgeX, math.floor(from.Y))
			return
		end

		run(from.X, bendX, math.floor(from.Y))
		Hud.dashedLine(stage, {
			position = UDim2.fromOffset(bendX, math.floor(math.min(from.Y, cardMidY))),
			length = math.abs(cardMidY - from.Y),
			axis = "Y",
			zIndex = 1,
		})
		run(bendX, cardEdgeX, math.floor(cardMidY))
	end

	------------------------------------------------------------------
	-- Slot cards
	------------------------------------------------------------------

	-- One mod slot, as a card at the far end of its leader line. A TextButton so the whole card is
	-- the hit target — clicking it opens the shared mod picker for that slot, which is the same popup
	-- (and the same EquipMod remote) the Inventory panel's detail view uses.
	local function drawSlotCard(stage: Instance, key: string, slotIndex: number, built: boolean)
		local layout = CARD_LAYOUT[slotIndex]
		local x = layout.side == "left" and CARD_LEFT_X or CARD_RIGHT_X
		local equippedKey = built and ModPicker.equippedModKeyForSlot(key, slotIndex) or nil
		local mod = equippedKey and ModConfig.Mods[equippedKey]

		local card = Hud.new("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = mod and Hud.COLOR.PanelLight or Hud.darken(Hud.COLOR.Panel, 0.2),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(x, layout.top),
			Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
			Text = "",
			ZIndex = 2,
			Parent = stage,
		}, { Hud.corner(Hud.RADIUS.Button) })

		if mod then
			Hud.new("UIStroke", { Color = Hud.COLOR.Accent, Thickness = 1, Parent = card })
		else
			-- Dashed, because that is what the design uses to mean "nothing fitted here yet" — and
			-- because a solid muted border would read the same as a fitted card at a glance.
			Hud.dashedBox(card, {
				width = CARD_WIDTH,
				height = CARD_HEIGHT,
				color = Hud.COLOR.Line,
				cornerInset = Hud.RADIUS.Button, -- the card is rounded; see cornerInset's own comment
				zIndex = 2,
			})
		end

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.fromOffset(9, 7),
			Size = UDim2.new(1, -18, 0, 12),
			Text = ("SLOT %d"):format(slotIndex),
			TextColor3 = mod and Hud.COLOR.Accent or Hud.COLOR.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 2,
			Parent = card,
		})

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Body,
			Position = UDim2.fromOffset(9, 22),
			Size = UDim2.new(1, -18, 0, 17),
			Text = mod and mod.DisplayName or "Empty",
			TextColor3 = mod and Hud.COLOR.Text or Hud.COLOR.Muted,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 2,
			Parent = card,
		})

		-- The mockup's third line on an empty slot read "unlock 40 cores". Slots are never locked —
		-- see this file's header. "Click to fit" is what the slot actually wants from you.
		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.fromOffset(9, 40),
			Size = UDim2.new(1, -18, 0, 22),
			Text = mod and modEffectSummary(mod) or (built and "click to fit" or "needs building"),
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 11,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 2,
			Parent = card,
		})

		if built then
			card.MouseButton1Click:Connect(function()
				ModPicker.openModPicker("Robots", key, slotIndex)
			end)
		end
	end

	------------------------------------------------------------------
	-- Footer
	------------------------------------------------------------------

	local function drawFooter(stage: Instance, key: string, built: boolean)
		local recipe = CraftingRecipes.Robots[key]
		local fireRate, damage, hp = effectiveStats(key)
		local modded = built
			and (fireRate ~= recipe.FireRate or damage ~= recipe.BaseDamage or hp ~= recipe.HP)

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.fromOffset(Hud.SPACE.M, FOOTER_TOP),
			Size = UDim2.fromOffset(240, 14),
			Text = modded and "WITH MODS" or "BASE STATS",
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = stage,
		})

		-- Each value is tinted Accent only if a fitted mod actually moved it, so "what did my loadout
		-- buy me" is answerable at a glance without a second before/after line competing with the rig
		-- for space.
		local accent = hex(Hud.COLOR.Accent)
		local function value(text: string, changed: boolean): string
			return changed and ('<font color="%s">%s</font>'):format(accent, text) or text
		end

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.fromOffset(Hud.SPACE.M, FOOTER_TOP + 16),
			RichText = true,
			Size = UDim2.fromOffset(300, 24),
			Text = ("%s  ×  %s  ·  %s"):format(
				value(("%.1f dmg"):format(damage), damage ~= recipe.BaseDamage),
				value(("%.1f/s"):format(fireRate), fireRate ~= recipe.FireRate),
				value(("%d hp"):format(math.floor(hp + 0.5)), hp ~= recipe.HP)
			),
			TextColor3 = Hud.COLOR.Text,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = stage,
		})

		if not built then
			-- No buttons for an unbuilt robot: the Build action lives on the rail (where the mockup
			-- puts it), so all the footer owes you here is the price.
			Hud.new("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Font = Hud.FONT.Mono,
				Position = UDim2.fromOffset(STAGE_WIDTH - Hud.SPACE.M, FOOTER_TOP + 12),
				Size = UDim2.fromOffset(240, 32),
				Text = Hud.costString(recipe.Cost),
				TextColor3 = Hud.COLOR.Muted,
				TextSize = Hud.TEXTSIZE.Label,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = stage,
			})
			return
		end

		local canDeployMore = deployedCountForRobot(key) < ownedCount(key)

		Hud.button({
			variant = "primary",
			text = "Fit mod",
			position = UDim2.fromOffset(STAGE_WIDTH - Hud.SPACE.M - 104, FOOTER_TOP + 4),
			size = UDim2.fromOffset(104, 40),
			parent = stage,
			onClick = function()
				-- The primary action of a Welding Station is fitting a mod, so it gets the primary
				-- button — but the slot cards are the real control, and this just opens the first one
				-- that is free (or slot 1 when the rig is full, so the button is never dead).
				for slotIndex = 1, ModConfig.SlotsPerItem do
					if not ModPicker.equippedModKeyForSlot(key, slotIndex) then
						ModPicker.openModPicker("Robots", key, slotIndex)
						return
					end
				end
				ModPicker.openModPicker("Robots", key, 1)
			end,
		})

		-- One button, two states, exactly as the old row had it: once every owned copy is on defense
		-- duty there is nothing left to deploy, so the only move left is pulling one back off.
		Hud.button({
			variant = "secondary",
			text = canDeployMore and "Deploy" or "Recall",
			position = UDim2.fromOffset(STAGE_WIDTH - Hud.SPACE.M - 104 - Hud.SPACE.S - 96, FOOTER_TOP + 4),
			size = UDim2.fromOffset(96, 40),
			parent = stage,
			onClick = function()
				if canDeployMore then
					local result = Remotes.DeployRobot:InvokeServer(key)
					if not result.Success then
						Hud.showFailure("Deploy failed", result.Reason)
					end
				else
					local result = Remotes.UndeployRobot:InvokeServer(key)
					if not result.Success then
						Hud.showFailure("Undeploy failed", result.Reason)
					end
				end
			end,
		})
	end

	------------------------------------------------------------------
	-- Left rail
	------------------------------------------------------------------

	local function makeRailLabel(text: string, order: number, parent: Instance)
		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 14),
			Text = text,
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = parent,
		})
	end

	local function makeRailRow(key: string, built: boolean, order: number, parent: Instance)
		local recipe = CraftingRecipes.Robots[key]
		local selected = selectedKey == key
		local height = built and RAIL_ROW_HEIGHT or RAIL_UNBUILT_ROW_HEIGHT

		local row = Hud.new("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = selected and Hud.COLOR.PanelLight or Hud.darken(Hud.COLOR.Panel, 0.2),
			BorderSizePixel = 0,
			LayoutOrder = order,
			Size = UDim2.fromOffset(RAIL_WIDTH, height),
			Text = "",
			Parent = parent,
		})

		-- Selection reads as an accent edge on the left — the same language the Smelting rail and
		-- ResearchPanel's active row already use, rather than a third way of saying "this one".
		Hud.new("Frame", {
			BackgroundColor3 = selected and Hud.COLOR.Accent or Hud.COLOR.Line,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 3, 1, 0),
			Parent = row,
		})

		if not built then
			-- Started 4px in so the dashed left edge does not sit on top of the selection strip above.
			-- The row itself is square, so no cornerInset.
			Hud.dashedBox(row, {
				position = UDim2.fromOffset(4, 0),
				width = RAIL_WIDTH - 4,
				height = height,
				color = Hud.COLOR.Line,
			})
		end

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.fromOffset(11, 6),
			Size = UDim2.new(1, -46, 0, 14),
			Text = recipe.DisplayName,
			TextColor3 = built and Hud.COLOR.Text or Hud.COLOR.Muted,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})

		Hud.new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.new(1, -10, 0, 6),
			Size = UDim2.fromOffset(30, 14),
			Text = ("t%d"):format(recipe.Tier),
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})

		if built then
			-- Three pips, one per mod slot, filled when something is fitted. The rail's whole job once
			-- you own several robots is "which of these still has a slot going spare", and three 15px
			-- bars answer that without opening each one.
			local pips = Hud.new("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(11, 28),
				Size = UDim2.new(1, -22, 0, 4),
				Parent = row,
			}, { Hud.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 3),
			}) })

			for slotIndex = 1, ModConfig.SlotsPerItem do
				Hud.new("Frame", {
					BackgroundColor3 = ModPicker.equippedModKeyForSlot(key, slotIndex)
						and Hud.COLOR.Accent
						or Hud.COLOR.Line,
					BorderSizePixel = 0,
					Size = UDim2.fromOffset(15, 4),
					Parent = pips,
				})
			end

			-- Only when there is more than one, so the common case stays a clean two-line row.
			if ownedCount(key) > 1 then
				Hud.new("TextLabel", {
					AnchorPoint = Vector2.new(1, 0),
					BackgroundTransparency = 1,
					Font = Hud.FONT.Mono,
					Position = UDim2.new(1, -10, 0, 24),
					Size = UDim2.fromOffset(40, 14),
					Text = ("x%d"):format(ownedCount(key)),
					TextColor3 = Hud.COLOR.Muted,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Right,
					Parent = row,
				})
			end
		else
			Hud.new("TextLabel", {
				BackgroundTransparency = 1,
				Font = Hud.FONT.Mono,
				Position = UDim2.fromOffset(11, 24),
				Size = UDim2.new(1, -22, 0, 26),
				Text = Hud.costString(recipe.Cost),
				TextColor3 = Hud.COLOR.Muted,
				TextSize = 11,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = row,
			})
		end

		row.MouseButton1Click:Connect(function()
			selectedKey = key
			refresh()
		end)
	end

	local function drawRail(parent: Instance, built: { string }, unbuilt: { string })
		local rail = Hud.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(0, RAIL_WIDTH, 1, -(RAIL_BUILD_BUTTON_HEIGHT + Hud.SPACE.S)),
			Parent = parent,
		}, { Hud.new("UIListLayout", {
			Padding = UDim.new(0, Hud.SPACE.XS + 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}) })

		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end

		if #built > 0 then
			makeRailLabel("BUILT", nextOrder(), rail)
			for _, key in ipairs(built) do
				makeRailRow(key, true, nextOrder(), rail)
			end
		end

		if #unbuilt > 0 then
			if #built > 0 then
				Hud.new("Frame", {
					BackgroundColor3 = Hud.COLOR.Line,
					BorderSizePixel = 0,
					LayoutOrder = nextOrder(),
					Size = UDim2.new(1, 0, 0, 1),
					Parent = rail,
				})
			end
			makeRailLabel("NOT BUILT", nextOrder(), rail)
			for _, key in ipairs(unbuilt) do
				makeRailRow(key, false, nextOrder(), rail)
			end
		end

		if #unbuilt == 0 then
			return
		end

		-- The build button targets whatever is selected when that is something unbuilt, and otherwise
		-- the cheapest thing you have not built — so it is always a live offer rather than a control
		-- that goes dead the moment you click a robot you already own.
		local target = (table.find(unbuilt, selectedKey) and selectedKey or unbuilt[1]) :: string
		local recipe = CraftingRecipes.Robots[target]

		Hud.button({
			variant = Wallet.CanAfford(Hud.profile, recipe.Cost) and "primary" or "secondary",
			text = ("Build %s"):format(recipe.DisplayName),
			anchorPoint = Vector2.new(0, 1),
			position = UDim2.new(0, 0, 1, 0),
			size = UDim2.fromOffset(RAIL_WIDTH, RAIL_BUILD_BUTTON_HEIGHT),
			parent = parent,
			onClick = function()
				-- Deliberately NOT gated client-side on affordability: CraftItem re-checks the cost
				-- anyway, and its rejection names the material you are short of, which is more use
				-- than a button that silently does nothing.
				local result = Remotes.CraftItem:InvokeServer("Robots", target)
				if not result.Success then
					Hud.showFailure("Build failed", result.Reason)
				end
			end,
		})
	end

	------------------------------------------------------------------
	-- Render
	------------------------------------------------------------------

	local function render()
		local built, unbuilt = sortedKeys()

		-- Re-validated every render rather than trusted: a key can stop being owned, or stop existing
		-- at all, between one render and the next.
		if not selectedKey or not CraftingRecipes.Robots[selectedKey] then
			selectedKey = built[1] or unbuilt[1]
		end

		local maxSlots = CraftingRecipes.MaxDeployedRobots(Hud.profile)
		local deployedTotal = #(Hud.profile.DeployedRobots or {})
		readoutValue.Text = ("%d / %d"):format(deployedTotal, maxSlots)
		readoutValue.TextColor3 = deployedTotal < maxSlots and Hud.COLOR.Good or Hud.COLOR.Muted
		readout.Visible = true

		local body = Hud.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, BODY_HEIGHT),
			Parent = listFrame,
		})

		drawRail(body, built, unbuilt)

		local stage = Hud.new("Frame", {
			BackgroundColor3 = Hud.darken(Hud.COLOR.Panel, 0.15),
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(RAIL_WIDTH + Hud.SPACE.M, 0),
			Size = UDim2.new(1, -(RAIL_WIDTH + Hud.SPACE.M), 1, 0),
			Parent = body,
		}, { Hud.corner(Hud.RADIUS.Panel), Hud.stroke() })

		if not selectedKey then
			-- Only reachable if CraftingRecipes.Robots is empty, which would be a config mistake
			-- rather than a state a player can get into — but a blank stage with no explanation is
			-- exactly the "I click and nothing happens" failure this project keeps hitting.
			Hud.new("TextLabel", {
				BackgroundTransparency = 1,
				Font = Hud.FONT.Body,
				Position = UDim2.fromOffset(Hud.SPACE.L, Hud.SPACE.L),
				Size = UDim2.new(1, -Hud.SPACE.L * 2, 0, 40),
				Text = "No robots are configured.",
				TextColor3 = Hud.COLOR.Muted,
				TextSize = Hud.TEXTSIZE.Body,
				TextWrapped = true,
				Parent = stage,
			})
			return
		end

		local key = selectedKey :: string
		local recipe = CraftingRecipes.Robots[key]
		local isBuilt = ownedCount(key) > 0
		local deployed = deployedCountForRobot(key)

		local titleRow = Hud.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Hud.SPACE.L, 10),
			Size = UDim2.new(1, -Hud.SPACE.L * 2, 0, 26),
			Parent = stage,
		}, { Hud.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 9),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}) })

		Hud.new("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			LayoutOrder = 1,
			Size = UDim2.fromOffset(0, 26),
			Text = recipe.DisplayName,
			TextColor3 = Hud.COLOR.Text,
			TextSize = Hud.TEXTSIZE.Title,
			Parent = titleRow,
		})

		local status, statusColor
		if not isBuilt then
			status, statusColor = "not built", Hud.COLOR.Muted
		elseif deployed > 0 then
			status, statusColor = ("deployed ×%d"):format(deployed), Hud.COLOR.Good
		else
			status, statusColor = "in storage", Hud.COLOR.Muted
		end

		Hud.new("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			LayoutOrder = 2,
			Size = UDim2.fromOffset(0, 26),
			Text = status,
			TextColor3 = statusColor,
			TextSize = Hud.TEXTSIZE.Label,
			Parent = titleRow,
		})

		local centres = drawRig(stage, key, isBuilt)
		for slotIndex = 1, ModConfig.SlotsPerItem do
			-- CARD_LAYOUT hand-places three cards around a 180x230 rig; a fourth would have nowhere to
			-- go that does not collide with the other three, so a SlotsPerItem bump needs a layout
			-- decision, not just another loop iteration. Warn rather than erroring inside the render.
			if not CARD_LAYOUT[slotIndex] then
				warn(("[WeldingPanel] no card position for mod slot %d — add one to CARD_LAYOUT"):format(slotIndex))
				break
			end
			if centres[slotIndex] then
				drawLeader(stage, centres[slotIndex], slotIndex)
				drawSlotCard(stage, key, slotIndex, isBuilt)
			end
		end

		drawFooter(stage, key, isBuilt)
	end

	return {
		render = render,
		-- Called by renderCraftList when it renders any OTHER tab: the readout lives in the shared
		-- panel header, which that sweep does not clear, so it would otherwise sit there claiming a
		-- deploy count over the Mods or Turrets tab.
		hideReadout = function()
			readout.Visible = false
		end,
	}
end

return WeldingPanel
