--[[
	WeldingPanel.lua
	All four of the Welding Station's tabs — Robots, Mods, Turrets, Drones. The Robots tab is HUD
	phase 3's "Rig Diagram" (design round, DESIGN_NOTES.md section C — the chosen direction is
	Welding A); the other three are that direction carried across the rest of the station.

	WHAT CHANGED AND WHY. Robots used to be a flat list of `makeEquipmentRow`s: one 90px row per
	robot, with the three mod slots as three little buttons along the bottom of it. That layout said
	nothing about what a mod slot IS — three buttons in a row read as three more list items, not as
	three hardpoints on a machine. The brief for this phase was that the four station menus should
	stop being the same screen four times, and specifically that "Welding is about attaching mods to
	a weapon, so it wants the weapon and its slots on screen, not a list of mod names."

	So: the selected robot is drawn centre-stage as a line-drawing rig, its three mod slots are
	hardpoints ON that rig, and each hardpoint runs a dashed leader line out to a card naming what is
	fitted there. The list of robots survives as a left rail, split into what you have built and what
	you have not, because picking which robot you are looking at is still a list-shaped job.

	THE OTHER THREE TABS HAD NO MOCKUP — the design round only ever drew the Robots tab for this
	station. Rather than invent three more directions, they take the shape that round produced, which
	by then was the station's identity: a rail of candidates on the left, the selected one rendered
	large on the right with its real numbers, and its action in the footer. What each stage DRAWS is
	the part that differs, and in every case it is the thing the old row list could not say:

	- Mods — every mod in this game is a TRADE, and a row could only print its authored sentence and
	  its price. The stage draws each multiplier as a bar running out from a 1.0x centre line, right
	  in Good for a buff and left in Bad for a nerf, so the trade is a shape rather than a sentence.
	  Underneath it lists WHERE the mod is currently fitted, which is otherwise near-impossible to
	  reconstruct: mods are per item TYPE and can sit in any of three slots on any robot or weapon.
	- Turrets — six types differing on four axes at once. "30 dmg · 95 range · 0.35/s · 5 AOE" in a
	  subtitle is not something anyone compares against another row's four numbers, which is exactly
	  what choosing a turret is. They are bars, scaled against the best in class, plus a segmentBar
	  of your actual base-defense slots so "can I even place another" is answered on the same screen.
	- Drones — one Core slotted at a time out of four, so it is a loadout screen, not a catalogue.
	  The drone is drawn on the same chassis machinery the robots use, with a SINGLE hardpoint at its
	  core bay. That the bay holds one thing is then something you can see rather than be told.

	The rail, the stage title, the stat bars and the footer are one implementation each, shared by
	all four tabs — four near-identical copies is exactly how the old `makeRow` lists drifted into
	stating a cost four slightly different ways.

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
	it had grown back over 4,200 lines and its top-level local count has to leave room for the Forge
	rebuild that comes next. Constructor-shaped (not self-booting like ShopPanel/TurretPanel) because
	it renders into `listFrame`, which is and stays a MainHud local — the same reason
	InventoryPanel.new takes a context.

	ROUTING. `render(tab)` takes the tab name. Robots/Mods/Turrets/Drones are declared by no other
	station (StationConfig.Types), so MainHud routes all four here on the name alone.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)
local DroneConfig = require(ReplicatedStorage.Shared.DroneConfig)
local ModConfig = require(ReplicatedStorage.Shared.ModConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local TurretConfig = require(ReplicatedStorage.Shared.TurretConfig)
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

local RAIL_ROW_HEIGHT = 46 -- a row whose second line is the pip strip
local RAIL_TALL_ROW_HEIGHT = 54 -- a row whose second line is wrapped text (a cost, an effect)
local RAIL_BUILD_BUTTON_HEIGHT = 40
local RAIL_SCROLLBAR = 4
-- Rows are laid out inside a ScrollingFrame, so they have to leave the scrollbar its lane or the
-- bar draws on top of every row's right edge.
local RAIL_ROW_WIDTH = RAIL_WIDTH - RAIL_SCROLLBAR

local RIG_STROKE = 2
local HARDPOINT_STROKE = 2

-- Stat bars (Mods' trade-off bars, Turrets' profile bars). One geometry for both so the two tabs
-- read as the same instrument at the same place on screen.
local BAR_ROW_HEIGHT = 28
local BAR_LABEL_WIDTH = 96
local BAR_TRACK_X = Hud.SPACE.L + BAR_LABEL_WIDTH + Hud.SPACE.M
local BAR_TRACK_WIDTH = 250
local BAR_HEIGHT = 10
local BAR_VALUE_WIDTH = 120

-- What a full half of a signed (centred) bar means. Fixed rather than scaled to the biggest mod in
-- the table, so the bars mean the same thing on every mod's screen and two mods can be compared by
-- remembering the shape rather than re-reading the axis. 0.5 = +/-50%, which comfortably contains
-- every multiplier ModConfig currently ships (the widest is Overclocked Core's +40% / -30%).
local SIGNED_BAR_FULL_SCALE = 0.5

local FOOTER_VALUE_WIDTH = 300

-- The best of each turret stat across every type, so the Turrets tab's bars are proportions of
-- "the best in class" rather than of an arbitrary ceiling. Computed once at require time: the
-- table is static config and recomputing it per render would be four loops a frame for a number
-- that cannot change.
local TURRET_STAT_MAX = (function()
	local max = { Damage = 1, Range = 1, FireRate = 1, AOE = 1 }
	for key in pairs(TurretConfig.Types) do
		local stats = TurretConfig.GetTurretEffectiveStats(key, 1)
		if stats then
			max.Damage = math.max(max.Damage, stats.Damage)
			max.Range = math.max(max.Range, stats.Range)
			max.FireRate = math.max(max.FireRate, stats.FireRate)
			max.AOE = math.max(max.AOE, stats.AOE)
		end
	end
	return max
end)()

-- The drone's chassis sits left of centre with its single card on the right, positioned so the
-- leader line between them is dead straight — there is only one hardpoint, so there is no fan to
-- arrange and no reason to bend anything.
local DRONE_ORIGIN = Vector2.new(120, 96)
local DRONE_SIZE = Vector2.new(150, 140)
local DRONE_CARD_LAYOUT = { side = "right", top = 151 } -- mid-height 185 = the bay hardpoint's y

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

-- The drone's chassis, in a 150x140 box. One hardpoint, at the core bay under its belly — you get
-- exactly one Core slotted at a time, and a single socket drawn on the machine says that better
-- than a sentence does.
local DRONE_RIG = {
	shapes = {
		{ "rect", 12, 4, 30, 4 }, -- rotor discs
		{ "rect", 108, 4, 30, 4 },
		{ "bar", 25, 8, 3, 8, "line" }, -- masts
		{ "bar", 122, 8, 3, 8, "line" },
		{ "rect", 8, 16, 34, 12 }, -- rotor arms
		{ "rect", 108, 16, 34, 12 },
		{ "bar", 40, 34, 20, 3, "line" }, -- shoulders joining the arms to the pod
		{ "bar", 90, 34, 20, 3, "line" },
		{ "rect", 45, 30, 60, 40 }, -- body pod
		{ "bar", 57, 44, 10, 3, "optic" },
		{ "bar", 83, 44, 10, 3, "optic" },
		{ "rect", 58, 78, 34, 22 }, -- core bay housing
		{ "bar", 74, 100, 3, 14, "line" }, -- sensor stalk
	},
	hardpoints = { { 75, 89, 14 } },
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

-- One row of the left rail. A row shows a title, an optional right-aligned badge, and then EITHER a
-- `pips` strip (Robots uses it for "which mod slots are filled") or a wrapped `subtitle` (everything
-- else uses it for a cost or an effect), never both — two second lines would not fit, and choosing
-- between them is the tab's decision rather than the rail's.
export type RailRow = {
	key: string,
	title: string,
	badge: string?,
	badgeColor: Color3?,
	subtitle: string?,
	pips: { boolean }?,
	dashed: boolean?, -- the "you do not have this yet" treatment: dashed border, muted title
}

export type RailSection = { heading: string, rows: { RailRow } }

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

	-- Which row each tab's stage is showing, keyed by tab name. Client-only UI state: it survives a
	-- re-render (every InventoryUpdate re-renders the open tab) and is re-validated on each one in
	-- case the key stops existing. Per TAB, not one shared value, so switching Robots -> Mods -> Robots
	-- comes back to the robot you were looking at rather than resetting to the top of the list.
	local selected: { [string]: string? } = {}

	------------------------------------------------------------------
	-- Header readout: the station-wide fact for whichever tab is open
	------------------------------------------------------------------
	-- "DEPLOYED 2 / 3" on Robots, "SLOTS 1 / 2" on Turrets, and so on — one number per tab that is
	-- true of the STATION rather than of the selected row, which is why it lives in the panel header
	-- rather than inside the tab body (the mockup puts the deploy count in the title bar for the same
	-- reason). Built once here and relabelled per render rather than rebuilt: it is the only piece of
	-- this panel that outlives a renderCraftList sweep.
	local readout = Hud.new("Frame", {
		Name = "StationReadout",
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

	local readoutLabel = Hud.new("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Hud.FONT.Display,
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 20),
		Text = "",
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

	-- `good` is what the value means, not what colour it is: a count with room left in it reads
	-- Good, one that is full or empty reads Muted. Callers pass the meaning, not the palette entry,
	-- so a retune stays in one place.
	local function setReadout(label: string, value: string, good: boolean)
		readoutLabel.Text = label
		readoutValue.Text = value
		readoutValue.TextColor3 = good and Hud.COLOR.Good or Hud.COLOR.Muted
		readout.Visible = true
	end

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
	--
	-- Takes the spec rather than a robot key so the Drones tab can hand it a drone chassis with one
	-- hardpoint instead of a robot with three. `iconKey` is the UiIconConfig lookup, `origin`/`size`
	-- place the box inside the stage, and `isFilled(index)` says whether each hardpoint is occupied.
	-- Returns each hardpoint's centre in STAGE coordinates.
	local function drawChassis(stage: Instance, spec, opts: {
		iconKey: string,
		origin: Vector2,
		size: Vector2,
		built: boolean,
		isFilled: (number) -> boolean,
	}): { Vector2 }
		local lineColor = opts.built and Hud.COLOR.Text or Hud.COLOR.Line
		local opticColor = opts.built and Hud.COLOR.Good or Hud.COLOR.Line

		local holder = Hud.new("Frame", {
			Name = "Chassis",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(opts.origin.X, opts.origin.Y),
			Size = UDim2.fromOffset(opts.size.X, opts.size.Y),
			Parent = stage,
		})

		-- If the silhouette art ever lands, it replaces the drawn chassis wholesale; the hardpoints
		-- below are drawn on top either way, since those are state (fitted / empty), not art.
		local image = UiIconConfig.Get(opts.iconKey) or UiIconConfig.Get("rig_generic")
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
			for _, shape in ipairs(spec.shapes) do
				drawShape(holder, shape, lineColor, opticColor)
			end
		end

		local centres = {}
		for index, point in ipairs(spec.hardpoints) do
			local filled = opts.built and opts.isFilled(index)
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

			centres[index] = Vector2.new(opts.origin.X + point[1], opts.origin.Y + point[2])
		end

		return centres
	end

	-- The Robots tab's use of drawChassis: the robot's own rig at the stage's fixed rig box, with one
	-- hardpoint per ModConfig.SlotsPerItem slot.
	--
	-- A rig with fewer hardpoints than there are slots (a hand-written RIGS entry that fell behind a
	-- SlotsPerItem bump) would silently drop the extra slot, and an unreachable mod slot is exactly the
	-- kind of quiet HUD failure this project keeps getting bitten by — so it warns and borrows the
	-- generic rig's points rather than just vanishing.
	local function drawRig(stage: Instance, key: string, built: boolean): { Vector2 }
		local rig = RIGS[key] or GENERIC_RIG
		if #rig.hardpoints < ModConfig.SlotsPerItem then
			warn(("[WeldingPanel] rig %s has %d hardpoints for %d mod slots; borrowing the generic rig's")
				:format(key, #rig.hardpoints, ModConfig.SlotsPerItem))
			rig = { shapes = rig.shapes, hardpoints = GENERIC_RIG.hardpoints }
		end

		return drawChassis(stage, rig, {
			iconKey = "rig_" .. key,
			origin = Vector2.new(RIG_LEFT, RIG_TOP),
			size = Vector2.new(RIG_WIDTH, RIG_HEIGHT),
			built = built,
			isFilled = function(slotIndex: number): boolean
				return ModPicker.equippedModKeyForSlot(key, slotIndex) ~= nil
			end,
		})
	end

	-- The dashed run from a hardpoint out to its card: out to the bend, up or down to the card's
	-- mid-height, then in to the card's near edge — collapsing to a single straight run when the
	-- hardpoint already sits at the card's height. Drawn at ZIndex 1 so the cards (2) sit over the
	-- line rather than the line crossing them.
	local function drawLeader(stage: Instance, from: Vector2, layout: { side: string, top: number })
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
	-- The rail — shared by all four tabs
	------------------------------------------------------------------
	-- Every tab in this station is the same shape: a list of candidates on the left, the selected one
	-- rendered large on the right. That came out of the Robots rebuild and it is the station's
	-- identity now, so the rail is ONE builder the four tabs feed rows into rather than four
	-- near-identical row functions — which is precisely how the old `makeRow` lists drifted into
	-- stating a cost four slightly different ways.
	--
	-- A row shows a title, an optional right-aligned badge, and then EITHER a `pips` strip (Robots
	-- uses it for "which mod slots are filled") or a wrapped `subtitle` (everything else uses it for
	-- a cost or an effect), never both — two second lines would not fit and picking between them is
	-- the caller's decision, not this function's.

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

	local function makeRailRow(tab: string, row: RailRow, order: number, parent: Instance)
		local isSelected = selected[tab] == row.key
		local height = row.subtitle and RAIL_TALL_ROW_HEIGHT or RAIL_ROW_HEIGHT

		local button = Hud.new("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = isSelected and Hud.COLOR.PanelLight or Hud.darken(Hud.COLOR.Panel, 0.2),
			BorderSizePixel = 0,
			LayoutOrder = order,
			Size = UDim2.fromOffset(RAIL_ROW_WIDTH, height),
			Text = "",
			Parent = parent,
		})

		-- Selection reads as an accent edge on the left — the same language the Smelting rail and
		-- ResearchPanel's active row already use, rather than a third way of saying "this one".
		Hud.new("Frame", {
			BackgroundColor3 = isSelected and Hud.COLOR.Accent or Hud.COLOR.Line,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 3, 1, 0),
			Parent = button,
		})

		if row.dashed then
			-- Started 4px in so the dashed left edge does not sit on top of the selection strip above.
			-- The row itself is square, so no cornerInset.
			Hud.dashedBox(button, {
				position = UDim2.fromOffset(4, 0),
				width = RAIL_ROW_WIDTH - 4,
				height = height,
				color = Hud.COLOR.Line,
			})
		end

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.fromOffset(11, 6),
			Size = UDim2.new(1, -(row.badge and 68 or 22), 0, 14),
			Text = row.title,
			TextColor3 = row.dashed and Hud.COLOR.Muted or Hud.COLOR.Text,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = button,
		})

		if row.badge then
			Hud.new("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Font = Hud.FONT.Mono,
				Position = UDim2.new(1, -10, 0, 6),
				Size = UDim2.fromOffset(56, 14),
				Text = row.badge,
				TextColor3 = row.badgeColor or Hud.COLOR.Muted,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = button,
			})
		end

		if row.pips then
			-- One 15px bar per slot, filled when something is fitted. The rail's whole job once you
			-- own several of a thing is "which of these still has a slot going spare", and a strip of
			-- bars answers that without opening each one.
			local pips = Hud.new("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(11, 28),
				Size = UDim2.new(1, -22, 0, 4),
				Parent = button,
			}, { Hud.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 3),
			}) })

			for _, filled in ipairs(row.pips) do
				Hud.new("Frame", {
					BackgroundColor3 = filled and Hud.COLOR.Accent or Hud.COLOR.Line,
					BorderSizePixel = 0,
					Size = UDim2.fromOffset(15, 4),
					Parent = pips,
				})
			end
		elseif row.subtitle then
			Hud.new("TextLabel", {
				BackgroundTransparency = 1,
				Font = Hud.FONT.Mono,
				Position = UDim2.fromOffset(11, 24),
				Size = UDim2.new(1, -22, 0, 26),
				Text = row.subtitle,
				TextColor3 = Hud.COLOR.Muted,
				TextSize = 11,
				-- Truncated as well as wrapped: this box is two lines tall and a four-material craft
				-- cost is three. The stage always shows the full string, so an ellipsis here loses
				-- nothing — whereas an overflowing label just draws outside its row.
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = button,
			})
		end

		button.MouseButton1Click:Connect(function()
			selected[tab] = row.key
			refresh()
		end)
	end

	-- `action` is the button pinned to the foot of the rail, and only the Robots tab has one (its
	-- Build control, where the mockup drew it). The other three tabs put their action in the stage
	-- footer instead, because there it can sit next to the numbers you are deciding on — and two
	-- buttons doing the same job on one screen is worse than either.
	--
	-- SCROLLING, not a plain Frame: six turret types at 54px each overflow the rail's ~344px, and a
	-- Frame would clip the last two with nothing on screen to say they exist.
	local function drawRail(parent: Instance, tab: string, sections: { RailSection }, action: {
		text: string,
		variant: string,
		onClick: () -> (),
	}?)
		local rail = Hud.new("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = RAIL_SCROLLBAR,
			Size = UDim2.new(
				0, RAIL_WIDTH,
				1, action and -(RAIL_BUILD_BUTTON_HEIGHT + Hud.SPACE.S) or 0
			),
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

		local drewSomething = false
		for _, section in ipairs(sections) do
			if #section.rows > 0 then
				if drewSomething then
					Hud.new("Frame", {
						BackgroundColor3 = Hud.COLOR.Line,
						BorderSizePixel = 0,
						LayoutOrder = nextOrder(),
						Size = UDim2.new(1, -RAIL_SCROLLBAR, 0, 1),
						Parent = rail,
					})
				end
				makeRailLabel(section.heading, nextOrder(), rail)
				for _, row in ipairs(section.rows) do
					makeRailRow(tab, row, nextOrder(), rail)
				end
				drewSomething = true
			end
		end

		if not action then
			return
		end

		Hud.button({
			variant = action.variant,
			text = action.text,
			anchorPoint = Vector2.new(0, 1),
			position = UDim2.new(0, 0, 1, 0),
			size = UDim2.fromOffset(RAIL_WIDTH, RAIL_BUILD_BUTTON_HEIGHT),
			parent = parent,
			onClick = action.onClick,
		})
	end

	------------------------------------------------------------------
	-- Stage furniture — shared by all four tabs
	------------------------------------------------------------------

	-- body (the full-width row parented into listFrame), rail slot, and the stage plate beside it.
	local function makeShell(): (Frame, Frame)
		local body = Hud.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, BODY_HEIGHT),
			Parent = listFrame,
		})

		local stage = Hud.new("Frame", {
			BackgroundColor3 = Hud.darken(Hud.COLOR.Panel, 0.15),
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(RAIL_WIDTH + Hud.SPACE.M, 0),
			Size = UDim2.new(1, -(RAIL_WIDTH + Hud.SPACE.M), 1, 0),
			Parent = body,
		}, { Hud.corner(Hud.RADIUS.Panel), Hud.stroke() })

		return body, stage
	end

	-- The selected thing's name, with a short status beside it in its own colour. Every tab opens
	-- with this line so "what am I looking at, and do I have it" is answered before anything else.
	local function makeStageTitle(stage: Instance, name: string, status: string, statusColor: Color3)
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
			Text = name,
			TextColor3 = Hud.COLOR.Text,
			TextSize = Hud.TEXTSIZE.Title,
			Parent = titleRow,
		})

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
	end

	local function makeSectionHeading(stage: Instance, text: string, y: number)
		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.fromOffset(Hud.SPACE.L, y),
			Size = UDim2.fromOffset(300, 14),
			Text = text,
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = stage,
		})
	end

	local function makeBodyText(stage: Instance, text: string, y: number, height: number)
		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Body,
			Position = UDim2.fromOffset(Hud.SPACE.L, y),
			Size = UDim2.new(1, -Hud.SPACE.L * 2, 0, height),
			Text = text,
			TextColor3 = Hud.COLOR.Muted,
			TextSize = Hud.TEXTSIZE.Body,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = stage,
		})
	end

	-- One labelled horizontal bar. Two modes, because the two tabs that use it are asking different
	-- questions:
	--
	--   "fill"   — how big is this number against the biggest one in its class? Fills from the left.
	--              Turrets: a Mortar's range next to a Pulse's is the whole reason to look at this
	--              tab, and no wall of digits makes that comparison for you.
	--   "signed" — which way does this mod push, and how hard? Fills OUT FROM THE CENTRE, right in
	--              Good for a buff and left in Bad for a nerf. Every mod in the game is a trade, and
	--              a centred bar is the only shape that says "trade" at a glance.
	--
	-- `alpha` is 0..1 for fill, and -1..1 for signed (already normalised by the caller against
	-- SIGNED_BAR_FULL_SCALE, so the two ends of the bar mean a fixed percentage rather than whatever
	-- the biggest mod happens to be).
	local function makeStatBar(stage: Instance, opts: {
		label: string,
		value: string,
		alpha: number,
		mode: string,
		y: number,
		color: Color3?,
		muted: boolean?,
	})
		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.fromOffset(Hud.SPACE.L, opts.y),
			Size = UDim2.fromOffset(BAR_LABEL_WIDTH, BAR_ROW_HEIGHT),
			Text = opts.label,
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = stage,
		})

		local track = Hud.new("Frame", {
			BackgroundColor3 = Hud.darken(Hud.COLOR.Panel, 0.3),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(BAR_TRACK_X, opts.y + (BAR_ROW_HEIGHT - BAR_HEIGHT) / 2),
			Size = UDim2.fromOffset(BAR_TRACK_WIDTH, BAR_HEIGHT),
			Parent = stage,
		}, { Hud.corner(2) })

		local fillColor = opts.color or Hud.COLOR.Accent

		if opts.mode == "signed" then
			-- The 1.0x baseline, drawn whether or not this stat moves — it is what makes the empty
			-- half of the bar readable as "no change" rather than as a bar that failed to render.
			Hud.new("Frame", {
				BackgroundColor3 = Hud.COLOR.Line,
				BorderSizePixel = 0,
				Position = UDim2.new(0.5, -1, 0, -3),
				Size = UDim2.fromOffset(2, BAR_HEIGHT + 6),
				Parent = track,
			})

			local magnitude = math.clamp(math.abs(opts.alpha), 0, 1) / 2
			if magnitude > 0 then
				Hud.new("Frame", {
					BackgroundColor3 = fillColor,
					BorderSizePixel = 0,
					Position = UDim2.fromScale(opts.alpha >= 0 and 0.5 or 0.5 - magnitude, 0),
					Size = UDim2.new(magnitude, 0, 1, 0),
					Parent = track,
				})
			end
		else
			Hud.new("Frame", {
				BackgroundColor3 = fillColor,
				BorderSizePixel = 0,
				Size = UDim2.new(math.clamp(opts.alpha, 0, 1), 0, 1, 0),
				Parent = track,
			}, { Hud.corner(2) })
		end

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.fromOffset(BAR_TRACK_X + BAR_TRACK_WIDTH + Hud.SPACE.S, opts.y),
			Size = UDim2.fromOffset(BAR_VALUE_WIDTH, BAR_ROW_HEIGHT),
			Text = opts.value,
			TextColor3 = opts.muted and Hud.COLOR.Muted or Hud.COLOR.Text,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = stage,
		})
	end

	-- The bottom strip every tab ends with: an eyebrow, a value line, and up to two buttons pinned
	-- to the right. Buttons are listed PRIMARY FIRST and laid out right-to-left from the stage edge,
	-- so the main action always lands in the same place whatever else is beside it.
	local function makeStageFooter(stage: Instance, opts: {
		eyebrow: string,
		value: string,
		valueColor: Color3?,
		richText: boolean?,
		buttons: { { text: string, variant: string, width: number, onClick: () -> () } }?,
		-- Right-aligned muted text for a footer with no buttons — a price you cannot act on from
		-- this screen, say. Drawn where the buttons would have gone, so passing both would overlap.
		note: string?,
	})
		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.fromOffset(Hud.SPACE.M, FOOTER_TOP),
			Size = UDim2.fromOffset(300, 14),
			Text = opts.eyebrow,
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = stage,
		})

		-- Only squeezed to FOOTER_VALUE_WIDTH when there is something to its right to avoid; with a
		-- bare footer it gets the whole width, or a sentence like "Fit it on the Robots tab" truncates
		-- for no reason.
		local crowded = (opts.buttons and #opts.buttons > 0) or opts.note ~= nil

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.fromOffset(Hud.SPACE.M, FOOTER_TOP + 16),
			RichText = opts.richText or false,
			Size = UDim2.fromOffset(
				crowded and FOOTER_VALUE_WIDTH or (STAGE_WIDTH - Hud.SPACE.M * 2),
				24
			),
			Text = opts.value,
			TextColor3 = opts.valueColor or Hud.COLOR.Text,
			TextSize = 15,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = stage,
		})

		if opts.note then
			Hud.new("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Font = Hud.FONT.Mono,
				Position = UDim2.fromOffset(STAGE_WIDTH - Hud.SPACE.M, FOOTER_TOP + 12),
				Size = UDim2.fromOffset(240, 32),
				Text = opts.note,
				TextColor3 = Hud.COLOR.Muted,
				TextSize = Hud.TEXTSIZE.Label,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = stage,
			})
		end

		local x = STAGE_WIDTH - Hud.SPACE.M
		for _, spec in ipairs(opts.buttons or {}) do
			x -= spec.width
			Hud.button({
				variant = spec.variant,
				text = spec.text,
				position = UDim2.fromOffset(x, FOOTER_TOP + 4),
				size = UDim2.fromOffset(spec.width, 40),
				parent = stage,
				onClick = spec.onClick,
			})
			x -= Hud.SPACE.S
		end
	end

	------------------------------------------------------------------
	-- Robots tab
	------------------------------------------------------------------

	-- The rig's mod-adjusted numbers, then Deploy/Recall and Fit mod. Each value is tinted Accent
	-- only if a fitted mod actually moved it, so "what did my loadout buy me" is answerable at a
	-- glance without a second before/after line competing with the rig for space.
	local function drawRobotFooter(stage: Instance, key: string, built: boolean)
		local recipe = CraftingRecipes.Robots[key]
		local fireRate, damage, hp = effectiveStats(key)
		local modded = built
			and (fireRate ~= recipe.FireRate or damage ~= recipe.BaseDamage or hp ~= recipe.HP)

		local accent = hex(Hud.COLOR.Accent)
		local function value(text: string, changed: boolean): string
			return changed and ('<font color="%s">%s</font>'):format(accent, text) or text
		end

		local numbers = ("%s  ×  %s  ·  %s"):format(
			value(("%.1f dmg"):format(damage), damage ~= recipe.BaseDamage),
			value(("%.1f/s"):format(fireRate), fireRate ~= recipe.FireRate),
			value(("%d hp"):format(math.floor(hp + 0.5)), hp ~= recipe.HP)
		)

		if not built then
			-- No buttons for an unbuilt robot: the Build action lives on the rail (where the mockup
			-- puts it), so all the footer owes you here is the price.
			makeStageFooter(stage, {
				eyebrow = "BASE STATS",
				value = numbers,
				richText = true,
				note = Hud.costString(recipe.Cost),
			})
			return
		end

		local canDeployMore = deployedCountForRobot(key) < ownedCount(key)

		makeStageFooter(stage, {
			eyebrow = modded and "WITH MODS" or "BASE STATS",
			value = numbers,
			richText = true,
			buttons = {
				{
					text = "Fit mod",
					variant = "primary",
					width = 104,
					onClick = function()
						-- The primary action of a Welding Station is fitting a mod, so it gets the
						-- primary button — but the slot cards are the real control, and this just
						-- opens the first one that is free (or slot 1 when the rig is full, so the
						-- button is never dead).
						for slotIndex = 1, ModConfig.SlotsPerItem do
							if not ModPicker.equippedModKeyForSlot(key, slotIndex) then
								ModPicker.openModPicker("Robots", key, slotIndex)
								return
							end
						end
						ModPicker.openModPicker("Robots", key, 1)
					end,
				},
				{
					-- One button, two states, exactly as the old row had it: once every owned copy is
					-- on defense duty there is nothing left to deploy, so the only move left is
					-- pulling one back off.
					text = canDeployMore and "Deploy" or "Recall",
					variant = "secondary",
					width = 96,
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
				},
			},
		})
	end

	local function renderRobots()
		local built, unbuilt = sortedKeys()

		-- Re-validated every render rather than trusted: a key can stop being owned, or stop existing
		-- at all, between one render and the next.
		if not selected.Robots or not CraftingRecipes.Robots[selected.Robots] then
			selected.Robots = built[1] or unbuilt[1]
		end

		local maxSlots = CraftingRecipes.MaxDeployedRobots(Hud.profile)
		local deployedTotal = #(Hud.profile.DeployedRobots or {})
		setReadout("DEPLOYED", ("%d / %d"):format(deployedTotal, maxSlots), deployedTotal < maxSlots)

		local body, stage = makeShell()

		local function railRowFor(key: string, isBuilt: boolean): RailRow
			local recipe = CraftingRecipes.Robots[key]
			local pips = nil
			if isBuilt then
				pips = {}
				for slotIndex = 1, ModConfig.SlotsPerItem do
					pips[slotIndex] = ModPicker.equippedModKeyForSlot(key, slotIndex) ~= nil
				end
			end
			local owned = ownedCount(key)
			return {
				key = key,
				title = recipe.DisplayName,
				badge = isBuilt and owned > 1 and ("t%d  x%d"):format(recipe.Tier, owned)
					or ("t%d"):format(recipe.Tier),
				pips = pips,
				subtitle = not isBuilt and Hud.costString(recipe.Cost) or nil,
				dashed = not isBuilt,
			}
		end

		local builtRows, unbuiltRows = {}, {}
		for _, key in ipairs(built) do
			table.insert(builtRows, railRowFor(key, true))
		end
		for _, key in ipairs(unbuilt) do
			table.insert(unbuiltRows, railRowFor(key, false))
		end

		local action = nil
		if #unbuilt > 0 then
			-- The build button targets whatever is selected when that is something unbuilt, and
			-- otherwise the cheapest thing you have not built — so it is always a live offer rather
			-- than a control that goes dead the moment you click a robot you already own.
			local target = (table.find(unbuilt, selected.Robots) and selected.Robots or unbuilt[1]) :: string
			local recipe = CraftingRecipes.Robots[target]
			action = {
				text = ("Build %s"):format(recipe.DisplayName),
				variant = Wallet.CanAfford(Hud.profile, recipe.Cost) and "primary" or "secondary",
				onClick = function()
					-- Deliberately NOT gated client-side on affordability: CraftItem re-checks the
					-- cost anyway, and its rejection names the material you are short of, which is
					-- more use than a button that silently does nothing.
					local result = Remotes.CraftItem:InvokeServer("Robots", target)
					if not result.Success then
						Hud.showFailure("Build failed", result.Reason)
					end
				end,
			}
		end

		drawRail(body, "Robots", {
			{ heading = "BUILT", rows = builtRows },
			{ heading = "NOT BUILT", rows = unbuiltRows },
		}, action)

		if not selected.Robots then
			-- Only reachable if CraftingRecipes.Robots is empty, which would be a config mistake
			-- rather than a state a player can get into — but a blank stage with no explanation is
			-- exactly the "I click and nothing happens" failure this project keeps hitting.
			makeBodyText(stage, "No robots are configured.", Hud.SPACE.L, 40)
			return
		end

		local key = selected.Robots :: string
		local recipe = CraftingRecipes.Robots[key]
		local isBuilt = ownedCount(key) > 0
		local deployed = deployedCountForRobot(key)

		local status, statusColor
		if not isBuilt then
			status, statusColor = "not built", Hud.COLOR.Muted
		elseif deployed > 0 then
			status, statusColor = ("deployed ×%d"):format(deployed), Hud.COLOR.Good
		else
			status, statusColor = "in storage", Hud.COLOR.Muted
		end
		makeStageTitle(stage, recipe.DisplayName, status, statusColor)

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
				drawLeader(stage, centres[slotIndex], CARD_LAYOUT[slotIndex])
				drawSlotCard(stage, key, slotIndex, isBuilt)
			end
		end

		drawRobotFooter(stage, key, isBuilt)
	end

	------------------------------------------------------------------
	-- Mods tab
	------------------------------------------------------------------
	-- A mod is a TRADE — every one of the six gives something up — and the old list showed only its
	-- authored sentence and its price. Two things this answers that the list could not: which way and
	-- how hard each multiplier pushes (the centred bars), and WHERE the mod you already own is
	-- currently fitted, which is genuinely hard to reconstruct otherwise because mods are per item
	-- TYPE and can sit in any of three slots on any robot or weapon type you own.

	local function modIsOwned(key: string): boolean
		return (Hud.profile.CraftedMods or {})[key] == true
	end

	-- The item TYPES currently carrying this mod, as display names. Walks EquippedMods rather than
	-- asking per item, because the profile is keyed the other way round (itemKey -> slots -> modKey)
	-- and there is no reverse index.
	local function fittedOn(modKey: string): { string }
		local names = {}
		for itemKey, slots in pairs(Hud.profile.EquippedMods or {}) do
			for slotIndex, equipped in pairs(slots) do
				if equipped == modKey then
					local recipe = CraftingRecipes.Robots[itemKey] or CraftingRecipes.Weapons[itemKey]
					table.insert(names, ("%s · slot %d"):format(
						recipe and recipe.DisplayName or itemKey, slotIndex))
				end
			end
		end
		table.sort(names)
		return names
	end

	local function renderMods()
		local keys = {}
		for key in pairs(ModConfig.Mods) do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return ModConfig.Mods[a].DisplayName < ModConfig.Mods[b].DisplayName
		end)

		local ownedRows, unownedRows = {}, {}
		local ownedCountTotal = 0
		for _, key in ipairs(keys) do
			local mod = ModConfig.Mods[key]
			local owned = modIsOwned(key)
			if owned then
				ownedCountTotal += 1
			end
			local fitted = owned and #fittedOn(key) or 0
			table.insert(owned and ownedRows or unownedRows, {
				key = key,
				title = mod.DisplayName,
				badge = owned and fitted > 0 and ("x%d"):format(fitted) or nil,
				badgeColor = Hud.COLOR.Accent,
				subtitle = owned and modEffectSummary(mod) or Hud.costString(mod.Cost),
				dashed = not owned,
			})
		end

		if not selected.Mods or not ModConfig.Mods[selected.Mods] then
			selected.Mods = (ownedRows[1] and ownedRows[1].key) or (unownedRows[1] and unownedRows[1].key)
		end

		setReadout("CRAFTED", ("%d / %d"):format(ownedCountTotal, #keys), ownedCountTotal < #keys)

		local body, stage = makeShell()
		drawRail(body, "Mods", {
			{ heading = "CRAFTED", rows = ownedRows },
			{ heading = "NOT CRAFTED", rows = unownedRows },
		})

		if not selected.Mods then
			makeBodyText(stage, "No mods are configured.", Hud.SPACE.L, 40)
			return
		end

		local key = selected.Mods :: string
		local mod = ModConfig.Mods[key]
		local owned = modIsOwned(key)

		makeStageTitle(stage, mod.DisplayName, owned and "crafted" or "not crafted",
			owned and Hud.COLOR.Good or Hud.COLOR.Muted)
		makeBodyText(stage, mod.Description, 42, 34)

		makeSectionHeading(stage, "TRADE-OFF", 86)

		-- Fixed full-scale rather than "whatever the biggest mod does", so the bars mean the same
		-- thing on every mod's screen and two mods can be compared by remembering the shape.
		local stats = {
			{ label = "damage", multiplier = mod.DamageMultiplier },
			{ label = "fire rate", multiplier = mod.FireRateMultiplier },
			{ label = "hp", multiplier = mod.HPMultiplier },
		}
		for index, stat in ipairs(stats) do
			local y = 106 + (index - 1) * BAR_ROW_HEIGHT
			if stat.multiplier then
				local delta = stat.multiplier - 1
				makeStatBar(stage, {
					label = stat.label,
					value = signedPercent(stat.multiplier),
					alpha = delta / SIGNED_BAR_FULL_SCALE,
					mode = "signed",
					y = y,
					color = delta >= 0 and Hud.COLOR.Good or Hud.COLOR.Bad,
				})
			else
				makeStatBar(stage, {
					label = stat.label,
					value = "no change",
					alpha = 0,
					mode = "signed",
					y = y,
					muted = true,
				})
			end
		end

		if mod.HPMultiplier then
			Hud.new("TextLabel", {
				BackgroundTransparency = 1,
				Font = Hud.FONT.Mono,
				Position = UDim2.fromOffset(BAR_TRACK_X, 106 + 3 * BAR_ROW_HEIGHT),
				Size = UDim2.fromOffset(360, 16),
				Text = "hp only applies to robots — a weapon has none",
				TextColor3 = Hud.COLOR.Muted,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = stage,
			})
		end

		makeSectionHeading(stage, "FITTED ON", 214)
		local fitted = owned and fittedOn(key) or {}
		makeBodyText(
			stage,
			#fitted > 0 and table.concat(fitted, "\n")
				or (owned and "Not fitted anywhere yet." or "Craft it first."),
			232,
			72
		)

		if owned then
			makeStageFooter(stage, {
				eyebrow = "CRAFTED",
				value = "Fit it on the Robots tab, or on a weapon from your Inventory.",
				valueColor = Hud.COLOR.Muted,
			})
			return
		end

		makeStageFooter(stage, {
			eyebrow = "CRAFT COST",
			value = Hud.costString(mod.Cost),
			buttons = { {
				text = "Craft",
				variant = Wallet.CanAfford(Hud.profile, mod.Cost) and "primary" or "secondary",
				width = 104,
				onClick = function()
					local result = Remotes.CraftItem:InvokeServer("Mods", key)
					if not result.Success then
						Hud.showFailure("Craft failed", result.Reason)
					end
				end,
			} },
		})
	end

	------------------------------------------------------------------
	-- Turrets tab
	------------------------------------------------------------------
	-- Turrets differ from each other on four axes at once (damage, range, fire rate, how many targets
	-- one shot hits), and the old list printed all four as digits in a subtitle. "30 dmg · 95 range ·
	-- 0.4/s · 5 AOE" is not a thing anyone compares in their head against another row's four numbers,
	-- which is exactly what choosing a turret requires — so they are bars, scaled against the best in
	-- class, and the comparison happens visually.

	local function turretBuiltCount(typeKey: string): number
		local count = 0
		for _, turret in ipairs(Hud.profile.Turrets or {}) do
			if turret.TypeKey == typeKey then
				count += 1
			end
		end
		return count
	end

	local function renderTurrets()
		local unlocked = Hud.profile.UnlockedTurretBlueprints or {}

		-- Sorted by blueprint cost so the rail reads as a progression rather than a hash order —
		-- the same ordering the list it replaces used.
		local keys = {}
		for key in pairs(TurretConfig.Types) do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return (TurretConfig.Types[a].BlueprintCost.Scrap or 0) < (TurretConfig.Types[b].BlueprintCost.Scrap or 0)
		end)

		local knownRows, lockedRows = {}, {}
		for _, key in ipairs(keys) do
			local typeData = TurretConfig.Types[key]
			local known = unlocked[key] == true
			local count = turretBuiltCount(key)
			table.insert(known and knownRows or lockedRows, {
				key = key,
				title = typeData.DisplayName,
				badge = known and count > 0 and ("x%d"):format(count) or nil,
				badgeColor = Hud.COLOR.Accent,
				subtitle = known
					and ("%.0f dmg  ·  %.0f studs"):format(typeData.BaseDamage, typeData.Range)
					or ("blueprint · %s"):format(Hud.costString(typeData.BlueprintCost)),
				dashed = not known,
			})
		end

		if not selected.Turrets or not TurretConfig.Types[selected.Turrets] then
			selected.Turrets = (knownRows[1] and knownRows[1].key) or (lockedRows[1] and lockedRows[1].key)
		end

		local slotCount = TurretConfig.GetSlotCount(Hud.profile.ResearchTier)
		local placed, builtTotal = 0, 0
		for _, turret in ipairs(Hud.profile.Turrets or {}) do
			builtTotal += 1
			if turret.SlotIndex then
				placed += 1
			end
		end
		setReadout("SLOTS", ("%d / %d"):format(placed, slotCount), placed < slotCount)

		local body, stage = makeShell()
		drawRail(body, "Turrets", {
			{ heading = "BLUEPRINTS OWNED", rows = knownRows },
			{ heading = "LOCKED", rows = lockedRows },
		})

		if not selected.Turrets then
			makeBodyText(stage, "No turret types are configured.", Hud.SPACE.L, 40)
			return
		end

		local key = selected.Turrets :: string
		local typeData = TurretConfig.Types[key]
		local known = unlocked[key] == true
		local count = turretBuiltCount(key)

		local status, statusColor
		if not known then
			status, statusColor = "blueprint locked", Hud.COLOR.Muted
		elseif count > 0 then
			status, statusColor = ("built ×%d"):format(count), Hud.COLOR.Good
		else
			status, statusColor = "blueprint owned", Hud.COLOR.Muted
		end
		makeStageTitle(stage, typeData.DisplayName, status, statusColor)
		makeBodyText(stage, typeData.Description, 42, 34)

		makeSectionHeading(stage, "PROFILE  ·  AT LEVEL 1", 86)

		-- Level 1 deliberately, not the level of one you happen to own: this screen is for choosing
		-- WHICH turret to build. A placed turret's own levelled numbers live on its slot panel
		-- (TurretPanel.lua), which is where you go to upgrade it.
		local stats = TurretConfig.GetTurretEffectiveStats(key, 1)
		local rows = {
			{ label = "damage", value = ("%.0f"):format(stats.Damage), alpha = stats.Damage / TURRET_STAT_MAX.Damage },
			{ label = "range", value = ("%.0f studs"):format(stats.Range), alpha = stats.Range / TURRET_STAT_MAX.Range },
			{ label = "fire rate", value = ("%.2f/s"):format(stats.FireRate), alpha = stats.FireRate / TURRET_STAT_MAX.FireRate },
			{ label = "targets", value = stats.AOE > 1 and ("%d at once"):format(stats.AOE) or "single", alpha = stats.AOE / TURRET_STAT_MAX.AOE },
		}
		for index, row in ipairs(rows) do
			makeStatBar(stage, {
				label = row.label,
				value = row.value,
				alpha = row.alpha,
				mode = "fill",
				y = 104 + (index - 1) * BAR_ROW_HEIGHT,
				color = known and Hud.COLOR.Accent or Hud.COLOR.Line,
				muted = not known,
			})
		end

		makeSectionHeading(stage, "BASE DEFENSE SLOTS", 228)

		-- segmentBar is the HUD's existing "N discrete things, some of them used" bar — the same one
		-- the base integrity readout uses. Three states here, not two: a slot with a turret standing
		-- in it, a turret built but not yet carried out to a pad, and an empty slot.
		local slotHolder = Hud.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Hud.SPACE.L, 248),
			Size = UDim2.new(1, -Hud.SPACE.L * 2, 0, 16),
			Parent = stage,
		})
		local cells = Hud.segmentBar(slotHolder, math.max(slotCount, 1))
		for index, cell in ipairs(cells) do
			if index <= placed then
				cell.BackgroundColor3 = Hud.COLOR.Accent
			elseif index <= builtTotal then
				cell.BackgroundColor3 = Hud.COLOR.AccentDark
			end
		end

		local unplaced = builtTotal - placed
		makeBodyText(
			stage,
			unplaced > 0
				and ("%d placed, %d built and waiting — click a slot pad at your base to set one down.")
					:format(placed, unplaced)
				or ("%d of %d slots in use. More slots come with Research Tier."):format(placed, slotCount),
			272,
			34
		)

		if not known then
			makeStageFooter(stage, {
				eyebrow = "BLUEPRINT NOT OWNED",
				value = ("Buy it at the Hub Shop for %s"):format(Hud.costString(typeData.BlueprintCost)),
				valueColor = Hud.COLOR.Muted,
				buttons = { {
					text = "Locked",
					variant = "secondary",
					width = 104,
					onClick = function()
						Hud.showFailure(
							"Locked",
							("You need the %s blueprint — buy it at the Hub Shop."):format(typeData.DisplayName))
					end,
				} },
			})
			return
		end

		makeStageFooter(stage, {
			eyebrow = "BUILD COST",
			value = Hud.costString(typeData.CraftCost),
			buttons = { {
				text = "Build",
				variant = Wallet.CanAfford(Hud.profile, typeData.CraftCost) and "primary" or "secondary",
				width = 104,
				onClick = function()
					-- Reuses the shared CraftItem remote with a "Turrets" tree — same plot/station
					-- gate and cost validation Robots and Mods already go through.
					local result = Remotes.CraftItem:InvokeServer("Turrets", key)
					if not result.Success then
						Hud.showFailure("Build failed", result.Reason)
					else
						Hud.showToast(
							("Built a %s — click a slot pad at your base to place it."):format(typeData.DisplayName), 4)
						refresh()
					end
				end,
			} },
		})
	end

	------------------------------------------------------------------
	-- Drones tab
	------------------------------------------------------------------
	-- You get ONE Core slotted at a time out of four, which makes this a loadout screen, not a
	-- catalogue — and the station already has a way of drawing "a machine with a slot in it". So the
	-- drone is drawn on the same chassis machinery the robots use, with a single hardpoint at its
	-- core bay and one card on the end of a leader line naming what is in it. That the bay is one
	-- socket rather than three is then something you can see rather than something you have to be
	-- told.

	-- The bay's one card, at the far end of the leader line. Deliberately NOT drawSlotCard: that one
	-- is a mod slot on a robot (numbered, clickable, opens the mod picker), and this is a single
	-- fixed bay whose contents are changed by the footer button, not by clicking the card. Sharing
	-- one function would have meant a parameter for every difference.
	local function drawDroneCard(stage: Instance, key: string, isEquipped: boolean, unlocked: boolean)
		local core = DroneConfig.Cores[key]
		local lit = unlocked and isEquipped

		local card = Hud.new("Frame", {
			BackgroundColor3 = lit and Hud.COLOR.PanelLight or Hud.darken(Hud.COLOR.Panel, 0.2),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(CARD_RIGHT_X, DRONE_CARD_LAYOUT.top),
			Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
			ZIndex = 2,
			Parent = stage,
		}, { Hud.corner(Hud.RADIUS.Button) })

		if lit then
			Hud.new("UIStroke", { Color = Hud.COLOR.Accent, Thickness = 1, Parent = card })
		else
			Hud.dashedBox(card, {
				width = CARD_WIDTH,
				height = CARD_HEIGHT,
				color = Hud.COLOR.Line,
				cornerInset = Hud.RADIUS.Button,
				zIndex = 2,
			})
		end

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Display,
			Position = UDim2.fromOffset(9, 7),
			Size = UDim2.new(1, -18, 0, 12),
			Text = "CORE BAY",
			TextColor3 = lit and Hud.COLOR.Accent or Hud.COLOR.Muted,
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
			Text = lit and core.DisplayName or "Empty",
			TextColor3 = lit and Hud.COLOR.Text or Hud.COLOR.Muted,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 2,
			Parent = card,
		})

		-- What the card says when the bay is empty depends on WHY it is empty, because the three
		-- reasons need three different next actions from the player.
		local hint
		if lit then
			hint = "one core at a time"
		elseif not unlocked then
			hint = ("research tier %d"):format(DroneConfig.UnlockResearchTier)
		elseif (Hud.profile.OwnedDroneCores or {})[key] then
			hint = "slot it below"
		else
			hint = "not owned yet"
		end

		Hud.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Hud.FONT.Mono,
			Position = UDim2.fromOffset(9, 40),
			Size = UDim2.new(1, -18, 0, 22),
			Text = hint,
			TextColor3 = Hud.COLOR.Muted,
			TextSize = 11,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 2,
			Parent = card,
		})
	end

	local function renderDrones()
		local unlocked = DroneConfig.IsUnlocked(Hud.profile)
		local owned = Hud.profile.OwnedDroneCores or {}
		local equipped = Hud.profile.EquippedDroneCore

		local ownedRows, lockedRows = {}, {}
		for _, key in ipairs(DroneConfig.Order) do
			local core = DroneConfig.Cores[key]
			local isOwned = owned[key] == true
			table.insert(isOwned and ownedRows or lockedRows, {
				key = key,
				title = core.DisplayName,
				badge = equipped == key and "SLOTTED" or nil,
				badgeColor = Hud.COLOR.Good,
				subtitle = isOwned and DroneConfig.EffectSummary(key, Hud.profile)
					or (core.Source == "Craft" and Hud.costString(core.Cost) or "Black Market · Epic roll"),
				dashed = not isOwned,
			})
		end

		if not selected.Drones or not DroneConfig.Cores[selected.Drones] then
			selected.Drones = equipped or (ownedRows[1] and ownedRows[1].key) or DroneConfig.Order[1]
		end

		if not unlocked then
			setReadout("BAY", ("locked · tier %d"):format(DroneConfig.UnlockResearchTier), false)
		else
			local core = equipped and DroneConfig.Cores[equipped]
			setReadout("CORE", core and core.DisplayName or "none slotted", core ~= nil)
		end

		local body, stage = makeShell()
		drawRail(body, "Drones", {
			{ heading = "OWNED", rows = ownedRows },
			{ heading = "NOT OWNED", rows = lockedRows },
		})

		local key = selected.Drones :: string
		local core = DroneConfig.Cores[key]
		local isOwned = owned[key] == true
		local isEquipped = equipped == key

		local status, statusColor
		if not unlocked then
			status, statusColor = ("bay locked · research tier %d"):format(DroneConfig.UnlockResearchTier), Hud.COLOR.Muted
		elseif isEquipped then
			status, statusColor = "slotted", Hud.COLOR.Good
		elseif isOwned then
			status, statusColor = "owned", Hud.COLOR.Muted
		else
			status, statusColor = "not owned", Hud.COLOR.Muted
		end
		makeStageTitle(stage, core.DisplayName, status, statusColor)
		makeBodyText(stage, core.Description, 42, 34)

		-- The bay is drawn as "lit" only when this Core is actually in it, so browsing a Core you own
		-- but have not slotted does not look like it is already fitted.
		local centres = drawChassis(stage, DRONE_RIG, {
			iconKey = "rig_drone",
			origin = DRONE_ORIGIN,
			size = DRONE_SIZE,
			built = unlocked,
			isFilled = function(): boolean
				return isEquipped
			end,
		})

		if centres[1] then
			drawLeader(stage, centres[1], DRONE_CARD_LAYOUT)
		end

		drawDroneCard(stage, key, isEquipped, unlocked)

		if not unlocked then
			makeStageFooter(stage, {
				eyebrow = "DRONE BAY LOCKED",
				value = ("Unlocks at Research Tier %d."):format(DroneConfig.UnlockResearchTier),
				valueColor = Hud.COLOR.Muted,
			})
			return
		end

		if isOwned then
			makeStageFooter(stage, {
				eyebrow = "EFFECT AT YOUR RESEARCH TIER",
				value = DroneConfig.EffectSummary(key, Hud.profile),
				buttons = { {
					text = isEquipped and "Unslot" or "Slot it",
					variant = isEquipped and "secondary" or "primary",
					width = 104,
					onClick = function()
						-- Written as an explicit nil local rather than `isEquipped and nil or key`:
						-- that expression evaluates to `key` when isEquipped is true, because `nil`
						-- is falsy. The same trap the tool-mod and drone rows already carried a
						-- comment about.
						local desired: string? = nil
						if not isEquipped then
							desired = key
						end
						local result = Remotes.EquipDroneCore:InvokeServer(desired)
						if not result.Success then
							Hud.showFailure("Couldn't slot that Core", result.Reason)
						else
							refresh()
						end
					end,
				} },
			})
			return
		end

		if core.Source == "Craft" then
			makeStageFooter(stage, {
				eyebrow = "CRAFT COST",
				value = Hud.costString(core.Cost),
				buttons = { {
					text = "Craft",
					variant = Wallet.CanAfford(Hud.profile, core.Cost) and "primary" or "secondary",
					width = 104,
					onClick = function()
						local result = Remotes.CraftItem:InvokeServer("Drones", key)
						if not result.Success then
							Hud.showFailure("Craft failed", result.Reason)
						else
							refresh()
						end
					end,
				} },
			})
			return
		end

		makeStageFooter(stage, {
			eyebrow = "NOT CRAFTABLE",
			value = "Only drops from Epic rolls in Black Market cases.",
			valueColor = Hud.COLOR.Muted,
			buttons = { {
				text = "Where?",
				variant = "secondary",
				width = 104,
				onClick = function()
					Hud.showFailure(
						("%s can't be built"):format(core.DisplayName),
						"It only drops from Epic rolls in Black Market cases.")
				end,
			} },
		})
	end

	------------------------------------------------------------------
	-- Dispatch
	------------------------------------------------------------------

	local TABS = {
		Robots = renderRobots,
		Mods = renderMods,
		Turrets = renderTurrets,
		Drones = renderDrones,
	}

	return {
		-- Guarded and warned rather than indexed blind: an unguarded nil call here would throw inside
		-- renderCraftList and take the whole panel down, which presents as "the station menu opens
		-- empty" with nothing obvious in Output. Same rule as every other strategy-table dispatch in
		-- this project.
		render = function(tab: string)
			local fn = TABS[tab]
			if not fn then
				warn(("[WeldingPanel] no renderer for tab %q"):format(tostring(tab)))
				return
			end
			fn()
		end,
		-- Called by renderCraftList when it renders a tab this panel does not own: the readout lives
		-- in the shared panel header, which that sweep does not clear, so it would otherwise sit there
		-- claiming a deploy count over the Forge's Weapons tab.
		hideReadout = function()
			readout.Visible = false
		end,
	}
end

return WeldingPanel
