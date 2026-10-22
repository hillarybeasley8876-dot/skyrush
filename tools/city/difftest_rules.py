#!/usr/bin/env python3
"""difftest_rules — old checkout versus new checkout: do ALL validator rules print identical results?

    python difftest_rules.py <old repo root> <new repo root> <city.json> [<city.json> ...] [--jobs 3]

Runs `tools/city/one_rule.py <map> --max 100000` in both checkouts on every map (in parallel) and compares the
text. Used by the lead to accept a change of the validator that must not change any verdict.
"""
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor


def run(root, city):
    t0 = time.time()
    p = subprocess.run([sys.executable, root + "/tools/city/one_rule.py", city, "--max", "100000"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    return p.stdout + p.stderr, time.time() - t0


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    jobs = int(argv[argv.index("--jobs") + 1]) if "--jobs" in argv else 3
    if "--jobs" in argv:
        args.remove(argv[argv.index("--jobs") + 1])
    old, new, maps = args[0], args[1], args[2:]
    tasks = [(root, m) for m in maps for root in (old, new)]
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        results = list(pool.map(lambda t: run(*t), tasks))
    bad = 0
    for i, m in enumerate(maps):
        (a, ta), (b, tb) = results[2 * i], results[2 * i + 1]
        same = a == b
        fails = sum(1 for l in a.splitlines() if l.startswith("FAIL"))
        print("%-6s %-26s rules failing: %d   old %.0fs  new %.0fs  (%d lines)" % ("SAME" if same else "DIFF", m.split("/")[-1], fails, ta, tb, len(a.splitlines())))
        if not same:
            bad += 1
            al, bl = a.splitlines(), b.splitlines()
            shown = 0
            for x, y in zip(al, bl):
                if x != y and shown < 5:
                    print("   old: %s\n   new: %s" % (x[:160], y[:160]))
                    shown += 1
            if len(al) != len(bl):
                print("   line counts differ: old %d new %d" % (len(al), len(bl)))
    print("DIFFTEST %s" % ("FAIL (%d maps differ)" % bad if bad else "OK (all maps identical)"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
