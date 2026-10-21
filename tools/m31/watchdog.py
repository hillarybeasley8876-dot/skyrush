#!/usr/bin/env python3
"""Background watchdog for M3.1 jobs (lead tool). Every 120 s:
- a job whose last error says the context window overflowed, or whose live context passed 900k tokens,
  is restarted in a fresh session (checkpoint + brief + "continue the current round") via feedback;
- prints one line per action to jobs/.watchdog.log.
Run: nohup python3 tools/m31/watchdog.py >/dev/null 2>&1 &"""
import json
import os
import signal
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
JOBS = os.path.join(ROOT, "jobs")
sys.path.insert(0, os.path.dirname(__file__))
import ctx  # noqa: E402

LOG = os.path.join(JOBS, ".watchdog.log")
LIMIT = 900000
NOTE = ("Your previous session reached M3.1's context limit and was closed automatically (not an error in your work). "
        "Continue the CURRENT round: read status/{job}.md, the newest reviews/{job}-r*.md (every MUST-FIX still open) and "
        "reviews/{job}-lead.md, check what is already on disk, finish, verify, update status, report with evidence.")


def log(msg):
    with open(LOG, "a") as f:
        f.write(time.strftime("%H:%M:%S ") + msg + "\n")


def restart(job, state):
    for key in ("sup_pid", "pid"):
        pid = state.get(key)
        if pid:
            try:
                os.killpg(pid, signal.SIGKILL) if key == "pid" else os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
    time.sleep(3)
    out = subprocess.run([sys.executable, os.path.join(ROOT, "tools/m31/m31.py"), "feedback", job, "--text",
                          NOTE.format(job=job)], capture_output=True, text=True)
    log("restarted %s fresh: %s %s" % (job, out.stdout.strip(), out.stderr.strip()[:200]))


def main():
    while True:
        for job in sorted(d for d in os.listdir(JOBS) if not d.startswith(".")):
            try:
                state, size = ctx.last_context(job)
            except (OSError, ValueError):
                continue
            err = state.get("error") or ""
            overflow = "context window exceeds" in err or "(2013)" in err
            if state.get("status") in ("running", "backoff") and (overflow or size > LIMIT):
                restart(job, state)
        time.sleep(120)


if __name__ == "__main__":
    main()
