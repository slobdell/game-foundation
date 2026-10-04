#!/usr/bin/env python3
"""Add a level: copy game/levels/_template/template.tscn to game/levels/<id>/<id>.tscn and register it in
data/levels.json. Then open it in the editor (make editor) or have Claude add things to it."""
import argparse, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", required=True)
    ap.add_argument("--title", required=True)
    ap.add_argument("--music", default="")
    a = ap.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]*", a.id):
        print(f"level id '{a.id}' must be lowercase letters, digits and _ (like lava_fields)")
        return 1
    levels_path = ROOT / "data" / "levels.json"
    data = json.loads(levels_path.read_text())
    if a.id in data["levels"]:
        print(f"there is already a level called '{a.id}'")
        return 1
    scene = ROOT / "game" / "levels" / a.id / f"{a.id}.tscn"
    scene.parent.mkdir(parents=True, exist_ok=True)
    text = (ROOT / "game" / "levels" / "_template" / "template.tscn").read_text()
    text = text.replace('level_id = "template"', f'level_id = "{a.id}"')
    text = text.replace('[node name="Template"', '[node name="%s"' % "".join(w.capitalize() for w in a.id.split("_")))
    scene.write_text(text)
    data["levels"][a.id] = {"scene": f"res://game/levels/{a.id}/{a.id}.tscn", "title": a.title, "music": a.music}
    levels_path.write_text(json.dumps(data, indent=2) + "\n")
    print(f"made {scene.relative_to(ROOT)} and added '{a.id}' to data/levels.json")
    print(f"try it: make run LEVEL={a.id}   (screenshot: make shot LEVEL={a.id})")
    return 0

if __name__ == "__main__":
    sys.exit(main())
