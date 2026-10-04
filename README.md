# Game Foundation

A starting point for making your own 3D game with Claude. You have the ideas and make the choices; Claude
builds it with you, one playable step at a time.

## Starting (kids)

You only type three things yourself. Open a terminal and type:

```
git clone <the link your parent gives you> my-game
cd my-game
claude
```

Then say hi. Claude takes it from there: it will help you name your game, connect it to **your** GitHub account
(you'll type a short code on github.com), and start building with you. You never have to remember any git
commands: Claude makes the save points and backs everything up to your GitHub.

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

- **Before the kids start:** push this foundation to GitHub (`FOUNDATION.md` says how) and give them its clone
  link. Make the foundation repo **public** (it has no secrets) so the kids' first `git clone` needs no password. Each kid needs: a GitHub account, git, Python 3, `make`, `ffmpeg`, and Claude Code. Godot and GitHub's
  `gh` tool download themselves into the game folder (`make bootstrap`, `make gh`).
- Each kid's GitHub sign-in is stored inside their game folder (`.gh/`, never committed) and used for that repo
  only, so it doesn't touch your GitHub account on a shared computer.
- API keys for Meshy (3D models) and ElevenLabs (sounds and voices) go in
  `~/.config/game-foundation/keys.env` (`export MESHY_API_KEY=…`, `export ELEVENLABS_API_KEY=…`). `make doctor`
  says whether they're set. Every paid request is logged with its cost in `assets/meshy_ledger.md` and
  `assets/audio/elevenlabs_ledger.md`.
- Claude backs the game up to the kid's own **private** repo routinely (`_agents/git.md`); force-pushes and
  history rewrites are denied in `.claude/settings.json`. Anything **public** (a playable web link, itch.io) needs
  your yes (`_agents/sharing.md`).
- How it all works: `CLAUDE.md`, `HANDOFF.md`, `_agents/`. Maintaining the foundation itself: `FOUNDATION.md`.
