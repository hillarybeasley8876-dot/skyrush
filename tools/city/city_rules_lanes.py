"""city_rules_lanes — the lane centres of a road.

The lane centres are offset from the centre-line by the median and the lane
width; the helpers find the lane a mark stands on.
"""
import math

import citylib

from city_rules_graph import _cumulative

def _right_normal(tan):
    dx, dz = tan[0], tan[2]
    length = math.hypot(dx, dz) or 1.0
    return (-dz / length, dx / length)


def lane_centres(road):
    """The lane centre polylines of a road: [(points, direction)]."""
    out = []
    pts = road["points"]
    one_way = road["lanes_back"] == 0
    for direction, count in ((1, road["lanes_fwd"]), (-1, road["lanes_back"])):
        for index in range(count):
            if one_way:
                # a one-way road is centred on its own centre-line
                offset = (index + 0.5 - count / 2.0) * road["lane_width"]
            else:
                offset = (road["median"] * 0.5
                          + (index + 0.5) * road["lane_width"])
            line = []
            for i, p in enumerate(pts):
                a = pts[max(0, i - 1)]
                b = pts[min(len(pts) - 1, i + 1)]
                nx, nz = _right_normal((b[0] - a[0], 0.0, b[2] - a[2]))
                sign = 1.0 if direction > 0 else -1.0
                line.append((p[0] + nx * offset * sign, p[1],
                             p[2] + nz * offset * sign))
            out.append((line, direction))
    return out


def nearest_lane(road, point):
    """The lane centre closest to the plan position.

    The distance is measured to the lane *line*, not to its 2 m control
    points, so a mark between two control points is not an error.
    Returns (distance, lane index, point, heading, direction) or None.
    """
    best = None
    for index, (line, direction) in enumerate(lane_centres(road)):
        for i in range(len(line) - 1):
            a, b = line[i], line[i + 1]
            d = citylib.point_seg_distance(point, (a[0], a[2]), (b[0], b[2]))
            if best is None or d < best[0]:
                heading = math.degrees(math.atan2(b[0] - a[0],
                                                   -(b[2] - a[2]))) % 360.0
                if direction < 0:
                    heading = (heading + 180.0) % 360.0
                t = 0.0 if d < 1e-9 else min(1.0, max(0.0, _seg_t(
                    point, a, b)))
                p = (a[0] + (b[0] - a[0]) * t, a[1],
                     a[2] + (b[2] - a[2]) * t)
                best = (d, index, p, heading, direction)
    return best


def lane_at(road, point, y, heading=None):
    """The lane of the road that carries the mark.

    Where a road crosses itself in plan (the Nanpu spiral) the lane under
    the mark is the one at the mark's height, not the one that happens to
    be closest in plan.
    """
    cands = []
    cum = _cumulative(road["points"])
    for index, (line, direction) in enumerate(lane_centres(road)):
        for i in range(len(line) - 1):
            a, b = line[i], line[i + 1]
            d = citylib.point_seg_distance(point, (a[0], a[2]), (b[0], b[2]))
            if d > 3.0:
                continue
            t = 0.0 if d < 1e-9 else min(1.0, max(0.0, _seg_t(
                point, a, b)))
            p = (a[0] + (b[0] - a[0]) * t, a[1],
                 a[2] + (b[2] - a[2]) * t)
            heading = math.degrees(math.atan2(b[0] - a[0],
                                               -(b[2] - a[2]))) % 360.0
            if direction < 0:
                heading = (heading + 180.0) % 360.0
            s = cum[i] + (cum[i + 1] - cum[i]) * t
            cands.append((d, index, p, heading, direction, s))
    if not cands:
        return None
    # the lane at the height of the mark, if there is one
    level = [c for c in cands if abs(c[2][1] - y) <= 0.5]
    if level:
        if heading is not None:
            same = [c for c in level if _angle_diff(c[3], heading) <= 30.0]
            if same:
                return min(same, key=lambda c: c[0])
        return min(level, key=lambda c: c[0])
    return min(cands, key=lambda c: (abs(c[2][1] - y), c[0]))


def _seg_t(point, a, b):
    """Where the projection of the point falls on the segment a-b (0-1)."""
    ab = (b[0] - a[0], b[2] - a[2])
    den = ab[0] ** 2 + ab[1] ** 2
    if den < 1e-9:
        return 0.0
    return ((point[0] - a[0]) * ab[0] + (point[1] - a[2]) * ab[1]) / den


def _angle_diff(a, b):
    return abs((a - b + 180.0) % 360.0 - 180.0)


def _block_height(blocks, x, z, exempt=()):
    """The height of the tallest lot at the plan position.

    The landmark plazas are left out: a sky lane is meant to thread the
    towers of the dossier between their deck and their crossbeam.
    """
    best = 0.0
    for block in blocks:
        if block.get("notes") in exempt:
            continue
        if not citylib.point_in_polygon((x, z), block["polygon"]):
            continue
        best = max(best, block["height_m"][1])
    return best


