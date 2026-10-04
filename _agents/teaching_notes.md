# Teaching notes: what the director is learning

Claude keeps this up to date every session (`teaching.md` says how to teach). Two parts: the **Skills** table
(where they are on each idea) and the **Learning log** (one entry per learning moment, newest first).

## Skills

Stages: — not yet · **I do** (seen Claude do it) · **we do** (did it with help) · **you do** (did it alone).
Move a skill forward only when they've done it well. Add rows when they learn things not listed.

| # | Skill | Stage | Since |
|---|---|---|---|
| 1 | Games are made of pieces (scenes, nodes) | — | |
| 2 | Tuning numbers in the Inspector | — | |
| 3 | Writing content in data files (dialogue, missions, items) | — | |
| 4 | Save points and backups (git, GitHub) | — | |
| 5 | Variables and `if` | — | |
| 6 | Functions and signals | — | |
| 7 | Coordinates and movement | — | |
| 8 | Finding bugs (errors, `print`) | — | |
| 9 | Tests | — | |
| 10 | Writing a small script | — | |
| 11 | Writing prompts for models and sounds | — | |
| 12 | Planning a feature in steps | — | |

## Learning log

(Newest first. Date, the idea, what they did hands-on, their one-sentence recap in their words.)

## Ready-made explanations

Concepts written so they can be re-explained or shown again. **Append; don't rewrite.** Format: **Concept**, the
one-line version, and a way to *show* it (something to click or change and watch).

---

### Scenes are Lego, scripts are behaviour
- **One line:** a scene is a reusable bundle of things; a script gives one thing its behaviour. A level is a
  scene; the player is a scene; the game snaps them together.
- **Show it:** `make editor`, open the meadow, select `Star1`, Ctrl+D to duplicate it, drag the copy somewhere,
  F5. There's one more star to collect.

### Deciding vs doing
- **One line:** the player doesn't read the keyboard. Something decides (you, the autopilot, a test) and the
  player does it.
- **Show it:** `make run` (you drive) vs `make demo` (the autopilot drives). Same player, different decider.

### Numbers you can tune
- **One line:** `@export` numbers show up in the Inspector, so you can change how the game feels without code.
- **Show it:** open `game/kit/player/player.tscn`, click `Player`, change `Jump Velocity` from 6 to 12, play.

### Content is data
- **One line:** the missions, items and dialogue are text files in `data/`. Change the file, change the game.
- **Show it:** open `data/dialogue/guide_hello.json`, change what the Guide says, `make run`, talk to them.

### Tests: the game checks itself
- **One line:** tests are little robots that play a bit of the game and check it worked, so new things can't
  quietly break old things.
- **Show it:** `make test FILTER=player`. Then change `walk_speed` to 0 in `player.gd`, run it again, watch it
  fail, and put it back.
