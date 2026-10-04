"""Music: Suno-style track -> seamless levelled loop + music.json; the check catches clicks, fades, loudness, rights."""

from __future__ import annotations

import math
import random
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as c  # noqa: E402
import music  # noqa: E402
from testkit import AudioCase  # noqa: E402

RATE = 22050
BAR = 2.4  # 100 bpm, 4/4


def fake_suno_song(path: Path, body_s: float = 30.0) -> None:
    """1 s silence, a 3 s quiet intro, a body whose 2-bar pattern repeats (kick, hat, two-chord bass), a 4 s fade-out,
    1 s silence: the shape of a real Suno download, with known musical period."""
    rng = random.Random(3)
    out = []
    total = 1.0 + 3.0 + body_s + 4.0 + 1.0
    for i in range(int(total * RATE)):
        t = i / RATE
        if t < 1.0 or t > total - 1.0:
            out.append(0.0)
            continue
        melody = 0.15 * math.sin(2 * math.pi * (220 if (t % (2 * BAR)) < BAR else 330) * t)
        if t < 4.0:
            out.append(0.3 * melody)
            continue
        beat = t % 0.6
        kick = 0.6 * math.sin(2 * math.pi * 60 * beat) * math.exp(-25 * beat)
        hat = 0.15 * (rng.random() * 2 - 1) * math.exp(-80 * ((t - 0.3) % 0.6))
        level = 1.0 if t < total - 5.0 else max(0.0, (total - 1.0 - t) / 4.0)
        out.append(level * (kick + hat + melody))
    c.write_wav(path, [x * 0.8 for x in out], RATE)


class UnitTest(unittest.TestCase):
    def test_seconds(self):
        self.assertEqual(music.seconds("1:30"), 90.0)
        self.assertEqual(music.seconds("12.5"), 12.5)
        self.assertEqual(music.seconds(""), 0.0)

    def test_crossfade_makes_the_wrap_continuous(self):
        frames = 1000
        stereo = []
        for i in range(frames + 100):
            stereo += [math.sin(i * 0.37), math.cos(i * 0.21)]
        looped = music.crossfade_loop(stereo, frames, 100)
        self.assertEqual(len(looped), frames * 2)
        self.assertAlmostEqual(looped[0], stereo[2 * frames], places=6, msg="the first sample continues the last")
        self.assertAlmostEqual(looped[-2], stereo[2 * (frames - 1)], places=6)
        self.assertAlmostEqual(looped[200], stereo[200], places=6, msg="after the fade the music is untouched")

    def test_find_loop_end_finds_the_musical_period(self):
        period = 48  # frames
        feats = [((i % period) * 1.0, ((i % period) // 6) * 1.0) for i in range(600)]
        end, mismatch = music.find_loop_end(feats, 10, 200, 520, 0.0, 60)
        self.assertEqual((end - 10) % period, 0)
        self.assertLess(mismatch, 0.01)
        self.assertGreater(end, 450, "the longest good loop wins")
        on_bars, _ = music.find_loop_end(feats, 10, 200, 520, 24.0, 60)
        self.assertEqual((on_bars - 10) % 24, 0)


class ImportTest(AudioCase):
    def test_import_a_song_into_a_clean_loop(self):
        song = self.root / "Downloads" / "Lava Theme.wav"
        song.parent.mkdir(parents=True)
        fake_suno_song(song)
        result = self.run_tool("music.py", "import", str(song), "--id", "lava_theme", "--bpm", "100")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        track = self.read("assets/music/music.json")["tracks"]["lava_theme"]
        self.assertEqual(track["file"], "lava_theme.ogg")
        self.assertEqual(track["rights"], music.UNRECORDED)
        self.assertIn("record the rights", result.stdout)
        start, end = track["section_s"]
        self.assertAlmostEqual(((end - start) / BAR) % 1.0 if ((end - start) / BAR) % 1.0 < 0.5 else 1.0 - ((end - start) / BAR) % 1.0,
                               0.0, delta=0.02, msg="the loop is whole bars")
        self.assertGreater(end - start, 15.0)
        self.assertLess(end, 34.0, "the fade-out is not in the loop")
        problems, _ = music.check(self.root / "assets/music", log=lambda *_: None)
        self.assertEqual(problems, [])
        self.assertIn("loop=true", (self.root / "assets/music/lava_theme.ogg.import").read_text())
        lufs, peak = c.measure_lufs(self.root / "assets/music/lava_theme.ogg")
        self.assertAlmostEqual(lufs, c.MUSIC_LUFS, delta=1.0)
        check = self.run_tool("music.py", "check")
        self.assertEqual(check.returncode, 0, check.stdout)
        self.assertIn("rights not recorded yet", check.stdout)

    def test_import_without_tempo_and_with_from_to_and_rights(self):
        song = self.root / "song.wav"
        fake_suno_song(song, body_s=24.0)
        result = self.run_tool("music.py", "import", str(song), "--id", "cave", "--from", "0:05", "--to", "0:27",
                               "--rights", "Suno Pro, 2026-10-04", "--title", "Cave")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        track = self.read("assets/music/music.json")["tracks"]["cave"]
        self.assertEqual(track["rights"], "Suno Pro, 2026-10-04")
        self.assertGreaterEqual(track["section_s"][0], 5.0)
        self.assertLessEqual(track["section_s"][1], 27.0)

    def test_the_check_catches_clicks_fades_and_missing_files(self):
        folder = self.root / "assets/music"
        clicky = self.root / "clicky.wav"
        c.write_wav(clicky, [0.5 * math.sin(2 * math.pi * 331.7 * i / RATE) for i in range(RATE * 6)], RATE)
        music.import_track(clicky, "clicky", folder, exact=True, rights="test", log=lambda *_: None)
        fading = self.root / "fading.wav"
        c.write_wav(fading, [math.sin(i * 0.05) * max(0.0, 1 - i / (RATE * 6)) * 0.5 for i in range(RATE * 6)], RATE)
        music.import_track(fading, "fading", folder, exact=True, rights="test", log=lambda *_: None)
        manifest = self.read("assets/music/music.json")
        manifest["tracks"]["gone"] = {"file": "gone.ogg", "rights": "x"}
        manifest["tracks"]["fading"]["rights"] = ""
        self.write("assets/music/music.json", manifest)
        problems = " | ".join(music.check(folder, log=lambda *_: None)[0])
        self.assertIn("clicky: the loop seam jumps", problems)
        self.assertIn("fading: the end is", problems)
        self.assertIn("fading: needs a rights note", problems)
        self.assertIn("gone: gone.ogg is not there", problems)

    def test_missing_input_is_a_plain_message(self):
        result = self.run_tool("music.py", "import", str(self.root / "nope.mp3"), "--id", "x")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("is not there", result.stderr)


if __name__ == "__main__":
    unittest.main()
