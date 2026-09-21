--[[
	WeaponPoseConfig.lua
	The looping hold pose a player plays while a gun Tool is equipped — one animation id per weapon
	FAMILY, resolved the same way ItemIconConfig resolves icons: exact weapon key first, then the
	weapon's CraftingRecipes.Weapons[key].Family, then Default. So three or four poses dress all 18
	guns, and a single weapon that needs its own can have one without touching this lookup.

	HOW TO FILL THIS IN: publish the pose animation, then paste the id next to its family. Just the
	number — Get() adds the "rbxassetid://" prefix. A 0 means "not made yet" and is NOT an error:
	Get returns nil, WeaponToolService plays nothing, and the player holds the gun on Roblox's own
	default arms exactly as they do today.

	THE POSE ITSELF (see DESIGN_NOTES): keyframe the ARM joints only — RightUpperArm/RightLowerArm/
	RightHand and their left-hand pair, plus UpperTorso if a lean is wanted. Keyframing the legs or
	the root would fight the default walk/run/jump instead of layering over them, which is the whole
	reason one static pose is enough. One keyframe, Looped = true.

	PRIORITY IS SET IN CODE, NOT HERE. WeaponToolService forces the track to Action priority on play,
	so a pose published at the wrong priority still layers correctly rather than being silently
	ignored or silently stopping the legs — a published animation's priority is otherwise invisible
	from Studio once it's uploaded, and that is a bad thing to have to guess at.

	GROUP-OWNED PLACES: an animation uploaded to a personal account will not load in a group place
	(and vice versa). It fails quietly, so if a pose does nothing, check who owns it first.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)

local WeaponPoseConfig = {}

WeaponPoseConfig.Poses = {
	-- Used when a weapon's family has no pose of its own. Also the whole system while only one pose
	-- exists — every gun uses it until the families below are filled in.
	Default = 135572728079965, -- the two-handed Sniper pose: the safest catch-all for a gun with no pose of its own

	-- Per family (the same six families the icons use).
	Salvage = 137890625294422, -- PipePistol, ScrapSMG, RailRifle, ArcCannon
	Flamethrowers = 132623057769269, -- Flamethrower, IceThrower, PoisonThrower
	Bows = 125134621015809, -- RegularBow, Longbow, ExplosiveBow, StringedBow
	Snipers = 135572728079965, -- RegularSniper, QuickSniper
	GrenadeLaunchers = 135572728079965, -- GrenadeLauncher, StickyGrenade — STAND-IN: the Sniper pose, until a launcher pose exists
	Miniguns = 135572728079965, -- Trailblazer, Hellfire, Minigun — STAND-IN: the Sniper pose; a hip-fire pose would read better

	-- Per weapon, optional: add a weapon's own key here (e.g. Minigun = 123) and it beats its
	-- family, for the one gun that a shared pose reads wrong on.
}

local function normalize(value: any): string?
	if value == nil or value == 0 or value == "" then
		return nil
	end
	if type(value) == "number" then
		return ("rbxassetid://%d"):format(value)
	end
	return tostring(value)
end

-- weaponKey -> the pose animation to play, or nil for "no pose, use the default arms".
function WeaponPoseConfig.Get(weaponKey: string): string?
	local exact = normalize(WeaponPoseConfig.Poses[weaponKey])
	if exact then
		return exact
	end
	local recipe = CraftingRecipes.Weapons[weaponKey]
	local family = recipe and recipe.Family
	if family then
		local byFamily = normalize(WeaponPoseConfig.Poses[family])
		if byFamily then
			return byFamily
		end
	end
	return normalize(WeaponPoseConfig.Poses.Default)
end

return WeaponPoseConfig
