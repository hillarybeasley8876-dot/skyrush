#!/usr/bin/env python3
"""check_open_edges — can a car fall off a deck? (no Godot needed)

    python tools/city/check_open_edges.py <tiles dir> <lanes.json> [--min-height 3] [--step 6] [--reach 12] [--max-bad N] [--csv out.csv] [--top 15]

For every lane of lanes.json that is on a deck (the lane point is at least --min-height metres up), every --step metres,
to the left and to the right: a ray runs sideways from the lane centre for --reach metres.
  * a BARRIER ends it (any collider that is not a road surface: a parapet, a concrete barrier, a rail, a pier; its height range
    has to reach the height of a car body: from the lane height up to 0.5 m above it);
  * the road surface ends it too, as an OPEN EDGE, when no surface collider within [-1.2, +0.5] m of the lane height lies under the ray
    for 1.0 m: the car that drives over that edge falls to the street.
A ray that finds neither within the reach (a very wide deck) is not judged. An open edge is reported once per lane point and side.
Prints the number of open edges (of the regular lanes of the roads and of the connector lanes j_*, attach_*, chain_* apart), the worst roads, the
first positions and "OPEN_EDGES OK" or "OPEN_EDGES FAIL n". Exit 0 when the regular open edges are <= --max-regular (default: --max-bad) and the
connector ones <= --max-connector (default: --max-bad); --max-bad itself defaults to 0.
The gaps that a ramp needs (the parapet gives way where its lanes leave the deck) are not open edges: the surface of the ramp carries on
under the ray, and the ray ends at the parapet on the far side of the ramp.
"""
import collections
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_path_blockers as cp  # noqa: E402
import check_surface_coverage as cs  # noqa: E402

SCAN = 0.5            # m: the step of the surface scan along the ray
VOID_RUN = 1.0        # m: the surface has to be missing this long to be an edge
BELOW, ABOVE = 1.2, 0.5
CAR_TOP = 0.5         # m above the lane: a barrier has to reach this high to stop a car (and start below it)


def ray_segment_t(px, pz, dx, dz, a, b):
    """The parameter t >= 0 where the ray p + t*d crosses the segment a-b (in x/z), or None."""
    ex, ez = b[0] - a[0], b[1] - a[1]
    den = dx * ez - dz * ex
    if abs(den) < 1e-9:
        return None
    t = ((a[0] - px) * ez - (a[1] - pz) * ex) / den
    u = ((a[0] - px) * dz - (a[1] - pz) * dx) / den
    if t >= 0.0 and -1e-6 <= u <= 1.0 + 1e-6:
        return t
    return None


def first_barrier(px, py, pz, dx, dz, reach, tris, grid):
    """The distance along the ray to the first barrier triangle that reaches a car body at height py, or None."""
    best = None
    seen = set()
    steps = int(reach // cp.CELL) + 1
    for k in range(steps + 1):
        cx, cz = int((px + dx * min(k * cp.CELL, reach)) // cp.CELL), int((pz + dz * min(k * cp.CELL, reach)) // cp.CELL)
        for i in grid.get((cx, cz), ()):
            if i in seen:
                continue
            seen.add(i)
            tri = tris[i][0]
            lo, hi = min(v[1] for v in tri), max(v[1] for v in tri)
            if hi < py + 0.05 or lo > py + CAR_TOP:
                continue
            pts = [(v[0], v[2]) for v in tri]
            for a, b in ((pts[0], pts[1]), (pts[1], pts[2]), (pts[2], pts[0])):
                t = ray_segment_t(px, pz, dx, dz, a, b)
                if t is not None and t <= reach and (best is None or t < best):
                    best = t
    return best


def surface_here(x, y, z, grid):
    for t in grid.get((int(x // cs.CELL), int(z // cs.CELL)), ()):
        h = cs.height_at(t, x, z)
        if h is not None and y - BELOW <= h <= y + ABOVE:
            return True
    return False


def first_void(px, py, pz, dx, dz, limit, sgrid):
    """The distance where the surface under the ray is missing for VOID_RUN metres, or None within limit."""
    missing_from = None
    t = SCAN
    while t <= limit + VOID_RUN:
        here = surface_here(px + dx * t, py, pz + dz * t, sgrid)
        if here:
            missing_from = None
        elif missing_from is None:
            missing_from = t
        elif t - missing_from >= VOID_RUN:
            return missing_from
        t += SCAN
    return None


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]

    def opt(name, default):
        return argv[argv.index(name) + 1] if name in argv else default

    min_h, step, reach = float(opt("--min-height", "3")), float(opt("--step", "6")), float(opt("--reach", "12"))
    max_bad, top, csv_path = int(opt("--max-bad", "0")), int(opt("--top", "15")), opt("--csv", "")
    max_regular, max_connector = int(opt("--max-regular", str(max_bad))), int(opt("--max-connector", str(max_bad)))
    for n in ("--min-height", "--step", "--reach", "--max-bad", "--top", "--csv", "--max-regular", "--max-connector"):
        if n in argv:
            args.remove(argv[argv.index(n) + 1])
    barriers = cp.barrier_triangles(args[0])
    bgrid = cp.build_grid(barriers)
    surf = []
    for name in sorted(os.listdir(args[0])):
        if name.startswith("roads_") and name.endswith(".gltf"):
            surf += cs.load_tile_triangles(os.path.join(args[0], name))
    sgrid = cs.build_grid(surf)
    lanes = json.load(open(args[1], encoding="utf-8"))["lanes"]
    per_road, rows, checked = collections.Counter(), [], 0
    for lane in lanes:
        pts = lane["points"]
        if len(pts) < 2 or max(p[1] for p in pts) < min_h:
            continue
        dist, next_at = 0.0, 0.0
        for a, b in zip(pts, pts[1:]):
            seg = math.dist(a, b)
            if seg < 1e-6:
                continue
            ux, uz = (b[0] - a[0]) / seg, (b[2] - a[2]) / seg
            while next_at <= dist + seg:
                f = (next_at - dist) / seg
                px, py, pz = a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
                next_at += step
                if py < min_h:
                    continue
                for side, (dx, dz) in (("right", (-uz, ux)), ("left", (uz, -ux))):
                    checked += 1
                    wall = first_barrier(px, py, pz, dx, dz, reach, barriers, bgrid)
                    limit = reach if wall is None else wall
                    void = first_void(px, py, pz, dx, dz, limit, sgrid)
                    if void is not None and (wall is None or void < wall - 0.1):
                        per_road[lane["road"]] += 1
                        rows.append((lane["road"], lane["id"], side, round(px, 1), round(py, 1), round(pz, 1), round(void, 1)))
            dist += seg
    if csv_path:
        open(csv_path, "w", encoding="utf-8").write("road,lane,side,x,y,z,edge_at\n" + "\n".join(",".join(map(str, r)) for r in rows) + "\n")
    connectors = sum(1 for r in rows if r[1].startswith(("j_", "attach_", "chain_")))
    regular = len(rows) - connectors
    print("%d rays checked, %d open edges: %d on the regular lanes, %d on the connector lanes" % (checked, len(rows), regular, connectors))
    print("worst roads: " + ", ".join("%s:%d" % kv for kv in per_road.most_common(top)))
    for r in rows[:top]:
        print("open edge: %s %s %s at (%.1f, %.1f, %.1f), the surface ends %.1f m out" % (r[0], r[1], r[2], r[3], r[4], r[5], r[6]))
    ok = regular <= max_regular and connectors <= max_connector
    print("OPEN_EDGES %s (regular %d of at most %d, connectors %d of at most %d)" % ("OK" if ok else "FAIL", regular, max_regular, connectors, max_connector))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
