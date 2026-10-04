"""The whole concept → pick → 3D flow against the mock Meshy server: no network, no key, no credits.

Run with `make py-test` (python3 -m unittest discover -s tools/assets -p 'test_*.py'). Every test works in a
temporary copy of the repo layout, so the real review manifest and ledger are never touched.
"""

import contextlib
import io
import json
import os
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate  # noqa: E402
import mock_provider  # noqa: E402
import review  # noqa: E402

SLOTS = {
    "_about": "test slots",
    "player": {"kind": "character", "size_m": [0.8, 1.8, 0.6], "placeholder": "capsule", "color": "#3d8bfd",
               "tris": 20000, "notes": "the hero the player controls"},
    "prop_rock": {"kind": "prop", "size_m": [1.6, 1.0, 1.4], "placeholder": "box", "color": "#7d7d7d", "tris": 3000},
}
ART = """# Art direction

## Style prompt

```text
chunky hand-painted fantasy, warm sunset colours, soft rounded shapes
```
"""


class FlowTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server, cls.state = mock_provider.serve(0)
        cls.url = f"http://127.0.0.1:{cls.server.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "data").mkdir()
        (self.root / "data" / "slots.json").write_text(json.dumps(SLOTS))
        (self.root / "_agents").mkdir()
        (self.root / "_agents" / "art_direction.md").write_text(ART)
        self.paths = review.Paths(self.root)
        self.state.requests.clear()
        self.key = mock.patch.dict(os.environ, {"MESHY_API_KEY": "mock"})
        self.key.start()

    def tearDown(self):
        self.key.stop()
        self.tmp.cleanup()

    # ---- helpers ----
    def gen(self, *args) -> tuple:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = generate.main(["--root", str(self.root), "--base-url", self.url, "--poll-interval", "0", *args])
        return code, out.getvalue(), err.getvalue()

    def rev(self, *args) -> tuple:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = review.main(["--root", str(self.root), *args])
        return code, out.getvalue(), err.getvalue()

    def posts(self, family: str) -> list:
        return [body for method, path, body in self.state.requests if method == "POST" and path.endswith(family)]

    def items(self) -> dict:
        return {i["id"]: i for i in review.load(self.paths)["items"]}

    def two_concepts_picked(self, pick="player_b", note="the toast one, he looks brave"):
        self.assertEqual(self.gen("concept", "--slot", "player", "--prompt", "a knight made of toast", "--title", "Toast knight")[0], 0)
        self.assertEqual(self.gen("concept", "--slot", "player", "--prompt", "a knight made of jelly", "--title", "Jelly knight")[0], 0)
        self.assertEqual(self.rev("choices", "--name", "models-1")[0], 0)
        (self.root / "data" / "decisions").mkdir(exist_ok=True)
        (self.root / "data" / "decisions" / "models-1.json").write_text(json.dumps(
            {"player": {"pick": pick, "note": note, "at": "2026-10-04T10:00:00Z"}}))
        code, out, err = self.rev("apply", "--name", "models-1")
        self.assertEqual(code, 0, err)
        return out

    # ---- concepts ----
    def test_concept_adds_the_style_and_tail_registers_it_and_logs_the_credits(self):
        code, out, err = self.gen("concept", "--slot", "player", "--prompt", "a knight made of toast")
        self.assertEqual(code, 0, err)
        body = self.posts("text-to-image")[0]
        self.assertTrue(body["prompt"].startswith("a knight made of toast."))
        self.assertIn("chunky hand-painted fantasy", body["prompt"], "the game's one style is in every prompt")
        self.assertIn("A-pose", body["prompt"], "characters get the character tail")
        self.assertTrue(body["remove_background"])
        item = self.items()["player_a"]
        self.assertEqual((item["slot"], item["status"]), ("player", "waiting"))
        self.assertTrue((self.root / item["image"]).exists())
        self.assertTrue((self.root / "assets" / "review" / ".gdignore").exists())
        self.assertEqual(review.ledger_total(self.paths.ledger), 9)
        self.assertIn("9 credits", out)

    def test_concept_ids_count_up_per_slot(self):
        for _ in range(3):
            self.assertEqual(self.gen("concept", "--slot", "prop_rock", "--prompt", "a lava rock")[0], 0)
        self.assertEqual(sorted(self.items()), ["prop_rock_a", "prop_rock_b", "prop_rock_c"])
        self.assertIn("One single object", self.posts("text-to-image")[0]["prompt"])

    def test_an_unchosen_art_style_refuses_before_spending(self):
        (self.root / "_agents" / "art_direction.md").write_text(ART.replace("chunky hand-painted fantasy", "TODO: with the kid"))
        code, _, err = self.gen("concept", "--slot", "player", "--prompt", "a knight")
        self.assertEqual(code, 1)
        self.assertIn("art style isn't chosen", err)
        self.assertEqual(self.posts("text-to-image"), [], "nothing may be spent")

    def test_unknown_slot_refuses_before_spending(self):
        code, _, err = self.gen("concept", "--slot", "dragon", "--prompt", "a dragon")
        self.assertEqual(code, 1)
        self.assertIn("no slot 'dragon'", err)
        self.assertEqual(self.state.requests, [])

    def test_references_make_it_image_to_image(self):
        ref = self.root / "ref.png"
        ref.write_bytes(mock_provider.png())
        self.assertEqual(self.gen("concept", "--slot", "player", "--prompt", "toast knight", "--reference", "ref.png")[0], 0)
        body = self.posts("image-to-image")[0]
        self.assertTrue(body["reference_image_urls"][0].startswith("data:image/png;base64,"))

    def test_a_downloaded_but_unregistered_concept_is_not_paid_for_twice(self):
        self.assertEqual(self.gen("concept", "--slot", "player", "--prompt", "toast knight", "--id", "player_x")[0], 0)
        review.update(self.paths, lambda m: m["items"].clear())  # as if registering had crashed
        self.assertEqual(self.gen("concept", "--slot", "player", "--prompt", "toast knight", "--id", "player_x")[0], 0)
        self.assertEqual(len(self.posts("text-to-image")), 1)
        self.assertIn("player_x", self.items())

    # ---- the page ----
    def test_choices_spec_follows_the_page_contract(self):
        self.gen("concept", "--slot", "player", "--prompt", "toast knight", "--title", "Toast knight", "--note", "reads well")
        self.gen("concept", "--slot", "player", "--prompt", "jelly knight")
        self.gen("concept", "--slot", "prop_rock", "--prompt", "lava rock")
        code, out, err = self.rev("choices", "--name", "models-1")
        self.assertEqual(code, 0, err)
        spec = json.loads((self.root / "build" / "pages" / "models-1.spec.json").read_text())
        self.assertEqual(spec["name"], "models-1")
        self.assertTrue(spec["title"] and spec["intro"])
        self.assertEqual([q["id"] for q in spec["questions"]], ["player", "prop_rock"])
        player = spec["questions"][0]
        self.assertEqual(player["kind"], "pick_one")
        self.assertIn("the hero the player controls", player["prompt"])
        self.assertEqual([o["id"] for o in player["options"]], ["player_a", "player_b", review.NONE_OPTION])
        self.assertEqual(player["options"][0]["label"], "Toast knight")
        self.assertEqual(player["options"][0]["note"], "reads well")
        self.assertTrue((self.root / player["options"][0]["image"]).exists(), "image paths are repo-relative and exist")
        for question in spec["questions"]:
            for option in question["options"]:
                self.assertTrue(set(option) <= {"id", "label", "image", "audio", "text", "note"}, option)

    def test_the_spec_passes_the_choices_page_builders_own_check(self):
        builder = Path(__file__).resolve().parents[1] / "pages" / "choices_page.py"
        if not builder.exists():
            self.skipTest("tools/pages/choices_page.py isn't here")
        sys.path.insert(0, str(builder.parent))
        import choices_page
        self.gen("concept", "--slot", "player", "--prompt", "toast knight")
        self.gen("concept", "--slot", "prop_rock", "--prompt", "lava rock")
        self.assertEqual(self.rev("choices", "--name", "models-1")[0], 0)
        spec = json.loads((self.root / "build" / "pages" / "models-1.spec.json").read_text())
        choices_page.validate(spec, self.root)  # raises SpecError on any mismatch

    def test_choices_with_nothing_waiting_says_so(self):
        code, _, err = self.rev("choices", "--name", "models-1")
        self.assertEqual(code, 1)
        self.assertIn("no concepts are waiting", err)

    def test_applying_the_kids_pick_approves_it_in_their_words(self):
        out = self.two_concepts_picked()
        items = self.items()
        self.assertEqual(items["player_b"]["status"], "approved")
        self.assertEqual(items["player_b"]["kid_words"], "the toast one, he looks brave")
        self.assertEqual(items["player_a"]["status"], "rejected")
        self.assertEqual(items["player_a"]["kid_words"], "picked player_b instead on page models-1")
        self.assertIn("PICKED player_b", out)
        self.assertEqual(self.rev("apply", "--name", "models-1")[0], 0, "applying twice is harmless")
        self.assertEqual(self.items()["player_b"]["status"], "approved")

    def test_none_of_these_rejects_all_and_passes_on_the_kids_words(self):
        out = self.two_concepts_picked(pick="none", note="make him bigger and greener")
        self.assertEqual({i["status"] for i in self.items().values()}, {"rejected"})
        self.assertIn("make him bigger and greener", out)

    def test_an_empty_pick_with_a_note_means_none_of_these(self):
        out = self.two_concepts_picked(pick="", note="more sparkly please")
        self.assertEqual({i["status"] for i in self.items().values()}, {"rejected"})
        self.assertIn("more sparkly please", out)

    def test_a_pick_that_was_not_on_the_page_is_an_error(self):
        self.gen("concept", "--slot", "player", "--prompt", "toast knight")
        self.rev("choices", "--name", "p")
        (self.root / "data" / "decisions").mkdir()
        (self.root / "data" / "decisions" / "p.json").write_text(json.dumps({"player": {"pick": "player_z", "note": ""}}))
        self.assertEqual(self.rev("apply", "--name", "p")[0], 1)

    def test_a_manual_approval_needs_the_kids_words(self):
        self.gen("concept", "--slot", "player", "--prompt", "toast knight")
        self.assertEqual(self.rev("decide", "player_a", "approved")[0], 1)
        self.assertEqual(self.rev("decide", "player_a", "approved", "--words", "yes that one!")[0], 0)

    # ---- 3D ----
    def test_3d_is_refused_until_the_kid_picks(self):
        self.gen("concept", "--slot", "player", "--prompt", "toast knight")
        code, _, err = self.gen("model", "--id", "player_a")
        self.assertEqual(code, 1)
        self.assertIn("only a picture the kid picked", err)
        self.assertEqual(self.posts("image-to-3d"), [])

    def test_the_picked_concept_becomes_a_model_once(self):
        self.two_concepts_picked()
        code, out, err = self.gen("model", "--slot", "player")
        self.assertEqual(code, 0, err)
        body = self.posts("image-to-3d")[0]
        self.assertEqual(body["model_type"], "smart-topology")
        self.assertEqual(body["target_polycount"], generate.SMART_TOPOLOGY_MAX, "20k × 0.85 is capped at T2's 15k")
        self.assertTrue(body["image_url"].startswith("data:image/png;base64,"), "sends the full-size concept")
        incoming = self.root / "assets" / "incoming"
        self.assertTrue((incoming / "player_b.glb").read_bytes().startswith(b"glTF"))
        self.assertTrue((incoming / "player_b.emission.png").exists())
        self.assertTrue((incoming / ".gdignore").exists(), "Godot must not import raw downloads")
        self.assertEqual(json.loads((incoming / "player_b.json").read_text())["slot"], "player")
        item = self.items()["player_b"]
        self.assertEqual(item["model_file"], "assets/incoming/player_b.glb")
        self.assertEqual(review.ledger_total(self.paths.ledger), 9 + 9 + 15)
        self.assertIn("make model-fit SLOT=player", out)
        # the same picture again is refused (it would pay twice), and allowed with a reason
        code, _, err = self.gen("model", "--id", "player_b")
        self.assertEqual(code, 1)
        self.assertIn("already went to 3D", err)
        self.assertEqual(self.gen("model", "--id", "player_b", "--retry", "the arms were fused")[0], 0)
        self.assertTrue((incoming / "player_b_2.glb").exists())
        self.assertEqual(self.rev("model-file", "--slot", "player")[1].strip(), "assets/incoming/player_b_2.glb")

    def test_high_quality_uses_meshy_6_and_costs_30(self):
        self.two_concepts_picked()
        self.assertEqual(self.gen("model", "--slot", "player", "--quality", "high")[0], 0)
        self.assertEqual(self.posts("image-to-3d")[0]["ai_model"], "meshy-6")
        self.assertEqual(review.ledger_total(self.paths.ledger), 9 + 9 + 30)

    def test_text_to_3d_without_a_concept(self):
        code, out, err = self.gen("text3d", "--slot", "prop_rock", "--prompt", "a lava rock", "--name", "rock_quick")
        self.assertEqual(code, 0, err)
        self.assertTrue((self.root / "assets" / "incoming" / "rock_quick.glb").exists())
        self.assertEqual(review.ledger_total(self.paths.ledger), 30)
        self.assertEqual(self.posts("text-to-3d")[0]["target_polycount"], 2550)

    # ---- failures ----
    def test_a_failed_task_is_logged_at_zero(self):
        code, _, err = self.gen("concept", "--slot", "prop_rock", "--prompt", "FAIL rock")
        self.assertEqual(code, 1)
        self.assertIn("FAILED", err)
        self.assertIn("| FAILED |", self.paths.ledger.read_text())
        self.assertEqual(review.ledger_total(self.paths.ledger), 0)
        self.assertEqual(self.items(), {})

    def test_rate_limits_are_retried(self):
        with mock.patch("time.sleep"):
            self.assertEqual(self.gen("concept", "--slot", "prop_rock", "--prompt", "RATELIMIT rock")[0], 0)

    def test_bad_key_and_no_credits_explain_themselves(self):
        with mock.patch.dict(os.environ, {"MESHY_API_KEY": "bad-key"}):
            code, _, err = self.gen("concept", "--slot", "prop_rock", "--prompt", "rock")
        self.assertEqual(code, 1)
        self.assertIn("API key was rejected", err)
        with mock.patch.dict(os.environ, {"MESHY_API_KEY": "broke"}):
            self.assertIn("out of credits", self.gen("concept", "--slot", "prop_rock", "--prompt", "rock")[2])

    def test_no_key_explains_how_to_get_one(self):
        with mock.patch.dict(os.environ, {"MESHY_API_KEY": ""}):
            code, _, err = self.gen("balance")
        self.assertEqual(code, 3)
        self.assertIn("keys.env", err)


class MockFilesTest(unittest.TestCase):
    def test_box_glb_is_a_valid_textured_gltf(self):
        data = mock_provider.box_glb(texture_px=64)
        magic, version, length = struct.unpack("<4sII", data[:12])
        self.assertEqual((magic, version, length), (b"glTF", 2, len(data)))
        json_length = struct.unpack("<I", data[12:16])[0]
        gltf = json.loads(data[20:20 + json_length])
        self.assertEqual(gltf["images"][0]["mimeType"], "image/png")
        self.assertEqual(gltf["accessors"][0]["max"], [10.0, 4.5, 15.0])

    def test_png_is_a_png(self):
        self.assertTrue(mock_provider.png(8, 8).startswith(b"\x89PNG\r\n\x1a\n"))


class LedgerTest(unittest.TestCase):
    def test_total_counts_reported_and_estimated_credits(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "ledger.md"
            review.ledger_append("text-to-image", {"id": "a", "status": "SUCCEEDED", "consumed_credits": 9}, "x", "", path)
            review.ledger_append("image-to-3d", {"id": "b", "status": "SUCCEEDED"}, "y | z", 100, path)
            review.ledger_append("image-to-3d", {"id": "c", "status": "FAILED"}, "y", 100, path)
            self.assertEqual(review.ledger_total(path), 9 + 15)
            self.assertIn("| ~15 |", path.read_text())


if __name__ == "__main__":
    unittest.main()
