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
