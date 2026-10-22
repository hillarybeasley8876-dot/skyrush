#!/usr/bin/env python3
"""make_chain_paths — one drivable path per end-to-end road joint, from lanes.json (for `gd.py drive --follow=`).

    python tools/city/make_chain_paths.py <lanes.json> <outdir> [--reach 140] [--radius 6]

Finds the joints like check_chain_links (a regular lane of one road whose end is within --radius of the start of a
regular lane of another road, heading within 40 degrees, height within 1.5 m), keeps the pair of lanes with the
same index nearest to each other per joint and direction, and writes a path that drives --reach metres up to the joint,
through the link (a direct link or one connector lane) and --reach metres on, as <outdir>/chain.<lane u>.json:
  {"id", "chain", "points", "speed_kmh", "end_radius", "spawn"}   (the format of make_attach_paths)
A joint whose lanes are not linked is reported and skipped.
"""
import collections
import json
import math
import os
import sys

CELL = 8.0


def heading(a, b):
    return math.degrees(math.atan2(b[0] - a[0], -(b[2] - a[2]))) % 360.0


def turn(a, b):
    return abs((a - b + 180.0) % 360.0 - 180.0)


def tail(points, reach):
    out, acc = [points[-1]], 0.0
    for a, b in zip(reversed(points[:-1]), reversed(points)):
        acc += math.dist(a, b)
        out.append(a)
        if acc >= reach:
            break
    return out[::-1]


def head(points, reach):
    out, acc = [points[0]], 0.0
    for a, b in zip(points, points[1:]):
        acc += math.dist(a, b)
        out.append(b)
        if acc >= reach:
            break
    return out


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    opt = lambda n, d: float(argv[argv.index(n) + 1]) if n in argv else d  # noqa: E731
    reach, radius = opt("--reach", 140.0), opt("--radius", 6.0)
    for n in ("--reach", "--radius"):
        if n in argv:
            args.remove(argv[argv.index(n) + 1])
    lanes = json.load(open(args[0], encoding="utf-8"))["lanes"]
    out_dir = args[1]
    os.makedirs(out_dir, exist_ok=True)
    by_id = {l["id"]: l for l in lanes}
    starts = collections.defaultdict(list)
    for l in lanes:
        if not l.get("connector"):
            p = l["points"][0]
            starts[(int(p[0] // CELL), int(p[2] // CELL))].append(l)
    made, unlinked = 0, []
    for u in lanes:
        if u.get("connector"):
            continue
        e = u["points"][-1]
        best = None
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for v in starts.get((int(e[0] // CELL) + dx, int(e[2] // CELL) + dz), ()):
                    if v["road"] == u["road"]:
                        continue
                    s = v["points"][0]
                    d = math.hypot(s[0] - e[0], s[2] - e[2])
                    if d > radius or abs(s[1] - e[1]) > 1.5:
                        continue
                    if turn(heading(v["points"][0], v["points"][1]), heading(u["points"][-2], u["points"][-1])) > 40.0:
                        continue
                    if best is None or d < best[0]:
                        best = (d, v)
        if best is None or best[0] > 1.6:
            continue
        v = best[1]
        chain = None
        if v["id"] in u.get("next", []):
            chain = [u, v]
        else:
            for cid in u.get("next", []):
                c = by_id.get(cid)
                if c is not None and c.get("connector") and not cid.startswith("j_") and v["id"] in c.get("next", []):
                    chain = [u, c, v]
                    break
        if chain is None:
            if not any(n.startswith("j_") for n in u.get("next", [])):
                unlinked.append(u["id"])
            continue
        pts = []
        for n, lane in enumerate(chain):
            p = lane["points"]
            p = tail(p, reach) if n == 0 else head(p, reach) if n == len(chain) - 1 else p
            for q in p:
                if not pts or math.dist(pts[-1], q) > 0.5:
                    pts.append(q)
        h = heading(pts[0], pts[min(6, len(pts) - 1)])
        doc = {"id": "chain.%s" % u["id"], "chain": [c["id"] for c in chain],
               "points": [[round(x, 2), round(y, 2), round(z, 2)] for x, y, z in pts],
               "speed_kmh": 60.0, "end_radius": 10.0,
               "spawn": [round(pts[0][0], 2), round(pts[0][1] + 0.5, 2), round(pts[0][2], 2), round(-h, 1)]}
        with open(os.path.join(out_dir, "chain.%s.json" % u["id"]), "w", encoding="utf-8") as fh:
            json.dump(doc, fh)
        made += 1
    print("CHAIN PATHS written: %d in %s; unlinked: %s" % (made, out_dir, ", ".join(unlinked) or "none"))
    return 1 if unlinked else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
