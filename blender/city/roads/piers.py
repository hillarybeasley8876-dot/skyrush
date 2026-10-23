"""T-piers: a single column with a hammerhead cap, half of them wrapped in ivy.

Section (dossier §2.3): column 2.0 x 3.0 m with 0.4 m corner rounds standing on
the GROUND, a 16 m hammerhead cap ACROSS the road (2.6 m wide along the road, 2.0 m deep
at the column) whose top is the girder underside, and portal frames where a
road runs below.
"""
import math
import random

import bmesh
from mathutils import Vector

from city.roads import collision, levels, meshkit, profiles

CONCRETE = "SH_concrete_pier"
IVY = "Road_Ivy"

COL_ACROSS = 2.0        # column, across the road
COL_ALONG = 3.0         # column, along the road
COL_RADIUS = 0.4        # corner radius
CAP_LENGTH = 16.0       # cap, across the road
CAP_WIDTH = 2.6         # cap, along the road
CAP_DEPTH = 2.0         # cap depth at the column
CAP_TIP = 1.2           # cap depth at the tips
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
    """Portal frame: two columns and a cross beam over the road below."""
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
    r2 = radius * radius
    return any((px - point.x) ** 2 + (pz - point.y) ** 2 < r2 for (px, pz) in paths)


def plan_closest(road, point):
    """(plan distance, index, t) of the closest point on a road's centre line.

    `Road.closest` measures in 3D, so a pier 30 m above a road below it looks
    30 m away from it and the column is placed in the lane below.
    """
    best = (1e18, 0, 0.0)
    px, py = point.x, point.y
    for i in range(len(road.path) - 1):
        a = road.path[i]
        ab = road.path[i + 1] - a
        l2 = ab.x * ab.x + ab.y * ab.y
        t = 0.0 if l2 < 1e-9 else max(0.0, min(1.0, ((px - a.x) * ab.x + (py - a.y) * ab.y) / l2))
        d = math.hypot(px - (a.x + ab.x * t), py - (a.y + ab.y * t))
        if d < best[0]:
            best = (d, i, t)
    return best


def _road_height(road, idx, t):
    """The height of a road's centre line at a point of its path."""
    return road.path[idx].z + (road.path[idx + 1].z - road.path[idx].z) * t


def blocked(city, point, ignore_road, zg, clearance=CLEARANCE):
    """True when a column at `point` would cross another road's carriageway."""
    for road in city.roads:
        if road.id == ignore_road:
            continue
        lay = profiles.layout(road)
        dist, idx, t = plan_closest(road, point)
        if dist >= lay["asphalt_half"] + clearance:
            continue
        # the other road's surface must be between the ground and the girder
        if GROUND_Z - 1.0 <= _road_height(road, idx, t) <= zg:
            return True
    return False


def _lower_road(city, point, ignore_road, zg):
    """The road that runs under a pier point (the one the portal has to span)."""
    best = None
    for road in city.roads:
        if road.id == ignore_road:
            continue
        lay = profiles.layout(road)
        dist, idx, t = plan_closest(road, point)
        if dist >= lay["asphalt_half"] + PORTAL_CLEARANCE:
            continue
        if not (GROUND_Z - 1.0 <= _road_height(road, idx, t) <= zg):
            continue
        if best is None or dist < best[0]:
            best = (dist, road, idx, t)
    return best


def _portal_ok(city, road, lower, zg, station):
    """How a portal frame can span the road below: (across, half span) or None.

    The columns stand beside the road below when the two run parallel, and
    before and after it when they cross.  The span grows with the angle.
    """
    _dist, other, idx, _t = lower
    t_other = other.frames[idx][0]
    t_own = road.frames[road.index_at(station)][0]
    angle = levels.angle_between(t_other, t_own)
    if other.path[idx].z > zg - 2.5:
        return None       # the road below is too high for a beam over it
    half = profiles.layout(other)["asphalt_half"]
    clear = half + PORTAL_CLEARANCE
    if angle <= math.radians(PORTAL_PARALLEL):
        return (True, clear / math.cos(angle))
    return (False, clear / math.sin(angle))


def _shift_limit(road):
    """How far a column may move sideways and still stand under the deck."""
    lay = profiles.layout(road)
    return max(0.0, lay["half_width"] - COL_ACROSS * 0.5 - 0.25)


def _placement(s, p, r, t, zg, portal, shift, span=0.0, across=True):
    """One pier: where it stands, how tall it is and whether it is a portal."""
    return {"s": s, "p": p, "r": r, "t": t, "zg": zg, "portal": portal,
            "shift": shift, "span": span, "across": across}


def pier_positions(city, road, paths=()):
    """Pier placements: the piers of a road, in the order they stand."""
    out = []
    spacing = max(8.0, road.pier_spacing)
    s = spacing * 0.5
    last = 0.0
    while s < road.length:
        if road.pier_allowed(s):
            place = _place(city, road, s, spacing, paths)
            if place is None and s - last > MAX_GAP:
                # the deck must never fly: a portal frame goes here even when it
                # is tight
                place = _forced(city, road, s, paths)
            if place is not None:
                out.append(place)
                last = s
        s += spacing
    return out


def _forced(city, road, s, paths=()):
    """A pier for a spot where no clear column fits: a portal over the road below."""
    p, t, r, u, _ = road.at(s)
    zg = road.path[road.index_at(s)].z - profiles.GIRDER_DEPTH
    if zg <= 1.5:
        return None
    portal = _portal(city, road, s, p, r, t, zg, paths)
    if portal is not None:
        return portal
    # no portal fits: a column that stands in no lane, even if it has to
    # stand away from the deck
    for shift in SHIFTS:
        q = p + r * shift
        if not blocked(city, q, road.id, zg) and not blocked_lane(paths, q):
            return _placement(s, q, r, t, zg, False, shift)
    return _placement(s, p, r, t, zg, False, 0.0)


def _column_clear(city, road, q, zg, lower_id, paths):
    """True when a column at `q` stands in no lane.

    The road below is left out: the columns of a portal stand beside it on
    purpose.  Every other road and every turning path of a junction counts:
    a column in a lane is a wall across it.
    """
    for other in city.roads:
        if other.id == road.id or other.id == lower_id:
            continue
        lay = profiles.layout(other)
        dist, idx, t = plan_closest(other, q)
        if dist >= lay["asphalt_half"] + CLEARANCE:
            continue
        if GROUND_Z - 1.0 <= _road_height(other, idx, t) <= zg:
            return False
    return not blocked_lane(paths, q)


def _portal(city, road, s, p, r, t, zg, paths=()):
    """A portal frame over the road below: the columns stand beside it.

    The frame is centred on the road below, so the beam carries the deck, and
    the columns are pushed further out until they stand in no lane at all.
    """
    lower = _lower_road(city, p, road.id, zg)
    if lower is None:
        return None
    ok = _portal_ok(city, road, lower, zg, s)
    if ok is None:
        return None
    across, half = ok
    axis = r if across else t
    _dist, other, idx, t_lower = lower
    origin = other.path[idx].lerp(other.path[idx + 1], t_lower)
    for extra in (0.0, 4.0, 8.0, 12.0, 16.0):
        reach = half + extra
        a = origin + axis * reach
        b = origin - axis * reach
        if _column_clear(city, road, a, zg, other.id, paths) and                 _column_clear(city, road, b, zg, other.id, paths):
            return _placement(s, origin, r, t, zg, True, 0.0, 2.0 * reach, across)
    return None


def _place(city, road, s, spacing, paths=()):
    """Find a clear spot for the pier: shift it sideways, then along the road.

    A column that stands in another road's carriageway blocks a driving lane,
    so the pier moves until it is clear; when it cannot, a portal frame spans
    the road below.  A pier is never dropped: the deck would fly.
    """
    limit = _shift_limit(road)
    for along in (0.0, spacing * 0.25, -spacing * 0.25, spacing * 0.5, -spacing * 0.5):
        at = s + along
        if at <= 0.0 or at >= road.length or not road.pier_allowed(at):
            continue
        p, t, r, u, _ = road.at(at)
        zg = road.path[road.index_at(at)].z - profiles.GIRDER_DEPTH
        if zg <= 1.5:
            continue
        for shift in SHIFTS:
            if abs(shift) > limit:
                continue
            q = p + r * shift
            if not blocked(city, q, road.id, zg) and not blocked_lane(paths, q):
                return _placement(at, q, r, t, zg, False, shift)
        portal = _portal(city, road, at, p, r, t, zg, paths)
        if portal is not None:
            return portal
    return None


def build_ivy(bm, origin, right, tangent, height, seed):
    """Patchy ivy on a pier: leaf cards with an organic top edge."""
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
    for place in pier_positions(city, road, paths):
        s = place["s"]
        p = place["p"]
        r = place["r"]
        t = place["t"]
        zg = place["zg"]
        portal = place["portal"]
        span = place["span"]
        across = place["across"]
        builder = tileset.builder_at(p)
        bm = bmesh.new()
        build_pier(bm, city, road, p, r, t, zg, portal, span, across)
        builder.add(CONCRETE, bm)
        if not portal and road.pier_spacing > 0:
            ivy_h = min(IVY_HEIGHT, zg - CAP_DEPTH)
            if ivy_h > 1.0 and (int(s / max(1.0, road.pier_spacing)) % 2 == 0):
                bmi = bmesh.new()
                build_ivy(bmi, p, r, t, ivy_h, int(s * 7.0) + len(road.id))
                builder.add(IVY, bmi)
        collision.pier_column(builder, p, r, t, zg, portal, span, across)
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
            "shift_m": round(place["shift"], 2),
            "span_m": round(span, 2) if portal else 0.0,
        })


