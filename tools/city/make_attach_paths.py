#!/usr/bin/env python3
"""make_attach_paths — one drivable path per ramp attach, from lanes.json (for `gd.py drive --follow=`).

    python tools/city/make_attach_paths.py <lanes.json> <city.json> <outdir> [--reach 120] [--max-turn 30]

For every attach of every ramp: the best chain of lanes parent -> [connector] -> ramp (the ramp leaves its parent)
or ramp -> [connector] -> parent (the ramp joins it), joints turning at most --max-turn degrees, cut to --reach metres
before and after the joint, written as <outdir>/<ramp>.<attach_start|attach_end>.json:
  {"id", "points": [[x,y,z]...], "speed_kmh", "end_radius", "spawn": [x, y, z, yaw_deg]}
The spawn is the first point lifted 0.5 m, with the yaw the game expects (-heading).
"""
import json
import math
import os
import sys

TOL = 60.0
DEPTH = 3


def heading(a, b):
    return math.degrees(math.atan2(b[0] - a[0], -(b[2] - a[2]))) % 360.0


def diff(a, b):
    return abs((a - b + 180.0) % 360.0 - 180.0)


def end_heading(lane, end):
    pts = lane["points"]
    if end == 1:
        j = len(pts) - 1
        i = j
        while i > 0 and math.dist(pts[i], pts[j]) < 4.0:
            i -= 1
        return heading(pts[i], pts[j])
    i = j = 0
    while j < len(pts) - 1 and math.dist(pts[i], pts[j]) < 4.0:
        j += 1
    return heading(pts[i], pts[j])


def plen(points):
    return sum(math.dist(a, b) for a, b in zip(points, points[1:]))


def tail(points, reach):
    """The last `reach` metres of a polyline."""
    out, acc = [points[-1]], 0.0
    for a, b in zip(reversed(points[:-1]), reversed(points)):
        acc += math.dist(a, b)
        out.append(a)
        if acc >= reach:
            break
    return out[::-1]


def head(points, reach):
    """The first `reach` metres of a polyline."""
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
    reach, max_turn = opt("--reach", 120.0), opt("--max-turn", 30.0)
    for n in ("--reach", "--max-turn"):
        if n in argv:
            args.remove(argv[argv.index(n) + 1])
    doc = json.load(open(args[0], encoding="utf-8"))
    city = json.load(open(args[1], encoding="utf-8"))
    out_dir = args[2]
    os.makedirs(out_dir, exist_ok=True)
    lanes = {l["id"]: l for l in doc["lanes"]}
    by_road = {}
    for l in doc["lanes"]:
        by_road.setdefault(l["road"], []).append(l)
    adj = {}
    for k in doc.get("links", []):
        adj.setdefault(k["from"], set()).add(k["to"])
    for l in doc["lanes"]:
        for n in l.get("next", []):
            adj.setdefault(l["id"], set()).add(n)

    def chains(src, goals):
        """Shortest smooth chains of lane ids from src to any lane of goals (BFS, at most DEPTH hops)."""
        frontier = [[src["id"]]]
        found = []
        for _ in range(DEPTH):
            nxt = []
            for chain in frontier:
                a = lanes[chain[-1]]
                for to in sorted(adj.get(chain[-1], ())):
                    b = lanes.get(to)
                    if b is None or to in chain or diff(end_heading(a, 1), end_heading(b, 0)) > max_turn:
                        continue
                    if to in goals:
                        found.append(chain + [to])
                    else:
                        nxt.append(chain + [to])
            if found:
                return found
            frontier = nxt
        return found

    made, missing = 0, []
    for road in city["roads"]:
        if road["kind"] != "ramp":
            continue
        for key, idx in (("attach_start", 0), ("attach_end", -1)):
            att = road.get(key)
            if not att:
                continue
            cp = road["points"][idx]
            near = lambda p: math.dist((p[0], p[2]), (cp[0], cp[2]))  # noqa: E731
            ramp_lanes = [l for l in by_road.get(road["id"], []) if not l.get("connector")]
            parent_lanes = [l for l in by_road.get(att["road"], []) if not l.get("connector")]
            best = None
            if key == "attach_start":
                sources = [l for l in parent_lanes if near(l["points"][-1]) <= TOL]
                goals = {l["id"] for l in ramp_lanes if near(l["points"][0]) <= TOL}
            else:
                sources = [l for l in ramp_lanes if near(l["points"][-1]) <= TOL]
                goals = {l["id"] for l in parent_lanes if near(l["points"][0]) <= TOL}
            for s in sources:
                for chain in chains(s, goals):
                    cost = sum(plen(lanes[c]["points"]) for c in chain[1:-1])
                    if best is None or cost < best[0]:
                        best = (cost, chain)
            if best is None:
                missing.append("%s.%s" % (road["id"], key))
                continue
            chain = [lanes[c] for c in best[1]]
            pts = []
            for n, lane in enumerate(chain):
                p = lane["points"]
                p = tail(p, reach) if n == 0 else head(p, reach) if n == len(chain) - 1 else p
                for q in p:
                    if not pts or math.dist(pts[-1], q) > 0.5:
                        pts.append(q)
            h = heading(pts[0], pts[min(6, len(pts) - 1)])
            doc_out = {"id": "%s.%s" % (road["id"], key), "chain": best[1],
                       "points": [[round(x, 2), round(y, 2), round(z, 2)] for x, y, z in pts],
                       "speed_kmh": 55.0, "end_radius": 10.0,
                       "spawn": [round(pts[0][0], 2), round(pts[0][1] + 0.5, 2), round(pts[0][2], 2), round(-h, 1)]}
            with open(os.path.join(out_dir, "%s.%s.json" % (road["id"], key)), "w", encoding="utf-8") as fh:
                json.dump(doc_out, fh)
            made += 1
    print("PATHS written: %d in %s; no smooth chain for: %s" % (made, out_dir, ", ".join(missing) or "none"))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
