#!/usr/bin/env python3
"""check_junction_exits — can a car leave every two-way road at every junction of the roads unit? (lanes.json only, no Godot)

    python tools/city/check_junction_exits.py <city.json> <lanes.json> [--max N] [--quiet]

The connectors of a junction (lanes with "connector": true) carry the id of their junction ("junction": the junction of the roads
unit, after blender/city/roads/load.py merged the records of city.json that describe one crossing). A road is ENTERED at a junction
when a connector of that junction leads into one of its lanes, and LEFT when one of its lanes leads into a connector of the junction.
A two-way road (lanes in both directions) that a junction enters but never leaves runs through the junction: its lanes are not cut
there, so the cars on it cannot turn off it, and the turns from the side streets onto it end on the middle of its lanes. The cause
seen first: a side street that ends at the kerb of a main road puts the centre of the junction beside the main road (Henan Rd at
the junction of st_d1_ns_3 and st_d2_ew_4: 18.5 m off its centre line), and the main road is cut only within a radius of the
centre, which its centre line never comes into.

THROUGH   a two-way road entered at a junction and never left there
Prints the count, the first cases and "JUNCTION_EXITS OK" or "JUNCTION_EXITS FAIL n"; exit 0 when n <= --max (default 0).
"""
import collections
import json
import sys


def through_roads(city, lanes):
    roads = {r["id"]: r for r in city["roads"]}
    by_id = {l["id"]: l for l in lanes}
    entered = collections.defaultdict(set)
    left = collections.defaultdict(set)
    for lane in lanes:
        if lane.get("connector") and lane.get("junction"):
            for nxt in lane.get("next") or []:
                target = by_id.get(nxt)
                if target is not None and not target.get("connector"):
                    entered[lane["junction"]].add(target["road"])
    for lane in lanes:
        if lane.get("connector"):
            continue
        for nxt in lane.get("next") or []:
            con = by_id.get(nxt)
            if con is not None and con.get("connector") and con.get("junction"):
                left[con["junction"]].add(lane["road"])
    out = []
    for jid in sorted(entered):
        for rid in sorted(entered[jid] - left[jid]):
            road = roads.get(rid)
            if road is not None and road.get("lanes_fwd", 0) > 0 and road.get("lanes_back", 0) > 0:
                out.append((jid, rid))
    return out


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    limit = int(argv[argv.index("--max") + 1]) if "--max" in argv else 0
    if "--max" in argv:
        args.remove(argv[argv.index("--max") + 1])
    if len(args) != 2:
        print(__doc__)
        return 2
    city = json.load(open(args[0], encoding="utf-8"))
    lanes = json.load(open(args[1], encoding="utf-8"))["lanes"]
    bad = through_roads(city, lanes)
    print("%d two-way roads run through a junction that enters them (no lane of theirs leaves it)" % len(bad))
    if "--quiet" not in argv:
        for jid, rid in bad[:30]:
            print("THROUGH %s: %s" % (jid, rid))
    print("JUNCTION_EXITS OK" if len(bad) <= limit else "JUNCTION_EXITS FAIL %d" % len(bad))
    return 0 if len(bad) <= limit else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
