# Audio: sound effects, voices, music, and the `Sound` service

Three pipelines feed one runtime service. The kid's ear decides every sound; the agent makes options and builds.
The do-this version for the kid's agent is `.claude/skills/make-sound/SKILL.md`; this is the reference.

| What | Source | Lives in | Made by | Played by |
|---|---|---|---|---|
| Sound effects | ElevenLabs sound effects (or free placeholders) | `assets/audio/sounds.json` -> `assets/audio/sfx/<id>_v<n>.ogg` | `make sounds`, `make sounds-placeholders` | `Sound.play(id, at)` |
| Voices | ElevenLabs text-to-speech | `data/voices.json` + `data/dialogue/*.json` -> `assets/voices/<line id>.ogg` | `make voices` | `Sound.voice(line_id)` (the dialogue box calls it) |
| Music | Suno (the kid makes it on suno.com) | `assets/music/<id>.ogg` + `assets/music/music.json` | `make music-import` | `Sound.music(id)` |

Choosing by ear: `make audio-choices` makes 2-3+ takes and a choices-page spec; the kid taps; `make audio-apply` puts
the picks in the game (`_agents/choices_pages.md` for the page itself). `make audio-check` (in `make check`) guards it
all. Nothing needs a key until you make real audio: placeholders are synthesised locally (CC0), and missing audio is
silent, never an error.

## The runtime: `Sound` (game/kit/audio/sound.gd, an autoload)

```gdscript
Sound.play("pickup")                    # no position: menus, "you got it!" (UI bus)
Sound.play("footstep", self)            # 3D, rides on a Node3D (Node2D -> 2D positional) (SFX bus)
Sound.play("hit", global_position)      # 3D at a spot. Use this for a node about to be freed (it takes the sound with it)
var hum = Sound.play("portal_hum", self) # a loop (sounds.json "loop": true) ... Sound.stop(hum)
Sound.music("lava_theme")               # cross-fade (1.5 s), looping; same id again = nothing; "" = fade to silence
await Sound.voice("guide_hi_1")         # a dialogue line; music ducks 10 dB under it; await = until THIS line ends
Sound.set_volume("Music", 0.5)          # settings sliders: Master, Music, SFX, Voice, UI (linear 0..1)
```

- **Variants:** every `<id>.ogg` and `<id>_v<number>.ogg` in `assets/audio/sfx/` is a take of `id`; each play picks
  one at random, never the same twice in a row, with a +-5 % pitch wobble (`"pitch"` in sounds.json; 0 = off).
  An id may not end in `_v<number>` (sounds.json validation enforces it).
- **Per-sound settings** come from `assets/audio/sounds.json` at startup: `volume_db`, `pitch`, `loop`, optional `bus`.
  The export presets include `assets/audio/*.json`, so the exported game reads them too.
- **Missing anything** (sound, track, line, folder): one plain `print` per id ("Sound: no sound "x" yet, playing
  nothing (how to make it)") and nothing plays. Never `push_warning`: the test runner fails tests on engine warnings,
  and half-made audio is a normal state. A missing track leaves the current music playing. A missing line's signal
  fires next frame, so a dialogue awaiting it never hangs.
- The same sound asked for twice within 30 ms plays once (ten pickups in one frame are one ding). At most 32 positional
  sounds at once (more are skipped). Non-positional one-shots share 8 players (the oldest is reused).
- `voice()` returns a per-line signal; a new line cuts off the old one (whose signal fires next frame, so the awaiting
  code resumes outside the new call). `voice_finished(line_id)` fires for every line.
- Files generated while the game runs are found after `Sound.rescan()`. A fresh `.ogg` that Godot has not imported yet
  is played raw (`AudioStreamOggVorbis.load_from_file`), so `make sounds` then F5 works before `make import`.

### Buses (`default_bus_layout.tres`, at the repo root)

| Bus | Level | Gets |
|---|---|---|
| Master | 0 dB, HardLimiter ceiling -1 dB, **no pre-gain** | everything |
| Music | -6 dB (ducked -10 dB more under a voice) | `Sound.music` |
| SFX | 0 dB | positional sounds |
| Voice | 0 dB | `Sound.voice` |
| UI | -2 dB | non-positional sounds |

Godot loads `res://default_bus_layout.tres` by default (the project setting `audio/buses/default_bus_layout`).
Levels are set so that the pipelines' targets sit well together: effects at -16 dBFS (loudest 400 ms), voices at
-16 LUFS, music at -18 LUFS then -6 dB on its bus. Mixing a single sound: `volume_db` in sounds.json.

### 3D fall-off

Godot's inverse-distance model with `unit_size` 10 m, `max_db` 0, `max_distance` 150 m, distance filter -6 dB, panning
0.5. The listener is the camera, a third-person camera is 5-10 m behind the player, so the player's own sounds are at
full level and a sound 20 m away is about -6 dB, 40 m about -12 dB.

## Lessons carried over from Tank Squad (each cost real time there)

1. **Declare every bus in `default_bus_layout.tres`; never `AudioServer.add_bus` at runtime.** In the browser a bus
   created or re-routed at runtime silenced every sound after it. `Sound` falls back to Master if a bus is missing.
2. **The web build has no bus effects.** Godot's web export plays audio as "samples" (the default, and the right one
   for weak machines): volume, pitch and panning work, bus volumes work, but limiters/compressors/reverbs do not run.
   So the music duck is a bus-VOLUME tween (works everywhere), and on the web `Sound` trims Master -3 dB for headroom.
3. **No limiter with make-up gain on Master.** Tank Squad's old limiter lifted everything +3 dB and clamped every loud
   sound to the same level (a tank and a machine gun alike). A HardLimiter at `pre_gain_db = 0` only catches peaks.
4. **Distance must not kill the sound from a third-person camera.** Tank Squad's fight was 40-120 m from the camera and
   the default fall-off plus a -24 dB distance filter took 8-25 dB off; quiet distance is fine, inaudible is a bug.
5. **Levelled at the source, mixed in one place.** Every file is normalised by the pipeline, so `volume_db` in
   sounds.json and the bus levels are the whole mix; nobody edits a WAV to make it louder.
6. **A freed node takes its sounds with it.** A sound attached to a picked-up star stops when the star is freed;
   pass `global_position` for those. (Pruning freed players needs an untyped loop; a typed lambda errors.)

## Sound effects pipeline (`tools/audio/sfx.py`)

`assets/audio/sounds.json` is a list, one sound per line:
`{"id", "prompt", "duration" (0.5-30 s), "variants" (1-8), "loop", "volume_db"?, "pitch"?, "influence"? (0-1,
default 0.4), "placeholder"?}`. Write prompts about the physical event ("a wooden crate dropped on stone"), not the game.

`make sounds` makes every sound whose files are missing, still placeholders, or **stale** (prompt/duration/loop
changed since recorded: `assets/audio/made.json` stores a fingerprint per file). One request = one take =
`POST /v1/sound-generation` (model `eleven_text_to_sound_v2`, `loop: true` for loops). Each take is trimmed, levelled
(loudest 400 ms at -16 dBFS, peak under -1 dBFS, re-encoded lower if Vorbis overshoots), faded 10 ms at the end, and
encoded Ogg (one-shots mono, loops stereo, loop sounds get `loop=true` in their `.import`). A sound's takes are only
installed when all of them succeeded. The mp3 masters stay in `build/audio/masters/` (re-levelling is free).

`make sounds-placeholders`: a synthesised stand-in (blip, sweep_up/down, thump, click, whoosh, chime, fanfare, buzz,
thunk, hum) for every sound with no files, guessed from the id or set by `"placeholder"`. Never overwrites real takes.

## Voices pipeline (`tools/audio/voices.py`)

`data/voices.json`: `{"model": "eleven_multilingual_v2", "speakers": {"<name>": {"voice_id", "voice_name", "about",
"settings": {"stability", "similarity_boost", "style", "use_speaker_boost", "speed"}}}}`. Speaker names match the
dialogue's `speaker` ignoring case. The starters are ElevenLabs premade voices: narrator = George
(`JBFqnCBsd6RMkjVDRZzb`, warm British storyteller), guide = Jessica (`cgSgspJ2msm6clMCkdW9`, playful, bright).

Lines: every `{"speaker", "text", "voice": "<line id>"}` in `data/dialogue/*.json`, including inside `variants`. A line
without `voice` stays silent text. `make voices` records lines that are missing or whose text/voice/settings changed
(fingerprint in made.json); `FORCE=1` re-records. `POST /v1/text-to-speech/<voice_id>`; each clip is trimmed, levelled
to -16 LUFS, mono Ogg, `assets/voices/<line id>.ogg`. `make voice-list SEARCH=...` lists the account's voices
(`GET /v2/voices`, free).

## Music pipeline (`tools/audio/music.py`)

`make music-import IN=<suno.mp3> ID=<id> [FROM= TO= BPM= RIGHTS= TITLE=]`:
1. Decode, find the audible span. Start at `FROM`, else where the music is in full swing (first second within 6 dB of
   the track's typical level: a quiet intro would otherwise match the fade-out best).
2. Find the loop end: frames of 50 ms, (log energy, zero-crossing rate); the end whose next 3 s look most like the
   start's next 3 s, on whole bars from the start when `BPM` is given, longer loops winning near-ties, never inside the
   last 3 s (room to compare and cross-fade). Minimum loop 15 s (or half the section).
3. Cut [start, end + 1 s], equal-power cross-fade the 1 s after the end into the head: the wrap is continuous.
4. Level to -18 LUFS (peak under -1 dB), Ogg Vorbis q5 stereo, `loop=true` in the `.import`, a row in `music.json`:
   `{file, title, source, from_file, section_s, loop_s, bpm, lufs, peak_db, rights, imported, placeholder?}`.

`make music-check`: every row's file exists and is `<id>.ogg`, loudness within 2 LU, peak under -1 dB, at least 4 s,
the wrap has no sample jump (over 4x a typical step) and no level jump (over 6 dB: a fade-out in the loop), a rights
note. "Rights not recorded" and placeholders are notes, not failures. Suno guidance for the kid:
`assets/music/PROMPTS.md`.

## Choosing by ear (`tools/audio/choices.py`)

`make audio-choices NAME=<slug> SOUNDS=a,b LINES=l1 SPEAKER=guide VOICES=id1,id2,id3 [TEXT= N=]` builds
`build/pages/<slug>.spec.json` and runs `make choices-page`. Questions: `sound.<id>` (pick_one, or pick_many when the
sound has variants: the picks become the rotation and sounds.json's `variants` follows), `line.<id>` (pick_one),
`speaker.<name>` (pick_one; each voice says one of that speaker's lines). A sound already recorded for real adds a
"The one in the game now" option. Takes are kept in `build/audio/candidates/` and reused while the prompt/text is
unchanged (rebuilding a page is free; it needs no key then). The option->file map is
`build/audio/candidates/<slug>.choices.json`. `make audio-apply NAME=<slug>` reads `data/decisions/<slug>.json`; an
empty pick = "none of these": it prints the note and touches nothing.

## Costs and keys

- Key: `ELEVENLABS_API_KEY` in `~/.config/game-foundation/keys.env` (the Makefile includes it). A real key starts with
  `sk_`; the dashboard's key *id* is refused before anything is sent.
- Sound effects: about **10 credits per second** of audio per take (measured on Tank Squad, ~60 runs). A 0.6 s
  footstep with 4 variants: ~24 credits. Speech: **1 credit per character** (multilingual v2; flash/turbo 0.5).
- Every paid run prints the estimate before and the account balance before -> after, and appends a row to
  `assets/audio/elevenlabs_ledger.md` (committed). A restricted key that may not read the balance records "?".
  `DRY=1` prices without sending.
- Free testing: `make audio-mock` (a pretend ElevenLabs on port 8099), then `MOCK=1` on any paid target; mock runs
  write `build/audio/mock_ledger.md`, never the real ledger.

## Tests

- `make py-test` runs `tools/audio/test_*.py`: every tool end to end against the mock in a throwaway copy of the repo
  layout (`AUDIO_REPO_ROOT`; the key is removed from the environment), plus the loop finder, cross-fade, recipes and
  the check. ~90 s on the laptop. No network, no credits.
- `make test FILTER=audio` runs `tests/test_audio_*.gd` against tiny fixtures in `game/kit/audio/fixtures/`: missing
  ids silent and warning-free, variants found and rotated, 2D/3D placement, freed carriers, loops stopped, music
  cross-fade and looping, voice duck and per-line signals, the bus layout (limiter without make-up).
- `make audio-check` must pass on a fresh clone (placeholders committed, nothing recorded yet).
