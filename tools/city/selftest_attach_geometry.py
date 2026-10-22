#!/usr/bin/env python3
"""selftest_attach_geometry — the attach geometry of the Nanpu ramps.

    python tools/city/selftest_attach_geometry.py [data/city/city.json]

The ramp attach rule (city_rules_attach) says *that* a ramp attaches; this
script says *where* the three ramps that had to be re-drawn have to attach,
so a later change cannot quietly move them again:

  * the lower spiral ends on the inner edge of the L3 loop's carriageway
    (the loop runs counter-clockwise, so its inner edge is to the left),
  * the Pudong loop lands on Pudong South Rd along the road's own
    direction, on the road's centre-line,
  * the L3 WB>SB ramp joins the N-S elevated along its direction.

It also checks that the two Nanpu ramps keep their smooth height profile.

The measurements use the attach rule's own helpers, so the script measures
exactly what the rule measures.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import city_attach  # noqa: E402
import citylib  # noqa: E402
from city_rules import HEIGHT_TOLERANCE, KINK_LIMIT, PLAN_TOLERANCE  # noqa: E402
from city_rules_attach import _closest_on, _direction, _heading  # noqa: E402

TANGENT_TOLERANCE = 8.0


def angle_diff(a, b):
    return abs((a - b + 180.0) % 360.0 - 180.0)


def tangent_error(road, key, parent):
    """The angle between the ramp's end direction and the parent's."""
    idx = 0 if key == "attach_start" else -1
    ct = _direction(road, idx)
    _plan, tan, _y = _closest_on(parent, road["points"][idx])
    return min(angle_diff(_heading(ct), _heading(tan)),
               angle_diff(_heading(ct), _heading(tan) + 180.0))


def lateral_offset(road, key, parent):
    """The signed offset of the ramp's end from the parent's centre-line."""
    idx = 0 if key == "attach_start" else -1
    p = road["points"][idx]
    _s, lat, _h, _y = city_attach.project(parent["points"], (p[0], p[2]))
    return lat


def kink(road):
    """The largest grade change per 10 m of a road."""
    pts = citylib.road_points(road, 2.0)
    grades = []
    for a, b in zip(pts, pts[1:]):
        run = math.hypot(b[0] - a[0], b[2] - a[2])
        grades.append((b[1] - a[1]) / run if run > 1e-6 else 0.0)
    worst = 0.0
    for i in range(len(grades) - 5):
        worst = max(worst, abs(grades[i + 5] - grades[i]))
    return worst


def main(argv):
    path = argv[1] if len(argv) > 1 else os.path.join(HERE, "..", "..",
                                                       "data", "city", "city.json")
    city = citylib.load_json(path)
    by_id = {r["id"]: r for r in city["roads"]}
    bad = 0

    def check(label, ok, detail):
        nonlocal bad
        if not ok:
            bad += 1
        print("%s %s (%s)" % ("PASS" if ok else "FAIL", label, detail))

    lower = by_id["nanpu_spiral_lower"]
    upper = by_id["nanpu_spiral_upper"]
    want = -(city_attach.asphalt_half(upper) + city_attach.asphalt_half(lower))
    lat = lateral_offset(lower, "attach_end", upper)
    check("the lower spiral ends on the L3 loop's inner edge",
          abs(lat - want) <= PLAN_TOLERANCE,
          "lateral %.2f m, wanted %.2f m" % (lat, want))
    err = tangent_error(lower, "attach_end", upper)
    check("the lower spiral runs along the L3 loop", err <= TANGENT_TOLERANCE,
          "%.1f deg" % err)
    _plan, _tan, parent_y = _closest_on(upper, lower["points"][-1])
    height = abs(lower["points"][-1][1] - parent_y)
    check("the lower spiral ends at the L3 loop's height",
          height <= HEIGHT_TOLERANCE, "%.3f m" % height)

    loop = by_id["nanpu_pudong_loop"]
    road = by_id["pudong_south_rd"]
    plan_err, _tan, _y = _closest_on(road, loop["points"][-1])
    check("the Pudong loop lands on Pudong South Rd", plan_err <= PLAN_TOLERANCE,
          "%.2f m off the centre-line" % plan_err)
    err = tangent_error(loop, "attach_end", road)
    check("the Pudong loop runs along Pudong South Rd", err <= TANGENT_TOLERANCE,
          "%.1f deg" % err)

    ramp = by_id["ramp_l3_wb_sb"]
    ns = by_id["ns_elevated"]
    err = tangent_error(ramp, "attach_end", ns)
    check("the L3 WB>SB ramp runs along the N-S elevated", err <= TANGENT_TOLERANCE,
          "%.1f deg" % err)

    for rid in ("nanpu_spiral_lower", "nanpu_pudong_loop"):
        k = kink(by_id[rid])
        check("%s has no kink in its height profile" % rid, k <= KINK_LIMIT,
              "%.3f %% per 10 m" % (k * 100.0))

    print("selftest_attach_geometry: %d case(s) wrong" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
