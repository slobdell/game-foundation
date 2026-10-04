# FOUNDATION: maintaining the template

This repo is **Game Foundation**, the template every kid's game starts from. You're here with the parent, not a
kid director. (In a kid's game, `git remote get-url foundation` succeeds and `CLAUDE.md` applies instead.)

## What it is and where it came from

The parent and Claude built **Tank Squad** (`~/projects/godot`), a large multiplayer tank RTS. What carried over
was not its game code but its **working loop**: a Makefile for every workflow, a `HANDOFF.md` that a fresh
agent can pick up from, `_agents/` docs that stay true, strict tests (errors fail tests; a gate must be able to
fail), screenshots Claude actually looks at, tap-to-pick choices pages so the human makes every subjective call,
and the asset (Meshy) and audio (ElevenLabs, Suno) pipelines. Those were generalised here. Left behind on
purpose: multiplayer, determinism, remote build machines, and parallel worktree agents (a kid's game is one
Claude and one director).

Decisions already made for the kids (so their Claude can focus on their game):
- **3D, third-person, Godot 4.7 GDScript, Compatibility renderer.** Every idea the kids had (lava planet,
  swamps, national parks, food land, space, a kingdom, superheroes) fits a third-person explorer. 2D would be a
  separate kit.
- **The kit** (`game/kit/`): player + camera + input/autopilot, collectibles, NPCs + dialogue, missions,
  levels + portals, combat (health, shots, a chaser enemy), build mode, HUD, save, visual slots, Sound.
- **Content as JSON** in `data/`, validated by `tests/test_data.gd`.
- **Visual slots**: art never changes gameplay; placeholders until a model exists.
- **The director decides anything subjective**, through choices pages.

## Making a kid's game

```
make new-game NAME="Lava Lover" DIR=~/projects/lava-lover DIRECTOR=<first name>
cd ~/projects/lava-lover && make check
```
Then open Claude Code in that folder with the kid. It starts with *Day one* in `HANDOFF.md`.
`new-game` clones this repo (remote `foundation`), names the game, shares the Godot toolchain, and marks the
director's files `merge=ours` so later updates never overwrite their game.

## Improving the foundation, and shipping improvements to the games

1. Work here on `main`. Kit changes go in `game/kit/` with tests; docs in `_agents/` and `.claude/skills/`.
2. Keep the sample content small and generic. It's meant to be replaced.
3. `make check` must end `>> check: ALL GREEN`; for visible changes `make shots` and look. Commit, then
   `make foundation-selftest` (a throwaway game cloned from the commit must pass `make check` too).
4. In each game: `make foundation-update` (fetches, merges, runs the check). Kit, tools and docs come across;
   the director's files (HANDOFF, game_design, data/, levels, assets, project.godot) are kept as they are.
   If a kit change needs a data change (a new field), say so in the commit message and in that game's HANDOFF.
5. Good improvements found inside a kid's game (a better enemy, a new mission step) can come back here:
   generalise, test, commit, then every game gets them.

## Ownership map (for parallel work on the foundation)

| Area | Paths |
|---|---|
| Core | `Makefile`, `mk/core.mk`, `mk/play.mk`, `mk/foundation.mk`, `tests/run_tests.gd`, `tests/test_case.gd`, `tools/lint.gd`, `tools/new_*.{py,sh}` |
| Kit | `game/`, `data/` (not `data/voices.json`), `tests/test_*.gd` for the kit |
| Assets (Meshy) | `tools/assets/`, `assets/pipeline/`, `mk/assets.mk`, `_agents/assets.md`, `_agents/art_direction.md`, `.claude/skills/make-model/` |
| Audio (ElevenLabs, Suno) | `tools/audio/`, `game/kit/audio/`, `mk/audio.mk`, `data/voices.json`, `assets/audio/`, `assets/music/`, `_agents/audio.md`, `.claude/skills/make-sound/` |
| Pages and sharing | `tools/pages/`, `tools/web_smoke/`, `tools/serve_web.py`, `mk/pages.mk`, `mk/web.mk`, `export_presets.cfg`, `_agents/choices_pages.md`, `_agents/sharing.md`, `.claude/skills/choices/` |

## Ideas for later

- A title screen and pause menu in the kit.
- Pathfinding enemies (NavigationRegion3D per level).
- A 2D variant of the kit, if a kid's idea is really 2D.
- Windows export templates, so friends without a browser-capable machine can play.
- Touch controls for phones/tablets in the web build.

## Status

(Update at the end of each foundation session: what changed, the last commit with a green `make check`, and
which machine ran it.)
