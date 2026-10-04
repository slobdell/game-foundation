"""Choices: takes -> a spec the choices page accepts -> the director's picks -> in the game. Against the mock."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from testkit import CALLUM, GEORGE, JESSICA, AudioCase  # noqa: E402

SOUNDS = [
    {"id": "footstep", "prompt": "a squishy footstep on moss", "duration": 0.5, "variants": 2, "loop": False},
    {"id": "fanfare", "prompt": "a tiny fanfare", "duration": 1.0, "variants": 1, "loop": False},
]
DIALOGUE = {"id": "intro", "lines": [{"speaker": "Guide", "text": "Ahoy, explorer!", "voice": "guide_ahoy"}]}


def page_validator():
    """tools/pages/choices_page.validate if that tool is there (another workstream owns it), else None."""
    sys.path.insert(0, str(HERE.parent / "pages"))
    try:
        import choices_page
    except ImportError:
        return None
    return choices_page.validate


class ChoicesTest(AudioCase):
    def setUp(self):
        super().setUp()
        self.write("assets/audio/sounds.json", "[\n" + ",\n".join("  " + json.dumps(s) for s in SOUNDS) + "\n]\n")
        self.starter_voices()
        self.write("data/dialogue/intro.json", DIALOGUE)

    def spec(self, name):
        return self.read("build/pages/%s.spec.json" % name)

    def decide(self, name, answers):
        self.write("data/decisions/%s.json" % name, {q: dict(a, at="2026-10-04T10:00:00") for q, a in answers.items()})

    def test_sound_and_line_takes_become_a_valid_spec(self):
        result = self.run_tool("choices.py", "build", "--name", "first_pick", "--sounds", "footstep,fanfare",
                               "--lines", "guide_ahoy")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        spec = self.spec("first_pick")
        kinds = {q["id"]: (q["kind"], len(q["options"])) for q in spec["questions"]}
        self.assertEqual(kinds, {"sound.footstep": ("pick_many", 3), "sound.fanfare": ("pick_one", 3),
                                 "line.guide_ahoy": ("pick_one", 3)})
        self.assertEqual(len(self.posts("/v1/sound-generation")), 6)
        self.assertEqual(len(self.posts("/v1/text-to-speech/")), 3)
        for question in spec["questions"]:
            for option in question["options"]:
                self.assertTrue((self.root / option["audio"]).exists(), option["audio"])
        validate = page_validator()
        if validate is not None:
            validate(spec, root=self.root)  # raises on anything the page builder would refuse
        self.assertIn("| choices first_pick |", (self.root / "build/audio/mock_ledger.md").read_text())
        again = self.run_tool("choices.py", "build", "--name", "first_pick", "--sounds", "footstep,fanfare",
                              "--lines", "guide_ahoy")
        self.assertIn("nothing spent", again.stdout)
        self.assertEqual(len(self.posts()), 9, "rebuilding the page reuses the takes")

    def test_picks_go_into_the_game(self):
        self.run_tool("choices.py", "build", "--name", "p", "--sounds", "footstep,fanfare", "--lines", "guide_ahoy")
        takes = self.root / "build/audio/candidates"
        self.decide("p", {"sound.footstep": {"pick": ["take1", "take2", "take3"], "note": "all squishy!"},
                          "sound.fanfare": {"pick": "take2", "note": ""},
                          "line.guide_ahoy": {"pick": "take3", "note": ""}})
        result = self.run_tool("choices.py", "apply", "--name", "p")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        sfx = self.root / "assets/audio/sfx"
        self.assertEqual(sorted(p.name for p in sfx.glob("footstep*.ogg")), ["footstep_v1.ogg", "footstep_v2.ogg", "footstep_v3.ogg"])
        self.assertEqual((sfx / "fanfare_v1.ogg").read_bytes(), (takes / "sound/fanfare/take2.ogg").read_bytes())
        self.assertEqual((self.root / "assets/voices/guide_ahoy.ogg").read_bytes(),
                         (takes / "line/guide_ahoy/take3.ogg").read_bytes())
        sounds = self.read("assets/audio/sounds.json")
        self.assertEqual(sounds[0]["variants"], 3, "three picked, so the game rotates three")
        self.assertIn("all squishy!", result.stdout)
        made = self.read("assets/audio/made.json")
        self.assertEqual({v["by"] for v in made.values()}, {"elevenlabs"})
        calls = len(self.posts())
        dry = self.run_tool("sfx.py", "--dry-run")
        self.assertIn("nothing to make", dry.stdout, "picked takes count as real, current recordings")
        voices = self.run_tool("voices.py", "--dry-run")
        self.assertIn("nothing to record", voices.stdout)
        self.assertEqual(len(self.posts()), calls)

    def test_none_of_these_changes_nothing(self):
        self.run_tool("choices.py", "build", "--name", "q", "--sounds", "fanfare")
        self.decide("q", {"sound.fanfare": {"pick": "", "note": "more trumpets"}})
        result = self.run_tool("choices.py", "apply", "--name", "q")
        self.assertIn("none of these", result.stdout)
        self.assertIn("more trumpets", result.stdout)
        self.assertFalse((self.root / "assets/audio/sfx/fanfare_v1.ogg").exists())

    def test_pick_a_voice_for_a_speaker(self):
        result = self.run_tool("choices.py", "build", "--name", "guide_voice", "--speaker", "guide",
                               "--voices", ",".join([JESSICA, CALLUM, GEORGE]))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        question = self.spec("guide_voice")["questions"][0]
        self.assertEqual(question["id"], "speaker.guide")
        labels = [o["label"] for o in question["options"]]
        self.assertEqual(labels, ["Jessica (now)", "Callum", "George"])
        spoken = {c["body"]["text"] for c in self.posts("/v1/text-to-speech/")}
        self.assertEqual(spoken, {"Ahoy, explorer!"}, "each voice says one of the speaker's own lines")
        self.decide("guide_voice", {"speaker.guide": {"pick": CALLUM, "note": "PIRATE"}})
        applied = self.run_tool("choices.py", "apply", "--name", "guide_voice")
        self.assertIn("make voices", applied.stdout)
        voices = self.read("data/voices.json")
        self.assertEqual(voices["speakers"]["guide"]["voice_id"], CALLUM)
        self.assertEqual(voices["speakers"]["guide"]["voice_name"], "Callum")

    def test_without_a_key_only_existing_takes_work(self):
        self.run_tool("choices.py", "build", "--name", "r", "--sounds", "fanfare")
        real = "https://api.elevenlabs.io"
        reuse = self.run_tool("choices.py", "build", "--name", "r", "--sounds", "fanfare", "--base-url", real, mock=False)
        self.assertEqual(reuse.returncode, 0, reuse.stdout + reuse.stderr)
        new = self.run_tool("choices.py", "build", "--name", "r2", "--sounds", "footstep", "--base-url", real, mock=False)
        self.assertNotEqual(new.returncode, 0)
        self.assertIn("ELEVENLABS_API_KEY is not set", new.stderr)


if __name__ == "__main__":
    unittest.main()
