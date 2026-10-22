#!/usr/bin/env python3
"""check_attach_geometry — are the lane links at the ramp attaches SMOOTH enough to drive?

    python tools/city/check_attach_geometry.py <lanes.json> <city.json> [--max-turn 30] [--quiet]

check_lane_links.py asks "is there a link?". This asks "can a car follow it?": for every lane of every ramp that
starts or ends at an attach, there must be a path through the lane graph (parent lane -> [connector] -> ramp lane,
or the reverse, at most 3 lanes) in which the direction of travel changes by at most --max-turn degrees at every
joint. A connector that bridges a 6 m lateral gap in 3 m of road turns the traffic by 70-90 degrees: cars cannot
follow it, they hit the parapet.
"Heading at a joint" = direction of the last (or first) 4 m of a lane.
"""
import json
import math
import sys

TOL = 60.0
DEPTH = 3


def heading(a, b):
    return math.degrees(math.atan2(b[0] - a[0], -(b[2] - a[2]))) % 360.0


def diff(a, b):
    return abs((a - b + 180.0) % 360.0 - 180.0)


def end_heading(lane, end):
    """Direction of travel at the start (end=0) or the finish (end=1) of a lane, over about 4 m."""
    pts = lane["points"]
    if end == 1:
        j = len(pts) - 1
        i = j
        while i > 0 and math.dist(pts[i], pts[j]) < 4.0:
            i -= 1
        return heading(pts[i], pts[j])
    i = 0
    j = 0
    while j < len(pts) - 1 and math.dist(pts[i], pts[j]) < 4.0:
        j += 1
    return heading(pts[i], pts[j])


def main(argv):
    quiet = "--quiet" in argv
    max_turn = float(argv[argv.index("--max-turn") + 1]) if "--max-turn" in argv else 30.0
    args = [a for a in argv[1:] if not a.startswith("--")]
    if "--max-turn" in argv:
        args.remove(argv[argv.index("--max-turn") + 1])
    doc = json.load(open(args[0], encoding="utf-8"))
    city = json.load(open(args[1], encoding="utf-8"))
    lanes = {l["id"]: l for l in doc["lanes"]}
    by_road = {}
    for l in doc["lanes"]:
        by_road.setdefault(l["road"], []).append(l)
    adj = {}
    for k in doc.get("links", []):
        adj.setdefault(k["from"], set()).add(k["to"])
    for l in doc["lanes"]:
        for n in l.get("next", []):
            adj.setdefault(l["id"], set()).add(n)

    def smooth_path(src, goal_ids):
        """True when some path src -> ... -> a lane of goal_ids turns at most max_turn at every joint."""
        frontier = [(src["id"], 0)]
        seen = {src["id"]}
        while frontier:
            nxt = []
            for lid, depth in frontier:
                a = lanes[lid]
                if depth >= DEPTH:
                    continue
                for to in sorted(adj.get(lid, ())):
                    b = lanes.get(to)
                    if b is None:
                        continue
                    if diff(end_heading(a, 1), end_heading(b, 0)) > max_turn:
                        continue
                    if to in goal_ids:
                        return True
                    if to not in seen:
                        seen.add(to)
                        nxt.append((to, depth + 1))
            frontier = nxt
        return False

    bad, checked = [], 0
    for road in city["roads"]:
        if road["kind"] != "ramp":
            continue
        for key, idx in (("attach_start", 0), ("attach_end", -1)):
            att = road.get(key)
            if not att:
                continue
            cp = road["points"][idx]
            ramp_lanes = by_road.get(road["id"], [])
            parent_lanes = by_road.get(att["road"], [])
            if key == "attach_start":
                targets = [l for l in ramp_lanes if not l.get("connector") and math.dist((l["points"][0][0], l["points"][0][2]), (cp[0], cp[2])) <= TOL]
                sources = [l for l in parent_lanes if not l.get("connector") and math.dist((l["points"][-1][0], l["points"][-1][2]), (cp[0], cp[2])) <= TOL]
                for t in targets:
                    checked += 1
                    if not any(smooth_path(s, {t["id"]}) for s in sources):
                        bad.append("%s.%s: no smooth path into ramp lane %s (turn limit %.0f deg)" % (road["id"], key, t["id"], max_turn))
            else:
                sources = [l for l in ramp_lanes if not l.get("connector") and math.dist((l["points"][-1][0], l["points"][-1][2]), (cp[0], cp[2])) <= TOL]
                goals = {l["id"] for l in parent_lanes if not l.get("connector") and math.dist((l["points"][0][0], l["points"][0][2]), (cp[0], cp[2])) <= TOL}
                for s in sources:
                    checked += 1
                    if not goals or not smooth_path(s, goals):
                        bad.append("%s.%s: no smooth path out of ramp lane %s (turn limit %.0f deg)" % (road["id"], key, s["id"], max_turn))
    for line in bad[: (0 if quiet else 40)]:
        print("FAIL", line)
    print("ATTACH_GEOMETRY %s (%d ramp lanes at attaches, %d without a smooth link, turn limit %.0f deg)" % (
        "FAIL" if bad else "OK", checked, len(bad), max_turn))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
