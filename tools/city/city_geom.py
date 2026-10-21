"""city_geom — curve generators for the SKYRUSH city layout.

Screen convention for angles: the map is north up, +X east, +Z south, so a
position at polar angle `a` is (cx + R*cos a, cz - R*sin a).  Increasing `a`
therefore turns counter-clockwise on the map.
"""
import math

from citylib import catmull_rom, polyline_length


HERMITE_STEPS = 24     # the samples of a Hermite piece


def adiff(a, b):
    """The signed difference b - a, folded into (-180, 180]."""
    return (b - a + 540.0) % 360.0 - 180.0


def heading_of(dx, dz):
    """The heading in degrees (0 = north, 90 = east)."""
    return math.degrees(math.atan2(dx, -dz)) % 360.0


def dir_of(deg):
    """The unit vector of a heading."""
    r = math.radians(deg)
    return (math.sin(r), -math.cos(r))


def left_normal(deg):
    """The unit vector 90 deg to the left of a heading."""
    return (-math.cos(math.radians(deg)), -math.sin(math.radians(deg)))


def right_normal(deg):
    """The unit vector 90 deg to the right of a heading."""
    return (math.cos(math.radians(deg)), math.sin(math.radians(deg)))


def scale(v, k):
    """A vector scaled by k."""
    return (v[0] * k, v[1] * k)


def blend_path(start, start_dir, end, end_dir, n=24, bulge=0.0, scale=0.5):
    """Hermite path from `start` (heading `start_dir`) to `end` (heading
    `end_dir`).

    `scale` is the length of the tangent handles (0.5 = half the chord).  A
    small scale keeps the curvature at the ends low, which matters for the
    ramps: they must meet their parent without a kink."""
    p0 = (start[0], start[1])
    p3 = (end[0], end[1])
    dist = math.dist(p0, p3) or 1.0
    m1 = (start_dir[0] * dist * scale, start_dir[1] * dist * scale)
    m2 = (end_dir[0] * dist * scale, end_dir[1] * dist * scale)
    out = []
    for i in range(n + 1):
        t = i / n
        t2, t3 = t * t, t * t * t
        h00 = 2 * t3 - 3 * t2 + 1
        h10 = t3 - 2 * t2 + t
        h01 = -2 * t3 + 3 * t2
        h11 = t3 - t2
        x = h00 * p0[0] + h10 * m1[0] + h01 * p3[0] + h11 * m2[0]
        z = h00 * p0[1] + h10 * m1[1] + h01 * p3[1] + h11 * m2[1]
        if bulge:
            nx, nz = -m2[1], m2[0]
            length = math.hypot(nx, nz) or 1.0
            k = bulge * math.sin(math.pi * t)
            x += nx / length * k
            z += nz / length * k
        out.append([x, z])
    return out


def sweep_path(p0, dir0, p1, dir1, mid=None, scale=0.75, n=18):
    """A road sweep from `p0` (heading `dir0`) to `p1` (heading `dir1`).

    The path is two Hermite sweeps that meet at `mid` (the middle of the two
    ends by default) and it leaves and arrives along the given directions, so
    a ramp can leave and meet its parent without a kink.
    """
    p0 = (p0[0], p0[1])
    p1 = (p1[0], p1[1])
    if mid is None:
        mid = ((p0[0] + p1[0]) * 0.5, (p0[1] + p1[1]) * 0.5)
    h0 = math.degrees(math.atan2(dir0[0], -dir0[1]))
    h1 = math.degrees(math.atan2(dir1[0], -dir1[1]))
    diff = (h1 - h0 + 540.0) % 360.0 - 180.0
    h_mid = (h0 + diff * 0.5) % 360.0
    r = math.radians(h_mid)
    d_mid = (math.sin(r), -math.cos(r))
    part1 = blend_path(p0, dir0, mid, d_mid, n, scale=scale)
    part2 = blend_path(mid, d_mid, p1, dir1, n, scale=scale)
    return [list(p) for p in part1] + [list(p) for p in part2[1:]]


def heading_of(dx, dz):
    """The heading in degrees (0 = north, 90 = east)."""
    return math.degrees(math.atan2(dx, -dz)) % 360.0


def right_normal(deg):
    """The unit vector 90 deg to the right of a heading."""
    return (math.cos(math.radians(deg)), math.sin(math.radians(deg)))


def scale(v, k):
    """A vector scaled by k."""
    return (v[0] * k, v[1] * k)


def ramp_path(p0, d0, p1, d1, radius=90.0, n=20):
    """A ramp plan: a straight lead, a circular arc and a straight lead-out.

    The path leaves `p0` along `d0` and arrives at `p1` along `d1`, so a
    ramp can join its parents without a kink.  The arc's radius shrinks
    until the two straights are long enough to hold it.
    """
    h0 = heading_of(d0[0], d0[1])
    h1 = heading_of(d1[0], d1[1])
    turn = (h1 - h0 + 540.0) % 360.0 - 180.0
    if abs(turn) < 1e-3:
        return [[p0[0] + (p1[0] - p0[0]) * i / n,
                 p0[1] + (p1[1] - p0[1]) * i / n] for i in range(n + 1)]
    sign = 1.0 if turn > 0 else -1.0        # +1 for a right turn
    inside0 = (sign * right_normal(h0)[0], sign * right_normal(h0)[1])
    inside1 = (sign * right_normal(h1)[0], sign * right_normal(h1)[1])
    r = radius
    for _ in range(40):
        c0 = (p0[0] + r * inside0[0], p0[1] + r * inside0[1])
        c1 = (p1[0] + r * inside1[0], p1[1] + r * inside1[1])
        det = d0[0] * d1[1] - d0[1] * d1[0]
        if abs(det) < 1e-9:
            break
        rx, ry = c1[0] - c0[0], c1[1] - c0[1]
        t = (rx * d1[1] - ry * d1[0]) / det
        centre = (c0[0] + d0[0] * t, c0[1] + d0[1] * t)
        lead0 = (centre[0] - p0[0]) * d0[0] + (centre[1] - p0[1]) * d0[1]
        lead1 = (centre[0] - p1[0]) * d1[0] + (centre[1] - p1[1]) * d1[1]
        if lead0 >= 8.0 and lead1 >= 8.0:
            break
        r *= 0.9
    a0 = (p0[0] + lead0 * d0[0], p0[1] + lead0 * d0[1])
    a1 = (p1[0] + lead1 * d1[0], p1[1] + lead1 * d1[1])
    arc = []
    for i in range(n + 1):
        h = h0 + turn * i / n
        rn = right_normal(h)
        arc.append([centre[0] - sign * r * rn[0], centre[1] - sign * r * rn[1]])
    out = [[p0[0], p0[1]], [a0[0], a0[1]]]
    out.extend(arc[1:-1])
    out.append([a1[0], a1[1]])
    out.append([p1[0], p1[1]])
    return out


# ---------------------------------------------------------------- curves

def hermite(p0, m0, p1, m1, n=HERMITE_STEPS):
    """Sample a cubic Hermite from p0 (tangent m0) to p1 (tangent m1)."""
    out = []
    for i in range(n + 1):
        t = i / float(n)
        t2, t3 = t * t, t * t * t
        h00 = 2 * t3 - 3 * t2 + 1
        h10 = t3 - 2 * t2 + t
        h01 = -2 * t3 + 3 * t2
        h11 = t3 - t2
        out.append((h00 * p0[0] + h10 * m0[0] + h01 * p1[0] + h11 * m1[0],
                    h00 * p0[1] + h10 * m0[1] + h01 * p1[1] + h11 * m1[1]))
    return out


def leg_mag(p0, h0, p1, h1):
    """The tangent length of the Hermite that best approximates a circular arc."""
    c = math.dist(p0, p1)
    th = min(abs(math.radians(adiff(h0, h1))), 3.0)
    return c / (3.0 * math.cos(th / 4.0))


def tangent_point(p0, d0, p1, d1):
    """The intersection of the two lines p0+t*d0 and p1+u*d1."""
    den = d0[0] * (-d1[1]) - d0[1] * (-d1[0])
    if abs(den) < 1e-9:
        return ((p0[0] + p1[0]) * 0.5, (p0[1] + p1[1]) * 0.5)
    rx, ry = p1[0] - p0[0], p1[1] - p0[1]
    t = (rx * (-d1[1]) - ry * (-d1[0])) / den
    return (p0[0] + d0[0] * t, p0[1] + d0[1] * t)


def arc_points(centre, radius, h0, h1, n=HERMITE_STEPS):
    """Points of the circular arc from heading h0 to h1.

    The centre lies to the right of the travel direction (a right turn), so
    the arc itself is to the left of its centre.
    """
    out = []
    for i in range(n + 1):
        h = h0 + (h1 - h0) * i / float(n)
        ln = left_normal(h)
        out.append((centre[0] + radius * ln[0], centre[1] + radius * ln[1]))
    return out
