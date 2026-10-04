# HANDOFF

> **Read [`_agents/orientation.md`](_agents/orientation.md) next**, then invoke the `session` skill.
> This file is the game's current state. Update it at the end of every session (the `session` skill says how).

_Last updated: (template, before day one)_

## Where the game stands

**A blank slate.** Nothing in this game is the director's yet. What exists is a working **starter kit** that
proves everything works end to end:

- a third-person character you can walk, sprint, jump and shoot with (WASD / arrows / gamepad, mouse to look),
- two sample levels joined by portals (`meadow`, `hilltop`),
- a friendly NPC with dialogue, three sample missions, stars to collect, two slimes to chase off,
- build mode (B) to place blocks, a save file, a HUD,
- placeholder shapes for every model (the `make-model` skill replaces them) and placeholder sounds (the
  `make-sound` skill replaces them),
- tests, screenshots, a browser build.

All of it is **sample content to be replaced**: the kit (`game/kit/`) stays, and the content (`data/`,
`game/levels/`, models, sounds) becomes the director's. `make demo` shows the sample playing by itself.

`make check` was green on the foundation at its last commit (see `FOUNDATION.md` for the hash and machine).

## Setup (before day one)

Not done yet. If this repo has no `foundation` remote, or no `origin` (their own GitHub repo), use the
**`setup-my-game`** skill first (about 10 minutes): their game's name, signing this folder in to their GitHub,
their own private repo, the first backup. Then Day one.

## Day one (the first session)

Goal: by the end, the director has **told you their idea**, **picked** how a few things look, **learned one
thing**, and **played one thing that is theirs**: their world's ground and sky, and their hero walking around
in it. And it's all backed up on their GitHub.

Remember who you're talking to: an 11- or 13-year-old. Short, plain, one question at a time (`CLAUDE.md`).

1. **Say hi and ask for the idea.** One or two lines. "Tell me about the game you want to make. What do you do
   in it? Where does it happen?" Let them talk. Ask one follow-up at a time: what's the most fun moment, who
   are you, what's the first thing you'd do. If you don't know their age yet, ask casually and note it in
   `game_design.md` (it changes how you explain things).
2. **Write it down in their words** in `_agents/game_design.md` (*The idea* and *The director's words*).
   Read it back in two sentences and ask if that's right.
3. **Find the first playable slice.** The smallest version that's already fun, e.g. "you land on the lava
   planet, walk around, and collect three fire crystals". Put the big dream on the *Someday* list so nothing
   is lost. Propose the slice and let them adjust it.
4. **Set the look.** Ask for 3 words for the style ("cute, glowing, spooky"). Write the art direction with them
   (`_agents/art_direction.md`, the `make-model` skill). Then make 2–3 concept images of **their hero** and put
   them on a choices page. They pick.
5. **Make it theirs today**, without waiting for any 3D: turn the meadow into their first place (ground and sky colours, a name), swap the stars for their collectible
   (`data/items.json`), and write the first NPC's lines with them (or remove the NPC). Run `make check`,
   `make shot`, look at the screenshot, then `make run` for them to play.
6. **If time remains**, send the picked hero concept to 3D (`make-model`) and drop it in, or make their first
   sound (`make-sound`).
7. **The first learning moment**: while doing step 5, let them duplicate a collectible in the editor or change
   a number in the Inspector themselves (`teaching.md`, ideas #1–2). Record it in `teaching_notes.md`.
8. **Close the session** (the `session` skill): update this file, `game_design.md`, `teaching_notes.md`,
   `roadmap.md`, commit, and `make backup`. Show them their save point on GitHub.

## Next steps

(Fill in at the end of each session: what was done, what the director wants next, any open choices pages.)

## Open choices pages

(Published pages waiting for the director's taps: name, link, what it decides.)
