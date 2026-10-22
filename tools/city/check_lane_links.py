#!/usr/bin/env python3
"""check_lane_links — every ramp attach is a drivable link in lanes.json.

    python tools/city/check_lane_links.py <lanes.json> <city.json> [--quiet]

The old Godot test only asks "does any link leave one of the ramp's lanes?". This asks the real question,
per attach of every ramp:
  * attach_start (the ramp leaves its parent): a lane of the PARENT ending next to the attach must reach a
    lane of the RAMP that starts next to it;
  * attach_end (the ramp joins its parent): a lane of the RAMP ending next to the attach must reach a lane
    of the PARENT that starts next to it;
reaching = following links / `next` through at most 3 lanes (junction connectors may sit in between).
"Next to" = the lane end is within 25 m (the road builder's ATTACH_TOLERANCE) of the ramp's end point.
Also reports ramp lanes marked as a map-edge terminus that are nowhere near the map edge.
"""
import json
import math
import sys

TOL = 25.0
DEPTH = 3
EDGE = 60.0


def d2(a, b):
    return math.hypot(a[0] - b[0], a[2] - b[2])


def main(argv):
    quiet = "--quiet" in argv
    args = [a for a in argv[1:] if not a.startswith("--")]
    lanes_doc = json.load(open(args[0], encoding="utf-8"))
    city = json.load(open(args[1], encoding="utf-8"))
    lanes = {l["id"]: l for l in lanes_doc["lanes"]}
    by_road = {}
    for lane in lanes_doc["lanes"]:
        by_road.setdefault(lane["road"], []).append(lane)
    adj = {}
    for link in lanes_doc.get("links", []):
        adj.setdefault(link["from"], set()).add(link["to"])
    for lane in lanes_doc["lanes"]:
        for nxt in lane.get("next", []):
            adj.setdefault(lane["id"], set()).add(nxt)
    roads = {r["id"]: r for r in city["roads"]}

    def reaches(sources, targets):
        want = {t["id"] for t in targets}
        frontier = {s["id"] for s in sources}
        seen = set(frontier)
        for _ in range(DEPTH):
            nxt = set()
            for lid in frontier:
                for to in adj.get(lid, ()):
                    if to in want:
                        return True
                    if to not in seen:
                        seen.add(to)
                        nxt.add(to)
            frontier = nxt
        return False

    missing, total = [], 0
    for road in city["roads"]:
        if road["kind"] != "ramp":
            continue
        for key, idx in (("attach_start", 0), ("attach_end", -1)):
            att = road.get(key)
            if not att or att["road"] not in roads:
                continue
            total += 1
            cp = road["points"][idx]
            ramp_lanes = by_road.get(road["id"], [])
            parent_lanes = by_road.get(att["road"], [])
            if key == "attach_start":
                sources = [l for l in parent_lanes if d2(l["points"][-1], cp) <= TOL]
                targets = [l for l in ramp_lanes if d2(l["points"][0], cp) <= TOL]
            else:
                sources = [l for l in ramp_lanes if d2(l["points"][-1], cp) <= TOL]
                targets = [l for l in parent_lanes if d2(l["points"][0], cp) <= TOL]
            ok = bool(sources) and bool(targets) and reaches(sources, targets)
            if not ok:
                near_end = min((d2(l["points"][-1], cp) for l in (parent_lanes if key == "attach_start" else ramp_lanes)), default=-1.0)
                near_start = min((d2(l["points"][0], cp) for l in (ramp_lanes if key == "attach_start" else parent_lanes)), default=-1.0)
                missing.append("%s.%s -> %s: %d source lanes, %d target lanes within %.0f m (nearest source end %.1f m, nearest target start %.1f m)" % (
                    road["id"], key, att["road"], len(sources), len(targets), TOL, near_end, near_start))
            elif not quiet:
                print("OK      %s.%s -> %s" % (road["id"], key, att["road"]))
    win = city["window"]
    fake_edges = []
    for lane in lanes_doc["lanes"]:
        if lane.get("terminus_kind") != "map_edge" or roads.get(lane["road"], {}).get("kind") != "ramp":
            continue
        end = lane["points"][-1]
        edge = min(end[0] - win["x_min"], win["x_max"] - end[0], end[2] - win["z_min"], win["z_max"] - end[2])
        if edge > EDGE:
            fake_edges.append("%s ends %.0f m from the window edge but is a map_edge terminus" % (lane["id"], edge))
    for line in missing:
        print("MISSING", line)
    for line in fake_edges[:8]:
        print("FAKE_EDGE", line)
    if len(fake_edges) > 8:
        print("FAKE_EDGE ... %d more" % (len(fake_edges) - 8))
    bad = len(missing) + len(fake_edges)
    print("LANE_LINKS %s (%d attaches, %d missing, %d ramp lanes wrongly marked as map edge)" % (
        "OK" if not bad else "FAIL", total, len(missing), len(fake_edges)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
