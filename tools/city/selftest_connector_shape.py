#!/usr/bin/env python3
"""selftest_connector_shape — check_connector_shape.py catches the connectors that loop or kink and lets the smooth ones through.

    python tools/city/selftest_connector_shape.py [<lanes.json>]

Synthetic connectors (a quarter turn, a straight one, a lane change, a U-turn, one that backs up, one with a corner, one that
bows far out); with a lanes.json, the looping connector of Lujiazui Ring Rd at st_d7_ew_16 must be found if the file has it.
Prints one line per case and "SELFTEST_CONNECTOR_SHAPE OK" or "... FAIL n".
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_connector_shape as ccs  # noqa: E402

failed = 0


def case(name, ok):
    global failed
    print("%s %s" % ("PASS" if ok else "FAIL", name))
    if not ok:
        failed += 1


def conn(cid, points, src="a", dst="b"):
    return [{"id": src, "points": [[0, 0, 0], [1, 0, 0]], "next": [cid]},
            {"id": cid, "connector": True, "junction": "j", "points": points, "next": [dst]},
            {"id": dst, "points": [[0, 0, 0], [1, 0, 0]], "next": []}]


def kind(points):
    found = ccs.defects(conn("c", points))
    return found[("a", "b")][0] if found else None


def arc(radius, degrees, n=20, start=0.0):
    out = []
    for k in range(n + 1):
        t = math.radians(start + degrees * k / n)
        out.append([radius * math.sin(t), 0.0, radius * (1 - math.cos(t))])
    return out


case("a quarter turn of 12 m is fine", kind(arc(12.0, 90.0)) is None)
case("a straight connector is fine", kind([[x * 2.0, 0.0, 0.0] for x in range(15)]) is None)
lane_change = [[x * 2.0, 0.0, 3.5 * (0.5 - 0.5 * math.cos(math.pi * x / 14))] for x in range(15)]
case("a lane change of 3.5 m over 28 m is fine", kind(lane_change) is None)
case("a U-turn of 8 m radius is fine", kind(arc(8.0, 180.0, 24)) is None)
backs_up = [[x * 2.0, 0.0, 0.0] for x in range(8)] + [[12.6, 0.0, 0.3], [13.2, 0.0, 0.6]] + [[14.0 + x * 2.0, 0.0, 0.6] for x in range(6)]
backs_up[8] = [13.4, 0.0, 0.0]
backs_up[9] = [12.6, 0.0, 0.05]
case("a connector that backs up 0.8 m is a LOOP", kind(backs_up) == "LOOP")
corner = [[x * 2.0, 0.0, 0.0] for x in range(8)] + [[14.0 + x * 2.0 * math.cos(math.radians(60)), 0.0, x * 2.0 * math.sin(math.radians(60))] for x in range(1, 8)]
case("a corner of 60 degrees in one step is a KINK", kind(corner) == "KINK")
bow = [[24.2 * k / 30, 0.0, 20.0 * math.sin(math.pi * k / 30)] for k in range(31)]
case("a straight movement that bows 20 m out over a 24 m chord is a LOOP", kind(bow) == "LOOP")
loop = arc(6.0, 360.0, 36)
case("a full loop is a LOOP", kind(loop) == "LOOP")

ref = conn("c", backs_up)
found = ccs.defects(ref)
case("the same defect in the reference is an old one", ("a", "b") in found and found[("a", "b")][0] == "LOOP")

if len(sys.argv) > 1:
    lanes = json.load(open(sys.argv[1], encoding="utf-8"))["lanes"]
    ids = {lane["id"] for lane in lanes}
    cid = "j_lujiazui_ring_rd_st_d7_ew_16_lujiazui_ring_rd_5_fwd2_straight_lujiazui_ring_rd_6_fwd2"
    if cid in ids:
        found = ccs.defects(lanes)
        case("the 61.6 m connector of Lujiazui Ring Rd at st_d7_ew_16 is a LOOP",
             any(v[1] == cid and v[0] == "LOOP" for v in found.values()))
    else:
        print("SKIP the file has no %s" % cid)

print("SELFTEST_CONNECTOR_SHAPE OK" if failed == 0 else "SELFTEST_CONNECTOR_SHAPE FAIL %d" % failed)
sys.exit(1 if failed else 0)
