# Content template — Black Market

Fill this in as you go. It lives in the repo so it survives between sessions and I can read it
directly and generate the config from it.

**You don't need to fill in everything to start.** Each section is independent — a finished
Ultimate mods table is enough to build all the Ultimate mods, even if guns are still blank.

## What I need from you vs. what I'll decide

**From you** — intent and mechanics: what a thing *does*, what makes it feel good, roughly how
strong it should be relative to other things.

**From me** — exact numbers, cost tables, drop weights, folder/naming conventions, UI, and how it
plugs into the existing systems. If you give me "a flamethrower that freezes instead of burns, hits
everything in a cone, weak per-tick but slows hard", I can turn that into config.

Rough is fine. **"I'm not sure yet" is a useful answer** — it tells me to leave a seam there rather
than guess and lock something in.

---

## 1. Ultimate mods (Mythical passives)

The big one. These are behaviours, not stat multipliers.

### What I need per mod

| Field | Meaning |
|---|---|
| Name | Player-facing, e.g. "Detonator Core" |
| Description | One line the player reads |
| **What it does** | Plain language. Be specific about *when* it triggers. |
| Numbers | Radius / damage % / duration / chance / count — guesses are fine, I'll balance |
| Drawback | If any. "None" is a valid answer — you said these can be pure upside |

### ⚠️ The thing I most need you to be specific about: WHEN it fires

I currently have two hook points:

- **`OnHit`** — your shot landed on an enemy
- **`OnKill`** — your shot killed an enemy

Anything that fires at one of those moments, I can build **today, as pure config.**

Anything that fires at a *different* moment needs a new hook — still cheap, but I need to know.
Examples of things that would need one:

- "every 5th shot is explosive" → needs an on-fire hook (fires even on a miss)
- "when you take damage, ..." → needs an on-player-damaged hook
- "at the start of a wave, ..." → needs an on-encounter-start hook
- "+40% damage to enemies above 80% health" → not a hook at all; that's a conditional stat
  modifier and belongs in a different place

**So for each mod, just tell me the trigger moment in plain words** — "when I kill something",
"every time I hit", "when I get hit", "constantly". I'll work out where it goes.

### Example (filled in — this is one of the working placeholders)

```
Name:        Detonator Core
Description: Enemies you kill detonate, damaging everything nearby.
Does:        When my shot kills an enemy, their corpse explodes.
Trigger:     when I kill something
Numbers:     18 stud radius, 60% of the killing blow's damage to each enemy hit
Drawback:    none
```

### Your mods

```
Name:
Description:
Does:
Trigger:
Numbers:
Drawback:
```

*(repeat as many times as you like)*

---

## 2. Gun variant families

### ⚠️ Read this first — it may need architecture, like the hooks did

Right now **every gun fires the same way**: one hitscan ray, one target, on a fire-rate cooldown
(`CombatClient` raycasts, the server recomputes and applies damage to that one enemy).

A flamethrower spraying a cone, a bazooka exploding on impact, and an arcing bow shot are **not
that**. They'd need a "fire pattern" concept — the same kind of named-strategy table the Ultimate
effects use, but for how a shot resolves.

That's very doable, but it's the gun equivalent of the hooks: **worth knowing before I build the
families, not after.**

So per family, tell me: **does it shoot like a normal gun, or differently?**

- *"like a normal gun, just different stats/feel"* → I can build it now
- *"sprays a cone"* / *"explodes where it lands"* / *"arcs and drops"* / *"pierces in a line"* →
  needs a fire pattern; tell me which and I'll add it

### What I need per family

| Field | Meaning |
|---|---|
| Family name | e.g. Flamethrowers, Bows, Snipers, Heavy/Ray |
| How it shoots | See above — normal, or how it differs |
| Feel | e.g. "low damage per tick but constant", "one big slow shot" |

### And per gun inside a family

| Field | Meaning |
|---|---|
| Name | e.g. "Cryo Projector" |
| Description | One line |
| Its twist | The thing that makes it different from others in the family — "freezing flame that slows", "shock arrows that chain" |
| Rough power | Where it sits vs. the others — starter / mid / best-in-family |

Remember: **a blueprint unlocks the whole family** (your decision), so each family wants at
least 2–3 guns in it or the tab feels empty.

```
Family:
How it shoots:
Feel:

  Gun name:
  Description:
  Its twist:
  Rough power:
```

---

## 3. Tools (Epic tier)

### ⚠️ This one has no existing system at all

`ToolTier` today is a single sequential upgrade track (Rusty Pickaxe → Plasma Drill). There is no
concept of *owning a tool as an item*. So tools need the most design from you.

Per tool:

| Field | Meaning |
|---|---|
| Name | e.g. "Survey Drone" |
| What it does | Plain language |
| **How you use it** | The important one — see below |
| Numbers | Guesses fine |

**"How you use it"** — which of these is it?

- **Passive** — you own it and it just works (e.g. "your pickaxe mines 3 blocks at once")
- **Equipped** — takes a slot, works while equipped
- **Placed** — you put it down in the world like a turret (e.g. a drone that patrols)
- **Activated** — you press something to use it, then it goes on cooldown

Each of those is a different amount of work, so this answer shapes the whole system.

```
Name:
What it does:
How you use it:
Numbers:
```

---

## 4. Cases

I can pick sensible odds — but these are yours to steer, since they're the monetisation surface.

Per case type:

| Field | Meaning |
|---|---|
| Name | e.g. "Scavenged Case" |
| Cost | Scrap / Cores / Contraband — and roughly how much |
| Pool | Which top-tier line: **guns**, **mods**, or **mixed** (your call was separate lines) |
| Odds | Rough feel — "mythical should be genuinely rare", or actual percentages if you have them |
| Decode time | How long it sits in the Hacker Machine |

Also:

- **How many case types** do you want to start with? (I'd suggest 3–4: a cheap Scrap one, a
  gun-line one, a mod-line one, and the Robux lucky one.)
- **Robux lucky case daily limit** — how many per day?

```
Name:
Cost:
Pool:
Odds:
Decode time:
```

---

## 5. Contraband

The premium currency. I need earn rates or it's either worthless or trivially farmable.

- **From raids** — how much per raid? Per boss? Only on a clean extract?
- **From base defense** — per boss wave? Every N waves?
- **Robux bundles** — how many Contraband per bundle, and roughly what price points?
- **Daily cap on earning it?** (Common in this genre; stops one player farming out the economy.)

---

## Still open (from DESIGN_NOTES, not urgent)

- Where the Black Market dealer and Hacker Machine physically live — same station with two tabs,
  or two separate tagged Parts in the world? (Two stations = more Studio setup for you.)
- Whether armour/cosmetics from the old Main shop idea come back as a case pool, a Hub Shop tab,
  or get dropped.
