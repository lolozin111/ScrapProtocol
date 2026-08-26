--[[
	StationService.lua
	Second layer of the base-area gate, on top of PlotService's "are you at your own base at
	all": several Workbench actions also require standing near the SPECIFIC physical station that
	does that job — a Workbench for Tools/Auto-Miner/Suit upgrades, a Welding Station for Weapons/
	Robots/Mods. Tag a Part or Model "Station" (StationConfig.Tag) in Studio and give it a child
	StringValue named "StationType" set to a key in StationConfig.Types (e.g. "Welding") — no code
	changes needed to add more of any type, or move one.

	Every caller here already checks PlotService.IsPlayerInOwnPlot first (this is only ever the
	SECOND check, never a replacement for it), so in practice a station only ever gets reached
	while a player is already standing in their own base. This service answers "is a station of
	the right TYPE nearby, AND is it actually mine" — same shape as MiningService's own distance
	check, just against tagged instances instead of a single node.

	Ownership: BaseService stamps every Station-tagged descendant of a player's cloned base Model
	with an OwnerUserId attribute matching that player. A station with NO OwnerUserId attribute
	(a loose block placed straight in the world, not part of any base Model — e.g. current
	placeholder testing before real base art exists) is left open to everyone; once it's part of
	a real per-player base, the owner check kicks in automatically with no extra setup.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StationConfig = require(ReplicatedStorage.Shared.StationConfig)

local StationService = {}

local function getStationType(inst: Instance): string?
	local marker = inst:FindFirstChild("StationType")
	if marker and marker:IsA("StringValue") then
		return marker.Value
	end
	return nil
end

-- Distance from `position` to the station's nearest SURFACE, not its centre.
--
-- This used to measure centre-to-centre (inst.Position, or a Model's PrimaryPart/pivot), which
-- silently punished big stations: StationConfig.InteractDistance is 12 studs, so a shop built as a
-- 30-stud-wide model put its own centre ~15 studs from where you stand at the counter, and every
-- interaction was rejected with "You need to be at the Hub Shop to do that" while you were plainly
-- standing at it. Worse, it was inconsistent — walking to the side the pivot happened to sit on
-- worked fine, so it looked like only SOME purchases failed.
--
-- Measuring to the bounding box means InteractDistance reads as "12 studs from the thing," which
-- is what it always claimed to mean, and a station can be any size without retuning anything.
local function distanceToStation(inst: Instance, position: Vector3): number?
	local reference: CFrame, size: Vector3

	if inst:IsA("BasePart") then
		reference, size = inst.CFrame, inst.Size
	elseif inst:IsA("Model") then
		local ok, cframe, boxSize = pcall(function()
			return inst:GetBoundingBox()
		end)
		if not ok or not cframe then
			return nil
		end
		reference, size = cframe, boxSize
	else
		return nil
	end

	-- Point-to-box distance in the station's OWN space, so a rotated station is measured correctly
	-- rather than against a world-axis-aligned approximation of itself. Clamping each axis to the
	-- box's half-extent and taking the magnitude of whatever's left over gives 0 for a point inside
	-- the box (standing on/in the station counts as distance 0, which is right).
	local localPoint = reference:PointToObjectSpace(position)
	local half = size / 2
	local overshoot = Vector3.new(
		math.max(math.abs(localPoint.X) - half.X, 0),
		math.max(math.abs(localPoint.Y) - half.Y, 0),
		math.max(math.abs(localPoint.Z) - half.Z, 0)
	)
	return overshoot.Magnitude
end

-- True if `player` is within StationConfig.InteractDistance of ANY Station-tagged instance whose
-- StationType matches `stationType`.
function StationService.IsPlayerNearStation(player: Player, stationType: string): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false
	end

	for _, inst in ipairs(CollectionService:GetTagged(StationConfig.Tag)) do
		if getStationType(inst) == stationType then
			-- nil OwnerUserId = not part of any player's base yet (loose testing block) = open to all.
			local ownerUserId = inst:GetAttribute("OwnerUserId")
			if ownerUserId == nil or ownerUserId == player.UserId then
				local distance = distanceToStation(inst, rootPart.Position)
				if distance and distance <= StationConfig.InteractDistance then
					return true
				end
			end
		end
	end

	return false
end

return StationService
