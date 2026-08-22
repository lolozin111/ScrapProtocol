--[[
	StationService.lua
	Second layer of the base-area gate, on top of PlotService's "are you at your own base at
	all": several Workbench actions also require standing near the SPECIFIC physical station that
	does that job — a Workbench for Tools/Auto-Miner/Suit upgrades, a Welding Station for Weapons/
	Robots/Mods. Tag a Part or Model "Station" (StationConfig.Tag) in Studio and give it a child
	StringValue named "StationType" set to a key in StationConfig.Types (e.g. "Welding") — no code
	changes needed to add more of any type, or move one.

	Deliberately doesn't care WHICH plot a station belongs to or WHOSE it is — every caller here
	already checks PlotService.IsPlayerInOwnPlot first (this is only ever the SECOND check, never
	a replacement for it), so in practice a station only ever gets reached while a player is
	already standing in their own base. This service only has to answer "is a station of the
	right TYPE nearby" — same shape as MiningService's own distance check, just against tagged
	instances instead of a single node.
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

local function getStationPosition(inst: Instance): Vector3?
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		if inst.PrimaryPart then
			return inst.PrimaryPart.Position
		end
		local ok, cframe = pcall(function()
			return inst:GetPivot()
		end)
		if ok then
			return cframe.Position
		end
	end
	return nil
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
			local position = getStationPosition(inst)
			if position and (position - rootPart.Position).Magnitude <= StationConfig.InteractDistance then
				return true
			end
		end
	end

	return false
end

return StationService
