--[[
	CaseConfig.lua
	Sealed cases sold by the Black Market dealer and opened on the Hacker Machine.

	See DESIGN_NOTES.md's "Black Market & Hacker Machine" section for the design this implements.

	=== HOW A CASE RESOLVES ===
	  1. roll a RARITY off the case's own Odds
	  2. pick one entry from that rarity's POOL
	Rarity decides what KIND of thing you get; the pool decides which one. That two-step is what
	lets two cases share the same odds but hand out completely different content — the whole point
	of the specialised lines below.

	=== THE CURRENCY SPLIT (deliberate) ===
	Scrap and Cores buy the ordinary cases, so the main currency never goes dead once a player has
	finished building. Contraband — earned from raids and boss waves, or bought with Robux as a
	grind skip — buys the premium-odds lines. The paid path buys TIME and ODDS, never exclusive
	content: everything in a Contraband case can also be reached through play.

	=== POOLS ===
	A pool is a list of { Kind, Key, Min, Max, Weight }. Kinds:
	  Currency  Scrap / Cores / Contraband
	  Ore       any OreConfig.Ores key
	  Refined   any RefinedOreConfig RefinedKey
	  Core      a CoreItem (CoreT1, ...)
	  Ultimate  a Mythical passive (UltimateConfig.Mods)
	  Tool      a special pickaxe (ToolModConfig)
	  DroneCore a drone companion Core (DroneConfig) — the two that cannot be crafted
	  WeaponFamily  unlocks a whole gun family in the Forge (WeaponFamilyConfig)

	=== ADDING THE MISSING CONTENT ===
	Every Kind above is live. Adding a new one is a pool entry here plus a matching branch in
	BlackMarketService.GrantReward — everything else (odds, rolling, the decode flow, the dealer UI,
	duplicate handling) already handles whatever you put in.
]]

local CaseConfig = {}

CaseConfig.RarityOrder = { "Common", "Rare", "Epic", "Legendary", "Mythical" }

----------------------------------------------------------------------
-- Pools
----------------------------------------------------------------------

-- Shared by every case unless a case names its own. Weights are relative WITHIN a pool.
CaseConfig.Pools = {
	Common = {
		{ Kind = "Currency", Key = "Scrap", Min = 150, Max = 400, Weight = 40 },
		{ Kind = "Ore", Key = "ScrapIron", Min = 40, Max = 120, Weight = 30 },
		{ Kind = "Ore", Key = "CopperWire", Min = 25, Max = 80, Weight = 25 },
		{ Kind = "Ore", Key = "SteelPlating", Min = 15, Max = 45, Weight = 15 },
	},

	Rare = {
		{ Kind = "Currency", Key = "Cores", Min = 15, Max = 45, Weight = 40 },
		{ Kind = "Ore", Key = "GoldContacts", Min = 10, Max = 30, Weight = 25 },
		{ Kind = "Refined", Key = "SteelIngot", Min = 8, Max = 25, Weight = 20 },
		{ Kind = "Refined", Key = "CopperCoil", Min = 8, Max = 25, Weight = 20 },
	},

	Epic = {
		-- Special pickaxes (ToolModConfig). Weighted above the materials for the same reason the
		-- Legendary tier leads with gun families: a rarity that mostly pays out ore is a dead rung.
		-- The materials stay as the duplicate floor once a player owns all three.
		{ Kind = "Tool", Key = "SplitHead", Weight = 18 },
		{ Kind = "Tool", Key = "Featherweight", Weight = 18 },
		{ Kind = "Tool", Key = "Prospector", Weight = 18 },
		-- The two Drone Cores you cannot craft. Weighted below the pickaxes because they are useless
		-- until Research Tier 3 unlocks the drone itself — rolling one early is a promise rather than
		-- a reward, and the reveal says so.
		{ Kind = "DroneCore", Key = "Scavenger", Weight = 11 },
		{ Kind = "DroneCore", Key = "Recon", Weight = 11 },
		{ Kind = "Refined", Key = "HardenedPlate", Min = 15, Max = 40, Weight = 16 },
		{ Kind = "Refined", Key = "GoldBar", Min = 10, Max = 30, Weight = 16 },
		{ Kind = "Ore", Key = "VoidiumShard", Min = 5, Max = 18, Weight = 9 },
		{ Kind = "Currency", Key = "Contraband", Min = 1, Max = 3, Weight = 5 },
	},

	Legendary = {
		-- Gun-family blueprints. Each unlocks a WHOLE family in the Forge, not one gun — see
		-- WeaponFamilyConfig. Weighted well above the material fallbacks, because "Legendary" paying
		-- out ore is exactly the dead rung this tier is supposed to avoid; the materials are here as
		-- the duplicate-protection floor once a player owns every family.
		{ Kind = "WeaponFamily", Key = "Bows", Weight = 14 },
		{ Kind = "WeaponFamily", Key = "Snipers", Weight = 14 },
		{ Kind = "WeaponFamily", Key = "Flamethrowers", Weight = 14 },
		{ Kind = "WeaponFamily", Key = "GrenadeLaunchers", Weight = 14 },
		{ Kind = "WeaponFamily", Key = "Miniguns", Weight = 14 },
		{ Kind = "Refined", Key = "VoidiumCore", Min = 8, Max = 20, Weight = 12 },
		{ Kind = "Currency", Key = "Contraband", Min = 4, Max = 10, Weight = 12 },
		{ Kind = "Core", Key = "CoreT3", Min = 1, Max = 2, Weight = 6 },
	},

	-- The reason to chase premium cases at all.
	Mythical = {
		{ Kind = "Ultimate", Key = "Detonator", Weight = 1 },
		{ Kind = "Ultimate", Key = "Ricochet", Weight = 1 },
		{ Kind = "Ultimate", Key = "LegBreaker", Weight = 1 },
		{ Kind = "Ultimate", Key = "HundredMil", Weight = 1 },
		{ Kind = "Ultimate", Key = "SharkBullet", Weight = 1 },
		{ Kind = "Ultimate", Key = "AimBot", Weight = 1 },
	},
}

----------------------------------------------------------------------
-- Cases
----------------------------------------------------------------------

-- Odds are relative weights, not percentages — they do not need to sum to anything. A rarity
-- omitted entirely cannot drop from that case, which is how the cheap lines are kept from ever
-- producing an Ultimate.
CaseConfig.Cases = {
	Scavenged = {
		DisplayName = "Scavenged Case",
		Description = "Whatever the last crew left behind. Mostly junk, occasionally not.",
		Cost = { Scrap = 600 },
		DecodeSeconds = 120,
		Odds = { Common = 78, Rare = 20, Epic = 2 },
	},

	Encrypted = {
		DisplayName = "Encrypted Case",
		Description = "Someone locked this properly. Better contents, longer crack.",
		Cost = { Cores = 60 },
		DecodeSeconds = 420,
		Odds = { Common = 45, Rare = 38, Epic = 15, Legendary = 2 },
	},

	-- The premium line. Contraband-only, and the only shipped case that can roll Mythical, which is
	-- what makes Contraband worth having rather than just another number.
	Blackline = {
		DisplayName = "Blackline Case",
		Description = "Off-books hardware. The only place Ultimate mods surface.",
		Cost = { Contraband = 12 },
		DecodeSeconds = 900,
		Odds = { Rare = 30, Epic = 40, Legendary = 22, Mythical = 8 },
	},

	-- Bought with Robux, capped daily — see DailyLimit. The cap is what keeps this a grind SKIP
	-- rather than a way to buy past the game entirely, which is the line the design draws.
	Prototype = {
		DisplayName = "Prototype Case",
		Description = "Straight off the bench. The best odds anyone sells.",
		Cost = {}, -- paid in Robux via ShopConfig, not from the profile
		RobuxProductKey = "PrototypeCase",
		DailyLimit = 3,
		DecodeSeconds = 600,
		Odds = { Epic = 40, Legendary = 40, Mythical = 20 },
	},
}

----------------------------------------------------------------------
-- Rushing a decode
----------------------------------------------------------------------

-- Two paths with deliberately different risk (see DESIGN_NOTES): Robux finishes instantly and
-- safely; Cores finishes instantly but can corrupt the case. The paid path buys certainty, the
-- grind path is a gamble — which is what stops the Cores rush from simply being the better option.
-- A "unique" reward — an Ultimate, a weapon-family blueprint, a special pickaxe, a Drone Core — is
-- a permanent unlock rather than a count, so rolling one you already own can otherwise pay nothing at
-- all, which is the most disappointing possible outcome of a premium case.
--
-- It used to convert to a flat, hand-tuned Contraband consolation per Kind (6 / 10 / 4 / 5). That was
-- four numbers nobody could relate back to anything, and they paid the SAME whether the duplicate
-- fell out of a 600-Scrap Scavenged Case or a 12-Contraband Blackline. Now it refunds half of what
-- the case actually cost, in the currency it cost — so compensation scales with the stake on its own
-- and there is nothing per-Kind left to tune.
CaseConfig.DuplicateRefundFraction = 0.5

-- The Robux case has no profile-side Cost to take a fraction of (see Prototype above — it is paid in
-- Robux through ShopConfig, not out of the profile), so it names its refund outright instead.
CaseConfig.RobuxDuplicateRefund = { Contraband = 8 }

-- The refund for a duplicate out of `caseKey`, as a cost-shaped table ({ Scrap = 300 }).
--
-- Rounded UP, and never below 1: a cheap case refunding zero of something would read as "you got
-- nothing", which is the exact outcome this mechanic exists to prevent.
--
-- SHARED rather than server-only, for the same reason as everything else in this project that both
-- sides have to agree on: the reveal card tells the player what they are getting back, and a HUD
-- that works it out its own way is a HUD that can promise a number the server will not pay.
function CaseConfig.DuplicateRefund(caseKey: string): { [string]: number }
	local case = CaseConfig.Cases[caseKey]
	if not case then
		return {}
	end

	local refund = {}
	local priced = false
	for key, amount in pairs(case.Cost or {}) do
		refund[key] = math.max(math.ceil(amount * CaseConfig.DuplicateRefundFraction), 1)
		priced = true
	end

	if not priced then
		for key, amount in pairs(CaseConfig.RobuxDuplicateRefund) do
			refund[key] = amount
		end
	end

	return refund
end

CaseConfig.Rush = {
	CoresCost = 25,
	CorruptChance = 0.25, -- lose the case entirely
	RobuxProductKey = "InstantDecode",
}

----------------------------------------------------------------------
-- Dealer stock rotation
----------------------------------------------------------------------

-- Same deterministic time-hash approach TurretConfig.GetRotatingStock uses, and for the same
-- reason: both client and server derive today's stock independently from the clock and always
-- agree, with no persisted state to disagree about.
CaseConfig.RestockPeriodSeconds = 4 * 3600
CaseConfig.StockSize = 3

-- Never rotates out. The cheap case has to always be buyable or a player can be locked out of the
-- entire system by a bad roll of the stock.
CaseConfig.AlwaysStocked = { "Scavenged" }

local function seededRandom(seed: number): number
	-- Self-contained hash rather than math.randomseed, which would perturb every other system's
	-- randomness as a side effect (enemy spawns, loot rolls) the moment this was called.
	local x = (seed * 9301 + 49297) % 233280
	return x / 233280
end

function CaseConfig.GetRotatingStock(now: number): { string }
	local window = math.floor(now / CaseConfig.RestockPeriodSeconds)

	local rotatable = {}
	for key in pairs(CaseConfig.Cases) do
		local always = false
		for _, fixed in ipairs(CaseConfig.AlwaysStocked) do
			if fixed == key then
				always = true
				break
			end
		end
		-- Robux cases are always available; they are not part of the rotation gamble.
		if not always and not CaseConfig.Cases[key].RobuxProductKey then
			table.insert(rotatable, key)
		end
	end
	table.sort(rotatable) -- stable input, so the same window always yields the same stock

	local stock = {}
	for _, key in ipairs(CaseConfig.AlwaysStocked) do
		table.insert(stock, key)
	end
	for key, case in pairs(CaseConfig.Cases) do
		if case.RobuxProductKey then
			table.insert(stock, key)
		end
	end

	local slots = math.max(CaseConfig.StockSize - #stock, 0)
	local index = 1
	while slots > 0 and #rotatable > 0 do
		local pick = math.floor(seededRandom(window + index * 7919) * #rotatable) + 1
		table.insert(stock, table.remove(rotatable, math.clamp(pick, 1, #rotatable)))
		slots -= 1
		index += 1
	end
	return stock
end

-- Seconds until the dealer restocks, for the UI countdown.
function CaseConfig.SecondsUntilRestock(now: number): number
	return CaseConfig.RestockPeriodSeconds - (now % CaseConfig.RestockPeriodSeconds)
end

return CaseConfig
