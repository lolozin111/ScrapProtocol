--[[
	SoundConfig.lua
	Every sound in the game, by name, with its asset ID and how it should play. Read by
	StarterPlayerScripts/Sfx.lua — nothing else should build a Sound instance by hand.

	Same shape and the same rules as ItemIconConfig/UiIconConfig, deliberately: one config file of
	asset IDs, filled in a few at a time, where a missing entry is never an error.

	HOW TO FILL THIS IN: upload the audio to Roblox (Studio -> View -> Asset Manager -> Audio), then
	replace the 0 next to the name with the number Roblox gives you back. Just the number — Sfx adds
	the "rbxassetid://" prefix itself. A full "rbxassetid://123" string works too.

	A 0 means "not uploaded yet" and is NOT an error. Sfx.play on a silent entry does nothing at all
	and warns once per name, so the game stays playable with no audio whatsoever and each sound
	starts working the moment its number lands here. This is the same rule the rest of the project
	follows for missing art: a missing asset falls back and warns, it never breaks the loop.

	AUDIO ON ROBLOX, worth knowing before you go hunting for IDs: audio you did not upload yourself
	is usually NOT playable in your experience — Roblox gates third-party audio, and a sound from a
	toolbox model will often just be silent with a permissions error in Output rather than a missing
	asset. Upload your own files, or use assets from Roblox's own audio library that are marked
	usable. If a sound is silent in Studio but its ID is filled in here, check Output for a
	permissions line before assuming this file is wrong.

	FIELDS, all optional except Id:
	  Id      number | string   the asset. 0 = not uploaded yet (silent, warns once).
	  Volume  number            0-1ish. Default 0.5.
	  Pitch   number | {n, n}   PlaybackSpeed. A pair is a RANDOM RANGE rolled per play, which is
	                            what stops a rapid-fire sound (a mining swing, a minigun) turning
	                            into a machine-gun of one identical sample. Default 1.
	  Range   number            3D only: RollOffMaxDistance in studs. Default 120.
	  Looped  boolean           For ambience. Sfx.loop handles these; Sfx.play does not.

	NAMING: keys are free-form and used only from Lua, so unlike ItemIconConfig nothing has to match
	another config's keys character for character — EXCEPT the WeaponFire_* entries, whose suffix is
	the weapon's Family from CraftingRecipes.Weapons. Sfx.weaponFire(family) builds that name, so a
	family with no entry falls back to WeaponFire_Default rather than going silent.
]]

local SoundConfig = {}

SoundConfig.DefaultVolume = 0.5
SoundConfig.DefaultRange = 120

SoundConfig.Sounds = {
	------------------------------------------------------------------
	-- UI. All 2D (non-positional). These fire constantly, so they want
	-- to be short, quiet, and dry — a UI click at Volume 0.5 is much
	-- louder in practice than a gunshot at 0.5, because nothing
	-- attenuates it.
	------------------------------------------------------------------
	ButtonClick   = { Id = 0, Volume = 0.35 },
	ButtonHover   = { Id = 0, Volume = 0.15 },
	PanelOpen     = { Id = 0, Volume = 0.4 },
	PanelClose    = { Id = 0, Volume = 0.3 },
	TabSwitch     = { Id = 0, Volume = 0.25 },

	-- One per toast kind, matching the accent cap colours. Bad is the one worth getting right:
	-- it is the only audio feedback a rejected action gets, and a rejection that sounds the same
	-- as a success trains people to ignore both.
	ToastInfo     = { Id = 0, Volume = 0.3 },
	ToastGood     = { Id = 0, Volume = 0.35 },
	ToastBad      = { Id = 0, Volume = 0.4 },

	Purchase      = { Id = 0, Volume = 0.5 },
	Sell          = { Id = 0, Volume = 0.45 },
	Denied        = { Id = 0, Volume = 0.4 },

	------------------------------------------------------------------
	-- Mining. The swing fires several times a second at a high swing
	-- rate, so it NEEDS a pitch range; a fixed pitch here is the single
	-- most fatiguing sound the game could have.
	------------------------------------------------------------------
	MineSwing     = { Id = 0, Volume = 0.45, Pitch = { 0.92, 1.08 }, Range = 80 },
	MineHit       = { Id = 0, Volume = 0.5, Pitch = { 0.9, 1.1 }, Range = 80 },
	OreBreak      = { Id = 0, Volume = 0.6, Pitch = { 0.95, 1.05 }, Range = 100 },
	OreCollect    = { Id = 0, Volume = 0.35, Pitch = { 0.98, 1.06 } },
	ShaftReset    = { Id = 0, Volume = 0.7, Range = 250 },
	HazardWarn    = { Id = 0, Volume = 0.5 },

	------------------------------------------------------------------
	-- Combat. WeaponFire_* keys off CraftingRecipes.Weapons[key].Family
	-- — six families, so six sounds rather than one per weapon, the
	-- same economy getItemIcon's family fallback uses for icons.
	------------------------------------------------------------------
	WeaponFire_Default          = { Id = 0, Volume = 0.5, Pitch = { 0.96, 1.04 }, Range = 150 },
	WeaponFire_Bows             = { Id = 0, Volume = 0.45, Pitch = { 0.97, 1.03 }, Range = 120 },
	WeaponFire_Flamethrowers    = { Id = 0, Volume = 0.4, Pitch = { 0.98, 1.02 }, Range = 120 },
	WeaponFire_GrenadeLaunchers = { Id = 0, Volume = 0.6, Pitch = { 0.95, 1.05 }, Range = 180 },
	WeaponFire_Miniguns         = { Id = 0, Volume = 0.4, Pitch = { 0.94, 1.06 }, Range = 150 },
	WeaponFire_Salvage          = { Id = 0, Volume = 0.5, Pitch = { 0.94, 1.06 }, Range = 140 },
	WeaponFire_Snipers          = { Id = 0, Volume = 0.65, Pitch = { 0.98, 1.02 }, Range = 250 },

	EnemyHit      = { Id = 0, Volume = 0.4, Pitch = { 0.9, 1.1 }, Range = 120 },
	Headshot      = { Id = 0, Volume = 0.55, Range = 120 },
	Crit          = { Id = 0, Volume = 0.55, Range = 120 },
	EnemyDeath    = { Id = 0, Volume = 0.5, Pitch = { 0.92, 1.08 }, Range = 140 },
	PlayerHurt    = { Id = 0, Volume = 0.5 },
	PlayerDown    = { Id = 0, Volume = 0.7 },
	ShieldBreak   = { Id = 0, Volume = 0.55 },
	Dash          = { Id = 0, Volume = 0.4, Pitch = { 0.97, 1.03 } },
	Reload        = { Id = 0, Volume = 0.4, Range = 60 },

	------------------------------------------------------------------
	-- Raid
	------------------------------------------------------------------
	RoomEnter     = { Id = 0, Volume = 0.45 },
	NodeChoose    = { Id = 0, Volume = 0.35 },
	ChestOpen     = { Id = 0, Volume = 0.6, Range = 80 },
	BossSpawn     = { Id = 0, Volume = 0.8 },
	Extract       = { Id = 0, Volume = 0.6 },
	RunDefeat     = { Id = 0, Volume = 0.6 },
	CardPick      = { Id = 0, Volume = 0.5 },

	------------------------------------------------------------------
	-- Crafting, forging, smelting
	------------------------------------------------------------------
	CraftStart    = { Id = 0, Volume = 0.45 },
	CraftDone     = { Id = 0, Volume = 0.55 },
	SmeltStart    = { Id = 0, Volume = 0.4 },
	SmeltDone     = { Id = 0, Volume = 0.5 },
	ForgeRoll     = { Id = 0, Volume = 0.5 },
	-- Deliberately separate from ForgeRoll: the reveal is the payoff and wants its own sound, and
	-- a rare reveal that sounds identical to a common one throws away the only moment in the Forge
	-- where audio can carry the whole feeling.
	RarityReveal  = { Id = 0, Volume = 0.6 },

	------------------------------------------------------------------
	-- Base and waves
	------------------------------------------------------------------
	WaveStart     = { Id = 0, Volume = 0.6 },
	WaveClear     = { Id = 0, Volume = 0.6 },
	TurretPlace   = { Id = 0, Volume = 0.5, Range = 80 },
	TurretFire    = { Id = 0, Volume = 0.35, Pitch = { 0.94, 1.06 }, Range = 120 },
	BaseUpgrade   = { Id = 0, Volume = 0.6 },
}

-- Returns the entry, or nil when the name is unknown OR its Id is still 0. Callers treat both the
-- same way (play nothing), so they are one return rather than two — the DIFFERENCE matters only to
-- Sfx's warning, which says which of the two it was, because "you typo'd the name" and "you haven't
-- uploaded it yet" need different fixes.
function SoundConfig.Get(name: string): ({ [string]: any }?, string?)
	local entry = SoundConfig.Sounds[name]
	if entry == nil then
		return nil, "unknown"
	end
	local id = entry.Id
	if id == nil or id == 0 or id == "" then
		return nil, "empty"
	end
	return entry, nil
end

-- "rbxassetid://N" from either a bare number or an already-prefixed string, same rule as
-- ItemIconConfig.Get so a pasted full asset string works exactly as well as a pasted number.
function SoundConfig.AssetId(entry: { [string]: any }): string
	local id = entry.Id
	if type(id) == "number" then
		return ("rbxassetid://%d"):format(id)
	end
	return tostring(id)
end

-- The WeaponFire name for a family, with the Default fallback applied here rather than at the call
-- site — so a new weapon family added to CraftingRecipes makes a sound immediately (the default
-- one) instead of silently having none until someone remembers to add an entry.
function SoundConfig.WeaponFireName(family: string?): string
	if family then
		local specific = "WeaponFire_" .. family
		local entry = SoundConfig.Sounds[specific]
		if entry and entry.Id ~= 0 and entry.Id ~= "" then
			return specific
		end
	end
	return "WeaponFire_Default"
end

return SoundConfig
