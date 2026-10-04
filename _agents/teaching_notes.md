# Teaching notes

Concepts the director met, written so they can be re-explained or shown again. **Append; don't rewrite.**
Add an entry when something confused them and then clicked, or when they asked "how does that work?".

Format: **Concept**, the one-line version, why it matters, and a way to *show* it (something to click or change
and watch). Seed entries below are from the kit; mark which ones the director has actually seen.

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
