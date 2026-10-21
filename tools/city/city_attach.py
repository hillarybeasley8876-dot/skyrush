"""city_attach — how a ramp meets its parent road.

A ramp never joins a parent on the parent's centre-line: it joins the
*edge* of the carriageway it serves, so the parent's own lanes stay clear.
The offset is the paved half-width of the parent plus the paved half-width
of the ramp:

    lateral = direction * (asphalt_half(parent) + asphalt_half(ramp))

`direction` is +1 for a ramp that runs with the parent's points and -1 for
one that runs against them; the schema's `side` is "right" for +1 and "left"
for -1.
"""
import math

RAMP_LANE_W = 3.75
RAMP_SHOULDER = 1.5


def asphalt_half(road):
    """Half the paved width of a road (the roads unit's `layout()` rule)."""
    get = road.get if isinstance(road, dict) else (
        lambda k, d=0.0: getattr(road, k, d))
    if get("lanes_back", 0) == 0:
        return (get("lanes_fwd", 0) * get("lane_width", RAMP_LANE_W) / 2.0
                + get("shoulder", 0.0))
    inner = 0.5 if (get("kind") in ("elevated", "ramp", "bridge")
                    and get("median", 0.0) > 0) else 0.0
    return (get("median", 0.0) / 2.0 + inner
            + get("lanes_fwd", 0) * get("lane_width", RAMP_LANE_W)
            + get("shoulder", 0.0))


def ramp_half(lanes):
    """The paved half-width of a ramp with `lanes` lanes."""
    return lanes * RAMP_LANE_W / 2.0 + RAMP_SHOULDER


def heading_of(dx, dz):
    """The heading in degrees (0 = north, 90 = east)."""
    return math.degrees(math.atan2(dx, -dz)) % 360.0


def dir_of(deg):
    """The unit vector of a heading."""
    r = math.radians(deg)
    return (math.sin(r), -math.cos(r))


def right_normal(deg):
    """The unit vector 90 deg to the right of a heading."""
    return (math.cos(math.radians(deg)), math.sin(math.radians(deg)))


def side_name(direction):
    """The schema's `side` for a ramp that runs in `direction`."""
    return "right" if direction > 0 else "left"


def attach_point(road, s, direction, ramp_half_m):
    """The point and traffic heading where a ramp meets `road`.

    The point sits on the edge of the carriageway the ramp serves; the
    heading is the direction the traffic runs there.
    """
    p, tan = road.point_at(s)
    h = heading_of(tan[0], tan[2])
    lat = direction * (asphalt_half(road) + ramp_half_m)
    rn = right_normal(h)
    flow = h if direction > 0 else (h + 180.0) % 360.0
    return (p[0] + rn[0] * lat, p[2] + rn[1] * lat), flow


def project(points, point):
    """Where a plan position lies on a centre-line.

    Returns (station, lateral, heading, height): the arc length of the
    projection, the offset to the right of the points, the heading of the
    centre-line there and its height.  The lateral is positive to the right
    of the road's own direction of travel.
    """
    best = None
    acc = 0.0
    for i, p in enumerate(points):
        if i + 1 >= len(points):
            break
        q = points[i + 1]
        dx, dz = q[0] - p[0], q[2] - p[2]
        run = math.hypot(dx, dz)
        if run < 1e-9:
            continue
        t = max(0.0, min(1.0, ((point[0] - p[0]) * dx
                               + (point[1] - p[2]) * dz) / (run * run)))
        qx, qz = p[0] + t * dx, p[2] + t * dz
        d = math.hypot(point[0] - qx, point[1] - qz)
        if best is None or d < best[0]:
            lat = ((point[0] - qx) * (-dz) + (point[1] - qz) * dx) / run
            best = (d, acc + t * run, lat, heading_of(dx, dz),
                    p[1] + t * (q[1] - p[1]))
        acc += run
    return best[1:]
