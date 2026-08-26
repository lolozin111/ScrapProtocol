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
	is the free starting base every player has by default (profile.BaseTier). BaseService.lua now
	owns the UpgradeBase remote (gated at the Workbench, same as UpgradeTool/UpgradeSuit) that
	spends BaseTierCosts[nextTier] and bumps profile.BaseTier, then calls RebuildPlayerBase again
	to swap the physical Model.

	WallHP (added alongside the Combat Engine's wall-defense rework — see DESIGN_NOTES.md) is the
	base's real combat stat now: CombatEncounterService.RunWave reads
	BaseConfig.GetWallMaxHP(profile.BaseTier) at the start of every wave, so the wall gets tougher
	automatically the moment UpgradeBase bumps profile.BaseTier — no combat-side changes needed.
	Numbers below are a first guess, worth a playtest before treating as final.

	TURRETS (Base Defense & Turrets phase, round 2): superseded the first pass's "every deployed
	Robot gets a physical body" approach with a real dedicated Turret system — see
	TurretConfig.lua/TurretService.lua/TurretShopService.lua. What's left here is just the physical/
	Studio-facing half (Turret Models + their fallback + the placement ring), since that's a
	base-layout concern same as the rest of this file; everything about turret TYPES, leveling,
	blueprints, and the rotating Shop lives in TurretConfig.lua instead.

	CoreItems requirement: on top of BaseTierCosts' raw-material cost, upgrading past Tier 1 now
	also requires a specific profile.CoreItems entry (see DataService.lua/WaveService.lua) — dropped
	by base-defense boss waves, not purchasable. See BaseTierCoreRequirement below.
]]

local BaseConfig = {}

BaseConfig.TemplateFolderName = "BaseTemplates"

BaseConfig.Tiers = {
	{ Name = "Scrap Workbench", ModelName = "BaseTier1", WallHP = 150 },
	{ Name = "Reinforced Workshop", ModelName = "BaseTier2", WallHP = 300 },
	{ Name = "Fortified Bunker", ModelName = "BaseTier3", WallHP = 550 },
	{ Name = "Bastion", ModelName = "BaseTier4", WallHP = 900 },
	-- Add more tiers here (and the matching Studio Model) to extend the ladder — no code changes
	-- needed elsewhere, BaseTierCosts below just needs a matching entry.
}

-- Scrap + raw ore. Scrap is the game's main currency (raids and loot pay it out), and upgrading
-- the base itself is the single biggest thing it's spent on — so a base tier is gated on having
-- done BOTH halves of the loop: raided for Scrap and mined for materials. The CoreItem
-- requirement below adds the third (cleared a wave milestone), which is what makes a tier a real
-- checkpoint rather than something you can grind out of one activity.
--
-- Placeholder numbers — per-gamemode drop rates aren't settled yet, so treat the shape (Scrap
-- climbing steeply, ore following the tier ladder) as the intent and the values as provisional.
BaseConfig.BaseTierCosts = {
	[2] = { Scrap = 400, ScrapIron = 100, CopperWire = 50 },
	[3] = { Scrap = 1200, SteelPlating = 150, CopperWire = 80, GoldContacts = 20 },
	[4] = { Scrap = 3000, GoldContacts = 60, SteelPlating = 250 },
}

-- The CoreItem (profile.CoreItems, see DataService.lua) each BaseTier upgrade additionally
-- requires, on top of BaseTierCosts above — dropped by base-defense boss waves, see
-- RewardTables.BossCoreForMilestone/WaveService.lua, never purchasable with any currency. Keeps
-- the "beat a real wave milestone" gate the original design called for without needing a whole
-- separate boss-arena system — base defense's existing every-5th-wave elite cadence now IS the
-- boss milestone. No entry for Tier 1 (everyone starts there, nothing to gate).
BaseConfig.BaseTierCoreRequirement = {
	[2] = { Key = "CoreT1", Amount = 1 },
	[3] = { Key = "CoreT2", Amount = 1 },
	[4] = { Key = "CoreT3", Amount = 1 },
}

-- TurretModels: same Studio convention as EnemyModels/ItemIcons — a plain Folder
-- (ServerStorage.TurretModels, see default.project.json) holding one Model per
-- TurretConfig.Types key it's meant to represent, named EXACTLY that key (e.g. "SniperTurret").
-- No matching Model yet? TurretService falls back to a small plain placeholder pedestal — same
-- "functional before art" convention as everywhere else — and warns once per key in Output.
BaseConfig.TurretModelsFolderName = "TurretModels"

-- Fallback placeholder pedestal size (studs) when a turret type has no built Model yet.
BaseConfig.TurretFallbackSize = Vector3.new(3, 3, 3)

-- Turret SLOT ring — fixed, evenly-spaced positions (TurretConfig.GetSlotCount(profile
-- .ResearchTier) of them) a player can place a turret instance into; no more freeform "stand
-- anywhere and click place" like the first pass. Sized as a fraction of the plot's own claimed
-- footprint (PlotConfig.FootprintHalfSize) so every slot lands comfortably inside whatever BaseTier
-- Model is currently built, without needing to know that Model's real size.
BaseConfig.TurretRingRadiusFraction = 0.55

-- FALLBACK ONLY. CombatEncounterService.getWallAttackRange measures the "close enough to attack
-- the wall" distance off the player's REAL built base Model (BaseService.GetPlayerBaseModel) at
-- the start of every wave — this flat number is only ever used if that lookup fails for some
-- reason (base not finished building yet, bounding-box call errors). Sized as the half-DIAGONAL of
-- BaseService.FALLBACK_FLOOR_SIZE (40x40 → sqrt(20^2 + 20^2) ≈ 28), matching how
-- getWallAttackRange measures a real base now (circumscribed circle around the footprint, not
-- inscribed — see that function's own comment for why an inscribed circle let enemies stop while
-- still standing on the platform). getWallAttackRange adds its own WALL_STOP_MARGIN on top of
-- whichever of these two it uses, so this number itself doesn't need extra margin baked in.
BaseConfig.WallAttackRange = 28

function BaseConfig.GetWallMaxHP(baseTier: number?): number
	local tier = (baseTier and BaseConfig.Tiers[baseTier]) or BaseConfig.Tiers[1]
	return (tier and tier.WallHP) or 150
end

return BaseConfig
