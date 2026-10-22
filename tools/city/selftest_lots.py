#!/usr/bin/env python3
"""selftest_lots — the polygon clipper of city_blocks (lead's oracle, read-only for the job)

    python tools/city/selftest_lots.py

city_blocks.clip_polygon_by_corridor(poly, points, need) -> [piece, ...]
  poly    the lot: a list of [x, z] points (counter-clockwise seen from above = NEGATIVE shoelace area in (x, z))
  points  the centre-line of a road: a list of [x, z] points (at least 2)
  need    the half width of the corridor to cut out (road half width plus clearance), metres
  returns the pieces of the lot that are left (the lot may be cut into several pieces that share edges, as it is when
          a street ends inside it), each a list of [x, z] with at least 3 points and the SAME winding
          as the input, none of them closer than `need` to the centre-line, nothing cut that is further away
          than 1.5 * need (the corridor may have square caps and corners, not more).
Every case is judged by sampling: a random point of the lot that is at least `need` + 0.05 m from the centre-line
and not within the cap slack must lie in some piece, and a point closer than `need` - 0.05 m must lie in none.
"""
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import citylib  # noqa: E402
import city_blocks  # noqa: E402


def seg_dist(p, a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dz * dz
    t = 0.0 if l2 < 1e-12 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / l2))
    return math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dz))


def line_dist(p, pts):
    return min(seg_dist(p, a, b) for a, b in zip(pts, pts[1:]))


def shoelace(poly):
    return citylib.polygon_area([tuple(p) for p in poly])


def inside(p, poly):
    return citylib.point_in_polygon((p[0], p[1]), [tuple(q) for q in poly])


def ccw(poly):
    """The repo's counter-clockwise: negative shoelace area."""
    return poly if shoelace(poly) < 0 else poly[::-1]


SQUARE = ccw([[0.0, 0.0], [100.0, 0.0], [100.0, 100.0], [0.0, 100.0]])
LSHAPE = ccw([[0.0, 0.0], [100.0, 0.0], [100.0, 40.0], [40.0, 40.0], [40.0, 100.0], [0.0, 100.0]])


def judge(name, poly, road, need, expect_pieces=None, expect_area=None, samples=3000):
    problems = []
    try:
        pieces = city_blocks.clip_polygon_by_corridor([list(p) for p in poly], [list(p) for p in road], need)
    except Exception as exc:  # noqa: BLE001
        print("FAIL %-34s raised %s: %s" % (name, type(exc).__name__, exc))
        return False
    if expect_pieces is not None and len(pieces) != expect_pieces:
        problems.append("%d pieces, expected %d" % (len(pieces), expect_pieces))
    sign = 1 if shoelace(poly) > 0 else -1
    area = 0.0
    for piece in pieces:
        if len(piece) < 3:
            problems.append("a piece has %d points" % len(piece))
            continue
        a = shoelace(piece)
        if a * sign <= 0:
            problems.append("a piece has the wrong winding (area %.1f, input %.1f)" % (a, shoelace(poly)))
        area += abs(a)
        for p, q in zip(piece, piece[1:] + piece[:1]):
            if math.hypot(p[0] - q[0], p[1] - q[1]) < 1e-6:
                problems.append("a piece has a doubled point at (%.1f, %.1f)" % (p[0], p[1]))
                break
    if expect_area is not None and abs(area - expect_area) > 0.01 * expect_area + 1.0:
        problems.append("area %.0f, expected %.0f" % (area, expect_area))
    xs = [p[0] for p in poly]
    zs = [p[1] for p in poly]
    rng = random.Random(7)
    wrong_kept = wrong_cut = 0
    for _ in range(samples):
        p = (rng.uniform(min(xs), max(xs)), rng.uniform(min(zs), max(zs)))
        if not inside(p, poly):
            continue
        d = line_dist(p, road)
        kept = any(inside(p, piece) for piece in pieces)
        if d >= 1.5 * need + 0.05 and not kept:
            wrong_cut += 1
        if d <= need - 0.05 and kept:
            wrong_kept += 1
    if wrong_kept:
        problems.append("%d sample points closer than %.1f m to the road are still in a piece" % (wrong_kept, need))
    if wrong_cut:
        problems.append("%d sample points further than %.1f m from the road were cut away" % (wrong_cut, 1.5 * need))
    print("%s %-34s %d pieces, area %.0f%s" % ("PASS" if not problems else "FAIL", name, len(pieces), area,
                                                "" if not problems else "  -> " + "; ".join(problems)))
    return not problems


def main():
    ok = True
    ok &= judge("a road across a square", SQUARE, [[50.0, -20.0], [50.0, 120.0]], 10.0, 2, 8000.0)
    ok &= judge("a road far away", SQUARE, [[200.0, -20.0], [200.0, 120.0]], 10.0, 1, 10000.0)
    ok &= judge("a diagonal road", SQUARE, [[-20.0, -20.0], [120.0, 120.0]], 8.0, 2)
    ok &= judge("a dead-end street into the lot", SQUARE, [[-30.0, 50.0], [40.0, 50.0]], 8.0, None, 9232.0)
    ok &= judge("a road across an L-shaped lot", LSHAPE, [[20.0, -20.0], [20.0, 120.0]], 6.0, 2)
    ok &= judge("a road with a 90 degree bend", SQUARE, [[10.0, -20.0], [10.0, 60.0], [120.0, 60.0]], 9.0, None)
    ok &= judge("a road that swallows the lot", [[0.0, 0.0], [20.0, 0.0], [20.0, 20.0], [0.0, 20.0]] if shoelace([[0.0, 0.0], [20.0, 0.0], [20.0, 20.0], [0.0, 20.0]]) < 0 else [[0.0, 0.0], [0.0, 20.0], [20.0, 20.0], [20.0, 0.0]],
                [[-50.0, 10.0], [70.0, 10.0]], 30.0, 0, 0.0)
    clockwise = SQUARE[::-1]
    ok &= judge("a clockwise lot keeps its winding", clockwise, [[50.0, -20.0], [50.0, 120.0]], 10.0, 2, 8000.0)
    print("SELFTEST_LOTS %s" % ("OK" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
