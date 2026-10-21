#!/usr/bin/env python3
"""Machine-wide slot pool: run a command while holding one of N flock slots.

  slots.py <pool> <n> [--timeout SECS] -- <command...>
--timeout kills the command's process group after SECS (exit 124, prints "[slots] TIMEOUT").
Defaults per pool when omitted: light 300 s, import 900 s, heavy 600 s.
Pools used by SKYRUSH: heavy (Godot windowed runs + Blender renders, n=3), import (n=1, Godot imports).
Waits (printing a notice to stderr) until a slot is free; the slot is released when the command exits.
"""
import fcntl
import os
import signal
import subprocess
import sys
import time

DEFAULT_TIMEOUT = {"light": 300, "import": 900, "heavy": 600}

SLOT_DIR = os.path.expanduser("~/m/skyrush/jobs/.slots")


MAX_WAIT = 540  # give up before a caller's 10-min tool timeout, instead of piling up stale waiters


def acquire(pool, n):
    os.makedirs(SLOT_DIR, exist_ok=True)
    noted = False
    deadline = time.time() + MAX_WAIT
    while True:
        if time.time() > deadline:
            sys.stderr.write("[slots] gave up after %d s waiting for a free '%s' slot (machine busy) - retry later\n"
                             % (MAX_WAIT, pool))
            sys.exit(75)
        for i in range(n):
            fd = os.open(os.path.join(SLOT_DIR, "%s_%d.lock" % (pool, i)), os.O_CREAT | os.O_RDWR)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return fd
            except OSError:
                os.close(fd)
        if not noted:
            sys.stderr.write("[slots] waiting for a free '%s' slot (%d in use)...\n" % (pool, n))
            noted = True
        time.sleep(3)


def run(cmd, timeout):
    proc = subprocess.Popen(cmd, start_new_session=True)
    try:
        return proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        sys.stderr.write("[slots] TIMEOUT after %d s, killing: %s\n" % (timeout, " ".join(cmd)[:200]))
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
        return 124


def main():
    args = sys.argv[1:]
    if "--" not in args or len(args) < 4:
        sys.exit(__doc__)
    sep = args.index("--")
    pool, n, opts, cmd = args[0], int(args[1]), args[2:sep], args[sep + 1:]
    timeout = DEFAULT_TIMEOUT.get(pool, 600)
    if "--timeout" in opts:
        timeout = int(opts[opts.index("--timeout") + 1])
    fd = acquire(pool, n)
    try:
        sys.exit(run(cmd, timeout))
    finally:
        os.close(fd)


if __name__ == "__main__":
    main()
