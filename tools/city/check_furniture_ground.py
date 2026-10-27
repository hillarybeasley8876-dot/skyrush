#!/usr/bin/env python3
"""check_furniture_ground — what does the street furniture stand on: a sidewalk, or the asphalt cars drive on? (no Godot needed)

    python tools/city/check_furniture_ground.py <road tiles dir> <furniture> [--max-asphalt N] [--min kind=N,...] [--quiet]

<furniture> is the road_furniture.json of a roads build ({"props": [{"kind", "x", "y", "z", "road", ...}]}) or the dump of the
props the game placed (game/tools/furniture_dump.gd: [[type, x, y, z, road], ...]). Every prop of a SOLID kind is looked up in the
tiles from above: the meshes under it at its own height (within LEVEL m) are asphalt (SH_wet_asphalt), sidewalk (SH_sidewalk,
the kerbs, the tactile strips) or planter (the soil and the ivy of the planters).

ON_ASPHALT   a solid prop with asphalt under it and no sidewalk or planter: it stands where cars drive (a tree in the
             asphalt of a junction, 2.65 m from the centre of a turning lane)
Prints the counts per kind, the first cases, and "FURNITURE_GROUND OK" or "FURNITURE_GROUND FAIL n": n is the number of
ON_ASPHALT props over --max-asphalt (default 0) plus the kinds below their --min count.
"""
import collections
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_surface_coverage as cs  # noqa: E402

SOLID = ("tree", "lamp", "lamp_heritage", "lamp_magnolia", "traffic_light", "bus_stop", "sign", "billboard", "noise_wall")
GROUND = {"asphalt": ("SH_wet_asphalt",),
          "sidewalk": ("SH_sidewalk", "Road_Tactile_Strip", "SH_kerb"),
          "planter": ("Road_Planter_Soil", "Road_Ivy")}
CELL = 4.0
LEVEL = 1.0   # m: a mesh this close to the height of the prop is the ground it stands on


def ground_index(tile_dir):
    """{(cell x, cell z): [(ground kind, triangle)]} of the ground meshes of every tile"""
    out = collections.defaultdict(list)
    for name in sorted(os.listdir(tile_dir)):
        if not name.endswith(".gltf"):
            continue
        g = json.load(open(os.path.join(tile_dir, name), encoding="utf-8"))
        bufs = None
        for node in g["nodes"]:
            if "mesh" not in node:
                continue
            kind = next((k for k, ends in GROUND.items() if any(node.get("name", "").endswith(e) for e in ends)), None)
            if kind is None:
                continue
            if bufs is None:
                bufs = [open(os.path.join(tile_dir, b["uri"]), "rb").read() for b in g["buffers"]]
            shift = node.get("translation", (0, 0, 0))
            for prim in g["meshes"][node["mesh"]]["primitives"]:
                pos = cs.read_accessor(g, bufs, prim["attributes"]["POSITION"])
                ind = cs.read_accessor(g, bufs, prim["indices"]) if "indices" in prim else list(range(len(pos)))
                for k in range(0, len(ind) - 2, 3):
                    tri = tuple(tuple(pos[ind[k + j]][c] + shift[c] for c in range(3)) for j in range(3))
                    add(out, kind, tri)
    return out


def add(index, kind, tri):
    xs = [p[0] for p in tri]
    zs = [p[2] for p in tri]
    for i in range(int(math.floor(min(xs) / CELL)), int(math.floor(max(xs) / CELL)) + 1):
        for j in range(int(math.floor(min(zs) / CELL)), int(math.floor(max(zs) / CELL)) + 1):
            index[(i, j)].append((kind, tri))


def ground_at(index, x, y, z):
    """the ground kinds under a point at its height"""
    kinds = set()
    for kind, tri in index.get((int(math.floor(x / CELL)), int(math.floor(z / CELL))), ()):
        (x1, y1, z1), (x2, y2, z2), (x3, y3, z3) = tri
        d = (z2 - z3) * (x1 - x3) + (x3 - x2) * (z1 - z3)
        if abs(d) < 1e-9:
            continue
        l1 = ((z2 - z3) * (x - x3) + (x3 - x2) * (z - z3)) / d
        l2 = ((z3 - z1) * (x - x3) + (x1 - x3) * (z - z3)) / d
        l3 = 1.0 - l1 - l2
        if min(l1, l2, l3) >= -1e-4 and abs(l1 * y1 + l2 * y2 + l3 * y3 - y) <= LEVEL:
            kinds.add(kind)
    return kinds


def load_props(path):
    """[(kind, x, y, z, road)] of a road_furniture.json or of a dump of the game"""
    data = json.load(open(path, encoding="utf-8"))
    if isinstance(data, dict):
        return [(p["kind"], float(p["x"]), float(p.get("y", 0.0)), float(p["z"]), p.get("road", "")) for p in data["props"]]
    return [(r[0], float(r[1]), float(r[2]), float(r[3]), r[4] if len(r) > 4 else "") for r in data]


def classify(index, props):
    """{kind: Counter(ground)} and the ON_ASPHALT props"""
    by_kind = collections.defaultdict(collections.Counter)
    bad = []
    for prop in props:
        if prop[0] not in SOLID:
            continue
        under = ground_at(index, prop[1], prop[2], prop[3])
        if "sidewalk" in under:
            tag = "sidewalk"
        elif "planter" in under:
            tag = "planter"
        elif "asphalt" in under:
            tag = "asphalt"
            bad.append(prop)
        else:
            tag = "none"
        by_kind[prop[0]][tag] += 1
    return by_kind, bad


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    for name in ("--max-asphalt", "--min"):
        if name in argv:
            args.remove(argv[argv.index(name) + 1])
    if len(args) != 2:
        print(__doc__)
        return 2
    limit = int(argv[argv.index("--max-asphalt") + 1]) if "--max-asphalt" in argv else 0
    minimum = {}
    if "--min" in argv:
        for part in argv[argv.index("--min") + 1].split(","):
            kind, count = part.split("=")
            minimum[kind] = int(count)
    by_kind, bad = classify(ground_index(args[0]), load_props(args[1]))
    total = sum(sum(c.values()) for c in by_kind.values())
    print("%d solid props, %d of them on the asphalt (%.1f %%)" % (total, len(bad), 100.0 * len(bad) / max(1, total)))
    short = []
    for kind in sorted(by_kind, key=lambda k: -sum(by_kind[k].values())):
        c = by_kind[kind]
        n = sum(c.values())
        print("  %-14s %6d  sidewalk %5.1f %%  planter %5.1f %%  asphalt %5.1f %%  none %5.1f %%" % (
            kind, n, 100.0 * c["sidewalk"] / n, 100.0 * c["planter"] / n, 100.0 * c["asphalt"] / n, 100.0 * c["none"] / n))
    for kind, count in sorted(minimum.items()):
        have = sum(by_kind.get(kind, {}).values())
        if have < count:
            short.append(kind)
            print("TOO_FEW %s: %d (at least %d)" % (kind, have, count))
    if "--quiet" not in argv:
        for prop in bad[:15]:
            print("ON_ASPHALT %s of %s at (%.1f, %.1f, %.1f)" % (prop[0], prop[4] or "-", prop[1], prop[2], prop[3]))
    over = max(0, len(bad) - limit) + len(short)
    print("FURNITURE_GROUND OK" if over == 0 else "FURNITURE_GROUND FAIL %d" % over)
    return 0 if over == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
