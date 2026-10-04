# Game Foundation

A starting point for making your own 3D game with Claude. You have the ideas and make the choices; Claude
builds it with you, one playable step at a time.

## Starting

1. Open a terminal in this folder and run `make bootstrap` (once per computer: downloads Godot).
2. Start Claude Code here and say hi. It knows what to do on day one: it will ask about your game.

## Commands you'll use

| Command | What it does |
|---|---|
| `make run` | Play your game |
| `make play-new` | Play from the very beginning (doesn't touch your save) |
| `make demo` | Watch the game play itself |
| `make editor` | Open your game in the Godot editor |
| `make shots` | Take a picture of every level (in `build/screenshots/`) |
| `make check` | Check that everything still works |
| `make help` | Every command there is |

**Controls:** WASD or arrows to move, mouse to look (click the window first; Esc lets the mouse go), Space to
jump, Shift to sprint, E to talk or use, F or click to shoot, B for build mode (Q next piece, R turn, E place).
A gamepad works too.

## For parents

- API keys for Meshy (3D models) and ElevenLabs (sounds and voices) go in
  `~/.config/game-foundation/keys.env` (`export MESHY_API_KEY=…`, `export ELEVENLABS_API_KEY=…`). `make doctor`
  says whether they're set. Every paid request is logged with its cost in `assets/meshy_ledger.md` and
  `assets/audio/elevenlabs_ledger.md`.
- Claude never pushes or publishes without you (`git push` is denied in `.claude/settings.json`; sharing is in
  `_agents/sharing.md`).
- How it all works: `CLAUDE.md`, `HANDOFF.md`, `_agents/`. Maintaining the foundation itself: `FOUNDATION.md`.
