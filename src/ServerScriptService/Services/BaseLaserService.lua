--[[
	BaseLaserService.lua
	Security lasers on Tier 4+ bases. A base template that contains a "Laser" and a "Button" (names in
	BaseConfig.Lasers) gets a ProximityPrompt on the Button that only the base's owner can use:

	  ON  — lasers visible; any player other than the owner, and any enemy, who touches one dies.
	  OFF — lasers invisible and harmless (and non-collidable, so there is no invisible wall).

	Wired up from BaseService.BaseBuilt rather than a Script inside the template: the template lives only
	in Studio (not synced from src/), and a copied Script would not know whose base it sits in. Re-runs on
	every rebuild, so a tier upgrade keeps the current state. The on/off state is saved on the profile
	(BaseLasersOn), so it survives a rejoin; a fresh profile starts off.

	Enemies are recognised by the "Enemy" tag CombatEncounterService puts on every spawn, so robots
	(untagged, and not players) walk through. The prompt is hidden for everyone but the
	owner by BaseLaserClient.client.lua; the owner check here is the real gate.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseConfig = require(ReplicatedStorage.Shared.BaseConfig)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local RateLimiter = require(script.Parent.RateLimiter)
-- The server's own copy of a player's HP, so a laser kill lands on the number the server decides
-- fights by. See PlayerVitals.lua's header (2026-09-23 exploit review, F3).
local PlayerVitals = require(script.Parent.PlayerVitals)

local CONFIG = BaseConfig.Lasers
local PROMPT_TAG = "BaseLaserPrompt" -- read by BaseLaserClient to hide the prompt from non-owners

local BaseLaserService = {}

local lasersOn: { [number]: boolean } = {} -- owner UserId -> on
local laserParts: { [number]: { BasePart } } = {} -- owner UserId -> laser parts in their current base
local laserFx: { [number]: { Instance } } = {} -- owner UserId -> decals/beams/lights drawing those lasers
local prompts: { [number]: { ProximityPrompt } } = {}

-- Prefix match, so names work however they are numbered: "Laser", "Laser1", a "Lasers" folder holding
-- them all; "Button", "ButtonT4", "ButtonT5".
local function nameStartsWith(inst: Instance, prefix: string): boolean
	return string.sub(string.lower(inst.Name), 1, #prefix) == string.lower(prefix)
end

-- Every BasePart that is, or sits inside, something whose name starts with LaserName. Deduped, since a
-- "Lasers" folder may itself contain parts also named Laser.
local function collectLaserParts(baseModel: Model): { BasePart }
	local seen, parts = {}, {}
	local function add(part: BasePart)
		if not seen[part] then
			seen[part] = true
			table.insert(parts, part)
		end
	end
	for _, inst in ipairs(baseModel:GetDescendants()) do
		if nameStartsWith(inst, CONFIG.LaserName) then
			if inst:IsA("BasePart") then
				add(inst)
			end
			for _, child in ipairs(inst:GetDescendants()) do
				if child:IsA("BasePart") then
					add(child)
				end
			end
		end
	end
	return parts
end

-- A ProximityPrompt must sit under a BasePart or Attachment, so a Button Model uses its PrimaryPart or
-- first BasePart.
local function promptParentFor(button: Instance): Instance?
	if button:IsA("BasePart") or button:IsA("Attachment") then
		return button
	end
	if button:IsA("Model") and button.PrimaryPart then
		return button.PrimaryPart
	end
	return button:FindFirstChildWhichIsA("BasePart", true)
end

-- Everything else that draws a laser besides the Part itself: a Decal/Texture on it still shows on a
-- fully transparent Part, and a Beam can hang off a laser's Attachment while living somewhere else in
-- the base entirely. Collected once per build, since the Beam search walks the whole base.
local function collectLaserFx(baseModel: Model, parts: { BasePart }): { Instance }
	local isLaserPart, fx = {}, {}
	for _, part in ipairs(parts) do
		isLaserPart[part] = true
		for _, inst in ipairs(part:GetDescendants()) do
			if not inst:IsA("Beam") then -- Beams are all picked up by the pass below
				table.insert(fx, inst)
			end
		end
	end
	for _, inst in ipairs(baseModel:GetDescendants()) do
		if inst:IsA("Beam") then
			local a0, a1 = inst.Attachment0, inst.Attachment1
			if isLaserPart[inst.Parent] or (a0 and isLaserPart[a0.Parent]) or (a1 and isLaserPart[a1.Parent]) then
				table.insert(fx, inst)
			end
		end
	end
	return fx
end

-- The as-built look is remembered the first time, so ON restores exactly what was authored.
local function setShown(inst: Instance, on: boolean)
	if inst:IsA("BasePart") or inst:IsA("Decal") then -- Decal covers Texture
		if inst:GetAttribute("LaserOnTransparency") == nil then
			inst:SetAttribute("LaserOnTransparency", inst.Transparency)
		end
		inst.Transparency = on and inst:GetAttribute("LaserOnTransparency") or 1
	elseif inst:IsA("Beam") or inst:IsA("ParticleEmitter") or inst:IsA("Light") or inst:IsA("Trail")
		or inst:IsA("Highlight") or inst:IsA("SurfaceGui") or inst:IsA("BillboardGui") then
		inst.Enabled = on
	elseif inst:IsA("SelectionBox") then
		inst.Visible = on
	end
end

local function applyState(userId: number)
	local on = lasersOn[userId] == true
	for _, part in ipairs(laserParts[userId] or {}) do
		if part:GetAttribute("LaserOnCanCollide") == nil then
			part:SetAttribute("LaserOnCanCollide", part.CanCollide)
		end
		part.CanCollide = on and part:GetAttribute("LaserOnCanCollide") or false
		setShown(part, on)
	end
	for _, inst in ipairs(laserFx[userId] or {}) do
		setShown(inst, on)
	end
	for _, prompt in ipairs(prompts[userId] or {}) do
		prompt.ActionText = on and CONFIG.DeactivateText or CONFIG.ActivateText
	end
end

local function onLaserTouched(ownerUserId: number, hit: BasePart)
	if not lasersOn[ownerUserId] then
		return
	end
	-- Walk up to the tagged enemy Model: the part touched can sit inside a nested rig Model.
	local enemy = hit:FindFirstAncestorOfClass("Model")
	while enemy and not CollectionService:HasTag(enemy, "Enemy") do
		enemy = enemy:FindFirstAncestorOfClass("Model")
	end
	local character = enemy or hit:FindFirstAncestorOfClass("Model")
	local victimPlayer = nil
	if not enemy then
		victimPlayer = character and Players:GetPlayerFromCharacter(character)
		if not victimPlayer or victimPlayer.UserId == ownerUserId then
			return
		end
	end
	-- Killed outright rather than damaged: the encounter loop polls health, so a laser kill counts
	-- exactly like a gun kill. A PLAYER victim goes through PlayerVitals so the kill lands on the
	-- server's own copy of their HP — a laser that only zeroed the Humanoid would be survivable by
	-- a client that writes its own Health, and would leave the server still calling them alive.
	-- An ENEMY has no PlayerVitals record and never should, so that path stays on the Humanoid.
	if victimPlayer then
		PlayerVitals.Kill(victimPlayer)
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

local function wireBase(player: Player, baseModel: Model)
	local userId = player.UserId
	if lasersOn[userId] == nil then -- first build this session: restore the saved switch
		local profile = DataService.Get(player)
		lasersOn[userId] = profile ~= nil and profile.BaseLasersOn == true
	end
	-- The previous base's parts and prompts were destroyed with it, taking their connections along.
	laserParts[userId] = collectLaserParts(baseModel)
	laserFx[userId] = collectLaserFx(baseModel, laserParts[userId])
	prompts[userId] = {}

	local buttons = {}
	for _, inst in ipairs(baseModel:GetDescendants()) do
		if nameStartsWith(inst, CONFIG.ButtonName) then
			-- Skip a "Button..." part inside a "Button..." model, or the one button would get two prompts.
			local parent, nested = inst.Parent, false
			while parent and parent ~= baseModel do
				if nameStartsWith(parent, CONFIG.ButtonName) then
					nested = true
					break
				end
				parent = parent.Parent
			end
			if not nested then
				table.insert(buttons, inst)
			end
		end
	end

	if #laserParts[userId] == 0 and #buttons == 0 then
		return -- Tier 1-3, or a fallback floor: no lasers here
	end
	if #laserParts[userId] == 0 or #buttons == 0 then
		warn(("[BaseLaserService] %s has a %s but no %s — lasers will not work on this base. Check the names inside ReplicatedStorage.BaseTemplates."):format(
			baseModel.Name,
			#buttons > 0 and CONFIG.ButtonName or CONFIG.LaserName,
			#buttons > 0 and CONFIG.LaserName or CONFIG.ButtonName))
	end

	for _, part in ipairs(laserParts[userId]) do
		part.Touched:Connect(function(hit)
			onLaserTouched(userId, hit)
		end)
	end

	for _, button in ipairs(buttons) do
		local parent = promptParentFor(button)
		if not parent then
			warn(("[BaseLaserService] %s in %s has no BasePart to hold a prompt — make it a Part, or a Model with a Part inside."):format(button:GetFullName(), baseModel.Name))
			continue
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "LaserPrompt"
		prompt.ObjectText = "Base Lasers"
		prompt.HoldDuration = CONFIG.PromptHoldDuration
		prompt.MaxActivationDistance = CONFIG.PromptMaxDistance
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("OwnerUserId", userId)
		CollectionService:AddTag(prompt, PROMPT_TAG)
		prompt.Triggered:Connect(function(triggeringPlayer)
			if triggeringPlayer.UserId ~= userId then
				warn(("[BaseLaserService] %s tried to toggle %s's lasers — rejected."):format(triggeringPlayer.Name, player.Name))
				return
			end
			if not RateLimiter.Check(triggeringPlayer, "BaseLaserToggle", CONFIG.ToggleCooldown) then
				return
			end
			lasersOn[userId] = not lasersOn[userId]
			local profile = DataService.Get(player)
			if profile then
				profile.BaseLasersOn = lasersOn[userId] -- saved with the rest of the profile on autosave/leave
			end
			applyState(userId)
		end)
		prompt.Parent = parent
		table.insert(prompts[userId], prompt)
	end

	applyState(userId)
end

function BaseLaserService.AreLasersOn(player: Player): boolean
	return lasersOn[player.UserId] == true
end

BaseService.BaseBuilt:Connect(wireBase)

-- The saved switch is written to the profile at toggle time, so this only clears session tables and
-- PlayerRemoving (not DataService.PlayerSaving) is still fine.
Players.PlayerRemoving:Connect(function(player)
	lasersOn[player.UserId] = nil
	laserParts[player.UserId] = nil
	laserFx[player.UserId] = nil
	prompts[player.UserId] = nil
end)

return BaseLaserService
