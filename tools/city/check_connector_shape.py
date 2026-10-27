#!/usr/bin/env python3
"""check_connector_shape — does a junction connector take the way a car would drive, or does it loop? (lanes.json only, no Godot)

    python tools/city/check_connector_shape.py <lanes.json> [--ref <lanes.json>] [--max N] [--quiet]

A connector (a lane with "connector": true and a "junction") is the path of one movement through a junction. Its shape follows
the junction that built it (the centre and the fan of that junction). When two junction records describe one crossing (two side
streets that meet a road a few metres apart) both build the same movement, and job roads-lane-dupes keeps the first one: for the
straight movement of Lujiazui Ring Rd at st_d7_ew_16 / st_d7_ew_17 the one it kept is 61.6 m long for a chord of 24.2 m and turns
167 degrees on the way (the other was 24.7 m and smooth). The race of the Lujiazui ring turned off the ring there, and four rivals
needed the marshal at its start (`test_real_start.gd`).

LOOP   the turning of the connector in both directions together exceeds its net turn by more than LOOP_DEG degrees (it winds back
       and forth, or round a loop), or its length is more than STRETCH times its chord plus STRETCH_PAD metres
KINK   one step of the polyline turns by more than KINK_DEG degrees (a corner that no car drives)
With --ref the kinds are compared by movement (the lane before and the lane after the connector): a movement that the reference
build has with the same defect is an old one. Exit 0 when the new defects are at most --max (default 0); without --ref every
defect counts. Prints "CONNECTOR_SHAPE OK" or "CONNECTOR_SHAPE FAIL n".
"""
import json
import math
import sys
from collections import Counter

LOOP_DEG = 60.0     # degrees of turning beyond the net turn
STRETCH = 1.6       # length over chord
STRETCH_PAD = 6.0   # m
KINK_DEG = 50.0     # degrees in one step


def steps(points):
    out = []
    for a, b in zip(points, points[1:]):
        dx, dz = b[0] - a[0], b[2] - a[2]
        if math.hypot(dx, dz) > 0.05:
            out.append(math.atan2(dz, dx))
    return out


def wrap(angle):
    while angle > math.pi:
        angle -= 2 * math.pi
    while angle < -math.pi:
        angle += 2 * math.pi
    return angle


def shape(points):
    """(length, chord, net turn, turning both ways, worst step), the angles in degrees"""
    length = sum(math.hypot(b[0] - a[0], b[2] - a[2]) for a, b in zip(points, points[1:]))
    chord = math.hypot(points[-1][0] - points[0][0], points[-1][2] - points[0][2])
    heads = steps(points)
    turns = [wrap(b - a) for a, b in zip(heads, heads[1:])]
    net = math.degrees(sum(turns))
    both = math.degrees(sum(abs(t) for t in turns))
    worst = math.degrees(max((abs(t) for t in turns), default=0.0))
    return length, chord, net, both, worst


def defects(lanes):
    """{(from lane, to lane): (kind, connector id, length, chord, net, both, worst)}"""
    before = {}
    for lane in lanes:
        for nxt in lane.get("next") or []:
            before.setdefault(nxt, lane["id"])
    out = {}
    for lane in lanes:
        if not lane.get("connector") or not lane.get("junction") or len(lane["points"]) < 3:
            continue
        length, chord, net, both, worst = shape(lane["points"])
        kind = None
        if both - abs(net) > LOOP_DEG or length > STRETCH * chord + STRETCH_PAD:
            kind = "LOOP"
        elif worst > KINK_DEG:
            kind = "KINK"
        if kind:
            key = (before.get(lane["id"], "?"), (lane.get("next") or ["?"])[0])
            out[key] = (kind, lane["id"], length, chord, net, both, worst)
    return out


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    for name in ("--ref", "--max"):
        if name in argv:
            args.remove(argv[argv.index(name) + 1])
    if len(args) != 1:
        print(__doc__)
        return 2
    found = defects(json.load(open(args[0], encoding="utf-8"))["lanes"])
    old = {}
    if "--ref" in argv:
        old = defects(json.load(open(argv[argv.index("--ref") + 1], encoding="utf-8"))["lanes"])
    new = {k: v for k, v in found.items() if k not in old or old[k][0] != v[0]}
    limit = int(argv[argv.index("--max") + 1]) if "--max" in argv else 0
    kinds = Counter(v[0] for v in found.values())
    print("%d connectors with a defect (%s), %d of them new%s" % (
        len(found), ", ".join("%s %d" % kv for kv in sorted(kinds.items())) or "none", len(new),
        " against the reference (%d there)" % len(old) if "--ref" in argv else ""))
    if "--quiet" not in argv:
        for key, (kind, cid, length, chord, net, both, worst) in sorted(new.items(), key=lambda kv: -kv[1][5])[:25]:
            print("%s %s: %.1f m for a chord of %.1f m, net turn %+.0f deg, turning %.0f deg, worst step %.0f deg" % (
                kind, cid, length, chord, net, both, worst))
    ok = len(new) <= limit
    print("CONNECTOR_SHAPE OK" if ok else "CONNECTOR_SHAPE FAIL %d" % len(new))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
