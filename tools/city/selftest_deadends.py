#!/usr/bin/env python3
"""selftest_deadends — why do the road ends of the map not reach a road?

    python tools/city/selftest_deadends.py [--max N] [--reach 1400]

Prints one line per road end that the rule "no dead ends" complains about:
what the search for a road found, how far the next road along the street's
own line is, and how far the nearest road in any direction is.  It is the
probe the dead-end job used to decide its policy, and it is the
regression test for it: the number of dead ends it prints must be zero.
"""
import contextlib
import io
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import build_city          # noqa: E402
import city_rules         # noqa: E402
import city_snap          # noqa: E402
import citylib            # noqa: E402
from city_water import is_water, on_land  # noqa: E402

SCRATCH = "F:/dev/skyrush-out/tmp/city-deadends/probe_city.json"


def _build():
    """The city as the game sees it, written to the scratch folder."""
    with contextlib.redirect_stdout(io.StringIO()):
        build_city.main(SCRATCH)
    return citylib.load_json(SCRATCH)


def _dense(poly, step=15.0):
    """The points of a polyline, every `step` metres."""
    out = [poly[0]]
    acc = 0.0
    for a, b in zip(poly, poly[1:]):
        length = math.dist(a, b)
        n = max(1, int(length / step))
        for k in range(1, n + 1):
            t = k / n
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def _nearest_roads(point, index, polys, limit=600.0):
    """The roads near the point: (distance, name, point on the road)."""
    out = []
    seen = set()
    for name, _idx, _q in index.within(point, limit):
        if name in seen:
            continue
        seen.add(name)
        poly = polys[name]
        dist, near = city_snap.closest_point(poly, point)
        if dist <= limit:
            out.append((dist, name, near))
    out.sort()
    return out


def _angle_to(point, near, name, polys):
    """The angle between the direction to a road and the road's own line."""
    dist = math.dist(point, near)
    if dist < 1e-6:
        return 0.0
    link_dir = ((near[0] - point[0]) / dist, (near[1] - point[1]) / dist)
    _d, pidx = city_snap.nearest_on(polys[name], near)
    return city_snap.angle_between(link_dir,
                                   city_snap.poly_direction(polys[name], pidx))


def _grade(road, point):
    """The height of a road at a point, and whether it is at grade there."""
    best, best_y = 1e18, 0.0
    for p in road["points"]:
        d = math.hypot(p[0] - point[0], p[2] - point[1])
        if d < best:
            best, best_y = d, p[1]
    return "%s y=%.1f" % (road.get("kind", "?"), best_y)


def _end_plan(points, start):
    """The two-point plan of a road at one of its ends."""
    if start:
        return [(points[1][0], points[1][2]), (points[0][0], points[0][2])], 0
    n = len(points)
    return [(points[n - 2][0], points[n - 2][2]), (points[n - 1][0], points[n - 1][2])], 1


def main(argv):
    limit = int(argv[argv.index("--max") + 1]) if "--max" in argv else 60
    reach = float(argv[argv.index("--reach") + 1]) if "--reach" in argv else 1400.0
    city = _build()
    window = city["window"]
    polys = {r["id"]: [(p[0], p[2]) for p in r["points"]] for r in city["roads"]}
    widths = {r["id"]: citylib.road_width(r) for r in city["roads"]}
    index = citylib.PolyIndex()
    for name, poly in polys.items():
        index.add(name, _dense(poly))
    fails = city_rules.check_dead_ends(city)
    by_id = {r["id"]: r for r in city["roads"]}
    print("dead ends: %d" % len(fails))
    for message in fails[:limit]:
        road_id = message.split()[0]
        road = by_id[road_id]
        pts = road["points"]
        start = message.split()[1] == "start"
        point = (pts[0][0], pts[0][2]) if start else (pts[-1][0], pts[-1][2])
        plan, end = _end_plan(pts, start)
        far = city_snap.scan(plan, end, index, polys, widths, road_id, window,
                             reach)
        near = _nearest_roads(point, index, polys)
        edge = (point[0] <= window["x_min"] + 40.0
                or point[0] >= window["x_max"] - 40.0
                or point[1] <= window["z_min"] + 40.0
                or point[1] >= window["z_max"] - 40.0)
        print("%-18s %-5s (%7.1f,%7.1f) %s" % (
            road_id, "start" if start else "end", point[0], point[1],
            "AT THE EDGE" if edge else ""))
        print("    along the line to %.0f m: %s%s" % (
            reach, far["kind"], "" if far["road"] is None
            else " %s at %.0f m" % (far["road"], far["s"])))
        if far["point"] is not None:
            print("    that run is %s" % ("on land" if on_land(point, far["point"])
                                          else "OVER WATER"))
        for dist, name, p in near[:3]:
            if name == road_id:
                continue
            print("    nearest road %-16s %5.0f m  angle %3.0f deg  %s  %s" % (
                name, dist, _angle_to(point, p, name, polys),
                "on land" if on_land(point, p) else "over water",
                _grade(by_id[name], p)))
        if is_water(point):
            print("    the end itself is in the water")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
