"""city_water — the Huangpu and Suzhou Creek of the map (dossier 10.4).

The river polygon is closed outside the map window, so the water never
shows an open edge; the creek is a 70 m wide band.
"""
import math
import os

import citylib

_LAYOUT = citylib.load_json(os.path.join(
    os.path.dirname(__file__), "..", "..", "ref", "shanghai", "build",
    "map_layout_v1.json"))
_LAYOUT_RIVER = _LAYOUT["river"]


def _water_polygon():
    """The Huangpu polygon, closed north of the map window."""
    west = [tuple(p) for p in _LAYOUT_RIVER["huangpu_west_bank_puxi"]]
    east = [tuple(p) for p in _LAYOUT_RIVER["huangpu_east_bank_pudong"]]
    poly = list(west)
    poly.append([east[-1][0], -1400.0])
    poly.extend(reversed(east[:-1]))
    return poly


def _creek_polygon(half=35.0):
    """Suzhou Creek as a polygon (70 m wide)."""
    line = [tuple(p) for p in _LAYOUT_RIVER["suzhou_creek_centerline"]]
    left, right = [], []
    for i, p in enumerate(line):
        a = line[max(0, i - 1)]
        b = line[min(len(line) - 1, i + 1)]
        dx, dz = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dz) or 1.0
        nx, nz = dz / length, -dx / length
        left.append((p[0] + nx * half, p[1] + nz * half))
        right.append((p[0] - nx * half, p[1] - nz * half))
    return left + list(reversed(right))


HUANGPU = _water_polygon()
CREEK = _creek_polygon()


def is_water(p):
    """True if the 2D point is inside the Huangpu or Suzhou Creek."""
    return (citylib.point_in_polygon(p, HUANGPU)
            or citylib.point_in_polygon(p, CREEK))


def on_land(p0, p1, step=15.0):
    """True if the straight line between two points stays on land."""
    length = math.dist(p0, p1)
    n = max(1, int(length / step))
    for i in range(n + 1):
        t = i / n
        if is_water((p0[0] + (p1[0] - p0[0]) * t,
                     p0[1] + (p1[1] - p0[1]) * t)):
            return False
    return True


def _split_by_water(p0, p1, step=12.0):
    """The stretches of a line that are on land."""
    length = math.dist(p0, p1)
    n = max(2, int(length / step))
    runs, cur = [], []
    for i in range(n + 1):
        t = i / n
        p = (p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t)
        if is_water(p):
            if len(cur) > 1:
                runs.append(cur)
            cur = []
        else:
            cur.append(p)
    if len(cur) > 1:
        runs.append(cur)
    return runs


def _clip_rect(p0, p1, rect):
    """The part of the segment p0-p1 inside the rectangle (Liang-Barsky)."""
    x0, x1, z0, z1 = rect
    dx, dz = p1[0] - p0[0], p1[1] - p0[1]
    t0, t1 = 0.0, 1.0
    for p, q in ((-dx, p0[0] - x0), (dx, x1 - p0[0]), (-dz, p0[1] - z0), (dz, z1 - p0[1])):
        if abs(p) < 1e-9:
            if q < 0:
                return None
            continue
        r = q / p
        if p < 0:
            if r > t1:
                return None
            t0 = max(t0, r)
        else:
            if r < t0:
                return None
            t1 = min(t1, r)
    return ((p0[0] + t0 * dx, p0[1] + t0 * dz), (p0[0] + t1 * dx, p0[1] + t1 * dz))
