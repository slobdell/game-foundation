---
name: make-sound
description: Turn a sound the director (the kid) imagines into audio in the game - a sound effect ("a squishy footstep", "a laser zap"), a character or narrator voice ("the guide should sound like a pirate"), a recorded dialogue line, or music (they make it in Suno, you import it). ElevenLabs for effects and voices, a choices page so the kid picks by ear, then it plays in the game. Use whenever the kid wants something to sound different, a new sound, a voice, or new music.
---

# Make a sound

The kid's ear decides; you make options, they pick, you build. One step at a time, and let them listen at every step.
Reference: `_agents/audio.md`. Every paid step prints its credits and is written in `assets/audio/elevenlabs_ledger.md`;
say the cost out loud before you run it ("this costs about 30 credits").

## A sound effect

1. **Words.** Ask what it should sound like. Write a prompt about the *physical thing happening*: "a boot squelching
   into wet mud, one step", not "footstep sound for my game". Add texture words they say (squishy, sparkly, metal).
2. **Entry.** Add or edit its line in `assets/audio/sounds.json` (one sound per line):
   `{"id": "footstep", "prompt": "...", "duration": 0.6, "variants": 4, "loop": false, "volume_db": -8}`.
   `duration` 0.5-30 s (short is better for one-shots). `variants`: footsteps/hits 3-4, a fanfare 1.
   `loop: true` for wind, a humming portal, rain. New id? Free stand-in first: `make sounds-placeholders ONLY=<id>`.
3. **Takes to hear:** `make audio-choices NAME=<id>_pick SOUNDS=<id>` (PAID: about 10 credits per second per take;
   default 3 takes, more when `variants` > 1). It builds the page; publish and read the taps as in the `choices` skill
   (`make choices-apply NAME=... IN=...`).
4. **Apply:** `make audio-apply NAME=<id>_pick`. "None of these" comes back as a note: change the prompt with the
   kid's words, build a new page (`NAME=<id>_pick_2`).
5. **Hear it in the game:** `make import`, then play. Too loud or quiet? Change `volume_db` (-6 = half as loud).
   The code side: `Sound.play("<id>")` (no place), `Sound.play("<id>", self)` (follows a node),
   `Sound.play("<id>", global_position)` (a spot). Loops: keep what `play()` returns, `Sound.stop(it)` later.

Many sounds at once, no page (the kid already approved the prompts): `make sounds DRY=1` (the price), then `make sounds`.

## A voice for a character

1. Ask how they should sound (old, young, pirate, robot, fast, slow, grumpy). `make voice-list SEARCH="<word>"` (free)
   shows matching voices in the account. Not enough? On elevenlabs.io's Voice Library, add voices to "My Voices",
   then they appear in `voice-list`.
2. Pick 2-3 *different* candidates and let the kid hear them say one of that character's lines:
   `make audio-choices NAME=<speaker>_voice SPEAKER=<speaker> VOICES=id1,id2,id3` (about 1 credit per character each).
3. Taps, then `make audio-apply NAME=<speaker>_voice`: it sets `data/voices.json`. Fine-tune with the kid in
   `settings`: `stability` lower = more expressive, `speed` 0.7-1.2.
4. `make voices` records every line of theirs again in the new voice.

## Recorded dialogue lines

A line in `data/dialogue/*.json` gets a recording when it has a `"voice": "<line id>"` (unique, lowercase), e.g.
`{"speaker": "Guide", "text": "Ahoy!", "voice": "guide_ahoy"}`. The speaker must be in `data/voices.json` (case
doesn't matter). `make voices DRY=1` (price), `make voices` (records what is missing or whose text changed). To let the
kid choose between readings: `make audio-choices NAME=lines_pick LINES=guide_ahoy,guide_bye`.

## Music (the kid makes it in Suno)

1. Ask about the place: how should it feel to be there? Fast or slow? What instruments?
2. Write a Style-of-Music prompt WITH them using `assets/music/PROMPTS.md` (instrumental, steady, loopable, a BPM).
3. They make it on suno.com, listen to both takes, generate again until one is right, and download the MP3.
4. `make music-import IN=~/Downloads/<file>.mp3 ID=<place>_theme BPM=<the BPM> RIGHTS="Suno <plan>, <date>"`
   (add `FROM=0:15 TO=2:00` to skip an intro or ending). Then `make music-check` and `make import`.
5. Wire it: `"music": "<id>"` for the level in `data/levels.json`, or `Sound.music("<id>")`. Play it together and
   listen to the moment it loops; if it jumps, re-import with `FROM`/`TO` moved a bar or two.

## Before you say done

`make audio-check` (and `make check`). Then play it with the kid: only their ears can say it sounds right.
