#!/usr/bin/env python3
"""Record the director's taps from a published choices page in data/decisions/<name>.json.

    python3 tools/pages/apply_choices.py <name> <dump>        # or: make choices-apply NAME=<name> IN=<dump>

<dump> is what the ArtifactData tool's read of the page's "choices" collection gave you. The simple path:

    ArtifactData  action="list"  url=<the page's artifact url>  collection="choices"  out_dir="build/pages/<name>/taps"

which saves one file per question, build/pages/<name>/taps/choices/<question id>.json; then IN=build/pages/<name>/taps.
Also accepted: a single JSON file holding the read result as text (a list of documents, {"documents": [...]},
{"docs": [...]}, or {"<question id>": {...}}), each document either the body itself or {"id", "data": body, ...}.

The output (FIXED; the asset and audio pipelines read it):

    {"<question id>": {"pick": "<option id>" | ["<id>", ...], "note": "<the kid's words>", "at": "<ISO time>"}}

keep_redo questions record "keep" or "redo". An empty pick ("" or []) with a note means the director said none of
these: read the note. Questions with no pick and no note are left out. Answers already in the file for questions the
dump does not mention are kept. Standard library only.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LIST_KEYS = ("documents", "docs", "results", "items", "rows")


class DumpError(ValueError):
    pass


def _doc_id(entry: dict) -> str | None:
    for key in ("id", "doc_id", "name", "path"):
        value = entry.get(key)
        if isinstance(value, str) and value:
            return value.rstrip("/").split("/")[-1]
    return None


def _body(entry: dict) -> dict:
    for key in ("data", "fields", "body"):
        if isinstance(entry.get(key), dict):
            return entry[key]
    return entry


def read_dump(path: Path) -> dict:
    """{question id: document body} from an out_dir folder or a JSON file of the read result."""
    path = Path(path)
    if path.is_dir():
        folder = path / "choices" if (path / "choices").is_dir() else path
        files = sorted(folder.glob("*.json"))
        if not files:
            raise DumpError(f"no .json documents in {folder} (did the read save the 'choices' collection there?)")
        found = {}
        for f in files:
            try:
                entry = json.loads(f.read_text())
            except json.JSONDecodeError as e:
                raise DumpError(f"{f} is not JSON: {e}")
            if isinstance(entry, dict):
                found[f.stem] = _body(entry) if not ("pick" in entry or "note" in entry) else entry
        return found
    if not path.is_file():
        raise DumpError(f"nothing at {path}")
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        raise DumpError(f"{path} is not JSON: {e}")
    if isinstance(data, dict):
        for key in LIST_KEYS:
            if isinstance(data.get(key), list):
                data = data[key]
                break
    if isinstance(data, list):
        found = {}
        for entry in data:
            if not isinstance(entry, dict):
                continue
            doc_id = _doc_id(entry)
            if doc_id:
                found[doc_id] = _body(entry)
        return found
    if isinstance(data, dict):
        return {k: (_body(v) if not ("pick" in v or "note" in v) else v)
                for k, v in data.items() if isinstance(v, dict)}
    raise DumpError(f"{path}: expected a list or an object of documents")


def normalise(docs: dict, spec: dict | None) -> tuple[dict, list]:
    """(decisions in the fixed format, warnings)."""
    questions = {q["id"]: q for q in spec["questions"]} if spec else {}
    out, warnings = {}, []
    for qid, body in docs.items():
        q = questions.get(qid)
        if spec and not q:
            warnings.append(f"{qid}: not a question on this page; skipped")
            continue
        pick = body.get("pick", "")
        many = (q and q["kind"] == "pick_many") or (not q and isinstance(pick, list))
        if many:
            pick = [p for p in (pick if isinstance(pick, list) else [pick]) if isinstance(p, str) and p]
        else:
            pick = pick if isinstance(pick, str) else ""
        note = body.get("note", "")
        note = note.strip() if isinstance(note, str) else ""
        at = body.get("at", "")
        at = at if isinstance(at, str) else ""
        if not pick and not note:
            continue
        if q:
            valid = {"keep", "redo"} if q["kind"] == "keep_redo" else {o["id"] for o in q["options"]}
            for p in (pick if isinstance(pick, list) else [pick] if pick else []):
                if p not in valid:
                    warnings.append(f"{qid}: pick {p!r} is not one of {sorted(valid)}; recorded anyway")
        out[qid] = {"pick": pick, "note": note, "at": at}
    return out, warnings


def apply(name: str, dump: Path, decisions_dir: Path, spec_path: Path | None) -> tuple[Path, dict, list]:
    spec = json.loads(spec_path.read_text()) if spec_path and spec_path.is_file() else None
    found, warnings = normalise(read_dump(dump), spec)
    target = decisions_dir / f"{name}.json"
    existing = json.loads(target.read_text()) if target.is_file() else {}
    merged = {**existing, **found}
    if spec:  # page order, then anything older
        order = [q["id"] for q in spec["questions"]]
        merged = {k: merged[k] for k in order if k in merged} | {k: v for k, v in merged.items() if k not in order}
    decisions_dir.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(merged, indent=2, ensure_ascii=False) + "\n")
    if spec is None:
        warnings.append(f"no spec found for {name}: picks recorded without checking them against the options")
    return target, found, warnings


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("name", help="the page's name (its spec is build/pages/<name>.spec.json)")
    ap.add_argument("dump", help="the out_dir the read saved into, or a JSON file of the read result")
    ap.add_argument("--decisions", default=str(ROOT / "data" / "decisions"), help="where <name>.json goes")
    ap.add_argument("--spec", default=None, help="the spec (default build/pages/<name>.spec.json)")
    args = ap.parse_args(argv)
    spec_path = Path(args.spec) if args.spec else ROOT / "build" / "pages" / f"{args.name}.spec.json"
    try:
        target, found, warnings = apply(args.name, Path(args.dump), Path(args.decisions), spec_path)
    except (DumpError, json.JSONDecodeError) as e:
        print(f"choices apply FAILED: {e}", file=sys.stderr)
        return 1
    for w in warnings:
        print(f"choices apply: {w}", file=sys.stderr)
    for qid, d in found.items():
        pick = ", ".join(d["pick"]) if isinstance(d["pick"], list) else d["pick"]
        print(f"  {qid:<20} {pick or '(none of these)':<24} {('“' + d['note'] + '”') if d['note'] else ''}")
    print(f">> choices apply: {len(found)} answer(s) recorded in {target.relative_to(ROOT) if target.is_relative_to(ROOT) else target}")
    if not found:
        print(">> nothing tapped yet: ask the director to open the page and pick, then read the taps again")
    return 0


if __name__ == "__main__":
    sys.exit(main())
