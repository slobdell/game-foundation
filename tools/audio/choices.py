#!/usr/bin/env python3
"""Let the director HEAR a few takes and pick: builds a choices-page spec, then applies the picks.

    python3 tools/audio/choices.py build --name squishy --sounds footstep [--n 4]          # PAID: new takes
    python3 tools/audio/choices.py build --name lines --lines guide_hi_1,guide_hi_2         # PAID: new takes
    python3 tools/audio/choices.py build --name guide_voice --speaker guide --voices ID1,ID2,ID3 [--text "Ahoy!"]
    python3 tools/audio/choices.py apply --name squishy                                     # after the taps

build: makes the candidate takes (kept in build/audio/candidates/, reused while the prompt/text is unchanged so a
rebuilt page costs nothing), writes build/pages/<name>.spec.json for tools/pages/choices_page.py, and remembers which
file each option is in build/audio/candidates/<name>.choices.json. One question per sound, line, or speaker:

    sound.<id>      pick the take(s) the game should use (a sound with variants > 1 lets you pick several)
    line.<id>       pick the best reading of a dialogue line
    speaker.<name>  pick the voice a character speaks with (each option says the same sample line)

apply: reads data/decisions/<name>.json ({"<question id>": {"pick": ..., "note": ...}}) and puts the picked takes into
the game (assets/audio/sfx/<id>_v<n>.ogg, assets/voices/<line>.ogg, or the speaker's voice_id in data/voices.json).
An empty pick means "none of these": its note says what to change; nothing is touched.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as c  # noqa: E402
import sfx  # noqa: E402
import voices as vo  # noqa: E402

DEFAULT_SAMPLE = "Hi there! I'm so glad you're here. Come on, let's go and explore!"


def _takes_dir(kind: str, key: str, root: Path) -> Path:
    return root / kind / key


def _ensure_takes(folder: Path, fp: str, n: int, make, log) -> tuple[list[Path], int]:
    """Up to n takes in folder (made by make(path)), reusing ones made from the same fingerprint. -> (takes, new)."""
    meta = c.read_json(folder / "takes.json", {})
    if meta.get("fp") != fp and folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True, exist_ok=True)
    c.write_json(folder / "takes.json", {"fp": fp})
    takes, new = [], 0
    for k in range(1, n + 1):
        path = folder / ("take%d.ogg" % k)
        if not path.exists():
            make(path, k)
            new += 1
            log("  made %s" % c.rel(path))
        takes.append(path)
    return takes, new


def build(name: str, sound_ids: list[str], line_ids: list[str], speaker_name: str = "", voice_ids: list[str] = (),
          text: str = "", n: int = 0, client: c.Client | None = None, root: Path = c.CANDIDATES,
          pages: Path = c.PAGES, log=print) -> dict:
    """Returns {"spec": path, "requests": int, "seconds": float, "chars": int}. Needs a client only for new takes."""
    sounds = {s["id"]: s for s in sfx.load()}
    voices = vo.load_voices()
    model = voices.get("model", c.TTS_MODEL)
    lines = {line["voice"]: line for line in vo.voiced_lines()}
    questions, sidecar, cost = [], {}, {"requests": 0, "seconds": 0.0, "chars": 0}

    def need_client():
        if client is None:
            raise SystemExit("new takes are needed; that costs credits (run without --dry-run)")
        return client

    for sid in sound_ids:
        if sid not in sounds:
            raise SystemExit("%r is not in assets/audio/sounds.json: add it first" % sid)
        sound = sounds[sid]
        variants = int(sound.get("variants", 1))
        count = n or min(8, max(3, variants + 1))

        def make(path, k, sound=sound):
            need_client()
            sfx.make_take(client, sound, path, c.BUILD_AUDIO / "masters" / ("try_%s_%d.%s.mp3" % (
                sound["id"], k, sfx.fingerprint(sound))))
            cost["requests"] += 1
            cost["seconds"] += float(sound["duration"])

        takes, _ = _ensure_takes(_takes_dir("sound", sid, root), sfx.fingerprint(sound), count, make, log)
        options = [{"id": "take%d" % k, "label": "Take %d" % k, "audio": c.rel(p)} for k, p in enumerate(takes, 1)]
        current = sfx.files_for(sid)
        if current and sfx.status(sound, c.load_made()) != "placeholder":
            options.append({"id": "current", "label": "The one in the game now", "audio": c.rel(current[0])})
        many = variants > 1
        questions.append({
            "id": "sound.%s" % sid, "kind": "pick_many" if many else "pick_one",
            "prompt": ("Which %s sounds are best? Pick about %d: the game mixes them up." % (sid.replace("_", " "), variants))
            if many else "Which %s sound is best?" % sid.replace("_", " "),
            "options": options})
        sidecar["sound.%s" % sid] = {"kind": "sound", "id": sid, "fp": sfx.fingerprint(sound),
                                     "options": {o["id"]: o["audio"] for o in options}}

    for line_id in line_ids:
        if line_id not in lines:
            raise SystemExit("no dialogue line has \"voice\": %r" % line_id)
        line = lines[line_id]
        entry = vo.speaker(voices, line.get("speaker", ""))
        if entry is None:
            raise SystemExit("%r is spoken by %r, who has no voice in data/voices.json" % (line_id, line.get("speaker")))
        fp = vo.fingerprint(line, entry, model)

        def make(path, k, line=line, entry=entry, fp=fp):
            need_client()
            _, billed = vo.record_line(client, line["text"], entry, model, path,
                                       c.BUILD_AUDIO / "voice_masters" / ("try_%s_%d.%s.mp3" % (line["voice"], k, fp)))
            cost["requests"] += 1
            cost["chars"] += billed

        takes, _ = _ensure_takes(_takes_dir("line", line_id, root), fp, n or 3, make, log)
        options = [{"id": "take%d" % k, "label": "Take %d" % k, "audio": c.rel(p), "text": line["text"]}
                   for k, p in enumerate(takes, 1)]
        questions.append({"id": "line.%s" % line_id, "kind": "pick_one",
                          "prompt": "%s says: \"%s\". Which reading is best?" % (line.get("speaker"), line["text"]),
                          "options": options})
        sidecar["line.%s" % line_id] = {"kind": "line", "id": line_id, "fp": fp,
                                        "options": {o["id"]: o["audio"] for o in options}}

    if speaker_name:
        entry = vo.speaker(voices, speaker_name)
        key = next((k for k in voices.get("speakers", {}) if k.lower() == speaker_name.lower()), speaker_name.lower())
        if len(voice_ids) < 2:
            raise SystemExit("give at least 2 voice ids to choose between (make voice-list shows them)")
        sample = text or next((l["text"] for l in lines.values() if str(l.get("speaker", "")).lower() == key), DEFAULT_SAMPLE)
        settings = (entry or {}).get("settings", {})
        names = {}
        if client is not None:
            try:
                names = {v["voice_id"]: v.get("name", v["voice_id"]) for v in client.voices()}
            except c.ElevenLabsError:
                names = {}
        options = []
        for voice_id in voice_ids:
            fake_entry = {"voice_id": voice_id, "settings": settings}
            fp = c.fingerprint(sample, voice_id, settings, model)

            def make(path, k, fake_entry=fake_entry, fp=fp):
                need_client()
                _, billed = vo.record_line(client, sample, fake_entry, model, path,
                                           c.BUILD_AUDIO / "voice_masters" / ("try_voice_%s.%s.mp3" % (fake_entry["voice_id"], fp)))
                cost["requests"] += 1
                cost["chars"] += billed

            takes, _ = _ensure_takes(_takes_dir("speaker", "%s_%s" % (key, voice_id), root), fp, 1, make, log)
            label = names.get(voice_id, voice_id)
            if entry and entry.get("voice_id") == voice_id:
                label += " (now)"
            options.append({"id": voice_id, "label": label, "audio": c.rel(takes[0]), "text": sample})
        questions.append({"id": "speaker.%s" % key, "kind": "pick_one",
                          "prompt": "Which voice should %s have?" % key, "options": options})
        sidecar["speaker.%s" % key] = {"kind": "speaker", "id": key,
                                       "options": {o["id"]: {"audio": o["audio"], "name": o["label"].replace(" (now)", "")}
                                                   for o in options}}

    if not questions:
        raise SystemExit("nothing to choose: give --sounds, --lines, or --speaker with --voices")
    spec = {"name": name, "title": "Pick your sounds" if not speaker_name else "Pick a voice",
            "intro": "Press play on each one, then pick the one you like best. Write a note if none are right "
                     "(like \"squishier\" or \"more pirate-y\").",
            "questions": questions}
    spec_path = pages / ("%s.spec.json" % name)
    c.write_json(spec_path, spec)
    c.write_json(root / ("%s.choices.json" % name), sidecar)
    return dict(cost, spec=spec_path, model=model)


def save_sounds(sounds: list[dict], path: Path = c.SOUNDS_JSON) -> None:
    """One sound per line, the way the starter file is written (easy to read and to diff)."""
    path.write_text("[\n" + ",\n".join("  " + json.dumps(s, ensure_ascii=False) for s in sounds) + "\n]\n")


def apply(name: str, root: Path = c.CANDIDATES, decisions: Path = c.DECISIONS, log=print) -> int:
    decision_path = decisions / ("%s.json" % name)
    sidecar = c.read_json(root / ("%s.choices.json" % name), None)
    if sidecar is None:
        raise SystemExit("no candidates for %r (build/audio/candidates/%s.choices.json); run audio-choices first"
                         % (name, name))
    answers = c.read_json(decision_path, None)
    if answers is None:
        raise SystemExit("no answers yet: %s (make choices-apply NAME=%s IN=... records the taps)" % (c.rel(decision_path), name))
    sounds = sfx.load()
    by_id = {s["id"]: s for s in sounds}
    voices = vo.load_voices()
    changed_sounds = False
    applied = 0
    for qid, info in sidecar.items():
        answer = answers.get(qid)
        if not answer:
            log("  %s: no answer yet" % qid)
            continue
        pick = answer.get("pick")
        picks = [p for p in (pick if isinstance(pick, list) else [pick]) if p]
        note = str(answer.get("note", "")).strip()
        if not picks:
            log("  %s: none of these. Their note: \"%s\". Change the prompt/text/voice and build the page again."
                % (qid, note or "(no note)"))
            continue
        unknown = [p for p in picks if p not in info["options"]]
        if unknown:
            log("  %s: picks %s are not options of this page; skipped" % (qid, unknown))
            continue
        if info["kind"] == "sound":
            sound = by_id.get(info["id"])
            if sound is None:
                log("  %s: %s is no longer in sounds.json; skipped" % (qid, info["id"]))
                continue
            takes = []
            for p in picks:
                if p == "current":
                    takes += sfx.files_for(sound["id"])
                else:
                    takes.append(c.ROOT / info["options"][p])
            staged = []
            scratch = root / "_staging" / sound["id"]
            scratch.mkdir(parents=True, exist_ok=True)
            for k, take in enumerate(takes, 1):  # copy first: "current" files are about to be replaced
                staged.append(scratch / ("%d.ogg" % k))
                shutil.copyfile(take, staged[-1])
            sfx.install(sound, staged, fp=info["fp"])
            shutil.rmtree(scratch, ignore_errors=True)
            if int(sound.get("variants", 1)) != len(staged):
                sound["variants"] = len(staged)
                changed_sounds = True
            log("  %s: %d take(s) now in the game (%s)" % (qid, len(staged), ", ".join(picks)))
        elif info["kind"] == "line":
            dest = vo.clip_path(info["id"])
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(c.ROOT / info["options"][picks[0]], dest)
            c.record_made({c.rel(dest): {"by": "elevenlabs", "fp": info["fp"], "at": c.now_iso()}})
            log("  %s: %s is the line now" % (qid, picks[0]))
        elif info["kind"] == "speaker":
            voice_id = picks[0]
            entry = voices.setdefault("speakers", {}).setdefault(info["id"], {"settings": {}})
            old = entry.get("voice_id")
            entry["voice_id"] = voice_id
            entry["voice_name"] = info["options"][voice_id]["name"]
            c.write_json(c.VOICES_JSON, voices)
            stale = [l["voice"] for l in vo.voiced_lines() if str(l.get("speaker", "")).lower() == info["id"].lower()]
            log("  %s: %s speaks with %s now%s" % (qid, info["id"], entry["voice_name"],
                                                   "" if old != voice_id or not stale else " (unchanged)"))
            if stale and old != voice_id:
                log("    %d of their lines need recording in the new voice: make voices" % len(stale))
        applied += 1
        if note:
            log("    their note: \"%s\"" % note)
    if changed_sounds:
        save_sounds(sounds)
        log("  sounds.json: variants updated to the number of takes picked")
    log("applied %d of %d questions. Next: make import, then play." % (applied, len(sidecar)))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    b = sub.add_parser("build")
    b.add_argument("--name", required=True, help="the page's name (lowercase slug)")
    b.add_argument("--sounds", default="")
    b.add_argument("--lines", default="")
    b.add_argument("--speaker", default="")
    b.add_argument("--voices", default="")
    b.add_argument("--text", default="", help="what each candidate voice says (default: one of the speaker's lines)")
    b.add_argument("--n", type=int, default=0, help="takes per sound/line (default 3, more for sounds with variants)")
    b.add_argument("--base-url", default="")
    b.add_argument("--note", default="")
    a = sub.add_parser("apply")
    a.add_argument("--name", required=True)
    args = parser.parse_args(argv)
    if args.command == "apply":
        return apply(args.name)
    split = lambda text: [x.strip() for x in text.split(",") if x.strip()]  # noqa: E731
    import re
    if not re.match(r"^[a-z0-9][a-z0-9_-]{0,63}$", args.name):
        raise SystemExit("NAME must be a lowercase slug like footstep_pick")
    try:
        client = c.Client(args.base_url)
    except SystemExit as no_key:  # fine while every take already exists; build() says so if one must be made
        client, why = None, str(no_key)
    before = client.credits_left() if client else None
    try:
            result = build(args.name, split(args.sounds), split(args.lines), args.speaker, split(args.voices), args.text,
                       args.n, client)
    except SystemExit as error:
        if client is None and "costs credits" in str(error):
            raise SystemExit(why) from None
        raise
    if result["requests"]:
        after = client.credits_left()
        estimate = int(round(result["seconds"] * c.SFX_CREDITS_PER_SECOND +
                             result["chars"] * c.TTS_CREDITS_PER_CHAR.get(result["model"], 1.0)))
        amount = ", ".join(x for x in ("%.1f s" % result["seconds"] if result["seconds"] else "",
                                       "%d chars" % result["chars"] if result["chars"] else "") if x)
        c.append_ledger(c.ledger_path(client.url), "choices %s" % args.name,
                        c.SFX_MODEL if result["seconds"] and not result["chars"] else result["model"],
                        result["requests"], amount, estimate, before, after,
                        args.note or ("" if client.real else "mock"))
        print("choices: %d new takes, about %d credits; credits %s -> %s%s" % (
            result["requests"], estimate, before, after, "" if client.real else " [mock]"))
    else:
        print("choices: every take already existed; nothing spent")
    print("spec: %s\nnext: make choices-page NAME=%s, publish it, the director taps, make choices-apply, then "
          "make audio-apply NAME=%s" % (c.rel(result["spec"]), args.name, args.name))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
