# Orientation

**Read this first. Three minutes now saves thirty later.**

## What this is

A Godot 4.7 (GDScript) **3D game** made by a kid director with Claude. It starts from **Game Foundation**, a
working kit of game pieces plus the workflow that keeps the game working as it grows: tests, screenshots,
choices pages, a Makefile and these docs. The director's actual game is described in
[game_design.md](game_design.md). Where it stands right now is in `HANDOFF.md`.

## How a session works

```
 HANDOFF.md ─▶ session skill: greet → pick ONE thing → build → check → director plays → record ─▶ HANDOFF.md
                                              │                  │
                                    choices page for       make check + look
                                    anything subjective    at the screenshots
```

- [working_with_the_director.md](working_with_the_director.md): who decides what, how to talk, big dreams in small steps.
- [verification.md](verification.md): what "done" means.
- [lessons.md](lessons.md): mistakes already made once (on a big earlier project), so you don't repeat them.

## The game in one picture

```
 decides                      does                         shows
┌─────────────────────┐  MoveCommand  ┌──────────────┐   ┌─────────────────────────────┐
│ PlayerInput (keys)  │ ────────────▶ │    Player    │   │ ModelSlot: a visual slot     │
│ Autopilot (demo)    │  every tick   │ (moves, jumps│   │ from data/slots.json, filled │
│ a test              │               │ shoots, uses)│   │ by a Meshy model or a shape  │
└─────────────────────┘               └──────┬───────┘   └─────────────────────────────┘
                                             │ walks into / interacts with
                     Collectible · Npc · Portal · Enemy · Place · Prop  (game/kit/world, combat)
                                             │ Game.report("collected"/"talked"/"reached"/"defeated"/"built")
                                             ▼
          Autoloads:  Game (inventory, flags, save) → Missions (data/missions.json) → HUD
                      Levels (data/levels.json)  Dialogue (data/dialogue/)  Sound (sfx, music, voices)
```

Three ideas hold it together (details in [architecture.md](architecture.md)):
1. **Deciding is separate from doing.** The Player never reads the keyboard; something fills in a `MoveCommand`.
   That's why the autopilot, tests and screenshots can drive it.
2. **Content is data.** Items, levels, missions, dialogue, build pieces and visual slots are JSON in `data/`.
   Adding content is a data change plus a test, rarely new code.
3. **Art never changes gameplay.** Everything you see names a *visual slot*; collision sizes come from the slot,
   not the model. A new model can be dropped in at any time and nothing about play changes.

## Layout

```
Makefile, mk/*.mk        every workflow: `make help`
CLAUDE.md, HANDOFF.md    instructions; current state
project.godot            engine settings, input map, autoloads (comments explain the choices)
game/main.gd             snaps the pieces together; launch flags (--level, --autopilot, --screenshot…)
game/kit/                the reusable kit: player/, camera/, world/, combat/, missions/, ui/, build/, look/, audio/
game/levels/<id>/        the director's levels (one scene each; _template/ is copied by make new-level)
data/                    the game's content as JSON (items, levels, missions, dialogue/, slots, pieces, voices)
assets/models/           finished 3D models, one per visual slot (assets pipeline)
assets/audio, music, voices   sounds, music, voice lines (audio pipeline)
assets/review/           concept images and the review manifest (never shipped in the game)
tests/                   headless tests (make test); tests/support/ has fixtures
tools/                   Python + Godot tools: assets/, audio/, pages/, web_smoke/, lint.gd, new_level.py
_agents/                 these docs
build/                   everything make produces (screenshots, exports, pages); never committed
```

## First commands

```
make bootstrap      # once per computer: pinned Godot + export templates into .tools/
make doctor         # what's installed, and whether the Meshy / ElevenLabs keys are set
make check          # everything headless; ends with ">> check: ALL GREEN"
make demo           # watch the game play itself
make run            # play it
make shots          # a screenshot of every level -> build/screenshots/ (then LOOK at them)
```

## Trip-ups (each has bitten someone)

- **A new `class_name` is invisible to headless runs until `make import`.** Every make target that runs the game
  imports first. If you run Godot by hand and get "Identifier not found", import.
- **Never run two headless Godots in this folder at once**: they corrupt `.godot/`, and the errors look like
  broken code. Make targets take a lock (`$(LOCK)` in the Makefile); use the targets.
- **Forward is −Z, Y is up, positive `rotation.y` turns LEFT.** (`godot_basics.md`)
- **Physics only moves on physics frames.** In tests, `await wait_physics_frames(n)` after you push something.
- **Engine warnings and errors fail tests.** That's deliberate. If a test *means* to cause one, declare it with
  `expect_error()` / `expect_warning()`.
- **Read the summary line**, not an exit code through a pipe: `N passed, M failed`, `>> check: ALL GREEN`,
  `lint: all N scripts compile`. A count of zero is not a pass.
- **The browser build only uses the Compatibility renderer** (already set). Don't switch to Forward+.
- **Screenshots need a display.** `make shot` / `make shots` / `make run` open a window; tests and exports don't.
