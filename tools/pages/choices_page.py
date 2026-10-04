#!/usr/bin/env python3
"""Build a tap-to-pick "choices page" from a spec: the director (the kid) taps, Claude reads the taps back.

    python3 tools/pages/choices_page.py build/pages/<name>.spec.json      # or: make choices-page NAME=<name>

Writes build/pages/<name>/index.html (one self-contained page: images and audio embedded as data: URIs) and
build/pages/<name>/publish.json (the exact Artifact-tool arguments to publish it). If the media would push the page
past the size budget, they are written to build/pages/<name>/media/ instead and publish.json lists them as `files`.

The spec (the contract other tools write; _agents/choices_pages.md has the whole story):

    {"name": "<slug>", "title": str, "intro": str,
     "questions": [{"id": str, "prompt": str, "kind": "pick_one" | "keep_redo" | "pick_many",
                    "options": [{"id": str, "label": str, "image": "<repo path>"?, "audio": "<repo path>"?,
                                 "text": str?, "note": str?}]}]}

On the published page every question is saved to the Artifact's database as one document, choices/<question id> =
{"pick": "<option id>" | ["<id>", ...] | "keep" | "redo", "note": "<the kid's words>", "at": "<ISO time>"}.
tools/pages/apply_choices.py turns those documents into data/decisions/<name>.json.

Standard library only. Images are downscaled with Pillow if it is installed, else ffmpeg, else copied as they are;
audio is turned into mp3 with ffmpeg when it is not already mp3/ogg (else copied).
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
TEMPLATE = HERE / "choices_page.html"

KINDS = ("pick_one", "keep_redo", "pick_many")
# The Artifact db's path grammar: letters, digits and _ - . ~ : @ + (we drop the odd ones to keep ids simple).
ID_RE = re.compile(r"^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,63}$")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
IMAGE_MAX_PX = 1024          # long side; big enough to fill a desktop card, small enough for a phone
EMBED_BUDGET = 12_000_000    # bytes of embedded media; the published page's hard limit is 16 MB
AUDIO_EXTS = {".mp3", ".ogg", ".oga", ".wav", ".flac", ".m4a", ".aac", ".opus"}
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg"}


class SpecError(ValueError):
    pass


# ---- The spec -----------------------------------------------------------------------------------------------------

def load_spec(path: Path) -> dict:
    try:
        spec = json.loads(Path(path).read_text())
    except FileNotFoundError:
        raise SpecError(f"no spec at {path}")
    except json.JSONDecodeError as e:
        raise SpecError(f"{path} is not valid JSON: {e}")
    validate(spec)
    return spec


def validate(spec: dict, root: Path = ROOT) -> None:
    """Raises SpecError naming the first problem a person can fix."""
    if not isinstance(spec, dict):
        raise SpecError("the spec must be a JSON object")
    name = spec.get("name")
    if not isinstance(name, str) or not NAME_RE.match(name):
        raise SpecError(f"name must be a lowercase slug like 'hero_colour' (got {name!r})")
    if not isinstance(spec.get("title"), str) or not spec["title"].strip():
        raise SpecError("title is required")
    questions = spec.get("questions")
    if not isinstance(questions, list) or not questions:
        raise SpecError("questions must be a non-empty list")
    seen = set()
    for q in questions:
        qid = q.get("id") if isinstance(q, dict) else None
        if not isinstance(qid, str) or not ID_RE.match(qid):
            raise SpecError(f"question id {qid!r}: use letters, digits, _ - . only (it becomes a database path)")
        if qid in seen:
            raise SpecError(f"question id {qid!r} is used twice")
        seen.add(qid)
        if q.get("kind") not in KINDS:
            raise SpecError(f"question {qid}: kind must be one of {', '.join(KINDS)} (got {q.get('kind')!r})")
        if not isinstance(q.get("prompt"), str) or not q["prompt"].strip():
            raise SpecError(f"question {qid}: prompt is required")
        options = q.get("options")
        if not isinstance(options, list) or not options:
            raise SpecError(f"question {qid}: options must be a non-empty list")
        if q["kind"] != "keep_redo" and len(options) < 2:
            raise SpecError(f"question {qid}: a {q['kind']} question needs at least 2 options")
        oids = set()
        for o in options:
            oid = o.get("id") if isinstance(o, dict) else None
            if not isinstance(oid, str) or not ID_RE.match(oid):
                raise SpecError(f"question {qid}: option id {oid!r}: use letters, digits, _ - . only")
            if oid in oids:
                raise SpecError(f"question {qid}: option id {oid!r} is used twice")
            oids.add(oid)
            if not isinstance(o.get("label"), str) or not o["label"].strip():
                raise SpecError(f"question {qid}, option {oid}: label is required")
            for key, exts in (("image", IMAGE_EXTS), ("audio", AUDIO_EXTS)):
                if key in o and o[key] is not None:
                    p = (root / o[key]) if not Path(o[key]).is_absolute() else Path(o[key])
                    if not p.is_file():
                        raise SpecError(f"question {qid}, option {oid}: {key} file not found: {o[key]}")
                    if p.suffix.lower() not in exts:
                        raise SpecError(f"question {qid}, option {oid}: {key} must be one of {sorted(exts)}")


# ---- Media --------------------------------------------------------------------------------------------------------

def _run(cmd: list) -> bool:
    try:
        return subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def _has_alpha_ffprobe(src: Path) -> bool:
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=pix_fmt",
                              "-of", "csv=p=0", str(src)], capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired):
        return True
    return "a" in out.replace("gray", "")  # rgba, ya8, pal8 w/ alpha shows as pal8 (kept as png below)


def prepare_image(src: Path, work: Path, convert: bool = True) -> Path:
    """A web-sized copy of src (long side <= IMAGE_MAX_PX): JPEG unless it has transparency (then PNG)."""
    if not convert or src.suffix.lower() in (".svg", ".gif"):
        return src
    try:
        from PIL import Image  # optional
        with Image.open(src) as im:
            im.load()
            alpha = im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info)
            if max(im.size) <= IMAGE_MAX_PX and src.stat().st_size < 400_000:
                return src
            im.thumbnail((IMAGE_MAX_PX, IMAGE_MAX_PX))
            out = work / (src.stem + (".png" if alpha else ".jpg"))
            if alpha:
                im.convert("RGBA").save(out, optimize=True)
            else:
                im.convert("RGB").save(out, quality=84, optimize=True, progressive=True)
            return out
    except ImportError:
        pass
    except Exception as e:  # a file Pillow cannot read: let ffmpeg try
        print(f"choices page: Pillow could not read {src.name} ({e}); trying ffmpeg", file=sys.stderr)
    if shutil.which("ffmpeg"):
        alpha = src.suffix.lower() in (".png", ".webp") and _has_alpha_ffprobe(src)
        out = work / (src.stem + (".png" if alpha else ".jpg"))
        scale = f"scale='min({IMAGE_MAX_PX},iw)':'min({IMAGE_MAX_PX},ih)':force_original_aspect_ratio=decrease"
        cmd = ["ffmpeg", "-y", "-v", "error", "-i", str(src), "-vf", scale, "-frames:v", "1"]
        cmd += [] if alpha else ["-q:v", "4"]
        if _run(cmd + [str(out)]) and out.stat().st_size < src.stat().st_size:
            return out
        return src
    print(f"choices page: no Pillow or ffmpeg; {src.name} goes in at full size", file=sys.stderr)
    return src


def prepare_audio(src: Path, work: Path, convert: bool = True) -> Path:
    """mp3/ogg as they are (re-encoded only when big); anything else becomes a 128 kbit/s mp3."""
    ext = src.suffix.lower()
    small_web = ext in (".mp3", ".ogg", ".oga", ".opus", ".m4a") and src.stat().st_size < 1_500_000
    if not convert or small_web:
        return src
    if not shutil.which("ffmpeg"):
        print(f"choices page: no ffmpeg; {src.name} goes in as it is ({src.stat().st_size // 1000} kB)",
              file=sys.stderr)
        return src
    out = work / (src.stem + ".mp3")
    kbps = "128k" if ext not in (".mp3", ".ogg") else "96k"
    if _run(["ffmpeg", "-y", "-v", "error", "-i", str(src), "-vn", "-c:a", "libmp3lame", "-b:a", kbps, str(out)]):
        return out
    print(f"choices page: ffmpeg could not convert {src.name}; it goes in as it is", file=sys.stderr)
    return src


def _mime(path: Path) -> str:
    ext = path.suffix.lower()
    return {".mp3": "audio/mpeg", ".ogg": "audio/ogg", ".oga": "audio/ogg", ".opus": "audio/ogg",
            ".wav": "audio/wav", ".flac": "audio/flac", ".m4a": "audio/mp4", ".aac": "audio/aac",
            ".svg": "image/svg+xml", ".webp": "image/webp"}.get(ext) or mimetypes.guess_type(path.name)[0] \
        or "application/octet-stream"


# ---- Build --------------------------------------------------------------------------------------------------------

def build(spec: dict, out_root: Path, root: Path = ROOT, convert: bool = True, embed: str = "auto") -> dict:
    """Writes <out_root>/<name>/index.html (+ media/, publish.json). Returns the publish arguments."""
    validate(spec, root)
    name = spec["name"]
    out_dir = out_root / name
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)
    page = {"name": name, "title": spec["title"], "intro": spec.get("intro", ""), "questions": []}
    media = []  # (option dict in page, key, prepared path)
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for qi, q in enumerate(spec["questions"]):
            pq = {"id": q["id"], "prompt": q["prompt"], "kind": q["kind"], "options": []}
            for o in q["options"]:
                po = {k: o[k] for k in ("id", "label", "text", "note") if o.get(k)}
                for key, prep in (("image", prepare_image), ("audio", prepare_audio)):
                    if o.get(key):
                        src = Path(o[key]) if Path(o[key]).is_absolute() else root / o[key]
                        sub = work / f"{qi}_{o['id']}_{key}"
                        sub.mkdir()
                        prepared = prep(src, sub, convert)
                        kept = sub / f"{q['id']}--{o['id']}{prepared.suffix.lower()}"
                        shutil.copyfile(prepared, kept)
                        media.append((po, key, kept))
                pq["options"].append(po)
            page["questions"].append(pq)
        total = sum(p.stat().st_size for _, _, p in media)
        inline = embed == "always" or (embed == "auto" and total * 4 / 3 < EMBED_BUDGET)
        files = {}
        if inline:
            for po, key, p in media:
                po[key] = f"data:{_mime(p)};base64," + base64.b64encode(p.read_bytes()).decode("ascii")
        else:
            (out_dir / "media").mkdir()
            for po, key, p in media:
                shutil.copyfile(p, out_dir / "media" / p.name)
                po[key] = f"media/{p.name}"
                files[f"media/{p.name}"] = _rel(out_dir / "media" / p.name, root)
    html_text = render(page)
    index = out_dir / "index.html"
    index.write_text(html_text)
    size = index.stat().st_size
    if size > 16_000_000:
        raise SpecError(f"the page is {size / 1e6:.1f} MB; the limit is 16 MB. Use fewer or shorter media.")
    publish = {
        "file_path": _rel(index, root),
        "capabilities": {"db": {}},
        "icon": "vote",
        "description": "Tap a pick in each scene; your picks save for Claude to read.",
    }
    if files:
        publish["files"] = files
    (out_dir / "publish.json").write_text(json.dumps(publish, indent=2) + "\n")
    publish["_stats"] = {"page_bytes": size, "media_bytes": total, "media_count": len(media), "embedded": inline}
    return publish


def _rel(path: Path, root: Path) -> str:
    try:
        return str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        return str(path.resolve())


def _esc(text: str) -> str:
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;"))


def render(page: dict) -> str:
    data = json.dumps(page, ensure_ascii=False).replace("</", "<\\/").replace("<!--", "<\\!--")
    return (TEMPLATE.read_text()
            .replace("__TITLE__", _esc(page["title"]))
            .replace("__PAGE_JSON__", data))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("spec", help="build/pages/<name>.spec.json")
    ap.add_argument("--out", default=str(ROOT / "build" / "pages"), help="output root (default build/pages)")
    ap.add_argument("--embed", choices=("auto", "always", "never"), default="auto",
                    help="put media inside the page (auto: when they fit the size budget)")
    ap.add_argument("--no-convert", action="store_true", help="use media files exactly as they are")
    args = ap.parse_args(argv)
    try:
        spec = load_spec(Path(args.spec))
        publish = build(spec, Path(args.out), convert=not args.no_convert, embed=args.embed)
    except SpecError as e:
        print(f"choices page FAILED: {e}", file=sys.stderr)
        return 1
    st = publish.pop("_stats")
    n_q = len(spec["questions"])
    print(f">> choices page: {publish['file_path']} ({st['page_bytes'] / 1e6:.2f} MB, {n_q} question(s), "
          f"{st['media_count']} media file(s) {'embedded' if st['embedded'] else 'beside it in media/'})")
    print(f">> publish with the Artifact tool using: {Path(publish['file_path']).parent}/publish.json")
    print(json.dumps(publish, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
