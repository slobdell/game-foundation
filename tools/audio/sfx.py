#!/usr/bin/env python3
"""Sound effects from ElevenLabs: assets/audio/sounds.json in, assets/audio/sfx/<id>_v<n>.ogg out.

    python3 tools/audio/sfx.py --dry-run                 # what would be made, and what it costs (free)
    python3 tools/audio/sfx.py                           # make every sound that has no real recording yet (PAID)
    python3 tools/audio/sfx.py --only footstep,jump      # just these (PAID)
    python3 tools/audio/sfx.py --only jump --force       # again, even though they exist (PAID)
    python3 tools/audio/sfx.py --base-url http://127.0.0.1:8099   # against the mock: free, writes a mock ledger

sounds.json is a list; each entry:

    {"id": "footstep", "prompt": "a squishy footstep on wet moss", "duration": 0.6, "variants": 4, "loop": false,
     "volume_db": -4, "pitch": 0.08, "influence": 0.4, "placeholder": "thump"}

  id         lowercase letters, digits, _ (what the game calls: Sound.play("footstep")). Not ending in _v<digits>.
  prompt     what it should sound like, for ElevenLabs. Describe the physical event, not the game ("a wooden crate
             dropped on stone", not "build sound").
  duration   seconds, 0.5-30 (the API's range).
  variants   how many different takes the game rotates between (1-8). Footsteps want 4+, a fanfare 1.
  loop       true for a sound that repeats seamlessly (wind, a humming portal). Loops are kept in stereo.
  volume_db  optional mix level in the game (0 = as made; -6 = half as loud). The game reads it.
  pitch      optional random pitch wobble each play (default 0.05 = +-5 %); 0 turns it off.
  influence  optional, 0-1: how literally ElevenLabs follows the prompt (default 0.4).
  placeholder optional: which free synthesised stand-in to use (see placeholders.py); guessed from the id if absent.

A sound is made when it has no real recording: its files are missing, still the free placeholders, or were made
from a different prompt/duration (the prompt changed, so the old take is stale). Every request is one take; a take
costs about 10 credits per second. The cost is printed before and after, and every paid run is appended to
assets/audio/elevenlabs_ledger.md.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as c  # noqa: E402

PLACEHOLDER_KINDS = ("blip", "sweep_up", "sweep_down", "thump", "click", "whoosh", "chime", "fanfare", "hum", "buzz",
                     "thunk")


def load(path: Path = c.SOUNDS_JSON) -> list[dict]:
    data = c.read_json(path, [])
    problems = validate(data)
    if problems:
        raise SystemExit("%s:\n  %s" % (c.rel(path), "\n  ".join(problems)))
    return data


def validate(data) -> list[str]:
    """What is wrong with sounds.json, as sentences (empty when fine)."""
    if not isinstance(data, list):
        return ["sounds.json must be a JSON list of sounds: [{\"id\": ..., \"prompt\": ...}, ...]"]
    problems, seen = [], set()
    for index, sound in enumerate(data):
        if not isinstance(sound, dict):
            problems.append("entry %d is not an object" % index)
            continue
        sid = sound.get("id")
        where = "sound %r" % sid if sid else "entry %d" % index
        if not isinstance(sid, str) or not c.ID_RE.match(sid):
            problems.append("%s: id must be lowercase letters, digits and _ (like \"footstep\")" % where)
        elif c.VARIANT_RE.search(sid):
            problems.append("%s: an id may not end in _v<number> (that is how variant files are named)" % where)
        if sid in seen:
            problems.append("%s appears twice" % where)
        seen.add(sid)
        if not isinstance(sound.get("prompt"), str) or len(sound.get("prompt", "").strip()) < 3:
            problems.append("%s: needs a prompt describing the sound" % where)
        try:
            seconds = float(sound.get("duration", 0))
            if not 0.5 <= seconds <= 30.0:
                problems.append("%s: duration %.2f must be 0.5-30 seconds" % (where, seconds))
        except (TypeError, ValueError):
            problems.append("%s: duration must be a number of seconds" % where)
        variants = sound.get("variants", 1)
        if not isinstance(variants, int) or not 1 <= variants <= 8:
            problems.append("%s: variants must be a whole number 1-8" % where)
        if not isinstance(sound.get("loop", False), bool):
            problems.append("%s: loop must be true or false" % where)
        if "volume_db" in sound and not isinstance(sound["volume_db"], (int, float)):
            problems.append("%s: volume_db must be a number" % where)
        if "pitch" in sound and not (isinstance(sound["pitch"], (int, float)) and 0 <= sound["pitch"] <= 0.5):
            problems.append("%s: pitch must be 0-0.5" % where)
        if "influence" in sound and not (isinstance(sound["influence"], (int, float)) and 0 <= sound["influence"] <= 1):
            problems.append("%s: influence must be 0-1" % where)
        if "placeholder" in sound and sound["placeholder"] not in PLACEHOLDER_KINDS:
            problems.append("%s: placeholder must be one of %s" % (where, ", ".join(PLACEHOLDER_KINDS)))
    return problems


def fingerprint(sound: dict) -> str:
    return c.fingerprint(sound["prompt"], float(sound["duration"]), bool(sound.get("loop", False)),
                         float(sound.get("influence", 0.4)), c.SFX_MODEL)


def variant_path(sound_id: str, n: int, folder: Path = c.SFX_DIR) -> Path:
    return folder / ("%s_v%d.ogg" % (sound_id, n))


def files_for(sound_id: str, folder: Path = c.SFX_DIR) -> list[Path]:
    """Every shipped file of a sound: <id>.ogg and <id>_v<n>.ogg (the same rule the game uses)."""
    if not folder.exists():
        return []
    import re
    pattern = re.compile(r"^%s(_v\d+)?\.ogg$" % re.escape(sound_id))
    return sorted(p for p in folder.iterdir() if pattern.match(p.name))


def status(sound: dict, made: dict, folder: Path = c.SFX_DIR) -> str:
    """"ok" (real recordings, current prompt), "missing", "placeholder", or "stale" (the prompt changed)."""
    files = files_for(sound["id"], folder)
    if not files:
        return "missing"
    records = [made.get(c.rel(f), {}) for f in files]
    if any(r.get("by", "placeholder") == "placeholder" for r in records):
        return "placeholder"
    if any(r.get("fp") != fingerprint(sound) for r in records):
        return "stale"
    return "ok"


def plan(sounds: list[dict], made: dict, only: set | None = None, force: bool = False,
         folder: Path = c.SFX_DIR) -> list[dict]:
    todo = []
    for sound in sounds:
        if only and sound["id"] not in only:
            continue
        state = status(sound, made, folder)
        if force or state != "ok":
            todo.append({"sound": sound, "reason": "forced" if (force and state == "ok") else state})
    return todo


def estimate(todo: list[dict]) -> tuple[int, float, int]:
    """(requests, seconds of audio, estimated credits)."""
    requests = sum(int(t["sound"].get("variants", 1)) for t in todo)
    seconds = sum(float(t["sound"]["duration"]) * int(t["sound"].get("variants", 1)) for t in todo)
    return requests, seconds, int(round(seconds * c.SFX_CREDITS_PER_SECOND))


def make_take(client: c.Client, sound: dict, out: Path, master: Path) -> dict:
    """One paid request -> one levelled Ogg at `out`. The mp3 master is kept in build/ (re-levelling is free)."""
    audio = client.sound(sound["prompt"], float(sound["duration"]), bool(sound.get("loop", False)),
                         float(sound.get("influence", 0.4)))
    master.parent.mkdir(parents=True, exist_ok=True)
    master.write_bytes(audio)
    info = c.level_sound(master, out, loop=bool(sound.get("loop", False)))
    if sound.get("loop"):
        c.set_import_loop(out, True)
    return info


def install(sound: dict, takes: list[Path], folder: Path = c.SFX_DIR, by: str = "elevenlabs",
            made_path: Path = c.MADE_JSON, fp: str | None = None) -> list[Path]:
    """Make `takes` (levelled Oggs) the sound's files: <id>_v1..n, every older file of it removed."""
    folder.mkdir(parents=True, exist_ok=True)
    old = files_for(sound["id"], folder)
    staged = []
    for n, take in enumerate(takes, 1):
        tmp = folder / (".%s_v%d.new.ogg" % (sound["id"], n))
        tmp.write_bytes(Path(take).read_bytes())
        staged.append(tmp)
    for path in old:
        path.unlink()
        imp = Path(str(path) + ".import")
        if imp.exists() and not sound.get("loop"):
            imp.unlink()
    final = []
    for n, tmp in enumerate(staged, 1):
        dest = variant_path(sound["id"], n, folder)
        tmp.rename(dest)
        if sound.get("loop"):
            c.set_import_loop(dest, True)
        final.append(dest)
    c.forget_made(old, made_path)
    c.record_made({c.rel(p): {"by": by, "fp": fp or fingerprint(sound), "prompt": sound["prompt"], "at": c.now_iso()}
                   for p in final}, made_path)
    return final


def generate(todo: list[dict], client: c.Client, folder: Path = c.SFX_DIR, made_path: Path = c.MADE_JSON,
             log=print, work: Path = c.BUILD_AUDIO) -> dict:
    made, failed = [], []
    for item in todo:
        sound = item["sound"]
        takes = []
        for n in range(1, int(sound.get("variants", 1)) + 1):
            scratch = work / "sfx_new" / ("%s_v%d.ogg" % (sound["id"], n))
            master = work / "masters" / ("%s_v%d.%s.mp3" % (sound["id"], n, fingerprint(sound)))
            try:
                info = make_take(client, sound, scratch, master)
            except (c.ElevenLabsError, RuntimeError) as error:
                log("FAILED %s take %d: %s" % (sound["id"], n, error))
                failed.append(sound["id"])
                break
            log("  made %s take %d (%.1f s, level %.1f dB, peak %.1f dB)" % (sound["id"], n, info["seconds"],
                                                                         info["level_db"], info["peak_db"]))
            takes.append(scratch)
        if len(takes) == int(sound.get("variants", 1)):
            install(sound, takes, folder, made_path=made_path)
            made.append(sound["id"])
    return {"made": made, "failed": failed}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", default="", help="comma-separated sound ids")
    parser.add_argument("--force", action="store_true", help="make them again even if they exist (PAID)")
    parser.add_argument("--dry-run", action="store_true", help="print the plan and the cost, send nothing")
    parser.add_argument("--base-url", default="", help="the ElevenLabs server (the mock: http://127.0.0.1:8099)")
    parser.add_argument("--note", default="", help="a note for the ledger line")
    parser.add_argument("--sounds", type=Path, default=c.SOUNDS_JSON)
    args = parser.parse_args(argv)
    sounds = load(args.sounds)
    only = {s.strip() for s in args.only.split(",") if s.strip()} or None
    unknown = (only or set()) - {s["id"] for s in sounds}
    if unknown:
        raise SystemExit("not in sounds.json: %s (add an entry first)" % ", ".join(sorted(unknown)))
    todo = plan(sounds, c.load_made(), only, args.force)
    requests, seconds, credits = estimate(todo)
    if not todo:
        print("sounds: nothing to make; every sound%s has a real recording for its current prompt"
              % (" asked for" if only else ""))
        return 0
    print("sounds: %d to make, %d requests, %.1f s of audio, about %d credits" % (len(todo), requests, seconds, credits))
    for item in todo:
        sound = item["sound"]
        print("  %-18s %-11s x%d  %4.1f s  %s" % (sound["id"], item["reason"], int(sound.get("variants", 1)),
                                                 float(sound["duration"]), sound["prompt"][:60]))
    if args.dry_run:
        print("(dry run: nothing sent)")
        return 0
    client = c.Client(args.base_url)
    before = client.credits_left()
    report = generate(todo, client)
    after = client.credits_left()
    c.append_ledger(c.ledger_path(client.url), "sounds: " + ",".join(report["made"] + report["failed"]), c.SFX_MODEL,
                    requests, "%.1f s" % seconds, credits, before, after, args.note or ("" if client.real else "mock"))
    spent = (before - after) if isinstance(before, int) and isinstance(after, int) else None
    print("sounds: made %d, failed %d; credits %s -> %s (%s)%s" % (
        len(report["made"]), len(report["failed"]), before, after,
        "spent %d" % spent if spent is not None else "about %d; the key cannot read the balance" % credits,
        "" if client.real else " [mock]"))
    print("  ledger: %s. Next: make import (or open the editor), then play." % c.rel(c.ledger_path(client.url)))
    return 1 if report["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
