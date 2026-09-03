# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A [Rojo](https://rojo.space) project for a Roblox game ("Salvage Protocol"): mining, crafting,
base building, wave defense, and raids. Source of truth is the `.lua`/`.server.lua`/`.client.lua`
files under `src/`; Rojo syncs them live into Roblox Studio as they're edited. There is no
JS/npm toolchain, no test runner, and no linter/formatter config in this repo (no `selene.toml`,
`stylua.toml`, `wally.toml`, or `rojo.toml`/`aftman.toml`) — treat this as plain Luau source
edited directly, verified by running the game in Studio, not by a build step.

## Running it

1. `rojo serve` from this folder (or "Rojo: Start" in VS Code) starts the sync server.
2. In Roblox Studio, connect via the Rojo plugin, then Play/Play Solo to test.
3. There is no automated test suite — verification is manual, in Studio. `README.md` section
   4 ("Testing the loop") is a detailed, numbered end-to-end script (which Tag/StringValue setup
   each system needs in a test place, and what to click/observe) for exercising every system.
   When you change a service's behavior, check whether that numbered script still describes it
   accurately and needs updating.

## How `src/` maps to Roblox services

`default.project.json` is the Rojo manifest and is the actual source of truth for the DataModel
tree — check it before assuming where something lives or what Remotes exist:

- `src/ReplicatedStorage/Shared/*.lua` → `ReplicatedStorage.Shared` — pure config ModuleScripts.
- `src/ServerScriptService/Main.server.lua` + `Services/*.lua` → `ServerScriptService`.
- `src/StarterPlayerScripts/*.client.lua` → `StarterPlayer.StarterPlayerScripts`.
- `ReplicatedStorage.Remotes` (every RemoteEvent/RemoteFunction) is declared entirely inside
  `default.project.json`, not created in Lua — add new ones there.
- Empty asset folders the running game expects content in (also declared in
  `default.project.json`, populated by hand in Studio, not synced from `src/`):
  `ReplicatedStorage.ItemIcons`, `ReplicatedStorage.WeaponTools`, `ReplicatedStorage.BaseTemplates`,
  `ReplicatedStorage.UiIcons`, `ServerStorage.EnemyModels`, `ServerStorage.RaidRoomModels`,
  `ServerStorage.TurretModels`.

## Core architecture

**Config vs. logic split.** Every tunable number — costs, drop rates, wave scaling, hazard
bands, rarity weights — lives in `src/ReplicatedStorage/Shared/*Config.lua`, one file per
system, never inline in a service. Retuning the economy means editing a Config module, not
service logic.

**Services are self-booting singletons.** Each `ServerScriptService/Services/*.lua` is a
ModuleScript that wires up its own RemoteEvent/RemoteFunction handlers as top-level code, which
only runs the first time the module is `require`d. `Main.server.lua` is nothing but an ordered
list of `require(Services.X)` calls — order matters (`DataService` must load first; everything
else reads/writes player state through it) and adding a new service means adding it to that list.

**DataService owns all persistence.** `DataService.lua` is the only module allowed to touch
`DataStoreService`. Everything else reads/writes player state via its API
(`DataService.Get`, `AddCurrency`, `AddOre`, `TrySpend`, etc.) against an in-memory
`cache[userId]`. New player-state fields go in `defaultProfile()`; `backfillMissingFields`
fills them in for existing saves on load, so old saves never need a migration script for a
simple new field. Profiles **are** session-locked: load/save go through `UpdateAsync` against an
envelope (`{ Data = profile, Lock = { ServerId, Heartbeat } }`), so two servers can't hold the same
profile and a player whose lock can't be acquired is kicked rather than let in with an unsaveable
profile. `DataService.Save` returns whether the write landed — check it before telling a player
their purchase went through. When a save's *shape* changes (not just a new field), follow the existing
`migrateLegacyWeapons` pattern: a one-time, self-guarding conversion run from `loadProfile`.

**Some `Services/*.lua` files are shared utilities, not services** — no remotes, required by
consumers, following the `CombatMath`/`DamagePipeline` precedent. Reach for these instead of
re-solving the same problem locally, because each one exists specifically because it *was* re-solved
locally several times and the copies drifted:

- `RateLimiter.Check(player, key, cooldownSeconds)` — tests and stamps in one call. Every remote
  that can be spammed goes through it.
- `PlayerActivityService.TryAcquire/Release/Get` — one authoritative activity per player (`Wave`,
  `Raid`, `OutpostRaid`). Replaced five uncoordinated private busy-flags that let a wave and a raid
  overwrite each other's combat state.
- `OreGate.CanMine(player, oreKey)` — the tool-tier + wave-unlock check, previously duplicated
  between `MiningService` and `MineShaftService` with a comment warning about the drift.
- `Shared/Wallet.lua` — where a cost key lives on a profile, how much you have, what it's called.
  Shared (not server-only) so the HUD can't disagree with what the server will charge.
- `ModConfig.ApplyMods(fireRate, damage, hp, itemKey, profile)`,
  `CraftingRecipes.MaxDeployedRobots(profile)`, and `ForgeConfig`'s `RarityIndex` /
  `NeedsDiscardConfirm` / `LuckPoints` / `RollWeights` / `RollChances` — same idea, same reason. All
  of them used to live inside server-only modules (`CombatMath.lua`'s local `applyMods`,
  `CraftingService`'s inline slot math, `ForgeService`'s `rarityIndex`/`rollRarity`) until a
  redesigned HUD panel needed the same numbers client-side, at which point the choice was one shared
  function or two implementations that drift. `CombatMath.applyMods` and `ForgeService.rarityIndex`
  are now one-line delegates and `rollRarity` walks the shared weights. Anything the HUD has to AGREE
  with the server about belongs in `Shared/` — the Crucible's odds bar must not be able to advertise
  odds the roll will not honour.

**`StarterPlayerScripts/HudKit.lua` is the client-side equivalent** — the shared foundation every
HUD panel is built out of, not just the palette (`HudKit.COLOR`) it started as. It now also carries
`HudKit.FONT`/`TEXTSIZE`/`SPACE`/`RADIUS` token tables (named roles — e.g. `FONT.Display` for
headings, `TEXTSIZE.Body`, `SPACE.M` — pulled from sizes already scattered across the HUD rather
than invented fresh, so adopting them is a no-visual-diff change) and `HudKit.button(opts)`, which
builds a `primary`/`secondary`/`danger`-variant `TextButton` with real hover/press feedback
(`TweenService`, Cancel-then-Play so mashing or fast mouse-in/out never stacks competing tweens) —
there was not one `TweenService` call or hover/press state anywhere in the HUD before this. Hover
and press shades are *derived* from each variant's base color via `HudKit.lighten`/`darken`, so a
palette retune propagates to every button automatically instead of needing a matching edit
somewhere else. New UI should reach for `HudKit.button` and the token tables instead of hand-rolling
another one-off `TextButton`, for the same reason as the server-side list above: every hand-rolled
button is a copy that can drift from the others. (`makeRow`'s inline button and other existing
hand-built `TextButton`s are untouched — this is additive, not a required migration.) It also carries three drawing primitives for shapes Roblox has no
element for — `HudKit.ring` (a progress arc, 90 rotated Frames), `HudKit.dashedLine` and
`HudKit.dashedBox` (dashed rules and borders, short Frames in a run) — each built the same way and
for the same reason: there is no arc primitive and no dash pattern, and inventing an asset would put
the treatment behind art that doesn't exist. HudKit also
gained `getUiIcon`/`applyIcon`, resolving against a new `ReplicatedStorage.UiIcons` folder through
the same `resolveIcon` lookup the pre-existing `getItemIcon` uses (chrome/button glyphs vs.
inventory item art, kept as separate folders so their naming can't collide); `applyIcon` also copies
`ImageRectOffset`/`ImageRectSize` off the template instance, so a future move from separate image
assets to one sprite atlas needs no code change at any call site — just set the rect on the Studio
template. All of this is additive: every pre-existing `HudKit` export kept its name, signature, and
behavior.

**To write profile data on disconnect, connect to `DataService.PlayerSaving`, never to
`Players.PlayerRemoving`.** `PlayerRemoving` handlers fire in connection order, connections are made
on first `require`, and `DataService` is required first — so by the time any other service's handler
runs, the profile has already been saved and evicted from the cache and its `DataService.Get`
returns nil. A whole raid's collected loot was being discarded this way, silently. `PlayerSaving` is
a BindableEvent fired synchronously at the top of that handler, before the save and before the cache
clear, and from `BindToClose` too.

**New behaviour goes in a flat table of named strategies, keyed by a config string.** The recurring
shape: `EnemyAI.Patterns`, `RobotBehaviors`, `UltimateEffects.OnHit`/`.OnKill`,
`StatusEffects`/`StatusConfig`, `ProjectileConfig`'s per-weapon profiles. Adding an enemy AI, a
passive, a status, or a gun that flies differently is one function plus one config entry — not a new
branch in a dispatch chain. Dispatch sites must guard the lookup (`if fn then`) and `warn()` on a
miss: an unguarded nil call inside a tick loop throws and strands the run's state.

**Server-authoritative everywhere.** The client only ever reports intent ("I hit this node",
"I clicked this station") over a Remote; the server (mostly `StationService`/`PlotService` for
where-gating, then the owning service for the actual legality/amount) decides whether it's
legal and computes any reward. Never trust a client-supplied amount. A rejected action should
never fail silently — see the `MineFailed`/toast/warn conventions used throughout for surfacing
*why* something was blocked, not just declining it.

**World setup is tag-driven, not hardcoded.** Systems key off `CollectionService` tags placed
on Parts/Models in Studio (`Plot`, `Station` + `StationType`, `OreNode` + `OreType`, `Node` +
`NodeType`, `MineShaftStart`, `ExpeditionStart`/`ExpeditionLever`, `TurretSlot`, `TrainingDummy`,
`Tree`), read by the matching service. This means most new-content work (placing another ore node, another station) is a
Studio/tagging task, not a code change — code changes are for new *systems* or new *config
entries* (e.g. a new key in `OreConfig.Ores`).

**`InventoryUpdate` is a partial patch with a hand-maintained convention.** ~15 server call sites
each send a different subset of keys; the client blind-merges (`for k,v in pairs(patch) do
profile[k] = v end` in `MainHud.client.lua`). Two rules follow, and neither is enforced by anything
but discipline:

- **To clear a field, send `Field = value or false`, never a bare `nil`.** A nil-valued entry is
  dropped from a Lua table literal before it reaches the wire, so `SmeltJob = nil` silently sends
  nothing and the client keeps the stale value. `false` is falsy everywhere it's compared and
  actually survives the trip.
- **After any spend, call `DataService.PushWallet(player)`** rather than hand-listing currency
  keys. A handler that spends Cores but broadcasts only its own domain fields leaves the client's
  mirror stale, so the cost looks like it never happened — indistinguishable from a bug, and much
  harder to diagnose than one. Three handlers had drifted this way before the helper existed.

**Silent failure is the defining hazard here.** Three separate bugs have presented as "I click and
nothing happens", each with a different root cause: a `warn()` that only reached the Studio Output
window, a `CanQuery = false` part that mouse rays passed straight through, and a service missing
from `Main.server.lua`'s require list — which leaves its RemoteFunction with no `OnServerInvoke`,
so `InvokeServer` yields **forever** with no error at all. When something "does nothing", suspect
these before suspecting the logic. Guards now in place: `MainHud`'s `showFailure()` toasts every
rejection on screen, and `Main.server.lua` warns at boot about any service module that is never
required. (You cannot check the remotes directly — reading `remote.OnServerInvoke` throws, since
Roblox callbacks are write-only.)

**Luau allows 200 locals per function scope, and `MainHud.client.lua` used to sit close to it.**
Exceeding it is a *compile* error ("Out of local registers"), so the whole script fails to load and
the HUD simply never appears — it is not a runtime warning you'll spot in Output. The grouped-table
trick (bundling related UI elements into one table — `inv`, `research`, `turretPanel`, `shopUI`,
`pity` — instead of one local per frame) bought back registers for a while, but the file kept
growing anyway, so four of those five groups have since been lifted into their own ModuleScripts
beside `HudKit.lua` and `ModPicker.lua`: `ShopPanel.lua`, `TurretPanel.lua`, `ResearchPanel.lua`, and
`InventoryPanel.lua`. `WeldingPanel.lua`, `ForgePanel.lua` and `CasePanel.lua` joined them later for
a different reason — not grouped tables but whole redesigned tabs (all four of the Welding Station's,
the Forge's Weapons tab, and the Hacker Machine's Decode tab with its case-opening reveal), extracted
as they were rewritten rather than after. That is the pattern: a station's tabs move out as they are
redone. `WeldingPanel.lua` is also where the phase-3 station
shape lives — rail of candidates left, selected one rendered large right, action in the footer, with
the rail/title/stat-bar/footer builders shared by all four tabs — so a new tab in that station is a
stage, not a screen.

`MainHud.client.lua` is ~3,600 lines and ~144 top-level locals after all of that, well clear of the
ceiling for the first time in a while.
`MainHud.client.lua` went from 4121 lines / ~164 top-level locals to 3121
lines / ~151 — a smaller drop than the four extractions suggest, because the grouped-table trick had
already banked most of the register savings; each extraction only nets back one local (`require`)
minus however many aliases MainHud still needs for functions the extracted module exposes back to
it. Don't expect a bigger win from moving `pity` too.

`pity` stayed behind for a long time on purpose — `refreshPityBar`/`refreshPotionButton` were
forward-declared and CALLED from the Forge tab before they were assigned, a self-reference that only
works within one compile unit, and `setForgeWidgetsVisible` was called from two more places. That
whole tangle is GONE: the Crucible (`ForgePanel.lua`) draws pity as its own HEAT gauge and the Luck
Potion as its own additive slot, so the docked widgets, their refreshers, and the visibility toggle
were all deleted rather than moved. Worth knowing as the general lesson: a forward-declare tangle
that blocks an extraction is usually a sign the thing wants REDESIGNING out of existence, not
relocating.

The precedent for the next panel: `ModPicker.lua`, `ShopPanel.lua`, and `TurretPanel.lua` all
self-boot their whole UI as top-level code the first time they're `require`d, because they only ever
parent into `Hud.screenGui` — nothing they build needs to live inside a MainHud-owned instance.
`ResearchPanel.lua` instead exposes a constructor (`ResearchPanel.new(statusPanel)`) because its
button has to parent into the always-visible status panel, which stays a MainHud local.
`InventoryPanel.lua` also exposes a constructor (`InventoryPanel.new(context)`), but for a different
reason:
it depends on three helpers that stay behind in MainHud (`deployedCountForRobot`, `affixSummary`,
`openUltPicker`, shared with the Welding/Forge tabs) plus `ORE_DISPLAY_ORDER`, passed in through
`context` at construction time rather than duplicated. Match whichever shape fits: self-boot if the
new panel only ever touches `Hud.screenGui`, a constructor if it needs something that has to stay in
MainHud. When moving code between files, **extract the exact text — never retype it**; a
hand-retyped UI helper with subtly different sizes/positions looks like a rendering bug, not a typo,
and costs far more to find than the move saved.

**Missing art never breaks the loop.** Enemy rigs, gun Tools, base/raid-room models, and item
icons are all optional — every service that clones one of these falls back to a plain
placeholder (gray box/floor, colored tile with text) and a `warn()` when the expected
`ServerStorage`/`ReplicatedStorage` model/image is absent, rather than erroring. Preserve this
pattern in any new content-driven feature.

## Agent routing

This repo has nine subagents defined under `.claude/agents/sp-*.md`, with their models already
pinned in frontmatter: `sp-scout`, `sp-remote-scout`, and `sp-contract-scout` are `model: haiku`;
`sp-combat-dev`, `sp-server-dev`, `sp-data-dev`, `sp-config-dev`, and `sp-docs-dev` are
`model: sonnet`. The intended split is Haiku reads, Sonnet writes, and the main session (Opus)
holds the plan — the fleet exists specifically to keep exploration off the most expensive tier.
Nothing in the tooling enforces this; it only holds if the main session actually delegates instead
of quietly reading and editing everything itself, which is the default behavior a fresh session
reverts to. Route explicitly, every session:

**Reads go to a Haiku scout, not to you.** There are three, split by what they're looking at:

- `sp-scout` — general lookup: where a symbol is defined, every call site of a function or a
  Remote, whether a config field or API actually exists, confirming a change landed.
- `sp-remote-scout` — the client-to-server surface specifically: whether a RemoteEvent/
  RemoteFunction handler validates its arguments, gates on plot/station, rate-limits through
  `RateLimiter`, and re-derives rewards server-side instead of trusting the client.
- `sp-contract-scout` — Studio tag/attribute contracts (`CollectionService` tags, expected
  attributes), placeholder-fallback behavior, and drift between a config value, the code that
  reads it, and what the docs claim.

Dispatch independent lookups in parallel, in one message — that's the whole point of having three
of them instead of one. Ask a scout for a finding (`file:line`, a symbol, a yes/no, a short table),
never for pasted file contents; if you wanted the raw text you could have read it yourself for the
same cost.

**Writes go to a Sonnet implementer**, and only once you can name the exact `file:line` targets and
the intended behavior. "Go look into X and fix it" belongs to a scout call first — dispatching an
implementer to investigate defeats the division of labor as surely as reading the file yourself
would, it just hides the cost inside someone else's turn. If you can't point at a line, you aren't
ready to dispatch. Ownership is intentionally narrow and non-overlapping:

- `sp-combat-dev` — `CombatEncounterService`, `EnemyAI`, `RobotBehaviors`, `DamagePipeline`,
  `TurretService`, `CombatMath`, `WaveService`.
- `sp-server-dev` — every other service under `ServerScriptService/Services/`, plus
  `StarterPlayerScripts/`.
- `sp-data-dev` — `DataService.lua` and anything touching the saved profile shape or the
  `PlayerRemoving`/`BindToClose` disconnect path. Narrow scope on purpose: this is the one file
  that can silently corrupt or drop a save, so it gets its own dedicated implementer rather than
  being folded into `sp-server-dev`.
- `sp-config-dev` — `ReplicatedStorage/Shared/*Config.lua` only; it cannot touch service logic,
  which keeps "retune a number" changes from ever accidentally becoming "retune a number and also
  refactor the service that reads it."
- `sp-docs-dev` — `README.md`, `DESIGN_NOTES.md`, `CLAUDE.md`.

**One implementer per file, always.** Two Sonnet agents editing the same file in the same round
clobber each other's edits with no merge step to catch it. When a change spans files owned by
different implementers, sequence them — dispatch the first, take its result, then dispatch the
second with that result as input — rather than firing both at once.

**Pin the model on built-in agents too.** `Explore`, `Plan`, and `general-purpose` declare no
`model` of their own, so they silently inherit whatever spawned them — Opus, in the main session.
An unpinned `Explore` call for a routine search runs a haiku-shaped task at opus prices and quietly
defeats the entire arrangement without ever looking wrong. Pass `model: "haiku"` explicitly when
spawning one of these to read, and `model: "sonnet"` when spawning one to write.

**Opus holds the plan, not the source.** Direct `Read`/`Grep` calls from the main session are for
short confirmations and final assembly — checking one thing before writing the plan, verifying an
implementer's diff — not for bulk exploration. If you're reading more than a couple of files
yourself, that work belonged to a scout.

**Do not spawn `sp-lead`.** It is itself `model: opus`, so calling it from an Opus main session
stacks a second Opus that starts cold and has to re-derive context the main session already holds
— strictly worse than the main session just doing the work. It stays on disk under the
retired-files convention (see below) and is only invoked when the user names it explicitly. One
Opus per task.

**The escape hatch: a trivial single-file edit goes direct.** Dispatching an agent — spinning up
context, waiting on a round trip — costs more than a one-line fix takes to make by hand. Routing
exists to avoid burning Opus on exploration and multi-file work, not to turn every edit into a
ceremony.

## Keeping usage down

Every turn re-sends the whole conversation, so a long session costs more with each message even when
the work is small. Three habits matter, in order of how much they save:

**Prefer a direct edit to a subagent for anything you already understand.** A subagent starts COLD:
it re-reads the files to make its change, so a three-line edit can cost 40-100k tokens that two tool
calls would have done for a fraction. Agents earn their cost on genuine multi-file work, on broad
investigation where you don't yet know what you're looking for, and on long verbatim moves — not on
"bump this constant" or "rename this field". This is an amendment to **Agent routing** above, not a
contradiction of it: route reads to Haiku scouts and multi-file writes to Sonnet implementers, but
do not dispatch a cold agent to do something you could type yourself in one call.

**Batch verification.** One command with several greps beats six commands with one each; each round
trip re-sends the conversation.

**Screenshots and large file dumps are permanent.** An image stays in context for every subsequent
turn of the session. Read the part of a file you need, not the whole file, and don't re-read what
you have already read this session.

**`/clear` between distinct tasks is safe in this repo, and is the biggest single saving.** It is
safe *because* the state lives on disk rather than in the conversation: this file loads
automatically, the memory directory reloads, `DESIGN_NOTES.md` carries the live plan and its
"Resuming after a context reset" section says where to pick up, and commit messages record why each
change was made. If something is worth carrying across a reset, write it to one of those before
clearing — not into a longer conversation.

## Where design intent lives

- `README.md` documents what's actually built, organized by system, plus the numbered
  Studio testing script (section 4) — update the relevant bullet/step when a system's behavior
  or setup changes.
- `DESIGN_NOTES.md` is the living backlog/vision doc: bigger not-yet-built ideas, the reasoning
  behind non-obvious past decisions (including full rewrite histories, e.g. why the mining zone
  moved from a scattered-ring layout to dig-down shafts), and a "Known interim decisions" section
  at the bottom listing placeholders that are deliberate, not bugs — read that section before
  "fixing" something that looks unfinished. It can be ahead of `README.md` for systems that are
  freshly built but not yet folded into the testing script (check its "Status at a glance" table
  at the top).
- Retired files are sometimes left on disk on purpose for reference/rollback (e.g.
  `ResourceZoneService.lua`/`ResourceZoneConfig.lua`, superseded by `MineShaftService.lua`) —
  check `Main.server.lua`'s `require` list and the surrounding comments before assuming a file
  on disk is active.
