#!/usr/bin/env python3
"""check_lane_dupes — no two connectors join the same two lanes, and no movement is lost (lanes.json only, no Godot).

    python tools/city/check_lane_dupes.py <lanes.json> [--ref <lanes.json of the reference build>] [--quiet]

A connector lane of a junction joins the lane it leaves from (the lane whose "next" holds it) to the lane it leads to (its own
"next"). Two junctions close together (a staggered crossing: two T-junctions 28 m apart on Chongqing Rd) both took the lane that
passes between them as an approach and both built the same straight-on connector: two lanes in the same place, and two traffic
cars on them overlap without seeing each other (soak_traffic: a car stood 39 s on Chongqing Rd, touching the other one).
  DUPLICATE  a (from lane, to lane) pair joined by more than one connector
With --ref, the movements of the two graphs are compared: the set of (from lane, to lane) pairs that a connector or a direct link
joins (by lane id; the connectors themselves are not counted) must be the same:
  LOST       a pair of the reference that the graph no longer joins
  NEW        a pair the reference does not join
Prints the counts, the first pairs of each kind, and "LANE_DUPES OK" or "LANE_DUPES FAIL n"; exit 1 on a failure.
"""
import collections
import json
import sys


def load(path):
    return json.load(open(path, encoding="utf-8"))["lanes"]


def pairs(lanes):
    """{(from, to): [connector ids]} for the movements through connectors, and the set of all joined pairs."""
    by_id = {l["id"]: l for l in lanes}
    through = collections.defaultdict(list)
    joined = set()
    for lane in lanes:
        if lane.get("connector"):
            continue
        for nxt in lane.get("next") or []:
            target = by_id.get(nxt)
            if target is None:
                continue
            if not target.get("connector"):
                joined.add((lane["id"], nxt))
                continue
            for dst in target.get("next") or []:
                through[(lane["id"], dst)].append(nxt)
                joined.add((lane["id"], dst))
    return through, joined


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    ref = argv[argv.index("--ref") + 1] if "--ref" in argv else None
    if ref:
        args.remove(ref)
    if len(args) != 1:
        print(__doc__)
        return 2
    lanes = load(args[0])
    through, joined = pairs(lanes)
    dupes = {k: v for k, v in through.items() if len(v) > 1}
    fails = len(dupes)
    print("%d lanes, %d movements through connectors, %d pairs joined by more than one connector (%d extra connectors)"
          % (len(lanes), len(through), len(dupes), sum(len(v) - 1 for v in dupes.values())))
    if "--quiet" not in argv:
        for (a, b), ids in sorted(dupes.items())[:8]:
            print("DUPLICATE %s -> %s: %s" % (a, b, ", ".join(ids)))
    if ref:
        _through, ref_joined = pairs(load(ref))
        lost = sorted(ref_joined - joined)
        new = sorted(joined - ref_joined)
        print("against the reference: %d pairs lost, %d new" % (len(lost), len(new)))
        for a, b in lost[:8]:
            print("LOST %s -> %s" % (a, b))
        for a, b in new[:8]:
            print("NEW %s -> %s" % (a, b))
        fails += len(lost) + len(new)
    print("LANE_DUPES OK" if not fails else "LANE_DUPES FAIL %d" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
