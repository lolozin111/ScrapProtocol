# `.design/` — design working files

Not a build input. Rojo only syncs `src/`, and nothing in the game reads anything here. These are
the mockups and source art behind the HUD's look, kept in the repo so they cannot be lost silently
to a `git clean` or a fresh clone.

## Source art

- **`panelframe.png`** — the 9-slice frame every HUD panel renders through. This is the SOURCE for
  the uploaded Roblox asset whose ID lives in `ReplicatedStorage/Shared/UiIconConfig.lua` under the
  `panelframe` key. If that asset ever needs regenerating or retouching, start here.
- `panelframe-preview.png`, `slice-demo.png` — how that frame slices and stretches; reference only.

## Mockups

Two design rounds, each settled on a page before any code was written. That sequencing is the
reason both rounds went well, and `DESIGN_NOTES.md` treats it as the process to repeat.

**Round 1 — the HUD chrome** (built, shipped):

- `Main.dc.html`, `CommandDeck.dc.html`, `EdgeRig.dc.html` + `canvas.json` — the three competing
  directions (A Forged Panel / B Command Deck / C Edge Rig).
- `hud-directions.html` — those three presented side by side.
- `forged-rig.html` — the chosen A×C hybrid. This is the visual language the HUD actually uses:
  angular clipped corners, bevelled shells, accent caps.
- `icon-prompts.html` — prompts used to generate the HUD icon set.

**Round 2 — the station menus** (`menus/`, partly built — see `DESIGN_NOTES.md` "HUD phase 3"):

- `menus/*.dc.html` + `menus/canvas.json` — ten mockups: three Forge directions, two each for
  Smelting, Welding and Workbench, and two popup treatments.
- `menus/station-menu-directions.html` — GENERATED, do not hand-edit. It is the published review
  page, live at https://claude.ai/code/artifact/11c89954-fefe-4302-bae9-fe6186f12ed1
- `menus/page.skeleton.html` — the source that generates it. Each `<!--MOCKUP:Name-->` marker is
  replaced with the markup extracted verbatim from `Name.dc.html` (everything between `</helmet>`
  and `</x-dc>`). Edit the skeleton or an artboard, never the generated page.

## About the `.dc.html` files

They are Claude Design artboards. Each one renders as a frame on a single pan/zoom canvas laid out
by the sibling `canvas.json`, and they seed into an editable canvas through the `design` skill's
helper — click-to-select, a properties panel, inline text editing.

That is why round 2 shipped as a flat HTML page instead: assembling the canvas needs Node or Bun,
and neither is installed on this machine. The artboards are written and correct, so the moment one
exists the canvas can be seeded from them unchanged. Nothing needs redrawing.
