#!/usr/bin/env python3
"""A pretend Meshy server, so the whole model pipeline can be tested with no network, no key and no credits.

    make assets-mock                                   # serves http://127.0.0.1:8799 until Ctrl+C
    MESHY_BASE_URL=http://127.0.0.1:8799 MESHY_API_KEY=mock make art-concept SLOT=prop_rock PROMPT="a lava rock"

Follows Meshy's request/response shapes (docs.meshy.ai, as verified with a live key in Tank Squad). Tasks move
one status per poll (PENDING → IN_PROGRESS → SUCCEEDED), report `consumed_credits` at Meshy's prices, and serve
a textured box GLB (20 × 9 × 30 units, facing +Z, like a real download: the wrong size and the glTF facing) or
a 64 px concept PNG. Scripted failures, for tests:
    API key "bad-key" → 401          API key "broke" → 402 (out of credits)
    prompt containing "FAIL" → the task FAILS (0 credits)     prompt containing "RATELIMIT" → one 429 first
Standard library only.
"""

import itertools
import json
import re
import struct
import sys
import threading
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# What each request costs on Meshy (docs.meshy.ai/en/api/pricing); the mock charges the same.
CREDITS = {"text-to-image": 9, "image-to-image": 9, "image-to-3d": 15, "image-to-3d meshy-6": 30,
           "text-to-3d-preview": 20, "text-to-3d-refine": 10}
FAMILIES = ("text-to-image", "image-to-image", "image-to-3d", "text-to-3d")


# ---- tiny file makers (also used by the tests) ------------------------------------------------------------------

def png(width: int = 64, height: int = 64, color=(200, 90, 40)) -> bytes:
    """An RGB PNG: a coloured square with a lighter checker, so it's visibly an image on a review page."""
    rows = bytearray()
    light = tuple(min(255, c + 50) for c in color)
    for y in range(height):
        rows.append(0)
        for x in range(width):
            rows.extend(light if ((x * 8 // width) + (y * 8 // height)) % 2 else color)
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(bytes(rows), 6)) + chunk(b"IEND", b"")


def box_glb(size=(20.0, 9.0, 30.0), texture_px: int = 1024) -> bytes:
    """A valid glTF 2.0 binary box with UVs and an embedded base-colour texture (0 = untextured)."""
    sx, sy, sz = (s / 2.0 for s in size)
    faces = [  # 4 corners per face so each face gets its own UVs and normal
        ((0, 0, 1), [(-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)]),
        ((0, 0, -1), [(sx, -sy, -sz), (-sx, -sy, -sz), (-sx, sy, -sz), (sx, sy, -sz)]),
        ((1, 0, 0), [(sx, -sy, sz), (sx, -sy, -sz), (sx, sy, -sz), (sx, sy, sz)]),
        ((-1, 0, 0), [(-sx, -sy, -sz), (-sx, -sy, sz), (-sx, sy, sz), (-sx, sy, -sz)]),
        ((0, 1, 0), [(-sx, sy, sz), (sx, sy, sz), (sx, sy, -sz), (-sx, sy, -sz)]),
        ((0, -1, 0), [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, -sy, sz), (-sx, -sy, sz)]),
    ]
    positions, normals, uvs, indices = b"", b"", b"", b""
    for n, (normal, corners) in enumerate(faces):
        for corner, uv in zip(corners, [(0, 1), (1, 1), (1, 0), (0, 0)]):
            positions += struct.pack("<3f", *corner)
            normals += struct.pack("<3f", *normal)
            uvs += struct.pack("<2f", *uv)
        base = n * 4
        indices += struct.pack("<6H", base, base + 1, base + 2, base, base + 2, base + 3)
    views = [positions, normals, uvs, indices]
    image = png(texture_px, texture_px) if texture_px else b""
    if image:
        views.append(image)
    binary, offsets = b"", []
    for data in views:
        offsets.append(len(binary))
        binary += data + b"\x00" * (-len(data) % 4)
    material = {"name": "Main", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0}}
    if image:
        material["pbrMetallicRoughness"]["baseColorTexture"] = {"index": 0}
    gltf = {
        "asset": {"version": "2.0", "generator": "game-foundation mock_provider"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "MockModel", "mesh": 0}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0}]}],
        "materials": [material],
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": [{"buffer": 0, "byteOffset": offsets[i], "byteLength": len(views[i])} for i in range(len(views))],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 24, "type": "VEC3", "min": [-sx, -sy, -sz], "max": [sx, sy, sz]},
            {"bufferView": 1, "componentType": 5126, "count": 24, "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": 24, "type": "VEC2"},
            {"bufferView": 3, "componentType": 5123, "count": 36, "type": "SCALAR"},
        ],
    }
    if image:
        gltf["images"] = [{"bufferView": 4, "mimeType": "image/png"}]
        gltf["textures"] = [{"source": 0}]
    text = json.dumps(gltf, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    chunks = struct.pack("<I4s", len(text), b"JSON") + text + struct.pack("<I4s", len(binary), b"BIN\x00") + binary
    return struct.pack("<4sII", b"glTF", 2, 12 + len(chunks)) + chunks


# ---- the server ---------------------------------------------------------------------------------------------------

class MockState:
    def __init__(self):
        self.tasks = {}
        self.ids = itertools.count(1)
        self.rate_limited = set()
        self.requests = []  # (method, path, body): what the client sent, for assertions
        self.lock = threading.Lock()
        self._glb = None

    def glb(self) -> bytes:
        if self._glb is None:
            self._glb = box_glb()
        return self._glb


class Handler(BaseHTTPRequestHandler):
    state: MockState = None  # set by serve()

    def log_message(self, *args):
        pass

    def _send(self, code, payload=None, content_type="application/json", headers=None):
        body = payload if isinstance(payload, bytes) else json.dumps(payload or {}).encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _auth(self) -> bool:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer ") or header == "Bearer bad-key":
            self._send(401, {"message": "Invalid API key"})
            return False
        if header == "Bearer broke":
            self._send(402, {"message": "Insufficient credits"})
            return False
        return True

    def do_GET(self):
        if self.path.startswith("/files/"):
            name = self.path.rsplit("/", 1)[1]
            if name.endswith(".glb"):
                return self._send(200, self.state.glb(), "model/gltf-binary")
            return self._send(200, png(), "image/png")
        if not self._auth():
            return
        self.state.requests.append(("GET", self.path, None))
        if self.path == "/openapi/v1/balance":
            return self._send(200, {"balance": 1000})
        match = re.fullmatch(r"/openapi/v[12]/(%s)/([\w-]+)" % "|".join(FAMILIES), self.path)
        with self.state.lock:
            task = self.state.tasks.get(match.group(2)) if match else None
            if task is None:
                return self._send(404, {"message": "Task not found"})
            self._advance(task)
            view = dict(task["view"])
        self._send(200, view)

    def do_POST(self):
        if not self._auth():
            return
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(length) or b"{}") if length else {}
        self.state.requests.append(("POST", self.path, body))
        prompt = str(body.get("prompt", "") or body.get("texture_prompt", "") or "")
        if "RATELIMIT" in prompt and prompt not in self.state.rate_limited:
            self.state.rate_limited.add(prompt)
            return self._send(429, {"message": "RateLimitExceeded"}, headers={"Retry-After": "0"})
        match = re.fullmatch(r"/openapi/v[12]/(%s)" % "|".join(FAMILIES), self.path)
        if not match:
            return self._send(404, {"message": "no such endpoint"})
        family = match.group(1)
        error = self._validate(family, body, prompt)
        if error:
            return self._send(400, {"message": error})
        if family == "text-to-3d" and body.get("mode") == "refine":
            prompt = self.state.tasks[body["preview_task_id"]]["prompt"]
        with self.state.lock:
            task_id = f"mock-{next(self.state.ids):04d}"
            kind = f"text-to-3d-{body.get('mode')}" if family == "text-to-3d" else family
            price_key = "image-to-3d meshy-6" if family == "image-to-3d" and body.get("ai_model") in ("meshy-6", "meshy-7", "latest") else kind
            self.state.tasks[task_id] = {"prompt": prompt, "polls": 0, "pbr": body.get("enable_pbr"), "kind": kind,
                                         "credits": CREDITS.get(price_key, 0), "view": {
                "id": task_id, "type": kind, "status": "PENDING", "progress": 0, "prompt": prompt,
                "model_urls": {}, "texture_urls": [], "task_error": None, "created_at": 1}}
        self._send(200, {"result": task_id})

    def _validate(self, family: str, body: dict, prompt: str) -> str:
        tasks = self.state.tasks
        if family in ("text-to-image", "image-to-image") and (not prompt or not body.get("ai_model")):
            return "ai_model and prompt are required"
        if family == "image-to-image" and not 1 <= len(body.get("reference_image_urls") or []) <= 5:
            return "reference_image_urls must have 1-5 images"
        if family == "image-to-3d":
            source = tasks.get(body.get("input_task_id", ""))
            if not body.get("image_url") and (source is None or source["view"]["status"] != "SUCCEEDED"):
                return "image_url or a SUCCEEDED input_task_id is required"
            if body.get("model_type") == "smart-topology" and not 100 <= body.get("target_polycount", 4000) <= 15000:
                return "target_polycount must be 100-15000 for smart-topology"
        if family == "text-to-3d":
            mode = body.get("mode")
            if mode == "preview" and not prompt:
                return "prompt is required"
            if mode == "refine":
                preview = tasks.get(body.get("preview_task_id"))
                if preview is None or preview["view"]["status"] != "SUCCEEDED":
                    return "preview_task_id must be a SUCCEEDED preview task"
            elif mode != "preview":
                return "mode must be preview or refine"
        return ""

    def _advance(self, task: dict):
        """One status step per poll; the second poll finishes (or fails, for FAIL prompts)."""
        task["polls"] += 1
        view = task["view"]
        if view["status"] in ("SUCCEEDED", "FAILED"):
            return
        base = f"http://{self.headers.get('Host')}"
        if task["polls"] == 1:
            view.update(status="IN_PROGRESS", progress=50)
        elif "FAIL" in task["prompt"]:
            view.update(status="FAILED", progress=0, consumed_credits=0, task_error={"message": "mock generation failed"})
        elif task["kind"] in ("text-to-image", "image-to-image"):
            view.update(status="SUCCEEDED", progress=100, consumed_credits=task["credits"],
                        image_urls=[f"{base}/files/{view['id']}_concept.png"])
        else:
            view.update(status="SUCCEEDED", progress=100, consumed_credits=task["credits"],
                        model_urls={"glb": f"{base}/files/{view['id']}.glb"})
            if task["pbr"] and task["kind"] != "text-to-3d-preview":
                view["texture_urls"] = [{key: f"{base}/files/{view['id']}_{key}.png"
                                         for key in ("base_color", "metallic", "normal", "roughness", "emission")}]


def serve(port: int = 0):
    """Starts the mock on a background thread. Returns (server, state); server.server_address[1] is the port."""
    state = MockState()
    handler = type("BoundHandler", (Handler,), {"state": state})
    server = ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, state


if __name__ == "__main__":
    server, _ = serve(int(sys.argv[1]) if len(sys.argv) > 1 else 8799)
    print(f"mock Meshy on http://127.0.0.1:{server.server_address[1]}  (Ctrl+C to stop)\n"
          f"  in another terminal: export MESHY_BASE_URL=http://127.0.0.1:{server.server_address[1]} MESHY_API_KEY=mock")
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        server.shutdown()
