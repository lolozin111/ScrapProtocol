--[[
	BaseLaserClient.client.lua
	Hides every base-laser ProximityPrompt that isn't on this player's own base, so visitors never see
	an "Activate Lasers" prompt they can't use. Purely cosmetic: Enabled is set locally only, and
	BaseLaserService rejects a non-owner trigger regardless.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local PROMPT_TAG = "BaseLaserPrompt" -- matches BaseLaserService

local localPlayer = Players.LocalPlayer

local function onPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") and prompt:GetAttribute("OwnerUserId") ~= localPlayer.UserId then
		prompt.Enabled = false
	end
end

for _, prompt in ipairs(CollectionService:GetTagged(PROMPT_TAG)) do
	onPrompt(prompt)
end
CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(onPrompt)
