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

	=== ADDING A CORE ===
	An entry here plus a matching strategy in DroneBehaviors.lua. If Source is "Craft" give it a
	Cost; if "Case", add a `{ Kind = "DroneCore", Key = "..." }` line to CaseConfig's Epic pool.
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
	  Params     handed to the behaviour untouched
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
