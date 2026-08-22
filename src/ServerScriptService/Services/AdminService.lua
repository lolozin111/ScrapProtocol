--[[
	AdminService.lua
	Chat command so whoever AdminConfig.IsAdmin() already applies to can flip their own dev
	shortcuts off for a bit — useful for testing what a normal player actually experiences
	(Energy costs, real timed combat) without editing code every time. Session-only: resets to
	the normal auto-detected value on rejoin or server restart.

	Type in the in-game chat:
	  /admin off  — disable admin shortcuts for yourself, this session
	  /admin on   — re-enable them
	  /admin      — toggle

	Silently ignored for anyone who isn't already an admin (see AdminConfig.SetOverride) — this
	can't be used to grant admin to a random player.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminConfig = require(ReplicatedStorage.Shared.AdminConfig)

local AdminService = {}

local function handleChatted(player: Player, message: string)
	local lower = message:lower()
	if lower ~= "/admin" and lower ~= "/admin on" and lower ~= "/admin off" then
		return
	end

	if lower == "/admin off" then
		AdminConfig.SetOverride(player, false)
	elseif lower == "/admin on" then
		AdminConfig.SetOverride(player, true)
	else
		AdminConfig.SetOverride(player, not AdminConfig.IsAdmin(player))
	end

	print(("[AdminService] Admin shortcuts are now %s for %s (this session only)."):format(
		AdminConfig.IsAdmin(player) and "ON" or "OFF", player.Name))
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		handleChatted(player, message)
	end)
end)

return AdminService
