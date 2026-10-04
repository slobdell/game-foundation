"""Shared pieces of the audio tools: paths, ffmpeg helpers, loudness, the ElevenLabs client, the ledger.

Standard library + ffmpeg only (numpy is never required). Every other tool in tools/audio imports this.
_agents/audio.md explains the three pipelines (sounds, voices, music) that use it.
"""

from __future__ import annotations

import datetime
import hashlib
import json
import math
import os
import re
import struct
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import wave
from pathlib import Path

## The repo. AUDIO_REPO_ROOT points every path at another folder: the tests use it to run the real tools on a
## throwaway copy of the repo's layout, so they can never touch the real assets.
ROOT = Path(os.environ.get("AUDIO_REPO_ROOT", "") or Path(__file__).resolve().parents[2]).resolve()
SOUNDS_JSON = ROOT / "assets" / "audio" / "sounds.json"
SFX_DIR = ROOT / "assets" / "audio" / "sfx"
MADE_JSON = ROOT / "assets" / "audio" / "made.json"
LEDGER = ROOT / "assets" / "audio" / "elevenlabs_ledger.md"
VOICES_JSON = ROOT / "data" / "voices.json"
DIALOGUE_DIR = ROOT / "data" / "dialogue"
VOICE_DIR = ROOT / "assets" / "voices"
MUSIC_DIR = ROOT / "assets" / "music"
MUSIC_JSON = MUSIC_DIR / "music.json"
BUILD_AUDIO = ROOT / "build" / "audio"
CANDIDATES = BUILD_AUDIO / "candidates"
PAGES = ROOT / "build" / "pages"
DECISIONS = ROOT / "data" / "decisions"

REAL_BASE_URL = "https://api.elevenlabs.io"
KEY_ENV = "ELEVENLABS_API_KEY"
BASE_URL_ENV = "ELEVENLABS_BASE_URL"
KEY_PREFIX = "sk_"
SFX_MODEL = "eleven_text_to_sound_v2"
TTS_MODEL = "eleven_multilingual_v2"
OUTPUT_FORMAT = "mp3_44100_128"
## Planning numbers only; the ledger records the account's real balance before and after whenever the key may read it.
## Sound effects: measured on Tank Squad (2026-09/10, ~60 runs): 10 credits per second of generated audio.
## Speech: ElevenLabs bills per character (multilingual v2: 1 credit; flash/turbo: 0.5).
SFX_CREDITS_PER_SECOND = 10.0
TTS_CREDITS_PER_CHAR = {"eleven_multilingual_v2": 1.0, "eleven_v3": 1.0, "eleven_flash_v2_5": 0.5,
                        "eleven_turbo_v2_5": 0.5}
REQUEST_TIMEOUT_S = 180.0
RETRY_DELAYS_S = (2.0, 6.0, 15.0)

## Sound effects: every shipped one-shot is levelled so its loudest 400 ms sits at SFX_LEVEL_DB (RMS, dBFS) with its
## peak under SFX_PEAK_DB. Then a click and a whoosh start equally loud; `volume_db` in sounds.json is the mix.
SFX_LEVEL_DB = -16.0
SFX_PEAK_DB = -1.0
## Voices and music are levelled by integrated loudness (EBU R128). Voices sit 2 LU above the music, and the Music bus
## is a further 6 dB down (default_bus_layout.tres), so speech is always clear.
VOICE_LUFS = -16.0
MUSIC_LUFS = -18.0
PEAK_CEILING_DB = -1.0

ID_RE = re.compile(r"^[a-z0-9][a-z0-9_]*$")
VARIANT_RE = re.compile(r"_v\d+$")


# ---- small helpers ---------------------------------------------------------------------------------------------------

def rel(path: Path) -> str:
    """A repo-relative path string (what specs, ledgers and made.json store)."""
    try:
        return str(Path(path).resolve().relative_to(ROOT))
    except ValueError:
        return str(path)


def fingerprint(*parts) -> str:
    """A short hash of everything that shaped a file: change any of it and the file is stale."""
    return hashlib.sha1(json.dumps(parts, sort_keys=True).encode()).hexdigest()[:10]


def read_json(path: Path, default):
    path = Path(path)
    if not path.exists():
        return default
    return json.loads(path.read_text())


def write_json(path: Path, data, indent: int = 2) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=indent, ensure_ascii=False) + "\n")


def now_iso() -> str:
    return datetime.datetime.now().replace(microsecond=0).isoformat()


# ---- made.json: where every shipped sound / voice file came from -----------------------------------------------------

def load_made(path: Path = MADE_JSON) -> dict:
    return read_json(path, {})


def record_made(entries: dict, path: Path = MADE_JSON) -> None:
    """entries: {repo path: {"by": "placeholder" | "elevenlabs" | ..., "fp": fingerprint, ...}}"""
    made = load_made(path)
    made.update(entries)
    for key in [k for k in made if not (ROOT / k).exists()]:
        del made[key]
    write_json(path, dict(sorted(made.items())))


def forget_made(paths: list, path: Path = MADE_JSON) -> None:
    made = load_made(path)
    for p in paths:
        made.pop(rel(p), None)
    write_json(path, dict(sorted(made.items())))


# ---- ffmpeg ------------------------------------------------------------------------------------------------------------

def ffmpeg(*args: str, input_bytes: bytes | None = None) -> bytes:
    result = subprocess.run(["ffmpeg", "-v", "error", "-y", *args], input=input_bytes, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError("ffmpeg failed: %s" % result.stderr.decode(errors="replace").strip()[-400:])
    return result.stdout


def duration(path: Path) -> float:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1",
                          str(path)], capture_output=True, text=True)
    try:
        return float(out.stdout.strip())
    except ValueError:
        return 0.0


def decode(path: Path, rate: int = 44100, channels: int = 1) -> list[float]:
    """The file as float samples (interleaved when channels > 1)."""
    raw = ffmpeg("-i", str(path), "-ac", str(channels), "-ar", str(rate), "-f", "s16le", "-c:a", "pcm_s16le", "pipe:1")
    count = len(raw) // 2
    return [s / 32768.0 for s in struct.unpack("<%dh" % count, raw[:count * 2])]


def write_wav(path: Path, samples: list[float], rate: int, channels: int = 1) -> None:
    with wave.open(str(path), "wb") as out:
        out.setnchannels(channels)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(struct.pack("<%dh" % len(samples),
                                    *(int(max(-1.0, min(1.0, s)) * 32767) for s in samples)))


def peak_db(samples: list[float]) -> float:
    peak = max((abs(s) for s in samples), default=0.0)
    return 20 * math.log10(peak) if peak > 0 else -120.0


def loudest_window_db(samples: list[float], rate: int, window_s: float = 0.4) -> float:
    """RMS of the loudest `window_s` stretch, dBFS: a short sound's loudness (R128 gating ignores sub-400 ms clips)."""
    n = max(1, min(len(samples), int(rate * window_s)))
    if not samples:
        return -120.0
    squares = [s * s for s in samples]
    total = sum(squares[:n])
    best = total
    for i in range(n, len(squares)):
        total += squares[i] - squares[i - n]
        if total > best:
            best = total
    rms = math.sqrt(max(best, 0.0) / n)
    return 20 * math.log10(rms) if rms > 0 else -120.0


def measure_lufs(path: Path) -> tuple[float, float]:
    """(integrated LUFS, true peak dBTP) by ffmpeg's ebur128. Very short or silent files read about -70."""
    result = subprocess.run(["ffmpeg", "-v", "info", "-nostats", "-i", str(path), "-af", "ebur128=peak=true",
                             "-f", "null", "-"], capture_output=True, text=True)
    text = result.stderr
    summary = text[text.rfind("Summary:"):] if "Summary:" in text else text
    lufs = re.search(r"I:\s*(-?[\d.]+|-inf)\s*LUFS", summary)
    peak = re.search(r"Peak:\s*(-?[\d.]+|-inf)\s*dBFS", summary)
    as_float = lambda m: -120.0 if (m is None or "inf" in m.group(1)) else float(m.group(1))  # noqa: E731
    return as_float(lufs), as_float(peak)


def level_sound(source: Path, out: Path, loop: bool = False, trim: bool = True, stereo: bool | None = None) -> dict:
    """A sound-effect master -> a shipped Ogg: silence trimmed off the front (not for loops), levelled to SFX_LEVEL_DB
    on its loudest 400 ms with the peak held under SFX_PEAK_DB, a 10 ms fade at the end (no click), Ogg Vorbis.
    One-shots are mono (3D sounds are positioned anyway, and it halves the size); loops stay stereo."""
    stereo = loop if stereo is None else stereo
    rate = 44100
    with tempfile.TemporaryDirectory() as scratch:
        wav = Path(scratch) / "in.wav"
        filters = ["silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.005"] if (trim and not loop) else []
        ffmpeg("-i", str(source), *(["-af", ",".join(filters)] if filters else []), "-ac", "1", "-ar", str(rate),
               "-c:a", "pcm_s16le", str(wav))
        samples = decode(wav, rate)
        if not samples or peak_db(samples) < -80:
            raise RuntimeError("%s is silent" % source.name)
        level = loudest_window_db(samples, rate)
        gain = SFX_LEVEL_DB - level
        gain = min(gain, SFX_PEAK_DB - 0.3 - peak_db(samples))  # never over the ceiling
        length = len(samples) / rate
        af = ["volume=%.2fdB" % gain]
        if not loop:
            af.append("afade=t=out:st=%.3f:d=0.01" % max(0.0, length - 0.01))
        out.parent.mkdir(parents=True, exist_ok=True)
        # The Vorbis encoder can overshoot the peak by a dB or two on noisy material; measure and re-encode lower.
        for _ in range(4):
            ffmpeg("-i", str(source), *(["-af", ",".join(filters + af)]), "-ac", "2" if stereo else "1",
                   "-ar", str(rate), "-c:a", "libvorbis", "-q:a", "4", str(out))
            final = decode(out, rate, 2 if stereo else 1)
            over = peak_db(final) - (SFX_PEAK_DB - 0.1)
            if over <= 0:
                break
            gain -= over + 0.3
            af[0] = "volume=%.2fdB" % gain
    final = decode(out, rate)
    return {"level_db": round(loudest_window_db(final, rate), 1), "peak_db": round(peak_db(final), 1),
            "seconds": round(len(final) / rate, 2)}


def level_speech(source: Path, out: Path) -> dict:
    """A voice master -> a shipped Ogg: silence trimmed off both ends, VOICE_LUFS, peak under the ceiling, mono."""
    trim = ("silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.02,areverse,"
            "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.08,areverse")
    with tempfile.TemporaryDirectory() as scratch:
        wav = Path(scratch) / "trimmed.wav"
        ffmpeg("-i", str(source), "-af", trim, "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", str(wav))
        lufs, _ = measure_lufs(wav)
        samples = decode(wav)
        if lufs < -60:  # too short for R128 gating: fall back to the loudest-window measure
            lufs = loudest_window_db(samples, 44100) - 3.0
        gain = min(VOICE_LUFS - lufs, PEAK_CEILING_DB - 0.5 - peak_db(samples))
        out.parent.mkdir(parents=True, exist_ok=True)
        for _ in range(4):
            ffmpeg("-i", str(wav), "-af", "volume=%.2fdB" % gain, "-ac", "1", "-c:a", "libvorbis", "-q:a", "3", str(out))
            over = peak_db(decode(out)) - (PEAK_CEILING_DB - 0.1)
            if over <= 0:
                break
            gain -= over + 0.3
    lufs, peak = measure_lufs(out)
    return {"lufs": round(lufs, 1), "peak_db": round(peak, 1), "seconds": round(duration(out), 2)}


# ---- Godot import settings ---------------------------------------------------------------------------------------------

def set_import_loop(ogg: Path, loop: bool, loop_offset: float = 0.0) -> None:
    """Write (or edit) the Ogg's .import file so Godot imports it looping. The runtime sets `loop` on music too,
    but the import setting makes the editor's preview loop and keeps the loop offset with the file."""
    path = Path(str(ogg) + ".import")
    params = {"loop": "true" if loop else "false", "loop_offset": repr(float(loop_offset))}
    if not path.exists():
        path.write_text('[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n\n[params]\n\n' +
                        "".join("%s=%s\n" % kv for kv in params.items()) + "bpm=0\nbeat_count=0\nbar_beats=4\n")
        return
    text = path.read_text()
    if "[params]" not in text:
        text += "\n[params]\n\n"
    for key, value in params.items():
        if re.search(r"^%s=.*$" % key, text, re.M):
            text = re.sub(r"^%s=.*$" % key, "%s=%s" % (key, value), text, flags=re.M)
        else:
            text = text.replace("[params]\n\n", "[params]\n\n%s=%s\n" % (key, value), 1)
    path.write_text(text)


# ---- ElevenLabs --------------------------------------------------------------------------------------------------------

class ElevenLabsError(RuntimeError):
    def __init__(self, status: int, message: str):
        super().__init__("ElevenLabs said %s: %s" % (status, message))
        self.status = status


def base_url(explicit: str = "") -> str:
    return (explicit or os.environ.get(BASE_URL_ENV, "") or REAL_BASE_URL).rstrip("/")


def is_real(url: str) -> bool:
    return url.rstrip("/") == REAL_BASE_URL


def ledger_path(url: str) -> Path:
    """Real runs append to the committed ledger; a mock run writes to build/ so it never looks like spending."""
    return LEDGER if is_real(url) else BUILD_AUDIO / "mock_ledger.md"


class Client:
    """The few ElevenLabs REST calls we use, over urllib (no SDK). `base_url` points it at the mock for tests."""

    def __init__(self, url: str = "", api_key: str | None = None, delays=RETRY_DELAYS_S):
        self.url = base_url(url)
        key = (api_key if api_key is not None else os.environ.get(KEY_ENV, "")).strip()
        if is_real(self.url):
            if not key:
                raise SystemExit("%s is not set. Put `export %s=sk_...` in ~/.config/game-foundation/keys.env "
                                 "(elevenlabs.io -> Settings -> API Keys). Nothing was sent." % (KEY_ENV, KEY_ENV))
            if not key.startswith(KEY_PREFIX):
                raise SystemExit("that looks like an ElevenLabs key *id*, not the key: a real key starts with %s. "
                                 "Nothing was sent." % KEY_PREFIX)
        self.key = key or "sk_mock"
        self.delays = delays
        self.real = is_real(self.url)

    def _request(self, method: str, path: str, body: dict | None = None) -> tuple[bytes, dict]:
        data = json.dumps(body).encode() if body is not None else None
        headers = {"xi-api-key": self.key, "Accept": "*/*"}
        if data is not None:
            headers["Content-Type"] = "application/json"
        for delay in tuple(self.delays) + (None,):
            request = urllib.request.Request(self.url + path, data=data, headers=headers, method=method)
            try:
                with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_S) as response:
                    return response.read(), {k.lower(): v for k, v in response.headers.items()}
            except urllib.error.HTTPError as error:
                text = error.read().decode(errors="replace")[:300]
                if delay is None or not (error.code == 429 or error.code >= 500):
                    raise ElevenLabsError(error.code, text) from None
            except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
                if delay is None:
                    raise ElevenLabsError(0, "could not reach %s (%s)" % (self.url, error)) from None
            time.sleep(delay)
        raise AssertionError("unreachable")

    def credits_left(self) -> int | None:
        """The account's remaining credits, or None when the key may not read it (a restricted key)."""
        try:
            raw, _ = self._request("GET", "/v1/user/subscription")
            sub = json.loads(raw)
            return int(sub["character_limit"]) - int(sub["character_count"])
        except (ElevenLabsError, KeyError, ValueError):
            return None

    def sound(self, prompt: str, seconds: float, loop: bool = False, influence: float = 0.4) -> bytes:
        body = {"text": prompt, "duration_seconds": float(seconds), "prompt_influence": float(influence),
                "model_id": SFX_MODEL}
        if loop:
            body["loop"] = True
        audio, _ = self._request("POST", "/v1/sound-generation?output_format=%s" % OUTPUT_FORMAT, body)
        return audio

    def speak(self, voice_id: str, text: str, settings: dict | None = None, model: str = TTS_MODEL) -> tuple[bytes, int]:
        """(mp3 bytes, characters billed: the response's character-cost header, else the text's length)."""
        body = {"text": text, "model_id": model}
        if settings:
            body["voice_settings"] = settings
        audio, headers = self._request("POST", "/v1/text-to-speech/%s?output_format=%s" % (voice_id, OUTPUT_FORMAT), body)
        try:
            cost = int(headers.get("character-cost", ""))
        except ValueError:
            cost = len(text)
        return audio, cost

    def voices(self) -> list[dict]:
        found, token = [], ""
        while True:
            raw, _ = self._request("GET", "/v2/voices?page_size=100" + ("&next_page_token=" + token if token else ""))
            page = json.loads(raw)
            found += page.get("voices", [])
            token = page.get("next_page_token") or ""
            if not page.get("has_more") or not token:
                return found


def append_ledger(path: Path, what: str, model: str, requests: int, amount: str, estimate: int,
                  before, after, note: str = "") -> None:
    """One line per paid run. `amount` is "12.0 s" (sounds) or "340 chars" (voices)."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        path.write_text("# ElevenLabs ledger\n\nEvery paid request, appended by tools/audio (sfx.py, voices.py, "
                        "choices.py). Sounds cost about %g credits per second, speech about 1 credit per character. "
                        "\"before → after\" is the account balance when the key may read it.\n\n"
                        "| Date | What | Model | Requests | Amount | Est. credits | Credits before → after | Spent | Note |\n"
                        "|---|---|---|---|---|---|---|---|---|\n" % SFX_CREDITS_PER_SECOND)
    spent = str(before - after) if isinstance(before, int) and isinstance(after, int) else ""
    with path.open("a") as handle:
        handle.write("| %s | %s | %s | %d | %s | %d | %s → %s | %s | %s |\n" % (
            datetime.date.today().isoformat(), what, model, requests, amount, estimate,
            "?" if before is None else before, "?" if after is None else after, spent, note.replace("|", "/")))
