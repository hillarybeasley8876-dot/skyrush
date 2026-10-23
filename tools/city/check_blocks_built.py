#!/usr/bin/env python3
"""check_blocks_built — does every lot of the map carry a building? (the offline twin of test_blocks.gd, no Godot needed)

    python tools/city/check_blocks_built.py <blocks dir> [--tiles "tx,tz;tx,tz"] [--city city.json] [--min-coverage 0.30] [--max-bad N]

Reads the sidecars blocks_<tx>_<tz>.json that blender/city/buildings/build_city.py writes next to the tile glb files. Every entry of
their "blocks" list (a lot of the map, a piece of a lot is one entry) that is not a park or a plaza must have at least one building
and must be built at least --min-coverage of its area: the same rule as _check_block_coverage of game/assets/city/blocks/tests/test_blocks.gd.
With --city the sidecar must have been built from that city.json (its "city_sha256").
Without --tiles every sidecar of the folder is checked. Prints the lots that fail and "BLOCKS_BUILT OK" or "BLOCKS_BUILT FAIL n".
Exit 0 when the number of failing lots is <= --max-bad (default 0).
"""
import glob
import hashlib
import json
import os
import sys


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]

    def opt(name, default):
        return argv[argv.index(name) + 1] if name in argv else default

    tiles = [t.strip() for t in opt("--tiles", "").split(";") if t.strip()]
    city_path = opt("--city", "")
    min_cov = float(opt("--min-coverage", "0.30"))
    max_bad = int(opt("--max-bad", "0"))
    for name in ("--tiles", "--city", "--min-coverage", "--max-bad"):
        if name in argv:
            args.remove(argv[argv.index(name) + 1])
    digest = hashlib.sha256(open(city_path, "rb").read()).hexdigest() if city_path else ""
    if tiles:
        paths = [os.path.join(args[0], "blocks_%s.json" % t.replace(",", "_")) for t in tiles]
    else:
        paths = sorted(glob.glob(os.path.join(args[0], "blocks_*.json")))
    bad, lots = [], 0
    for path in paths:
        if not os.path.exists(path):
            bad.append("%s: no sidecar" % os.path.basename(path))
            continue
        data = json.load(open(path, encoding="utf-8"))
        name = os.path.basename(path)
        if digest and data.get("city_sha256") != digest:
            bad.append("%s: built from another map" % name)
        for entry in data.get("blocks", []):
            if entry.get("style") in ("park", "plaza"):
                continue
            lots += 1
            if int(entry.get("buildings", 0)) == 0:
                bad.append("%s: lot %s (%.0f m2) has no building" % (name, entry.get("id"), float(entry.get("area", 0.0))))
            elif float(entry.get("coverage", 0.0)) < min_cov:
                bad.append("%s: lot %s (%.0f m2) is only %.0f %% built" % (name, entry.get("id"), float(entry.get("area", 0.0)),
                                                                       100.0 * float(entry.get("coverage", 0.0))))
    for line in bad[:40]:
        print(line)
    print("%d sidecars, %d lots, %d fail" % (len(paths), lots, len(bad)))
    ok = len(bad) <= max_bad
    print("BLOCKS_BUILT %s" % ("OK" if ok else "FAIL %d" % len(bad)))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
