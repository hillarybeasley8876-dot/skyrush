#!/usr/bin/env python3
"""check_lane_graph — is the lane graph made of real lanes? (no Godot needed)

    python tools/city/check_lane_graph.py <lanes.json> [--max-giants N] [--max-junction-termini N] [--quiet]

Two defects that the offline checks of the ramps never saw, and that the route and traffic code of the game suffers from:
  giants      a junction connector (a movement through a junction) longer than --max-connector metres (default 200) or
              whose two ends are further apart than 120 m (the cap of lane_paths.MAX_CONNECTOR). A movement is a few
              metres to a few dozen metres; a 346 m or 1500 m one is a phantom lane across blocks, rivers and decks.
              (Merge junctions had no cap: 98 phantom movements; the cap now holds for them too.)
  termini     a lane without a successor that is flagged terminus_kind "junction": a road that ends at a crossing and
              has no movement there. At a T the side road must turn left or right onto the through road; a through road
              that is not cut at the T (a rounding error in the kerb return, junctions.MIN_CUT) leaves 50-200 of them.
Also prints the number of connectors, their median and longest length, and the lanes without successor / predecessor.
Exit 0 when giants <= --max-giants (default 0) and termini <= --max-junction-termini (default: no limit).
"""
import json
import math
import sys
from collections import Counter

CHORD_CAP = 120.0


def plen(points):
    return sum(math.dist(a, b) for a, b in zip(points, points[1:]))


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    quiet = "--quiet" in argv

    def opt(name, default):
        return float(argv[argv.index(name) + 1]) if name in argv else default

    max_connector = opt("--max-connector", 200.0)
    max_giants = int(opt("--max-giants", 0))
    max_termini = int(opt("--max-junction-termini", 10 ** 9))
    for name in ("--max-connector", "--max-giants", "--max-junction-termini"):
        if name in argv:
            args.remove(argv[argv.index(name) + 1])
    lanes = json.load(open(args[0], encoding="utf-8"))["lanes"]
    by_id = {lane["id"]: lane for lane in lanes}
    connectors = [lane for lane in lanes if lane.get("junction")]
    lengths = sorted(plen(lane["points"]) for lane in connectors)
    giants = []
    for lane in connectors:
        length = plen(lane["points"])
        chord = math.dist(lane["points"][0], lane["points"][-1])
        if length > max_connector or chord > CHORD_CAP:
            giants.append((length, chord, lane["id"]))
    giants.sort(reverse=True)
    termini = [lane for lane in lanes if not lane["next"] and lane.get("terminus_kind") == "junction"]
    indegree = Counter(n for lane in lanes for n in lane["next"] if n in by_id)
    print("%d lanes, %d junction connectors (median %.0f m, longest %.0f m)" % (
        len(lanes), len(connectors), lengths[len(lengths) // 2] if lengths else 0.0, lengths[-1] if lengths else 0.0))
    print("%d lanes without a successor (%d at a junction, %d at the map edge), %d without a predecessor" % (
        sum(1 for lane in lanes if not lane["next"]), len(termini),
        sum(1 for lane in lanes if not lane["next"] and lane.get("terminus_kind") == "map_edge"),
        sum(1 for lane in lanes if indegree[lane["id"]] == 0)))
    if not quiet:
        for (length, chord, lid) in giants[:10]:
            print("giant connector: %.0f m long, ends %.0f m apart: %s" % (length, chord, lid))
        by_road = Counter(lane["road"] for lane in termini)
        if termini:
            print("junction termini by road: %s" % ", ".join("%s:%d" % kv for kv in by_road.most_common(8)))
    ok = len(giants) <= max_giants and len(termini) <= max_termini
    print("LANE_GRAPH %s (giants %d of at most %d, junction termini %d of at most %s)" % (
        "OK" if ok else "FAIL", len(giants), max_giants, len(termini), max_termini if max_termini < 10 ** 9 else "any"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
