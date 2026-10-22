#!/usr/bin/env python3
"""mutation_check — a new test must FAIL on the code as it was before the fix.

    python tools/mutation_check.py --test res://ai/traffic/tests/test_layers.gd --files game/ai/traffic/traffic_player_events.gd game/ai/traffic/traffic_lane_change.gd [--base REF] [--expect "text"]

For every file in --files the version of the job's base commit (REF, default: the merge base of HEAD with improve/openworld)
is written over the working copy, the test is run (`tools/gd.py test <res path>`), and the working copies are put back
(also when the run crashes).  Files that do not exist at the base are removed for the run.
Prints MUTATION_CHECK OK when the test failed on the old code (exit code != 0, and a line starting with FAIL, and
--expect found in the output if given), and the test also passes again on the restored code is NOT judged here (a separate
acceptance step runs it).  Prints MUTATION_CHECK FAIL <why> otherwise.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT)] + list(args), capture_output=True, text=True, encoding="utf-8", errors="replace")


def main(argv):
    def opt(name, default=None):
        return argv[argv.index(name) + 1] if name in argv else default
    test = opt("--test")
    base = opt("--base")
    expect = opt("--expect")
    files = []
    if "--files" in argv:
        i = argv.index("--files") + 1
        while i < len(argv) and not argv[i].startswith("--"):
            files.append(argv[i])
            i += 1
    if not test or not files:
        print("MUTATION_CHECK FAIL usage: --test res://... --files a.gd b.gd")
        return 2
    if base is None:
        res = git("merge-base", "HEAD", "improve/openworld")
        if res.returncode != 0:
            print("MUTATION_CHECK FAIL cannot find the merge base: %s" % res.stderr.strip())
            return 2
        base = res.stdout.strip()
    saved = {}
    try:
        for name in files:
            path = ROOT / name
            saved[name] = path.read_bytes() if path.exists() else None
            old = subprocess.run(["git", "-C", str(ROOT), "show", "%s:%s" % (base, name)], capture_output=True)
            if old.returncode == 0:
                path.write_bytes(old.stdout)
            elif path.exists():
                path.unlink()
        proc = subprocess.run([sys.executable, str(ROOT / "tools" / "gd.py"), "test", test], capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=1500)
        out = (proc.stdout or "") + (proc.stderr or "")
    finally:
        for name, data in saved.items():
            path = ROOT / name
            if data is None:
                if path.exists():
                    path.unlink()
            else:
                path.write_bytes(data)
    fails = [line for line in out.splitlines() if line.startswith("FAIL")]
    if proc.returncode == 0:
        print("MUTATION_CHECK FAIL the test PASSES on the code of %s: it does not test the fix" % base[:10])
        return 1
    if not fails:
        print("MUTATION_CHECK FAIL the test failed on the old code without a FAIL line (a crash, not a finding):")
        print("\n".join(out.splitlines()[-12:]))
        return 1
    if expect and expect not in out:
        print("MUTATION_CHECK FAIL the old code failed, but not with %r" % expect)
        return 1
    print("MUTATION_CHECK OK: the test fails on the old code of %s (%d FAIL lines, first: %s)" % (base[:10], len(fails), fails[0][:120]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
