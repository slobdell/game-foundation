"""Sound effects: sounds.json validation, generation against the mock, skipping, staleness, the ledger, keys."""

from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as c  # noqa: E402
import sfx  # noqa: E402
from testkit import AudioCase  # noqa: E402

SOUNDS = [
    {"id": "boing", "prompt": "a cartoon spring boing", "duration": 0.6, "variants": 2, "loop": False},
    {"id": "wind", "prompt": "a gentle steady wind over a meadow", "duration": 2.0, "variants": 1, "loop": True},
]


class ValidateTest(unittest.TestCase):
    def test_the_starter_sounds_are_valid(self):
        data = json.loads((c.ROOT / "assets/audio/sounds.json").read_text())
        self.assertEqual(sfx.validate(data), [])
        ids = {s["id"] for s in data}
        for wanted in ("pickup", "jump", "footstep", "ui_click", "portal", "build_place", "mission_complete"):
            self.assertIn(wanted, ids)

    def test_problems_are_named(self):
        bad = [{"id": "Bad Id", "prompt": "x y z", "duration": 1},
               {"id": "step_v2", "prompt": "a step", "duration": 1},
               {"id": "long", "prompt": "too long", "duration": 31},
               {"id": "none", "prompt": "no variants", "duration": 1, "variants": 0},
               {"id": "long", "prompt": "twice", "duration": 1},
               {"id": "loud", "prompt": "a sound", "duration": 1, "placeholder": "kazoo"}]
        problems = " | ".join(sfx.validate(bad))
        for needle in ("lowercase", "_v<number>", "0.5-30", "variants", "twice", "placeholder"):
            self.assertIn(needle, problems)
        self.assertEqual(sfx.validate({"id": "x"}), ["sounds.json must be a JSON list of sounds: [{\"id\": ..., \"prompt\": ...}, ...]"])

    def test_variant_files_belong_to_the_right_sound(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            for name in ("step.ogg", "step_v1.ogg", "step_v12.ogg", "step_big_v1.ogg", "steps.ogg", "step_vx.ogg"):
                (folder / name).write_bytes(b"")
            self.assertEqual([p.name for p in sfx.files_for("step", folder)], ["step.ogg", "step_v1.ogg", "step_v12.ogg"])


class GenerateTest(AudioCase):
    def setUp(self):
        super().setUp()
        self.write("assets/audio/sounds.json", SOUNDS)

    def test_dry_run_costs_nothing_and_prices_the_plan(self):
        result = self.run_tool("sfx.py", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("3 requests", result.stdout)
        self.assertIn("about 32 credits", result.stdout)  # (0.6 * 2 + 2.0) s * 10
        self.assertEqual(self.posts(), [])

    def test_makes_every_variant_levelled_and_ledgers_it(self):
        result = self.run_tool("sfx.py")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.posts("/v1/sound-generation")), 3)
        sfx_dir = self.root / "assets/audio/sfx"
        self.assertEqual(sorted(p.name for p in sfx_dir.glob("*.ogg")), ["boing_v1.ogg", "boing_v2.ogg", "wind_v1.ogg"])
        made = self.read("assets/audio/made.json")
        self.assertEqual({v["by"] for v in made.values()}, {"elevenlabs"})
        loop_body = [p["body"] for p in self.posts() if "wind" in p["body"]["text"]][0]
        self.assertTrue(loop_body["loop"])
        self.assertIn("loop=true", (sfx_dir / "wind_v1.ogg.import").read_text())
        for path in sfx_dir.glob("*.ogg"):
            samples = c.decode(path)
            self.assertLessEqual(c.peak_db(samples), c.SFX_PEAK_DB + 0.05, path.name)
            self.assertAlmostEqual(c.loudest_window_db(samples, 44100), c.SFX_LEVEL_DB, delta=3.0, msg=path.name)
        ledger = (self.root / "build/audio/mock_ledger.md").read_text()
        self.assertIn("| 3 | 3.2 s | 32 |", ledger)
        self.assertIn("100000 → 99968 | 32 |", ledger)
        self.assertFalse((self.root / "assets/audio/elevenlabs_ledger.md").exists(), "a mock run never looks like spend")
        self.assertIn("spent 32", result.stdout)

    def test_skips_what_exists_and_remakes_what_changed(self):
        self.run_tool("sfx.py")
        first = len(self.posts())
        again = self.run_tool("sfx.py")
        self.assertIn("nothing to make", again.stdout)
        self.assertEqual(len(self.posts()), first)
        changed = [dict(SOUNDS[0], prompt="a bigger, wobblier spring boing"), SOUNDS[1]]
        self.write("assets/audio/sounds.json", changed)
        result = self.run_tool("sfx.py", "--dry-run")
        self.assertIn("stale", result.stdout)
        self.run_tool("sfx.py")
        self.assertEqual(len(self.posts()) - first, 2, "only the changed sound's two takes")
        forced = self.run_tool("sfx.py", "--only", "wind", "--force")
        self.assertEqual(forced.returncode, 0)
        self.assertEqual(len(self.posts()) - first, 3)

    def test_placeholders_are_replaced_by_real_takes(self):
        self.run_tool("placeholders.py")
        made = self.read("assets/audio/made.json")
        self.assertEqual({v["by"] for v in made.values()}, {"placeholder"})
        self.assertEqual(self.posts(), [])
        dry = self.run_tool("sfx.py", "--dry-run")
        self.assertIn("placeholder", dry.stdout)
        self.run_tool("sfx.py")
        made = self.read("assets/audio/made.json")
        self.assertEqual({v["by"] for v in made.values()}, {"elevenlabs"})
        self.assertEqual(len(made), 3)

    def test_fewer_variants_removes_the_extra_files(self):
        self.run_tool("sfx.py")
        self.write("assets/audio/sounds.json", [dict(SOUNDS[0], variants=1, prompt="one boing"), SOUNDS[1]])
        self.run_tool("sfx.py", "--only", "boing")
        names = sorted(p.name for p in (self.root / "assets/audio/sfx").glob("boing*.ogg"))
        self.assertEqual(names, ["boing_v1.ogg"])

    def test_retries_a_busy_server_but_not_a_refusal(self):
        self.mock.fail_next = [503]
        ok = self.run_tool("sfx.py", "--only", "wind")
        self.assertEqual(ok.returncode, 0, ok.stdout + ok.stderr)
        self.assertTrue((self.root / "assets/audio/sfx/wind_v1.ogg").exists())
        self.mock.fail_next = [400]
        refused = self.run_tool("sfx.py", "--only", "boing")
        self.assertEqual(refused.returncode, 1)
        self.assertIn("FAILED boing", refused.stdout)
        self.assertFalse((self.root / "assets/audio/sfx/boing_v1.ogg").exists(), "half a sound is not installed")

    def test_unknown_ids_and_missing_keys_stop_before_sending(self):
        unknown = self.run_tool("sfx.py", "--only", "nope")
        self.assertNotEqual(unknown.returncode, 0)
        self.assertIn("not in sounds.json", unknown.stderr)
        no_key = self.run_tool("sfx.py", "--base-url", c.REAL_BASE_URL, mock=False)
        self.assertNotEqual(no_key.returncode, 0)
        self.assertIn("ELEVENLABS_API_KEY is not set", no_key.stderr)
        key_id = self.run_tool("sfx.py", "--base-url", c.REAL_BASE_URL, mock=False, env={"ELEVENLABS_API_KEY": "abc123"})
        self.assertIn("key *id*", key_id.stderr)
        self.assertEqual(self.posts(), [])
        self.assertFalse(re.search(r"made", no_key.stdout + key_id.stdout))


if __name__ == "__main__":
    unittest.main()
