"""The geometry of the movement through a junction.

A movement is a cubic Bezier from the end of the approach lane to the start of
the exit lane.  The shape of that curve is searched in connector_curve (the
length of its control arms decides how wide the turn is), and the height of
every sample is the height of the junction's fill there, so a car never drives
on air.

A movement that already drives well keeps the curve it had: the search only
replaces the curves that looped, backed up or turned a corner.
"""
import math

from mathutils import Vector

from city.roads import connector_curve, junction_fill, levels

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
    """The curve of the movement: from the approach lane's end to the exit lane's start.

    The curve the old code built (the control points pulled towards the centre
    of the junction, every sample that leaves the fill moved onto its outline)
    drives badly: 1093 of the 7261 connectors looped, backed up or turned a
    corner.  Where that curve is smooth it is kept, so the rest of the city
    does not move; where it is not, the shape is searched in connector_curve.

    A movement that no curve of the family can keep on the asphalt of the
    junction keeps the old curve: it is covered by the asphalt, it only drives
    badly.
    """
    p0 = v3(src["points"][-1])
    p3 = v3(dst["points"][0])
    if (p3 - p0).length > MAX_CONNECTOR:
        return []   # the two lanes do not meet: a data error, not a movement (a merge has no fill, the cap holds there too)
    d0 = v3(src["points"][-1]) - v3(src["points"][-2])
    d1 = v3(dst["points"][1]) - v3(dst["points"][0])
    if d0.length < 1e-6 or d1.length < 1e-6:
        return []
    d0.normalize()
    d1.normalize()
    old = _pulled(src, dst, centre, fan, straight, d0, d1)
    if old and connector_curve.smooth(_plan(old)):
        return old
    plan, tier = connector_curve.choose(p0, p3, d0, d1, fan, straight, centre, _plan(old))
    if len(plan) < 2 or (fan is not None and tier == 2):
        return old
    if fan is None or (straight and d0.dot(d1) > STRAIGHT_IN_LINE):
        # a merge has no fill under it, and a straight movement runs on the road
        # of a wide junction: the height of the movement is the height of the
        # road it leaves and of the road it joins
        heights = _road_heights(old, plan)
    else:
        wide = (fan[0], levels.offset_ring(fan[1], junction_fill.COLLIDER_MARGIN))
        pts = [[round(p.x, 2), round(p.z, 2), round(-p.y, 2)] for p in plan]
        return resample(fit_to_road(pts, wide, src, dst))
    return resample([[round(p.x, 2), round(h, 2), round(-p.y, 2)]
                     for p, h in zip(plan, heights)])


def _plan(pts):
    """The Godot points of a lane as the plan of the junction (Blender x, y)."""
    return [Vector((float(p[0]), -float(p[2]), 0.0)) for p in pts]


def _pulled(src, dst, centre, fan, straight, d0, d1):
    """The curve of the old code: the control points pulled towards the centre of the junction.

    Every sample that leaves the fill is moved onto the outline of the fill, so
    the curve becomes a zigzag along the kerb.  It is kept where it drives
    well, and where the shape is searched for a better one.
    """
    p0 = v3(src["points"][-1])
    p3 = v3(dst["points"][0])
    wide = None
    if fan is not None:
        wide = (fan[0], levels.offset_ring(fan[1], junction_fill.COLLIDER_MARGIN))
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
        if straight and pull == 0.0 and d0.dot(d1) > STRAIGHT_IN_LINE and not all(inside_fan(p, fan) for p in pts):
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
        near = connector_curve.nearest_on_ring(fan[1], q)
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


def fit_to_road(pts, fan, src, dst):
    """Give every sample the height of the junction's fill, keeping the ends exact.

    The samples that run on the road towards the junction follow the lane they
    leave: the height of the fill there is the height of its nearest edge,
    which is the height of the road a little further on, and a car that drives
    on that height floats above the asphalt.
    """
    _hub, ring = fan
    heights = []
    inside = []
    for p in pts:
        q = Vector((float(p[0]), -float(p[2]), 0.0))
        heights.append(levels.fan_z_at(fan, q))
        inside.append(levels.point_in_ring(ring, q))
    y0 = float(src["points"][-1][1])
    y1 = float(dst["points"][0][1])
    e0 = y0 - heights[0]
    e1 = y1 - heights[-1]
    last = max(1, len(pts) - 1)
    first = None
    end = None
    for i, f in enumerate(inside):
        if f:
            if first is None:
                first = i
            end = i
    out = []
    for i, p in enumerate(pts):
        if first is None or i < first:
            y = y0 + _road_rise(pts, i, src, True)
        elif i > end:
            y = y1 + _road_rise(pts, i, dst, False)
        else:
            # the correction to the lane's height only reaches the first and the
            # last samples: in between the movement follows the fill exactly
            w0 = max(0.0, 1.0 - i / float(BLEND_SAMPLES))
            w1 = max(0.0, 1.0 - (last - i) / float(BLEND_SAMPLES))
            y = heights[i] + e0 * w0 + e1 * w1
        out.append([p[0], round(y, 2), p[2]])
    return out


def _road_rise(pts, i, lane, at_end):
    """How much the road of a lane rises from the end of the lane to a sample.

    `at_end` is true for the lane the movement leaves, false for the one it
    joins: the samples that run on the road are between the end of the lane
    and the junction, so they lie against the direction of travel.
    """
    if at_end:
        origin = lane["points"][-1]
        other = lane["points"][-2]
    else:
        origin = lane["points"][0]
        other = lane["points"][1]
    ox, oy = float(origin[0]), -float(origin[2])
    nx, ny = float(other[0]), -float(other[2])
    span = math.hypot(nx - ox, ny - oy)
    if span < 1e-6:
        return 0.0
    slope = (float(origin[1]) - float(other[1])) / span
    px, py = float(pts[i][0]), -float(pts[i][2])
    along = ((px - ox) * (nx - ox) + (py - oy) * (ny - oy)) / span
    return slope * along


def _fractions(pts):
    """The length along a polyline, as a fraction of its length."""
    out = [0.0]
    for a, b in zip(pts, pts[1:]):
        out.append(out[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    total = out[-1] if len(out) > 1 else 0.0
    if total < 1e-6:
        return [0.0] * len(out)
    return [x / total for x in out]


def _road_heights(old, plan):
    """The height of the old curve, matched to the new plan by the length along it.

    A merge has no fill under it: the height of the movement is the height of
    the road it leaves and of the road it joins, and the old curve is the one
    that follows them.
    """
    old_f = _fractions([(float(p[0]), -float(p[2])) for p in old])
    new_f = _fractions([(p.x, p.y) for p in plan])
    out = []
    j = 0
    for f in new_f:
        while j + 1 < len(old_f) and old_f[j + 1] < f:
            j += 1
        if j + 1 >= len(old_f):
            out.append(float(old[-1][1]))
            continue
        span = old_f[j + 1] - old_f[j]
        t = (f - old_f[j]) / span if span > 1e-6 else 0.0
        out.append(float(old[j][1]) + (float(old[j + 1][1]) - float(old[j][1])) * t)
    return out
