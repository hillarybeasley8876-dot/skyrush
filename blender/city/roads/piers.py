"""T-piers: a single column with a hammerhead cap, half of them wrapped in ivy.

Section (dossier §2.3): column 2.0 x 3.0 m with 0.4 m corner rounds standing on
the GROUND, a 16 m hammerhead cap ACROSS the road (2.6 m wide along the road,
2.0 m deep at the column tapering to 1.2 m at the tips) whose top is the girder
underside, and portal frames where a road runs below.
"""
import math
import random

import bmesh
from mathutils import Vector

from city.roads import levels, meshkit, profiles

CONCRETE = "SH_concrete_pier"
IVY = "Road_Ivy"
COLLIDER = "concrete-colonly"

COL_ACROSS = 2.0        # column, across the road
COL_ALONG = 3.0         # column, along the road
COL_RADIUS = 0.4        # corner radius
CAP_LENGTH = 16.0       # cap, across the road
CAP_WIDTH = 2.6         # cap, along the road
CAP_DEPTH = 2.0         # cap depth at the column
CAP_TIP = 1.2           # cap depth at the tips
SHIFT_LIMIT = 16.0      # how far a column may move to clear a carriageway
# the sideways steps of the search: a column has to clear the whole width of
# the road it would stand in
SHIFTS = (0.0, 2.0, -2.0, 4.0, -4.0, 6.0, -6.0, 8.0, -8.0, 10.0, -10.0,
          12.0, -12.0, 14.0, -14.0, 16.0, -16.0)
PORTAL_CLEARANCE = 1.5  # portal columns stand this far outside the lower road
PORTAL_PARALLEL = 45.0  # below this angle the road below runs parallel
MAX_GAP = 45.0          # the longest stretch of deck without a pier
CLEARANCE = 3.0         # a column keeps this far away from another road's lanes
IVY_HEIGHT = 7.6
IVY_CARDS = 9          # the leaf cards of one pier
IVY_CARD_WIDTH = 1.3  # the width of one card
GROUND_Z = 0.0


def rounded_rect(half_across, half_along, radius, seg=2):
    """Points of a rounded rectangle in the (across, along) plane, counter-clockwise."""
    pts = []
    corners = [(half_across - radius, half_along - radius, 0.0),
               (-(half_across - radius), half_along - radius, math.pi * 0.5),
               (-(half_across - radius), -(half_along - radius), math.pi),
               (half_across - radius, -(half_along - radius), math.pi * 1.5)]
    for (cx, cy, a0) in corners:
        for s in range(seg + 1):
            a = a0 + (math.pi * 0.5) * s / seg
            pts.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    return pts


def _at(origin, right, tangent, a, b, z):
    """A point in the road frame at an ABSOLUTE height z (the origin's z is ignored)."""
    p = origin + right * a + tangent * b
    return Vector((p.x, p.y, z))


def _prism(bm, section, z0, z1, origin, right, tangent):
    """Loft a 2D section between two absolute heights and cap it."""
    lo = [bm.verts.new(_at(origin, right, tangent, a, b, z0)) for (a, b) in section]
    hi = [bm.verts.new(_at(origin, right, tangent, a, b, z1)) for (a, b) in section]
    n = len(section)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bm.faces.new(tuple(reversed(lo)))
    bm.faces.new(tuple(hi))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_column(bm, origin, right, tangent, z0, z1, scale=1.0):
    """Rounded rectangular column between two heights."""
    sec = rounded_rect(COL_ACROSS * 0.5 * scale, COL_ALONG * 0.5 * scale,
                       COL_RADIUS * scale)
    return _prism(bm, sec, z0, z1, origin, right, tangent)


def build_cap(bm, origin, right, tangent, zg):
    """Hammerhead cap across the road: the top is the girder underside zg."""
    rings = []
    steps = 6
    for i in range(steps + 1):
        t = -1.0 + 2.0 * i / steps
        x = t * CAP_LENGTH * 0.5
        depth = min(CAP_DEPTH + (CAP_TIP - CAP_DEPTH) * abs(t), zg)
        ring = []
        for (a, z) in ((-CAP_WIDTH * 0.5, zg - depth), (CAP_WIDTH * 0.5, zg - depth),
                       (CAP_WIDTH * 0.5, zg), (-CAP_WIDTH * 0.5, zg)):
            ring.append(bm.verts.new(_at(origin, right, tangent, x, a, z)))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(4):
            k2 = (k + 1) % 4
            bm.faces.new((r0[k], r0[k2], r1[k2], r1[k]))
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_portal(bm, origin, right, tangent, zg, span, across=True):
    """Portal frame: two columns and a cross beam over the road below.

    `across` is True when the road below runs parallel to this road: the
    columns stand beside it. It is False when the road below crosses this one:
    the columns stand before and after the crossing.
    """
    axis = right if across else tangent
    for s in (-1.0, 1.0):
        build_column(bm, origin + axis * (s * span * 0.5), right, tangent, GROUND_Z, zg - 1.2)
    beam = []
    top = []
    for (a, b) in ((span * 0.5 + 0.4, -0.6), (span * 0.5 + 0.4, 0.6),
                   (-span * 0.5 - 0.4, 0.6), (-span * 0.5 - 0.4, -0.6)):
        beam.append(bm.verts.new(_at(origin, right, tangent, a, b, zg - 1.2)))
        top.append(bm.verts.new(_at(origin, right, tangent, a, b, zg)))
    for k in range(4):
        k2 = (k + 1) % 4
        bm.faces.new((beam[k], beam[k2], top[k2], top[k]))
    bm.faces.new(tuple(reversed(beam)))
    bm.faces.new(tuple(top))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def blocked_lane(paths, point, radius=CLEARANCE):
    """True when a column stands in a turning path of a junction."""
    x, y = point.x, point.y
    r2 = radius * radius
    for (px, pz) in paths:
        dx = px - x
        dy = pz - y
        if dx * dx + dy * dy < r2:
            return True
    return False


def blocked(city, point, ignore_road, zg, clearance=CLEARANCE):
    """True when a column at `point` would cross another road's carriageway."""
    for road in city.roads:
        if road.id == ignore_road:
            continue
        lay = profiles.layout(road)
        dist, idx, t = road.closest(point)
        if dist >= lay["asphalt_half"] + clearance:
            continue
        # the other road's surface must be between the ground and the girder
        other_z = road.path[idx].z + (road.path[idx + 1].z - road.path[idx].z) * t
        if GROUND_Z - 1.0 <= other_z <= zg:
            return True
    return False


def _lower_road(city, point, ignore_road, zg):
    """The road that runs under a pier point (the one the portal has to span)."""
    best = None
    for road in city.roads:
        if road.id == ignore_road:
            continue
        lay = profiles.layout(road)
        dist, idx, t = road.closest(point)
        if dist >= lay["asphalt_half"] + PORTAL_CLEARANCE:
            continue
        other_z = road.path[idx].z + (road.path[idx + 1].z - road.path[idx].z) * t
        if not (GROUND_Z - 1.0 <= other_z <= zg):
            continue
        if best is None or dist < best[0]:
            best = (dist, road, idx)
    return best


def _portal_ok(city, road, lower, zg):
    """How a portal frame can span the road below: (across, span) or None.

    When the road below runs parallel to this road, the columns of the portal
    stand beside it. When it crosses this one, the columns stand before and
    after the crossing. Either way the beam is over the road below and its top
    is the underside of the girder.
    """
    _dist, other, idx = lower
    t_other = other.frames[idx][0]
    t_own = road.frames[road.index_at(0.0)][0]
    angle = levels.angle_between(t_other, t_own)
    if other.path[idx].z > zg - 2.5:
        return None       # the road below is too high for a beam over it
    half = profiles.layout(other)["asphalt_half"]
    span = 2.0 * (half + PORTAL_CLEARANCE)
    if angle <= math.radians(PORTAL_PARALLEL):
        return (True, span)
    return (False, span)


def pier_positions(city, road, paths=()):
    """Pier placements: (distance, point, right, tangent, girder underside, portal)."""
    out = []
    spacing = max(8.0, road.pier_spacing)
    s = spacing * 0.5
    last = 0.0
    while s < road.length:
        if road.pier_allowed(s):
            place = _place(city, road, s, spacing, paths)
            if place is not None:
                out.append(place)
                last = s
            elif s - last > MAX_GAP:
                # the deck must never fly: a portal frame goes here even when it
                # is tight
                forced = _forced(city, road, s, paths)
                if forced is not None:
                    out.append(forced)
                    last = s
        s += spacing
    return out


def _forced(city, road, s, paths=()):
    """A pier for a spot where no clear column fits: a portal over the road below."""
    p, t, r, u, _ = road.at(s)
    zg = road.path[road.index_at(s)].z - profiles.GIRDER_DEPTH
    if zg <= 1.5:
        return None
    lower = _lower_road(city, p, road.id, zg)
    if lower is None:
        return None
    return (s, p, r, t, zg, True, 0.0)


def _place(city, road, s, spacing, paths=()):
    """Find a clear spot for the pier: shift it sideways, then along the road.

    A column that stands in another road's carriageway blocks a driving lane,
    so the pier moves until it is clear; when it cannot, a portal frame spans
    the road below. A pier is never dropped: the deck would fly.
    """
    for along in (0.0, spacing * 0.25, -spacing * 0.25, spacing * 0.5, -spacing * 0.5):
        at = s + along
        if at <= 0.0 or at >= road.length or not road.pier_allowed(at):
            continue
        p, t, r, u, _ = road.at(at)
        zg = road.path[road.index_at(at)].z - profiles.GIRDER_DEPTH
        if zg <= 1.5:
            continue
        for shift in SHIFTS:
            q = p + r * shift
            if not blocked(city, q, road.id, zg) and not blocked_lane(paths, q):
                return (at, q, r, t, zg, False, shift)
        lower = _lower_road(city, p, road.id, zg)
        if lower is not None:
            portal = _portal_ok(city, road, lower, zg)
            if portal is not None:
                return (at, p, r, t, zg, True, 0.0)
    return None


def build_ivy(bm, origin, right, tangent, height, seed):
    """Patchy ivy on a pier: leaf cards with an organic top edge.

    The cards stand against the column and carry the alpha atlas of the ivy, so
    the plant ends in a ragged edge instead of a box sleeve.
    """
    rng = random.Random(seed)
    for _ in range(IVY_CARDS):
        angle = rng.random() * 2.0 * math.pi
        width = IVY_CARD_WIDTH * (0.75 + 0.5 * rng.random())
        tall = height * (0.45 + 0.55 * rng.random())
        out = Vector((math.cos(angle), math.sin(angle), 0.0))
        side = Vector((-out.y, out.x, 0.0))
        centre = origin + out * (COL_ACROSS * 0.5)
        a = centre - side * (width * 0.5)
        b = centre + side * (width * 0.5)
        v0 = bm.verts.new(a)
        v1 = bm.verts.new(b)
        v2 = bm.verts.new(b + Vector((0.0, 0.0, tall)))
        v3 = bm.verts.new(a + Vector((0.0, 0.0, tall)))
        face = bm.faces.new((v0, v1, v2, v3))
        uv = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
        for loop, coord in zip(face.loops, ((0.0, 0.0), (width, 0.0),
                                             (width, tall), (0.0, tall))):
            loop[uv].uv = coord
    return bm


def build_pier(bm, city, road, p, r, t, zg, portal, span=12.0, across=True):
    """The concrete of one pier: a column from the ground plus the hammerhead cap."""
    if portal:
        build_portal(bm, p, r, t, zg, span, across)
        return
    top = max(GROUND_Z, zg - CAP_DEPTH)
    if top - GROUND_Z > 0.3:
        build_column(bm, p, r, t, GROUND_Z, top)
    build_cap(bm, p, r, t, zg)


def build(city, road, tileset, records, paths=()):
    """Add the piers of a road to the tile builders; appends records for the data files."""
    for (s, p, r, t, zg, portal, shift) in pier_positions(city, road, paths):
        builder = tileset.builder_at(p)
        bm = bmesh.new()
        span = 12.0
        across = True
        if portal:
            lower = _lower_road(city, p, road.id, zg)
            if lower is not None:
                half = profiles.layout(lower[1])["asphalt_half"]
                span = 2.0 * (half + PORTAL_CLEARANCE)
                ok = _portal_ok(city, road, lower, zg)
                if ok is not None:
                    across, span = ok
        build_pier(bm, city, road, p, r, t, zg, portal, span, across)
        builder.add(CONCRETE, bm)
        if not portal and road.pier_spacing > 0:
            ivy_h = min(IVY_HEIGHT, zg - CAP_DEPTH)
            if ivy_h > 1.0 and (int(s / max(1.0, road.pier_spacing)) % 2 == 0):
                bmi = bmesh.new()
                build_ivy(bmi, p, r, t, ivy_h, int(s * 7.0) + len(road.id))
                builder.add(IVY, bmi)
        _add_collider(builder, p, r, t, zg, portal, span, across)
        records.append({
            "road": road.id,
            "x": round(p.x, 2),
            "y": GROUND_Z,
            "z": round(-p.y, 2),
            "deck_y": round(road.path[road.index_at(s)].z, 2),
            "heading_deg": round(math.degrees(math.atan2(t.y, t.x)), 1),
            "distance_m": round(s, 1),
            "type": "portal" if portal else "t_pier",
            "height_m": round(zg, 2),
            "shift_m": round(shift, 2),
            "span_m": round(span, 2) if portal else 0.0,
        })


def _add_collider(builder, p, r, t, zg, portal, span=12.0, across=True):
    """A closed convex collider for the column so cars cannot drive through it."""
    bm = bmesh.new()
    if portal:
        axis = r if across else t
        for s in (-1.0, 1.0):
            _box(bm, p + axis * (s * span * 0.5), r, t, COL_ACROSS, COL_ALONG,
                 GROUND_Z, zg - 1.2)
    else:
        _box(bm, p, r, t, COL_ACROSS, COL_ALONG, GROUND_Z, zg - CAP_DEPTH)
    builder.add_named(COLLIDER, bm)


def _box(bm, centre, right, tangent, across, along, z0, z1):
    """A closed box in the road frame."""
    hx, hy = along * 0.5, across * 0.5
    corners = []
    for a in (-hx, hx):
        for b in (-hy, hy):
            for c in (z0, z1):
                p = centre + tangent * a + right * b
                corners.append(Vector((p.x, p.y, c)))
    idxs = [bm.verts.new(c) for c in corners]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
             (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for f in faces:
        bm.faces.new([idxs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm
