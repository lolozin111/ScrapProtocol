--[[
	CombatClient.client.lua
	Turns a mouse click into a shot during a base-defense wave. Stays "dumb" on purpose, same
	philosophy as MiningController.client.lua: this script's only real jobs are (1) figure out
	where the player is aiming via a camera raycast, (2) draw a quick tracer so a shot FEELS
	instant, and (3) tell the server what it claims it hit. Every real number — did it actually
	land, how much damage, was the target even alive — is recomputed from scratch server-side in
	CombatEncounterService.lua's RequestFireWeapon handler. This file could lie about all three
	arguments it sends and the worst it could do is waste a cooldown-gated no-op; it can never
	inject a damage number.

	SCOPE NOTE: "click to fire a hitscan raycast, with a shot report" was my own default design for
	"how does the player actually fire," not something explicitly specified — Salvage Protocol has
	no real projectile physics today, and a hitscan-plus-cosmetic-tracer is the standard lightweight
	Roblox pattern for this. Swap this file (only this file — the server-side pipeline doesn't care
	how a hit was determined) for real projectile travel later if that turns out to matter more than
	it does right now.

	Client-side fire-rate pacing here is a courtesy, not security — it's read straight off the
	currently-EQUIPPED gun Tool's own WeaponKey attribute (see WeaponToolService.lua) via
	CraftingRecipes.Weapons' BASE FireRate (mods/affixes aren't known client-side), just to keep the
	tracer/click rate feeling right. The server enforces the REAL mod-adjusted cooldown independently
	and silently drops anything that arrives faster than that, same as every other timing-sensitive
	remote in this game.

	Firing now requires an actual gun Tool held in the character's hand (WeaponToolService.lua
	clones one into the Backpack when you Equip a weapon from the Inventory panel; the player picks
	it up into their hand the normal Roblox hotbar way from there) — not just "you have some weapon
	equipped in your profile somewhere." No Tool in hand, clicking does nothing client-side.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)

local Remotes = ReplicatedStorage.Remotes
local RequestFireWeapon = Remotes.RequestFireWeapon
local WaveUpdate = Remotes.WaveUpdate
local RaidRoomUpdate = Remotes.RaidRoomUpdate

local LocalPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local MAX_RANGE = 300 -- generous; DamagePipeline's own RangeProfile is what actually punishes distance
local DEFAULT_FIRE_RATE = 2 -- used only if the equipped weapon can't be resolved for some reason

----------------------------------------------------------------------
-- Currently-held gun Tool — tracked via Character.ChildAdded/Removed rather than Tool.Equipped/
-- Unequipped on any one instance, since WeaponToolService.lua destroys and re-clones a fresh Tool
-- instance every time EquippedWeaponId changes; watching the character's own children stays
-- correct across that without needing to re-connect per-instance every time.
----------------------------------------------------------------------

local equippedTool: Tool? = nil

local function isWeaponTool(instance: Instance): boolean
	return instance:IsA("Tool") and instance:GetAttribute("WeaponTool") == true
end

local function onCharacterAdded(character: Model)
	equippedTool = nil
	for _, child in ipairs(character:GetChildren()) do
		if isWeaponTool(child) then
			equippedTool = child
		end
	end
	character.ChildAdded:Connect(function(child)
		if isWeaponTool(child) then
			equippedTool = child
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child == equippedTool then
			equippedTool = nil
		end
	end)
end

if LocalPlayer.Character then
	onCharacterAdded(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

local function getEquippedFireRate(): number
	local weaponKey = equippedTool and equippedTool:GetAttribute("WeaponKey")
	local recipe = weaponKey and CraftingRecipes.Weapons[weaponKey]
	return (recipe and recipe.FireRate) or DEFAULT_FIRE_RATE
end

----------------------------------------------------------------------
-- Combat-active gate — only lets clicks do anything while SOME fight is actually running (base
-- defense OR a Raid Room Combat node), so idling around otherwise doesn't spam tracers or
-- RequestFireWeapon calls the server would just no-op anyway. Two separate remotes feed this
-- because they're two separate encounter flows (WaveService's base defense vs RaidRoomService's
-- instanced rooms — see CombatEncounterService.lua's RunWave/RunRaidCombat) that both ultimately
-- resolve into the same activeEncounters/RequestFireWeapon pipeline server-side; this file just
-- needs to know when EITHER one is live. Originally only listened to WaveUpdate, which meant
-- clicking during a Raid Room fight did nothing at all — RaidRoomUpdate never touched this flag.
----------------------------------------------------------------------

local combatActive = false

WaveUpdate.OnClientEvent:Connect(function(update)
	if update.Status == "WaveStart" then
		combatActive = true
	elseif update.Status == "RunEnded" or update.Status == "Interrupted" then
		combatActive = false
	end
end)

RaidRoomUpdate.OnClientEvent:Connect(function(update)
	-- Ambush nodes (RaidRoomService.beginAmbush) run the same RunRaidCombat engine per wave, just
	-- relabeled "AmbushStart"/"AmbushEnd" instead of "CombatStart"/"CombatEnd" — see that function's
	-- own comment. Toggling per wave (true during each wave, false during the short breather between
	-- them) is correct here, same as it already is for a single Combat encounter.
	if update.Status == "CombatStart" or update.Status == "AmbushStart" then
		combatActive = true
	elseif update.Status == "CombatEnd" or update.Status == "AmbushEnd" then
		combatActive = false
	end
end)

----------------------------------------------------------------------
-- Tracer — purely cosmetic, purely local. A thin fading beam from the player toward the hit point,
-- just enough for a shot to read as "something happened" the instant you click, well before any
-- server round-trip could confirm it landed.
----------------------------------------------------------------------

local function drawTracer(origin: Vector3, hitPosition: Vector3)
	local distance = (hitPosition - origin).Magnitude
	if distance <= 0 then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 214, 130)
	part.Size = Vector3.new(0.1, 0.1, distance)
	part.CFrame = CFrame.lookAt(origin, hitPosition) * CFrame.new(0, 0, -distance / 2)
	part.Parent = Workspace
	Debris:AddItem(part, 0.08)
end

----------------------------------------------------------------------
-- Firing
----------------------------------------------------------------------

local lastFireTime = 0

local function fireOnce()
	if not equippedTool then
		return -- nothing held in hand — see this file's header on why that's required now
	end

	local character = LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	local cooldown = 1 / math.max(getEquippedFireRate(), 0.01)
	local now = os.clock()
	if now - lastFireTime < cooldown then
		return
	end
	lastFireTime = now

	local mousePosition = UserInputService:GetMouseLocation()
	local unitRay = camera:ViewportPointToRay(mousePosition.X, mousePosition.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * MAX_RANGE, params)
	if not result then
		return
	end

	-- Cheap client-side prefilter so a miss against scenery/terrain doesn't bother the server at
	-- all — RequestFireWeapon would reject it anyway (only real spawned enemies are in
	-- encounter.EnemyByModel), this just skips the round-trip for the common "clicked the floor" case.
	local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
	if not hitModel or not hitModel:FindFirstChildOfClass("Humanoid") then
		return
	end

	local origin = rootPart.Position
	drawTracer(origin, result.Position)
	RequestFireWeapon:FireServer(result.Instance, origin, result.Position)
end

----------------------------------------------------------------------
-- Input — hold-to-fire, same feel as clicking through the mining ProximityPrompt but faster since
-- combat needs an actual rate of fire instead of a hold-duration gate.
----------------------------------------------------------------------

local holding = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not combatActive then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = false
	end
end)

game:GetService("RunService").Heartbeat:Connect(function()
	if holding and combatActive then
		fireOnce()
	end
end)
