---
name: make-model
description: Turn something the director (the kid) imagines - a character, creature, monster, pickup, prop, tree, building piece - into a 3D model in the game with Meshy - concept pictures, the kid picks one on a choices page, then 3D, fitted into a visual slot. Use whenever the kid wants a new thing to look a certain way, or wants a placeholder shape replaced with real art.
---

# Make a model

The kid decides how everything looks. You make the options, they pick, and you build. Go at their pace and show them
pictures at every step. Reference: `_agents/assets.md`. Every step is a make target and prints its credits.

## 0. Once per game: the art style

If `_agents/art_direction.md` still says TODO under **Style prompt**, choose the style with the kid first (that file
says how). `make art-concept` refuses until it's filled in.

## 1. The slot

- Find the slot in `data/slots.json` (`make assets-slots`). New thing? Add a slot: a lower_case name, `kind`,
  `size_m` [width, height, depth] in real metres (ask the kid how big it is next to them), `placeholder`, `color`,
  `tris` (`_agents/assets.md`, Budgets), and `notes` saying what it is in kid words.
- Ask the kid to describe it. Write their words down.

## 2. Two or three pictures

Turn their words into 2-3 **different** ideas, each a short concrete description (see *Writing prompts*):

```bash
make art-concept SLOT=enemy_lava PROMPT="a round lava blob with a cracked rock crust and big eyes" TITLE="Lava blob" NOTE="cute, easy to spot"
make art-concept SLOT=enemy_lava PROMPT="a rock golem with glowing orange cracks" TITLE="Rock golem" NOTE="scary, chunky"
```

Open every picture (`assets/review/images/<id>.jpg`) and look at it. Remake any bad one before the kid sees it.

## 3. The kid picks

```bash
make art-choices NAME=lava_monsters      # the spec: build/pages/lava_monsters.spec.json
```

Then follow the `choices` skill: `make choices-page NAME=lava_monsters`, publish, let the kid tap, then
`make choices-apply NAME=lava_monsters IN=...`. Then record the picks:

```bash
make art-decide NAME=lava_monsters
```

"None of these" means: read their note, make new pictures, and offer them again. Never pick for them.

## 4. 3D, fitted into the slot

Tell the kid it costs about 15 credits, then:

```bash
make model-generate SLOT=enemy_lava      # ≈15 credits, takes a few minutes
make model-fit SLOT=enemy_lava           # size, feet on the ground, facing -Z, triangle budget
make model-look SLOT=enemy_lava          # build/screenshots/look-enemy_lava.png
```

**Read the look picture.** Is the face on the FRONT arrow's side? If not, run `make model-look-raw IN=assets/incoming/<id>.glb`,
then refit with `FORWARD=+x` (or `-x`, `-z`). Does it glow in the picture but not here? Refit with `GLOW=1`.

## 5. The kid sees it in the game

Run the game and let them walk up to it. Ask: keep it, or change something? A change means new pictures
(back to 2) or a refit, never a silent fix. Then:

```bash
make assets-check && make check
```

Commit `data/slots.json`, `assets/models/`, `assets/review/`, `assets/meshy_ledger.md` and `assets/incoming/<id>.json`
(the raw `.glb` stays on this computer: `.gitignore`), with the kid's words in the message.
