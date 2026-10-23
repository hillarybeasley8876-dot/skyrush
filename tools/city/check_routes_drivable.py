#!/usr/bin/env python3
"""check_routes_drivable — can the game build a lane-following racing line for every route? (no Godot needed)

    python tools/city/check_routes_drivable.py <city.json> <lanes.json> [--quiet] [--max-bad N]

A Python replica of what game/world/api/route_builder.gd does when a race starts: gates that do not lie on a lane
of their level turn towards the next gate (route_gates.face_the_route); for every leg between two checkpoints it
takes the lanes within 8 m (plan distance) and within LEVEL m in height (as LaneSpatial.query does) whose direction
agrees with the gate (dot >= 0.3), searches the shortest lane path from any of them to any lane of the next gate,
slices it and bakes the line every 2 m like the game's Curve3D. A leg is reported when
  no lane        a gate has no lane (of its level) within 30 m
  relaxed        a gate has no lane (of its level) within 8 m (the game falls back to 30 m)
  no path        no forward lane path joins the gates (the game draws a straight line instead)
  doubles back   the path comes back on the same lane (the game drops the leg)
  long           the driven length of the leg is far from the 300-500 m the validator expects (> 800 m)
  detour         the leg drives more than twice the distance between its gates plus 400 m
  reversals      the racing line of a route turns back on itself (3 or more reversal points: dot of the direction before and
                 5 points ahead < -0.5; the same count as game/world/tests/test_route_layers.gd)
Prints one line per bad leg and a summary line "ROUTES_DRIVABLE OK" or "ROUTES_DRIVABLE FAIL n legs".
Exit 0 when the number of bad legs is <= --max-bad (default 0).
--no-face keeps the heading of every gate (without route_gates.face_the_route, which turns a gate towards the next one).
--lanes prints the lane ids of every bad leg.
"""
import heapq
import json
import math
import sys
from collections import defaultdict

GATE_RADIUS = 8.0
GATE_RADIUS_FALLBACK = 30.0
GATE_TANGENT = 0.3
GATE_ALIGN = 0.819        # route_gates.GATE_ALIGN: a gate on a lane of its level that runs within 35 degrees keeps its heading
LEVEL = 3.0               # level_rules.LEVEL
CELL = 32.0
LONG_LEG = 800.0
BAKE = 2.0                # the bake interval of the racing line (route_builder.SLICE_STEP, Curve3D.bake_interval)
HAIRPIN_FREE = 100.0      # lane_path_finder.HAIRPIN_*: a short lane that turns by more than this many degrees costs extra
HAIRPIN_COST = 600.0
HAIRPIN_LANE_MAX = 200.0
HAIRPIN_REACH = 4.0
REFINE = 0.5              # route_builder._nearest_offset: the step of the refinement round the best sample


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
        self.hairpins = {}

    def length(self, i):
        return self.cum[i][-1]

    def query(self, p, radius, y=None, tol=LEVEL):
        """lane index -> (plan distance, closest point y, offset along the lane, tangent xz) like LaneSpatial.query:
        with y given only the segments whose closest point is within tol metres of that height count."""
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
                    qy = a[1] + t * (b[1] - a[1])
                    if y is not None and abs(qy - y) > tol:
                        continue
                    if i in out and out[i][0] <= d:
                        continue
                    norm = math.sqrt(l2)
                    out[i] = (d, qy, self.cum[i][k] + t * norm, (ddx / norm, ddz / norm))
        return out

    def nearest_offset(self, i, p):
        """route_builder._nearest_offset: the lane is sampled every length/int(length/8) metres and the sample with the
        smallest plan distance + height difference wins (a lane that crosses itself has two levels at one x/z); the winner is
        refined every 0.5 m over the 8 m round it, so two lanes beside each other give a gate the same offset."""
        length = self.length(i)
        steps = max(int(length / 8.0), 1)

        def score(off):
            q = self.at(i, off)
            return math.hypot(q[0] - p[0], q[2] - p[2]) + abs(q[1] - p[1])

        best, best_d = 0.0, float("inf")
        for s in range(steps + 1):
            off = length * s / steps
            d = score(off)
            if d < best_d:
                best_d, best = d, off
        centre, reach = best, length / steps
        lo, hi = max(0.0, centre - reach), min(length, centre + reach)
        n = max(int((hi - lo) / REFINE), 1)
        for k in range(n + 1):
            off = lo + (hi - lo) * k / n
            d = score(off)
            if d < best_d:
                best_d, best = d, off
        return best

    def at(self, i, off):
        """The point of lane i at the offset off (metres along it)."""
        pts, cum = self.lanes[i]["points"], self.cum[i]
        if off <= 0.0:
            return pts[0]
        for k in range(1, len(pts)):
            if off <= cum[k] or k == len(pts) - 1:
                seg = cum[k] - cum[k - 1]
                t = 0.0 if seg < 1e-9 else min(1.0, (off - cum[k - 1]) / seg)
                a, b = pts[k - 1], pts[k]
                return [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1]), a[2] + t * (b[2] - a[2])]
        return pts[-1]


def gate_lanes(lanes, gate, forward, radius):
    """LanePathFinder.gate_lanes: the lanes within radius of the gate, on its level, that run the way the gate faces."""
    out = {}
    for i, (d, y, off, tan) in lanes.query(gate, radius, gate[1]).items():
        if forward is not None and tan[0] * forward[0] + tan[1] * forward[1] < GATE_TANGENT:
            continue
        out[i] = (d, y, off)
    return out


def heading_to_forward(h):
    """city.json heading: 0 = north (-Z), 90 = east (+X)."""
    r = math.radians(h)
    return (math.sin(r), -math.cos(r))


def hairpin_cost(lanes, i):
    """LanePathFinder._hairpin_cost: a short lane that turns by more than 100 degrees between its first and its last 4 m is a
    hairpin (a U-turn through a junction) and costs up to 600 m of path, growing with the square of the turn."""
    cached = lanes.hairpins.get(i)
    if cached is not None:
        return cached
    cost = 0.0
    length = lanes.length(i)
    if 1.0 < length <= HAIRPIN_LANE_MAX:
        reach = min(HAIRPIN_REACH, length * 0.5)
        p0, p1 = lanes.at(i, 0.0), lanes.at(i, reach)
        q0, q1 = lanes.at(i, length - reach), lanes.at(i, length)
        head = (p1[0] - p0[0], p1[2] - p0[2])
        tail = (q1[0] - q0[0], q1[2] - q0[2])
        lh, lt = math.hypot(*head), math.hypot(*tail)
        if lh > 0.01 and lt > 0.01:
            angle = math.degrees(math.acos(max(-1.0, min(1.0, (head[0] * tail[0] + head[1] * tail[1]) / (lh * lt)))))
            share = max(0.0, min(1.0, (angle - HAIRPIN_FREE) / (180.0 - HAIRPIN_FREE)))
            cost = HAIRPIN_COST * share * share
    lanes.hairpins[i] = cost
    return cost


def link_cost(lanes, i, n):
    """LanePathFinder._link_cost: the plan gap between the end of lane i and the start of lane n, plus the length of n and its
    hairpin cost."""
    a, b = lanes.lanes[i]["points"][-1], lanes.lanes[n]["points"][0]
    return math.hypot(a[0] - b[0], a[2] - b[2]) + lanes.length(n) + hairpin_cost(lanes, n)


def shortest(lanes, sources, targets):
    """LanePathFinder.find_multi: Dijkstra over the lane links, sources cost 0, entering a lane costs its link cost."""
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
            nc = c + link_cost(lanes, i, n)
            if n not in dist or nc < dist[n]:
                dist[n] = nc
                prev[n] = i
                heapq.heappush(heap, (nc, n))
    return None


def slice_lane(lanes, i, off_from, off_to):
    """route_builder._slice: the points of lane i between two offsets, a point at least every 2 m (a slice that ends before
    it starts wraps round the lane)."""
    length = lanes.length(i)
    if length < 0.01:
        return []

    def on(offset):
        return length if offset >= length - 0.001 else offset % length

    start, end = on(off_from), on(off_to)
    spans = [(start, end)] if end >= start else [(start, length), (0.0, end)]
    out = []
    for (x, y) in spans:
        steps = max(int((y - x) / BAKE), 1)
        for k in range(steps + 1):
            out.append(lanes.at(i, x + (y - x) * k / steps))
    return out


def bake(points):
    """Spline.make_curve(_unique(points)) baked every 2 m: the points of the racing line the tests of the game look at."""
    kept = []
    for p in points:
        if kept and math.dist(kept[-1], p) < 1.0:
            continue
        kept.append(p)
    if len(kept) < 2:
        return kept
    out, carry = [kept[0]], 0.0
    for a, b in zip(kept, kept[1:]):
        seg = math.dist(a, b)
        at = BAKE - carry
        while at <= seg:
            t = at / seg
            out.append([a[k] + t * (b[k] - a[k]) for k in range(3)])
            at += BAKE
        carry = seg - (at - BAKE)
    if math.dist(out[-1], kept[-1]) > 0.01:
        out.append(kept[-1])
    return out


def reversals(line):
    """Indices where the line turns back on itself (as test_route_layers.gd: dot < -0.5 over 5 baked points)."""
    out = []
    for i in range(1, len(line) - 5):
        a = (line[i + 5][0] - line[i][0], line[i + 5][2] - line[i][2])
        b = (line[i][0] - line[i - 1][0], line[i][2] - line[i - 1][2])
        la, lb = math.hypot(*a), math.hypot(*b)
        if la > 0.1 and lb > 0.1 and (a[0] * b[0] + a[1] * b[1]) / (la * lb) < -0.5:
            out.append(i)
    return out


def on_a_lane(lanes, gate, forward):
    """route_gates.on_a_lane: a lane of the level of the gate within 8 m runs within 35 degrees of the way it faces."""
    return any(tan[0] * forward[0] + tan[1] * forward[1] >= GATE_ALIGN
               for (d, y, off, tan) in lanes.query(gate, GATE_RADIUS, gate[1]).values())


def face_the_route(lanes, cps, face):
    """route_gates.face_the_route: the forward (x, z) of every gate; a gate that is on no lane of its level and faces away
    from the next gate turns towards it."""
    out = []
    for i, cp in enumerate(cps):
        f = heading_to_forward(cp[3])
        nxt = cps[(i + 1) % len(cps)]
        to_next = (nxt[0] - cp[0], nxt[2] - cp[2])
        if face and not on_a_lane(lanes, cp[:3], f) and f[0] * to_next[0] + f[1] * to_next[1] <= 0.0:
            n = math.hypot(*to_next) or 1.0
            f = (to_next[0] / n, to_next[1] / n)
        out.append(f)
    return out


def leg_report(lanes, a, b, fa, fb):
    """(problem or None, driven metres, line points, lane sequence) for the leg from gate a to gate b."""
    src = gate_lanes(lanes, a[:3], fa, GATE_RADIUS)
    tgt = gate_lanes(lanes, b[:3], fb, GATE_RADIUS)
    relaxed = False
    if not src or not tgt:
        src = gate_lanes(lanes, a[:3], fa, GATE_RADIUS_FALLBACK)
        tgt = gate_lanes(lanes, b[:3], fb, GATE_RADIUS_FALLBACK)
        relaxed = True
    if not src or not tgt:
        return "no lane within 30 m of the %s gate" % ("first" if not src else "second"), 0.0, [], []
    seq = shortest(lanes, sorted(src), set(tgt))
    if seq is None:
        return "no forward lane path between the gates", 0.0, [], []
    n = len(seq)
    entries = [lanes.nearest_offset(seq[0], a[:3])] + [0.0] * (n - 1)
    exits = [lanes.length(i) for i in seq[:-1]] + [lanes.nearest_offset(seq[-1], b[:3])]
    line = []
    for k in range(n):
        if exits[k] < entries[k] - 0.5:
            if k == 0:
                continue   # the gate lies past the end of the lane: the leg starts on the next lane
            return "doubles back on lane %s" % lanes.lanes[seq[k]]["id"], 0.0, [], seq
        line += slice_lane(lanes, seq[k], entries[k], exits[k])
    if not line:
        return "no usable line: the only lane ends before the first gate", 0.0, [], seq
    metres = sum(math.dist(p, q) for p, q in zip(line, line[1:]))
    problems = []
    if relaxed:
        problems.append("relaxed: a gate is more than 8 m from the lanes of its level")
    if metres > LONG_LEG:
        problems.append("long: %.0f m driven" % metres)
    return ("; ".join(problems) if problems else None), metres, line, seq


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    quiet = "--quiet" in argv
    show_lanes = "--lanes" in argv
    face = "--no-face" not in argv
    max_bad = int(argv[argv.index("--max-bad") + 1]) if "--max-bad" in argv else 0
    if "--max-bad" in argv:
        args.remove(argv[argv.index("--max-bad") + 1])
    city = json.load(open(args[0], encoding="utf-8"))
    lanes = Lanes(json.load(open(args[1], encoding="utf-8")))
    bad = 0
    for route in city["routes"]:
        cps = route["checkpoints"]
        forwards = face_the_route(lanes, cps, face)
        legs = [(i, i + 1) for i in range(len(cps) - 1)]
        circuit = route.get("kind") == "race" or route.get("laps", 1) > 1
        if circuit:
            legs.append((len(cps) - 1, 0))
        total, route_bad, whole, owner = 0.0, 0, [], []
        for (i, j) in legs:
            problem, metres, line, seq = leg_report(lanes, cps[i], cps[j], forwards[i], forwards[j])
            total += metres
            straight = math.hypot(cps[i][0] - cps[j][0], cps[i][2] - cps[j][2])
            if not problem and metres > 2.0 * straight + 400.0:
                problem = "detour: %.0f m driven for %.0f m between the gates" % (metres, straight)
            if problem:
                route_bad += 1
                if not quiet:
                    print("%s leg %d->%d: %s" % (route["id"], i, j, problem))
                    if show_lanes and seq:
                        print("    lanes: %s" % " > ".join(lanes.lanes[k]["id"] for k in seq))
            whole += line
            owner += [i] * len(line)
        baked = bake(whole)
        revs = reversals(baked)
        places = []
        for k in revs:
            nearest = min(range(len(whole)), key=lambda m: math.dist(whole[m], baked[k]))
            places.append("(%.0f, %.0f) leg %d" % (baked[k][0], baked[k][2], owner[nearest]))
        if revs:
            route_bad += 1
            if not quiet:
                print("%s: %d reversals in the racing line, at %s" % (route["id"], len(revs), ", ".join(places[:8])))
        bad += route_bad
        print("route %-16s %2d legs, %2d bad, driven %5.1f km, %d reversals" % (route["id"], len(legs), route_bad, total / 1000.0, len(revs)))
    print("ROUTES_DRIVABLE %s" % ("OK" if bad <= max_bad else "FAIL %d legs" % bad))
    return 0 if bad <= max_bad else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
