# Design Notes — living doc

This is where the bigger, not-yet-built ideas live so they don't get lost between sessions.
`README.md` documents what's actually built; this file is the backlog/vision behind it. Read
this before starting any of the not-yet-built sections below — it captures real decisions
already made (numbers, mechanics, sequencing), not just vague direction.

## Status at a glance

| Zone | Status |
|---|---|
| Raid Energy (Expedition gating) | **Built** |
| Mining zone (dig-down/Y-levels) | **Built** — see below |
| Base (crafting process, tiers, mods, turrets) | Not started |
| Main shop (rotating stock, geode/extractor) | Not started |
| PvP base invasion | Not started, sequence last |

Agreed build order (most recent discussion): Raid Energy → Mining zone rework → weapon mod
slots → base building/tiers (+ boss waves) → rotating shop → PvP invasion last. Re-confirm this
order before starting each one — priorities may have shifted. Next up: weapon/robot mod slots,
then base building/tiers.

## Mining zone — BUILT

Shipped as `MineShaftConfig.lua`/`MineShaftService.lua`/`MineShaftController.client.lua`,
replacing `ResourceZoneService.lua`/`ResourceZoneConfig.lua`'s scattered-ring layout entirely
(those files are still on disk for reference but no longer required by `Main.server.lua`).

**Current design (4th and final rework — a real 3D voxel grid):** `MineShaftStart` is a Part you
place somewhere with genuine open air underneath — up on a platform, not resting on the map's
actual ground. Everything is built as ordinary, real, solid Parts directly below it — no
teleporting, no relocated "pocket" dimension, nothing fake. Only the top layer (Depth 0, a
`GridWidth` x `GridLength` grid, 128x128 by default) is generated up front — that's the quarry
floor you walk onto. Digging works by **cellular reveal**: destroying a block checks its 6
face-adjacent neighbors (down/up/+X/-X/+Z/-Z) and spawns a fresh block in any that have never been
touched before (`MineShaftService.revealNeighbors`). Since Depth 0 starts completely filled in,
mining a Depth-0 block only ever reveals the block below it — but once you're a level down,
sideways neighbors are just as unexplored as the one below, so the mine grows into real connected
tunnels the deeper you go, not a single one-block shaft per surface cell. Breaking a block just
leaves real open air, so the player naturally falls/steps into it under ordinary gravity — no
explicit teleport needed anywhere in this version.

**This took four attempts to get right** — worth understanding why the first three didn't work,
so nobody re-walks that path:
1. *Scattered narrow shafts* — the very first pass, 9 separate one-cell-wide holes with walls
   between every one. Wrong shape entirely ("its supposed to be a big square area... a square
   field where there will be blocks that fill it up").
2. *One quarry grid, digging real ground out from under it* — tried disabling `CanCollide` on
   real parts under the quarry (broke collision for the WHOLE map, since `CanCollide` is a
   whole-Part property and the map's ground was one shared Part), then tried real CSG subtraction
   instead (`SubtractAsync`/`Terrain:FillBlock` — correct in principle, but silently failed for
   this map's actual geometry, leaving the player still stuck in solid ground with no visible
   error).
3. *Relocating everything below Depth 0 into a separate hidden "pocket" elsewhere in the world* —
   avoided touching real geometry at all, which was the right instinct, but added a lot of
   incidental complexity (teleporting, absolute-position landing math, a fully sealed
   walls+floor+roof box) and still shipped two more bugs on top of that: the pocket's downward
   offset tripped `Workspace.FallenPartsDestroyHeight` (an engine setting, default -500, that
   silently destroys any BasePart — including a player's character — below that Y, which is
   exactly what "teleported somewhere and instantly died" was), and the sealed roof left zero
   headroom above the first pocket level, so the post-mine landing spot ended up on TOP of the
   roof instead of inside it ("only one block in there," labels floating in a void with nothing
   visible below them).
4. **What's actually shipped now**, described above — real space, real gravity, cellular reveal,
   nothing relocated or faked. This is simpler AND fixes the earlier bugs by construction: no real
   geometry is ever modified (you supply the clear space up front by where you place the anchor),
   and there's no teleport math to get wrong because gravity already does the right thing once a
   block is real and its neighbor cell is real, ordinary open air.

**Performance note:** shipped at 128x128 (~16,000 Parts for the first layer alone) but dropped to
32x32 (~1,024) after testing — plenty of room without the load-in cost. `populateGrid` still
yields periodically while generating so it doesn't hitch the server, and per-block BillboardGui
labels were deliberately dropped in favor of ONE reusable hover label
(`MineShaftController.client.lua`) that re-targets whichever block you're actually looking at —
a permanent GUI per block would have been a real client-side cost for something only ever useful
one block at a time. `GridWidth`/`GridLength` is still the first knob to turn in either direction.

- **Three block kinds per cell**, weighted by depth (`MineShaftConfig.KindWeightBands`): mostly
  **Rock filler** (destroys for nothing — makes ore feel earned, not just sitting there), some
  **Ore** (an actual resource, rarer ore more common with depth — `OreWeightBands`, same shape as
  the old ring zone's distance bands), and a few, more often the deeper you go, **Lava pockets**
  (mine one through and it bursts for real damage instead of a reward, no warning in its label
  first). Rock is floored (30-40% even in the deepest band) so filler never fully disappears even
  very deep, per the explicit ask. Depth 1-4's Ore rate was tuned down after testing — 40% Ore
  felt like too much too early — to 80% Rock / 20% Ore total, split 75/25 Scrap Iron/Copper Wire
  (no Steel Plating that shallow), landing on roughly the requested "80% rock, 15% iron, 5%
  copper."
- Interaction is a `ClickDetector` (matching the Expedition nodes), not the hold-style
  `ProximityPrompt` ore mining uses — a prompt on a block directly under the player's own feet
  fails its line-of-sight check and silently never fires, which is what broke mining entirely on
  the first pass.
- Separately, ambient environmental hazards past a depth threshold — currently Heat (depth 6+)
  and Toxic Air (depth 12+), `MineShaftConfig.HazardTypes` — deal periodic damage. This is the
  "go deep, but you need to be equipped for it" layer from the original ask, and it's a separate
  risk from Lava pockets ("the air down here is dangerous" vs. "you dug into an active pocket").
  **Reworked into 3 Tiers per hazard type**, damage roughly doubling each Tier (Heat: 4/8/16,
  Toxic Air: 7/14/28) — the deeper you go, the worse that specific hazard gets, and Heat/Toxic Air
  now apply independently (both can tick in the same interval once you're deep enough for both,
  instead of only the "worst" one firing like the original single-threshold version did). Gear no
  longer just flips a hazard off once you hit some required **Suit tier** (Workbench → Suit,
  `UpgradeSuit`) — each tier's `Protection` table knocks a hazard DOWN by however many Tiers it
  specifies instead ("Tier 2 becomes the new Tier 1" if your gear reduces it by 1), only fully
  zeroing the damage once the reduction brings the effective Tier to 0. Thermal Liner reduces Heat
  by 1 Tier; Rebreather Rig keeps that AND reduces Toxic Air by 1 Tier — neither fully negates the
  deepest Tier of a hazard on its own, which is intentional (going deep should always cost
  something, even fully geared). Damage ticks every `HazardCheckIntervalSeconds` (2s, sped up
  from an original 4s — healing was outpacing the slower tick easily); the depth HUD panel itself
  updates on its own faster `DepthReportIntervalSeconds` (0.5s) loop so it doesn't feel laggy. A
  "virus" hazard type could be added the same way later if wanted.
- **Recall button** — now visible any time you're anywhere in the mine, including right at the
  Depth-0 surface (originally gated behind actually descending a level first). Respawns you at a
  normal SpawnLocation at full health. Added because the mine has no climb-out mechanic: once
  you're a few levels deep there's no way back up under your own power.
- Multiplayer-synced by construction: every cell's state is one shared, server-tracked value (the
  `cells` sparse table in `MineShaftService.lua`) — if one player digs somewhere open, everyone
  sees it already open. No per-player mine state anywhere.
- **Zone spacing** — `KindWeightBands`/`OreWeightBands`/`HazardTypes` boundaries were originally
  only 4-8 levels apart, so the ore mix and hazard tier both shifted within just a few blocks of
  digging — nowhere near enough room to actually feel like a big cave. Respaced to 40+ levels
  between each boundary, and `MaxDepth` (the Bedrock cutoff) bumped from 40 to 200 so the deepest
  zone actually has room to exist instead of being squeezed out.
- **Full reset** (`MineShaftConfig.ResetIntervalSeconds`/`ResetBlockThreshold`/`ResetLockSeconds`)
  — the whole mine tears down and rebuilds every 30 minutes, or immediately once 20,000 blocks
  have been mined since the last reset, whichever comes first. `performReset` (in
  `MineShaftService.lua`) ejects anyone currently inside (`LoadCharacter`, same as Recall), locks
  out new mining for `ResetLockSeconds` (a few seconds) so it reads as an actual event, then
  destroys every live block, clears the `cells`/`blockOwner` state, and rebuilds a fresh Depth-0
  floor via `regenerateDepthZero` (the guard rail and `originCFrame` are cached from the very
  first generation and reused, not rebuilt, so resets don't stack duplicate geometry on top of
  themselves). Keeps the mine from turning into an ever-growing swiss-cheese sprawl of old
  tunnels and gives everyone a reason to come back to a fresh one.

## Base

Several distinct pieces bundled under "the base":

- **Base plots — BUILT.** Prerequisite groundwork for everything else in this section: every
  player needs an actual place their base lives before "the base" means anything. Split into two
  services on purpose — `PlotService.lua` owns WHERE a base lives, `BaseService.lua` owns WHAT
  gets physically built there — so a future base-tier upgrade only ever touches BaseService, never
  the assignment/respawn logic.

  `PlotService.lua`: on join, a random unclaimed Part tagged `Plot` (`PlotConfig.Tag`) in
  Workspace is assigned to the player (`playerPlot`/`plotOwner` tables), freed back to the pool on
  `PlayerRemoving`. First revision had the `Plot` Part itself double as the visible floor the
  player stood on; direct feedback was that it should instead be an invisible area with an actual
  base Model loaded onto it based on save data — so `sanitizePlot` now forces every tagged Part
  transparent/non-collidable/non-queryable the moment it's tagged (at boot, and via
  `CollectionService:GetInstanceAddedSignal` for ones added later), regardless of how it was built
  in Studio. It's purely an anchor CFrame now. Rather than fighting Roblox's own SpawnLocation/
  team auto-pick logic (which would let anyone land on ANY enabled SpawnLocation, not specifically
  their own), the character is manually repositioned onto its assigned plot's CFrame via
  `CharacterAdded` every time one fires — which means Recall, End Expedition, and the mine's
  full-reset eviction (all of which already call `player:LoadCharacter()`) now land the player at
  their own base automatically, for free, no extra code needed in any of those three places.
  `PlotService.PlotAssigned` (a `BindableEvent`) is how `BaseService` learns a plot exists to
  build on — deliberately a signal rather than `BaseService` guessing at `Players.PlayerAdded`
  connection order, since Roblox doesn't guarantee two separately-connected listeners on the same
  event fire in a fixed order relative to each other's yields.

  `BaseService.lua`: on `PlotAssigned`, clones a Model from `ReplicatedStorage.BaseTemplates`
  onto the plot's CFrame (`model:PivotTo(plot.CFrame)`), picking which tier via
  `profile.BaseTier` (new `DataService` field, same shape as `ToolTier`/`SuitTier`, always `1` for
  now — see `BaseConfig.lua`). `RebuildPlayerBase(player, plot)` is exposed and safe to call again
  — a future base-upgrade remote just calls it a second time to swap the model, destroying
  whatever was cloned before. No Studio Model built yet for a tier? Rather than leave the player
  standing on the now-invisible, non-collidable Plot anchor (a guaranteed fall into the void),
  `buildFallbackBase` clones a single plain gray placeholder floor and warns in Output instead —
  same "functional before art" approach as everything else in this project. `waitForProfile`
  mirrors `Remotes.GetProfile.OnServerInvoke`'s existing poll-with-retries pattern, since
  `DataService`'s own `PlayerAdded` handler loads the profile via a yielding DataStore call that
  isn't guaranteed to finish before `BaseService`'s `PlotAssigned` handler runs.

  `PlotService.IsPlayerInOwnPlot(player)` is the base-area gate: a box-contains check against the
  assigned plot's own CFrame and `PlotConfig.FootprintHalfSize` — deliberately NOT derived from
  the anchor Part's own (now largely irrelevant) `Size`, since the anchor is just a small marker
  and the actual claimed base area is configured separately, sized for whatever the biggest
  `BaseConfig` tier ends up being. Every Workbench-adjacent remote handler calls this first and
  rejects with `PlotConfig.NotInBaseMessage` if it's false — `CraftItem`/`DeployRobot`/`EquipMod`
  (`CraftingService.lua`), `UpgradeTool` (`MiningService.lua`), `UpgradeSuit`
  (`MineShaftService.lua`), `CraftAutoMiner` (`AutoMinerService.lua`), and `StartWave`
  (`WaveService.lua`, via a `"NotInBase"` `WaveUpdate` status the HUD handles the same way it
  already handled `"NoGear"`). Ordinary ore mining (`MineNode`) and the mine shaft itself are
  deliberately NOT gated — only the things that conceptually happen "at the workbench" or "at the
  base" are. **Setup requirement:** at least one Part tagged `Plot` must exist in Studio or
  literally nothing craftable will work (a placeholder floor still spawns even with zero
  `BaseTemplates` built, so testing isn't blocked on real art) — see the README's "Base plots"
  bullet and testing step 1.
- **Base stations — BUILT.** A second, more specific gate on top of the plot-wide one above,
  requested directly after Base plots shipped: several Workbench actions should require standing
  near a specific physical prop, not just anywhere in the plot — a Workbench for Tools/Auto-Miner/
  Suit, a Welding Station for Weapons/Robots/Mods, matching how the player described wanting to
  build the base ("workbench... forge... a welding place so you can build your robots"). Shipped
  as: `StationConfig.lua` (pure data — the `Station` tag, `InteractDistance` = 12 studs, and a
  `Types` table keyed `Crafting`/`Welding`/`Forge`, each with a `DefaultTab` and
  `NotThereMessage`) and `StationService.lua` (`IsPlayerNearStation(player, stationType)` — scans
  every `Station`-tagged instance for one whose child `StringValue` `StationType` matches, within
  `InteractDistance` of the player's `HumanoidRootPart`). Every remote `PlotService
  .IsPlayerInOwnPlot` already gated now ALSO calls `StationService.IsPlayerNearStation` right
  after it, with the specific station type each action belongs to (`CraftItem`/`DeployRobot`/
  `EquipMod` -> `Welding`; `UpgradeTool`/`CraftAutoMiner`/`UpgradeSuit` -> `Crafting`) — plot check
  first (broad: are you home at all), station check second (specific: are you at the right prop).
  `StartWave` stays plot-only, no station — "Start Defense" isn't tied to a particular structure.

  Deliberately does NOT hide Workbench tabs based on proximity — every tab is always visible via
  the general **Workbench** action-row button, same as before; only the underlying action itself
  rejects with a clear reason if you're not near the right station, matching the existing
  plot-gate UX pattern rather than introducing a second, different kind of restriction. What
  clicking a physical station DOES do (client-side, `MainHud.client.lua`'s `setupStation`, same
  ClickDetector+Highlight interaction model as Expedition Nodes) is open the Workbench straight to
  that station's `DefaultTab` as a convenience — `selectTab` was factored out of `makeTabButton`'s
  click handler specifically so both paths share it.

  The Forge is registered in `StationConfig.Types` (so a station can already be tagged and placed)
  but has `DefaultTab = nil` and no server-side action routes to it yet — clicking one just prints
  a "doesn't do anything yet" notice client-side. It's there as a placeholder for the ore-smelting
  mechanic below, not yet wired to one.
- **Ore smelting (Forge mechanic) — NOT BUILT, planned.** Explicitly requested as a real mechanic,
  not just flavor for the Forge prop: raw ore (`ScrapIron`, `CopperWire`, etc.) would get
  converted into a refined material before it's usable in recipes, instead of being spent directly
  as `CraftingRecipes`/`ModConfig` costs do today. Deliberately deferred past the base-stations
  work above (including by the player's own call when asked) — scope it as its own task once the
  physical base (Workbench/Welding/Forge props) is built and tested, since it touches
  `OreConfig.lua` (or a new `RefinedOreConfig.lua`), `DataService`'s `OreCounts` shape, every
  recipe's `Cost` table, and needs a new `SmeltService.lua` + a real Forge remote/UI — a bigger
  lift than the station-gating infrastructure, and one worth designing fresh rather than bolting
  onto this session's momentum.
- **Base defense minigame — NOT BUILT, planned, needs its own design pass.** Player feedback
  while planning the base layout: base-defense (`WaveService`'s "Start Defense") should give
  players more to actively DO while defending, not just watch a headless DPS-vs-enemy-HP-pool
  simulation tick by (see `WaveService.lua`'s own header comment — it was always meant to be
  swapped out once real combat exists, this is that swap). Player's own words: "add smth more to
  the base... something that will make players spend a little more time in base... maybe we could
  have stuff in the base to add defense mechanisms and stuff and then have a minigame happen for
  the base defense." Loosely implies two related but separable ideas worth untangling in a future
  session: (1) placeable defense structures physically sitting in the base (turrets/robots as real
  world objects, not just abstract `DeployedRobots` entries — ties into the Turrets bullet below),
  and (2) an actual interactive minigame/real-time element during a wave run instead of the
  current auto-resolving tick loop. Deliberately NOT scoped or started this session — "minigame"
  covers a huge range of actual designs (aiming/shooting, a tower-defense placement phase, a
  timing/rhythm mechanic, etc.) and deserves its own dedicated requirements conversation rather
  than a guessed implementation. Revisit once the physical base (this section's other BUILT items)
  is in place and tested.
- **Crafting process** — smelting, wiring, etc. as actual steps with a "cute" animation, not an
  instant craft. Build the functional version first (a timed progress bar the player waits out,
  no art) before layering the animation/juice on top — same systems-then-art approach as
  everything else in this project.
- **Base building/tiers** — the player upgrades the base itself to get stronger and defend
  against more (explicitly including, later, other players — see PvP section). Tiers gate access
  to better materials/robots (example given: Tier 3 unlocks "vibranium," a cool droid, etc.).
  Moving from one tier to the next requires beating a specific wave milestone, or getting a drop
  from a wave boss past a certain wave — i.e. `WaveService` needs an actual boss/drop concept,
  which doesn't exist yet (it's currently a generic enemy-count/multiplier simulation with no
  boss or loot table). The loading half of this now already exists (see Base plots above,
  specifically `BaseConfig.Tiers`/`profile.BaseTier`/`BaseService.RebuildPlayerBase`) — what's
  still missing is purely the purchase/unlock side: an `UpgradeBase` remote that spends
  `BaseConfig.BaseTierCosts[nextTier]` and bumps `profile.BaseTier`, same sequential pattern as
  `UpgradeTool`/`UpgradeSuit`, gated behind whatever the wave-boss-drop concept ends up being.
- **Weapon/robot mod slots — BUILT.** 3 slots per weapon (or robot TYPE) for modifiers with real
  tradeoffs, e.g. a speed module that increases fire rate but lowers damage. Shipped as:
  `ModConfig.lua` (pure data — `SlotsPerItem = 3`, 6 mods: Speed Coil, Heavy Rounds, Stabilizer,
  Scavenged Capacitor, Reinforced Plating, Overclocked Core — each with optional
  `FireRateMultiplier`/`DamageMultiplier`/`HPMultiplier` fields, missing = 1x/no-op). Mods are
  permanent unlocks (`profile.CraftedMods`, craftable via the existing `CraftItem` remote with
  `tree="Mods"`) equipped per slot via a new `EquipMod` RemoteFunction into
  `profile.EquippedMods[itemKey][slotIndex]`.

  `CraftingRecipes.lua`'s flat `DPS` field was split into `FireRate`/`BaseDamage` (product equals
  the old DPS numbers exactly) so mods can multiply each independently.
  `CombatMath.GetEffectiveStats(tree, key, profile)` applies all equipped mods to a recipe and
  returns `{FireRate, Damage, DPS, HP}`; `GetPlayerCombatDPS` now routes through it, so
  `WaveService`/`NodeService` needed zero changes — they already just call
  `CombatMath.GetPlayerCombatDPS(profile)`.

  **Key simplification, deliberate:** mods apply per item TYPE, not per robot instance.
  `CraftedRobots` is a plain owned-count and `DeployedRobots` is a repeatable key list — neither
  has per-instance identity — so equipping a mod on "Scrapbot" affects every deployed Scrapbot at
  once. Building real per-instance robot identity would be a much bigger lift for a payoff the
  game doesn't need yet; revisit only if that ever stops being true.

  HUD: new "Mods" tab (craft menu widened 590->640, tabs shrunk 100->90px to fit 6). Owned
  weapons/robots now render as a taller "equipment row" (`makeEquipmentRow`) with 3 slot buttons
  underneath the normal name/stats/action row. First pass had these cycle in place through owned
  mods on click — direct user feedback was that clicking a slot should instead open a picker
  showing what's actually available, so it's now a popup (`openModPicker`/`modPickerFrame`, a
  `screenGui` sibling of `craftFrame` and `shopFrame`) listing every owned mod (plus "None" to
  clear the slot); selecting one calls `EquipMod` and closes the popup. `ModConfig.Rarities` was
  added alongside this — every mod is currently `Common` (it's a display label the picker prefixes
  onto each mod's name, e.g. `[Common] Speed Coil`) — real rarity tiers/weighted drops are a later
  addition once mods stop being flat-craftable from the start; the structure's there now so that
  swap doesn't require touching the picker UI again. No manual client-side refresh on equip:
  `EquipMod`'s server handler fires the same `InventoryUpdate` patch pattern every other
  craft/deploy action already uses, and the existing listener re-renders the open craft list.
- **Turrets** — player-placed structures defending the base/resources. Worth clarifying when
  this gets picked up: is this meant to be a genuinely new placeable-structure type, or just
  what `DeployedRobots` (which already exist and already defend in `WaveService`) get renamed
  to/reskinned as? Could be much less work than it sounds depending on the answer. Likely the
  same conversation as the Base defense minigame bullet above — "physical defense structures in
  the base" is exactly what Turrets already is, so scope both together when this gets picked up.

## Raid section — BUILT

This became the Expedition + Raid Energy system. For reference, the original ask: near the base,
raids give strong rewards, so gate them behind an Energy resource; a rare pickup found while
mining ("energy drink") grants bonus energy; regen should be "long but not sooo long" that it's
boring.

Shipped as: `RaidEnergyConfig.lua`/`RaidEnergyService.lua` — 1 Energy per raid attempt (charged
on start, win or lose), 5 max, regen 1 every 4 minutes while connected, a 3%-per-mining-hit
chance at a rare Energy Drink (+2 Energy, can overflow up to 8). Also added since: the Expedition
queue now only starts when the lever is pulled (previously it auto-spawned at server boot) and a
"Return to Base" button ends it early — see `ExpeditionService.lua`'s `EndExpedition` remote.
Both of those were interim fixes with an explicit note that a real teleport-to-a-separate-area
flow is the intended eventual replacement for "pull a lever to start."

## Main shop

- **Rotating stock** — the shop's available items change over time (a schedule/rotation), not a
  static catalog.
- Sells: pieces of technology, gun/robot mods (ties into the Base mod-slot system above), armor,
  possibly cosmetic skins.
- **Geode/extractor mechanic** — buy a sealed rare geode from the shop, place it in an extractor
  structure, wait a timer, crack it open for a rare gem or Cores sellable for real value. This is
  explicitly meant as a "grow a garden" return-hook (something to check back on later), but
  should NOT be the only thing to do in the game — a supplement, not the core loop.
- **Flag for later**: once real money touches anything with randomized rewards (geodes, etc.),
  check Roblox's policy on randomized virtual item mechanics (odds disclosure requirements) — not
  a blocker for prototyping, but relevant before shipping a monetized version.

## PvP base invasion

Players can invade another player's base to steal a bonus. The victim loses a percentage (~20%
suggested) of whatever the raider actually got from the invasion.

**Sequence this last, deliberately** — flagged as the highest-risk item in the whole roadmap:

- Needs some matchmaking or parity check so it's not just farming weaker players.
- Needs protection against being raided while offline — usually the single biggest complaint/
  exploit vector in every game that does base-raiding (Clash of Clans-style shields/insurance is
  the standard answer, but it's real design + engineering work, not a toggle).
- Needs its own combat-testing loop, separate from PvE.
- Depends on the economy and combat numbers from every other system being reasonably balanced
  first — building PvP balance on top of numbers that are still going to change means redoing it.

## Known interim decisions (context for future sessions — don't "fix" these back)

- `AdminConfig.lua` — the game's owner (auto-detected via `game.CreatorId`, or an explicit
  `AdminUserIds` list for Group-owned games/teammates) gets dev-only shortcuts: raids resolve as
  an instant win with no Energy cost, no gear/cooldown checks. Purely a testing aid, not a player
  feature.
- Expedition start/end is currently lever-pull-to-start, "Return to Base" button-to-end. This is
  a deliberate placeholder for a real teleport-to-a-separate-instance flow, not the final design.
- `ResourceZoneService.lua`/`ResourceZoneConfig.lua` (the old scattered-ring ore layout) are
  retired — replaced by `MineShaftService.lua`'s dig-down shafts, see the Mining zone section
  above. The files are left on disk for reference/rollback but are no longer required by
  `Main.server.lua`; don't re-enable or tune them.
