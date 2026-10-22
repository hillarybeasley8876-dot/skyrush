#!/usr/bin/env python3
"""run_tests — run every Godot test through tools/gd.py and summarise the result.

    python tools/run_tests.py [--filter substring] [--jobs 5] [--timeout 300] [--out DIR] [--list]

Each test's output goes to <out>/<name>.log; <out>/summary.json has one record per test
(exit code, checks, failures, seconds, the first failing lines) so two runs can be compared.
Exit code 0 only when every test exited 0.
"""
import json
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJ = ROOT / "game"
SKIP = {"test_host.gd"}


def discover(filt):
    out = []
    for path in sorted(PROJ.rglob("test_*.gd")):
        if ".godot" in path.parts or path.name in SKIP:
            continue
        res = "res://" + path.relative_to(PROJ).as_posix()
        if filt and filt not in res:
            continue
        out.append(res)
    return out


CRASH_AT_EXIT = (4294967295, -1)   # Godot exits with -1 at shutdown on a busy machine, after the verdict was printed


def run_once(res, timeout):
    try:
        proc = subprocess.run([sys.executable, str(ROOT / "tools" / "gd.py"), "test", res], capture_output=True,
                              text=True, encoding="utf-8", errors="replace", timeout=timeout + 600)
        return (proc.stdout or "") + (proc.stderr or ""), proc.returncode
    except subprocess.TimeoutExpired as exc:
        return (exc.stdout or b"").decode("utf-8", "replace") if isinstance(exc.stdout, bytes) else (exc.stdout or ""), 124


def run_one(res, out_dir, timeout):
    name = res.replace("res://", "").replace("/", "__").replace(".gd", "")
    t0 = time.time()
    text, code = run_once(res, timeout)
    retries = 0
    # a clean verdict followed by a crash at exit is a flake, not a failure: look again (twice at most)
    while code in CRASH_AT_EXIT and retries < 2 and not any(l.startswith("FAIL") for l in text.splitlines()):
        retries += 1
        text, code = run_once(res, timeout)
    secs = time.time() - t0
    (out_dir / (name + ".log")).write_text(text, encoding="utf-8")
    checks = failures = 0
    m = re.search(r"TEST [\w.\-]+: (\d+) checks?, (\d+) failures?", text)
    if m:
        checks, failures = int(m.group(1)), int(m.group(2))
    fails = [l.strip() for l in text.splitlines() if l.startswith(("FAIL", "SCRIPT ERROR", "ERROR:"))][:5]
    return res, {"exit": code, "checks": checks, "failures": failures, "secs": round(secs, 1), "first_fails": fails, "retries": retries,
                 "passed_lines": sum(1 for l in text.splitlines() if l.startswith("PASS"))}


def main(argv):
    def opt(name, default):
        return argv[argv.index(name) + 1] if name in argv else default

    tests = discover(opt("--filter", ""))
    if "--list" in argv:
        print("\n".join(tests))
        return 0
    out_dir = Path(opt("--out", str(ROOT.parent / "skyrush-out" / "tests" / "latest")))
    out_dir.mkdir(parents=True, exist_ok=True)
    jobs, timeout = int(opt("--jobs", "5")), int(opt("--timeout", "300"))
    print("running %d tests, %d at a time -> %s" % (len(tests), jobs, out_dir), flush=True)
    results = {}
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        for res, rec in pool.map(lambda r: run_one(r, out_dir, timeout), tests):
            results[res] = rec
            flag = "ok  " if rec["exit"] == 0 else ("TIME" if rec["exit"] == 124 else "FAIL")
            print("%s %-62s checks=%-3d fail=%-3d %5.0fs" % (flag, res[6:], rec["checks"], rec["failures"], rec["secs"]), flush=True)
    (out_dir / "summary.json").write_text(json.dumps(results, indent=1, ensure_ascii=False), encoding="utf-8")
    bad = [r for r, v in results.items() if v["exit"] != 0]
    print("\n%d tests, %d passed, %d failed or timed out" % (len(results), len(results) - len(bad), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
