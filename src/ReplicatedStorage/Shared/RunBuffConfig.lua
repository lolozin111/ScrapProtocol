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
-- Raised from PerRoom 0.25 / PerMap 1.0 on 2026-09-25, and it had to move for the Nano Repair
-- retune to mean anything: that perk's Lv5 total was 5% x 5 levels = EXACTLY the old 25% room
-- ceiling, so its capstone was already being clipped and lifting the perk alone would have been an
-- inert change. The trade is real and deliberate -- a more generous shop-heal budget makes a raid
-- Heal ROOM slightly less precious, which is the thing this cap was introduced to protect.
RunBuffConfig.ShopHealCap = { PerRoom = 0.35, PerMap = 1.6 }

RunBuffConfig.CritMultiplier = 1.5 -- damage multiplier on a crit proc (Overclock Chip, Lv3 and up)

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
		PerLevel = { DamagePct = 0.10 }, -- +10% damage per level (Lv5 = +50%)
		Lv3 = { CritChance = 0.05 }, -- +5% flat crit, the RARE cap's step (crit used to start at Epic)
		Lv4 = { CritChance = 0.10 }, -- +10% flat crit, the Epic-cap step
		Lv5 = { CritChance = 0.15, GuaranteedCritEvery = 5 }, -- +15% crit AND every 5th shot crits outright
		Card = { Label = "Damage", StatKey = "DamagePct", Format = "Percent" },
	},

	RapidFeeder = {
		DisplayName = "Rapid Feeder",
		Kind = "Perk",
		Icon = "RunRapidFeeder",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 100, Epic = 140, Legendary = 190 },
		PerLevel = { FireRatePct = 0.09 }, -- +9% fire rate per level (Lv5 = +45%)
		Lv3 = { OpeningBurstPct = 0.20, OpeningBurstSeconds = 3 }, -- the RARE cap's step
		Lv4 = { OpeningBurstPct = 0.30, OpeningBurstSeconds = 3 }, -- +30% for the first 3s of a fight
		-- The Legendary capstone: a bigger opening burst AND a kill-fed frenzy that chains through a room.
		Lv5 = { OpeningBurstPct = 0.45, OpeningBurstSeconds = 4, KillFrenzyPct = 0.40, KillFrenzySeconds = 3 },
		Card = { Label = "Fire Rate", StatKey = "FireRatePct", Format = "Percent" },
	},

	PlatedVest = {
		DisplayName = "Plated Vest",
		Kind = "Perk",
		Icon = "RunPlatedVest",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 120, Epic = 190, Legendary = 260 },
		PerLevel = { MaxHpPct = 0.12 }, -- +12% max HP per level (Lv5 = +60%)
		Lv3 = { EliteBossDamageTakenPct = -0.10 }, -- the RARE cap's step
		Lv4 = { EliteBossDamageTakenPct = -0.15 }, -- -15% damage taken from elites/bosses
		-- The Legendary capstone: a quarter less damage from the things that actually kill you, and a
		-- once-per-room bail-out that triggers earlier and gives more.
		Lv5 = { EliteBossDamageTakenPct = -0.25, LowHpShieldThreshold = 0.30, LowHpShieldPct = 0.35 },
		Card = { Label = "Max HP", StatKey = "MaxHpPct", Format = "Percent" },
	},

	NanoRepair = {
		DisplayName = "Nano Repair",
		Kind = "Perk",
		Icon = "RunNanoRepair",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 100, Epic = 140, Legendary = 190 },
		-- 6% not 5%: at the OLD 5% the Lv5 total was 25%, which is EXACTLY ShopHealCap.PerRoom's old
		-- ceiling -- the capstone was already being clipped, so raising this alone would have changed
		-- nothing. The cap moved with it (see RunBuffConfig.ShopHealCap).
		PerLevel = { RoomClearHealPct = 0.06 }, -- heal 6% max HP per level on room clear (Lv5 = 30%, under the 35% room cap)
		Lv3 = { KillHealPct = 0.01 }, -- kills also heal, the RARE cap's step
		Lv4 = { KillHealPct = 0.015 }, -- 1.5% per kill, the Epic-cap step (same cap)
		-- The Legendary capstone: kills heal more, and healing past full stops being wasted at all.
		Lv5 = { KillHealPct = 0.025, OverhealToShield = true },
		Card = { Label = "Room Clear Heal", StatKey = "RoomClearHealPct", Format = "Percent" },
	},

	KineticBarrier = {
		DisplayName = "Kinetic Barrier",
		Kind = "Perk",
		Icon = "RunKineticBarrier",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 110, Epic = 150, Legendary = 200 },
		PerLevel = { ShieldPctOfMaxHp = 0.10 }, -- shield worth 10% max HP per level, refills each room (Lv5 = 50%)
		Lv3 = { RefillAfterSeconds = 10 }, -- the RARE cap's step: it also refills mid-room
		Lv4 = { RefillAfterSeconds = 8 }, -- refills after 8s without taking damage, the Epic-cap step
		-- The Legendary capstone: refills twice as often as Rare, and breaking it clears the space around
		-- you rather than nudging it.
		Lv5 = { RefillAfterSeconds = 5, BreakKnockbackRadius = 16, BreakKnockbackForce = 70 },
		Card = { Label = "Shield", StatKey = "ShieldPctOfMaxHp", Format = "Percent" },
	},

	ScavengersLens = {
		DisplayName = "Scavenger's Lens",
		Kind = "Perk",
		Icon = "RunScavengersLens",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 110, Epic = 150, Legendary = 200 },
		PerLevel = { LootPct = 0.12 }, -- +12% ore/Scrap from drops and chests per level (Lv5 = +60%)
		Lv3 = { ChestHoldSeconds = 2 }, -- chests open in 2s instead of 3, the RARE cap's step
		Lv4 = { ChestHoldSeconds = 1.5 }, -- 1.5s, the Epic-cap step
		-- The Legendary capstone: near-instant chests and two extra items out of every one.
		Lv5 = { ChestHoldSeconds = 1, ChestBonusItems = 2 },
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
		-- A ring on the GROUND that burns enemies standing in it, not a sphere around your chest.
		-- Height is what makes that true in the damage test: reach is measured on the floor plane
		-- (horizontal distance from you) and then bounded vertically by Height, so jumping does not
		-- drag the burn up off the floor with you and leave the drawn ring claiming a reach it no
		-- longer has. Generous on purpose -- a jump should never interrupt your own aura.
		Base = { Radius = 10, TickSeconds = 0.5, Height = 14 },
		PerLevel = { DamagePerSecond = 4 }, -- +4 DPS to everything inside the ring per level (Lv4 Epic cap = 16)
		Lv3 = { RadiusPct = 0.15 }, -- ring 10 -> 11.5 studs, the RARE cap's step (see LevelStats on why Lv3 exists now)
		Lv4 = { RadiusPct = 0.30 }, -- ring 10 -> 13 studs, the Epic-cap step
		-- The Legendary capstone, and it is meant to feel like one: the ring DOUBLES to 20 studs and the
		-- burn jumps to a flat 25 DPS, well above where the linear +4/level ramp would have landed (20).
		-- Restating DamagePerSecond here REPLACES that ramp outright -- see LevelStats. Radius growth is
		-- safe to be this aggressive because the aura is a filled DISC (horizontal distance to the
		-- player), so a wider ring is strictly more coverage, with no pocket in the middle. OrbitBlades
		-- is a ring BAND and deliberately does not grow -- see its entry.
		Lv5 = { Status = "Slow", RadiusPct = 1.00, DamagePerSecond = 25 },
		Card = { Label = "Burn Damage", StatKey = "DamagePerSecond", Format = "Rate" },
	},

	OrbitBlades = {
		DisplayName = "Orbit Blades",
		Kind = "Gear",
		Icon = "RunOrbitBlades",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 180, Epic = 230, Legendary = 280 },
		-- 2 blades circle the player, each can hit the same target once per cooldown.
		--
		-- OrbitSpeed (radians/second) is SHARED rather than a private constant in RunBuffService for
		-- the same reason the rest of this file exists: the client draws the blades and the server
		-- decides what they cut, and both derive the angle from this number and Workspace:GetServerTimeNow().
		-- One number, one synchronized clock, no messages -- so the blade you see and the blade that
		-- hits are the same blade by construction. Two copies of the speed would drift apart slowly and
		-- invisibly, which is the worst version of this bug.
		Base = { Blades = 2, OrbitRadius = 6, HitCooldown = 0.5, OrbitSpeed = 2 },
		PerLevel = { DamagePerHit = 3 }, -- +3 damage per hit per level (Lv5 = 15)
		Lv3 = { ExtraBlades = 1 }, -- 3 blades, the RARE cap's step
		-- The orbit radius deliberately does NOT grow with level, unlike ScorchAura's ring. The blades
		-- damage only what comes within ~3 studs of a BLADE, so they cut a ring BAND rather than a filled
		-- disc, and anything closer to you than the orbit sits in a safe pocket. Widening the orbit widens
		-- that pocket -- it would make the blades WORSE against exactly the enemies you want them for,
		-- now that a Scavenger attacks from 6 studs. An OrbitRadiusPct key was tried here and removed for
		-- this reason (the user's call, 2026-09-25); the multiplier survives in RunBuffService so the
		-- option stays one config value away, but do not re-add it without solving the pocket first.
		-- Max level grows the blade COUNT and their damage instead, which has no such downside.
		Lv4 = { ExtraBlades = 2 }, -- 4 blades, the Epic-cap step
		-- The Legendary capstone: 5 blades at 15 damage each. Single-target DPS works out at roughly
		-- blades * damage / orbit period (2pi/OrbitSpeed = 3.14s), so the ramp is about 8.6 -> 15.3 ->
		-- 23.9 DPS across the three rarity caps -- each cap close to double the last, which is the point.
		Lv5 = { Status = "Staggered", ExtraBlades = 3 }, -- 5 blades; hits also apply Staggered (StatusConfig.Staggered)
		Card = { Label = "Blades circling you", Special = "OrbitBladeCount" },
	},

	LaserDrone = {
		DisplayName = "Laser Drone",
		Kind = "Gear",
		Icon = "RunLaserDrone",
		Rarities = RunBuffConfig.RarityOrder,
		Price = { Rare = 170, Epic = 220, Legendary = 270 },
		Base = { Range = 25, ShotsPerSecond = 2 }, -- a drone that auto-shoots the nearest enemy in range
		-- Damage per shot is deliberately NOT lifted. ExtraBeams below fires at DIFFERENT targets (see
		-- GearBehaviors.LaserDrone: it sorts candidates and shoots the nearest N), so beams spread damage
		-- rather than stacking it on one enemy -- which already made this the strongest single-target gear
		-- piece of the three at ~26 DPS. It gets a rate-and-targets capstone instead of a damage one.
		PerLevel = { DamagePerShot = 2 }, -- +2 damage per shot per level (Lv5 = 10)
		Lv3 = { FireRatePct = 0.15 }, -- 2.3 shots/s, the RARE cap's step
		Lv4 = { FireRatePct = 0.30 }, -- 2.6 shots/s, the Epic-cap step
		-- The Legendary capstone: 3 shots/s on the nearest enemy (30 DPS) and two further beams, so it
		-- covers three targets at once instead of one.
		Lv5 = { FireRatePct = 0.50, ExtraBeams = 2 },
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
	-- Tier overrides, applied in ASCENDING order so a higher tier's value wins. This used to be two
	-- hardcoded blocks for Lv4 and Lv5, which quietly meant a RARE copy could never have a tier step
	-- of its own -- Rare caps at level 3, so every milestone in the file landed above its ceiling and
	-- a Rare item's only progression was the linear PerLevel term. Walking the levels generically
	-- lets each rarity cap (Rare 3 / Epic 4 / Legendary 5) get a step that a player at that cap
	-- actually reaches.
	--
	-- Starts at 2 because level 1 IS the PerLevel term above; an Lv1 table would just be a confusing
	-- second way to write a base value.
	--
	-- Note this OVERWRITES rather than accumulates: an Lv5 entry restating a key REPLACES the Lv4
	-- value, and restating a PerLevel key replaces the computed `perLevelValue * level` entirely.
	-- That is load-bearing, not incidental -- it is how a capstone sets a flat number (ScorchAura's
	-- Lv5 DamagePerSecond) instead of being stuck with whatever the linear ramp reached.
	for tierLevel = 2, level do
		local tier = item["Lv" .. tostring(tierLevel)]
		if tier then
			for key, value in pairs(tier) do
				stats[key] = value
			end
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
