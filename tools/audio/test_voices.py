"""Voices: dialogue lines (incl. variants) -> one clip per voiced line, against the mock; skipping; re-recording."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as c  # noqa: E402
import voices as vo  # noqa: E402
from testkit import CALLUM, AudioCase  # noqa: E402

DIALOGUE = {
    "id": "guide_hello",
    "lines": [
        {"speaker": "Guide", "text": "Oh, hello! You must be new here.", "voice": "guide_hello_1"},
        {"speaker": "Guide", "text": "This line stays silent text."},
        {"speaker": "Narrator", "text": "And so it began.", "voice": "narr_begin"},
    ],
    "variants": [{"when": {"flag": "x"}, "lines": [{"speaker": "guide", "text": "Back again?", "voice": "guide_again"}]}],
}


class ParseTest(unittest.TestCase):
    def test_the_starter_voices_are_valid(self):
        voices = json.loads((c.ROOT / "data/voices.json").read_text())
        self.assertEqual(vo.validate_voices(voices), [])
        self.assertIsNotNone(vo.speaker(voices, "Guide"), "the starter dialogue's speaker has a voice")
        self.assertIsNotNone(vo.speaker(voices, "narrator"))

    def test_lines_are_found_inside_variants_and_checked(self):
        found = []
        vo._walk_lines(DIALOGUE, found, "x.json")
        self.assertEqual([l.get("voice") for l in found], ["guide_hello_1", None, "narr_begin", "guide_again"])
        voices = {"speakers": {"guide": {"voice_id": "a" * 20}}}
        voiced = [l for l in found if l.get("voice")]
        problems = " | ".join(vo.validate_lines(voiced + [dict(voiced[0])], voices))
        self.assertIn("'Narrator', who has no voice", problems)
        self.assertIn("used twice", problems)

    def test_bad_voice_settings_are_named(self):
        problems = " | ".join(vo.validate_voices({"model": "eleven_x", "speakers": {
            "a": {"voice_id": "short"}, "b": {"voice_id": "x" * 20, "settings": {"stability": 3, "pitch": 1}}}}))
        for needle in ("price", "needs a voice_id", "stability must be 0-1", "unknown settings"):
            self.assertIn(needle, problems)


class RecordTest(AudioCase):
    def setUp(self):
        super().setUp()
        self.starter_voices()
        self.write("data/dialogue/guide_hello.json", DIALOGUE)

    def test_records_every_voiced_line_once(self):
        dry = self.run_tool("voices.py", "--dry-run")
        self.assertIn("3 lines to record", dry.stdout)
        self.assertEqual(self.posts(), [])
        result = self.run_tool("voices.py")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.posts("/v1/text-to-speech/")
        self.assertEqual(len(calls), 3)
        self.assertEqual(calls[0]["body"]["voice_settings"], {"stability": 0.5})
        clips = sorted(p.name for p in (self.root / "assets/voices").glob("*.ogg"))
        self.assertEqual(clips, ["guide_again.ogg", "guide_hello_1.ogg", "narr_begin.ogg"])
        for name in clips:
            lufs, peak = c.measure_lufs(self.root / "assets/voices" / name)
            self.assertAlmostEqual(lufs, c.VOICE_LUFS, delta=1.5, msg=name)
            self.assertLessEqual(peak, c.PEAK_CEILING_DB + 0.3, name)
        ledger = (self.root / "build/audio/mock_ledger.md").read_text()
        chars = sum(len(t) for t in ("Oh, hello! You must be new here.", "And so it began.", "Back again?"))
        self.assertIn("%d chars | %d |" % (chars, chars), ledger)
        again = self.run_tool("voices.py")
        self.assertIn("nothing to record", again.stdout)
        self.assertEqual(len(self.posts()), 3)

    def test_edited_text_or_voice_is_recorded_again(self):
        self.run_tool("voices.py")
        edited = json.loads(json.dumps(DIALOGUE))
        edited["lines"][0]["text"] = "Hello there, explorer!"
        self.write("data/dialogue/guide_hello.json", edited)
        dry = self.run_tool("voices.py", "--dry-run")
        self.assertIn("guide_hello_1", dry.stdout)
        self.assertIn("changed", dry.stdout)
        self.assertIn("1 lines to record", dry.stdout)
        self.starter_voices(narrator=CALLUM, guide="cgSgspJ2msm6clMCkdW9")
        dry = self.run_tool("voices.py", "--dry-run")
        self.assertIn("2 lines to record", dry.stdout, "the narrator's new voice + the edited line")

    def test_only_and_force(self):
        self.run_tool("voices.py", "--only", "narr_begin")
        self.assertEqual(len(self.posts()), 1)
        self.run_tool("voices.py", "--only", "narr_begin", "--force")
        self.assertEqual(len(self.posts()), 2)
        bad = self.run_tool("voices.py", "--only", "nope")
        self.assertIn("no dialogue line has voice id nope", bad.stderr)

    def test_unknown_speaker_stops_everything(self):
        self.write("data/voices.json", {"speakers": {"guide": {"voice_id": "cgSgspJ2msm6clMCkdW9"}}})
        result = self.run_tool("voices.py")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("'Narrator', who has no voice", result.stderr)
        self.assertEqual(self.posts(), [])

    def test_a_voice_the_service_does_not_know_fails_that_line(self):
        self.starter_voices(narrator="NotARealVoiceId123", guide="cgSgspJ2msm6clMCkdW9")
        result = self.run_tool("voices.py")
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAILED narr_begin", result.stdout)
        self.assertTrue((self.root / "assets/voices/guide_hello_1.ogg").exists(), "the other lines still recorded")

    def test_voice_list_and_search(self):
        listing = self.run_tool("voices.py", "--list")
        self.assertIn("JBFqnCBsd6RMkjVDRZzb", listing.stdout)
        self.assertIn("5 voices", listing.stdout)
        pirate = self.run_tool("voices.py", "--list", "pirate")
        self.assertIn(CALLUM, pirate.stdout)
        self.assertIn("1 voices matching 'pirate'", pirate.stdout)


if __name__ == "__main__":
    unittest.main()
