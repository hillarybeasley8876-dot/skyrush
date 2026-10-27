#!/usr/bin/env python3
"""selftest_tunnel_portals — check_tunnel_portals.py catches what it is for and lets through what is fine.

    python tools/city/selftest_tunnel_portals.py <good city.json> [<old city.json>]

The good city must pass; every case below is built from it by one change and must give exactly the verdict it names. The old
city (the map before the portals were fixed, e.g. `git show f5e214d:data/city/city.json`) must fail on the streets that stood
on the ramps. Prints one line per case and "SELFTEST_TUNNEL_PORTALS OK" or "... FAIL n".
"""
import copy
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_tunnel_portals as ctp  # noqa: E402
import citylib  # noqa: E402

failed = 0


def verdict(city):
    _lines, fails, notes = ctp.check(city)
    return set((k[0], k[2]) for k in fails), set((k[0], k[2]) for k in notes)


def case(name, ok):
    global failed
    print("%s %s" % ("PASS" if ok else "FAIL", name))
    if not ok:
        failed += 1


def tunnel_of(city):
    return [r for r in city["roads"] if r["id"] == "yanan_tunnel"][0]


def station(city, depth_lo, depth_hi, east):
    """A point of the tunnel whose depth is in the range, in the Puxi (east=False) or Pudong half; with its unit side vector."""
    pts = tunnel_of(city)["points"]
    for i in range(1, len(pts) - 1):
        p = pts[i]
        if depth_lo <= -p[1] <= depth_hi and (p[0] > 300.0) == east:
            a, b = pts[i - 1], pts[i + 1]
            n = math.hypot(b[0] - a[0], b[2] - a[2])
            return p, (-(b[2] - a[2]) / n, (b[0] - a[0]) / n)
    raise SystemExit("no station %.1f-%.1f m deep" % (depth_lo, depth_hi))


def street(rid, centre, side, y, half_len=30.0, kind="surface", lanes=2, sidewalk=3.0, shift=0.0):
    """A straight road across (along `side`) the point, `shift` metres along the tunnel."""
    pts = []
    for k in range(-int(half_len), int(half_len) + 1, 2):
        pts.append([centre[0] + side[0] * k + side[1] * shift, y, centre[2] + side[1] * k - side[0] * shift])
    return {"id": rid, "kind": kind, "points": pts, "lanes_fwd": lanes, "lanes_back": lanes, "lane_width": 3.5,
            "median": 0.0, "shoulder": 0.5, "sidewalk": sidewalk, "style": {"parapet": "none"}}


def main(argv):
    good = citylib.load_json(argv[1])
    f, _n = verdict(good)
    case("the good city passes", not f)

    p, side = station(good, 2.0, 3.0, east=False)
    c = copy.deepcopy(good)
    c["roads"].append(street("st_fake_cross", p, side, 0.0))
    f, _n = verdict(c)
    case("a street across the Puxi trough fails OPEN_CROSSING", ("OPEN_CROSSING", "st_fake_cross") in f)

    c = copy.deepcopy(good)
    c["roads"].append(street("deck_fake_over", p, side, -p[1] * 0 + 8.0, kind="elevated", sidewalk=0.0))
    f, _n = verdict(c)
    case("a deck 8 m up over the trough passes (a bridge over it)", not f)

    c = copy.deepcopy(good)
    c["roads"].append(street("deck_fake_low", p, side, 3.0, kind="elevated", sidewalk=0.0))
    f, _n = verdict(c)
    case("a deck 3 m up over a trough 2-3 m deep fails (5-6 m over the tunnel road)", ("OPEN_CROSSING", "deck_fake_low") in f)

    # a street beside the trough: the carriageway (2 x 2 x 3.5 + 1 = 15 m, half 7.5) clear of the 12 m footprint, its
    # 3 m sidewalk over it: the street runs along the tunnel 21 m off its centre line
    pts = tunnel_of(good)["points"]
    i0 = next(i for i, q in enumerate(pts) if -q[1] > 1.5 and q[0] < 0.0)
    near = []
    for q, r in zip(pts[i0:i0 + 20], pts[i0 + 1:i0 + 21]):
        n = math.hypot(r[0] - q[0], r[2] - q[2])
        sx, sz = -(r[2] - q[2]) / n, (r[0] - q[0]) / n
        near.append([q[0] - sx * 21.0, 0.0, q[2] - sz * 21.0])
    beside = {"id": "st_fake_beside", "kind": "surface", "points": near, "lanes_fwd": 2, "lanes_back": 2, "lane_width": 3.5,
              "median": 0.0, "shoulder": 0.5, "sidewalk": 3.0, "style": {"parapet": "none"}}
    c = copy.deepcopy(good)
    c["roads"].append(beside)
    f, n = verdict(c)
    case("a street beside the trough whose sidewalk reaches over it passes, reported SIDEWALK",
         not f and ("SIDEWALK", "st_fake_beside") in n)

    c = copy.deepcopy(good)
    c["junctions"] = [j for j in c["junctions"] if j["id"] != "j_lujiazui_ring_rd_yanan_tunnel"]
    f, _n = verdict(c)
    case("the ring road crossing without its junction fails GRADE_CROSSING", ("GRADE_CROSSING", "lujiazui_ring_rd") in f)
    case("... and its shallow mouth is no longer a junction mouth (OPEN_CROSSING)", ("OPEN_CROSSING", "lujiazui_ring_rd") in f)

    q, qs = station(good, 2.0, 3.0, east=True)
    c = copy.deepcopy(good)
    c["blocks"].append({"id": "b_fake_lot", "polygon": [[q[0] - 8, q[2] - 8], [q[0] + 8, q[2] - 8], [q[0] + 8, q[2] + 8],
                                                         [q[0] - 8, q[2] + 8]]})
    f, _n = verdict(c)
    case("a lot on the Pudong trough fails LOT_ON_TROUGH", ("LOT_ON_TROUGH", "b_fake_lot") in f)

    c = copy.deepcopy(good)
    tunnel_of(c)["points"][-1][1] = -1.0
    f, _n = verdict(c)
    case("a tunnel that ends 1 m under the ground fails END_NOT_AT_GRADE", ("END_NOT_AT_GRADE", "end") in f)

    c = copy.deepcopy(good)
    for pt in tunnel_of(c)["points"]:
        if pt[0] > 600.0:
            pt[1] = min(pt[1], -2.0)
    f, _n = verdict(c)
    case("the old Pudong ramp (2 m under the ring road) fails OPEN_CROSSING with the ring road",
         ("OPEN_CROSSING", "lujiazui_ring_rd") in f)

    if len(argv) > 2:
        old = citylib.load_json(argv[2])
        f, _n = verdict(old)
        want = {"lujiazui_ring_rd", "st_fujian_portal", "st_henan_portal", "st_henan_rd", "yanan_rd_surface"}
        got = set(o for k, o in f if k == "OPEN_CROSSING")
        case("the old map fails OPEN_CROSSING on %s" % ", ".join(sorted(want)), want <= got)

    print("SELFTEST_TUNNEL_PORTALS %s" % ("OK" if failed == 0 else "FAIL %d" % failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
