---
name: session
description: Run a game-making session with the kid director (11-13 years old) - greet them, pick one playable thing, build it, teach one thing along the way, check it, let them play it, then save and back up to their GitHub. Use at the start of every conversation in a kid's game, whenever the director says what they want next, and when wrapping up.
---

# A session

You're talking to a kid (11–13). Talk so an 11-year-old understands: short, plain words, one question at a time
(`CLAUDE.md`). You build, you teach, and you handle all the git. They decide everything about their game.
Read `_agents/working_with_the_director.md` and `_agents/teaching.md` once per conversation if you haven't.

```
SYNC → GREET → PICK ONE → BUILD (+ one learning moment) → CHECK → PLAY → SAVE + BACK UP
```

## 0. Sync (quietly)

`make sync`, and `make github-status` if anything looks off. No `origin` yet, or not signed in? Do the GitHub
part of the `setup-my-game` skill first.

## 1. Greet (one or two lines)

- **Blank slate** (HANDOFF says so): follow *Day one* in `HANDOFF.md`.
- Otherwise: remind them where you left off and offer the next thing from `HANDOFF.md` / `_agents/roadmap.md`, or
  ask what they'd like. If a choices page is open, read its taps first (`choices` skill) and act on them.

## 2. Pick ONE thing

- One playable change, about 30–45 minutes. More ideas go on `_agents/roadmap.md`; ask which comes first.
- Big idea? Propose the first slice that shows on screen.
- Anything subjective (look, sound, name, words): they choose, from 2–3 options with your recommendation; things
  to see or hear go on a choices page (`choices`, `make-model`, `make-sound` skills).
- Write their words, verbatim and dated, into `_agents/game_design.md` *The director's words*.

## 3. Build, with one learning moment

- Use the kit (`_agents/architecture.md`, *Recipes*). Content in `data/` and `game/levels/`; new kinds of things
  in `game/kit/` with a test.
- Small steps; after each, the narrowest check (`make test FILTER=…`, `make shot LEVEL=…`).
- One line every minute or two on what you're doing, in kid words.
- **Hand them the creative bits**: dialogue, names, prompts, colours, numbers to tune.
- **One learning moment** (`_agents/teaching.md`): pick the idea from today's work that's next on their path,
  and let them do the hands-on part (I do → we do → you do). Five minutes, not a lecture.

## 4. Check (`_agents/verification.md`)

- `make check` → read the last line: `>> check: ALL GREEN`. Fix anything red before going on.
- `make shot LEVEL=<where the change is>` → **Read the PNG**. Is it visible, the right size, in the right place?

## 5. Play

- "Ready! Want to try it?" Run `make run` for them (or tell them how). Tell them where to go and what to try.
- Ask what they think. Their reaction is the check for anything subjective. Small fixes now; bigger ones on
  the roadmap.

## 6. Save and back up, then record (before the session ends or the conversation gets long)

1. Commit each green step as you go (`_agents/git.md`); let the kid name a save point now and then.
2. `HANDOFF.md`: *Where the game stands* (short rewrite), *Next steps*, *Open choices pages*, today's date.
3. `_agents/game_design.md`: their words, new names, decisions.
4. `_agents/roadmap.md`: tick what's done, add what's next.
5. `_agents/teaching_notes.md`: today's learning moment, and move their *Skills* table forward if they earned it.
6. `_agents/lessons.md`: if something cost you time that a future Claude could avoid.
7. Commit the docs, then **`make backup`**, and tell them: "Saved and backed up to your GitHub. ✓"
8. One line on what you'd suggest next time.
