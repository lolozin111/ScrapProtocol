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
  `ReplicatedStorage.ItemIcons`, `ReplicatedStorage.WeaponTools`, `ServerStorage.EnemyModels`,
  `ServerStorage.RaidRoomModels`, `ServerStorage.TurretModels`.

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
simple new field. `DataService.lua`'s own header notes this hand-rolled version isn't
session-locked across servers — swap in ProfileService before real concurrent players.
When a save's *shape* changes (not just a new field), follow the existing
`migrateLegacyWeapons` pattern: a one-time, self-guarding conversion run from `loadProfile`.

**Server-authoritative everywhere.** The client only ever reports intent ("I hit this node",
"I clicked this station") over a Remote; the server (mostly `StationService`/`PlotService` for
where-gating, then the owning service for the actual legality/amount) decides whether it's
legal and computes any reward. Never trust a client-supplied amount. A rejected action should
never fail silently — see the `MineFailed`/toast/warn conventions used throughout for surfacing
*why* something was blocked, not just declining it.

**World setup is tag-driven, not hardcoded.** Systems key off `CollectionService` tags placed
on Parts/Models in Studio (`Plot`, `Station` + `StationType`, `OreNode` + `OreType`, `Node` +
`NodeType`, `MineShaftStart`, `ExpeditionStart`/`ExpeditionLever`, `Tree`), read by the matching
service. This means most new-content work (placing another ore node, another station) is a
Studio/tagging task, not a code change — code changes are for new *systems* or new *config
entries* (e.g. a new key in `OreConfig.Ores`).

**Missing art never breaks the loop.** Enemy rigs, gun Tools, base/raid-room models, and item
icons are all optional — every service that clones one of these falls back to a plain
placeholder (gray box/floor, colored tile with text) and a `warn()` when the expected
`ServerStorage`/`ReplicatedStorage` model/image is absent, rather than erroring. Preserve this
pattern in any new content-driven feature.

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
