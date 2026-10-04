"""Helpers for tools/audio/test_*.py: a throwaway repo layout, the mock server, and running a tool against both.

Every test that runs a tool runs it as a subprocess with AUDIO_REPO_ROOT set to a temp folder, so the real
assets/, data/ and ledger are never touched, and ELEVENLABS_API_KEY removed, so nothing can reach the real service.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import mock_elevenlabs  # noqa: E402

GEORGE = "JBFqnCBsd6RMkjVDRZzb"
JESSICA = "cgSgspJ2msm6clMCkdW9"
CALLUM = "N2lVS1w4EtoT3dr4eOWO"


class AudioCase(unittest.TestCase):
    """A temp repo (self.root) and a running mock (self.url, self.mock)."""

    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.root = Path(self._dir.name)
        self.server, self.url, self.mock = mock_elevenlabs.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self._dir.cleanup()

    def write(self, rel: str, data) -> Path:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data if isinstance(data, str) else json.dumps(data, indent=1))
        return path

    def read(self, rel: str):
        return json.loads((self.root / rel).read_text())

    def run_tool(self, tool: str, *args: str, mock: bool = True, env: dict | None = None) -> subprocess.CompletedProcess:
        environment = {k: v for k, v in os.environ.items() if k not in ("ELEVENLABS_API_KEY", "ELEVENLABS_BASE_URL")}
        environment["AUDIO_REPO_ROOT"] = str(self.root)
        environment.update(env or {})
        command = [sys.executable, str(HERE / tool), *args]
        if mock and tool != "check.py" and tool != "placeholders.py" and "--base-url" not in args and args[:1] != ("apply",) \
                and args[:1] != ("check",) and args[:1] != ("import",):
            command += ["--base-url", self.url]
        return subprocess.run(command, capture_output=True, text=True, timeout=300, env=environment)

    def posts(self, path_prefix: str = "") -> list[dict]:
        return [call for call in self.mock.calls if call["method"] == "POST" and call["path"].startswith(path_prefix)]

    def starter_voices(self, **speakers):
        speakers = speakers or {"narrator": GEORGE, "guide": JESSICA}
        self.write("data/voices.json", {"model": "eleven_multilingual_v2", "speakers": {
            name: {"voice_id": vid, "settings": {"stability": 0.5}} for name, vid in speakers.items()}})


def copy_real(rel: str, root: Path) -> None:
    """Copy a file of the real repo into the temp repo (starter content tests)."""
    source = HERE.parents[1] / rel
    dest = root / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, dest)
