--[[
	MiningService.lua
	Handles ore-node hits. The client only ever says "I hit this node" — the server decides
	whether that's legal (tool tier, unlock gate, distance) and how much ore it's worth.
	Never let the client tell the server how much ore to grant.

	Expects ore nodes in the workspace to be Parts/Models tagged with a StringValue named
	"OreType" whose value matches a key in OreConfig.Ores (e.g. "ScrapIron"). Tag your map's
	ore nodes this way in Studio — no code changes needed to add more nodes. ResourceZoneService
	builds nodes the same way procedurally, so everything below applies equally to both.

	Depletion: every node survives OreConfig.Ores[oreKey].MaxHits successful mines before going
	empty for RespawnSeconds, tracked via a "HitsRemaining" Attribute (replicates to clients for
	free — no RemoteEvent needed) and lazily initialized here the first time a node is ever
	mined, so hand-placed nodes that predate this feature don't need any Studio edits. A
	"Depleted" Attribute mirrors whether it's currently empty; MiningController listens to that
	one to enable/disable the node's ProximityPrompt client-side (purely a UX nicety — this
	service is what actually enforces it, regardless of what the client's prompt is doing).

	Tool tiers: MineNode is a fire-and-forget RemoteEvent, so a rejected attempt used to fail
	completely silently client-side — the player just saw nothing happen with no way to know
	why. A blocked-by-tool-tier ore (e.g. Steel Plating needs ToolTier 2) was ALSO, until now,
	permanently unreachable regardless, because nothing ever raised a player's ToolTier past the
	starting 1 — see UpgradeTool below, the fix for both problems at once.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OreConfig = require(ReplicatedStorage.Shared.OreConfig)
local RaidEnergyConfig = require(ReplicatedStorage.Shared.RaidEnergyConfig)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local DataService = require(script.Parent.DataService)
local RaidEnergyService = require(script.Parent.RaidEnergyService)
local PlotService = require(script.Parent.PlotService)
local StationService = require(script.Parent.StationService)
local RateLimiter = require(script.Parent.RateLimiter)
local OreGate = require(script.Parent.OreGate)

local Remotes = ReplicatedStorage.Remotes
local MineNode = Remotes.MineNode
local UpgradeTool = Remotes.UpgradeTool

local MAX_MINING_DISTANCE = 12 -- studs; reject hits from further away than this

local MiningService = {}

local function getOreTypeFromNode(node: Instance): string?
	local marker = node:FindFirstChild("OreType")
	if marker and marker:IsA("StringValue") then
		return marker.Value
	end
	return nil
end

----------------------------------------------------------------------
-- Tool mods — the special pickaxes, one equipped at a time.
--
-- No station gate, matching how weapon and Ultimate loadout changes work: choosing which gear is
-- active is not crafting, and making a player walk to a bench to swap pickaxes would be friction
-- with nothing behind it.
----------------------------------------------------------------------

Remotes.EquipToolMod.OnServerInvoke = function(player: Player, toolKey: string?)
	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	-- nil unequips, which is the only way back to plain tier behaviour once you own one.
	if toolKey == nil then
		profile.EquippedTool = nil
		Remotes.InventoryUpdate:FireClient(player, { EquippedTool = false })
		return { Success = true }
	end

	if not ToolModConfig.Tools[toolKey] then
		return { Success = false, Reason = "Unknown tool" }
	end
	if not (profile.OwnedTools or {})[toolKey] then
		return { Success = false, Reason = "You don't own that pickaxe — they come from Black Market cases." }
	end

	profile.EquippedTool = toolKey
	Remotes.InventoryUpdate:FireClient(player, { EquippedTool = toolKey })
	return { Success = true, EquippedTool = toolKey }
end

----------------------------------------------------------------------
-- Tool tier upgrades
----------------------------------------------------------------------

UpgradeTool.OnServerInvoke = function(player: Player)
	if not PlotService.IsPlayerInOwnPlot(player) then
		return { Success = false, Reason = PlotConfig.NotInBaseMessage }
	end
	if not StationService.IsPlayerNearStation(player, "Crafting") then
		return { Success = false, Reason = StationConfig.Types.Crafting.NotThereMessage }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Reason = "Profile not loaded" }
	end

	local nextTier = profile.ToolTier + 1
	local nextToolData = OreConfig.ToolTiers[nextTier]
	if not nextToolData then
		return { Success = false, Reason = "Already at the max tool tier" }
	end

	local cost = OreConfig.ToolTierCosts[nextTier]
	if not cost then
		return { Success = false, Reason = "No cost configured for this tier — add one to OreConfig.ToolTierCosts" }
	end

	local spent = DataService.TrySpend(player, cost)
	if not spent then
		return { Success = false, Reason = "Not enough resources" }
	end

	profile.ToolTier = nextTier

	Remotes.InventoryUpdate:FireClient(player, {
		OreCounts = profile.OreCounts,
		ToolTier = profile.ToolTier,
	})

	return { Success = true, ToolTier = profile.ToolTier }
end

----------------------------------------------------------------------
-- Depletion / respawn
----------------------------------------------------------------------

-- Reads the node's current HitsRemaining, seeding it from OreConfig on first read — this is
-- what makes depletion apply retroactively to any node that already existed before this
-- feature, hand-placed or not, with zero Studio edits required.
local function getHitsRemaining(node: Instance, oreData): number
	local hits = node:GetAttribute("HitsRemaining")
	if hits == nil then
		hits = oreData.MaxHits
		node:SetAttribute("HitsRemaining", hits)
	end
	return hits
end

-- Best-effort visual feedback — only touches a "Label" BillboardGui if the node happens to have
-- one (ResourceZoneService's procedural nodes do; older hand-placed ones might not, and that's
-- fine, this just no-ops for those).
local function updateNodeVisual(node: Instance, oreData, hitsRemaining: number, depleted: boolean)
	if node:IsA("BasePart") then
		node.Transparency = depleted and 0.75 or 0
	end
	local billboard = node:FindFirstChild("Label")
	local textLabel = billboard and billboard:FindFirstChildOfClass("TextLabel")
	if textLabel then
		textLabel.Text = depleted
			and "Depleted"
			or ("%s (%d/%d)"):format(oreData.DisplayName, hitsRemaining, oreData.MaxHits)
	end
end

MineNode.OnServerEvent:Connect(function(player: Player, node: Instance)
	if typeof(node) ~= "Instance" or not node:IsDescendantOf(workspace) then
		return
	end

	-- HumanoidRootPart, not character.PrimaryPart: Roblox does not guarantee PrimaryPart is set on
	-- a character model, so reading it was a silent "mining does nothing" for anyone whose rig
	-- happened not to have it. Every other service in this codebase already looks the root part up
	-- by name; these two mining services were the odd ones out.
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local nodePosition = node:IsA("BasePart") and node.Position
		or (node:IsA("Model") and node.PrimaryPart and node.PrimaryPart.Position)
	if not nodePosition then
		return
	end
	if (rootPart.Position - nodePosition).Magnitude > MAX_MINING_DISTANCE then
		return
	end

	local oreKey = getOreTypeFromNode(node)
	if not oreKey then
		return
	end

	local canMine, reason = OreGate.CanMine(player, oreKey)
	if not canMine then
		Remotes.MineFailed:FireClient(player, reason or "Can't mine this yet")
		return
	end

	-- Swing pacing, enforced server-side. MineNode is a fire-and-forget RemoteEvent with only a
	-- distance check in front of it, so before this a modified client could fire it in a tight
	-- loop and drain any node as fast as it could send packets — every hit granting full yield.
	-- OreConfig.ToolTiers[].SwingTime had described this pacing since the config was first
	-- written but was never actually read by anything; this is where it finally applies.
	--
	-- Read from the player's CURRENT tier, not cached: upgrading your tool is supposed to make
	-- you mine faster (1.2s at Rusty Pickaxe down to 0.3s at Plasma Drill), which is half the
	-- point of buying the upgrade at all. The client's own ProximityPrompt HoldDuration is a UX
	-- nicety on top of this, exactly like the Depleted attribute is — this check is what's real.
	-- OreGate.CanMine above already proved the profile exists. The `or ToolTiers[1]` fallback guards
	-- the index itself, not the profile: a ToolTier past the end of the ladder (a save written
	-- against a longer one, a bad value) would otherwise error inside the remote handler.
	local profile = DataService.Get(player)
	local toolData = OreConfig.ToolTiers[profile.ToolTier] or OreConfig.ToolTiers[1]
	if not RateLimiter.Check(player, "MineNode", toolData.SwingTime) then
		Remotes.MineFailed:FireClient(player, "Swinging too fast — wait for your tool to reset")
		return
	end

	local oreData = OreConfig.Ores[oreKey]

	-- Never trust the client's ProximityPrompt state — it's only a UX nicety, this check is
	-- what actually enforces "an empty node can't be mined."
	local hitsRemaining = getHitsRemaining(node, oreData)
	if hitsRemaining <= 0 then
		Remotes.MineFailed:FireClient(player, "Depleted — wait for it to respawn")
		return
	end

	-- profile/toolData were already resolved for the swing-pacing check above.
	local yield = math.floor(oreData.BaseYield * toolData.YieldMultiplier + 0.5)
	DataService.AddOre(player, oreKey, yield)

	Remotes.InventoryUpdate:FireClient(player, { OreCounts = profile.OreCounts })

	-- Rare Energy Drink find — deliberately uncommon (see RaidEnergyConfig), fires its own
	-- InventoryUpdate/EnergyDrinkFound so the player gets a distinct "you got lucky" moment
	-- instead of it blending into the ordinary ore yield above.
	if math.random() <= RaidEnergyConfig.EnergyDrinkFindChance then
		RaidEnergyService.GrantEnergyDrink(player)
	end

	hitsRemaining -= 1
	node:SetAttribute("HitsRemaining", hitsRemaining)

	if hitsRemaining <= 0 then
		node:SetAttribute("Depleted", true)
		updateNodeVisual(node, oreData, 0, true)

		task.delay(oreData.RespawnSeconds, function()
			if not node.Parent then
				return -- node was removed entirely (e.g. the zone got wiped) — nothing to respawn
			end
			node:SetAttribute("HitsRemaining", oreData.MaxHits)
			node:SetAttribute("Depleted", false)
			updateNodeVisual(node, oreData, oreData.MaxHits, false)
		end)
	else
		updateNodeVisual(node, oreData, hitsRemaining, false)
	end
end)

return MiningService
