#!/usr/bin/env bash
# GitHub for a kid's game, run by Claude (see _agents/git.md). The kid's GitHub sign-in is kept INSIDE this game
# folder (.gh/, git-ignored) and wired into this repo only, so it never mixes with a parent's (or a sibling's)
# GitHub account on the same computer.
#
#   tools/github.sh status            signed in? as whom? own repo? last backup?
#   tools/github.sh login             starts the browser sign-in in the background, prints the one-time code
#   tools/github.sh create <repo>     makes <login>/<repo> PRIVATE on GitHub, makes it `origin`, pushes
#   tools/github.sh backup            pushes the current branch to origin
#   tools/github.sh sync              fetches origin and fast-forwards if GitHub has newer work
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GH="${GH:-.tools/gh-2.102.0/bin/gh}"
GH="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$GH")"  # readlink -f is missing on older Macs
export GH_CONFIG_DIR="$ROOT/.gh"
export GH_PROMPT_DISABLED=1
mkdir -p "$GH_CONFIG_DIR"; chmod 700 "$GH_CONFIG_DIR"

signed_in() { "$GH" auth status --hostname github.com >/dev/null 2>&1; }
login_name() { "$GH" api user --jq .login 2>/dev/null; }

# Use THIS folder's sign-in for github.com pushes and pulls, and nothing from the computer's global git config.
wire_git() {
	git config --local --unset-all credential.https://github.com.helper 2>/dev/null || true
	git config --local --add credential.https://github.com.helper ""
	git config --local --add credential.https://github.com.helper "!GH_CONFIG_DIR='$GH_CONFIG_DIR' '$GH' auth git-credential"
	# Commits are signed with the kid's GitHub name and private no-reply address (never a real email).
	local login id
	login=$(login_name); id=$("$GH" api user --jq .id 2>/dev/null)
	if [ -n "$login" ] && [ -n "$id" ]; then
		git config --local user.name "$login"
		git config --local user.email "$id+$login@users.noreply.github.com"
	fi
}

case "${1:-status}" in
status)
	if signed_in; then echo "github: signed in as $(login_name)"; else echo "github: NOT signed in (make github-login)"; fi
	origin=$(git remote get-url origin 2>/dev/null || true)
	if [ -z "$origin" ]; then echo "repo:   no GitHub repo of its own yet (make github-create REPO=<name>)"
	else
		echo "repo:   $origin"
		git fetch -q origin 2>/dev/null && {
			branch=$(git branch --show-current)
			ahead=$(git rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo "?")
			behind=$(git rev-list --count "HEAD..origin/$branch" 2>/dev/null || echo "?")
			echo "backup: $ahead commit(s) not backed up yet, $behind newer on GitHub"
		} || echo "backup: could not reach GitHub (offline, or not signed in)"
	fi
	foundation=$(git remote get-url foundation 2>/dev/null || true)
	echo "kit:    ${foundation:-no foundation remote}"
	;;
login)
	if signed_in; then echo "github: already signed in as $(login_name)"; wire_git; exit 0; fi
	log="$ROOT/build/github-login.log"; mkdir -p "$ROOT/build"; : > "$log"
	# In the background: it waits until the kid approves the code in their browser, then saves the sign-in here.
	GH_BROWSER=true nohup "$GH" auth login --web --hostname github.com --git-protocol https --skip-ssh-key \
		< /dev/null > "$log" 2>&1 &
	for _ in $(seq 1 30); do grep -q "code" "$log" && break; sleep 0.5; done
	code=$(grep -oE '[A-Z0-9]{4}-[A-Z0-9]{4}' "$log" | head -1)
	if [ -z "$code" ]; then echo "github login FAILED to start:"; cat "$log"; exit 1; fi
	echo "GITHUB CODE: $code"
	echo "The kid opens https://github.com/login/device (signed in to THEIR GitHub account), types the code, and"
	echo "clicks Authorize. Then run: make github-status   (it says 'signed in as ...' once it worked)"
	;;
create)
	repo="${2:?usage: github.sh create <repo-name>}"
	signed_in || { echo "not signed in to GitHub yet: make github-login first"; exit 1; }
	wire_git
	if git remote get-url origin >/dev/null 2>&1; then echo "this game already has a GitHub repo: $(git remote get-url origin)"; exit 1; fi
	git remote get-url foundation >/dev/null 2>&1 || { echo "run make start-my-game first (no foundation remote)"; exit 1; }
	"$GH" repo create "$repo" --private --source=. --remote=origin --push \
		--description "My game, made with Game Foundation" || exit 1
	git branch --set-upstream-to="origin/$(git branch --show-current)" >/dev/null 2>&1 || true
	echo ">> github: https://github.com/$(login_name)/$repo (private) is this game's backup"
	;;
backup)
	git remote get-url origin >/dev/null 2>&1 || { echo "no GitHub repo yet: make github-create REPO=<name>"; exit 1; }
	signed_in && wire_git
	branch=$(git branch --show-current)
	[ -z "$(git status --porcelain)" ] || echo "note: there are changes not committed yet; only commits are backed up"
	git push -q origin "$branch" && echo ">> backup: pushed $branch to $(git remote get-url origin) ($(git rev-parse --short HEAD))"
	;;
sync)
	git remote get-url origin >/dev/null 2>&1 || { echo "no GitHub repo yet; nothing to sync"; exit 0; }
	signed_in && wire_git
	git fetch -q origin || { echo "could not reach GitHub"; exit 1; }
	branch=$(git branch --show-current)
	behind=$(git rev-list --count "HEAD..origin/$branch" 2>/dev/null || echo 0)
	if [ "$behind" = "0" ]; then echo ">> sync: up to date with GitHub"; exit 0; fi
	git merge --ff-only -q "origin/$branch" && echo ">> sync: got $behind newer commit(s) from GitHub" \
		|| { echo "sync: this computer AND GitHub both have new work; they need merging (see _agents/git.md)"; exit 1; }
	;;
*) echo "usage: github.sh status|login|create <repo>|backup|sync"; exit 2 ;;
esac
