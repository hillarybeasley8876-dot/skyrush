#!/usr/bin/env python3
"""restamp_blocks — the building tiles of the old map are the tiles of a new city.json that only changes what they never read.

    python tools/city/restamp_blocks.py <old city.json> <new city.json> [<blocks dir>] [--dry-run]

blender/city/buildings/build_city.py writes the sha256 of the city.json it was built from into every sidecar
blocks_<tx>_<tz>.json, and test_blocks.gd and check_blocks_built.py fail a tile that was built from another map. The tile builder
reads the window, the blocks, the roads and the water of the map: a new map that only changes the POIs, the sky lanes, the routes,
the spawns, the junctions or the notes gives the same tiles, and rebuilding all of them in Blender would only change their
digest. The tool checks that every other section of the two maps is the same and that every sidecar was built from the old map,
then writes the digest of the new map into the sidecars (those 64 characters are all that change). Anything else needs the
rebuild. Prints "RESTAMP OK n" or the reason it refused (exit 1).
"""
import glob
import hashlib
import json
import os
import sys

## The sections of city.json the tile builder never reads (blender/city/buildings: build_city.py, citydata.py).
NOT_READ = ("pois", "sky_lanes", "routes", "spawns", "junctions", "notes")
BLOCKS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "game", "assets", "city", "blocks")


def main(argv):
    dry = "--dry-run" in argv
    args = [a for a in argv[1:] if not a.startswith("--")]
    if len(args) < 2:
        print(__doc__)
        return 2
    old_raw = open(args[0], "rb").read()
    new_raw = open(args[1], "rb").read()
    folder = args[2] if len(args) > 2 else BLOCKS_DIR
    old_map = json.loads(old_raw.decode("utf-8"))
    new_map = json.loads(new_raw.decode("utf-8"))
    changed = [key for key in sorted(set(old_map) | set(new_map)) if key not in NOT_READ
               and json.dumps(old_map.get(key), sort_keys=True) != json.dumps(new_map.get(key), sort_keys=True)]
    if changed:
        print("RESTAMP REFUSED: the tile builder reads %s, and it changed: rebuild the tiles" % ", ".join(changed))
        return 1
    old_digest = hashlib.sha256(old_raw).hexdigest()
    new_digest = hashlib.sha256(new_raw).hexdigest()
    paths = sorted(glob.glob(os.path.join(folder, "blocks_*.json")))
    if not paths:
        print("RESTAMP REFUSED: no sidecar in %s" % folder)
        return 1
    stale = []
    for path in paths:
        recorded = json.loads(open(path, "rb").read().decode("utf-8")).get("city_sha256", "")
        if recorded not in (old_digest, new_digest):
            stale.append("%s (%s)" % (os.path.basename(path), recorded[:12]))
    if stale:
        print("RESTAMP REFUSED: %d sidecars were not built from the old map: %s" % (len(stale), ", ".join(stale[:8])))
        return 1
    done = 0
    for path in paths:
        raw = open(path, "rb").read()
        key = ('"city_sha256": "%s"' % old_digest).encode("ascii")
        if raw.count(key) != 1:
            continue        # already the new map
        if not dry:
            with open(path, "wb") as fh:
                fh.write(raw.replace(key, ('"city_sha256": "%s"' % new_digest).encode("ascii")))
        done += 1
    print("RESTAMP OK %d of %d sidecars %s %s -> %s (the map changed only in %s)" % (
        done, len(paths), "would move" if dry else "moved", old_digest[:12], new_digest[:12],
        ", ".join(k for k in NOT_READ if json.dumps(old_map.get(k), sort_keys=True) != json.dumps(new_map.get(k), sort_keys=True))
        or "nothing"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
