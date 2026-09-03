--[[
	ForgeConfig.lua
	Pure data for the Forge — where weapons are rolled, not flat-crafted. Every weapon type in
	CraftingRecipes.Weapons is still the base stat line (cost, tier, FireRate, BaseDamage), but the
	Forge wraps each roll in a unique instance (see DataService.lua's profile.Weapons) with its own
	Rarity and 0-3 randomly rolled Affixes on top of those base stats. Reforge the same weapon type
	as many times as you can afford it — every roll is a brand new instance, never a shared upgrade
	to one you already own (see DESIGN_NOTES.md's "Forge" section for why: it's what makes rarity
	and Luck mean anything — a guaranteed one-of-each-type crafting system has no room for either).

	The Forge is craft-only — rolling a weapon and equipping/managing one it are two different
	screens now. Owned weapons, equipping, and mod slots all live in the Inventory panel; this
	station's own Weapons tab only ever shows the Luck/Pity status and the roll buttons themselves.

	Luck: two independent sources both push the odds toward better rarities, and they stack —
	ForgeTiers is your literal Forge's permanent upgrade track (same shape as MineShaftConfig
	.SuitTiers — the better your Forge, the luckier every roll on it is), LuckPotion is a one-time
	consumable burned on a single roll. Both just add flat "luck points" — see
	ForgeService.rollRarity for exactly how those points bend the weights below.

	Pity: an unlucky streak still eventually pays off. Pity.Threshold rolls in a row without landing
	Pity.MinRarity or better forces the NEXT roll to be at least that rarity (still randomized among
	everything from MinRarity up, luck-weighted same as any other roll — pity guarantees a floor, it
	doesn't guarantee which tier above that floor you get). Landing MinRarity+ on your own, pity or
	not, resets the counter back to zero — see ForgeService.ForgeWeapon.
]]

local ForgeConfig = {}

-- Order matters here — rollRarity below walks this list low-to-high, so it has to be Common first,
-- Legendary last. ModConfig.Rarities carries the DisplayName/Badge/Color for each of these keys —
-- this file only owns how OFTEN each one comes up, not how it's presented.
ForgeConfig.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

-- Relative weights at zero luck. Common dominates; Legendary is a real event, not a coin flip.
ForgeConfig.BaseWeights = {
	Common = 100,
	Uncommon = 40,
	Rare = 15,
	Epic = 5,
	Legendary = 1,
}

-- How many bonus stat affixes a roll of this rarity gets. Common weapons come out of the Forge
-- with nothing extra beyond the recipe's own base stats — rarity is what buys you affixes at all.
ForgeConfig.AffixCountByRarity = {
	Common = 0,
	Uncommon = 1,
	Rare = 2,
	Epic = 2,
	Legendary = 3,
}

-- Each rolled affix picks one entry here at random and rolls a magnitude between Min and Max
-- (stored as "+X%", e.g. 0.23 = +23%, applied multiplicatively on top of ModConfig's type-level
-- mods — see CombatMath.GetEffectiveWeaponStats). Multiple distinct Keys can land on the same
-- weapon even if they share a Stat (e.g. Sharpened + Overcharged both boost Damage) — ForgeService
-- only dedupes by Key, not by Stat, so stacking two damage affixes is a real, if rare, outcome.
ForgeConfig.AffixPool = {
	{ Key = "Sharpened", Stat = "DamageMultiplier", Label = "Sharpened", Min = 0.05, Max = 0.30 },
	{ Key = "Overcharged", Stat = "DamageMultiplier", Label = "Overcharged", Min = 0.10, Max = 0.45 },
	{ Key = "Lightweight", Stat = "FireRateMultiplier", Label = "Lightweight", Min = 0.05, Max = 0.30 },
	{ Key = "HairTrigger", Stat = "FireRateMultiplier", Label = "Hair-Trigger", Min = 0.10, Max = 0.45 },
}

-- Permanent Forge upgrade track — the literal station gets better, and every roll on it gets
-- luckier as a direct result. Same "sequential tier, index 1 is the free starting tier" shape as
-- MineShaftConfig.SuitTiers/OreConfig.ToolTiers. Bonus is flat luck points, added straight into
-- rollRarity's weight math (see ForgeService.lua) alongside whatever the Luck Potion adds.
ForgeConfig.ForgeTiers = {
	{ Name = "Scrap Forge", Bonus = 0 },
	{ Name = "Reinforced Forge", Bonus = 15 },
	{ Name = "Tempered Forge", Bonus = 35 },
	{ Name = "Masterwork Forge", Bonus = 60 },
}
ForgeConfig.ForgeTierCosts = {
	[2] = { CopperWire = 40, GoldContacts = 10 },
	[3] = { SteelPlating = 50, GoldContacts = 25 },
	[4] = { GoldContacts = 60, VoidiumShard = 5 },
}

-- Consumable, craftable at the Forge (CraftLuckPotion remote). Burned automatically on the very
-- next ForgeWeapon roll once the player opts in client-side — see ForgeService.ForgeWeapon's
-- usePotion parameter. Stacks additively with ForgeTiers' permanent Bonus for that one roll only.
ForgeConfig.LuckPotion = {
	Cost = { GoldContacts = 20, CopperWire = 15 },
	Bonus = 40,
}

-- Pity: guards against a genuinely unlucky run of rolls. See this file's header comment for the
-- exact rule; ForgeService.ForgeWeapon tracks profile.ForgePityCounter and forces the floor once
-- it reaches Threshold.
ForgeConfig.Pity = {
	Threshold = 15,
	MinRarity = "Rare",
}

-- A roll lands in profile.ForgeOutput (the Crucible's output tray), not straight into your
-- inventory — you Collect it or Trash it. Rolling again while the tray is occupied OVERWRITES what
-- is in it, which is the right default: the common case is a junk roll you want to reroll
-- immediately, and taxing that to guard the rare case would be backwards. This is the rarity at
-- which that stops being the right default and the client raises a confirmation first.
--
-- A KEY, not an index, and compared through RarityOrder — never a hardcoded rarity name at the call
-- site. Reordering or inserting a rarity then moves this threshold with it automatically.
--
-- Set it to nil to never confirm; set it to "Common" to confirm on every discard.
ForgeConfig.DiscardConfirmMinRarity = "Epic"

-- Index of a rarity key within RarityOrder (1 = Common ... 5 = Legendary). Lives here rather than
-- in ForgeService because the HUD needs the same comparison — the Crucible decides whether to raise
-- the discard confirmation, and it must reach the same answer the server will.
function ForgeConfig.RarityIndex(rarityKey: string?): number
	for index, key in ipairs(ForgeConfig.RarityOrder) do
		if key == rarityKey then
			return index
		end
	end
	return 1
end

-- Whether discarding a pending output of this rarity should be confirmed first. Both the Crucible
-- (which raises the popup) and ForgeService.ForgeWeapon (which refuses an unconfirmed roll that
-- would discard one) ask this, so a client that lies about the confirm flag can only hurt itself —
-- the same reasoning as the Recall remote's re-checks.
function ForgeConfig.NeedsDiscardConfirm(rarityKey: string?): boolean
	if not rarityKey or not ForgeConfig.DiscardConfirmMinRarity then
		return false
	end
	return ForgeConfig.RarityIndex(rarityKey) >= ForgeConfig.RarityIndex(ForgeConfig.DiscardConfirmMinRarity)
end

-- Total luck points for a roll: your Forge's permanent ForgeTiers bonus, plus the Luck Potion's
-- one-roll bonus if you are burning one.
--
-- SHARED, not server-only, for the same reason Shared/Wallet.lua is: the Crucible prints your luck
-- in its header and draws the odds bar those points produce, and a HUD that computes luck its own
-- way is a HUD that can promise odds the server will not honour.
function ForgeConfig.LuckPoints(profile, usePotion: boolean?): number
	local tierData = ForgeConfig.ForgeTiers[(profile and profile.ForgeTier) or 1]
	return (tierData and tierData.Bonus or 0) + (usePotion and ForgeConfig.LuckPotion.Bonus or 0)
end

-- The weight table a roll of this luck actually uses. Every non-Common tier's weight scales by
-- (1 + luckPoints/100) — Common itself never moves, so more luck just grows the non-Common slice of
-- the pie relative to it. `floorIndex` (default 1) restricts the roll to RarityOrder[floorIndex..],
-- which is how a pity-forced roll guarantees at least Pity.MinRarity.
--
-- Returns the per-rarity weights and their total. ForgeService.rollRarity walks these to pick a
-- rarity; the Crucible normalises them into the percentages on its odds bar. One function, so the
-- bar cannot advertise odds the roll does not use.
function ForgeConfig.RollWeights(luckPoints: number, floorIndex: number?): ({ [string]: number }, number)
	local floor = floorIndex or 1
	local weights = {}
	local total = 0
	for index, rarityKey in ipairs(ForgeConfig.RarityOrder) do
		if index >= floor then
			local base = ForgeConfig.BaseWeights[rarityKey] or 0
			local weight = (rarityKey == "Common") and base or (base * (1 + luckPoints / 100))
			weights[rarityKey] = weight
			total += weight
		end
	end
	return weights, total
end

-- The same weights as fractions of 1, in RarityOrder, for drawing. A rarity below the floor comes
-- back as 0 rather than being omitted, so the bar keeps five segments and a pity-forced roll reads
-- as "these three are the only outcomes now" rather than as a bar that changed shape.
function ForgeConfig.RollChances(luckPoints: number, floorIndex: number?): { number }
	local weights, total = ForgeConfig.RollWeights(luckPoints, floorIndex)
	local chances = {}
	for index, rarityKey in ipairs(ForgeConfig.RarityOrder) do
		chances[index] = total > 0 and (weights[rarityKey] or 0) / total or 0
	end
	return chances
end

return ForgeConfig
