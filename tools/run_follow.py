#!/usr/bin/env python3
"""run_follow — drive every path file with the game's path-following autodrive and judge the run.

    python tools/run_follow.py <paths dir> [--only substring] [--out DIR] [--time-limit 90] [--with-traffic]

The trials are a test of the road (the geometry under a real car), so the traffic, the police and the rivals are stubbed:
a traffic car that stands on a ramp stops the car, and the trial reports a "stuck" road. --with-traffic runs them as the game does.

For each <paths dir>/*.json: `gd.py drive --follow=... --spawn=...` (a game window opens, one run at a time),
then the telemetry csv is judged:
  reached   the run printed "follow reached the end" (the car got to the end of the path)
  clean     lowest health >= 70 (no real collision on the way), no speed rise above 80 km/h between rows, no step above 10 m
  smooth    the car never slows below 12 km/h after the first 6 s (it did not get stuck or wedged)
Writes <out>/summary.json; prints one line per path. Exit 0 when every path is reached and clean and smooth.
"""
import csv
import json
import math
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def judge(csv_path, stdout):
    rows = list(csv.DictReader(open(csv_path, encoding="utf-8"))) if Path(csv_path).exists() else []
    if len(rows) < 20:
        return {"reached": False, "clean": False, "smooth": False, "why": ["no telemetry"]}
    why = []
    reached = "follow reached the end" in stdout
    if not reached:
        why.append("did not reach the end")
    health = min(float(r["health"]) for r in rows)
    prev, bad_step, bad_rise = None, 0.0, 0.0
    for r in rows:
        cur = (float(r["x"]), float(r["y"]), float(r["z"]), float(r["speed_kmh"]))
        if prev:
            bad_step = max(bad_step, math.dist(cur[:3], prev[:3]))
            bad_rise = max(bad_rise, cur[3] - prev[3])
        prev = cur
    clean = health >= 70 and bad_step <= 10 and bad_rise <= 80
    if not clean:
        why.append("health %.0f, biggest step %.1f m, biggest speed rise %.0f km/h" % (health, bad_step, bad_rise))
    late = [float(r["speed_kmh"]) for r in rows if float(r["t"]) > 6.0]
    smooth = bool(late) and min(late) >= 12.0
    if not smooth:
        why.append("slowest speed after 6 s is %.0f km/h (stuck?)" % (min(late) if late else -1))
    return {"reached": reached, "clean": clean, "smooth": smooth, "health": health, "why": why, "t_end": float(rows[-1]["t"])}


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    opt = lambda n, d: argv[argv.index(n) + 1] if n in argv else d  # noqa: E731
    only, out = opt("--only", ""), Path(opt("--out", str(ROOT.parent / "skyrush-out" / "follow")))
    with_traffic = "--with-traffic" in argv
    for n in ("--only", "--out", "--time-limit"):
        if n in argv:
            args.remove(argv[argv.index(n) + 1])
    out.mkdir(parents=True, exist_ok=True)
    paths = sorted(p for p in Path(args[0]).glob("*.json") if only in p.name)
    results, bad = {}, 0
    for p in paths:
        spec = json.loads(p.read_text(encoding="utf-8"))
        sp = spec["spawn"]
        csv_path = out / (p.stem + ".csv")
        t0 = time.time()
        proc = subprocess.run([sys.executable, str(ROOT / "tools" / "gd.py"), "drive", "--timeline=res://tools/timelines/follow_120s.json",
                               "--follow=" + p.as_posix(), "--spawn=%s,%s,%s,%s" % tuple(sp), "--skip-menu", "--log=" + csv_path.as_posix(), "--out=" + p.stem]
                              + ([] if with_traffic else ["--stub=traffic,police,rivals"]),
                              capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=900)
        verdict = judge(csv_path, (proc.stdout or "") + (proc.stderr or ""))
        results[p.stem] = verdict
        ok = verdict["reached"] and verdict["clean"] and verdict["smooth"]
        bad += 0 if ok else 1
        print("%-5s %-44s t=%5.1fs  %s" % ("ok" if ok else "FAIL", p.stem, verdict.get("t_end", 0.0), "; ".join(verdict["why"])), flush=True)
    (out / "summary.json").write_text(json.dumps(results, indent=1), encoding="utf-8")
    print("FOLLOW %d paths, %d not clean" % (len(paths), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
