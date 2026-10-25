#!/usr/bin/env python3
"""selftest_skylanes — the five sky lanes of the map are playable corridors.

The rule of the validator (city_rules_routes.check_sky_lanes) is one
opinion; this is a second one, written from the brief: a launch pad on a
lane centre with 300 m of straight run-up behind it, a lane that starts
exactly on the pad and leaves the way the pad points, a gentle pitch, a
clearance of 10 m over every lot it flies over, a landing over a drivable
lane, and a flight corridor that keeps its shape (long, with its N2 rings,
and over the Huangpu for the two river lanes).

    python tools/city/selftest_skylanes.py [city.json]

Without a path the test builds the map into the scratch folder and reads
it from there.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import citylib        # noqa: E402
from city_json import load_json   # noqa: E402

LANES = ("huangpu_jump", "dragon_stack", "century_canyon", "nanpu_cables",
         "bund_riverside")
RIVER_LANES = ("huangpu_jump", "bund_riverside")
EXEMPT = ("landmark:dragon_pillar", "landmark:nanpu_tower_w",
          "landmark:nanpu_tower_e")
RUN_UP = 300.0                 # the straight run-up of a launch pad
RUN_UP_TURN = 3.0              # degrees of heading change over the run-up
HEADING_TOLERANCE = 10.0       # degrees
PITCH_LIMIT = 26.0             # degrees over 60 m (the lanes climb at 25)
CLEARANCE = 10.0               # the lane clears the lots by 10 m
RING_SPACING = 250.0           # the N2 rings along a lane
MAX_CRUISE = 240.0             # the highest a sky lane flies (the player asked for
                               # higher flights, 2026-10-25: up to 220 m)
MIN_LENGTH = 300.0             # the shortest a sky lane may be
OVER_RIVER = 200.0             # the river lanes cross the Huangpu
SCRATCH = "F:/dev/skyrush-out/tmp/city-skylanes/city.json"

fails = []


def fail(msg):
    fails.append(msg)
    print("FAIL", msg)


def angle_diff(a, b):
    return abs((a - b + 180.0) % 360.0 - 180.0)


def stations(road):
    """The cumulative distances of the stations of a road."""
    cum = [0.0]
    for a, b in zip(road["points"], road["points"][1:]):
        cum.append(cum[-1] + math.dist((a[0], a[2]), (b[0], b[2])))
    return cum


def heading_at(road, cum, s):
    """The heading of the centre-line of a road at the distance `s`."""
    pts = road["points"]
    best = min(range(len(cum)), key=lambda i: abs(cum[i] - s))
    a = pts[max(0, best - 1)]
    b = pts[min(len(pts) - 1, best + 1)]
    return math.degrees(math.atan2(b[0] - a[0], -(b[2] - a[2]))) % 360.0


def lane_lines(road):
    """The lane centre polylines of a road: [(points, direction)]."""
    out = []
    pts = road["points"]
    for direction, count in ((1, road["lanes_fwd"]), (-1, road["lanes_back"])):
        for index in range(count):
            offset = road["median"] * 0.5 + (index + 0.5) * road["lane_width"]
            line = []
            for i, p in enumerate(pts):
                a = pts[max(0, i - 1)]
                b = pts[min(len(pts) - 1, i + 1)]
                dx, dz = b[0] - a[0], b[2] - a[2]
                length = math.hypot(dx, dz) or 1.0
                sign = 1.0 if direction > 0 else -1.0
                line.append((p[0] - dz / length * offset * sign, p[1],
                             p[2] + dx / length * offset * sign))
            out.append((line, direction))
    return out


def nearest_lane(roads, point):
    """The lane centre closest to the plan position.

    Returns (distance, heading, direction, road id) or None.
    """
    best = None
    for road in roads:
        for line, direction in lane_lines(road):
            for i in range(len(line) - 1):
                a, b = line[i], line[i + 1]
                d = citylib.point_seg_distance(point, (a[0], a[2]), (b[0], b[2]))
                if best is None or d < best[0]:
                    head = math.degrees(math.atan2(b[0] - a[0],
                                                   -(b[2] - a[2]))) % 360.0
                    if direction < 0:
                        head = (head + 180.0) % 360.0
                    best = (d, head, direction, road["id"])
    return best


def block_height(blocks, x, z):
    """The height of the tallest lot under the plan position."""
    best = 0.0
    for b in blocks:
        if b.get("notes") in EXEMPT:
            continue
        if citylib.point_in_polygon((x, z), b["polygon"]):
            best = max(best, b["height_m"][1])
    return best


def check_lane(lane, city, roads):
    """The checks of one sky lane."""
    lid = lane["id"]
    pts = lane["points"]
    pad = lane["pad"]
    if len(pts) < 2:
        fail("lane %s has no points" % lid)
        return
    # the lane starts exactly on the pad
    start = math.dist(pts[0], (pad["x"], pad["y"], pad["z"]))
    if start > 0.5:
        fail("lane %s starts %.2f m from the pad" % (lid, start))
    # the pad stands on a lane centre, with its heading
    found = nearest_lane(roads, (pad["x"], pad["z"]))
    if found is None or found[0] > 0.5:
        fail("lane %s: the pad is %.2f m from a lane centre"
             % (lid, found[0] if found else -1.0))
        return
    if angle_diff(found[1], pad["heading_deg"]) > HEADING_TOLERANCE:
        fail("lane %s: the pad heads %.0f deg, the lane %.0f"
             % (lid, pad["heading_deg"], found[1]))
    # the run-up: 300 m of road behind the pad that barely turns
    road = [r for r in roads if r["id"] == found[3]][0]
    cum = stations(road)
    s_pad = _nearest_s(road, cum, pad)
    if s_pad < RUN_UP - 1.0:
        fail("lane %s: only %.0f m of run-up behind the pad"
             % (lid, s_pad))
    else:
        turn = angle_diff(heading_at(road, cum, s_pad),
                          heading_at(road, cum, s_pad - RUN_UP))
        if turn > RUN_UP_TURN:
            fail("lane %s: the run-up turns %.1f deg over %.0f m"
                 % (lid, turn, RUN_UP))
    # the lane leaves the way the pad points
    head = math.degrees(math.atan2(pts[1][0] - pts[0][0],
                                   -(pts[1][2] - pts[0][2]))) % 360.0
    if angle_diff(head, pad["heading_deg"]) > HEADING_TOLERANCE:
        fail("lane %s: the first segment heads %.0f deg, the pad %.0f"
             % (lid, head, pad["heading_deg"]))
    # the pitch and the clearance
    for a, b in zip(pts, pts[1:]):
        run = math.hypot(b[0] - a[0], b[2] - a[2])
        if run > 60.0:
            pitch = abs(math.degrees(math.atan2(b[1] - a[1], run)))
            if pitch > PITCH_LIMIT:
                fail("lane %s: %.0f deg pitch over %.0f m" % (lid, pitch, run))
                break
    for a, b in zip(pts, pts[1:]):
        run = math.hypot(b[0] - a[0], b[2] - a[2])
        steps = max(1, int(run / 5.0))
        for k in range(steps + 1):
            t = float(k) / steps
            x = a[0] + (b[0] - a[0]) * t
            z = a[2] + (b[2] - a[2]) * t
            y = a[1] + (b[1] - a[1]) * t
            top = block_height(city["blocks"], x, z)
            if top and y < top + CLEARANCE - 0.05:
                fail("lane %s: %.0f m over a lot of %.0f m at (%.0f, %.0f)"
                     % (lid, y, top, x, z))
                break
        else:
            continue
        break
    # the shape of the corridor
    length = sum(math.dist((a[0], a[2]), (b[0], b[2])) for a, b in zip(pts, pts[1:]))
    if length < MIN_LENGTH:
        fail("lane %s is only %.0f m long" % (lid, length))
    if max(p[1] for p in pts) > MAX_CRUISE:
        fail("lane %s flies at %.0f m" % (lid, max(p[1] for p in pts)))
    rings = lane.get("n2_rings_m", [])
    if not rings:
        fail("lane %s has no N2 ring" % lid)
    elif rings[0] > RING_SPACING + 1.0:
        fail("lane %s: the first ring is at %.0f m" % (lid, rings[0]))
    for a, b in zip(rings, rings[1:]):
        if b - a > RING_SPACING + 1.0:
            fail("lane %s: %.0f m between the rings" % (lid, b - a))
    # the landing is over a drivable lane: the spiral ramps have a lane at
    # every level, so the lane of the right height counts
    end = pts[-1]
    cands = []
    for r in city["roads"]:
        if r["kind"] == "tunnel":
            continue
        for line, direction in lane_lines(r):
            for i in range(len(line) - 1):
                a, b = line[i], line[i + 1]
                d = citylib.point_seg_distance((end[0], end[2]),
                                                (a[0], a[2]), (b[0], b[2]))
                if d <= 7.0:
                    cands.append((abs(a[1] - end[1]), d, a[1]))
    if not cands:
        fail("lane %s: the end is not over a drivable lane" % lid)
        return
    cands.sort()
    _dh, _d, height = cands[0]
    if not -5.0 <= end[1] - height <= 15.0:
        fail("lane %s: the end is %.1f m above the lane"
             % (lid, end[1] - height))
    # the river lanes cross the Huangpu and land on the far bank
    if lid in RIVER_LANES:
        river = next(w["polygon"] for w in city["water"] if w["id"] == "huangpu")
        over = 0.0
        for a, b in zip(pts, pts[1:]):
            run = math.dist((a[0], a[2]), (b[0], b[2]))
            steps = max(1, int(run / 5.0))
            for k in range(steps):
                t = (k + 0.5) / steps
                x = a[0] + (b[0] - a[0]) * t
                z = a[2] + (b[2] - a[2]) * t
                if citylib.point_in_polygon((x, z), river):
                    over += run / steps
        if over < OVER_RIVER:
            fail("lane %s flies only %.0f m over the Huangpu" % (lid, over))
        if citylib.point_in_polygon((end[0], end[2]), river):
            fail("lane %s ends over the water" % lid)


def _nearest_s(road, cum, pad):
    """The station of the road that is closest to the pad."""
    best = 0.0
    best_d = 1e18
    for i, p in enumerate(road["points"]):
        d = math.hypot(p[0] - pad["x"], p[2] - pad["z"])
        if d < best_d:
            best_d, best = d, cum[i]
    return best


def main(path=None):
    if path is None:
        path = SCRATCH
        if not os.path.exists(path):
            import build_city
            os.makedirs(os.path.dirname(path), exist_ok=True)
            build_city.main(out=path)
    city = load_json(path)
    roads = city["roads"]
    lanes = {l["id"]: l for l in city["sky_lanes"]}
    for lid in LANES:
        if lid not in lanes:
            fail("sky lane %s is missing" % lid)
    for lid in lanes:
        if lid not in LANES:
            fail("sky lane %s is not one of the five" % lid)
    for lid in LANES:
        if lid in lanes:
            check_lane(lanes[lid], city, roads)
    if fails:
        print("SELFTEST FAIL (%d)" % len(fails))
        return 1
    print("SELFTEST OK (%d lanes: %s)" %
          (len(lanes), ", ".join("%s=%.0fm" % (k, sum(
              math.dist((a[0], a[2]), (b[0], b[2]))
              for a, b in zip(lanes[k]["points"], lanes[k]["points"][1:])))
              for k in sorted(lanes))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else None))

