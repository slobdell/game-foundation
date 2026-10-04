#!/usr/bin/env bash
# Run a windowed harness command (screenshots) and FAIL if it printed any engine/script error, even when it
# exited 0. Some engine errors (e.g. a failed Array.filter call) print to the console without reaching
# the game's ErrorWatch logger, so the console is checked too. Benign shutdown noise is allowed below.
# usage: tools/run_strict.sh <log file> <command...>
set -uo pipefail
log="$1"; shift
"$@" > "$log" 2>&1
status=$?
grep -E 'screenshot saved|RUNTIME ERRORS|^  [0-9]+x ' "$log"
errors=$(grep -E '^(ERROR|SCRIPT ERROR|USER ERROR)' "$log" \
	| grep -vE 'resources still in use at exit|ObjectDB instances leaked at exit' | sort | uniq -c | sort -rn)
if [ -n "$errors" ]; then
	echo "STRICT RUN FAILED: the game printed errors (full log: $log):"
	echo "$errors" | head -10
	exit 1
fi
exit $status
