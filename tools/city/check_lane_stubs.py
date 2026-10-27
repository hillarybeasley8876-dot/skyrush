#!/usr/bin/env python3
"""check_lane_stubs — does a lane build leave lanes that a car cannot leave, cannot enter, or that are too short to hold one?
(lanes.json only, no Godot)

    python tools/city/check_lane_stubs.py <lanes.json> --ref <reference lanes.json> [--max-stubs N] [--quiet]

Compared with a reference build (the lanes before a change), by position: a lane end or start that the reference has at the same
place (within MATCH m, same level) is an old one.
DEAD_END   a lane without a successor that ends at a junction (terminus_kind "junction") where the reference has none: the
           traffic on it stops there for good (a car that drives into it never comes out).
ORPHAN     a road lane (not a junction connector) without a predecessor where the reference has none: no car can drive onto
           it; it only fills with the cars that spawn on it.
STUB       a road lane shorter than STUB_M m: shorter than a car with its gap. Two junctions whose cuts leave a few metres of
           road between them make one (job roads-junction-exits: 6 m of Lujiazui Ring Rd between the junctions of st_d7_ew_9
           and st_d7_ew_8; its southbound lanes had no successor, its northbound ones no predecessor). Counted, and compared
           with --max-stubs (default: the number of the reference).
Exit 0 when no DEAD_END and no ORPHAN is new and STUB <= the limit. Prints "LANE_STUBS OK" or "LANE_STUBS FAIL n".
"""
import json
import math
import sys
from collections import defaultdict

MATCH = 1.5     # m: an end of the reference this close (and on the same level) is the same end
LEVEL = 2.5     # m: two points are on the same level
STUB_M = 10.0   # m: a road lane shorter than this cannot hold a car and its gap


def plen(points):
    return sum(math.dist(a, b) for a, b in zip(points, points[1:]))


def ends(lanes):
    """(dead ends at a junction, road lanes without a predecessor, road lanes shorter than STUB_M)"""
    incoming = defaultdict(int)
    for lane in lanes:
        for nxt in lane.get("next") or []:
            incoming[nxt] += 1
    dead = [lane for lane in lanes if not lane.get("next") and lane.get("terminus_kind") == "junction"]
    orphans = [lane for lane in lanes if not lane.get("connector") and incoming[lane["id"]] == 0]
    stubs = [lane for lane in lanes if not lane.get("connector") and plen(lane["points"]) < STUB_M]
    return dead, orphans, stubs


class Points:
    """the end (or start) points of some lanes, for "is there one within MATCH m of here?" """

    def __init__(self, points):
        self.cells = defaultdict(list)
        for p in points:
            self.cells[(int(p[0] // 10), int(p[2] // 10))].append(p)

    def near(self, p):
        cx, cz = int(p[0] // 10), int(p[2] // 10)
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for q in self.cells.get((cx + dx, cz + dz), ()):
                    if math.hypot(q[0] - p[0], q[2] - p[2]) <= MATCH and abs(q[1] - p[1]) <= LEVEL:
                        return True
        return False


def compare(lanes, ref):
    dead, orphans, stubs = ends(lanes)
    rdead, rorphans, rstubs = ends(ref)
    old_dead = Points([lane["points"][-1] for lane in rdead])
    old_orphans = Points([lane["points"][0] for lane in rorphans])
    new_dead = [lane for lane in dead if not old_dead.near(lane["points"][-1])]
    new_orphans = [lane for lane in orphans if not old_orphans.near(lane["points"][0])]
    return new_dead, new_orphans, stubs, rstubs


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    for name in ("--ref", "--max-stubs"):
        if name in argv:
            args.remove(argv[argv.index(name) + 1])
    if len(args) != 1 or "--ref" not in argv:
        print(__doc__)
        return 2
    lanes = json.load(open(args[0], encoding="utf-8"))["lanes"]
    ref = json.load(open(argv[argv.index("--ref") + 1], encoding="utf-8"))["lanes"]
    new_dead, new_orphans, stubs, rstubs = compare(lanes, ref)
    limit = int(argv[argv.index("--max-stubs") + 1]) if "--max-stubs" in argv else len(rstubs)
    print("%d new dead ends at a junction, %d new lanes without a predecessor, %d lanes shorter than %.0f m (%d in the "
          "reference, at most %d)" % (len(new_dead), len(new_orphans), len(stubs), STUB_M, len(rstubs), limit))
    if "--quiet" not in argv:
        for lane in new_dead[:20]:
            print("DEAD_END %s: %.1f m long, ends at (%.1f, %.1f, %.1f)" % ((lane["id"], plen(lane["points"])) + tuple(lane["points"][-1])))
        for lane in new_orphans[:20]:
            print("ORPHAN %s: %.1f m long, starts at (%.1f, %.1f, %.1f)" % ((lane["id"], plen(lane["points"])) + tuple(lane["points"][0])))
        ref_ids = {lane["id"] for lane in rstubs}
        for lane in [s for s in stubs if s["id"] not in ref_ids][:20]:
            print("STUB %s: %.1f m long at (%.1f, %.1f, %.1f)" % ((lane["id"], plen(lane["points"])) + tuple(lane["points"][0])))
    bad = len(new_dead) + len(new_orphans) + max(0, len(stubs) - limit)
    print("LANE_STUBS OK" if bad == 0 else "LANE_STUBS FAIL %d" % bad)
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
