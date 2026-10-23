#!/usr/bin/env python3
"""check_road_retrace — does a road of city.json double back along itself?

    python tools/city/check_road_retrace.py <city.json> [--max-roads N] [--max-metres M] [--quiet]

A road whose polyline goes out to a tip and comes back along the same line has two carriageways on top of each other, a
lane that ends where it starts and a "junction" at both of its ends. The lattice streets of the west and north of the map
have 112 of them (153 turning points, 25 of them on the edge of the window): the generator joins the two halves of a street at
a shared point without turning the first half round.
A turning point is a vertex where the direction reverses (dot of the two segments < -0.8). The retraced length of a turning
point is how many metres after it the polyline stays within 3 m of the part before it (the part that is walked twice).
Prints one line per road (the worst first) and "ROAD_RETRACE OK" / "ROAD_RETRACE FAIL (roads, metres)".
Exit 0 when the number of roads with a turning point is <= --max-roads (default 0) and the retraced metres <= --max-metres (default 0).
"""
import json
import math
import sys

TURN = -0.8        # the cosine under which two segments are a U-turn
SAME = 3.0         # m: a point this close to the part before the turn is on it
MIN_SEG = 0.2


def turning_points(pts):
    out = []
    for i in range(1, len(pts) - 1):
        a = (pts[i][0] - pts[i - 1][0], pts[i][2] - pts[i - 1][2])
        b = (pts[i + 1][0] - pts[i][0], pts[i + 1][2] - pts[i][2])
        la, lb = math.hypot(*a), math.hypot(*b)
        if la > MIN_SEG and lb > MIN_SEG and (a[0] * b[0] + a[1] * b[1]) / (la * lb) < TURN:
            out.append(i)
    return out


def dist_to_polyline(p, pts):
    best = float("inf")
    for a, b in zip(pts, pts[1:]):
        dx, dz = b[0] - a[0], b[2] - a[2]
        l2 = dx * dx + dz * dz
        t = 0.0 if l2 < 1e-9 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[2] - a[2]) * dz) / l2))
        best = min(best, math.hypot(a[0] + t * dx - p[0], a[2] + t * dz - p[2]))
    return best


def retraced(pts, k):
    """Metres after the turning point k that lie on the part before it."""
    before = pts[:k + 1]
    total = 0.0
    for i in range(k + 1, len(pts)):
        if dist_to_polyline(pts[i], before) > SAME:
            break
        total += math.hypot(pts[i][0] - pts[i - 1][0], pts[i][2] - pts[i - 1][2])
    return total


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    quiet = "--quiet" in argv

    def opt(name, default):
        return float(argv[argv.index(name) + 1]) if name in argv else default

    max_roads, max_metres = int(opt("--max-roads", 0)), opt("--max-metres", 0.0)
    for name in ("--max-roads", "--max-metres"):
        if name in argv:
            args.remove(argv[argv.index(name) + 1])
    city = json.load(open(args[0], encoding="utf-8"))
    rows, total = [], 0.0
    for road in city["roads"]:
        pts = road["points"]
        turns = turning_points(pts)
        if not turns:
            continue
        metres = sum(retraced(pts, k) for k in turns)
        total += metres
        rows.append((metres, road["id"], len(turns), len(pts)))
    rows.sort(reverse=True)
    if not quiet:
        for (metres, rid, n, count) in rows[:25]:
            print("%-22s %d turning point(s), %.0f m walked twice, %d points" % (rid, n, metres, count))
    ok = len(rows) <= max_roads and total <= max_metres
    print("ROAD_RETRACE %s (%d roads with a turning point of %d, %.0f m walked twice)" % (
        "OK" if ok else "FAIL", len(rows), len(city["roads"]), total))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
