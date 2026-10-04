"""Placeholders (every recipe makes usable audio; the music loop is seamless) and audio-check (fresh repo green;
real problems red; missing audio only a note)."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import check  # noqa: E402
import common as c  # noqa: E402
import music  # noqa: E402
import placeholders  # noqa: E402
from testkit import AudioCase, copy_real  # noqa: E402


class PlaceholderTest(unittest.TestCase):
    def test_ids_get_sensible_recipes(self):
        expect = {"pickup": "blip", "coin_big": "blip", "jump": "sweep_up", "footstep": "thump", "ui_click": "click",
                  "portal": "chime", "build_place": "thunk", "build_denied": "buzz", "mission_complete": "fanfare",
                  "zzz": "blip"}
        for sound_id, kind in expect.items():
            self.assertEqual(placeholders.guess({"id": sound_id}), kind, sound_id)
        self.assertEqual(placeholders.guess({"id": "lava", "loop": True}), "hum")
        self.assertEqual(placeholders.guess({"id": "lava", "placeholder": "whoosh"}), "whoosh")

    def test_every_recipe_makes_audio_the_check_accepts(self):
        with tempfile.TemporaryDirectory() as tmp:
            for kind in placeholders.sfx.PLACEHOLDER_KINDS:
                for n in (1, 2):
                    source, seconds = placeholders.recipe(kind, n)
                    wav, ogg = Path(tmp) / "raw.wav", Path(tmp) / ("%s%d.ogg" % (kind, n))
                    c.ffmpeg("-f", "lavfi", "-i", source, "-t", "%g" % seconds, "-ac", "1", "-c:a", "pcm_s16le", str(wav))
                    c.level_sound(wav, ogg, loop=kind == "hum", trim=False)
                    samples = c.decode(ogg)
                    self.assertLessEqual(c.peak_db(samples), check.PEAK_MAX_DB, kind)
                    level = c.loudest_window_db(samples, 44100)
                    self.assertTrue(check.SFX_LEVEL_RANGE[0] <= level <= check.SFX_LEVEL_RANGE[1], (kind, level))

    def test_the_explore_loop_is_seamless(self):
        left, right = placeholders.explore_loop()
        for channel in (left, right):
            jump, gap = music.seam(channel, 22050)
            self.assertLess(jump, 1.5)
            self.assertLess(gap, music.SEAM_LEVEL_DB_MAX, "a new bar starts, not a fade")


class CheckTest(AudioCase):
    def test_the_real_repo_passes(self):
        result = subprocess.run([sys.executable, str(HERE / "check.py")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("audio-check: OK", result.stdout)

    def test_a_fresh_layout_with_nothing_made_is_fine(self):
        copy_real("assets/audio/sounds.json", self.root)
        copy_real("data/voices.json", self.root)
        self.write("data/dialogue/a.json", {"id": "a", "lines": [{"speaker": "Guide", "text": "Hi!", "voice": "hi"}]})
        result = self.run_tool("check.py")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("no audio yet", result.stdout)
        self.assertIn("not recorded yet", result.stdout)
        self.assertIn("no music yet", result.stdout)
        made = self.run_tool("placeholders.py", "--music")
        self.assertEqual(made.returncode, 0, made.stdout + made.stderr)
        result = self.run_tool("check.py")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("still placeholders", result.stdout)

    def test_real_problems_fail(self):
        self.write("assets/audio/sounds.json", [
            {"id": "loud", "prompt": "a loud thing", "duration": 1},
            {"id": "hum", "prompt": "a steady hum", "duration": 2, "loop": True}])
        self.starter_voices()
        self.write("data/dialogue/a.json", {"id": "a", "lines": [{"speaker": "Pirate", "text": "Arr", "voice": "arr"}]})
        sfx = self.root / "assets/audio/sfx"
        sfx.mkdir(parents=True)
        c.ffmpeg("-f", "lavfi", "-i", "sine=f=300:d=0.5", "-af", "volume=20dB", "-c:a", "libvorbis", str(sfx / "loud.ogg"))
        c.ffmpeg("-f", "lavfi", "-i", "sine=f=100:d=1", "-af", "volume=-20dB", "-c:a", "libvorbis", str(sfx / "hum_v1.ogg"))
        c.ffmpeg("-f", "lavfi", "-i", "sine=f=100:d=1", "-c:a", "libvorbis", str(sfx / "stray.ogg"))
        result = self.run_tool("check.py")
        self.assertEqual(result.returncode, 1)
        for needle in ("loud.ogg: peaks at", "hum_v1.ogg: a loop sound, but its import is not set to loop",
                       "'Pirate', who has no voice", "stray.ogg belongs to no sound"):
            self.assertIn(needle, result.stdout)
        self.write("assets/audio/sounds.json", "{broken")
        broken = self.run_tool("check.py")
        self.assertNotEqual(broken.returncode, 0)


if __name__ == "__main__":
    unittest.main()
