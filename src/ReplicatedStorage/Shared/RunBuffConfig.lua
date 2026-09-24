--[[
	RunBuffConfig.lua
	Pure data + pure helpers for the Salvage Run shop rework (DESIGN_NOTES.md, "Raid shop rework —
	SPEC SETTLED 2026-09-22" / "BUILD CONTRACT"). Replaces the old fixed-menu `NodeConfig.ShopCatalog`
	for raid Shop rooms: each visit rolls a handful of random offers from `Items` below, cards are
	shown with rarity = level ceiling (Rare 3 / Epic 4 / Legendary 5), and perks/gear live on the RUN
	STATE only — they end with the run by construction, no `RunOnly` tag needed.

	This module holds NO Instances and requires NO services — `RunBuffService` (server) and
	`RaidShopPanel` (client HUD) both read it directly so the shop can never advertise an offer the
	server won't honour, same reasoning as `ForgeConfig`/`ModConfig.ApplyMods` in CLAUDE.md's shared-
	helper list.

	Numbers throughout are placeholders per the design doc ("numbers marked ~ are placeholders") —
	the shape is approved, the values are not final balance.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModConfig = require(ReplicatedStorage.Shared.ModConfig)

local RunBuffConfig = {}

----------------------------------------------------------------------
-- Rarity ladder — walked low-to-high, same convention as ForgeConfig.RarityOrder. Rarity sets the
-- LEVEL CEILING only (the user's settled assumption): a Rare copy of an item you already own at
-- Epic still gives +1 level, it just can't push you past Epic's cap of 4.
----------------------------------------------------------------------

RunBuffConfig.RarityOrder = { "Rare", "Epic", "Legendary" }

RunBuffConfig.RarityCaps = {
	Rare = 3,
	Epic = 4,
	Legendary = 5,
}

-- Reuse ModConfig's rarity colors rather than inventing new ones (Rare/Epic/Legendary already exist
-- there for Forged weapons) — one palette, one place it can drift from.
function RunBuffConfig.RarityColor(rarity: string): Color3?
	local entry = ModConfig.Rarities[rarity]
	return entry and entry.Color
end

----------------------------------------------------------------------
-- Shop roll shape — how many offers a Shop room rolls per visit and what rarity they come in.
-- Weights are independent of `RarityCaps`; a Legendary OFFER is just rare to see, not a bigger jump.
----------------------------------------------------------------------

RunBuffConfig.OfferRarityWeights = {
	Rare = 70,
	Epic = 24,
	Legendary = 6,
}

RunBuffConfig.OffersPerShop = { Min = 3, Max = 4 }

-- At most one Escape-kind offer (Beacon/Insurance) per shop visit, so a roll can't crowd out every
-- perk/gear slot with one-use items.
RunBuffConfig.MaxEscapeOffersPerShop = 1

----------------------------------------------------------------------
-- Equipment slots, selling, healing cap, crit — the other flat numbers from the BUILD CONTRACT.
----------------------------------------------------------------------

RunBuffConfig.Slots = 4 -- perks + gear share this pool; Escape items take none (Round 2 answers)

RunBuffConfig.SellRefund = 0.5 -- selling a slotted item back refunds 50% of total Scrap paid for it

-- Separate from the Support Core drone's raid heal cap (15%/room, 75%/map) — the user's call, Round 2.
RunBuffConfig.ShopHealCap = { PerRoom = 0.25, PerMap = 1.0 }

RunBuffConfig.CritMultiplier = 1.5 -- damage multiplier on a crit proc (Overclock Chip's Lv4/Lv5)

----------------------------------------------------------------------
-- Items — 9 levelled perks/gear + 2 Escape items. Shape:
--   DisplayName, Kind ("Perk"|"Gear"|"Escape"), Icon (ReplicatedStorage.UiIcons key), Rarities
--   (which rarities this item can be offered at — normal items span the whole ladder, Escape items
--   are Epic only per the settled spec), Price[Rarity] in Scrap, Base (non-levelled constants, if
--   any), PerLevel (numeric stat table multiplied by current level), Lv4/Lv5 (flat bonus params
--   unlocked at that level — Epic reaches Lv4, Legendary reaches both), Card (HUD display: a Label
--   plus either a StatKey/Format pair for CardValue() to compute from, a Special case, or a static
--   Description for one-use Escape items).
--
--   A missing PerLevel/Lv4/Lv5 key is simply absent from LevelStats()'s output — same "missing means
--   no effect" convention as ModConfig's optional multipliers.
----------------------------------------------------------------------

RunBuffConfig.Items = {
	----------------------------------------------------------------
	-- Perks
	----------------------------------------------------------------

	OverclockChip = {
		DisplayName = "Overclock Chip",
		Kind = "Perk",
		Icon = "RunOverclockChip",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 100, Epic = 140, Legendary = 190 },
		PerLevel = { DamagePct = 0.08 }, -- +8% damage per level (Lv3 Rare cap = +24%, matches the Card.dc.html mock)
		Lv4 = { CritChance = 0.05 }, -- +5% flat crit chance, Epic+
		Lv5 = { GuaranteedCritEvery = 10 }, -- every 10th shot is a guaranteed crit, Legendary only
		Card = { Label = "Damage", StatKey = "DamagePct", Format = "Percent" },
	},

	RapidFeeder = {
		DisplayName = "Rapid Feeder",
		Kind = "Perk",
		Icon = "RunRapidFeeder",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 100, Epic = 140, Legendary = 190 },
		PerLevel = { FireRatePct = 0.07 }, -- +7% fire rate per level
		Lv4 = { OpeningBurstPct = 0.30, OpeningBurstSeconds = 3 }, -- +30% fire rate for the first 3s of a fight
		Lv5 = { KillFrenzyPct = 0.25, KillFrenzySeconds = 2 }, -- each kill: +25% fire rate for 2s
		Card = { Label = "Fire Rate", StatKey = "FireRatePct", Format = "Percent" },
	},

	PlatedVest = {
		DisplayName = "Plated Vest",
		Kind = "Perk",
		Icon = "RunPlatedVest",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 120, Epic = 190, Legendary = 260 },
		PerLevel = { MaxHpPct = 0.10 }, -- +10% max HP per level
		Lv4 = { EliteBossDamageTakenPct = -0.10 }, -- -10% damage taken from elites/bosses
		Lv5 = { LowHpShieldThreshold = 0.25, LowHpShieldPct = 0.20 }, -- once/room, dropping under 25% HP grants a shield worth 20% max HP
		Card = { Label = "Max HP", StatKey = "MaxHpPct", Format = "Percent" },
	},

	NanoRepair = {
		DisplayName = "Nano Repair",
		Kind = "Perk",
		Icon = "RunNanoRepair",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 100, Epic = 140, Legendary = 190 },
		PerLevel = { RoomClearHealPct = 0.05 }, -- heal 5% max HP per level on room clear (subject to ShopHealCap)
		Lv4 = { KillHealPct = 0.01 }, -- kills also heal 1% max HP (same cap)
		Lv5 = { OverhealToShield = true }, -- healing past full HP becomes a small shield instead of being wasted
		Card = { Label = "Room Clear Heal", StatKey = "RoomClearHealPct", Format = "Percent" },
	},

	KineticBarrier = {
		DisplayName = "Kinetic Barrier",
		Kind = "Perk",
		Icon = "RunKineticBarrier",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 110, Epic = 150, Legendary = 200 },
		PerLevel = { ShieldPctOfMaxHp = 0.08 }, -- shield worth 8% max HP per level, refills each room
		Lv4 = { RefillAfterSeconds = 8 }, -- also refills mid-room after 8s without taking damage
		Lv5 = { BreakKnockbackRadius = 10, BreakKnockbackForce = 40 }, -- breaking the shield knocks nearby enemies back
		Card = { Label = "Shield", StatKey = "ShieldPctOfMaxHp", Format = "Percent" },
	},

	ScavengersLens = {
		DisplayName = "Scavenger's Lens",
		Kind = "Perk",
		Icon = "RunScavengersLens",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 110, Epic = 150, Legendary = 200 },
		PerLevel = { LootPct = 0.10 }, -- +10% ore/Scrap from drops and chests per level
		Lv4 = { ChestHoldSeconds = 2 }, -- chests open in 2s instead of 3
		Lv5 = { ChestBonusItems = 1 }, -- every chest drops one extra item
		Card = { Label = "Loot Bonus", StatKey = "LootPct", Format = "Percent" },
	},

	----------------------------------------------------------------
	-- Gear — worn effects that supplement the player's equipped weapon, not replace it. Damage
	-- numbers are deliberately well under a weapon's own DPS (CraftingRecipes.Weapons ranges roughly
	-- 4-48 DPS) since gear stacks ON TOP of whatever gun is out.
	----------------------------------------------------------------

	ScorchAura = {
		DisplayName = "Scorch Aura",
		Kind = "Gear",
		Icon = "RunScorchAura",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 160, Epic = 210, Legendary = 270 },
		Base = { Radius = 10, TickSeconds = 0.5 }, -- a ring around the player that burns enemies standing in it
		PerLevel = { DamagePerSecond = 3 }, -- +3 DPS to everything inside the ring per level (Lv5 = 15 DPS, well under a weak gun's own DPS)
		Lv4 = { RadiusPct = 0.30 }, -- ring radius +30% (10 -> 13 studs) — the Epic-cap step
		-- The Legendary-cap step, and deliberately the bigger of the two: 10 -> 17 studs. Growth is
		-- banked at the caps rather than spread evenly per level (the user's call, 2026-09-24) so the
		-- ring keeps its milestone feel instead of creeping. LevelStats overlays Lv5 onto Lv4 key by
		-- key, so restating RadiusPct here REPLACES the 0.30 above rather than stacking with it.
		Lv5 = { Status = "Slow", RadiusPct = 0.70 }, -- enemies inside the ring are Slowed (StatusConfig.Slow)
		Card = { Label = "Burn Damage", StatKey = "DamagePerSecond", Format = "Rate" },
	},

	OrbitBlades = {
		DisplayName = "Orbit Blades",
		Kind = "Gear",
		Icon = "RunOrbitBlades",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 180, Epic = 230, Legendary = 280 },
		Base = { Blades = 2, OrbitRadius = 6, HitCooldown = 0.5 }, -- 2 blades circle the player, each can hit the same target once per cooldown
		PerLevel = { DamagePerHit = 2 }, -- +2 damage per hit per level
		-- Same cap-step shape as ScorchAura above, on a key of its own: RadiusPct is already summed
		-- into Aggregate's flat totals by the aura, and a second item writing the same key there would
		-- be a collision waiting for the first reader of it.
		Lv4 = { ExtraBlades = 1, OrbitRadiusPct = 0.30 }, -- +1 blade; orbit 6 -> 7.8 studs
		Lv5 = { Status = "Staggered", OrbitRadiusPct = 0.70 }, -- Staggered (StatusConfig.Staggered); orbit 6 -> 10.2 studs
		Card = { Label = "Blades circling you", Special = "OrbitBladeCount" },
	},

	LaserDrone = {
		DisplayName = "Laser Drone",
		Kind = "Gear",
		Icon = "RunLaserDrone",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 170, Epic = 220, Legendary = 270 },
		Base = { Range = 25, ShotsPerSecond = 2 }, -- a drone that auto-shoots the nearest enemy in range
		PerLevel = { DamagePerShot = 2 }, -- +2 damage per shot per level
		Lv4 = { FireRatePct = 0.30 }, -- fires 30% faster
		Lv5 = { ExtraBeams = 1 }, -- fires a second beam
		Card = { Label = "Damage Per Shot", StatKey = "DamagePerShot", Format = "Flat" },
	},

	----------------------------------------------------------------
	-- Escape — no levels, no slot. Epic only (the settled spec's exact prices).
	----------------------------------------------------------------

	ExtractionBeacon = {
		DisplayName = "Extraction Beacon",
		Kind = "Escape",
		Icon = "RunExtractionBeacon",
		Rarities = { "Epic" },
		Price = { Epic = 220 },
		OneUse = true, -- consuming it counts as a clean extract: the run ends now, ore is kept
		Card = { Label = "Leave the raid now", Description = "Counts as a clean extract. Your ore comes home." },
	},

	SalvageInsurance = {
		DisplayName = "Salvage Insurance",
		Kind = "Escape",
		Icon = "RunSalvageInsurance",
		Rarities = { "Epic" },
		Price = { Epic = 180 },
		KeepOrePct = 0.40, -- on Defeat/Abandon, keep 40% of this run's RunLocked ore instead of losing all of it
		Card = { Label = "Keep Ore On Death", Description = "Keep 40% of your run's ore if you die or abandon." },
	},
}

----------------------------------------------------------------------
-- Pure helpers — no Instances, no services. Shared by RunBuffService (server) and RaidShopPanel
-- (client) so the shop can't show a number the server won't honour.
----------------------------------------------------------------------

-- The level ceiling for a given rarity. Returns nil for an unrecognized rarity (e.g. an Escape
-- item's caller passing nothing sensible) rather than guessing.
function RunBuffConfig.Cap(rarity: string): number?
	return RunBuffConfig.RarityCaps[rarity]
end

-- Position of a rarity in RarityOrder (1 = Rare .. 3 = Legendary), or 0 if not found — 0 sorts below
-- every real rarity, which is the safe default for a comparison rather than nil.
function RunBuffConfig.RarityIndex(rarity: string): number
	for i, r in ipairs(RunBuffConfig.RarityOrder) do
		if r == rarity then
			return i
		end
	end
	return 0
end

--[[
	PreviewOffer(owned, offer, slotsUsed)

	owned: the player's current entry for this item, or nil/false if they don't have it —
	       { Rarity: string, Level: number }
	offer: the rolled shop card — { ItemKey: string, Rarity: string }
	slotsUsed: how many of RunBuffConfig.Slots are currently occupied

	Returns a plain table describing what buying `offer` would do, so the HUD card and the server's
	actual purchase agree on the outcome before Scrap changes hands:
	{ FromLv, ToLv, PrevCap, NewCap, RarityUp: boolean, IsNew: boolean, NeedsSlot: boolean,
	  Blocked: nil | "Maxed" | "SlotsFull" | "AlreadyHeld" }
]]
function RunBuffConfig.PreviewOffer(owned, offer, slotsUsed: number)
	local item = RunBuffConfig.Items[offer.ItemKey]
	assert(item, ("RunBuffConfig.PreviewOffer: unknown item key %s"):format(tostring(offer.ItemKey)))

	local result = {
		FromLv = 0,
		ToLv = 0,
		PrevCap = 0,
		NewCap = 0,
		RarityUp = false,
		IsNew = false,
		NeedsSlot = false,
		Blocked = nil,
	}

	-- Escape items: no levels, no slot, capped at one held at a time.
	if item.Kind == "Escape" then
		if owned then
			result.Blocked = "AlreadyHeld"
			return result
		end
		result.IsNew = true
		return result
	end

	-- Not owned yet: a fresh Lv1 pickup, needs a free slot.
	if not owned then
		result.IsNew = true
		result.ToLv = 1
		result.NewCap = RunBuffConfig.Cap(offer.Rarity) or 0
		result.NeedsSlot = true
		if slotsUsed >= RunBuffConfig.Slots then
			result.Blocked = "SlotsFull"
		end
		return result
	end

	-- Already owned, offer is a higher rarity: keep the level, raise the ceiling, no new slot.
	local ownedCap = RunBuffConfig.Cap(owned.Rarity) or 0
	if RunBuffConfig.RarityIndex(offer.Rarity) > RunBuffConfig.RarityIndex(owned.Rarity) then
		result.RarityUp = true
		result.FromLv = owned.Level
		result.ToLv = owned.Level
		result.PrevCap = ownedCap
		result.NewCap = RunBuffConfig.Cap(offer.Rarity) or ownedCap
		return result
	end

	-- Already owned, same or lower rarity: +1 level, capped at the OWNED rarity's ceiling.
	result.FromLv = owned.Level
	result.PrevCap = ownedCap
	result.NewCap = ownedCap
	if owned.Level >= ownedCap then
		result.ToLv = owned.Level
		result.Blocked = "Maxed"
		return result
	end
	result.ToLv = owned.Level + 1
	return result
end

-- The stat table an item contributes at `level`: PerLevel entries scaled by level, plus Lv4's flat
-- params folded in at level >= 4 and Lv5's at level >= 5. Missing tables are simply skipped.
function RunBuffConfig.LevelStats(itemKey: string, level: number)
	local item = RunBuffConfig.Items[itemKey]
	if not item then
		return {}
	end

	local stats = {}
	if item.PerLevel then
		for key, perLevelValue in pairs(item.PerLevel) do
			stats[key] = perLevelValue * level
		end
	end
	if level >= 4 and item.Lv4 then
		for key, value in pairs(item.Lv4) do
			stats[key] = value
		end
	end
	if level >= 5 and item.Lv5 then
		for key, value in pairs(item.Lv5) do
			stats[key] = value
		end
	end
	return stats
end

-- The value string shown on a card for one item at one level (e.g. "+16%", "1.5/s"). Escape items
-- have no level-scaled value — their Card.Description is the whole story, so this returns that
-- instead (matching Card.dc.html's `oneUse` branch, which shows a description, not a from/to value).
function RunBuffConfig.CardValue(itemKey: string, level: number): string
	local item = RunBuffConfig.Items[itemKey]
	if not item or not item.Card then
		return ""
	end
	local card = item.Card

	if item.Kind == "Escape" then
		return card.Description or ""
	end

	if card.Special == "OrbitBladeCount" then
		local blades = (item.Base and item.Base.Blades) or 0
		if level >= 4 and item.Lv4 and item.Lv4.ExtraBlades then
			blades += item.Lv4.ExtraBlades
		end
		return tostring(blades)
	end

	local perLevelValue = (item.PerLevel and item.PerLevel[card.StatKey]) or 0
	local raw = perLevelValue * level

	if card.Format == "Percent" then
		return string.format("+%d%%", math.floor(raw * 100 + 0.5))
	elseif card.Format == "Rate" then
		return string.format("%.1f/s", raw)
	elseif card.Format == "Flat" then
		return string.format("+%d", raw)
	end
	return tostring(raw)
end

-- Sums numeric stats across every owned item (at its current level) plus every picked boss card,
-- into one flat table combat code can read without knowing which perk/gear/card contributed what.
-- Non-numeric fields (e.g. OrbitBlades' Lv5 `Status = "Staggered"`) are intentionally NOT summed
-- here — those are per-item effects the consuming service reads via LevelStats directly, not
-- something that makes sense added across items.
--   ownedByKey: { [itemKey] = { Rarity = ..., Level = ... }, ... } or nil
--   bossCards: array of { ..., Stats = { [statKey] = number, ... } } or nil
function RunBuffConfig.Aggregate(ownedByKey, bossCards)
	local totals = {}

	local function addNumbers(tbl)
		if not tbl then
			return
		end
		for key, value in pairs(tbl) do
			if type(value) == "number" then
				totals[key] = (totals[key] or 0) + value
			end
		end
	end

	if ownedByKey then
		for itemKey, owned in pairs(ownedByKey) do
			addNumbers(RunBuffConfig.LevelStats(itemKey, owned.Level))
		end
	end

	if bossCards then
		for _, card in ipairs(bossCards) do
			addNumbers(card.Stats)
		end
	end

	return totals
end

return RunBuffConfig
