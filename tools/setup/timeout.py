#!/usr/bin/env python3
"""Run a command, killing it (and anything it started) after N seconds: `timeout.py SECONDS cmd args...`.

The portable replacement for GNU `timeout` (macOS doesn't have it). Exit code 124 on timeout, like GNU timeout.
Python 3.9+, standard library only.
"""
import os
import signal
import subprocess
import sys


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: timeout.py SECONDS command [args...]", file=sys.stderr)
        return 2
    seconds, command = float(sys.argv[1]), sys.argv[2:]
    try:
        # Its own process group, so a timeout also stops whatever the command started.
        child = subprocess.Popen(command, start_new_session=True)
    except FileNotFoundError:
        print("timeout.py: command not found: %s" % command[0], file=sys.stderr)
        return 127

    def stop(signum, _frame):
        try:
            os.killpg(child.pid, signum)
        except ProcessLookupError:
            pass

    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, stop)
    try:
        code = child.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        print("timeout.py: '%s' took longer than %gs; stopped it" % (os.path.basename(command[0]), seconds),
              file=sys.stderr)
        stop(signal.SIGTERM, None)
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            stop(signal.SIGKILL, None)
            child.wait()
        return 124
    return 128 - code if code < 0 else code


if __name__ == "__main__":
    sys.exit(main())
