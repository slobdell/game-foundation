---
name: session
description: Run a game-making session with the kid director - greet them, pick one playable thing, build it, check it, let them play it, and record what happened. Use at the start of every conversation in this repo, whenever the director says what they want next, and when wrapping up.
---

# A session

The director is a kid making their own game. You build; they decide. Read
`_agents/working_with_the_director.md` once per conversation if you haven't. `HANDOFF.md` says where things stand.

```
GREET → PICK ONE → BUILD (small steps, say what you're doing) → CHECK → PLAY → RECORD
```

## 1. Greet (one or two lines)

- **Blank slate** (HANDOFF says so): follow *Day one* in `HANDOFF.md`.
- Otherwise: remind them where you left off and offer the next thing from `HANDOFF.md` / `_agents/roadmap.md`, or
  ask what they'd like. If a choices page is open, check its taps first (`choices` skill) and act on them.

## 2. Pick ONE thing

- One playable change, about 30–45 minutes. If they ask for more, write the rest on `_agents/roadmap.md` and ask
  which comes first.
- If it's big, propose the first slice that shows on screen ("first the volcano you can walk around, then the
  lava that hurts, then the house").
- Anything subjective (look, sound, name, words): they choose. Offer 2–3 options with your recommendation; for
  things to see or hear, use a choices page (`choices`, `make-model`, `make-sound` skills).
- Write their words about it, verbatim and dated, into `_agents/game_design.md` *The director's words*.

## 3. Build

- Use the kit (`_agents/architecture.md`, *Recipes*). Content goes in `data/` and `game/levels/`; new kinds of
  things go in `game/kit/` with a test.
- Small steps; after each, run the narrowest check (`make test FILTER=…`, `make shot LEVEL=…`).
- Every minute or two, one line on what you're doing. Hand them the creative bits while you do the plumbing:
  dialogue, names, prompts, colours, numbers to tune.

## 4. Check (`_agents/verification.md`)

- `make check` → read the last line: `>> check: ALL GREEN`. If it says FAILED, fix it before going on.
- `make shot LEVEL=<where the change is>` → **Read the PNG**. Is the new thing visible, the right size, the right
  place? Fix it if not.

## 5. Play

- "Ready! Run `make run` (or I can start it)." If it isn't obvious, tell them where to go and what to try.
- Ask what they think. Their reaction is the check for anything subjective. Act on it now if it's small,
  otherwise put it on the roadmap.

## 6. Record (before the session ends or the conversation gets long)

1. `HANDOFF.md`: *Where the game stands* (rewrite, short), *Next steps*, *Open choices pages*, today's date.
2. `_agents/game_design.md`: their words, new names, decisions.
3. `_agents/roadmap.md`: tick what's done, add what's next.
4. `_agents/teaching_notes.md`: if a concept clicked for them.
5. `_agents/lessons.md`: if something cost you time that a future Claude could avoid.
6. Commit with a plain message (`git add -A && git commit -m "…"`), only when `make check` is green.
   Never push or publish without a parent.
7. Tell them in one line what you'd suggest next time.
