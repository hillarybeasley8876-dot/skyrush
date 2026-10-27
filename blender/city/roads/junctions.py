"""Junctions: a flat asphalt polygon blending the meeting roads, kerb returns,
crosswalks and stop lines.

The junction is the union of the arm corridors; its boundary is the arm side
lines joined by kerb-return fillets (radius 9 m). Only the arms that share a
height form a junction (see levels.py): an elevated road crossing a street is
left alone. The fill follows the arms' heights, so a ramp that lands on a
street meets it at the right height, and the collision is the same polygon
(lowered 1 cm) instead of a disc.
"""
import math

from mathutils import Vector

from city.roads import junction_fill, junction_markings, levels, profiles


KERB_RETURN = 9.0
MAX_REACH = 20.0       # how far the kerb return may reach past the kerb line
MIN_ARM_ANGLE = 25.0   # two arms closer than this are a merge, not a junction
END_CAP = 14.0          # how far the junction reaches past the arm's kerb line
MIN_CUT = 1.0           # a kerb cut shorter than this is no kerb return (the straight side of a T has a rounding error of 1e-5)


def line_intersect(p1, d1, p2, d2):
    """Intersection of the lines p1+t*d1 and p2+s*d2."""
    det = d1.x * (-d2.y) - d1.y * (-d2.x)
    if abs(det) < 1e-9:
        return None
    rhs = p2 - p1
    t = (rhs.x * (-d2.y) - rhs.y * (-d2.x)) / det
    return p1 + d1 * t


def _on_road(road, s):
    """The point of the centre line of a road at the distance `s` along it."""
    i = road.index_at(s)
    if i >= len(road.path) - 1:
        return road.path[-1]
    seg = road.dist[i + 1] - road.dist[i]
    t = 0.0 if seg < 1e-9 else max(0.0, min(1.0, (s - road.dist[i]) / seg))
    return road.path[i].lerp(road.path[i + 1], t)


def arm_geometry(city, junction):
    """The arms of a junction: [{road, index, dir, half, tangent, n, z, sign}].

    Only the arms that share a level are returned: a crossing with a road at
    another height is grade separated and has no junction.  `off` says that the
    junction stands beside the road instead of on it: the fill of such a
    junction is drawn on the road, not on the centre of the junction.
    """
    centre = city.junction_centre(junction)
    arms = []
    for (road, idx, dist) in city.junction_arms(junction):
        t = road.frames[idx][0]
        lay = profiles.layout(road)
        half = lay["asphalt_half"]
        s0, z0 = road.project(centre)
        # the junction stands beside a road whose side street ends at it: the
        # fill of the junction is then drawn on that road, not on the centre
        off = dist > half
        base = _on_road(road, s0) if off else centre
        if idx > 0:
            arms.append({"road": road, "index": idx, "dir": -t.copy(), "half": half,
                         "tangent": t.copy(), "sign": -1.0, "z": z0, "s0": s0,
                         "base": base, "off": off})
        if idx < len(road.path) - 1:
            arms.append({"road": road, "index": idx, "dir": t.copy(), "half": half,
                         "tangent": t.copy(), "sign": 1.0, "z": z0, "s0": s0,
                         "base": base, "off": off})
    for a in arms:
        d = a["dir"]
        a["n"] = Vector((-d.y, d.x, 0.0))
    return levels.dominant(arms), centre


def is_merge(arms):
    """True when two arms run almost parallel: that is a merge, not a junction.

    A merge has no junction box (no fill, no kerb returns, no crossings), but
    the lanes of the two roads are still linked: the traffic of the ramp joins
    the traffic of the road.
    """
    ordered = _ordered(arms)
    for i, a in enumerate(ordered):
        b = ordered[(i + 1) % len(ordered)]
        if a is b:
            continue
        if a["dir"].dot(b["dir"]) > math.cos(math.radians(MIN_ARM_ANGLE)):
            return True
    return False


def _fillet_points(prev, cur, centre, radius):
    """Corner fillet between two arms: the tangent point on each arm."""
    c1 = centre + prev["n"] * prev["half"]
    c2 = centre - cur["n"] * cur["half"]
    f1 = centre + prev["n"] * (prev["half"] + radius)
    f2 = centre - cur["n"] * (cur["half"] + radius)
    f = line_intersect(f1, prev["dir"], f2, cur["dir"])
    if f is None:
        return None
    t_prev = c1 + prev["dir"] * ((f - c1).dot(prev["dir"]))
    t_cur = c2 + cur["dir"] * ((f - c2).dot(cur["dir"]))
    return f, t_prev, t_cur


def _fillet(prev, cur, centre):
    """The corner fillet of two arms, with a radius that keeps the kerb sane.

    A shallow crossing pushes the fillet of a wide road hundreds of metres out,
    so the radius is reduced until the kerb return stays within reach.
    """
    radius = KERB_RETURN
    fl = None
    for _ in range(6):
        fl = _fillet_points(prev, cur, centre, radius)
        if fl is None:
            return None
        fc, _t_a, _t_b = fl
        over = 1.0
        for arm in (prev, cur):
            cut = (fc - centre).dot(arm["dir"])
            limit = arm["half"] + MAX_REACH
            if cut > limit:
                over = max(over, cut / limit)
        if over <= 1.0:
            return fl
        radius = max(2.0, radius / over)
    return fl


def _ordered(arms):
    """Arms sorted counter-clockwise around the junction."""
    order = sorted(range(len(arms)), key=lambda i: math.atan2(arms[i]["dir"].y, arms[i]["dir"].x))
    return [arms[i] for i in order]


def _arm_z(arm, distance):
    """The height of an arm's road `distance` metres from the junction."""
    road = arm["road"]
    return levels.z_at(road, arm["s0"] + arm["sign"] * distance)


def _chamfer(prev, cur, centre):
    """A straight corner between two arms that are nearly parallel.

    Returns (point, cut_prev, cut_cur): the corner point and how far along each
    arm it lies.
    """
    l1 = centre + prev["n"] * prev["half"]
    l2 = centre - cur["n"] * cur["half"]
    p = line_intersect(l1, prev["dir"], l2, cur["dir"])
    limit = prev["half"] + cur["half"] + 30.0
    if p is None:
        d = l1 - l2
        mid = (l1 + l2) * 0.5
        p = mid + d.normalized() * limit * 0.5 if d.length > 1e-6 else mid
    else:
        v = p - centre
        if v.length > limit:
            p = centre + v.normalized() * limit
    cut_a = max(0.0, (p - centre).dot(prev["dir"]))
    cut_b = max(0.0, (p - centre).dot(cur["dir"]))
    return p, cut_a, cut_b


def _corner(prev, cur, centre):
    """The corner between two arms.

    Returns (points, z_first, z_last, cut_prev, cut_cur): the points walk the
    kerb return arc, or the straight chamfer of two nearly parallel arms.
    """
    fl = _fillet(prev, cur, centre)
    if fl is not None:
        fc, t_a, t_b = fl
        cut_a = (t_a - centre).dot(prev["dir"])
        cut_b = (t_b - centre).dot(cur["dir"])
        if cut_a > max(4.0, prev["half"] * 0.5) and cut_b > max(4.0, cur["half"] * 0.5):
            a0 = math.atan2((t_a - fc).y, (t_a - fc).x)
            a1 = math.atan2((t_b - fc).y, (t_b - fc).x)
            sweep = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
            radius = (t_a - fc).length
            pts = []
            for s in range(1, 8):
                f = s / 7.0
                ang = a0 + sweep * f
                pts.append(fc + Vector((math.cos(ang), math.sin(ang), 0.0)) * radius)
            return pts, _arm_z(prev, cut_a), _arm_z(cur, cut_b), cut_a, cut_b
    p, cut_a, cut_b = _chamfer(prev, cur, centre)
    z = 0.5 * (prev["z"] + cur["z"])
    return [p], z, z, cut_a, cut_b


def road_radius(arms, road_id):
    """How far from the junction centre a road's kerb is cut back.

    The road's surface and its kerb stop here and the junction's fill takes
    over, so the fill's height has to match the road's height at this point.
    """
    best = None
    for a in arms:
        if a["road"].id != road_id:
            continue
        cut = min(a.get("_cut_left", 0.0), a.get("_cut_right", 0.0))
        if cut < MIN_CUT:
            cut = a["half"] + KERB_RETURN
        cut = min(cut, a["half"] + MAX_REACH)
        best = cut if best is None else min(best, cut)
    return best if best is not None else 0.0


def _cross_section(arm, arms):
    """Where an arm's road ends and the junction's fill takes over.

    The road's surface is cut at the first path sample beyond the kerb return,
    so the fill starts exactly there: the fill's height is then the road's
    height and a car crossing the seam meets no step.
    """
    road = arm["road"]
    radius = road_radius(arms, road.id)
    s0 = arm["s0"]
    if arm["sign"] > 0.0:
        j = road.first_beyond(s0 + radius)
    else:
        j = road.last_before(s0 - radius)
    s = road.dist[j]
    d = (s - s0) if arm["sign"] > 0.0 else (s0 - s)
    return max(1.0, d), levels.z_at(road, s)


def boundary(arms, centre):
    """The junction outline: a ring of points, each with its height.

    The ring starts at each arm's kerb line (where the road's own surface ends
    and the fill begins) and follows the kerb returns around the corners, so
    the fill meets the road at exactly the road's height.

    Returns (ring, arcs): the ring is the closed polygon of the junction fill
    (points with their z) and the arcs are the kerb-return arcs.
    """
    ordered = _ordered(arms)
    n = len(ordered)
    corners = []
    for k, a in enumerate(ordered):
        nxt = ordered[(k + 1) % n]
        pts, z_a, z_b, cut_a, cut_b = _corner(a, nxt, centre)
        a["_cut_left"] = cut_a
        nxt["_cut_right"] = cut_b
        corners.append((pts, z_a, z_b))
    ring = []
    arcs = []
    for k, a in enumerate(ordered):
        nxt = ordered[(k + 1) % n]
        pts, z_tan, z_tan_b = corners[k]
        cross_d, z_rad = _cross_section(a, arms)
        cross_d_b, z_rad_b = _cross_section(nxt, arms)
        a["_cross_z"] = z_rad
        radius = cross_d
        radius_b = cross_d_b
        base = _on_road(a["road"], a["s0"] + a["sign"] * radius) if a["off"] \
            else centre + a["dir"] * radius
        cross_r = base - a["n"] * a["half"]
        cross_l = base + a["n"] * a["half"]
        ring.append((cross_r, -a["n"], z_rad))
        ring.append((cross_l, a["n"], z_rad))
        for s in range(1, 4):
            f = s / 4.0
            ring.append((cross_l.lerp(pts[0], f), a["n"], z_rad + (z_tan - z_rad) * f))
        arc = []
        for i, q in enumerate(pts):
            f = (i + 1) / float(len(pts) + 1)
            z = z_tan + (z_tan_b - z_tan) * f
            arc.append(Vector((q.x, q.y, z)))
            ring.append((q, (q - centre).normalized(), z))
        # the next arm's right side, from the corner back to its kerb line
        base_b = _on_road(nxt["road"], nxt["s0"] + nxt["sign"] * radius_b) if nxt["off"] \
            else centre + nxt["dir"] * radius_b
        cross_r_b = base_b - nxt["n"] * nxt["half"]
        for s in range(1, 4):
            f = s / 4.0
            ring.append((pts[-1].lerp(cross_r_b, f), -nxt["n"], z_tan_b + (z_rad_b - z_tan_b) * f))
        arcs.append(arc)
    return ring, arcs


def outline(arms, centre):
    """The junction's fill outline: (hub, ring) where the ring carries its heights."""
    ring, arcs = boundary(arms, centre)
    if len(ring) < 3:
        return None, []
    pts = [Vector((p.x, p.y, z)) for (p, _n, z) in ring]
    # the hub sits at the mean height of the arms' cross-sections: the fill then
    # follows the roads that meet here instead of tilting away from them (an
    # elevated road that slopes through a junction used to end up with a fill
    # that stood a metre above its own asphalt)
    heights = [a.get("_cross_z", a["z"]) for a in arms]
    level = sum(heights) / len(heights)
    hub = Vector((centre.x, centre.y, level))
    return (hub, pts), arcs


def fan(arms, centre):
    """The junction's fill fan: (hub, ring), or None when there is no junction."""
    if len(arms) < 2:
        return None
    fill, _arcs = outline(arms, centre)
    return fill


def trim_indices(city, road, junction, path=None):
    """Path sample indices of a road that lie inside a junction.

    The kerb of the road stops where the kerb-return arc starts, so the cut is at
    the arc's tangent point, not at the junction's outer cap. Only a road that
    is an arm of the junction's level is cut: a road that passes underneath is
    left alone. The samples of every junction of the road are taken together
    (junction_holes.road_holes), so the cuts of two junctions cannot eat each
    other, and a road that a junction stands beside is cut where the junction
    stands on it; `path` is the road's own path.
    """
    from city.roads import junction_holes
    return set(junction_holes.road_holes(city, road).get(junction["id"], ()))


def collision_excluded(city, road, junction, path=None):
    """The path samples of a road that the junction's own fill takes over.

    The road's surface collider has to reach the cross-section of the fill: if
    it stops at the kerb return, a car crosses a gap of one sample and drops
    through it.
    """
    out = set()
    arms, centre = arm_geometry(city, junction)
    if not arms:
        return out
    if not any(a["road"].id == road.id for a in arms):
        return out
    if is_merge(arms):
        return out       # a merge has no fill: the roads simply meet
    boundary(arms, centre)
    radius = road_radius(arms, road.id)
    if radius <= 0.0:
        return out
    for a in arms:
        if a["road"].id != road.id:
            continue
        if a["sign"] > 0.0:
            j = road.first_beyond(a["s0"] + radius)
        else:
            j = road.last_before(a["s0"] - radius)
        # the samples strictly inside the junction: the road's own collider
        # reaches the cross-section, where the fill's collider takes over
        for i in range(min(a["index"], j) + 1, max(a["index"], j)):
            out.add(i)
    return out


def build(city, junction, tileset):
    """All junction geometry for one junction."""
    arms, centre = arm_geometry(city, junction)
    if len(arms) < 2 or is_merge(arms):
        return
    fill, arcs = outline(arms, centre)
    z = fill[0].z if fill else 0.0
    junction_fill.build_fill(fill, tileset)
    junction_markings.build_kerb(arcs, tileset)
    # the crossings stand on the road of their arm, not on the centre of the
    # junction, which stands beside a road whose side street ends at it
    for a in arms:
        junction_markings.build_crossings([a], a["base"], tileset, z, END_CAP)
    junction_markings.build_arrows(arms, centre, tileset, z)
