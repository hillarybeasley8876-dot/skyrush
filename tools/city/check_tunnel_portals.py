#!/usr/bin/env python3
"""check_tunnel_portals — no street crosses the open trough of a tunnel ramp, the tunnel meets a street at grade only at a
junction of the two, and no lot stands on the trough (city.json only: no Godot, no Blender).

    python tools/city/check_tunnel_portals.py <city.json> [--quiet]

A tunnel road is split by the depth of its road, d = -y:
  AT GRADE  d <= 0.3 m            a street like any other: it may meet another road at grade only at a junction of the two
  OPEN      0.3 m < d < 6.0 m     the trough between the ground and the 6 m a bore needs over its road (tunnel.py: the crown
                                  of a bore is 5.98 m over the road): open to the sky, walled, fenced at the ground; no road at
                                  street level may cross it and no lot may stand on it
  COVERED   d >= 6.0 m            in the bore: a road over it needs 6 m (the clearance rule of validate.py checks that)

The footprint of the tunnel is its two bores and their walls, TROUGH_HALF = 12 m either side of the centre line (the bore
centres are 7.25 m out, the outer face of a wall 4.4 m further).  The footprint of another road is its carriageway (lanes,
median, shoulders); its sidewalks are reported apart and do not fail.

Failures, one line per road pair:
  OPEN_CROSSING     a sample of the open trough lies inside the carriageway of another road that is less than 6 m over the
                    tunnel road there (an elevated deck 6 m or more over it bridges the trough and is fine)
  GRADE_CROSSING    a sample of the tunnel at grade lies inside the carriageway of another road within 1 m of its height and
                    no junction lists both roads within (the two paved widths) / 2 + 10 m of the station (validate.py's reach)
  LOT_ON_TROUGH     a sample of the open trough lies inside a lot
  END_NOT_AT_GRADE  an end of the tunnel road is not at grade
Reported only: SIDEWALK (the sidewalk of another road reaches over the open trough: the parapet of the trough stands on it)
and MOUTH (the first MOUTH_DEPTH of the trough lies in a junction of the tunnel and the other road: the roads unit trims the
tunnel road at the junction and the plate of the junction slopes down to it, the walls of the trough start outside it).

Prints the stretches of each tunnel, the failures and "TUNNEL_PORTALS OK" or "TUNNEL_PORTALS FAIL n"; exit 1 on a failure.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import citylib  # noqa: E402

AT_GRADE = 0.3
COVER = 6.0
TROUGH_HALF = 12.0
ACROSS_STEP = 2.0
SAME_LEVEL = 1.0
JUNCTION_MARGIN = 10.0
MOUTH_DEPTH = 1.0
CELL = 25.0


def carriageway_half(road):
    lanes = (road.get("lanes_fwd", 0) + road.get("lanes_back", 0)) * road.get("lane_width", 3.75)
    return (lanes + road.get("median", 0.0) + 2.0 * road.get("shoulder", 0.0)) * 0.5


def sidewalk(road):
    return road.get("sidewalk", 0.0) if road.get("kind", "surface") == "surface" else 0.0


class SegmentGrid:
    """The segments of the roads in a coarse grid: the roads near a point, with the distance and the height there."""

    def __init__(self, roads):
        self.roads = roads
        self.cells = {}
        for ri, road in enumerate(roads):
            pts = road["points"]
            reach = carriageway_half(road) + sidewalk(road)
            for i in range(len(pts) - 1):
                a, b = pts[i], pts[i + 1]
                x0, x1 = min(a[0], b[0]) - reach, max(a[0], b[0]) + reach
                z0, z1 = min(a[2], b[2]) - reach, max(a[2], b[2]) + reach
                for cx in range(int(math.floor(x0 / CELL)), int(math.floor(x1 / CELL)) + 1):
                    for cz in range(int(math.floor(z0 / CELL)), int(math.floor(z1 / CELL)) + 1):
                        self.cells.setdefault((cx, cz), []).append((ri, i))

    def near(self, x, z, skip):
        """{road index: (distance to its centre line, its height there)} for the roads whose paved width reaches (x, z)."""
        best = {}
        for ri, i in self.cells.get((int(math.floor(x / CELL)), int(math.floor(z / CELL))), ()):
            if ri in skip:
                continue
            a, b = self.roads[ri]["points"][i], self.roads[ri]["points"][i + 1]
            dx, dz = b[0] - a[0], b[2] - a[2]
            l2 = dx * dx + dz * dz
            u = 0.0 if l2 < 1e-12 else max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[2]) * dz) / l2))
            d = math.hypot(x - a[0] - dx * u, z - a[2] - dz * u)
            if ri not in best or d < best[ri][0]:
                best[ri] = (d, a[1] + (b[1] - a[1]) * u)
        return best


def classify(y):
    d = -y
    if d <= AT_GRADE:
        return "AT_GRADE"
    if d < COVER:
        return "OPEN"
    return "COVERED"


def stretches(pts, cum):
    """[(class, s0, s1)] along the road."""
    out = []
    for p, s in zip(pts, cum):
        c = classify(p[1])
        if out and out[-1][0] == c:
            out[-1][2] = s
        else:
            out.append([c, s, s])
    return out


def lots_near(blocks, box):
    x0, x1, z0, z1 = box
    out = []
    for b in blocks:
        poly = b.get("polygon")
        if not poly:
            continue
        xs = [p[0] for p in poly]
        zs = [p[1] for p in poly]
        if max(xs) < x0 or min(xs) > x1 or max(zs) < z0 or min(zs) > z1:
            continue
        out.append((b["id"], [(p[0], p[1]) for p in poly]))
    return out


def check(city):
    roads = city["roads"]
    by_id = {r["id"]: r for r in roads}
    grid = SegmentGrid(roads)
    pairs = {}
    for j in city.get("junctions", []):
        rs = j.get("roads", [])
        for a in rs:
            for b in rs:
                if a < b:
                    pairs.setdefault((a, b), []).append(j)
    fails = {}
    notes = {}
    lines = []

    def add(table, key, s, depth, x, z):
        rec = table.get(key)
        if rec is None:
            table[key] = [s, s, depth, depth, x, z, 1]
        else:
            rec[1] = s
            rec[2] = min(rec[2], depth)
            rec[3] = max(rec[3], depth)
            rec[6] += 1

    for ti, tunnel in enumerate(roads):
        if tunnel.get("kind") != "tunnel":
            continue
        pts = tunnel["points"]
        cum = citylib.cumulative([(p[0], 0.0, p[2]) for p in pts])
        for c, s0, s1 in stretches(pts, cum):
            lines.append("%s %-8s s %7.1f .. %7.1f  (%5.0f m)" % (tunnel["id"], c, s0, s1, s1 - s0))
        for end, p in (("start", pts[0]), ("end", pts[-1])):
            if classify(p[1]) != "AT_GRADE":
                add(fails, ("END_NOT_AT_GRADE", tunnel["id"], end), 0.0, -p[1], p[0], p[2])
        open_box = None
        for i, p in enumerate(pts):
            if classify(p[1]) == "OPEN":
                b = (p[0] - TROUGH_HALF, p[0] + TROUGH_HALF, p[2] - TROUGH_HALF, p[2] + TROUGH_HALF)
                open_box = b if open_box is None else (min(open_box[0], b[0]), max(open_box[1], b[1]),
                                                       min(open_box[2], b[2]), max(open_box[3], b[3]))
        lots = lots_near(city.get("blocks", []), open_box) if open_box else []
        tw = citylib.road_width(tunnel)
        for i, p in enumerate(pts):
            c = classify(p[1])
            if c == "COVERED":
                continue
            a = pts[max(0, i - 1)]
            b = pts[min(len(pts) - 1, i + 1)]
            dx, dz = b[0] - a[0], b[2] - a[2]
            n = math.hypot(dx, dz) or 1.0
            rx, rz = -dz / n, dx / n
            k = -TROUGH_HALF
            while k <= TROUGH_HALF + 1e-6:
                x, z = p[0] + rx * k, p[2] + rz * k
                for ri, (dist, oy) in grid.near(x, z, (ti,)).items():
                    other = roads[ri]
                    if other.get("kind") == "tunnel":
                        continue
                    inside = dist <= carriageway_half(other)
                    on_walk = not inside and dist <= carriageway_half(other) + sidewalk(other)
                    key = (min(tunnel["id"], other["id"]), max(tunnel["id"], other["id"]))
                    reach = tw * 0.5 + citylib.road_width(other) * 0.5 + JUNCTION_MARGIN
                    junction = any(math.hypot(p[0] - j["x"], p[2] - j["z"]) <= reach for j in pairs.get(key, ()))
                    if c == "OPEN":
                        if oy - p[1] >= COVER:
                            continue
                        if inside and junction and -p[1] < MOUTH_DEPTH:
                            add(notes, ("MOUTH", tunnel["id"], other["id"]), cum[i], -p[1], x, z)
                        elif inside:
                            add(fails, ("OPEN_CROSSING", tunnel["id"], other["id"]), cum[i], -p[1], x, z)
                        elif on_walk:
                            add(notes, ("SIDEWALK", tunnel["id"], other["id"]), cum[i], -p[1], x, z)
                    elif inside and abs(oy - p[1]) < SAME_LEVEL and not junction:
                        add(fails, ("GRADE_CROSSING", tunnel["id"], other["id"]), cum[i], -p[1], x, z)
                if c == "OPEN":
                    for lid, poly in lots:
                        if citylib.point_in_polygon((x, z), poly):
                            add(fails, ("LOT_ON_TROUGH", tunnel["id"], lid), cum[i], -p[1], x, z)
                k += ACROSS_STEP
    return lines, fails, notes


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    quiet = "--quiet" in argv
    if len(args) != 1:
        print(__doc__)
        return 2
    city = citylib.load_json(args[0])
    lines, fails, notes = check(city)
    if not quiet:
        for line in lines:
            print(line)
    for (kind, tid, other), (s0, s1, d0, d1, x, z, n) in sorted(fails.items()):
        print("%s %s x %s: %d samples, s %.0f..%.0f, depth %.2f..%.2f m, at (%.0f, %.0f)"
              % (kind, tid, other, n, s0, s1, d0, d1, x, z))
    if not quiet:
        for (kind, tid, other), (s0, s1, d0, d1, x, z, n) in sorted(notes.items()):
            print("%s %s x %s: %d samples, s %.0f..%.0f, depth %.2f..%.2f m, at (%.0f, %.0f) (reported only)"
                  % (kind, tid, other, n, s0, s1, d0, d1, x, z))
    if fails:
        print("TUNNEL_PORTALS FAIL %d" % len(fails))
        return 1
    print("TUNNEL_PORTALS OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
