# Salvage Protocol — starter scaffold

This is a [Rojo](https://rojo.space) project: the source of truth for your scripts lives in
these files, and Rojo syncs them into Roblox Studio live as you (or an AI assistant) edit them
in a normal code editor. It implements the full loop from the design doc end to end — mining,
crafting, deploying robots, and running wave-defense sessions for Scrap/Cores — with clearly
marked placeholders where visuals, real combat, and UI need to be built on top.

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
  mining Just Works, gated by tool tier and wave-unlock as configured.
- **Crafting** — call the `CraftItem` RemoteFunction from a UI button with a tree name
  (`"Weapons"` or `"Robots"`) and a recipe key from `CraftingRecipes.lua`. Cost is validated
  and deducted server-side.
- **Deploying robots** — call `DeployRobot` the same way with a robot key you already own.
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
  Cores currency), and Combat Outposts (a single fixed-difficulty fight for loot, where you
  take real damage every second it isn't won — see `NodeConfig.lua` for the three tiers).
  Setup is identical in spirit to ore nodes: tag a Part `Node`, add a `StringValue` named
  `NodeType` set to `"Heal"`, `"Shop"`, or `"Combat"`. Combat nodes additionally need a
  `NumberValue` named `Tier` (1, 2, or 3) matching `NodeConfig.CombatTiers`.
- **Expedition path (procedural)** — `ExpeditionService.lua` generates a chain of 5–8 node
  slots stretching out from a Part you tag `ExpeditionStart` (its facing direction is the
  path's direction). Every 3rd slot is a fork — two nodes appear side by side, and engaging
  with either one (a heal, a purchase, or a cleared raid) despawns the other; the rest of the
  slots each have a flat 30% chance of holding a single node at all. Combat nodes spawned this
  way are one-time — they're destroyed after a successful raid, unlike the permanent hand-
  placed ones. Tag a second Part `ExpeditionLever` to let players regenerate the whole path on
  demand. See `ExpeditionConfig.lua` to retune slot count, fork spacing, node odds, or the
  Combat/Shop/Heal weighting.

## 4. Testing the loop (debug HUD)

`MainHud.client.lua` builds a plain, undecorated HUD in code — a currency readout, a
Workbench panel (Weapons/Robots tabs, craft and deploy buttons), and a Start Defense button
with a live wave/HP bar. It exists so the loop is actually visible before any real art or UI
design happens. To test end to end:

1. Place a Part in the workspace, tag it `OreNode` (Studio's Tag Editor, top ribbon under
   **Model** or via `CollectionService`), and add a child `StringValue` named `OreType` with
   value `ScrapIron`.
2. Play, walk up to it, hold the ProximityPrompt to mine — the Scrap/ore count updates live.
3. Open **Workbench** (bottom of screen), craft a Pipe Pistol or a Scrapbot.
4. If you crafted a robot, click it again to **Deploy** it.
5. Click **Start Defense** — the wave panel appears and the objective/enemy bars move as the
   simulated combat resolves (see the big comment in `WaveService.lua` for what this is
   standing in for).
6. Place three more Parts and tag one each `Node` with `NodeType` = `Heal`, `Shop`, and
   `Combat` (give the Combat one a `Tier` NumberValue set to `1`). Walk to the Combat node and
   hold the **Raid** prompt — the raid panel (bottom-right) shows enemy HP and your own HP
   draining together. Clear it, then visit the Shop node and spend the Scrap/ore you've
   earned; visit the Heal node any time your HP is low.
7. Place one more Part near your base and tag it `ExpeditionStart` — whichever way its front
   face points is the direction the path will generate down. Press Play: a chain of 5–8
   colored, labeled nodes should appear stretching out from it (orange = Combat, blue = Shop,
   green = Heal), with some slots skipped entirely (the 30% roll) and a **pair** of nodes side
   by side every 3rd slot (a fork). Walk into range of one fork option and clear/use it — the
   other option in that pair should immediately disappear. Optionally tag a second Part
   `ExpeditionLever` near the start and hold its prompt to wipe and regenerate the whole path
   on demand (handy for re-rolling while you tune `ExpeditionConfig.lua`).

## 5. Environment effects (optional polish)

`EnvironmentFX.client.lua` adds two cheap cosmetic touches so the world feels different as you
travel away from base — neither is required for the loop to work, but both are on by default
once you tag the right instances:

- **Trees swaying** — tag any Part or Model `Tree` and it'll gently sway in place. No other
  setup needed.
- **Fog thickening with distance** — automatic once you have an `ExpeditionStart` Part placed
  (see step 7 above); the world reads as hazier/more remote the further you walk from it.
  Tune `NEAR_FOG_END`, `FAR_FOG_END`, `FAR_DISTANCE`, and the two fog colors at the top of the
  script.
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
