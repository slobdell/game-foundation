#!/usr/bin/env python3
"""Character and narrator voices from ElevenLabs: dialogue lines in, assets/voices/<line id>.ogg out.

    python3 tools/audio/voices.py --dry-run              # which lines would be recorded, and what it costs (free)
    python3 tools/audio/voices.py                        # record every voiced line that has no clip yet (PAID)
    python3 tools/audio/voices.py --only guide_hi_1      # just these line ids (PAID)
    python3 tools/audio/voices.py --list                 # the voices this ElevenLabs account can use (free)
    python3 tools/audio/voices.py --list pirate          # ...whose name/description/labels mention "pirate"

Who speaks how: data/voices.json

    {"model": "eleven_multilingual_v2",
     "speakers": {"guide": {"voice_id": "cgSgspJ2msm6clMCkdW9", "voice_name": "Jessica",
                            "settings": {"stability": 0.45, "similarity_boost": 0.8, "style": 0.3,
                                         "use_speaker_boost": true, "speed": 1.0}}}}

Speaker names match the dialogue's "speaker" without caring about case ("Guide" uses "guide").

What is said: data/dialogue/*.json, each {"id": ..., "lines": [{"speaker": "Guide", "text": "Hi!", "voice": "guide_hi_1"}]}
(lines may also sit inside "variants"). A line with a "voice" field gets a clip, assets/voices/<that id>.ogg, which the
dialogue box plays with Sound.voice(). Lines without one stay silent text.

A clip is recorded when it is missing, or when its text, speaker voice or settings changed since it was made (so an
edited line is never out of sync with its recording). Existing, current clips are skipped unless --force. Speech costs
about 1 credit per character (multilingual v2). Every paid run is appended to assets/audio/elevenlabs_ledger.md.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as c  # noqa: E402

SETTING_KEYS = {"stability", "similarity_boost", "style", "use_speaker_boost", "speed"}


def load_voices(path: Path = c.VOICES_JSON) -> dict:
    return c.read_json(path, {"model": c.TTS_MODEL, "speakers": {}})


def speaker(voices: dict, name: str) -> dict | None:
    """The speaker entry for a dialogue speaker name, matched without case."""
    for key, entry in voices.get("speakers", {}).items():
        if key.lower() == str(name).strip().lower():
            return entry
    return None


def validate_voices(voices: dict) -> list[str]:
    problems = []
    if not isinstance(voices, dict) or not isinstance(voices.get("speakers"), dict):
        return ["voices.json needs {\"speakers\": {\"<name>\": {\"voice_id\": ...}}}"]
    if voices.get("model", c.TTS_MODEL) not in c.TTS_CREDITS_PER_CHAR:
        problems.append("voices.json: model %r is not one we know the price of (%s)"
                        % (voices.get("model"), ", ".join(c.TTS_CREDITS_PER_CHAR)))
    lowered = set()
    for name, entry in voices["speakers"].items():
        if name.lower() in lowered:
            problems.append("speaker %r is listed twice (names ignore case)" % name)
        lowered.add(name.lower())
        if not isinstance(entry, dict) or not isinstance(entry.get("voice_id"), str) or len(entry["voice_id"]) < 8:
            problems.append("speaker %r needs a voice_id (make voice-list shows the ones you can use)" % name)
            continue
        settings = entry.get("settings", {})
        unknown = set(settings) - SETTING_KEYS
        if unknown:
            problems.append("speaker %r: unknown settings %s (allowed: %s)" % (name, sorted(unknown), sorted(SETTING_KEYS)))
        for key in ("stability", "similarity_boost", "style"):
            if key in settings and not (isinstance(settings[key], (int, float)) and 0 <= settings[key] <= 1):
                problems.append("speaker %r: %s must be 0-1" % (name, key))
        if "speed" in settings and not (isinstance(settings["speed"], (int, float)) and 0.7 <= settings["speed"] <= 1.2):
            problems.append("speaker %r: speed must be 0.7-1.2" % name)
    return problems


def _walk_lines(node, found: list, source: str) -> None:
    if isinstance(node, dict):
        if isinstance(node.get("lines"), list):
            for line in node["lines"]:
                if isinstance(line, dict):
                    found.append(dict(line, _file=source))
        for key, value in node.items():
            if key != "lines":
                _walk_lines(value, found, source)
    elif isinstance(node, list):
        for value in node:
            _walk_lines(value, found, source)


def dialogue_lines(folder: Path = c.DIALOGUE_DIR) -> list[dict]:
    """Every line in every dialogue file (including inside "variants"), each tagged with its file."""
    found: list = []
    for path in sorted(Path(folder).glob("*.json")) if Path(folder).exists() else []:
        _walk_lines(c.read_json(path, {}), found, c.rel(path))
    return found


def voiced_lines(folder: Path = c.DIALOGUE_DIR) -> list[dict]:
    return [line for line in dialogue_lines(folder) if line.get("voice")]


def validate_lines(lines: list[dict], voices: dict) -> list[str]:
    problems, seen = [], {}
    for line in lines:
        line_id = line.get("voice")
        if not isinstance(line_id, str) or not c.ID_RE.match(line_id):
            problems.append("%s: voice id %r must be lowercase letters, digits and _" % (line["_file"], line_id))
            continue
        if line_id in seen:
            problems.append("voice id %r is used twice (%s and %s): every recorded line needs its own"
                            % (line_id, seen[line_id], line["_file"]))
        seen[line_id] = line["_file"]
        if not str(line.get("text", "")).strip():
            problems.append("%s: line %r has no text to say" % (line["_file"], line_id))
        if speaker(voices, line.get("speaker", "")) is None:
            problems.append("%s: line %r is spoken by %r, who has no voice in data/voices.json"
                            % (line["_file"], line_id, line.get("speaker")))
    return problems


def fingerprint(line: dict, entry: dict, model: str) -> str:
    return c.fingerprint(line["text"], entry["voice_id"], entry.get("settings", {}), model)


def clip_path(line_id: str, folder: Path = c.VOICE_DIR) -> Path:
    return folder / ("%s.ogg" % line_id)


def plan(lines: list[dict], voices: dict, made: dict, only: set | None = None, force: bool = False,
         folder: Path = c.VOICE_DIR) -> list[dict]:
    model = voices.get("model", c.TTS_MODEL)
    todo = []
    for line in lines:
        if only and line["voice"] not in only:
            continue
        entry = speaker(voices, line.get("speaker", ""))
        if entry is None:
            continue
        path = clip_path(line["voice"], folder)
        record = made.get(c.rel(path), {})
        if not path.exists():
            reason = "missing"
        elif record.get("fp") != fingerprint(line, entry, model):
            reason = "changed"
        elif force:
            reason = "forced"
        else:
            continue
        todo.append({"line": line, "speaker": entry, "reason": reason, "path": path})
    return todo


def estimate(todo: list[dict], model: str) -> tuple[int, int]:
    chars = sum(len(t["line"]["text"]) for t in todo)
    return chars, int(round(chars * c.TTS_CREDITS_PER_CHAR.get(model, 1.0)))


def record_line(client: c.Client, text: str, entry: dict, model: str, out: Path, master: Path) -> tuple[dict, int]:
    audio, billed = client.speak(entry["voice_id"], text, entry.get("settings"), model)
    master.parent.mkdir(parents=True, exist_ok=True)
    master.write_bytes(audio)
    return c.level_speech(master, out), billed


def generate(todo: list[dict], voices: dict, client: c.Client, made_path: Path = c.MADE_JSON, log=print,
             work: Path = c.BUILD_AUDIO) -> dict:
    model = voices.get("model", c.TTS_MODEL)
    made, failed, billed = [], [], 0
    for item in todo:
        line, entry = item["line"], item["speaker"]
        fp = fingerprint(line, entry, model)
        try:
            info, chars = record_line(client, line["text"], entry, model, item["path"],
                                      work / "voice_masters" / ("%s.%s.mp3" % (line["voice"], fp)))
        except (c.ElevenLabsError, RuntimeError) as error:
            log("FAILED %s: %s" % (line["voice"], error))
            failed.append(line["voice"])
            continue
        billed += chars
        c.record_made({c.rel(item["path"]): {"by": "elevenlabs", "fp": fp, "speaker": line.get("speaker"),
                                             "text": line["text"], "at": c.now_iso()}}, made_path)
        log("  recorded %-22s %4.1f s  %5.1f LUFS  \"%s\"" % (line["voice"], info["seconds"], info["lufs"],
                                                          line["text"][:50]))
        made.append(line["voice"])
    return {"made": made, "failed": failed, "billed_chars": billed}


def list_voices(client: c.Client, search: str = "") -> list[dict]:
    found = []
    for voice in client.voices():
        labels = voice.get("labels") or {}
        blob = " ".join([voice.get("name", ""), voice.get("description") or "", " ".join(map(str, labels.values())),
                         voice.get("category", "")]).lower()
        if search and not all(word in blob for word in search.lower().split()):
            continue
        found.append(voice)
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", default="", help="comma-separated line (voice) ids")
    parser.add_argument("--force", action="store_true", help="record them again even if current (PAID)")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--list", nargs="?", const="", default=None, metavar="SEARCH",
                        help="list the account's voices (free), optionally only those matching SEARCH")
    parser.add_argument("--base-url", default="")
    parser.add_argument("--note", default="")
    args = parser.parse_args(argv)
    if args.list is not None:
        voices = list_voices(c.Client(args.base_url), args.list)
        for voice in voices:
            labels = voice.get("labels") or {}
            print("%-22s %-22s %s" % (voice.get("voice_id"), voice.get("name", "")[:22],
                                      ", ".join("%s" % v for v in labels.values() if v)))
            if voice.get("description"):
                print("%-22s   %s" % ("", voice["description"][:100]))
        print("%d voices%s. Use one: put its voice_id under a speaker in data/voices.json "
              "(or let the director pick: make audio-choices SPEAKER=<name> VOICES=id1,id2,id3)."
              % (len(voices), " matching %r" % args.list if args.list else ""))
        return 0
    voices = load_voices()
    lines = voiced_lines()
    problems = validate_voices(voices) + validate_lines(lines, voices)
    if problems:
        raise SystemExit("can't record yet:\n  " + "\n  ".join(problems))
    only = {s.strip() for s in args.only.split(",") if s.strip()} or None
    unknown = (only or set()) - {line["voice"] for line in lines}
    if unknown:
        raise SystemExit("no dialogue line has voice id %s" % ", ".join(sorted(unknown)))
    model = voices.get("model", c.TTS_MODEL)
    todo = plan(lines, voices, c.load_made(), only, args.force)
    if not todo:
        print("voices: nothing to record; %d voiced lines all have current clips" % len(lines))
        return 0
    chars, credits = estimate(todo, model)
    print("voices: %d lines to record, %d characters, about %d credits (%s)" % (len(todo), chars, credits, model))
    for item in todo:
        print("  %-22s %-8s %-10s \"%s\"" % (item["line"]["voice"], item["reason"], item["line"].get("speaker", ""),
                                            item["line"]["text"][:60]))
    if args.dry_run:
        print("(dry run: nothing sent)")
        return 0
    client = c.Client(args.base_url)
    before = client.credits_left()
    report = generate(todo, voices, client)
    after = client.credits_left()
    c.append_ledger(c.ledger_path(client.url), "voices: %d lines" % len(todo), model, len(todo),
                    "%d chars" % chars, credits, before, after, args.note or ("" if client.real else "mock"))
    print("voices: recorded %d, failed %d, billed %d characters; credits %s -> %s%s" % (
        len(report["made"]), len(report["failed"]), report["billed_chars"], before, after,
        "" if client.real else " [mock]"))
    print("  ledger: %s. Next: make import, then talk to them in the game." % c.rel(c.ledger_path(client.url)))
    return 1 if report["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
