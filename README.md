# Salvage Protocol — starter scaffold

This is a [Rojo](https://rojo.space) project: the source of truth for your scripts lives in
these files, and Rojo syncs them into Roblox Studio live as you (or an AI assistant) edit them
in a normal code editor. It implements the full loop from the design doc end to end — mining,
crafting, deploying robots, and running wave-defense sessions for Scrap/Cores — with clearly
marked placeholders where visuals, real combat, and UI need to be built on top.

See `DESIGN_NOTES.md` for the bigger not-yet-built ideas (mining zone rework, base building/mod
slots, the shop, PvP raiding) and which interim decisions here are deliberate placeholders, not
finished design.

## 1. Set up Rojo (one-time)

1. Install [Rojo](https://rojo.space/docs/v7/getting-started/installation/) — either the VS
   Code extension (easiest) or the standalone CLI.
2. In Roblox Studio, install the **Rojo plugin** from the Creator Store (search "Rojo").
3. Open this folder in VS Code (or your editor of choice).

## 2. Run it

1. Start the Rojo server: in VS Code, `Rojo: Start` from the command palette, or from a
   terminal in this folder, `rojo serve`.
2. In Roblox Studio, open (or create) your place, open the Rojo plugin panel, and click
   **Connect**. Your scripts and the `Remotes` folder will appear in the correct services.
3. Press Play (or Play Solo) to test.

Every time you or an AI assistant edits a `.lua` file here, Studio picks up the change live —
no manual copy-pasting scripts into Studio.

## 3. What's already wired up

- **Mining** — tag any Part or Model in your map with the `OreNode` tag (Studio's Tag Editor,
  `CollectionService`) and give it a child `StringValue` named `OreType` set to one of the
  keys in `OreConfig.lua` (e.g. `ScrapIron`). A ProximityPrompt appears automatically and
  mining Just Works, gated by tool tier and wave-unlock as configured — a rejected attempt now
  always explains itself via a `MineFailed` warning in the Output window instead of just doing
  nothing. Every node **depletes**: it survives `OreConfig.Ores[key].MaxHits` hits, then goes
  empty (dimmed, prompt disabled) for `RespawnSeconds` before coming back — tracked via
  `HitsRemaining`/`Depleted` Attributes that `MiningService.lua` initializes automatically the
  first time a node is ever mined, so this applies to hand-placed nodes too, no Studio edits
  needed. Tool tier — which gates Steel Plating and above — only ever goes up via the
  Workbench's **Tools** tab (`UpgradeTool`, costs in `OreConfig.ToolTierCosts`); there was no
  way to raise it before, which is why those ores were unreachable.
- **Mine shaft (voxel grid)** — `MineShaftService.lua` builds a real 3D grid of mineable blocks
  (`MineShaftConfig.GridWidth` x `GridLength`, 128x128 by default) starting from a Part tagged
  `MineShaftStart`. **This anchor needs genuinely open air underneath it** — put it up on a
  platform, not resting on your map's real ground — because the whole grid is built as ordinary,
  real, solid Parts directly below it; there's no teleporting and no separate hidden area
  involved. Only the top layer (Depth 0) is generated up front, filling the entire footprint —
  that's the quarry floor you walk onto. Every layer after that is generated on demand: mining a
  block checks its 6 face-adjacent neighbors (down/up/+X/-X/+Z/-Z) and spawns a fresh block in any
  that have never been touched before. Since Depth 0 starts completely filled in, mining a
  Depth-0 block only ever reveals the one below it, but once you're a level down, sideways
  neighbors are just as unexplored as the one below — so the mine grows into real connected
  tunnels the deeper you go, not a single one-block shaft per surface cell. Breaking a block just
  leaves ordinary open air, so you naturally fall/step into it under normal gravity — no explicit
  teleport happening anywhere. (Three earlier designs tried teleporting the player around and/or
  modifying real ground geometry, and each broke in its own way — see `DESIGN_NOTES.md` for the
  full history if curious; this version sidesteps all of that by just using real, ordinary space.)

  Most cells roll as plain **Rock filler** (destroys for nothing — it's there so ore feels like
  something you dig for), some roll as an actual **Ore** resource (`MineShaftConfig
  .OreWeightBands`, same "deeper = rarer" idea the old ring zone used), and a few — more often the
  deeper you go — roll as a **Lava pocket**: mine one through and it bursts for real damage
  (`LavaDamage`) instead of a reward, with no warning in its label ahead of time. All three get
  more or less common with depth (`MineShaftConfig.KindWeightBands`) but Rock is floored (30-40%)
  so filler never fully disappears even very deep. Separately, past a depth threshold, ambient
  environmental risk (`MineShaftConfig.HazardBands`) deals periodic damage unless your **Suit
  tier** covers it (Workbench → Suit tab, `UpgradeSuit`, costs in `SuitTierCosts`) — a top-right
  HUD panel shows your current depth and whichever hazard applies there. A **Recall** button
  (bottom action row) appears once you're a level or more down and respawns you at full health —
  at your own base plot if you have one (see **Base plots** below), otherwise a normal
  SpawnLocation — there's no climb-out mechanic yet, so this is the only way back up on demand.
  Blocks are **click-based** (`MineShaftController.client.lua`, a `ClickDetector` +
  hover `Highlight`, same interaction model the Expedition nodes use), not the hold-style
  `ProximityPrompt` ore mining still uses — a prompt attached to a block directly under the
  player's own feet routinely fails its default line-of-sight check and just never triggers, so
  click-based is what actually works for something you stand on top of. Blocks don't carry their
  own permanent label — with up to ~16,000+ live at once, `MineShaftController.client.lua` shows
  ONE reusable hover label instead, re-targeted to whichever block you're actually looking at.
  Every cell's state is one shared, server-tracked value, same multiplayer-synced requirement the
  ring zone had — if one player opens up a tunnel, everyone sees it already open. **This
  replaces** `ResourceZoneService.lua`/`ResourceZoneConfig.lua` (the old scattered-ring layout) —
  those files are still on disk for reference but are no longer required by `Main.server.lua`;
  see `DESIGN_NOTES.md` for why. See `MineShaftConfig.lua` to retune grid size, hits, kind/ore/
  hazard weighting, or suit costs — `GridWidth`/`GridLength` is the first thing to shrink if
  16,000+ initial blocks turns out to be too much for a given map.
- **Base plots** — every player needs somewhere the Workbench and Start Defense will actually
  work (see below), which means Studio needs at least one Part tagged `Plot` (`PlotConfig.Tag`)
  before ANYTHING craftable works at all. This is a two-piece system: **PlotService.lua** owns
  WHERE a player's base lives, **BaseService.lua** owns WHAT gets physically built there.

  A `Plot`-tagged Part can be anything, anywhere — `PlotService` forces it invisible, non-
  collidable, and non-queryable the instant it sees the tag, no matter how you built it, because
  it's only ever used as an anchor CFrame, never actually stood on. On join, `PlotService`
  randomly assigns one unclaimed tagged Part to the player and fires a `PlotAssigned` signal;
  `BaseService` picks that up and clones a Model from a `BaseTemplates` folder in
  `ReplicatedStorage` onto that same CFrame — matching whichever `BaseConfig.Tiers` entry the
  player's saved `profile.BaseTier` points at (always `1` for now — no purchase flow exists yet,
  see `DESIGN_NOTES.md`'s "Base building/tiers" bullet). **If you haven't built a `BaseTier1`
  Model yet**, `BaseService` clones a single plain gray placeholder floor instead (and warns in
  Output) so nobody falls into the void while you're still building real base art — swap it out
  by adding `ReplicatedStorage/BaseTemplates/BaseTier1` (a Model whose intended floor sits at
  local Y=0, e.g. its `PrimaryPart` is the floor piece) whenever you're ready.

  The character is repositioned onto its plot's anchor every time it spawns, not just the first
  time — Recall, End Expedition, and the mine's full-reset eviction all already call
  `player:LoadCharacter()`, so this happens for free everywhere those already fire, no extra code
  needed in any of the three. Plots free back to the pool when a player leaves. Add more `Plot`
  Parts to support more concurrent players — if none are free when someone joins, they just don't
  get a base yet (a warning prints server-side; nothing crashes).
- **Base stations** — a second, more specific gate layer inside your base plot: several Workbench
  actions now also require standing near a particular physical prop, not just anywhere in the
  plot. Tag a Part or Model `Station` (`StationConfig.Tag`) and give it a child `StringValue`
  named `StationType` set to one of three keys: `Crafting` (a **Workbench** prop — gates Tools,
  Auto-Miner, and Suit upgrades), `Welding` (a **Welding Station** prop — gates Robots and Mods),
  or `Forge` (gates Weapons and Smelting — every weapon in the game is rolled here now, see "Forge"
  below, and raw ore gets refined here too, see "Ore Smelting" below).
  There's no standalone "Workbench" button anymore — clicking a `Crafting`/`Welding`/`Forge`
  station in-world is the ONLY way to open the menu, and it opens scoped to just that station's own
  tabs (`StationConfig.Types[type].Tabs`) rather than every tab: a `Welding` station's menu only
  ever shows Robots/Mods, a `Forge` station's only ever shows Weapons, a `Crafting` station's only
  ever shows Tools/Auto-Miner/Suit. On top
  of that, the actual craft/upgrade/deploy/equip action still gets rejected server-side too
  (`StationService.IsPlayerNearStation`, `StationConfig.InteractDistance` = 12 studs) if you try
  it while not near the right station, with a clear "You need to be at your Workbench/Welding
  Station to do that" reason — the client-side tab restriction is a UX improvement on top of that
  server check, not a replacement for it. Place as many of each type as you like, anywhere inside
  your `PlotConfig.FootprintHalfSize` box. Once a station is built as part of a real per-player
  `BaseTemplates` Model (see "Base plots" above), it also only works for its owner —
  `BaseService` stamps an `OwnerUserId` attribute on every `Station`-tagged descendant of a
  player's cloned base, so nobody can walk into someone else's base and use their gear. A loose
  `Station` block placed directly in the world (not part of any base Model — i.e. what
  placeholder-block testing looks like right now) has no owner and stays open to everyone.
- **Crafting** — call the `CraftItem` RemoteFunction from a UI button with a tree name
  (`"Robots"` or `"Mods"` — **not** `"Weapons"` anymore, see "Forge" below) and a recipe key from
  `CraftingRecipes.lua`/`ModConfig.lua`. Cost is validated and deducted server-side. **Only works
  while standing at your own base plot, near the right station** — see `PlotService
  .IsPlayerInOwnPlot` and `StationService.IsPlayerNearStation`, which every Workbench/Forge remote
  (`CraftItem`, `DeployRobot`, `EquipMod`, `EquipWeapon`, `ForgeWeapon`, `CraftLuckPotion`,
  `UpgradeForgeTier`, `StartSmelt`, `UpgradeTool`, `UpgradeSuit`, `CraftAutoMiner`) and `StartWave` (plot only,
  no station needed) check first, rejecting with a clear reason if you're not.
- **Forge (weapon rolling + rarity + Luck + Pity)** — every weapon in the game is Forged, not
  flat-crafted: click the **Forge** station's Weapons tab, pick a weapon type, and hit "Forge" to
  spend that recipe's normal `CraftingRecipes.Weapons[key].Cost` and mint a brand-new unique
  instance (`profile.Weapons`, `{ Id, WeaponKey, Rarity, Affixes }`) — rolling the same type twice
  gives you two independent weapons, never a shared upgrade. Rarity (`ModConfig.Rarities` — Common
  through Legendary) is weighted-random (`ForgeConfig.BaseWeights`/`ForgeService.rollRarity`), and
  higher rarities roll 1-3 bonus stat affixes (`ForgeConfig.AffixPool` — flat +Damage or
  +Fire-Rate percentages) on top of the recipe's base stats. **This tab is craft-only** — it shows
  your Forge-tier upgrade row, a Luck Potion craft row, a "last result" readout, and one Forge
  button per weapon type, nothing more; there are no Equip buttons or mod slots here (they used to
  sit right below each owned weapon on this tab, which just duplicated the Inventory panel and made
  "click Forge" and "click Equip" easy to mix up). Owning, equipping, and mod-slotting a Forged
  weapon all happen exclusively in the **Inventory panel** now (see below).

  **Luck** pushes the odds toward better rarities two ways that stack: your Forge's own permanent
  `ForgeTier` upgrade track (Forge's Weapons tab, same sequential-tier shape as Tool/Suit tier,
  costed by `ForgeConfig.ForgeTierCosts` — there's no separate abstract "Luck" stat, a better Forge
  just rolls luckier) and a consumable **Luck Potion** (craftable at the Forge,
  `ForgeConfig.LuckPotion`, burned on one roll). Whether the next roll spends a Potion is armed by
  a **square button** (`potionButton`, icon via `ReplicatedStorage.ItemIcons.LuckPotion` same as
  everything else, badge shows how many you own) docked directly under the Forge menu — not a row
  buried inside its tab, but not a permanent HUD fixture either. **Pity** backstops a genuinely
  unlucky run: `ForgeConfig.Pity.Threshold` (15) rolls in a row without landing `Pity.MinRarity`
  (Rare) or better forces the very next roll to at least that rarity — still luck-weighted among
  Rare-and-up, not a flat guarantee of exactly Rare. Shown the same way: a **pity progress bar**
  (`pityBarFrame`) reading `Forge Pity: N / 15 (Rare+)` with a filling bar, docked right beside the
  Potion button, filling the rest of the row out to the Forge menu's own right edge. **Both widgets
  are Forge-only** — hidden the rest of the time, and hidden again for the Workbench/Welding
  Station's own menus (`setForgeWidgetsVisible`, toggled from `openStationMenu`/
  `craftCloseButton`) — they only ever appear docked under the Forge's own Weapons tab, resetting
  to empty the moment any roll, forced or not, lands Rare+. The bottom action row
  (Inventory/Start Defense/etc.) hides for the same window, since on shorter viewports the docked
  row sits low enough to overlap it otherwise.

  Pick which owned instance actually counts for combat DPS with `EquipWeapon`
  (`profile.EquippedWeaponId`, called from the Inventory panel) — same "explicit choice wins, else
  auto-pick the highest-DPS owned instance" fallback the old type-level `EquipWeapon` had, just
  re-pointed at instances. **Existing saves migrate automatically**: any weapons owned under the
  old flat system before this update convert into Common-rarity, zero-affix instances the first
  time that player's save loads (`DataService.migrateLegacyWeapons`) — nothing is lost, just
  upgraded into the new shape. See `DESIGN_NOTES.md`'s "Forge / weapon rarity, Luck & Pity" bullet
  for the full implementation writeup.
- **Ore Smelting** — the Forge's other job: its **Smelting** tab turns raw ore into refined
  material, one batch at a time. The tab is one square panel (`RefinedOreConfig.lua`) with three
  states: click the centered icon to open a popup grid into your raw ore inventory (only ores
  you own at least one legal batch of are listed), pick one and a quantity readout, a "Reset," and
  four bulk-add buttons (`+1`/`+10`/`+100`/`MAX` — each ADDS BATCHES, i.e. `RefineRatio`-sized
  steps: 3:1 for Scrap Iron/Copper Wire, 2:1 for Steel Plating/Gold Contacts, 1:1 for Voidium
  Shard, so the quantity is always a legal multiple) plus a "Smelt" button appear, and once you hit
  it a live countdown/progress bar takes over until the batch finishes. Batch time is
  `RefinedOreConfig.ComputeSmeltSeconds(quantity) = BaseSeconds + LogSecondsPerOre * math.log
  (quantity)` — a real logarithm, so bigger batches cost less time per raw ore, not just
  proportionally more total time (but still climb at a real pace, not flatten out almost
  immediately — see `DESIGN_NOTES.md` for the exact numbers, and `SmeltService.lua` for where a
  future Smelt Speed gamepass/upgrade would hook in).
  One job at a time per player (`profile.SmeltJob`, cleared by `SmeltService.lua`'s background
  loop the moment `FinishTime` passes — works the same whether you're online or not when it
  finishes), granting `profile.RefinedOreCounts[RefinedKey]`. Refined materials show up in the
  Inventory panel's Materials tab once you own at least one, but aren't spendable on anything yet —
  wiring them into `CraftingRecipes`/`ModConfig` costs is a deliberately separate follow-up. See
  `DESIGN_NOTES.md`'s "Ore smelting" bullet for the full implementation writeup, including which
  numbers (RefineRatios, refined-material names, the time-formula constants) were picked without a
  playtest and are worth reconsidering.
- **Deploying robots** — call `DeployRobot` with a robot key you already own; `UndeployRobot`
  (same signature) pulls one matching instance back off defense duty. `DeployRobot` caps at how
  many of that key you actually own, not just "own at least one," so the same single owned robot
  can't be deployed into every free slot at once.
- **Weapon/robot mods** — Welding Station → Mods tab (or the Inventory panel's Mods tab) to craft
  permanent mod unlocks (`ModConfig.lua`, 3 slots per weapon/robot type — see `DESIGN_NOTES.md`'s
  "Base" section for the full design and why mods apply per item type rather than per robot/weapon
  instance). For a Forged weapon, mod slots key off its `WeaponKey` (type), not its unique instance
  Id — equipping a mod on "Pipe Pistol" affects every Pipe Pistol instance you own at once, same
  simplified design robots always had. Owned weapon/robot rows grow 3 slot buttons — click one to
  open a picker popup listing every mod you currently own (each tagged with its rarity —
  everything's `Common` for now, see `ModConfig.Rarities`) plus a "None" option to clear the slot.
  Equip via the `EquipMod` RemoteFunction (`tree, itemKey, slotIndex, modKey`) — gated to the Forge
  for the Weapons tree, the Welding Station for Robots. `CombatMath.GetEffectiveWeaponStats`/
  `GetEffectiveStats` applies whatever's equipped when computing DPS.
- **Inventory panel** — a second, always-available panel (`inventoryButton` in the bottom action
  row) for viewing and managing everything you own, filtered into four tabs: **Weapons**,
  **Robots**, **Mods**, **Materials**. Unlike the Workbench, it's NOT gated to any station or
  plot — you can open it and browse from anywhere, since it's just a window onto your save data.
  Presented as an icon grid — one square tile per item/material, not rows — and clicking a tile
  opens a detail panel beside the Inventory with a bigger image, description, stats, and (for
  Weapons/Robots) an action button and mod slots. The Weapons tab shows every Forged instance you
  own (rarity badge in the tile corner, full affix summary in the detail panel) and lets you pick
  which single instance actually counts for combat DPS (`EquipWeapon` RemoteFunction,
  `profile.EquippedWeaponId`) — leave nothing equipped and it falls back to auto-picking the
  highest-DPS owned instance. The Robots tab shows owned-vs-deployed counts per robot and toggles
  Deploy/Undeploy. The Mods tab lists everything you own with its rarity. The Materials tab shows
  Scrap, Cores, every ore/material count, and any refined materials you've smelted at least one of
  (see "Ore Smelting" above) — this is where that information moved to once the top-left readout
  got trimmed down to just Scrap/Cores/Energy (see "Testing the loop" below).
  Equip/Deploy/Undeploy actions from this panel still only actually work while standing at the
  right station (Forge for weapons, Welding for robots) — same server-side gate as everywhere
  else, browsing is just unrestricted.

  **Icons** (optional — everything works without them, just shows a plain colored tile with the
  item's name as text): add an `ImageLabel`, `ImageButton`, or `Decal` inside
  `ReplicatedStorage.ItemIcons` (an empty Folder, already in `default.project.json`), named EXACTLY
  like the item's key (e.g. `PipePistol`, `ScrapIron`, `SpeedCoil`, or the literal `Scrap`/`Cores`
  for the two currencies), and set its Image/Texture property via Studio's normal asset picker.
  Only that one property is read — nothing else about the instance matters, so any leftover
  default size/position on it is harmless. **Descriptions** live in code: `CraftingRecipes.lua`'s
  Weapons/Robots entries and `OreConfig.lua`'s Ores entries each have a `Description` field
  (`ModConfig.lua`'s mods already did) — edit those directly to change the flavor text shown in
  the detail panel.
- **Auto-Miner** — `AutoMinerService.lua` handles a one-time-craftable "Mini Particle
  Accelerator" (Workbench → Auto-Miner tab, cost in `AutoMinerConfig.lua`) that passively grants
  a small amount of Scrap Iron on a timer for every player who's built one, whether they're
  actively playing or not. Deliberately modest — it's meant to supplement mining, not replace
  the reason to do it — and the pre-scaffolded `AutoMiner` game pass (`ShopConfig.GamePasses`)
  simply doubles the tick rate rather than making it a must-buy. MVP-scoped as pure data, same
  as wave defense: no physical structure to place in the world yet.
- **Wave defense** — fire the `StartWave` RemoteEvent to begin a run; listen to `WaveUpdate`
  on the client to drive your HUD. **This combat is a headless simulation** (your total DPS
  vs. an enemy HP pool, ticking once per second) so the whole loop is playable before you've
  built any enemy models or gun-firing code — see the big comment at the top of
  `WaveService.lua` for exactly how to swap in real spawned enemies later.
- **Data & saving** — every player's Scrap, Cores, ore counts, crafted items, and highest wave
  autosave every two minutes and on leave. Swap `DataService.lua` for
  [ProfileService](https://github.com/MadStudioRoblox/ProfileService) before you have real
  concurrent players — this hand-rolled version doesn't session-lock across servers.
- **Monetization** — `ShopService.lua` handles `ProcessReceipt` for developer products and
  syncs game-pass ownership. **You must create the actual Game Passes and Developer Products**
  for your experience in the Creator Dashboard and paste their numeric ids into
  `ShopConfig.lua` — everything is `Id = 0` (disabled) until you do.
- **Expedition nodes** — `NodeService.lua` handles three node types placed out in the open
  world, separate from home-base defense: Heal Stations, the Shop (the actual sink for Scrap/
  Cores currency), and Combat Outposts (a single fight for loot, where you take real damage
  every second it isn't won — see `NodeConfig.lua` for the three tiers; expedition Combat tier
  is rolled per row, not fixed — see the queue bullet below). Setup is identical in spirit to
  ore nodes: tag a Part `Node`, add a `StringValue` named `NodeType` set to `"Heal"`, `"Shop"`,
  or `"Combat"`. Combat nodes additionally need a `NumberValue` named `Tier` (1, 2, or 3)
  matching `NodeConfig.CombatTiers`.
- **Raid Energy** — `RaidEnergyService.lua` charges `RaidEnergyConfig.EnergyPerExpedition` (1)
  Energy the moment you pull the Expedition lever and a run actually starts (see
  `ExpeditionService.lua`'s `RegenerateExpedition` handler) — NOT per Combat node inside that
  run, so a queue with three Combat rows still only costs 1 Energy total, not 3. Charged on
  start, not on clearing the run, so bailing out partway still costs you something. Energy caps
  at `MaxEnergy` (5) and regenerates 1 every `RegenIntervalSeconds` (4 min) while you're
  connected — it does not catch up for time spent offline, same deliberate simplification as the
  Auto-Miner. A rare "Energy Drink" find (`EnergyDrinkFindChance`, 3% per successful mining hit —
  intentionally uncommon) grants a burst of bonus Energy that CAN push you above the normal cap,
  up to `OverflowCap` (8); that overflow just drains back down as you spend it rather than being
  topped up further by regen. Out of Energy shows as a `NoEnergy` warning in Output instead of
  the lever silently doing nothing. See `RaidEnergyConfig.lua` to retune the cost, cap, regen
  speed, or drink rarity.
- **Expedition queue** — `ExpeditionService.lua` keeps 5–8 node rows sitting at fixed slots out
  from a Part you tag `ExpeditionStart` (its facing direction is the lane's direction) — the
  nodes come to the player, not the other way around, but only in response to the player:
  nothing moves on a timer. **Nothing spawns until a player pulls the lever** (tag a second Part
  `ExpeditionLever`) — that's what starts a run; the queue sits empty/inactive at server start
  instead of auto-populating. A **Return to Base** button appears in the HUD's bottom action row
  whenever a run is active, and ends it early: heals you to full and wipes the queue back to
  inactive (rewards are already banked the instant each node resolves, so there's nothing to
  lose by leaving). Both the lever-to-start and button-to-end are explicit placeholders for a
  planned teleport-to-a-separate-area flow — see `DESIGN_NOTES.md`. NOTE: this is still the one
  shared queue every player sees, so ending it via the button wipes it for everyone on it, not
  just you. Clicking it mid-raid cancels that raid cleanly too (no failure penalty, the raid loop
  now checks whether its node still exists rather than ticking on forever against a node that's
  already gone — see `NodeService.lua`'s `runRaid`). Every 3rd row is a fork — two nodes side by side — and engaging with
  either one (a heal, a purchase, or a cleared raid) destroys both it and its sibling; a plain
  row holds one node. Only the row closest to the anchor (slot 1) is ever clickable (click, not
  hold — see below); the moment it's cleared, every other row animates one slot closer and a
  fresh row fills the vacated back slot. Combat/Heal/Shop nodes spawned this way are all
  one-time — each is destroyed the moment it's used, unlike the permanent hand-placed ones,
  which persist. Combat tier for each row is a **weighted roll that shifts with depth**
  (`ExpeditionConfig.TierWeightBands`/`GetTierForSlot`) — mostly Tier 1 for the first few rows,
  Tier 2 showing up here and there after that, and the harder tiers taking over the further the
  queue has spawned — rather than a hard cutoff, so difficulty ramps gradually instead of
  spiking. Node type (Combat/Shop/Heal) is a weighted roll too, but the live queue is never
  allowed to have fewer than `ExpeditionConfig.MinCombatNodes` Combat nodes active — every time a
  new row is about to spawn, if the current count is under that floor, the roll is skipped and
  Combat is forced instead (still capped by `MaxCombatNodes`), so a stretch of nothing-but-
  Shop/Heal can't happen. Raise `MinCombatNodes` if you want Combat showing up even more often.
  See `ExpeditionConfig.lua` to retune queue size, shift-animation speed, fork spacing, the
  Combat/Shop/Heal weighting, the tier-weight bands, or the min/max Combat node counts.
- **Node interaction is click-based** — Heal/Shop/Combat nodes use a `ClickDetector`
  (`MaxActivationDistance = 50`), not the hold-style `ProximityPrompt` that ore mining and the
  Expedition lever still use. Left-click a node in range to use it; a thin outline highlights on
  hover so it's clear what's interactive. Only the current frontmost row (slot 1) is usable —
  the server always enforces this (`ExpeditionService.CanAccessSlot`), and the client also
  checks it before opening any node UI at all: `ExpeditionService.lua` replicates which row is
  frontmost via a `CurrentSlotId` Attribute on the `Expedition` folder (Attributes replicate to
  clients automatically, no RemoteEvent needed), and `MainHud.client.lua`'s
  `isNodeCurrentlyAccessible()` compares a clicked node's `SlotIndex` against it — so a node
  further back in the queue (which can still be within the 50-stud click range) refuses to open
  client-side instead of opening a Shop/Heal panel for something you can't actually use yet.
- **Mid-raid lockout** — while a raid is in progress, that player can't Heal, Shop, or Skip
  *anything* (not just the node they're raiding) until it resolves — closes an exploit where a
  fork's other option shares the same row/slot as the node being raided, so without this a
  player could dodge a losing fight by using or skipping the sibling out from under it.
- **Skip** — any expedition node can be abandoned without engaging it (e.g. a Shop you can't
  afford anything at) via the `SkipNode` remote; the Shop panel exposes a "Skip" button for it.
  Skipping a fork option destroys it and its sibling and advances the queue exactly like using
  it would, just with no reward. Blocked during an active raid for the same reason as above.
- **Admin dev shortcuts** — `AdminConfig.lua` auto-detects the place's owner (via
  `game.CreatorId`, works automatically in Studio when you're testing as yourself; add your
  UserId to `AdminUserIds` too if the game ends up owned by a Group instead of your personal
  account) and lets that player instantly win any Combat raid — no gear check, no cooldown, no
  Energy cost, full loot immediately. Purely a testing aid so you can blow past combat while
  working on everything downstream of it; not something a normal player ever sees. Since this
  is otherwise always-on, type **`/admin off`** in the in-game chat to test what a normal player
  actually experiences (Energy costs, real timed combat) — `/admin on` re-enables it, plain
  `/admin` toggles. Session-only (`AdminService.lua`), resets to the normal auto-detected value
  on rejoin. Silently ignored for anyone who isn't already an admin.

## 4. Testing the loop (debug HUD)

`MainHud.client.lua` builds a plain, undecorated HUD in code — a trimmed currency readout
(Scrap/Cores/Energy only), a Workbench panel (opens only from a physical station), an Inventory
panel (opens from anywhere — equip/deploy/undeploy your gear, see everything you own including
raw materials), and a Start Defense button with a live wave/HP bar. It exists so the loop is
actually visible before any real art or UI design happens. To test end to end:

1. Place any Part somewhere in your map (any size — it'll be forced invisible/non-collidable
   automatically) and tag it `Plot` (Studio's Tag Editor, top ribbon under **Model**, or via
   `CollectionService`). This is required before anything else below works — **without a tagged
   `Plot` Part, the Workbench and Start Defense will refuse to do anything**, since both now only
   work while you're standing at your own base. Press Play: check the Output window for a
   `[PlotService]` warning if no plot was available, and a `[BaseService]` warning telling you no
   `BaseTier1` Model was found yet — that's expected until you build one, you should still land
   on a plain gray placeholder floor at the plot's location the moment you spawn, not fall
   through into nothing. (Optional: build a Model under `ReplicatedStorage/BaseTemplates` named
   `BaseTier1`, floor at local Y=0, to replace the placeholder with something real — see the
   **Base plots** bullet above.)
2. Inside your base's footprint (within `PlotConfig.FootprintHalfSize` of the `Plot` Part), place
   three more Parts. Tag each `Station` and give it a child `StringValue` named `StationType` set
   to `Crafting`, `Welding`, and `Forge` respectively. These are your **Workbench**, **Welding
   Station**, and **Forge** props — any size/shape works, they don't need to look like anything
   yet.
3. Place a Part in the workspace, tag it `OreNode` (Studio's Tag Editor, top ribbon under
   **Model** or via `CollectionService`), and add a child `StringValue` named `OreType` with
   value `ScrapIron`.
4. Play, walk up to it, hold the ProximityPrompt to mine — the Scrap/ore count updates live.
   (Mining ordinary ore nodes works anywhere on the map, not just at your base.)
5. Click your `Crafting`-tagged Station — the menu should open titled **Workbench**, showing only
   the **Tools** / **Auto-Miner** / **Suit** tabs (no Weapons/Robots/Mods at all — there's no
   general Workbench button anymore, so this is the only way in), landing on **Tools**, and
   hovering the station should show its outline highlight. Close it with the **X** in the top
   corner, then click your `Welding` Station instead — the menu should reopen titled **Welding
   Station**, this time showing only Robots/Mods, landing on **Robots**. Craft a Scrapbot from
   there — it should succeed. Now walk away from the station (but stay inside your plot) and try
   crafting again from the same still-open menu — it should fail with a "You need to be at your
   Welding Station to do that" warning in Output. Walk back next to it and confirm it works again.
   Then walk well outside your `Plot` Part's footprint entirely and try once more — this time it
   should fail with "You need to be at your own base to do that" instead (the broader plot check,
   checked first).
6. Before opening any station, confirm neither the Pity bar nor the Potion button is visible
   anywhere on screen — they're Forge-only now. Click your `Crafting` Workbench or `Welding`
   Station and confirm they still don't appear (only the Forge shows them). Click your
   `Forge`-tagged Station — the menu should open titled **Forge**, and the moment it does, a small
   **Forge Pity** bar (`Forge Pity: 0 / 15 (Rare+)`, empty fill) and a 64x64 square **Luck Potion**
   button (plain "Luck Potion" text and a `0` badge, since you have none yet and haven't added an
   icon) should appear docked in a row directly under the Forge window — the Potion button flush
   with its left edge, the Pity bar filling the rest of the row out to its right edge. The
   **Weapons** tab itself shows only a Forge-tier upgrade row, a Luck Potion craft row, and one
   **Forge** row per weapon type — no owned-weapon rows, Equip buttons, Pity row, or Potion toggle
   inside it, those live in the docked row below the window now. Click **Forge** on Pipe Pistol —
   it should spend the recipe cost, the Pity bar should tick to `1 / 15` with its fill nudging
   forward, and a **Last Forged: [Rarity] Pipe Pistol** row should appear inside the menu showing
   an affix summary (most rolls will say "No bonus affixes" — Common has none by design, see
   `ForgeConfig.AffixCountByRarity`). Craft a Luck Potion from the row above (costs Copper Wire +
   Gold Contacts) and confirm the Potion button's badge updates to `1`; click the Potion button
   itself and confirm it highlights (armed); Forge another weapon and confirm the badge drops back
   to `0` and the button un-highlights, since the toggle is one-shot. Forge about 15 more (any
   type, Potion armed or not) without landing Rare or better and confirm the roll that hits the
   threshold is guaranteed at least Rare (the Pity bar should snap back to empty on that roll, and
   every roll that naturally lands Rare+ before then should already reset it early). While the
   Forge is open, confirm the bottom **Inventory**/**Start Defense** row is gone (it would
   otherwise sit under/behind the docked Pity bar and Potion button on shorter windows). Close the
   Forge with the **X** and confirm the Pity bar and Potion button disappear immediately AND the
   Inventory/Start Defense row comes right back. Then click your Scrapbot's row (while near the
   Welding Station) to **Deploy** it.
7. While still at the **Forge**, click its **Smelting** tab — a square panel should appear showing
   a centered clickable icon (plain "Select\nOre" placeholder text until you add an icon) and the
   prompt "Select Ore to Smelt". Click it — a popup should open titled **Select Ore**, showing a
   grid tile for every raw ore you own at least one full batch of (e.g. 3+ Scrap Iron, since it
   refines 3:1). Pick **Scrap Iron** — the popup closes and the square panel now shows "Scrap Iron
   (owned N)", a `3 ore` readout with a small **Reset** button beside it, a row of **+1**/**+10**/
   **+100**/**MAX** buttons, an estimated output/time readout (`-> 1 Steel Ingot · 0:46`), and a
   **Smelt** button that wasn't there before you picked an ore. Click **+10** and confirm the
   quantity jumps by 10 BATCHES (30 raw ore, since Scrap Iron refines 3:1), not by 10 raw ore; click
   **MAX** and confirm it jumps straight to the largest multiple of 3 you can afford without going
   over; click **Reset** and confirm it drops back to the smallest legal batch (3). Confirm the "->
   N Steel Ingot" count and estimated time keep pace with whichever quantity you land on, and that
   the estimated time grows much more slowly than the quantity does (log, not linear — compare the
   estimate at quantity 3 vs. a much bigger one via **+100**/**MAX** if you have that much ore).
   Click **Smelt** — the stepper/buttons should be replaced immediately by a countdown ("Ready in
   M:SS") and a filling
   progress bar, and your Scrap Iron count (Materials tab) should already be down by the amount you
   fed in. Try clicking the Smelting tab's icon while a job is running — nothing should let you
   start a second one (there's no picker to reopen; the panel is showing the countdown, not the
   picker state). Wait for it to finish (or reduce `RefinedOreConfig.SmeltTime.BaseSeconds`
   temporarily to speed up testing) — the panel should flip back to the "Select Ore to Smelt" icon
   on its own within a couple seconds of hitting zero (the background loop ticks every
   `SmeltTime.TickSeconds`, not instantly), and the Inventory panel's Materials tab should now show
   a new **Steel Ingot** tile with the refined count. Close the Forge and reopen it on the
   **Smelting** tab again to confirm the panel remembers there's nothing in progress (it should, not
   get stuck showing a stale state).
8. Click **Start Defense** — the wave panel appears and the objective/enemy bars move as the
   simulated combat resolves (see the big comment in `WaveService.lua` for what this is
   standing in for). This one only needs you inside your plot generally, not near a specific
   station.
9. Place three more Parts and tag one each `Node` with `NodeType` = `Heal`, `Shop`, and
   `Combat` (give the Combat one a `Tier` NumberValue set to `1`). Left-click the Combat node
   (within 50 studs) to raid it — this spends 1 Energy (top-left readout, starts full at 5/5) —
   the raid panel (bottom-right) shows enemy HP and your own HP draining together. Clear it,
   then click the Shop node and spend the Scrap/ore you've earned; click the Heal node any time
   your HP is low. Raid a 6th time with Energy at 0 and you should get a "Not enough Energy"
   warning in Output instead of the raid starting. (If you're testing as the place's owner, raids
   resolve as an instant win with no Energy spent — see "Admin dev shortcuts" above. Add a
   teammate's UserId to `AdminConfig.AdminUserIds` if you want them to see normal combat while
   you test as admin, or vice versa.)
10. Place one more Part near your base, tag it `ExpeditionStart` (whichever way its front face
   points is the lane direction), and tag a second Part near it `ExpeditionLever`. Press Play —
   the lane area should be **empty** at first, nothing spawns on its own anymore. Hold the
   lever's prompt: 5–8 colored, labeled node rows should now appear at fixed slots along the
   lane (orange = Combat, blue = Shop, green = Heal), with a **pair** of nodes side by side every
   3rd row (a fork), and a **Return to Base** button should appear in the HUD's bottom action
   row. They should sit still — nothing moves until you act. Only the nearest row (slot 1) is
   clickable — try clicking a row further back and you'll get a "Locked" warning in Output
   instead of it working. Click one option of a fork and its sibling disappears immediately;
   either way, once slot 1 is resolved, every other row animates one slot closer and a brand new
   row fills the back slot. Click **Return to Base** mid-run (not mid-raid): you should heal to
   full, the queue should wipe back to empty with nothing left behind, and the button should
   disappear again — pull the lever a few times in a row and confirm the node count stays
   consistent instead of growing each time. Then start a Combat raid (`/admin off` first if
   you're testing as owner, so it actually takes time) and click **Return to Base** WHILE it's
   running: the raid panel should close immediately with no failure message, instead of
   continuing to tick/damage you in the background. The same `ExpeditionStart` Part also anchors
   the resource zone (next step) and the distance fog.
11. Place one more Part **up on a platform with genuinely open air underneath it** (not resting on
   your map's real ground — the whole grid gets built as real solid Parts directly below this, so
   it needs real clear space to build into), tag it `MineShaftStart`. Press Play — check the
   Output window for `[MineShaftService] populated 16384/16384 Depth-0 blocks` (generation is
   spread across a few frames, so this may take a moment to print). You should see one big
   128x128-cell rock floor with a low guard rail around its edge, colored blocks scattered across
   it (mostly grey Rock, some ore-colored blocks, and the occasional glowing orange "??? "block —
   that one's a Lava pocket, no warning which one until you break it). **Hover** over the block
   you're standing on — a thin outline highlights it and a floating label shows its kind/depth/hit
   counter (this is ONE reusable label that follows your cursor, not a permanent tag on every
   block) — then **click** it (click-based, not the hold-style ProximityPrompt ore mining still
   uses, since a prompt attached to a block directly under the player's own feet routinely fails
   its line-of-sight check and never triggers). It takes several hits — watch the hover label's
   hit counter count down — and on the final hit it's destroyed and you should naturally fall
   straight through into a freshly-spawned block one level (`CellSize`, 6 studs) below — ordinary
   gravity, no teleport. Keep digging straight down a few more levels: confirm ore names show up
   and get rarer with depth (`MineShaftConfig.OreWeightBands`), that a `MineFailed` warning
   appears in Output if you hit ore needing a Tool Tier you don't have yet, and that mining a
   "???" block deals a damage burst instead of granting anything (check your HP). Once you're a
   couple levels down, try mining **sideways** instead of straight down — confirm a new block
   appears in that direction too (this only works below Depth 0, since Depth 0 starts completely
   filled in — see `DESIGN_NOTES.md`). Dig to depth 6 or deeper without upgrading your Suit and
   you should also start taking separate periodic damage from the ambient hazard — the top-right
   HUD panel should show your current depth and a red hazard warning (e.g. "Heat — need Thermal
   Liner"); Recall or walk back to your base, open **Workbench → Suit** near your `Crafting`
   Station and upgrade, and the same depth should stop damaging you and
   the panel should turn green. Once you're a level or more down, a **Recall** button should
   appear in the bottom action row — click it and confirm you respawn back at your base plot at
   full health. Dig a tunnel somewhere else on the grid and confirm it's shared server-side (have a
   second player, or a second Studio test server, check the same spot and confirm they see it
   already open). (NOTE: this replaces the old scattered-ring zone — `ResourceZoneService.lua` no
   longer runs; see `DESIGN_NOTES.md`.)
12. Open **Workbench → Auto-Miner** (near your `Crafting` Station) and click **Build** (costs
    Scrap Iron + Copper Wire). Once built, the row switches to showing the passive rate (e.g.
    `+3 Scrap Iron every 60s`); wait a tick or two and confirm your Scrap Iron count ticks up on
    its own, whether or not you're actively mining.
13. Open **Workbench → Mods** (near your `Welding` Station) and craft a mod (e.g. Speed Coil,
    costs Copper Wire). Forge a Pipe Pistol at the **Forge** if you haven't already, and confirm
    its row further down the Forge's Weapons tab now shows 3 slot buttons underneath. Click a
    slot — a **popup should open** listing every mod you currently own (each prefixed with its
    rarity, e.g. `[Common] Speed Coil`) plus a "None" option. Click Speed Coil — the popup closes
    and the slot button should now read "Speed Coil". Open that same slot again and confirm it
    shows "Selected" next to Speed Coil. Craft a second, different mod and equip it into a
    different slot; then try equipping that same mod into a third slot on the same weapon and
    confirm it's rejected (check the Output window for the warning). Deploy a robot and equip a
    mod on it the same way (near the Welding Station this time, not the Forge).
14. Click **Inventory** in the bottom action row — it should open from anywhere, not just near a
    station (walk well outside your plot first to confirm this), showing a grid of square tiles
    rather than rows. Since you haven't added anything to `ReplicatedStorage.ItemIcons` yet, every
    tile should show as a plain colored square with the item's name as text instead of a blank
    square — that's the expected no-icon fallback, not a bug. Click the **Materials** tab, then
    click the **Scrap Iron** tile — a detail panel should pop up to the right of the Inventory
    showing its name, description, and "You have: N" matching the count that's now missing from
    the trimmed-down top-left readout; click the **X** on the detail panel to close just that
    panel (the Inventory itself should stay open). Switch to **Weapons** and click a tile you
    own — the detail panel should show its rarity/stats/affix summary/description, three mod slot
    buttons (clicking one should open the same mod picker popup from before), and an **Equip**
    button at the bottom (or **Equipped**, highlighted, if it's your current pick). While standing
    away from your Forge, click **Equip** on a weapon instance that isn't already equipped and
    confirm it's rejected with a "You need to be at your Forge" reason; walk back and confirm it
    succeeds — the button should flip to "Equipped" and the tile itself should pick up the accent
    highlight without needing to reopen the panel. Craft a second copy of a robot you already own
    (needs 2+ owned) and deploy both from the **Robots** tab detail panel — its stats line should
    read "owned 2, deployed 2" and the button should flip to **Undeploy**; click it and confirm one
    instance comes back off duty ("deployed 1") and the button flips back to **Deploy**. Confirm
    the **Mods** tab's tiles open a detail panel with the mod's description and rarity but no
    action button (mods equip through a Weapon/Robot's own slots, not directly). Finally, go back
    to the Forge's own Weapons tab and confirm it does NOT show that weapon's row or an Equip
    button anywhere — the Forge stays craft-only, this Inventory panel is the only place equipping
    happens. If you want to test the icon system itself: add an
    `ImageLabel` named `PipePistol` inside `ReplicatedStorage.ItemIcons`, set its Image property to
    any decal/image asset, and confirm that specific tile (and its detail panel) picks up the
    picture instead of the placeholder text. The same convention covers the persistent **Luck
    Potion** button from step 6 — add one named exactly `LuckPotion` and confirm that square button
    (not a tile, but same `getItemIcon` lookup) picks up the picture too.

## 5. Environment effects (optional polish)

`EnvironmentFX.client.lua` adds two cheap cosmetic touches so the world feels different as you
travel away from base — neither is required for the loop to work, but both are on by default
once you tag the right instances:

- **Trees swaying** — tag any Part or Model `Tree` and it'll gently sway in place. No other
  setup needed.
- **Fog/haze thickening with distance** — automatic once you have an `ExpeditionStart` Part
  placed (see step 7 above); the world reads as hazier/more remote the further you walk from
  it. If your place's Lighting has an `Atmosphere` object (check Explorer), the script drives
  its `Haze`/`Density`/`Color` — Atmosphere overrides plain `Lighting.Fog*` rendering when
  present, so that's the property that actually matters. Tune `FAR_HAZE`, `NEAR_FOG_END`/
  `FAR_FOG_END`, `FAR_DISTANCE`, and the two colors at the top of the script; there's also a
  throttled `print` in there reporting live distance/haze numbers to the Output window if you
  need to double check it's working.
- **"Stuff out of bounds disappears" as you go further** — this one needs no script at all:
  select `Workspace` in Studio's Explorer, and in the Properties panel set
  `StreamingEnabled` to `true`. Roblox will then automatically stream parts in/out based on
  distance from the player (tune `StreamingMinRadius`/`StreamingTargetRadius` alongside it if
  the default falloff feels too aggressive or too lenient). This is a per-place engine setting,
  not something `ExpeditionConfig.lua` controls.

## 6. What you still need to build

This scaffold deliberately stops at the systems layer — the parts an AI assistant is best at
and that are easy to get subtly wrong (economy math, save data, purchase handling). It does
*not* include:

- Ore node / base / arena 3D art (see "Art & the icon" in the design doc for the palette and
  a shortlist of what to model)
- Real enemy NPCs, pathfinding, and gun-firing/hit detection (replaces the WaveService
  simulation loop)
- Real UI *design* — `MainHud.client.lua` is functional, not styled; treat it as scaffolding
  to reskin once the loop feels right, not a finished screen
- Sound design, icon, and thumbnail

## 7. Config-driven by design

Every number lives in `src/ReplicatedStorage/Shared/*.lua` — ore yields, crafting costs, wave
scaling, shop prices, node loot tables — not scattered through the service scripts. Retune the
whole economy by editing those files; you shouldn't need to touch service logic to change a
price, a drop rate, or an outpost's difficulty.
