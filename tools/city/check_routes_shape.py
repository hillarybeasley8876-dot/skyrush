#!/usr/bin/env python3
"""check_routes_shape — the routes of a city.json have the shape the game expects.

    python tools/city/check_routes_shape.py <city.json>

validate.py already checks every checkpoint (on a lane, heading, 300-500 m driven apart, reachable, in
order).  It cannot tell a 3-checkpoint "grand loop" from a real one, so this adds what it misses:
the five routes exist, are long enough, and their grids and checkpoints are sane.
"""
import json
import math
import sys

# route id -> (kind, minimum checkpoints): about 35 % of the itinerary's road length at 400 m spacing
EXPECTED = {
    "grand_loop": ("race", 15),
    "elevated_sprint": ("sprint", 8),
    "river_loop": ("pursuit", 12),
    "bund_sprint": ("sprint", 4),
    "lujiazui_ring": ("race", 6),
}


def main(path):
    city = json.load(open(path, encoding="utf-8"))
    routes = {r["id"]: r for r in city["routes"]}
    win = city["window"]
    bad = []
    for rid in sorted(set(EXPECTED) - set(routes)):
        bad.append("route %s is missing" % rid)
    for rid in sorted(set(routes) - set(EXPECTED)):
        bad.append("route %s is not one of the five" % rid)
    for rid, (kind, least) in EXPECTED.items():
        route = routes.get(rid)
        if route is None:
            continue
        cps = route["checkpoints"]
        if route.get("kind") != kind:
            bad.append("route %s has kind %s, expected %s" % (rid, route.get("kind"), kind))
        if len(cps) < least:
            bad.append("route %s has %d checkpoints, at least %d expected" % (rid, len(cps), least))
        if list(route["grid"]) != list(cps[0]):
            bad.append("route %s: the grid is not the first checkpoint" % rid)
        for i, cp in enumerate(cps):
            if not (win["x_min"] <= cp[0] <= win["x_max"] and win["z_min"] <= cp[2] <= win["z_max"]):
                bad.append("route %s cp%02d lies outside the map window" % (rid, i))
            if not 0.0 <= cp[3] < 360.0:
                bad.append("route %s cp%02d heading %s is not in [0, 360)" % (rid, i, cp[3]))
        for i in range(len(cps) - 1):
            gap = math.hypot(cps[i][0] - cps[i + 1][0], cps[i][2] - cps[i + 1][2])
            if gap < 100.0:
                bad.append("route %s: cp%02d and cp%02d are only %.0f m apart in plan (consecutive "
                           "checkpoints are 300-500 m driven apart)" % (rid, i, i + 1, gap))
    for line in bad:
        print("FAIL", line)
    print("ROUTES_SHAPE %s (%d routes: %s)" % ("FAIL" if bad else "OK", len(routes),
                                                ", ".join("%s=%d" % (k, len(v["checkpoints"])) for k, v in routes.items())))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
