# Art direction: how this game looks

> **Fill this in WITH THE KID on day one, before the first picture.** Every concept picture gets the style prompt
> below added to it (`tools/assets/generate.py`), so the whole game looks like ONE world instead of a pile of
> pictures from different games. Until the style prompt is filled in, `make art-concept` refuses to run.
> The kid decides every word of the look. You help them say it in words a picture generator understands.

## How to choose it with the kid (10 minutes)

1. Ask what games, films or books look like the world they imagine. Write their words down exactly, below.
2. Make **two or three style test pictures** of ONE simple thing from their game (the hero, or a tree), each in a
   different style, and put them on a choices page (the `make-model` skill shows how). Mood pictures and whole
   scenes need `KEEP_BG=1`. Use `--no-style` for these tests only (`tools/assets/generate.py concept --no-style ...`).
3. The kid picks one. Write the style prompt from **the picture they picked**, not from adjectives. When Tank Squad
   briefed from adjectives it took six failed concepts to notice. Once a picture is picked, pass it as a
   reference (`REFS=assets/review/images/<id>.jpg`): a reference carries a look far better than words do.
4. Fill in the sections below and commit them.

Good style prompts name a **look**, **colours**, **materials** and **lighting**, in 15-40 words. For example:
- *"chunky hand-painted fantasy, like a storybook, warm sunset colours, soft rounded shapes, thick outlines"*
- *"realistic and gritty, real-world materials with rust and dust, harsh desert sunlight"*
- *"glossy toy-like plastic, candy colours, smooth shiny surfaces, bright studio lighting"*
- *"low-poly flat-shaded, a few bold colours per object, no textures, clean geometric shapes"*

Don't put game words in it ("low poly game asset", "triangles") unless that IS the look the kid wants: the
pipeline handles budgets after the picture, and Tank Squad's first concept came out as a toy because of them.

## The kid's own words

TODO: what the kid said about how the game should look, quoted exactly, with the date.

## Style prompt

The ```text block below is added to every concept prompt. Keep it to one paragraph.

```text
TODO: fill in with the kid (see above)
```

## Picked reference pictures

The concept pictures that define the look (paths under `assets/review/images/`). Pass one as `REFS=` when a new
thing should match an existing one. A reference decides the **shape and proportion**, the prompt decides the
details: pick a reference shaped like the new thing.

- (none yet)

## Rules for this game

Anything the kid decided that every picture should follow (colours that mean something, things that never appear,
how big or small things are). Add to this as the game grows.

- No text or logos in generated pictures (generators garble letters; put signs and words on in the game instead).
