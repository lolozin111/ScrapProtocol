--[[
	Sfx.lua
	The one place a Sound gets built. Everything audible goes through Sfx.play / Sfx.playAt /
	Sfx.loop, named from Shared/SoundConfig.lua — no service or panel should call Instance.new("Sound")
	itself, for the same reason nothing hand-rolls a TextButton any more: two copies drift.

	WHY CLIENT-SIDE. Feedback sounds belong on the machine that caused them. A click, a mining swing
	or a rejected purchase played from the server arrives a round trip after the thing it is meant to
	confirm, which reads as lag even when nothing is lagging. Raids are private instances and base
	waves are the player's own plot, so there is almost nothing here another player would need to
	hear — where there eventually is, the server should fire a remote and let each client play it,
	not parent a Sound in Workspace.

	MISSING AUDIO NEVER BREAKS ANYTHING. An entry still sitting at Id = 0 plays nothing and warns
	once. A name that is not in SoundConfig at all also plays nothing, and warns once with a
	different message, because a typo and an unfilled slot need different fixes. Same rule the rest
	of the project uses for missing models and icons.

	NO DEPENDENCY ON HudKit, on purpose: HudKit calls INTO this module for button and toast sounds,
	so requiring it back would be a cycle. 2D sounds are parented to SoundService, which plays them
	non-positionally, rather than to the HUD's ScreenGui.
]]

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundConfig = require(ReplicatedStorage.Shared.SoundConfig)

local Sfx = {}

-- Global mute, for a settings toggle later. Checked at play time rather than at require time, so
-- flipping it takes effect immediately.
Sfx.Muted = false

-- One warning per name, not per call. A mining swing with no asset would otherwise print several
-- times a second and bury everything else in Output — which is exactly how a useful warning becomes
-- a reason to stop reading Output.
local warned: { [string]: boolean } = {}

local function warnOnce(name: string, reason: string)
	if warned[name] then
		return
	end
	warned[name] = true
	if reason == "unknown" then
		warn(("[Sfx] No sound named %q in SoundConfig.Sounds — check the spelling."):format(name))
	else
		warn(("[Sfx] Sound %q has no asset ID yet (Id = 0 in SoundConfig). Playing nothing."):format(name))
	end
end

local function pitchFor(entry): number
	local pitch = entry.Pitch
	if pitch == nil then
		return 1
	end
	if type(pitch) == "number" then
		return pitch
	end
	-- A {min, max} pair is rolled per play. This is what keeps a rapid sound from reading as one
	-- sample retriggered — see SoundConfig's note on MineSwing.
	local lo, hi = pitch[1] or 1, pitch[2] or 1
	if hi < lo then
		lo, hi = hi, lo
	end
	return lo + math.random() * (hi - lo)
end

-- Builds the Sound, unparented and not yet playing. nil means "nothing to play" — muted, unknown
-- name, or an asset ID still at 0 — and every caller treats all three the same way.
local function build(name: string): (Sound?, { [string]: any }?)
	if Sfx.Muted then
		return nil, nil
	end
	local entry, reason = SoundConfig.Get(name)
	if not entry then
		warnOnce(name, reason or "empty")
		return nil, nil
	end

	local sound = Instance.new("Sound")
	sound.Name = "Sfx_" .. name
	sound.SoundId = SoundConfig.AssetId(entry)
	sound.Volume = entry.Volume or SoundConfig.DefaultVolume
	sound.PlaybackSpeed = pitchFor(entry)
	return sound, entry
end

-- Where a sound should hang, given what the caller passed. Returns the parent plus, when one had to
-- be created, a holder to destroy alongside the sound.
--
-- A BasePart means the sound RIDES it (a firing gun, a moving enemy); a Vector3 means a fixed point
-- (an impact, which should not follow whatever it hit); nil means 2D. A Model with no usable part
-- falls back to 2D rather than dropping the sound, because a placeholder rig with no PrimaryPart is
-- a known, tolerated state in this project and silence would be the wrong penalty for it.
local function resolveParent(target): (Instance, Instance?)
	if target == nil then
		return SoundService, nil
	end
	if typeof(target) == "Vector3" then
		local holder = Instance.new("Part")
		holder.Name = "SfxPoint"
		holder.Anchored = true
		holder.CanCollide = false
		-- CanQuery = false matters specifically in this project: a stray queryable part in the world
		-- is one of the documented causes of "I click and nothing happens", because mouse rays stop
		-- on it. An invisible one nobody knows about is the worst version of that.
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.Position = target
		holder.Parent = workspace
		return holder, holder
	end
	if typeof(target) == "Instance" then
		if target:IsA("BasePart") then
			return target, nil
		end
		if target:IsA("Model") then
			local part = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
			if part then
				return part, nil
			end
		end
	end
	return SoundService, nil
end

local function apply3D(sound: Sound, entry, target)
	if target == nil then
		return
	end
	sound.RollOffMaxDistance = (entry and entry.Range) or SoundConfig.DefaultRange
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
end

-- Destroy after it finishes. Ended is the right signal but it never fires for a sound that fails to
-- load (a bad ID, or third-party audio this experience is not allowed to play — see SoundConfig's
-- note), so Debris is the backstop. Without it every failed sound would be a permanent instance,
-- and the failure mode of the audio system would be a slow leak instead of silence.
--
-- Loops deliberately do NOT come through here: their lifetime belongs to the caller, and handing a
-- looping sound to Debris would silence the ambience ten seconds in.
local MAX_LIFETIME = 10

local function playOnce(sound: Sound, holder: Instance?)
	sound.Ended:Once(function()
		sound:Destroy()
		if holder then
			holder:Destroy()
		end
	end)
	Debris:AddItem(sound, MAX_LIFETIME)
	if holder then
		Debris:AddItem(holder, MAX_LIFETIME)
	end
	sound:Play()
end

-- A 2D sound: UI, and anything about the local player's own state. Returns the Sound, or nil when
-- there was nothing to play — callers should not need to check.
function Sfx.play(name: string): Sound?
	local sound = build(name)
	if not sound then
		return nil
	end
	sound.Parent = SoundService
	playOnce(sound)
	return sound
end

-- A 3D sound at a place in the world. See resolveParent for what `target` may be.
function Sfx.playAt(name: string, target: BasePart | Model | Vector3): Sound?
	local sound, entry = build(name)
	if not sound then
		return nil
	end
	apply3D(sound, entry, target)
	local parent, holder = resolveParent(target)
	sound.Parent = parent
	playOnce(sound, holder)
	return sound
end

-- The weapon's family sound, falling back to WeaponFire_Default. `family` comes from
-- CraftingRecipes.Weapons[key].Family.
function Sfx.weaponFire(family: string?, target: (BasePart | Model | Vector3)?): Sound?
	local name = SoundConfig.WeaponFireName(family)
	if target then
		return Sfx.playAt(name, target)
	end
	return Sfx.play(name)
end

-- Ambience, and anything that runs until told to stop. Returns a stop function — ALWAYS, even when
-- nothing is playing, so a caller can store and call it without a nil check and without its
-- teardown path depending on whether the asset happened to be filled in yet.
function Sfx.loop(name: string, target: (BasePart | Model | Vector3)?): () -> ()
	local sound, entry = build(name)
	if not sound then
		return function() end
	end
	sound.Looped = true
	apply3D(sound, entry, target)
	local parent, holder = resolveParent(target)
	sound.Parent = parent
	sound:Play()

	local stopped = false
	return function()
		if stopped then
			return
		end
		stopped = true
		if sound.Parent then
			sound:Stop()
			sound:Destroy()
		end
		if holder and holder.Parent then
			holder:Destroy()
		end
	end
end

return Sfx
