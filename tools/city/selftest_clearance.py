#!/usr/bin/env python3
"""selftest_clearance — proves the fast deck clearance rule agrees with the old one.

    python tools/city/selftest_clearance.py [data/city/city.json]

The clearance rule got 5x faster (city_rules_index.py).  A rule that is wrong
in a way that only shows on another map is worthless, so this file keeps a
*copy* of the old implementation and requires the new one to give the very
same list of failures on

  * the map as it is,
  * a map with every elevated road raised by 1 m,
  * a map with every elevated road lowered by 1 m,
  * a map with the points of one ramp shifted 3 m sideways.

The old code is slow (about 85 s on the whole city), so this takes a few
minutes.
"""
import copy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import citylib  # noqa: E402
import city_rules_attach  # noqa: E402
from city_rules import (GORE, CLEARANCE, TUNNEL_CLEARANCE,  # noqa: E402
                        deck_depth)


# ------------------------------------------------- the old implementation

def ref_height_at(road, x, z):
    """The height of a road at the plan position (x, z)."""
    pts = road["points"]
    best, best_y = 1e18, 0.0
    for p in pts:
        d = (p[0] - x) ** 2 + (p[2] - z) ** 2
        if d < best:
            best, best_y = d, p[1]
    return best_y


def ref_within(city, radius, skip=()):
    """The roads whose centre-line comes within `radius` of a point."""
    index = city.setdefault("_index", None)
    if index is None:
        index = citylib.PolyIndex()
        for road in city["roads"]:
            index.add(road["id"], [(p[0], p[2]) for p in road["points"]])
        city["_index"] = index
    return index


def ref_point_at(road, s):
    """The point at the distance `s` along a road (x, z) and its tangent."""
    pts = road["points"]
    acc = 0.0
    for a, b in zip(pts, pts[1:]):
        run = math.hypot(b[0] - a[0], b[2] - a[2])
        if acc + run >= s:
            t = (s - acc) / run if run > 1e-9 else 0.0
            return (a[0] + t * (b[0] - a[0]), a[2] + t * (b[2] - a[2])), \
                (b[0] - a[0], b[2] - a[2])
        acc += run
    a, b = pts[-2], pts[-1]
    return (b[0], b[2]), (b[0] - a[0], b[2] - a[2])


def ref_attach_gore(road, other, point):
    """True when the point is inside the attach gore of the pair."""
    for owner in (road, other):
        for key in ("attach_start", "attach_end"):
            att = owner.get(key)
            if not att:
                continue
            if att["road"] not in (road["id"], other["id"]):
                continue
            parent = road if att["road"] == road["id"] else other
            anchor, _tan = ref_point_at(parent, att["at"])
            if anchor and math.hypot(point[0] - anchor[0],
                                     point[2] - anchor[1]) <= GORE:
                return True
    return False


def ref_gore(road, other, station):
    """True when the station of the road is in the attach gore of the pair."""
    for key, at_start in (("attach_start", True), ("attach_end", False)):
        att = road.get(key)
        if not att or att["road"] != other["id"]:
            continue
        length = road["_length"]
        d = station if at_start else length - station
        if d <= GORE:
            return True
    return False


def ref_junction_at(city, x, z, radius=40.0, roads=None):
    """The junction at the plan position, if there is one."""
    for j in city["junctions"]:
        if math.hypot(j["x"] - x, j["z"] - z) > radius:
            continue
        if roads and not all(r in j["roads"] for r in roads):
            continue
        return j
    return None


def ref_junction_pair(city, road_id, other_id):
    """The junctions that list both roads."""
    for j in city["junctions"]:
        if road_id in j["roads"] and other_id in j["roads"]:
            return j
    return None


def ref_junction_exempt(city, road, other, point, road_w, other_w):
    """True if the point is at a junction of the two roads."""
    j = ref_junction_pair(city, road["id"], other["id"])
    if j is None:
        return False
    reach = road_w * 0.5 + other_w * 0.5 + 10.0
    return math.hypot(point[0] - j["x"], point[2] - j["z"]) <= reach


def ref_exempt(city, road, other, point, road_w, other_w):
    """The exemptions of the clearance rule."""
    if ref_attach_gore(road, other, point):
        return True
    if road["kind"] == "surface" and other["kind"] == "surface":
        return ref_junction_exempt(city, road, other, point, road_w, other_w)
    junction = ref_junction_at(city, point[0], point[2], 40.0,
                               (road["id"], other["id"]))
    if junction:
        if abs(ref_height_at(road, point[0], point[2])) < 1.0 or \
                abs(ref_height_at(other, point[0], point[2])) < 1.0:
            return True
    return False


def reference_check_clearance(city):
    """The deck clearance rule as it was before the speed-up."""
    fails = []
    by_id = {r["id"]: r for r in city["roads"]}
    index = ref_within(city, 0)
    seen = set()
    pairs = {}
    for road in city["roads"]:
        width = citylib.road_width(road)
        pts = citylib.road_points(road, 2.0)
        cum = citylib.cumulative(pts)
        road["_length"] = cum[-1]
        for i, p in enumerate(pts):
            for name, _idx, q in index.within((p[0], p[2]), width * 0.5 + 40.0):
                if name == road["id"]:
                    continue
                other = by_id[name]
                other_w = citylib.road_width(other)
                if math.hypot(p[0] - q[0], p[2] - q[1]) > width * 0.5 + other_w * 0.5:
                    continue
                oy = ref_height_at(other, p[0], p[2])
                gap = p[1] - oy
                if abs(gap) < 1.0:
                    need = 0.0
                else:
                    upper = road if gap > 0 else other
                    if road["kind"] == "tunnel" or other["kind"] == "tunnel":
                        need = TUNNEL_CLEARANCE
                    else:
                        need = CLEARANCE + deck_depth(upper)
                if abs(gap) >= need - 0.05:
                    continue
                if ref_gore(road, other, cum[i]):
                    continue
                if ref_exempt(city, road, other, p, width, other_w):
                    continue
                key = (road["id"], other["id"], round(p[0] / 20.0),
                       round(p[2] / 20.0))
                if key in seen:
                    continue
                seen.add(key)
                pair = (road["id"], other["id"])
                if pair not in pairs:
                    pairs[pair] = [0, gap, need, p[0], p[2]]
                pairs[pair][0] += 1
                if abs(gap) < abs(pairs[pair][1]):
                    pairs[pair][1] = gap
                    pairs[pair][2] = need
                    pairs[pair][3] = p[0]
                    pairs[pair][4] = p[2]
    for pair, (count, gap, need, x, z) in sorted(pairs.items(),
                                                 key=lambda kv: kv[1][1]):
        fails.append("%s x %s: %d samples, worst %.1f m (need %.1f) at "
                     "(%.0f, %.0f)" % (pair[0], pair[1], count, gap, need, x, z))
    return fails


# ------------------------------------------------- the perturbed maps

def raise_elevated(city, metres):
    """A copy of the map with every elevated road raised (or lowered)."""
    out = copy.deepcopy(city)
    for road in out["roads"]:
        if road["kind"] == "elevated":
            for p in road["points"]:
                p[1] += metres
    return out


def shift_ramp(city, metres):
    """A copy of the map with the points of one ramp shifted sideways."""
    out = copy.deepcopy(city)
    ramp = next(r for r in out["roads"] if r["kind"] == "ramp")
    pts = ramp["points"]
    dx = pts[-1][0] - pts[0][0]
    dz = pts[-1][2] - pts[0][2]
    length = math.hypot(dx, dz) or 1.0
    nx, nz = -dz / length, dx / length
    for p in pts:
        p[0] += nx * metres
        p[2] += nz * metres
    return out


def main(argv):
    path = argv[1] if len(argv) > 1 else os.path.join(
        HERE, "..", "..", "data", "city", "city.json")
    city = citylib.load_json(path)
    cases = [
        ("the map as it is", city),
        ("every elevated road raised by 1 m", raise_elevated(city, 1.0)),
        ("every elevated road lowered by 1 m", raise_elevated(city, -1.0)),
        ("one ramp shifted 3 m sideways", shift_ramp(city, 3.0)),
    ]
    bad = 0
    for label, case in cases:
        want = reference_check_clearance(copy.deepcopy(case))
        got = city_rules_attach.check_clearance(copy.deepcopy(case))
        ok = want == got
        bad += 0 if ok else 1
        print("%s %s (%d failing items)" % ("PASS" if ok else "FAIL", label,
                                           len(want)))
        if not ok:
            print("      %d old items, %d new items" % (len(want), len(got)))
            for a, b in zip(want, got):
                if a != b:
                    print("      old: %s" % a)
                    print("      new: %s" % b)
                    break
    print("selftest_clearance: %d case(s) wrong" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
