--[[
	WeaponToolService.lua
	Turns "which weapon instance is equipped" (profile.EquippedWeaponId, unchanged — still the
	single source of truth CombatMath/RequestFireWeapon resolve combat stats from) into an actual
	Roblox Tool sitting in the player's Backpack/hotbar. Before this, "equipping" a weapon was pure
	data — nothing physical ever showed up for the player to hold. Only ONE gun Tool ever exists at
	a time, mirroring EquippedWeaponId's own "one equipped instance" model: syncing to a new weapon
	always tears down whichever gun Tool currently exists first.

	Call `WeaponToolService.SyncEquippedTool(player, weaponInstance)` any time EquippedWeaponId
	changes — `weaponInstance` is the resolved {Id, WeaponKey, Rarity, Affixes} table from
	profile.Weapons, or nil to clear the hotbar entirely. This file never touches
	profile.EquippedWeaponId itself; the caller (ForgeService.lua) owns that.

	Tool templates: drop a real Tool into ReplicatedStorage.WeaponTools (a plain Folder, see
	default.project.json), named EXACTLY like the weaponKey (e.g. "PipePistol"), with a Part named
	"Handle" — same "template folder, no code changes needed" convention as
	ServerStorage.EnemyModels/ReplicatedStorage.BaseTemplates/ReplicatedStorage.ItemIcons. UNLIKE
	those, a missing weapon Tool template doesn't just skip silently — a Tool with no Handle can't
	be held at all, so this builds a plain placeholder box Tool on the fly instead (cached after the
	first build) so equipping never breaks before gun art exists. Swap in the real Tool later; this
	file picks it up automatically the moment a Studio-authored one with that exact name exists,
	since the placeholder path is only ever a fallback.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)
local WeaponPoseConfig = require(ReplicatedStorage.Shared.WeaponPoseConfig)
local PlayerSpeed = require(script.Parent.PlayerSpeed)
local DataService = require(script.Parent.DataService)

local WeaponToolService = {}

-- WeaponKey -> a master Tool to :Clone() from (either the real Studio-authored template, or a
-- synthesized placeholder kept alive only by this table reference). Built/found once, reused for
-- every future equip of that weapon type.
local templateCache: { [string]: Tool } = {}

local function buildPlaceholderTool(weaponKey: string, recipe): Tool
	local tool = Instance.new("Tool")
	tool.Name = (recipe and recipe.DisplayName) or weaponKey
	tool.RequiresHandle = true
	tool.CanBeDropped = false -- dropping would desync from EquippedWeaponId — not offered yet

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.6, 0.6, 2.4)
	handle.Color = Color3.fromRGB(120, 120, 130)
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Parent = tool

	return tool
end

-- Only REAL Studio-authored templates are cached. A synthesized placeholder is rebuilt each time
-- instead, so the folder gets re-checked on every equip: caching the placeholder meant that once a
-- weapon had been equipped before its art existed, adding the real Tool mid-session had no effect
-- and you kept getting the grey box — quietly contradicting this file's own header, which promises
-- it "picks it up automatically the moment a Studio-authored one exists". Building a two-part Tool
-- is trivially cheap; being wrong about which gun the player is holding is not.
--
-- The warn is deduped separately so re-checking the folder doesn't spam Output on every equip.
local warnedMissingTemplate: { [string]: boolean } = {}

local function getTemplate(weaponKey: string): Tool
	local cached = templateCache[weaponKey]
	if cached then
		return cached
	end

	local templatesFolder = ReplicatedStorage:FindFirstChild("WeaponTools")
	local existing = templatesFolder and templatesFolder:FindFirstChild(weaponKey)
	if existing and existing:IsA("Tool") and existing:FindFirstChild("Handle") then
		templateCache[weaponKey] = existing
		return existing
	end

	if not warnedMissingTemplate[weaponKey] then
		warnedMissingTemplate[weaponKey] = true
		warn(("[WeaponToolService] No Tool template (with a Handle) found for %s in ReplicatedStorage.WeaponTools — using a placeholder box. Build a real Tool there named exactly %q once you have a gun model."):format(weaponKey, weaponKey))
	end
	return buildPlaceholderTool(weaponKey, CraftingRecipes.Weapons[weaponKey])
end

-- The hold pose (WeaponPoseConfig) — a looping arm-only animation played while a gun is out, so the
-- player visibly holds it instead of running with empty hands. Layered rather than replacing
-- anything: Action priority beats the default walk/run on the joints the pose actually keyframes
-- (the arms) and leaves every other joint to Roblox's own animations, which is why one static pose
-- covers walking, running, jumping and falling without a clip for each.
--
-- Priority is forced HERE rather than trusted from the uploaded asset. An animation published at
-- the wrong priority fails in one of two silent ways — ignored under the walk, or stopping the legs
-- outright — and which one is invisible from Studio after upload.
local POSE_FADE = 0.15 -- seconds, both directions; a hard cut to a pose reads as a snap

local animationCache: { [string]: Animation } = {}
local activePose: { [number]: AnimationTrack } = {} -- userId -> the pose track currently playing

-- userId -> animationId -> a track already loaded onto THIS character's Animator.
--
-- Why tracks are cached and loaded EARLY: loading a track is what actually fetches the animation
-- data, and doing it at Equipped time meant the first equip of a session played Roblox's default
-- hold for a beat before the real pose appeared. So the track is loaded when the gun Tool is
-- built (SyncEquippedTool) — which also covers every respawn, since the gun is rebuilt from the
-- profile then — and Equipped only has to :Play() something already resident. The join-time
-- preload in LoadingScreen covers the download; this covers the per-character load on top of it.
--
-- Keyed per character, NOT per player: a track belongs to the Animator it was loaded on, and that
-- Animator dies with the character, so this is cleared on CharacterAdded rather than reused.
local poseTracks: { [number]: { [string]: AnimationTrack } } = {}

local function animationFor(animationId: string): Animation
	local animation = animationCache[animationId]
	if not animation then
		animation = Instance.new("Animation")
		animation.AnimationId = animationId
		animationCache[animationId] = animation
	end
	return animation
end

-- Loads (and caches) the pose track for weaponKey on the player's current character, without
-- playing it. Returns nil when there is no pose for this weapon, or no character to load onto yet.
local function loadPoseTrack(player: Player, weaponKey: string): AnimationTrack?
	local animationId = WeaponPoseConfig.Get(weaponKey)
	if not animationId then
		return nil -- no pose made for this weapon yet; default arms, as before this existed
	end

	local forPlayer = poseTracks[player.UserId]
	if forPlayer and forPlayer[animationId] then
		return forPlayer[animationId]
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end

	local ok, track = pcall(function()
		return animator:LoadAnimation(animationFor(animationId))
	end)
	if not ok or not track then
		warn(("[WeaponToolService] Could not load the hold pose for %s (%s) — check the animation exists and is owned by whoever owns this place."):format(weaponKey, animationId))
		return nil
	end

	-- Priority and Looped are set once, here, rather than at every play.
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true

	forPlayer = forPlayer or {}
	forPlayer[animationId] = track
	poseTracks[player.UserId] = forPlayer
	return track
end

local function stopPose(player: Player)
	local track = activePose[player.UserId]
	activePose[player.UserId] = nil
	if track then
		-- The track outlives its Animator on respawn; stopping a dead one throws rather than no-ops.
		pcall(function()
			track:Stop(POSE_FADE)
		end)
	end
end

local function playPose(player: Player, weaponKey: string)
	stopPose(player)

	-- Almost always a cache hit by the time this runs — see loadPoseTrack's comment. It still
	-- loads on demand as a fallback, for the case where the character wasn't ready when the gun
	-- was built.
	local track = loadPoseTrack(player, weaponKey)
	if not track then
		return
	end

	track:Play(POSE_FADE)
	activePose[player.UserId] = track
end

local function isWeaponTool(instance: Instance): boolean
	return instance:IsA("Tool") and instance:GetAttribute("WeaponTool") == true
end

-- Clears any existing gun Tool out of both Backpack (not currently held) and Character (currently
-- held) — a player mid-fight holding their old gun when they re-equip a new one from the Inventory
-- shouldn't end up holding both.
-- Clearing a weapon has to drop its wield penalty too. Unequipped does NOT fire when a held
-- Tool is destroyed out from under the character, so without this, swapping away from the
-- Longshot Rifle would leave the player permanently slow with nothing on screen to explain it.
local function clearExistingWeaponTools(player: Player)
	for _, container in ipairs({ player:FindFirstChild("Backpack"), player.Character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if isWeaponTool(child) then
					child:Destroy()
				end
			end
		end
	end
	PlayerSpeed.Set(player, "Wield", nil)
	stopPose(player) -- Unequipped never fires for a held Tool that is destroyed; see above
end

function WeaponToolService.SyncEquippedTool(player: Player, weaponInstance)
	clearExistingWeaponTools(player)

	if not weaponInstance then
		return
	end

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		-- No Backpack yet (character not fully loaded). Not an error — the CharacterAdded resync
		-- below covers this the moment the character (and its Backpack) actually exists.
		return
	end

	local recipe = CraftingRecipes.Weapons[weaponInstance.WeaponKey]
	local template = getTemplate(weaponInstance.WeaponKey)
	local tool = template:Clone()
	tool.Name = (recipe and recipe.DisplayName) or weaponInstance.WeaponKey
	tool:SetAttribute("WeaponTool", true)
	tool:SetAttribute("WeaponKey", weaponInstance.WeaponKey)
	tool:SetAttribute("WeaponInstanceId", weaponInstance.Id)

	-- Wield penalty: heavy weapons slow you while HELD, not merely owned — so the Longshot Rifle's
	-- drawback is something you can put away rather than a tax on carrying it around. Equipped and
	-- Unequipped are the Tool's own events, which means this covers dropping it, dying with it, and
	-- switching to another slot without any of those being handled separately.
	--
	-- Keyed "Wield" in PlayerSpeed so it composes with a Speed Boost instead of the two overwriting
	-- each other, and clearing it restores whatever else is still running.
	local wieldMultiplier = recipe and recipe.WieldSpeedMultiplier
	if wieldMultiplier then
		tool.Equipped:Connect(function()
			PlayerSpeed.Set(player, "Wield", wieldMultiplier)
		end)
		tool.Unequipped:Connect(function()
			PlayerSpeed.Set(player, "Wield", nil)
		end)
	end

	-- Same pair of events as the wield penalty above, and for the same reason: Equipped/Unequipped
	-- already cover dropping the gun, dying with it and switching slots. The one case they DON'T
	-- cover is the tool being destroyed while held — clearExistingWeaponTools handles that, exactly
	-- as it already has to for the wield penalty.
	tool.Equipped:Connect(function()
		playPose(player, weaponInstance.WeaponKey)
	end)
	tool.Unequipped:Connect(function()
		stopPose(player)
	end)

	-- Load the pose onto this character NOW, while the gun is only sitting in the Backpack, so the
	-- first Equipped has nothing left to fetch. This is what stops the first equip of a session
	-- showing Roblox's default hold for a beat before snapping into the real pose.
	loadPoseTrack(player, weaponInstance.WeaponKey)

	tool.Parent = backpack
end

-- Re-sync on every spawn: Roblox doesn't reliably carry a held Tool through character death/respawn
-- (whatever's still parented to the old Character gets destroyed with it), and Backpack contents
-- aren't guaranteed to survive a full LoadCharacter reset either. Rather than depend on engine
-- behavior here, just rebuild the gun from profile.EquippedWeaponId — the actual source of truth —
-- every time a character loads in, same "state on the profile, not on the instance" spirit as
-- everything else in this codebase.
-- Same defensive polling every other consumer of a freshly-loaded profile uses (BaseService,
-- TurretService). Without it, the FIRST CharacterAdded after joining routinely fired before
-- DataService's asynchronous load finished, this returned early, and the player spawned with no
-- gun until they happened to respawn — with nothing to explain it.
local function waitForProfile(player: Player)
	local profile = DataService.Get(player)
	local attempts = 0
	while not profile and attempts < 50 and player.Parent do
		task.wait(0.1)
		profile = DataService.Get(player)
		attempts += 1
	end
	return profile
end

Players.PlayerRemoving:Connect(function(player: Player)
	activePose[player.UserId] = nil -- no profile data here, so PlayerRemoving is fine
	poseTracks[player.UserId] = nil
end)

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function()
		-- Tracks belong to the old character's Animator, which has just been replaced. Dropping them
		-- here means SyncEquippedTool below loads fresh ones onto the new Animator.
		poseTracks[player.UserId] = nil
		activePose[player.UserId] = nil

		local profile = waitForProfile(player)
		if not profile or not profile.EquippedWeaponId then
			return
		end
		for _, weaponInstance in ipairs(profile.Weapons) do
			if weaponInstance.Id == profile.EquippedWeaponId then
				WeaponToolService.SyncEquippedTool(player, weaponInstance)
				break
			end
		end
	end)
end)

return WeaponToolService
