#!/usr/bin/env bash
# (Parent / foundation side) Make a game folder for a kid on this computer:
#   make new-game NAME="Lava Lover" DIR=~/projects/lava-lover DIRECTOR=Sam
# The usual path is the kid cloning the foundation from GitHub themselves; their Claude then runs
# start-my-game (the setup-my-game skill). This does the same thing from a local clone, and is what
# make foundation-selftest uses.
set -euo pipefail
NAME="${1:?usage: new_game.sh NAME DIR DIRECTOR}"; DIR="${2:?}"; DIRECTOR="${3:-}"
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${DIR/#\~/$HOME}"
if [ -e "$DIR" ]; then echo "new-game: $DIR already exists"; exit 1; fi
if [ -n "$(git -C "$SRC" status --porcelain)" ]; then
	echo "new-game: the foundation has uncommitted changes; commit them first so the game starts from a known commit"; exit 1
fi
git clone --quiet "$SRC" "$DIR"
if [ -d "$SRC/.tools" ] && [ ! -e "$DIR/.tools" ]; then ln -s "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SRC/.tools")" "$DIR/.tools"; fi
"$DIR/tools/start_my_game.sh" "$NAME" "$DIRECTOR"
echo ">> new game: $DIR"
