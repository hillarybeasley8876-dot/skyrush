"""Levels: a crossing at a different height is not a junction.

Shanghai's elevated roads cross the surface streets without meeting them, but
the city file lists every crossing as a junction. The arms therefore have to be
grouped by height first: only the arms that share a level form a real junction
(with a fill, kerb returns and lane movements); the others are grade separated
and are left completely alone.

The height of an arm is the height of its road at the junction, and the fill
follows the arms (it is not a flat slab) so a ramp that lands on a street still
meets it at the right height.
"""
import math

from mathutils import Vector

LEVEL_TOL = 0.45    # two arms of one junction may differ by at most this much


def z_at(road, s):
    """The height of a road's centre line at the distance `s` along its path."""
    d = road.dist
    if s <= 0.0:
        return road.path[0].z
    if s >= road.length:
        return road.path[-1].z
    i = len(d) - 2
    for k in range(len(d) - 1):
        if d[k] <= s <= d[k + 1]:
            i = k
            break
    seg = d[i + 1] - d[i]
    t = 0.0 if seg <= 1e-6 else (s - d[i]) / seg
    return road.path[i].z + (road.path[i + 1].z - road.path[i].z) * t


def arm_sign(road, idx):
    """+1 when the arm leaves the junction along the path, -1 when it comes back."""
    return 1.0 if idx < len(road.path) - 1 else -1.0


def cluster(arms, tol=LEVEL_TOL):
    """Group the arms by height: the groups are the levels of the crossing."""
    groups = []
    for a in sorted(arms, key=lambda x: x["z"]):
        for g in groups:
            if abs(a["z"] - g[0]["z"]) <= tol:
                g.append(a)
                break
        else:
            groups.append([a])
    return groups


def dominant(arms, tol=LEVEL_TOL):
    """The level of a crossing: the group with the most arms (the lowest on a tie).

    Returns [] when no group has two arms: a single arm is not a junction, it is
    a road crossing another road at a different height.
    """
    groups = cluster(arms, tol)
    if not groups:
        return []
    best = None
    for g in groups:
        key = (-len(g), g[0]["z"])
        if best is None or key < best[0]:
            best = (key, g)
    return best[1] if len(best[1]) >= 2 else []


def triangle_z(a, b, c, p):
    """The height of the triangle (a, b, c) at the plan point `p` (Vector, z = 0)."""
    v0 = Vector((b.x - a.x, b.y - a.y))
    v1 = Vector((c.x - a.x, c.y - a.y))
    v2 = Vector((p.x - a.x, p.y - a.y))
    den = v0.x * v1.y - v0.y * v1.x
    if abs(den) < 1e-9:
        return None
    u = (v2.x * v1.y - v2.y * v1.x) / den
    v = (v0.x * v2.y - v0.y * v2.x) / den
    if u < -0.001 or v < -0.001 or u + v > 1.001:
        return None
    return a.z + (b.z - a.z) * u + (c.z - a.z) * v


def fan_z_at(fan, p):
    """The height of a junction's fill at the plan point `p` (Blender Vector)."""
    hub, ring = fan
    for i in range(len(ring) - 1):
        z = triangle_z(hub, ring[i], ring[i + 1], p)
        if z is not None:
            return z
    # outside the fill: take the height of the nearest edge
    best = None
    n = len(ring)
    for i in range(n):
        a = ring[i]
        b = ring[(i + 1) % n]
        ab = b - a
        l2 = ab.length_squared
        t = 0.0 if l2 < 1e-9 else max(0.0, min(1.0, (p - a).dot(ab) / l2))
        q = a + ab * t
        d = (q.x - p.x) ** 2 + (q.y - p.y) ** 2
        if best is None or d < best[0]:
            best = (d, a.z + (b.z - a.z) * t)
    return best[1] if best else hub.z


def offset_point(p, tangent, distance):
    """A plan point `distance` metres along `tangent` from `p`."""
    return Vector((p.x + tangent.x * distance, p.y + tangent.y * distance, 0.0))


def angle_between(a, b):
    """The angle between two plan directions, in radians (0 = parallel)."""
    ang = math.atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)
    return abs(ang)


def point_in_ring(ring, p):
    """True when the plan point `p` is inside the ring (ray casting)."""
    inside = False
    n = len(ring)
    for i in range(n):
        a = ring[i]
        b = ring[(i + 1) % n]
        if (a.y > p.y) != (b.y > p.y):
            x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
            if p.x < x:
                inside = not inside
    return inside


def offset_ring(ring, margin):
    """A ring pushed outwards by `margin` (a miter offset).

    The junction's collision uses it: the movements cut the corners a little,
    and a car must never drop through the seam between the fill and the road.
    """
    n = len(ring)
    if n < 3 or margin <= 0.0:
        return list(ring)
    normals = []
    for i in range(n):
        a = ring[i]
        b = ring[(i + 1) % n]
        dx, dy = b.x - a.x, b.y - a.y
        length = math.hypot(dx, dy)
        if length < 1e-6:
            normals.append(None)
            continue
        normals.append(Vector((dy / length, -dx / length, 0.0)))
    out = []
    for i in range(n):
        n0 = normals[i - 1]
        n1 = normals[i]
        if n0 is None or n1 is None:
            out.append(ring[i].copy())
            continue
        p = ring[i]
        bis = n0 + n1
        if bis.length < 1e-6:
            out.append(p + n1 * margin)
            continue
        bis.normalize()
        # the miter length grows with the corner angle
        cos_half = max(0.35, bis.dot(n1))
        out.append(p + bis * (margin / cos_half))
    return out
