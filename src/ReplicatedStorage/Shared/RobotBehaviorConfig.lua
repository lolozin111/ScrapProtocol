--[[
	RobotBehaviorConfig.lua
	Maps every CraftingRecipes.Robots key to how it behaves during a real-time combat encounter
	(CombatEncounterService.lua) — layered on top of CraftingRecipes the same way ForgeConfig,
	AutoMinerConfig, and every other add-on config in this project sits beside the recipe table
	instead of editing it directly.

	Two Modes:
	- "Combat" — the robot deals damage. Behavior picks HOW it targets, looked up by name in
	  RobotBehaviors.lua (server-side, since it's live combat logic, not data).
	- "Utility" — the robot buffs the player instead of dealing damage directly. Same
	  name-lookup-into-RobotBehaviors.lua pattern.

	This is deliberately a flat table of named behaviors, not a real behavior-tree engine — a robot
	just points at one named strategy plus its own tunables. Adding a new behavior later means
	writing one new function in RobotBehaviors.lua and pointing a config entry at its name; nothing
	about this file or the engine that reads it needs to change. If robot logic ever needs to
	branch on live conditions (health thresholds, ally state, priority between options) THAT's the
	point where upgrading to a real tree earns its cost — not needed yet.

	None of the 4 robots built so far use Utility mode — their existing CraftingRecipes stats
	(FireRate/BaseDamage/HP) were designed around dealing damage, so none of their flavor text
	actually fits "grants a shield" well. RobotBehaviors.Shield/SpeedBoost are built and working
	regardless, ready for whenever a support-flavored robot recipe exists to use them.
]]

local RobotBehaviorConfig = {}

RobotBehaviorConfig.Robots = {
	-- "A wobbly chassis... a single trigger-happy arm" — one arm, one target at a time.
	Scrapbot = {
		Mode = "Combat",
		Behavior = "SingleTarget",
	},
	-- "Sprays more than it aims" — hits more than one target, less focus per hit.
	SentryDrone = {
		Mode = "Combat",
		Behavior = "Cleave",
		TargetCount = 2,
	},
	-- "Slow and heavily plated" — no reason to change its targeting, it just hits hard and tanks.
	IronGuardian = {
		Mode = "Combat",
		Behavior = "SingleTarget",
	},
	-- Its own CraftingRecipes description already calls this out: "splash damage, treat as AoE" —
	-- Cleave with the widest target count of the four, matching "wide blast radius."
	ArcTurret = {
		Mode = "Combat",
		Behavior = "Cleave",
		TargetCount = 3,
	},
}

return RobotBehaviorConfig
