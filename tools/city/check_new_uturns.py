#!/usr/bin/env python3
"""check_new_uturns — the U-turns a lane build adds: are they wide enough for a car? (lanes.json only, no Godot)

    python tools/city/check_new_uturns.py <lanes.json> --ref <reference lanes.json> [--min-chord M] [--max N]

A connector (a lane with "connector": true) that the reference build does not have (by id) and that turns by 150 degrees or more
between its first and its last direction is a U-turn. A car turns on a radius of 6 m or more: the two ends of a U-turn must be at
least --min-chord metres apart (default 12). With --max (default 12) the number of new U-turns is capped: a U-turn is the way out
of a dead end (job roads-dead-end-uturns), not a move of every junction.
Prints the new U-turns and "UTURNS OK" or "UTURNS FAIL n" (the narrow ones plus the ones over --max).
"""
import json
import math
import sys

TURN = 150.0


def heading_change(points):
    """the turn between the first and the last direction of a polyline, in degrees (unsigned, 0..180)"""
    a = (points[1][0] - points[0][0], points[1][2] - points[0][2])
    b = (points[-1][0] - points[-2][0], points[-1][2] - points[-2][2])
    la, lb = math.hypot(*a), math.hypot(*b)
    if la < 1e-6 or lb < 1e-6:
        return 0.0
    cos = max(-1.0, min(1.0, (a[0] * b[0] + a[1] * b[1]) / (la * lb)))
    return math.degrees(math.acos(cos))


def new_uturns(lanes, ref):
    old = {lane["id"] for lane in ref}
    out = []
    for lane in lanes:
        if not lane.get("connector") or lane["id"] in old or len(lane["points"]) < 3:
            continue
        if heading_change(lane["points"]) >= TURN:
            p, q = lane["points"][0], lane["points"][-1]
            out.append((lane["id"], math.hypot(q[0] - p[0], q[2] - p[2])))
    return out


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    for name in ("--ref", "--min-chord", "--max"):
        if name in argv:
            args.remove(argv[argv.index(name) + 1])
    if len(args) != 1 or "--ref" not in argv:
        print(__doc__)
        return 2
    lanes = json.load(open(args[0], encoding="utf-8"))["lanes"]
    ref = json.load(open(argv[argv.index("--ref") + 1], encoding="utf-8"))["lanes"]
    min_chord = float(argv[argv.index("--min-chord") + 1]) if "--min-chord" in argv else 12.0
    limit = int(argv[argv.index("--max") + 1]) if "--max" in argv else 12
    found = new_uturns(lanes, ref)
    narrow = [u for u in found if u[1] < min_chord]
    print("%d new U-turns, %d of them narrower than %.0f m (at most %d new ones)" % (len(found), len(narrow), min_chord, limit))
    for cid, chord in found[:20]:
        print("%s %s: the ends %.1f m apart" % ("NARROW" if chord < min_chord else "UTURN", cid, chord))
    bad = len(narrow) + max(0, len(found) - limit)
    print("UTURNS OK" if bad == 0 else "UTURNS FAIL %d" % bad)
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
