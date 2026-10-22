#!/usr/bin/env python3
"""check_path_blockers — does a barrier collider stand in the way of a car on the follow paths? (no Godot needed)

    python tools/city/check_path_blockers.py <tiles dir> <paths dir> [--lift 0.30] [--step 1.0] [--max-bad N] [--csv out.csv]
    python tools/city/check_path_blockers.py <tiles dir> --lanes <lanes.json> [--prefix attach_] [--step 3.0] [--max-bad N]

Reads the glTF road tiles, takes every triangle of the colliders that are NOT the road surface (the nodes whose name holds
"colonly" but not "surface": concrete barriers, parapets, steel rails, pier columns), and moves a car-sized box
(1.9 m wide, 1.0 m high, 4.2 m long, its underside --lift metres above the path) along every <paths dir>/*.json
(a path file is {"id", "points": [[x, y, z], ...]}, the files make_attach_paths.py and make_chain_paths.py write),
one position per --step metres, heading along the path.  A position where a triangle touches the box is blocked.
This is the offline twin of game/world/tests/probe_path_blockers.gd (which also sees the props of the world).
With --lanes every lane of lanes.json (optionally only those whose id starts with --prefix) is one path (--step 3 by default),
and the blocked points are summed per road: the worst roads are printed instead of one line per path.
--lip M also looks at the road SURFACE colliders: a position is a "lip" when the highest surface triangle under the car's
footprint (3 x 3 sample points, triangles within 3 m of the path height) is more than M metres (default 0.25) above the path:
a step the car drives into (e.g. the widened acceleration strip of the parent road lying 1 m above the ramp's deck).
--max-lips N makes more than N lip positions a failure (default: lips are only printed).
--min-barrier-area guards against "fixing" the blockers by deleting the barriers: the total surface area of the barrier
colliders (3D, all triangles) must be at least that many square metres.
Prints one line per path and "PATH_BLOCKERS OK" or "PATH_BLOCKERS FAIL n blocked points in m paths"; exit 0 when the
number of blocked points is <= --max-bad (default 0).
"""
import collections
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_surface_coverage as cs  # noqa: E402

HALF = (0.95, 0.5, 2.1)   # half width, half height, half length of the box
CELL = 16.0


def barrier_triangles(tiles_dir):
    """All triangles of the non-surface colliders of the tiles: [((x, y, z) * 3), ...]."""
    out = []
    for name in sorted(os.listdir(tiles_dir)):
        if not (name.startswith("roads_") and name.endswith(".gltf")):
            continue
        path = os.path.join(tiles_dir, name)
        gltf = json.load(open(path, encoding="utf-8"))
        base = os.path.dirname(path)
        bufs = [open(os.path.join(base, b["uri"]), "rb").read() for b in gltf["buffers"]]
        for node in gltf.get("nodes", []):
            nm = node.get("name", "")
            if "colonly" not in nm or "surface" in nm or "mesh" not in node:
                continue
            shift = node.get("translation", (0.0, 0.0, 0.0))
            for prim in gltf["meshes"][node["mesh"]]["primitives"]:
                pos = cs.read_accessor(gltf, bufs, prim["attributes"]["POSITION"])
                ind = cs.read_accessor(gltf, bufs, prim["indices"]) if "indices" in prim else list(range(len(pos)))
                for k in range(0, len(ind) - 2, 3):
                    tri = tuple((pos[ind[k + j]][0] + shift[0], pos[ind[k + j]][1] + shift[1], pos[ind[k + j]][2] + shift[2])
                                for j in range(3))
                    out.append((tri, nm))
    return out


def build_grid(tris):
    grid = collections.defaultdict(list)
    for i, (t, _nm) in enumerate(tris):
        xs, zs = [p[0] for p in t], [p[2] for p in t]
        for a in range(int(min(xs) // CELL), int(max(xs) // CELL) + 1):
            for b in range(int(min(zs) // CELL), int(max(zs) // CELL) + 1):
                grid[(a, b)].append(i)
    return grid


def up_facing(t):
    """True when the front face of the triangle (counter-clockwise seen from above) looks up."""
    ux, uz = t[1][0] - t[0][0], t[1][2] - t[0][2]
    vx, vz = t[2][0] - t[0][0], t[2][2] - t[0][2]
    return vx * uz - vz * ux > 0.0


def tri_box_overlap(v0, v1, v2, half):
    """Triangle against an axis aligned box centred at the origin (Akenine-Moeller separating axis test)."""
    hx, hy, hz = half
    e = ((v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2]), (v2[0] - v1[0], v2[1] - v1[1], v2[2] - v1[2]),
         (v0[0] - v2[0], v0[1] - v2[1], v0[2] - v2[2]))
    vs = (v0, v1, v2)
    for ex, ey, ez in e:
        for axis in ((0.0, -ez, ey), (ez, 0.0, -ex), (-ey, ex, 0.0)):
            p = [v[0] * axis[0] + v[1] * axis[1] + v[2] * axis[2] for v in vs]
            r = hx * abs(axis[0]) + hy * abs(axis[1]) + hz * abs(axis[2])
            if min(p) > r or max(p) < -r:
                return False
    for k, h in enumerate(half):
        vals = [v[k] for v in vs]
        if min(vals) > h or max(vals) < -h:
            return False
    n = (e[0][1] * e[1][2] - e[0][2] * e[1][1], e[0][2] * e[1][0] - e[0][0] * e[1][2], e[0][0] * e[1][1] - e[0][1] * e[1][0])
    d = n[0] * v0[0] + n[1] * v0[1] + n[2] * v0[2]
    r = hx * abs(n[0]) + hy * abs(n[1]) + hz * abs(n[2])
    return abs(d) <= r


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    opt = lambda n, d: argv[argv.index(n) + 1] if n in argv else d  # noqa: E731
    lift, step, max_bad = float(opt("--lift", "0.30")), float(opt("--step", "1.0")), int(opt("--max-bad", "0"))
    csv_path = opt("--csv", "")
    min_area = float(opt("--min-barrier-area", "0"))
    lip = float(opt("--lip", "0.25"))
    max_lips = int(opt("--max-lips", "-1"))
    lanes_path = opt("--lanes", "")
    prefix = opt("--prefix", "")
    for n in ("--lift", "--step", "--max-bad", "--csv", "--lanes", "--prefix", "--min-barrier-area", "--lip", "--max-lips"):
        if n in argv:
            args.remove(argv[argv.index(n) + 1])
    if lanes_path and "--step" not in argv:
        step = 3.0
    tris = barrier_triangles(args[0])
    grid = build_grid(tris)
    surf_grid = None
    if max_lips >= 0 or "--lip" in argv:
        surf = []
        for name in sorted(os.listdir(args[0])):
            if name.startswith("roads_") and name.endswith(".gltf"):
                surf += cs.load_tile_triangles(os.path.join(args[0], name))
        surf_grid = cs.build_grid(surf)
    lips_total = 0
    if lanes_path:
        lane_docs = [{"id": l["id"], "road": l["road"], "points": l["points"]}
                     for l in json.load(open(lanes_path, encoding="utf-8"))["lanes"]
                     if l["id"].startswith(prefix) and len(l["points"]) >= 2]
        files = [None] * len(lane_docs)
    else:
        files = sorted(f for f in os.listdir(args[1]) if f.endswith(".json"))
    per_road = collections.Counter()
    total, rows = 0, []
    for k, f in enumerate(files):
        doc = lane_docs[k] if lanes_path else json.load(open(os.path.join(args[1], f), encoding="utf-8"))
        pts = doc["points"]
        dist, next_probe, blocked, first = 0.0, 0.0, 0, ""
        lips, lip_first = 0, ""
        for a, b in zip(pts, pts[1:]):
            seg = math.dist(a, b)
            if seg < 1e-3:
                continue
            fx, fz = (b[0] - a[0]) / seg, (b[2] - a[2]) / seg
            norm = math.hypot(fx, fz) or 1.0
            fx, fz = fx / norm, fz / norm
            rx, rz = -fz, fx
            while next_probe <= dist + seg:
                t = (next_probe - dist) / seg
                cx, cy, cz = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t + lift + HALF[1], a[2] + (b[2] - a[2]) * t
                hit = None
                cand = set()
                for dx in (-1, 0, 1):
                    for dz in (-1, 0, 1):
                        cand.update(grid.get((int(cx // CELL) + dx, int(cz // CELL) + dz), ()))
                for i in cand:
                    tri, nm = tris[i]
                    loc = []
                    for v in tri:
                        dxv, dyv, dzv = v[0] - cx, v[1] - cy, v[2] - cz
                        loc.append((dxv * rx + dzv * rz, dyv, dxv * fx + dzv * fz))
                    if tri_box_overlap(loc[0], loc[1], loc[2], HALF):
                        hit = nm
                        break
                if surf_grid is not None:
                    top = None
                    for lat in (-0.9, 0.0, 0.9):
                        for lon in (-2.0, 0.0, 2.0):
                            qx, qz = cx + rx * lat + fx * lon, cz + rz * lat + fz * lon
                            for tri in surf_grid.get((int(qx // cs.CELL), int(qz // cs.CELL)), ()):
                                h = cs.height_at(tri, qx, qz)
                                # a step the wheels run into: 0.25 .. 0.9 m above the lane, facing up (the colliders are one sided:
                                # a deck overhead is no obstacle, a car below passes through its back face)
                                if h is not None and lip < h - (cy - lift - HALF[1]) < 0.9 and up_facing(tri):
                                    top = h if top is None else max(top, h)
                    if top is not None:
                        lips += 1
                        lip_first = lip_first or "%.2f m above the path at %.0f m (%.1f, %.1f, %.1f)" % (top - (cy - lift - HALF[1]), next_probe, cx, cy - lift - HALF[1], cz)
                if hit:
                    blocked += 1
                    first = first or "%s at %.0f m (%.1f, %.1f, %.1f)" % (hit, next_probe, cx, cy - lift - HALF[1], cz)
                    rows.append("%s,%.0f,%.1f,%.1f,%.1f,%s" % (doc.get("id", f), next_probe, cx, cy - lift - HALF[1], cz, hit))
                next_probe += step
            dist += seg
        total += blocked
        lips_total += lips
        if lanes_path:
            if blocked:
                per_road[doc["road"]] += blocked
            continue
        print("%s %-44s %3d blocked points%s%s" % ("ok  " if not blocked else "BAD ", doc.get("id", f), blocked, "" if not first else "  first: " + first,
                                              "" if not lips else "  LIPS %d, first %s" % (lips, lip_first)))
    if csv_path:
        open(csv_path, "w", encoding="utf-8").write("path,at_m,x,y,z,collider\n" + "\n".join(rows) + "\n")
    if lanes_path:
        print("worst roads: " + ", ".join("%s:%d" % kv for kv in per_road.most_common(12)))
    area = 0.0
    for t, _nm in tris:
        ux, uy, uz = (t[1][i] - t[0][i] for i in range(3))
        vx, vy, vz = (t[2][i] - t[0][i] for i in range(3))
        area += 0.5 * math.sqrt((uy * vz - uz * vy) ** 2 + (uz * vx - ux * vz) ** 2 + (ux * vy - uy * vx) ** 2)
    print("triangles %d, paths %d, barrier collider area %.0f m2" % (len(tris), len(files), area))
    if min_area and area < min_area:
        print("PATH_BLOCKERS FAIL the barrier colliders shrank to %.0f m2 (at least %.0f m2): the barriers were deleted, not moved" % (area, min_area))
        return 1
    if surf_grid is not None:
        print("lips: %d positions with a surface step of more than %.2f m" % (lips_total, lip))
        if max_lips >= 0 and lips_total > max_lips:
            print("PATH_BLOCKERS FAIL %d lip positions (at most %d)" % (lips_total, max_lips))
            return 1
    print("PATH_BLOCKERS %s" % ("OK" if total <= max_bad else "FAIL %d blocked points in %d paths" % (total, len(files))))
    return 0 if total <= max_bad else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
