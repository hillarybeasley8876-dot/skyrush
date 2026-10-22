#!/usr/bin/env python3
"""check_routes_drivable — can the game build a lane-following racing line for every route? (no Godot needed)

    python tools/city/check_routes_drivable.py <city.json> <lanes.json> [--quiet] [--max-bad N]

A Python replica of what game/world/api/route_builder.gd does when a race starts: for every leg between two
checkpoints it takes the lanes within 8 m (plan distance, as LaneSpatial.query does) whose direction agrees with
the gate (dot >= 0.3), searches the shortest lane path from any of them to any lane of the next gate, and slices it.
A leg is reported when
  no lane        a gate has no lane within 30 m
  relaxed        a gate has no lane within 8 m (the game falls back to 30 m)
  no path        no forward lane path joins the gates (the game draws a straight line instead)
  doubles back   the path comes back on the same lane (the game drops the leg)
  wrong level    a lane taken for the gate is more than LEVEL m above or below the gate (a street under a deck)
  long           the driven length of the leg is far from the 300-500 m the validator expects (> 800 m)
Prints one line per bad leg and a summary line "ROUTES_DRIVABLE OK" or "ROUTES_DRIVABLE FAIL n legs".
Exit 0 when the number of bad legs is <= --max-bad (default 0).
--no-face keeps the heading of every gate (without route_builder._face_the_route, which turns a gate towards the next one).
"""
import heapq
import json
import math
import sys
from collections import defaultdict

GATE_RADIUS = 8.0
GATE_RADIUS_FALLBACK = 30.0
GATE_TANGENT = 0.3
LEVEL = 4.0
CELL = 32.0
LONG_LEG = 800.0


class Lanes:
    def __init__(self, doc):
        self.lanes = doc["lanes"]
        self.index = {ln["id"]: i for i, ln in enumerate(self.lanes)}
        self.cum = []
        self.grid = defaultdict(list)
        for i, ln in enumerate(self.lanes):
            pts = ln["points"]
            cum = [0.0]
            for a, b in zip(pts, pts[1:]):
                cum.append(cum[-1] + math.dist(a, b))
            self.cum.append(cum)
            for k, (a, b) in enumerate(zip(pts, pts[1:])):
                for cx in range(int(min(a[0], b[0]) // CELL) - 1, int(max(a[0], b[0]) // CELL) + 2):
                    for cz in range(int(min(a[2], b[2]) // CELL) - 1, int(max(a[2], b[2]) // CELL) + 2):
                        self.grid[(cx, cz)].append((i, k))
        self.next = [[self.index[n] for n in ln.get("next", []) if n in self.index] for ln in self.lanes]

    def length(self, i):
        return self.cum[i][-1]

    def query(self, p, radius):
        """lane index -> (plan distance, closest point y, offset along the lane, tangent xz) like LaneSpatial.query."""
        out = {}
        cx, cz = int(p[0] // CELL), int(p[2] // CELL)
        span = max(int(radius // CELL), 1)
        seen = set()
        for dx in range(-span, span + 1):
            for dz in range(-span, span + 1):
                for (i, k) in self.grid.get((cx + dx, cz + dz), ()):
                    if (i, k) in seen:
                        continue
                    seen.add((i, k))
                    a, b = self.lanes[i]["points"][k], self.lanes[i]["points"][k + 1]
                    ddx, ddz = b[0] - a[0], b[2] - a[2]
                    l2 = ddx * ddx + ddz * ddz
                    if l2 < 1e-4:
                        continue
                    t = max(0.0, min(1.0, ((p[0] - a[0]) * ddx + (p[2] - a[2]) * ddz) / l2))
                    qx, qz = a[0] + t * ddx, a[2] + t * ddz
                    d = math.hypot(qx - p[0], qz - p[2])
                    if d > radius:
                        continue
                    if i in out and out[i][0] <= d:
                        continue
                    norm = math.sqrt(l2)
                    out[i] = (d, a[1] + t * (b[1] - a[1]), self.cum[i][k] + t * norm, (ddx / norm, ddz / norm))
        return out


def gate_lanes(lanes, gate, forward, radius):
    out = {}
    for i, (d, y, off, tan) in lanes.query(gate, radius).items():
        if forward is not None and tan[0] * forward[0] + tan[1] * forward[1] < GATE_TANGENT:
            continue
        out[i] = (d, y, off)
    return out


def heading_to_forward(h):
    """city.json heading: 0 = north (-Z), 90 = east (+X)."""
    r = math.radians(h)
    return (math.sin(r), -math.cos(r))


def shortest(lanes, sources, targets):
    """Dijkstra over the lane links; the cost of entering a lane is its length."""
    dist, prev, heap = {}, {}, []
    for s in sources:
        dist[s] = 0.0
        heapq.heappush(heap, (0.0, s))
    done = set()
    while heap:
        c, i = heapq.heappop(heap)
        if i in done:
            continue
        done.add(i)
        if i in targets:
            seq = [i]
            while seq[-1] in prev:
                seq.append(prev[seq[-1]])
            return seq[::-1]
        for n in lanes.next[i]:
            nc = c + lanes.length(i)
            if n not in dist or nc < dist[n]:
                dist[n] = nc
                prev[n] = i
                heapq.heappush(heap, (nc, n))
    return None


def leg_report(lanes, a, b, fa, fb):
    """(problem or None, driven metres) for the leg from gate a to gate b."""
    src = gate_lanes(lanes, a[:3], fa, GATE_RADIUS)
    tgt = gate_lanes(lanes, b[:3], fb, GATE_RADIUS)
    relaxed = False
    if not src or not tgt:
        src = gate_lanes(lanes, a[:3], fa, GATE_RADIUS_FALLBACK)
        tgt = gate_lanes(lanes, b[:3], fb, GATE_RADIUS_FALLBACK)
        relaxed = True
    if not src or not tgt:
        return "no lane within 30 m of the %s gate" % ("first" if not src else "second"), 0.0
    wrong = [lanes.lanes[i]["id"] for i, (d, y, off) in src.items() if abs(y - a[1]) > LEVEL]
    wrong += [lanes.lanes[i]["id"] for i, (d, y, off) in tgt.items() if abs(y - b[1]) > LEVEL]
    seq = shortest(lanes, list(src), set(tgt))
    if seq is None:
        return "no forward lane path between the gates", 0.0
    # slicing: the first lane is entered at the nearest offset of the first gate, the last one left at the offset of the second
    first, last = seq[0], seq[-1]
    off_in = src[first][2]
    off_out = tgt[last][2]
    if len(seq) == 1 and off_out < off_in - 0.5:
        return "doubles back: the second gate lies behind the first on lane %s" % lanes.lanes[first]["id"], 0.0
    metres = (off_out - off_in) if len(seq) == 1 else (lanes.length(first) - off_in) + sum(lanes.length(i) for i in seq[1:-1]) + off_out
    problems = []
    if relaxed:
        problems.append("relaxed: a gate is more than 8 m from the lanes")
    if metres > LONG_LEG:
        problems.append("long: %.0f m driven" % metres)
    if wrong:
        problems.append("wrong level: lane(s) %s are more than %.0f m from the gate in height" % (", ".join(sorted(set(wrong))[:3]), LEVEL))
    return ("; ".join(problems) if problems else None), metres


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    quiet = "--quiet" in argv
    face = "--no-face" not in argv
    max_bad = int(argv[argv.index("--max-bad") + 1]) if "--max-bad" in argv else 0
    if "--max-bad" in argv:
        args.remove(argv[argv.index("--max-bad") + 1])
    city = json.load(open(args[0], encoding="utf-8"))
    lanes = Lanes(json.load(open(args[1], encoding="utf-8")))
    bad = 0
    for route in city["routes"]:
        cps = route["checkpoints"]
        forwards = []
        for i, cp in enumerate(cps):
            f = heading_to_forward(cp[3])
            nxt = cps[(i + 1) % len(cps)]
            to_next = (nxt[0] - cp[0], nxt[2] - cp[2])
            if face and f[0] * to_next[0] + f[1] * to_next[1] <= 0.0:   # route_builder._face_the_route
                n = math.hypot(*to_next) or 1.0
                f = (to_next[0] / n, to_next[1] / n)
            forwards.append(f)
        legs = [(i, i + 1) for i in range(len(cps) - 1)]
        if route.get("kind") == "race" or route.get("laps", 1) > 1:
            legs.append((len(cps) - 1, 0))
        total, route_bad = 0.0, 0
        for (i, j) in legs:
            problem, metres = leg_report(lanes, cps[i], cps[j], forwards[i], forwards[j])
            total += metres
            if problem:
                route_bad += 1
                if not quiet:
                    print("%s leg %d->%d: %s" % (route["id"], i, j, problem))
        bad += route_bad
        print("route %-16s %2d legs, %2d bad, driven %5.1f km" % (route["id"], len(legs), route_bad, total / 1000.0))
    print("ROUTES_DRIVABLE %s" % ("OK" if bad <= max_bad else "FAIL %d legs" % bad))
    return 0 if bad <= max_bad else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
