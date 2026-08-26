--[[
	ProjectileService.lua
	Real travelling bullets, server-authoritative.

	REPLACES HITSCAN. Every shot used to resolve instantly: the client raycast, told the server what
	it hit, and damage landed the same frame. That had two consequences worth naming, because both
	were reported as bugs rather than recognised as the design:

	  - Firing was gated on ALREADY aiming at something with a Humanoid. Aim at the floor and the
	    client silently dropped the shot — no tracer, no sound, nothing. The gun felt dead.
	  - There was no projectile to see, so "did I hit that" was pure inference.

	Now the server spawns a real Part, steps it, and resolves the hit on impact. Because the server
	owns it, everyone sees the same bullet, and the shot and the hit are two separate moments — which
	is exactly what arcing arrows, bouncing grenades and piercing rounds need. Fire patterns beyond
	a straight line are additions to THIS file, not a second system.

	=== TRUST MODEL (unchanged) ===
	The client still only reports intent: where it fired from and which way it was pointing. Origin
	is sanity-checked against the server's own view of the player, fire rate is enforced server-side,
	and damage is recomputed from server state. A spoofed client can aim wherever it likes; it cannot
	invent damage, and it cannot fire faster than its weapon allows.

	=== WHY SERVER-SIMULATED, NOT CLIENT-PREDICTED ===
	A client-predicted projectile would feel a round-trip snappier, at the cost of two simulations
	that can disagree, and of other players not seeing your shots. At the speeds below, travel time
	dominates the round trip anyway — a 220-stud/s bullet crossing a base takes far longer than the
	latency — so the simpler authoritative model costs almost nothing and keeps this file the only
	place a bullet exists.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ProjectileConfig = require(ReplicatedStorage.Shared.ProjectileConfig)

local ProjectileService = {}

-- Set by CombatEncounterService at load. A function rather than a require, because that file
-- already requires enough and this only ever needs the one entry point — see its own
-- ResolvePlayerHit.
local resolveHit: ((Player, Instance, Vector3, Vector3, any) -> boolean)? = nil

function ProjectileService.SetHitResolver(fn)
	resolveHit = fn
end

local projectileFolder = Workspace:FindFirstChild("Projectiles")
if not projectileFolder then
	projectileFolder = Instance.new("Folder")
	projectileFolder.Name = "Projectiles"
	projectileFolder.Parent = Workspace
end

-- Every projectile in flight. One shared Heartbeat steps all of them rather than a coroutine each,
-- same "one loop iterates every live thing" convention as the encounter tick and the smelting loop.
local live: { any } = {}

local function destroyProjectile(projectile)
	if projectile.Part then
		projectile.Part:Destroy()
		projectile.Part = nil
	end
	projectile.Dead = true
end

-- Fires one projectile. `spec` carries everything captured AT FIRE TIME — damage, the weapon's
-- profile, which Ultimate was equipped — so a shot resolves against the loadout that fired it even
-- if the player swaps weapons while it is still in the air.
function ProjectileService.Fire(player: Player, origin: Vector3, direction: Vector3, spec)
	local config = spec.Projectile or ProjectileConfig.Default

	local part = Instance.new("Part")
	part.Name = "Projectile"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(config.Radius * 2, config.Radius * 2, config.Radius * 2)
	part.Color = config.Color or ProjectileConfig.Default.Color
	part.Material = Enum.Material.Neon
	part.Anchored = true   -- stepped by hand below; physics would fight the raycast
	part.CanCollide = false
	part.CanQuery = false  -- must never be hit by another projectile's own raycast
	part.CFrame = CFrame.new(origin)
	part.Parent = projectileFolder

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- The shooter and every projectile are excluded: without this a bullet spawned at the muzzle
	-- immediately hits the player who fired it.
	params.FilterDescendantsInstances = { player.Character, projectileFolder }

	table.insert(live, {
		Player = player,
		Part = part,
		Position = origin,
		Velocity = direction.Unit * config.Speed,
		Gravity = config.Gravity or 0,
		Spec = spec,
		Params = params,
		DistanceLeft = config.Range or ProjectileConfig.Default.Range,
		PiercesLeft = config.Pierce or 0,
		AlreadyHit = {},
		Dead = false,
	})
end

RunService.Heartbeat:Connect(function(dt)
	for index = #live, 1, -1 do
		local projectile = live[index]

		if projectile.Dead or not projectile.Part or not projectile.Part.Parent then
			destroyProjectile(projectile)
			table.remove(live, index)
		else
			-- Gravity first, so the step below already reflects this frame's fall — an arcing shot
			-- computed the other way round drifts consistently high.
			if projectile.Gravity ~= 0 then
				projectile.Velocity += Vector3.new(0, -projectile.Gravity * dt, 0)
			end

			local step = projectile.Velocity * dt
			local distance = step.Magnitude

			-- Raycast the SEGMENT travelled this frame rather than testing the new position. At these
			-- speeds a bullet covers several studs per frame, so a point test would tunnel straight
			-- through anything thinner than one step.
			local result = Workspace:Raycast(projectile.Position, step, projectile.Params)

			if result then
				local hitPosition = result.Position
				local consumed = false

				if resolveHit then
					consumed = resolveHit(projectile.Player, result.Instance, projectile.Position, hitPosition, projectile.Spec)
				end

				if consumed and projectile.PiercesLeft > 0 then
					-- Punched through something that counted. Keep flying, but never hit the same
					-- body twice — exclude it and carry on from the impact point.
					projectile.PiercesLeft -= 1
					local exclude = projectile.Params.FilterDescendantsInstances
					table.insert(exclude, result.Instance:FindFirstAncestorOfClass("Model") or result.Instance)
					projectile.Params.FilterDescendantsInstances = exclude
					projectile.Position = hitPosition
					projectile.Part.CFrame = CFrame.new(hitPosition)
				else
					destroyProjectile(projectile)
					table.remove(live, index)
				end
			else
				projectile.Position += step
				projectile.Part.CFrame = CFrame.new(projectile.Position)
				projectile.DistanceLeft -= distance
				if projectile.DistanceLeft <= 0 then
					destroyProjectile(projectile)
					table.remove(live, index)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for index = #live, 1, -1 do
		if live[index].Player == player then
			destroyProjectile(live[index])
			table.remove(live, index)
		end
	end
end)

return ProjectileService
