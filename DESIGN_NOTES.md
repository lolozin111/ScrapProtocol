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
| Raid overhaul | **Scope cut to one mode for v1 (2026-09-08)** — steps 5-6 deferred post-launch; step 1 built AND VERIFIED in Studio 2026-09-08, step 2 (room variant folders) BUILT 2026-09-08, not yet verified in Studio, see Phase 00 below; **exit doors switched OFF 2026-09-09** — the Sector Map picks the next room again (`RaidConfig.ExitDoorsEnabled`) |
| Enemy AI patterns | **Engine built, two patterns** — `Chaser` (six enemy types) and, shipped 2026-09-09, `Slam` (`Siegebreaker` only — a telegraphed wind-up/impact cycle, see "The Voidium infestation" below) |
| Enemy art (Studio models) | **4 of 5 built (2026-09-10)** — Scavenger, Raider, Brute, Siegebreaker in `ServerStorage.EnemyModels`; VoidwakenHulk imported, textured, assembled and rigged with `FistR`/`FistL` hit-point Attachments (2026-09-10/11); HipHeight and the move into `EnemyModels` wait on his lying-down pose — see "Resuming after a context reset" |
| Voidium infestation (lore + the raid boss) | **Partially built 2026-09-09** — `EliteTypes`/`BossTypes` split into separate pools and `Siegebreaker` shipped as the new elite; the bloom itself (the actual raid boss per Decision 2 below) is still designed, not built — see "The Voidium infestation" below; `Siegebreaker` also rolls into raid Combat rooms (`EliteChance`, 2026-09-09) |
| Boss escort (spawn zones in the Boss room) | **Designed 2026-09-09, nothing built** — blocked on the spawn-zone curves; see "Boss escort" below |
| Animation pass | **In progress on the Hulk (2026-09-11)** — his Idle (`113796712422007`) and heavy rock-arm attack (`137947497885396`, markers `ImpactR` ×2 + `ImpactRFinal`) are animated in Blender and published; crawl/attack-L/turn/death still to animate. **NO playback code exists yet** — nothing plays any of them, and that build needs the user's go-ahead. Full pipeline, damage/slow numbers and marker contract in "Resuming after a context reset". Was deferred post-launch on 2026-09-08; see Phase 01 |
| Early-game pacing & onboarding | **Partially built** — item 1 (ore sells for Scrap) shipped in the ore rework; starter objectives (item 2) still planned, not built — see below |
| Raid shop rework (run-only perks) | **Planned, not built** — half the tag plumbing exists |
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
2. ~~Room variant folders~~ — **BUILT (2026-09-08), NOT YET VERIFIED IN STUDIO** — small,
   independent, unblocks Studio art. See "Decision 3 — room variants" above and
   `RaidRoomService.lua`'s `pickRoomTemplate`.
3. Mode plumbing — a `RaidMode` on the raid state plus one `RaidConfig.Modes` table of named rules
   (the project's standard flat-table-of-strategies shape).
4. Salvage Run — cheapest: tagging, carry cap, Extraction as a real room. Almost no new systems.
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
`GetRunProgressionMultiplier` (RaidConfig.lua:360) is `1 + step * 0.12` — LINEAR AND UNBOUNDED, no
clamp. Net effect: deep raids are five enemies with ever-larger health bars, and the authored-room
path the build sheet recommends makes it worse, not better. The user's diagnosis was correct.

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

## Raid shop rework — PLANNED, NOT BUILT

Requested in an earlier session, never built there either. Recorded properly this time.

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

**Displayed two ways:** a bottom-left status panel (health bar, a reserved-and-disabled stamina
slot, and a Research row that opens the requirements popup) and a floating sign over the base
showing owner + tier. The stamina bar is a deliberate placeholder — there is no stamina or dash
system in the codebase at all yet (no input handling, no regen loop, no server validation), so it is
shown visibly disabled rather than lying about a stat nothing drives.

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
- Still to animate: movement (crawl/drag — he DOES chase), attack L, a turn-in-place, and a death
  (under 2s, since `humanoid.Died` destroys the model after `task.delay(2, ...)`;
  `BreakJointsOnDeath` must be UNTICKED on his Humanoid or the RootJoint snaps on death).

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
