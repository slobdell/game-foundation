#!/usr/bin/env python3
"""audio-check: is every piece of the game's audio where it should be, and at a sensible level? (part of make check)

    python3 tools/audio/check.py

PROBLEMS (fail): sounds.json / voices.json / music.json malformed; a dialogue line whose speaker has no voice; a
shipped sound, voice clip or track too loud (over the peak ceiling) or far too quiet/loud for its kind; a loop sound
whose import is not set to loop; a music loop that would click.
NOTES (printed, fine): sounds or lines with no audio yet (the game stays silent for them, by design), placeholders
still in use, files nothing refers to, ids the game's code or levels ask for that do not exist.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as c  # noqa: E402
import music  # noqa: E402
import sfx  # noqa: E402
import voices as vo  # noqa: E402

## Bounds for shipped files. Sound effects are levelled to -16 dBFS on their loudest 400 ms; voices to -16 LUFS.
SFX_LEVEL_RANGE = (-30.0, -8.0)
VOICE_LUFS_RANGE = (-22.0, -11.0)
PEAK_MAX_DB = -0.5


def check_sounds(problems: list, notes: list, sounds_path: Path = c.SOUNDS_JSON, folder: Path = c.SFX_DIR,
                 made_path: Path = c.MADE_JSON) -> list[dict]:
    data = c.read_json(sounds_path, None)
    if data is None:
        problems.append("%s is missing (it lists the game's sounds; [] is fine)" % c.rel(sounds_path))
        return []
    found = sfx.validate(data)
    problems += ["sounds.json: " + p for p in found]
    if found:
        return []
    made = c.load_made(made_path)
    silent, placeholder, stale = [], [], []
    owned = set()
    for sound in data:
        files = sfx.files_for(sound["id"], folder)
        owned.update(files)
        state = sfx.status(sound, made, folder)
        if state == "missing":
            silent.append(sound["id"])
        elif state == "placeholder":
            placeholder.append(sound["id"])
        elif state == "stale":
            stale.append(sound["id"])
        for path in files:
            samples = c.decode(path)
            peak, level = c.peak_db(samples), c.loudest_window_db(samples, 44100)
            if peak > PEAK_MAX_DB:
                problems.append("%s: peaks at %.1f dB (over %.1f); make it again with make sounds ONLY=%s"
                                % (c.rel(path), peak, PEAK_MAX_DB, sound["id"]))
            if not SFX_LEVEL_RANGE[0] <= level <= SFX_LEVEL_RANGE[1]:
                problems.append("%s: level %.1f dB is outside %g..%g (made outside the pipeline?)"
                                % (c.rel(path), level, *SFX_LEVEL_RANGE))
            if sound.get("loop"):
                imp = Path(str(path) + ".import")
                if not imp.exists() or not re.search(r"^loop=true$", imp.read_text(), re.M):
                    problems.append("%s: a loop sound, but its import is not set to loop (make sounds-placeholders "
                                    "or make sounds ONLY=%s fixes it)" % (c.rel(path), sound["id"]))
    if silent:
        notes.append("no audio yet (silent in the game): %s. Free stand-ins: make sounds-placeholders" % ", ".join(silent))
    if placeholder:
        notes.append("still placeholders: %s (make sounds makes real ones)" % ", ".join(placeholder))
    if stale:
        notes.append("prompt changed since recorded: %s (make sounds re-makes them)" % ", ".join(stale))
    if folder.exists():
        for path in sorted(folder.glob("*.ogg")):
            if path not in owned:
                notes.append("%s belongs to no sound in sounds.json (the game will never play it)" % c.rel(path))
    return data


def check_voices(problems: list, notes: list) -> None:
    voices = c.read_json(c.VOICES_JSON, None)
    if voices is None:
        problems.append("data/voices.json is missing")
        return
    problems += ["voices.json: " + p for p in vo.validate_voices(voices)]
    lines = vo.voiced_lines()
    problems += vo.validate_lines(lines, voices)
    missing, wanted = [], set()
    for line in lines:
        wanted.add(line.get("voice"))
        path = vo.clip_path(str(line.get("voice")))
        if not path.exists():
            missing.append(str(line.get("voice")))
    if missing:
        notes.append("%d voiced line(s) not recorded yet (silent, the text still shows): %s. make voices records them"
                     % (len(missing), ", ".join(missing[:8]) + (" ..." if len(missing) > 8 else "")))
    if c.VOICE_DIR.exists():
        for path in sorted(c.VOICE_DIR.glob("*.ogg")):
            if path.stem not in wanted:
                notes.append("%s: no dialogue line has \"voice\": \"%s\"" % (c.rel(path), path.stem))
                continue
            lufs, peak = c.measure_lufs(path)
            if peak > PEAK_MAX_DB:
                problems.append("%s: peaks at %.1f dB (over %.1f)" % (c.rel(path), peak, PEAK_MAX_DB))
            if lufs > -60 and not VOICE_LUFS_RANGE[0] <= lufs <= VOICE_LUFS_RANGE[1]:
                problems.append("%s: %.1f LUFS is outside %g..%g (record it again: make voices ONLY=%s FORCE=1)"
                                % (c.rel(path), lufs, VOICE_LUFS_RANGE[0], VOICE_LUFS_RANGE[1], path.stem))


def check_references(notes: list, sound_ids: set, music_ids: set) -> None:
    """Ids the game asks for that do not exist (a note, not a failure: missing audio is silent by design)."""
    asked = set()
    for path in (c.ROOT / "game").rglob("*.gd") if (c.ROOT / "game").exists() else []:
        if "kit/audio" in str(path):
            continue
        text = path.read_text(errors="replace")
        asked |= set(re.findall(r"Sound\.play\(\s*\"([a-z0-9_]+)\"", text))
        asked |= set(re.findall(r"@export var sound\s*:?=\s*\"([a-z0-9_]+)\"", text))
    for scene in (c.ROOT / "game").rglob("*.tscn") if (c.ROOT / "game").exists() else []:
        asked |= set(re.findall(r"^sound = \"([a-z0-9_]+)\"", scene.read_text(errors="replace"), re.M))
    unknown = sorted(asked - sound_ids)
    if unknown:
        notes.append("the game's code asks for sounds not in sounds.json: %s" % ", ".join(unknown))
    levels = c.read_json(c.ROOT / "data" / "levels.json", {})
    wanted = {str(v.get("music", "")) for v in (levels.get("levels", {}) or {}).values() if isinstance(v, dict)}
    unknown_music = sorted(m for m in wanted - music_ids if m)
    if unknown_music:
        notes.append("levels.json asks for music that is not imported yet: %s" % ", ".join(unknown_music))


def main(argv: list[str] | None = None) -> int:
    problems: list[str] = []
    notes: list[str] = []
    sounds = check_sounds(problems, notes)
    check_voices(problems, notes)
    music_problems, music_notes = music.check(log=lambda *_: None)
    problems += ["music: " + p for p in music_problems]
    notes += ["music: " + n for n in music_notes]
    manifest = c.read_json(c.MUSIC_JSON, {"tracks": {}})
    check_references(notes, {s["id"] for s in sounds}, set(manifest.get("tracks", {})))
    print("audio-check: %d sounds, %d voiced lines, %d music tracks" % (
        len(sounds), len(vo.voiced_lines()), len(manifest.get("tracks", {}))))
    for note in notes:
        print("  note: " + note)
    for problem in problems:
        print("PROBLEM " + problem)
    print("audio-check: %s" % ("%d problems" % len(problems) if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
