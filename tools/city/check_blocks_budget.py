#!/usr/bin/env python3
"""check_blocks_budget — do the building tiles meet the triangle budgets without being gutted? (no Godot needed)

    python tools/city/check_blocks_budget.py <blocks dir> --ref <reference.json> [--near 600000] [--far 40000] [--only "tx,tz;tx,tz"]

Reads blocks_<tx>_<tz>.json (the sidecar: stats.tris of the near tile, stats.buildings) and blocks_<tx>_<tz>_far.gltf
(the triangles of the far LOD, counted from the index accessors) for every tile of the directory (or the --only list).
Requirements per tile:
  1. the near tile has at most --near triangles and the far LOD at most --far (the budgets of the brief, the same numbers
     as game/assets/city/blocks/tests/test_blocks.gd);
  2. the tile keeps its buildings: at least 95 % of the buildings of the reference tile;
  3. the tile is not gutted: the near tile keeps at least 60 % of the reference triangles (or the budget, if smaller... it
     must be under the budget AND over 60 % of the reference), the far LOD keeps at least 25 % of the reference triangles
     and never fewer than 2000.
The reference file is {tile: {"near": tris, "buildings": n, "far": tris}} (the unconstrained build of the same city).
Prints one line per tile and "BLOCKS_BUDGET OK" or "BLOCKS_BUDGET FAIL n".
"""
import json
import os
import sys


def far_tris(path):
    g = json.load(open(path, encoding="utf-8"))
    n = 0
    for m in g.get("meshes", []):
        for p in m["primitives"]:
            if "indices" in p:
                n += g["accessors"][p["indices"]]["count"] // 3
    return n


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    opt = lambda n, d: argv[argv.index(n) + 1] if n in argv else d  # noqa: E731
    near_budget, far_budget = int(opt("--near", "600000")), int(opt("--far", "40000"))
    ref = json.load(open(opt("--ref", ""), encoding="utf-8"))
    only = [t.strip().replace(",", "_") for t in opt("--only", "").split(";") if t.strip()]
    for n in ("--near", "--far", "--ref", "--only"):
        if n in argv:
            args.remove(argv[argv.index(n) + 1])
    folder = args[0]
    tiles = sorted(f[:-5] for f in os.listdir(folder) if f.startswith("blocks_") and f.endswith(".json") and not f.endswith("_far.json"))
    if only:
        tiles = [t for t in tiles if t[len("blocks_"):] in only]
    bad = 0
    for tile in tiles:
        side = json.load(open(os.path.join(folder, tile + ".json"), encoding="utf-8"))["stats"]
        far_path = os.path.join(folder, tile + "_far.gltf")
        far = far_tris(far_path) if os.path.exists(far_path) else 0
        r = ref.get(tile)
        problems = []
        if side["tris"] > near_budget:
            problems.append("near %d > %d" % (side["tris"], near_budget))
        if far > far_budget:
            problems.append("far %d > %d" % (far, far_budget))
        if r:
            if side["buildings"] < 0.95 * r["buildings"]:
                problems.append("buildings %d < 95%% of %d" % (side["buildings"], r["buildings"]))
            if side["tris"] < 0.60 * r["near"]:
                problems.append("near %d < 60%% of %d (gutted)" % (side["tris"], r["near"]))
            if far < max(2000, 0.25 * r["far"]):
                problems.append("far %d < 25%% of %d (gutted)" % (far, r["far"]))
        else:
            problems.append("no reference for this tile")
        bad += 1 if problems else 0
        print("%s %-16s near %7d  far %6d  buildings %4d%s" % ("BAD " if problems else "ok  ", tile[len("blocks_"):], side["tris"], far,
                                                               side["buildings"], "  " + "; ".join(problems) if problems else ""))
    print("tiles checked: %d" % len(tiles))
    print("BLOCKS_BUDGET %s" % ("OK" if bad == 0 and tiles else "FAIL %d" % bad))
    return 0 if bad == 0 and tiles else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
