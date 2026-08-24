--[[
	RefinedOreConfig.lua
	Static data for the Forge's Ore Smelting mechanic — the Forge's second job besides rolling
	weapons. Every raw ore in OreConfig.Ores can be smelted down into its own refined material at
	a fixed RefineRatio (raw ore consumed per 1 unit of refined material produced).

	Smelting itself is a single-job-at-a-time thing per player (see SmeltService.lua's
	profile.SmeltJob) — pick a raw ore you own, pick a quantity (must be a positive multiple of
	that ore's RefineRatio), and the Forge produces RefinedOreCounts over time.

	Batch time uses an actual logarithm (ComputeSmeltSeconds below), per direct request: the more
	raw ore you feed into one batch, the less time it costs per individual ore, but the total batch
	time still grows (just far more slowly than linearly) — so throwing your whole stockpile in at
	once is always at least as time-efficient as doing it in small batches, without making batch
	size irrelevant.

	Refined materials aren't spendable anywhere yet — CraftingRecipes.lua/ModConfig.lua's Cost
	tables would need to start requiring them as inputs for that, which is a deliberately separate,
	larger follow-up. For now this just gives smelting somewhere to go: it accumulates and shows up
	in the Inventory panel's Materials tab (see MainHud.client.lua's renderInvMaterials).
]]

local RefinedOreConfig = {}

-- RefineRatio = how many units of the raw ore it takes to produce ONE unit of the refined
-- material. Common/early ores cost more raw material per refined unit (they're plentiful, so
-- that's fine); rarer ores refine close to 1:1 since you won't have much of them to spare.
RefinedOreConfig.Ores = {
	ScrapIron = {
		RefinedKey = "SteelIngot",
		DisplayName = "Steel Ingot",
		Description = "Scrap Iron, melted down and poured into a clean ingot. Denser and more useful than the raw scrap it came from.",
		RefineRatio = 3,
	},
	CopperWire = {
		RefinedKey = "CopperCoil",
		DisplayName = "Copper Coil",
		Description = "Salvaged wiring stripped, melted, and re-wound into a uniform coil — none of the corrosion or kinks of the raw stuff.",
		RefineRatio = 3,
	},
	SteelPlating = {
		RefinedKey = "HardenedPlate",
		DisplayName = "Hardened Plate",
		Description = "Steel plating re-forged and tempered. Heavier work than Scrap Iron, but the payoff is worth it.",
		RefineRatio = 2,
	},
	GoldContacts = {
		RefinedKey = "GoldBar",
		DisplayName = "Gold Bar",
		Description = "Corroded gold contacts, refined down to a small, dense bar. Nothing wasted.",
		RefineRatio = 2,
	},
	VoidiumShard = {
		RefinedKey = "VoidiumCore",
		DisplayName = "Voidium Core",
		Description = "Whatever a Voidium Shard actually is, refining it doesn't make it any less unsettling to hold. Refines almost 1:1 — there's no fat to trim off something like this.",
		RefineRatio = 1,
	},
}

-- Reverse index (RefinedKey -> that same entry) — the Inventory panel's Materials tab and detail
-- popup show tiles keyed by RefinedKey (icons are per refined material, same ItemIcons convention
-- as everything else — see MainHud.client.lua's getItemIcon), so this is the fast way back to the
-- raw-ore entry's DisplayName/Description/RefineRatio from just the refined key. Built once here
-- rather than making every caller loop over RefinedOreConfig.Ores to find it.
RefinedOreConfig.ByRefinedKey = {}
for oreKey, data in pairs(RefinedOreConfig.Ores) do
	RefinedOreConfig.ByRefinedKey[data.RefinedKey] = {
		OreKey = oreKey,
		DisplayName = data.DisplayName,
		Description = data.Description,
		RefineRatio = data.RefineRatio,
	}
end

-- BaseSeconds = time for the smallest possible batch (quantity == that ore's RefineRatio, i.e.
-- log(RefineRatio) applied below — see ComputeSmeltSeconds). LogSecondsPerOre scales how much
-- extra time bigger batches add — logarithmically, not linearly, so per-ore time keeps dropping
-- as you throw more raw ore into a single batch, but the total batch time still keeps climbing at
-- a real, noticeable pace rather than flattening out almost immediately (a log curve tapers off
-- fast on its own — LogSecondsPerOre = 24, not something smaller like 8, is what keeps a 100+-ore
-- batch meaningfully slower than a 10-ore one instead of "basically instant either way"). That
-- headroom is deliberate: it leaves room for a future "Smelt Speed" gamepass or upgrade to cut
-- this multiplier down later (see SmeltService.lua's StartSmelt handler for the exact hook point —
-- multiply the ComputeSmeltSeconds result there, no change needed to the formula itself) and
-- actually feel like something. TickSeconds is just how often SmeltService's background loop
-- checks for finished jobs, same pattern as AutoMinerConfig.TickSeconds.
RefinedOreConfig.SmeltTime = {
	BaseSeconds = 20,
	LogSecondsPerOre = 24,
	TickSeconds = 2,
}

-- ComputeSmeltSeconds(quantity): quantity is raw ore units fed into the batch (>= 1). Uses an
-- actual math.log — quantity/ComputeSmeltSeconds(quantity) (time per raw ore) strictly decreases
-- as quantity grows, which is the literal ask: "the more you put the less time it is per ore."
-- Shared between server (SmeltService, authoritative) and client (MainHud, for the estimated-time
-- readout shown before a job even starts) so the formula only lives in one place.
function RefinedOreConfig.ComputeSmeltSeconds(quantity: number): number
	quantity = math.max(quantity, 1)
	return RefinedOreConfig.SmeltTime.BaseSeconds + RefinedOreConfig.SmeltTime.LogSecondsPerOre * math.log(quantity)
end

return RefinedOreConfig
