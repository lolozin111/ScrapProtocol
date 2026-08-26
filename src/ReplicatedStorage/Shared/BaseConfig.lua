--[[
	BaseConfig.lua
	The physical, Studio-facing half of the base — the parts that are NOT per-tier.

	The base TIER ladder (names, Models, costs, WallHP, footprint size, wave gates) is deliberately
	NOT here: it moved to ResearchConfig.lua when profile.BaseTier and profile.ResearchTier were
	merged into one progression number. If you're looking for "what does Tier 3 cost / how big is
	it / which Model does it use", that's ResearchConfig.Tiers.

	What's left below is the stuff that stays the same at every tier: the turret Model/placement
	conventions, and one combat fallback number.
]]

local BaseConfig = {}

-- TurretModels: same Studio convention as EnemyModels/ItemIcons — a plain Folder
-- (ServerStorage.TurretModels, see default.project.json) holding one Model per
-- TurretConfig.Types key it's meant to represent, named EXACTLY that key (e.g. "SniperTurret").
-- No matching Model yet? TurretService falls back to a small plain placeholder pedestal — same
-- "functional before art" convention as everywhere else — and warns once per key in Output.
BaseConfig.TurretModelsFolderName = "TurretModels"

-- Fallback placeholder pedestal size (studs) when a turret type has no built Model yet.
BaseConfig.TurretFallbackSize = Vector3.new(3, 3, 3)

-- Turret SLOT ring — fixed, evenly-spaced positions (TurretConfig.GetSlotCount(profile
-- .ResearchTier) of them) a player can place a turret instance into; no freeform "stand anywhere
-- and click place". Expressed as a FRACTION of the current tier's own footprint
-- (ResearchConfig.GetFootprintHalfSize) rather than an absolute radius, which is what lets the ring
-- widen automatically as the base grows: a tier that unlocks more slots also enlarges the footprint,
-- so the extra pads get real room instead of being crammed into a fixed-size circle.
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
--
-- Deliberately still a flat number rather than per-tier: it only applies when the real measurement
-- failed, and in that case the base almost certainly hasn't been built yet — so the smallest
-- sensible guess is the right one regardless of what tier the player has reached.
BaseConfig.WallAttackRange = 28

return BaseConfig
