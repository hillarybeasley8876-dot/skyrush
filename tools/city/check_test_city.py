#!/usr/bin/env python3
"""check_test_city — is the race of the test city a circuit on its own roads? (data/city/test_city.json only, no Godot)

    python tools/city/check_test_city.py <test_city.json> <reference test_city.json>

The test city is the small city of test_world_api.gd; its route test_loop is a race (a circuit of 2 laps) that has to run on the
roads of the test city: along main_ew, up onto the elevated road elev_ew and back, joined where the roads meet. A new road may
join two roads; it may not be a second road drawn over an existing one (job test-city-loop, round 1: a one-way loop laid along
main_ew and along elev_ew, joined to nothing, and the race ran on it alone).

CHANGED     a road, junction, block, poi, sky lane or spawn of the reference is changed or gone
ALONG       a new road runs along an existing one: more than 25 % of its length (sampled every 5 m) lies within 15 m of the centre
            line of an existing road at the same level (|dy| < 3 m), leaving out the 20 m at each end (where it joins them)
LONG        a new road longer than 400 m (a link between two roads is short)
LOOSE_END   an end of a new road joins no existing road: no junction record within 15 m that lists it and an existing road, and
            no attach_start / attach_end to an existing road
GATES       test_loop is not a race of 2 laps with at least 4 gates and the grid (-450, 0, -5, 90), or it has no gate within 6 m of
            main_ew at ground level, or no gate within 6 m of elev_ew where that road is at least 8 m up
Prints one line per problem and "TEST_CITY OK" or "TEST_CITY FAIL n".
"""
import json
import math
import sys

ALONG_SHARE = 0.25
ALONG_DIST = 15.0
LEVEL = 3.0
MAX_LINK = 400.0
END_DIST = 15.0
END_ZONE = 20.0   # m: the first and the last metres of a new road join the roads at its ends
GATE_DIST = 6.0
STEP = 5.0


def samples(points, step=STEP):
    out = []
    for a, b in zip(points, points[1:]):
        n = max(1, int(math.ceil(math.dist(a, b) / step)))
        for k in range(n):
            t = k / n
            out.append([a[i] + (b[i] - a[i]) * t for i in range(3)])
    out.append(list(points[-1]))
    return out


def length(points):
    return sum(math.dist(a, b) for a, b in zip(points, points[1:]))


def nearest(road, p):
    """(plan distance, height of the road there) of the centre line of a road nearest to p"""
    best = (1e18, 0.0)
    pts = road["points"]
    for a, b in zip(pts, pts[1:]):
        vx, vz = b[0] - a[0], b[2] - a[2]
        l2 = vx * vx + vz * vz
        t = 0.0 if l2 < 1e-9 else max(0.0, min(1.0, ((p[0] - a[0]) * vx + (p[2] - a[2]) * vz) / l2))
        d = math.hypot(a[0] + t * vx - p[0], a[2] + t * vz - p[2])
        if d < best[0]:
            best = (d, a[1] + (b[1] - a[1]) * t)
    return best


def check(city, ref):
    problems = []
    old_roads = {r["id"]: r for r in ref["roads"]}
    for key in ("junctions", "blocks", "pois", "sky_lanes", "spawns", "water"):
        old, new = ref.get(key), city.get(key)
        if isinstance(old, list) and isinstance(new, list):
            for item in old:
                if item not in new:
                    problems.append("CHANGED %s: %s" % (key, item.get("id", str(item)[:60]) if isinstance(item, dict) else str(item)[:60]))
        elif old != new:
            problems.append("CHANGED %s" % key)
    roads = {r["id"]: r for r in city["roads"]}
    for rid, road in old_roads.items():
        if roads.get(rid) != road:
            problems.append("CHANGED road %s" % rid)
    new_roads = [r for r in city["roads"] if r["id"] not in old_roads]
    for road in new_roads:
        pts = road["points"]
        near = 0
        total = length(pts)
        smp = []
        run = 0.0
        prev = None
        for p in samples(pts):
            run += math.dist(prev, p) if prev is not None else 0.0
            prev = p
            if END_ZONE <= run <= total - END_ZONE:
                smp.append(p)     # the ends of a link lie at the roads it joins: they do not count
        for p in smp:
            for other in old_roads.values():
                d, h = nearest(other, p)
                if d <= ALONG_DIST and abs(h - p[1]) < LEVEL:
                    near += 1
                    break
        if smp and near > ALONG_SHARE * len(smp):
            problems.append("ALONG %s: %d of %d samples run along an existing road" % (road["id"], near, len(smp)))
        if length(pts) > MAX_LINK:
            problems.append("LONG %s: %.0f m" % (road["id"], length(pts)))
        for end, key in ((pts[0], "attach_start"), (pts[-1], "attach_end")):
            attach = road.get(key) or {}
            if attach.get("road") in old_roads:
                continue
            ok = any(math.hypot(j["x"] - end[0], j["z"] - end[2]) <= END_DIST and road["id"] in j.get("roads", [])
                     and any(r in old_roads for r in j.get("roads", [])) for j in city.get("junctions", []))
            if not ok:
                problems.append("LOOSE_END %s at (%.0f, %.0f, %.0f)" % (road["id"], end[0], end[1], end[2]))
    route = next((r for r in city.get("routes", []) if r.get("id") == "test_loop"), None)
    if route is None:
        problems.append("GATES test_loop is gone")
    else:
        cps = route.get("checkpoints", [])
        shape_ok = route.get("kind") == "race" and route.get("laps") == 2 and len(cps) >= 4 and route.get("grid") == [-450, 0, -5, 90]
        main = old_roads.get("main_ew")
        elev = old_roads.get("elev_ew")
        on_main = main is not None and any(nearest(main, c)[0] <= GATE_DIST and abs(c[1] - nearest(main, c)[1]) < LEVEL for c in cps)
        on_elev = elev is not None and any(nearest(elev, c)[0] <= GATE_DIST and nearest(elev, c)[1] >= 8.0
                                           and abs(c[1] - nearest(elev, c)[1]) < LEVEL for c in cps)
        if not (shape_ok and on_main and on_elev):
            problems.append("GATES test_loop: race of 2 laps with 4 gates and its grid %s, a gate on main_ew %s, a gate on the "
                            "elevated part of elev_ew %s" % (shape_ok, on_main, on_elev))
    return problems


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    city = json.load(open(argv[1], encoding="utf-8"))
    ref = json.load(open(argv[2], encoding="utf-8"))
    problems = check(city, ref)
    for line in problems:
        print(line)
    print("TEST_CITY OK" if not problems else "TEST_CITY FAIL %d" % len(problems))
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
