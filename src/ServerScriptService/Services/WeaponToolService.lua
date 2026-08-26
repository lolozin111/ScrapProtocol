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

local function isWeaponTool(instance: Instance): boolean
	return instance:IsA("Tool") and instance:GetAttribute("WeaponTool") == true
end

-- Clears any existing gun Tool out of both Backpack (not currently held) and Character (currently
-- held) — a player mid-fight holding their old gun when they re-equip a new one from the Inventory
-- shouldn't end up holding both.
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

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function()
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
