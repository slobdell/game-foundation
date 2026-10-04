---
name: choices
description: Let the director (the kid) make a subjective call by tapping on a "choices page" instead of you deciding. Use whenever something is a matter of taste - how a character, place or item looks, a sound or voice, music, a colour, a name, a title, which ideas go in - and whenever you made something they should approve (keep or redo). Builds the page, publishes it as an Artifact with a database, reads the taps back, records them in data/decisions/.
---

# Choices pages

The kid is the director. **You never pick anything subjective.** Offer 2-3 real options on a choices page, let them
tap, then build what they picked. Facts and engineering (how to code it, what file goes where) are yours to decide.
Full reference: `_agents/choices_pages.md`.

## 1. Make the options, then write the spec

- 2-3 options per question, clearly different from each other (not three near-identical blues). Every option is
  something you could really build next. For something you just made, ask `keep_redo`.
- Make the media first (pictures, sounds), saved in the repo. Paths in the spec are repo-relative.
- Words a kid reads: short prompts ("What colour is your hero?"), plain labels, one-line `note` for a tradeoff.
- Write `build/pages/<name>.spec.json`. `<name>` is a new lowercase slug per page (`hero_look`, `hero_look_2`):

```json
{"name": "hero_look", "title": "Hero Looks", "intro": "Pick the one you like best. Say why if you want!",
 "questions": [
   {"id": "colour", "kind": "pick_one", "prompt": "What colour is your hero?",
    "options": [{"id": "red", "label": "Rocket red", "image": "assets/review/hero_red.png", "note": "Easy to spot"},
                {"id": "teal", "label": "Sea teal", "image": "assets/review/hero_teal.png"}]},
   {"id": "jump", "kind": "pick_one", "prompt": "Which jump sound?",
    "options": [{"id": "boing", "label": "Boing", "audio": "assets/review/jump_boing.wav"},
                {"id": "zip", "label": "Zip", "audio": "assets/review/jump_zip.wav"}]},
   {"id": "powers", "kind": "pick_many", "prompt": "Which power-ups go in level 1?",
    "options": [{"id": "magnet", "label": "Cheese magnet", "text": "Cheese flies to you."},
                {"id": "shield", "label": "Bubble shield", "text": "One free hit."}]},
   {"id": "tune", "kind": "keep_redo", "prompt": "Keep this title tune?",
    "options": [{"id": "tune_v1", "label": "Title tune, try 1", "audio": "assets/review/tune_v1.wav"}]}]}
```

Kinds: `pick_one` (one), `pick_many` (any number), `keep_redo` (shows the thing; the answer is `keep` or `redo`).

## 2. Build it and look at it

```bash
make choices-page NAME=hero_look          # -> build/pages/hero_look/index.html + publish.json
make choices-shot NAME=hero_look TAP=1    # phone + desktop screenshots; checks taps save. LOOK at the PNGs.
```

## 3. Publish it

Call the **Artifact** tool with the values in `build/pages/<name>/publish.json`: `file_path`, `icon`,
`description`, `capabilities: {"db": {}}` (without `db` nothing saves), and `files` if listed. Do not change the page
by hand. Then tell the kid, in one or two short sentences: the link, what to do ("tap the one you like in each
scene, and say why if you want"), and "tell me when you're done".

## 4. Read the taps back and record them

When they say they're done (or before you build the next thing), read the page's database with **ArtifactData**:

```
action: "list", url: <the page's artifact url>, collection: "choices", out_dir: "build/pages/<name>/taps"
```

```bash
make choices-apply NAME=hero_look IN=build/pages/hero_look/taps   # -> data/decisions/hero_look.json
```

Read the printed table and the notes. Then build what they picked. An empty pick with a note means "none of
these": make new options from their words. Nothing tapped yet? Ask them to open the link; never guess for them.

If saving didn't work for them, the page shows **Copy my picks**: they paste the text to you, and you write
`data/decisions/<name>.json` by hand in the same format.
