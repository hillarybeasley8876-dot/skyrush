#!/usr/bin/env python3
"""fail_lines — run a Godot test and accept only the FAIL lines that are on an allow list.

    python tools/fail_lines.py <res://test.gd> [--allow REGEX ...] [--min-pass N] [--timeout 900] [--args "--timeout=300 --route=x"]

Runs `tools/gd.py test <test>` and reads its output.  Every line that starts with FAIL must match one of the --allow
regular expressions (re.search); lines that do not are printed as NEW FAIL.  At least --min-pass lines must start with PASS
(a test that crashes at the start prints none).  Engine errors (lines starting with SCRIPT ERROR or "ERROR:") and a test host timeout ("TEST TIMEOUT") count as new
FAIL lines unless allowed.
Prints FAIL_LINES OK (n allowed) or FAIL_LINES FAIL.  The exit code is 0 only for OK.
Use it for tests that have known failures that are not the job's business: the job must not add a failing check and must
fix the ones that are its own.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main(argv):
    test = argv[1]
    allow, min_pass, timeout, extra = [], 1, 900, []
    i = 2
    while i < len(argv):
        if argv[i] == "--args":
            extra = argv[i + 1].split()
            i += 2
        elif argv[i] == "--allow":
            allow.append(re.compile(argv[i + 1]))
            i += 2
        elif argv[i] == "--min-pass":
            min_pass = int(argv[i + 1])
            i += 2
        elif argv[i] == "--timeout":
            timeout = int(argv[i + 1])
            i += 2
        else:
            i += 1
    cmd = [sys.executable, str(ROOT / "tools" / "gd.py"), "test", test] + (["--"] + extra if extra else [])
    proc = subprocess.run(cmd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=timeout + 600)
    out = (proc.stdout or "") + (proc.stderr or "")
    passes = sum(1 for line in out.splitlines() if line.startswith("PASS"))
    allowed, new = 0, []
    for line in out.splitlines():
        if line.startswith(("FAIL", "SCRIPT ERROR", "ERROR:", "TEST TIMEOUT", "TEST ERROR")):
            if any(rx.search(line) for rx in allow):
                allowed += 1
            else:
                new.append(line)
    for line in new[:30]:
        print("NEW FAIL", line[:240])
    print("%d PASS lines, %d allowed FAIL lines, %d new" % (passes, allowed, len(new)))
    if passes < min_pass:
        print("FAIL_LINES FAIL: only %d PASS lines (need %d): the test did not run through" % (passes, min_pass))
        return 1
    if new:
        print("FAIL_LINES FAIL")
        return 1
    print("FAIL_LINES OK (%d allowed)" % allowed)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
