#!/usr/bin/env python3
"""check_route_itinerary — does the race drive the roads of its itinerary? (no Godot needed)

    python tools/city/check_route_itinerary.py <city.json> <lanes.json> [--quiet] [--off M]

The game builds the racing line of a route from the shortest lane path between each two gates (check_routes_drivable.py is
the replica of that). The generator places the gates along the itinerary of the route (its "segments": the roads in order,
with the direction of the traffic), every 400 m of driving. Where the itinerary comes back near itself (out on Henan Rd, back
on Fujian Rd 127 m to the west), the shortest path between two gates can leave the itinerary and cut across, and the race then
never drives the roads in between: the line is still drivable and every leg is 300-500 m, so the other checks see nothing.

For every leg of every route (the closing leg of a circuit is only counted for SKIPPED: it goes back to the start by any way) the
shortest lane
path is taken with check_routes_drivable.leg_report, the lanes are turned into roads (the connectors of the junctions are not
counted), and:
  OFF_ITINERARY  the leg drives more than --off metres (60) on roads that are not in the itinerary
  SKIPPED        a road of the itinerary is driven by no leg at all (the race does not go there)
Prints one line per failure and "ROUTE_ITINERARY OK" or "ROUTE_ITINERARY FAIL n"; exit 1 on a failure.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_routes_drivable as crd  # noqa: E402

OFF = 60.0


def lane_road(lane):
    """The road of a lane, or None for a connector of a junction."""
    if lane.get("connector"):
        return None
    return lane.get("road")


def leg_roads(lanes, seq):
    """[(road, metres)] in the order the leg drives them (the same road twice in a row is merged)."""
    out = []
    for k in seq:
        lane = lanes.lanes[k]
        road = lane_road(lane)
        if road is None:
            continue
        pts = lane["points"]
        metres = sum(((b[0] - a[0]) ** 2 + (b[2] - a[2]) ** 2) ** 0.5 for a, b in zip(pts, pts[1:]))
        if out and out[-1][0] == road:
            out[-1] = (road, out[-1][1] + metres)
        else:
            out.append((road, metres))
    return out


def check_route(route, lanes, off):
    fails = []
    itinerary = [s[0] for s in route.get("segments", [])]
    cps = route["checkpoints"]
    forwards = crd.face_the_route(lanes, cps, True)
    driven = set()
    for i in range(len(cps) - 1):
        _problem, _metres, _line, seq = crd.leg_report(lanes, cps[i], cps[i + 1], forwards[i], forwards[i + 1], False)
        roads = leg_roads(lanes, seq or [])
        outside = sum(m for r, m in roads if r not in itinerary)
        if outside > off:
            names = ", ".join("%s %.0f m" % (r, m) for r, m in roads if r not in itinerary)
            fails.append("OFF_ITINERARY %s leg %d->%d: %.0f m off the itinerary (%s)" % (route["id"], i, i + 1, outside, names))
        driven |= set(r for r, _m in roads if r in itinerary)
    circuit = route.get("kind") == "race" or route.get("laps", 1) > 1
    if circuit and len(cps) > 1:
        # the closing leg may go back to the start by any way, but the roads of the itinerary it drives are driven
        _problem, _metres, _line, seq = crd.leg_report(lanes, cps[-1], cps[0], forwards[-1], forwards[0], True)
        driven |= set(r for r, _m in leg_roads(lanes, seq or []))
    for r in itinerary:
        if r not in driven:
            fails.append("SKIPPED %s: the race never drives %s" % (route["id"], r))
    return fails


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    off = float(argv[argv.index("--off") + 1]) if "--off" in argv else OFF
    if "--off" in argv:
        args.remove(argv[argv.index("--off") + 1])
    if len(args) != 2:
        print(__doc__)
        return 2
    city = json.load(open(args[0], encoding="utf-8"))
    lanes = crd.Lanes(json.load(open(args[1], encoding="utf-8")))
    fails = []
    for route in city["routes"]:
        got = check_route(route, lanes, off)
        if "--quiet" not in argv:
            print("route %-16s %2d gates, %2d itinerary roads: %s" % (route["id"], len(route["checkpoints"]),
                                                                    len(route.get("segments", [])), "ok" if not got else "%d failures" % len(got)))
        fails += got
    for line in fails:
        print(line)
    print("ROUTE_ITINERARY OK" if not fails else "ROUTE_ITINERARY FAIL %d" % len(fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
