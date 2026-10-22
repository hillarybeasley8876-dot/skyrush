#!/usr/bin/env python3
"""check_network_size — the road network did not shrink to make a rule pass.

    python tools/city/check_network_size.py <city.json> [--min-km 173] [--min-roads 340]

Counts the roads and the drivable length (sum of every road's plan length) and fails when either drops
below the limits. The unmodified generator gives 354 roads and 178.8 km: the defaults allow 3 % loss,
which is room for trimming a few dangling stubs but not for deleting whole streets.
"""
import json
import math
import sys


def main(argv):
    city = json.load(open(argv[1], encoding="utf-8"))
    min_km = float(argv[argv.index("--min-km") + 1]) if "--min-km" in argv else 173.0
    min_roads = int(argv[argv.index("--min-roads") + 1]) if "--min-roads" in argv else 340
    km = sum(math.hypot(b[0] - a[0], b[2] - a[2]) for r in city["roads"]
             for a, b in zip(r["points"], r["points"][1:])) / 1000.0
    roads = len(city["roads"])
    ok = km >= min_km and roads >= min_roads
    print("roads %d (min %d), drivable %.1f km (min %.1f)" % (roads, min_roads, km, min_km))
    print("NETWORK_SIZE %s" % ("OK" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
