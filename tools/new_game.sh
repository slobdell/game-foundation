#!/usr/bin/env bash
# Start a kid's game from this foundation:  make new-game NAME="Lava Lover" DIR=~/projects/lava-lover DIRECTOR=Sam
#
# - clones the foundation (so the new repo has a `foundation` remote to pull kit improvements from later),
# - names the game, leaves HANDOFF.md at "blank slate" so the kid's Claude starts with Day one,
# - marks the director's files merge=ours, so `make foundation-update` never overwrites their game,
# - shares this machine's Godot toolchain instead of downloading it again.
set -euo pipefail
NAME="${1:?usage: new_game.sh NAME DIR DIRECTOR}"; DIR="${2:?}"; DIRECTOR="${3:-}"
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${DIR/#\~/$HOME}"
if [ -e "$DIR" ]; then echo "new-game: $DIR already exists"; exit 1; fi
if [ -n "$(git -C "$SRC" status --porcelain)" ]; then
	echo "new-game: the foundation has uncommitted changes; commit them first so the game starts from a known commit"; exit 1
fi
git clone --quiet "$SRC" "$DIR"
cd "$DIR"
git remote rename origin foundation
git config merge.ours.driver true
# The director's own files: on a foundation update, keep the game's version whenever both sides changed.
cat >> .gitattributes <<'ATTR'
# The director's game: `make foundation-update` keeps these as they are in this repo.
HANDOFF.md merge=ours
README.md merge=ours
_agents/game_design.md merge=ours
_agents/art_direction.md merge=ours
_agents/teaching_notes.md merge=ours
_agents/roadmap.md merge=ours
data/** merge=ours
game/levels/** merge=ours
assets/** merge=ours
project.godot merge=ours
ATTR
python3 - "$NAME" "$DIRECTOR" <<'PY'
import re, sys
name, director = sys.argv[1], sys.argv[2]
p = "project.godot"; s = open(p).read()
s = s.replace('config/name="New Game"', 'config/name="%s"' % name.replace('"', ''))
open(p, "w").write(s)
p = "_agents/game_design.md"; s = open(p).read()
s = s.replace("Director: (first name or nickname only)", "Director: %s" % (director or "(first name or nickname only)"))
s = s.replace("Game title: (theirs)", "Game title: %s (working title; ask if they want to change it)" % name)
open(p, "w").write(s)
p = "README.md"; s = open(p).read()
s = re.sub(r"^# .*", "# %s" % name, s, count=1)
open(p, "w").write(s)
PY
if [ -d "$SRC/.tools" ] && [ ! -e .tools ]; then ln -s "$(readlink -f "$SRC/.tools")" .tools; fi
git add -A && git commit --quiet -m "Start $NAME from Game Foundation $(git -C "$SRC" rev-parse --short HEAD)"
echo ">> new game: $DIR  (foundation $(git -C "$SRC" rev-parse --short HEAD))"
echo "   next: cd $DIR && make check   then open Claude Code there; it starts with Day one."
