#!/usr/bin/env python3
"""check_chain_links — lanes that continue into another road are linked to it (no Godot needed)

    python tools/city/check_chain_links.py <lanes.json> [--quiet] [--radius 6]

Two roads that meet end to end (the end of one is the start of the other, no junction between them) must be
joined by lane links, otherwise every car that drives up to the joint reaches a dead end.  The lane builder
used to link only junctions and mid-road ramp attaches, so the elevated chain ns_elevated -> inner_ring ->
nanpu_spiral_upper -> nanpu_bridge had no links at all (14 lanes ended in the air).

For every REGULAR lane u (not a connector) of road A, and every regular lane v of another road B whose start lies
within --radius metres (plan) and 1.5 m (height) of u's end, with a heading that differs by at most 40 degrees:
  A  u must have a successor      (u.next is not empty)
  B  v must have a predecessor    (some lane lists v in next)
  D  a pair that is linked is linked smoothly: directly (the ends are at most 1.6 m apart) or through exactly one
     connector lane (at most 60 m long); the heading changes at the joint by at most 30 degrees
  C  a pair whose ends are within 1.6 m (the same lane index) must be linked, unless u leads into a junction (j_ lanes)
  E  u is linked to at most 2 lanes of the other road (a merge or a split, not a lane-change bouquet)
Prints one line per failure and "CHAIN_LINKS OK" or "CHAIN_LINKS FAIL n".  Exit 0 when OK.
"""
import collections
import json
import math
import sys

CELL = 8.0
HEIGHT = 1.5
HEADING = 40.0
SMOOTH = 30.0


def heading(a, b):
    return math.degrees(math.atan2(b[0] - a[0], -(b[2] - a[2]))) % 360.0


def turn(a, b):
    return abs((a - b + 180.0) % 360.0 - 180.0)


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    quiet = "--quiet" in argv
    radius = float(argv[argv.index("--radius") + 1]) if "--radius" in argv else 6.0
    if "--radius" in argv:
        args.remove(argv[argv.index("--radius") + 1])
    lanes = json.load(open(args[0], encoding="utf-8"))["lanes"]
    by_id = {l["id"]: l for l in lanes}
    has_prev = set(n for l in lanes for n in l.get("next", []))
    starts = collections.defaultdict(list)
    for l in lanes:
        if l.get("connector"):
            continue
        p = l["points"][0]
        starts[(int(p[0] // CELL), int(p[2] // CELL))].append(l)
    out_head = lambda l: heading(l["points"][-2], l["points"][-1])   # noqa: E731
    in_head = lambda l: heading(l["points"][0], l["points"][1])      # noqa: E731
    bad, joints, direct = [], 0, 0
    pairs_by_u = collections.defaultdict(list)
    for u in lanes:
        if u.get("connector"):
            continue
        e = u["points"][-1]
        cx, cz = int(e[0] // CELL), int(e[2] // CELL)
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for v in starts.get((cx + dx, cz + dz), ()):
                    if v["road"] == u["road"]:
                        continue
                    s = v["points"][0]
                    d = math.hypot(s[0] - e[0], s[2] - e[2])
                    if d > radius or abs(s[1] - e[1]) > HEIGHT or turn(in_head(v), out_head(u)) > HEADING:
                        continue
                    pairs_by_u[u["id"]].append((d, v))
    fed = set()
    for uid, cands in pairs_by_u.items():
        u = by_id[uid]
        joints += 1
        linked_to = 0
        if not u.get("next"):
            bad.append("A  %s ends at a joint with %s but has no successor" % (uid, min(cands, key=lambda c: c[0])[1]["id"]))
        for d, v in cands:
            fed.add(v["id"])
            reach = None
            if v["id"] in u.get("next", []):
                reach = [u, v]
                if d > 1.6:
                    bad.append("D  %s -> %s is a direct link across %.1f m (use a connector lane)" % (uid, v["id"], d))
            else:
                for cid in u.get("next", []):
                    c = by_id.get(cid)
                    if c is not None and c.get("connector") and not cid.startswith("j_") and v["id"] in c.get("next", []):
                        reach = [u, c, v]
                        break
            if reach is None:
                if d <= 1.6 and not any(n.startswith("j_") for n in u.get("next", [])):
                    bad.append("C  %s does not reach %s (%.1f m apart, same lane index) directly or through one connector" % (uid, v["id"], d))
                continue
            direct += 1
            linked_to += 1
            for a_, b_ in zip(reach, reach[1:]):
                dh = turn(out_head(a_), in_head(b_))
                if dh > SMOOTH:
                    bad.append("D  the link %s -> %s turns %.0f degrees" % (a_["id"], b_["id"], dh))
            if len(reach) == 3:
                c = reach[1]
                length = sum(math.dist(p_, q_) for p_, q_ in zip(c["points"], c["points"][1:]))
                if length > 60.0:
                    bad.append("D  the connector %s is %.0f m long" % (c["id"], length))
        if linked_to > 2:
            bad.append("E  %s is linked to %d lanes of the other road" % (uid, linked_to))
    for vid in sorted(fed):
        if vid not in has_prev:
            bad.append("B  %s starts at a joint but has no predecessor" % vid)
    if not quiet:
        for line in bad[:60]:
            print("FAIL", line)
        if len(bad) > 60:
            print("... and %d more" % (len(bad) - 60))
    print("joints: %d lanes end at a joint with another road, %d pairs are linked" % (joints, direct))
    print("CHAIN_LINKS %s" % ("OK" if not bad else "FAIL %d" % len(bad)))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
