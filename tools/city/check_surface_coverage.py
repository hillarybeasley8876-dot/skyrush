#!/usr/bin/env python3
"""check_surface_coverage — does every lane sample have road surface collision under it? (no Godot needed)

    python tools/city/check_surface_coverage.py <tiles dir> <lanes.json> [--tol 0.15] [--csv out.csv] [--top 12] [--prefix attach_] [--max-bad N] [--max-area M2]

Parses the glTF tiles (roads_<tx>_<tz>.gltf + .bin), takes every triangle of the nodes named *surface-colonly*
(the road surface colliders), and for each lane point (every lane and connector of lanes.json) asks: is there a
surface triangle whose XZ footprint contains the point and whose height there is within --tol of the lane height?
This is the same question as the ray sweep of test_drive_collision.gd ("every lane has a road surface under it").
With --prefix only the lanes whose id starts with it are checked (attach_ = the connector lanes at the ramp attaches).
Prints the number of bad samples in total and per road, and the total area of all surface colliders.
Exit 0 when the total is <= --max-bad (default 0) and, when --max-area is given, the collider area is <= it
(so a job cannot "cover" the lanes by laying huge slabs).
"""
import array
import collections
import json
import math
import os
import struct
import sys

CELL = 16.0
FMT = {5123: ("H", 2), 5125: ("I", 4), 5121: ("B", 1)}


def read_accessor(gltf, bufs, idx):
    acc = gltf["accessors"][idx]
    view = gltf["bufferViews"][acc["bufferView"]]
    data = bufs[view["buffer"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    count = acc["count"]
    if acc["type"] == "VEC3":
        stride = view.get("byteStride", 12)
        out = []
        for i in range(count):
            out.append(struct.unpack_from("<3f", data, start + i * stride))
        return out
    code, size = FMT[acc["componentType"]]
    stride = view.get("byteStride", size)
    return [struct.unpack_from("<" + code, data, start + i * stride)[0] for i in range(count)]


def load_tile_triangles(path):
    gltf = json.load(open(path, encoding="utf-8"))
    base = os.path.dirname(path)
    bufs = [open(os.path.join(base, b["uri"]), "rb").read() for b in gltf["buffers"]]
    tris = []
    for node in gltf.get("nodes", []):
        name = node.get("name", "")
        if "surface-colonly" not in name or "mesh" not in node:
            continue
        shift = node.get("translation", (0.0, 0.0, 0.0))
        for prim in gltf["meshes"][node["mesh"]]["primitives"]:
            pos = read_accessor(gltf, bufs, prim["attributes"]["POSITION"])
            ind = read_accessor(gltf, bufs, prim["indices"]) if "indices" in prim else list(range(len(pos)))
            for k in range(0, len(ind) - 2, 3):
                a, b, c = (pos[ind[k]], pos[ind[k + 1]], pos[ind[k + 2]])
                tris.append(tuple((p[0] + shift[0], p[1] + shift[1], p[2] + shift[2]) for p in (a, b, c)))
    return tris


def build_grid(tris):
    grid = collections.defaultdict(list)
    for t in tris:
        xs, zs = [p[0] for p in t], [p[2] for p in t]
        for i in range(int(min(xs) // CELL), int(max(xs) // CELL) + 1):
            for j in range(int(min(zs) // CELL), int(max(zs) // CELL) + 1):
                grid[(i, j)].append(t)
    return grid


def height_at(t, x, z):
    """Height of the triangle at (x, z) or None when the point is outside its XZ footprint."""
    (ax, ay, az), (bx, by, bz), (cx, cy, cz) = t
    den = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
    if abs(den) < 1e-12:
        return None
    u = ((bz - cz) * (x - cx) + (cx - bx) * (z - cz)) / den
    v = ((cz - az) * (x - cx) + (ax - cx) * (z - cz)) / den
    w = 1.0 - u - v
    eps = -1e-6
    if u < eps or v < eps or w < eps:
        return None
    return u * ay + v * by + w * cy


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    opt = lambda n, d: argv[argv.index(n) + 1] if n in argv else d  # noqa: E731
    tol, top, max_bad = float(opt("--tol", "0.15")), int(opt("--top", "12")), int(opt("--max-bad", "0"))
    prefix = opt("--prefix", "")
    max_area = float(opt("--max-area", "0"))
    for v in (opt("--tol", ""), opt("--top", ""), opt("--max-bad", ""), opt("--csv", ""), prefix, opt("--max-area", "")):
        if v in args:
            args.remove(v)
    tiles_dir, lanes_path = args[0], args[1]
    tris = []
    for name in sorted(os.listdir(tiles_dir)):
        if name.startswith("roads_") and name.endswith(".gltf"):
            tris += load_tile_triangles(os.path.join(tiles_dir, name))
    grid = build_grid(tris)
    area = sum(0.5 * abs((t[1][0] - t[0][0]) * (t[2][2] - t[0][2]) - (t[2][0] - t[0][0]) * (t[1][2] - t[0][2])) for t in tris)
    lanes = json.load(open(lanes_path, encoding="utf-8"))["lanes"]
    bad, total = collections.Counter(), 0
    rows = []
    for lane in lanes:
        if prefix and not lane["id"].startswith(prefix):
            continue
        for p in lane["points"]:
            total += 1
            x, y, z = p[0], p[1], p[2]
            ok = False
            for t in grid.get((int(x // CELL), int(z // CELL)), ()):
                h = height_at(t, x, z)
                if h is not None and abs(h - y) <= tol:
                    ok = True
                    break
            if not ok:
                bad[lane["road"]] += 1
                rows.append("%s,%.2f,%.2f,%.2f" % (lane["road"], x, y, z))
    if "--csv" in argv:
        open(opt("--csv", ""), "w", encoding="utf-8").write("road,x,y,z\n" + "\n".join(rows) + "\n")
    print("triangles %d, lane samples %d, collider area %.0f m2 (XZ)" % (len(tris), total, area))
    print("SURFACE_COVERAGE bad samples: %d (%.2f %%)" % (sum(bad.values()), 100.0 * sum(bad.values()) / max(total, 1)))
    print("worst roads: " + ", ".join("%s:%d" % kv for kv in bad.most_common(top)))
    if max_area and area > max_area:
        print("SURFACE_AREA too large: %.0f m2 > %.0f m2" % (area, max_area))
        return 1
    return 0 if sum(bad.values()) <= max_bad else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
