"""city_snap — the street ends are snapped onto the roads they meet.

The surface network has no dead ends: every street either ends on another
road (a junction) or at the window edge (the map lists those in `dead_ends`).

Two rules decide where a street end stops:
  * a street that *crosses* a road ends on that road's centre-line, so the
    junction sits where the two roads really meet;
  * a street that *runs along* a road (less than 35 deg between them) is cut
    at the road's edge and ends there, so the two footprints never overlap.

The searches run on a coarse index (the roads every 20 m) and the exact
geometry is used for the answer.
"""
import math

import citylib

REACH = 400.0            # how far a street end looks for a road
STEP = 20.0              # the step of the walk along the street's line
CROSS_ANGLE = 35.0       # below this the street runs along the road
KEEP_OUT = 1.0           # the gap between a street end and the road's edge
T_JUNCTION = 14.0        # how close a street end must be to a road's
                         # centre-line to count as a T junction
COARSE = 10              # one point every 20 m in the search index


def direction(plan, end):
    """The unit direction of a plan polyline at one of its ends."""
    if end == 0:
        a, b = plan[0], plan[1]
    else:
        a, b = plan[-2], plan[-1]
    dx, dz = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dz) or 1.0
    return (dx / length, dz / length)


def angle_between(a, b):
    """The angle between two directions, in degrees (0-90)."""
    dot = abs(a[0] * b[0] + a[1] * b[1])
    return math.degrees(math.acos(max(-1.0, min(1.0, dot))))


def poly_direction(poly, index):
    """The unit direction of a polyline at one of its points."""
    a = poly[max(0, index - 1)]
    b = poly[min(len(poly) - 1, index + 1)]
    dx, dz = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dz) or 1.0
    return (dx / length, dz / length)


def nearest_on(poly, point):
    """The distance from a point to a polyline and the index of its point."""
    best, best_i = 1e18, 0
    for i, p in enumerate(poly):
        d = math.dist(point, p)
        if d < best:
            best, best_i = d, i
    for j in (best_i - 1, best_i):
        if 0 <= j < len(poly) - 1:
            best = min(best, citylib.point_seg_distance(
                point, poly[j], poly[j + 1]))
    return best, best_i


def seg_hit(origin, direction, poly, limit=1e18):
    """The first point where the ray meets a polyline (None if it misses)."""
    best = None
    for a, b in zip(poly, poly[1:]):
        ex, ez = b[0] - a[0], b[1] - a[1]
        den = direction[0] * ez - direction[1] * ex
        if abs(den) < 1e-6:
            continue
        t = ((a[0] - origin[0]) * ez - (a[1] - origin[1]) * ex) / den
        u = ((a[0] - origin[0]) * direction[1]
             - (a[1] - origin[1]) * direction[0]) / den
        if t < -1.0 or u < 0.0 or u > 1.0 or t > limit:
            continue
        t = max(0.0, t)
        if best is None or t < best[0]:
            best = (t, (origin[0] + direction[0] * t,
                        origin[1] + direction[1] * t))
    return best[1] if best else None


def inside_window(point, window):
    """True if the plan position is inside the map window."""
    return (window["x_min"] <= point[0] <= window["x_max"]
            and window["z_min"] <= point[1] <= window["z_max"])


def coarse_index(polys, widths):
    """A search index with one point every 20 m of every road."""
    index = citylib.PolyIndex()
    for name, poly in polys.items():
        index.add(name, poly[::COARSE] + poly[-1:])
    return index


def snap_end(plan, end, index, polys, widths, own_id, window):
    """Where a street end must stop, and the road it meets (or None).

    The end walks along its own line until it reaches a road: on the
    centre-line of a road it crosses, at the edge of a road it runs along.
    """
    point = (plan[end][0], plan[end][1])
    head = direction(plan, end)
    half = widths.get(own_id, 12.0) * 0.5
    for i in range(int(REACH / STEP) + 1):
        s = i * STEP
        sample = (point[0] + head[0] * s, point[1] + head[1] * s)
        if not inside_window(sample, window):
            return sample, None
        best = None
        for name, _idx, _q in index.within(sample, 60.0):
            if name == own_id:
                continue
            poly = polys[name]
            other = widths.get(name, 0.0) * 0.5
            dist, pidx = nearest_on(poly, sample)
            if dist > other + half + KEEP_OUT:
                continue
            if best is None or dist < best[0]:
                best = (dist, name, poly, pidx)
        if best is None:
            continue
        dist, name, poly, pidx = best
        other = widths.get(name, 0.0) * 0.5
        if s == 0.0 and dist <= other + T_JUNCTION:
            return point, name          # the end is already on the road
        if angle_between(head, poly_direction(poly, pidx)) >= CROSS_ANGLE:
            hit = seg_hit(point, head, poly, REACH)
            return (hit if hit else sample), name
        # the street runs along the road: it stops at the road's edge
        back = max(0.0, s - STEP)
        return (point[0] + head[0] * back, point[1] + head[1] * back), name
    return None, None


def seg_hits(a, b, poly):
    """The points where the segment a-b crosses a polyline."""
    dx, dz = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dz)
    if length < 1e-9:
        return []
    out = []
    for c, d in zip(poly, poly[1:]):
        if (max(a[0], b[0]) < min(c[0], d[0]) or max(c[0], d[0]) < min(a[0], b[0])
                or max(a[1], b[1]) < min(c[1], d[1])
                or max(c[1], d[1]) < min(a[1], b[1])):
            continue
        hit = _seg_hit(a, (dx / length, dz / length), [c, d], length)
        if hit is not None:
            out.append((hit[0], hit))
    out.sort()
    return out


def _seg_hit(origin, direction, poly, limit=1e18):
    """The first point where the ray meets a polyline (None if it misses)."""
    best = None
    for a, b in zip(poly, poly[1:]):
        ex, ez = b[0] - a[0], b[1] - a[1]
        den = direction[0] * ez - direction[1] * ex
        if abs(den) < 1e-6:
            continue
        t = ((a[0] - origin[0]) * ez - (a[1] - origin[1]) * ex) / den
        u = ((a[0] - origin[0]) * direction[1]
             - (a[1] - origin[1]) * direction[0]) / den
        if t < -1.0 or u < 0.0 or u > 1.0 or t > limit:
            continue
        t = max(0.0, t)
        if best is None or t < best[0]:
            best = (t, (origin[0] + direction[0] * t,
                        origin[1] + direction[1] * t))
    return best[1] if best else None


def closest_point(poly, point):
    """The point of a polyline closest to a point, and the distance."""
    best, best_i = 1e18, 0
    for i, p in enumerate(poly):
        d = math.dist(point, p)
        if d < best:
            best, best_i = d, i
    best_point = poly[best_i]
    for j in (best_i - 1, best_i):
        if 0 <= j < len(poly) - 1:
            a, b = poly[j], poly[j + 1]
            ab = (b[0] - a[0], b[1] - a[1])
            den = ab[0] ** 2 + ab[1] ** 2
            if den < 1e-9:
                continue
            t = max(0.0, min(1.0, ((point[0] - a[0]) * ab[0]
                                    + (point[1] - a[1]) * ab[1]) / den))
            q = (a[0] + ab[0] * t, a[1] + ab[1] * t)
            d = math.dist(point, q)
            if d < best:
                best = d
                best_point = q
    return best, best_point
