#!/bin/bash
# One-time setup of a kid's Mac for Game Foundation. The parent renders the command that runs this
# (make kid-setup-command, on the parent's computer) and sends it; someone pastes it into Terminal on the Mac.
#
# What it does, in order (safe to run again: every step skips what's already done):
#   1. Apple's Command Line Tools (git, make). If missing, macOS shows an "Install" window: click Install.
#   2. Saves the Meshy and ElevenLabs keys to ~/.config/game-foundation/keys.env (only this user can read it)
#      and loads them in every new Terminal window.
#   3. Installs Claude Code (Anthropic's installer, into your home folder; no admin password).
#   4. Downloads the game starter into ~/my-game (or GAME_DIR) and installs its tools: Godot, Python, ffmpeg,
#      GitHub's gh (all inside that folder; no admin password).
#   5. Tells you the last step: open Terminal, `cd ~/my-game`, `claude`, and sign in (send Dad the link).
#
# Keys come in through the environment: MESHY_API_KEY, ELEVENLABS_API_KEY, ELEVENLABS_KEY_ID.
# Written for macOS's own /bin/bash 3.2: no bash-4 features.
set -u

REPO_URL="${GAME_FOUNDATION_REPO:-https://github.com/slobdell/game-foundation.git}"
GAME_DIR="${GAME_DIR:-$HOME/my-game}"
KEYS_DIR="$HOME/.config/game-foundation"
KEYS_FILE="$KEYS_DIR/keys.env"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31mSetup stopped: %s\033[0m\n' "$*"; printf 'Send a photo of this window to Dad.\n'; exit 1; }

if [ "$(uname -s)" != "Darwin" ] && [ -z "${SETUP_ALLOW_NON_MAC:-}" ]; then die "this script is for a Mac"; fi
if [ "$(id -u)" -eq 0 ]; then die "don't run this with sudo; paste the command exactly as it was sent"; fi

# Keep the Mac awake while big downloads run (macOS only; harmless if missing).
if command -v caffeinate >/dev/null 2>&1; then caffeinate -dimsu -w $$ >/dev/null 2>&1 & fi

say "Game Foundation setup for $(id -un). This takes 10-30 minutes (big downloads). Leave this window open."

# ---- 1. Command Line Tools (git, make) -----------------------------------------------------------
say "1/5  Apple's developer tools (git, make)"
if [ "$(uname -s)" = "Darwin" ] && ! xcode-select -p >/dev/null 2>&1; then
	warn "Not installed yet. A window will pop up: click Install, then Agree. (It may ask for this Mac's password.)"
	xcode-select --install >/dev/null 2>&1 || true
	printf '    waiting for the install to finish'
	n=0
	until xcode-select -p >/dev/null 2>&1 && /usr/bin/git --version >/dev/null 2>&1; do
		sleep 10; n=$((n + 1)); printf '.'
		if [ $n -ge 270 ]; then echo; die "the developer tools didn't finish installing within 45 minutes. Run the command again after they finish."; fi
	done
	echo
fi
command -v git >/dev/null 2>&1 || die "git is missing"
command -v make >/dev/null 2>&1 || die "make is missing"
ok "git $(git --version | awk '{print $3}'), make"

# ---- 2. Keys ------------------------------------------------------------------------------------------
say "2/5  Saving the art and sound keys"
for var in MESHY_API_KEY ELEVENLABS_API_KEY ELEVENLABS_KEY_ID; do
	eval "val=\${$var:-}"
	[ -n "$val" ] || die "the command is missing $var (ask Dad to make the command again)"
done
mkdir -p "$KEYS_DIR"
chmod 700 "$KEYS_DIR"
umask 077
{
	echo "# Game Foundation keys (from Dad). Secret: don't share or post this file."
	printf 'export MESHY_API_KEY=%q\n' "$MESHY_API_KEY"
	printf 'export ELEVENLABS_API_KEY=%q\n' "$ELEVENLABS_API_KEY"
	printf 'export ELEVENLABS_KEY_ID=%q\n' "$ELEVENLABS_KEY_ID"
} > "$KEYS_FILE"
chmod 600 "$KEYS_FILE"
umask 022
LOAD_LINE='[ -f "$HOME/.config/game-foundation/keys.env" ] && . "$HOME/.config/game-foundation/keys.env"'
for rc in "$HOME/.zshrc" "$HOME/.bash_profile"; do
	touch "$rc"
	grep -qF 'game-foundation/keys.env' "$rc" || printf '\n# Game Foundation keys\n%s\n' "$LOAD_LINE" >> "$rc"
done
ok "keys saved in $KEYS_FILE (readable only by $(id -un))"

# ---- 3. Claude Code -------------------------------------------------------------------------------------
say "3/5  Claude Code"
export PATH="$HOME/.local/bin:$PATH"
if command -v claude >/dev/null 2>&1; then
	ok "already installed ($(claude --version 2>/dev/null | head -1))"
else
	curl -fsSL https://claude.ai/install.sh | bash || die "Claude Code didn't install"
	command -v claude >/dev/null 2>&1 || die "Claude Code installed but the 'claude' command isn't found"
	ok "installed ($(claude --version 2>/dev/null | head -1))"
fi
for rc in "$HOME/.zshrc" "$HOME/.bash_profile"; do
	grep -qF '.local/bin' "$rc" || printf '\n# Claude Code\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
done

# ---- 4. The game starter and its tools ---------------------------------------------------------------
say "4/5  The game starter ($GAME_DIR)"
if [ -d "$GAME_DIR/.git" ]; then
	ok "already downloaded"
else
	[ -e "$GAME_DIR" ] && die "$GAME_DIR already exists but isn't the game. Move it away and run the command again."
	git clone -q "$REPO_URL" "$GAME_DIR" || die "couldn't download the game starter"
	ok "downloaded"
fi
cd "$GAME_DIR" || die "can't open $GAME_DIR"
say "     Installing the game tools: Godot, Python, ffmpeg, GitHub's gh (the slow part, ~1.5 GB)"
. "$KEYS_FILE"
make bootstrap || die "installing the game tools failed (the lines above say why)"
make gh >/dev/null || die "installing GitHub's gh tool failed"
ok "tools installed"
say "     Checking everything works (a few minutes)"
if make check > "$GAME_DIR/build/setup-check.log" 2>&1; then
	ok "all checks passed"
else
	warn "some checks failed: Claude will look at it (log: build/setup-check.log). Setup can still continue."
fi
make doctor 2>/dev/null | sed 's/^/    /'

# ---- 5. Last step ---------------------------------------------------------------------------------------
say "5/5  All set! Last step (with the kid):"
cat <<EOF

    1. Open a NEW Terminal window and type:     cd $GAME_DIR && claude
    2. Claude asks how to sign in: choose the Claude account (subscription) option.
       If a browser page opens on this Mac, CLOSE it. Don't sign in there.
       Copy the long link Claude shows in Terminal and send it to Dad. He approves it on HIS
       computer and sends you back a code. Paste the code into Terminal and press Enter.
       (Never type Dad's Google or Claude password on this Mac.)
    3. Say hi to Claude! It will help you name your game, connect it to YOUR GitHub
       account, and start building.

EOF
