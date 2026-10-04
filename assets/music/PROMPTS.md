# Music: making a track in Suno, and getting it into the game

The game's music is made by the director (the kid) at **suno.com**. The agent coaches the prompt; the kid makes the
track, listens, and decides. Then `make music-import` turns the download into a seamless loop the game can play.
How the pipeline works: `_agents/audio.md`. The agent's step-by-step: `.claude/skills/make-sound/SKILL.md`.

## What a game track needs (different from a song)

- **Instrumental.** Words fight with the dialogue and get annoying on the 40th loop. Toggle *Instrumental* on.
- **Steady.** One mood the whole way through: no big build-up, no drop, no long quiet break. It plays under the game
  for minutes; the player should feel it, not follow it.
- **Loops.** The importer finds the loop itself, but it can only loop what repeats. "Steady groove, repeating"
  helps; "epic journey through many sections" does not.
- **A tempo** in the prompt ("90 BPM"). Pass the same number as `BPM=` on import and the loop lands on whole bars.
- **Not too busy in the middle.** Footsteps, pickups and voices live in the mids; leave them room ("light", "airy",
  "soft", "background", "minimal").

## A prompt in four parts

Suno's **Style of Music** box. Keep it to one line of comma-separated words:

1. **Genre / feel:** `cozy adventure game music`, `mysterious cave ambient`, `bouncy chiptune`, `calm lofi`.
2. **Instruments (2-4):** `marimba, soft strings, light hand drums`, `warm synth pads, plucked harp`.
3. **Mood words from the kid** (ask them: "how should it feel to be here?"): `curious`, `sunny`, `sneaky`, `brave`.
4. **Game words:** `instrumental, loopable, steady, 90 BPM, video game background music`.

Optional **Lyrics** box (with Instrumental on, Suno reads these as structure hints):

    [Instrumental]
    [Intro: soft pad swell]
    [Main: steady groove, marimba melody]
    [Main: same groove, melody an octave up]
    [Outro: gentle ending]

## Starter prompts (change them with the kid's own words)

| Place | Style of Music |
|---|---|
| A meadow / home base | `cozy adventure game music, marimba, acoustic guitar, soft strings, light hand percussion, sunny, curious, instrumental, loopable, steady, 90 BPM` |
| A lava planet | `tense sci-fi exploration music, deep synth bass, low taiko drums, distant choir pads, hot, rumbling, brave, instrumental, loopable, steady, 100 BPM` |
| Food land | `bouncy whimsical game music, pizzicato strings, xylophone, tuba, playful, silly, sweet, instrumental, loopable, steady, 110 BPM` |
| An alien-invaded planet (story mode) | `cinematic sci-fi adventure, pulsing synths, orchestral brass, steady drums, determined, mysterious, instrumental, loopable, 105 BPM` |
| A national park | `gentle outdoors music, fingerpicked acoustic guitar, flute, soft piano, birdsong feel, peaceful, wonder, instrumental, loopable, 85 BPM` |
| A cave / night | `mysterious ambient game music, soft bells, warm low drone, gentle plucks, quiet, curious, instrumental, loopable, steady, 70 BPM` |
| Boss fight | `energetic battle music, driving drums, electric bass, bold brass stabs, exciting but not scary, instrumental, loopable, 130 BPM` |
| Victory / menu | `triumphant cheerful game menu music, bright brass, bells, strings, proud, happy, instrumental, loopable, 100 BPM` |

Suno makes two takes per prompt. Let the kid listen to both (and generate again if neither is right). **Their ear
decides.** Download the one they pick as MP3 (the WAV is fine too).

## Import it

    make music-import IN=~/Downloads/"Lava Planet.mp3" ID=lava_theme BPM=100 RIGHTS="Suno Pro, 2026-10-04"

- `ID` is the name the game uses: `Sound.music("lava_theme")`, or `"music": "lava_theme"` for a level in
  `data/levels.json`. Re-importing the same ID replaces the track (`ID=explore` replaces the placeholder).
- Optional `FROM=0:12 TO=2:05`: use only that stretch (skip a long intro, stop before the ending). Without `FROM`
  the importer starts where the music is in full swing; without `TO` it may use everything up to the fade-out.
- It finds the loop, cross-fades the end into the start, levels it to -18 LUFS, writes `assets/music/<ID>.ogg`, and
  records it in `assets/music/music.json`. Then `make music-check`, `make import`, and play it.
- **Listen to the loop point with the kid.** If the jump back is noticeable, import again with a different
  `FROM`/`TO` (move them by a bar or two); `make music-check` catches clicks and a fade-out in the loop.

## Rights

What you may do with a Suno track depends on the plan it was made under: the free plan is non-commercial, paid plans
allow commercial use (check suno.com's current terms). Record the plan and date with `RIGHTS="Suno <plan>, <date>"`;
`music.json` keeps it, and `make music-check` reminds you while it is missing. Playing the game at home is fine either
way; it matters before the game is shared or sold.
