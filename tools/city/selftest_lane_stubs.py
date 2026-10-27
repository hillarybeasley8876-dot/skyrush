#!/usr/bin/env python3
"""selftest_lane_stubs — check_lane_stubs.py catches what it is for and lets through what is fine.

    python tools/city/selftest_lane_stubs.py [<reference lanes.json> <lanes.json with the stubs>]

Synthetic cases: a small lane graph (two roads through a junction) is the reference; every case changes it once and must give
exactly the verdict it names. With the two files (the lanes before and after job roads-junction-exits), the reference must pass
against itself and the later build must fail with the dead ends of Lujiazui Ring Rd. Prints one line per case and
"SELFTEST_LANE_STUBS OK" or "... FAIL n".
"""
import copy
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_lane_stubs as cls  # noqa: E402

failed = 0


def case(name, ok):
    global failed
    print("%s %s" % ("PASS" if ok else "FAIL", name))
    if not ok:
        failed += 1


def line(x0, z0, x1, z1, y=0.0, step=2.0):
    n = max(1, int(round(((x1 - x0) ** 2 + (z1 - z0) ** 2) ** 0.5 / step)))
    return [[x0 + (x1 - x0) * k / n, y, z0 + (z1 - z0) * k / n] for k in range(n + 1)]


def lane(lid, road, points, nxt=(), connector=False, terminus=None):
    out = {"id": lid, "road": road, "dir": 1, "points": points, "next": list(nxt)}
    if connector:
        out["connector"] = True
        out["junction"] = "j_a_b"
    if terminus:
        out["terminus"] = True
        out["terminus_kind"] = terminus
    return out


def reference():
    """road a runs east into a junction at x 50, road b leaves it east; a side road c starts at the map edge and ends at the
    junction (an old dead end: the reference has it too)."""
    return [
        lane("a_0", "a", line(0, 0, 40, 0), ["con_a_b"]),
        lane("con_a_b", "a", line(40, 0, 60, 0), ["b_0"], connector=True),
        lane("b_0", "b", line(60, 0, 120, 0), [], terminus="map_edge"),
        lane("c_0", "c", line(50, -60, 50, -10), [], terminus="junction"),
    ]


def verdict(lanes, ref, max_stubs=None):
    new_dead, new_orphans, stubs, rstubs = cls.compare(lanes, ref)
    limit = len(rstubs) if max_stubs is None else max_stubs
    return len(new_dead), len(new_orphans), max(0, len(stubs) - limit)


ref = reference()
case("the reference passes against itself", verdict(ref, ref) == (0, 0, 0))

# a stub between two cuts: 6 m of road b after the junction, no successor, no predecessor
lanes = copy.deepcopy(ref)
lanes.append(lane("b_stub", "b", line(62, 4, 68, 4), [], terminus="junction"))
case("a 6 m stub without links is a new dead end, a new orphan and a new stub", verdict(lanes, ref) == (1, 1, 1))
case("--max-stubs lets one more stub through (the dead end and the orphan still fail)", verdict(lanes, ref, max_stubs=1) == (1, 1, 0))

# a long lane that the junction no longer feeds: an orphan, not a stub
lanes = copy.deepcopy(ref)
lanes[1]["next"] = []
lanes[1]["terminus_kind"] = "junction"
case("a connector that lost its successor is a dead end and its lane an orphan", verdict(lanes, ref) == (1, 1, 0))

# the old dead end of road c moved by 1 m: the same end
lanes = copy.deepcopy(ref)
for p in lanes[3]["points"]:
    p[2] += 1.0
case("an old dead end 1 m away is the old one", verdict(lanes, ref) == (0, 0, 0))

# the same dead end 5 m up (another level): new
lanes = copy.deepcopy(ref)
for p in lanes[3]["points"]:
    p[1] += 5.0
case("a dead end on another level is new (and its start an orphan there)", verdict(lanes, ref) == (1, 1, 0))

# a stub that is linked both ways is still a stub
lanes = copy.deepcopy(ref)
lanes[1]["next"] = ["b_short"]
lanes.append(lane("b_short", "b", line(60, 0, 66, 0), ["con_b"]))
lanes.append(lane("con_b", "b", line(66, 0, 70, 0), ["b_0"], connector=True))
case("a linked 6 m lane is a stub only", verdict(lanes, ref) == (0, 0, 1))

# a dead end at the map edge or at a building is not a junction dead end
lanes = copy.deepcopy(ref)
lanes.append(lane("d_0", "d", line(0, 30, 40, 30), [], terminus="building"))
dead, orphans, _ = verdict(lanes, ref)
case("a lane that ends in a building is not a dead end at a junction", dead == 0 and orphans == 1)

if len(sys.argv) == 3:
    before = json.load(open(sys.argv[1], encoding="utf-8"))["lanes"]
    after = json.load(open(sys.argv[2], encoding="utf-8"))["lanes"]
    case("the lanes before the job pass against themselves", verdict(before, before) == (0, 0, 0))
    new_dead, new_orphans, stubs, rstubs = cls.compare(after, before)
    ids = {lane["id"] for lane in new_dead}
    case("the later build fails with the dead ends of Lujiazui Ring Rd",
         {"lujiazui_ring_rd_10_back0", "lujiazui_ring_rd_10_back1", "lujiazui_ring_rd_10_back2"} <= ids)

print("SELFTEST_LANE_STUBS OK" if failed == 0 else "SELFTEST_LANE_STUBS FAIL %d" % failed)
sys.exit(1 if failed else 0)
