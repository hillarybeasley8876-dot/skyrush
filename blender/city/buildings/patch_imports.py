"""Patch the .import files of the city tiles.

    python3 blender/city/buildings/patch_imports.py [--dir game/assets/city/blocks]

The scene importer writes the .import file of a new tile with its own defaults.  Two
of them cost a lot and are not wanted:

  meshes/generate_lods=false        the city has its own near/far tiles
  meshes/create_shadow_meshes=false the shadow casting is done by the world
  meshes/ensure_tangents=true       the tiles are written WITHOUT tangents (a third
                                    of the bytes), so the import has to generate them
                                    or the normal maps of the facades are wrong.

Run it once after the first import of a new tile (the editor writes the .import file
when it first sees the asset).
"""
import argparse
import os
import sys

BLOCKS_DIR = os.path.expanduser("~/m/skyrush/game/assets/city/blocks")

WANTED = {
    "meshes/generate_lods": "false",
    "meshes/create_shadow_meshes": "false",
    "meshes/ensure_tangents": "true",
}


def patch(path):
    """Set the wanted options in one .import file; returns the number of changes."""
    with open(path, "r") as fh:
        lines = fh.read().splitlines()
    changed = 0
    out = []
    seen = set()
    for line in lines:
        key = line.split("=")[0].strip()
        if key in WANTED:
            seen.add(key)
            want = "%s=%s" % (key, WANTED[key])
            if line != want:
                changed += 1
            out.append(want)
        else:
            out.append(line)
    for key, value in WANTED.items():
        if key not in seen:
            out.append("%s=%s" % (key, value))
            changed += 1
    if changed:
        with open(path, "w") as fh:
            fh.write("\n".join(out) + "\n")
    return changed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=BLOCKS_DIR)
    opts = ap.parse_args()
    if not os.path.isdir(opts.dir):
        print("no such directory: %s" % opts.dir)
        return 1
    files = 0
    changed = 0
    for name in sorted(os.listdir(opts.dir)):
        if not name.startswith("blocks_") or not name.endswith(".import"):
            continue
        files += 1
        changed += patch(os.path.join(opts.dir, name))
    print("%d .import files, %d options fixed" % (files, changed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
