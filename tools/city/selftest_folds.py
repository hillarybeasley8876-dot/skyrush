#!/usr/bin/env python3
"""selftest_folds — no street folds back on itself.

    python tools/city/selftest_folds.py

The end of a street walks along the street's own line until it reaches a
road.  When that road lies on the street's own line, the end jumps over
the points the street has there: those points have to be dropped, or the
street folds back on itself (two carriageways on top of each other, a
lane that starts and ends at the same junction, a car that reverses on
the spot).

This checks the cut on small synthetic plans and on the real map:

  * the end that jumps into the street drops the points it passed over;
  * an end that reaches further out drops nothing;
  * a curved plan keeps the points the jump did not pass over;
  * no street of the built map has a turning point (`check_road_retrace`).
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import city_grid        # noqa: E402
import city_snap        # noqa: E402
import check_road_retrace as retrace  # noqa: E402

try:
    trim_to_end = city_snap.trim_to_end
except AttributeError:
    trim_to_end = None

LINE = [(0.0, 0.0), (10.0, 0.0), (20.0, 0.0), (30.0, 0.0), (40.0, 0.0)]
CURVE = [(0.0, 0.0), (10.0, 0.0), (20.0, 0.0), (20.0, 10.0),
         (30.0, 20.0), (40.0, 30.0)]


def _same(got, want, tol=1e-6):
    """True if two plans are the same list of points."""
    if len(got) != len(want):
        return False
    for a, b in zip(got, want):
        if abs(a[0] - b[0]) > tol or abs(a[1] - b[1]) > tol:
            return False
    return True


def cases():
    """The synthetic cases: (name, plan, end, snapped, expected)."""
    return [
        ("the start jumps into the street", LINE, 0, (15.0, 0.0),
         [(15.0, 0.0), (20.0, 0.0), (30.0, 0.0), (40.0, 0.0)]),
        ("the end jumps into the street", LINE, 1, (25.0, 0.0),
         [(0.0, 0.0), (10.0, 0.0), (20.0, 0.0), (25.0, 0.0)]),
        ("the start reaches further out", LINE, 0, (-12.0, 0.0),
         [(-12.0, 0.0), (10.0, 0.0), (20.0, 0.0), (30.0, 0.0), (40.0, 0.0)]),
        ("a curved plan keeps the rest", CURVE, 1, (35.0, 25.0),
         [(0.0, 0.0), (10.0, 0.0), (20.0, 0.0), (20.0, 10.0),
          (30.0, 20.0), (35.0, 25.0)]),
    ]


def check_cases():
    """The synthetic cases of the cut: how many of them are wrong."""
    bad = 0
    for name, plan, end, snapped, want in cases():
        if trim_to_end is None:
            print("FAIL %s: city_snap.trim_to_end is missing" % name)
            bad += 1
            continue
        got = [tuple(p) for p in trim_to_end([list(p) for p in plan], end, snapped)]
        if _same(got, want):
            print("PASS %s" % name)
            continue
        bad += 1
        print("FAIL %s: %s" % (name, got))
        print("     the plan should be %s" % (want,))
    return bad


def check_map():
    """No street of the built map folds back on itself."""
    import build_city
    roads = build_city.build_main_roads()
    streets, _dead = city_grid.build_streets(roads)
    for st in streets:
        st.build()
    folded = []
    for st in streets:
        plan = [(p[0], 0.0, p[1]) for p in st.plan]
        built = [(p[0], p[1], p[2]) for p in st.points]
        if retrace.turning_points(plan) or retrace.turning_points(built):
            folded.append(st.id)
    ok = not folded
    print("%s no street of the map folds back on itself (%d street(s))"
          % ("PASS" if ok else "FAIL", len(folded)))
    for rid in folded[:8]:
        print("       %s" % rid)
    return 0 if ok else 1


def main():
    bad = check_cases() + check_map()
    print("selftest_folds: %d case(s) wrong" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
