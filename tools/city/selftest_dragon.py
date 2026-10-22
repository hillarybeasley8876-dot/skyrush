#!/usr/bin/env python3
"""selftest_dragon — the dragon interchange must clear itself.

    python tools/city/selftest_dragon.py [data/city/city.json]

The eight ramps of the 龙柱 interchange cross each other, the Yan'an elevated
and the surface frontage road.  This is a direct geometric check of that
crossing: two dragon decks whose carriageways overlap in plan must leave
5.5 m plus the depth of the upper structure between them.  The check runs
on the map and on a broken map, so it cannot pass by accident.
"""
import copy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import citylib  # noqa: E402
from city_rules import CLEARANCE, deck_depth  # noqa: E402
from city_rules_index import PointGrid  # noqa: E402

DRAGON = ("ramp_l3_", "ramp_l4_", "ramp_rt_")
FRONTAGE = "yanan_frontage_n"
PILLAR = (-1299.0, 687.0)
AXIS_PASS = 4.5      # the left turns graze the pillar axis
AXIS_CLEAR = 51.0    # the right turns swing this far clear of it
L3_LEVEL = 16.5
L4_LEVEL = 23.9
STACK = 7.1          # the clearance between the L3 and the L4 deck
STEP = 2.0           # the sample step of the check


def dragon_roads(city):
    """The dragon ramps and the frontage road, in a stable order."""
    out = [r for r in city["roads"]
           if r["id"].startswith(DRAGON) or r["id"] == FRONTAGE]
    out.sort(key=lambda r: r["id"])
    return out


def overlap_failures(city):
    """The dragon deck pairs too close in height where their decks overlap."""
    roads = dragon_roads(city)
    widths = [citylib.road_width(r) for r in roads]
    depths = [deck_depth(r) for r in roads]
    grid = PointGrid(roads, widths)
    fails = []
    for ri, road in enumerate(roads):
        hw = widths[ri] * 0.5
        for p in citylib.road_points(road, STEP):
            near, _own = grid.near(p[0], p[2], hw, hw + 40.0, ri)
            for oi, oy in near:
                if oi == ri:
                    continue
                gap = p[1] - oy
                if abs(gap) < 1.0:
                    continue                      # at grade: a crossing, not a deck
                upper = ri if gap > 0 else oi
                need = CLEARANCE + depths[upper]
                if abs(gap) < need - 0.05:
                    fails.append("%s x %s: %.2f m (need %.1f) at (%.0f, %.0f)"
                                 % (roads[ri]["id"], roads[oi]["id"], gap, need,
                                    p[0], p[2]))
    return fails


def axis_distance(road):
    """The smallest plan distance from the road to the pillar axis."""
    return min(math.hypot(p[0] - PILLAR[0], p[2] - PILLAR[1])
               for p in road["points"])


def level_errors(city):
    """The L3 and L4 decks must be at their level where they cross the axis."""
    out = []
    for road in city["roads"]:
        rid = road["id"]
        level = None
        if rid.startswith("ramp_l3"):
            level = L3_LEVEL
        elif rid.startswith("ramp_l4"):
            level = L4_LEVEL
        if level is None:
            continue
        near = [p[1] for p in road["points"]
                if math.hypot(p[0] - PILLAR[0], p[2] - PILLAR[1]) < 20.0]
        if not near:
            out.append("%s never comes near the pillar axis" % rid)
            continue
        error = max(abs(y - level) for y in near)
        if error > 0.3:
            out.append("%s is %.2f m off Y=%.1f at the pillar" % (rid, error, level))
    return out


def stack_error(city):
    """The smallest vertical gap between an L3 deck and an L4 deck."""
    roads = {r["id"]: r for r in city["roads"]}
    l3 = [r for r in roads.values() if r["id"].startswith("ramp_l3")]
    l4 = [r for r in roads.values() if r["id"].startswith("ramp_l4")]
    worst = 1e18
    for a in l3:
        for b in l4:
            for p in a["points"]:
                if math.hypot(p[0] - PILLAR[0], p[2] - PILLAR[1]) > 30.0:
                    continue
                best = min(abs(p[1] - q[1]) for q in b["points"]
                           if math.hypot(q[0] - PILLAR[0], q[2] - PILLAR[1]) < 30.0)
                worst = min(worst, best)
    return worst


def axis_errors(city):
    """The left turns graze the axis, the right turns keep clear of it."""
    out = []
    for road in city["roads"]:
        rid = road["id"]
        if not rid.startswith(DRAGON):
            continue
        d = axis_distance(road)
        if rid.startswith(("ramp_l3", "ramp_l4")):
            if d > AXIS_PASS:
                out.append("%s stays %.1f m from the axis" % (rid, d))
        elif d < AXIS_CLEAR:
            out.append("%s comes %.1f m from the axis" % (rid, d))
    return out


def ground_errors(city):
    """No dragon deck may dive under the ground."""
    out = []
    for road in city["roads"]:
        if not road["id"].startswith(DRAGON):
            continue
        low = min(p[1] for p in road["points"])
        if low < 0.0:
            out.append("%s dips to Y=%.2f" % (road["id"], low))
    return out


def drop_ramp(city, metres=3.0):
    """A copy of the map with one dragon deck pushed down."""
    out = copy.deepcopy(city)
    ramp = next(r for r in out["roads"] if r["id"] == "ramp_l4_sb_eb")
    for p in ramp["points"]:
        p[1] -= metres
    return out


def check(city):
    """Every dragon problem of the map, one line each."""
    out = []
    out += overlap_failures(city)
    out += level_errors(city)
    out += axis_errors(city)
    out += ground_errors(city)
    worst = stack_error(city)
    if worst < STACK - 0.05:
        out.append("the L3 and L4 decks are only %.2f m apart at the pillar" % worst)
    return out


def main(argv):
    path = argv[1] if len(argv) > 1 else os.path.join(
        HERE, "..", "..", "data", "city", "city.json")
    city = citylib.load_json(path)
    cases = [
        ("the unmodified interchange clears itself", city, 0),
        ("a deck pushed 3 m down is caught", drop_ramp(city), 1),
    ]
    bad = 0
    for label, target, want in cases:
        found = check(target)
        ok = (len(found) > 0) == bool(want)
        bad += 0 if ok else 1
        print("%s %s" % ("PASS" if ok else "FAIL", label))
        for line in found[:6]:
            print("       %s" % line)
    print("selftest_dragon: %d case(s) wrong" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
