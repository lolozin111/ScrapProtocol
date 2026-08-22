--[[
	BaseConfig.lua
	Pure data for the physical base structures BaseService.lua clones onto each player's plot.

	Studio setup: create a Folder named BaseConfig.TemplateFolderName ("BaseTemplates") directly
	under ReplicatedStorage, and put one Model inside it per tier below, named to match that
	tier's ModelName exactly (e.g. "BaseTier1"). Build each Model with its intended floor at local
	Y=0 (e.g. set the Model's PrimaryPart to a floor piece) — BaseService positions a clone via
	`model:PivotTo(plot.CFrame)`, so whatever sits at the model's own local origin lands exactly on
	the plot's anchor point. If a tier's Model is missing, BaseService falls back to a single plain
	placeholder floor instead of leaving the player standing on nothing — same "functional before
	art" spirit as the rest of this project — and warns in Output so it's obvious a Model still
	needs to be built.

	Tiers are sequential, same shape as OreConfig.ToolTiers / MineShaftConfig.SuitTiers — index 1
	is the free starting base every player has by default (profile.BaseTier). Nothing purchases a
	tier upgrade yet (no UpgradeBase remote exists) — this is groundwork so the load path already
	knows how to pick the right Model once that purchase flow gets built (see DESIGN_NOTES.md's
	"Base building/tiers" bullet). BaseTierCosts is here in the same shape SuitTierCosts/
	ToolTierCosts already use, ready for whenever that remote gets written.
]]

local BaseConfig = {}

BaseConfig.TemplateFolderName = "BaseTemplates"

BaseConfig.Tiers = {
	{ Name = "Scrap Workbench", ModelName = "BaseTier1" },
	{ Name = "Reinforced Workshop", ModelName = "BaseTier2" },
	-- Add more tiers here (and the matching Studio Model) to extend the ladder — no code changes
	-- needed elsewhere once BaseTierCosts below and an UpgradeBase remote eventually exist.
}

BaseConfig.BaseTierCosts = {
	[2] = { ScrapIron = 100, CopperWire = 50 },
}

return BaseConfig
