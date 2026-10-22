#!/usr/bin/env python3
"""selftest_corridor — the fast corridor search must equal the slow one.

The reference implementation below is a verbatim copy of the `inside_corridor`
/ `_nearest` / `_point_seg_distance` of city_corridor.py as it was before the
speed-up.  The live code must answer every probe point exactly as the
reference does: the same corridor (the same object) and the same point on the
centre-line, to the last bit.

    python tools/city/selftest_corridor.py
"""
import math
import os
import random
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import city_corridor        # noqa: E402


# ---------------------------------------------------------------- reference --
# verbatim copy of the old city_corridor code, the yardstick of the test.

def ref_point_seg_distance(p, a, b):
    """The distance from a point to a segment."""
    dx, dz = b[0] - a[0], b[1] - a[1]
    den = dx * dx + dz * dz
    t = 0.0 if den < 1e-9 else max(0.0, min(1.0, ((p[0] - a[0]) * dx
                                                    + (p[1] - a[1]) * dz) / den))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dz)


def ref_nearest(points, point):
    """The distance from a point to a polyline and the point on it."""
    best, best_p = 1e18, points[0]
    for a, b in zip(points, points[1:]):
        d = ref_point_seg_distance(point, a, b)
        if d < best:
            best = d
            t = 0.0
            dx, dz = b[0] - a[0], b[1] - a[1]
            den = dx * dx + dz * dz
            if den > 1e-9:
                t = max(0.0, min(1.0, ((point[0] - a[0]) * dx
                                        + (point[1] - a[1]) * dz) / den))
            best_p = (a[0] + t * dx, a[1] + t * dz)
    return best, best_p


def ref_inside_corridor(point, corridors):
    """The corridor the point lies in, if any."""
    for entry in corridors:
        d, near = ref_nearest(entry["points"], point)
        if d < entry["half"]:
            return entry, near
    return None, None


# ------------------------------------------------------------------ scenery --

def _wander(rng, start, n, step, turn):
    """A polyline that wanders like an arterial road."""
    x, z = start
    a = rng.uniform(0.0, 360.0)
    out = [(x, z)]
    for _ in range(n):
        a += rng.uniform(-turn, turn)
        r = math.radians(a)
        x += math.sin(r) * step * rng.uniform(0.6, 1.4)
        z -= math.cos(r) * step * rng.uniform(0.6, 1.4)
        out.append((x, z))
    return out


def _corridors(rng):
    """A handful of realistic corridors: long, crossing and far apart."""
    out = []
    plan = [
        # (start, segments, step, turn, half)
        ((-1800.0, 900.0), 420, 14.0, 4.0, 16.5),
        ((-2000.0, -400.0), 500, 18.0, 3.0, 21.0),
        ((-300.0, 1500.0), 380, 12.0, 6.0, 12.0),
        ((300.0, -1400.0), 260, 9.0, 8.0, 9.5),
        ((1500.0, 1200.0), 300, 22.0, 5.0, 18.0),
        ((-1000.0, 200.0), 200, 6.0, 12.0, 7.0),
        ((100.0, 100.0), 50, 4.0, 20.0, 6.0),
        ((-600.0, 600.0), 120, 5.0, 15.0, 25.0),
    ]
    for i, (start, n, step, turn, half) in enumerate(plan):
        pts = _wander(rng, start, n, step, turn)
        out.append({"id": "c%d" % i, "points": pts, "half": half})
    return out


def _probes(rng, corridors, quick):
    """The probe points: everywhere, on the lines, on the vertices, on the
    edge of a corridor."""
    random_n = 3000 if quick else 50000
    per_corridor = 60 if quick else 400
    out = []
    for _ in range(random_n):
        out.append((rng.uniform(-2200.0, 1800.0),
                    rng.uniform(-1400.0, 1700.0)))
    for entry in corridors:
        pts = entry["points"]
        half = entry["half"]
        for _ in range(per_corridor):          # on the centre-line
            i = rng.randrange(len(pts) - 1)
            a, b = pts[i], pts[i + 1]
            t = rng.random()
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        for p in pts:                          # on the vertices
            out.append(p)
        for _ in range(per_corridor):          # on the border of the corridor
            i = rng.randrange(len(pts) - 1)
            a, b = pts[i], pts[i + 1]
            dx, dz = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dz) or 1.0
            nx, nz = -dz / length, dx / length
            t = rng.random()
            px = a[0] + (b[0] - a[0]) * t
            pz = a[1] + (b[1] - a[1]) * t
            for k in (half, half * (1.0 - 1e-9), half * (1.0 + 1e-9),
                      half * 0.999999, half * 1.000001):
                s = 1.0 if rng.random() < 0.5 else -1.0
                out.append((px + nx * k * s, pz + nz * k * s))
    return out


def _same(a, b):
    """Two results are the same when the corridor and the point are."""
    if a[0] is not b[0]:
        return False
    if a[1] is None or b[1] is None:
        return a[1] is b[1]
    return repr(a[1]) == repr(b[1])


def _check(probes, corridors, what):
    """Every probe must be answered exactly as the reference answers it."""
    hits = 0
    for point in probes:
        ref = ref_inside_corridor(point, corridors)
        live = city_corridor.inside_corridor(point, corridors)
        if ref[0] is not None:
            hits += 1
        if not _same(ref, live):
            print("MISMATCH (%s) at %r" % (what, point))
            print("  reference: %s %r"
                  % (ref[0]["id"] if ref[0] else None, ref[1]))
            print("  live     : %s %r"
                  % (live[0]["id"] if live[0] else None, live[1]))
            return None
    return hits


def _changed_points():
    """A corridor whose points change must not be answered from a stale
    index."""
    rng = random.Random(4242)
    corridors = _corridors(rng)
    entry = corridors[0]
    pts = entry["points"]
    for _ in range(300):
        i = rng.randrange(len(pts))
        pts[i] = (pts[i][0] + 37.0, pts[i][1] - 11.0)
        point = (pts[i][0] + rng.uniform(-40.0, 40.0),
                 pts[i][1] + rng.uniform(-40.0, 40.0))
        ref = ref_inside_corridor(point, corridors)
        live = city_corridor.inside_corridor(point, corridors)
        if not _same(ref, live):
            print("MISMATCH (changed points) at %r" % (point,))
            return 1
    return 0


def _shared_points():
    """Two corridors on one list of points, with another half width."""
    rng = random.Random(99)
    pts = _wander(rng, (0.0, 0.0), 220, 8.0, 6.0)
    corridors = [{"id": "narrow", "points": pts, "half": 10.0},
                 {"id": "wide", "points": pts, "half": 30.0}]
    probes = [(rng.uniform(-250.0, 250.0), rng.uniform(-250.0, 250.0))
              for _ in range(2000)]
    for p in pts[::7]:
        probes.append(p)
    hits = _check(probes, corridors, "shared points")
    if hits is None:
        return 1
    print("OK shared points, %d probes, %d in a corridor"
          % (len(probes), hits))
    return 0


def main():
    quick = "--quick" in sys.argv
    rng = random.Random(20241023)
    corridors = _corridors(rng)
    probes = _probes(rng, corridors, quick)
    hits = 0
    t0 = time.time()
    refs = [ref_inside_corridor(point, corridors) for point in probes]
    t1 = time.time()
    for point, ref in zip(probes, refs):
        live = city_corridor.inside_corridor(point, corridors)
        if ref[0] is not None:
            hits += 1
        if not _same(ref, live):
            print("MISMATCH at %r" % (point,))
            print("  reference: %s %r"
                  % (ref[0]["id"] if ref[0] else None, ref[1]))
            print("  live     : %s %r"
                  % (live[0]["id"] if live[0] else None, live[1]))
            return 1
    t2 = time.time()
    print("OK %d probes, %d in a corridor, reference %.1f s, live %.1f s"
          % (len(probes), hits, t1 - t0, t2 - t1))
    if _changed_points():
        return 1
    print("OK the changed points of a corridor are seen")
    return _shared_points()


if __name__ == "__main__":
    sys.exit(main())
