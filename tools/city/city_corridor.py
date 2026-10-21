"""city_corridor — the corridors of the arterial roads.

The lattice streets of the districts may not run inside the footprint of
an arterial: a street that follows an arterial shares its pavement with
it, and the two road markings and kerbs are drawn on top of each other.

Every lattice street is therefore cut at the edge of the arterial corridor
and meets the arterial on its own centre-line, where the junction is.  The
cut end is bent (a dog-leg) so that the street meets the arterial at a
right angle: a street that crosses an arterial at 20 degrees would share
a hundred metres of pavement with it.
"""
import math

from city_geom import hermite

CORRIDOR_MARGIN = 6.0     # the gap between an arterial and a lattice street
CROSS_ANGLE = 60.0        # the angle a street meets an arterial at
DOGLEG = 70.0             # the length of the bend
SAMPLE = 4.0              # the step of the walk along a street


def corridor_half(road):
    """The half width of the corridor of a road."""
    width = (road.get("lanes_fwd", 0) + road.get("lanes_back", 0)) \
        * road.get("lane_width", 3.5) / 2.0
    return width + road.get("median", 0.0) / 2.0 + CORRIDOR_MARGIN


def _point_seg_distance(p, a, b):
    """The distance from a point to a segment."""
    dx, dz = b[0] - a[0], b[1] - a[1]
    den = dx * dx + dz * dz
    t = 0.0 if den < 1e-9 else max(0.0, min(1.0, ((p[0] - a[0]) * dx
                                                    + (p[1] - a[1]) * dz) / den))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dz)


def _nearest(points, point):
    """The distance from a point to a polyline and the point on it."""
    best, best_p = 1e18, points[0]
    for a, b in zip(points, points[1:]):
        d = _point_seg_distance(point, a, b)
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


def _heading(points, at):
    """The heading of a polyline at one of its points."""
    for a, b in zip(points, points[1:]):
        if _point_seg_distance(at, a, b) < 0.5:
            return math.degrees(math.atan2(b[0] - a[0], -(b[1] - a[1]))) % 360.0
    a, b = points[0], points[1]
    return math.degrees(math.atan2(b[0] - a[0], -(b[1] - a[1]))) % 360.0


def _angle(a, b):
    """The angle between two headings, in degrees (0-180)."""
    d = abs((a - b + 180.0) % 360.0 - 180.0)
    return min(d, 180.0 - d)


def _rotate(deg, turn):
    """A heading turned by `turn` degrees."""
    return (deg + turn) % 360.0


def _dir(deg):
    """The unit vector of a heading."""
    r = math.radians(deg)
    return (math.sin(r), -math.cos(r))


def inside_corridor(point, corridors):
    """The corridor the point lies in, if any."""
    for entry in corridors:
        d, near = _nearest(entry["points"], point)
        if d < entry["half"]:
            return entry, near
    return None, None


def trim(run, corridors):
    """The pieces of a street that lie outside every arterial corridor."""
    out = []
    current = []
    for point in _samples(run):
        entry, _near = inside_corridor(point, corridors)
        if entry is None:
            current.append(point)
        else:
            if len(current) > 1:
                out.append(current)
            current = []
    if len(current) > 1:
        out.append(current)
    return out


def _samples(run, step=SAMPLE):
    """The points of a street, every `step` metres."""
    out = [list(run[0])]
    acc = 0.0
    for a, b in zip(run, run[1:]):
        length = math.dist(a, b)
        n = max(1, int(length / step))
        for k in range(1, n + 1):
            t = k / n
            out.append([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t])
        acc += length
    return out


def dogleg(piece, corridors, at_end=True):
    """The end of a street bent so that it meets the arterial squarely.

    The street turns away from its own line before the arterial and comes
    back to it at a right angle, so the two roads share no pavement.
    """
    if len(piece) < 2:
        return piece
    if at_end:
        head, prev = piece[-1], piece[-2]
    else:
        head, prev = piece[0], piece[1]
    d = _unit((head[0] - prev[0], head[1] - prev[1]))
    travel = d if at_end else (-d[0], -d[1])
    entry, near = inside_corridor(head, corridors)
    if entry is None:
        return piece
    heading = _heading(entry["points"], near)
    street = math.degrees(math.atan2(travel[0], -travel[1])) % 360.0
    alpha = _angle(street, heading)
    if alpha >= CROSS_ANGLE:
        return piece
    start = _point_at_distance(piece, head, DOGLEG, at_end)
    if start is None:
        return piece
    turned = _turned(street, heading, alpha, start, near)
    if turned is None:
        return piece
    t = _dir(turned)
    bend = [start[0] + t[0] * DOGLEG, start[1] + t[1] * DOGLEG]
    curve = hermite(start, travel, bend, t, 8)
    meet = _meet(bend, t, entry)
    if meet is None:
        meet = [bend[0] + t[0] * 40.0, bend[1] + t[1] * 40.0]
    points = [list(p) for p in piece]
    trimmed = []
    for p in points:
        if math.dist(p, start) < 0.6:
            continue
        trimmed.append(p)
    middle = [list(q) for q in curve[1:]] + [list(meet)]
    if at_end:
        return trimmed + middle
    return [list(q) for q in reversed(middle)] + trimmed


def _unit(v):
    """The unit vector of a vector."""
    length = math.hypot(v[0], v[1]) or 1.0
    return (v[0] / length, v[1] / length)


def _turned(street, heading, alpha, start, near):
    """The heading the street turns to, or None."""
    delta = CROSS_ANGLE - alpha
    toward = _unit((near[0] - start[0], near[1] - start[1]))
    for way in (1.0, -1.0):
        turned = _rotate(street, way * delta)
        if _angle(turned, heading) < CROSS_ANGLE - 0.5:
            continue
        t = _dir(turned)
        if t[0] * toward[0] + t[1] * toward[1] > 0.0:
            return turned
    return None


def _meet(bend, t, entry):
    """The point where the bent street reaches the arterial's centre-line."""
    for a, b in zip(entry["points"], entry["points"][1:]):
        hit = _cross(bend, t, a, b)
        if hit is not None:
            return hit
    return None


def _cross(origin, direction, a, b):
    """The intersection of a ray and a segment."""
    ex, ez = b[0] - a[0], b[1] - a[1]
    den = direction[0] * ez - direction[1] * ex
    if abs(den) < 1e-9:
        return None
    t = ((a[0] - origin[0]) * ez - (a[1] - origin[1]) * ex) / den
    u = ((a[0] - origin[0]) * direction[1]
         - (a[1] - origin[1]) * direction[0]) / den
    if t < 0.0 or u < 0.0 or u > 1.0:
        return None
    return [origin[0] + t * direction[0], origin[1] + t * direction[1]]


def _point_at_distance(points, head, distance, at_end=True):
    """The point of a street `distance` metres from its end."""
    if at_end:
        a, b = points[-1], points[-2]
    else:
        a, b = points[0], points[1]
    run = math.dist(a, b)
    if run < 1e-6 or run < distance:
        return None
    t = (run - distance) / run
    return [b[0] + t * (a[0] - b[0]), b[1] + t * (a[1] - b[1])]
