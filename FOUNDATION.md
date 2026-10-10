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
- **Claude talks at an 11-year-old's level, teaches one hands-on thing per session** (`_agents/teaching.md`,
  progress in `teaching_notes.md`), **and runs all git and GitHub for the kid** (`_agents/git.md`): their own
  private repo, commits on every green step, a backup every session.

## How a kid's game is made

**The intended path (the kid does it, Claude guides):**
1. The parent pushes this foundation to GitHub once (below) and gives the kids its clone link.
2. The kid runs `git clone <link> my-game && cd my-game && claude`, and says hi.
3. Their Claude sees a fresh clone (no `foundation` remote, no maintainer flag) and runs the `setup-my-game`
   skill: `make start-my-game` (rename `origin` → `foundation`, name the game, protect the director's files with
   `merge=ours`), `make github-login` (browser device code; the sign-in is stored in the game folder's `.gh/` and
   wired into that repo only), `make github-create REPO=…` (their own **private** repo as `origin`, first push).
4. From then on Claude commits each green step and runs `make backup` every session (`_agents/git.md`).

**The local shortcut (the parent, on this computer):** `make new-game NAME="Lava Lover" DIR=~/projects/lava-lover
DIRECTOR=<name>` clones from this folder and runs the same `start-my-game`; the kid's Claude then does only the
GitHub part. `make foundation-selftest` uses it.

**This checkout is marked as the maintainer's** (`git config foundation.maintainer true`, local only; it is not
cloned), which is how Claude tells "maintaining the template" from "a kid's fresh clone". Set it again if you
re-clone the foundation to maintain it.

## Putting the foundation on GitHub (once)

```
make gh                                    # the project-local gh tool
GH_CONFIG_DIR=~/.config/gh .tools/gh-*/bin/gh auth login --web   # your own account, not a kid's
.tools/gh-*/bin/gh repo create game-foundation --public --source=. --remote=origin --push
```
**Public is recommended**: the foundation has no secrets (keys live in `~/.config/game-foundation/keys.env`,
sign-ins in git-ignored `.gh/`), and a kid's very first `git clone` happens before any GitHub sign-in exists, so
cloning a private repo would make them type a username and an access token. If it must be private: add each kid
as a collaborator (read access) and do the first clone for them (`make new-game`, or clone after
`gh auth login` as them); `make foundation-update` then works through the game's own sign-in. After that, `git push origin main` publishes
foundation improvements; each game picks them up with `make foundation-update`.

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
| Core | `Makefile`, `mk/core.mk`, `mk/play.mk`, `mk/foundation.mk`, `mk/git.mk`, `tools/github.sh`, `tools/start_my_game.sh`, `tools/setup/` (lock, timeout, shell wrapper, zip_members), `tests/run_tests.gd`, `tests/test_case.gd`, `tools/lint.gd`, `tools/new_*.{py,sh}` |
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

**2026-10-10: Mac support + one-command setup.** `4e764d2` ports the toolchain to macOS (per-OS Godot, gh,
project-local Python 3.12 and ffmpeg, portable lock/timeout helpers, make 3.81 / bash 3.2 compatible).
`tools/setup_mac.sh` + `make kid-setup-command` (prints the pasteable command with the parent's keys). The whole
setup script was run end to end on Linux in a throwaway HOME from a fresh clone: exit 0, the game's `make check`
ALL GREEN. Never yet run on a real Mac: watch the first one.

**2026-10-10: published.** Public at **https://github.com/slobdell/game-foundation** (`origin`), pushed from
`7fd8343`. The kids clone it with `git clone https://github.com/slobdell/game-foundation.git my-game`. An
anonymous clone (no sign-in) was checked to work. Publishing foundation improvements: commit, `make
foundation-selftest`, `git push origin main`. This checkout's GitHub sign-in is the lead's own (`~/.config/gh`).

**2026-10-04, second pass: kids as the audience.** Claude talks at an 11-year-old's level, teaches one hands-on
thing per session (`teaching.md`), and runs all git/GitHub (`git.md`, `setup-my-game` skill, `make gh /
start-my-game / github-login / github-create / backup / sync`). `make foundation-selftest` ALL GREEN at `8a8e5ca`
(laptop). Tested by hand in a scratch clone: start-my-game, backup and sync against a stand-in remote (including
a commit from "another computer"), and every refusal (not signed in, no origin, maintainer checkout).
`gh auth login` was checked to print its device code non-interactively; a real sign-in and `gh repo create` have
NOT been run yet (no kid account here): watch the first one.

**2026-10-04: first version.** `make check` ALL GREEN at `e22fd0c` on the laptop (58 Godot tests, 82 Python
tests, lint 51 scripts, export-web 39 MB). `make shots` and `make web-smoke` green and looked at.
`make foundation-selftest` green at `e22fd0c` (a fresh clone passes `make check`). `foundation-update` was tried by
hand: a kit doc change merged in, and the game's own HANDOFF.md was kept (merge=ours).
Not yet exercised with real credits: Meshy (mock only) and ElevenLabs (mock only). The first real run of each
should be watched by the parent: check the ledger lines match the provider's dashboard.
Known slow spot: `tools/audio` Python tests take ~87 s of `make check`'s ~3 min.
`.tools` in a new game is a symlink to the foundation's toolchain (which may itself point at another
project's); if that folder moves, run `make bootstrap` in the game.
