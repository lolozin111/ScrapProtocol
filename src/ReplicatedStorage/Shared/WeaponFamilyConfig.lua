--[[
	WeaponFamilyConfig.lua
	Which weapons belong together, and which of those groups a player has actually unlocked.

	=== WHY FAMILIES EXIST ===
	The Forge's Weapons tab used to be a flat list of every weapon in the game, which was fine at
	four. It is not fine at eighteen — the list stops being a menu and becomes a wall. Families give
	that list a top level: pick Bows, see the bows.

	They are also the delivery mechanism for Black Market gun variants. A blueprint unlocks a WHOLE
	FAMILY rather than a single gun ("the blueprint will unlock a new gun tab for that variant"), so
	rolling one Bow blueprint opens Bows as a category and the individual bows are then Forged
	normally, with the usual rarity/affix roll. That is deliberately different from how turrets work,
	where a blueprint unlocks exactly one thing: a family is a much bigger prize, which is what a
	Legendary case roll should feel like.

	=== UNLOCKING ===
	`profile.UnlockedWeaponFamilies[key] = true`. Salvage is unlocked for everyone from the first
	login (see DefaultUnlocked below) — without it a new player has no weapons at all and no way to
	fight for the ones they're missing. Every other family comes from a case.

	Unlock state is enforced SERVER-SIDE in ForgeService.ForgeWeapon. The Forge UI hiding a locked
	family is a convenience on top of that check, never a replacement for it.

	=== ADDING A FAMILY ===
	An entry here, an `Order` position, and `Family = "<key>"` on its weapons in CraftingRecipes.
	Then add a `{ Kind = "WeaponFamily", Key = "<key>" }` entry to CaseConfig's Legendary pool so it
	is actually obtainable. Nothing else needs to change.
]]

local WeaponFamilyConfig = {}

-- Display order in the Forge, low to high. A plain list rather than an `Order` field per entry so
-- there is exactly one place to reorder, and no way for two families to claim the same slot.
WeaponFamilyConfig.Order = {
	"Salvage",
	"Flamethrowers",
	"Bows",
	"Snipers",
	"GrenadeLaunchers",
	"Miniguns",
}

WeaponFamilyConfig.Families = {
	Salvage = {
		DisplayName = "Salvage",
		Description = "Improvised guns built from whatever the wasteland left behind.",
		UnlockedByDefault = true,
	},

	Flamethrowers = {
		DisplayName = "Flamethrowers",
		BlueprintName = "Flamethrower Schematics",
		Description = "Short range, no aiming to speak of, and everything in the cone keeps burning.",
	},

	Bows = {
		DisplayName = "Bows",
		BlueprintName = "Bowyer's Notes",
		Description = "Silent, arcing, and rewarding to aim. Arrows drop — lead your shots.",
	},

	Snipers = {
		DisplayName = "Snipers",
		BlueprintName = "Marksman Dossier",
		Description = "One shot, one line straight through several bodies. Slow to fire, slow to carry.",
	},

	GrenadeLaunchers = {
		DisplayName = "Grenade Launchers",
		BlueprintName = "Ordnance Manual",
		Description = "Lobbed, bouncing, and indiscriminate. Damage is in the blast, not the hit.",
	},

	Miniguns = {
		DisplayName = "Miniguns",
		BlueprintName = "Rotary Assembly Plans",
		Description = "Individually pathetic rounds, delivered faster than anything else in the game.",
	},
}

-- The starting set, as a fresh table each call — handed straight to a profile, so returning a shared
-- one would let every player scribble on the same table.
function WeaponFamilyConfig.DefaultUnlocked(): { [string]: boolean }
	local unlocked = {}
	for key, family in pairs(WeaponFamilyConfig.Families) do
		if family.UnlockedByDefault then
			unlocked[key] = true
		end
	end
	return unlocked
end

-- Tolerant of an older save that predates this field entirely: a nil map still grants the
-- default-unlocked families, so nobody logs in weaponless while backfillMissingFields catches up.
function WeaponFamilyConfig.IsUnlocked(profile, key: string): boolean
	local family = WeaponFamilyConfig.Families[key]
	if not family then
		return false
	end
	if family.UnlockedByDefault then
		return true
	end
	return (profile and profile.UnlockedWeaponFamilies or {})[key] == true
end

-- What a blueprint is called when a case hands one over.
function WeaponFamilyConfig.BlueprintName(key: string): string
	local family = WeaponFamilyConfig.Families[key]
	if not family then
		return key
	end
	return family.BlueprintName or (family.DisplayName .. " Blueprint")
end

return WeaponFamilyConfig
