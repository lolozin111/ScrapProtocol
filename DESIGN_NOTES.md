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
| Research level (progression tiers) | **Built** — see below |
| Main shop (rotating stock, geode/extractor) | **Superseded** by the Black Market — same flow |
| Selling (raw ore/refined material -> Scrap) | **Built** — Hub Shop's Sell tab, `SellService.lua` — see "Session context" below |
| Black Market & Hacker Machine | **Built** — dealer, cases, decode, Contraband. Gun variants + tools still to come |
| Ultimate mods (Mythical passives, 4th slot) | **Built** — all 6 |
| Status effects (bleed/poison/burn/stun/slow/frostbite/shred) | **Built** — see "Combat infrastructure" |
| Projectiles (real travelling shots) | **Built** — see "Combat infrastructure" |
| Damage numbers + training dummies | **Built** — the diagnosis layer for everything above |
| Session-locked saves | **Built** — see "Data safety" |
| Gun variants (14) + tools (3) | **Built** — 18 weapons across 6 families, 3 pickaxes |
| Drone companion (4 Drone Cores) | **Built** — unlocks at Research Tier 3, follows you everywhere |
| Player Test Mode (admin throwaway profile) | **Built** — see "Data safety" section below |
| HUD phase 3 (all station menus) | **Built and verified** — see "Road to release" below |
| Raid overhaul | **Scope cut to one mode for v1 (2026-09-08)** — steps 5-6 deferred post-launch; step 1 built AND VERIFIED in Studio 2026-09-08, step 2 (room variant folders) BUILT and VERIFIED in Studio 2026-09-15; **step 3 (mode plumbing) BUILT 2026-09-15, not yet verified**; step 4 next but its mode identity is an open question, see Phase 00 below; **exit doors switched OFF 2026-09-09** — the Sector Map picks the next room again (`RaidConfig.ExitDoorsEnabled`) |
| Enemy AI patterns | **Engine built, two patterns** — `Chaser` (six enemy types) and, shipped 2026-09-09, `Slam` (`Siegebreaker` only — a telegraphed wind-up/impact cycle, see "The Voidium infestation" below) |
| Enemy art (Studio models) | **All 5 built; all animated as of 2026-09-16** (walk + attack ids in `EnemyConfig.Animations`; Idle/Death deliberately left for a post-launch update). Originally: **4 of 5 built (2026-09-10)** — Scavenger, Raider, Brute, Siegebreaker in `ServerStorage.EnemyModels`; VoidwakenHulk imported, textured, rigged with `FistR`/`FistL` Attachments, in `EnemyModels`, and FIGHTING in raids as of 2026-09-15 (HipHeight/hitbox/facing now come from EnemyConfig) — see "Resuming after a context reset" |
| Voidium infestation (lore + the raid boss) | **Partially built 2026-09-09** — `EliteTypes`/`BossTypes` split into separate pools and `Siegebreaker` shipped as the new elite; the bloom itself (the actual raid boss per Decision 2 below) is still designed, not built — see "The Voidium infestation" below; `Siegebreaker` also rolls into raid Combat rooms (`EliteChance`, 2026-09-09) |
| Boss escort (spawn zones in the Boss room) | **Built 2026-09-15 with an interim count, untested in Studio** — the depth curve is still unbuilt, so `combatCount` is the Combat roll at the boss node's tier (Tier 3: 1–2 minions). User's call. See "Boss escort" below |
| Animation pass | **Hulk DONE and verified 2026-09-15** — Idle `113796712422007`, Walk `103708147649106`, heavy combo `137947497885396` (`ImpactR` ×2 + `ImpactRFinal`), left sweep `105875185230848` (`SweepLStart`/`SweepLEnd`), all playing through `AIPattern = "Animated"` (`EnemyAnimation.lua`). No death or turn animation, by the user's choice. Next animation: the player's DASH (`DashConfig.AnimationId`, user is making it). Other enemies still have no attack tell. Details in "Resuming after a context reset" |
| Stamina & dash | **Built 2026-09-15, verified working by the user** — 3 charges, 1 per 5s, Q/B/touch; **dash i-frames (0.3s) added 2026-09-22, raid-combat-path only, untested in Studio**; see "Stamina & dash" |
| Early-game pacing & onboarding | **Partially built** — item 1 (ore sells for Scrap) shipped in the ore rework; starter objectives (item 2) still planned, not built — see below |
| Raid shop rework (run-only perks) | **COMPLETE — verified in Studio by the user 2026-09-22** ("i tested myself and it looked fine") — cards, all 12 icons uploaded and live, 4 equipment slots + Sell, Extraction Beacon/Salvage Insurance, raid ore now `RunLocked`, boss cards now rendered with the same card (`RunCard.lua`) as the shop, crits, gear (aura/blades/drone). Deep verification of the individual mechanics (rarity-up math, Insurance's payout on death, gear damage) is deliberately DEFERRED to the game's testing phase — the user's call — see "Resuming after a context reset" |
| HudKit panel layer (`HudKit.LAYER`/`openPanel`/`closePanel`/`isPanelOpen`) | **Built 2026-09-22** — one panel open at a time (plus `stacked` for pickers), a scrim, and every world-input guard routed through it; new panels must use it — see "Resuming after a context reset" |
| Mine visual pass (chunky 12-stud blocks, saturated ore colors, reset sign) | **Built 2026-09-22** — see "Mining zone" below and "Resuming after a context reset" |
| Aim camera (over-the-shoulder while a gun is equipped) | **Built 2026-09-22, untested in Studio** — `AimCamera.client.lua`/`Shared/AimCameraConfig.lua` — see "Resuming after a context reset" |
| Dash i-frames | **Built 2026-09-22** — `DashConfig.IFrameSeconds`, honoured in the raid damage path only (not mine lava, not outpost chip damage yet) — see "Stamina & dash" and "Resuming after a context reset" |
| Mining cooldown bar (replaces the "Swinging too fast" toast) | **Built 2026-09-22** — `MiningCooldownBar.lua`, a frame-driven state machine — see "Resuming after a context reset" |
| Adversarial exploit review (F1-F8) | **Done 2026-09-23; all 8 STUDIO-VERIFIED 2026-09-25** — 8 findings, all fixed same day, all twenty checks passed — report: "Breaking Salvage Protocol", https://claude.ai/code/artifact/UkMW3M9KMJ8H7m8G1pYt7A — see "Resuming after a context reset" |
| Raid flow & end-of-run screen | **ALL 3 built 2026-09-23, none Studio-verified** — single-exit auto-advance with a travel wipe, `RunSummaryPanel.lua`'s staggered stats screen, and the notice/damage-number retrofit: four hand-rolled `roomBody` labels collapsed into one fading `noticeLine`, and bonus damage now MERGED into the hit that caused it (`feedbackBatch` in `CombatEncounterService`) so AimBot's top-up stops reading as a weak crit — see "Resuming after a context reset" |
| PvP base invasion | **Recommended cut from v1** — see "Road to release" below |

Agreed build order (most recent discussion): Raid Energy → Mining zone rework → weapon mod
slots → base building/tiers (+ turrets) → Research level → Black Market → PvP invasion last.
Re-confirm this order before starting each one — priorities may have shifted. Research and the
Black Market are both BUILT (the Black Market **superseded** the planned "main shop" rather than
being built alongside it — same rotating-stock shape, so they were merged).

**Next up: build the raid overhaul, now that Phase 00 has settled what it is** — see "Road to
release" immediately below, which supersedes the build order above as the live plan. The content backlog further down is now BUILT —
kept as the record of what each weapon was specced to do, since the code says how they work and only
this says what they were meant to feel like.

## Road to release — the live plan (2026-09-03)

Agreed with the user in full, in dependency order. Six phases, with a gate in front of them.

**Three companion pages hold the tickable versions of this.** They are private Artifacts, they persist
independently of any session, and they are the fastest way back into this plan after a reset:

- **Road to release** — this plan, phase by phase: https://claude.ai/code/artifact/c520148b-a3db-4056-b273-7b5cd0e87ac8
- **Asset Bench** — every missing art/Studio asset with its exact key: https://claude.ai/code/artifact/53fec0c0-7889-4e51-8399-5bbe26fb583b
- **Three Ways In** — the Phase 00 raid overhaul design, settled: https://claude.ai/code/artifact/bc06cd42-19a8-40d6-9d0a-1c50f5d67648
- **Raid Room Build Sheet** — the Studio contract a raid Room Model must meet (required PrimaryPart,
  pivot placement, the X-axis width budget, the `ExitDoor`/`SpawnPoint`/`InteractPoint` part specs,
  and the silent-fallback ladder), plus a per-room build checklist that persists:
  https://claude.ai/code/artifact/e83de301-0323-4cca-813e-6efbeb852f31

**STUDIO ART IN PROGRESS (2026-09-08).** The user is building raid Room Models by hand. The first
Combat room is DONE. Two facts established during that work, both worth keeping:

- **Room width is limited on X only.** `InstanceSlotSpacing` is 600 studs between CONCURRENT raid
  slots, and slots step along X exclusively — so a room must stay under ~500 wide on X, while Z
  (depth) and Y (height) are effectively unconstrained. A big room should grow long or tall, never
  wide. One slot serves a whole run: entering a node destroys the previous room and rebuilds at the
  same origin, so rooms are never side by side.
- **Skip fog; use the native skybox.** The user asked about a geometry "sky box". `Lighting.Sky` is
  already exactly that at infinite distance for zero studs, and a real box would eat the X budget.
  Note that `EnvironmentFX.client.lua` deliberately force-clears fog/Atmosphere at startup because
  distance fog was playtested and REJECTED ("hard to see") — do not reintroduce it globally. It runs
  once, not in a loop, so a per-raid Lighting swap would not fight it. Since raid instances are
  private to one player, a per-room-type `Lighting.Sky` swap off `RaidRoomUpdate`'s existing
  `Status = "Entered"` payload is cheap and unbuilt; it would need restoring on all four exit
  statuses (Extracted/Defeated/Abandoned/MapCleared) plus disconnect, or a player ends up on the
  overworld under a raid sky.

### Phase 00 — the gate: what the raid overhaul IS — DESIGNED (2026-09-03)

**The gate is open.** Settled in a design round with the user and written up in full on its own page,
**Three Ways In**: https://claude.ai/code/artifact/bc06cd42-19a8-40d6-9d0a-1c50f5d67648 — read that
before building any of it; what follows is the summary, not the spec.

It was a gate because **the enemy AI work depends on its answer** — what enemies should DO is a
function of what a raid is. That dependency is now resolved in the concrete direction below: nine
patterns, three per mode.

**The diagnosis the round started from, all four verified against source, not remembered.** The raid
structure is finished and correct after five build-and-playtest rounds; what is missing is content in
slots the engine already opened:

- `RaidConfig.CardPool` (RaidConfig.lua:528) is four stubs, one per rarity, no effects wired.
- `NodeConfig.ShopCatalog` (NodeConfig.lua:91) sells ore bundles, no rotation — a vending machine.
- **Nothing anywhere is tagged `RunLocked` or `Permanent`** (NodeConfig.lua:26). The most
  consequential one: `settleRunLoot` is fully built and fully inert, so pushing deeper risks nothing
  and extracting protects nothing. The one decision the raid is shaped around has no stakes on it.
- `EnemyAI.Patterns` (EnemyAI.lua:69) has exactly one entry, `Chaser`, and all six enemy types point
  at it — Combat, Ambush and Boss rooms play identically.

**Decision 1 — three raid modes, not one raid.** The user's call, and a better answer than any of the
three single directions offered: build all three, as modes, each owning ONE loot axis, so they demand
different builds and picking between them before spending Energy is itself a strategy layer. Each
mode adopts one of the hollow slots above as the thing it is *about*, which turns four disconnected
content chores into three coherent reasons to enter a raid.

- **Gauntlet** — Cores/Contraband. Cards are the point: they stack all run, always lost on exit.
  Endless chapters, one guaranteed Boss per map, payout multiplies with `MapsCleared`. Shop sells
  run-only perks (this is where the raid shop rework lands). Rewards glass cannon. Patterns:
  `Swarmer`, `Charger`, `Artillery`.
- **Salvage Run** — Ore/refined, the crafting feedstock. Every ore drop `RunLocked`; a carry cap; a
  physical Extraction room you must REACH to bank. Shop sells capacity and escape. Rewards
  survivability and movement. Patterns: `Stalker`, `Guardian`, `Screamer`.
- **Contract** — blueprints, gun variants, Drone Cores. A rotating board of objectives, fixed run
  length, reward tagged `Permanent` so completing banks it even on a bad exit. Rewards specialisation
  and prep. Patterns: `Defender`, `Runner`, `Sapper`.

> **REVERSED 2026-09-09 — the map choice went back ON the screen.** The user's call, after seeing
> both in Studio: *"the map looks way better rn, and it fits the flow of the game."* Clicking a
> circle is the input again. The rest of Decision 2 below is kept verbatim as the record of why the
> physical version was built and how it works, because it was NOT deleted — it is switched off at
> `RaidConfig.ExitDoorsEnabled = false`, and flipping that one word restores every part of it.
> `unlockExitDoors` and its label/prompt/Touched machinery stay intact in `RaidRoomService` for
> exactly that reason.
>
> What the reversal did NOT undo: the map is still the docked, persistent Sector Map panel, not the
> old centred overlay. It is a readout AND a control now — the overlay could only ever be one at a
> time, which is what made it worth replacing in the first place. Authored `ExitDoor` Parts stay in
> their room Models, sealed solid and invisible by `sealExitDoors` on every node entry, so nobody
> has to strip geometry out of a room that already has it. Two additions came with it: the panel
> un-collapses itself whenever a choice opens (a choice the player cannot see reads as a stalled
> run), and collapsing now retreats to the TOP-right instead of hanging at right-centre — the
> collapse used to change `Size` alone while `AnchorPoint` stayed `(1, 0.5)`, so the bar shrank
> around its own middle and never moved.

**Decision 2 — the map choice comes off the screen.** Also the user's, and the second half of what
they meant by "overhaul". Today a cleared room calls `showMapChoice`, the GUI map opens and you click
a circle. Instead the room's **exit doors unlock** — one per branch, each taking its destination
type's own `NodeTypes.Color` and `DisplayName` — and walking through one fires the SAME
`ChooseRaidNode` remote. The map GUI is demoted to a persistent read-only minimap: where you are,
what you cleared, what is ahead. `redrawMap`'s dendrogram layout is kept exactly as-is; its
5,000-map no-crossing-lines guarantee is worth more now that the map is a reference than it was when
it was a control.

Door contract (full version on the page): a Part named `ExitDoor` (new `RaidConfig.ExitDoorName`,
following `SpawnPointName`/`InteractPointName` exactly), ordered by an optional numeric `ExitIndex`
attribute or by local X when unset; doors invisible-but-solid until the encounter resolves (changed
2026-09-08 from a dark slab, at the user's ask — see `RaidConfig.ExitDoorSealedTransparency`, a
one-number revert); **too few
doors warns and falls back to the GUI map for that node** (the missing-art rule applied to geometry —
a half-built room must never strand a run); extras stay sealed; a leaf seals all of them and
`onMapCleared` fires unchanged; the fallback room grows doors procedurally on its guard rail the same
way it already grows an `InteractPoint`.

**Decision 3 — room variants. BUILT (2026-09-08).** `buildRoom` used to look up ONE Model per node
type, so a fifteen-node map walked through the identical box a dozen times. `RaidRoomModels.<Type>`
may now be a **Folder of Models** instead of a Model, one picked at random per node — backwards
compatible by construction (a Model is used directly, a Folder picks a random Model child), and it
turns "make the map pretty" into as many small Studio jobs as wanted instead of one big one. One
refinement past the original sketch: `pickRoomTemplate` (`RaidRoomService.lua`, just above
`buildRoom`) skips any variant Model that has no `PrimaryPart` rather than picking it and falling
back to the placeholder — picking-then-falling-back would have made a half-built variant an
intermittent, unreproducible "sometimes the room is the grey box" instead of a room that simply
never gets picked. Skipped variants are warned about by name so they don't go unnoticed. A Folder
where every child lacks a `PrimaryPart` returns nil, same as an empty Folder — `buildRoom` falls
back to the placeholder square exactly as it always has for a missing/unusable entry.

**What none of this touches**, worth stating because "overhaul" reads like a rewrite: `GenerateMap`'s
tree + retry, chaptered maps, `onMapCleared`, instancing and the slot free-list, `RunRaidCombat`,
room-authored spawns, `settleRunLoot`, the run currency pool, boss placement, Ambush run-scaling,
`PlayerActivityService` gating, Energy cost, `redrawMap`. **`EnemyAI.lua` does not change either** —
every pattern named above is one new function in `EnemyAI.Patterns` plus one config line, which is
what that table was built to be.

**Build order inside the overhaul** (dependency order — doors first because all three modes need
them, AI patterns last because they need three raids to exist):

1. ~~Physical exit doors + read-only minimap~~ — **BUILT (2026-09-03), VERIFIED IN STUDIO
   (2026-09-08)**, see "Raid Rooms — physical
   exit doors + the Sector Map" below.
2. ~~Room variant folders~~ — **BUILT (2026-09-08), VERIFIED IN STUDIO (2026-09-15, user: "room
   variants works")** — small,
   independent, unblocks Studio art. See "Decision 3 — room variants" above and
   `RaidRoomService.lua`'s `pickRoomTemplate`.
3. ~~Mode plumbing~~ — **BUILT 2026-09-15, NOT YET VERIFIED IN STUDIO.** `RaidConfig.Modes` with ONE
   entry, `Standard` (today's raid, every rule pointing at the value raids already used, so nothing
   plays differently), plus `RaidConfig.DefaultMode`. `state.RaidMode` is set at `RequestStartRaid`
   (optional client arg; nil → default; a malformed value is REJECTED with `Status = "UnknownMode"`,
   never defaulted). Rules and their readers: `EnergyCost` (start), `Map` (→ `GenerateMap(rules)` →
   `placeBossNodes`, at start AND on chapter regen; missing fields fall back to the module constants),
   `ShopCatalog` (a NodeConfig table NAME, read by `revealShop` and the Buy handler via
   `shopCatalogFor`), `CardsEnabled` (the post-boss pick; the `false` path is written but untested and
   the client has never seen a BossCleared without `CardChoices`), `DisplayName` (sent as
   `Mode`/`ModeName` in the map payload; nothing reads it yet). Deliberately NOT mode rules yet: enemy
   composition and depth curves (curve work) and `RunLocked` tagging (step 4).
   **SETTLED for step 4 — the mode's identity (2026-09-15).** Earlier the same day the user had
   called today's raid "a little game, sort of a hack and slash, so people can do stuff and get
   special items like Contraband", which did not sound like the Salvage Run this plan assumed. Asked
   directly, they clarified that it IS salvage-shaped: "you can get some quick resources and stuff,
   but its the main way to get contraband and some cores, but we only reward those after a player
   finishes a map node and then the game gotta make a new one so the player can continue, and also
   in boss nodes". The rules, agreed one by one:
   - **Scrap and ore** still drop in every room, and are always kept, as today.
   - **Contraband and Cores come ONLY from clearing a map (`onMapCleared`) and from beating a Boss
     node.** Take Cores out of the regular Combat loot tables (`NodeConfig.lua` ~52/62); the Boss
     table already has them (~77) and gains Contraband.
   - **They are held in the run and LOST on death or abandon.** Only Extract banks them. This
     deliberately overrides the older "currency is always banked in full" rule, for these two only.
   - **Each map clear pays more than the last** (scales with `MapsCleared`).
   - **The old flat Extract Contraband bonus (`completeRaid`) becomes a MULTIPLIER on everything
     banked at extract, scaled by the number of BOSSES DEFEATED this run.** The user first read it as
     "how far you go", then changed it: "make it multiply based on the number of bosses defeated, so it
     encourages players on doing bosses nodes". Bosses are 1–2 per map on random nodes at stage 3 or
     deeper (`placeBossNodes`), so a player can often route around them. That is the choice this
     rewards. Starting numbers, to tune in playtests, living in `RaidConfig`: 0 bosses ×1.0, then
     +0.25 per boss, capped at ×2.0. The per-map growth and the boss multiplier stack, which is why
     both start modest and the cap exists.
   - **The raid shop becomes Scrap-only** (`NodeConfig.ShopCatalog`, e.g. the 10-Cores item ~114),
     so it works from room one and Cores stay a prize you take home.
   Still open, not discussed: whether ore also becomes `RunLocked`, a carry cap, and a physical
   Extraction room (the rest of the original Salvage Run stakes layer). Mode key stays `Standard`.
4. ~~Raid rewards rework~~ — **BUILT 2026-09-16, NOT YET VERIFIED IN STUDIO.** The settled rules
   above, implemented as: `RaidConfig.ExtractionRewards` + `RollMapClearReward`/`RollBossReward`/
   `ExtractMultiplier` (shared, so the HUD and the server agree); `state.PendingRewards` and
   `state.BossesDefeated` in `RaidRoomService`, fed by `addPendingReward` from `onMapCleared` and the
   Boss branch, banked with the multiplier in `completeRaid` and simply dropped (but REPORTED) by
   `failRaid`/Abandon/disconnect; Cores stripped from `NodeConfig`s Combat tiers 2/3 and `BossLoot`;
   the Cores shop item repriced to Scrap. `RaidClient` shows CONTRABAND/CORES — AT RISK rows plus an
   EXTRACT BONUS row, and every end-of-raid toast names what was banked or lost. Still not built from
   the original Salvage Run layer: `RunLocked` ore, a carry cap, a physical Extraction room.
5. ~~Gauntlet~~ — **CUT FROM v1 (2026-09-08), first post-launch update.** A real card pool with real
   effects plus the run-only perk shop. Biggest content write.
6. ~~Contract~~ — **CUT FROM v1 (2026-09-08), post-launch.** Largest new surface: board, objective
   tracking, rotation, `Permanent` payouts.
7. Enemy AI patterns — **three, not nine**, now that only one mode ships. Pick them for VARIETY
   rather than mode identity (the nine were three-per-mode); worth its own short round once there is
   a real authored room to fight in.

**SCOPE CUT — one mode at release, 2026-09-08.** The user's call, and the right one. Steps 5 and 6
become the first post-launch update; v1 ships steps 2, 3, 4 and 7 only. Reasoning worth keeping:

- **Raids already exist and work.** The overhaul makes them better, it does not make them exist, so
  shipping one mode is not shipping a hole. That is the difference between this cut and cutting a
  system players would notice missing.
- **Verified before agreeing, not assumed:** neither currency the cut modes were to own is stranded
  by it. Cores come from Expedition combat nodes (NodeService.lua:57), cases and Robux; Contraband
  from base-defense boss waves (WaveService.lua:158) and cases. Gauntlet is not the only door to
  either.
- Contract was the single largest unbuilt surface left on the critical path, for no reason. AI
  patterns drop from nine to three — the step that has been blocked behind "what IS a raid" the
  longest just got two-thirds smaller.
- Same character as the PvP recommendation. Both trade release date for a strong first update, and
  between them there are now two updates' worth of already-designed content.

**Two conditions, or the update costs double:**

1. **Step 3 still gets built**, with exactly ONE entry in `RaidConfig.Modes`. Skipping it means
   retrofitting a mode axis later through raid state, config, the terminal, loot settlement and AI
   dispatch. One entry now makes the update purely additive: two more table entries plus content.
2. **Do NOT ship a NARROWED raid.** "Salvage Run owns the ore axis" only means anything when there
   are three modes to choose between. With one, it must not stop granting Cores to stay in its lane —
   it is simply THE raid, plus the stakes layer Salvage Run was going to add (`RunLocked` ore, a carry
   cap, a physical Extraction room). That layer is the actual prize and it is cheap: `settleRunLoot`
   is fully built and completely INERT today, because nothing anywhere is tagged `RunLocked`, so
   pushing deeper risks nothing and extracting protects nothing.

**What the cut strands, and what it does not.** `RaidConfig.CardPool`'s four effectless stubs belong
to Gauntlet, and cards were surfaced to players in an earlier round — so before release, check
whether a card UI is visible that does nothing, and either wire a few trivial effects or hide it
until the update. A visible reward that does nothing is worse than an absent one. The raid shop
rework is NOT stranded: Salvage Run's shop remit was already "capacity and escape", so
`NodeConfig.ShopCatalog`'s vending machine still gets replaced on the v1 path.

**Three Ways In stays valid** as the design record for all three modes — nothing about them was
un-decided, only re-sequenced.

**Five open decisions, each with a recommendation on the page, none blocking steps 1-2:** do the
modes cost the same Energy (rec: yes, 1 each); are Gauntlet cards lost on EVERY exit including a
clean one (rec: yes always — a bankable card makes Gauntlet a permanent-power farm and every other
system has to be balanced around it); does Salvage Run's carry cap cover currency (rec: no, currency
is already exempt from `RunLocked` by an earlier explicit decision); where does the Contract board
live (rec: a third tab on the existing raid terminal, not a new tagged Station — no Studio setup); do
all three modes unlock at once (rec: Salvage Run first, the other two behind Research Tiers).

**Three of those five are now MOOT FOR v1** by the scope cut above — Energy parity, Gauntlet's cards,
and the Contract board's home all belong to modes that no longer ship at release, and the unlock
question answers itself when only one mode exists. They stay recorded because the update has to
answer them. Only "does Salvage Run's carry cap cover currency" (rec: no) is still live, and it is
step 4's to settle.

**The Studio authoring contract, answered for the user during the round.** SUPERSEDED IN PART — every
marker named below is still correct, but this paragraph predates two rounds that added more: `ExitDoor`
shipped 2026-09-03 (step 1), and `PlayerSpawn` + `SpawnZone` shipped 2026-09-08 (see "Spawn zones +
difficulty curves" below, and the Raid Room Build Sheet page, for the full current contract). Kept
because the geometry and slot facts at the end of it are the durable part.
`ServerStorage.RaidRoomModels`, one Model per type named exactly `Start`/`Combat`/`Ambush`/`Heal`/
`Shop`/`Boss` — or, since the room-variants build, a Folder of such Models, see "Decision 3 — room
variants" above. Each needs a **PrimaryPart** and is built centred on the origin, since the Model is
cloned and `PivotTo`'d there. (This paragraph used to say a missing `PrimaryPart` falls back to the
placeholder SILENTLY. It no longer does: `pickRoomTemplate` warns, naming the offender, before
falling back.) Inside: `SpawnPoint`
Parts with a String attribute `EnemyType` from `Scavenger`/`Raider`/`Brute`/`ScrapCrawler`/
`SentinelDrone`/`Siegebreaker`/`VoidwakenHulk` (any key in EnemyConfig's
Types/EliteTypes/BossTypes; unrecognised spawns nothing and warns; none at all falls back to the
random 50-70 stud ring), and an `InteractPoint` Part on Heal/Shop which gets a ProximityPrompt added
automatically. No Model gives a 260x260 concrete square with an invisible guard rail. Rooms build at
`(0, 800, 0)`, 600 studs apart, up to 20 concurrent — each alone in its slot, so rotation never
matters.

### Spawn zones + difficulty curves — DESIGN ROUND 2026-09-07; MARKERS BUILT 2026-09-08, CURVES NOT

Raised by the user after building the first Combat room. Nothing here is implemented; this is the
record of the round so it survives a context reset. **Do not build any of it without a greenlight.**

**The problem, verified against source.** Enemy QUANTITY never scales with run depth.
`RaidConfig.CombatTierComposition` (RaidConfig.lua:316) is the whole story — tier 1/2/3 give 2-3,
3-4, 4-5 enemies at 1.0x/1.4x/1.9x strength — and it keys off a node's WITHIN-MAP Tier, not
`TotalNodesVisited`. So count tops out at 5 forever. A room with authored `SpawnPoint` parts
bypasses the roll entirely, making count literally constant. Meanwhile
`GetRunProgressionMultiplier` (RaidConfig.lua:360) is `1 + step * 0.12`, and at the time of this
round the step itself was unbounded. Net effect: deep raids are five enemies with ever-larger health
bars, and the authored-room path the build sheet recommends makes it worse, not better. The user's
diagnosis was correct.

**CORRECTION 2026-09-23 — the multiplier is no longer unbounded, and the count half is partially
addressed.** The adversarial exploit review (see "Resuming after a context reset") found this same
uncapped ladder was itself exploitable — a raid that never ends paying without limit (F4) — and
capped the STEP, not the intent: `RaidConfig.RunProgressionMaxStep = 10` bounds
`GetRunProgressionStep`, so `GetRunProgressionMultiplier` now tops out at `1 + 10 * 0.12` = 2.2x
instead of climbing forever. Separately, and using the same `TotalNodesVisited` step, the
enemy-COUNT half of this diagnosis — "count tops out at 5 forever" — now has a small answer short of
the zone redesign below: `RaidConfig.GetRunProgressionCountBonus` adds up to
`RunProgressionMaxExtraEnemies` (3) extra bodies to a Combat room's existing count roll, at
`RunProgressionCountPerStep` (0.5) per progression step, and Combat rooms now also apply the run
multiplier to enemy STRENGTH the way Ambush/Boss always did. This is deliberately the MODEST version
of the proposal immediately below, not the proposal itself: it reuses the existing count roll rather
than replacing fixed spawn points with volumes, so a room authored with `SpawnZone`s picks the extra
bodies up automatically and a room with only fixed `SpawnPoint`s still can't grow — which is exactly
the limitation the spawn-zone redesign below still exists to remove. That redesign remains unbuilt
and un-greenlit; nothing below this correction has changed.

**The proposal.** Replace fixed spawn points with spawn ZONES (volumes) for Combat/Ambush. On room
build, roll a composition from a table keyed by raid mode (the project's standard
flat-table-of-strategies shape, and already congruent with Phase 00's three modes). Per-type shares
expressed as a RATIO of a total enemy cap; the total cap grows with `TotalNodesVisited` on a
flattening curve.

**Agreed after discussion, point by point:**

1. **Zones for Combat/Ambush, points for Boss.** Settled. Boss rooms keep authored `SpawnPoint`
   placement so a boss lands exactly where built; regular rooms go random. The existing SpawnPoint
   path is NOT deleted — it stays as the Boss/set-piece tool. The first Combat room already built
   does not need redoing.
   - **CORRECTION 2026-09-09 — this was never true of the CODE, only of the intent.** `beginBoss`
     (RaidRoomService.lua:1203) calls `RunRaidCombat` with NO `explicitSpawns` argument; only
     `beginCombat` (:1000) and the Ambush wave loop (:1080) route through `resolveEnemyPlacements`.
     So a Boss room ignores authored `SpawnPoint`s AND `SpawnZone`s alike and spawns procedurally
     around the room centre. Found while writing the room-authoring checklist, after two rounds of
     notes had repeated the claim. The fix is small — pass `resolveEnemyPlacements(state, count)`
     into `RunRaidCombat` with the same nil-fallback `beginCombat` uses — but it is a CODE change
     and is NOT done. Until it lands, author the marker (it costs nothing and is the right one) but
     do not tune its position.
   - **FIXED 2026-09-09, points only.** `beginBoss` now calls `collectSpawnPoints` directly and
     passes the result as `RunRaidCombat`'s `explicitSpawns`, so an authored Boss room spawns its
     boss exactly where the Part sits. Deliberately NOT `resolveEnemyPlacements`: that path's
     zone-filled enemies would inherit `composition.Multiplier` (2.6x), making every zone-added body
     an elite body — the exact failure Decision 3 of the Boss escort round names. Zones in a Boss
     room stay inert BY DESIGN until the escort build gives minions their own multiplier and roster.
     Note the consequence: with points authored, the points decide the count (one Part, one enemy)
     and the `BossComposition` roll only sizes the procedural fallback — so a one-point Boss room is
     now a reliable single-boss fight without waiting on `EnemyCountMax` dropping to 1.

2. **Two different curves, deliberately opposed.** The user's call, and a sharper answer than the
   "make count the only axis" advice it replaced. QUANTITY grows on a loose log — climbing early,
   flattening late, so encounters never become unreadable mobs. STRENGTH/HP grows on a LOW
   EXPONENTIAL — near-flat for a long opening stretch, then moderate, then steep — used deliberately
   as a SOFT CAP on how far a player can push before a content update raises it.
   - Caution recorded: a flattening count curve plus an exponential strength curve reconverges on
     the "few beefy enemies" endgame the round started out trying to avoid. That is acceptable
     BECAUSE it is the intended wall, but it means the wall's position must be ONE tunable number,
     and it has to be read against the player power curve, not set in isolation.
   - Exponential also needs a hard ceiling. The current multiplier is unbounded; exponential reaches
     absurd/overflowing values much faster than linear. Clamp it.

3. **Server load — the user corrected the premise, and the correction stands.** Max players per
   server will be 8, not the 20 that `RaidConfig.MaxConcurrentInstances` provisions for, so the
   worst-case concurrent enemy count is ~8x a per-raid cap, not 20x. `MaxConcurrentInstances = 20`
   is over-provisioned relative to the real player cap and could simply be lowered to 8.
   - Longer-term idea (user's, deferred to a future update): render enemy MODELS and animations
     client-side only, keeping position, orientation and hitboxes server-authoritative. Sound, and
     compatible with the project's server-authoritative rule as stated. Two notes for whoever picks
     it up: the real server saving is dropping server-side `Humanoid` instances (expensive state
     machines), not the models per se — the AI tick cost stays either way; and it is a change to the
     COMBAT ENGINE CORE (`CombatEncounterService`, `EnemyAI`, `DamagePipeline`), not a small one.
   - **Do not couple the two.** Ship spawn zones with a conservative cap first; do the rendering
     optimisation as its own project, after profiling says it is needed.
   - **RESOLVED — Tier 1 chosen.** See "Enemy rendering tiers" immediately below. Tiers 2 and 3 are
     recorded but explicitly NOT planned; 8 players does not need them.

4. **Ratio rounding — round-up does not work, use a weighted draw instead.** Rounding every type UP
   breaks the budget: total 6 with .5/.35/.15 shares gives 3 + 3 + 1 = 7, over cap. Two workable
   fixes, second preferred:
   - Largest-remainder: floor everything, then hand leftovers to the biggest fractional parts.
   - **Treat ratios as WEIGHTS for a draw, and caps as ceilings rather than quotas.** Draw enemies
     one at a time by weight, skipping any type already at its ceiling, until the total is hit.
     Rare types get a real chance at low totals, the budget can never be exceeded, and there is no
     rounding step at all.

**Enemy rendering tiers — TIER 1 AGREED, NOT BUILT (2026-09-07).**

What enemies are today: full `Humanoid` rigs, moved with `Humanoid:MoveTo` (EnemyAI.lua:117), HP in
`Humanoid.Health`, damage via `TakeDamage` (CombatEncounterService.lua:385). That is the most
expensive per-NPC shape Roblox offers — a physics-simulated state machine doing per-frame ground
raycasts, plus automatic CFrame replication on every part of a moving multi-part rig. At 150+
enemies that is what costs the server, not the AI logic.

- **Tier 1 (AGREED).** Drop the server-side `Humanoid`. One anchored root part per enemy, moved by
  CFrame from the server; HP moves into the enemy record table. Model stays a real, visible,
  debuggable instance. ~80% of the win for ~20% of the work.
- **Tier 2 (recorded, not planned).** Server keeps only an invisible root part; clients build and
  animate the visual rig locally. Replication drops from ~15 parts per enemy to one.
- **Tier 3 (recorded, not planned).** No server instances at all — pure data, manual position
  broadcasts (~15Hz), client-side interpolation. Maximum performance, worst debuggability.

**Why the Tier 1 refactor is smaller than it looks:** this codebase already funnels enemies through
single chokepoints — one damage application (CombatEncounterService.lua:385), one alive check
(:358), one spawn path (:264-289), one movement call (EnemyAI.lua:117) — and `EnemyAI.lua` is 121
lines total. Four places, not a sprawl.

**Everything the user asked for is compatible with Tier 1**, and two things get better:

- **Animations — no Humanoid needed.** `AnimationController` + an `Animator` child plays animations
  on any rig. Drive it client-side: the server replicates "enemy is now in state X", the client
  plays the matching track. Zero animation cost on the server.
- **States (Idle / Combat / Ragdolled, a small set).** Fits the project's standard
  flat-table-of-strategies convention exactly — a sibling table beside `EnemyAI.Patterns`, one
  function plus one config entry per state.
- **Ragdoll gets CHEAPER.** Anchored normally; on death unanchor, add constraints, hand it to
  physics. Physics cost is paid only for actively ragdolling enemies for a couple of seconds,
  instead of for every living enemy every frame.
- **Pathfinding gets POSSIBLE.** `PathfindingService` does not require a Humanoid
  (`CreatePath` -> `ComputeAsync` -> `GetWaypoints`, then move along the waypoints yourself — which
  IS Tier 1's movement loop). Today `MoveTo` walks in a STRAIGHT LINE with no navmesh, so enemies
  already grind into walls; this is a gain, not a regression. Note while building rooms with
  interior geometry.

**Movement ladder for the pathfinding (the throttling matters).** `ComputeAsync` is expensive and
yields — 150 enemies pathing once a second would bury the server. Three steps, cheapest first:

1. Raycast at the target. Clear line? Walk straight. This is the common case.
2. Blocked? Compute a path, follow waypoints, recompute on a ~0.5-1s throttle, STAGGERED across
   enemies so they never all recompute on one frame.
3. **Stuck detector** — track ground actually covered; moving but not closing distance forces a
   recompute. This was the user's own framing ("im moving and moving but i dont get closer, let me
   make a path around") and it is the cheapest, most effective piece of the three.

Set `AgentRadius`/`AgentHeight` to match enemy size or they clip corners and wedge. The navmesh is
built from `CanCollide` geometry, so an invisible ring wall is correctly pathed around.

**DEFERRED DESIGN ROUND — per-enemy AI, states and animation.** The user wants a dedicated round,
later and closer to release, covering each enemy type's AI pattern, its state set, its behaviour,
and how each animation fits. Not now; the nine patterns Phase 00 names (three per mode) are the
input to that conversation.

**THE STUDIO CONTRACT — SETTLED 2026-09-08, BUILT 2026-09-08.** Raised by the user mid-way through
hand-building the first Combat room: they had the geometry but none of the markers, and wanted to
know what a map needs to FUNCTION before placing any. The full sheet is on the Raid Room Build Sheet
page (linked in "Road to release"), which now separates markers that are live from markers that are
agreed-but-unread. What follows is the reasoning, which the page does not carry in full.

**`PlayerSpawn` — a new marker, and the one that actually blocks room authoring.** There is no
player-entry marker at all today: `teleportPlayerToRoom` (RaidRoomService.lua:261) pivots the
character to `roomOrigin + Vector3.new(0, RaidConfig.RoomSpawnHeightOffset, 0)`, i.e. 5 studs above
the model's PIVOT, dead centre, facing an arbitrary direction. That was invisible while every room
was the 260x260 placeholder square. It stops being invisible the moment rooms grow long on Z the way
the width budget pushes them to — the player lands in the MIDDLE of the room with half the level
behind them. Fix is ~6 lines plus a `RaidConfig.PlayerSpawnName` constant: pivot to the marker's full
CFrame (so it sets FACING as well as position, which the current code cannot express at all), falling
back to origin+5 when absent. Silent-fallback ladder preserved; every room already built keeps
working. **Built 2026-09-08, same session, on the user's explicit greenlight.**
`teleportPlayerToRoom` (RaidRoomService.lua:275) now takes the room model as a parameter and pivots
the player to a `PlayerSpawn` Part's FULL CFrame when one exists; more than one found warns and uses
the first; absent (or no room model at all, e.g. mid-teardown), the pre-existing
origin+`RoomSpawnHeightOffset` fallback is unchanged, with no warn — a room legitimately may not have
one yet.

**`SpawnZone` — decided, point by point:**

1. **Dumb volumes plus an optional `Weight` number attribute** (absent = 1). A zone says WHERE, never
   WHAT. Per-zone `EnemyTypes` filtering was rejected: it would put composition in the mode-keyed
   table AND in every room model, which is the two-places-that-drift failure this codebase keeps
   having (`OreGate`, `ApplyMods`, `MaxDeployedRobots` all exist because of it). Weight is the one
   thing geometry genuinely knows that config cannot — a big arena should catch more spawns than a
   side alcove, and only the room knows which is which.
2. **Points and zones are BOTH honoured in the same room.** Authored `SpawnPoint`s spawn first and
   COUNT AGAINST the room's enemy budget; zones fill whatever remains. Rejected the simpler "points
   win outright" and "zones win in Combat/Ambush" because both make a pinned set piece plus a rolled
   encounter impossible without a second system. Note this supersedes the flat "zones for
   Combat/Ambush, points for Boss" framing of the 2026-09-07 round — Boss is still INTENDED to use
   points, but Combat may mix. (Boss honours neither marker in code today — see the correction under
   point 1 of the 2026-09-07 round above.)
3. **Neither marker present: warn loudly NAMING THE ROOM, then the existing 50-70 stud ring.** The
   fallback keeps the run alive (missing-art rule); the warn is what makes a half-authored room
   findable, since a silently-ring-spawning room is indistinguishable from a correct one until you
   notice enemies appearing through a wall. Chosen over a bare silent fallback for exactly the
   reason CLAUDE.md gives silent failure its own section.
4. **Placement inside a zone:** random X/Z within the part's own object space (so a ROTATED zone
   works as drawn), downward raycast to find the floor, minimum-distance check against the player.
   A zone that fails every attempt is skipped and warns. There is no "random point inside a part"
   helper anywhere in the repo today — this sets the precedent, so it wants writing as a shared
   function, not inline.
5. **Studio-side, the service force-sets `Transparency = 1`, `CanCollide = false` and
   `CanQuery = false`** at build time, so the author leaves the zone bright and visible in Studio and
   it disappears in game. `CanQuery = false` is deliberate and not cosmetic: a query-able invisible
   volume in front of the player is precisely the "I click and nothing happens" bug CLAUDE.md
   records, where mouse rays hit a part nobody can see.

**Built 2026-09-08, same session, on the user's explicit greenlight** (all in `RaidRoomService.lua`
unless noted):

- **`beginAmbush` gained authored-spawn support it never had.** `resolveEnemyPlacements` is the
  shared resolver, called by both `beginCombat` and by EACH WAVE of `beginAmbush` — fresh placements
  are rolled per wave rather than reusing one set for the whole encounter, so points and zones stay
  meaningful across a multi-wave fight instead of only applying to the first.
- **`pickRaidSpawnKeys` became a forward-declared local** (`local pickRaidSpawnKeys`, assigned later
  in the file as `pickRaidSpawnKeys = function(...)`), because `resolveEnemyPlacements` needs to call
  it — to draw a type key for each zone-filled position — from above its own definition further down
  the file. Same pattern the file already used for `enterNode`.
- **The empty-placement fallback, and why it matters.** If placement into zones (after topping up any
  authored points) yields zero positions — a zone floating over a gap with no floor beneath it, or one
  packed so close to the entrance that nothing inside it ever clears `SpawnZoneMinPlayerDistance` —
  `resolveEnemyPlacements` falls back to the procedural ring rather than handing the caller an empty
  list. This matters because `RunRaidCombat`'s zero-spawn path does not hang; it warns and resolves as
  "Cleared" — so an all-zones-failed room would otherwise have paid full loot for a fight that never
  happened, silently.
- **The `PlaceholderRoom` attribute, and why the warn needed it.** `buildFallbackRoom` now sets a
  `PlaceholderRoom` attribute on the placeholder Model, and `resolveEnemyPlacements`'s "neither marker
  present" warn checks for it before firing. Without that check the warn would fire on literally every
  single raid that falls back to the placeholder square, since that room legitimately has neither a
  `SpawnPoint` nor a `SpawnZone` by design — the warn exists to make a half-authored REAL room
  findable, not to complain about the intentional fallback.

**Still NOT built, still deferred — do not mistake this round for the curve work.** The quantity/
strength growth curves (loose-log count, low-exponential strength, both described earlier in this
section) and the mode-keyed composition pools — including whether `CombatTierComposition` survives at
all or is replaced outright — are untouched. Both belong to Phase 00 step 3, mode plumbing. This round
shipped marker plumbing only (`PlayerSpawn`, `SpawnZone`) against today's `CombatTierComposition`
budget, unchanged — a hand-authored room still draws from the same 2-3/3-4/4-5-enemy, 1.0x/1.4x/1.9x
tiers it always has; only WHERE those enemies land is new.

Where it fits: essentially Phase 00 step 3 (mode plumbing) with a spawn-composition layer attached.
`state.TotalNodesVisited` is already the depth input and already drives loot, so enemy count and
reward would scale off one counter and stay coherent for free.

### The Voidium infestation — LORE ROUND 2026-09-08. Pool split + `Siegebreaker` SHIPPED 2026-09-09; the bloom itself still NOTHING BUILT.

Raised by the user while thinking about what the raid Boss should be. This started as fiction and
scoping, not a build — no code existed for any of it at the time. Recorded because it is the input
step 7 (enemy AI patterns) has been waiting on — what enemies DO follows from what they ARE. One
piece of it stopped being fiction on 2026-09-09: see "Two things to settle before any of it is
built," item 1, now RESOLVED, and the new "Siegebreaker — design rationale" subsection below. The
bloom itself (Decision 2) is still unbuilt.

**The finding the round started from, and the state as of 2026-09-08 (now fixed — read on).**
`RaidConfig.BossComposition` (RaidConfig.lua:394) was 1-2 enemies at 2.6x drawn from
`EnemyConfig.EliteTypes`, and `EliteTypes` had exactly ONE entry. So every Boss room was one or two
`VoidwakenHulk`s, and they were also what elite waves spawned in base defense. **There was no boss
identity — there was a pool of one.** This is the exact problem item 1 below was raised to solve,
and it is now solved: `BossComposition` reads a new `EnemyConfig.BossTypes` table instead, holding
only `VoidwakenHulk`; `EliteTypes` now holds a different entry, `Siegebreaker`, built for this
session. The two pools cannot cross-contaminate any more — see that item for the mechanics.

**What was already written, and is now load-bearing.** `EnemyConfig.lua`'s header defines two
factions: **Construct** (scavenged security drones and automation gone haywire — "the nastier ones
are Voidium-corrupted") and **Rebel** (Mad-Max raiders, explicitly unrelated). `VoidwakenHulk` is
built on `ConstructBase`. The Forge already treats Voidium Shard as "not from around here, handle
carefully". So Voidium was ALREADY the thing that makes machines dangerous before this round.

**Decision 1 — Voidium infests hosts, it does not birth creatures.** The user's opening idea was
creatures BORN from Voidium, which would have made the Hulk genuinely alive. Settled instead on a
reading that keeps everything already written true: Voidium gets into MACHINES near the surface (every
Construct; the Hulk is what happens when it gets all the way in), and deeper down it stops needing a
host. The Hulk's own line — "Whatever Voidium did to this one" — presumes a "this one" existed
first, so corruption is the reading the config already commits to. Framing Voidium as a PROCESS with
stages rather than a species is also more useful, because stages are levels.

**Decision 2 — the raid boss is a Voidium BLOOM, not another humanoid.** A stationary/anchored
crystalline mass that spawns corrupted Constructs while the player breaks it. Four reasons, in order
of weight:

1. It is not the Hulk. Otherwise the Boss room is the elite you already fight, larger.
2. **It is the only boss shape that works with three AI patterns.** The scope cut took step 7 from
   nine patterns to three. A stationary spawner is a completely different fight from `Chaser`
   without needing a fourth pattern — the adds do the chasing.
3. **It is buildable with the art that exists.** There is no `VoidwakenHulk` rig in
   `ServerStorage.EnemyModels` yet, and a crystalline mass is geometry and material rather than an
   animated character rig. Congruent with the animation deferral above.
4. It closes the loop the ore ladder already implies: Voidium Shard is the top ore and refines to
   Voidium Core for the best gear, so the player is harvesting the infestation and putting it in
   their gun. That was latent in the config, not invented here.

**Decision 3 — the raid boss is MECHANICALLY the boss but LORE-WISE a minor thing.** The user's
call, and the sharpest part of the round. The bigger bosses are reserved for events and post-launch
updates. Mechanically nothing changes: it stays in `EliteTypes`, `BossComposition`'s 1-2 at 2.6x is
the right shape. **CORRECTION 2026-09-09 — "it stays in `EliteTypes`" is no longer literally
true.** The user's later call the same day (item 1 below, RESOLVED) moved `VoidwakenHulk` into a
new `BossTypes` table and put a different enemy, `Siegebreaker`, in `EliteTypes` instead — so the
Hulk is no longer what a base-defense elite wave spawns. Nothing about the LORE point here changes:
the Hulk still fills the boss slot, `BossComposition`'s shape (1-2 at 2.6x) is untouched, and this
decision's actual claim — mechanically-boss, lore-wise-minor — still holds. What moved is only
which enemy sits in which pool. What it buys:

- **It solves the repetition problem.** You fight a Boss room every map. If the raid boss were the
  apex of the world you would kill the biggest thing alive weekly and it would stop meaning anything
  by the third run. A local bloom recurring is just what an infestation does.
- **It keeps escalation room.** An apex raid boss forces every future event boss to top it, which is
  power-creep and name inflation from day one.
- It retro-justifies the Hulk: a corrupted Construct implies something nearby doing the corrupting,
  and that something is now what you fight at the end of the map.

The resulting ladder as ORIGINALLY DESIGNED in this round — three rungs built, one deliberately
undefined:

| Rung | What | State |
|---|---|---|
| Trash | Constructs and Rebels | 5 types built |
| Elite | `VoidwakenHulk` | built; what a bloom makes of what it finds |
| Raid boss | the bloom | DESIGNED, not built, unnamed |
| Event bosses | whatever seeds blooms | undefined ON PURPOSE |

**RECONCILIATION 2026-09-09 — read this honestly, not smoothed over.** The table above is what this
round intended: the bloom as the real raid boss, the Hulk as the elite beneath it (Decision 2,
reason 1 — "It is not the Hulk. Otherwise the Boss room is the elite you already fight, larger.").
That is NOT what shipped. The user's separate call today, ahead of the bloom existing, moved the
Hulk into the boss slot and put a new enemy, `Siegebreaker`, in the elite slot instead (item 1
below, RESOLVED). The ladder as it actually stands right now:

| Rung | What | State |
|---|---|---|
| Trash | Constructs and Rebels | 5 types built |
| Elite | `Siegebreaker` | built 2026-09-09 — see "Siegebreaker — design rationale" below |
| Raid boss | `VoidwakenHulk` | built; holding the boss slot until the bloom exists |
| Event bosses | whatever seeds blooms | undefined ON PURPOSE |

Read `EnemyConfig.BossTypes` as **"whatever currently occupies the boss slot,"** not as "the boss."
Today that's the Hulk, filling in early. When the bloom ships, the more likely shape is `BossTypes`
gaining a SECOND entry (the bloom) rather than replacing the Hulk outright — a Boss room could then
roll either, or the bloom specifically at deeper stages — but that is a future decision, not one
made here; do not assume it before it's discussed.

**The art consequence is real and worth stating plainly:** whoever designs/models `VoidwakenHulk`
should NOT treat it as the final word on what a raid Boss room looks or feels like. Decision 2's
whole point was that the actual raid boss should not just be "the elite you already fought, but
bigger" — that reasoning didn't go away just because the Hulk is filling the slot early. Build the
Hulk knowing a mechanically and visually different boss is still coming behind it. Enemy art
direction (covers both `Siegebreaker` and `VoidwakenHulk`):
https://claude.ai/code/artifact/4089f017-a2e1-4012-973a-1e394c58f05f

**Two things to settle before any of it is built:**

1. ~~**`EliteTypes` is one pool serving three jobs**~~ — RESOLVED 2026-09-09. Took the separate-pool
   option this item itself named as the cheapest fix: `EnemyConfig.BossTypes` (EnemyConfig.lua:174)
   is a new table, read only by `RaidRoomService.pickBossSpawnKeys` (RaidRoomService.lua:962);
   `EnemyConfig.EliteTypes` is read only by the base-defense elite pick
   (`CombatEncounterService.pickSpawnKeys`, line 183) and by authored `SpawnPoint` markers, unaffected
   by the split since `RaidConfig.lua:194`'s comment already covered any `Types`/`EliteTypes`/
   `BossTypes` key. `VoidwakenHulk` moved into `BossTypes`; `Siegebreaker` is a brand-new type built
   to refill `EliteTypes` rather than leaving it empty. `getEnemyTypeData`
   (`CombatEncounterService.lua:209`) now falls through all three tables in one lookup, shared by
   every spawn path — wave, raid, boss, and authored point alike — so nothing had to special-case
   which pool an enemy came from. See "Siegebreaker — design rationale" below for what the new type
   actually is and why it is not just the Hulk under a different name.
2. **The Boss node's `DisplayName` is currently `"Boss"`**, and exit doors plus the Sector Map both
   render the destination type's DisplayName — so the door announces exactly the significance
   Decision 3 says it should not have. `"Bloom"`/`"Growth"`/`"Infestation"` reads as a place rather
   than a title fight. One config string, no code. Held until the lore settles, because the word IS
   the lore.

**Still open:** the bloom has no name, and the event-boss tier is intentionally blank. The user is
still thinking about both. Do not invent either.

### Siegebreaker — design rationale (SHIPPED 2026-09-09, NOT verified in Studio)

Full spec: https://claude.ai/code/artifact/152b056a-bfd6-454d-923a-04e312e6ffa9

The new elite that refills `EliteTypes` now that `VoidwakenHulk` moved out (item 1 above,
RESOLVED). Two rungs, two identities, deliberately not the same axis:

- **Elite = armour.** `Siegebreaker`'s `Defense` is 45 (`EnemyConfig.EliteTypes.Siegebreaker`,
  EnemyConfig.lua) against a Construct base of 12 and the Hulk's own 28 — the most heavily
  defended thing in the game. A player fighting one watches their own damage numbers drop and has
  to change weapon or target rather than just out-DPSing it, which is a different pressure than
  "this one has more HP." Its HP, 140, is unremarkable on purpose.
- **Boss = mass.** `VoidwakenHulk` out-bulks it on raw HP instead — 340 base
  (`EnemyConfig.BossTypes.VoidwakenHulk`), which then also eats `RaidConfig.BossComposition`'s
  2.6x multiplier (884) before the run's own strength scaling is even applied. Its own `Defense`
  (28) is lower than the Siegebreaker's. The split is deliberate: elite tests whether you can get
  through something, boss tests whether you can out-damage something before it out-damages you.

**The slam replaces contact damage, it does not stack on it.** `Siegebreaker`'s `ContactDamage` is
0 — `EnemyAI.Patterns.Slam` (EnemyAI.lua) is a three-state idle/wind-up/impact cycle instead of the
flat per-tick `Chaser` hit, and it is the ONLY damage the type deals. Stacking a heavy telegraphed
hit on top of a normal contact cooldown would read as unfair damage from something standing next to
you rather than a single readable blow; replacing it keeps the telegraph honest — the red disc
growing under the model, holding for `SlamWindup` (0.9s) before the hit lands on a `SlamCooldown`
(3.5s) cycle, timed from IMPACT rather than from wind-up start specifically so a future tuning pass
shortening the tell can't silently shorten the real cooldown as a side effect.

**The key mechanic, and the one future session should not "fix":** the impact's radius check
(`(context.TargetPosition - enemy.SlamCentre).Magnitude <= enemy.SlamRadius`, `SlamRadius` = 14
studs) is deliberately MODE-AGNOSTIC. `context.TargetPosition` is already documented (EnemyAI.lua's
own header) as "just a point in space to defend" — the plot's fixed anchor in a wave, the player's
own live position in a raid — and `Slam` reuses that one check unmodified in both. The wall cannot
move, so in base defense the same check is an unavoidable heavy hit on a long, readable cadence,
which is fine, it is a wall. A raid player CAN walk out of the 14-stud circle during the 0.9s
wind-up they were just shown, so the identical check is a genuine, learnable dodge there. **Do not
split this into a wave-branch and a raid-branch "to make it fair"** — the fairness difference IS
the point, and it already falls out of what `TargetPosition` means in each mode without this
pattern ever needing to know which mode it is running in. `EnemyAI.lua`'s own inline comment on the
impact branch says the same thing, for the same reason a design note should say it too: this is the
kind of "obviously asymmetric, therefore surely a bug" shape that gets "fixed" by someone who hasn't
read why it's asymmetric on purpose.

**Raids could not actually spawn one until 2026-09-09 (second pass) — fixed.** The paragraph above
was written describing a raid dodge that nothing could reach. When the elite/boss pools were split
earlier the same day, `pickBossSpawnKeys` moved off `EliteTypes` onto the new `BossTypes`, and no
raid path was left reading `EliteTypes` at all: Combat rooms, Ambush waves and zone fill all draw
from `pickRaidSpawnKeys` → `WaveConfig.EnemyTypes` (`Raider`/`Scavenger`/`Brute`), and Boss rooms
draw from `BossTypes` (`VoidwakenHulk`). So the Siegebreaker existed only on elite waves, and the
key mechanic documented above was unreachable. Fallout from the split, not a decision — there was
never a working state to notice the loss from, because the type was created in that same commit.

Fixed by adding `EliteChance` to `RaidConfig.CombatTierComposition` (0 / 0.20 / 0.35 by Tier) and an
elite substitution step in `pickRaidSpawnKeys`. Four things worth not re-litigating:

- **It substitutes rather than adds**, diverging from the wave side, which adds one elite on top of
  the normal count. A wave is 8+ enemies; a raid room is 2-5, so the same "one more unit" is a much
  bigger spike there. Substituting also keeps `count` honest as the room's enemy budget, which
  `resolveEnemyPlacements` relies on to know how many zone positions to top authored SpawnPoints up
  to.
- **Tier 1 is zero** — `GetCombatTierForStage` puts stages 1-2 there, and the opening rooms should
  stay legible while a player is still reading the map.
- **No unfiltered fallback for the elite draw.** The normal roster falls back to the unfiltered list
  so a raid is never empty; an elite is a bonus threat, so "no built model yet" simply means no
  elite rather than a key that warns and skips inside `spawnEnemy`, silently costing the room an
  enemy. This is also why the change is safe to ship before the `Siegebreaker` Model exists.
- **Ambush deliberately passes no chance.** It is already the tougher variant (2-8 ramping waves,
  any single loss failing the raid); stacking a slam unit onto that compounds two curves tuned
  independently. If Ambush should get elites later it gets its OWN number, not a reuse of the
  Combat one.

Authored `SpawnPoint` Parts remain the way to pin a Siegebreaker into a specific room by hand
(`RaidConfig.SpawnPointEnemyAttribute` accepts `EliteTypes` keys) and are untouched by any of this —
a room that states its own composition still gets exactly what it asked for.

Every number above — `HP`, `Defense`, `SlamWindup`, `SlamDamage` (42), `SlamRadius`, `SlamCooldown`,
and the Hulk's new 340 HP — is unplaytested config the user expects to rebalance once this is
actually run in Studio. None of it should be read as tuned or final.

### Enemy model variant folders — SHIPPED 2026-09-09, NOT verified in Studio

`ServerStorage.EnemyModels.<ModelName>` may now be either a single Model (as before) or a **Folder
of Model variants**, one drawn per spawn — `pickEnemyTemplate` in `CombatEncounterService.lua`,
deliberately mirroring `RaidRoomService.pickRoomTemplate` rather than inventing a second answer to
the same question.

**Why.** Raised by the user while planning how to clothe the Rebel rigs. `EnemyModels` was a strict
`FindFirstChild(ModelName)` lookup, so every Scavenger on the field was the same clone — and
`WaveConfig.GetEnemyCount` is `5 + floor(wave * 1.5)`, meaning eight-plus identical people by wave 2.
The art direction had already called for varying their props precisely so a crowd would not read as
a rendering bug; the loader could not honour that. Rooms got variant folders on 2026-09-08 and
enemies never did, which was an oversight rather than a decision.

**Shuffled bag, not an independent roll (added 2026-09-09, after the first Studio look).** The
first cut was `variants[math.random(1, #variants)]`. Correct, and it still looked repetitive in
Studio — which is the actual bug, because the whole feature exists to fix an appearance. Independent
uniform draws clump: with 3 variants over the 8-ish spawns of one wave, ~33% of adjacent pairs match
and ~44% of waves contain a three-in-a-row. A crowd standing next to itself is exactly where that
clumping is most visible, so a Scavenger wave still read as copy-pasted.

`drawVariant` now keeps a shuffled bag per folder (keyed by `GetFullName()`, server-lifetime), deals
every variant once before reshuffling, and swaps the new bag's opener if it matches the previous
bag's last card — an adjacent repeat across a bag boundary being the one clump a bag alone still
allows, and the one most likely to be noticed. Both rates drop to zero. The bag is filtered against
the caller's freshly-collected variant list on every draw, so deleting a variant (or clearing its
`PrimaryPart`) in Studio mid-session cannot leave a stale template queued for cloning.

This also forced the split of `collectVariants` (what is usable) from `drawVariant` (take one):
`HasModelFor` asks whether a spawn is POSSIBLE and is called in a loop over every enemy key by
`pickRaidSpawnKeys`/`pickBossSpawnKeys`. Routing it through the draw would have burned bagged picks
for a question no enemy was spawned to answer — easily enough to empty the bag before the wave that
reads it even starts. With a stateless uniform roll that overlap was harmless, which is why the
first cut got away with a single function.

`RaidRoomService.pickRoomTemplate` was deliberately left on the plain uniform roll: it draws once
per room build rather than eight-plus times a wave, so there is no crowd to look copy-pasted. Worth
revisiting if a run's rooms start reading as samey.

**Two deliberate divergences from `pickRoomTemplate`, both worth keeping:**

1. **The skipped-variant warning is warn-once, keyed by the folder's full name.** `pickRoomTemplate`
   warns unguarded because it runs ONCE per room build. This runs once per ENEMY — eight-plus times
   a wave, every wave — so the same unguarded warn would bury the Output window it exists to be
   noticed in.
2. **`HasModelFor` runs the full variant collect, not a bare `FindFirstChild`.** An empty variant folder, or one
   whose every Model is missing a `PrimaryPart`, exists but cannot spawn anything. Answering "yes"
   for it would let `pickRaidSpawnKeys`/`pickBossSpawnKeys` draw that key and then spawn nothing —
   the exact silent skip `HasModelFor` was written to prevent.

`spawnEnemy`'s two failure messages were also split apart: "you haven't built it yet" and "you built
it but it isn't usable" send someone to two different places in Studio, and the single combined
message would have sent them hunting for a missing model that was sitting right there.

### Burrower enemy — DEFERRED TO A POST-LAUNCH UPDATE (raised and shelved 2026-09-09)

Raised by the user while planning the Scavenger's model: an enemy with mechanical claws that digs
underground and resurfaces near the player, which would also justify why it is fast. Explored, then
**deliberately shelved by the user for a future content update** rather than built — recorded here so
the reasoning is not re-derived from scratch next time it comes up.

**Why it did NOT go on the Scavenger.** Burrowing is a watch-that-one mechanic and the Scavenger is
bulk chaff — `WaveConfig.GetEnemyCount` is `5 + floor(wave * 1.5)`, so eight or more are on the field
by wave 2 and the roster is only three types deep. Eight simultaneous burrowers is noise, not
tension. The mechanic wants its own low-count enemy. This was the user's own call after the tension
was raised.

**The lore question, and how it was settled.** A clawed digging creature initially looked like it
reopened Decision 1 above ("Voidium infests hosts, it does not birth creatures"). It does not, on the
user's reading: the claws are **mechanical, scavenged and strapped on**, which is exactly the Rebel
faction brief in `EnemyConfig.lua`'s header — everything a Rebel wears was taken off something else.
A Rebel wielding a digging rig torn off a Construct reinforces the faction rather than straining it.
That reading stands whether or not the burrow mechanic is ever built, and it is also just a better
Scavenger prop than the "improvised weapon" the art direction originally called for: it gives the
crowd a CONSTANT (every Scavenger has the claw) while leaving the rest of the body free to vary, and
it explains why the game's weakest enemy is dangerous at all — the claw is the threat, the person
swinging it is 18 HP.

**Three things already worked out, for whenever it is built:**

1. **It would be the third `EnemyAI.Patterns` entry** — one function plus one config entry, no
   dispatch change, same as `Slam` was.
2. **It reads differently per mode, and that is fine — see `Slam`'s precedent.** In a raid the player
   IS the damage sink, so surfacing next to them is a straightforward ambush. In base defense
   enemies target the WALL, not the player, so "surface near the player" has no target — but
   surfacing PAST the player's turret coverage is a real flank, since turrets have range and the
   whole approach is what the defenses are built along. Do not branch on mode; let
   `context.TargetPosition` mean what it already means.
3. **The one hazard, and it is a bug this file has already recorded once.** `isEnemyAlive` is
   `Health > 0 and PrimaryPart ~= nil` (CombatEncounterService.lua), and its comment records a real
   incident where an enemy that was alive but untargetable meant **the wave never ended**. So a
   burrowed state must be a FLAG on the enemy record — never removing `PrimaryPart`, destroying
   parts, or unparenting the Model — and the resurface must run off a guaranteed timer, not a
   condition that can fail to fire. An alive, unkillable, underground enemy is that exact bug again.

**Also noted:** `EnemyConfig.ScrapCrawler` ("a maintenance drone with its safety governor long since
fried. Erratic, not smart.") is defined, never spawned, Construct faction, 22 HP, speed 14 — it was
floated as the natural home for this and is still sitting unused in the config. Adding any unused
type to the live roster is one string in `WaveConfig.EnemyTypes`, currently
`{ "Raider", "Scavenger", "Brute" }`.


### Boss escort — spawn zones in the Boss room — DESIGN ROUND 2026-09-09. NOTHING BUILT.

Raised by the user: can a Boss room carry a spawn ZONE as well as its authored `SpawnPoint`, so the
first few boss nodes are the bloom alone and deeper ones are bloom + minions? Yes — and it needs
almost no new machinery, because the 2026-09-07/08 spawn round already decided points and zones are
both honoured in the same room (see "Spawn zones + difficulty curves" above, agreed point 2).

**Decision 1 — the Boss room is one authored `SpawnPoint` plus zones, and the escort needs no
"activate at node N" flag.** Points spawn first and count against the room's enemy budget; zones fill
whatever remains. So at shallow depth the budget is consumed by the bloom's point and the zones fill
nothing — the boss-alone opening falls out of the existing curve rather than being switched on. A
per-zone activation attribute was explicitly REJECTED: it would put encounter scaling in the room
model as well as in config, which is the two-places-that-drift failure `OreGate`/`ApplyMods`/
`MaxDeployedRobots` all exist because of. Geometry says WHERE, config says HOW MANY.

**Decision 2 — `BossComposition` drops to exactly one.** `RaidConfig.BossComposition`
(RaidConfig.lua:394) currently rolls `EnemyCountMin = 1, EnemyCountMax = 2`. The bloom is a single
set-piece (see "The Voidium infestation", Decision 2), so this becomes `1, 1` and the room is
authored with ONE point. Left at 1-2 it would need two authored points and half of all boss rooms
would leave one unused.

**Decision 3 — minions are FEWER, not weaker.** The offset is on the QUANTITY curve only. A minion at
a given depth is exactly as tough as a regular Combat enemy at that depth: same roster
(`EnemyConfig.Types`, NOT `EliteTypes`), same run-progression strength multiplier. What they do not
get is the bloom's `BossComposition.Multiplier` of 2.6 — two multipliers live in the room, one for
the bloom and one for the escort. Sharing it would mean every added body is an added ELITE body and
the room's difficulty jumps far past what its enemy count suggests. Drawing the escort from
`EliteTypes` was rejected for the same reason: a bloom flanked by two Hulks is just a second boss
fight.

**Decision 4 — the offset is a FRACTION of the Combat count, not a subtraction.** The user's call
after both were laid out:

- Subtraction (`combatCount - 3`) keeps a constant gap forever, so deep boss rooms end up with nearly
  a full Combat room's worth of minions PLUS a boss — boss rooms get relatively heavier with depth.
- Fraction keeps the room's shape proportional at every depth.

The expression, one tunable:

```
minions = math.max(0, math.floor(combatCount * RaidConfig.BossMinionFraction) - 1)
```

The `-1` is STRUCTURAL, not a knob. A pure fraction does not produce the boss-alone opening the round
started from: shallow Combat rolls ~2, and `floor(2 * 0.6)` is 1, so the very first boss node would
already have an escort. With the `-1`: shallow resolves to 0 (bloom alone), `combatCount = 6`
resolves to 2. Do not "simplify" it away.

`RaidConfig.BossMinionFraction = 0.6` as a first guess, to sit beside `BossComposition`. It is the
single number to move in playtesting; the shape around it should not need touching.

**Decision 5 — the min-distance check widens to cover placed spawns, not just the player.** The spawn
round already specifies a minimum-distance test against the player when placing inside a zone. A
Boss-room zone that overlaps the arena would otherwise drop a Scavenger inside the bloom. Testing
against anything already spawned in the room is nearly free at these counts and is the difference
between an escort and a pile.

**Decision 6 — spawn markers are ALWAYS live; nothing about them is proximity-gated.** Confirmed by
the user 2026-09-09 after misreading the Heal/Shop `InteractPoint` prompt's 12-stud
`MaxActivationDistance` as applying to spawning: "spawnzones and spawnpoints on raids should never
have to activate like this, they should be active by design all the time." They already are — no
spawn marker anywhere consults player distance to decide whether to fire. The one distance number
near spawning, `SpawnZoneMinPlayerDistance` (25), is a PLACEMENT rejection rule, not an activation
gate: the zone is always live, it just will not use whichever part of itself the player is standing
in. Worth recording because the two read alike on a checklist and the distinction is the difference
between "zone off" and "zone on, minus a corner."

**Decision 7 — the per-marker firing rules, stated plainly.** All four already hold in code or in the
recorded design; written down because the user set them out as one set and they had never been
listed together:

| Marker | Room | Fires |
|---|---|---|
| `SpawnPoint` | Boss | Once — it is the boss |
| `SpawnZone` | Boss | Live, but contributes nothing until the `BossMinionFraction` threshold |
| `SpawnZone` | Combat | Once, count from the quantity curve |
| `SpawnZone` | Ambush | Once per wave, wave count from run depth |

**Ambush wave soft cap raised to 8 (2026-09-09).** `RaidConfig.AmbushWaveMax` 7 → 8, the user's
number. `RollAmbushWaveCount(totalNodesVisited)` already climbs toward it with run depth and clamps
there, so this is purely how far a deep run can push Ambush length. Independent of the unbuilt
curves — it works today.

**Explicitly PARKED — minions arriving mid-fight at boss HP thresholds.** Raised in passing and worth
building eventually, but it is the Ambush multi-wave mechanism, not this one: count here is decided
ONCE at room build from `totalNodesVisited`, the same input Combat rooms use. Folding a second
trigger into the boss room would make it two systems at once. Separate build, later.

**Also depends on `beginBoss` reading authored placements at all**, which it does not — see the
2026-09-09 correction under "Spawn zones + difficulty curves" point 1. The escort has nowhere to be
placed until that one-line-ish fix lands, since zones in a Boss room are read by nothing.
(Superseded: `beginBoss` reads SpawnPoints now.)

**BUILT 2026-09-15 — interim count, user's pick of three options.** The depth-based quantity curve
is still unbuilt, so `combatCount` is `math.random` over `CombatTierComposition[node.Tier]` (boss
nodes are always `BossTier` 3 → 4–5 → **1–2 minions**, never 0, until the curve lands and the `-1`
starts producing boss-alone shallow rooms). What shipped, by decision:
- D2: `BossComposition` is `1, 1`.
- D3: minions use `pickRaidSpawnKeys(n, 0)` (normal roster, no elites) at
  `CombatTierComposition[tier].Multiplier`, which is exactly what `beginCombat` passes (no run
  multiplier — the design text says "run-progression" but a real Combat room doesn't apply it, and
  "as tough as a regular Combat enemy" is the rule). Carried per spawn entry via a new optional
  `Multiplier` field, since `RunRaidCombat` takes one encounter multiplier.
- D4: `RaidConfig.BossMinionFraction = 0.6` with the structural `-1`.
- D5: `placeInZones` takes an optional `avoid` list; `RaidConfig.SpawnZoneMinSpawnDistance = 20`
  from the boss's SpawnPoint and earlier minions. A RINGED boss (no SpawnPoint) isn't avoided — his
  position isn't known until `RunRaidCombat` places him.
- `RunRaidCombat` now spawns `explicitSpawns` AND the `spawnKeys` ring when both are non-empty (it
  was either/or); every older caller passes an empty `spawnKeys` alongside explicit spawns.

**Depends on:** the spawn-zone curves themselves, which are DESIGNED but NOT BUILT (see "Spawn zones
+ difficulty curves" above — markers built 2026-09-08, curves not). There is no `combatCount` curve
to take a fraction OF until that lands, so this cannot be built first.

### Phase 01 — build the rest

- **Raid overhaul** — Phase 00 settled what it is; see there for the build order inside it, now CUT to
  four remaining steps for v1 (2, 3, 4, 7) with Gauntlet and Contract deferred post-launch.
  Absorbs the interim raid-map styling pass already written
  up in section B (node panels + Scraps Collected onto HudKit plates, map graph left alone); doing
  that inside the overhaul is cheaper than doing it twice.
- **Enemy AI patterns** — the ENGINE is finished and correct: one shared per-encounter tick loop,
  config-driven dispatch, wave scaling, spawn grace, robots answering with their own named
  behaviours. What is missing is content — `EnemyAI.Patterns` holds exactly one entry, `Chaser`, and
  every enemy including the elite points at it. Each new pattern is one function plus one config
  line. Note `EnemyAI`'s own header already anticipates raid combat: base defense aims
  `TargetPosition` at the plot anchor, and a raid mode that wants enemies chasing the PLAYER just
  passes a different point — that file does not change.
- **Raid shop rework** — already specced further down this file (run-only perks instead of ore
  bundles); half the tag plumbing exists.
- **Animations — SCOPED DOWN AND DEFERRED (2026-09-08).** Enemy attacks, robot fire, and the
  crafting "cute" step that has been open since the base phase. The user asked whether to hold the
  animation pass entirely and ship something free, upgrading it post-launch. Agreed, because
  animating now is guaranteed rework rather than risk: the clip set an enemy needs is a function of
  what it DOES, and that is undecided on purpose — the three AI patterns are step 7 of the raid
  overhaul (unbuilt) and the per-enemy states round is deliberately deferred to closer to release
  (see "DEFERRED DESIGN ROUND" above). Animate a `Chaser` today, make it an Artillery unit in step 7,
  throw the clips away. **The prerequisite is named, so this is a schedulable deferral, not a vague
  one:** the states round unblocks it, and Phase 02's feature freeze is what catches it if it slips.

  **The agreed release floor, per rig class:**

  - **Enemies (6 built + the raid boss = 7).** Model plus ONE attack animation. Only the four
    humanoid rigs (`Scavenger`/`Raider`/`Brute`/`VoidwakenHulk`) really need a clip; `ScrapCrawler`,
    `SentinelDrone` and the boss can tell with an effect (lunge, scale pop, colour flash, particle
    burst) instead. Locomotion comes free from Roblox's default R15 set. **Death needs no clip ever**
    — it is ragdoll, which the Tier 1 rendering section already plans and which gets CHEAPER under
    Tier 1 (physics paid only for the couple of seconds something is actually toppling).
  - **The attack tell is the one thing NOT shippable at zero.** Enemies deal contact damage on a
    cooldown, so with no tell the player takes damage from something that appears to be standing next
    to them. That is READABILITY, not polish — the difference between "that hurt" and "why did that
    hurt". It does not have to be an animation, but it has to be something.
  - **Deployed robots (4) need NO MODEL AT ALL** — corrected 2026-09-08, having first been written
    up here wrongly. They are deliberately ABSTRACT: no physical Model, no position, targeting and
    damage are nearest-to-player and instant. Stated independently in two headers
    (`CombatEncounterService.lua`'s SCOPE NOTE and `RobotBehaviors.lua`'s). Turrets are the physical
    deployable system; robots are stat contributors that never appear in the world. Anyone scoping
    art from this list must not queue four robot models.
  - **The drone companion is ONE model, not four.** `DroneService.lua:81` looks up
    `ServerStorage.DroneModels.Drone` — a single hardcoded name shared by all four Drone Cores.
    Note `DroneModels` is NOT declared in `default.project.json` the way `EnemyModels`/
    `RaidRoomModels`/`TurretModels` are, so it has to be created by hand in Studio; absent, the
    drone falls back to a tinted box plus a warn. Also note `buildBody` sets every descendant part
    `Anchored = true` (plus `CanCollide`/`CanQuery` false, the latter so the drone can never stop
    the player's own projectiles), so a rotor cannot be driven by a physics constraint — how its
    spin is driven needs deciding rather than assuming.
  - **Turrets (6).** Model plus a fire effect. Emplacements do not animate.

  **Cosmetic spin is not an animation, and must not be server-side.** A wheel or rotor is a part
  rotating forever: a `HingeConstraint` set to Motor, or (better here, and the recommendation) a
  plain CFrame spin in `EnvironmentFX.client.lua`, which is already the world-visuals client script.
  A server-side spin replicates a CFrame every frame for every robot, drone and turret on the map —
  precisely the cost the Tier 1 refactor exists to remove — and nothing about a spinning wheel is
  server-authoritative, so there is no reason to pay it. For rotors, a spinning part plus a
  semi-transparent blur disc reads better than actual spinning blades and is free.

  **Modelling constraint that follows, and it has to be known BEFORE the models are built:** moving
  parts must be SEPARATE parts welded on, never merged into the body — a wheel baked into the
  chassis cannot turn. Likewise the four humanoid enemies need real Motor6D joints if they are to
  carry an attack clip. **Rigs are safe against the Tier 1 refactor**: Tier 1 drops the server-side
  `Humanoid` and drives clips through an `AnimationController` instead, which is a change to the
  DRIVING CODE, not to the art — any rig with a normal Motor6D hierarchy plays either way.
- **Turret models** and **the mine's visual pass** — art; both also on the Asset Bench.
- **PvP base invasion — DECIDE. Recommendation: cut from v1.** It is the one remaining item that adds
  a whole new CLASS of exploit surface (player-vs-player state, griefing, offline raids) precisely
  when Phase 04 is trying to close that surface down, plus an entirely new balance axis to tune. This
  file has always sequenced it last. Shipping without it costs little; including it moves the release
  date a lot. It is a strong first post-launch update. The user is undecided — this is a
  recommendation, not a decision.

### Phase 02 — feature freeze

Nothing new after this line. Anything unbuilt goes on the post-launch list. Recorded as its own phase
because it is the step that gets skipped and is why projects at this stage do not ship.

### Phase 03 — cleanup

- **Memory leaks are a KNOWN pattern here, not a hypothetical.** Every animated thing built in the
  HUD phase needed an explicit `Disconnect` guard or it leaks one Heartbeat handler per render, for
  the rest of the session, with nothing in Output to say so — the Smelting dial, the Forge chamber
  ring and the case reel each carry that guard and a comment explaining it. A sweep for connections
  with no teardown is concrete and findable, and is the highest-value item in this phase.
- Dead and messy code: retired files still on disk, orphaned requires, comments describing code that
  has moved.
- Efficiency: re-render churn, per-frame work that could be event-driven, tables rebuilt per frame.
- **Debt: README's Smelting testing step (section 4, step 7)** still describes the pre-Batch-Dial UI —
  the ore-picker popup and the +1/+10/+100/MAX buttons, both deleted.
- **Debt: the Black Market's Cases tab** is the last station menu never given the phase-3 pass; still
  a plain `makeRow` list sitting next to the Crucible.

### Phase 04 — security

Full remote-surface audit (`sp-remote-scout` sweeps every RemoteEvent/RemoteFunction for argument
validation, plot/station gating, rate limiting, and rewards re-derived rather than trusted), then fix
what it finds, then a basic anti-cheat pass — movement and fire-rate sanity checks, impossible-value
rejection. Basic is the right scope: a Roblox game cannot win that fight, only make it boring.

**But the audit is the safety net, not the plan.** The actual defence is a standing habit that starts
NOW rather than at this phase: every new remote gets gated when it is written. An ungated remote costs
minutes to fix the day it is added and hours to find in a batch six features later.

### Phase 05 — sound and music

Sound effects (mining hits, gun fire, the Forge lever, the case reel landing — the reveal especially,
it is built for a sound it does not have yet) and music (base, raid, boss at minimum).

**Independent of everything above it, and movable.** Biggest perceived-quality jump per hour on the
whole plan and nothing blocks it — pull it forward whenever the project needs a morale win.

### Phase 06 — ship

Balance pass (every number in the Config modules is a first guess never played against), the full
README section 4 loop on a fresh profile the way a new player meets it, then a multi-player stress
test watching for whatever Phase 03 missed. Then release.

## Mining zone — BUILT

Shipped as `MineShaftConfig.lua`/`MineShaftService.lua`/`MineShaftController.client.lua`,
replacing `ResourceZoneService.lua`/`ResourceZoneConfig.lua`'s scattered-ring layout entirely
(those files are still on disk for reference but no longer required by `Main.server.lua`).

**Current design (4th and final rework — a real 3D voxel grid):** `MineShaftStart` is a Part you
place somewhere with genuine open air underneath — up on a platform, not resting on the map's
actual ground. Everything is built as ordinary, real, solid Parts directly below it — no
teleporting, no relocated "pocket" dimension, nothing fake. Only the top layer (Depth 0, a
`GridWidth` x `GridLength` grid, 32x32 by default) is generated up front — that's the quarry
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

**SUPERSEDED 2026-09-22 by the "chunky, Minecraft-ish" block pass** — see "Resuming after a
context reset" for the full record. Current live numbers: `GridWidth`/`GridLength` are **16x16**
(256 blocks for the first layer) and `CellSize` is **12 studs**, halved-cells-doubled-size from the
32x32-at-6-studs version directly above, so the actual footprint (192x192 studs) and dig-time
pacing are unchanged — just built out of fewer, bigger blocks. `MaxDepth` was also bumped from an
original 40 to **200** in the same pass, purely so the KindWeightBands/OreWeightBands/HazardTypes
depth zones (spaced 40+ levels apart) have room to breathe. Every number below this point in this
section describes the PRE-2026-09-22 grid and is kept for the rewrite history; check
`MineShaftConfig.lua` directly for anything you're about to rely on.

- **Three block kinds per cell**, weighted by depth (`MineShaftConfig.KindWeightBands`): mostly
  **Rock filler** (destroys for nothing — makes ore feel earned, not just sitting there), some
  **Ore** (an actual resource, rarer ore more common with depth — `OreWeightBands`, same shape as
  the old ring zone's distance bands), and a few, more often the deeper you go, **Lava pockets**
  (mine one through and it bursts for real damage instead of a reward, no warning in its label
  first). Rock is floored at 38% even in the deepest band (the four bands run 80/50/42/38% Rock)
  so filler never fully disappears even very deep, per the explicit ask. Depth 1-4's Ore rate was
  tuned down after testing — 40% Ore felt like too much too early — to 80% Rock / 20% Ore total,
  split 75/25 Iron Ore/Copper Ore (no Gold Ore that shallow), landing on roughly the requested
  "80% rock, 15% iron, 5% copper."
- Interaction is a `ClickDetector` (matching the Expedition nodes), not the hold-style
  `ProximityPrompt` ore mining uses — a prompt on a block directly under the player's own feet
  fails its line-of-sight check and silently never fires, which is what broke mining entirely on
  the first pass.
- Separately, ambient environmental hazards past a depth threshold — currently Heat (depth 25+)
  and Toxic Air (depth 38+), `MineShaftConfig.HazardTypes` — deal periodic damage. This is the
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
- **Raw ore keys renamed, and Gold/Platinum swapped gate slots.** `OreConfig.Ores` used to name raw
  material like a manufactured good — `ScrapIron`, `CopperWire`, `SteelPlating`, `GoldContacts`,
  `HardenedPlate` — even though every one of those is dug out of a wall, not built. Steel was the
  worst offender: raw `ScrapIron` smelted *into* `SteelIngot` at the Forge while `SteelPlating` was
  a completely separate thing you mined, so "Steel" meant two unrelated items depending on which
  system you were reading. Renamed to `IronOre`/`CopperOre`/`GoldOre`/`PlatinumOre`/`PlatinumBar`
  (`VoidiumShard` was already honestly named and is unchanged). Gold and Platinum deliberately
  **swapped** gate slots rather than mapping name-for-name, so the value ladder reads
  Iron -> Copper -> Gold -> Platinum -> Voidium: `GoldOre` now carries the mining stats
  (`MinToolTier = 2`, 5 hits, 35s respawn) that used to belong to the key `SteelPlating`, and
  `PlatinumOre` carries the stats (`MinToolTier = 3`, wave-5 gate, 3 hits, 60s respawn) that used to
  belong to `GoldContacts` — the stats stayed with the SLOT, not the metal. Only a saved profile's
  `OreCounts`/`RefinedOreCounts` migrate automatically, one-time and self-guarding, same shape as
  `migrateLegacyWeapons` (`DataService.migrateOreKeyRename`); a hand-placed `OreNode`'s `OreType`
  `StringValue` in Studio does not, and does not error on a stale value either — it just grants
  nothing (see "Known interim decisions" below).

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
- **Newbie Pity — BUILT (ore rework).** A first-time player's guaranteed Rare used to take the same
  15-roll drought as everyone else's — a long dry spell before you've even learned what the Forge is
  for. `ForgeConfig.Pity.NewbieThreshold = 5` plus a new `profile.NewbiePity` flag (defaults `true`
  in `defaultProfile()`) put a brand-new profile's pity floor at 5 rolls instead of 15 until pity
  actually resets for that player once; `ForgeService.ForgeWeapon` picks `NewbieThreshold` over
  `Threshold` with an `and`/`or` that falls back to the normal `Threshold` if `NewbiePity` is ever
  missing, and flips the flag to `false` for good the moment pity resets — so the shorter fuse only
  ever fires once per player. `backfillMissingFields` hands `NewbiePity = true` to every
  already-existing save too, deliberately: current players get one boosted run each rather than
  being excluded by an accident of when their save was created. `ForgePanel.lua`'s HEAT gauge mirrors
  the identical `and`/`or` check so the bar can never read a different threshold than the roll
  actually honours.
- **Ore smelting (separate Forge mechanic) — BUILT.** A second, independent thing the Forge does
  alongside weapon Forging: the Forge's new `"Smelting"` tab (`StationConfig.Types.Forge.Tabs` is
  now `{ "Weapons", "Smelting" }`) turns raw ore into refined material, one job at a time per
  player. Config lives in the new `RefinedOreConfig.lua`: `Ores[oreKey] = { RefinedKey,
  DisplayName, Description, RefineRatio }` (raw ore consumed per 1 refined unit — 3:1 for Iron
  Ore/Copper Ore, 2:1 for Gold Ore/Platinum Ore, 1:1 for Voidium Shard, all easy to
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

  ~~Deliberately still out of scope: rewiring `CraftingRecipes.lua`/`ModConfig.lua`'s `Cost` tables
  to actually require refined materials as crafting inputs. Right now refined materials accumulate
  and display but aren't spendable anywhere — that's its own follow-up task.~~ RESOLVED by later
  work — see "Half-built reward loops" below: several `TurretConfig`/`ResearchConfig`/
  `OreConfig.ToolTierCosts` entries now price in refined materials, and the ore rework's Hub Shop
  Sell tab (`SellService.lua`) gives them a sink even where nothing prices in them directly.

  **Numbers I picked myself, worth a playtest before treating as final:** the exact RefineRatios
  (3:1/3:1/2:1/2:1/1:1), the refined-material names (Steel Ingot/Copper Coil/Gold Bar/Platinum
  Bar/Voidium Core — renamed from Hardened Plate along with the raw-ore rename above, see the
  Mining zone section), and the time-formula constants (`BaseSeconds = 20`, `LogSecondsPerOre = 24` —
  a 3-Iron-Ore batch takes ~20 + 24*ln(3) ≈ 46s total, a 300-Iron-Ore batch takes
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
  fixed evenly-spaced ring positions (`TurretService.perimeterPosition`, reusing the same math round 1
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
no physical presence, raids still treat `DeployedRobots` as purely abstract. (3) ~~A raid drone-companion slot~~ — BUILT SINCE, and broader than this note describes: it
follows the player everywhere rather than only in raids. See "Drone companion" below.

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
- **Deliberately deferred**: no rotating/limited Shop stock (every `NodeConfig.ShopCatalog` item
  is always available); no fog-of-war on the map. (The drone-companion slot, also deferred here at
  the time, has since been built — see "Drone companion" below. It works in raids like everywhere
  else and needed nothing raid-specific.) All easy follow-ups once this first pass has been played.

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

### Raid Rooms — physical exit doors + the Sector Map (BUILT)

Step 1 of the raid overhaul's build order (see Phase 00). Mode-agnostic on purpose — all three raid
modes need it — and the biggest change in how a raid FEELS that the overhaul contains.

**The map stopped being the control.** A cleared room used to open a centred overlay you clicked a
circle on. Now the room's own doors unlock and you walk through one. `ChooseRaidNode` is unchanged
and still does the same `table.find(currentNode.Connections, nodeId)` legality check — only the input
moved, which is why this was cheap: a door is just another way to send an id the server already
validates.

- **`RaidConfig`** gained the whole door contract: `ExitDoorName` ("ExitDoor"), `ExitDoorIndexAttribute`
  ("ExitIndex"), `ExitDoorUseProximityPrompt` / `ExitDoorPromptDistance`, `ExitDoorSealedColor` /
  `ExitDoorUnlockedTransparency` / `ExitDoorLabelHeightOffset`, and `FallbackExitDoorCount` /
  `Size` / `Inset`.
- **`RaidRoomService`** gained `collectExitDoors` / `sealExitDoors` / `unlockExitDoors` plus
  `buildFallbackExitDoors`, and `showMapChoice` now unlocks doors instead of just firing an event.
  Doors are sealed on every room entry, BEFORE the type branch chain — sealing after it would
  immediately undo the Start node's own `showMapChoice`.
- **An unlocked door wears its DESTINATION's colour**, straight off `NodeTypes.Color`, with a
  floating label carrying that type's `DisplayName` and Tier. One colour language for the door, the
  map circle and the legend, and it cannot drift because all three read the same table.
- **Walk-through, not a prompt.** An unlocked door drops `CanCollide` and you pass through it —
  "to choose where to go is gonna be a physical thing." `ExitDoorUseProximityPrompt` flips the whole
  thing to a press-E affordance instead; both paths are implemented, so if playtesting says a
  walk-through triggers too easily (a door near an authored room's spawn point is the risk) that is a
  config flip rather than a code change.
- **Too few doors warns and re-opens the clickable map for that one node** — the missing-art rule
  applied to geometry. A room with one door in a two-way fork is playable, not a soft-lock. The
  payload carries `AllowNodeClick` so the client knows to make circles live again, and ONLY then.
- **The fallback square grows three doors of its own**, same idea as the `InteractPoint` stand-in it
  already grew, so physical exits work before a single Room Model exists. Three is one more than any
  map can currently use, which means the "extras stay sealed" path gets exercised every raid rather
  than only in authored rooms.

**The map became the Sector Map** (`RaidClient.client.lua`) — docked right, persistent for the whole
raid. It is the one part of that file that has had its reskin, because it is now on screen for the
entire run rather than for the few seconds a choice was open. (It was read-only when written; since
the 2026-09-09 reversal above it takes the click again, while keeping the docked persistent shape.)

- **On HudKit's angular plate**, with a `raid_map_backdrop` art slot in `UiIconConfig` — a full-bleed
  background image rather than a glyph, the only entry of its kind there. Scrimmed hard (0.72 plus a
  top-to-bottom gradient) because whatever art lands has to sit UNDER a node tree that must stay
  readable. At 0 it resolves to nothing and the procedural grid shows instead, so the panel is
  finished either way — wants something map-ish and roughly 3:4 portrait.
- **The tree draws top-to-bottom now**, stage on Y and lane on X. A docked panel is tall and narrow
  and a map can reach 14 stages deep. The dendrogram's no-crossing-lines guarantee is topological,
  not axis-dependent, so the swap keeps it intact.
- **Only the current node and its reachable children are labelled.** At 346x424 with up to 18 nodes,
  labelling everything is a wall of overlapping type. Type is carried by colour plus a legend; the
  map is for orienting, not for reciting the graph.
- **It draws your trail** — visited nodes solid, unvisited hollow, and edges you actually walked in
  warm gold. Reset per chapter, keyed off `StartNodeId` changing, since node ids are reused between
  generations and a previous chapter's visits say nothing about this one.
- **`ChoicePending` replaced `mapFrame.Visible`** as the gate on "Go Back To Base". The old test
  worked only because the map WAS the choice; with a permanent panel it would have left the bail-out
  button up for the whole raid and undone the rule it exists for ("so they cant just quit while doing
  a raid"). The server sets `ChoicePending` only while a choice is genuinely live.
- The banner's pulse is a single stored `Tween` with `RepeatCount = -1`, cancelled in a `hideSectorMap`
  teardown funnel — a looping tween on a hidden Frame runs forever otherwise, the same silent leak
  the Smelting dial and the case reel each carry a guard against. No Heartbeat connection anywhere in
  the panel, deliberately.

**Two bugs worth not relearning.** `HudKit.plate` returns **(surface, shell)**, surface FIRST — taking
them the other way round hides only the panel's inner face and leaves the outer frame drawn. And
`COLOR.MapLine` is gone: the map palette moved into a local `MAP` table, because every entry in it is
about drawing a chart rather than HUD chrome, and none of it is reused.

**Still to do on the map:** nothing blocks the next step, but the backdrop art does not exist yet and
is on the Asset Bench.


> **SUPERSEDED by the Black Market & Hacker Machine section above.** Kept for the reasoning, not as
> a separate thing to build — the geode/extractor mechanic below is the same shape as the case/decode
> flow. The Roblox randomized-rewards policy flag at the end of this section now applies to CASES.

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

## Combat infrastructure — BUILT (built to carry the Black Market content)

Three systems added while building the Ultimate mods. None were in the original plan; each turned
out to be load-bearing for content that is still to come, which is why they are recorded here
rather than buried in commit messages.

### Status effects — `StatusConfig.lua` / `StatusEffects.lua`

Bleed, Poison, Burn, Stun, Slow, Frostbite, ArmourShred. Built because the six Ultimate mods needed
three of them between them, and because **most of the unbuilt gun variants need the same ones** —
the IceThrower is Slow + Frostbite, the PoisonThrower is stacking Poison, the Trailblazer is Bleed,
Sticky grenades are Slow. Seven separate implementations of "damage over time" that could not
interact would have been the alternative.

Decisions worth not re-litigating:
- **Armour shred is multiplicative**, not a strip flag — so ".100mm removes 50%" and "Leg Breaker
  drops it to nothing" are one mechanism at two strengths, and two shredders compound.
- **Status damage runs the normal DamagePipeline.** A bleed that skipped mitigation would be
  strictly better than a bullet against armoured targets.
- **Re-applying at max stacks only extends the timer if the status says so** — which is what makes
  Poison "run off pretty quickly" if you stop applying it rather than being held forever by one hit.
- **Escalation is generic** (`EscalatesTo`/`EscalatesAtStacks`), so Frostbite becoming a Stun at 2
  stacks is config, and any future status can build into another the same way.

### Projectiles — `ProjectileService.lua` / `ProjectileConfig.lua`

Guns fired hitscan before this. Two consequences were reported as bugs: firing was gated on already
aiming at something with a Humanoid (so aiming at the floor produced no shot at all), and there was
nothing to see, so hits were pure inference.

Now the server spawns a real Part, steps it, and resolves on impact. The structural half is that
**fire and impact became separate moments** — everything a shot needs is captured at fire time, so
it resolves against the loadout that fired it even if the player swaps mid-flight.

**This is where the gun variants plug in.** A bow is slow + high gravity; a sniper is fast + flat +
high pierce; a grenade is slow + heavy gravity. Only patterns needing genuinely new behaviour —
cones, bouncing, impact explosions, attached/delayed detonation, tethers — are additions to
`ProjectileService`.

### Damage numbers + training dummies

Colour-coded floating numbers (`DamageNumbers.client.lua`) and dummies that are real enemy records
with a damage readout on their head (`TrainingDummyService.lua`). Built in response to "the mods
seemed to half work, I couldn't tell half of the time" — which was mostly true in the sense that a
Ricochet bounce off a starter pistol is a few points of damage and looks like nothing.

Worth keeping in mind when adding content: **if a new passive or gun cannot be seen working, that
is a tooling problem, not necessarily a broken feature.**

## Data safety — session locking (BUILT)

`DataService` used to load with `GetAsync` and save with `SetAsync` — two non-atomic operations with
no notion of ownership, so two servers could hold the same profile. Leaving one server and joining
another before the first saved silently rewound progress, with nothing logged.

Now everything goes through `UpdateAsync` (atomic per key) with a lock: claimed on load, heartbeat
refreshed on every save, released on leave and on `BindToClose`, stealable after 180s of silence so
a crashed server cannot lock someone out permanently. Saves re-check ownership before writing, so a
server whose lock was stolen discards its stale copy rather than clobbering a live session.

Two deliberate behaviour changes: a player whose lock cannot be acquired is **kicked** rather than
let in with an unsaveable profile, and `DataService.Save` now returns whether the write landed —
`ShopService` only reports `PurchaseGranted` when it did, so a player cannot pay and receive nothing.

ProfileService remains the more battle-tested option if this ever needs to do more.

### Player Test Mode — BUILT

An admin-only HUD button (`GetTestMode`/`ToggleTestMode`, gated by the same `AdminConfig.IsAdmin`
check as the `/admin` commands) that lets an admin preview the game as a brand-new player — Tier 1,
nothing owned — without disturbing their own save. Built once the session-locking work above made
"which profile is this server holding, and is it safe to throw away" something worth being precise
about.

**The flag lives in its own DataStore key (`"TestMode_" .. userId`), never inside the profile.** This
is the one decision worth recording, because it looks backwards at first: why not just add a
`TestMode` field to the profile like everything else? Because the whole point of the feature is that
a test session's profile is disposable — `PlayerAdded` hands it a `defaultProfile()` straight into
the cache and never loads or locks the real save, and `saveProfile` refuses to flush it to
DataStoreService no matter which of the four write paths (`DataService.Save`, autosave,
`PlayerRemoving`, `BindToClose`) asks. A flag stored inside that throwaway profile would be
discarded along with it every single session, and there would be no surviving place to ever record
"turn this back off" — the player would be stuck previewing a fresh profile forever. Putting the flag
in a key that outlives the throwaway profile is the only way the toggle can be bidirectional.

A few other decisions that follow from that same shape, in case a future session is tempted to
"simplify" this: it takes effect on the **next join only** (toggling mid-session would mean swapping
the profile a live session is reading/writing out from under itself — corruption, not preview,
which is why `ToggleTestMode` never touches `cache[userId]`), a test session never takes the real
profile's session lock (so another server stays completely free to load/save the player's actual
data the entire time), and `DataService.IsTestModeEnabled` **fails closed** on a DataStore read error
— resolves to "load the real profile," never to "hand them a blank one," since the latter is
indistinguishable from data loss from the player's own seat.

## Black Market & Hacker Machine — BUILT (content pending)

**Status:** the delivery system is done end to end — dealer with rotating stock, sealed cases,
timed decoding on the Hacker Machine, both rush paths, and Contraband as a real earned currency.
Ultimate mods drop from it for real.

**What is NOT built yet:** gun variants and special tools. Their pools exist in `CaseConfig` with
TODOs, and no shipped case rolls them — a case that promised a gun it could not deliver would be
worse than one that pays out materials. Adding them is: pool entries, a branch in
`BlackMarketService.GrantReward`, and the specialised gun-line/mod-line crates.

The original design follows.

## Black Market & Hacker Machine — design

A rotating-stock dealer selling **sealed cases**, decoded on a separate **Hacker Machine**. This is
the mid-to-endgame content faucet: it is where gun variants, special tools, and the Ultimate mods
come from. Deliberately not a general shop — it sells sealed randomness, not catalogue items.

**DECIDED: this SUPERSEDES the older "Main shop" idea below.** The geode → extractor → wait →
reward flow sketched there is the same flow as case → Hacker Machine → wait → reward, so building
both would be two systems doing one job. The Main shop section is kept below for its reasoning
(especially the note about Roblox's policy on randomized rewards, which now applies HERE), but it is
not a separate thing to build. If flat-catalogue items like armor or cosmetics are still wanted
later, they belong as tabs on an existing station rather than a third shop.

### Currencies — the deliberate split

- **Scrap / Cores** buy the **common stock and rerolls**. Stated reason: *"so the main currency
  never goes dead"* — Scrap has to keep mattering after the player has finished building.
- **Contraband** is a separate token that buys the **premium-odds stock**. Earned from raids and
  base defense, OR bought outright with Robux as a grind skip. This is the monetisation hook: the
  paid path buys time, not exclusive content.

### Cases

Sealed. Bought from the dealer, decoded at the Hacker Machine — decoding **takes real time**
(same shape as `SmeltService`'s job: one at a time, timestamp-based, finishes whether or not you
were online).

**Rushing a decode — DECIDED, two paths with different risk:**
- **Robux** → finishes instantly, **no risk**. The paid path buys time, never outcomes.
- **Cores** → finishes instantly but **carries a real risk of corrupting the case** (lose it, get
  nothing). The in-game shortcut is a gamble; the paid one is not.

That asymmetry is the point: someone who pays gets certainty, someone who grinds gets a choice
between waiting and gambling. It also gives Cores a second sink beyond turret upgrades.

**Rarity → what drops.** The tiers mean different KINDS of thing, not just better numbers:

| Rarity | Contents |
|---|---|
| Common | ordinary game loot — Scrap, ores |
| Rare | Cores |
| Epic | special tools |
| Legendary | gun variants |
| Mythical | Ultimate mods (the OP passives) |

**Case types differ by odds AND by pool.** Better cases have better Legendary/Mythical chances. On
top of that, cases are **specialised by what their top tiers can contain** — the decision made
explicitly: rather than one crate whose Legendary/Mythical pool mixes guns and mods, there are
separate crate lines where one only rolls **gun variants** at the top and another only rolls
**modifiers**. Reasoning, in the user's words: *"it gives the player more choices, more reason to
come back, the crates have more value."* Finer targeting on top of that is also wanted — e.g. a
crate weighted toward flamethrowers specifically when the Legendary roll lands.

A **Robux "super lucky" crate** exists with a **daily limit**.

### Ultimate mods — a fourth, exclusive slot

Weapons currently have `ModConfig.SlotsPerItem` (3) interchangeable mod slots. Ultimate mods do NOT
go in those. They get **their own dedicated slot**, and the exclusion runs **both ways**: only a
Mythical Ultimate mod fits the Ultimate slot, and an Ultimate mod cannot occupy a regular slot.

Design intent: these are **passives with no drawback — or a drawback whose upside is genuinely
worth it**. They are supposed to feel game-changing, not incremental. Examples given:

- an enemy's corpse **explodes on death**, dealing AOE to nearby enemies
- bullets that **ricochet**
- a bullet that **pierces 5 enemies and strips their Defense entirely for 10 seconds**

Note these are real combat behaviours, not stat multipliers — they need actual hook points in the
damage/encounter path, unlike existing mods which are pure `FireRate`/`Damage`/`HP` multipliers.

### Gun variants

Blueprints unlock whole **variant families**, and *"the blueprint will unlock a new gun tab for that
specific variant"* — so the Forge's Weapons tab gains a tab per unlocked family. Families named:
**flamethrowers, special bows, snipers, bazookas / ray cannons**.

Within a family sit specialised guns with their own twist — *"a bow that shoots shock arrows, or a
flamethrower that actually throws a freezing flame"*.

**DECIDED: a blueprint unlocks the whole FAMILY.** One Flamethrower blueprint opens the
Flamethrower tab and makes every flamethrower in it craftable with materials. Same shape as turret
blueprints already use (`profile.UnlockedTurretBlueprints`): the case grants ACCESS, materials
remain the gate. Cases stay valuable without becoming the only way to get a gun, and a player who
wants one specific weapon is never held hostage to a re-roll.

### Tools

Epic-tier case content. Examples: a **special drone**, a **pickaxe that mines 3 blocks at once**.
No existing system covers tools as items — `ToolTier` today is a single sequential upgrade track, so
this needs a real inventory-style tool concept.

### BUILD CONSTRAINT — content is placeholder, structure is not

Direct instruction: ship **placeholders** for the crazy modifiers, guns and tools *"but make it
modular, so when I introduce you with the table of contents for those stuff, where everything will
be detailed, with damage, description, behavior, perks and all that, we can just plug those in and
be ready to go."*

So the work is to get the DATA SHAPES and the HOOK POINTS right, with a couple of real working
examples proving the plumbing, and everything else arriving later as pure config entries. Concretely
that means:

- Ultimate mod effects should be **named strategies in a flat table** — the same pattern
  `EnemyAI.Patterns` and `RobotBehaviors` already use. A new passive becomes one function plus a
  config entry pointing at its name, never an engine change.
- The damage/encounter path needs **hook points** (on-kill, on-hit, on-fire) for those strategies to
  attach to. This is the part that cannot be deferred, because retrofitting hooks later means
  touching combat again.
- Case drop tables, case types, odds, gun families and tool definitions should all be **pure config**
  in the `Shared/` convention, so the content table drops in without service changes.

## Gun variants + tools — BUILT

The spec below is the user's own, verbatim. Kept after the build rather than deleted, because the
code records how each weapon works and only this records what it was meant to FEEL like — which is
what you need when retuning one.

**What it cost, in the end:** three shared systems and four one-off behaviours. Roughly half the
list was config.

| Delivered by | Weapons |
|---|---|
| Config alone (`ProjectileConfig` profile + recipe) | Scrap Bow, Longbow, Longshot Rifle, Scout Rifle, Rotary Cannon |
| One cone emitter (`Pellets`/`SpreadDegrees`) | all 3 flamethrowers |
| Bounce + fuse + `Explosion` payload | both grenade launchers |
| `WeaponBehaviors` strategy, one function each | ExplosiveBow, StringedBow, Trailblazer, Hellfire |
| `ToolModConfig` | all 3 pickaxes |

Two things worth carrying into the next content pass, both of which held up:

- **Prefer config to code.** A behaviour is a function somebody has to maintain; a profile entry is
  a row in a table. Four of eighteen weapons needed code.
- **Statuses already existed, so three guns cost almost nothing.** The IceThrower contains no
  ice-specific code anywhere — Frostbite already slowed, already stacked, already escalated to a
  Stun at 2. That was the payoff for building `StatusConfig` before the content that wanted it.

Guns are delivered by the Black Market: a **blueprint unlocks the whole family**, and the family
gets its own Forge tab. So rolling one Bow blueprint opens Bows as a category, and the individual
bows are then Forged normally. Legendary case tier = gun variants, Epic = tools.

### Flamethrowers

| Variant | Spec |
|---|---|
| Regular Flamethrower | Strong DoT damage, short range. |
| IceThrower | A mist of ice. DoT is weaker than the regular one, but it slows enemies and applies **Frostbite** every 2 seconds while they're being hit. At **2 stacks of Frostbite the enemy is stunned for 2 seconds**. |
| PoisonThrower | Same DoT as the regular one, but **stackable to 5x**; at full stacks it out-damages the regular flamethrower. The catch: the status runs off quickly, and it takes a **full 5 seconds to apply one stack**. Also leaves **poison puddles on the floor** that tick damage on anything walking through — damage dealt to enemies the player isn't even shooting. |

### Bows

| Variant | Spec |
|---|---|
| Regular Bow | Slow-ish fire rate, okay pierce, good damage on a headshot. |
| Longbow | Bigger arrow — more damage and excellent pierce, slower fire rate. |
| ExplosiveBow | Arrows deal base damage on hit, then **explode after a delay**. Explosion damage **scales with how many arrows are in that enemy** when it goes off, and **one arrow detonating detonates every other arrow in that enemy simultaneously**. These explosions do **not** damage nearby enemies — it's single-target burst, not AoE. |
| StringedBow | The **3rd and 4th shots are stringed arrows**. If they land on **different** enemies, those two are **pulled together into the same place** and deal bonus damage to each other. |

### Snipers

| Variant | Spec |
|---|---|
| Regular Sniper | Very slow fire rate, huge damage (**headshot or not — no headshot bonus needed**), good pierce, **slows the player while wielded**. |
| QuickSniper | Faster fire rate, less damage, good pierce. Fast, but explicitly **not automatic-gun fast**. |
| Trailblazer | Close to the regular sniper but less damage and more pierce. Each shot **leaves a line from the muzzle to the impact point** (max 100 magnitude) that deals **bleed damage to enemies that touch it**. |
| Hellfire | **Every 5th shot fires upward**, launching a cartridge that bursts in the air and rains **mini missiles at random floor positions**, each doing AoE damage. |

### Grenade Launchers

| Variant | Spec |
|---|---|
| Regular Grenade Launcher | Okay damage, normal fire rate, **no pierce — grenades bounce off enemies**. Very large AoE damage. |
| Sticky Grenade | Less damage, slightly more range. On explosion enemies become **sticky**: they stick to each other and are slowed. |

### Minigun

| Variant | Spec |
|---|---|
| Regular Minigun | *"I don't have that many ideas for the minigun at the moment"* — deliberately left open. Build it as a plain high-fire-rate, low-per-shot gun and revisit. |

### Tools (3 pickaxes, passive modifiers — "nothing too crazy for now")

- Pickaxe that **mines 3 blocks at once**.
- Pickaxe that **increases mining speed by a lot**.
- Pickaxe that **increases ore yield**.

### Decisions made during the build, worth not re-litigating

- **A family blueprint unlocks the whole family**, and the Forge's Weapons tab became a picker.
  A flat list was fine at four weapons and unreadable at eighteen. Locked families still show,
  naming the blueprint that opens them — a player who cannot see what they are missing has no reason
  to chase a case.
- **Pellet count buys consistency, never damage.** A cone weapon divides its shot damage across its
  pellets. Otherwise `Pellets` is a damage multiplier hiding in a hit-probability field.
- **Headshots became a real mechanic** rather than an AimBot-only flourish. Weapons opt in with
  `HeadshotMultiplier`; snipers set 1 deliberately, per the spec's "no matter if headshot".
- **Grenades deal nothing on contact.** Without that they chip on the way past and then explode —
  two weapons' worth of damage from one shot.
- **Explosion damage falls off to a floor.** A flat blast makes radius the only stat that matters
  and positioning irrelevant.
- **Blast damage got its own colour.** A grenade in a crowd is otherwise a wall of white numbers,
  and "how many did that catch" is the only interesting thing about a launcher.
- **`WeaponBehaviors` is separate from `UltimateEffects`.** They look alike and mean different
  things: an Ultimate is a mod you move between guns, a behaviour is what a gun IS. Merged, you get
  one config table where half the entries are equippable and half are not. They compose — an
  ExplosiveBow can carry Ricochet.
- **Shot counters are per weapon KEY and persist across encounters.** A gun whose gimmick is "every
  5th shot" must not reset its rhythm because a wave ended.
- **Tool mods never touch ToolTier.** Raising tier would also unlock ore it was never meant to gate
  (`MinToolTier`). They scale what a tier produces and nothing else.
- **One pickaxe equipped at a time.** Otherwise Prospector is strictly mandatory — yield multiplies
  with everything and there is no reason to take it off.

### Still open

- **The Minigun is deliberately plain**, per the spec's own "I don't have that many ideas for the
  minigun at the moment". It is an honest placeholder stat line — highest sustained DPS in the game,
  lowest burst. Do not invent a gimmick for it without asking.
- **`ServerStorage.WeaponTools` has no models for any of the 14.** Every one falls back to the grey
  placeholder box, which is expected, not a bug.
- **No weapon is balanced against another yet.** The numbers are first-pass and internally
  consistent within each family; they have not been played against each other.

## Drone companion — BUILT

One drone, unlocked once, that follows you EVERYWHERE — raids, base defense, the mine, the
overworld. What it does is decided by which of four **Drone Cores** is slotted, one at a time. The
drone is a chassis; the Cores are its personality.

### Decisions

- **Not raid-only**, despite the original deferred note saying "a raid drone-companion slot". Two of
  the four archetypes (Scavenger, Recon) have almost nothing to do inside a raid, and a companion
  that vanishes the moment you leave one is barely a companion.
- **It has a real body.** Deployed robots in this game are deliberately abstract — no model, no
  position — and that is right for a defense loadout you set and forget. It would be wrong here: the
  entire appeal of a companion is that it is THERE. Anchored and server-CFramed, because an
  unanchored part would be client-simulated and could be shoved through a wall.
- **Unlocked by Research Tier 3**, not bought. Reaching "Fortified Bunker" IS the unlock, so the
  drone arrives at the same milestone your base starts looking like a base.
- **The Cores split by source on purpose.** Combat and Support are CRAFTED at the Welding Station —
  predictable, you pick the one you want. Scavenger and Recon are Black Market **Epic** rolls — you
  chase them. So unlocking the drone is a beginning rather than a finished system: two Cores arrive
  immediately so it is useful at once, and two are a reason to keep opening cases long after every
  pickaxe is owned.
- **One Core at a time**, same shape as Ultimates and pickaxes. It is what makes "run Scavenger while
  mining, swap to Combat before a wave" a real decision instead of a menu.

### The four Cores

| Core | Source | What it does |
|---|---|---|
| **Combat** | Craft | Shoots the nearest enemy every 1.2s for flat damage. |
| **Support** | Craft | Heals 4% of your max health every 2s, but only after 4 seconds without being hit. |
| **Scavenger** | Epic case | 25% chance to double any ore you mine. No combat use whatsoever. |
| **Recon** | Epic case | Marks nearby enemies — visible through walls, and taking 25% more from everyone. |

Three of those exist because of a rule this project keeps re-learning: **an effect nobody can see
gets reported as broken.**

- Combat damage is **flat**, not a fraction of your weapon. A companion that scales off your gun is
  a damage multiplier in disguise — mandatory on a strong weapon, pointless on a weak one.
- Support is **suppressed while you are being shot at**. Without that it quietly out-heals chip
  damage and makes waves unlosable. It also fires a green heal NUMBER, because a slowly rising
  health bar is the least legible thing in the game.
- Scavenger is a **chance to double**, not a flat yield multiplier. A multiplier would be invisible;
  an occasional "the drone found something" is a moment you notice.
- Recon marks are a **debuff on the target**, not a personal bonus — so a marked enemy takes more
  from your turrets and robots too. A personal damage bonus would just make it a worse Combat Core.

### Structure

`DroneConfig` (Cores, unlock tier, flight), `DroneBehaviors` (the fourth flat-strategy-table in this
codebase, after EnemyAI.Patterns, RobotBehaviors, UltimateEffects and WeaponBehaviors), and
`DroneService` (body, flight, ticking). Adding a Core is one function plus a config entry.

`DroneService` does **not** require `CombatEncounterService` — that file requires half the game and
must not be required back. Same injection pattern as `GroundEffectService`: the combat engine hands
over its enemy query and damage handler at load.

### Scaling with Research Tier

Cores grow as your tier climbs past the one that unlocked the drone, declared per Core in `Scales`
(a map of param key to fraction-per-tier) and applied in one place, `DroneConfig.ScaledParams`.
Behaviours read plain numbers and never learn that scaling exists.

| Core | Scales | T3 | T4 | T5 | T6 |
|---|---|---|---|---|---|
| Combat | damage | 14 | 18.2 | 22.4 | 26.6 |
| Support | heal per tick | 4% | 5% | 6% | 7% |
| Scavenger | proc chance | 25% | 30% | 35% | 40% |
| Recon | mark duration | 4s | 5s | 6s | 7s |

What does NOT scale is the deliberate part:

- **Combat's range.** A drone out-ranging what you can see starts shooting things you have not
  noticed, which reads as the wave spawning wrong rather than as a stronger companion.
- **Support's suppression window.** Shortening it with tier erodes the one property keeping the Core
  from out-healing a live fight — that has to hold at every tier, unlike the number it heals for.
- **Scavenger's bonus size**, only its chance — so a late Scavenger fires noticeably more often
  rather than very occasionally paying out something absurd. Clamped at 95% so it stays a gamble.
- **Recon's debuff strength.** Scaling that would quietly buff every damage source in the game.

Additive per tier, not compounding: three steps of +25% is +75%, not +95%. A companion compounding
alongside everything else that already scales with tier (wall HP, turret levels, slot count) climbs
much faster than it reads on the page.

The Drones tab shows each owned Core's numbers **at your current tier** rather than its flavour
text, for the reason this project keeps relearning: a Core that quietly got 60% stronger with no
number attached is the same invisible-buff problem that made the Ultimate mods feel broken before
damage numbers existed.

### Still open

- **No drone art.** `ServerStorage.DroneModels.Drone` is honoured if you build one; until then it is
  a tinted neon ball that changes colour per Core. The colour is currently the fastest read on which
  Core is active.

## Early-game pacing & onboarding — PLANNED, NOT BUILT

Agreed after the roadmap was finished, while the user moved to art. Nothing here is implemented.
Recorded now because the analysis behind it is the part that would otherwise be lost.

### The problem

The concern raised was "6 tiers feels too few, players will think the game is unfinished." Tracing
the actual numbers said the opposite: rung count is not the risk, **the first five minutes are.**

Progression already runs on roughly seventeen parallel axes — Research (6), Tool tiers (4), Suit
tiers (3), Forge tiers (4), turret levels (to 60 across 2-9 slots), 6 weapon families, 18 weapons,
per-instance rarity and affixes, 6 Ultimates, mods, 4 robots, 3 pickaxes, 4 drone cores, highest
wave, mine depth, Contraband and cases. Nobody experiences that as "3 of 6 done"; they experience it
as "I want the Longbow." The ladder length is not what makes a game read as unfinished.

What IS a problem is the opening. A brand-new player currently:

1. spawns with **0 Scrap, 0 ore, and no weapon**
2. must mine ~9 hits of Iron Ore to afford a Pipe Pistol
3. forges and equips it
4. can only THEN raid — and **raiding is the only source of Scrap in the game**, since base defense
   was deliberately changed to grant none (see RewardTables.lua)
5. needs **400 Scrap** for Research Tier 2, roughly 10-30 Combat nodes, plus clearing wave 5

So the first sixty seconds hand the player nothing, and the whole combat system — the strongest part
of the game — sits behind a mining errand.

### The plan

~~**1. Ore sells for Scrap.**~~ BUILT, by the ore rework — `SellService.lua`/the `SellOre`
RemoteFunction, a new **Sell** tab on the Hub Shop (`StationConfig.Types.Shop.Tabs`), a new
`SellPrice` field on `OreConfig.Ores`/`RefinedOreConfig.Ores`. Makes mining pay the currency
everything is priced in, without reversing the "waves grant no Scrap" decision (still true for a
regular wave clear; see the Wave defense rework note above the "Half-built reward loops" section).
Also turns ore into a real choice (sell it, or keep it to craft/smelt with) rather than a one-way
input, and gives refined materials a sink even where nothing prices in them directly.

The **pricing constraint** below held: `SellPrice` on every ore is below its `NodeConfig
.ShopCatalog` buy-back rate (Iron Ore sells at 1, buys in a 25-for-40 bundle = 1.6/unit; Copper Ore
sells at 2, buys at 3.0/unit; Gold Ore sells at 5, buys at 6.0/unit) — not exactly "half the buy
rate" per unit for Copper/Gold, but sell always undercuts buy, so there's no infinite-Scrap loop.
**Where selling happens** was answered too: the Hub Shop's new Sell tab, the cheaper option this
note already flagged, not a dedicated "Scrapper" station.

> Original framing, kept for the reasoning: Shop nodes already SELL ore for Scrap
> (`NodeConfig.ShopCatalog`): 25 Iron Ore for 40, 20 Copper Ore for 60, 15 Gold Ore for 90 (renamed
> from Scrap Iron/Copper Wire/Steel Plating along with the rest of `OreConfig` — see the Mining zone
> section). If the sell price exceeds the buy price there is an infinite-Scrap loop that never
> touches mining. Ceilings are 1.6 / 3.0 / 6.0 Scrap per unit respectively; half the buy rate was the
> proposed convention. At 0.8 per Iron Ore a full node (3 ore/hit x 8 hits) is ~19 Scrap.

**2. Starter objectives, NOT a scripted tutorial.** The stated goal was a first-minute tutorial
covering mine / Forge / Welding / Workbench. A guided step-by-step needs step tracking, forced
prompts and skip handling, and Roblox players skip tutorials aggressively. A short objectives list
teaches the same things, cannot be skipped past, and doubles as the early-economy injection the game
needs anyway. Sketch:

| Objective | Reward |
|---|---|
| Mine 20 Iron Ore | +100 Scrap |
| Sell ore | +50 Scrap |
| Forge a weapon | +75 Scrap |
| Craft anything at the Welding Station | +100 Scrap |
| Clear wave 1 | +150 Scrap |

~475 Scrap for doing the five things worth learning, which lands the player at Tier 2 on the
intended 5-10 minute mark with no "click here" arrows. It teaches through the existing station gates
instead of building a parallel tutorial system.

**3. Pull Tier 2 forward** — roughly wave 3 and ~200 Scrap, so the first upgrade lands inside the
first session. Tiers 3-6 stay where they are: late-game slowness is fine, early-game slowness is not.

**4. Tiers 7-8 — DEFERRED, deliberately.** The request was more rungs for balancing headroom. The
counter is art debt, not design: every tier needs a `BaseTier{n}` Studio model and **five are already
unbuilt** (T2-T6). Going to 8 makes it seven. The same pacing control comes from moving the wave
gates and costs of the six that exist, and `ResearchConfig`'s header already notes that adding a tier
is one table entry plus a model, no code changes — so T7/T8 remain a twenty-minute job at any point,
including after the curve has actually been played. **Build 6, play it, then decide where a rung
would help.**

Also still open from the same conversation, flagged rather than proposed because it reverses a direct
past instruction: **base defense pays no Scrap or Cores at all**, which makes it economically a dead
end despite being the mode most likely to be a new player's first real activity.
`WaveConfig.GetScrapReward` is still defined and unused if this is ever revisited.

## Raid shop rework — PLANNED, NOT BUILT (SUPERSEDED — see "Resuming after a context reset"'s
## "Raid shop rework — SPEC SETTLED 2026-09-22" / "BUILD CONTRACT" for what actually got built)

Requested in an earlier session, never built there either. Recorded properly this time. Kept below as
the record of the ORIGINAL idea (a third `RunOnly`/`Consumed` tag, `StatusConfig`/`ModConfig`-shaped
accessories) — the settled spec took a different shape (perks/gear live on run state, not as tagged
inventory items, so no third tag was needed after all) and is what was actually built.

**The idea:** the raid Shop node should stop selling ore bundles and instead sell **accessories that
grant perks for the duration of the run** — things that help you push deeper on THIS raid and then
break when you leave, so they cannot be farmed and carried out. Occasionally, at a legendary-ish
rarity, it should offer something that DOES carry over — a special blueprint or similar.

**Half of this is already built and inert.** `NodeConfig`'s loot and shop entries support two tags,
both fully implemented in `RaidRoomService.settleRunLoot`, and **nothing is tagged with either yet**:

- `RunLocked` — lost if the run ends in Defeat or Abandon; kept on a clean Extract.
- `Permanent` — carried out regardless, even from a failed run. Overrides `RunLocked`.

`Permanent` maps exactly onto the wanted "legendary thing that carries over". But the perk
accessories need a **third state that does not exist yet**: expire on ANY exit, including a clean
extract. `RunLocked` is not that — extract cleanly and you keep it.

So the work is roughly:
1. A third tag (`RunOnly` / `Consumed`) meaning "never leaves the raid", handled alongside the other
   two in `settleRunLoot`.
2. A perk-accessory config — what they do and how they attach. The obvious reuse is `StatusConfig`
   for anything expressible as a buff, and `ModConfig`-shaped multipliers for the rest.
3. Rotating stock per raid, so the Shop node is a decision rather than a fixed menu. Note that Raid
   Rooms currently have NO stock rotation at all — every `ShopCatalog` item is always available,
   which is already flagged as deferred in the Raid Rooms section above.
4. Tag the rare carry-over item `Permanent` and it works with no further changes.

A placeholder set was explicitly acceptable for the first pass.

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
  an instant win, no gear/cooldown checks, and Energy is effectively infinite
  (`RaidEnergyService.HasInfiniteEnergy` — every spend path returns true without deducting, and
  the regen loop keeps the number pinned at `MaxEnergy` so the HUD doesn't read as stuck). Purely
  a testing aid, not a player feature. Infinite Energy is the one shortcut that Player Test Mode
  turns back OFF: a test session exists to see the game as a new player does, and an unreachable
  Energy ceiling would hide exactly the pacing problem it's there to surface.
- Expedition start/end is currently lever-pull-to-start, "Return to Base" button-to-end. This is
  a deliberate placeholder for a real teleport-to-a-separate-instance flow, not the final design.
- `ResourceZoneService.lua`/`ResourceZoneConfig.lua` (the old scattered-ring ore layout) are
  retired — replaced by `MineShaftService.lua`'s dig-down shafts, see the Mining zone section
  above. The files are left on disk for reference/rollback but are no longer required by
  `Main.server.lua`; don't re-enable or tune them.
- The raw-ore rename (`ScrapIron`->`IronOre`, `CopperWire`->`CopperOre`, `SteelPlating`->`GoldOre`,
  `GoldContacts`->`PlatinumOre`, `HardenedPlate`->`PlatinumBar`) only migrates saved profile data —
  every hand-placed `OreNode`'s `OreType` `StringValue` in Studio still needs re-tagging by hand, and
  Gold/Platinum swapped gate slots, so an old `SteelPlating` node becomes `GoldOre`, not the more
  obvious `PlatinumOre`. A stale `OreType` doesn't error; the node just grants nothing forever. If a
  node in an existing test place "stops working" after this change, re-tagging it is the fix, not a
  bug in `MiningService`.
- `profile.NewbiePity` is deliberately one-shot per player, including the one-time `true` every
  already-existing save was backfilled with — it is not supposed to come back once it flips to
  `false`. A fresh **Player Test Mode** profile does get it again, because that profile runs
  `defaultProfile()` from scratch each time; that's a side effect of Test Mode being a throwaway
  profile, not evidence the flag is resetting somewhere it shouldn't.
- **Dash i-frames (`DashConfig.IFrameSeconds`) only protect the raid combat damage path** —
  `CombatEncounterService.safeIsInvulnerable` is the only caller of `DashService.IsInvulnerable`.
  Mine shaft Lava damage (`MineShaftService`'s `Touched`/burst damage) and outpost `NodeService`
  chip damage go through their own, separate damage code and do not check it. Dashing through a
  Lava tick or an outpost hit today still hurts. This is a known gap, not a bug — extend it to
  those paths deliberately if/when they need it, don't assume `DashService.IsInvulnerable` is
  already wired everywhere damage can happen.

## Research level — BUILT

The progression rank, and the one number the player tracks. See `ResearchConfig.lua`.

**Two ladders became one.** `profile.BaseTier` (bought; picked the base Model and WallHP) and
`profile.ResearchTier` (hardcoded to 1; gated turret slots and turret tiers) both meant "how
developed is my base", were both gated on boss-wave drops, and would have forced the player to
track two numbers. `ResearchTier` is the survivor. `BaseTier` is legacy and migrates forward on
load (`DataService.migrateBaseTierToResearch`, takes the max so it can never move anyone
backwards, and is idempotent).

One tier now drives: which `BaseTemplates` Model is cloned, the plot's claimed footprint, WallHP in
defense, turret slot count, and how far a turret can be levelled.

**How it's earned:** reaching `RequiredWave` unlocks the tier; claiming it then costs Scrap + ore
plus one boss-wave `CoreItem`. The milestone gates it, the resources pay for it — wave defense sets
the pace while mining and raiding fund it. Gates land on multiples of `WaveConfig.EliteWaveInterval`
on purpose: the boss wave that unlocks a tier is the same wave that can drop the Core to pay for it.
Claimed at the Workbench via the `UpgradeResearch` remote (which replaced `UpgradeBase`).

`ResearchConfig.GetNextTierRequirements` is the SINGLE source of truth for what the next tier
needs — the HUD renders the requirements list from it and `BaseService` decides the claim with it,
so shown and enforced can never disagree.

**Stations live INSIDE the base Model** — no separate per-tier station folder. A `BaseTier{n}` Model
is expected to contain its own tier's Crafting/Welding/Forge stations as tagged descendants, and
`BaseService.tagStationOwnership` already walks descendants and stamps `OwnerUserId`, so this needed
no new code. Upgrading swaps shell and stations together, so a Tier 3 base can never end up wearing
Tier 1 stations. (The alternative — a parallel `Stations T1/T2/...` folder tree — was considered and
dropped: it only earns its complexity if stations need to vary independently of the shell.)

**The base grows with tier.** `FootprintHalfSize` is per-tier, and the turret slots derive from it —
they walk the square platform's perimeter (`TurretService.perimeterPosition`), inset by half a pad
plus `BaseConfig.TurretEdgeClearance`, so a tier that unlocks more slots also widens the square to
fit them, with nothing extra to tune. `PlotService.IsPlayerInOwnPlot` reads the same per-tier
footprint.

**Retuned since first ship: the ladder used to run 80 studs across at T1 up to 200 at T6 (Y climbing
30→50 alongside it).** That spread made plot spacing a real Studio burden — a builder had to leave
200-stud gaps between every `Plot` anchor just in case someone maxed out. The current ladder is flat
3-studs-of-width growth per tier with Y held constant at 30 for every tier: 48 studs across at T1 up
to 63 at T6 (24→31.5 half-extent). `BaseService.FALLBACK_FLOOR_SIZE` (the placeholder floor used
before a real `BaseTier1` Model exists) was retuned alongside it, from `Vector3.new(40, 2, 40)` to
`Vector3.new(48, 0.6, 48)`, so the placeholder now matches Tier 1's real platform exactly instead of
being a slightly-off guess. Y is deliberately NOT shrunk with the rest — it's the vertical half-extent
of the "am I at my own base" test in `PlotService.IsPlayerInOwnPlot`, not a visual dimension, and
shrinking it toward floor-thickness size would put a standing player's torso outside their own base.

**Non-obvious consequence, worth repeating where a builder will actually see it (README's Base
plots bullet):** shrinking `FootprintHalfSize` in config alone does NOT shrink the wave-defense
boundary. `CombatEncounterService.getWallAttackRange` measures "close enough to attack the wall"
and the spawn ring off the REAL base Model's measured bounding box (`BaseService.GetPlayerBaseModel`),
not off `ResearchConfig`'s number directly — so a Studio `BaseTier{n}` Model that isn't resized to
match the new ladder leaves enemies stopping (and spawning) at the OLD, bigger boundary, which no
longer lines up with the smaller platform underneath them. The config retune and the Studio art both
have to move together.

**Plot spacing is still a Studio concern, just a much smaller one now.** Hand-placed `Plot` anchors
should still be spaced for the largest tier (63 studs across at T6), not the smallest, but that's a
small ask compared to the old 200-stud top tier — which was the point of this retune.

**Displayed two ways:** a bottom-left status panel (health bar, stamina cells, and a Research row
that opens the requirements popup) and a floating sign over the base showing owner + tier. The
stamina slot was a disabled placeholder until the dash was built (2026-09-15, see "Stamina & dash").

### Stamina & dash — BUILT 2026-09-15, untested in Studio

User's spec: 3 stamina slots at the start, spent by dashes in whatever direction the player is
moving, recovering 1 per 5 seconds, with variables ready for a dash animation they will make.
- `Shared/DashConfig.lua` holds every number (MaxCharges 3, RechargeSeconds 5, Speed 80 × Duration
  0.22 ≈ 17.6 studs, Cooldown 0.35, WhenStandingStill "Facing", AllowInAir false, Keys Q + gamepad B,
  TouchButton) and the animation slots (`AnimationId` "" until published, speed, fade, priority,
  StopAnimationWithDash). Shared so the HUD and the client's prediction can't disagree with the server.
- `DashService` owns the charge count: lazy timestamp recharge (no per-player loop), `RequestDash`
  takes no arguments and is RateLimiter-gated at Cooldown × 0.8, every request is answered with a
  corrective `StaminaUpdate` ({Charges, MaxCharges, RechargeRemaining, RechargeSeconds}), refill on
  respawn. `GetCharges(player)` for future systems.
- `DashClient` predicts the spend (via `StaminaState.lua`, shared with MainHud) so the dash is instant,
  and moves the character with a `LinearVelocity` (PerAxis force limit, Y = 0 so gravity/jumps are
  untouched, RelativeTo World) for Duration. A character is simulated on its own client, so the
  movement can't be server-authoritative; the server keeps the COUNT honest.
- MainHud's stamina placeholder is now `Hud.segmentBar` cells; the recharging cell fills in.
- "In the beginning" → a future upgrade adds a profile field on top of MaxCharges. Not built.
- Not decided/handled: whether a Hulk slow (PlayerSpeed) should shorten dashes (it doesn't).
- **UPDATE 2026-09-22: i-frames during a dash are now built** — `DashConfig.IFrameSeconds = 0.3`,
  stamped as a `DashInvulnerableUntil` Player attribute the instant a charge is actually spent,
  read via `DashService.IsInvulnerable(player)`. Currently only checked in the raid combat damage
  path (`CombatEncounterService.safeIsInvulnerable`) — mine lava damage and outpost NodeService chip
  damage go through different code paths and do NOT check it, which is a known/deliberate gap for
  now, not a bug. See "Resuming after a context reset" for the full record.

Six tiers exist as placeholders (Scrap Workbench → Foundry, waves 0/5/10/15/20/25). Extending the
ladder is adding a table entry plus the matching Studio Model — no code changes.

## Turret economy — reworked so a turret is EARNED (BUILT)

Supersedes the "blueprint purchase mints a turret instance immediately" model described in the
Turrets bullet under `## Base`. Direct instruction after playtest: *"i want the turrets, at least
when you buy then to only make it available to craft it, not like you get the turret instant... so
that players are encouraged to mine and get resources, and craft it, thats the point of the game."*

**The intended loop, stated directly by the user:** mine to gather resources → raid for Scrap and
loot drops → wave defense for milestones (Research level) and other drops → better gear → run the
same cycle more efficiently. Each activity feeds a different part of the same build, so no single
one can be ground to skip the others.

**Currency roles, now explicit:**
- **Scrap is the main currency.** Raids and loot pay it out; almost everything worth building
  spends it. Previously it was earned but barely spent — base tiers and turrets were ore/Cores only.
- **Cores stay turret-UPGRADE-only.** Direct instruction: *"im okay with cores being used on
  turrets since it makes them have an use."* Cores drop from boss waves only, so keeping their sink
  narrow is what keeps them scarce.
- **Base/station upgrades cost Scrap + ore** (`BaseConfig.BaseTierCosts` gained a Scrap component
  at every tier, on top of the existing ore and the CoreItem gate).

**Turret acquisition is now three steps, not one:**
1. **Hub Shop** — `BlueprintCost`, now **Scrap** (was Cores). Buys the RECIPE, permanently
   (`profile.UnlockedTurretBlueprints`). Does not hand you a turret. Re-buying a known blueprint is
   rejected rather than silently charging again.
2. **Welding Station → Turrets tab** — `TurretConfig.CraftCost` (Scrap + raw ore), paid per turret.
   This is the real gate; it's what forces a mining run. Routed through the existing `CraftItem`
   remote with a new `"Turrets"` tree rather than a new remote, so it inherits the same plot gate,
   station gate and cost validation Robots/Mods already use. Blueprint ownership is re-checked
   server-side — the client hiding locked types is presentation, not enforcement.
3. **Slot pad at your base** — place it (unchanged, see the in-world placement bullet above).

This is also what finally gives `profile.UnlockedTurretBlueprints` a purpose — it was flagged in
the codebase audit as written-on-purchase and never read by anything.

`TurretService.MintTurret` is now the single place a Turret instance is created (crafting, and the
`/giveturret` admin command). It was previously copy-pasted across the shop purchase and the admin
grant — same Id counter, same shape, two chances to drift.

**All numbers here are placeholders.** Per-gamemode drop rates aren't settled yet (*"im still
thinking of each drops will each gamemode give, but for now just use a placeholder"*), so treat the
ratios as the intent — blueprint ≈ 2x one craft, craft cost climbing steeply by turret tier, base
tiers climbing steeply in Scrap — and the absolute values as provisional pending a real playtest.

## Environment effects — distance fog removed

`EnvironmentFX.client.lua` used to carry two cosmetic touches: tree sway (unchanged, still there)
and a distance-based fog/haze effect, driven every Heartbeat off distance from the
`ExpeditionStart` anchor, that thickened `Lighting.Fog*` (or an `Atmosphere`'s `Haze`/`Density` if
one was present — Atmosphere overrides plain Fog rendering when it exists) the further out you
walked. It's gone now: direct feedback was that it made the world harder to see, which defeats the
purpose of a cosmetic effect meant to make traveling feel different, not to hide the thing you're
walking toward.

**Why a one-time startup clear replaced it, instead of just deleting the per-frame writes:** the
Fog/Atmosphere properties this loop drove aren't owned by the script — `Lighting.FogEnd` is a
place-wide property that keeps whatever value was last written to it, and an `Atmosphere` instance
is something a builder adds by hand in Studio (not something this script creates), so it keeps
whatever `Haze`/`Density` it was saved with regardless of whether any script is touching it. Simply
removing the writes would have left every place file that already has a saved `Atmosphere` or a
non-default `FogEnd` looking exactly as hazy as before, with nothing in Output or in this script
explaining why — the "distance fog is gone" changelog line would have been a lie for anyone testing
in an existing place file. So the script now runs once at startup and forces `Lighting.FogStart = 0`,
`Lighting.FogEnd = 100000`, and any hand-placed `Atmosphere`'s `Density`/`Haze` to `0` — correct
regardless of what a given place has saved, not just the one currently open in Studio.

If a future session wants distance fog back, treat it as a re-add, not a revert: the removed loop's
tuning knobs (`FAR_HAZE`, `NEAR_FOG_END`/`FAR_FOG_END`, `FAR_DISTANCE`, and two colors) are gone
from the file, not commented out, on the theory that a half-remembered fog system sitting dead in
the script is more likely to confuse a future edit than a clean removal plus this note.

## Half-built reward loops (granted but unspendable — open follow-ups)

Surfaced by the codebase audit. These are **not** dead code to delete — each is one working half of
a loop whose other half was never built. Listed so a future session either finishes them or
deliberately cuts them, rather than rediscovering them one at a time.

- **`profile.InstantCraftTokens`** — granted by three separate sources (`NodeConfig`'s Shop
  catalog, `RewardTables`' Boss and Regular utility rolls, and a `ShopConfig` developer product)
  and **spendable nowhere**. There is no instant-craft mechanic: crafting has no duration to skip,
  so the token has nothing to do. Either give crafting a real timer (the way `SmeltService` already
  has one) so skipping it is worth something, or drop the token from those tables.
- ~~**`profile.RefinedOreCounts`**~~ — RESOLVED. Refined materials are now spendable: the upper
  half of the turret roster (`TurretConfig.CraftCost`), Research Tiers 3+ (`ResearchConfig`), and
  Tool Tier 4 (`OreConfig.ToolTierCosts`) all price partly in them, so smelting sits on the critical
  path instead of being a sink with no output.

  The blocker was never the cost tables — it was that `DataService.TrySpend` only understood
  `Scrap`/`Cores` and `OreCounts`, so a price quoted in `SteelIngot` silently read as "you have 0 of
  this ore" and every purchase failed. That bucket-routing logic was duplicated in four places (twice
  inside TrySpend, again in the Research requirements check, again in the HUD's cost formatter) and
  none of them knew refined materials existed. It now lives once, in **`Shared/Wallet.lua`**
  (`BucketFor` / `GetAmount` / `DisplayName` / `CostString` / `CanAfford`), shared by client and
  server so the UI can never disagree with what the server will actually charge. Costs can now be
  quoted in any bucket — currency, raw ore, refined material, or CoreItem — with no caller changes.
- ~~**`profile.ResearchTier`**~~ — RESOLVED. It is now the game's progression ladder with a real
  earn path (see "Research level" above), so turret levels are no longer capped at 10.

Two previously-dead fields have since been fixed and are now live: `OreConfig.ToolTiers[].SwingTime`
(now the server-side mining cooldown) and `profile.UnlockedTurretBlueprints` (now the blueprint
unlock gate — see the Turret economy section above).

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
- ~~**Hub Shop "buy/sell" — only buy shipped.**~~ HALF-RESOLVED by the ore rework. The original ask
  described the Hub as somewhere players "can go and buy/sell what they want." `TurretShopService.lua`
  still only has `BuyTurretBlueprint` — there's still no sell-back path for turrets or blueprints —
  but the Hub Shop station gained a second tab, **Sell** (`StationConfig.Types.Shop.Tabs`), backed by
  new `SellService.lua`/the `SellOre` RemoteFunction: raw ore and refined material both sell back for
  Scrap at a `SellPrice` field on `OreConfig.Ores`/`RefinedOreConfig.Ores`. Whether turret/blueprint
  sell-back is still wanted is **unconfirmed** — don't assume it's intentionally out of scope either.
- ~~**An earlier recommendation was superseded, not built**~~ — REVERSED SINCE. The idea noted
  here (a blueprint unlocking a craft-with-materials step rather than minting the turret directly)
  is what the game does now: the user asked for it explicitly — "I want the turrets, at least when
  you buy them, to only make it available to craft it, not like you get the turret instant". See
  "Turret economy" above. Left in place only so the reversal is legible rather than looking like
  drift.
- ~~**Top-of-file build order is stale**~~ — RESOLVED. "Status at a glance" and the build-order
  paragraph have been brought current: Research and the Black Market are both marked Built, the new
  combat systems have rows, and "next up" now points at the gun/tool content backlog.
- ~~**Hub Shop vs. the still-unbuilt "Main shop"**~~ — RESOLVED. The planned Main shop was
  **superseded by the Black Market**, which is the same rotating-stock shape doing the same job, so
  it was never built separately. The two remaining shops are deliberately distinct: the **Hub Shop**
  sells turret blueprints, the **Black Market** sells sealed cases. Both rotate on the same
  deterministic time-hash approach (`TurretConfig.GetRotatingStock` / `CaseConfig.GetRotatingStock`),
  which is what makes stock identical for every player on every server without storing anything.
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
  back to a small colored placeholder pedestal since none exist yet. (3) The Black Market and
  Hacker Machine need the same treatment — a `Station`-tagged Part/Model outside any `BaseTemplates`
  Model, with `StationType` set to exactly `"BlackMarket"` and `"Hacker"` respectively, or neither is
  reachable in-game. (4) `ReplicatedStorage.BaseTemplates` still only has `BaseTier1`; Research tiers
  2-6 all fall back to the placeholder floor until `BaseTier2`..`BaseTier6` Models exist.

## HUD phase 3 — stylised menus (PLANNED)

The chrome overhaul is done: every panel and button is on HudKit's angular frame, tokens, icons and
hover/press. What is NOT done is the *content* of the crafting menus, which are still lists of rows.
This section is the plan for that, plus two smaller corrections. Nothing here is built yet.

### A. Recall — small, do first

Two changes, both trivial in isolation, but the first has a consequence worth deciding before it is
built:

1. **Always visible**, not gated on being in a mine shaft. It currently appears only on `DepthUpdate`.
2. **Wrong colour.** It is `danger` (red). It should follow the palette like every other action —
   `secondary`.

**The consequence:** Recall and Return to Base currently SHARE the right-hand column, because they
were effectively mutually exclusive (see the shared-slot comment in `MainHud.client.lua`). A
permanently-visible Recall ends that. Return to Base then needs its own home, and the row becomes
four items again — which is what broke the centring on Start Defense in the first place. Options:

- A fourth slot mirrored on the left, keeping the row symmetric (Inventory + one more on the left,
  Defense centre, Recall + Return to Base on the right).
- Return to Base moves out of the row entirely, the way Test Mode did.
- Return to Base only appears when the player is actually ON the expedition rather than whenever the
  shared server-wide queue is active — which is arguably the real fix, since `CurrentSlotId` is a
  server-wide attribute and the button currently shows for players who have nothing to do with it.

**Also unresolved:** what Recall does when the player is not in a mine. `RecallFromMine` must reject
that safely; confirm before making the button permanent, or it becomes a button that appears to do
nothing — the exact failure mode this project keeps paying for.

### B. Raid map — light touch only

`RaidClient.client.lua` still has its own ScreenGui, its own `COLOR`/`new`/`corner` helpers, and no
HudKit styling except the Start Raid button. The map circles and node panels look nothing like the
rest of the HUD. A full migration is NOT wanted yet — the raid system is getting its own overhaul
later. Interim: apply the plate/panelframe treatment and the tokens to the node panels and the
Scraps Collected readout so it stops looking like a different game, and leave the map graph alone.

### C. Crafting menus — the real work

The Workbench, Forge, Welding Station and Smelting tabs are all the same shape: a tab row and a list
of `makeRow` entries. That is legible but characterless, and it is the same screen four times.

**The brief: each menu gets its own identity.** They should not look like one another. The Forge is
not a list — it is a machine you feed. A concrete example from the user, worth designing around:

> the forge could have a slot where you put unprocessed ore in, it processes it, and you pick it up

So: input slots, a visible process/progress state, an output you collect. The same thinking applies
to the others — Welding is about attaching mods to a weapon, so it wants the weapon and its slots on
screen, not a list of mod names.

**Process, matching the one that worked for the HUD:** design first, in an artifact, showing 2-3
distinct directions PER MENU rather than one house style applied four times. Pick or hybridise, then
build. Do not start implementing before the direction is chosen — the HUD overhaul went well
precisely because the look was settled on a page first.

### D. Popups

The toast, ModPicker, the ultimate picker and the case-opening flow never got the chrome pass. They
should be included in the design round above rather than retrofitted afterwards, since a popup that
does not match its parent menu is more jarring than one that matches nothing.

#### A-revised: Recall as a universal "go home" button — BUILT (2a652f1)

Decision: Recall is a single button meaning "bring me back to base", visible at all times. Where it
is not allowed, it toasts the reason rather than hiding. That also RETIRES Return to Base as a
separate control — same intent, different remote underneath — which removes the shared-slot problem
and leaves the action row a clean symmetric three.

**The trap, found before building it.** `RecallFromMine` is deliberately gated to the mine shaft.
Its own comment records why: it had no validation, and since `LoadCharacter` respawns at FULL
HEALTH, it was a free full-heal on demand anywhere in the game — including mid-raid with damage
ticking — making a player who bound it to a key effectively unkillable. Widening that remote to
"anywhere" re-opens exactly that exploit.

**So the general case must not respawn the character.** Move the character to the plot anchor via
CFrame instead, preserving health. `LoadCharacter` stays only for the mine, where it is already the
established way out and the heal is part of the deal.

Server-side rules, all enforced on the server and each with a toast on rejection:

- In the mine shaft -> existing `RecallFromMine` path, unchanged.
- On an expedition -> existing `EndExpedition` path. Note this ends the run for EVERY player on the
  shared queue, so it needs a confirmation, not a single click.
- In combat (a wave, a raid, an outpost) -> REFUSE, with a toast saying so. Teleporting out of a
  fight is the exploit in a different costume. `PlayerActivityService.Get` already knows the
  player's authoritative activity and is the right thing to ask.
- Otherwise -> CFrame move to the player's plot anchor, health untouched.

One new remote is cleaner than overloading `RecallFromMine`, so the mine's existing guard stays
exactly as tight as it is now. The client button picks the path from state it already tracks; the
server re-checks regardless, since the client can lie about all of it.


#### C-revised: directions drafted and CHOSEN (2026-09-02) — not yet built

The design round happened: ten mockups, 2-3 per menu, drafted blind (the user said draft rather than
describe first). Working files are `.design/menus/*.dc.html` + `canvas.json`, assembled into
`.design/menus/station-menu-directions.html` and published as an Artifact. The `.dc.html` files are
Claude Design artboards and seed straight into an editable canvas once Node exists on the machine —
there is none right now, which is the only reason that round shipped as a flat page.

**The picks:**

| Menu | Chosen | Panel size |
| --- | --- | --- |
| Forge — Weapons tab | **A, "Crucible"** — input bay / running chamber / output tray; pity drawn as machine heat, Luck Potion as an additive you slot in | 760x520 |
| Forge — Smelting tab | **B, "Batch Dial"** — one dial reading batch time, a quantity slider, per-ore cost underneath | drawn 640x424, must be re-proportioned |
| Welding Station | **A, "Rig Diagram"** — the robot centre-stage, its 3 mod slots as hardpoints on leader lines | 760x520 |
| Workbench | **B, "Spec Sheet"** — tabs stay; each is one equipped item as a hero with an explicit before/after for the next tier | 640x424 |
| Popups | **B, "Lifted Slabs"** — own plate, scrim, shadow, accent cap coloured by kind | — |
| Case opening | **A/B hybrid**, per direct request: A's in-panel reveal while the roll is running, then B's full-takeover card animates in when it lands | — |

**Facts the mockups got wrong, corrected against the code — fix these before building:**

- **Tool mods are not multi-slot.** `profile.EquippedTool` holds ONE key; `ToolModConfig.Tools` has
  exactly three (Split-Head Pick, Featherweight Pick, Prospector's Pick) and they are sideways
  choices, not a collection. Workbench B drew a chip row with an empty `+` slot. It is a pick-one.
- **Auto-Miner is not an upgrade track.** One-time craftable (`AutoMinerConfig.Cost` = 60 IronOre +
  15 CopperOre), `MaxOwned = 1`, yields `BaseYieldPerTick` 3 IronOre every `TickSeconds` 60. The
  tab is a build-it / own-it state, not levels. The mockup invented "Level 4 -> 5" and a cost.
  (Amounts unchanged by the ore rework — only the key names moved, `ScrapIron`->`IronOre` and
  `CopperWire`->`CopperOre`.)
- **Base tiers live in `ResearchConfig.Tiers`, not BaseConfig**, and there are SIX: Scrap Workbench,
  Reinforced Workshop, Fortified Bunker, Bastion, Citadel, Foundry. T2->T3 costs Scrap 1200 +
  GoldOre 150 + CopperOre 80 + SteelIngot 20 (same amounts as before the rename — `SteelPlating`
  became `GoldOre`, `CopperWire` became `CopperOre`; `SteelIngot` was already a refined-material
  key and didn't move). Turret slots by tier are 2/4/5/7/8/10
  (`TurretConfig.GetSlotCount`), so "+1 slot" is right for T2->T3 only by coincidence.
- **Robot mod slots are never locked.** `EquippedMods[itemKey][slotIndex]`, slotIndex 1..3, and
  `CraftingService` checks only the range — an empty slot means you have not fitted a mod, not that
  the slot needs buying. Welding A invented "unlock 40 cores". Also note `itemKey` is a robot TYPE,
  so every deployed Scrapbot shares one loadout.

**The structural conflict that has to be settled first.** Weapons and Smelting are two tabs of the
SAME station (`StationConfig.Types.Forge.Tabs`), and `craftFrame` is one plate sized once at
640x424. Forge A needs 760x520; Smelting B was drawn at 640x424. Resizing per TAB would make the
panel jump while switching tabs inside one station, which is worse than either size. So panel size
becomes **per station** — Forge and Welding at 760x520, Workbench staying 640x424 — and Smelting B
gets re-proportioned up to 760x520 rather than the panel shrinking under it.

**Server-side reality check, per pick:**

- **Smelting B is free.** `profile.SmeltJob` already carries `FinishTime` as an `os.time()` stamp, so
  a live countdown needs no new remote. The job also auto-grants — `SmeltService`'s loop adds the
  refined ore and clears the job — so there is correctly no Collect button in the design. One
  wrinkle: `RefinedOreConfig.SmeltTime.TickSeconds` is 2, so the grant lands up to 2s after the
  countdown hits zero. Show a "finishing" state, never a stuck 0:00.
- **Welding A and Workbench B are free.** Fitting a mod is the existing `CraftingService` remote;
  every number the Spec Sheet shows already exists in config.
- **Forge A's output tray is the ONE real server question.** `ForgeService.ForgeWeapon` inserts the
  instance straight into `profile.Weapons` and returns it — there is no uncollected state. Either
  (a) add a `ForgeOutput` profile field plus a collect remote, so the tray survives a relog, or
  (b) treat the tray as presentation of a roll that has already banked, which costs nothing
  server-side and cannot lose a weapon.

  **DECIDED: (a), real state.** Not for efficiency — for the pile. Players reroll the same weapon
  repeatedly chasing a good one, and if every roll lands in the inventory they drown in junk they
  then have to sort. The tray is what lets a roll be REFUSED. Note `ForgeOutput` follows the
  `SmeltJob`/`DecodeJob` convention exactly: a nil-able table, deliberately absent from
  `defaultProfile` (so nil already reads as "nothing pending" and no backfill is needed), always
  broadcast as `ForgeOutput or false`. That makes this a well-trodden shape, not a risky new field.

  Rules, all re-checked server-side:

  - The tray holds one pending weapon, with **Collect** and **Trash** side by side. Trash deletes it.
  - **No refund on trash, deliberately.** You paid for the roll, not for the gun. It also makes the
    player weigh keeping a mediocre gun against going and buying upgrades first, which is the
    intended pressure. Any refund would have to stay strictly under cost or forge-then-scrap becomes
    a farm loop.
  - **Rolling with the tray occupied overwrites it** — EXCEPT when the pending weapon is Epic or
    better, which raises a confirmation first. The threshold belongs in `ForgeConfig` (a
    `DiscardConfirmMinRarity = "Epic"` key) compared through the existing `ForgeConfig.RarityOrder`
    and `ForgeService`'s `rarityIndex` helper — never a hardcoded rarity name.
  - The confirm is client UX, so the SERVER still gates it: `ForgeWeapon` rejects a roll that would
    discard a pending Epic-or-better output unless the call carries an explicit confirm flag. A
    client that lies can then only hurt itself — same reasoning as the Recall remote's re-checks.

  Rejected: blocking the roll outright while the tray is occupied. It taxes the common case (junk
  roll, instant reroll) to guard the rare one, and the confirm already guards the rare one.

**Art needed before Welding A can look like the mockup:** one line-drawing silhouette per robot
(Scrapbot, Sentry Drone, Iron Guardian, Portable Arc Turret). All 22 existing `UiIconConfig.Icons` keys are
filled, so these are additions — upload the PNGs, add the asset IDs there (git-tracked, unlike the
Studio `ItemIcons` folder). Per the project's own rule, a missing rig silhouette must fall back to a
generic chassis outline rather than an empty frame. Forge A's chamber needs no art; it is gradients
and frames.

### Resuming after a context reset

**START HERE — LIVE STATE, END OF 2026-09-25.** Everything below this block is history or backlog.

**THE REPO IS IN A DESIGN PAUSE. Nothing is half-built.** The working tree is clean, everything is
committed AND PUSHED, and the next step is building — not deciding. Read these two pages before
touching anything; they are the plan, and they hold detail this file summarises:

- **The Next Five Jobs** — the agreed work with real `file:line` targets:
  https://claude.ai/artifact/Ni5SMuqXecy9Y6AbkM6xnw
- **Decoder Reveal Directions** — the settled case-opening design, three diagrams, and the balance
  table with the two traps that produced it: https://claude.ai/artifact/BtKK6rtg7X5dq4GfxH6oQv

**BUILD ORDER, agreed:**

1. **The chest fix** — a Combat/Ambush node auto-advances with the chest unopened. Real lost loot,
   and the only item on the list that is actively costing the player something. Needs one short scout
   pass to find the auto-advance call site; it was never in scope for an audit.
2. **Mods become countable** — decided in full. Spec under "THE AGREED PLAN" below and on the plan
   page. The trap: `backfillMissingFields` will NOT convert `true` to `1`, so this needs a real
   migration on the `migrateLegacyWeapons` pattern.
3. **The ore pickup popup** — cheap now the toast is plate-shelled; needs an icon slot on
   `HudKit.makeToast` and accumulation so a vein does not fire forty toasts.
4. **The decoder rebuild** — the biggest of the four, fully designed, nothing left to decide except
   one confirmation (below).

**EVERYTHING FROM 2026-09-25 IS UNVERIFIED IN STUDIO** except what round 6 covered. Round 6 passed
19 of 21 with both failures fixed the same day; the `SortOrder` fix, the raid shop's
`dismissOnScrim`, and the three wired sounds all landed AFTER that round ran and have never been
played. Round 6's checklist — and it is the only one whose verdicts a later session can actually
READ rather than ask about, because it is built on the `db` capability:
https://claude.ai/artifact/WSxQ7D47XQTFYBVc7k8e8v

**ONE THING TO CONFIRM WITH THE USER BEFORE BUILDING THE DECODER:** Prototype's Mythical rate stays
at **20%**, not the ~10% they floated. 10% would be a cut from today and would leave Prototype only
1.9x better than Blackline per minute of decode while costing real money. This was flagged to them as
a probable misremembering and NOT applied. Everything else in that design is settled.

**Sound is built and silent.** `Shared/SoundConfig.lua` + `StarterPlayerScripts/Sfx.lua`, ~50 entries
at `Id = 0`. Three call sites wired (button hover/press, toast by kind, mining swing). The next move
is the user uploading audio and pasting numbers — not code. Do not wire the remaining entries before
there is audio to judge them against.

**The fourth round is COMPLETE. All NINE checks passed in Studio** (T1, T2a, T2b, T3a, T3b, T4, T5,
T6, T7 — the last three added mid-round as the round itself produced fixes). Nothing this round built
is unverified. The checklist and every note the user wrote on it:
https://claude.ai/artifact/PYwNs5vZ37zBZmsXH1psCT

**ROUND 5 IS CLOSED: the eight exploit fixes (F1-F8) all passed in Studio, 2026-09-25.** The user
ran the checklist (https://claude.ai/artifact/5yNSs3qagi91T4TWP67fg7) and reported every check
passing. They had been committed 2026-09-23 and sat unverified while rounds 3 and 4 passed around
them. **That backlog is now empty — nothing in the repo is committed-but-unverified any more,** for
the first time since the audit began.

**One correction, because this file said the opposite.** The F1-F8 checklist page keeps its ticks in
the browser's `localStorage`, NOT in the artifact's database — so they persist for the user and are
INVISIBLE to a session that reads the page. "Verdicts and notes are stored WITH each page" is true
only of a page built on the `db` capability. Check which kind a page is before trusting a reset to
recover verdicts from it; otherwise the honest move is to ASK the user, which is what happened here.

Two things this round settled that are worth reading before touching the adjacent code:

- **The three replication-lag gear visuals are ALL closed** — Scorch Aura's ring, its floor-locking,
  and the Orbit Blades. The pattern they converged on is written up under the aura's entry. Read it
  before adding a fourth gear visual: the answer is an Anchored server part positioned from the
  CLIENT, never a weld and never a server Heartbeat.
- **The shop item retune is calibrated, not just shipped** — see "SHOP ITEM RETUNE" below, and in
  particular the closed weapon-relevance question. Someone comparing a 25-DPS aura to a 30-DPS gun
  will think the capstones are overtuned; they are comparing the one axis where gear competes and
  ignoring range, crit and mod slots, where it cannot.

### FOURTH SESSION, 2026-09-24 — ALL FOUR AGREED TASKS BUILT AND STUDIO-VERIFIED

**All nine checks passed** (T1, T2a, T2b, T3a, T3b, T4, plus T5, T6 and T7 added mid-round) — checklist
and the user's notes at
https://claude.ai/artifact/PYwNs5vZ37zBZmsXH1psCT. That includes both regression checks, which were
the real risk: base-wall attacks still work after the attack-slack split (T3b), and a normal
extraction is not mistaken for a character reset (T2b).

**T6 also confirmed the client-positioning pattern rather than just the blades.** The Orbit Blades
needed the two sides to agree on an ANGLE, not just a position — the aura's ring is rotationally
symmetric and needed only X/Z. That agreement is structural: both sides compute
`Workspace:GetServerTimeNow() * RunBuffConfig.Items.OrbitBlades.Base.OrbitSpeed`, a synchronized
clock times a SHARED speed, so nothing replicates and nothing drifts. Two consequences worth
knowing before reading that code: the server's accumulated `state.Angle += dt * 2` is GONE (an
accumulated angle is unreproducible by definition, so the client could never match it), and the hit
test COMPUTES blade positions from the shared helper rather than reading `blade.Position`, which
would otherwise test against parts frozen at spawn.

**One follow-up, from the user's note on T4** (*"it works, but make sure that the zone for the aura,
the circle is always on the floor, even when the player is jumping"*) — **BUILT AND VERIFIED (T5)**.
It was a real miss and worth recording as a pattern, because this ring has now been positioned three
ways and the first two each fixed one half and broke the other:

- **Server Heartbeat** — lagged. A server tick runs after the frame the player is looking at and
  then has to cross the network, so the ring chased where the player *was*.
- **Welded to the root** — cured the lag by handing position to the client's own physics, but a weld
  is RIGID, so jumping carried the ring up into the air. The thing drawn as a zone on the floor
  stopped being on the floor. That is the bug the user caught.
- **Positioned on the CLIENT** (`StarterPlayerScripts/ScorchAuraVisual.client.lua`, new) — gets both
  properties at once: the player's own frame with no round trip, and a Y free to be decided
  independently of the character's. The part stays Anchored and the server writes its CFrame exactly
  once, at creation, so nothing fights the per-frame local writes or replicates them back. The ring
  is found via a new `RunGearItem` attribute, **not** by name, because a real model cloned from
  `ServerStorage.RunGearModels` keeps the TEMPLATE's name — a name lookup would have worked right up
  until the art landed.

The damage test moved with it, and had to: a ring drawn on the floor that burns in a sphere around
your chest is a ring that lies, and this gear's whole design point was that its visual and its
damage read the same value. Reach is now horizontal distance from the root, bounded vertically by a
new `ScorchAura` `Base.Height` of 14 — a column, not an infinite one, so an enemy on a gantry
overhead is not standing in your ring. The horizontal term reads the same root X/Z the client draws
at, so the two cannot drift apart.

**The general lesson, and it is the second time this round it has come up:** when a fix trades one
property for another rather than adding one, the trade is usually hiding a third option. The weld
looked like the answer because it beat the Heartbeat on the axis being measured at the time (lag)
and nobody was measuring the other one (floor-locking) until the user jumped.

The four tasks the third round produced are all implemented, committed and now verified. The five
open questions that gated them were put to the user and answered; the answers are recorded inline
with each task below rather than kept as a separate list, because a decision with its consequence
next to it is the only form that survives a reset intact.


**R2/R3/R4 remain closed** (the Scorch Aura ring keeping up with the player — by a weld then, by
the client now; raid entry raising the Sector Map; the blue shield on
both HP bars). **B2 is now closed too** — the user confirmed the four lines in scope (room
description, interaction hint, "Fully healed.", boss-clear loot line) do fade. The room title, enemy
counter and buttons still pop, which is expected and was always what confused the original answer.

**1. R1, the Scavenger head — FIXED, and the nested-Model hypothesis was right.** The user confirmed
a Scavenger headshot has never dealt damage, which is what the hypothesis predicted.
`ResolvePlayerHit` took the FIRST Model ancestor of whatever the ray stopped on and gave up when
that model was not a key in `EnemyByModel`. The Scavenger's head sits inside a nested Model, so the
first ancestor was that inner sub-assembly and the shot resolved to no enemy at all. It now walks
the whole ancestor chain up to the workspace root.

**The general lesson, worth more than the fix.** This was never a headshot bug. The previous round's
change (score a headshot by WHERE the ray landed, not which part stopped it) was correct and is
still in; all it did was change the symptom from a white number to no number, because the shot never
reached the damage code in either version. A fix that changes a symptom without removing it is
evidence the diagnosis is in the wrong layer — that is what the second symptom was telling us, and
it took a round to hear it.

**Still worth a look, not done:** three other places take the same single hop —
`BaseLaserService.lua:145`, `DroneService.lua:119`, and `ProjectileService.lua:237` (the piercing
exclusion list, where a nested model means a pierced enemy can be re-hit). None are reported broken;
they are listed so the next person finds them without re-deriving the pattern.

**2. Resetting mid-raid — FIXED. A reset is a DEFEAT.** The user's call, and the only one of the
three options that stops reset being a free escape from a run about to go badly. Held loot is
forfeited and reported like any other death.

There were two holes, because raids have two kinds of room, and only fixing one would have left the
bug alive in the other half of the game:

- `RunRaidCombat` re-read `player.Character` every tick but never compared it to the body the fight
  started on, so a reset swapped in the fresh full-health character and the loop carried happily on
  against it. It captures `startCharacter` now and ends the fight when the body changes.
- Shop, Heal and Map rooms have nothing ticking at all and could not notice anything.
  `RaidRoomService` connects `CharacterRemoving` for the life of the raid, deferred (so `failRaid`'s
  own `LoadCharacter` does not run inside the handler that triggered it) and guarded on the raid
  still being that state (so every normal exit's respawn can never read as a reset).
  `cleanupRaid` drops the connection first thing, before anything there can respawn anybody.

The invisible half of this bug mattered more than the visible one: `PlayerActivityService` kept
holding the `Raid` activity, which soft-locked every LATER raid. The room geometry was the symptom
people could see.

**3. Enemy attack ranges — FIXED, but it was NOT the config-only change the notes predicted.**
`EnemyAI`'s `ATTACK_RANGE_SLACK` added a flat **12 studs** to every enemy's `ContactRange` in the
attack test, so a Scavenger configured to hit from 5 actually hit from 17 — and the planned retune
from 5 to 4 would have moved that to 16. Imperceptible. Retuning the config alone would have looked
like the fix did nothing.

Every word justifying that 12 is about walking to a BASE's wall, where an enemy stopping slightly
short of the ring used to freeze and never attack — nothing to do with chasing a player, where
there is no wall short of the target and the stand point is re-issued every think. Split in two:
`ATTACK_RANGE_SLACK` 12 for the wall, `PLAYER_ATTACK_RANGE_SLACK` 2 for a player. `context.TargetPlayer`
already marked the difference (raid contexts set it, `RunWave`'s base-defense context never has),
so the split needed no new field anywhere.

Per-type values, now that they mean something: **Scavenger 4, Brute 5, Raider 9** — real hitting
distances of 6, 7 and 11 studs. All three had been inheriting `RebelBase`'s 5. **The notes were
wrong that the Brute sat at 8**; that value at `EnemyConfig.lua:168` is the **Siegebreaker's**.

**The Hulk is untouched and could not have been touched by this.** His attacks are not gated by
`ContactRange` at all — the `Animated` pattern in `EnemyAnimation.lua:775` has its own
`AttackRadius` logic — so the `ContactRange < AttackRadius < TriggerRange` ordering his config
comment warns about is unaffected. Worth knowing before anyone else worries about it.

**4. Aura and blade reach — FIXED, both of them, config AND code.** The user confirmed "the aura
things" meant both items, and chose **bigger jumps at the rarity caps** over smooth per-level
growth, so both keep a milestone feel instead of creeping: **+30% at Lv4, +70% at Lv5**. Scorch Aura
goes 10 → 13 → 17 studs; Orbit Blades 6 → 7.8 → 10.2.

The aura was config-only as predicted — its visual and its damage test already read the same value,
so the ring could never lie about its reach. The blades needed real code: `RunBuffService` read
`item.Base.OrbitRadius` flat with no level term at all. It scales off the same value that positions
each blade, so they cannot be drawn wider than they cut. The key is **`OrbitRadiusPct`, not a second
use of `RadiusPct`** — `RunBuffConfig.Aggregate` sums every numeric level stat into one flat table,
so two items writing the same key there is a collision waiting for its first reader.

Note `LevelStats` overlays `Lv5` onto `Lv4` key by key, so restating a key in `Lv5` REPLACES the
`Lv4` value rather than stacking with it. That is why the aura's Lv5 entry says 0.70 and not 0.40.

### SHOP ITEM RETUNE, 2026-09-25 — BUILT AND STUDIO-VERIFIED (T7)

From the user's T6 note: *"these perks, these things u buy from the shop, should be like a bigg help
yk, cuz they can be hard to come by and etc... thats how these gamemodes usually work"* — plus,
specifically, bigger radius, more blades, more aura damage at max level.

**The framing that makes this coherent:** rarity sets a LEVEL CEILING, not a power number (Rare 3,
Epic 4, Legendary 5). So "max level" means Lv5, which needs a Legendary copy, which is genuinely
rare — and the capstone was previously just a status effect. Every rarity cap now gets a step a
player at that cap actually reaches, and Lv5 is a real jump.

**Config only.** Every capstone key was grepped against the services BEFORE any number moved, and
all of them are genuinely read — no inert buffs. That check is the reason the three findings below
exist, and it is worth repeating before any future balance pass on this file.

| | Lv3 (Rare cap) | Lv4 (Epic cap) | Lv5 (Legendary cap) |
|---|---|---|---|
| Scorch Aura | 12 DPS, 11.5 studs | 16 DPS, 13 studs | **25 DPS, 20 studs**, Slow |
| Orbit Blades | 3 blades, 9 dmg (~8.6 DPS) | 4 blades, 12 dmg (~15.3) | **5 blades, 15 dmg (~23.9)**, Staggered |
| Laser Drone | 6 dmg, 2.3/s | 8 dmg, 2.6/s | **10 dmg, 3/s, 3 beams** (~30 DPS) |
| Overclock Chip | +30% dmg, +5% crit | +40%, +10% crit | **+50%, +15% crit, crit every 5th shot** |
| Rapid Feeder | +27% rate, 20% burst | +36%, 30% burst | **+45%, 45% burst 4s, +40% kill frenzy 3s** |
| Plated Vest | +36% HP, -10% elite dmg | +48%, -15% | **+60%, -25%, 35% shield under 30% HP** |
| Nano Repair | 18%/room, 1% per kill | 24%/room, 1.5% | **30%/room, 2.5% per kill, overheal→shield** |
| Kinetic Barrier | 30% shield, 10s refill | 40%, 8s | **50%, 5s refill, 16-stud knockback** |
| Scavenger's Lens | +36% loot, 2s chests | +48%, 1.5s | **+60%, 1s chests, +2 items per chest** |

Blade DPS is `blades * damage / orbit period` (period = 2π/OrbitSpeed = 3.14s), which is why the
count matters more than the damage there.

**Three findings that changed what the retune could be. Each one is the same trap — a number
nothing consumes — and each was caught by checking rather than by assuming.**

1. **Nano Repair's capstone was already clipped.** Its Lv5 heal was 5% × 5 levels = **exactly**
   `ShopHealCap.PerRoom`'s old 25% ceiling, so lifting the perk alone would have changed literally
   nothing at max level. The cap had to move with it, to **35%/room and 160%/map**. That trade is
   real and deliberate, and someone will eventually wonder about it: a more generous shop-heal
   budget makes a raid **Heal room** slightly less precious, which is exactly what this cap was
   introduced to protect. Revisit the two together, never one alone.

2. **The Laser Drone was not the weak gear item.** The assumption going in was that leaving it out
   would make it the obvious dud. Wrong: `ExtraBeams` fires at **different** targets
   (`GearBehaviors.LaserDrone` sorts candidates by distance and shoots the nearest N), so beams
   SPREAD damage rather than stacking it on one enemy — and at ~26 DPS single-target it was already
   the strongest of the three. It got a rate-and-targets capstone instead of a damage one, and its
   `DamagePerShot` was deliberately left alone.

3. **Orbit Blades' radius growth is GONE, reversing part of 2026-09-24's change and part of the
   user's own original ask.** The blades damage only what comes within ~3 studs of a BLADE, so they
   cut a ring **band**, not a filled disc — anything closer to you than the orbit sits in a safe
   pocket. Widening the orbit widens that pocket, and with a Scavenger now attacking from 6 studs it
   would have made the blades worse against precisely the enemies they exist for. Presented as a
   trade-off; the user chose to keep the orbit at 6 and grow the COUNT instead. **The aura still
   doubles to 20 studs**, because it IS a filled disc (horizontal distance to the player) and has no
   pocket. The two items differ for a structural reason, not an inconsistent one.

**`LevelStats` stopped hardcoding Lv4 and Lv5** and now walks any `Lv<n>` key in ascending order.
The old shape quietly meant a **Rare copy could never have a tier step at all**: Rare caps at level
3, so every milestone in the file sat above its ceiling and a Rare item's only progression was the
linear `PerLevel` term. Worth knowing as a general lesson about this file — a tier table is only
reachable if some rarity's cap is at or above its level.

Note the overwrite semantics this relies on: an `Lv5` entry restating a key REPLACES the `Lv4` value,
and restating a `PerLevel` key replaces the computed `perLevelValue * level` outright. That is how
ScorchAura's Lv5 sets a flat 25 DPS instead of being stuck with whatever the linear ramp reached.

**Prices deliberately unchanged.** The user's reasoning was that these are hard to come by, so the
payoff should be big — that argues against charging more for it.

**The weapon-relevance risk is CLOSED, and the reasoning matters more than the verdict.** Going in,
the honest worry was that four maxed slots would make the equipped gun pointless — each maxed piece
is individually comparable to a mid-tier gun (weapons run roughly 4–48 DPS), and four together
plainly are not. Verified in play and the answer is no. The user's words: *"it looks good, guns do a
little less but they have wayy more range and they can crit and all, and my gun had no attachments
either, this is very good."*

**Why it holds, which is the part worth keeping:** raw DPS was never the whole comparison. A gun
keeps three things no gear piece has — **range** (gear is 6–20 studs; a gun reaches across a room),
**crit** (gear damage does not crit; `RollCrit` applies to weapon shots), and **mod slots**. So gear
being DPS-comparable at max level does not make it a replacement; it makes it a floor that the gun
builds on top of.

**And the test understates the margin:** that run was made with a gun carrying NO mods. A modded gun
widens the gap further, so the real ceiling is higher than what was measured.

**Treat this as calibration evidence, not just a pass.** If someone later looks at a 25-DPS aura
next to a 30-DPS gun and concludes the capstones are overtuned, they are comparing the one axis
where gear competes and ignoring the three where it cannot. Do not pull the Lv5 numbers down on that
reasoning alone. If a real problem does appear, the capstones are still the right lever rather than
the per-level ramps, since the ramps are what carry the early run.

### FIFTH SESSION, 2026-09-25 — THE EXPLOIT FIXES PASSED, AND THE BOOT CHECK NEARLY STOPPED THEM

**All twenty checks on the F1-F8 list passed** (https://claude.ai/artifact/5yNSs3qagi91T4TWP67fg7),
reported by the user. This closes the last committed-but-unverified work in the repo. Nothing here
needed a fix afterwards — the round found one problem, and it found it *before* Studio.

**The boot check was about to cry wolf, and check 1 says to STOP when it does.** `BaseLaserService`
is genuinely required at `Main.server.lua:23`, but it was missing from the HAND-TYPED copy of the
require list that the boot check compares the `Services/` folder against — so every boot warned that
a working feature (Tier 4+ base security lasers) was never required. Check 1 of the checklist reads
"no warning about unloaded modules" and tells the tester to stop if there is one. Added the missing
name; swept all of `Services/` against both lists first, and it was the only module in that state.

**This is the polish pass's item 2 in miniature, and it makes that item's argument rather than
retiring it.** The fix removes today's false alarm and changes nothing about the mechanism: a list
someone maintains by hand, whose failure is ASYMMETRIC. A name in the copy with no matching
`require` produces SILENCE — which is precisely the hang-forever bug the check exists to catch. The
loud half has now drifted twice; the quiet half cannot be observed at all. Item 2 (record what
actually loaded, e.g. a `load(name)` helper) is still the real answer and is still unstarted.

**Five of the eight were pre-cleared statically, which is worth repeating next round.** F1's
`NodeConfig.InteractDistance = 60`, F4's four caps, F7's shared `"MineSwing"` key across both mining
handlers, F8's `ResetBlockThreshold = 15000`, and F3's `PlayerVitals` presence in the correct
(transitive) half of the boot check are all just "did the constant land" — one batched grep answers
them and no Studio time is spent. What that leaves is the behavioural half, which is the part worth
a human anyway: the fourteen rerouted HP write sites and the two new refusals.

**The checklist pages do NOT hand their verdicts back to a session.** All three store ticks in
`localStorage`. This file claimed otherwise and the claim has been corrected in two places. The
practical consequence: a reset must ASK the user how a round went, and cannot read it off the page.
Build the next checklist on the `db` capability if that matters — the content of these pages is
fine, it is only the storage that does not do what the notes promised.

### SIXTH SESSION, 2026-09-25 — THE POLISH PASS, AND THE TOAST THAT LOOKED LIKE ANOTHER GAME

Round 5 closed at the top of this session (see "FIFTH SESSION"), so the polish pass inherited the
top slot. All three of its items are built. **Nothing in this session has been run in Studio.**

**Round 6 checklist — 21 checks: https://claude.ai/artifact/WSxQ7D47XQTFYBVc7k8e8v** — and this one is
built on the `db` capability, so unlike rounds 3/4/5 its verdicts and notes are readable by a later
session instead of living in the user's browser. **Read it before asking how the round went.**

**Item 2, the self-maintaining boot check.** Every require in `Main.server.lua` now goes through a
`load(name)` helper that stamps a `LOADED` set; the check compares that against the `Services`
folder. Same 29 services, same order — the resulting name set was diffed against the old one.
Why it mattered enough to do properly: the hand-typed copy had two failure directions and only one
was visible. Missing a name warns about a service that works (`BaseLaserService` did exactly this,
and was found during this session's pre-flight *because check 1 of the round-5 list says to STOP on
a boot warning*). A name PRESENT with no matching require produces silence — which is the
unregistered-handler bug the check exists to catch, so the check could be made to lie about the one
thing it is for. **The transitive list stays hand-typed and keeps that asymmetry**, deliberately:
deriving it means `load()`-ing those modules here, which moves WHEN they load, and order is
load-bearing in that file because `PlayerRemoving` fires in connection order.

**Item 3, the explicit disconnect.** `MainHud`'s `bindHealth` stores and disconnects its
`HealthChanged` handle. Not a leak — Roblox drops it with the Humanoid — it was the one
per-character connection in that file not stored, and respawning is constant now a raid death
replaces the body.

**Item 1, the UI in-place updates, in two commits.** `InventoryPanel` first (lower risk),
`RaidShopPanel` second (it must stay pixel-identical to `design/raid-shop/*.dc.html`). Two traps,
both worth knowing before pooling anything else in this codebase:

- **`LayoutOrder` must be set on every pass, outside the create/reuse branch.** A pooled row
  otherwise keeps its old order and the grid silently stops sorting. This bit for real in the shop:
  escape chips **never set `LayoutOrder` at all** and sorted correctly only because the whole row
  was destroyed and re-parented in sorted order every render. Pooling breaks that implicit
  assumption. `buildEscapeChip` takes an explicit `layoutOrder` now, fed the same sorted index the
  insertion order used to produce — identical output, stated instead of assumed.
- **A row's STRUCTURE is fixed at creation** from whatever resolved then. An inventory tile built
  before its icon existed has the wrong internals forever, so that case rebuilds rather than
  patches — which preserves the existing behaviour where dropping an icon into `ItemIcons` appears
  without a rejoin.

**`renderCards` is deliberately NOT pooled.** `RunCard.build` is a monolithic constructor with
several structural branches and no update path, and `RaidClient`'s boss pick calls it too — giving
it one safely is a restructure of a shared builder, not a pooling pass. A correct partial
conversion beat a complete one that risked the approved design.

**THE TOAST REWORK, which was not on any list.** The user's report: *"some pop stuff, those toaster
pop ups... compare a inventory, or a raid pop up, and compare it to a mine cooldown, and see how
different they are."* An audit of every transient notification found **six different visual
treatments**, and the toasts were the oldest: a flat rounded rectangle that snapped on and snapped
off, while the boss bar, mining cooldown bar and enemy alarm had all picked up eased motion and the
boss bar had picked up the angular `plate` shell.

Toasts are now `plate` + `accentCap` — the same language as every panel — with a 0.22s eased
slide-and-fade in and 0.28s out, on a **CanvasGroup** so shell, surface, cap and text fade on one
`GroupTransparency` tween instead of four trusted to stay in lockstep. Built on FIRST show, because
`HudKit.plate` is defined ~1000 lines below the toast and there is no plate to call at module load.

**There were TWO toasts** — this one and a near-identical copy in `RaidClient` with its own padding,
corner radius and 4s default. `HudKit.makeToast(opts)` is a factory now and the raid toast is one
call to it; both keep the positions they had, which the user asked for explicitly. The accent cap
is coloured per kind, so a rejection reads as a rejection before the text does — `showFailure`
already knew it was a failure and was discarding the fact. `showToast`/`showFailure` keep their
signatures, so all 88 call sites are untouched; `HudKit.showSuccess` is new and additive.

**What the audit did NOT find, which is worth recording so nobody re-runs it.** The first sweep
looked for hardcoded greys and found essentially none — the colour side of the HUD is clean, and
even `LoadingScreen`'s hand-copied palette still matches `HudKit.COLOR` exactly. What it found was
~24 surfaces writing `TextSize = 11` instead of a token. That is real untidiness but adopting those
tokens is explicitly a **no-visual-diff change**, so it would not have fixed anything the user could
see. The complaint was about motion and shell, not colour.

### ROUND 6 RESULTS, 2026-09-25 — 19 passed, 2 failed, both fixed same day

Checklist, with every verdict and the user's notes stored ON the page and readable by a later
session: https://claude.ai/artifact/WSxQ7D47XQTFYBVc7k8e8v. **Read it rather than asking.** That
property is new — rounds 3, 4 and 5 used `localStorage` and cannot be read back.

**C14 FAILED — raid shop slots rendered right-to-left. My regression, fixed.** Four layouts set no
`SortOrder`: the shop's slot row and escape-chip row, and the inventory's tile grid and detail-slot
row. It never mattered, because all four were destroyed and rebuilt in the intended order every
render, so child insertion order WAS the intended order (the children are unnamed, so name-sorting
was a no-op). Pooling removed that, and the `LayoutOrder` the conversion carefully set on every pass
was being ignored by the layout meant to read it. **The general lesson: the conversion added
`LayoutOrder` to the children and never checked that the parent honoured it — half a fix reads
exactly like a whole one until something reorders.** C9 and C13 passed with the same gap present in
the inventory; those tests simply didn't reorder anything. All four fixed, not just the one that
showed.

**C17 passed WITH A NOTE that was worse than most failures — fixed.** *"whenever you click outside
of it, it closes and you cant open it again, and get stuck."* `RaidShopPanel.Open` runs once per
node, when the server sends that node's `ShopOffers`, and nothing re-sends it (re-entering the same
Shop deliberately shows the same offers). So a scrim click destroyed the only UI for the node the
player was standing on. `HudKit.openPanel` already had `dismissOnScrim`; the shop just never passed
it, and it is the right panel for it — a decision point whose own LEAVE SHOP fires `"Continue"`, so
the single remaining exit also advances the node. **Worth remembering that this arrived on a PASS.**

**C12 FAILED, and it is NOT a bug — it is the design, and the user should decide whether to keep
it.** Reported as: one Heavy Rounds mod equipping onto several guns at once. That is exactly what
the code intends. `DataService`'s `defaultProfile` comments `CraftedMods` as `[modKey] = true (permanent
unlock, same shape as CraftedWeapons)`, and `CraftingService` REFUSES to craft a mod you already own
— so a second copy cannot exist and quantity is not modelled anywhere. `EquipMod`'s duplicate guard
is scoped to one item deliberately (the same mod twice in one weapon's slots would double one
multiplier for no reason); across items it was never meant to apply.

Making mods scarce is a real change, not a one-line fix, and it is put to the user rather than
assumed: it needs a reverse index, because — as this file already notes — `EquippedMods` is keyed
`itemKey -> slot -> modKey`, so "where is this mod currently fitted" has no lookup. It also changes
the crafting economy (a second copy has to become craftable) and needs a rule for what happens when
a mod is fitted somewhere else.

**C13's question, answered: yes, robots take mods exactly as weapons do.** Same `EquippedMods`
structure, `EquipMod` accepts `tree = "Robots"`, slots 1-3, and robot mod slots are never locked.
One caveat worth knowing: `itemKey` is a robot TYPE, so every deployed Scrapbot shares one loadout.

**Three things the notes surfaced that are NOT round-6 regressions, and are now backlog:**

1. **A Combat/Ambush node auto-advances with the chest unclaimed.** User: *"make sure that whenever
   there is a chest on that node, to hold the player until they open or they choose to skip it."*
   This is loot silently lost to the single-exit auto-advance built on 2026-09-23 — the auto-advance
   does not know the room still has something in it. Real bug, not cosmetic.
2. **An ore pickup should say what you got.** User: *"whenever you get their drop, make a cute pop up
   appear showing how much you got and the ore icon."* Now cheap: the toast is already
   plate-shelled, and `HudKit.getItemIcon` already resolves ore art. Wants an icon slot on the toast
   (the factory has no icon support yet) or a small dedicated pickup popup.
3. **`AimCamera` warns `R15 rig: Waist MISSING, Neck MISSING` at boot.** Reported on C1, which
   passed — the shoulder camera and facing lock work, only the pitch waits on the joint. Harmless
   today, but it is the sort of warning that trains people to ignore Output.

**ASSET NOTE: the user has a VFX pack** (2026-09-25), intended for attacks and abilities later. Not
yet in the repo or Studio. When it lands, the existing pattern applies — a config of asset keys with
a placeholder fallback, the way `ItemIconConfig`/`UiIconConfig`/`SoundConfig` all work — rather than
referencing particles by name from service logic.

### THE AGREED PLAN, 2026-09-25 (end of session) — READ THIS FIRST AFTER A RESET

Two companion pages hold it, and they are the fastest way back in:

- **The Next Five Jobs** — the plan, with real `file:line` targets:
  https://claude.ai/artifact/Ni5SMuqXecy9Y6AbkM6xnw
- **Decoder Reveal Directions** — three drawn directions for the case-opening reveal:
  https://claude.ai/artifact/BtKK6rtg7X5dq4GfxH6oQv

**The user's own ordering, verbatim:** mods countable → decoder rework (sketches first) → sound
hookup summary → the chest fix → the ore pickup popup. **My recommended ordering differs and is on
the plan page:** the chest first, because it is silently destroying loot while the rest is polish.
Confirm with the user before reordering their list.

**DECIDED: mods become countable.** "built once, use once per gun, so if u want u gotta have
multiples to fit different guns, so have them have a counter." The spec is on the plan page; the
facts behind it, which took a scout pass to establish:

- `CraftedMods[key] = true` today (`DataService.lua:228`), written in exactly ONE place
  (`CraftingService.lua:137`), and crafting REFUSES a duplicate (`:98`) — which is why a second copy
  cannot currently exist. That rejection has to go for any of this to work.
- **`backfillMissingFields` will NOT convert `true` to `1`.** It fills missing fields only. This
  needs a one-time self-guarding migration on the `migrateLegacyWeapons` pattern
  (`DataService.lua:271`) or every existing save gets a mod count of `true`.
- **There is no reverse index.** `EquippedMods` is `itemKey -> slot -> modKey`, so "how many copies
  of this mod are in use" must be counted by walking it. One shared helper — the server gate and the
  UI badge must not disagree.
- `WeldingPanel.lua:1395` does an explicit `== true` and breaks the moment the value is a number.
  `ModPicker.lua:30` iterates owned mods and should grey out ones whose copies are all fitted.
- **`ModConfig.ApplyMods` needs no change** — it reads modKey strings out of the slots table and
  never touches `CraftedMods`, so the stat maths is untouched.
- The Welding panel ALREADY badges a mod with how many slots carry it; that becomes `fitted/owned`.

**ALL FOUR QUESTIONS ANSWERED, 2026-09-25 (late session).** Supersedes the "FOUR QUESTIONS
OUTSTANDING" list below.

**1. Decoder: DECRYPTION, restructured by the user. CORRECTED 2026-09-25 — an earlier version of
this entry described the model WRONG; this is the right one.** Full spec and three diagrams:
https://claude.ai/artifact/BtKK6rtg7X5dq4GfxH6oQv

**The model, exactly.** A case starts at **Common** — not at a rarity rolled from the case's weight
table, which is what the wrong version said. Across the decode there are exactly **four upgrade
windows**, because four is what Common → Mythical requires. Each window is a **time RANGE, not a
fixed moment**, specifically so the schedule cannot be learned. When a window fires it rolls once:
*go up one tier?* A hit climbs one and the panel shows the new rarity; a miss changes nothing and the
next window is a fresh attempt at the same step. **Only the rarity is ever shown, never the item.**

Then **the reel can upgrade you again.** It rolls the rarity you earned, but an upgrade slot may be
hidden in the strip; landing on it makes the reel shake, grow and recolour, then re-roll one tier
higher — and that can chain. Reel odds, the user's numbers: Common→Rare 20%, Rare→Epic 5%,
Epic→Legendary 1%, Legendary→Mythical 0.1%.

**There is no upgrade slot to land on.** The server rolls the upgrade first and, on a hit, tells the
client to PLANT an upgrade card at the landing position. A client that genuinely chose where the reel
stopped could be made to stop wherever it liked.

**THE NUMBERS ARE NOT SETTLED, AND THE REASON IS STRUCTURAL — read this before picking any.** With
the chances as first discussed (60/25/5/1 from Common), **Mythical comes out at 0.01%** — one in ten
thousand, against 8% today. Reaching Mythical means passing EVERY gate, so its probability is the
four chances MULTIPLIED. The consequence, which no amount of retuning removes: **you cannot have a
rare Mythical and a rare Legendary at the same time.** Anything generous enough to make Mythical
reachable floods Legendary on the way past. Modelled, not guessed — the Markov run is in the session
and reproduced on the page.

**The lever that works: a per-case STARTING TIER.** Instead of everything starting at Common, a
Blackline opens already at Rare (three gates left) and a Prototype at Epic (two). That also does the
job the old per-case weight tables were doing, so replacing them costs nothing. Illustrative only —
the right way round is for the user to name the outcome (what fraction of Blacklines should end
Legendary, and Mythical) and solve the gates backwards from it. Guessing gates and seeing what falls
out is exactly how the 0.01% happened.

**RECOMMENDED NUMBERS, solved 2026-09-25 — keep today's payouts, change only the presentation.**
The gates below reproduce the CURRENT `CaseConfig` rarity tables to the decimal, so the ladder ships
as a pure presentation change. The argument for doing it this way: retuning the reveal and the reward
economy in one move means that when something feels wrong afterwards you cannot tell which half did
it. Feel the mechanic first, retune second.

| Case | Starts at | Gates (chance to climb one tier, per window) | Produces |
|---|---|---|---|
| Scavenged | Common | 6% / 6% | C78 R20 E2 |
| Encrypted | Common | 18% / 20% / 15% | C45 R38 E15 L2 |
| Blackline | **Rare** | 26% / 28% / 34% | R30 E40 L22 **M8** |
| Prototype | **Epic** | 20% / 22% | E40 L40 **M20** |

Solved by grid search over the 4-window Markov chain, not estimated. The script is trivial to redo:
four windows, each rolling "advance one tier?" against the gate for the tier you are currently on.

**SUPERSEDED BY THE USER, 2026-09-25: every case can reach Mythical, scaling with tier.** The user's
call — "lets make the chances for higher cases better as well". This REPLACES the keep-today's-payouts
recommendation immediately above, which is kept only for its reasoning. **This is a deliberate
economy change, not just a presentation change** — Scavenged and Encrypted can now produce tiers they
never could.

| Case | Starts at | Gates | C | R | E | L | M | decode per Mythical |
|---|---|---|---|---|---|---|---|---|
| Scavenged | Common | 14 / 16 / 26 / 34 | 55 | 34 | 9 | 2 | **0.2%** | ~1000 min |
| Encrypted | Common | 29 / 29 / 35 / 51 | 25 | 42 | 24 | 7 | **1.5%** | ~467 min |
| Blackline | **Rare** | 32 / 30 / 27 | — | 22 | 42 | 28 | **8%** | ~187 min |
| Prototype | **Epic** | 21 / 22 | — | — | 40 | 40 | **20%** | ~50 min |

**TWO FINDINGS THAT SHAPED THESE, both worth keeping — they are traps, not preferences.**

**1. The cheap case's Mythical rate has to be measured in DECODE TIME, not in percent.** The user
first proposed 1% for Scavenged. At 1% a Scavenged costs ~222 minutes of decode per Mythical and a
Blackline costs ~187 — effectively identical. Since bays are limited (3) and decode time is therefore
the real bottleneck for a dedicated player, premium currency would buy almost no throughput advantage
and Blackline would stop being the Mythical case in any meaningful sense. 0.2% restores a ~20x spread
across the four cases. **Always check the time-per-outcome, not the per-case percentage** — the
percentages look graded when the throughput is flat.

**2. Legendary and Mythical cannot sit close together on a low case.** Targeting L 2% / M 1% on
Scavenged made the solver put the LAST GATE AT 100% — i.e. "reach Legendary and Mythical is
guaranteed". That is degenerate, and it is forced by the structure: Mythical is reachable only
THROUGH Legendary with one window left, so the final gate is pinned by the ratio between them. Rule
of thumb that came out of it: keep M at roughly a tenth of L on the low cases, or the last gate stops
being a gate.

**Prototype stays at 20%, NOT the ~10% floated.** 10% would be a cut from today's 20%, and it would
leave Prototype only 1.9x better than Blackline per unit of decode time while costing real money.
Flagged to the user as a probable misremembering rather than applied silently; revisit if they
confirm they meant to lower it.

Solved by coordinate descent over the 4-window Markov chain, not estimated. Two solver bugs worth not
repeating if this is redone: a full 4-gate grid search does not finish in any reasonable time, and a
descent whose STEP shrinks while its SCAN RANGE does not will hang on the late passes.

**A property worth keeping on purpose, which fell out of the arithmetic rather than being designed.**
Blackline's gates RISE as you climb (26 → 28 → 34). Starting at Rare means three upgrades across four
windows, so there is a spare window, and the later gates have fewer remaining attempts to land in —
which forces them to be kinder. The consequence: **a case that reaches Legendary late in the decode
still has a real shot at Mythical.** The ladder gets more generous exactly when there is least time
left. Do not "fix" the rising numbers; they are doing something.

**THE KNOWN WEAKNESS, accepted deliberately: Scavenged.** At 6%/6%, **78% of Scavenged cases never
move at all** — two minutes, four windows, nothing. Because only the rarity is ever shown, a failed
window is invisible, so the mechanic does nothing for the cheapest case most of the time. Two honest
options: accept it (it is the grind case, it is short, and a climb becomes a real surprise), or
loosen Scavenged ALONE as the one deliberate economy change. **Recommendation: accept for now** —
ship against known numbers, then retune one case rather than four. Revisit after the first playtest.

The reel's hidden upgrades sit on top of all of this and nudge every distribution very slightly
upward (Epic→Legendary 1%, Legendary→Mythical 0.1%) — too small to compensate for in the gates.

**Pity: cases only.** The reel has none, but a reel upgrade landing on Legendary or Mythical RESETS
it — the good outcome arrived, so the mercy rule has done its job whichever system delivered it. Two
counters proposed, Legendary and Mythical separate, because with one a steady trickle of Legendaries
would keep resetting it and the Mythical floor would never arrive.

**Three bays**, each visitable, explicitly so it is something to run while offline — the user's
words: "smth people do it while offline yk?, they seem to like that".

**Still open:** whether the user accepts the solved gates above (recommendation: yes) and the
Scavenged weakness with them; whether the four windows sit at the same fractions for every case (a Scavenged decodes
in 2 minutes, a Blackline in 15 — same fractions scaled is the simple answer); and one pity counter
or two.

Consequences for the code, unchanged by the correction: `DecodeJob`/`DecodedCase` are SINGULAR on the
profile and both become collections (a save-shape change, so a real migration, not a backfill);
DISCARD is a new action needing a refund rule (proposal: no refund, no cost, you just free the bay);
and rush gets strictly stronger once nobody rushes a bad case.

**2. A mod already fitted elsewhere: REFUSE, then OFFER TO MOVE.** The user's answer, and better
than either option I put up: "refuse it first, make a pop up, and ask the player if they would like
to remove it from that gun and put on the new one." So the refusal states where the copy is, and the
confirm moves it — no silent stat loss on a weapon the player is not looking at, and no wasted trip
to go unfit it manually. Use `HudKit`'s existing modal/stacked-panel layer; do NOT hand-roll a
dialog.

**3. Duplicate mods STACK in one gun. "double the benefit, double the counter."** Two copies of Heavy
Rounds in one weapon apply the multiplier twice and consume two of the owned count. This REVERSES
the existing guard at `CraftingService.lua:296` ("Already equipped in another slot"), which exists
because stacking used to be free; with counts it stops being free and becomes a real three-slot
choice. Delete that guard as part of the counter work, and make sure `ModConfig.ApplyMods` genuinely
multiplies per slot rather than deduplicating — it walks `pairs(equipped)`, so it should already.

**4. Pity counter: YES.** Lives along the bay strip as `CRACKED 7 / 10`, always visible, and when it
is ready the floor STARTS one rung up instead of at the bottom. Numbers not chosen yet.

**FOUR QUESTIONS OUTSTANDING, all on the plan page.** Do not guess at these:

1. **Which decoder direction** (01 Decryption / 02 Shatter / 03 Salvage Rig). Blocks the rebuild.
   My pick is 01 and the reasoning is on the sketches page.
2. **Fitting a mod that is already on another gun — refuse or auto-move?** Building REFUSAL unless
   told otherwise: a silent stat loss on a weapon the player is not looking at is precisely the
   failure mode this project keeps hunting.
3. **Should two copies of one mod stack in one gun?** Refused today because it doubled a multiplier
   for free; with counts it stops being free and becomes a real choice. I would allow it.
4. **A pity counter for cases?** None exists. Blackline is the only Mythical source at 8%. Optional,
   changes the economy, the user's call.

**The decoder facts worth not re-deriving.** Decoding is a real-time job of 120s (Scavenged) to 900s
(Blackline), so the reveal is the payoff for a wait, not a slot pull — which is the argument against
the current CS:GO-style reel (`CasePanel.lua:419`, `drawReel`). Four cases; rarity order
Common/Rare/Epic/Legendary/Mythical; **Blackline is the only Mythical source in the game (8%)**;
duplicates of unique rewards refund half the case cost. All four case icons and every item icon are
uploaded except `CopperOre`, so a rebuild needs no new art.

**ASSET: the user has a VFX pack** for attacks and abilities, not yet in the repo. When it lands it
should follow the config-with-placeholder-fallback pattern (`ItemIconConfig`/`UiIconConfig`/
`SoundConfig`), not be referenced by name from service logic.

### WHAT TO DO NEXT

**Nothing from round 4 or round 5 is outstanding** — all nine checks passed, then all twenty did.
There is no committed-but-unverified work left in the repo. The list below is what remains
generally, in the order it is worth doing.

1. **SOUND — the system is BUILT, the assets are not.** `Shared/SoundConfig.lua` +
   `StarterPlayerScripts/Sfx.lua`, ~50 named entries all sitting at `Id = 0`, silent and warning
   once each. Three call sites wired (button hover/press, toast by kind, mining swing). **The next
   step is the user uploading audio and filling in numbers** — not more code. Wiring the remaining
   entries is one line each and should happen WITH the audio, not before it, so each one can be
   judged against how it actually sounds.
2. **The chest-skipped-on-auto-advance bug** — see "ROUND 6 RESULTS" above, item 1 of the backlog.
   Loot is being silently lost, which makes it the most valuable of the three.
3. **The ore-pickup popup** — see the same list, item 2. Cheap now the toast is rebuilt.
4. **Decide whether mods should be scarce** (round 6's C12). Currently one crafted mod fits every
   weapon at once, by design. The user flagged it as wrong; the change is not small. Their call.
5. **Studio-verify the 2026-09-25 fixes that came AFTER round 6 ran** — the four `SortOrder` rows,
   the raid shop's `dismissOnScrim`, and the three wired sounds (which are silent, so only their
   warnings are observable until assets land).
6. **The three other single-hop model lookups** named under the Scavenger head fix above
   (`BaseLaserService.lua:145`, `DroneService.lua:119`, `ProjectileService.lua:237`), if they turn
   out to matter.
7. **Raise `PLAYER_ATTACK_RANGE_SLACK` if enemy reach ever feels wrong again.** It passed at 2, but
   2 is deliberately tight and it is the first number to reach for, not the per-type `ContactRange`
   values.


### REPO STATE (2026-09-25, after round 4 closed)

- Branch `fix/audit-p0-p3`, tracking `origin/fix/audit-p0-p3`. Working tree CLEAN.
- **Everything is PUSHED as of 2026-09-25.** `origin/fix/audit-p0-p3` is level with local; there is
  no unpushed backlog for the first time in this branch's life. The user has standing authorization
  to have work COMMITTED; pushing stays theirs to approve each time — they authorised this one
  explicitly. Still no PR — don't open one unprompted.
- **`RaidConfig.DevFirstNodeType = "Shop"` is a TESTING setting that is currently live.** It only
  applies to a player holding the dev shortcuts, so it cannot affect a real player, but it should
  be revisited (set to `nil`) before launch rather than discovered later. Same for anything else
  gated on `DevShortcuts.Active`.
- **Checklists, newest first.** Round 4 (COMPLETE, all nine passed):
  https://claude.ai/artifact/PYwNs5vZ37zBZmsXH1psCT — round 3:
  https://claude.ai/artifact/JG4cBncHEgQY1QQGdZiUe3 — the exploit half (F1-F8):
  https://claude.ai/artifact/WSxQ7D47XQTFYBVc7k8e8v (round 6, 21 checks, OPEN — and the only one
  whose verdicts a session can read back) —
  https://claude.ai/artifact/5yNSs3qagi91T4TWP67fg7 (round 5, COMPLETE, all twenty passed). These
  pages exist so a round's verdicts outlive the conversation — but see the correction at the top of
  this section: only a page built on the `db` capability actually reads its ticks back to a session.
  All three above use `localStorage`, so their verdicts survive for the USER and a reset must ASK
  rather than read.

**Nothing is committed-and-unverified.** The eight exploit fixes were the last of it and they passed
on 2026-09-25. The paragraph that used to sit here tracked that backlog through three revisions —
first "nothing has been through Studio", then "rounds 3 and 4 passed but the exploit half didn't",
now empty. Keep the habit that emptied it: a round is a checklist page, run by the user, closed in
this file.

**Fixed after the first Studio test round (2026-09-23):**

- **Scorch Aura rendered as an upright dome beside the player, not a ring around them.** A Part with
  `Shape = Cylinder` has its axis along LOCAL X, so the disc's flat faces point along X and it
  stands on edge by default; the code rotated it 90 degrees about X, which spins a cylinder around
  its own axis and changes nothing visible. Rotating about Z lays it flat. With the 3-stud drop
  underneath, the old version read as a dome half-buried in the floor.
- **Scavenger headshots worked on some variants and not others.** `measureRestPoseHitbox` (which
  leaves the head OUT of the auto box so it stays hittable) and `ResolvePlayerHit`'s headshot test
  both hard-coded `Name == "Head"` case-sensitively, in two separate places. A variant whose head
  part was authored as `"head"` failed BOTH at once — the box swallowed the head and the shot that
  reached it did not count. One shared `isHeadPart` now, case-insensitive; a rig with no
  recognisable head warns once per model name, with a `NoHeadshots` opt-out on the EnemyConfig entry.
- **The health bar ticked +1 then -1 once a second, reported as "the Support Core isn't healing".**
  Roblox inserts a Script named `Health` into every character that restores 1% of MaxHealth per
  second — exactly +1/s at a 100 max. Invisible until `PlayerVitals` started owning the number, at
  which point the regen added a point and the mirror put it straight back, forever. Now disabled
  (not destroyed — `Disabled` is reversible, deleting leaves nothing to put back) for exactly as
  long as an activity holds the player, and re-enabled against both the character the activity
  started on and the one the player is wearing when it ends, since dying mid-raid replaces the body.
  Passive regen outside a fight is untouched. **This was masking the drone question entirely; the
  Support Core was subsequently confirmed working by the user.**

**Support Core heal rates, since this came up and will again.** It is **4% of max HP per 2-second
tick**, not per node — `DroneConfig.Support.Params.HealFraction` with `TickInterval = 2`. What
actually bounds it is the budget: `RaidRoomHealCap = 0.15` per room and `RaidMapHealCap = 0.75` per
map, both fractions of max health, both the user's call on 2026-09-22 so Heal rooms are not made
pointless. Base waves have no cap at all. It scales +25% per Research Tier above 3, which only makes
it reach the same cap faster. **Raising `HealFraction` therefore does almost nothing** — the cap
binds long before the rate does, and that is the knob anyone would instinctively reach for first.

**FIXED 2026-09-23 (committed, NOT Studio-verified): the damage-number colour collision.**
The diagnosis below is kept in full because it is the useful part — the fix is three paragraphs and
the reasoning is twenty. **What shipped: option 1, the fold.** The user chose it over the cheaper
`+N` grammar knowing it touches the combat path.

Reported twice as "crits are doing less damage than normal hits — the yellow numbers are lower than
the white ones". They are not crits, and nothing is miscalculating. Three separate mechanics are
wearing two nearly identical golds:

| what | colour | size | produced by |
|---|---|---|---|
| Headshot | `(255,220,90)` yellow | 26 | a hit on a part named Head, weapon with `HeadshotMultiplier > 1` |
| Crit | `(230,175,60)` gold | 28 | `RunBuffService.RollCrit` — Overclock Chip **Lv4+ only** |
| ScorchAura | `(255,110,40)` orange | 15 | the aura gear ticking |

The yellow numbers in the report are **AimBot's bonus hit**
(`UltimateEffects.lua`'s `OnHit.AimBot`). Every 3rd landed shot it deals
`ctx.Damage * (HeadshotMultiplier - 1)` — with the shipped `HeadshotMultiplier = 1.5` that is
**exactly half the main hit** — as a SEPARATE damage event tagged `"Headshot"`. So a 31 white and a
15 yellow are one shot: 31 + 15 = the 1.5x headshot. The yellow is lower than the white *by design*,
because it is a top-up rather than a replacement, and nothing on screen says so.

**And crits have almost certainly never fired for this player.** A crit requires an Overclock Chip
at Rare or better bought from a RAID shop (`RunBuffConfig.CritMultiplier = 1.5`; Lv3 gives 5%
chance, Lv4 10%, Lv5 15% plus a guaranteed crit every 5th shot -- retuned 2026-09-25, crit used to
start at Epic). Outside a raid `RollCrit` returns `false, 1`
unconditionally. There is no other crit source in the game. Confirmed by reading the whole path:
`spec.Damage = stats.Damage * damageMultiplier * critMultiplier`, applied once, never re-applied,
never inverted; a crit cannot come out lower than a normal hit.

**The actual defect is legibility, not arithmetic.** Four options were judged; the user picked the
first, the only one that changes the combat path:

1. **Fold the bonus into the main number** — **THIS IS WHAT SHIPPED.** One big number instead of two
   competing ones. The obstacle was real: the Ultimate hook fires AFTER `resolveAndApplyDamage` has
   already sent the main number, so it needed an ordering change in `ResolvePlayerHit`, not a retag.
2. Give bonus damage its own visual grammar — a `+15` prefix. Cheap, client-only, fixes the "why is
   my crit weaker" reading without touching combat. **Still available** if the fold misbehaves in
   Studio and has to be reverted.
3. Retag AimBot's bonus from `"Headshot"` to `"Ultimate"` (pink, which it genuinely is). One line,
   but it loses the "this was a headshot" read the effect is named for.
4. Nothing for AimBot; make crits legible instead.

There are 12 damage-number kinds and no legend anywhere in the game. **That root is still
untouched** — the fold fixes the one collision that was actually confusing a player, not the
absence of a legend. Worth revisiting if testers trip on the other eleven.

**How the fold works** (`CombatEncounterService.lua`, all of it commented in place).
`resolveAndApplyDamage` gained an optional trailing `feedbackBatch`; when one is present the
`DamageNumber:FireClient` is deferred into an accumulator instead. `ResolvePlayerHit` makes one per
hit, threads it through the weapon-behaviour context and the Ultimate ctx's `DealDamage`, and
flushes one merged number per enemy. The ~15 other call sites pass nothing and are byte-identical.
No damage math moved — only when the number reaches the screen.

Three things hold it up, and anyone touching this must not break them:

- **Keyed per ENEMY RECORD, not per shot.** Ricochet, Detonator and ExplosiveBow damage *other*
  enemies from the same shot and must keep their own numbers. Per-record keying gives that for free.
- **The batch is a fresh local**, never module- or player-scoped. A behaviour or Ultimate hook can
  yield; two players' shots sharing a batch would merge numbers that were never the same shot.
- **`flushFeedbackBatch` sets `Closed` before firing anything**, so a `DealDamage` deferred past the
  flush falls through to firing its own number rather than adding to a batch nobody will flush
  again — a dropped number, not a merged one.

**`ResolvePlayerHit` has TWO exits reachable after the batch exists** and both flush: the early
`return true` for a weapon with no Ultimate, and the final one. Missing the early one would silently
drop the damage number for *every non-Ultimate shot in the game* — if numbers ever vanish after a
future edit here, check that first.

Merged kind is the higher-priority of the two: `Crit > Headshot > Explosion > Ultimate > Normal`. A
crit is the rarer, bigger roll and wins the label; AimBot's bonus correctly promotes a plain hit to
Headshot, because 31 + 15 *is* the 1.5x headshot.

**What to watch for in Studio:** a merged number where two used to stack (AimBot equipped); a single
number per hit on a weapon with no Ultimate; and Ricochet/Detonator/ExplosiveBow still showing
separate numbers on each distinct enemy.

**AGREED NEXT WORK, in this order (the user chose it, 2026-09-23):**

1. ~~Auto-advance a single-exit node with a travel transition~~ — **BUILT.** `RaidConfig
   .AutoAdvanceSeconds`/`AutoAdvanceBlockedTypes`, `autoAdvanceTo` in RaidRoomService, travel wipe
   in RaidClient. Shop and Heal excluded; Start routes through the same rule.
2. ~~End-of-run stats screen, Sonic-style staggered reveal, multiplier last, Continue to extract~~ —
   **BUILT.** `RunSummaryPanel.lua`. Run duration, kills, damage dealt and best room are all newly
   tracked. A clean Extract HOLDS the player in the room until Continue (timeout
   `RaidConfig.SummaryTimeoutSeconds`); Defeat and Abandon tear down first and show the numbers over
   the base. That hold opened a loot dupe, now closed by making `settleRunLoot` idempotent.
3. ~~Retrofit the rest of the raid HUD's toasts and popups to the new style~~ — **BUILT.** Smaller
   than it sounded: `RaidClient`'s own `showToast`, the room panel title, the boss pick and the
   summary screen were already on tokens. What was left was four near-identical hand-rolled
   `TextLabel`s in `roomBody` (room description, interaction hint, "Fully healed.", boss-clear loot
   summary) differing only in text/colour/italic and a stray 13-vs-14 size — now one `noticeLine`
   helper beside `progressBar`, on `FONT.Body`/`TEXTSIZE.Label`, fading in 0.18s Quad Out like the
   summary rows. Plus the travel wipe's `GothamMedium`/`GothamBold` routed through
   `FONT.DisplayMedium`/`FONT.Display` (they were literally those tokens' own fallbacks, so it picks
   up Montserrat for free), `actionButton` onto `FONT.BodyBold`, and `progressBar`'s bare `10`
   named `TRACK_HEIGHT`. The damage-number half of this task is recorded above.

**With step 3 done, the three-task raid flow list is COMPLETE.** The polish pass below (UI in-place
updates, self-maintaining boot check, the one explicit disconnect) is still unstarted and was agreed
before any of this.

---

### SECOND STUDIO TEST ROUND, 2026-09-23 — 12 of 17 passed, 4 fixes shipped

Checklist, with the user's own notes on each check, at
https://claude.ai/artifact/JG4cBncHEgQY1QQGdZiUe3 (a retest group R1-R4 was added on top for the
fixes below; A-E are the original pass and stay as the record).

**The fold is VERIFIED.** A1/A2/A3 passed, including A2 — a weapon with no Ultimate still shows one
number per hit, which is the early-return flush in `ResolvePlayerHit` doing its job. That was the
change most likely to break something and it didn't.

Of the five flags, three were passes with a note attached. Two were real bugs. All four resulting
changes are committed and **not yet re-verified**:

- **Headshots were the only gameplay bug** (reported twice, as A4 and D2 — one defect). See the
  correction below; this was the second attempt at it.
- **Scorch Aura lagged the player.** Fixed by welding, NOT by the CFrame change that looked right.
- **Raid entry now raises the Sector Map** instead of auto-advancing (`Start` added to
  `AutoAdvanceBlockedTypes`). A design change the user asked for, not a bug.
- **The Plated Vest shield is drawn in blue on both HP bars.** The mechanic was never broken.

**Two wrong diagnoses worth remembering, because both were plausible and both would have shipped a
fix that changed nothing:**

1. **The aura's lag was replication, not maths.** The proposed fix was absolute-vs-relative CFrame.
   But the ring was `Anchored` and repositioned from a SERVER Heartbeat, so its position crossed the
   network before the client saw it — both CFrame forms arrive on exactly the same schedule. No
   server-side loop can fix this. Welding hands position to the client's own physics. **`OrbitBlades`
   has the identical lag and is deliberately unfixed**: a weld is a fixed offset and the blades
   orbit, so there is no static C0. Its fix is a client-side visual, still to do.
2. **The Plated Vest shield was never broken.** Because F3 had just moved player HP into
   `PlayerVitals`, "the new damage path doesn't consult the shield" was the obvious suspect — and
   wrong. `damageTarget` subtracts the shield at the top, before the `PlayerVitals.Damage` call, and
   the server already broadcast `Shield` on every combat tick. MainHud simply had no listener on
   `RaidRoomUpdate` and threw all three fields away. Reading the one function beat reasoning from
   the change log.

**THE HEADSHOT CORRECTION — the general lesson, not just the fix.** The first attempt made head-part
name matching case-insensitive. Correct, and not the problem. The real cause: every auto-hitbox
enemy carries a `Hitbox` Part with `CanQuery = true`, sized ONCE from the rest pose with heads
excluded, welded to the root. The rig then animates. On many walk-cycle frames the head sits inside
that still volume, so the ray stops on `Hitbox` and `isHeadPart(hitInstance)` scored a body hit —
which is why it looked random. It was the walk cycle.

Rather than re-cast past the hitbox (which would have kept the failed assumption alive with a
workaround bolted on), **the question changed: not WHICH PART stopped the ray, but WHERE ON THE
ENEMY it landed.** `record.HeadPart` is cached at spawn and read LIVE at hit time, so the threshold
animates with the head. A cached rest-pose offset would have been the same bug in a new shape.

Deliberately NOT done, so nobody "fixes" these later: `measureRestPoseHitbox` still excludes the
head (including it would resize every enemy's hit volume), and a rig with no head part still cannot
be headshot at all — a fallback zone from a fraction of body height would silently make every
headless enemy far more vulnerable to bows. The comment at the test says what an explicit opt-in
would look like.

**Two dev shortcuts were added this round, both to make testing possible at all:**

- `RaidConfig.DevFirstNodeType` (now `"Shop"`) — every first-pickable node becomes this type for a
  player holding the dev shortcuts. Was hard-coded to `"Boss"` inside `applyDevBossFirst`, which is
  why the first node was always a boss. Set it to `"Boss"` to test the card pick again, or `nil` to
  switch it off. Raid start only, not on map regeneration.
- `/giverunbuff [Key|all] [Rarity] [Level]` — grants a run upgrade directly, defaulting to the
  item's highest rarity and that rarity's level cap. Skips the shop's one-step-per-purchase pacing,
  which is the point; still honours `RunBuffConfig.Slots`, because the HUD draws a fixed number of
  slot tiles.

**Still open from this round:** B2 (whether the four retrofitted notice lines fade — the user
couldn't tell which text was in scope, and the answer is the room description, interaction hint,
"Fully healed." and the boss-clear line; everything else in that panel was never touched), and
`OrbitBlades`' replication lag.

**Also worth knowing for whoever picks this up:** the F4 caps (`RunProgressionMaxStep = 10`,
`MapGrowthCap = 4.0`, `RunProgressionMaxExtraEnemies = 3`) are balance numbers chosen during the
exploit fix, not numbers the exploit dictated. They bound the curves; where they bound them is still
open to retuning.

---

**STEP 0 — ADVERSARIAL EXPLOIT REVIEW: DONE, 2026-09-23.** The user's instruction, verbatim: "i want
u to approach the game as an exploiter/hacker, i want u to have malice, your goal will be to break
the game, make smth happen that shouldnt, see what you can do, and then u report back to me and tell
me what u find so we can add it to the plan" — an adversarial review of the game's own owner asking
for a pass before it goes to testers, distinct from the security checklist that had already passed:
that checklist asked "does each handler validate, gate, rate-limit and re-derive?" and every handler
said yes; an attacker instead asks what the rules ALLOW that the designer never pictured, and those
are different questions that find different bugs. Full findings report, with the attack steps and the
negative results (what does NOT work and why) that the checklist alone couldn't surface: "Breaking
Salvage Protocol", https://claude.ai/code/artifact/UkMW3M9KMJ8H7m8G1pYt7A.

Eight findings (F1-F8), all fixed the same day:

- **F1** — `InteractHeal` took an optional `node` argument and every gate sat behind
  `if typeof(node) == "Instance"`, so `InteractHeal:InvokeServer(nil)` skipped them all and handed
  back a full heal, from anywhere, every 20s. Fixed with `PlayerActivityService.Get` (refuses in ANY
  activity) plus a real `NodeType = "Heal"` node within the new `NodeConfig.InteractDistance` (60
  studs). See `NodeService.lua`'s `InteractHeal`.
- **F2** — `EndExpedition` was the same free full heal, on only a 3s cooldown, callable mid-raid.
  Now refuses while the caller holds any activity, and while anyone is mid-`OutpostRaid`.
- **F3** — player HP lived only on the client-owned Humanoid, so a modified client could never die
  and a Raid Room's `PendingRewards` (only lost on `Health <= 0`) could never actually be lost. New
  module `PlayerVitals.lua` (server-only utility, same category as `RateLimiter`/`CombatMath`) keeps
  the server's own HP copy, bracketed by `PlayerActivityService.TryAcquire`/`Release` so tracking
  exists exactly while an activity does; outside an activity it's a deliberate pass-through to the
  Humanoid (mine lava, base lasers, idle healing unaffected). Every player-damage/heal/death/
  MaxHealth site in the codebase now goes through it.
- **F4** — raid rewards scaled with run length uncapped, and Combat rooms never applied the run
  multiplier to enemy strength the way Ambush/Boss did. Fixed with `RaidConfig.RunProgressionMaxStep`
  (10, caps the multiplier at 2.2x), `ExtractionRewards.MapGrowthCap` (4.0, reached at the 10th
  clear), Combat rooms now passing `composition.Multiplier * runMultiplier`, and a modest new
  enemy-COUNT ladder (`GetRunProgressionCountBonus`) — see the correction on "Spawn zones +
  difficulty curves" above for exactly what this does and doesn't replace.
- **F5** — `EquipMod` bounded its slot index but never required a whole number, and a fractional
  slot created an extra one. Fixed to match the integer check `TurretService.PlaceTurretInSlot`
  always had.
- **F6** — the Expedition queue is one shared lane for the whole server; `SkipNode` and
  `RegenerateExpedition` could destroy the node another player was mid-fight in, which `runRaid`
  reads as a penalty-free cancel. `PlayerActivityService.TryAcquire` gained an optional `subject`
  plus `IsSubjectBusy`/`AnyActive`; both destroy paths now refuse.
- **F7** — `MineNode` and `MineShaftHit` paced off the same tool-swing time under two different
  `RateLimiter` keys, so alternating them mined at double rate. Both now share one key, `"MineSwing"`.
- **F8** — `MineShaftConfig.ResetBlockThreshold` raised 5,000 -> 15,000; the counter is global and a
  reset ejects everyone in the shaft, so the threshold is also the price of forcing that.

Also verified clean, recorded so nobody re-checks it: attributes are never client-writable
(`DashInvulnerableUntil`/`RunBaseMaxHealth` were never exposed, since Attributes replicate
server->client only); no grant site yields between its check and its payout; raid teardown can't
double-pay; combat rooms can't be re-entered for loot; `SellOre`/`StartSmelt` argument validation is
complete; every activity acquires and releases on every exit path; `RequestFireWeapon` is sound;
admin is UserId-based.

**ALL EIGHT ARE NOW STUDIO-VERIFIED (round 5, 2026-09-25) — every check on the checklist passed.**
The sentence here used to read "Nothing in this pass is Studio-verified yet", and stayed true
through two days and two unrelated rounds before round 5 finally ran it. It was also inserted AHEAD of the three-task
polish pass below, not in place of it — that pass was agreed and scoped first, on the same day, and
is still exactly where it was left.

**THE POLISH PASS — ALL THREE ITEMS BUILT 2026-09-25, NONE STUDIO-VERIFIED.** See "SIXTH SESSION"
above for what each one turned into. The scope below is kept as written because it is what was
agreed, and because two of the three grew a complication worth reading before touching them again.

Originally: **AGREED 2026-09-23, NOT STARTED.** The user
approved this scope and then cleared the session so it could be executed from this file. Three
read-only audits (security, efficiency, memory) ran first; their verdicts are recorded below the
task list. Do the tasks, commit each, and DON'T widen the scope — the user explicitly chose
"UI rebuilds + hygiene" over a deeper refactor, because the game enters its testing phase next and
breaking working systems now is the expensive mistake.

1. **UI in-place updates — the one real performance finding.** Three panels destroy and rebuild
   their entire grid on every update, and they update constantly during normal play:
   - `StarterPlayerScripts/RaidShopPanel.lua:770-779` (`renderCards`) and `:781-802`
     (`renderSlots`/`renderEscapeChips`) — every card and slot tile is destroyed and rebuilt when
     ANY run value changes (Scrap, ore-at-risk, slots used), several times per raid room.
   - `StarterPlayerScripts/InventoryPanel.lua:806-822` (`renderInvList`) — destroys EVERY inventory
     tile on every `InventoryUpdate` (fired from `MainHud.client.lua:3062-3065`). Looting one ore
     rebuilds hundreds of frames.
   - `StarterPlayerScripts/InventoryPanel.lua:390-393` (`rebuildInvDetailSlots`) — same pattern,
     smaller grid.
   Fix: reuse the frames. Keep a pool keyed by whatever identifies a row (item key / offer id /
   slot index), update text, colours, sizes and visibility in place, and only create or destroy
   when the SET of things actually changes. Card visuals live in `RunCard.lua` now and are shared
   with the boss pick — if `RunCard.build` grows an update path, both callers must keep working,
   and the shop must stay pixel-identical to `design/raid-shop/*.dc.html` (the user approved that
   design and asked for 100% loyalty to it).
2. **Make the boot check self-maintaining** (`ServerScriptService/Main.server.lua:85-115`). It
   currently warns "service module(s) exist but are NEVER required" off a HAND-TYPED copy of the
   require list, which had already drifted: `BaseLaserService` is genuinely required at line 23 but
   missing from the copy, so it warned about a working feature (Tier 4+ base security lasers —
   read its header; nothing is wrong with it). Worse, the failure is asymmetric: someone who adds a
   name to the copy but forgets the real `require` gets silence, which is exactly the hang-forever
   bug this check exists to catch. Fix: record what actually loaded — e.g. a small `load(name)`
   helper that stamps a set and returns `require(Services[name])`, used for every require in this
   file — so the check can never disagree with reality. Keep `INTENTIONALLY_UNLOADED` for the
   deliberately-retired files.
3. **Explicit disconnect for the per-respawn health-bar connection**
   (`StarterPlayerScripts/MainHud.client.lua:2715`, `humanoid.HealthChanged:Connect`). Not a leak —
   Roblox drops it with the destroyed Humanoid — but it is the only connection in the client made
   per character without being stored, and the codebase's discipline is explicit teardown.

**Audit verdicts, 2026-09-23 (read-only, no changes made):**
- **Security: clean.** Every remote in `default.project.json` was checked for argument validation,
  plot/station/distance gating, rate limiting and server-side reward derivation. No exploitable
  findings. Spot-verified by hand afterwards rather than taken on trust: `RequestExtractRaid`
  (requires `ExtractUnlocked` and not `InCombat`), `ChooseRaidNode` (verifies the node is connected
  to the current one), and `RaidRoomAction`'s "Buy" (rate-limited, offer resolved from
  `state.ShopOffers`, spends `RunCurrencyCollected`, never the profile).
- **Memory: clean.** Per-player tables clear on `PlayerRemoving`/cleanup, encounters destroy their
  enemies and effects, `blockOwner`/`cells` clear both per-block (`MineShaftService.lua:606`) and on
  reset (`:864-865`), and gear visuals are destroyed on sell, room change and run end.
- **Efficiency:** only the UI rebuilds above. The mine's per-block ClickDetector/Highlight, the
  polling loops (depth, hazard, energy, auto-miner), the tree sway and the gear Heartbeat were all
  examined and are either already tight or a documented tradeoff. `MiningCooldownBar.lua` was called
  out as the pattern to copy: it connects Heartbeat only while active and tears it down after.

**After the polish pass**, the roadmap is unchanged: turret models (the user's own Blender work) →
sound, music and weapon effects → the testing phase. Deep verification of the raid shop's mechanics
(rarity-up, insurance on death, gear damage, boss card stats) is deliberately deferred to that
testing phase — the user's call.

**Session of 2026-09-22/23 — what was built (all committed, this is history, not a to-do).**
Everything below in this block is committed. The roadmap block right after this one (labeled
"Older" now) is still the live sequence for what comes next.

1. **Raid shop rework — COMPLETE, verified by the user in Studio.** "i tested myself and it looked
   fine." All 4 cards render, all 12 icons are uploaded and live (`UiIconConfig.Icons` —
   `src/ReplicatedStorage/Shared/UiIconConfig.lua:89-102`, every entry non-zero), drawn at
   `ICON_GLYPH_SIZE = 58` inside the 76-stud icon plate (`RunCard.lua:197-202`) after the user found
   the mockup's original 40 too small against the uploaded PNGs' own built-in margins. The 4
   equipment slots, Sell (50% refund), the Extraction Beacon, and Salvage Insurance all work as
   spec'd. **Boss cards now use the exact same card** — `RunCard.build` (`RunCard.lua`, the whole
   file) is shared by `RaidShopPanel.lua` (the shop screen) and `RaidClient.client.lua`'s boss pick
   (`RaidClient.client.lua:502-672`, the `bossPick` IIFE) — the boss screen is titled "BOSS DEFEATED"
   / "CHOOSE ONE REWARD", offers 3 cards (`RaidRoomService.lua:1823`,
   `RaidConfig.RollCardChoices(3)`), each with a **TAKE** button and a "STACKS · NO SLOT" footnote in
   place of the shop card's pip row. This was the last piece of the shop rework the user asked for
   ("after that the shop rework will be done") — it is done.
   **Deliberately DEFERRED, the user's call:** deep verification of the actual mechanics (rarity-up
   math, Insurance's payout on a real death, gear damage numbers) — "for those things we gotta do the
   testing phase first before anything." Don't chase these as bugs before the testing phase; the UI
   and the wiring are confirmed, the numbers underneath are not yet.

2. **HudKit panel layer** — `HudKit.LAYER` (`HudKit.lua:190-201`), `HudKit.openPanel`/`closePanel`
   (`HudKit.lua:1944`, `:2026`), `HudKit.isPanelOpen` (`HudKit.lua:1912`), a shared scrim, one
   non-stacked panel open at a time (opening a second closes whatever was open first, through ITS
   OWN `onClose` so it cascades correctly), plus a `stacked` option for pickers/detail-panels that
   need to layer over an already-open panel instead of replacing it. The rule this encodes, worth
   repeating because it's the whole point: **any menu that opens must draw over everything and block
   all other input.** `AimCamera.client.lua` (below) checks `Hud.isPanelOpen()` every frame specifically
   to give the mouse back while a panel is open. **New panels MUST route through `openPanel`/
   `closePanel`** — don't hand-roll a `Visible = true` toggle for a new menu.

3. **Mine visual pass** — chunky 12-stud blocks on a 16x16 grid (`MineShaftConfig.GridWidth`/
   `GridLength = 16`, `CellSize = 12` — `MineShaftConfig.lua:40-55`), same 192x192-stud footprint as
   the previous 32x32-at-6-studs version, just fewer/bigger blocks. **The user cut a matching hole in
   their map to it**, and the pit sits `ForwardOffset = 6` studs in front of the `MineShaftStart`
   anchor (`MineShaftConfig.lua:68-75`), centred left-to-right — that's what they built their hole
   to, don't shift it without telling them. Saturated, hand-picked ore colors over
   `Enum.Material.Metal` (Rock/Bedrock stay `Enum.Material.Rock`) so an ore seam reads from across
   the quarry (`MineShaftConfig.lua:195-214`, `MineShaftService.lua:410-468`). The guard rail around
   the Depth-0 edge is only 2 studs tall (`MineShaftConfig.SurfaceGuardHeight`,
   `MineShaftConfig.lua:102-109`) — it was briefly 8 (proportional to the bigger blocks) and the user
   hit the real problem immediately: "rn u gotta jump in order to get into the mines and i dont want
   that." `MAX_MINING_DISTANCE`/`CLICK_DISTANCE` are both 24 studs
   (`MineShaftService.lua:71`, `MineShaftController.client.lua:47`) and the depth raycast reaches -40
   (`MineShaftService.lua:824`). **The reset counter is now a world-space `BillboardGui` sign**
   floating over the pit (`MineShaftService.lua:228-309` builds it, `:316-335` updates it) — 120x30
   studs, 40 studs up, a hot-orange pill bar with a big count and deliberately no caption (a "MINE
   RESET" line under the bar was too small to read at the distance the sign is actually seen from).
   **The top-centre HUD bar (`MineResetBar.lua`) and the `MineResetUpdate` remote were built earlier
   in this project and then DELETED** when the sign replaced them (removed from
   `default.project.json` too) — don't rebuild either; every reader of reset progress is now a plain
   Instance property this file sets directly.

4. **Aim camera** (`AimCamera.client.lua`, the whole file, + `Shared/AimCameraConfig.lua`) —
   over-the-shoulder while a gun is equipped: the camera slides to `ShoulderOffset`
   (`AimCameraConfig.lua:23`), the character turns to face wherever the camera looks so movement
   strafes instead of steers (`AimCamera.client.lua:383-395`), the torso pitches with the camera's
   vertical aim split between the Waist and Neck joints (`AimCamera.client.lua:396-417`), the mouse
   locks to screen centre with the icon hidden, and a 4-tick crosshair appears
   (`AimCamera.client.lua:135-146`). Released the instant a HudKit panel opens
   (`AimCamera.client.lua:374-378`, `Hud.isPanelOpen()`), without a full disengage, so re-opening the
   crosshair on close is instant. **Two traps hit while building this, worth remembering:**
   - A statement starting with `(` immediately after a call's closing `)` is Luau's "Ambiguous
     syntax" PARSE error, and a parse error means the *whole script* silently never loads — no
     camera, no warning, nothing in Output pointing at why. `tweenCameraOffset`
     (`AimCamera.client.lua:269-284`) works around it by holding the tween in a local and calling
     `:Play()` off that, rather than chaining off the constructor call directly.
   - The joint lookup must SEARCH descendants for the Waist/Neck Motor6Ds, not look them up by
     expected parent (`Head.Neck`/`UpperTorso.Waist`) — the first version did the latter, found
     neither, and concluded the rig "wasn't R15" on a rig that **was** R15
     (`AimCamera.client.lua:179-200`, see the comment on `findLookJoints`). It also has to tolerate
     either joint arriving on the character LATE (`attachJointWatcher`,
     `AimCamera.client.lua:204-228`) rather than only sampling once. My own wrong guess that the rig
     might be R6 cost a round trip before the real cause (parent-based lookup, not rig type) was
     found.

5. **Dash i-frames** — `DashConfig.IFrameSeconds = 0.3` (`DashConfig.lua:49`), stamped as a
   `DashInvulnerableUntil` Player attribute the instant a charge is actually spent (not on the
   rate-limit or empty-tank rejection paths — `DashService.lua:167-186`), read via
   `DashService.IsInvulnerable(player)` (`DashService.lua:133-136`). **Only honoured in the raid
   damage path** — `CombatEncounterService.safeIsInvulnerable`
   (`CombatEncounterService.lua:731-740`, called at `:1378`) is the only caller. **NOT honoured by
   mine Lava touch/burst damage or by `NodeService` outpost chip damage** — those are different code
   paths and don't check the attribute. This is noted here as a known/deliberate gap for now (also
   recorded in "Known interim decisions" below and in "Stamina & dash"), not something to extend
   without being asked.

6. **Mining cooldown bar** (`MiningCooldownBar.lua`, the whole file) — replaced the "Swinging too
   fast — wait for your tool to reset" toast with a quiet, almost-transparent grey bar just under the
   top of the screen that drains right-to-left and fades out. `Remotes.MineFailed` now takes a second
   `kind` argument (`MineShaftService.lua:683` fires `"Cooldown"`), and `MainHud.client.lua` skips the
   toast specifically for that kind (`MainHud.client.lua:3092-3100`) while every other rejection
   (wrong tier, too far, bedrock, lava) still toasts as before. **Took three attempts, and the lesson
   is worth keeping:** it must be a FRAME-DRIVEN STATE MACHINE (two booleans and a clock,
   `MiningCooldownBar.lua:83-164`), not `TweenService` tweens — a cancelled tween's `Completed` still
   fires, so fast clicking desynced the "is it visible" flag from what was actually on screen under
   the first two attempts. The other rule: **clicking must NOT restart a bar that's already
   running** (`MiningCooldownBar.Start`, `MiningCooldownBar.lua:169-192`) — the bar answers "how much
   longer until I can hit again," and restarting it on every click would answer that with a lie (a
   full bar for a cooldown about to end).

7. **The user's roadmap, still in order** (unchanged from the "Older" block below except items 1
   and 2 are now done): ~~Boss card redesign~~ DONE (item 1 above) → ~~Mine visual pass~~ DONE (item 3
   above) → **turret models** (the user's own Blender work — "i could make some models later but its
   all good for now"; placeholder neon gear visuals stay until then) → **cleanup of the game +
   security patches** — IN PROGRESS: three read-only audits are running right now (safety,
   efficiency, memory); a plan will be written to disk BEFORE any fix lands, per the
   step-back-when-a-fix-repeats/greenlight conventions → **sound/music/weapon effects** → **the
   testing phase**.

**Older — the user's ROADMAP after the shop, given 2026-09-22, in their order (kept for the
record; items 1-2 are now DONE, see the block above — the sequence for items 3-6 is still live).**
Do them in this sequence unless they say otherwise; each is its own job, and the greenlight rule
still applies:
1. **Boss card redesign** — the post-boss pick still renders as plain coloured buttons
   (`RaidClient.renderCardChoices`). Rebuild it with the SAME card look as the raid shop, which is
   the last piece of the shop rework ("after that the shop rework will be done"). DONE — see the
   NEWEST block above.
2. **Mine visual pass.** DONE — see the NEWEST block above.
3. **Turret models.** (The user will make gear/turret models themselves later — "i could make some
   models later but its all good for now". Placeholder neon gear visuals stay for now.)
4. **Cleanup of the game + security patches** — `sp-remote-scout` sweep is the obvious opener.
5. **Sound and music, plus weapon effects.**
6. **Then the game enters its testing phase.**

The icons landed 2026-09-22: all 12 shop icons are uploaded and live in `UiIconConfig` (commit
66be115), drawn at `ICON_GLYPH_SIZE = 58` after the user found 40 too small. The user confirmed the
shop "seems to be going great" in Studio — cards, icons, tinting and the 3-4 roll all render.

**Raid shop rework: BUILT 2026-09-22, verified in Studio by the user** ("i tested myself and it
looked fine") **— see the NEWEST block at the top of this section for current status.** All five
BUILD CONTRACT steps below landed (commits fbb6c60, 789b958) — `RunBuffConfig.lua`, `RunBuffService.lua`,
the combat hooks in `CombatEncounterService`/`DamagePipeline`, `RaidShopPanel.lua` + `RaidClient`
wiring, and this README pass (`sp-docs-dev`, this session). Known platform deviations from the approved mockup, worth knowing before anything gets
reported as a bug: Roblox `TextLabel`s have no letter-spacing equivalent, so the mockup's tracked-out
headers render tighter than the reference; the full-screen shop background is a 65% scrim
(`BackgroundTransparency = 0.35`) rather than a solid takeover, so the raid room stays visible behind
it on purpose; badge text (**NEW**/**RARITY UP**) pads itself with literal leading/trailing spaces
around the string rather than CSS padding; the pip "glow" ring on a level-up pip is a second `UIStroke`
layered outside the first, not a CSS box-shadow; and dashed pips/slot borders (`HudKit.dashedBox`) are
straight-edged dashes, not the mockup's rounded dash caps. Two numbers to watch in the first playtest:
`FIRE_RATE_COOLDOWN_TOLERANCE = 0.9` in `CombatEncounterService.lua` (a guessed 10% grace on the
fire-rate cooldown to absorb the client/server timing gap around Rapid Feeder's buffed rate — may need
retuning either direction) and `beginAmbush`'s `RunBuffService.OnRoomCleared` call, which fires once
PER WAVE inside the wave loop, not once for the whole Ambush node — so Nano Repair's room-clear heal
should trigger after every wave of an Ambush, same as a real Combat room, not just once at the end.
Also: `RaidConfig.Modes.Standard.ShopCatalog` (`"ShopCatalog"`) is now dead data — Shop rooms roll from
`RunBuffConfig.Items` instead — left in place for `sp-config-dev` to remove or repurpose rather than
deleted mid-build. **UPDATE: the icons landed 2026-09-22** — all 12 `UiIcons` images (9 perk/gear
icons, 2 Escape icons, the Scrap glyph — see README's icons paragraph for the exact key list) are
uploaded and live in `UiIconConfig.Icons`. The three optional `ServerStorage.RunGearModels`
(`ScorchAura`/`OrbitBlades`/`LaserDrone`) are still not placed — placeholder neon visuals cover them.

**Below this point is the DESIGN ROUND that produced the spec above — kept as the record of what was
agreed and why, not as a to-do list anymore.**

**Raid shop rework — SPEC SETTLED 2026-09-22 (the user's answers; numbers marked ~ are placeholders).**
- **Direction: a MIX** — mostly run perks, plus escape items. Scrap-only prices (settled earlier).
- **Stock rotates:** each Shop room rolls **3-4 random offers** from the pool. No fixed menu.
- **Shown as CARDS**, pretty — "i want the design of the game to look good". Card mockup gets agreed
  before building (build-the-reference-exactly rule).
- **Rarity tiers Rare / Epic / Legendary set the LEVEL CEILING:** Rare max Lv3, Epic max Lv4,
  Legendary max Lv5. Buying the same item again = +1 level, up to your rarity's ceiling. Buying a
  HIGHER rarity of an item you own keeps your level and raises the ceiling ("a rare at level 2, then
  you find legendary at the shop, you upgrade your current one to legendary at level 2"). At Lv5
  (Legendary max) it can't be bought again. Rarity colors: reuse `ModConfig.Rarities`.
  - OPEN, my assumption until the user says otherwise: rarity changes ONLY the ceiling, not the
    per-level strength; a lower-rarity card of an item you own at a higher rarity still gives +1 level.
- **Perks (stack by level):** damage boost, fire rate boost, more max HP, healing, shield, loot
  multiplier.
- **Healing has ITS OWN cap**, separate from the Support Core drone's 15%/room / 75%/map (user's call).
  Cap numbers not given yet.
- **Run GEAR (all three wanted):** a damage AURA ring around you; ORBITING BLADES; a LASER DRONE
  attached to you that auto-shoots nearby enemies. Assumed to level 1-5 like perks.
- **Escape:** Extraction Beacon (leave now as a clean extract, keep ore) and Salvage Insurance (keep
  part of your ore if you die).
- **Stakes switched ON with this round:** raid ORE is lost on Defeat AND Abandon; only a clean
  extract keeps it. Currency stays exempt (existing rule). This is what gives the escape items a job
  — tag the ore loot entries `RunLocked` (settleRunLoot already honours it; chest ore via
  `RaidChestConfig.RunLocked`).
- **NO Permanent / carry-over items yet** ("do not do permanent stuff just yet"). When they come,
  the carry-over is a RARE MATERIAL tagged `Permanent`.
- Perks/gear live on the RUN STATE, not as inventory items, so no new `RunOnly` tag is needed —
  they end with the run by construction.

**Round 2 answers, same day:**
- **Card design APPROVED — build it 100% as drawn** ("be 100% loyal... make them the same as the
  reference"). Reference: artifact "Raid Shop Cards" https://claude.ai/artifact/7fQAAZjT5RXviqtB81UG1q,
  `project/Card.dc.html`. Icons must become PNGs in `ReplicatedStorage.UiIcons` (user uploads; I export).
  Fonts map: Montserrat → `FONT.Display`, Inconsolata → `Enum.Font.Code`, Source Sans → `SourceSans`.
- Rarity = level cap only (assumption confirmed). **Plus capstones:** every item gets a bonus passive at
  Lv4 and a signature capstone at Lv5 — so Epic reaches one, Legendary both. Per-item list proposed on
  the canvas, awaiting approval.
- **Heal cap: 25% per room / 100% per map**, separate from the drone's.
- **4 equipment SLOTS per raid.** Sell refunds 50% of what you paid. Escape items (Beacon, Insurance)
  take NO slot. A rarity-up of an owned item takes no new slot.
- **Boss cards: wire them in THIS rework.** `RaidConfig.CardPool` is 4 effectless stubs today (checked
  2026-09-22) — the user believed boss buffs already worked. They reuse the shop's run-buff system,
  stack WITHOUT limit and take NO slots ("limitless scalability that is not OP").
- **Capstone sheet APPROVED as drawn** (`design/raid-shop/Capstones.dc.html`). GREENLIT to build.

**BUILD CONTRACT (2026-09-22) — the shared shape every implementer builds against.**
Design references (copied into the repo so they survive): `design/raid-shop/*.dc.html` — `Card.dc.html`
is the card, `Main.dc.html` the shop screen + slot bar, `SlotsFull.dc.html` the full state,
`Capstones.dc.html` the item list. Build the UI from these EXACTLY (sizes, colors, fonts, pip states).

Build order (one implementer per file; each step's result feeds the next):
1. **Config** (`sp-config-dev`) — new `Shared/RunBuffConfig.lua`: rarity caps (Rare 3 / Epic 4 /
   Legendary 5), offer rarity weights, `OffersPerShop` 3-4, `Slots = 4`, `SellRefund = 0.5`,
   `ShopHealCap` 25% room / 100% map, `CritMultiplier`, and `Items` — the 9 levelled items + 2 escape
   items from the capstone sheet, each with Kind, Icon key, Price per rarity, per-level stats, Lv4/Lv5
   params and card display (label + value per level). Pure shared helpers the HUD and server BOTH use:
   `PreviewOffer(owned, offer, slotsUsed)` (new / +1 level / rarity-up keeps level / Maxed / SlotsFull)
   and `Aggregate(owned, bossCards)` (summed stat totals). `RaidConfig.CardPool` → real boss cards
   carrying the same stat keys (small, rarity-scaled, unlimited). Ore loot entries in `NodeConfig`
   (CombatTiers, BossLoot) and `RaidChestConfig.RunLocked.Ore` → `RunLocked = true`.
2. **Server** (`sp-server-dev`) — new `Services/RunBuffService.lua` (utility, no remotes): per-player run
   buff state (Begin/End, owned items with Rarity/Level/Paid, held escape items, boss cards, shop heal
   budget), stat queries for combat, gear tick, on-kill/on-damaged/fight-start/room-clear hooks, MaxHP
   apply/restore, `RunFireRateMult` Player attribute for the client. `RaidRoomService`: Shop rolls
   offers per visit (stored on state), `RaidRoomAction` "Buy"/"Sell"/"UseBeacon" through RateLimiter,
   boss "ChooseCard" applies the card, Lens multiplier in grantRunLoot + chest payout, Insurance in
   settleRunLoot (forfeit keeps KeepOrePct of RunLocked ore), lifecycle calls. `RaidChest.Arm`: per-run
   hold time + bonus item count.
3. **Combat** (`sp-combat-dev`) — `CombatEncounterService`/`DamagePipeline`: damage mult + crit on
   player shots, fire-rate cooldown uses the buff, damage-taken mult (elite/boss), Barrier shield via
   existing `playerState.Shield`, Vest Lv5 trigger, on-kill hook, gear ticking in the raid loop (placeholder
   neon visuals, optional `ServerStorage.RunGearModels`). Buffs are neutral outside a raid run.
4. **Client** (`sp-server-dev`, parallel with 3 — disjoint files) — new `StarterPlayerScripts/RaidShopPanel.lua`
   (the cards + slot bar, icons via `HudKit.applyIcon(…, "UiIcons")` with a placeholder fallback),
   `RaidClient` wiring + Use Beacon button + real boss card text, `CombatClient` reads `RunFireRateMult`.
5. **Docs** (`sp-docs-dev`) — README section 4 steps; UiIcons key list for the user's icon upload.

**Older — end of session 2026-09-22 (first session).** Everything below this block is older.

**Where to pick up: the Salvage Run RAID SHOP REWORK — agreed as the next job, NOT started, not yet
designed with the user.** Start it as a design round, not a build: ask, then build. What's already
known, so the round doesn't have to rediscover it:
- **Today's shop** is `NodeConfig.ShopCatalog` (NodeConfig.lua ~91): the same fixed ore bundles every
  run, no rotation — a vending machine selling the very resource you came to farm.
- **What it was meant to become** (Three Ways In, Salvage Run's column): "capacity and escape — bag
  upgrades, a speed boost, one-shot extraction beacons". Treat that as a starting suggestion — the user
  replaced the old enemy-AI plan wholesale when shown it, and may do the same here.
- **A catch to raise early:** "bag upgrades" assume a CARRY CAP, and there isn't one — checked
  2026-09-22, no ore cap is enforced anywhere in raid code. Likewise NOTHING in raids is `RunLocked`
  yet, so there is currently no risk for "escape" items to protect against. Both are Salvage Run
  stakes that were designed but never switched on; the shop's shape depends on whether they are.
- **Plumbing that exists:** the shop is a Heal/Shop-style `InteractPoint` room (`beginInteractGated`
  in RaidRoomService); a purchase's Grant goes through `addRunReward` (RaidRoomService ~1845), the same
  sink as all raid loot; it's paid for from the run's own currency pool (`state.RunCurrencyCollected`,
  Scrap/Cores earned this run).

**This session's work, ALL VERIFIED in Studio by the user and committed** (see the blocks below for
detail): enemy pathfinding + stuck detection + spacing; the awareness states (idle / wander / spotting)
+ the Raider alarm; every enemy gets a hitbox; the Staggered slow on heavy guns; the Support Core's
raid heal cap (15% per room / 75% per map); and raid chests (the user: "it works").

**Debt from this session:** README.md section 4 (the numbered Studio testing script) describes none of
it — no step for enemy pathing/spacing, awareness + alarm, the chest, or the heal cap, and no mention
of the new `ServerStorage.RaidProps` folder or the `EnemyAlarm` remote. Worth one `sp-docs-dev` pass
before release; not urgent enough to block the shop round.

**Raid chests — BUILT and VERIFIED 2026-09-22.**

**Raid chests — SPEC SETTLED 2026-09-22 (the user's words, then the numbers derived from them).**
- **Loot:** "regular loot" — 1 to 5 DIFFERENT items per chest. The chance of more than one falls off
  exponentially, 5 items ≈ 10%: weights 1:33.4 / 2:24.7 / 3:18.3 / 4:13.5 / 5:10.0 (ratio ≈0.74 per
  step, which is what lands 5 on 10%). Each draw is a distinct item, sampled without replacement.
- **Categories:** currency (Scrap) "more than not"; Cores "really rarely"; Contraband "even more
  rare"; ores through their OWN loot table, Voidium "hella rare". Amounts per item: currency 70-200,
  rare currency (Cores, Contraband) 2-5, ores 5-20.
- **Opening:** hold a button for 3 seconds.
- **Placement:** the game decides — never inside anything, and the chest is placed BEFORE enemies
  spawn. The user's answers to the asked numbers: a chest in ~50% of Combat rooms; 1-2 guards.
- **Guards:** NOT the Siegebreaker ("an elite unit i dont want to pop around every single time") —
  a Brute usually, sometimes another enemy. Guards must stay near the chest (a Brute's normal 90-stud
  roam would walk it off the post).
- **Stakes:** chest loot flows through the SAME grant paths as other raid loot, so Salvage Run's rules
  (ore RunLocked, currency exempt) hold — a chest that paid out differently would be a loophole.

**BUILT 2026-09-22, VERIFIED by the user the same day** — `RaidChest.lua` + `Shared/RaidChestConfig.lua`,
driven from `RaidRoomService.beginCombat` (inside its task.spawn, BEFORE `RunRaidCombat`), with a
`ServerStorage.RaidProps.Chest` slot for real art (placeholder crate otherwise). Implementation facts
worth keeping:
- **No raid drop is RunLocked yet** — checked against source: nothing in `NodeConfig`'s loot tables sets
  it. So chest ore is kept on death too, matching the room. `RaidChestConfig.RunLocked` has one switch
  per category for when Salvage Run's "ore is lost if you die" stake is actually turned on.
- **Placement's real guarantee is the walkable-path check** from where the player entered (no jumping):
  a clear flat surface alone would happily put a chest on a shelf or a roof.
- **Guards carry `GuardPoint`/`GuardWanderRadius`** through `explicitSpawns` → the spawned record →
  `EnemyAwareness.Init`, so they idle/wander around the chest (8 studs), not their own spawn.
- **A Combat room with a chest now passes BOTH `explicitSpawns` (the guards) and `spawnKeys`**
  (the room's normal ring). RunRaidCombat honours both — that path already existed for Boss escorts.
- **Bosses in base defense — already impossible, no change made.** `VoidwakenHulk` is only in
  `EnemyConfig.BossTypes`, which waves never read; a wave "boss wave" is an elite wave (Siegebreaker).

**The user's other answers, same round:**
- `ScrapCrawler` / `SentinelDrone` are NOT in the release patch — no behaviour to design for v1.
  `VoidwakenHulk`'s current behaviour is right; leave it.
- **Bosses are RAID ONLY** — the Voidwaken Hulk "should not even spawn in base defense", at least for
  now. That also answers the laser question: no boss ever reaches a base, so boss immunity is moot.
- Base models match their tier footprints — no config change needed.
- **PINNED NEXT, after the chest: the Salvage Run raid shop rework** (capacity and escape, replacing
  the fixed ore-bundle vending machine).

**Session 2026-09-21, ENEMY AI DESIGN ROUND.** (Superseded by the block above.)

**The user's enemy AI design — SETTLED 2026-09-21, SUPERSEDES Three Ways In's `Stalker`/`Guardian`/
`Screamer`.** Those three were never built; the user was shown what they were meant to be and
replaced them with their own, which fits the enemies the game actually has. Build this, not those.

Raids only for spotting/alarms (the user's call) — in a base-defense wave every enemy is there to
attack the base, so they stay aggressive and aware. The MOVEMENT fixes below apply everywhere.

| Enemy | Spots you from | Once it spots you | Raider alarm |
|---|---|---|---|
| `Scavenger` (the user says "salvagers") | FAR | runs straight at you | — |
| `Raider` | SHORT | raises the ALARM: calls everyone toward you, plus an effect and a sound on the player so they KNOW they were caught | raises it |
| `Brute` | normal | WANDERS the map; on spotting, behaves like a Scavenger | always answers |
| `Siegebreaker` | VERY short | behaves like a Brute | answers with 50% chance |

Unassigned, asked and not yet answered: `ScrapCrawler`, `SentinelDrone`, `VoidwakenHulk`.

**What this needs that does not exist:** an UNAWARE state. Today every raid enemy spawns already
targeting the player, so there is nothing for "spotting" to transition out of. Idle/Wander → Alerted
is the core new piece; detection ranges, the alarm broadcast and the 50% answer are config on top.
Wandering uses the default Roblox walk animation (the user's ask). Rooms must be big enough for a
detection range to mean anything — worth saying when the user builds rooms for this.

**The chest — recommended YES, not yet built.** Raid rooms have no physical loot, so nothing is worth
guarding and Siegebreakers/Brutes have no reason to be where they are. A lootable chest gives them
one. Opening it should take a few seconds (a hold prompt), which makes it an exposed moment. Contents
would be the room's `RunLocked` ore, which fits Salvage Run's existing stake. Shape still to agree.

**Movement fixes — AGREED as step 1, all enemies, raids AND waves.** The user's diagnosis, correct and
confirmed against source: there is no `PathfindingService` anywhere in `src/`; `Humanoid:MoveTo`
walks a straight line, so enemies grind into walls and wedge. Three parts:
1. **Pathfinding** — the ladder designed in "Movement ladder for the pathfinding" above and never
   built: clear raycast → walk straight; blocked → path, recompute throttled and STAGGERED across
   enemies; `AgentRadius` sized per enemy.
2. **Stuck detection** — moving but not closing distance forces a recompute. The user's own framing.
3. **Spacing** — the user's words: enemies keep "a sense of distance of one another and they dont
   get too close to each other unless necessary but they still try not to overlap". So separation
   that relaxes near the target (close in to attack when needed), never overlapping.
Wandering is NOT in step 1 — it is meaningless while every enemy always knows where the player is,
so it lands with the Unaware state in step 2.

**Order agreed:** (1) movement fixes → (2) Unaware/Wander + spotting + the Raider alarm → (3) the chest.

**Step 2 BUILT 2026-09-21, VERIFIED by the user 2026-09-22 ("looks pretty good")** — `EnemyAwareness.lua` + `Shared/EnemyAwarenessConfig.lua`
+ `EnemyAlarm.client.lua` + `EnemyAnimation.Ambient`. Raids, Combat rooms only (Ambush/Boss start
aware by design). Decisions made in the build, all the user's to overturn: Scavenger ANSWERS the
alarm (the user said the Raider calls "everybody"); alerted lasts the whole room; being damaged by
anything alerts; a Raider killed by the shot that would have woken it raises NO alarm (stealth kills
are rewarded); an answering Raider does not re-raise. Watch the `AwarenessState` attribute on enemy
models in a playtest. If a type T-poses while idling/wandering, its rig doesn't use R15 joint names
and the default animations can't drive it — give it its own Idle in EnemyConfig. Starting numbers:
sight Scavenger 110 / Brute 60 / Raider 35 / Siegebreaker 20; wander radius Brute 90, others 8-20.

**Also shipped 2026-09-21 after the user's first movement playtest:** every enemy now gets a hitbox
(only the Hulk had one — shots at any animated pose passed through the rest-pose mesh collision and
dealt nothing); a `Staggered` 13%/1.5s slow on the four Snipers-family guns + RailRifle + ArcCannon;
and `EnemyMovement.Hold` settles instead of nudging forever (the Brute that "never stops").

**Step 1 BUILT 2026-09-21, VERIFIED by the user 2026-09-22.** Follow-up the same day: agent size now measured from the body core, not the whole model — a spear made a Raider too "wide" for doorways and it got trapped inside buildings. Support Core drone heal capped in raids (15%/room, 75%/map of max HP), also verified. `EnemyMovement.lua` (shared utility,
`WalkTo`/`Hold`/`Stop`) + `Shared/EnemyMovementConfig.lua`; all three straight-line `MoveTo` sites
now route through it. Things to watch in the first playtest, and the one bug already caught:
- **Caught in review, before any test:** the line-of-sight cast was aimed at the goal's own Y. A
  wave's goal sits at the plot anchor's height, near the floor, so the cast hit the GROUND and read
  every open field as blocked — every enemy pathfinding constantly and draining the shared budget.
  Now cast flat at root height, sphere capped at 1.5 studs (a shapecast ignores whatever it starts
  overlapping, so a wide sphere would go blind to terrain it touches). Worth remembering for step 2's
  detection ranges, which are the same kind of cast.
- **`CombatEnemies` doesn't collide with itself on purpose** (so a crowd can't jam a doorway) — that
  is WHY enemies overlapped completely, and why spacing had to be steering, not physics.
- If `[EnemyMovement] X failed to compute a path` shows in Output, that type's goal is unreachable
  from where it spawned (inside geometry, across a gap) — the enemy still walks straight, so it's a
  room/spawn layout problem, not a crash.
- Every number is in `EnemyMovementConfig` — spacing too wide or tight, re-plans too slow, stuck
  detection too eager are all config edits.

**Earlier in this session (2026-09-21):**

**Gun hold poses — BUILT and verified working by the user.** `WeaponPoseConfig.lua` (Shared) maps a
weapon to a looping arm-only animation, resolved exact key → `Family` → `Default`, the same shape
`ItemIconConfig` uses. The user made FOUR poses (pistol/Salvage, Flamethrowers, Bows, Snipers);
`GrenadeLaunchers`, `Miniguns` and `Default` stand in with the Sniper pose and are marked STAND-IN in
the file — an unposed gun reads worse than a slightly wrong one. Playback is
`StarterPlayerScripts/WeaponPose.client.lua`, off the `WeaponTool`/`WeaponKey` attributes
`WeaponToolService` stamps on each Tool.

**The lesson from that build, worth more than the feature.** The first equip of a session visibly
played Roblox's DEFAULT tool hold before snapping to the real pose. Two fixes were shipped against
the wrong diagnosis ("the animation is still downloading"): adding the pose ids to the join preload,
then loading the `AnimationTrack` at tool-BUILD time instead of at Equipped. Both helped slightly,
which is precisely what should have falsified the theory — a missing animation plays NOTHING, not
the default hold. It was a RACE: equipping fires locally, where Roblox's own `Animate` plays
"toolnone" immediately, while a server-played pose has to make a round trip back. Playing it on the
client removed the gap entirely. Two follow-ups worth keeping:
- **Priority `Action2`, not `Action`** — one step above what Roblox's tool animations use, so ours
  wins outright instead of tying and leaving the result to blend weights.
- **Cosmetic-only client authority is fine here** and does not dent the server-authoritative rule: a
  pose grants nothing. What a weapon IS, and whether it may fire, never moved.
- The preload work was NOT wasted (the data is still fetched at join) — but it was not the bug, and
  shipping it twice before questioning the premise is the thing to avoid next time.

**Where the user is now:** tuning each gun Tool's `Grip`/Handle placement in Studio so the model sits
right in the posed hand. `ReplicatedStorage.WeaponTools` still needs all 18 real Tools (a Tool with a
`Handle`; no family shortcut — that is an icon/pose resolver feature only). Until one exists for a
weapon, equipping gives a grey placeholder box and a warn, by design.

**Still not started:** ENEMY AI variety — three patterns exist (`Chaser`, `Slam`, `Animated`), Phase
00 step 7 wants three new ones. Plus the `CopperOre` icon, and the two open questions below.

**Session 2026-09-20.** (Superseded by the block above.)

Shipped this session (all committed on `fix/audit-p0-p3`, NOT pushed):
- **Base lasers persist and kill enemies** — both of last session's open questions, answered by the
  user. New profile field `BaseLasersOn` (backfilled `false`), restored on the first base build of a
  session and written on each toggle. Enemies now die to an active laser: `CombatEncounterService`'s
  `spawnEnemy` tags every spawn `Enemy`, `BaseLaserService` walks up from the touched part to that
  tag and sets `Health = 0`, so the kill counts exactly like a gun kill. Robots still pass through.
  NOT yet verified in Studio. Two known gaps, both deliberate and unasked: a BOSS walking into a
  laser dies instantly (could trivialise boss waves — one line to exempt), and a laser only ever
  fires if it sits where enemies actually walk, since they stop at the base's edge to attack it.
- **`ItemIconConfig.lua`** — item icons can now be filled in from code, the way `UiIconConfig` always
  worked for chrome. Created because the alternative was the user hand-building ~44 ImageLabels in a
  Studio folder that git never sees. `HudKit.getItemIcon` resolves config → `ItemIcons` folder for
  the exact key, then the same pair for the weapon's `Family`; `applyIcon(..., "ItemIcons")` consults
  it too. The folder convention is untouched and still honoured.
- **The icon set is IN.** 52 uploads wired up: every item key but `CopperOre` (not drawn yet), plus a
  per-weapon `ScrapSMG`, plus all six `rig_*` robot line drawings and `raid_map_backdrop` — the last
  entries in `UiIconConfig` that were still `0`. Confirmed rendering in game by the user.
- **The loading screen preloads the icon configs.** Found by the user: icons still popped in blank on
  first hover/inventory open, because a bare number in a config is invisible to both the instance
  tree walk and the `rbxassetid://` string match. Resolved through each module's own `Get()` rather
  than a blind table walk — a walk would have to treat every number as an id, and an unset icon IS
  the number 0. Side effect worth remembering: the Skip button (5s) drops you in before the preload
  finishes, so "icons still pop in" during a test usually means the screen was skipped.
- **All six base models built and placed** (user, in Studio). The setup contract they were built
  against — exact `BaseTier1`..`BaseTier6` names, `ReplicatedStorage.BaseTemplates`, PrimaryPart =
  floor at Orientation 0,0,0, per-tier footprint, the `Laser`/`Button` prefix pair on T4+ — is on a
  companion page: https://claude.ai/artifact/CiMxwyJeMb6oPEFVzYZ98d

Lessons worth keeping:
- **An asset's uploaded NAME stops mattering once the ID lives in a config.** Three of the 52 were
  uploaded misspelled (`ScavangedCapacitor`, `BlackLine`, `Rig_ArcTurret`) and needed no re-upload —
  the key in the file is the contract, the asset name is just a label. This is a real advantage of
  the config over the Studio folder, where the instance's name IS the lookup.
- **`MarketplaceService:GetProductInfo(id).Name` in the command bar maps a pile of pasted asset IDs
  back to their filenames.** That is how 52 unlabelled IDs became a mapping without guesswork; worth
  reaching for again rather than asking the user to copy names one at a time.
- **Preload lists drift from render paths unless they share a resolver.** Same lesson as `Shared/`
  generally: the loading screen asking `Get()` is why a future icon source can't be silently missed.

**Where to pick up, none of it started:** (1) guns in the player's hand — `ReplicatedStorage.WeaponTools`
is still empty, and it needs all 18 as real Tools with a Handle (no family shortcut, that is an
icon-resolver feature); (2) a gun-holding animation for the player — the user is making the dash
animation already, so animation work is live; (3) ENEMY AI variety — three patterns exist
(`Chaser`, `Slam`, `Animated`), Phase 00 step 7 wants three new ones. Plus the `CopperOre` icon
whenever it's drawn (one number into `ItemIconConfig`).

**Open questions:** should a BOSS be immune to base lasers? Do the finished base models match the
per-tier footprint numbers in `ResearchConfig` (the "am I at my base" radius), or should those
numbers move to match the art? Both are asked and unanswered.

**Session 2026-09-17.** (Superseded by the block above.)

Shipped this session (all committed AND PUSHED on `fix/audit-p0-p3`):
- **Enemy attack animations read right.** With no Idle animation there was nothing underneath an
  attack track, so a swing ended by snapping the rig to its rest T-pose (obvious on the Raider,
  chopped the Brute's follow-through). Settled after three tries — hold the last frame, hold the
  first frame, both worse — on: a type with NO Idle keeps its Move track playing while it stands in
  range, and the swing fades out (`ATTACK_FADE_OUT` 0.15s) onto that walk. Filling an Idle slot later
  switches it back to Idle automatically, no code change. `EnemyAnimation.PlayAttack` also warns once
  if a type's Attack animation is longer than its `AttackCooldown`. User: works, reads better.
- **Base security lasers, Tier 4+** (`BaseLaserService.lua`, `BaseLaserClient.client.lua`,
  `BaseConfig.Lasers`). Owner-only ProximityPrompt on the base's button: ON = lasers visible and any
  non-owner player who touches one dies; OFF = invisible, non-collidable, harmless. Off by default
  each session (not persisted), players only (enemies/robots pass through) — both easy to change if
  wanted. Names are PREFIX matched, case-insensitively: anything starting with `Laser` (a `Lasers`
  folder, `Laser1`…) and anything starting with `Button` (`ButtonT4`, so T5/T6 need no code change).
  Turning them off also hides Decals/Textures/Beams/Highlights/SurfaceGuis on those parts — a Decal
  stays visible on a fully transparent Part, which is what the "one laser still showing" bug was.
  User: works.
- **`BaseService.BaseBuilt`** — a new BindableEvent fired after each base Model is parented. That is
  the hook for anything that has to wire up parts INSIDE a base and survive a tier rebuild; a Script
  inside the template can't, since the template lives only in Studio and wouldn't know its owner.
- **Join loading screen** (`src/ReplicatedFirst/LoadingScreen.client.lua`, and `ReplicatedFirst` is
  now mapped in `default.project.json`). Preloads every asset-carrying instance under Workspace/
  ReplicatedStorage/Lighting/StarterGui/SoundService plus every `rbxassetid://` string found in
  `EnemyConfig` (enemy animations are ids in config, not instances, so nothing else would preload
  them). Progress bar, Skip button after 5s, fades out when done. It cannot require `HudKit`
  (StarterPlayerScripts has not replicated yet) so it keeps its own copy of six colors — keep them
  matched on a palette retune. User: works.

Lessons worth keeping:
- **A base template with no PrimaryPart spawned upside down.** `PivotTo` uses whatever WorldPivot the
  model happens to have. `BaseService` now warns at build time naming the tier. Convention: PrimaryPart
  = the floor Part, Orientation 0,0,0.
- **A fully transparent Part still shows its Decals/Textures**, and a Beam can hang off a laser's
  Attachment while living elsewhere in the base entirely.
- **Holding a frozen animation pose reads worse than falling back to a looping one.** Tried both ends
  of the swing; the walk won.

**Where to pick up — unchanged from yesterday, none of it started:** (1) finish the remaining BASE
models; (2) guns in the player's hand (`ReplicatedStorage.WeaponTools` still empty — Tool-with-Handle
vs. a `Motor6D`-attached model, and mind the `RightGrip` lesson below); (3) a gun-holding animation
for the player; (4) ENEMY AI variety — three patterns exist (`Chaser`, `Slam`, `Animated`), Phase 00
step 7 wants three new ones.

**Open questions — ANSWERED 2026-09-18:** step 4 verified working in Studio, rewards granted;
Siegebreaker slam is good; `MoveAnimationSpeed` stays as is; the user will make the dash animation.
Laser state now PERSISTS (`BaseLasersOn` profile field) and lasers now KILL ENEMIES (via a new `Enemy`
tag set in `CombatEncounterService.spawnEnemy`) — both built 2026-09-18, not yet verified in Studio.

**Working from the laptop:** repo pushed to GitHub, place saved to Roblox cloud, so both machines can
work from either. The setup checklist (what syncs, what has to be copied by hand — the `.claude`
memory folder does not sync) is at https://claude.ai/artifact/3rdpvUEwfY7Z5oANABYDqu

**Session 2026-09-15/16.** (Superseded by the block above.)

Shipped this session (all committed on `fix/audit-p0-p3`):
- **Raid mode identity SETTLED and step 4 BUILT** (not yet verified in Studio) — see "SETTLED for
  step 4" in Phase 00's build order for the rules and the implementation map, and README section 4's
  "Extraction rewards" paragraph for the exact Studio test.
- **Every regular enemy animates.** Only the Hulk could before, and only through `AIPattern =
  "Animated"`, which refuses to start without attack animations. New: `EnemyAnimation.Locomotion`
  (Idle/Move/Death) and `EnemyAnimation.PlayAttack`, both driven by `EnemyConfig`'s `Animations`
  table and called from `EnemyAI.Patterns.Chaser` AND `.Slam` (Slam could not animate at all before).
  Walk + attack ids are in for Scavenger, Raider, Brute; Siegebreaker has walk + slam. Idle and Death
  slots are deliberately empty — the user is saving those for a post-launch update, "it feels good so
  it doesn't need".
- **`WalkFacingOffset`** (`EnemyConfig`, degrees; `EnemyAI.ensureFacing`/`aimFacing`) — an
  AlignOrientation aims the WHOLE model at its target plus a build angle. The Raider needs -60.

Hard-won lessons from this session:
- **These enemy rigs carry NO Motor6Ds in `ServerStorage`.** The engine builds them from each
  MeshPart's RigAttachments when the model enters the workspace. Six separate attempts to fix the
  Raider's facing AT a joint failed for that one reason (all reverted; see the `BodyYawOffset`
  commits). Anything that must work on these rigs has to work on the whole assembly instead.
- **Never hand the user a Studio script that DELETES anything** — deleting a rig's Humanoid scale
  NumberValues visibly broke a model, Ctrl+Z did not undo it, and their place auto-saves. See the
  memory file `studio-scripts-never-delete`.
- **Their models arrive needing rig repair**, and the same script fixes each: accessories welded
  where they sit (never snapped to Roblox's standard attachment spots — that moved hand-placed
  armour), held Tools joined by a `Motor6D` (not the `RightGrip` weld), collisions off on hair, and
  an `Animator` added under the Humanoid.
- **A scaled rig (theirs is 1.76) rescales gear on load** from an `OriginalSize` CHILD object, not
  only the attribute of the same name.

**Where to pick up — the user's own plan for 2026-09-16:** (1) finish the remaining BASE models;
(2) guns in the player's hand — `ReplicatedStorage.WeaponTools` is still an empty folder, so decide
Tool-with-Handle vs. a `Motor6D`-attached model, and note the Tool `RightGrip` lesson above;
(3) a gun-holding animation for the player (the player has no animation system of its own yet —
`DashConfig.AnimationId` is the only existing hook, and it is still `""`); (4) if that lands, ENEMY
AI — the user: "rn they are pretty simple and superr dumb". Today there are three patterns total
(`Chaser`, `Slam`, `Animated`); `DESIGN_NOTES`' own Phase 00 step 7 wants three NEW ones picked for
VARIETY, and `EnemyAI.Patterns` is a flat named table precisely so each is one function plus one
config line.

**Open questions, none blocking:**
- Step 4 needs its Studio pass, and its numbers (`RaidConfig.ExtractionRewards`) are unplaytested
  placeholders — payout ranges, +35% per clear, +0.25 per boss, x2 cap.
- Does the Siegebreaker's slam animation fit inside `SlamWindup` (0.9s)? Raise the windup if not.
- Do the Brute/Siegebreaker need a `MoveAnimationSpeed` (they are the slow ones)?
- The rest of the original Salvage Run stakes layer — `RunLocked` ore, a carry cap, a physical
  Extraction room — is still unbuilt and was never discussed. Step 4 works without it.
- The dash animation id is still unpasted (`DashConfig.AnimationId = ""`).

**Session 2026-09-14/15.** (Superseded by the block above.)

Shipped this session (all committed and pushed on branch `fix/audit-p0-p3`, NOT merged to `main`):
- **The Hulk fights.** `AIPattern = "Animated"` / `EnemyAnimation.lua`: animation-marker hits
  measured from `FistR`/`FistL`, a Sweep window, refresh-not-stack slows, AlignOrientation turning
  about his body, server network ownership, hold-ground `AttackRadius` 50 / `ContactRange` 40, speed
  bursts, a config-sized `Hitbox`, `NoCollide`, `HipHeight` 12, `FacingYawOffset` -90, `MoveSpeed` 21.
  All numbers in `EnemyConfig.BossTypes.VoidwakenHulk`, each tuned live with the user. User: works.
- **Boss escort** (minions in Boss-room SpawnZones, interim tier count) — user: works.
- **Boss health bar** (`BossBar.lua`, "Boss" tag) and a HudKit pass over the raid HUD.
- **Admin shortcut:** an admin's raid opens on Boss nodes.
- **Stamina & dash** (`DashConfig`/`DashService`/`DashClient`/`StaminaState`) — user: works.
- **Raid overhaul step 2 verified; step 3 (mode plumbing) built, NOT verified in Studio.**

Hard-won lessons from this session, each cost real time:
- **New Remotes in `default.project.json` need `rojo serve` RESTARTED** — Rojo reads the project file
  only on start. And never `WaitForChild` a remote at the top of a boot-list service: it stalled every
  later service and the player didn't even spawn on their base.
- **Config edits only apply on a fresh Play** — a running test keeps the values it loaded.
- **A skinned mesh animated out of its rest pose keeps REST-pose collision** → needs a `Hitbox`.
- **Per-frame root CFrame writes fight a Humanoid's walk** (he crawled at any WalkSpeed); turn with
  a constraint instead. And set `SetNetworkOwner(nil)` on server-driven NPCs.
- **An internet outage (DnsResolve) looks like broken animations and a floating boss** — no
  animation loads, the rig shows its rest pose. Rule it out before tuning.

**Where to pick up:** (1) Step 3 VERIFIED in Studio by the user (2026-09-16, "step 3 all good").
(2) Step 4 is BUILT but NOT verified — see its entry in Phase 00's build order, and README section 4's
"Extraction rewards" paragraph for the exact test. (3) Paste the dash animation id when the user has it. (4) Offer
a PR from `fix/audit-p0-p3` to `main` — nothing from this session is on `main`.

**START AT "Road to release" NEAR THE TOP OF THIS FILE, not here.** That section is the live plan for
the whole project now; this one is the record of the HUD phase-3 round, which is finished, shipped
and verified in Studio. Phase 00 is now DONE — the raid overhaul is designed (three modes, physical
exit doors, room variants) and written up on the "Three Ways In" page linked from that section.

**HOLD (2026-09-06).** The user is designing several systems ahead of the build and asked to wait
for an explicit greenlight before starting any further step of the build order below. Report status
and stop; "pick up where we left off" is NOT the greenlight. Design work, docs and questions are
fine.

**SESSION OF 2026-09-09 → 09-10 — six commits, then the VoidwakenHulk art pipeline. READ THIS
ENTRY FIRST. It supersedes the art status in the older entries below: Raider, Brute and Siegebreaker
are no longer missing.**

Commits, all on `fix/audit-p0-p3`, none pushed:
- `43af692` — admins get infinite Energy outside a Player Test Session
  (`RaidEnergyService.HasInfiniteEnergy`). The old inline admin bypass in ExpeditionService's lever
  is gone; it skipped raid rooms and stayed on inside test mode.
- `63e1f6f` — enemy variant folders draw from a shuffled bag per folder (`drawVariant`) instead of an
  independent roll: every variant once before any repeats, and no back-to-back repeat across a
  reshuffle. `HasModelFor` uses the new `collectVariants`, so an existence check never burns a draw.
- `8e0f3da` — elites roll into raid Combat rooms: `EliteChance` on
  `RaidConfig.CombatTierComposition` (0 / 0.20 / 0.35 by Tier), SUBSTITUTING one rolled enemy.
  Ambush passes none. Closes a gap the pool split left: nothing on the raid side read `EliteTypes`,
  so the Siegebreaker's raid dodge was unreachable.
- `b2dfe4d` — **raid navigation is the Sector Map again; exit doors are OFF**
  (`RaidConfig.ExitDoorsEnabled = false`), reversing Decision 2 at the user's call. Doors stay in the
  authored rooms, sealed (solid and invisible). The map un-collapses itself when a choice opens, and
  collapsing now goes to the TOP-right (it used to stay at right-centre because only Size changed).
- `42e1ad4` — admin dev shortcut: a forced elite in every fight (raid Combat, every Ambush wave,
  every defense wave). It changes the spawn list only, NOT the wave's `isElite`, so boss-wave loot is
  untouched. New shared utility `Services/DevShortcuts.lua` (`Active(player)` = admin and not in a
  test session); `HasInfiniteEnergy` delegates to it. Authored-SpawnPoint rooms are covered by
  `ensureEliteInPlacements`.
- `2e8f963` — the shortcut reports what it actually did: `[Admin] ... forced an elite`, or a warn
  naming the exact `ServerStorage.EnemyModels` path it couldn't find, plus
  `[DevShortcuts] <name> — ON/OFF` (with the reason) whenever the gate flips.

**Confirmed by the user in Studio:** the Siegebreaker spawns under the forced-elite shortcut (after
the naming fix below). **Not yet verified:** infinite Energy; the shuffled bag's spread; the real
`EliteChance` roll with the shortcut off (`/admin off`, then Tier 2/3 rooms); map-click navigation,
auto-expand and collapse-to-top-right; the `[DevShortcuts]` OFF lines. README section 4 steps 15 and
24 cover these.

**Enemy art status.** Built in Studio by the user: Scavenger, Raider, Brute, Siegebreaker. Two
things cost real time and are worth not relearning:
- **Model names are exact and case-sensitive.** The Siegebreaker was first built as `SiegeBreaker`;
  `HasModelFor` quietly returned false and no elite could spawn. The `2e8f963` diagnostics are what
  surfaced it.
- **A rig that meets the documented contract (Humanoid + PrimaryPart) can still be unable to
  walk.** The Raider got stuck; the user fixed it without recording the cause. Likely causes, in
  order: an Anchored part; a prop with CanCollide wedging on geometry (every enemy part joins the
  `CombatEnemies` group, which only disables enemy-vs-enemy collision); or a PrimaryPart that isn't
  the HumanoidRootPart (`Chaser` measures distance from `model.PrimaryPart`, so a loose prop can
  freeze it in the in-range branch).

**VoidwakenHulk — THE ACTIVE WORKSTREAM. The Blender work is DONE; the Roblox work is next.**
- Source files live OUTSIDE the repo, and git does not back them up:
  `C:\Users\Carlin\Desktop\VoidHulk.blend` (Blender 5.1.1). The user was told to save
  `VoidwakenHulk_Color.png` (flat paint; its image datablock is named "MainBody Base Color"),
  `VoidwakenHulk_Baked.png` (the one for Roblox) and `VoidwakenHulk.fbx` beside it. Confirm the
  location if they aren't there.
- A skinned mesh: one mesh `MainBody` plus armature `Root`. **Bone names are a contract, because
  animations bind to them:** `Root` (Deform OFF), `Hips`, `Torso`, `Head`, `Shoulder.L`,
  `Upper_Arm.L`, `Lower_Arm.L`, `Hand.L`, `Shoulder.R`, `Upper_Arm.R`, `Lower_Arm.R`. There is no
  `Hand.R` on purpose: the arms are deliberately asymmetric (a massive pearl-rock right arm, a lean
  mechanical left one) because each is meant to behave differently as a boss mechanic.
- Weighted rigidly, one chunk per bone (Ctrl+P → With Empty Groups, then **L** + Assign at 1.0),
  which is the right method for a hard-surface model. UVs are Smart UV Project, Island Margin 0.02.
- Palette: pearl rock `#EDE9F3`; Voidium gem and veins `#8130F2` (hue-matched to
  `MineShaftConfig.OreColors.VoidiumShard`, 120/70/190, so it reads as the ore players mine);
  gunmetal body `#3A3D45`; eye dome near-black `#15161A`; orange accent rings; a red-orange spike.
- The bake: Cycles; material = paint × Ambient Occlusion (Distance 6), with the Multiply's Factor
  driven by a Map Range on HSV Saturation (0.25–0.4 → 1–0), so the saturated purple and orange skip
  the darkening. Previewed by wiring the Multiply straight into Material Output Surface, then baked
  with Bake Type **Emission** into `VoidwakenHulk_Baked`.
- **The copy already in the place, `(fixed2)VoildHulkV1`, predates the UV unwrap, so its UVs don't
  match the texture.** Delete it and `(Rough2)VoidHulk`, and import `VoidwakenHulk.fbx` fresh.

**Update at the very end of the session:** the user reports the Hulk is imported into Studio and "looking pretty", so steps 1–2 below appear DONE. Whether assembly (step 3) is done was not said — ask before walking through it, and don't make them re-import.

**Update, next session (2026-09-10 evening) — assembly DONE, float height and the move NOT done.**
- Done in Studio and seen in screenshots: Model `VoidwakenHulk` in **Workspace** holding `InitialPoses`
  (importer's; keep it, the Animation Editor uses it), `MainBody` (Anchored off, CanCollide off,
  Massless on; bones + `SurfaceAppearance` + a `Motor6D` named `RootJoint` made from the command bar
  with `C0 = r.CFrame:Inverse() * b.CFrame` so the mesh didn't snap), `HumanoidRootPart` (Part,
  unanchored, CanCollide on, torso-sized, Transparency still 0.5), `Humanoid` (RigType **R15**,
  RootPart resolved to HumanoidRootPart) with an `Animator`. Model `PrimaryPart` = HumanoidRootPart.
  The `AnimationController` is deleted.
- **Not done:** `HipHeight`, root Transparency → 1, and moving him into `ServerStorage.EnemyModels`.
- Measured in his current (upright) rest pose: 15.8 wide × 33.3 tall × 61.4 deep (the depth is mostly
  the right arm); root's bottom sits 17.8 studs above his lowest point.
- **At this size `Chaser` can never hit.** In a raid it tests the 3D distance from the root's CENTRE
  to the player's root against `ContactRange` (6, Construct default) + `ATTACK_RANGE_SLACK` (12) = 18,
  and his root is ~20 studs above a player's. The user chose to KEEP HIM FULL SIZE and solve it with
  the attack design below, not by shrinking him.
- **Agreed attack design (not built, needs the go-ahead):** the user animates each attack; in the
  Animation Editor they add an Animation Event marker on the frame the fist lands (names like
  `ImpactR`/`ImpactL`, a contract like the bone names). Server code plays the track, listens with
  `GetMarkerReachedSignal`, and on the marker damages the player if within a config radius of the
  FIST — the same shape as `Slam`'s impact check, but centred on the hand and timed by the animation.
  No Touched parts (the user's first idea was hand hitboxes; this replaced it). There is no
  `Hand.R` bone and a bone's position is its HEAD, so the right fist needs an `Attachment` (e.g.
  `FistR`) inside `Lower_Arm.R`, moved to the fist. Verify when building that the server sees the
  animated fist position, not the rest pose.
- **What the user is doing next:** re-posing him to LIE ON THE FLOOR (no legs) and making the attack
  animations. They were steered toward doing the lying pose as an idle ANIMATION rather than a new
  rest pose, because a new rest pose means re-exporting, re-importing and redoing the whole assembly
  above. Once the pose is settled, re-measure, then reshape the root block and set `HipHeight` to
  match — the numbers above are for the upright pose and will be wrong. The user will bring back
  published animation IDs + marker names.

**Update 2026-09-11 — the Idle is animated, imported and published.**
- **Idle animation ID: `rbxassetid://113796712422007`** (looping ON, priority Idle). Nothing plays it
  yet — the playback code still needs the go-ahead. The local `AnimSaves` copy was deleted on publish
  (the user has the Blender Action), so re-edits go through Blender → re-import.
- The lying-down pose is the Idle Action itself, as recommended; the rest pose is unchanged, so the
  Studio assembly stands. The Model's `Scale` reads **0.046** (shrunk after import); the idle still
  plays correctly at that scale. HipHeight / root block still to redo against the lying pose.
- **The pipeline that worked, repeat it for each attack.** Blender: one Action per animation, named,
  Fake User on; scene Frame Range covering the Action (the Idle runs 0–360); File → Export → FBX with
  Object Types = Armature + Mesh, Transform untouched, **Only Deform Bones OFF** (`Root` is Deform off
  and would be dropped), Add Leaf Bones OFF, Bake Animation ON with Key All Bones ON, NLA Strips OFF,
  **All Actions OFF**, Force Start/End Keying ON, Sampling Rate 1, Simplify 0. Studio: Animation Editor
  on the Hulk → ⋯ → Import → From FBX Animation with Rig Type Custom, **Rest Pose Source = Imported
  Rig**, **Scale Unit = Centimeter**, Scale Factor 1.0 → loop/priority → Save As → Publish to Roblox
  under the account/group that owns the game.
- For ATTACKS, keep the local copy on publish: the Impact markers are added in Studio's editor, so a
  fresh re-import from Blender loses them.
- **Pose convention (user's choice, Option A):** every animation starts AND ends in the Idle's lying
  pose (the first keyframe copied to the last), so crossfades between tracks stay invisible. No
  separate "ready" stance or wake-up animation.
- **Heavy attack (right rock arm) — published: `rbxassetid://137947497885396`.** Looping off,
  priority Action, local `AnimSaves` copy KEPT (the markers live in the Studio copy, not the FBX).
  It is a MULTI-HIT combo: several `ImpactR` markers for the earlier landings and one
  **`ImpactRFinal`** on the last, longer-wound-up blow, which is meant to hit harder. Confirmed
  count: **2 × `ImpactR`, then 1 × `ImpactRFinal`**.
- **Marker names are the strategy key.** Each marker NAME gets its own entry (damage, fist reach,
  slow) in the Hulk's config — the flat-table-of-named-strategies shape this repo uses everywhere —
  so a new named hit is a config entry, not a code change. `ImpactR`/`ImpactRFinal` today.
- **Light attack (left arm) is a SWEEP, not an impact — user's choice 2026-09-14.** A marker is an
  instant, so a single `ImpactL` would only catch players near the fist at that one frame. Instead the
  animation gets TWO events, **`SweepLStart`** and **`SweepLEnd`**; between them the server checks
  around `FistL` every frame, and each player can be hit AT MOST ONCE per swing. This is a second
  marker shape (a window, not a point) and needs its own small bit of server code alongside the
  `ImpactR` handling. Not built. **Numbers chosen by the user:** damage **8** per player per swing,
  reach **15 studs from `FistL`**, and it DOES slow. Slow amount/duration not given — proposed default
  is the regular-hit slow (40% for 1.5s, refreshes, never stacks); confirm when building. The 5.58s
  length is intended ("he is a slow guy"). Still needed: the published animation ID.
- **The Hulk's design, in the user's words:** the rock arm has a long wind-up and punishes greedy
  players; its hits SLOW the player, which is what balances his own very low speed. The slow is
  buildable today — `PlayerSpeed.Set(player, key, multiplier)` is the one authoritative owner of a
  player's WalkSpeed (`Services/PlayerSpeed.lua`), so a Hulk slow stamps its own key and clears it.
  **Numbers chosen by the user (2026-09-11):** damage 12 / 12 / 30 across the combo (~54 for the
  full thing; his plain ContactDamage is 22, the Siegebreaker's slam 42). Slow on EVERY hit —
  a regular marker slows **40% for 1.5s**, one tagged final/special slows **70% for 2.5s**.
  Fist reach: **20 studs on a regular marker, 28 on a final one** (the Siegebreaker's slam is 14;
  the user asked for "big but not too crazy" and 30 everywhere would have made the swing undodgeable
  while slowed). A hit landing on an already-slowed player **REFRESHES** the slow (user's call,
  2026-09-11) — it never stacks, so a three-hit combo can't pin the player in place.
  **Done in Studio (2026-09-11):** the fist points exist as Attachments — **`FistR` inside the
  `Lower_Arm.R` bone** (there is no `Hand.R`, and a bone's position is its joint, not the fist) and
  **`FistL` inside `Hand.L`** — both positioned on the fists in the standing rest pose. Hits measure
  from these, not from the bones. Nudging one in Studio retunes where a hit centres, no code change.
  **Flagged risk, accepted for now:** 70% puts the player at ~4.8 studs/s against his 10, for 2.5s,
  which is longer than his 1.6s AttackCooldown — so after a finisher he can close and swing again
  while the player still can't escape. If it plays badly, the least-invasive fixes in order:
  shorten the finisher slow to ~1.5s, soften it to 50-60%, or add a brief post-finisher window where
  he cannot hit.
- **BUILT 2026-09-14 (untested in Studio):** `AIPattern = "Animated"` → `Services/EnemyAnimation.lua`.
  Config lives on the Hulk's `EnemyConfig.BossTypes` entry: `Animations` (Idle/Move/Death), `Attacks`
  (weighted pick among those whose horizontal `TriggerRange`, default 30, covers the distance; he
  snaps to face the player on commit, `FacingYawOffset` fixes a sideways rig), and `AnimationHits`
  keyed by marker name (`Impact` = one check; `Sweep` = `<key>Start`/`<key>End` window, checked every
  Heartbeat, once per target). Walk ring `ContactRange = 15`; `AttackCooldown` counts from the END
  of an attack animation. A stun stops the swing. Hit damage × the spawn multiplier, like
  ContactDamage. Slow key `EnemyHitSlow`, token-refreshed. Fist position = the parent Bone's
  `TransformedWorldCFrame * attachment.CFrame`; **whether the server sees the animated pose is the
  open question** — `DebugHitboxes = true` answers it in one playtest. TriggerRange 30 / ring 15 are
  my guesses, not the user's; tune after seeing him swing. Empty ids/missing attachments warn once
  and degrade; no usable attack at all → plain Chaser with the fallback ContactDamage 22.
  **Waiting on:** the left sweep's published id (goes in `Attacks[2].AnimationId`).
- **User is DONE animating the Hulk (2026-09-14).** No death animation (`Animations.Death` stays
  `""`; he just goes limp/breaks and is removed 2s later) and no turn-in-place. Movement
  (`Animations.Move`) IS made: **Walk `rbxassetid://103708147649106`**. **Light attack (left sweep)
  published: `rbxassetid://105875185230848`.** All four ids are now in EnemyConfig.
- **First playtest (2026-09-14):** he was still in Workspace → moved to `ServerStorage.EnemyModels`.
  He spawned buried → **`HipHeight = 15`** (found live; now `EnemyConfig` `HipHeight`, applied at
  spawn, and `spawnEnemy` lifts the pivot by HipHeight + half the root so he doesn't visibly climb out
  of the floor). A "25" detour was judged during a DnsResolve internet outage where no animations
  loaded (rest pose reads as floating) — re-judge height only with Idle actually playing. Then
  **HipHeight 12** looked right with Idle playing. **Facing:** code-owned (AutoRotate off), found live
  via a `FacingYawOffset` Attribute → **-90**. The command-bar root rotation offered earlier was
  superseded by this; unknown whether the user ran it (if they did, -90 already accounts for it).
  Turning is per-Heartbeat at `TurnSpeed` 90°/s around the `Torso` bone (`TurnPivot`), and he only
  attacks within `AttackFacingTolerance` 30° of facing (the snap-on-attack was removed — user wanted
  less snappy). Walk plays at `MoveAnimationSpeed` 0.7 (user: "a bit too fast").
  **Hold ground (user's call):** `AttackRadius` 50 — inside it he doesn't walk, only turns and
  attacks; he walks once the player is beyond 50 and stops at `ContactRange` 40. Both attacks'
  `TriggerRange` raised to 50 to match. Flagged, not yet seen: fist reach is only 15–28 from the
  fist, so swings started from far out may miss by design unless his arms are that long.
  **Walk stutter fixed in code:** no enemy ever called `SetNetworkOwner(nil)`, so the nearest
  client simulated him and fought the server's MoveTo/turn — EnemyAnimation now claims server
  ownership. Attacks also wait until a started walk reaches the ContactRange ring, and the Move
  track follows the walk decision rather than measured velocity. (Other enemy types still don't
  set network ownership; nothing has reported stutter for them.)
  **User: "he is working" (2026-09-14)** → `DebugHitboxes` back to false. MoveSpeed 10 → **13**
  ("too slow"), crawl `MoveAnimationSpeed` 0.7 → 0.9 to keep pace.
- **Boss health bar + raid HUD tidy (2026-09-14, untested in Studio).** `spawnEnemy` tags any
  `EnemyConfig.BossTypes` model `"Boss"` with a `BossName` Attribute; `StarterPlayerScripts/BossBar.lua`
  (self-booting) finds it by tag and reads replicated `Humanoid.Health` — no remote. Top-centre
  plate, name + Mono HP readout, `COLOR.Bad` fill with a held damage trail; the room panel hides
  while it shows. RaidClient's Scraps readout, room panel shell, toast, Go Back To Base (`danger`)
  and Extract (`primary`) moved onto HudKit plate/button/tokens; the toast moved bottom-centre
  because it overlapped the room panel. Per-status room BODY content (Heal/Shop/BossCleared/card
  choice) still uses old fonts — deliberately left for a later pass.
- **Hitbox (2026-09-15):** he only took damage on his root — a skinned MeshPart's collision stays in
  its standing REST pose, so shots at the lying body passed through. `spawnEnemy` now welds an
  invisible, query-only, massless `Hitbox` Part to the root from `EnemyConfig` `Hitbox`, sized live
  by the user via `HitboxSize`/`HitboxOffset` Attributes: **Size (26, 18, 30), Offset (-18, -6, -5)**.
  (Config edits only apply on a fresh Play — a running test keeps the values it loaded; that cost a
  few rounds of "it isn't moving".) Same day: **AttackRadius 70 / ContactRange 60 / TriggerRange 70**
  (user: he still got too close to do anything), **MoveSpeed 15**, crawl anim 1.05. Then user: "works,
  just make him faster, add 10" → **MoveSpeed 25**, crawl anim 1.75. He now outpaces a player (16),
  so the "slows balanced by his low speed" design premise no longer holds — flagged to the user.
  **Then: raising MoveSpeed changed nothing** ("literally crawling") — so WalkSpeed wasn't the limit.
  Suspected cause: the per-Heartbeat `rootPart.CFrame` writes used for smooth turning fought the
  Humanoid's movement controller. Replaced with an `AlignOrientation` on the root (aimed each AI tick,
  `MaxAngularVelocity` = TurnSpeed). To keep "turn about his middle", the Hitbox is no longer
  massless: it outweighs the root, so the centre of mass (what physics rotates about) is his body.
  Also `NoCollide = true` (user asked; he snagged on stuff) — every part CanCollide false, HipHeight
  still holds him up. UNVERIFIED in Studio; if he still crawls, next suspects are the AttackRadius
  70 / ContactRange 60 band (he only ever walks ~10 studs before stopping) and Humanoid state.
  **Confirmed working by the user**; then MoveSpeed 25 → **21** ("4 less to make it perfect"), crawl 1.45.
- **"Spawn zones grey and not working" (2026-09-15).** Cause: the admin boss-first shortcut means
  every test lands in a Boss room, and `beginBoss` reads only `SpawnPoint`s (by design, Decision 7
  above: the Boss-room point IS the boss, zones are for the unbuilt escort). Zones were only hidden
  inside `collectSpawnZones`, which a Boss room never calls, so they stayed grey. Fixed: `buildRoom`
  now hides every `SpawnZone` at build for all room types. A change letting zones PLACE the boss when
  a Boss room has no SpawnPoint was written and REVERTED before commit — it contradicts Decision 7.
  Told the user to author a `SpawnPoint` (`EnemyType` = `VoidwakenHulk`) in the Boss room instead.
  Any future rig animated out of its rest pose needs the same entry. He faced
  the wrong way while walking (AutoRotate turns the HumanoidRootPart's LookVector, and the HRP's front
  isn't the mesh's front) — fix is rotating the HRP and recomputing `RootJoint.C0` from the command
  bar, NOT `FacingYawOffset` (that only covers the attack snap, not walking). Walk didn't show:
  fixed in code (forced track priorities + velocity-based walking check). A stop animation is not needed: Idle loops underneath and
  the Move track fades out over it (default 0.1s fade; offered 0.3s if the snap is visible).

**Next session, in order (Roblox side):**
1. 3D Importer → `VoidwakenHulk.fbx`, **Scale Unit = Centimeter**. The default `Stud` reads FBX
   centimetres as studs: ~100× oversized, which is over Roblox's 2,048-stud part limit.
2. Texture: a `SurfaceAppearance` inside the MeshPart, with `ColorMap` = `VoidwakenHulk_Baked.png`.
   Later, for the pearl: low roughness and zero metalness (pearl isn't metal).
3. Assembly: a Model named exactly **`VoidwakenHulk`**. Not "Voidwaken Hulk" (the DisplayName has a
   space) and not the file's old "VoildHulk". Inside it: a Part named exactly `HumanoidRootPart`
   (Transparency 1, CanCollide on, at his centre of mass); the MeshPart with CanCollide off and
   Massless on; a `Motor6D` inside the MeshPart with Part0 = HumanoidRootPart and Part1 = the
   MeshPart; a `Humanoid` with an `Animator` inside it; the Model's `PrimaryPart` =
   HumanoidRootPart. Delete the importer's `AnimationController` and any Moon Animator scratch
   objects. Set `HipHeight`, check his scale against a 5-stud player, then move him into
   `ServerStorage.EnemyModels`.
4. Test with a raid to a Boss node. **If the Boss room clears the instant you walk in, the name is
   wrong:** `pickBossSpawnKeys` falls back to the unfiltered pool, `spawnEnemy` skips the missing
   model, and a zero-spawn encounter resolves as trivially cleared.

**Planned, not built — each needs the user's go-ahead:**
- **Enemy animation playback. Nothing plays enemy animations today.** `EnemyAI` moves rigs with
  `Humanoid:MoveTo`, and rigs cloned from `ServerStorage` have no `Animate` script. This needs an
  `Animator` load-and-play in `spawnEnemy` plus triggers (idle, walk, attack, and the Slam's wind-up
  and impact). The user wants unique animations per enemy: the Studio-built rigs in Moon Animator
  (which needs Motor6D joints, not Welds), the Hulk in Blender, imported through the Animation
  Editor and published for IDs.
- **The Hulk's per-arm mechanic.** A new `EnemyAI.Patterns` entry, the same shape as `Slam`, plus
  config fields. The user hasn't said what each arm does yet. Ask before designing either the
  pattern or the animations, so the two are designed together.
- **The camera eye.** The dome is his dark eyeball. Studio parts: a dark tinted Glass shell slightly
  bigger than the dome, and a green Neon pupil disc (`#3DFF6E`) with a green PointLight. Code, not
  written yet: a client script that every frame pins the eye to the `Head` bone's
  `TransformedWorldCFrame` and places the pupil on the dome facing the player
  (`CFrame.lookAt(domeCentre, target) * CFrame.new(0, 0, -radius)`). The Hulk is boss-only and each
  raid has one player, so the target is always the local player.
- **Gem glow:** a PointLight in `#8130F2` on an `Attachment` parented to the `Torso` bone, so it
  moves with him. A texture can't glow; `SurfaceAppearance` has no emissive map.

**Offered and declined by the user; don't re-offer unprompted:** a spawn-time rig validator, a
boot-time check of every `EnemyConfig.ModelName` against `ServerStorage.EnemyModels`, and a dev
shortcut that forces the next node to be a Boss room.

**Found in passing, NOT fixed on this branch:** `MineShaftConfig.OreColors` has Gold and Platinum
swapped (Gold renders silver-grey and Platinum gold-yellow, the reverse of OreConfig's own
descriptions). It's slot-vs-metal drift from the ore rename: the colours followed the slot like the
stats did, but colour belongs to the metal. Handed off as a separate background task.

**SESSION OF 2026-09-09 — boss escort designed, three fixes shipped.** In order:
- `07c7d2d` — the Boss escort design round (zones in the Boss room). Read
  "Boss escort — spawn zones in the Boss room" for the five decisions. NOT BUILT, and blocked on the
  spawn-zone quantity curve, which is also still unbuilt.
- `e26ea41` — corrected two claims that were never true of the code: Boss rooms honouring authored
  placements, and `InteractPoint` accepting a Model.
- `8fffb6f` — **shipped**: `beginBoss` now honours authored `SpawnPoint`s (points only, on purpose —
  zones there would inherit the 2.6x boss multiplier). NOT yet verified in Studio: run a raid to a
  Boss node and check the Hulk lands on the authored Part rather than the room centre.
- `549da86` — **shipped**: `AmbushWaveMax` 7 -> 8, plus the marker firing-rules table.

**SESSION OF 2026-09-09, separately — the elite/boss pool split, `Siegebreaker` shipped. NONE OF
THIS IS VERIFIED IN STUDIO.** `EnemyConfig.EliteTypes` and a new `EnemyConfig.BossTypes` table are
now two separate pools instead of one table serving both jobs — see "The Voidium infestation"
section above, item 1 (now RESOLVED) and "Siegebreaker — design rationale" for the full mechanics
and the honest reconciliation with the earlier bloom-as-boss lore round. In short: `VoidwakenHulk`
moved into `BossTypes` and its HP went 220 -> 340; a new type, `Siegebreaker`, was built to refill
`EliteTypes`; `EnemyAI.Patterns.Slam` is a new, second AI pattern (the first was `Chaser`, alone,
since the combat engine shipped) — a telegraphed wind-up/impact cycle whose radius check is
deliberately mode-agnostic (wall in a wave, player in a raid).

**Nothing here has been run in Studio, and it cannot fully work yet even if it were.** Two brand
new Model names are required in `ServerStorage.EnemyModels` — `Siegebreaker` and `VoidwakenHulk` —
and NEITHER exists there yet. Until they're built: `Siegebreaker` will not spawn on an elite wave
at all, because — worth recording, it is a real asymmetry, not a guess — the base-defense elite
pick (`CombatEncounterService.pickSpawnKeys`) does NOT filter its draw by
`CombatEncounterService.HasModelFor` the way the boss picker
(`RaidRoomService.pickBossSpawnKeys`) and the regular raid picker (`pickRaidSpawnKeys`) both do; it
picks blind from `EliteTypes` and lets `spawnEnemy` warn-and-skip on the miss, which reads as "the
elite wave spawned nothing extra" rather than an error. `VoidwakenHulk` in a Boss room is better
protected — `pickBossSpawnKeys` DOES filter by `HasModelFor` first — but falls back to drawing
unfiltered from `BossTypes` anyway if literally nothing in the pool has a model (RaidRoomService.lua
~969), so a Boss room with no `VoidwakenHulk` Model built will still attempt the spawn and then hit
the same warn-and-skip path in `spawnEnemy`, which is indistinguishable from "the boss room spawned
nothing" without checking the Output window. Next session: build both Models (Humanoid +
PrimaryPart, same convention as every other enemy), THEN clear four waves to reach an elite wave and
separately run a raid to a Boss node, per README section 4 steps 15 and 24.

**SESSION OF 2026-09-09, continued — variant folders shipped, burrower shelved, ENEMY ART STARTED.**
Three commits, none pushed: `b7b0cf6` (the elite/boss split above), `4a9569a` (the burrower backlog
entry), `72c8e40` (enemy variant folders). Since the entry above:

- **`ServerStorage.EnemyModels.<ModelName>` may now be a FOLDER of variant Models**, one picked at
  random per spawn — see "Enemy model variant folders" above. Shipped because every Scavenger on the
  field was the same clone and `GetEnemyCount` puts eight-plus of them there by wave 2. NOT verified
  in Studio. The single-Model form still works unchanged; nothing needs migrating.
- **A burrowing enemy was designed and deliberately shelved by the user** for a post-launch update —
  see "Burrower enemy" above. The mechanical-claws prop it produced is still wanted on the Scavenger
  even though the burrow mechanic is not being built.
- **The user has BUILT the Scavenger models in Studio** — the first enemy art in the project. That is
  the only enemy model that exists. `Raider`, `Brute`, `Siegebreaker` and `VoidwakenHulk` are all
  still missing, and the consequences of each being missing are spelled out in the entry above.

**ENEMY ART IS THE USER'S ACTIVE WORKSTREAM.** Build order agreed: Raider next (duplicate a finished
Scavenger — same R15 skeleton, straighten the posture, widen the shoulders, swap the shirt, give it a
real gun), then Brute, then Siegebreaker, then VoidwakenHulk. The art direction for all five —
scale lineup, the Rebel/Construct material split, and which tool to build each one in — is on the
"Enemy Silhouettes" Artifact: https://claude.ai/code/artifact/4089f017-a2e1-4012-973a-1e394c58f05f
The Siegebreaker's own spec page is https://claude.ai/code/artifact/152b056a-bfd6-454d-923a-04e312e6ffa9

**Four Studio findings from that session, worth not relearning:**

1. **`ServerStorage.EnemyModels` content is NOT in this repo.** Rojo only syncs `src/`, and the folder
   is declared empty in `default.project.json` to be filled by hand. Every enemy rig the user builds
   lives in the place file alone — git is not backing it up.
2. **Layered clothing ("3D shirts") needs `WrapTarget` objects on the rig's body parts.** A default
   Rig Builder rig may have none, in which case the clothing silently renders nowhere with no error.
   Test with a `WrapTarget` count over the rig's descendants — a working R15 body has 15, one per
   part. If it has none, copy a real avatar character out of Workspace during Play and use that as
   the base rig instead.
3. **Toolbox "clothing" is usually not clothing.** A mesh grabbed from the Toolbox comes back from
   `MarketplaceService:GetProductInfo` as `AssetTypeId 39` (`SolidModel`), and `ApplyDescription`
   accepts it and silently ignores it — returning success, changing nothing. For a static NPC the
   answer is to `WeldConstraint` the mesh to the relevant body part, which is cheaper at runtime than
   layered clothing anyway and loses nothing on a rig that is never animated.
4. **`HumanoidDescription` has no `ShirtAccessory`/`JacketAccessory` properties.** Layered clothing
   goes through `desc:GetAccessories(true)` / `desc:SetAccessories(t, true)`. The named `*Accessory`
   properties that DO exist are the classic rigid slots — `HairAccessory` among them, which is why
   hair is a one-line change and a 3D shirt is not.


The user has finished AUTHORING the raid room Models in Studio and walked the whole room-authoring
contract; a checklist page of that contract exists as an Artifact (search the gallery for "Raid Room
Contract" — it is generated from `RaidConfig.lua`/`RaidRoomService.lua` and goes stale if either
moves). Nothing is pending on the user's side. Next raid work is the spawn-zone curves, and it needs
a greenlight.

**ORE REWORK — SHIPPED 2026-09-07, commit de1e11b, PARTIALLY VERIFIED.** Raw ores renamed
(`ScrapIron`->`IronOre`, `CopperWire`->`CopperOre`, `SteelPlating`->`GoldOre`,
`GoldContacts`->`PlatinumOre`, `HardenedPlate`->`PlatinumBar`); Gold and Platinum traded gate slots
so the value ladder reads Iron -> Copper -> Gold -> Platinum -> Voidium, with the mining stats
staying on the SLOT. Tool/Suit/Forge tiers repriced as Scrap + a ramping ore component, new
`SellService`/Sell tab on the Hub Shop, a small wave-clear Scrap trickle (partially reversing the
old "base defense grants no Scrap or Cores" instruction — Cores are still zero), and one-shot newbie
forge pity (`profile.NewbiePity`, 5 rolls instead of 15, cleared permanently on first reset).

CONFIRMED IN STUDIO: the Hub Shop station and its Sell tab both appear. NOT yet exercised: mining an
ore end to end, an actual sell, the wallet update, or the `0 / 5` pity gauge on a fresh profile —
README section 4 steps 3, 6 and the new step 23 cover exactly those. No ore-node re-tagging was
needed and none should be attempted: this place has ZERO instances tagged `OreNode` and mines via
`MineShaftStart`, so shaft blocks pick their ore from `MineShaftConfig` at runtime.

Sell prices and the tier ladders are UNPLAYTESTED, and the user expects to rebalance after
playtesting. All of it is pure config — `SellPrice` on OreConfig/RefinedOreConfig,
`OreConfig.ToolTierCosts`, `MineShaftConfig.SuitTierCosts`, `ForgeConfig.ForgeTierCosts`,
`WaveConfig.ScrapReward` — and no service reads a number directly, so retuning never touches
behaviour.

ICONS are the user's active workstream (6 of 99 done). `ReplicatedStorage.ItemIcons` is EMPTY, so
there is nothing to rename; the names the resolver expects are `IronOre`/`CopperOre`/`GoldOre`/
`PlatinumOre`/`VoidiumShard`, `SteelIngot`/`CopperCoil`/`GoldBar`/`PlatinumBar`/`VoidiumCore`, and
the six weapon families `Salvage`/`Flamethrowers`/`Bows`/`Snipers`/`GrenadeLaunchers`/`Miniguns` —
16 images covering every ore, every refined material and all 18 weapons, since `HudKit.getItemIcon`
now falls back from an item key to the weapon's `Family`.

**Step 1 of its build order is BUILT AND VERIFIED IN STUDIO (2026-09-08)** *(its exit-door half was switched OFF on 2026-09-09 — `RaidConfig.ExitDoorsEnabled = false`, the map is the input again; see the newest entry at the top of this section)* — physical exit doors plus
the Sector Map, see "Raid Rooms — physical exit doors + the Sector Map" below. The user built the
first authored Combat room and ran it. Confirmed WITH THEIR OWN EYES, not inferred: doors stay sealed
and invisible through the fight then appear on clear; walking through one actually travels to that
branch and the colour/label matched the destination; `PlayerSpawn` places and FACES the player; and
`SpawnZone` puts enemies inside the volumes, on the floor, never on top of the player.

**Still unexercised, so do not record these as verified:** the map GUI being genuinely read-only
(circles not responding to clicks), the deliberate too-few-doors fallback to the clickable map, a
zone's `Weight` visibly favouring the heavier zone over many runs, the duplicate-`PlayerSpawn` warn,
and the no-markers warn. README section 4 step 15 covers all of them.

**STUDIO ART IS THE USER'S ACTIVE WORKSTREAM (2026-09-08/09).** They are hand-building EIGHT raid
rooms — 2 Combat (one pre-existing), 2 Ambush, and one each of Start, Boss, Heal, Shop — ticking
them off on the Raid Room Build Sheet page as they go. Those eight double as step 2's Studio
verification. Combat/Ambush go in a Folder (variants); the other four stay a loose Model.

**ICON KEYS: the Asset Bench had FIVE STALE ONES and they are now fixed on the page.** The ore rework
renamed them and the Bench was never updated, so any icon drawn to the old names resolves to nothing
(`resolveIcon`, HudKit.lua:276, matches the ImageLabel's NAME inside `ReplicatedStorage.ItemIcons`).
Old -> new: `ScrapIron`->`IronOre`, `CopperWire`->`CopperOre`, `SteelPlating`->`GoldOre`,
`GoldContacts`->`PlatinumOre`, `HardenedPlate`->`PlatinumBar`. **The middle two are a RE-MAPPING, not
a rename** — Gold and Platinum traded gate slots in the rework, so art drawn as `SteelPlating` now
sits in the slot called `GoldOre`. The user said they had already drawn some of these; fixing them is
a rename of the instance, never a redraw. Also corrected on the Bench the same day: weapon icons are
SIX family icons not 18 (`HudKit.getItemIcon` falls back to `CraftingRecipes.Weapons[key].Family`),
deployed robots need NO world model, `ServerStorage.DroneModels` is undeclared in
`default.project.json`, and the rooms list was missing `Start` and `Ambush`.

**Step 2 is BUILT (2026-09-08), NOT YET VERIFIED IN STUDIO** — room variant folders
(`RaidRoomModels.<Type>` may now be a Folder of Models picked at random per node, via
`pickRoomTemplate` in `RaidRoomService.lua`; see "Decision 3 — room variants" above for the full
writeup, including the PrimaryPart-skipping refinement). **Step 3 (mode plumbing — a `RaidMode` on
the raid state plus one `RaidConfig.Modes` entry) is now the next build-order step.** It is still one
of the seven build-order steps, so the design-phase hold above still applies to it: do not start it
without an explicit greenlight.

The rest of this section is kept as the HUD round's own history.

Everything above is the live plan. Sections A and C's design round are done; B (raid map light
touch) is not started, C's BUILD is not started, D ships with C. The picks, the corrections, the
panel-size decision and the server-side notes are all in the "C-revised" table just above — start
there, not from the mockups, because the mockups contain the four wrong facts listed under it.

Build order that falls out of the dependencies: Smelting B first (zero server work, fits the
existing panel once it is re-proportioned), then Workbench B (zero server work), then Welding A
(needs the panel at 760x520 and the robot silhouettes), then Forge A (needs the panel, and the
output-tray decision above). Popups B underpins all four, so its plate/scrim/cap treatment wants
building as a shared HudKit helper before the first menu that raises one.

**Progress (2026-09-02).** Done AND verified in Studio by the user: `HudKit.modal` (the Popups B
plate), per-station panel sizing, Smelting B, Workbench B, and the whole Welding Station (Robots =
Welding A, plus Mods, Turrets and Drones), and Forge A (the Crucible). Built but NOT yet verified in
Studio: the case-opening A/B hybrid. **The design round is now built in full** — every row of the
picks table has shipped.

**Case opening, as built (`StarterPlayerScripts/CasePanel.lua`).** The A/B hybrid exactly as picked:
Popups A's in-panel reel while it runs, Popups B's full takeover when it lands.

**The flow gained a step, at the user's direction.** Decoding no longer opens the case. A finished
decode leaves it cracked-but-unopened in `profile.DecodedCase` (the same nil-able convention as
`SmeltJob`/`DecodeJob`/`ForgeOutput`), and a new `OpenCase` remote rolls and grants the contents when
the player presses Open. The reason is the reveal itself: a decode elapses on a timer that can fire
while the player is down a mine shaft, so paying out at completion meant the payoff of the whole
Black Market system was a toast nobody was looking at. Making opening deliberate means the animation
can only ever run while someone is watching it.

**Duplicates now refund half the case, in the currency it cost** — 300 Scrap from a Scavenged, 30
Cores from an Encrypted, 6 Contraband from a Blackline — with a flat 8 Contraband for the
Robux-bought Prototype, which has no profile-side price to halve (`CaseConfig.DuplicateRefund`).
That replaces four hand-tuned per-Kind Contraband consolations (6/10/4/5) which paid the same
whether the duplicate fell out of a 600-Scrap case or a 12-Contraband one, and which nobody could
relate back to anything. Refund amounts are rounded UP and never below 1: a case refunding zero would
read as "you got nothing", the exact outcome the mechanic exists to prevent.

**The reel is built backwards from an answer the server already gave**, with the winner planted at a
fixed index and filler cards weighted by that case's own Odds. That is how every case-opening
animation works and it is safe here for the usual reason: the client cannot change the outcome
because `OpenCase` granted it before the first frame. Every card carries a rarity edge on the way
past — the winner only grows and thickens ON ARRIVAL, or it would be spottable mid-spin.

**Two things Studio caught, both worth not relearning.** First: `HudKit.panelHeader` drew a
full-width bar flush against the top edge, so its top-right corner ran past the panelframe's
45-degree cut on EVERY panel in the game — the identical bug `accentCap` was written to fix, just
never applied to the header. `HudKit.CORNER_CUT` is now exported so a panel can inset its own
full-bleed decorations too, because `ClipsDescendants` does not help here: Roblox clips to the
rectangle, not to the sliced shape, so the diagonal corners still leak. Second: the reveal's diamond
backdrop was drawn at the mockup's literal 300, and a square rotated 45 degrees occupies side *
sqrt(2) in BOTH axes — 424x424 inside a 440-wide plate. Anything rotated has to be sized DOWN from
the space available rather than up from the number in the drawing.

`Remotes.CaseOpened` is GONE — event, listener and declaration. The reveal is driven by `OpenCase`'s
return value, so the event had no listener left, and its old client handler was also reading a
`ConsolationContraband` field that no longer exists.

**Welding A, as built (`StarterPlayerScripts/WeldingPanel.lua`).** All four of the station's tabs.
Four things came out of it that the Forge build should reuse or knows about:

- `HudKit.dashedLine` / `HudKit.dashedBox` — a dashed rule and a dashed border, built out of short
  Frames for the same reason `HudKit.ring` is built out of rotated ones: Roblox has no dash pattern
  and this project has no tiling asset. `dashedBox` takes a `cornerInset` so a dashed border drawn
  around a rounded frame does not poke past the curve. Both take PIXEL lengths, not UDim2s — a
  Scale-sized parent cannot say how long its own edge is at build time.
- `ModConfig.ApplyMods` — the mod multiplier loop MOVED out of `CombatMath.lua` (ServerScriptService,
  so the HUD cannot require it) into the shared config, and `CombatMath`'s `applyMods` is now a
  one-line delegate. The rig footer prints mod-adjusted `dmg × rate · hp`, and the alternative was a
  second copy of the math on the client. Same reasoning as `Shared/Wallet.lua`.
- `CraftingRecipes.MaxDeployedRobots(profile)` — base slots plus the ExtraRobotSlot pass, shared for
  the same reason: the header's "DEPLOYED 2 / 3" denominator and the one `DeployRobot` enforces are
  now the same function.
- The old `makeEquipmentRow` / `makeRobotRow` / `MOD_SLOT_WIDTH` / `renderModsRow` /
  `renderTurretsRow` / `renderDroneRows` are DELETED from `MainHud.client.lua`, which routes all four
  Welding tabs to the panel off a set DERIVED from `StationConfig.Types.Welding.Tabs` rather than a
  hand-written list. `renderCraftList` no longer has a fall-through branch either — an unrecognised
  tab name now warns instead of rendering nothing.

**The other three tabs had no mockup, and that was a decision rather than an oversight.** The design
round only ever drew Welding A, for the Robots tab. Rather than open a second round for Mods /
Turrets / Drones, they take the shape that round produced — rail of candidates left, selected one
rendered large right, action in the footer — which by then WAS the station's identity, and which the
phase-3 brief asked each station to have. Section C's "design first, then build" rule still stands
for a menu that needs a DIRECTION; it does not demand a fresh round to apply a direction already
chosen to the tabs sitting beside it in the same panel.

What each stage DRAWS is the part that differs, and in each case it is the thing the row list could
not say:

- **Mods** — each multiplier as a bar running out from a `1.0x` centre line (right/Good for a buff,
  left/Bad for a nerf) against a FIXED +/-50% scale, so two mods compare by shape rather than by
  re-reading an axis every time. Plus a "FITTED ON" list, which is the genuinely hard question:
  `EquippedMods` is keyed itemKey -> slot -> modKey, so "where is this mod" has no reverse index and
  nothing else in the HUD answers it.
- **Turrets** — damage / range / fire rate / targets as bars scaled against the best in class, at
  Level 1 (this screen picks WHICH to build; a placed turret's levelled numbers are TurretPanel's
  job), plus a `HudKit.segmentBar` of real slot usage in three states: placed, built-but-unplaced,
  empty. "Which one" and "can I even place another" belong on the same screen.
- **Drones** — the drone drawn on the same chassis machinery as the robots, with ONE hardpoint at its
  core bay. One Core at a time is then visible rather than stated.

Two refactors fell out of doing three more tabs rather than one, both worth knowing before the Forge:
`drawRig` split into a general `drawChassis(spec, opts)` plus a robot-specific wrapper, and
`drawLeader` now takes a card LAYOUT rather than a mod-slot index — so a one-socket machine can reuse
both. The rail, stage title, stat bars and footer are likewise one implementation each.

**Forge A, as built (`StarterPlayerScripts/ForgePanel.lua`).** The Weapons tab only; Smelting is the
Batch Dial and stays in MainHud. Three columns as drawn — input bay, chamber, output tray — with
`HudKit.ring` as the chamber's sweep (which is what that helper was built anticipating) and pity
redrawn as the machine's HEAT gauge.

**The output tray shipped as decided: real state (option (a)).** `profile.ForgeOutput` is a nil-able
table following the `SmeltJob`/`DecodeJob` convention exactly — absent from `defaultProfile` so nil
already reads as "nothing pending" and no backfill is needed, always broadcast as `ForgeOutput or
false`. Two new RemoteFunctions, `CollectForgeOutput` and `TrashForgeOutput`, both gated to
plot+Forge like the roll that produced the thing. The Id is minted at ROLL time, not at collect time,
so two pending rolls can never collide on one.

Everything in the decided rules list above is in: no refund on trash, a fresh roll overwrites the
tray, and `DiscardConfirmMinRarity` ("Epic", compared through `ForgeConfig.RarityIndex`) raises a
confirmation the SERVER independently enforces via a `confirmDiscard` flag on `ForgeWeapon`. The
rejection carries `NeedsDiscardConfirm = true` so the HUD can tell a question from a refusal without
parsing the reason string. Note the "your first weapon auto-equips" convenience moved from
`ForgeWeapon` to `CollectForgeOutput` — a weapon still in the tray is not owned, so it must not be
equippable.

**More shared math moved into config, same rule as the Welding round.** `ForgeConfig` gained
`RarityIndex`, `NeedsDiscardConfirm`, `LuckPoints`, `RollWeights` and `RollChances`;
`ForgeService.rarityIndex`/`rollRarity` now delegate. The chamber's odds bar normalises the SAME
weights the roll walks, so it cannot advertise odds the server will not honour — which for a
gambling screen is not a tidiness point.

**What the mockup did not settle, and what was decided instead.** It drew one dropdown labelled
Family and no way to pick WHICH gun in that family, but the input bay has to price a specific
recipe — so there are two rows of the same drawn control, Family and Weapon. And it drew a single
Collect button where the decision above had already called for Collect and Trash side by side; the
decision won.

**The docked pity bar and Luck Potion button are DELETED**, not hidden — heat and the additive slot
say the same two things inside the machine. That took `forgeDock`, `pity`, `potionButton`,
`potionPlaceholderLabel`, `potionBadge`, `POTION_BUTTON_SIZE`, `refreshPityBar`,
`refreshPotionButton` and `setForgeWidgetsVisible` out of `MainHud.client.lua` with it, and with
THOSE went the forward-declare tangle CLAUDE.md documented as the reason `pity` could never be
extracted. The bottom action row no longer hides itself when the Forge opens, because the dock it was
avoiding is gone. MainHud is down to ~3,600 lines and ~144 top-level locals, from 4,248 / 161 at the
start of the phase.

**Where the build deviates from the mockup, and why.** Three, all deliberate:

- **"Unlock 40 cores" on the empty slot is gone**, replaced by "click to fit". This is the corrected
  fact from the list above — slots are never locked.
- **The rig silhouettes are drawn, not loaded.** The art called for below still does not exist, so
  each robot gets a line-drawing chassis assembled from stroked Frames (`WeldingPanel`'s `RIGS`
  table, one shape list per robot, plus a `GENERIC_RIG` fallback). The `rig_<robotKey>` keys are in
  `UiIconConfig.Icons` at `0`; filling one in swaps that robot to the image with no code change.
  This is the project's missing-art rule applied properly, not a placeholder to replace later — but
  a real silhouette would still look better than four box-and-rectangle rigs.
- **Leader lines bend.** The mockup drew three straight dashed stubs that do not actually reach
  their cards (its own SVG has line 1 pointing the wrong way). Built as elbows — out from the
  hardpoint, along to the card's mid-height, in to its edge — collapsing to one straight run when
  the hardpoint already sits at the card's height. Straight-only would have forced the three cards
  to sit at the three hardpoint heights, which no rig can satisfy without two cards overlapping.

The ten mockups live at https://claude.ai/code/artifact/11c89954-fefe-4302-bae9-fe6186f12ed1 —
open that before building either remaining menu, since the whole point of the design round was that
the look got settled on a page first. The working files behind it are `.design/menus/*.dc.html`
plus `canvas.json`, which are UNTRACKED (the whole `.design/` folder is, by convention); they seed
into an editable Claude Design canvas via that skill's helper once Node exists on this machine —
there is none right now, which is the only reason the round shipped as a flat page.

Two shared pieces came out of that work and are the right things for the remaining menus to reach
for rather than re-solving:

- `HudKit.ring` — a circular progress arc built from 90 overlapping rotated Frames, because Roblox
  has no arc primitive and this project has no radial-fill asset. Forge A's chamber wants it.
- `makeSpecSheet` in `MainHud.client.lua` — the Workbench's hero/stats/cards/next-step shape. Only
  worth reusing if a menu genuinely has that shape; Welding A and Forge A do not.

Two lessons from the Smelting round, both worth not relearning:

- **Build what the reference shows, or say out loud that you cannot.** Smelting shipped first with a
  straight segment bar instead of the ring and a click-only slider instead of a drag, both of them
  quiet substitutions made because they were easier to get right blind. Both were rejected on sight
  and had to be redone.
- **A control that repaints by calling `renderCraftList` cannot be dragged**, because the re-render
  destroys the instance the pointer is holding. Anything continuous needs an in-place update path
  (see `applySmeltQuantity`) and a re-render only when the selection itself changes.
