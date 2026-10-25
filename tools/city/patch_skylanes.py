#!/usr/bin/env python3
"""patch_skylanes — rebuilds the sky lanes of a city.json with the generator of city_marks, nothing else.

    python tools/city/patch_skylanes.py [data/city/city.json] [--dry]

The whole city is not built again (its roads and blocks stay exactly as they are): every lane is made again by
city_marks._sky_lane from its row in city_marks.SKY_LANES, the roads of the file (their built points) and the lots of the file,
the way build_city.py makes it, so running the patch twice gives the same file. The pads must come out where they are. The file
keeps its line endings. Then the sky lane rules of validate.py and check_skylanes_shape run on the result.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import city_json  # noqa: E402
import city_marks  # noqa: E402
import city_road  # noqa: E402
import city_rules_routes  # noqa: E402
import city_skylanes  # noqa: E402


def roads_of(city):
    """The roads of a city.json as city_road.Road objects with their built points (no plan: they are not built again)."""
    out = {}
    for r in city["roads"]:
        road = city_road.Road(r["id"], r.get("name", ""), r.get("name_en", ""), r["kind"], [], [],
                              lanes_fwd=r["lanes_fwd"], lanes_back=r["lanes_back"], lane_width=r["lane_width"],
                              median=r.get("median", 1.0), shoulder=r.get("shoulder", 0.5),
                              sidewalk=r.get("sidewalk", 0.0))
        road.points = [list(p) for p in r["points"]]
        # the stations of a built road are measured on the ground plane (city_road.Road.build)
        dist = [0.0]
        for a, b in zip(road.points, road.points[1:]):
            dist.append(dist[-1] + math.hypot(b[0] - a[0], b[2] - a[2]))
        road.dist = dist
        out[r["id"]] = road
    return out


def main(argv):
    path = next((a for a in argv if not a.startswith("--")), os.path.join(HERE, "..", "..", "data", "city", "city.json"))
    dry = "--dry" in argv
    raw = open(path, "rb").read()
    crlf = b"\r\n" in raw
    city = json.loads(raw.decode("utf-8"))
    specs = {s[0]: s for s in city_marks.SKY_LANES}
    by_id = roads_of(city)
    before = json.dumps({k: v for k, v in city.items() if k != "sky_lanes"}, sort_keys=True)
    straightest = city_marks.straight_runup
    for i, lane in enumerate(city["sky_lanes"]):
        spec = specs[lane["id"]]
        # the pad stays where it is: the station of the pad is found on the road again (the straightest run-up of the rounded
        # points of the file may be another station than the one of the build)
        station = _pad_station(by_id[spec[2]], spec[4], spec[5], lane["pad"])
        city_marks.straight_runup = lambda *_args, **_kw: station
        try:
            new = city_marks._sky_lane(by_id, city["blocks"], spec)
        finally:
            city_marks.straight_runup = straightest
        pad, was = new["pad"], lane["pad"]
        moved = math.dist((pad["x"], pad["y"], pad["z"]), (was["x"], was["y"], was["z"]))
        assert moved < 0.2 and abs(pad["heading_deg"] - was["heading_deg"]) < 0.5, \
            "the pad of %s moved %.2f m: %s -> %s" % (lane["id"], moved, was, pad)
        points = new["points"]
        report = city_marks.SKY_REPORTS[lane["id"]]
        steepest = 0.0
        for a, b in zip(points, points[1:]):
            run = math.hypot(b[0] - a[0], b[2] - a[2])
            if run > 0.5:
                steepest = max(steepest, abs(math.degrees(math.atan2(b[1] - a[1], run))))
        print("%-15s %3d -> %3d points, %4.0f -> %4.0f m, corners %s, cruise %.0f m, %d points lifted over a lot, the steepest "
              "%4.1f deg, the first rise %.2f m in %.0f m, ends %.1f m over its last point's road; rings %s" % (
                  lane["id"], len(lane["points"]), len(points),
                  sum(math.dist(a, b) for a, b in zip(lane["points"], lane["points"][1:])),
                  sum(math.dist(a, b) for a, b in zip(points, points[1:])),
                  ", ".join("%s r%.0f" % (n, r) for n, r in zip(report["corners"], report["radii"])), report["cruise"],
                  report["lifted"], steepest, points[1][1] - points[0][1],
                  math.dist(points[0], points[1]), points[-1][1] - _road_height(city, points[-1]), new["n2_rings_m"]))
        city["sky_lanes"][i] = {**lane, "points": points, "n2_rings_m": new["n2_rings_m"]}
    after = json.dumps({k: v for k, v in city.items() if k != "sky_lanes"}, sort_keys=True)
    assert before == after, "something besides the sky lanes changed"
    fails = city_rules_routes.check_sky_lanes(city)
    for f in fails:
        print("RULE FAIL", f)
    print("sky lane rules: %s" % ("OK" if not fails else "%d failures" % len(fails)))
    if dry:
        return 1 if fails else 0
    text = city_json._dump(city, 0) + "\n"
    if crlf:
        text = text.replace("\n", "\r\n")
    open(path, "wb").write(text.encode("utf-8"))
    print("written", path)
    import check_skylanes_shape  # noqa: E402
    shape = check_skylanes_shape.main(path)
    return 1 if fails or shape else 0


def _pad_station(road, direction, lane_index, pad):
    """The station of the road whose lane point is the pad (to a centimetre)."""
    best = None
    for k in range(len(road.dist)):
        p = road.lane_point(road.dist[k], direction, lane_index)
        d = math.hypot(p[0] - pad["x"], p[2] - pad["z"])
        if best is None or d < best[0]:
            best = (d, road.dist[k])
    s = best[1]
    step = 1.0
    while step > 0.005:
        for cand in (s - step, s + step):
            p = road.lane_point(cand, direction, lane_index)
            d = math.hypot(p[0] - pad["x"], p[2] - pad["z"])
            if d < best[0]:
                best, s = (d, cand), cand
                break
        else:
            step /= 2.0
    return s


def _road_height(city, point):
    """The height of the lane of a road under a point (the rules' lane_at), or nan."""
    best = None
    for r in city["roads"]:
        if r["kind"] in ("tunnel",):
            continue
        found = city_rules_routes.lane_at(r, (point[0], point[2]), point[1])
        if found is not None and (best is None or (abs(found[2][1] - point[1]), found[0]) < best[0]):
            best = ((abs(found[2][1] - point[1]), found[0]), found)
    return best[1][2][1] if best else float("nan")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
