#!/usr/bin/env python3
"""Free stand-in audio, so the game makes SOME sound before a single credit is spent. All of it is CC0 (made here).

    python3 tools/audio/placeholders.py              # a placeholder for every sound in sounds.json with no files yet
    python3 tools/audio/placeholders.py --music      # also the "explore" music loop
    python3 tools/audio/placeholders.py --only jump  # just these

Sounds: each entry of sounds.json gets `variants` synthesised takes of a simple recipe (a blip, a sweep, a thump, ...),
picked by its "placeholder" field or guessed from its id. Placeholders never replace a real recording, and
`make sounds` replaces every placeholder with an ElevenLabs take. made.json marks them "by": "placeholder".

Music: "explore", a gentle 8-bar loop (90 BPM, C - Am - F - G), built sample by sample so it loops perfectly, then
imported through music.py like any track.
"""

from __future__ import annotations

import argparse
import math
import random
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as c  # noqa: E402
import sfx  # noqa: E402

## Which recipe an id gets when sounds.json does not say (first match wins).
GUESSES = [
    (("denied", "error", "fail", "wrong", "cant", "blocked"), "buzz"),
    (("complete", "win", "victory", "fanfare", "level_up", "success", "unlock"), "fanfare"),
    (("pickup", "coin", "collect", "star", "gem", "point", "get"), "blip"),
    (("jump", "hop", "bounce", "spring"), "sweep_up"),
    (("fall", "down", "shrink"), "sweep_down"),
    (("step", "foot", "walk", "land"), "thump"),
    (("click", "ui", "button", "select", "hover", "menu", "tap"), "click"),
    (("whoosh", "swish", "dash", "swing", "throw", "wind"), "whoosh"),
    (("portal", "magic", "teleport", "sparkle", "spell", "heal"), "chime"),
    (("build", "place", "drop", "hit", "thud", "hammer", "door"), "thunk"),
]


def guess(sound: dict) -> str:
    if sound.get("placeholder"):
        return sound["placeholder"]
    if sound.get("loop"):
        return "hum"
    tokens = sound["id"].split("_")
    for words, kind in GUESSES:  # whole words of the id, or their start/end ("footstep" ends in "step")
        if any(t == w or t.startswith(w) or t.endswith(w) for t in tokens for w in words if len(w) > 2 or t == w):
            return kind
    return "blip"


def recipe(kind: str, n: int) -> tuple[str, float]:
    """(an ffmpeg lavfi source, seconds) for take `n` (1-based) of a kind. Each take differs a little in pitch."""
    m = (1.0, 1.06, 0.95, 1.12, 0.9, 1.03, 0.97, 1.09)[(n - 1) % 8]
    if kind == "blip":
        d, f1, f2 = 0.35, 880 * m, 1320 * m
        e = "min(1,t*400)*exp(-8*t)*0.6*sin(2*PI*(%g*t+%g*max(0,t-0.07)))" % (f1, f2 - f1)
    elif kind == "sweep_up":
        d, f0 = 0.3, 250 * m
        e = "sin(PI*t/%g)*0.5*(sin(2*PI*(%g*t+%g*t*t))+0.3*sin(4*PI*(%g*t+%g*t*t)))" % (d, f0, 450 / d, f0, 450 / d)
    elif kind == "sweep_down":
        d, f0 = 0.4, 900 * m
        e = "sin(PI*t/%g)*0.5*sin(2*PI*(%g*t-%g*t*t))" % (d, f0, 350 / d)
    elif kind == "thump":
        return ("anoisesrc=d=0.2:c=brown:a=1:seed=%d,lowpass=f=%d,volume='min(1,t*300)*exp(-25*t)':eval=frame"
                % (n * 7, int(320 * m)), 0.2)
    elif kind == "click":
        d = 0.06
        e = "0.6*sin(2*PI*%g*t)*exp(-90*t)" % (1800 * m)
    elif kind == "whoosh":
        return ("anoisesrc=d=0.6:c=pink:a=1:seed=%d,bandpass=f=%d:w=900,volume='pow(sin(PI*t/0.6),2)':eval=frame"
                % (n * 11, int(1200 * m)), 0.6)
    elif kind == "chime":
        d = 1.2
        e = "+".join("0.25*exp(-2.5*t)*sin(2*PI*%g*t+0.5*sin(2*PI*5*t))" % (f * m) for f in (523.25, 659.25, 783.99))
    elif kind == "fanfare":
        d, notes = 1.4, (523.25, 659.25, 783.99, 1046.5)
        terms = []
        for k, f in enumerate(notes):
            s = 0.13 * k
            terms.append("gte(t,%g)*min(1,(t-%g)*300)*exp(-%g*(t-%g))*(sin(2*PI*%g*t)+0.3*sin(4*PI*%g*t))"
                         % (s, s, 3.0 if k == len(notes) - 1 else 9.0, s, f * m, f * m))
        e = "0.3*(%s)" % "+".join(terms)
    elif kind == "buzz":
        d = 0.3
        e = "0.35*(between(t,0,0.1)+between(t,0.15,0.25))*(sin(2*PI*%g*t)+0.5*sin(6*PI*%g*t))" % (140 * m, 140 * m)
    elif kind == "thunk":
        d = 0.35
        e = "0.6*sin(2*PI*%g*t)*exp(-14*t)+0.4*(2*random(0)-1)*exp(-80*t)" % (140 * m)
    elif kind == "hum":
        # Whole cycles of every partial and the tremolo in 4 s, so the loop is seamless.
        d, base = 4.0, (110, 120, 130, 100, 140, 115, 125, 105)[(n - 1) % 8]
        e = "0.3*(0.75+0.25*sin(2*PI*0.5*t))*(sin(2*PI*%d*t)+0.5*sin(2*PI*%g*t)+0.25*sin(2*PI*%d*t))" % (
            base, base * 1.5, base * 2)
    else:
        raise ValueError("no placeholder recipe %r" % kind)
    return "aevalsrc='%s':s=44100:d=%g" % (e, d), d


def make_sound(sound: dict, folder: Path = c.SFX_DIR, made_path: Path = c.MADE_JSON) -> list[Path]:
    kind = guess(sound)
    with tempfile.TemporaryDirectory() as scratch:
        takes = []
        for n in range(1, int(sound.get("variants", 1)) + 1):
            source, seconds = recipe(kind, n)
            wav = Path(scratch) / ("raw%d.wav" % n)
            c.ffmpeg("-f", "lavfi", "-i", source, "-t", "%g" % seconds, "-ac", "1", "-c:a", "pcm_s16le", str(wav))
            out = Path(scratch) / ("take%d.ogg" % n)
            c.level_sound(wav, out, loop=bool(sound.get("loop")), trim=False)
            takes.append(out)
        return sfx.install(sound, takes, folder, by="placeholder", made_path=made_path)


def make_sounds(sounds: list[dict], made: dict, only: set | None = None, folder: Path = c.SFX_DIR,
                made_path: Path = c.MADE_JSON, log=print) -> list[str]:
    done = []
    for sound in sounds:
        if only and sound["id"] not in only:
            continue
        state = sfx.status(sound, made, folder)
        files = sfx.files_for(sound["id"], folder)
        if state == "missing" or (state == "placeholder" and len(files) != int(sound.get("variants", 1))):
            make_sound(sound, folder, made_path)
            log("  placeholder %-18s %s x%d" % (sound["id"], guess(sound), int(sound.get("variants", 1))))
            done.append(sound["id"])
    return done


# ---- the music placeholder ---------------------------------------------------------------------------------------------

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def freq(name: str, octave: int) -> float:
    return 440.0 * 2 ** ((NOTE[name] + 12 * (octave - 4) - 9) / 12.0)


def explore_loop(rate: int = 22050, bpm: float = 90.0) -> tuple[list[float], list[float]]:
    """8 bars of C - Am - F - G twice, pad + arpeggio + bass, built circularly so the end flows into the start."""
    chords = [("C", "E", "G"), ("A", "C", "E"), ("F", "A", "C"), ("G", "B", "D")] * 2
    beat = 60.0 / bpm
    bar = 4 * beat
    total = int(round(len(chords) * bar * rate))
    mix = [0.0] * total
    rng = random.Random(7)

    def add(start_s: float, length_s: float, f: float, amp: float, attack: float, decay: float, harmonics=(1.0,)):
        first = int(start_s * rate)
        for i in range(int(length_s * rate)):
            t = i / rate
            env = min(1.0, t / attack) * math.exp(-decay * t) * min(1.0, (length_s - t) / 0.05)
            value = sum(h * math.sin(2 * math.pi * f * (k + 1) * t) for k, h in enumerate(harmonics))
            mix[(first + i) % total] += amp * env * value

    for index, chord in enumerate(chords):
        start = index * bar
        for note in chord:  # the pad
            add(start, bar + 0.4, freq(note, 4 if note in "CDE" else 3), 0.09, 0.6, 0.15, (1.0, 0.2))
        add(start, 1.9 * beat, freq(chord[0], 2), 0.22, 0.01, 1.2, (1.0, 0.35))  # bass, beats 1 and 3
        add(start + 2 * beat, 1.9 * beat, freq(chord[0], 2), 0.18, 0.01, 1.2, (1.0, 0.35))
        pattern = [0, 1, 2, 1, 0, 2, 1, 2]
        for step, which in enumerate(pattern):  # eighth-note arpeggio, an octave up, slightly humanised
            jitter = rng.uniform(-0.006, 0.006)
            add(start + step * beat / 2 + max(0.0, jitter), 0.8, freq(chord[which], 5), 0.07 * rng.uniform(0.8, 1.0),
                0.005, 4.0, (1.0, 0.15))
    # A circular echo (left 1/2 beat, right 3/4 beat): space without a tail that the loop would cut off.
    left = [mix[i] + 0.25 * mix[i - int(beat / 2 * rate)] + 0.1 * mix[i - int(beat * rate)] for i in range(total)]
    right = [mix[i] + 0.25 * mix[i - int(beat * 0.75 * rate)] + 0.1 * mix[i - int(beat * 1.5 * rate)] for i in range(total)]
    return left, right


def make_music(folder: Path = c.MUSIC_DIR, log=print) -> Path:
    import music  # noqa: E402 (music imports sfx-free helpers only)
    rate = 22050
    left, right = explore_loop(rate)
    peak = max(max(abs(x) for x in left), max(abs(x) for x in right))
    interleaved = [v / peak * 0.8 for pair in zip(left, right) for v in pair]
    with tempfile.TemporaryDirectory() as scratch:
        wav = Path(scratch) / "explore.wav"
        c.write_wav(wav, interleaved, rate, channels=2)
        entry = music.import_track(wav, "explore", folder=folder, exact=True, bpm=90,
                                   rights="CC0: synthesised by tools/audio/placeholders.py", title="Explore (placeholder)",
                                   placeholder=True, log=log)
    return folder / entry["file"]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", default="")
    parser.add_argument("--music", action="store_true", help="also (re)make the explore music placeholder")
    args = parser.parse_args(argv)
    only = {s.strip() for s in args.only.split(",") if s.strip()} or None
    done = make_sounds(sfx.load(), c.load_made(), only)
    print("placeholders: %d sounds made (sounds with files already were left alone)" % len(done))
    if args.music:
        track = c.read_json(c.MUSIC_JSON, {}).get("tracks", {}).get("explore")
        if track and not track.get("placeholder"):
            print("placeholders: music: explore is a real track; left alone")
        elif track and (c.MUSIC_DIR / track.get("file", "")).exists():
            print("placeholders: music: the explore placeholder is already there")
        else:
            print("placeholders: music -> %s" % c.rel(make_music()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
