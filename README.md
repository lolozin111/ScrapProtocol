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
  Auto-Miner, and Suit upgrades), `Welding` (a **Welding Station** prop — gates Weapons, Robots,
  and Mods), or `Forge` (no mechanic wired up yet — a real ore-smelting system is planned later,
  see `DESIGN_NOTES.md`; for now clicking it just prints a "doesn't do anything yet" notice).
  Clicking a `Crafting`/`Welding` station in-world opens the Workbench menu straight to that
  station's tab (`StationConfig.Types[type].DefaultTab`) as a convenience, but the tabs
  themselves aren't hidden or restricted by location — you can still browse everything from the
  general **Workbench** action-row button; only the actual craft/upgrade/deploy/equip action
  itself gets rejected server-side (`StationService.IsPlayerNearStation`,
  `StationConfig.InteractDistance` = 12 studs) if you try it while not near the right station,
  with a clear "You need to be at your Workbench/Welding Station to do that" reason. Place as
  many of each type as you like, anywhere inside your `PlotConfig.FootprintHalfSize` box.
- **Crafting** — call the `CraftItem` RemoteFunction from a UI button with a tree name
  (`"Weapons"`, `"Robots"`, or `"Mods"`) and a recipe key from `CraftingRecipes.lua`/
  `ModConfig.lua`. Cost is validated and deducted server-side. **Only works while standing at
  your own base plot, near the right station** — see `PlotService.IsPlayerInOwnPlot` and
  `StationService.IsPlayerNearStation`, which every Workbench remote (`CraftItem`, `DeployRobot`,
  `EquipMod`, `UpgradeTool`, `UpgradeSuit`, `CraftAutoMiner`) and `StartWave` (plot only, no
  station needed) check first, rejecting with a clear reason if you're not.
- **Deploying robots** — call `DeployRobot` the same way with a robot key you already own.
- **Weapon/robot mods** — Workbench → Mods tab to craft permanent mod unlocks (`ModConfig.lua`,
  3 slots per weapon/robot type — see `DESIGN_NOTES.md`'s "Base" section for the full design and
  why mods apply per item type rather than per robot instance). Once a weapon or robot is owned,
  its row in the Weapons/Robots tab grows 3 slot buttons — click one to open a picker popup
  listing every mod you currently own (each tagged with its rarity — everything's `Common` for
  now, see `ModConfig.Rarities`) plus a "None" option to clear the slot. Equip via the `EquipMod`
  RemoteFunction (`tree, itemKey, slotIndex, modKey`); `CombatMath.GetEffectiveStats` applies
  whatever's equipped when computing DPS.
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

`MainHud.client.lua` builds a plain, undecorated HUD in code — a currency readout, a
Workbench panel (Weapons/Robots tabs, craft and deploy buttons), and a Start Defense button
with a live wave/HP bar. It exists so the loop is actually visible before any real art or UI
design happens. To test end to end:

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
   two more Parts. Tag one `Station` and give it a child `StringValue` named `StationType` set to
   `Crafting`; tag the other `Station` too, with `StationType` set to `Welding`. These are your
   **Workbench** and **Welding Station** props — any size/shape works, they don't need to look
   like anything yet.
3. Place a Part in the workspace, tag it `OreNode` (Studio's Tag Editor, top ribbon under
   **Model** or via `CollectionService`), and add a child `StringValue` named `OreType` with
   value `ScrapIron`.
4. Play, walk up to it, hold the ProximityPrompt to mine — the Scrap/ore count updates live.
   (Mining ordinary ore nodes works anywhere on the map, not just at your base.)
5. Click your `Crafting`-tagged Station — the Workbench menu should open straight to the **Tools**
   tab, and hovering the station should show its outline highlight. Now click your `Welding`
   Station instead — the menu should jump to **Weapons**. Craft a Pipe Pistol from there — it
   should succeed. Now walk away from both stations (but stay inside your plot) and try crafting
   again from the same open menu — it should fail with a "You need to be at your Welding Station
   to do that" warning in Output. Walk back next to the Welding Station and confirm it works
   again. Then walk well outside your `Plot` Part's footprint entirely and try once more — this
   time it should fail with "You need to be at your own base to do that" instead (the broader
   plot check, checked first).
6. If you crafted a robot instead, click it again (while near the Welding Station) to **Deploy**
   it.
7. Click **Start Defense** — the wave panel appears and the objective/enemy bars move as the
   simulated combat resolves (see the big comment in `WaveService.lua` for what this is
   standing in for). This one only needs you inside your plot generally, not near a specific
   station.
8. Place three more Parts and tag one each `Node` with `NodeType` = `Heal`, `Shop`, and
   `Combat` (give the Combat one a `Tier` NumberValue set to `1`). Left-click the Combat node
   (within 50 studs) to raid it — this spends 1 Energy (top-left readout, starts full at 5/5) —
   the raid panel (bottom-right) shows enemy HP and your own HP draining together. Clear it,
   then click the Shop node and spend the Scrap/ore you've earned; click the Heal node any time
   your HP is low. Raid a 6th time with Energy at 0 and you should get a "Not enough Energy"
   warning in Output instead of the raid starting. (If you're testing as the place's owner, raids
   resolve as an instant win with no Energy spent — see "Admin dev shortcuts" above. Add a
   teammate's UserId to `AdminConfig.AdminUserIds` if you want them to see normal combat while
   you test as admin, or vice versa.)
9. Place one more Part near your base, tag it `ExpeditionStart` (whichever way its front face
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
10. Place one more Part **up on a platform with genuinely open air underneath it** (not resting on
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
11. Open **Workbench → Auto-Miner** (near your `Crafting` Station) and click **Build** (costs
    Scrap Iron + Copper Wire). Once built, the row switches to showing the passive rate (e.g.
    `+3 Scrap Iron every 60s`); wait a tick or two and confirm your Scrap Iron count ticks up on
    its own, whether or not you're actively mining.
12. Open **Workbench → Mods** (near your `Welding` Station) and craft a mod (e.g. Speed Coil,
    costs Copper Wire). Craft a Pipe Pistol if you haven't already, and confirm its row in the
    **Weapons** tab now shows 3 slot
    buttons underneath. Click a slot — a **popup should open** listing every mod you currently
    own (each prefixed with its rarity, e.g. `[Common] Speed Coil`) plus a "None" option. Click
    Speed Coil — the popup closes and the slot button should now read "Speed Coil". Open that same
    slot again and confirm it shows "Selected" next to Speed Coil. Craft a second, different mod
    and equip it into a different slot; then try equipping that same mod into a third slot on the
    same weapon and confirm it's rejected (check the Output window for the warning). Deploy a
    robot and equip a mod on it the same way.

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
