#!/usr/bin/env python3
"""The kid's picks and the Meshy spend ledger: nothing becomes a 3D model until the kid has picked its picture.

Every new model starts as 2-3 cheap concept pictures (tools/assets/generate.py concept). They wait here until the
kid picks one on a tap-to-pick page, in their own words; only a picked concept goes to image-to-3D, and only once.

    make art-choices NAME=models-1           # build/pages/models-1.spec.json: one question per slot with waiting pictures
    (turn the spec into the tap-to-pick page, the kid taps; their answers land in data/decisions/models-1.json)
    make art-decide NAME=models-1            # apply those answers: picked → approved, the others → rejected
    make art-decide ID=player_b DECISION=approved WORDS="the kid's own words"   # a pick given in chat instead
    make art-status                          # every concept, its status, and the credits spent

Files (all committed: they are the record of what the kid asked for and chose):
    assets/review/review.json       every concept: slot, prompt, task ids, status, the kid's words
    assets/review/images/<id>.jpg   each concept as the kid saw it
    assets/meshy_ledger.md          every Meshy request with its credits

Standard library, plus Pillow for smaller review images when it's installed (otherwise the PNG is copied as is).
"""

import argparse
import fcntl
import json
import re
import shutil
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATUSES = ("waiting", "approved", "rejected", "superseded")
REVIEW_PX = 768
NONE_OPTION = "none"

# Meshy API prices in credits (docs.meshy.ai/en/api/pricing), used when a task doesn't report its own.
PRICES = {
    "text-to-image": 9, "image-to-image": 9,
    "image-to-3d": 15, "image-to-3d meshy-6": 30,
    "text-to-3d-preview": 20, "text-to-3d-refine": 10,
}

LEDGER_HEADER = """# Meshy spend ledger

> Every Meshy API request this game made, appended by `tools/assets/generate.py`: credits as the task reported
> them (`consumed_credits`; failed tasks cost 0; `~` means estimated from the price list). `make art-status`
> prints the total. What things cost and how to spend wisely: `_agents/assets.md`.

| date (UTC) | request | task id | credits | for | result | balance after |
|---|---|---|---:|---|---|---:|
"""


class ReviewError(Exception):
    pass


class Paths:
    """Every file the asset tools read or write, under one root (the repo; a temp folder in tests)."""

    def __init__(self, root=ROOT):
        self.root = Path(root)
        self.review = self.root / "assets" / "review" / "review.json"
        self.images = self.root / "assets" / "review" / "images"
        self.ledger = self.root / "assets" / "meshy_ledger.md"
        self.slots = self.root / "data" / "slots.json"
        self.art_direction = self.root / "_agents" / "art_direction.md"
        self.incoming = self.root / "assets" / "incoming"
        self.pages = self.root / "build" / "pages"
        self.decisions = self.root / "data" / "decisions"

    def rel(self, path: Path) -> str:
        try:
            return str(Path(path).resolve().relative_to(self.root.resolve()))
        except ValueError:
            return str(path)


# ---- slots ----------------------------------------------------------------------------------------------------

def load_slots(paths: Paths) -> dict:
    if not paths.slots.exists():
        raise ReviewError(f"{paths.rel(paths.slots)} is missing")
    data = json.loads(paths.slots.read_text())
    return {name: slot for name, slot in data.items() if not name.startswith("_") and isinstance(slot, dict)}


def slot(paths: Paths, name: str) -> dict:
    slots = load_slots(paths)
    if name not in slots:
        raise ReviewError(f"no slot {name!r} in data/slots.json (make assets-slots lists them; add it there first). "
                          f"Slots: {', '.join(sorted(slots))}")
    return slots[name]


# ---- the manifest ---------------------------------------------------------------------------------------------

def load(paths: Paths) -> dict:
    if not paths.review.exists():
        return {"schema": 1, "items": []}
    return json.loads(paths.review.read_text())


def save(manifest: dict, paths: Paths) -> None:
    paths.review.parent.mkdir(parents=True, exist_ok=True)
    gdignore = paths.review.parent / ".gdignore"
    if not gdignore.exists():  # Godot must not import (or ship) the review pictures
        gdignore.write_text("")
    paths.review.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")


def update(paths: Paths, change):
    """Load, change and save the manifest under a lock (two concept requests can finish at the same time)."""
    paths.review.parent.mkdir(parents=True, exist_ok=True)
    with open(paths.review.with_suffix(".lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        manifest = load(paths)
        result = change(manifest)
        save(manifest, paths)
        return result


def find(manifest: dict, item_id: str) -> dict:
    for item in manifest["items"]:
        if item["id"] == item_id:
            return item
    raise ReviewError(f"no concept {item_id!r} (make art-status lists them)")


def next_id(manifest: dict, slot_name: str) -> str:
    """player_a, player_b, ... the first free letter for this slot."""
    taken = {item["id"] for item in manifest["items"]}
    for n in range(26 * 27):
        suffix = chr(ord("a") + n % 26) if n < 26 else chr(ord("a") + n // 26 - 1) + chr(ord("a") + n % 26)
        if f"{slot_name}_{suffix}" not in taken:
            return f"{slot_name}_{suffix}"
    raise ReviewError(f"too many concepts for {slot_name}")


def review_image(source: Path, dest_stem: Path) -> Path:
    """A smaller JPEG of the concept for the page (or a plain copy if Pillow is missing). Returns the file."""
    dest_stem.parent.mkdir(parents=True, exist_ok=True)
    try:
        from PIL import Image
        with Image.open(source) as image:
            image = image.convert("RGBA")
            image.thumbnail((REVIEW_PX, REVIEW_PX))
            flat = Image.new("RGB", image.size, (214, 214, 218))  # background-removed concepts sit on light grey
            flat.paste(image, mask=image.split()[3])
            dest = dest_stem.with_suffix(".jpg")
            flat.save(dest, "JPEG", quality=88)
            return dest
    except (ImportError, OSError):
        dest = dest_stem.with_suffix(source.suffix)
        shutil.copyfile(source, dest)
        return dest


def add(manifest: dict, paths: Paths, item_id: str, concept_json: Path, title: str = "", note: str = "") -> dict:
    """Registers a finished concept (generate.py wrote <id>.concept.json + .concept.png) as waiting for the kid."""
    if any(item["id"] == item_id for item in manifest["items"]):
        raise ReviewError(f"concept {item_id!r} already exists; a new picture needs a new id")
    sidecar = json.loads(concept_json.read_text())
    task = sidecar["task"]
    png = concept_json.with_name(concept_json.name.replace(".concept.json", ".concept.png"))
    if not png.exists():
        raise ReviewError(f"{png} is missing")
    image = review_image(png, paths.images / item_id)
    item = {
        "id": item_id, "slot": sidecar["slot"], "title": title or sidecar.get("subject", "")[:60],
        "subject": sidecar.get("subject", ""), "prompt": sidecar.get("prompt", ""),
        "references": sidecar.get("references", []), "note": note,
        "concept_task": task["id"], "concept_credits": credits_of(task, "text-to-image"),
        "source_png": paths.rel(png), "image": paths.rel(image),
        "status": "waiting", "kid_words": "", "decided": "", "page": "",
        "model_task": "", "model_file": "", "added": _today(),
    }
    manifest["items"].append(item)
    return item


def decide(manifest: dict, item_id: str, decision: str, words: str, page: str = "") -> dict:
    if decision not in STATUSES:
        raise ReviewError(f"the decision must be one of {', '.join(STATUSES)}")
    if decision == "approved" and not words.strip():
        raise ReviewError("an approval records the kid's own words (WORDS=\"...\"): what they said when they picked it")
    item = find(manifest, item_id)
    item.update(status=decision, kid_words=words.strip(), decided=_today())
    if page:
        item["page"] = page
    return item


def gate_3d(manifest: dict, item_id: str, retry_reason: str = "") -> dict:
    """The concept a 3D request may be built from, or an error saying why not (not picked, or already built)."""
    item = find(manifest, item_id)
    if item["status"] != "approved":
        raise ReviewError(f"concept {item_id!r} is {item['status']}: only a picture the kid picked goes to 3D "
                          f"(make art-choices, then make art-decide once they've picked)")
    if item.get("model_task") and not retry_reason:
        raise ReviewError(f"concept {item_id!r} already went to 3D (task {item['model_task']}, {item.get('model_file')}). "
                          f"Paying again for the same picture is a waste; if that model failed or came out broken, "
                          f"pass RETRY=\"why\"")
    return item


def approved_for(manifest: dict, slot_name: str) -> dict:
    """The newest picked concept for a slot that has no 3D model yet."""
    for item in reversed(manifest["items"]):
        if item["slot"] == slot_name and item["status"] == "approved" and not item.get("model_task"):
            return item
    raise ReviewError(f"no picked concept for {slot_name!r} is waiting for 3D (make art-status)")


def record_model(manifest: dict, item_id: str, task: dict, model_file: str) -> None:
    item = find(manifest, item_id)
    if item.get("model_task"):
        item.setdefault("previous_model_tasks", []).append(item["model_task"])
    item.update(model_task=task.get("id", ""), model_file=model_file,
                model_credits=credits_of(task, task.get("type", "image-to-3d")))


def model_file(manifest: dict, paths: Paths, slot_name: str) -> Path:
    """The newest downloaded 3D model for a slot (what make model-fit uses when IN= isn't given)."""
    for item in reversed(manifest["items"]):
        if item["slot"] == slot_name and item.get("model_file") and (paths.root / item["model_file"]).exists():
            return paths.root / item["model_file"]
    candidates = sorted(paths.incoming.glob(f"{slot_name}*.glb"), key=lambda p: p.stat().st_mtime)
    if candidates:
        return candidates[-1]
    raise ReviewError(f"no downloaded model for {slot_name!r} yet (make model-generate SLOT={slot_name}, or give IN=)")


# ---- the tap-to-pick page (tools/pages/choices_page.py builds it from this spec) ------------------------------

def choices_spec(manifest: dict, paths: Paths, name: str, title: str = "", intro: str = "", only_slots=()) -> dict:
    """One pick_one question per slot with waiting concepts, plus a "none of these" option. Marks the items as on
    this page, so the answers can be applied by page name."""
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", name or ""):
        raise ReviewError("NAME must be a short lowercase slug like models-1 (letters, digits, - and _)")
    slots = load_slots(paths)
    waiting = [i for i in manifest["items"] if i["status"] == "waiting" and (not only_slots or i["slot"] in only_slots)]
    if not waiting:
        raise ReviewError("no concepts are waiting for the kid (make art-concept first; make art-status)")
    questions = []
    for slot_name in dict.fromkeys(i["slot"] for i in waiting):
        about = slots.get(slot_name, {}).get("notes", "")
        options = [{"id": i["id"], "label": i["title"] or i["id"], "image": i["image"],
                    **({"note": i["note"]} if i.get("note") else {})}
                   for i in waiting if i["slot"] == slot_name]
        options.append({"id": NONE_OPTION, "label": "None of these",
                        "text": "Make new pictures. Write in the note what to change."})
        questions.append({"id": slot_name, "kind": "pick_one",
                          "prompt": f"Which one should be {about or slot_name}?" if about else f"Which {slot_name} do you like best?",
                          "options": options})
        for item in waiting:
            if item["slot"] == slot_name:
                item["page"] = name
    return {"name": name, "title": title or "Pick your models",
            "intro": intro or ("Tap the picture you like best for each one. Only the one you pick gets made into 3D, "
                               "so take your time. Add a note to say what you love or what to change."),
            "questions": questions}


def write_spec(spec: dict, paths: Paths) -> Path:
    paths.pages.mkdir(parents=True, exist_ok=True)
    out = paths.pages / f"{spec['name']}.spec.json"
    out.write_text(json.dumps(spec, indent=2, ensure_ascii=False) + "\n")
    return out


def apply_decisions(manifest: dict, paths: Paths, name: str) -> list:
    """Reads data/decisions/<name>.json (the kid's answers) and records them. Returns printable lines."""
    path = paths.decisions / f"{name}.json"
    if not path.exists():
        raise ReviewError(f"{paths.rel(path)} doesn't exist yet: the kid hasn't sent their picks from page {name!r}")
    answers = json.loads(path.read_text())
    lines = []
    for slot_name, answer in answers.items():
        on_page = [i for i in manifest["items"] if i.get("page") == name and i["slot"] == slot_name]
        if not on_page:
            lines.append(f"{slot_name}: no concepts from page {name!r} for this question (skipped)")
            continue
        picks = answer.get("pick")
        picks = picks if isinstance(picks, list) else [picks] if picks else []
        words = str(answer.get("note", "") or "").strip()
        if not picks and words:  # an empty pick with a note is "none of these" (tools/pages/apply_choices.py)
            picks = [NONE_OPTION]
        known = {i["id"] for i in on_page} | {NONE_OPTION}
        unknown = [p for p in picks if p not in known]
        if unknown:
            raise ReviewError(f"{slot_name}: picked {unknown}, which weren't options on page {name!r}")
        for item in on_page:
            if item["status"] != "waiting":
                continue  # already decided (applying twice changes nothing)
            if item["id"] in picks:
                decide(manifest, item["id"], "approved", words or f"picked it on page {name} (no note)", name)
                lines.append(f"{slot_name}: PICKED {item['id']} ({item['title']})" + (f": “{words}”" if words else ""))
            elif NONE_OPTION in picks:  # the note is about what to change: it applies to all of them
                decide(manifest, item["id"], "rejected", f"chose none of these on page {name}" + (f": {words}" if words else ""), name)
            elif picks:  # the note was about the one they picked, not this one
                decide(manifest, item["id"], "rejected", f"picked {', '.join(picks)} instead on page {name}", name)
        if NONE_OPTION in picks:
            lines.append(f"{slot_name}: NONE of these. Make new pictures" + (f"; the kid said: “{words}”" if words else
                                                                                 " (ask the kid what to change)"))
        if not picks:
            lines.append(f"{slot_name}: not answered yet (still waiting)")
    return lines


# ---- the ledger -----------------------------------------------------------------------------------------------

def credits_of(task: dict, request: str = "") -> str:
    """The credits a task cost: what Meshy reported, else "~<price>" from the list (0 for a failed task)."""
    for key in ("consumed_credits", "credits_consumed"):
        if task.get(key) is not None:
            return str(task[key])
    if task.get("status") in ("FAILED", "CANCELED"):
        return "0"
    return f"~{PRICES.get(request, 0)}"


def ledger_append(request: str, task: dict, purpose: str, balance, path: Path) -> str:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(LEDGER_HEADER)
    credits = credits_of(task, request)
    row = "| %s | %s | `%s` | %s | %s | %s | %s |\n" % (
        time.strftime("%Y-%m-%d %H:%M", time.gmtime()), request, task.get("id", "?"), credits,
        purpose.replace("|", "/"), task.get("status", "?"), balance)
    with path.open("a") as ledger:
        ledger.write(row)
    return credits


def ledger_total(path: Path) -> int:
    if not path.exists():
        return 0
    total = 0
    for line in path.read_text().splitlines():
        cells = [c.strip() for c in line.split("|")]
        if len(cells) > 5 and cells[3].startswith("`"):
            try:
                total += int(cells[4].lstrip("~"))
            except ValueError:
                pass
    return total


def _today() -> str:
    return time.strftime("%Y-%m-%d")


# ---- command line ---------------------------------------------------------------------------------------------

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=str(ROOT), help="repo root (tests use a temp folder)")
    sub = parser.add_subparsers(dest="command", required=True)
    p_add = sub.add_parser("add", help="register an already downloaded concept (generate.py concept does this itself)")
    p_add.add_argument("--id", required=True)
    p_add.add_argument("--concept", required=True, help="the <id>.concept.json generate.py wrote")
    p_add.add_argument("--title", default="")
    p_add.add_argument("--note", default="")
    p_decide = sub.add_parser("decide", help="record one decision given in chat")
    p_decide.add_argument("id")
    p_decide.add_argument("decision", choices=STATUSES)
    p_decide.add_argument("--words", default="")
    p_choices = sub.add_parser("choices", help="write the tap-to-pick page spec for the waiting concepts")
    p_choices.add_argument("--name", required=True)
    p_choices.add_argument("--title", default="")
    p_choices.add_argument("--intro", default="")
    p_choices.add_argument("--slot", action="append", default=[], help="only these slots (repeatable)")
    p_apply = sub.add_parser("apply", help="apply the kid's answers from data/decisions/<name>.json")
    p_apply.add_argument("--name", required=True)
    p_model = sub.add_parser("model-file", help="print the newest downloaded model for a slot")
    p_model.add_argument("--slot", required=True)
    sub.add_parser("status", help="every concept and the credits spent")
    args = parser.parse_args(argv)
    paths = Paths(args.root)
    try:
        if args.command == "add":
            item = update(paths, lambda m: add(m, paths, args.id, Path(args.concept), args.title, args.note))
            print(f"added {item['id']} (waiting for the kid): {item['image']}")
        elif args.command == "decide":
            item = update(paths, lambda m: decide(m, args.id, args.decision, args.words))
            print(f"{item['id']}: {item['status']}")
        elif args.command == "choices":
            def build(manifest):
                return write_spec(choices_spec(manifest, paths, args.name, args.title, args.intro, args.slot), paths)
            out = update(paths, build)
            spec = json.loads(out.read_text())
            count = sum(len(q["options"]) - 1 for q in spec["questions"])
            print(f"wrote {paths.rel(out)}: {len(spec['questions'])} question(s), {count} picture(s)")
            print(f"next: make choices-page NAME={args.name}, publish it and show the kid (_agents/choices_pages.md);\n"
                  f"      once they've tapped: make choices-apply NAME={args.name} IN=<taps folder> → "
                  f"data/decisions/{args.name}.json, then make art-decide NAME={args.name}")
        elif args.command == "apply":
            for line in update(paths, lambda m: apply_decisions(m, paths, args.name)):
                print(line)
            print("next: make model-generate SLOT=<slot> for each PICKED one (≈15 credits each)")
        elif args.command == "model-file":
            print(paths.rel(model_file(load(paths), paths, args.slot)))
        else:
            manifest = load(paths)
            for item in manifest["items"]:
                built = f"  → 3D {item['model_file']}" if item.get("model_file") else ""
                words = f"  “{item['kid_words']}”" if item.get("kid_words") else ""
                print(f"{item['status']:<10} {item['id']:<20} {item['slot']:<16} {item['title']}{words}{built}")
            if not manifest["items"]:
                print("no concepts yet (make art-concept SLOT=<slot> PROMPT=\"...\")")
            print(f"credits spent so far: {ledger_total(paths.ledger)} (assets/meshy_ledger.md)")
    except (ReviewError, OSError, KeyError, json.JSONDecodeError) as error:
        print(f"review: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
