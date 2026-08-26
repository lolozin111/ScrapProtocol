--[[
	CombatClient.client.lua
	Turns a mouse hold into a fire request. Stays "dumb" on purpose, same philosophy as
	MiningController.client.lua: this script decides only WHERE the player is aiming and WHEN they
	want to shoot. It never decides what was hit, and it never decides damage.

	Guns fire real travelling projectiles now, spawned and simulated server-side — see
	ProjectileService.lua. So this file no longer raycasts for a target, no longer draws its own
	tracer (the projectile is a real replicated Part everyone can see), and no longer reports a hit
	instance. It sends an origin and a direction; everything after that is the server's.

	TWO GATES WERE REMOVED HERE, both of which read as bugs:
	  - Firing required an active encounter, so shooting a training dummy — or anything at all
	    outside a wave — silently did nothing.
	  - Firing required the crosshair to already be over something with a Humanoid, so aiming at
	    the floor produced no shot whatsoever.
	Both are gone. You can always shoot; hitting something is the projectile's problem.

	What remains is a client-side fire-rate pace, purely so the visual rhythm feels right. It is
	read from the equipped Tool's WeaponKey attribute and uses the BASE FireRate (mods and affixes
	are not known client-side). The server enforces the real, mod-adjusted rate independently and
	silently drops anything arriving faster.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CraftingRecipes = require(ReplicatedStorage.Shared.CraftingRecipes)

local Remotes = ReplicatedStorage.Remotes
local RequestFireWeapon = Remotes.RequestFireWeapon

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
-- Firing is gated on HOLDING A GUN, and nothing else.
--
-- It used to also require an active encounter (a wave or a raid room), tracked by listening to
-- WaveUpdate and RaidRoomUpdate. That is why shooting a training dummy did nothing at all: the
-- server was perfectly willing, but the client never sent the request. It also meant a gun was
-- inert everywhere in the world except inside a fight, which is not how a gun should feel.
--
-- Nothing is lost by dropping it. The server still validates every shot (see RequestFireWeapon),
-- and a bullet fired at nothing simply flies off and expires.
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Firing
----------------------------------------------------------------------

local lastFireTime = 0

local function fireOnce()
	if not equippedTool then
		return -- nothing held in hand — see this file's header on why that's required
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

	-- Raycast ONLY to work out what the player is aiming AT, so the shot converges on the
	-- crosshair instead of running parallel to the camera. Nothing is decided by this: it is not a
	-- hit test, and a miss is not a reason to withhold the shot.
	--
	-- This used to double as a filter that dropped the shot entirely unless the crosshair was
	-- already on something with a Humanoid — which meant aiming at the floor, a wall, or a training
	-- dummy produced no tracer, no sound and no bullet. The gun read as broken. Shots now always
	-- fire; whether they hit anything is the projectile's business, server-side.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, workspace:FindFirstChild("Projectiles") }

	local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * MAX_RANGE, params)
	local aimPoint = result and result.Position or (unitRay.Origin + unitRay.Direction * MAX_RANGE)

	-- Fired from the character, not the camera, so the projectile visibly leaves the player rather
	-- than the viewport — but aimed at where the camera was pointing, so it still lands under the
	-- crosshair.
	local origin = rootPart.Position + Vector3.new(0, 1.5, 0)
	local direction = (aimPoint - origin)
	if direction.Magnitude < 0.001 then
		return
	end

	RequestFireWeapon:FireServer(origin, direction.Unit)
end

----------------------------------------------------------------------
-- Input — hold-to-fire, since combat needs a real rate of fire rather than a hold-duration gate.
----------------------------------------------------------------------

local holding = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
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
	if holding then
		fireOnce()
	end
end)
