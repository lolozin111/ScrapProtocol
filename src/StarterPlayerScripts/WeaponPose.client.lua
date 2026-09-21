--[[
	WeaponPose.client.lua
	Plays the looping hold pose (WeaponPoseConfig) while a gun Tool is out.

	WHY THIS IS ON THE CLIENT, when the Tool itself is server-owned (WeaponToolService):

	This started server-side, and the first equip visibly played Roblox's DEFAULT tool hold for a
	moment before snapping into the real pose. That was not the animation downloading — preloading
	it at join and loading the track early both helped only slightly, which is what ruled the theory
	out. It is a RACE. Equipping fires locally on this machine, where Roblox's own Animate script
	plays its "toolnone" pose immediately; the server's play of the real pose then has to make a
	round trip back here. The default hold winning by a network hop is exactly the flicker.

	Playing it here removes the trip entirely — the pose starts on the same frame as the equip. It
	still reaches everyone else, because an animation played on your own character replicates out
	through the Animator the same way your walk does.

	Nothing about this is a trust boundary: a pose is cosmetic, it grants nothing, and a player who
	edits it locally has changed how their own arms look. Every decision that MATTERS about a weapon
	— what it is, whether it may fire, what it hits for — stays on the server, unchanged.

	Priority is Action2, deliberately one step ABOVE the Action that Roblox's tool animations use,
	so ours wins outright instead of tying with "toolnone" and leaving the outcome to blend weights.
	It still only touches the joints the pose actually keyframes (the arms), so the legs keep running
	the default walk/run/jump underneath it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponPoseConfig = require(ReplicatedStorage.Shared.WeaponPoseConfig)

local POSE_FADE = 0.15 -- seconds, both directions; a hard cut to a pose reads as a snap

local player = Players.LocalPlayer

local animations: { [string]: Animation } = {}
local tracks: { [string]: AnimationTrack } = {} -- animationId -> track on the CURRENT character
local activeTrack: AnimationTrack? = nil
local animator: Animator? = nil

local function isWeaponTool(instance: Instance): boolean
	return instance:IsA("Tool") and instance:GetAttribute("WeaponTool") == true
end

-- Loads the track for weaponKey onto the current character without playing it. Returns nil when the
-- weapon has no pose yet (then the default arms play, exactly as before any of this existed).
local function trackFor(weaponKey: string?): AnimationTrack?
	if not weaponKey or not animator then
		return nil
	end

	local animationId = WeaponPoseConfig.Get(weaponKey)
	if not animationId then
		return nil
	end
	if tracks[animationId] then
		return tracks[animationId]
	end

	local animation = animations[animationId]
	if not animation then
		animation = Instance.new("Animation")
		animation.AnimationId = animationId
		animations[animationId] = animation
	end

	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if not ok or not track then
		warn(("[WeaponPose] Could not load the hold pose for %s (%s) — check the animation exists and is owned by whoever owns this place."):format(weaponKey, animationId))
		return nil
	end

	track.Priority = Enum.AnimationPriority.Action2
	track.Looped = true
	tracks[animationId] = track
	return track
end

local function stopPose()
	if activeTrack then
		pcall(function()
			(activeTrack :: AnimationTrack):Stop(POSE_FADE)
		end)
		activeTrack = nil
	end
end

local function playPose(weaponKey: string?)
	local track = trackFor(weaponKey)
	if track == activeTrack then
		return
	end
	stopPose()
	if track then
		track:Play(POSE_FADE)
		activeTrack = track
	end
end

-- A Tool parented INTO the character is what "equipped" means; back out to the Backpack, or
-- destroyed while held, is what "unequipped" means. Watching the parent rather than the Tool's own
-- Equipped/Unequipped events covers the destroyed-while-held case for free — the same case that
-- needed handling separately on the server side.
local function onCharacter(character: Model)
	tracks = {}
	activeTrack = nil
	animator = nil

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	animator = humanoid:WaitForChild("Animator", 10) :: Animator?
	if not animator then
		return
	end

	-- Load the pose for whatever gun this character already owns, before it is ever equipped, so
	-- the first equip has nothing left to fetch. Backpack and character both, since a respawn can
	-- hand the gun back either way.
	local backpack = player:FindFirstChildOfClass("Backpack")
	for _, container in ipairs({ backpack, character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if isWeaponTool(child) then
					trackFor(child:GetAttribute("WeaponKey"))
				end
			end
		end
	end

	character.ChildAdded:Connect(function(child)
		if isWeaponTool(child) then
			playPose(child:GetAttribute("WeaponKey"))
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if isWeaponTool(child) then
			stopPose()
		end
	end)

	-- Already holding one at spawn.
	for _, child in ipairs(character:GetChildren()) do
		if isWeaponTool(child) then
			playPose(child:GetAttribute("WeaponKey"))
		end
	end
end

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)
