"""The geometry of the movement through a junction.

A movement is a cubic Bezier from the end of the approach lane to the start of
the exit lane. The control points are pulled towards the junction centre so
the movement stays on the asphalt, and the height of every sample is the
height of the junction's fill there, so a car never drives on air.
"""
import math

from mathutils import Vector

from city.roads import junction_fill, levels

SAMPLE = 2.0
MAX_CONNECTOR = 120.0    # a movement longer than this is a data error, not a link
BLEND_SAMPLES = 4.0     # how many samples the lane's height blends into the fill
STRAIGHT_IN_LINE = 0.95  # cos 18 deg: the two lanes of a straight movement run on in line


def v3(p):
    """A Godot (x, y, z) point as a Blender (x, y, z) vector (Blender y = -Godot z)."""
    return Vector((float(p[0]), -float(p[2]), float(p[1])))


def resample(pts, step=SAMPLE):
    """Resample a polyline every `step` metres, keeping both ends."""
    if len(pts) < 2:
        return pts
    out = [pts[0]]
    carry = 0.0
    for a, b in zip(pts, pts[1:]):
        seg = math.dist(a, b)
        d = step - carry
        while d <= seg:
            t = d / seg if seg > 1e-6 else 0.0
            point = [a[i] + (b[i] - a[i]) * t for i in range(3)]
            if math.dist(out[-1], point) > 0.6:
                out.append(point)
            d += step
        carry = seg - (d - step)
    if math.dist(out[-1], pts[-1]) > 1e-4:
        if len(out) > 1 and math.dist(out[-1], pts[-1]) < 0.6:
            out.pop()
        out.append(pts[-1])
    return out


def bezier(p0, p1, p2, p3, step=SAMPLE):
    """A cubic Bezier sampled every `step` metres."""
    length = (p3 - p0).length
    count = max(2, int(math.ceil(length / step)))
    out = []
    for i in range(count + 1):
        t = i / float(count)
        u = 1.0 - t
        p = (p0 * (u ** 3) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t ** 3))
        out.append([round(p.x, 2), round(p.z, 2), round(-p.y, 2)])
    return out


def connector_points(src, dst, centre=None, fan=None, straight=False):
    """The Bezier from the approach lane's end to the exit lane's start.

    The control points are pulled towards the junction centre so the movement
    stays inside the junction (and on its asphalt) instead of bowing out over
    the kerb, and the height of every sample is the height of the junction's
    fill there, so a car never drives on air.

    A straight movement (`straight`, the two lanes in line) whose plain curve
    leaves the fill keeps the plain curve: pulled to the centre and clamped to
    the fill it swerved across the other lanes, 734 of 3306 more than 4 m and
    up to 27 m (the outer lanes of Century Ave at its side streets: the fill of
    a junction does not reach the far lanes of a wide road that passes it).
    """
    p0 = v3(src["points"][-1])
    p3 = v3(dst["points"][0])
    if (p3 - p0).length > MAX_CONNECTOR:
        return []   # the two lanes do not meet: a data error, not a movement (a merge has no fill, the cap holds there too)
    wide = None
    if fan is not None:
        # the drivable area is the junction's collision, a little wider than its
        # asphalt: the movement's height follows that surface, but it stays on
        # the asphalt itself
        wide = (fan[0], levels.offset_ring(fan[1], junction_fill.COLLIDER_MARGIN))
    d0 = v3(src["points"][-1]) - v3(src["points"][-2])
    d1 = v3(dst["points"][1]) - v3(dst["points"][0])
    if d0.length < 1e-6 or d1.length < 1e-6:
        return []
    d0.normalize()
    d1.normalize()
    span = max(4.0, (p3 - p0).length * 0.4)
    best = None
    for pull in (0.0, 0.3, 0.55, 0.8, 1.0):
        p1 = p0 + d0 * span
        p2 = p3 - d1 * span
        if pull > 0.0 and centre is not None:
            p1 = p1.lerp(centre, pull)
            p2 = p2.lerp(centre, pull)
        pts = bezier(p0, p1, p2, p3)
        if fan is None:
            return resample(pts)
        if straight and pull == 0.0 and d0.dot(d1) > STRAIGHT_IN_LINE                 and not all(inside_fan(p, fan) for p in pts):
            return resample(pts)
        pts = clamp_to_fill(pts, fan)
        pts = fit_to_fill(pts, wide, src, dst)
        pts = resample(pts)
        if best is None:
            best = pts
        if all(inside_fan(p, fan) for p in pts):
            return pts
    return best if best else []


def inside_fan(point, fan):
    """True when a Godot point lies on the junction's drivable area.

    The collision is a little wider than the asphalt, so a movement that just
    clips the kerb return still has road under it.
    """
    _hub, ring = fan
    p = Vector((float(point[0]), -float(point[2]), 0.0))
    return levels.point_in_ring(levels.offset_ring(ring, junction_fill.COLLIDER_MARGIN), p)


def clamp_to_fill(pts, fan):
    """Pull the samples that leave the junction's asphalt back onto it."""
    hub, _ring = fan
    out = []
    for n, p in enumerate(pts):
        if n == 0 or n == len(pts) - 1:
            out.append(p)   # the ends have to meet the lanes they join
            continue
        q = Vector((float(p[0]), -float(p[2]), 0.0))
        if levels.point_in_ring(fan[1], q):
            out.append(p)
            continue
        near = nearest_on_ring(fan[1], q)
        if near is None:
            out.append(p)
            continue
        d = hub - near
        if d.length < 1e-6:
            out.append(p)
            continue
        moved = near + d.normalized() * 0.5
        out.append([round(moved.x, 2), p[1], round(-moved.y, 2)])
    return out


def nearest_on_ring(ring, p):
    """The point of the ring closest to `p`."""
    best = None
    for i in range(len(ring)):
        a = ring[i]
        b = ring[(i + 1) % len(ring)]
        ab = b - a
        l2 = ab.length_squared
        t = 0.0 if l2 < 1e-9 else max(0.0, min(1.0, (p - a).dot(ab) / l2))
        q = a + ab * t
        d = (q - p).length_squared
        if best is None or d < best[0]:
            best = (d, q)
    return best[1] if best else None


def fit_to_fill(pts, fan, src, dst):
    """Give every sample the height of the junction's fill, keeping the ends exact."""
    _hub, ring = fan
    out = []
    heights = []
    for p in pts:
        q = Vector((float(p[0]), -float(p[2]), 0.0))
        heights.append(levels.fan_z_at(fan, q))
    y0 = float(src["points"][-1][1])
    y1 = float(dst["points"][0][1])
    e0 = y0 - heights[0]
    e1 = y1 - heights[-1]
    last = max(1, len(pts) - 1)
    for i, p in enumerate(pts):
        # the correction to the lane's height only reaches the first and the
        # last samples: in between the movement follows the fill exactly
        w0 = max(0.0, 1.0 - i / float(BLEND_SAMPLES))
        w1 = max(0.0, 1.0 - (last - i) / float(BLEND_SAMPLES))
        y = heights[i] + e0 * w0 + e1 * w1
        out.append([p[0], round(y, 2), p[2]])
    return out
