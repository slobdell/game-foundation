#!/usr/bin/env bash
# Turn a fresh clone of Game Foundation into the kid's own game, in place:
#   - the clone's `origin` (the foundation) is renamed `foundation`, so kit improvements can be pulled later
#     (make foundation-update) and `origin` is free for the kid's own GitHub repo (make github-create),
#   - the director's files are marked merge=ours, so foundation updates never overwrite their game,
#   - the game gets its name, and the design doc gets the director's name.
# usage: tools/start_my_game.sh "Lava Lover" Sam
set -euo pipefail
NAME="${1:?usage: start_my_game.sh NAME [DIRECTOR]}"; DIRECTOR="${2:-}"
cd "$(dirname "$0")/.."
if git remote get-url foundation >/dev/null 2>&1; then echo "start-my-game: already done (this repo has a foundation remote)"; exit 1; fi
if [ "$(git config --get foundation.maintainer || true)" = "true" ]; then
	echo "start-my-game: this is the foundation's own maintenance checkout; use make new-game to make a game"; exit 1
fi
[ -z "$(git status --porcelain)" ] || { echo "start-my-game: there are uncommitted changes; commit or discard them first"; exit 1; }
if git remote get-url origin >/dev/null 2>&1; then git remote rename origin foundation; fi
git config merge.ours.driver true
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
base=$(git rev-parse --short HEAD)
git add -A
git -c user.name="${DIRECTOR:-director}" -c user.email="${DIRECTOR:-director}@localhost" commit -q -m "Start $NAME from Game Foundation $base"
echo ">> $NAME is set up (from foundation $base). Next: make github-login, then make github-create REPO=<name>."
