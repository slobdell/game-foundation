#!/usr/bin/env python3
"""Make a demo choices page to try the whole loop: placeholder pictures and sounds, then the spec.

    make choices-demo      # = this, then choices_page.py build/pages/demo.spec.json

Writes build/pages/demo_media/*.png + *.wav (drawn and synthesised here, standard library only) and
build/pages/demo.spec.json, which uses every question kind.
"""

from __future__ import annotations

import json
import math
import struct
import sys
import wave
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build" / "pages"
MEDIA = OUT / "demo_media"


def write_png(path: Path, w: int, h: int, pixel) -> None:
    """pixel(x, y) -> (r, g, b). A plain 8-bit RGB PNG."""
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.extend(pixel(x, y))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))


def hero(body_rgb):
    """A friendly blob hero with eyes, standing on grass under a sky."""
    w, h = 480, 360

    def px(x, y):
        cx, cy, r = w / 2, h * 0.55, 95
        dx, dy = x - cx, (y - cy) * 1.1
        d = math.hypot(dx, dy)
        for ex in (-35, 35):  # eyes
            e = math.hypot(x - (cx + ex), y - (cy - 25))
            if e < 9:
                return (20, 22, 34)
            if e < 22:
                return (250, 250, 250)
        if d < r:
            shade = 0.75 + 0.25 * (1 - (dy + r) / (2 * r))
            return tuple(min(255, int(c * shade)) for c in body_rgb)
        if y > h * 0.78:
            return (86, 160, 72) if (x // 12 + y // 12) % 2 else (78, 148, 66)
        t = y / h
        return (int(120 + 90 * t), int(180 + 50 * t), 245)
    return w, h, px


def tone(path: Path, notes, rate=22050) -> None:
    """notes: [(freq start, freq end, seconds)] — a little chirp per note, 16-bit mono."""
    frames = bytearray()
    for f0, f1, dur in notes:
        n = int(rate * dur)
        phase = 0.0
        for i in range(n):
            t = i / n
            f = f0 + (f1 - f0) * t
            phase += 2 * math.pi * f / rate
            env = min(1.0, i / 200) * (1 - t) ** 1.5
            frames.extend(struct.pack("<h", int(12000 * env * math.sin(phase))))
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        wf.writeframes(bytes(frames))


def main() -> int:
    MEDIA.mkdir(parents=True, exist_ok=True)
    colours = {"red": (230, 70, 60), "teal": (30, 170, 160), "gold": (240, 180, 40)}
    for name, rgb in colours.items():
        write_png(MEDIA / f"hero_{name}.png", *hero(rgb))
    tone(MEDIA / "jump_boing.wav", [(220, 660, 0.35)])
    tone(MEDIA / "jump_zip.wav", [(900, 1800, 0.12)])
    tone(MEDIA / "jump_bloop.wav", [(500, 300, 0.15), (300, 600, 0.2)])
    tone(MEDIA / "theme_tune.wav", [(523, 523, 0.25), (659, 659, 0.25), (784, 784, 0.25), (1046, 1046, 0.5)])
    rel = lambda p: str(p.relative_to(ROOT))  # noqa: E731
    spec = {
        "name": "demo",
        "title": "Moon Muncher Picks",
        "intro": "This is a demo page. Tap the one you like best in each scene, and tell me why if you want to.",
        "questions": [
            {"id": "hero_colour", "kind": "pick_one", "prompt": "What colour is your hero?",
             "options": [
                 {"id": "red", "label": "Rocket red", "image": rel(MEDIA / "hero_red.png"), "note": "Easy to spot"},
                 {"id": "teal", "label": "Sea teal", "image": rel(MEDIA / "hero_teal.png")},
                 {"id": "gold", "label": "Sunny gold", "image": rel(MEDIA / "hero_gold.png"),
                  "note": "Shines at night"}]},
            {"id": "jump_sound", "kind": "pick_one", "prompt": "Which sound should the jump make?",
             "options": [
                 {"id": "boing", "label": "Boing", "audio": rel(MEDIA / "jump_boing.wav")},
                 {"id": "zip", "label": "Zip", "audio": rel(MEDIA / "jump_zip.wav")},
                 {"id": "bloop", "label": "Bloop", "audio": rel(MEDIA / "jump_bloop.wav")}]},
            {"id": "powerups", "kind": "pick_many", "prompt": "Which power-ups go in the first level?",
             "options": [
                 {"id": "double_jump", "label": "Double jump", "text": "Jump again in mid-air."},
                 {"id": "magnet", "label": "Cheese magnet", "text": "Moon cheese flies to you."},
                 {"id": "shield", "label": "Bubble shield", "text": "One free hit."},
                 {"id": "speed", "label": "Turbo boots", "text": "Run twice as fast for 10 seconds."}]},
            {"id": "theme_tune", "kind": "keep_redo", "prompt": "Keep this title tune, or should I make a new one?",
             "options": [{"id": "tune_v1", "label": "Title tune, try 1", "audio": rel(MEDIA / "theme_tune.wav"),
                          "note": "Four notes going up"}]},
        ],
    }
    (OUT / "demo.spec.json").write_text(json.dumps(spec, indent=2) + "\n")
    print(f">> demo spec: {rel(OUT / 'demo.spec.json')} ({len(list(MEDIA.iterdir()))} placeholder media files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
