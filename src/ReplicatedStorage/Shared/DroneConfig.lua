--[[
	DroneConfig.lua
	The drone companion and its four Drone Cores.

	=== WHAT THIS IS ===
	One drone, unlocked once, that follows you EVERYWHERE — raids, base defense, the mine, the
	overworld. What it DOES is decided by which Core is slotted into it, and you hold one at a time.
	So the drone is a chassis and the Cores are its personality, which is what makes "should I run
	Scavenger while mining and swap to Combat before a wave" a real decision rather than a menu.

	Deliberately not raid-only, even though the original note in DESIGN_NOTES.md said "a raid
	drone-companion slot": two of the four archetypes (Scavenger, Recon) have almost nothing to do
	inside a raid, and a companion that vanishes the moment you leave one is barely a companion.

	=== HOW IT IS EARNED ===
	The drone itself unlocks at Research Tier 3 (UnlockResearchTier) — the same "Fortified Bunker"
	milestone that widens your plot, so the drone arrives when your base starts looking like a base.
	Nothing to buy: reaching the tier IS the unlock.

	The Cores split by source on purpose:
	  Combat, Support     CRAFTED at the Welding Station. Predictable — you pick the one you want.
	  Scavenger, Recon    Black Market EPIC rolls. You cannot choose; you chase.
	That split means unlocking the drone is a beginning rather than a completed system: two cores
	arrive immediately so it is useful the moment you get it, and two are a reason to keep opening
	cases long after the pickaxes are all owned.

	=== SCALING ===
	A Core gets stronger as your Research Tier climbs past the one that unlocked the drone. Which of
	its Params scale is declared per Core in `Scales`, so the drone keeps pace with the base it came
	from instead of being a Tier 3 reward you are still carrying, unchanged, at Tier 6.

	Scaling is on the PARAMS, not on a hidden multiplier applied later, so `DroneConfig.ScaledParams`
	is the one place that knows about it and a behaviour reads plain numbers exactly as before.

	Deliberately additive-per-tier rather than compounding: three tiers of +25% is +75%, not +95%.
	Compounding a companion alongside everything else that scales with tier (wall HP, turret levels,
	slot count) stacks up much faster than it reads on the page.

	=== ADDING A CORE ===
	An entry here plus a matching strategy in DroneBehaviors.lua. If Source is "Craft" give it a
	Cost; if "Case", add a `{ Kind = "DroneCore", Key = "..." }` line to CaseConfig's Epic pool.
	`Scales` is optional — a Core without it simply stays flat.
]]

local DroneConfig = {}

-- Research tier that unlocks the drone chassis. See ResearchConfig.Tiers — 3 is "Fortified Bunker"
-- at wave 10.
DroneConfig.UnlockResearchTier = 3

-- Display order wherever Cores are listed.
DroneConfig.Order = { "Combat", "Support", "Scavenger", "Recon" }

--[[
	FIELDS
	  DisplayName / Description
	  Source     "Craft" (Welding Station) or "Case" (Black Market Epic)
	  Cost       required when Source is "Craft"
	  Behavior   strategy name in DroneBehaviors.lua
	  TickInterval  seconds between activations of that behaviour
	  Params     base numbers for the behaviour, AS THEY ARE AT THE UNLOCK TIER. What a behaviour
	             actually receives is DroneConfig.ScaledParams(core, profile) — see SCALING above.
	  Scales     optional { paramKey = fractionPerTier }. Omitted means that Core never changes.
	  Color      the drone's body tint while this Core is slotted — the fastest read on which one
	             is actually active, since you can see it hovering next to you
]]
DroneConfig.Cores = {
	Combat = {
		DisplayName = "Combat Core",
		Description = "Picks a target and shoots it. Won't win a fight for you; will finish one.",
		Source = "Craft",
		Cost = { Scrap = 900, SteelPlating = 60, CopperWire = 45 },
		Behavior = "Combat",
		TickInterval = 1.2,
		Color = Color3.fromRGB(255, 120, 90),
		Params = {
			Damage = 14,        -- flat, NOT scaled off your weapon: a companion that gets better
			                    -- purely because your gun did is a damage multiplier wearing a hat
			Range = 90,
		},
		-- Damage only. Range deliberately does not scale — a drone that out-ranges what you can see
		-- starts shooting things you have not noticed yet, which reads as the wave spawning wrong.
		Scales = { Damage = 0.30 },
	},

	Support = {
		DisplayName = "Support Core",
		Description = "Trickles your health back between fights. Quiet, and you'll miss it when it's gone.",
		Source = "Craft",
		Cost = { Scrap = 900, CopperWire = 70, SteelIngot = 15 },
		Behavior = "Support",
		TickInterval = 2,
		Color = Color3.fromRGB(120, 235, 150),
		Params = {
			-- A fraction of MaxHealth rather than a flat number, so it stays relevant if the player's
			-- health pool ever changes, and never trivialises a low-health character.
			HealFraction = 0.04,
			-- Held off while you are actively being shot at, so it tops you up BETWEEN fights instead
			-- of quietly out-healing incoming damage and making waves unlosable.
			SuppressedForSeconds = 4,
		},
		-- The heal scales; the suppression window does NOT. Shortening it with tier would erode the
		-- one thing keeping this from out-healing a fight, which is the property that has to hold at
		-- every tier rather than the number that is allowed to grow.
		Scales = { HealFraction = 0.25 },
	},

	Scavenger = {
		DisplayName = "Scavenger Core",
		Description = "Sifts what you break for anything you missed. Pure profit, no combat use at all.",
		Source = "Case",
		Behavior = "Scavenger",
		TickInterval = 0,   -- event-driven: fires when you mine, not on a timer
		Color = Color3.fromRGB(240, 200, 100),
		Params = {
			-- A CHANCE of a bonus haul rather than a flat yield multiplier. A multiplier would be
			-- invisible — you would never know it was working — where an occasional "the drone found
			-- something" is a moment you actually notice. Same reasoning as the damage numbers.
			Chance = 0.25,
			BonusMultiplier = 1.0, -- doubles that hit's yield when it procs
		},
		-- The proc CHANCE scales rather than the size of the bonus, so a late-game Scavenger fires
		-- noticeably more often instead of very occasionally paying out an absurd number. Clamped
		-- below 1 in ScaledParams so it can never become a guaranteed double.
		Scales = { Chance = 0.20 },
	},

	Recon = {
		DisplayName = "Recon Core",
		Description = "Paints everything nearby. You see them through walls, and they take more from everyone.",
		Source = "Case",
		Behavior = "Recon",
		TickInterval = 1.5,
		Color = Color3.fromRGB(140, 190, 255),
		Params = {
			Range = 120,
			-- Marking is a team-wide debuff on the target, not a personal damage bonus, which is what
			-- keeps Recon from just being a worse Combat Core.
			MarkDuration = 4,
		},
		-- Duration, not range or strength: a longer mark means more of the wave stays lit at once,
		-- which is what Recon is actually for. Scaling the debuff itself would quietly buff every
		-- damage source in the game at once.
		Scales = { MarkDuration = 0.25 },
	},
}

-- How the chassis flies. Tuned so it reads as "following you" rather than "welded to your back".
DroneConfig.Follow = {
	Offset = Vector3.new(3.5, 4.5, 2.5), -- right, up, behind — out of the crosshair on purpose
	-- Fraction of the remaining gap closed per second. Below 1 gives the lag that makes it look like
	-- a thing keeping up with you rather than part of the character model.
	Smoothing = 6,
	BobHeight = 0.35,
	BobSpeed = 2.2,
	-- Past this it gives up and teleports. Covers respawns, raid teleports and mine-shaft falls,
	-- none of which it could ever catch up with by flying.
	TeleportDistance = 120,
}

-- A Core's Params with its `Scales` entries grown by the player's Research Tier. Returns the Core's
-- own Params table untouched when nothing scales, so the common case allocates nothing.
--
-- Bonus is (tier - UnlockResearchTier), so a Core is exactly its printed numbers at the tier that
-- unlocked it and only grows from there — the config reads as what you get when you first earn it.
function DroneConfig.ScaledParams(coreData, profile)
	local params = coreData.Params or {}
	if not coreData.Scales then
		return params
	end

	local tier = (profile and profile.ResearchTier) or 1
	local steps = math.max(0, tier - DroneConfig.UnlockResearchTier)
	if steps == 0 then
		return params
	end

	-- Copied, never mutated: Params is shared config, and writing scaled values back into it would
	-- compound every time this ran and leak one player's tier into everyone else's drone.
	local scaled = table.clone(params)
	for key, perTier in pairs(coreData.Scales) do
		local base = params[key]
		if type(base) == "number" then
			scaled[key] = base * (1 + perTier * steps)
		end
	end

	-- A probability that scaled past certainty would make its Core silently stop being a gamble.
	if scaled.Chance then
		scaled.Chance = math.min(scaled.Chance, 0.95)
	end

	return scaled
end

-- One line describing what this Core does AT THIS PLAYER'S TIER. The Drones tab shows it, because
-- a Core that quietly got 60% stronger with no number attached is the same invisible-buff problem
-- that made the Ultimate mods feel broken before damage numbers existed.
function DroneConfig.EffectSummary(coreKey: string, profile): string
	local core = DroneConfig.Cores[coreKey]
	if not core then
		return ""
	end
	local p = DroneConfig.ScaledParams(core, profile)

	if coreKey == "Combat" then
		return ("%d damage every %.1fs, up to %d studs"):format(p.Damage, core.TickInterval, p.Range)
	elseif coreKey == "Support" then
		return ("+%.0f%% max HP every %.0fs, %.0fs after being hit"):format(
			p.HealFraction * 100, core.TickInterval, p.SuppressedForSeconds)
	elseif coreKey == "Scavenger" then
		return ("%.0f%% chance to double any ore you mine"):format(p.Chance * 100)
	elseif coreKey == "Recon" then
		return ("marks enemies within %d studs for %.1fs"):format(p.Range, p.MarkDuration)
	end
	return ""
end

function DroneConfig.IsUnlocked(profile): boolean
	return (profile and profile.ResearchTier or 1) >= DroneConfig.UnlockResearchTier
end

function DroneConfig.Equipped(profile)
	local key = profile and profile.EquippedDroneCore
	return key and DroneConfig.Cores[key] or nil
end

-- Cores this player could craft right now, in display order. Used by the Welding Station's tab.
function DroneConfig.CraftableKeys(): { string }
	local keys = {}
	for _, key in ipairs(DroneConfig.Order) do
		if DroneConfig.Cores[key].Source == "Craft" then
			table.insert(keys, key)
		end
	end
	return keys
end

return DroneConfig
