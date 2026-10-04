"""Tests for the choices pages: the spec check, the page build, and reading the taps back. No network, no browser.

    python3 -m unittest discover -s tools/pages -p 'test_*.py'      # (make py-test runs it)
"""

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import apply_choices  # noqa: E402
import choices_page  # noqa: E402
import make_demo  # noqa: E402


def spec(**over):
    s = {"name": "hero", "title": "Hero picks", "intro": "Tap one.",
         "questions": [
             {"id": "colour", "kind": "pick_one", "prompt": "Colour?",
              "options": [{"id": "red", "label": "Red"}, {"id": "blue", "label": "Blue", "note": "calm"}]},
             {"id": "powers", "kind": "pick_many", "prompt": "Powers?",
              "options": [{"id": "fly", "label": "Fly"}, {"id": "swim", "label": "Swim"}, {"id": "dig", "label": "Dig"}]},
             {"id": "song", "kind": "keep_redo", "prompt": "Keep the song?",
              "options": [{"id": "v1", "label": "Song, try 1", "text": "la la"}]},
         ]}
    s.update(over)
    return s


class Base(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)


class SpecCheck(Base):
    def bad(self, s, words):
        with self.assertRaises(choices_page.SpecError) as cm:
            choices_page.validate(s, self.root)
        self.assertIn(words, str(cm.exception))

    def test_good_spec_passes(self):
        choices_page.validate(spec(), self.root)

    def test_name_must_be_a_slug(self):
        self.bad(spec(name="My Page"), "slug")

    def test_question_id_must_be_a_db_path_segment(self):
        s = spec()
        s["questions"][0]["id"] = "hero/colour"
        self.bad(s, "database path")

    def test_unknown_kind(self):
        s = spec()
        s["questions"][0]["kind"] = "pick_two"
        self.bad(s, "kind must be one of")

    def test_pick_one_needs_two_options(self):
        s = spec()
        s["questions"][0]["options"] = s["questions"][0]["options"][:1]
        self.bad(s, "at least 2 options")

    def test_keep_redo_may_have_one_option(self):
        choices_page.validate(spec(), self.root)  # "song" has one

    def test_duplicate_ids(self):
        s = spec()
        s["questions"][1]["id"] = "colour"
        self.bad(s, "used twice")
        s = spec()
        s["questions"][0]["options"][1]["id"] = "red"
        self.bad(s, "used twice")

    def test_missing_media_file(self):
        s = spec()
        s["questions"][0]["options"][0]["image"] = "art/nope.png"
        self.bad(s, "image file not found")

    def test_wrong_media_type(self):
        (self.root / "x.txt").write_text("hi")
        s = spec()
        s["questions"][0]["options"][0]["audio"] = "x.txt"
        self.bad(s, "audio must be one of")


class Build(Base):
    def media_spec(self):
        make_demo.write_png(self.root / "red.png", 40, 30, lambda x, y: (200, 10, 10))
        make_demo.tone(self.root / "boing.wav", [(300, 600, 0.05)])
        s = spec()
        s["questions"][0]["options"][0]["image"] = "red.png"
        s["questions"][0]["options"][1]["audio"] = "boing.wav"
        return s

    def page_data(self, index: Path) -> dict:
        text = index.read_text()
        start = text.index('id="page-data">') + len('id="page-data">')
        return json.loads(text[start:text.index("</script>", start)].replace("<\\/", "</"))

    def test_embeds_media_and_writes_publish_args(self):
        publish = choices_page.build(self.media_spec(), self.root / "out", self.root, convert=False)
        index = self.root / "out" / "hero" / "index.html"
        data = self.page_data(index)
        opt = data["questions"][0]["options"]
        self.assertTrue(opt[0]["image"].startswith("data:image/png;base64,"))
        self.assertTrue(opt[1]["audio"].startswith("data:audio/wav;base64,"))
        self.assertEqual(opt[1]["note"], "calm")
        self.assertEqual(publish["capabilities"], {"db": {}})
        self.assertNotIn("files", publish)
        saved = json.loads((self.root / "out" / "hero" / "publish.json").read_text())
        self.assertEqual(saved["file_path"], "out/hero/index.html")
        text = index.read_text()
        self.assertTrue(text.startswith("<meta charset"), "the Artifact skeleton supplies doctype/head/body")
        self.assertIn("<title>Hero picks</title>", text[:8000])
        self.assertIn('db.doc("choices/" + q.id)', text)

    def test_media_beside_the_page_when_asked(self):
        publish = choices_page.build(self.media_spec(), self.root / "out", self.root, convert=False, embed="never")
        data = self.page_data(self.root / "out" / "hero" / "index.html")
        self.assertEqual(data["questions"][0]["options"][0]["image"], "media/colour--red.png")
        self.assertEqual(publish["files"]["media/colour--red.png"], "out/hero/media/colour--red.png")
        self.assertTrue((self.root / "out" / "hero" / "media" / "colour--blue.wav").exists())

    def test_script_cannot_be_closed_by_spec_text(self):
        s = spec(title="</script><b>hi</b>")
        choices_page.build(s, self.root / "out", self.root, convert=False)
        text = (self.root / "out" / "hero" / "index.html").read_text()
        self.assertNotIn("</script><b>", text)
        self.assertEqual(self.page_data(self.root / "out" / "hero" / "index.html")["title"], "</script><b>hi</b>")

    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg not installed")
    def test_wav_becomes_mp3_with_ffmpeg(self):
        choices_page.build(self.media_spec(), self.root / "out", self.root, convert=True)
        data = self.page_data(self.root / "out" / "hero" / "index.html")
        self.assertTrue(data["questions"][0]["options"][1]["audio"].startswith("data:audio/mpeg;base64,"))


class Apply(Base):
    def setUp(self):
        super().setUp()
        self.spec_path = self.root / "hero.spec.json"
        self.spec_path.write_text(json.dumps(spec()))
        self.decisions = self.root / "decisions"

    def run_apply(self, dump):
        return apply_choices.apply("hero", dump, self.decisions, self.spec_path)

    def test_out_dir_dump(self):
        d = self.root / "taps" / "choices"
        d.mkdir(parents=True)
        (d / "colour.json").write_text(json.dumps({"pick": "blue", "note": " so calm ", "at": "2026-10-04T10:00:00Z"}))
        (d / "powers.json").write_text(json.dumps({"pick": ["fly", "dig"], "note": "", "at": "t"}))
        (d / "song.json").write_text(json.dumps({"pick": "redo", "note": "faster", "at": "t"}))
        target, found, warnings = self.run_apply(self.root / "taps")
        self.assertEqual(warnings, [])
        out = json.loads(target.read_text())
        self.assertEqual(out, {
            "colour": {"pick": "blue", "note": "so calm", "at": "2026-10-04T10:00:00Z"},
            "powers": {"pick": ["fly", "dig"], "note": "", "at": "t"},
            "song": {"pick": "redo", "note": "faster", "at": "t"},
        })
        self.assertEqual(list(out), ["colour", "powers", "song"])

    def test_wrapped_documents_in_one_file(self):
        f = self.root / "read.json"
        f.write_text(json.dumps({"documents": [
            {"id": "colour", "version": 3, "data": {"pick": "red", "note": "", "at": "t"}},
            {"path": "choices/powers", "data": {"pick": "swim", "note": "", "at": "t"}},
        ], "next_cursor": None}))
        _, found, _ = self.run_apply(f)
        self.assertEqual(found["colour"]["pick"], "red")
        self.assertEqual(found["powers"]["pick"], ["swim"], "pick_many always records a list")

    def test_plain_mapping_and_list(self):
        f = self.root / "read.json"
        f.write_text(json.dumps({"colour": {"pick": "red", "note": "", "at": "t"}}))
        self.assertEqual(self.run_apply(f)[1]["colour"]["pick"], "red")
        f.write_text(json.dumps([{"doc_id": "song", "data": {"pick": "keep", "at": "t"}}]))
        self.assertEqual(self.run_apply(f)[1]["song"]["pick"], "keep")

    def test_unpicked_skipped_note_only_kept_unknown_warned(self):
        f = self.root / "read.json"
        f.write_text(json.dumps({
            "colour": {"pick": "", "note": "", "at": "t"},
            "powers": {"pick": [], "note": "none of these, I want lasers", "at": "t"},
            "song": {"pick": "maybe", "note": "", "at": "t"},
            "ghost": {"pick": "x", "at": "t"},
        }))
        _, found, warnings = self.run_apply(f)
        self.assertNotIn("colour", found)
        self.assertEqual(found["powers"], {"pick": [], "note": "none of these, I want lasers", "at": "t"})
        self.assertIn("song", found)
        self.assertTrue(any("ghost" in w for w in warnings))
        self.assertTrue(any("'maybe'" in w for w in warnings))

    def test_merges_with_earlier_answers(self):
        self.decisions.mkdir()
        (self.decisions / "hero.json").write_text(json.dumps({"colour": {"pick": "red", "note": "", "at": "old"},
                                                               "song": {"pick": "redo", "note": "", "at": "old"}}))
        f = self.root / "read.json"
        f.write_text(json.dumps({"song": {"pick": "keep", "note": "", "at": "new"}}))
        target, _, _ = self.run_apply(f)
        out = json.loads(target.read_text())
        self.assertEqual(out["colour"]["at"], "old")
        self.assertEqual(out["song"]["pick"], "keep")

    def test_empty_folder_is_an_error(self):
        (self.root / "empty").mkdir()
        with self.assertRaises(apply_choices.DumpError):
            self.run_apply(self.root / "empty")

    def test_no_spec_still_records(self):
        f = self.root / "read.json"
        f.write_text(json.dumps({"colour": {"pick": "red", "at": "t"}, "powers": {"pick": ["a"], "at": "t"}}))
        target, found, warnings = apply_choices.apply("hero", f, self.decisions, self.root / "missing.json")
        self.assertEqual(found["powers"]["pick"], ["a"])
        self.assertTrue(any("no spec" in w for w in warnings))


if __name__ == "__main__":
    unittest.main()
