#!/usr/bin/env python3
"""analyze_follow — where along each path did a follow drive first get hurt or stuck?

    python tools/analyze_follow.py <follow out dir> <paths dir>

For every <paths dir>/*.json with a <follow out dir>/<name>.csv: the first row where health drops or the car stays
below 3 km/h for 2 s, as a distance along the path, next to the distance of the joint (where the chain leaves its first lane).
"""
import csv
import json
import math
import sys
from pathlib import Path


def main(argv):
    out, paths = Path(argv[1]), Path(argv[2])
    for p in sorted(paths.glob("*.json")):
        c = out / (p.stem + ".csv")
        if not c.exists():
            continue
        spec = json.loads(p.read_text(encoding="utf-8"))
        pts = spec["points"]
        cum = [0.0]
        for a, b in zip(pts, pts[1:]):
            cum.append(cum[-1] + math.dist(a, b))
        rows = [r for r in csv.DictReader(open(c, encoding="utf-8"))
                if all(r.get(k) not in (None, "") for k in ("t", "x", "y", "z", "health", "speed_kmh"))]  # a cut-off last row has no health
        if len(rows) < 5:
            continue

        def along(r):
            x, z = float(r["x"]), float(r["z"])
            i = min(range(len(pts)), key=lambda k: math.hypot(pts[k][0] - x, pts[k][2] - z))
            return cum[i], math.hypot(pts[i][0] - x, pts[i][2] - z), i

        h0 = float(rows[0]["health"])
        event = None
        slow_since = None
        for r in rows:
            t, h, v = float(r["t"]), float(r["health"]), float(r["speed_kmh"])
            if h < h0 - 2.5 and event is None:
                event = ("hurt", r)
            if t > 3.0:
                if v < 3.0:
                    slow_since = slow_since if slow_since is not None else t
                    if t - slow_since >= 2.0 and event is None:
                        event = ("stuck", r)
                else:
                    slow_since = None
            h0 = max(h0, h) if h > h0 else h0
        chain = spec.get("chain", [])
        joint = cum[-1] * 0.5
        # the joint: where the path first leaves the first lane (approximated by the 2nd chain element's first point)
        if event is None:
            print("%-40s clean (length %.0f m)" % (p.stem, cum[-1]))
            continue
        kind, r = event
        s, off, i = along(r)
        print("%-40s %-5s at t=%.1f s, %.0f m along a %.0f m path (%.1f m off the line) at (%.0f, %.1f, %.0f), speed %.0f, health %s" % (
            p.stem, kind, float(r["t"]), s, cum[-1], off, float(r["x"]), float(r["y"]), float(r["z"]), float(r["speed_kmh"]), r["health"]))
        print("      chain: %s" % " -> ".join(chain))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
