# 3D models: from "I want a lava monster" to a model in the game

> The kid's step-by-step is the `make-model` skill (`.claude/skills/make-model/SKILL.md`). This file is the
> reference behind it: the flow, the slot contract, budgets, costs, how to write prompts, and what goes wrong.
> The process comes from Tank Squad (`~/projects/godot`, where it made every vehicle and prop), made generic.

## The flow

```
data/slots.json      a slot: what the thing is, how big (metres), its triangle budget
      │  make art-concept SLOT= PROMPT=  (×2-3 different ideas)      ≈9 credits each
      ▼
assets/review/       concept pictures waiting for the kid
      │  make art-choices NAME=   →  make choices-page NAME=  →  publish, kid taps  →  make choices-apply
      ▼
data/decisions/NAME.json      the kid's picks, in their own words
      │  make art-decide NAME=
      ▼
approved concept     │  make model-generate SLOT=                                    ≈15 credits
      ▼
assets/incoming/<id>.glb      the raw download (wrong size, wrong way round, too many triangles)
      │  make model-fit SLOT= [FORWARD=]   (size, feet, facing, budget, web textures)
      ▼
assets/models/<slot>.glb      in the game: every ModelSlot showing this slot now draws it
      │  make model-look SLOT=   →  look at it yourself, then show the kid  →  make assets-check
```

**Nothing becomes 3D until the kid picks its picture** (`generate.py` refuses), and nothing goes to 3D twice
without a reason (`RETRY="..."`). A picture costs 9 credits and 3D costs 15, and fixing a model nobody wanted
takes a whole session. Picking between 2-3 pictures is fast and fun for the kid. Judging one picture on its own isn't.

Every Meshy request is appended to `assets/meshy_ledger.md` with its credits, and each command prints what it
cost and the total so far. `make art-status` shows every concept and the total; `make meshy-balance` shows what's
left on the account.

## The slot contract (`data/slots.json`)

Everything you can SEE names a slot. Until `assets/models/<slot>.glb` (or `.tscn`) exists, the game draws the
slot's coloured placeholder shape, so the game is always playable and art can arrive at any time.

| field | meaning |
|---|---|
| `kind` | `character`, `creature`, `pickup`, `prop`, `build`, `vehicle`, ... (picks the prompt tail and defaults) |
| `size_m` | `[width, height, depth]` in metres: the box the model must fit. Gameplay (collision) uses this, never the art |
| `placeholder`, `color` | the shape drawn until a model exists (`capsule`, `box`, `cylinder`, `sphere`, `prism`) |
| `tris` | triangle budget (see Budgets) |
| `notes` | what it is, in words; the choices page asks "Which one should be *notes*?" |
| `fit` *(optional)* | `contain` (default): scaled evenly until it just fits, proportions kept. `stretch` (default for `build`): each axis scaled to exactly `size_m`, so pieces tile on the grid |
| `textures` *(optional)* | largest texture edge in px. Default 1024 for characters, 512 for everything else |

**A finished model** is `res://assets/models/<slot>.glb`, standing with **its feet at the origin** (bottom at y = 0,
centred on x and z), **facing −Z**, already scaled to `size_m`, within its triangle budget. `make model-fit`
does all of that; `make assets-check` (part of `make check`) enforces it on every file in `assets/models/`, and on
`data/slots.json` itself. **A `<slot>.tscn` wins over `<slot>.glb`** (ModelSlot loads `.tscn` first): write one
only to wrap a model with something extra (a glow light, an animation). `model-fit` warns when one exists.
`assets/models/models.json` records where each model came from (concept, Meshy task, prompt, license note).

Adding a new slot: add a line to `data/slots.json` with a real-world size (measure: a door is 2 m, a person
1.7-1.8 m, a car 4.5 × 1.5 × 1.8 m), then `make assets-slots`.

## Budgets (the game runs in a web browser on ordinary laptops)

| kind | triangles | why |
|---|---:|---|
| the player character | 15-20k | seen up close all the time |
| other characters, creatures | 8-15k | |
| props (rocks, trees, furniture) | 2-6k | there are many of them |
| pickups, small things, build pieces | 1-2k | many on screen, small |

- `model-fit` simplifies anything over budget (Godot's meshoptimizer). It reports "simplified A → B triangles".
  Simplifying 3× is fine; 10× starts to melt details. Raise the slot's `tris` instead of losing what the kid liked.
- `generate.py` asks Meshy for ~85% of the budget (Smart Topology tops out at 15,000).
- **Textures:** the colour map is capped at the slot's `textures`, and normal/roughness/metallic maps at half of
  that (they barely show at game distance and are most of a model's download). Textures stay inside the GLB and
  import as **Basis Universal** (the `.glb.import` the pipeline writes): one file, ~¼ of the GPU memory, and it works in
  every browser. `make assets-textures` repairs the setting if a GLB was added by hand.
- **Draw calls:** one per material. `model-fit` merges surfaces that share a material; the check warns over 4.

## What it costs (Meshy Pro: $20 a month for 1,000 credits ≈ $0.02 a credit)

| request | credits |
|---|---:|
| concept picture (text-to-image or image-to-image, `nano-banana-pro`) | 9 |
| picture → 3D, normal (`meshy-t2` Smart Topology, textured) | 15 |
| picture → 3D, `QUALITY=high` (`meshy-6`, textured) | 30 |
| text → 3D with no picture (preview 20 + texture 10) | 30 |
| a failed task | 0 |

A typical model is 2-3 pictures plus one 3D, about **35-45 credits (~$0.80)**, so a month of Pro makes ~20-25 models.
The API needs a paid plan (the free plan has no API). On paid plans the customer owns the output; free-plan output
is CC BY 4.0 (credit Meshy). Meshy keeps result files ~3 days, so download promptly (the tools do).
Don't start spending on a big batch without telling the kid how many credits it takes, so they decide
what's worth it.

## Writing prompts

The kid describes the thing. **You turn it into a short, concrete description.** `generate.py` adds the game's style
(`_agents/art_direction.md`) and a tail that asks for one whole object on a plain background. So write only the
subject: what it is, its shape, its materials, its colours, one or two memorable details.

- **Be concrete.** "A round, friendly lava monster made of cooling black rock with glowing orange cracks, stubby
  legs, big round eyes" beats "a cool lava monster".
- **2-3 genuinely different ideas per slot**, not three versions of one idea: a rock golem, a lava blob, a fire
  salamander. Give each a `TITLE` the kid can read and a one-line `NOTE` (what's good or risky about it).
- **One thing per picture.** No scenes, no ground, no other characters: the 3D step turns the whole picture into
  one model. (The tail already says so; don't add "in a volcano" to the subject.)
- **No words or logos** in pictures: generators garble letters. Signs and text go on in the game.
- **Characters in an A-pose** (the tail asks for it): arms away from the body, so the 3D step can separate them and
  the model can be rigged later.
- **Don't add game words** ("low poly", "game asset") to save triangles: the pipeline handles budgets after the
  picture. In Tank Squad those words made the first concept look like a toy, and it was rejected.
- **A reference picture beats adjectives.** When something must match an existing look, pass a picked concept
  as `REFS=assets/review/images/<id>.jpg` (image-to-image). The reference decides **shape and proportion**;
  the words only decide details. If the shape must differ (a long bus, not a van), use a reference with that shape,
  because no wording will stretch it (Tank Squad spent 36 credits learning this).
- **Mood pictures** (a whole scene, to agree on a look for a level) need `KEEP_BG=1`, or background removal erases
  the scene. They never go to 3D.
- **The style is chosen once, with the kid, on day one** (`_agents/art_direction.md`). One look for the whole game.
  Write it from the picture they picked, not from adjectives. When the kid picks a concept that shows the look
  better than the words do, add it to "Picked reference pictures" there.

## Look at everything before the kid does

- **Every concept picture:** open each image (`assets/review/images/<id>.jpg`) before building the page.
  Regenerate failures under a new id and mark the bad one `make art-decide ID=... DECISION=superseded WORDS="why"`:
  a cropped object, two objects, garbled text, a scene instead of an object, the wrong thing entirely.
  The kid should only ever choose between good options.
- **Every fitted model:** `make model-look SLOT=...` writes `build/screenshots/look-<slot>.png`, four sides
  inside the slot's yellow box, with a red **FRONT** arrow (−Z) and a 1.7 m person for scale. Read the picture.
  Is the face on the FRONT side? Is it the right size next to the person? Is anything missing or melted?
- **Then the kid sees it in the game**: run it (`make run`), walk up to it. That is the check that counts.
- `make assets-gallery` shows every slot side by side (models and the placeholders still waiting).

## Failure modes and fixes (most learned the expensive way in Tank Squad)

| symptom | cause | fix |
|---|---|---|
| model faces sideways or backwards in `model-look` | the download didn't face +Z (generators often don't) | `make model-look-raw IN=<download>` shows its +X (red) and +Z (blue) axes; refit with `FORWARD=+x` / `-x` / `-z` (or `TURN=45`) |
| lying on its back / upside down | the source's up axis isn't +Y | `UP=+z` (or `-y` etc.) |
| "fills only width 30%" note, model looks thin | its proportions differ from `size_m` | fine for `contain`; or make `size_m` match the thing (the kid's thing decides, not the box) |
| "stretched 2.5× out of proportion" | a `stretch` slot and a differently shaped model | regenerate with a reference of the right shape, or make the slot `contain` |
| details melted | simplified 10× or more | raise the slot's `tris`, refit |
| arms fused to the body | character not in an A-pose in the picture | regenerate the picture (the tail asks for A-pose; say it again in the subject), `RETRY=` |
| picture is a whole scene, or the background was erased | scene prompt / background removal | object prompts only; `KEEP_BG=1` for mood pictures |
| it doesn't glow like the picture | Meshy's glow (emission) map isn't used by default; it comes in dim | `make model-fit SLOT=... GLOW=1` (or `GLOW=3` brighter). The map is the generator's guess, so look at it |
| a picked picture from days ago | Meshy forgets tasks after ~3 days | nothing to do: `model-generate` sends the saved picture itself, not the old task |
| `model-generate` refuses | not picked, or already built | `make art-status`; build only what the kid picked; `RETRY="why"` to pay again |
| HTTP 401 / 402 / 403 | wrong key / out of credits / plan without API | `make doctor`; a grown-up fixes the account |
| still `IN_PROGRESS` at the timeout | Meshy is slow today | check app.meshy.ai before asking again: asking again pays again |
| new model doesn't show in the game | a `<slot>.tscn` exists (it wins), or not imported | delete the `.tscn`; `make import` |
| two Godots at once corrupt `.godot/` | not via `$(LOCK)` | every target already locks; never run headless Godot by hand without `flock build/.godot.lock` |

## Practising and testing without spending

`make assets-mock` serves a pretend Meshy on port 8799 (no key, no credits, a textured box for every model).
Point the real commands at it with `MESHY_BASE_URL=http://127.0.0.1:8799 MESHY_API_KEY=mock make art-concept ...`.
Clean up what that run wrote (`assets/review/`, `assets/incoming/`, `assets/meshy_ledger.md`, the fitted model)
before committing, or the record will show pretend spending.

`make py-test` runs the whole concept → pick → 3D flow against the mock in a temporary folder
(`tools/assets/test_generate.py`), including the spec checked by the choices page's own validator. `make test
FILTER=assets` fits a real model (`tests/fixtures/models/broken_car.glb`, CC0 Quaternius) into slots
(`tests/test_assets_pipeline.gd`).

## Files

| path | what |
|---|---|
| `tools/assets/generate.py` | Meshy client: `concept`, `model`, `text3d`, `balance` (standard library) |
| `tools/assets/review.py` | concept manifest, the choices spec, applying the kid's picks, the ledger |
| `tools/assets/mock_provider.py` | the pretend Meshy |
| `assets/pipeline/pipeline.gd` | headless commands: `slots`, `inspect`, `normalize`, `check`, `textures` |
| `assets/pipeline/asset_{slots,normalizer,inspector,checker,io}.gd` | the contract, the fitter, measuring, the check, files |
| `assets/pipeline/model_look.gd` | the pictures: `model-look`, `model-look-raw`, `assets-gallery` |
| `assets/review/review.json`, `images/` | every concept, its prompt, task ids, status, the kid's words (committed) |
| `assets/incoming/` | raw Meshy downloads + `<name>.json` (task, prompt, license). Not imported by Godot (`.gdignore`). Only the `.json` is committed; the raw GLBs (10–20 MB each) are git-ignored and stay on this computer |
| `assets/models/` | finished models + `models.json` (where each came from) |
| `assets/meshy_ledger.md` | every request and its credits (committed) |

## Not built yet (ideas, in the order they'd matter)

- **Animated characters.** Models are static today (rigged downloads are frozen in their rest pose). Meshy can rig
  and animate (≈5 credits a rig, docs.meshy.ai), which would need a `.tscn` wrapper per slot with an
  AnimationPlayer and walk/idle names the game agrees on.
- **One model split into several slots** (a vehicle and its turret). Tank Squad's `AssetSplitter` did this.
- **Batches:** many concepts at once (Meshy allows 10 parallel tasks). Today run `art-concept` several times.
