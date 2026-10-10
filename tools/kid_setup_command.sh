#!/usr/bin/env bash
# (Parent's computer) Print the ONE command that sets up a kid's Mac: it downloads tools/setup_mac.sh at the
# exact commit on GitHub (so what runs is what was reviewed) and passes the three keys in.
#   make kid-setup-command          (reads MESHY_API_KEY, ELEVENLABS_API_KEY, ELEVENLABS_KEY_ID from your shell)
# The output CONTAINS YOUR KEYS. Send it privately, and delete the message once the setup has run.
set -euo pipefail
cd "$(dirname "$0")/.."
missing=""
for var in MESHY_API_KEY ELEVENLABS_API_KEY ELEVENLABS_KEY_ID; do
	[ -n "${!var:-}" ] || missing="$missing $var"
done
[ -z "$missing" ] || { echo "not set in this shell:$missing  (open a new terminal so ~/.bashrc is loaded)" >&2; exit 1; }
git fetch -q origin main
sha=$(git rev-parse origin/main)
if ! git cat-file -e "$sha:tools/setup_mac.sh" 2>/dev/null; then
	echo "tools/setup_mac.sh is not on GitHub's main yet: commit and git push origin main first" >&2; exit 1
fi
if [ "$(git rev-parse HEAD)" != "$sha" ]; then
	echo "note: your local main differs from GitHub's; the command uses GitHub's $(git rev-parse --short "$sha")" >&2
fi
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
url="https://raw.githubusercontent.com/slobdell/game-foundation/$sha/tools/setup_mac.sh"
echo "# ---- Paste this whole line into Terminal on the kid's Mac (contains secret keys) ----" >&2
printf 'curl -fsSL %s -o /tmp/game-foundation-setup.sh && MESHY_API_KEY=%s ELEVENLABS_API_KEY=%s ELEVENLABS_KEY_ID=%s /bin/bash /tmp/game-foundation-setup.sh\n' \
	"$url" "$(q "$MESHY_API_KEY")" "$(q "$ELEVENLABS_API_KEY")" "$(q "$ELEVENLABS_KEY_ID")"
