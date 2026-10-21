"""The size table of the city tiles (the numbers of the import budget).

    python3 blender/city/buildings/tile_stats.py [--dir game/assets/city/blocks]

It prints one line per tile: the .gltf, the .bin and the far LOD size, the triangles
and the buildings, and the totals at the end.  The lead's budget is 15 MB per tile and
250 MB for the whole city.
"""
import argparse
import json
import os

BLOCKS_DIR = os.path.expanduser("~/m/skyrush/game/assets/city/blocks")
BUDGET_MB = 15.0
TOTAL_BUDGET_MB = 250.0


def _size(path):
    return os.path.getsize(path) if os.path.exists(path) else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=BLOCKS_DIR)
    opts = ap.parse_args()
    files = sorted(f for f in os.listdir(opts.dir)
                   if f.startswith("blocks_") and f.endswith(".json"))
    total = 0
    over = []
    print("%-16s %8s %9s %8s %8s %9s" % ("tile", "buildings", "tris", "gltf", "bin", "far"))
    for name in files:
        with open(os.path.join(opts.dir, name)) as fh:
            data = json.load(fh)
        base = name[:-5]
        gltf = _size(os.path.join(opts.dir, base + ".gltf"))
        binary = _size(os.path.join(opts.dir, base + ".bin"))
        far = _size(os.path.join(opts.dir, base + "_far.bin"))
        tris = data.get("stats", {}).get("tris", 0)
        size = (gltf + binary) / 1e6
        total += gltf + binary + far
        if size > BUDGET_MB:
            over.append((base, size))
        print("%-16s %8d %9d %8.2f %8.2f %9.2f" %
              (base, len(data.get("buildings", [])), tris, gltf / 1e6,
               binary / 1e6, far / 1e6))
    print("total %.1f MB in %d tiles (budget %.0f MB); %d tiles over %.0f MB" %
          (total / 1e6, len(files), TOTAL_BUDGET_MB, len(over), BUDGET_MB))
    for base, size in over:
        print("   over budget: %s %.1f MB" % (base, size))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
