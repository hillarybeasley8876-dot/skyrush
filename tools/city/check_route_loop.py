#!/usr/bin/env python3
"""check_route_loop — the grand loop comes back to its start, and nothing else of the routes moved (city.json only).

    python tools/city/check_route_loop.py <new city.json> <reference city.json> [--loop-only]

Passes when, in the new map:
  * grand_loop is a race whose itinerary ("segments") begins with the race up to the tunnel, in this order: the Yan'an
    elevated road, the dragon ramp, the N-S elevated road, the inner ring, the Nanpu spiral and bridge, the Pudong loop,
    Pudong South Rd, Century Ave and the tunnel (each with its direction);
  * its last checkpoint is within MAX_CLOSE metres (in plan) of its first one, and it has at least 20 checkpoints;
  * its itinerary goes by the Bund (MUST_DRIVE: Nanjing E Rd and the Bund, the part of the race the loop is for);
  * every other route has exactly the checkpoints, the grid and the itinerary it has in the reference map (not with --loop-only:
    a job that places the gates of every route anew checks only the grand loop).
Prints one line per failure and "ROUTE_LOOP OK" or "ROUTE_LOOP FAIL n"; exit 1 on a failure.
"""
import json
import math
import sys

HEAD = [["yanan_elevated", 1], ["ramp_rt_eb_sb", 1], ["ns_elevated", 1], ["inner_ring", 1], ["nanpu_spiral_upper", 1],
        ["nanpu_bridge", 1], ["nanpu_pudong_loop", 1], ["pudong_south_rd", -1], ["century_ave", -1], ["yanan_tunnel", -1]]
MAX_CLOSE = 900.0
MUST_DRIVE = ("st_nanjing_e_rd", "bund_zhongshan_e1")
MIN_CHECKPOINTS = 20


def check(new, ref, loop_only=False):
    fails = []
    routes = {r["id"]: r for r in new["routes"]}
    loop = routes.get("grand_loop")
    if loop is None:
        return ["grand_loop is missing"]
    if loop.get("kind") != "race":
        fails.append("grand_loop is a %s, not a race" % loop.get("kind"))
    seg = loop.get("segments", [])
    if [list(s) for s in seg[:len(HEAD)]] != HEAD:
        fails.append("grand_loop does not begin with the race up to the tunnel: %s" % seg[:len(HEAD)])
    for road in MUST_DRIVE:
        if road not in [s[0] for s in seg]:
            fails.append("grand_loop does not go by %s" % road)
    cps = loop.get("checkpoints", [])
    if len(cps) < MIN_CHECKPOINTS:
        fails.append("grand_loop has %d checkpoints (at least %d)" % (len(cps), MIN_CHECKPOINTS))
    elif math.hypot(cps[-1][0] - cps[0][0], cps[-1][2] - cps[0][2]) > MAX_CLOSE:
        fails.append("grand_loop ends %.0f m from its start (at most %.0f): last checkpoint (%.0f, %.0f)"
                     % (math.hypot(cps[-1][0] - cps[0][0], cps[-1][2] - cps[0][2]), MAX_CLOSE, cps[-1][0], cps[-1][2]))
    for old in ([] if loop_only else ref["routes"]):
        if old["id"] == "grand_loop":
            continue
        cur = routes.get(old["id"])
        if cur is None:
            fails.append("%s is missing" % old["id"])
            continue
        for key in ("checkpoints", "grid", "segments", "kind", "laps"):
            if cur.get(key) != old.get(key):
                fails.append("%s: its %s changed" % (old["id"], key))
    return fails


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    if len(args) != 2:
        print(__doc__)
        return 2
    new = json.load(open(args[0], encoding="utf-8"))
    ref = json.load(open(args[1], encoding="utf-8"))
    fails = check(new, ref, "--loop-only" in argv)
    for line in fails:
        print(line)
    print("ROUTE_LOOP OK" if not fails else "ROUTE_LOOP FAIL %d" % len(fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
