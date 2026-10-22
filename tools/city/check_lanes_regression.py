#!/usr/bin/env python3
"""check_lanes_regression — a changed lanes.json did not damage the lane graph.

    python tools/city/check_lanes_regression.py <new lanes.json> <baseline lanes.json> <city.json>

Used by jobs that change how lanes are cut or linked. The baseline is the lanes.json the unmodified builder
produces (lanes-only build of the same city.json). It requires:
  1. roads that have nothing to do with a ramp attach are IDENTICAL to the baseline (same lane ids, same
     points, same links): a change for the attaches must not touch the rest of the city;
  2. every road keeps its drivable length: the lanes of a road cover the same metres (within 2 m per road);
  3. no sliver: no new lane shorter than 5 m (the baseline's shortest lanes are exempt);
  4. every link points at lanes that exist, `next` matches the links, lane ids are unique;
  5. a link between two real lanes joins them end to end: the end of the first and the start of the second
     are within 0.5 m (connector lanes carry the bigger gaps), the same rule test_lanes.gd applies.
"""
import json
import math
import sys


def plen(points):
    return sum(math.dist(a, b) for a, b in zip(points, points[1:]))


def main(argv):
    new = json.load(open(argv[1], encoding="utf-8"))
    base = json.load(open(argv[2], encoding="utf-8"))
    city = json.load(open(argv[3], encoding="utf-8"))
    touched = set()
    for road in city["roads"]:
        for key in ("attach_start", "attach_end"):
            if road.get(key):
                touched.add(road["id"])
                touched.add(road[key]["road"])
    bad = []

    def by_road(doc):
        out = {}
        for lane in doc["lanes"]:
            out.setdefault(lane["road"], []).append(lane)
        return out

    nb, bb = by_road(new), by_road(base)
    # 1. untouched roads identical
    for rid, lanes in bb.items():
        if rid in touched:
            continue
        a = sorted((l["id"], json.dumps(l["points"]), sorted(l["next"])) for l in lanes if not l.get("connector"))
        b = sorted((l["id"], json.dumps(l["points"]), sorted(l["next"])) for l in nb.get(rid, []) if not l.get("connector"))
        if a != b:
            bad.append("road %s has nothing to do with an attach but its lanes changed" % rid)
    # 2. same drivable length per road
    for rid, lanes in bb.items():
        ba = sum(plen(l["points"]) for l in lanes if not l.get("connector"))
        na = sum(plen(l["points"]) for l in nb.get(rid, []) if not l.get("connector"))
        if abs(ba - na) > 2.0:
            bad.append("road %s: lanes cover %.1f m, baseline %.1f m" % (rid, na, ba))
    # 3. slivers
    base_short = min((plen(l["points"]) for l in base["lanes"] if not l.get("connector")), default=0.0)
    floor = min(5.0, base_short)
    slivers = [l["id"] for l in new["lanes"] if not l.get("connector") and plen(l["points"]) < floor - 1e-6]
    if slivers:
        bad.append("%d lanes shorter than %.1f m, e.g. %s" % (len(slivers), floor, ", ".join(slivers[:4])))
    # 4. consistency
    ids = [l["id"] for l in new["lanes"]]
    lane = {l["id"]: l for l in new["lanes"]}
    if len(ids) != len(lane):
        bad.append("duplicate lane ids")
    for link in new["links"]:
        if link["from"] not in lane or link["to"] not in lane:
            bad.append("link %s -> %s names a lane that does not exist" % (link["from"], link["to"]))
            break
    link_pairs = {(k["from"], k["to"]) for k in new["links"]}
    for l in new["lanes"]:
        for n in l["next"]:
            if (l["id"], n) not in link_pairs:
                bad.append("lane %s lists next %s without a link" % (l["id"], n))
                break
    # 5. links join end to end
    worst, count = 0.0, 0
    for link in new["links"]:
        a, b = lane.get(link["from"]), lane.get(link["to"])
        if not a or not b or a.get("connector") or b.get("connector"):
            continue
        gap = math.dist(a["points"][-1], b["points"][0])
        worst = max(worst, gap)
        if gap > 0.5:
            count += 1
    if count:
        bad.append("%d direct links between real lanes do not meet end to end (worst %.2f m)" % (count, worst))
    for line in bad[:30]:
        print("FAIL", line)
    print("LANES_REGRESSION %s (%d lanes, %d links, %d problems)" % ("FAIL" if bad else "OK", len(new["lanes"]), len(new["links"]), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
