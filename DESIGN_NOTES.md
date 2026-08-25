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
| Base (crafting process, mods, tiers, turrets) | **Built** — see below (crafting process' "cute" animation step still not started) |
| Main shop (rotating stock, geode/extractor) | Not started |
| PvP base invasion | Not started, sequence last |

Agreed build order (most recent discussion): Raid Energy → Mining zone rework → weapon mod
slots → base building/tiers (+ turrets) → rotating shop → PvP invasion last. Re-confirm this
order before starting each one — priorities may have shifted. Next up: main shop, then PvP
invasion.

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

  Revised after playtesting: the general **Workbench** action-row button is gone entirely, and the
  Workbench menu now ALSO hides tabs it can't use — clicking a station is the only way to open the
  menu at all, and it opens scoped to just `StationConfig.Types[x].Tabs` (Crafting -> Tools/
  Auto-Miner/Suit, Welding -> Weapons/Robots/Mods). `MainHud.client.lua`'s `rebuildTabs` tears down
  and rebuilds the tab row (`tabRow:GetChildren()` -> destroy TextButtons -> `makeTabButton` per
  name) every time `openStationMenu` runs, then calls `selectTab(stationData.DefaultTab)` — so a
  Welding Station's menu physically cannot show the Suit tab, not just "doesn't default to it."
  `craftFrame` picked up a title label (set to `stationData.DisplayName`, e.g. "Welding Station")
  and its own `craftCloseButton` ("X") since there's no toggle button left to close it with. This
  is stricter than the original design note below (which explicitly called this out as NOT hiding
  tabs) — the player's own follow-up feedback after using it was that having every tab reachable
  from every station read as broken/confusing, not that the server-side reject-with-a-reason
  wasn't clear enough. `StationService.IsPlayerNearStation` is still the actual enforcement either
  way; this only ever changes what the client bothers to *offer*.

  The Forge went live later this session as the home of weapon Forging — see the "Forge / weapon
  rarity & Luck" bullet below. It no longer sits at `DefaultTab = nil`; it now owns the Weapons tab
  that used to live on the Welding Station. Ore-smelting (a separate, still-unbuilt idea for the
  same prop) is covered by its own bullet further down so the two don't get conflated.

  Per-player ownership: `BaseService.RebuildPlayerBase` stamps every `Station`-tagged descendant
  of a player's freshly-cloned base Model with an `OwnerUserId` attribute matching that player
  (`tagStationOwnership`), and `StationService.IsPlayerNearStation` only counts a station toward
  the check if it has no owner OR the owner matches the calling player — so once real per-player
  `BaseTemplates` Models exist, players can no longer walk into someone else's base and use their
  Workbench/Welding/Forge. A station with no `OwnerUserId` (a loose block placed directly in the
  world, not inside any base Model — i.e. exactly what placeholder-block testing looks like right
  now) stays open to everyone on purpose, so nothing about current testing changes until stations
  actually live inside a `BaseTemplates` Model.
- **Inventory panel — BUILT.** Requested right after Base stations shipped: a real equip/manage
  screen, plus somewhere to see resource counts that wasn't the increasingly cluttered top-left
  currency readout (four ore lines plus Scrap/Cores/Energy all crammed into one corner). Shipped
  as a new always-available panel (`inventoryButton` in the bottom action row — unlike the
  Workbench, NOT gated to any station or plot, since it's read-only browsing until you actually
  click something) with four filter tabs — Weapons, Robots, Mods, Materials — built the same
  tabbed-frame way as the Workbench, just with a static tab set instead of a per-station one
  (`makeInvTabButton` × 4, no `rebuildTabs` needed here).

  Two real gameplay gaps got closed to make this useful, not just a second read-only view of data
  that already existed elsewhere:
  1. **Weapon equip choice.** Before this, combat DPS always auto-picked whichever owned weapon
     had the highest DPS (`CombatMath.GetPlayerCombatDPS`) — there was no way to choose. Added
     `profile.EquippedWeapon` (a weaponKey, or nil/absent for "no explicit choice, keep
     auto-picking best") and an `EquipWeapon` remote (`CraftingService.lua`, same plot+Welding
     Station gate as every other loadout remote). **Superseded later this session** by the Forge's
     per-instance weapon model — see "Forge / weapon rarity, Luck & Pity" below: `EquippedWeapon`
     became `EquippedWeaponId` (targets one specific rolled instance, not a shared type), and the
     remote moved to `ForgeService.lua`, gated to the Forge instead of the Welding Station. The
     underlying idea (an explicit choice that overrides auto-best, falling back to auto-best when
     unset) is unchanged, just re-pointed at instances instead of types.
  2. **Robot undeploy.** `DeployRobot` existed but nothing could reverse it — once a robot was on
     defense duty it stayed there permanently (no bug on its own, just a missing action nobody had
     needed to build yet). Added `UndeployRobot` (mirror of DeployRobot: removes one matching
     instance from `profile.DeployedRobots`). Building the Robots tab's "owned N, deployed M" row
     also surfaced a real pre-existing gap: `DeployRobot` only checked `CraftedRobots[key] > 0`,
     never how many of that key were ALREADY deployed — so one owned copy of a robot could be
     deployed into every free slot at once. Fixed alongside (counts current `DeployedRobots`
     matches for that key, rejects once it reaches the owned count).

  `deployedCountForRobot` (`MainHud.client.lua`) is shared between the Inventory panel and the
  Welding Station's own Weapons/Robots tabs (via `makeWeaponRow`/`makeRobotRow`), which got the
  same Equip/Deploy-Undeploy treatment instead of the old static "Owned" button that did nothing
  when clicked — the exact "nothing happens when I click it" complaint that started this session's
  mod picker work, just recurring in a different spot. The Workbench's Weapons/Robots tabs stayed
  row-based (crafting NEW items needs cost text a tile can't show), but the Inventory panel itself
  got redesigned a second time this session, from rows to an icon grid, per direct follow-up
  feedback right after the row version shipped: "you have your stuff in squares... where you can
  put an image to represent the item... when you select an item, another window pops up right
  next to the inventory[.]"

  Shipped as: `invListFrame`'s layout swapped from `UIListLayout` to `UIGridLayout`
  (`TILE_SIZE` = 76, 8px cell padding), and `makeItemTile(key, displayName, badgeText, highlighted,
  onSelect)` builds one square `ImageButton` per owned item/material — a small corner badge (tier
  for weapons, owned-count for robots), an accent-colored background when equipped/deployed, and a
  plain colored square with the item's name as text when it has no icon yet, same
  "functional-before-art" fallback used everywhere else in this project. Clicking a tile opens a
  second panel, `invDetailFrame`, positioned just right of the Inventory (`showInvDetail(category,
  key)`) — bigger image, stats line, description, and for Weapons/Robots only: the same 3 mod-slot
  buttons the old row version had (`rebuildInvDetailSlots`, reusing the existing mod picker
  popup unchanged) plus the Equip/Deploy-Undeploy action button. Mods/Materials tiles open the same
  panel with those two hidden — nothing to equip or slot into for a raw mod/resource on its own.
  `refreshInvDetailIfShowing` re-populates the open detail panel whenever `InventoryUpdate` patches
  the profile, so equipping something updates the button/stats in place without needing to
  re-click the tile. The old row-only helpers built for Inventory specifically (`makeInfoRow`,
  `makeStatRow`) were deleted once nothing referenced them anymore — `makeRow`/`makeEquipmentRow`
  (used by the Workbench) were untouched.

  Icons: `ReplicatedStorage.ItemIcons` (a plain `Folder`, declared in `default.project.json`, NOT
  `$path`-synced so Rojo leaves anything manually added inside it alone across syncs — same
  pattern as the `Remotes` folder). Drop an `ImageLabel`/`ImageButton`/`Decal` in there named
  EXACTLY like the item's key (a weaponKey/robotKey/modKey, an oreKey, or the literal strings
  `"Scrap"`/`"Cores"`) and set its `Image` (or `Texture`) property via Studio's normal asset
  picker — `getItemIcon` (`MainHud.client.lua`) reads only that one property, so nothing else
  about the instance (size, position, anything) matters. No matching instance = the tile/detail
  panel just falls back to no image, no code changes needed either way.

  Descriptions live in code now, next to each item's other data, per direct instruction ("just
  make somewhere on the code for the description"): `CraftingRecipes.lua`'s Weapons/Robots entries
  and `OreConfig.lua`'s Ores entries each got a `Description` field this session (`ModConfig.lua`'s
  mods already had one from earlier). Scrap/Cores aren't real ore entries anywhere, so their
  descriptions are just inlined in `showInvDetail` instead of a shared config table.

  Materials tab absorbed the top-left readout's old ore breakdown (plus Scrap/Cores shown again
  for a complete picture) as tiles now too — `currencyFrame` up top stays trimmed to just
  Scrap/Cores/Energy. Forward-compatible with the planned Forge/smelting mechanic below — refined
  materials just need adding to `renderInvMaterials`'s list, no new tab or icon-lookup change
  required.
- **Forge / weapon rarity, Luck & Pity — BUILT.** Requested right after the Inventory panel
  shipped: "do you think we should add modifiers on guns whenever they are crafted, with items
  that boost the players luck to get better stats and stuff, just like the game forge yk." Three
  design decisions confirmed with the player up front: every weapon Forged is its own unique
  instance (not a shared type-level roll), Luck works BOTH as a permanent upgradeable stat AND a
  consumable item, and yes, this should finally activate `ModConfig.Rarities` (which had sat at
  one populated tier, Common, since it was first built as a placeholder).

  This is the single biggest structural change of the session — weapon *ownership* itself changed
  shape, from "do I have this type, yes/no" to "how many of these do I have and what did each one
  roll." Shipped in two passes: an initial build, then a revision right after playtesting it.

  **Initial build:**

  - **`ForgeConfig.lua` (new)** — every tunable number: `RarityOrder`/`BaseWeights` (relative odds
    at zero luck: Common 100, Uncommon 40, Rare 15, Epic 5, Legendary 1), `AffixCountByRarity`
    (0/1/2/2/3 bonus affixes per rarity tier), `AffixPool` (Damage/Fire-Rate-boosting affixes, each
    with a Min/Max roll range), a permanent Luck-tier track, and a one-roll consumable Luck item.
  - **`ModConfig.Rarities` expanded** from just `Common` to Common/Uncommon/Rare/Epic/Legendary,
    each with a `DisplayName`, a 1-letter `Badge` (for tile corners), and a `Color`. Mods themselves
    are still all Common — this table is now shared infrastructure the Forge actually uses, mods
    just haven't grown a rarity-drop system of their own yet.
  - **`DataService.lua`** — `profile.Weapons` (list of `{ Id, WeaponKey, Rarity, Affixes }`
    instances) and `profile.NextWeaponId` (mints `"w1"`, `"w2"`, ... — never reused) replace the old
    flat `profile.CraftedWeapons` boolean set as the source of truth for weapon ownership.
    `CraftedWeapons` itself stays in the schema, now purely as migration input (see below) — nothing
    writes a new `true` into it anymore. `profile.EquippedWeaponId` replaces `EquippedWeapon`
    (references an instance Id, not a type). **Migration:** `migrateLegacyWeapons` runs once per
    `loadProfile` call and converts any pre-Forge `CraftedWeapons[key] = true` entries into
    Common-rarity, zero-affix `Weapons` instances — self-guarding (only runs while `Weapons` is
    still empty AND `CraftedWeapons` has legacy entries), so existing players' weapons aren't
    deleted, just upgraded into the new shape the first time their save loads under this system.
  - **`ForgeService.lua` (new)** — `ForgeWeapon` spends the recipe's normal
    `CraftingRecipes.Weapons[key].Cost`, rolls a rarity (`rollRarity`: every non-Common tier's
    weight scales by `1 + luckPoints/100`), rolls that rarity's affix count from `AffixPool`
    (`rollAffixes`, deduped by affix Key so the same flavor never lands twice, though two different
    Damage-boosting affixes both landing is a real if rare outcome), and mints a new instance —
    first weapon ever Forged auto-equips, every roll after that is an explicit `EquipWeapon` choice.
  - **`CombatMath.lua`** — new `GetEffectiveWeaponStats(weaponInstance, profile)` layers the
    instance's rolled `Affixes` multiplicatively on top of the existing type-level mod multipliers
    (`applyMods`, unchanged). `GetPlayerCombatDPS`'s weapon half now resolves `EquippedWeaponId` to
    a specific instance (falling back to auto-picking the highest-DPS owned instance, same "explicit
    choice wins, else auto-best" shape as before) instead of a type key.
  - **`CraftingService.lua`** — `CraftItem` now rejects `tree == "Weapons"` outright (points players
    at the Forge instead of silently doing nothing). `EquipMod`'s station gate now depends on tree:
    Weapons gates to the Forge, Robots still gates to Welding — and its weapon-ownership check
    changed from `CraftedWeapons[itemKey] == true` to "does the player own ANY Forged instance with
    this `WeaponKey`," since mod slots stay per weapon TYPE (unchanged design, see `ModConfig.lua`'s
    header comment) even though individual weapons are now per-instance.
  - **`StationConfig.lua`** — `Welding.Tabs` dropped `"Weapons"` (now just Robots/Mods,
    `DefaultTab` moved to `"Robots"`); `Forge.Tabs` gained `{ "Weapons" }` with
    `DefaultTab = "Weapons"` — the Forge finally has a real menu instead of the placeholder
    "doesn't do anything yet" click response.

  **Revision, right after the player tried it:** three pieces of direct feedback on the same
  screenshot — "why are the equipping buttons here, take them out, they are just to craft here,"
  "make a pity system... whenever you craft a gun," "the luck should increase by forge tier," and
  "the charm stuff would be more potions or smth like that."

  - **Equip buttons removed from the Forge's Weapons tab entirely.** The initial build listed every
    owned instance right below the roll buttons via `makeWeaponRow(instance)`, each with its own
    Equip button and mod slots — which just duplicated the Inventory panel on the same screen and
    made "click Forge" and "click Equip" easy to fumble together, per the player's own framing
    ("they are just to craft here"). `makeWeaponRow` and the owned-instance loop were deleted from
    `MainHud.client.lua` outright; the Forge's Weapons tab (`renderForgeWeapons`) now shows only
    Luck/Pity status, the roll buttons, and a "Last Forged: [Rarity] Name" readout so a roll still
    gives immediate feedback without listing everything you own. Equipping, mod slots, and browsing
    owned weapons are Inventory-panel-only now — `EquipWeapon` is still gated to the Forge
    server-side, it's just never called from the Forge's own tab anymore.
  - **Pity system — new.** `ForgeConfig.Pity` (`Threshold = 15`, `MinRarity = "Rare"`) and
    `profile.ForgePityCounter` (increments every roll, resets to 0 the instant a roll — forced or
    natural — lands `MinRarity` or better). Once the counter reaches `Threshold`, `ForgeWeapon`
    calls `rollRarity` with a floor index locking the roll to `MinRarity` and up (`rollRarity`
    gained an optional `floorIndex` parameter for this — same weighted math, just restricted to a
    tier subset), so a genuinely unlucky streak is guaranteed to pay off without ever going below
    the guaranteed floor exactly (still randomized which of Rare/Epic/Legendary you actually land
    on). Originally shown as a plain text row inside the Forge's Weapons tab; moved to a persistent
    HUD bar the very next round of feedback — see below.
  - **Luck reframed as your Forge's own tier, not an abstract stat.** `ForgeConfig.LuckTiers`
    renamed to `ForgeTiers` (values unchanged: 0/15/35/60 bonus luck across 4 tiers), themed as
    upgrading the physical station itself ("Scrap Forge" -> "Reinforced Forge" -> "Tempered Forge"
    -> "Masterwork Forge") rather than charm-flavored names — a better Forge just rolls luckier,
    full stop. `profile.LuckTier`/`UpgradeLuck` renamed to `profile.ForgeTier`/`UpgradeForgeTier`
    throughout (`ForgeService.lua`, `DataService.lua`, the HUD). No migration needed for the rename
    itself — `backfillMissingFields` just defaults `ForgeTier = 1` for any save that predates it;
    the old `LuckTier` key, if present on disk, is simply never read again.
  - **Luck Charm renamed to Luck Potion.** `ForgeConfig.LuckCharm` -> `LuckPotion`,
    `profile.LuckCharms` -> `LuckPotions`, `CraftLuckCharm` remote -> `CraftLuckPotion` — same
    mechanic (flat-craftable consumable, burned on one roll via a client-side toggle, server
    re-validates ownership regardless so the toggle can never desync into spending one that isn't
    there), reflavored per direct request ("the charm stuff would be more potions or smth like
    that"). Every `default.project.json` remote name updated to match.
  - **Inventory panel's Weapons tab is unaffected by any of this** — `renderInvWeapons`/
    `showInvDetail` already lived entirely in the Inventory (tiles use the weapon TYPE's icon,
    select by instance Id, rarity `Badge` in the tile corner, full affix summary in the detail
    panel's description) and remains the sole place to equip a Forged weapon or manage its mod
    slots.

  **Second revision, immediately after seeing the first one in Studio:** the Pity row and the
  Potion toggle row were still just plain text rows inside the Forge menu — the player asked for
  both to become persistent HUD elements instead: "make the pity a bar that is under the hud, that
  has a progression hud, and a number of current/total, the potion should also be like a button
  outside of the main gui, like a square and icon placeholder so you can click on it and consume a
  potion for the next role."

  - **Pity bar — new persistent widget.** A small always-visible panel (`pityBarFrame`) parented
    directly to `screenGui`, positioned just under the top-left currency readout (not inside
    `craftFrame` at all anymore) — a caption reading `Forge Pity: N / 15 (Rare+)` above a track/fill
    progress bar (`pityTrack`/`pityFill`, same two-frame pattern as the wave/raid panels'
    `makeBar` helper), fill width driven by `counter / Threshold` clamped to `[0, 1]`. Refreshed via
    a `refreshPityBar()` function called from the `InventoryUpdate` listener, the initial
    `GetProfile` bootstrap, AND immediately inside the Forge roll button's success callback (for
    snappier feedback than waiting on the follow-up `InventoryUpdate` broadcast, though the counter
    itself is server-authoritative so that immediate call is mostly a no-op until the real patch
    lands a moment later — harmless, not misleading, just occasionally redundant). The "Pity" text
    row was deleted from `renderForgeWeapons` entirely.
  - **Luck Potion button — new persistent widget.** A 64x64 square `ImageButton`
    (`potionButton`), also parented to `screenGui`, sitting just below the pity bar in the same
    left-side column — icon via `getItemIcon("LuckPotion")` (same icon-folder convention as
    everything else; add an image named exactly `LuckPotion` to `ReplicatedStorage.ItemIcons` to
    give it real art) with a plain-text placeholder fallback and a corner badge showing
    `profile.LuckPotions`. Clicking it toggles `forgeUsePotion` — the exact same client-side
    one-shot-toggle variable the old in-menu row flipped, just moved to a different piece of UI —
    and highlights (`COLOR.AccentDark`) while armed. The Forge roll buttons still read
    `forgeUsePotion` at click time exactly as before; nothing about `ForgeWeapon`'s server contract
    changed, only where the toggle lives visually. The "Use a Potion on next roll" text row was
    deleted from `renderForgeWeapons` entirely.
  - Both widgets needed `local refreshPityBar` / `local refreshPotionButton` forward-declared up in
    the Forge tab section (same forward-reference pattern `renderCraftList` already used) — the
    Forge roll button is defined earlier in the file than these widgets (the potion button
    specifically needs `getItemIcon`, which only exists once the Inventory panel section has run),
    but still needs to call them the instant a roll resolves.

  **Third revision, right after that:** the two widgets being permanently visible (parented
  straight to `screenGui`, always `Visible = true`, sitting in their own top-left column) turned
  out to read as clutter the rest of the time — "currently the pity and all that appears even when
  the forge UI is not open, please only have the pity appear when the forge UI is open, and make
  it under the forge GUI please for some cool layout thing, and make the potion close to the forge
  UI too."

  - **Both widgets now dock directly under `craftFrame`** instead of living under the currency
    readout — `potionButton` is a fixed 64-wide square flush with `craftFrame`'s left edge,
    `pityBarFrame` fills the remaining width out to `craftFrame`'s own right edge, both starting
    10px below its bottom edge and vertically centered against each other. Together they read as
    one row attached to the bottom of the Forge menu rather than two unrelated panels bolted to a
    random corner of the screen.
  - **Both start `Visible = false`** and are only ever shown while the Forge specifically is open.
    New `setForgeWidgetsVisible(visible)` toggles both together (so a future edit can't accidentally
    update one and forget the other) — called `true` from `openStationMenu` only when
    `stationData == StationConfig.Types.Forge` (an identity check against the specific table in
    `StationConfig.Types`, since `openStationMenu` is shared across every station type and
    `stationData` doesn't otherwise carry a type key back with it), and called `false`
    unconditionally from `craftCloseButton`'s handler regardless of which station's menu was open.
  - **`actionRow` (Inventory/Start Defense/etc.) hides while the Forge widgets are up.** On shorter
    viewports the docked row sits low enough to overlap the bottom action row — screenshotted by
    the player. `setForgeWidgetsVisible` now also sets `actionRow.Visible = not visible`, so the
    action row disappears the instant the Forge opens and comes back the instant it closes.
    `local actionRow` joined the same forward-declaration cluster as `refreshPityBar`/
    `refreshPotionButton` up in the Forge tab section, since `setForgeWidgetsVisible` (defined
    there) needs to reach a Frame that isn't actually created until the "Bottom action buttons"
    section much further down.
- **Ore smelting (separate Forge mechanic) — BUILT.** A second, independent thing the Forge does
  alongside weapon Forging: the Forge's new `"Smelting"` tab (`StationConfig.Types.Forge.Tabs` is
  now `{ "Weapons", "Smelting" }`) turns raw ore into refined material, one job at a time per
  player. Config lives in the new `RefinedOreConfig.lua`: `Ores[oreKey] = { RefinedKey,
  DisplayName, Description, RefineRatio }` (raw ore consumed per 1 refined unit — 3:1 for Scrap
  Iron/Copper Wire, 2:1 for Steel Plating/Gold Contacts, 1:1 for Voidium Shard, all easy to
  rebalance) plus `ByRefinedKey` (a reverse index built once at load time, since UI code looks
  things up by `RefinedKey` more often than by the raw ore key) and `SmeltTime = { BaseSeconds,
  LogSecondsPerOre, TickSeconds }` behind the batch-time formula, `ComputeSmeltSeconds(quantity)`:
  `BaseSeconds + LogSecondsPerOre * math.log(quantity)` — an actual logarithm, so time-per-raw-ore
  (`ComputeSmeltSeconds(quantity) / quantity`) strictly decreases as the batch gets bigger, per the
  literal ask ("the more you put the less time it is per ore"). Shared between server and client
  so the formula only lives in one place; the client uses it to show an estimated time before a
  job even starts, not just to render the countdown once one's running.

  New `SmeltService.lua` (mirrors `ForgeService.lua`'s station-gate pattern) owns the `StartSmelt`
  remote: validates the ore key, that `quantity` is a positive multiple of that ore's
  `RefineRatio`, and that the player owns enough; rejects outright if `profile.SmeltJob` is already
  set (one job at a time); deducts the raw ore immediately and sets `profile.SmeltJob = { OreKey,
  Quantity, RefinedKey, RefinedAmount, FinishTime }` (`FinishTime = os.time() + duration` —
  timestamp-based, not tick-accumulation). A shared `task.spawn` loop, same one-loop-for-every-
  player pattern as `AutoMinerService.lua`, checks every connected player's `SmeltJob` every
  `SmeltTime.TickSeconds` and once `FinishTime` has passed grants `RefinedOreCounts[RefinedKey] +=
  RefinedAmount` (via new `DataService.AddRefinedOre`, mirroring `AddOre`) and clears the job —
  this naturally supports a job finishing while the player's offline, no separate catch-up logic
  needed. `DataService.defaultProfile()` gained `RefinedOreCounts = {}`; `profile.SmeltJob` is
  deliberately NOT in `defaultProfile()` at all, same reasoning as `EquippedWeaponId` — nil reads
  identically whether the key is present-and-nil or simply absent, and every broadcast of it uses
  `SmeltJob or false` so a clear actually survives the table literal instead of silently vanishing.

  `MainHud.client.lua`'s Smelting tab is one square panel (per the exact "background that is like
  a square" ask) with three states, picked by `profile.SmeltJob` first (server-authoritative, wins
  over everything) then a client-only `smeltSelectedOreKey`/`smeltQuantity` pair: (1) nothing
  picked — one big centered icon button that opens a new `orePickerFrame` popup, a grid of your
  owned raw ore (reusing `makeItemTile`/`getItemIcon` from the Inventory panel, filtered to ores
  you own at least one legal batch of); (2) an ore picked — a quantity readout plus a "Reset" (back
  down to one batch) and a row of four bulk-add buttons (`+1`/`+10`/`+100`/`MAX`, revised from an
  initial lone +/- stepper per direct feedback that it was too slow for stocking up a big batch) —
  all four ADD BATCHES (`RefineRatio`-sized steps), not raw ore one at a time, so the quantity
  landed on is always a legal multiple with no rounding needed, clamped to what you own; an
  estimated-time readout; and a "Smelt" button that only appears once something's actually
  selected; (3) a job running — a countdown
  ("Ready in M:SS") and a progress bar, kept live by a dedicated `task.spawn` loop that re-renders
  the tab once a second while it's open and a job is active (since `InventoryUpdate` patches only
  arrive on start/finish, not every tick in between). `renderSmeltingTab` is forward-declared in
  the same cluster as `refreshPityBar`/`refreshPotionButton`/`actionRow`, same reason as those:
  `renderCraftList`'s dispatcher (defined earlier in the file) needs to call it, but its real
  definition needs `getItemIcon`/`makeItemTile`, which aren't available until the Inventory panel
  section runs. The Inventory panel's Materials tab now also shows refined materials (only once
  you own at least one of a given kind, unlike raw ore/currency which always show a tile even at
  zero) — exactly what that function's own pre-existing comment anticipated, no new Inventory tab
  needed.

  Deliberately still out of scope: rewiring `CraftingRecipes.lua`/`ModConfig.lua`'s `Cost` tables
  to actually require refined materials as crafting inputs. Right now refined materials accumulate
  and display but aren't spendable anywhere — that's its own follow-up task.

  **Numbers I picked myself, worth a playtest before treating as final:** the exact RefineRatios
  (3:1/3:1/2:1/2:1/1:1), the refined-material names (Steel Ingot/Copper Coil/Hardened Plate/Gold
  Bar/Voidium Core), and the time-formula constants (`BaseSeconds = 20`, `LogSecondsPerOre = 24` —
  a 3-Scrap-Iron batch takes ~20 + 24*ln(3) ≈ 46s total, a 300-Scrap-Iron batch takes
  ~20 + 24*ln(300) ≈ 157s total, i.e. only ~3.3x longer for 100x the ore, ~0.52s per ore vs. ~15.5s
  per ore for the small batch — batch time still climbs at a real pace instead of flattening out
  almost immediately, per direct feedback that the original `LogSecondsPerOre = 8` made "the
  seconds added get too little pretty fast." `SmeltService.lua`'s `StartSmelt` handler has a
  comment marking exactly where to multiply the computed duration for a future "Smelt Speed"
  gamepass/upgrade — not built yet, just left room for).
- **Base defense minigame — HALF BUILT, see "Combat Engine" section below.** Player feedback
  while planning the base layout: base-defense (`WaveService`'s "Start Defense") should give
  players more to actively DO while defending, not just watch a headless DPS-vs-enemy-HP-pool
  simulation tick by. The interactive half of that ask — real enemies, real aiming/shooting, real
  Humanoid health as the loss condition — is now built; see the Combat Engine section for the full
  writeup. The other half the player's own phrasing implied — placeable defense structures
  physically sitting in the base — is now BUILT too, see the "Base building/tiers" and "Turrets"
  bullets below (the "Base Defense & Turrets" phase this comment used to point forward to).
- **Crafting process** — smelting, wiring, etc. as actual steps with a "cute" animation, not an
  instant craft. Build the functional version first (a timed progress bar the player waits out,
  no art) before layering the animation/juice on top — same systems-then-art approach as
  everything else in this project.
- **Base building/tiers — BUILT.** The player upgrades the base itself to get stronger and defend
  against more. The loading half already existed (`BaseConfig.Tiers`/`profile.BaseTier`/
  `BaseService.RebuildPlayerBase`, see Base plots above) — this phase added the purchase/unlock
  side: a new `UpgradeBase` RemoteFunction (`BaseService.lua`) spends `BaseConfig
  .BaseTierCosts[nextTier]`, bumps `profile.BaseTier`, and calls `RebuildPlayerBase` again to swap
  the physical Model in place — same sequential-tier shape and gating as `UpgradeTool`/
  `UpgradeSuit` (plot + `StationService.IsPlayerNearStation(player, "Crafting")`, i.e. the
  Workbench). `BaseConfig.Tiers` grew from 2 entries to 4 (`Fortified Bunker`/`Bastion` added,
  `WallHP` 150/300/550/900) so there's a real ladder to climb. HUD: new "Base" tab on the
  Workbench menu (`StationConfig.Types.Crafting.Tabs`), `renderBaseRow` in `MainHud.client.lua`,
  same row shape as `renderToolRow`/`renderSuitRow`.

  **Original scope cut, since RESOLVED (Base Defense & Turrets phase round 2):** the note above
  used to flag that tier advancement wasn't gated behind "beating a specific wave milestone, or
  getting a drop from a wave boss past a certain wave" since base defense had no boss concept yet.
  It does now — see "Wave defense rewards — REWORKED (boss waves + Core items)" below.
  `BaseConfig.BaseTierCoreRequirement[nextTier]` (`{[2]={Key="CoreT1",Amount=1}, [3]={Key=
  "CoreT2",Amount=1}, [4]={Key="CoreT3",Amount=1}}`) is now checked in `BaseService.UpgradeBase`
  ON TOP OF (not instead of) the existing `BaseTierCosts` resource cost — both must be satisfied,
  cost is spent first via the existing `TrySpend`, then the CoreItem via the new
  `DataService.TrySpendCoreItem`, and the pre-check reads both BEFORE either commits so a
  half-affordable upgrade never partially spends. Exactly the wave-boss-drop gate this bullet used
  to defer.
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
- **Turrets — REBUILT as a fully independent system (Base Defense & Turrets phase round 2),
  SUPERSEDING everything the previous draft of this bullet described.** Direct instruction after
  seeing round 1 (every deployed robot getting a physical body): turrets should be their own
  first-class thing — bought as blueprints from a Hub Shop, placed into a limited number of fixed
  base slots, leveled up individually with an exponential Cores cost, no mod slots (only distinct
  hardcoded varieties), and gated into higher tiers by a not-yet-built Research system. Round 1's
  entire `DeployedRobots`-as-turret approach is retired — `CraftingRecipes.Robots`/`DeployedRobots`/
  `RobotBehaviorConfig`/`RobotBehaviors.lua` are all UNTOUCHED and still 100% power raid combat
  support (`RunRaidCombat`); they just no longer double as "the turret system," and
  `profile.TurretPlacements` (round 1's placement data) is gone, replaced by the model below.

  **Data model** (`DataService.lua`'s `defaultProfile`): `profile.Turrets` — a flat list of owned
  turret instances, `{Id, TypeKey, Level, SlotIndex?}` (`SlotIndex` omitted = sitting in Storage,
  unplaced); `profile.UnlockedTurretBlueprints[typeKey] = true` once bought (currently just a
  flavor/history flag — buying twice mints two independent instances, nothing stops it);
  `profile.NextTurretId` (monotonic counter, `"t1"`, `"t2"`, ...); `profile.ResearchTier` (see the
  skeleton bullet below); `profile.CoreItems[coreKey]` (see the wave-rewards bullet below).

  **Hub Shop — BUILT** (`TurretConfig.lua`, `TurretShopService.lua`, `StationConfig.Types.Shop`).
  A physical Station, per direct instruction, located OUTSIDE any player's base — "somewhere, like
  a HUB," a SHARED world location every player can reach, not gated behind `PlotService
  .IsPlayerInOwnPlot` the way base stations are (only `StationService.IsPlayerNearStation(player,
  "Shop")`); this relies on the existing behavior that a `Station`-tagged instance with no
  `OwnerUserId` attribute (i.e. not cloned into any player's plot) stays open to everyone. Stock
  rotates every `TurretConfig.ShopRotationPeriodSeconds` (6h), 3 of 6 `TurretConfig.Types` visible
  at once, via `GetRotatingStock(now)` — a PURE function of wall-clock time (a small self-contained
  sine-hash Fisher-Yates shuffle, deliberately NOT `math.random`/`math.randomseed`, so looking up
  the stock never perturbs the game's global RNG state as a side effect). Client and server each
  call it independently and always agree, no remote round-trip needed to know what's for sale;
  `TurretShopService.BuyTurretBlueprint` still re-derives it server-side rather than trusting
  whatever the client claims it saw. Buying spends `typeData.BlueprintCost` (Cores) and mints a
  brand-new unplaced instance straight into `profile.Turrets` — there's no separate "craft with raw
  materials" step, the blueprint purchase IS how you get the turret.

  **6 Types, no mods** (`TurretConfig.Types` — Pulse/Flak/Sniper/Arc/Mortar/Rail), each a fixed
  `Range`/`FireRate`/`BaseDamage`/`AOE` (how many nearest-in-range targets one shot hits — 1 =
  single-target)/`ParticleColor`. Per direct instruction, all variety lives here, not in equippable
  modifiers — Pulse is cheap/rapid/short-range, Flak is a wide multi-target burst, Sniper/Rail are
  slow heavy single-target at real range, Arc chains to several mid-range targets, Mortar is the
  extreme long-range/huge-splash/very-slow end. Numbers are a first guess, worth a playtest.

  **Leveling — every placed instance levels up independently**, exponential Cores cost per direct
  instruction: `GetTurretUpgradeCost(level) = floor(20 * 1.2^(level-1))` (+20%/level — "grind a
  little to max it out"). Every `LevelsPerTier = 10` levels bumps the turret's internal Tier
  (`GetTurretTier(level) = floor((level-1)/10)+1`); effective stats
  (`GetTurretEffectiveStats`) scale Damage +8%/level and Range/FireRate a deliberately mild
  +2%/level, plus a flat +15% Damage bonus per Tier crossed, so crossing a Tier feels like a real
  breakthrough, not just "10 more levels of the same slope." **Crossing into a new Tier additionally
  requires `profile.ResearchTier` to have caught up** — see the skeleton bullet below; this is a
  deliberate gate, not a bug, until Research ships for real.

  **Slots — fixed count per base, per direct formula:** `GetSlotCount(researchTier)` — Research
  Tier 1 = 2 slots baseline, then each subsequent ODD tier adds 1, each EVEN tier adds 2. Slots are
  fixed evenly-spaced ring positions (`TurretService.ringPosition`, reusing the same math round 1
  used), not freeform placement anymore — `PlaceTurretInSlot(turretId, slotIndex)` moves an owned
  instance into a specific numbered slot (rejects an already-occupied slot), `UnplaceTurret(turretId)`
  sends it back to Storage, `UpgradeTurret(turretId)` spends Cores and bumps Level (both plot-gated
  via `PlotService.IsPlayerInOwnPlot`, since placement/leveling — unlike buying the blueprint — does
  happen in your own base). **Direct request: "make sure the player is able to see possible slots
  where they can put their turret"** — every EMPTY slot gets a real physical marker in the world too
  (`TurretService.buildSlotMarker`: a translucent neon pad + floating BillboardGui), not just an
  occupied/nothing binary. Base physical size growing alongside Research
  Tier (to make room for the growing slot count) is a Studio-authoring/art concern, not something
  code auto-generates — flagged for whoever builds the BaseTier Models next, not deferred silently.

  **Placement is IN-WORLD, not a menu (revised after playtest — the first pass was half-baked).**
  Originally every slot was a row in the Workbench's Base tab: one row per slot, an Unplace row
  under each occupied one, and a "Storage" list whose Place button silently auto-picked the first
  open slot. That made "which slot" not a real choice and put turret management nowhere near the
  turrets. Now **clicking a slot in the world is the interaction** — direct instruction: *"when you
  click the blue turret zone it opens up your turret inventory and you can place down turrets that
  you own, not something that you change on the base tab on the crafting table."*
  `TurretService.makeSlotInteractive` tags every slot (empty pad AND placed turret alike)
  `TurretSlot`, stamps `SlotIndex`/`OwnerUserId`, and parents a named `SlotClick` ClickDetector;
  `MainHud.client.lua`'s `setupTurretSlot`/`openTurretPanel` render a popup that shows either your
  unplaced turrets (empty slot → "Place here") or the occupant's live stats with Upgrade/Unplace
  (occupied slot). Interaction range is `TurretConfig.SlotInteractDistance` (24 studs — roomier
  than `StationConfig.InteractDistance` on purpose, since the slot ring sits out near the plot
  edge). The Base tab keeps only what has no physical thing to click: the BaseTier upgrade and the
  Research/slot-count readout, plus a placed/stored count pointing at the pads.

  **Combat resolution moved OUT of the placement layer**, unlike round 1 (which left combat fully
  abstract): `CombatEncounterService.lua`'s new local `fireTurrets(turretRecords, aliveEnemies, now)`
  — called only from `RunWave` (base defense), never `RunRaidCombat` — owns real range-checked
  targeting from the TURRET's own `WorldPosition` (not "nearest to the player," genuinely different
  from how Robots target), sorted by distance-to-turret, hitting up to `AOE` nearest-in-range targets
  per shot on the turret's own `FireRate` cooldown. **Direct request: "make sure turrets shoot a
  particle when they are shooting smth so it looks cool"** — each turret Model gets (or
  auto-creates) a "Muzzle" Attachment holding a manual-emit `ParticleEmitter` tinted via the type's
  `ParticleColor`; on fire, the Muzzle's `WorldCFrame` is pointed roughly at the primary target
  (`CFrame.new(origin, target)`) and `emitter:Emit(14)` fires. Damage itself still resolves
  instantly under the hood (no real projectile/hit-detection tied to the burst) — same "the particle
  sells it, the number just moves" approach the player's own hitscan weapon already uses.

  **Research Tier — SKELETON ONLY, per direct instruction ("just have some skeleton or smth as a
  placeholder until we have the real deal").** `profile.ResearchTier = 1`, no purchase/progression
  flow exists yet at all — it only feeds `GetSlotCount` and the turret Tier-crossing gate above.
  Building the real Research system (how it's earned, what else it unlocks) is explicitly the next
  roadmap step, not this one.

  **Deliberately deferred, not an oversight** (carried over from round 1, still true): turrets have
  no HP and can't be destroyed — enemies still only ever attack the base/wall, never a turret
  specifically, so nothing forces destructibility onto the physical layer either. Also still no true
  projectile-travel physics — the muzzle burst is a cosmetic sell, not a simulated bullet.

  HUD (`MainHud.client.lua`): the Workbench's "Base" tab now shows a Research Tier readout, one row
  per fixed slot (occupied slots show type/Level/Tier plus stats and an Upgrade button — locked to
  "Needs Research T`n`" once a Tier-crossing upgrade would require Research the player doesn't have
  yet — and a separate Unplace row; empty slots show a plain placeholder row so the slot COUNT is
  always visible even with nothing placed), then a Storage section listing bought-but-unplaced
  instances with a one-click "Place" that auto-picks the first open slot (no drag-and-drop/picker
  UI — simplest thing that works, matches this project's "functional before art" default
  everywhere else). A new "Blueprints" tab (`StationConfig.Types.Shop`) renders the Hub Shop's
  current rotating stock with Buy buttons.
- **Wave defense rewards — REWORKED into boss waves + Core items (Base Defense & Turrets phase
  round 2), per direct instruction: "this wave defense system will not reward the player with
  scraps or stuff like that, it will only reward the core stuff, and maybe some utility items here
  and there."** Base defense grants NO Scrap/Cores at all anymore —
  `WaveConfig.GetScrapReward`/`GetCoresReward` are left defined (some future pacing mechanic might
  want them) but nothing calls them. Every `WaveConfig.EliteWaveInterval`-th wave (5, 10, 15, ... —
  cadence, and the underlying spawn mechanism, both UNCHANGED from before; only the REWARD changed,
  a deliberate scope simplification vs. building a whole separate boss-arena encounter) is now a
  full BOSS WAVE: clearing it GUARANTEES one CoreItem via `RewardTables.CoreKeyForMilestone
  (WaveConfig.BossMilestoneIndex(wave))` → `DataService.AddCoreItem(player, coreKey, 1)` —
  `"CoreT1"`/`"CoreT2"`/`"CoreT3"` for milestones 1/2/3, clamped at the highest configured tier so a
  long run (wave 20+) keeps dropping the same top-tier core rather than erroring. Placeholder names,
  per direct instruction ("i will be changing the names later"). Boss waves also roll
  `RewardTables.Roll("BossUtility")` (35% chance each of a Wave Revive Token / Instant Craft Token);
  regular waves roll `RewardTables.Roll("RegularUtility")` (8% chance each) — "maybe some utility
  items here and there." `RewardTables.Roll`'s own shape (pure lookup + independent per-entry chance
  roll, returns a `{Type, Key, Amount}` list) is unchanged from before this rework, only the tables
  themselves and their `Type = "Utility"` entries are new; `DataService.AddCurrency` (already generic
  enough to increment any flat profile field, same mechanism `ShopService` uses for
  `InstantCraftTokens`/`WaveReviveTokens`) needed zero changes to route them. `CoreItems` feed
  straight into `BaseConfig.BaseTierCoreRequirement` — see the "Deliberate scope cut... RESOLVED"
  note under "Base building/tiers" above.

## Combat Engine — BUILT

Phase 1 of the endgame roadmap (see the published roadmap for the full pathway). Replaces
`WaveService`'s old headless simulation — compare total DPS against an abstract enemy HP pool
once a second, chip an abstract "objective" HP down — with real spawned enemies and real per-hit
damage resolution. Scoped deliberately narrow: **only `WaveService.lua` (base defense) was
rewired this pass.**
`NodeService.lua`'s raid Combat Outposts still use their old chip-damage-per-second placeholder
— wiring them into this engine is deferred to the Raid Rooms roadmap phase, so they have somewhere
physical to spawn enemies into first rather than reusing base defense's open-plot spawn logic.

**Enemy theme:** two hostile factions, sharing one metatable-based config —
`ReplicatedStorage/Shared/EnemyConfig.lua`. `local function defineEnemy(base, overrides) return
setmetatable(overrides, {__index = base}) end` layers a per-type override table on top of a
shared faction template, so a field a specific enemy type doesn't define falls through to its
faction's default automatically. `ConstructBase` (Rogue Constructs — malfunctioning machinery,
slower/tankier, `Defense=12`) and `RebelBase` (Mad-Max-style Rebels — faster/squishier,
`Defense=4`) are the two templates. Regular types: `Scavenger`/`Raider`/`Brute` (Rebel),
`ScrapCrawler`/`SentinelDrone` (Construct). One elite type exists already, `VoidwakenHulk`
(`EnemyConfig.EliteTypes`, HP=220) — its comment plants the seed for a future boss-drop reward
hook (Research Level's "Special Core") without implementing that hook yet.

**Damage resolution** — `ServerScriptService/Services/DamagePipeline.lua` — is an ORDERED LIST of
small modifier steps (`DamagePipeline.Steps`), not one big formula, specifically so balancing
later means "add/remove/reorder a step," never "untangle a function that does five things at
once." Today's three steps, in order: `RangeFalloff` (optional per-weapon `RangeProfile` —
`{FalloffStart, FalloffEnd, MinMultiplier}` — nil on a weapon means this step is a no-op, so most
of `CraftingRecipes.Weapons` never needs to know it exists; only shotgun/sniper-flavored weapons
should bother setting one), `DefenseMitigation` (RATIO-based, not flat — `damage *
100/(100+effectiveDefense)`, chosen specifically so a heavily-defended target is never literally
unkillable to a weak weapon the way flat subtraction hitting 0 would allow; `Penetration`, an
optional field on the hit packet, reduces the target's effective defense before the ratio runs),
`MinimumFloor` (absolute floor of 1 damage, same "never truly unkillable" reasoning). Order is
meaningful, not cosmetic — see the file's own header for why a future additive step (e.g. a flat
"weak point" bonus) would care where in the list it sits, even though today's three steps all
happen to be multiplicative and therefore commute.

**Server authority:** everything mechanical/logical resolves server-side, on purpose, to close
off exploits — the client only ever reports a CLAIMED hit (which Instance, claimed origin,
claimed hit position) via a new `RequestFireWeapon` RemoteEvent; the server independently
resolves the real enemy record via trusted instance lookup (rejecting anything not in that
player's own active encounter), sanity-checks the claimed origin against the server-known player
position (`ORIGIN_SANITY_STUDS = 12`), recomputes base damage entirely server-side from
`CombatMath.GetEffectiveWeaponStats` (the existing mod+affix-aware source of truth — unchanged),
and enforces the weapon's real fire-rate cooldown server-side. The client cannot inject a damage
number no matter what it sends. Visuals (a cosmetic tracer) stay client-only so the server isn't
spending cycles on anything nobody needs it to compute.

**AI and robot participation** both follow the SAME pre-existing convention this codebase already
uses for background loops (AutoMinerService/SmeltService): one shared per-encounter tick loop
(`CombatEncounterService.RunWave`, `TICK_SECONDS = 0.15`) iterates every live enemy and every
deployed robot once per tick, NOT one coroutine per entity.
`ServerScriptService/Services/EnemyAI.lua` is a flat table of named patterns looked up by
`EnemyConfig.Types[key].AIPattern` — only `Chaser` exists today (walk at the target, deal
`ContactDamage` on a cooldown once in range), deliberately the only pattern for this first pass;
a new pattern is one new function plus pointing an `EnemyConfig` entry at its name.
`ServerScriptService/Services/RobotBehaviors.lua` is the same shape for robots, looked up by
`RobotBehaviorConfig.lua`'s per-robot `{Mode, Behavior}` pairs instead of a full behavior tree
(a deliberate simplification from the original "modal AI with tree logic" ask — the entries
themselves are the only inputs that vary, not the tree shape). `Combat.SingleTarget` and
`Combat.Cleave` (hits the nearest N enemies, `TargetCount` configurable per robot) cover all 4
existing robots today; `Utility.Shield` and `Utility.SpeedBoost` are built and working but unused
— none of the 4 existing robots' flavor fits a support role yet, so nothing was forced into
Utility mode just to fill the category. Enemies never call `Humanoid:TakeDamage` directly — they
go through a `context.DamageTarget(amount)` closure that drains a temporary shield-absorb pool
(`playerState.Shield`, filled by `Utility.Shield`) before real Humanoid health drops, so
`EnemyAI.lua` never needs to know Shields exist at all.

**Win/loss and rewards:** `WaveService`'s existing endless-ladder structure (wave 1, 2, 3...
forever, tracked via `profile.HighestWave`, ending only on loss or disconnect) was deliberately
PRESERVED — this pass only replaced what happens INSIDE one wave, not the ladder shape itself.
"Wave cleared" = every spawned enemy dead and the wall still standing (see "Wall defense rework"
below for what "the wall" means and why the loss condition isn't the player's own Humanoid
anymore); "defeated" consumes the existing one-time `WaveReviveTokens` continue if the player has
one, otherwise ends the run. Rewards originally stayed on WaveConfig's smooth
`GetScrapReward`/`GetCoresReward` per-wave formulas layered additively with an elite-wave loot
table (`ReplicatedStorage/Shared/RewardTables.lua`, `RewardTables.Roll(stageKey)`) — **this has
since been REWORKED again** (Base Defense & Turrets phase round 2): Scrap/Cores rewards are gone
entirely, elite waves are now full boss waves guaranteeing a Core item, see "Wave defense rewards
— REWORKED" under `## Base` above for the full current shape. `RewardTables.Roll`'s own pure-
lookup/pure-roll shape (a `{Type, Key, Amount}` list, `nil`-safe throughout) is unchanged from this
original build, only the tables themselves changed. This mirrors `NodeService.lua`'s existing
raid-loot pattern in spirit without directly reusing/refactoring it.

**Client-side:** a new `StarterPlayerScripts/CombatClient.client.lua` — click-and-hold to fire a
camera raycast (hitscan, with a "shot report" sent to the server), paced by the equipped weapon's
BASE `FireRate` from `CraftingRecipes.Weapons` for feel only (the server enforces the real
mod-adjusted cooldown independently). Draws a short-lived Neon tracer part purely for local visual
feedback. This hitscan-plus-tracer approach was my own default for "how does the player actually
fire" — not explicitly specified — since the game has no real projectile-travel physics yet;
swapping it for true projectiles later only touches this one file, since `DamagePipeline`/
`CombatEncounterService` don't care how a hit was determined, only that one landed. As of the
weapon-Tool rework below, firing also requires an actual gun Tool held in the character's hand,
not just "some weapon equipped in your profile somewhere."

**Deliberately deferred, not forgotten:** (1) `NodeService.lua`/raid Combat Outposts, as noted
above. (2) Deployed robots stayed ABSTRACT through this pass — no physical Model or position, just
an abstract entry that acts on its own cooldown from wherever the player is; their combat/utility
EFFECTS were fully real and working, only the "turn them into a placed-in-the-world turret" visual
layer was deferred — that specific idea (a deployed robot getting a physical body) DID ship as
round 1 of the base-defense Turrets work, but has SINCE been superseded by round 2's fully
independent Turret system (blueprints/slots/leveling, decoupled from `DeployedRobots` entirely) —
see the "Turrets" bullet under `## Base` above for the current shape. Deployed robots themselves
remain exactly as this section describes either way — abstract, combat/utility effects fully real,
no physical presence, raids still treat `DeployedRobots` as purely abstract. (3) A raid
drone-companion slot (specialized "Drone Cores" —
Combat/Support/Scavenger/Recon archetypes) was explicitly requested for later and explicitly NOT
to be built yet — noted here so it isn't lost, not started.

### Combat Engine — first playtest revisions

Direct feedback after the first real playtest of the above: "its not perfect perfect but its
there, its working" — four follow-up changes, all shipped in the same pass.

**Spawn spacing.** Enemies visibly clumped together on spawn — the original spawn loop picked a
fully independent random angle per enemy, which let two independent draws land right next to each
other by chance, especially on later waves with bigger spawn counts. `CombatEncounterService.lua`
now gives each enemy an evenly-spaced angle slot around the base (`2*pi / spawn count`) plus a
small `±15°` random jitter (`SPAWN_ANGLE_JITTER`) instead — guarantees real separation between
neighbors while still not reading as a perfectly robotic ring. Spawn radius also widened
(15–30 studs → 50–80 studs), tied to the wall-defense rework below.

**Wall defense rework.** The original version made the player's own real Humanoid health the loss
condition — direct feedback afterward was that base defense should be about defending the BASE,
not the player personally: "instead of the wave trying to kill you, [make it] the enemies trying
to 'kill' the wall in your base." Reworked:
- Every enemy now targets the player's own PLOT position (`PlotService.GetPlayerPlot`) instead of
  the player, via a new `WallHP` pool CombatEncounterService owns per-run
  (`BaseConfig.GetWallMaxHP(profile.BaseTier)` — 150/300 HP across the two base tiers that existed
  at the time, now a 150/300/550/900 four-tier ladder since Base building/tiers shipped — see
  `## Base` above — still first-guess numbers worth a playtest). `WaveService.lua` never needs to
  know WallHP exists —
  it still just sees "Cleared"/"Defeated"/"Interrupted", same as before.
- "Close enough to attack the wall" is a flat distance check against the BASE's position
  (`BaseConfig.WallAttackRange = 40`, roughly matching `PlotConfig.FootprintHalfSize`'s edge) —
  explicitly NOT a per-enemy melee range and NOT collision with a literal wall Part/mesh, per
  direct instruction ("the enemy has to be a certain magnitude of the base... not from the wall
  itself"). `EnemyConfig.Types[x].ContactRange` (the old player-melee distances, 5–6 studs) is
  overridden at spawn time to this flat value instead — the per-type numbers stay in EnemyConfig
  unused for now, ready for a future mode (raid rooms) that wants real melee-vs-player distances.
- `EnemyAI.lua`'s `Chaser` pattern got more generic, not more complex: it dropped its
  `TargetHumanoid`-alive check entirely (there's no Humanoid to check anymore) and now just always
  damages through `context.DamageTarget` once in range — `TargetPosition` is documented as "just a
  point in space to defend," so a future mode pointing it back at the player needs zero changes to
  this file.
- Shield (`RobotBehaviors.Utility.Shield`) now absorbs hits on the WALL's behalf instead of the
  player's — same absorb-pool-before-real-health code, only what it's ultimately protecting
  changed. The player's own Humanoid health is untouched by this whole system now; dying to
  something unrelated just interrupts the run rather than counting as a loss.
- Revive Tokens needed no new logic — retrying a wave already meant calling `RunWave` again from
  scratch, which naturally rebuilds a full WallHP pool at the top of the run. "Revived" now just
  means "wall repaired," not "player healed."

**Weapon Tools/hotbar.** Equipping a weapon used to be pure data (`profile.EquippedWeaponId`) with
nothing physical to show for it. Direct feedback: guns should be an equippable Tool that goes into
the hotbar from the Inventory panel, clearing out whichever gun was equipped before, so a real gun
Model can exist later. Shipped as `ServerScriptService/Services/WeaponToolService.lua`:
- `WeaponToolService.SyncEquippedTool(player, weaponInstance)` is called from
  `ForgeService.lua`'s `EquipWeapon` handler (and its auto-equip-on-first-Forge path) every time
  `EquippedWeaponId` changes. It destroys any existing Tool tagged `WeaponTool=true` out of both
  Backpack and Character first (only one gun at a time, mirroring `EquippedWeaponId` itself being
  singular), then clones a template into the player's Backpack with `WeaponTool`/`WeaponKey`/
  `WeaponInstanceId` attributes set.
- Template lookup follows the same "drop a same-named thing in a folder, no code changes needed"
  convention as `ServerStorage.EnemyModels`/`ReplicatedStorage.BaseTemplates` — build a real Tool
  in the new `ReplicatedStorage.WeaponTools` folder (see `default.project.json`) named exactly a
  weaponKey (e.g. `PipePistol`), with a Part named `Handle`. UNLIKE those other template folders,
  a missing weapon Tool doesn't just skip — a Tool literally can't be held without a Handle — so
  this builds and caches a plain placeholder box Tool on the fly instead, so equipping never
  breaks before gun art exists.
- Re-syncs on every `CharacterAdded` from `profile.EquippedWeaponId` (the actual source of truth),
  rather than trusting Roblox to carry a held Tool through character death/respawn reliably.
- `CombatClient.client.lua` now tracks whichever Tool is actually parented to the Character (held
  in hand, not just sitting in Backpack) via `ChildAdded`/`ChildRemoved`, and reads `WeaponKey`
  straight off that Tool's own Attribute for fire-rate pacing — dropped its old `GetProfile`/
  `InventoryUpdate` profile-mirroring code entirely, since the held Tool is now a simpler and
  always-in-sync source for the same information. Firing requires a Tool actually in hand now, not
  just an equipped weapon in the profile.

**Loadout actions no longer plot/station-gated.** Direct feedback: "on the inventory you can only
equip stuff when you are nearby the forge... you should be able to equip and do whatever you want
even if you are outside the base." `EquipWeapon` (`ForgeService.lua`) and `DeployRobot`/
`UndeployRobot`/`EquipMod` (`CraftingService.lua`) all dropped their `PlotService.IsPlayerInOwnPlot`
+ `StationService.IsPlayerNearStation` checks — changing your loadout now works from anywhere in
the world. Only actually CRAFTING a new item (`CraftItem`, `ForgeWeapon`, `CraftLuckPotion`,
`UpgradeForgeTier`) still requires standing at the right station — the split is "equip/deploy is
just picking from what you already own," "craft is the thing that should require the workbench."

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
flow is the intended eventual replacement for "pull a lever to start." **That replacement is the
Raid Rooms system directly below** — Expedition/NodeService are left exactly as they were, running
in parallel, not replaced.

### Raid Rooms — instanced, first pass (BUILT)

The "real teleport-to-a-separate-area flow" flagged above, now built: `RaidConfig.lua` (data +
pure `GenerateMap()` graph generator) and `RaidRoomService.lua` (orchestration), plus
`RaidClient.client.lua` for the map/room GUI — all new files, `ExpeditionService`/`NodeService`
untouched. Direct ask: "the player teleports somewhere and then an area is created... whenever an
end condition for that specific node is met, make that the player open a GUI map, and the player
can choose a path to follow, but make it like a path that makes itself... the fork is just 2
different nodes that will lead to the same thing... make combat more common, heal stations to
appear in intervals, and shops have a raw chance of appearing... make the map pretty... with
circles... and lines path connecting each other... for now just text [not a logo]."

- **Instancing.** No hand-placed Studio anchor (unlike Plot/Expedition/MineShaft) — a raid gets a
  private slot at a fixed point high in the sky (`RaidConfig.InstanceOrigin`), offset per
  concurrent raid so players never share space (`RaidConfig.MaxConcurrentInstances` slots, a
  simple free-list in `RaidRoomService.lua`). `RequestStartRaid` spends 1 Energy via the same
  `RaidEnergyService.TrySpendEnergy` Expedition already uses.
- **Map generation** (`RaidConfig.GenerateMap`) — a chain of 2-3 fork-and-merge "diamonds": each
  stage branches into two independent short sequences (1-2 nodes each, so "this path is this
  sequence of stuff, or this path is this type of sequence") that reconverge into one shared hub
  node before the next diamond, capped with a single dead-end Extraction node. Regular-node type
  is Combat by default ("make combat more common"), Heal forced at a fixed interval
  (`RaidConfig.HealInterval`, not random — "heal stations to appear in intervals"), Shop a flat
  independent probability (`RaidConfig.ShopChance` — "a raw chance"). The whole map generates and
  reveals up front (not fog-of-war) — the client dims/locks whatever isn't the current or an
  immediately-reachable node.
- **Rooms.** One named Model per node type in `ServerStorage.RaidRoomModels` (same "drop a
  same-named thing in a folder" convention as `EnemyModels`/`BaseTemplates`), falling back to a
  plain big square (`RaidConfig.FallbackRoomSize`) if that type has no Model built yet — per the
  explicit ask.
- **Combat rooms reuse the REAL engine**, not a new one: `CombatEncounterService.RunRaidCombat` is
  a new sibling to `RunWave` (wall-defense) — same `spawnEnemy`/`resolveAndApplyDamage`/`EnemyAI`/
  `RobotBehaviors`/`activeEncounters` (so `RequestFireWeapon` already just works, unmodified), but
  enemies chase the player's own LIVE position every tick instead of a fixed wall anchor, and the
  loss condition is the player's real Humanoid health instead of a `WallHP` pool. This is exactly
  what `CombatEncounterService.lua`'s own header flagged as the intended next step once Raid Rooms
  had real physical spawn points to hand the engine to — see that function's own comment for why
  it deliberately takes an explicit `spawnKeys`/multiplier instead of knowing about `RaidConfig` at
  all. Difficulty scales by `RaidConfig.GetCombatTierForStage` (how deep into the map), reusing
  `NodeConfig.CombatTiers[tier].Loot` for rewards — the same table Expedition's Combat Outposts
  already use, so loot doesn't need a second table maintained in parallel. Shop rooms reuse
  `NodeConfig.ShopCatalog` the same way.
- **Map GUI** (`RaidClient.client.lua`, its own `ScreenGui`, not bolted onto `MainHud.client.lua`)
  — circles per node (colored by type, matching `ExpeditionService`'s existing Combat/Shop/Heal
  palette) positioned by stage/lane, connecting lines drawn as rotated thin Frames (no native line
  primitive in Roblox GUI). No icons/logos yet — text labels only, per the explicit "for now."
- **Deliberately deferred**: no drone-companion slot here either (see the note above this
  section); no rotating/limited Shop stock (every `NodeConfig.ShopCatalog` item is always
  available); no fog-of-war on the map. All easy follow-ups once this first pass has been played.

### Raid Rooms — chaptered maps, Ambush, room-authored spawns (BUILT)

Direct playtest feedback on the first pass above: nodes felt skippable, the map's own shape read
the same every raid, falling off the fallback room's edge, and a request for real map-building
control instead of always-procedural fights.

- **Chaptered maps, not one fixed graph.** A generated map (`RaidConfig.GenerateMap`) is now a
  bounded "chapter" — reaching its dead end (still the `Extraction` node type internally) no longer
  ends the raid. `RaidRoomService.onMapCleared` marks the raid's first clear and immediately
  generates a brand new map with its own fresh random shape, continuing straight into it — "create
  a map with different paths, and when the player gets to the end, generate a new one... it doesn't
  necessarily gotta connect to each other, which makes it less complex." Actually leaving the raid
  and banking everything is now its own explicit `RequestExtractRaid` action, gated on
  `state.ExtractUnlocked` — off (Abandon only, forfeits nothing already looted) until the first
  chapter's cleared, on (an Extract button next to Abandon) from then on: "before the first clear,
  is just an abandon button... an extract button should be available after the first clear."
- **Fixed a real "skip" bug.** A fork's two branches used to roll their length
  (`RaidConfig.BranchLengthMin/Max`) independently, so one path could come out objectively shorter
  than its sibling — picking it meant fewer nodes for free. Both branches of one fork now share a
  single roll; the content down each side (types/Tiers) still varies independently, just never a
  plain node-count shortcut.
- **Ambush** — a new, rarer node type (`RaidConfig.AmbushChance`) that's several
  `CombatEncounterService.RunRaidCombat` calls back to back as separate waves instead of Combat's
  one. Wave count is random and grows with `state.MapsCleared` (`RaidConfig.RollAmbushWaveCount`) —
  2-3 early, climbing toward a cap of 7 the deeper into a raid you get. Loot grants per wave
  cleared; losing any single wave fails the whole raid, same as Combat.
- **Room-authored spawns.** A Combat or Ambush Room Model built in Studio can now place Parts named
  exactly `RaidConfig.SpawnPointName` ("SpawnPoint"), each carrying a string Attribute named
  `RaidConfig.SpawnPointEnemyAttribute` ("EnemyType") set to an enemy type key from
  `EnemyConfig.Types`/`EliteTypes` (e.g. "Raider", "Brute", "ScrapCrawler", "SentinelDrone",
  "Scavenger", or the elite "VoidwakenHulk"). `RaidRoomService.collectSpawnPoints` reads these and
  `CombatEncounterService.RunRaidCombat`'s new `explicitSpawns` parameter spawns exactly what's
  placed, at the exact positions placed, instead of the original random circle-around-center roll —
  a room with no SpawnPoints falls back to that original roll unchanged. A SpawnPoint with a
  missing/unrecognized `EnemyType` spawns nothing there and `warn()`s instead of guessing.
- **Fallback room** grew from a cramped 50x50 to `RaidConfig.FallbackRoomSize` 260x260, and its
  guard rail (see the first pass's own "no falling into the void" fix) is now fully invisible
  (`Transparency = 1`, collision unchanged) — a visible concrete wall around an area that size read
  worse than just not seeing the edge at all.

### Raid Rooms — map shape rebuilt as a real tree (BUILT)

Direct playtest feedback: two nodes with lines that visibly crossed, and clicking one of them
"just skipped the wave" — plus a hand-drawn reference of the much simpler shape actually wanted.

- **Root cause.** The fork-and-merge diamond shape (both pass's map generation) let two different
  branches reconverge into one shared hub node. That hub was still just a normally-rolled regular
  node (`rollRegularType` has zero awareness it's a merge point), so nothing was actually broken in
  a way that could reliably be reproduced from code alone — but a shared hub is exactly the kind of
  coincidence-prone shape that produces confusing crossing lines on a stage/lane-column layout, and
  removing that possibility entirely was more reliable than chasing one specific rendering edge
  case. `RaidConfig.GenerateMap` no longer has any merge points at all.
- **New shape: a real tree.** `Start` → one trunk node → a guaranteed first split into two
  branches (`buildBranch`), each its own sequence of `RaidConfig.SegmentLengthMin/Max` (2-3) nodes
  that either ends in its own `Extraction` leaf or splits again (`RaidConfig.ForkChance`, capped by
  `RaidConfig.MaxForkDepth` so a path can only split 2 more times after the first). Every node has
  exactly one parent — `Connections` IS a node's children list now, nothing more. A map can end up
  with several `Extraction` leaves scattered across it instead of one fixed dead end; reaching
  *any* of them triggers `RaidRoomService.onMapCleared`, same as before.
- **Client layout rebuilt to match** (`RaidClient.client.lua`'s `redrawMap`) — the old
  stage/lane-column grouping assumed nodes could share an incoming edge; the new one is a proper
  dendrogram layout: walk the tree from `Start`, hand each leaf the next sequential lane
  left-to-right, and give every internal node the average of its own children's lanes on the way
  back up the recursion. Because it's a genuine tree, this guarantees connecting lines never cross
  — not "usually doesn't," an actual guarantee from the math, verified by running the generator +
  layout 5,000 times standalone (no orphans, no cycles, every leaf is `Extraction`, worst-case
  stage depth 14 / worst-case leaf count 8 both hit and both fit the resized map canvas).

### Raid Rooms — post-playtest polish round (BUILT)

Direct playtest feedback after finishing a full raid map: it was "pretty good" but the map felt too
small on a second playthrough, the map GUI's nodes were rendering too small/sparse, enemy hits felt
unfair the instant they spawned, enemies could keep pace with the player forever, the raid combat
spawn ring felt too close, `Extraction` as its own node type wasn't wanted, and nothing stopped a
player from quitting mid-room-interaction.

- **Minimum map size.** `RaidConfig.GenerateMap` is now a retry wrapper around a private
  `generateOnce()` — it regenerates from scratch (up to `RaidConfig.MaxGenerateAttempts = 25` times)
  until the tree has at least `RaidConfig.MinMapNodes = 12` nodes, falling back to the largest
  attempt seen if every attempt undershoots. A 5,000-trial standalone simulation of this exact retry
  logic hit 0/5000 fallbacks (avg ~18 nodes, 3-8 leaves per map).
- **`Extraction` removed as a node type.** There's no dedicated `Extraction` entry in
  `RaidConfig.NodeTypes` anymore — a branch's dead end is just whichever regular type
  (Combat/Ambush/Heal/Shop) its last node already rolled. `RaidRoomService` tells a leaf apart from
  a mid-branch node purely by an empty `Connections` list (`advanceFromNode`, called from every
  place a room's own encounter/action finishes — Combat cleared, Ambush's last wave cleared, Heal
  and Shop's "Continue"), not by `Type`. Any `ServerStorage.RaidRoomModels.Extraction` folder built
  for the old type is now unused.
- **Map GUI now scales to fit.** `RaidClient.client.lua`'s `redrawMap` used to lay out every map
  with the same fixed stage/lane spacing and node size regardless of how big the map actually was —
  a small map (near `MinMapNodes`) ended up huddled in one corner of the panel. Spacing and node
  diameter are now computed fresh per map from its actual stage count/lane count, clamped to a
  reasonable range, and the whole layout is centered (both axes) in the fixed canvas.
- **Spawn-damage grace period.** `CombatEncounterService.spawnEnemy` now stamps `SpawnTime` on every
  enemy it spawns; `EnemyAI.lua`'s Chaser pattern won't land a hit until 1 full second
  (`SPAWN_GRACE_SECONDS`) has passed since that spawn, on top of its normal attack cooldown — an
  enemy can still walk in and close distance immediately, just can't deal damage the instant it
  appears.
- **Enemies a little slower than the player.** No code in this project sets the player's own
  `WalkSpeed`, so it sits at Roblox's unmodified default of 16 — and `EnemyConfig.lua`'s
  `RebelBase.MoveSpeed` (used unmodified by Scavenger/Raider) was exactly 16 too, meaning those two
  types could keep pace with the player forever. Dropped to 14, matching `ScrapCrawler`'s own
  existing override.
- **Raid spawn ring widened.** `CombatEncounterService.RAID_SPAWN_RADIUS_MIN/MAX` moved from 15/22
  to 50/70 studs, matching the room's own bigger 260x260 fallback footprint. Room-authored
  `SpawnPoint` placements are unaffected — they always spawn at their exact placed positions.
- **"Go Back To Base" button.** A renamed, repositioned version of the old bottom-right Abandon
  Raid button — now top-center, outside the map GUI panel, and visible *only* while the branching
  map (`mapFrame`) is actually open, not "whenever a raid is active and not mid-Combat" like before.
  With this gate there's no way to bail out mid-Heal/mid-Shop/mid-Combat anymore, only at the exact
  moment a map choice is showing — "so they cant just quit while doing a raid." Extract kept its
  original bottom-right spot and its original (broader) visibility rule, since banking loot and
  leaving cleanly isn't the "quit early for nothing" behavior this was aimed at.

### Raid Rooms — Ambush run-scaling fix, interactable Heal/Shop, run economy, Boss + cards (BUILT)

Direct playtest feedback after another full raid: Ambush wave count spiked way too early (already
at wave 5 by the 3rd Ambush node), a wave visibly got skipped once, Heal/Shop felt too automatic,
and a request for a whole new layer — a run-scoped currency economy, a Boss node, and a roguelike
post-boss card pick.

- **Ambush scaling root-caused and reworked.** `RollAmbushWaveCount` used to factor in a node's own
  within-map `Tier` on top of `MapsCleared`, so one deep node on the very first map could already
  roll close to the max. It's now driven ONLY by `state.TotalNodesVisited` — a counter that
  persists across map regenerations (unlike anything keyed off the current map alone) — via
  `RaidConfig.GetRunProgressionMultiplier`, the same curve loot amounts and Ambush enemy strength
  now read from too. Verified via a 5,000-trial standalone simulation: waves stay at 2-3 through
  most of map 1, reach ~5 by roughly the 3rd map, and cap at 7 well into a long run.
- **Ambush "skipped wave" — best available fix, not a confirmed root cause.** Couldn't reproduce a
  server-side logic bug from code review (same honest caveat as the earlier crossing-lines bug) —
  the most plausible mechanism found was `pickRaidSpawnKeys` drawing an enemy type with no built
  Model in `ServerStorage.EnemyModels`, which silently resolves to a 0-enemy wave that
  `RunRaidCombat` auto-clears instantly. Hardened against it: `CombatEncounterService.HasModelFor`
  filters the random draw down to types that actually have a Model built (same fix applied to a new
  `pickBossSpawnKeys`), and the zero-spawn fallback now logs which type keys were attempted.
- **Heal/Shop now require interaction.** Both wait for the player to trigger a ProximityPrompt on a
  Part named `RaidConfig.InteractPointName` in the room (`RaidRoomService.beginInteractGated`,
  created automatically if the Part exists but has no Prompt yet) instead of firing the instant the
  room is entered — "so later on I can put an actual NPC in there." A room without that Part yet
  (the fallback square, or an unfinished authored room) just fires immediately, same as before.
- **Run-scoped currency economy.** Loot earned mid-raid no longer touches the player's real profile
  immediately. Scrap/Cores collected land in `state.RunCurrencyCollected` — a live pool shown on a
  new "Scraps Collected" GUI panel (visible only while a raid is active) that the raid's own Shop
  spends against instead of the player's actual currency. Everything else earned (Ore) sits in
  `state.RunLoot` until the raid ends. `settleRunLoot` then banks it all: currency always in full;
  everything else in full too UNLESS the raid ended in a Defeat/Abandon AND the specific drop is
  tagged `RunLocked` on its loot-table entry (NodeConfig.lua), UNLESS that same entry is ALSO
  tagged `Permanent`. No existing loot entries are tagged either way yet — behavior is unchanged
  until specific entries are tagged later.
- **Boss node.** `RaidConfig.GenerateMap` converts 1-2 of a freshly-built map's own regular nodes
  into Boss encounters (`placeBossNodes`), never closer to Start than `BossMinStageIndex` (stage 3)
  — "so players have time to get healed and etc before the boss fight." One tougher `RunRaidCombat`
  encounter off `EnemyConfig.EliteTypes` (`BossComposition`); clearing it fully heals the player and
  offers a rarity-weighted card pick (`RaidConfig.RollCardChoices`, `CardRarityWeights`) that the
  player must choose from before the map advances. Card system is a placeholder scaffold — one stub
  card per rarity, no real buff effects wired up (`state.CollectedCards` just records the pick) —
  proves out the rarity/roll/pick-one flow for real content to replace it later.

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

## Session context — decisions not yet captured

Loose ends from the Base Defense & Turrets round-2 chat (Hub Shop/blueprints/turret
slots-and-leveling/boss-wave Core economy — see the "Turrets" and "Wave defense rewards" bullets
under `## Base` for what actually shipped) that didn't make it into the writeup above or into
`README.md`. Everything below is either a real open question or a discarded alternative, not a
restatement of anything already documented.

- **Turret "effects" — likely NOT built as a real gameplay trait, unconfirmed whether that's
  actually a gap.** The original request listed turret variety as "specific ranges, damage, speed,
  AOE, effects and all that." Range/`BaseDamage`/AOE landed as literal fields; `FireRate` stood in
  for "speed" (no real projectile-travel exists to give speed its own meaning). But "effects" as a
  distinct per-type GAMEPLAY trait — a slow, a burn, a stun, anything beyond raw damage — was never
  built. The only per-type field that could be mistaken for it is `ParticleColor`, which is purely
  cosmetic (feeds the muzzle-burst particle from the separate "make it look cool when firing" ask,
  a different request in the same message). **Unconfirmed** whether "effects" meant real gameplay
  effects (a genuine gap, worth a follow-up type-differentiator later) or was loosely gesturing at
  the visual burst that did ship — flag before treating the 6 turret types as fully varied.
- **Hub Shop "buy/sell" — only buy shipped.** The original ask described the Hub as somewhere
  players "can go and buy/sell what they want." `TurretShopService.lua` only has
  `BuyTurretBlueprint` — there's no sell-back path for turrets, blueprints, or anything else.
  Whether that half was a deliberate scope cut or just hasn't been gotten to yet was never actually
  discussed — **unconfirmed**, don't assume it's intentionally out of scope.
- **An earlier recommendation was superseded, not built — don't resurrect it.** Before the
  build-it green light, one design option floated for the Hub Shop was blueprints unlocking a
  separate craft-with-materials step rather than minting the turret directly. The user's own
  follow-up instructions were explicit enough ("turrets will be bought their blueprint... and then
  the turrets will be placed in base") that the simpler direct-purchase-mints-an-instance model
  shipped instead — confirmed decided, not an oversight. Noting it only so a future session doesn't
  see "no separate craft step" and think it's an unaddressed idea.
- **Research Tier is confirmed as the explicit next roadmap step, but the top-of-file build order
  doesn't say so yet.** "Status at a glance" and the "Agreed build order" paragraph at the top of
  this file still read "Next up: main shop, then PvP invasion," with no mention of Research at all
  — stale relative to this chat, where the user stated directly that Research is next
  ("research level, which we will be making that on the next step of roadmap"). Worth updating that
  table/paragraph (and probably adding a Research row) before starting the next session, rather
  than trusting the old "main shop next" framing.
- **Hub Shop vs. the still-unbuilt "Main shop" — never reconciled, unconfirmed how they relate.**
  The not-yet-built shop described elsewhere in this file (rotating stock, sells armor/mods/
  cosmetics, geode/extractor sink) and this round's Hub Shop (rotating stock, sells turret
  blueprints only) both landed on the same "rotating stock" shape independently — this chat never
  connected the two. **Unconfirmed** whether the Main shop is a separate station, the same Hub
  station with more tabs, or should eventually reuse `TurretConfig.GetRotatingStock`'s
  deterministic time-hash approach for its own rotation.
- **Possible tie-in to an older planned hook — never connected in this chat, unconfirmed.** The
  Combat Engine section's `VoidwakenHulk` elite-type comment (written in an earlier session)
  already plants the seed for "a future boss-drop reward hook (Research Level's 'Special Core')."
  This round's `profile.ResearchTier`/`profile.CoreItems`/boss-wave Core drops line up suspiciously
  well with that old idea, but nobody in this chat actually pointed the two at each other. Flagging
  so a future session checks whether `VoidwakenHulk` (or elites generally) should eventually feed
  into the same boss-wave Core-drop path this round built, rather than treating them as unrelated.
- **Two Studio TODOs surfaced in chat that never made it into this file:** (1) nothing in the world
  currently satisfies the Hub Shop's requirement — a `Station`-tagged Part/Model needs to exist
  somewhere outside any `BaseTemplates` Model, with a child `StringValue` `StationType` set to
  exactly `"Shop"`, or the Blueprints tab is unreachable in-game. (2) `ServerStorage.TurretModels`
  can optionally hold a real Model per `TurretConfig.Types` key (same convention as
  `EnemyModels`/`BaseTemplates` — floor at local Y=0, `PrimaryPart` set); every type currently falls
  back to a small colored placeholder pedestal since none exist yet.
