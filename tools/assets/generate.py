#!/usr/bin/env python3
"""Meshy: concept pictures, then 3D models from the picture the kid picked. Every request is logged with its credits.

    generate.py concept --slot player --prompt "a knight made of toast" [--id player_a] [--title "Toast knight"]
                        [--note "tradeoff shown under the picture"] [--reference img.png ...] [--keep-background]
        Text-to-image (or image-to-image with references), ≈9 credits. The game's style from
        _agents/art_direction.md is added to the prompt, plus a "one whole object on a plain background" tail.
        The picture is registered as waiting for the kid (tools/assets/review.py).
    generate.py model --slot player | --id player_b [--retry "why"] [--quality high]
        Image-to-3D from the concept the kid PICKED (refused otherwise, and refused twice), ≈15 credits
        (30 with --quality high). Downloads assets/incoming/<id>.glb (+ texture maps), ready for make model-fit.
    generate.py text3d --slot prop_rock --prompt "..." [--name NAME]
        Text-to-3D with no picture first (≈30 credits): quick experiments only; the picture flow is better.
    generate.py balance
        Credits left on the account (free).

The key comes from the environment (MESHY_API_KEY), never from the repo. MESHY_BASE_URL (or --base-url) points
everything at the mock server (tools/assets/mock_provider.py), which is how the tests run with no network or key.
Standard library only. The whole flow and its lessons: _agents/assets.md.
"""

import argparse
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import review  # noqa: E402
from review import Paths, ReviewError  # noqa: E402

MESHY_URL = "https://api.meshy.ai"
IMAGE_MODEL = "nano-banana-pro"
# Generators overshoot a little; ask for ~85% of the slot's budget so fitting rarely has to simplify.
POLY_HEADROOM = 0.85
SMART_TOPOLOGY_MAX = 15000
LICENSE_NOTE = ("Meshy paid plans: the customer owns generated assets (terms §3.2). Free-plan output is CC BY 4.0 "
                "and needs credit to Meshy.")

# Added after the kid's description so every concept is one whole object, easy to turn into 3D. What each kind
# needs: characters in a relaxed A-pose (arms away from the body, so the 3D step can separate them, and so the
# model can be rigged later); objects seen three-quarter from slightly above, so the front and the top both show.
TAILS = {
    "character": ("One single character, full body in frame from head to feet, standing in a relaxed A-pose with the "
                  "arms held slightly away from the body, three-quarter front view, plain light grey studio background, "
                  "no ground, no shadow, nothing else in the picture, no text, no logos."),
    "build": ("One single building piece with a chunky shape that fills a box, whole piece in frame, three-quarter "
              "view from slightly above, plain light grey studio background, no ground, no people, no text, no logos."),
    "default": ("One single object, the whole thing in frame, three-quarter front view from slightly above, plain "
                "light grey studio background, no ground, no people, nothing else in the picture, no text, no logos."),
}
TAILS["creature"] = TAILS["character"].replace("character", "creature").replace(
    " in a relaxed A-pose with the arms held slightly away from the body", " in a neutral pose with its legs and arms clear of its body")
SCENE_TAIL = "No text, no logos."


class ProviderError(Exception):
    pass


# ---- HTTP -----------------------------------------------------------------------------------------------------

class Http:
    def __init__(self, base_url: str, token: str, retries: int = 4, backoff: float = 2.0):
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.retries = retries
        self.backoff = backoff

    def request(self, method: str, path: str, body=None) -> dict:
        url = path if path.startswith("http") else self.base_url + path
        data = json.dumps(body).encode() if body is not None else None
        for attempt in range(self.retries + 1):
            req = urllib.request.Request(url, data=data, method=method, headers={
                "Authorization": f"Bearer {self.token}", "Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=60) as response:
                    return json.loads(response.read() or b"{}")
            except urllib.error.HTTPError as error:
                detail = error.read().decode(errors="replace")[:300]
                if error.code == 429 and attempt < self.retries:
                    wait = float(error.headers.get("Retry-After") or self.backoff * (2 ** attempt))
                    print(f"  Meshy is busy; trying again in {wait:.0f}s", file=sys.stderr)
                    time.sleep(wait)
                    continue
                hints = {401: "the API key was rejected (check MESHY_API_KEY)", 402: "the account is out of credits",
                         403: "this Meshy plan doesn't include API access (it needs Pro or better)"}
                raise ProviderError(f"{method} {path}: HTTP {error.code} {hints.get(error.code, '')} {detail}".strip())
            except urllib.error.URLError as error:
                raise ProviderError(f"{method} {url}: {error.reason}")
        raise ProviderError(f"{method} {path}: still busy after {self.retries} retries")

    def download(self, url: str, dest: Path) -> int:
        for attempt in range(self.retries + 1):  # a paid result must survive a flaky connection
            try:
                with urllib.request.urlopen(url, timeout=120) as response:
                    payload = response.read()
                break
            except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
                if attempt == self.retries:
                    raise ProviderError(f"download {url}: {error} (Meshy keeps files ~3 days: retry soon)")
                print(f"  download failed ({error}); retrying", file=sys.stderr)
                time.sleep(self.backoff * (2 ** attempt))
        dest.parent.mkdir(parents=True, exist_ok=True)
        if not (dest.parent / ".gdignore").exists():  # raw downloads are never imported (or shipped) by Godot
            (dest.parent / ".gdignore").write_text("")
        dest.write_bytes(payload)
        return len(payload)


# ---- Meshy ----------------------------------------------------------------------------------------------------

class Meshy:
    """Text-to-image, image-to-image, image-to-3D, text-to-3D (preview → refine). Docs: docs.meshy.ai."""
    terminal = {"SUCCEEDED", "FAILED", "CANCELED"}

    def __init__(self, http: Http, poll_interval: float = 5.0, timeout: float = 900.0):
        self.http, self.poll_interval, self.timeout = http, poll_interval, timeout
        self.on_finished = None  # callable(request, task): the ledger

    def balance(self):
        """Credits left, or "" if it can't be read."""
        try:
            return self.http.request("GET", "/openapi/v1/balance").get("balance", "")
        except ProviderError:
            return ""

    def concept(self, prompt: str, references=(), keep_background: bool = False) -> dict:
        # Objects headed for 3D want the background removed; a whole scene (mood picture) must keep it.
        body = {"ai_model": IMAGE_MODEL, "prompt": prompt, "remove_background": not keep_background, "aspect_ratio": "1:1"}
        family = "text-to-image"
        if references:
            family = "image-to-image"
            body["reference_image_urls"] = list(references)
        task_id = self.http.request("POST", f"/openapi/v1/{family}", body)["result"]
        print(f"  {family} task {task_id}")
        return self._wait(f"/openapi/v1/{family}", task_id, family)

    def image_to_3d(self, image: str, polycount: int, quality: str = "normal") -> dict:
        source = {"image_url": image}
        if quality == "high":  # meshy-6: one fused, denser mesh; 30 credits
            shape = {"ai_model": "meshy-6", "should_remesh": True, "topology": "triangle", "target_polycount": polycount}
            request = "image-to-3d meshy-6"
        else:  # meshy-t2 Smart Topology: clean low-poly topology, 15 credits (chosen over meshy-7 in Tank Squad)
            shape = {"model_type": "smart-topology", "ai_model": "meshy-t2",
                     "target_polycount": max(100, min(polycount, SMART_TOPOLOGY_MAX))}
            request = "image-to-3d"
        body = {"target_formats": ["glb"], **shape, **source, "should_texture": True, "enable_pbr": True,
                "texture_resolution": "2k"}
        task_id = self.http.request("POST", "/openapi/v1/image-to-3d", body)["result"]
        print(f"  image-to-3d task {task_id}")
        return self._wait("/openapi/v1/image-to-3d", task_id, request)

    def text_to_3d(self, prompt: str, polycount: int) -> dict:
        preview_id = self.http.request("POST", "/openapi/v2/text-to-3d", {
            "mode": "preview", "prompt": prompt[:600], "ai_model": "meshy-6", "target_formats": ["glb"],
            "should_remesh": True, "topology": "triangle", "target_polycount": polycount})["result"]
        print(f"  text-to-3d preview task {preview_id}")
        self._wait("/openapi/v2/text-to-3d", preview_id, "text-to-3d-preview")
        refine_id = self.http.request("POST", "/openapi/v2/text-to-3d", {
            "mode": "refine", "preview_task_id": preview_id, "ai_model": "meshy-6", "enable_pbr": True,
            "texture_resolution": "2k", "target_formats": ["glb"]})["result"]
        print(f"  text-to-3d refine task {refine_id}")
        return self._wait("/openapi/v2/text-to-3d", refine_id, "text-to-3d-refine")

    def _wait(self, family: str, task_id: str, request: str) -> dict:
        deadline = time.monotonic() + self.timeout
        last = ""
        while True:
            task = self.http.request("GET", f"{family}/{task_id}")
            status = task.get("status", "")
            if status in self.terminal:
                if self.on_finished is not None:
                    self.on_finished(request, task)
                if status != "SUCCEEDED":
                    message = (task.get("task_error") or {}).get("message", "")
                    raise ProviderError(f"task {task_id} {status}: {message} (failed tasks cost nothing; try again, "
                                        f"maybe with a simpler prompt)")
                return task
            if time.monotonic() > deadline:
                raise ProviderError(f"task {task_id} still {status} after {self.timeout:.0f}s; it may still finish: "
                                    f"check app.meshy.ai before asking again (that would pay twice)")
            line = f"  {status.lower().replace('_', ' ')} {task.get('progress', 0)}%"
            if line != last:
                print(line, flush=True)
                last = line
            time.sleep(self.poll_interval)

    @staticmethod
    def files(task: dict) -> dict:
        """{'model': url, '<map>': url} for the GLB and its PBR maps (base_color, normal, emission, ...)."""
        found = {"model": (task.get("model_urls") or {}).get("glb")}
        textures = task.get("texture_urls") or []
        if textures:
            for key, url in textures[0].items():
                if url:
                    found[key] = url
        return found


# ---- prompts --------------------------------------------------------------------------------------------------

def style_prompt(paths: Paths) -> str:
    """The game's ONE look: the ```text block under '## Style prompt' in _agents/art_direction.md."""
    if not paths.art_direction.exists():
        raise ProviderError(f"{paths.rel(paths.art_direction)} is missing: every game writes down its art style first")
    text = paths.art_direction.read_text()
    section = re.search(r"^## Style prompt\s*$(.*?)(?=^## |\Z)", text, re.S | re.M)
    block = re.search(r"```text\s*\n(.*?)```", section.group(1), re.S) if section else None
    if not block:
        raise ProviderError(f"{paths.rel(paths.art_direction)} has no ```text block under '## Style prompt'")
    style = " ".join(block.group(1).split())
    if not style or "TODO" in style or "<" in style:
        raise ProviderError("the art style isn't chosen yet: fill in '## Style prompt' in _agents/art_direction.md with "
                            "the kid first (see that file), or pass --no-style for a one-off")
    return style


def compose(subject: str, kind: str, style: str, keep_background: bool = False) -> str:
    """subject (what the kid described) + the game's style + the 'one whole object' tail."""
    parts = [subject.strip().rstrip(".") + "."]
    if style:
        parts.append(f"Art style: {style.rstrip('.')}.")
    parts.append(SCENE_TAIL if keep_background else TAILS.get(kind, TAILS["default"]))
    return " ".join(parts)


def polycount(slot: dict) -> int:
    return max(100, int(int(slot.get("tris", 3000)) * POLY_HEADROOM))


def data_uri(path: Path) -> str:
    """A local picture as a base64 data URI (Meshy accepts these instead of a public URL)."""
    if not path.exists():
        raise ProviderError(f"image {path} not found")
    kind = "jpeg" if path.suffix.lower() in (".jpg", ".jpeg") else "png"
    return f"data:image/{kind};base64," + base64.b64encode(path.read_bytes()).decode()


# ---- commands -------------------------------------------------------------------------------------------------

def run_concept(args, paths: Paths, meshy: Meshy) -> int:
    slot = review.slot(paths, args.slot)
    manifest = review.load(paths)
    item_id = args.id or review.next_id(manifest, args.slot)
    if not re.fullmatch(r"[a-z0-9_]+", item_id):
        raise ProviderError("the id must be lower_case letters, digits and _ (it becomes a file name)")
    if any(i["id"] == item_id for i in manifest["items"]):
        raise ProviderError(f"concept {item_id!r} already exists (leave out NAME= to get the next free id)")
    style = "" if args.no_style else style_prompt(paths)
    prompt = compose(args.prompt, slot.get("kind", "prop"), style, args.keep_background)
    sidecar = paths.incoming / f"{item_id}.concept.json"
    if sidecar.exists():  # downloaded earlier but never registered (e.g. a crash): register it, don't pay again
        print(f"  {paths.rel(sidecar)} is already downloaded: registering it without a new request")
    else:
        references = [r if r.startswith(("http://", "https://", "data:")) else data_uri(paths.root / r) for r in args.reference]
        meshy.on_finished = ledger_logger(paths, meshy, f"{item_id} ({args.slot})")
        task = meshy.concept(prompt, references, args.keep_background)
        urls = task.get("image_urls") or []
        if not urls:
            raise ProviderError("the picture task succeeded but sent no image")
        size = meshy.http.download(urls[0], paths.incoming / f"{item_id}.concept.png")
        sidecar.write_text(json.dumps({"slot": args.slot, "subject": args.prompt, "prompt": prompt,
                                       "references": args.reference, "keep_background": args.keep_background,
                                       "task": task}, indent=2) + "\n")
        print(f"  downloaded {paths.rel(paths.incoming / (item_id + '.concept.png'))} ({size / 1024:.0f} KB)")
    item = review.update(paths, lambda m: review.add(m, paths, item_id, sidecar, args.title, args.note))
    print(f"concept {item_id} is waiting for the kid: {item['image']}")
    print("next: make 2-3 different ideas for this slot, look at each picture yourself, then make art-choices NAME=<page>")
    return 0


def run_model(args, paths: Paths, meshy: Meshy) -> int:
    manifest = review.load(paths)
    if args.id:
        item = review.gate_3d(manifest, args.id, args.retry)
    else:
        if not args.slot:
            raise ProviderError("give --slot (the newest picked concept for it) or --id")
        item = review.gate_3d(manifest, review.approved_for(manifest, args.slot)["id"], args.retry)
    slot = review.slot(paths, item["slot"])
    source = paths.root / item["source_png"]  # the full-size background-removed original beats the review JPEG
    image = data_uri(source if source.exists() else paths.root / item["image"])
    target = polycount(slot)
    print(f"meshy: making {item['id']} ({item['title']}) into 3D for slot {item['slot']} (about {target} triangles)")
    meshy.on_finished = ledger_logger(paths, meshy, f"{item['id']} ({item['slot']})")
    task = meshy.image_to_3d(image, target, args.quality)
    name = item["id"] if not item.get("model_task") else f"{item['id']}_{len(item.get('previous_model_tasks', [])) + 2}"
    glb = paths.incoming / f"{name}.glb"
    # Record the paid task BEFORE downloading: whatever happens next, it must never be requested twice.
    review.update(paths, lambda m: review.record_model(m, item["id"], task, paths.rel(glb)))
    downloaded = download_all(meshy, task, paths.incoming, name)
    write_sidecar(paths.incoming / f"{name}.json", item["slot"], item["prompt"], task, downloaded, item["id"])
    print(f"next: make model-fit SLOT={item['slot']}   (then make model-look SLOT={item['slot']} and show the kid)")
    return 0


def run_text3d(args, paths: Paths, meshy: Meshy) -> int:
    slot = review.slot(paths, args.slot)
    style = "" if args.no_style else style_prompt(paths)
    prompt = compose(args.prompt, slot.get("kind", "prop"), style)
    name = args.name or f"{args.slot}_t3d_{time.strftime('%Y%m%d_%H%M%S')}"
    meshy.on_finished = ledger_logger(paths, meshy, f"{name} ({args.slot}, no concept)")
    print(f"meshy: text-to-3D for slot {args.slot}")
    task = meshy.text_to_3d(prompt, polycount(slot))
    downloaded = download_all(meshy, task, paths.incoming, name)
    write_sidecar(paths.incoming / f"{name}.json", args.slot, prompt, task, downloaded, "")
    print(f"next: make model-fit SLOT={args.slot} IN={paths.rel(paths.incoming / (name + '.glb'))}")
    return 0


def download_all(meshy: Meshy, task: dict, out_dir: Path, name: str) -> dict:
    downloaded = {}
    for kind, url in Meshy.files(task).items():
        if not url:
            continue
        dest = out_dir / (f"{name}.glb" if kind == "model" else f"{name}.{kind}.png")
        size = meshy.http.download(url, dest)
        downloaded[kind] = dest.name
        print(f"  downloaded {dest.name} ({size / 1024:.0f} KB)")
    if "model" not in downloaded:
        raise ProviderError("the task succeeded but sent no GLB")
    if "emission" in downloaded:
        print(f"  it came with a glow map ({downloaded['emission']}): make model-fit ... GLOW=1 uses it")
    return downloaded


def write_sidecar(path: Path, slot: str, prompt: str, task: dict, files: dict, item_id: str) -> None:
    path.write_text(json.dumps({"slot": slot, "prompt": prompt, "concept": item_id, "files": files,
                                "license_note": LICENSE_NOTE, "task": task,
                                "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z")}, indent=2) + "\n")


def ledger_logger(paths: Paths, meshy: Meshy, purpose: str):
    def log(request: str, task: dict) -> None:
        balance = meshy.balance()
        credits = review.ledger_append(request, task, purpose, balance, paths.ledger)
        left = f"; {balance} left on the account" if balance != "" else ""
        print(f"  Meshy {request}: {credits} credits ({task.get('status')}); "
              f"{review.ledger_total(paths.ledger)} spent so far{left}", flush=True)
    return log


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=str(review.ROOT), help="repo root (tests use a temp folder)")
    parser.add_argument("--base-url", default=os.environ.get("MESHY_BASE_URL", ""), help="the mock server, in tests")
    parser.add_argument("--poll-interval", type=float, default=5.0)
    parser.add_argument("--timeout", type=float, default=900.0)
    sub = parser.add_subparsers(dest="command", required=True)
    p_concept = sub.add_parser("concept", help="a concept picture for the kid to pick from (≈9 credits)")
    p_concept.add_argument("--slot", required=True)
    p_concept.add_argument("--prompt", required=True, help="what the thing is, in plain words (the style is added)")
    p_concept.add_argument("--id", default="", help="default: <slot>_a, <slot>_b, ...")
    p_concept.add_argument("--title", default="", help="a short name the kid will see under the picture")
    p_concept.add_argument("--note", default="", help="one line under the picture: what's good or risky about it")
    p_concept.add_argument("--reference", action="append", default=[], help="a picture (repo path or URL) to start from")
    p_concept.add_argument("--keep-background", action="store_true", help="a whole scene / mood picture, never for 3D")
    p_concept.add_argument("--no-style", action="store_true", help="don't add the art direction's style")
    p_model = sub.add_parser("model", help="image-to-3D from the concept the kid picked (≈15 credits)")
    p_model.add_argument("--slot", default="")
    p_model.add_argument("--id", default="")
    p_model.add_argument("--retry", default="", help="why a concept that already went to 3D must go again")
    p_model.add_argument("--quality", choices=["normal", "high"], default="normal",
                         help="normal: meshy-t2 smart topology, 15 credits; high: meshy-6, 30 credits")
    p_text = sub.add_parser("text3d", help="text-to-3D with no concept picture (≈30 credits)")
    p_text.add_argument("--slot", required=True)
    p_text.add_argument("--prompt", required=True)
    p_text.add_argument("--name", default="")
    p_text.add_argument("--no-style", action="store_true")
    sub.add_parser("balance", help="credits left (free)")
    args = parser.parse_args(argv)
    paths = Paths(args.root)

    token = os.environ.get("MESHY_API_KEY", "")
    if not token:
        print("MESHY_API_KEY is not set. To turn on Meshy:\n"
              "  1. a grown-up makes a Meshy Pro account and an API key (app.meshy.ai → API)\n"
              "  2. put  export MESHY_API_KEY=msy_...  in ~/.config/game-foundation/keys.env (never in the repo)\n"
              "  3. make doctor   (should say: meshy key: set)\n"
              "To practise without a key: make assets-mock, then MESHY_BASE_URL=http://127.0.0.1:8799 MESHY_API_KEY=mock",
              file=sys.stderr)
        return 3
    meshy = Meshy(Http(args.base_url or MESHY_URL, token), args.poll_interval, args.timeout)
    if args.base_url:
        print(f"(using the mock Meshy at {args.base_url}: nothing is spent)")
    try:
        if args.command == "concept":
            return run_concept(args, paths, meshy)
        if args.command == "model":
            return run_model(args, paths, meshy)
        if args.command == "text3d":
            return run_text3d(args, paths, meshy)
        balance = meshy.balance()
        print(f"Meshy balance: {balance if balance != '' else 'unknown (the key may be wrong)'} credits; "
              f"{review.ledger_total(paths.ledger)} spent by this game so far")
        return 0
    except (ProviderError, ReviewError, OSError) as error:
        print(f"meshy: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
