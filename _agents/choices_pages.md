# Choices pages: how the director decides

The kid is the director: every subjective call (looks, sounds, music, colours, names, which ideas go in) is theirs.
Claude never decides those. It makes 2-3 options, puts them on a **choices page**, publishes it as a private
claude.ai Artifact with a database, the kid taps, and Claude reads the taps back into `data/decisions/<name>.json`,
which the asset and audio pipelines read. The short, do-this version is the skill: `.claude/skills/choices/SKILL.md`.
This doc is the reference: why it is built this way, the contracts, and the platform facts you would otherwise
have to rediscover.

This is the process Tank Squad (`~/projects/godot`) used for every subjective decision for 17 rounds (its concept
review page and audio audition page). What carried over: one tap writes one database document, the page shows the
saved state when reopened, a note box beside every choice, and a page that still works (read-only) outside the
Artifact viewer.

## The loop

| Step | Who | How |
|---|---|---|
| 1. Make the options | Claude | media into the repo (e.g. `assets/review/`, kept out of exports), 2-3 options per question |
| 2. Spec | Claude (or a pipeline tool) | `build/pages/<name>.spec.json` (contract below) |
| 3. Build + look | Claude | `make choices-page NAME=<name>`, then `make choices-shot NAME=<name> TAP=1` and look at the PNGs |
| 4. Publish | Claude | Artifact tool, values from `build/pages/<name>/publish.json` (`capabilities: {"db": {}}`) |
| 5. Tap | the kid | opens the link, taps, types why |
| 6. Read back | Claude | ArtifactData `list`, `collection: "choices"`, `out_dir: build/pages/<name>/taps` |
| 7. Record | Claude | `make choices-apply NAME=<name> IN=build/pages/<name>/taps` |
| 8. Build what they picked | Claude | the pipelines read `data/decisions/<name>.json` |

`make choices-demo` builds `build/pages/demo/` (placeholder pictures and sounds, every question kind) to try it.

## Contract 1: the spec (`build/pages/<name>.spec.json`)

```json
{"name": "<slug>", "title": "...", "intro": "...",
 "questions": [{"id": "...", "prompt": "...", "kind": "pick_one" | "keep_redo" | "pick_many",
                "options": [{"id": "...", "label": "...", "image": "<repo path>"?, "audio": "<repo path>"?,
                             "text": "..."?, "note": "..."?}]}]}
```

- `name`: lowercase slug, `[a-z0-9_-]`. It names the page's folder, the decisions file and (by file path) the
  Artifact. Use a **new name for each new page** (`hero_look_2`): republishing the same file path updates the same
  Artifact, and its database still holds the old taps.
- Question and option ids: letters, digits, `_ - .` (a question id becomes a database document id).
- `pick_one` and `pick_many` need at least 2 options. `keep_redo` usually has 1 (the thing to judge); it may show
  several (a set of sounds judged together). Its answer is `keep` or `redo`, never an option id.
- `image`: png, jpg, webp, gif, svg. `audio`: mp3, ogg, wav, flac, m4a, opus.
- `text` is shown on the card (good for name ideas and text-only options); `note` is the small grey tradeoff line.
- `tools/pages/choices_page.py` validates all of this and names the first problem.

## Contract 2: the database (what the page writes)

One document per question: `choices/<question id>`, written with `set()` on every tap and on every note change:

```json
{"pick": "<option id>" | ["<id>", ...] | "keep" | "redo", "note": "<the kid's words>", "at": "<ISO time>"}
```

Tapping your pick again un-picks it (`""` / `[]`). The note saves 1.2 s after typing stops, and on leaving the box.

## Contract 3: the decisions file (`data/decisions/<name>.json`)

```json
{"<question id>": {"pick": "<option id>" | ["<id>", ...], "note": "<kid's words>", "at": "<iso time>"}}
```

Written by `tools/pages/apply_choices.py` in page order. `pick_many` is always a list; `keep_redo` is `"keep"` or
`"redo"`. A question with no pick and no note is left out. **An empty pick with a note means "none of these"**: read
the note and make new options. Applying again merges: questions in the new dump replace their entries, others stay.
Picks that aren't on the spec are warned about but still recorded (the kid's tap is the truth).

## The Artifact platform: facts learned (runtime contract 0.2.67, October 2026)

Load the `artifact-capabilities` skill for the current, authoritative version; this is what the page relies on.

- **Publishing.** Artifact tool, `file_path` = the page, `capabilities: {"db": {}}`, a one-word `icon` (`"vote"`)
  on the first publish, a one-sentence `description`. Media written beside the page (only when they don't fit) go
  in `files: {"media/x.jpg": "build/pages/<name>/media/x.jpg"}`. The page file is wrapped in
  `<!doctype html><head>...</head><body>` at publish time, so the generated `index.html` starts with
  `<meta charset><title><style>` and has no html/head/body tags of its own (`<title>` must be in the first 8 KB).
  Republishing the same `file_path` in the same session updates the same URL; a new path makes a new Artifact.
- **Size.** 16 MB per page, embedded `data:` URIs included. The builder embeds media while they total under
  ~12 MB base64 (`EMBED_BUDGET`), downscales images to 1024 px (Pillow, else ffmpeg; JPEG unless transparent) and
  turns wav/flac into 128 kbit/s mp3 (ffmpeg). Over budget it writes `media/` beside the page and lists them in
  `publish.json` as `files` (15 MB per file there).
- **What the page can load.** Scripts only from cdnjs/jsdelivr/unpkg; stylesheets only from Google Fonts; images
  and audio only as `data:` URIs or files published beside the page. Audio plays only after a tap. No `alert()`.
- **The db API in the page.** `const db = await window.claude.use("db")` resolves the namespace, or `null` (not
  served/granted, e.g. a plain browser: then there is no `window.claude` at all). The promise resolves later than the
  first script run, so render first and light saving up when it resolves. `db.doc("choices/q1").set({...})` writes
  a whole document (path segments: letters, digits, `_ - . ~ : @ +`; even segment count = document);
  `db.collection("choices").onSnapshot(next, err)` delivers `{docs: [{id, exists, data()}]}` now and on every change;
  subscribe once. One write at a time per document, only on a real change (the page queues: newest state wins).
  Errors have a `code`: `invalid_argument` (also what a viewer without write access gets), `unavailable`, `revoked`...
- **Who can write.** By default the owner and anyone at Contributor level or higher. The kid opens the page signed in
  as the account that published it (theirs), so they are the owner. If the parent shares the link with someone at
  Viewer level, that person sees the picks but cannot change them.
- **Reading back (ArtifactData tool).** `action: "list"`, `url`, `collection: "choices"`. With `out_dir` it saves
  one pretty-printed file per document at `<out_dir>/choices/<doc id>.json` containing the bare document body
  (`{"pick":..., "note":..., "at":...}`; observed in Tank Squad's dumps). Without `out_dir` the documents come back
  inline; save that text to a `.json` file and pass it as `IN=`: `apply_choices.py` accepts a list of documents,
  `{"documents"|"docs": [...]}`, `{id: body}`, and entries shaped `{"id"|"doc_id"|"path", "data": body}`.
  A `list` returns up to 100 documents by default (plenty: one per question).
- **Checking after the first publish** (the platform's own rule): one ArtifactData `list` of `choices` to confirm it
  answers (empty is fine). Don't write test documents into the kid's page.

## Without the Artifact viewer

Opened as a plain file (or anywhere `claude.use("db")` gives `null`), the page still works: taps highlight, and
the footer shows a text summary and **Copy my picks**. The kid pastes that to Claude, who writes the decisions file
by hand in contract 3's format. `make choices-shot` runs the page against a pretend database (`fakeRuntime()` in
`tools/web_smoke/page_shot.mjs`), so the screenshots show the real saving state, and with `TAP=1` it taps the
first option of every question and checks each tap reached `choices/<id>` with the note.

## Files

| File | What |
|---|---|
| `tools/pages/choices_page.py` | spec -> `build/pages/<name>/index.html` + `publish.json` (validation, media prep) |
| `tools/pages/choices_page.html` | the page template (all CSS/JS; data goes in as JSON) |
| `tools/pages/apply_choices.py` | the read-back -> `data/decisions/<name>.json` |
| `tools/pages/make_demo.py` | placeholder media + the demo spec (`make choices-demo`) |
| `tools/pages/test_choices.py` | unit tests (`make py-test`) |
| `tools/web_smoke/page_shot.mjs` | screenshots + tap check (`make choices-shot`) |
| `mk/pages.mk` | the targets |

## Design notes

- Big tap targets (cards are buttons; 56 px pick buttons; 64 px keep/redo), one column on a phone, Atkinson
  Hyperlegible for reading (designed for legibility), light and dark themes from the viewer's setting.
- Questions are numbered "Scene 1 of 4": the kid is the director, and the order is real.
- Feedback a kid can trust: each question shows "Saving..." then "Saved ✓" (or a plain error); the bar at the top
  counts "3 of 4 picked" and says whether picks are saving.
- Changing your mind is free: tap another option, or tap your pick again to clear it.
