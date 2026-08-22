--[[
	PlotConfig.lua
	Pure data for the base-plot system. Place one Part per plot anywhere in Studio and tag it
	"Plot" (PlotConfig.Tag) via the Tag Editor plugin — no code changes needed to add more plots.

	The Plot Part is just an invisible ANCHOR now, not a physical floor — PlotService forces it
	transparent/non-collidable/non-queryable the moment it sees the tag, regardless of however you
	built it in Studio. Its CFrame is the only thing that matters: PlotService assigns one
	unclaimed Plot Part to each player on join, and BaseService.lua clones an actual Base Model
	(see BaseConfig.lua) on top of that same CFrame — THAT'S what the player actually sees and
	stands on. Build your Plot Parts as small, plain, easy-to-place markers; build the real-looking
	base structure as a separate Model template instead (see BaseConfig.lua's header comment).
]]

local PlotConfig = {}

PlotConfig.Tag = "Plot" -- CollectionService tag for each plot's anchor Part

-- Half-extents (studs, local X/Y/Z relative to the plot anchor's own CFrame) of the region that
-- counts as "at your own base" for PlotService.IsPlayerInOwnPlot. Deliberately NOT derived from
-- the anchor Part's own Size — the anchor is just a small marker, this is how big the actual
-- claimed base area is. Sized generously for whatever the biggest Base Model tier ends up being;
-- bump it up if a larger base template needs more room than this.
PlotConfig.FootprintHalfSize = Vector3.new(40, 30, 40)

-- How high above the plot anchor's own position a respawning character is placed. Trusts that
-- whatever's built on top of the anchor (a real Base Model, or BaseService's plain placeholder
-- floor if none exists yet) has its own walkable floor at roughly the anchor's height — build
-- Base Model templates with their floor at local Y=0 / their PrimaryPart at floor level so
-- `model:PivotTo(plot.CFrame)` lines them up correctly.
PlotConfig.SpawnHeightOffset = 5

PlotConfig.NoPlotMessage = "No base plot is available right now — ask the builder to add more Plot parts in Studio."
PlotConfig.NotInBaseMessage = "You need to be at your own base to do that."

return PlotConfig
