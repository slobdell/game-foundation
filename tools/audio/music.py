#!/usr/bin/env python3
"""Music from Suno: import a downloaded track as a seamless game loop, and check every track.

    python3 tools/audio/music.py import ~/Downloads/lava.mp3 --id lava_theme [--from 0:12] [--to 2:05] [--bpm 100]
                                        [--rights "Suno Pro, 2026-10-04"] [--title "Lava Theme"]
    python3 tools/audio/music.py check                       # every track in assets/music/music.json

Import: decodes whatever Suno gave (mp3, wav, m4a...), trims silence, keeps FROM..TO if given (without FROM it
starts where the music is in full swing, past a quiet intro; TO cuts off Suno's ending), then finds the loop: the
point late in the track whose next few seconds sound most like the
start (energy and brightness, compared frame by frame), on whole bars when you give --bpm. The end is cross-faded
into the start, so the loop has no click and no gap. Then it is levelled to -18 LUFS (peak under -1 dB), encoded Ogg
Vorbis to assets/music/<id>.ogg, set to loop on import, and recorded in assets/music/music.json with its rights note.

Check: every track's file exists, its loudness is within 2 LU of the target, its peak is under -1 dB, the loop seam
has no jump (sample or level), and it has a rights note. A placeholder track is reported, not failed.
"""

from __future__ import annotations

import argparse
import math
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as c  # noqa: E402

TOLERANCE_LU = 2.0
SILENCE_DB = -50.0
ANALYSIS_RATE = 8000
FRAME_S = 0.05
COMPARE_S = 3.0          # how much music after each candidate point is compared with the start
MIN_LOOP_S = 15.0
CROSSFADE_S = 1.0
BITRATE_Q = "5"          # Vorbis quality: ~160 kbps stereo, transparent for game music
## The seam: the jump between the last and first sample, against the track's typical sample-to-sample step.
SEAM_RATIO_MAX = 4.0
SEAM_LEVEL_DB_MAX = 6.0  # the last and first half-second may differ this much in level (a fade-out looping = no)
UNRECORDED = "UNRECORDED: which Suno plan was this made under, and when?"


def seconds(text) -> float:
    """"1:32", "92" or "92.5" -> seconds; "" -> 0."""
    text = str(text or "").strip()
    if not text:
        return 0.0
    if ":" in text:
        minutes, rest = text.split(":", 1)
        return int(minutes) * 60 + float(rest)
    return float(text)


def audible_span(samples: list[float], rate: int) -> tuple[float, float]:
    threshold = 10 ** (SILENCE_DB / 20.0)
    first = next((i for i, s in enumerate(samples) if abs(s) > threshold), 0)
    last = next((i for i in range(len(samples) - 1, -1, -1) if abs(samples[i]) > threshold), len(samples) - 1)
    return first / rate, (last + 1) / rate


def features(samples: list[float], rate: int, frame_s: float = FRAME_S) -> list[tuple[float, float]]:
    """Per frame: (log energy, zero-crossing rate). Enough to tell "the drums are in, it's bright" from a breakdown."""
    n = max(1, int(rate * frame_s))
    out = []
    for start in range(0, len(samples) - n + 1, n):
        frame = samples[start:start + n]
        energy = sum(x * x for x in frame) / n
        crossings = sum(1 for a, b in zip(frame, frame[1:]) if (a < 0) != (b < 0)) / n
        out.append((10 * math.log10(energy + 1e-10), crossings * 100))
    return out


def in_full_swing(feats: list[tuple[float, float]], lo_s: float, hi_s: float, window_s: float = 1.0) -> float:
    """Without FROM: where the music is in full swing (the first second as loud as the track's typical second, less
    6 dB), so a quiet Suno intro does not become the loop's start (it would match the fade-out ending best)."""
    lo, hi = int(lo_s / FRAME_S), int(hi_s / FRAME_S)
    n = max(1, int(window_s / FRAME_S))
    levels = [sum(f[0] for f in feats[i:i + n]) / n for i in range(lo, max(lo + 1, hi - n))]
    if not levels:
        return lo_s
    typical = sorted(levels)[len(levels) // 2]
    first = next((i for i, level in enumerate(levels) if level >= typical - 6.0), 0)
    return (lo + first) * FRAME_S


def find_loop_end(feats: list[tuple[float, float]], start_f: int, lo_f: int, hi_f: int, step_f: float = 0.0,
                  compare_f: int = int(COMPARE_S / FRAME_S)) -> tuple[int, float]:
    """The frame E in [lo_f, hi_f] whose next `compare_f` frames best match the ones after `start_f`.
    `step_f` > 0 keeps E on whole bars from the start. Returns (E, mismatch); later ends win near-ties."""
    reference = feats[start_f:start_f + compare_f]
    best = None
    candidates = []
    if step_f > 0:
        k = 1
        while start_f + k * step_f <= hi_f:
            e = int(round(start_f + k * step_f))
            if e >= lo_f:
                candidates.append(e)
            k += 1
    else:
        candidates = list(range(lo_f, hi_f + 1))
    for e in candidates:
        window = feats[e:e + compare_f]
        if len(window) < len(reference) or not reference:
            continue
        mismatch = sum(abs(a[0] - b[0]) / 6.0 + abs(a[1] - b[1]) / 10.0 for a, b in zip(reference, window)) / len(reference)
        score = mismatch - 0.05 * (e - lo_f) / max(1, hi_f - lo_f)  # prefer the longer loop when it's a near-tie
        if best is None or score < best[0]:
            best = (score, e, mismatch)
    if best is None:
        return hi_f, math.inf
    return best[1], best[2]


def crossfade_loop(stereo: list[float], loop_frames: int, fade_frames: int) -> list[float]:
    """stereo interleaved [start .. end + fade]; returns [start .. end] whose head is blended with what followed the
    end (equal-power), so playing it on repeat flows: last sample = audio just before `end`, first = audio at `end`."""
    out = stereo[:loop_frames * 2]
    for i in range(fade_frames):
        a = i / fade_frames
        fade_in, fade_out = math.sin(a * math.pi / 2), math.cos(a * math.pi / 2)
        for ch in range(2):
            out[2 * i + ch] = stereo[2 * i + ch] * fade_in + stereo[2 * (loop_frames + i) + ch] * fade_out
    return out


def load_manifest(folder: Path = c.MUSIC_DIR) -> dict:
    return c.read_json(folder / "music.json", {"target_lufs": c.MUSIC_LUFS, "tracks": {}})


def import_track(source: Path, track_id: str, folder: Path = c.MUSIC_DIR, cut_from: float = 0.0, cut_to: float = 0.0,
                 bpm: float = 0.0, rights: str = "", title: str = "", exact: bool = False, placeholder: bool = False,
                 log=print) -> dict:
    source = Path(source).expanduser()
    if not source.exists():
        raise SystemExit("%s is not there (check the path; Suno downloads usually land in ~/Downloads)" % source)
    if not c.ID_RE.match(track_id):
        raise SystemExit("--id %r: use lowercase letters, digits and _ (like lava_theme)" % track_id)
    folder.mkdir(parents=True, exist_ok=True)
    analysis = c.decode(source, ANALYSIS_RATE)
    total_s = len(analysis) / ANALYSIS_RATE
    if exact:
        start_s, end_s = 0.0, total_s
        fade_s = 0.0
    else:
        a_lo, a_hi = audible_span(analysis, ANALYSIS_RATE)
        feats = features(analysis, ANALYSIS_RATE)
        start_s = max(a_lo, cut_from) if cut_from > 0 else in_full_swing(feats, a_lo, a_hi)
        limit_s = min(a_hi, cut_to) if cut_to > 0 else a_hi
        if limit_s - start_s < 4.0:
            raise SystemExit("FROM/TO leave only %.1f s of music; a loop needs more" % (limit_s - start_s))
        fade_s = min(CROSSFADE_S, (limit_s - start_s) / 8)
        start_f = int(start_s / FRAME_S)
        compare_f = int(min(COMPARE_S, (limit_s - start_s) / 4) / FRAME_S)
        # The loop's end leaves room after it for the comparison and the cross-fade (both read audio past the end).
        hi_f = int((limit_s - max(fade_s, compare_f * FRAME_S)) / FRAME_S)
        lo_f = start_f + int(min(MIN_LOOP_S, (hi_f - start_f) * FRAME_S * 0.5) / FRAME_S)
        bar_f = (4 * 60.0 / bpm) / FRAME_S if bpm > 0 else 0.0
        end_f, mismatch = find_loop_end(feats, start_f, lo_f, hi_f, bar_f, max(1, compare_f))
        end_s = end_f * FRAME_S
        if bpm > 0:  # put the end exactly a whole number of bars after the start (frames round)
            bar = 4 * 60.0 / bpm
            end_s = start_s + round((end_s - start_s) / bar) * bar
        log("  loop %.2f-%.2f s (%.1f s, match %.2f; lower is better)%s" % (
            start_s, end_s, end_s - start_s, mismatch, ", on bars at %g bpm" % bpm if bpm > 0 else ""))
    rate = 44100
    with tempfile.TemporaryDirectory() as scratch:
        raw = Path(scratch) / "section.wav"
        c.ffmpeg("-ss", "%.4f" % start_s, "-i", str(source), "-t", "%.4f" % (end_s - start_s + fade_s),
                 "-ac", "2", "-ar", str(rate), "-c:a", "pcm_s16le", str(raw))
        stereo = c.decode(raw, rate, channels=2)
        loop_frames = min(int(round((end_s - start_s) * rate)), len(stereo) // 2 - int(fade_s * rate))
        looped = crossfade_loop(stereo, loop_frames, int(fade_s * rate)) if fade_s > 0 else stereo[:loop_frames * 2]
        wav = Path(scratch) / "loop.wav"
        c.write_wav(wav, looped, rate, channels=2)
        lufs, _ = c.measure_lufs(wav)
        gain = min(c.MUSIC_LUFS - lufs, c.PEAK_CEILING_DB - 0.7 - c.peak_db(looped))
        destination = folder / ("%s.ogg" % track_id)
        for _ in range(4):
            c.ffmpeg("-i", str(wav), "-af", "volume=%.2fdB" % gain, "-c:a", "libvorbis", "-q:a", BITRATE_Q,
                     str(destination))
            over = c.peak_db(c.decode(destination, rate, 2)) - (c.PEAK_CEILING_DB - 0.2)
            if over <= 0:
                break
            gain -= over + 0.3
    c.set_import_loop(destination, True, 0.0)
    final_lufs, peak = c.measure_lufs(destination)
    manifest = load_manifest(folder)
    old = manifest["tracks"].get(track_id, {})
    entry = {
        "file": destination.name,
        "title": title or old.get("title") or track_id.replace("_", " ").title(),
        "source": "placeholder" if placeholder else "suno",
        "from_file": source.name if not placeholder else "",
        "section_s": [round(start_s, 2), round(end_s, 2)],
        "loop_s": round(c.duration(destination), 2),
        "bpm": bpm or old.get("bpm", 0),
        "lufs": round(final_lufs, 1),
        "peak_db": round(peak, 1),
        "rights": rights or (old.get("rights", UNRECORDED) if not old.get("placeholder") else UNRECORDED),
        "imported": c.now_iso(),
    }
    if placeholder:
        entry["placeholder"] = True
    manifest["tracks"][track_id] = entry
    manifest.setdefault("target_lufs", c.MUSIC_LUFS)
    c.write_json(folder / "music.json", manifest)
    log("imported %s -> %s: %.1f s loop, %.1f LUFS, peak %.1f dB, %d KB" % (
        source.name, c.rel(destination), entry["loop_s"], final_lufs, peak, destination.stat().st_size // 1024))
    if entry["rights"] == UNRECORDED:
        log("  NOTE: record the rights before sharing the game: --rights \"Suno <plan>, <date>\" (free plans are "
            "non-commercial)")
    return entry


def seam(samples: list[float], rate: int) -> tuple[float, float]:
    """(sample jump at the wrap / the track's typical step, level difference dB of the last vs first half-second)."""
    steps = sorted(abs(b - a) for a, b in zip(samples[::7], samples[1::7]))
    typical = steps[int(len(steps) * 0.99)] if steps else 0.0
    jump = abs(samples[0] - samples[-1]) / max(typical, 1e-4)
    half = int(rate * 0.5)
    level = lambda xs: 10 * math.log10(sum(x * x for x in xs) / max(1, len(xs)) + 1e-10)  # noqa: E731
    return jump, abs(level(samples[-half:]) - level(samples[:half]))


def check(folder: Path = c.MUSIC_DIR, log=print) -> tuple[list[str], list[str]]:
    """(problems, notes). Problems fail make music-check / audio-check; notes are printed."""
    problems, notes = [], []
    manifest_path = folder / "music.json"
    if not manifest_path.exists():
        notes.append("no music yet (%s); make sounds-placeholders makes the explore loop" % c.rel(manifest_path))
        return problems, notes
    manifest = c.read_json(manifest_path, {})
    target = float(manifest.get("target_lufs", c.MUSIC_LUFS))
    tracks = manifest.get("tracks")
    if not isinstance(tracks, dict):
        return ["music.json needs {\"tracks\": {...}}"], notes
    for track_id, track in sorted(tracks.items()):
        if not c.ID_RE.match(track_id):
            problems.append("%s: track ids are lowercase letters, digits and _" % track_id)
        path = folder / str(track.get("file", ""))
        if not track.get("file") or not path.exists():
            problems.append("%s: %s is not there (import it again: make music-import)" % (track_id, track.get("file")))
            continue
        if path.name != "%s.ogg" % track_id:
            problems.append("%s: the file must be %s.ogg (the game plays assets/music/<id>.ogg)" % (track_id, track_id))
        lufs, peak = c.measure_lufs(path)
        samples = c.decode(path, 22050)
        length = len(samples) / 22050
        jump, level_gap = seam(samples, 22050) if length > 1.0 else (0.0, 0.0)
        if abs(lufs - target) > TOLERANCE_LU:
            problems.append("%s: %.1f LUFS is %.1f LU off the %.0f target (import it again)" % (track_id, lufs,
                                                                                              lufs - target, target))
        if peak > c.PEAK_CEILING_DB + 0.2:
            problems.append("%s: peaks at %.1f dB, over the %.1f ceiling" % (track_id, peak, c.PEAK_CEILING_DB))
        if length < 4.0:
            problems.append("%s: only %.1f s long; a loop that short repeats annoyingly" % (track_id, length))
        if jump > SEAM_RATIO_MAX:
            problems.append("%s: the loop seam jumps (%.1fx a normal step): it will click every repeat; import "
                            "again with a different FROM/TO" % (track_id, jump))
        if level_gap > SEAM_LEVEL_DB_MAX:
            problems.append("%s: the end is %.1f dB away from the start in level (a fade-out?): use TO= to stop "
                            "before Suno's ending" % (track_id, level_gap))
        rights = str(track.get("rights", "")).strip()
        if not rights:
            problems.append("%s: needs a rights note (which Suno plan, and the date)" % track_id)
        elif rights == UNRECORDED:
            notes.append("%s: rights not recorded yet (fine for playing at home; needed before sharing)" % track_id)
        if track.get("placeholder"):
            notes.append("%s: still the placeholder (make a Suno track, then make music-import ID=%s)" % (track_id, track_id))
        log("  %-16s %5.1f LUFS  peak %5.1f dB  %5.1f s loop  seam %.1f / %.1f dB%s" % (
            track_id, lufs, peak, length, jump, level_gap, "  (placeholder)" if track.get("placeholder") else ""))
    for path in sorted(folder.glob("*.ogg")):
        if path.stem not in tracks:
            notes.append("%s is not in music.json (import it with make music-import so it is levelled and looped)"
                         % c.rel(path))
    return problems, notes


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    imp = sub.add_parser("import", help="import a Suno download as a game loop")
    imp.add_argument("source", type=Path)
    imp.add_argument("--id", required=True, dest="track_id")
    imp.add_argument("--from", dest="cut_from", default="", help="start here (m:ss or seconds): skip Suno's intro")
    imp.add_argument("--to", dest="cut_to", default="", help="stop here: skip the ending / fade-out")
    imp.add_argument("--bpm", type=float, default=0.0, help="the tempo, if known: the loop lands on whole bars")
    imp.add_argument("--rights", default="", help="e.g. \"Suno Pro, 2026-10-04\"")
    imp.add_argument("--title", default="")
    imp.add_argument("--folder", type=Path, default=c.MUSIC_DIR)
    chk = sub.add_parser("check", help="check every track")
    chk.add_argument("--folder", type=Path, default=c.MUSIC_DIR)
    args = parser.parse_args(argv)
    if args.command == "import":
        import_track(args.source, args.track_id, args.folder, seconds(args.cut_from), seconds(args.cut_to), args.bpm,
                     args.rights, args.title)
        problems, _ = check(args.folder, log=lambda *_: None)
        mine = [p for p in problems if p.startswith(args.track_id + ":")]
        for problem in mine:
            print("PROBLEM " + problem)
        print("next: make import, then play (levels.json \"music\": \"%s\" picks it for a level)" % args.track_id)
        return 1 if mine else 0
    problems, notes = check(args.folder)
    for note in notes:
        print("  note: " + note)
    for problem in problems:
        print("PROBLEM " + problem)
    print("music-check: %d problems" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
