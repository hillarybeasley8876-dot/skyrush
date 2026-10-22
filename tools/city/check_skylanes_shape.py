#!/usr/bin/env python3
"""check_skylanes_shape — the sky lanes of a city.json keep the shape the game expects.

    python tools/city/check_skylanes_shape.py <city.json>

validate.py checks the pad, the run-up, the pitch, the clearance and the rings. It cannot tell a real
flight corridor from a 50 m stub, so this adds: the five lanes exist, are long, the two river lanes
really fly over the Huangpu and land on the far side, and the first point is exactly the pad.
"""
import json
import math
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0] if "/" in __file__ else ".")
import citylib  # noqa: E402

EXPECTED = ("huangpu_jump", "dragon_stack", "century_canyon", "nanpu_cables", "bund_riverside")
RIVER_LANES = ("huangpu_jump", "bund_riverside")
MIN_LENGTH = 300.0
MIN_OVER_RIVER = 200.0


def length(points):
    return sum(math.dist((a[0], a[2]), (b[0], b[2])) for a, b in zip(points, points[1:]))


def over_river(points, polygon):
    """Metres of the lane (sampled every 5 m) that fly over the Huangpu polygon."""
    metres = 0.0
    for a, b in zip(points, points[1:]):
        run = math.dist((a[0], a[2]), (b[0], b[2]))
        n = max(1, int(run / 5.0))
        for k in range(n):
            t = (k + 0.5) / n
            x = a[0] + (b[0] - a[0]) * t
            z = a[2] + (b[2] - a[2]) * t
            if citylib.point_in_polygon((x, z), polygon):
                metres += run / n
    return metres


def main(path):
    city = json.load(open(path, encoding="utf-8"))
    lanes = {s["id"]: s for s in city["sky_lanes"]}
    river = next(w["polygon"] for w in city["water"] if w["id"] == "huangpu")
    bad = []
    for lid in EXPECTED:
        if lid not in lanes:
            bad.append("sky lane %s is missing" % lid)
    for lid in sorted(set(lanes) - set(EXPECTED)):
        bad.append("sky lane %s is not one of the five" % lid)
    for lid in EXPECTED:
        lane = lanes.get(lid)
        if lane is None:
            continue
        pts, pad = lane["points"], lane["pad"]
        if length(pts) < MIN_LENGTH:
            bad.append("sky lane %s is only %.0f m long (at least %.0f)" % (lid, length(pts), MIN_LENGTH))
        start = math.dist(pts[0], (pad["x"], pad["y"], pad["z"]))
        if start > 0.5:
            bad.append("sky lane %s: the first point is %.2f m from the pad (must be the pad)" % (lid, start))
        if lid in RIVER_LANES:
            metres = over_river(pts, river)
            if metres < MIN_OVER_RIVER:
                bad.append("sky lane %s flies only %.0f m over the Huangpu (at least %.0f)" % (lid, metres, MIN_OVER_RIVER))
            if citylib.point_in_polygon((pts[-1][0], pts[-1][2]), river):
                bad.append("sky lane %s ends over the water, it must land on the far bank" % lid)
        if len(lane.get("n2_rings_m", [])) < 1:
            bad.append("sky lane %s has no N2 ring" % lid)
    for line in bad:
        print("FAIL", line)
    print("SKYLANES_SHAPE %s (%d lanes: %s)" % ("FAIL" if bad else "OK", len(lanes),
                                                 ", ".join("%s=%.0fm" % (k, length(v["points"])) for k, v in lanes.items())))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
