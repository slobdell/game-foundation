#!/usr/bin/env python3
"""Run a command while holding an exclusive lock on a file: `lock.py LOCKFILE cmd args...`.

The portable replacement for `flock LOCKFILE cmd` (flock is Linux-only). Waits for the lock, runs the command
with the same stdin/stdout/stderr, exits with its exit code. Two headless Godots in one checkout corrupt the
.godot/ cache, so every headless Godot run in the Makefile goes through this. Python 3.9+, standard library only.
"""
import fcntl
import os
import signal
import subprocess
import sys


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: lock.py LOCKFILE command [args...]", file=sys.stderr)
        return 2
    lock_path, command = sys.argv[1], sys.argv[2:]
    os.makedirs(os.path.dirname(os.path.abspath(lock_path)), exist_ok=True)
    with open(lock_path, "a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            child = subprocess.Popen(command)
        except FileNotFoundError:
            print("lock.py: command not found: %s" % command[0], file=sys.stderr)
            return 127
        # Pass Ctrl-C / termination on to the child, then report the way a shell would.
        for sig in (signal.SIGINT, signal.SIGTERM):
            signal.signal(sig, lambda signum, _frame: child.send_signal(signum))
        code = child.wait()
    return 128 - code if code < 0 else code


if __name__ == "__main__":
    sys.exit(main())
