#!/usr/bin/env python3
"""A pretend ElevenLabs server: the same few endpoints, real (synthesised) audio back, no account, no credits.

    python3 tools/audio/mock_elevenlabs.py --port 8099            # or: make audio-mock
    make sounds BASE_URL=http://127.0.0.1:8099                    # then any paid target, for free

Endpoints (the ones tools/audio uses):
    POST /v1/sound-generation           -> mp3 of shaped noise, as long as asked (0.5-30 s, else 422)
    POST /v1/text-to-speech/<voice id>  -> mp3 with one tone burst per word; header character-cost = len(text)
    GET  /v2/voices                     -> a few of ElevenLabs' public premade voices
    GET  /v1/user/subscription          -> a balance that goes down as you "spend"
Every request needs an xi-api-key header (any value), like the real one. The tests run it in a thread (start()).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

## A few of ElevenLabs' premade voices (public ids from their docs), so voice-list has something to show.
VOICES = [
    {"voice_id": "JBFqnCBsd6RMkjVDRZzb", "name": "George", "category": "premade",
     "labels": {"accent": "british", "age": "middle aged", "gender": "male", "use_case": "narration"},
     "description": "Warm, captivating storyteller."},
    {"voice_id": "cgSgspJ2msm6clMCkdW9", "name": "Jessica", "category": "premade",
     "labels": {"accent": "american", "age": "young", "gender": "female", "use_case": "conversational"},
     "description": "Playful, bright, warm."},
    {"voice_id": "IKne3meq5aSn9XLyUdCD", "name": "Charlie", "category": "premade",
     "labels": {"accent": "australian", "age": "young", "gender": "male", "use_case": "conversational"},
     "description": "Deep, confident, energetic."},
    {"voice_id": "XrExE9yKIg1WjnnlVkGX", "name": "Matilda", "category": "premade",
     "labels": {"accent": "american", "age": "middle aged", "gender": "female", "use_case": "narration"},
     "description": "Knowledgable, professional."},
    {"voice_id": "N2lVS1w4EtoT3dr4eOWO", "name": "Callum", "category": "premade",
     "labels": {"accent": "transatlantic", "age": "middle aged", "gender": "male", "use_case": "characters"},
     "description": "Husky trickster, a gravelly pirate-ish character voice."},
]


def _mp3(lavfi: str, seconds: float) -> bytes:
    result = subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", lavfi, "-t", "%.3f" % seconds,
                             "-ac", "2", "-ar", "44100", "-c:a", "libmp3lame", "-b:a", "96k", "-f", "mp3", "pipe:1"],
                            capture_output=True, check=True)
    return result.stdout


def sound_audio(prompt: str, seconds: float, loop: bool, take: int) -> bytes:
    """Pink noise shaped like a hit (or steady, for a loop), a little different for every prompt and take."""
    seed = int(hashlib.sha1(("%s/%d" % (prompt, take)).encode()).hexdigest()[:6], 16)
    shape = "1" if loop else "exp(-5*t/%.3f)" % seconds
    lead = "" if loop else "*gte(t,0.03)"  # real effects rarely start on sample zero
    return _mp3("anoisesrc=d=%.3f:c=pink:a=0.5:seed=%d,volume='%s%s':eval=frame" % (seconds, seed, shape, lead), seconds)


def speech_audio(text: str) -> bytes:
    """One 180-390 Hz burst per word, with a pause after punctuation: real speech-shaped timing, trivially synthetic."""
    clock, terms = 0.2, []
    for number, word in enumerate(re.findall(r"\S+", text)):
        length = max(0.12, 0.055 * len(re.sub(r"[^A-Za-z']", "", word)))
        terms.append("between(t,%.3f,%.3f)*sin(2*PI*%d*t)" % (clock, clock + length, 180 + 35 * (number % 6)))
        clock += length + (0.3 if re.search(r"[,.!?;]$", word) else 0.13)
    expression = "0.4*(%s)" % ("+".join(terms) or "0")
    return _mp3("aevalsrc='%s':s=22050:d=%.3f" % (expression, clock + 0.3), clock + 0.3)


class State:
    def __init__(self, credits: int = 100000):
        self.limit = credits
        self.used = 0
        self.calls: list[dict] = []
        self.fail_next: list[int] = []  # statuses the next POSTs get before it behaves (tests the retries)
        self.lock = threading.Lock()


def make_handler(state: State):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):  # quiet
            pass

        def _send(self, status: int, body: bytes, kind: str = "application/json", headers: dict | None = None):
            self.send_response(status)
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(body)))
            for key, value in (headers or {}).items():
                self.send_header(key, str(value))
            self.end_headers()
            self.wfile.write(body)

        def _json(self, status: int, data):
            self._send(status, json.dumps(data).encode())

        def _guard(self, post: bool = False) -> bool:
            if not self.headers.get("xi-api-key"):
                self._json(401, {"detail": {"status": "missing_api_key", "message": "no xi-api-key"}})
                return False
            with state.lock:
                if post and state.fail_next:
                    self._json(state.fail_next.pop(0), {"detail": "mock failure"})
                    return False
            return True

        def do_GET(self):
            if not self._guard():
                return
            path = urlparse(self.path).path
            with state.lock:
                state.calls.append({"method": "GET", "path": path})
            if path == "/v1/user/subscription":
                return self._json(200, {"character_count": state.used, "character_limit": state.limit, "tier": "mock"})
            if path in ("/v2/voices", "/v1/voices"):
                return self._json(200, {"voices": VOICES, "has_more": False, "next_page_token": None})
            self._json(404, {"detail": "no such endpoint in the mock: %s" % path})

        def do_POST(self):
            if not self._guard(post=True):
                return
            path = urlparse(self.path).path
            length = int(self.headers.get("Content-Length", 0))
            try:
                body = json.loads(self.rfile.read(length) or b"{}")
            except ValueError:
                return self._json(400, {"detail": "body is not JSON"})
            with state.lock:
                state.calls.append({"method": "POST", "path": path, "body": body})
                take = len(state.calls)
            if path == "/v1/sound-generation":
                seconds = float(body.get("duration_seconds") or 2.0)
                if not 0.5 <= seconds <= 30 or not body.get("text"):
                    return self._json(422, {"detail": "duration_seconds must be 0.5-30 and text is required"})
                with state.lock:
                    state.used += int(round(seconds * 10))
                return self._send(200, sound_audio(body["text"], seconds, bool(body.get("loop")), take), "audio/mpeg")
            match = re.fullmatch(r"/v1/text-to-speech/([A-Za-z0-9]+)", path)
            if match:
                if match.group(1) not in {v["voice_id"] for v in VOICES}:
                    return self._json(404, {"detail": {"status": "voice_not_found", "message": "unknown voice"}})
                text = str(body.get("text", ""))
                if not text.strip():
                    return self._json(422, {"detail": "text is required"})
                with state.lock:
                    state.used += len(text)
                return self._send(200, speech_audio(text), "audio/mpeg", {"character-cost": len(text)})
            self._json(404, {"detail": "no such endpoint in the mock: %s" % path})

    return Handler


def start(port: int = 0, credits: int = 100000):
    """Run the mock in a background thread: returns (server, url, state). server.shutdown() stops it."""
    state = State(credits)
    server = ThreadingHTTPServer(("127.0.0.1", port), make_handler(state))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, "http://127.0.0.1:%d" % server.server_address[1], state


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=8099)
    args = parser.parse_args(argv)
    state = State()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(state))
    print("mock ElevenLabs on http://127.0.0.1:%d (Ctrl+C stops). Use BASE_URL=http://127.0.0.1:%d with any audio "
          "target." % (args.port, args.port))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
