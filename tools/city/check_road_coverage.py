#!/usr/bin/env python3
"""check_road_coverage — does a changed city.json still have the same roads on the ground? (no Godot needed)

    python tools/city/check_road_coverage.py <new city.json> <baseline city.json> [--keep 0.995] [--extra 0.01] [--cell 2]

Every road polyline is laid on a grid of --cell metre cells (a cell is covered when a road passes through it). The new map
has to keep at least --keep of the cells the baseline covers (a cell counts as kept when the new map covers it or one of its
8 neighbours), and may add at most --extra of the baseline's cell count of cells that no baseline cell is next to.
Used by the jobs that clean up road polylines: a street that is folded back on itself covers the same cells twice, so removing
the fold changes the length of the road but not its coverage, while deleting the street changes the coverage.
Prints "ROAD_COVERAGE OK" or "ROAD_COVERAGE FAIL".
"""
import json
import math
import sys


def cells(city, cell):
    out = set()
    for road in city["roads"]:
        pts = road["points"]
        for a, b in zip(pts, pts[1:]):
            length = math.hypot(b[0] - a[0], b[2] - a[2])
            steps = max(int(length / (cell * 0.5)), 1)
            for k in range(steps + 1):
                t = k / steps
                out.add((int((a[0] + (b[0] - a[0]) * t) // cell), int((a[2] + (b[2] - a[2]) * t) // cell)))
    return out


def near(cell, other):
    cx, cz = cell
    return any((cx + dx, cz + dz) in other for dx in (-1, 0, 1) for dz in (-1, 0, 1))


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]

    def opt(name, default):
        return float(argv[argv.index(name) + 1]) if name in argv else default

    keep, extra, cell = opt("--keep", 0.995), opt("--extra", 0.01), opt("--cell", 2.0)
    for name in ("--keep", "--extra", "--cell"):
        if name in argv:
            args.remove(argv[argv.index(name) + 1])
    new = cells(json.load(open(args[0], encoding="utf-8")), cell)
    old = cells(json.load(open(args[1], encoding="utf-8")), cell)
    kept = sum(1 for c in old if near(c, new))
    added = sum(1 for c in new if not near(c, old))
    ok = kept >= keep * len(old) and added <= extra * len(old)
    print("baseline cells %d: kept %d (%.3f %%, at least %.1f %%), new cells %d (%.3f %% of the baseline, at most %.1f %%)" % (
        len(old), kept, 100.0 * kept / max(len(old), 1), 100.0 * keep, added, 100.0 * added / max(len(old), 1), 100.0 * extra))
    print("ROAD_COVERAGE %s" % ("OK" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
