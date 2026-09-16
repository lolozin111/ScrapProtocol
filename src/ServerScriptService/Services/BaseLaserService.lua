--[[
	BaseLaserService.lua
	Security lasers on Tier 4+ bases. A base template that contains a "Laser" and a "Button" (names in
	BaseConfig.Lasers) gets a ProximityPrompt on the Button that only the base's owner can use:

	  ON  — lasers visible; any player other than the owner who touches one dies.
	  OFF — lasers invisible and harmless (and non-collidable, so there is no invisible wall).

	Wired up from BaseService.BaseBuilt rather than a Script inside the template: the template lives only
	in Studio (not synced from src/), and a copied Script would not know whose base it sits in. Re-runs on
	every rebuild, so a tier upgrade keeps the current state. State is per session, off by default.

	Only players are killed — enemies and robots walk through. The prompt is hidden for everyone but the
	owner by BaseLaserClient.client.lua; the owner check here is the real gate.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseConfig = require(ReplicatedStorage.Shared.BaseConfig)
local BaseService = require(script.Parent.BaseService)
local RateLimiter = require(script.Parent.RateLimiter)

local CONFIG = BaseConfig.Lasers
local PROMPT_TAG = "BaseLaserPrompt" -- read by BaseLaserClient to hide the prompt from non-owners

local BaseLaserService = {}

local lasersOn: { [number]: boolean } = {} -- owner UserId -> on
local laserParts: { [number]: { BasePart } } = {} -- owner UserId -> laser parts in their current base
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

local function applyState(userId: number)
	local on = lasersOn[userId] == true
	for _, part in ipairs(laserParts[userId] or {}) do
		-- The as-built look is remembered on first touch, so ON restores exactly what was authored.
		if part:GetAttribute("LaserOnTransparency") == nil then
			part:SetAttribute("LaserOnTransparency", part.Transparency)
			part:SetAttribute("LaserOnCanCollide", part.CanCollide)
		end
		part.Transparency = on and part:GetAttribute("LaserOnTransparency") or 1
		part.CanCollide = on and part:GetAttribute("LaserOnCanCollide") or false
		for _, fx in ipairs(part:GetDescendants()) do
			if fx:IsA("Beam") or fx:IsA("ParticleEmitter") or fx:IsA("Light") or fx:IsA("Trail") then
				fx.Enabled = on
			end
		end
	end
	for _, prompt in ipairs(prompts[userId] or {}) do
		prompt.ActionText = on and CONFIG.DeactivateText or CONFIG.ActivateText
	end
end

local function onLaserTouched(ownerUserId: number, hit: BasePart)
	if not lasersOn[ownerUserId] then
		return
	end
	local character = hit:FindFirstAncestorOfClass("Model")
	local victim = character and Players:GetPlayerFromCharacter(character)
	if not victim or victim.UserId == ownerUserId then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

local function wireBase(player: Player, baseModel: Model)
	local userId = player.UserId
	-- The previous base's parts and prompts were destroyed with it, taking their connections along.
	laserParts[userId] = collectLaserParts(baseModel)
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

-- No profile data involved, so PlayerRemoving (not DataService.PlayerSaving) is fine here.
Players.PlayerRemoving:Connect(function(player)
	lasersOn[player.UserId] = nil
	laserParts[player.UserId] = nil
	prompts[player.UserId] = nil
end)

return BaseLaserService
