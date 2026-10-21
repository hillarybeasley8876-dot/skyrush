"""Tunnel interiors (dossier §4).

Two Ø 11 m bores, one per carriageway, each centred on its carriageway:
7.5 m roadway + 0.3 m concrete kerbs. The walls are white enamel panels
(#ECEFF0) from 0.5 to 3.2 m with a 0.3 m colour stripe at 1.2 m and dark
concrete above; 1.2 m luminaires every 2.4 m at both ceiling corners, jet-fan
pairs every 250 m, lane-control signals every 150 m and a portal U-trough with a
height-limit gantry.
"""
import math

import bmesh
from mathutils import Vector

from city.roads import meshkit, profiles

ENAMEL = "Road_Tunnel_Enamel"
STRIPE = "Road_Tunnel_Stripe"
DARK = "Road_Tunnel_Dark"
LED = "Road_Led_Tunnel"
CONCRETE = "SH_concrete_pier"
STEEL = "Road_Steel_Girder"

BORE_RADIUS = 5.5
CLEARANCE = 4.5          # road surface to the crown of the bore
ROADWAY = 7.5            # the roadway of one bore
KERB = 0.3
ENAMEL_LOW = 0.5
ENAMEL_HIGH = 3.2
STRIPE_LOW = 1.05
STRIPE_HIGH = 1.35
LUMINAIRE_LENGTH = 1.2
LUMINAIRE_SPACING = 2.4
JET_FAN_SPACING = 250.0
SIGNAL_SPACING = 150.0
EXIT_SIGN_SPACING = 80.0
PORTAL_CLEARANCE = 5.4
PORTAL_LINTEL = 6.1
HEIGHT_LIMIT = 4.2


def bore_offsets(lay):
    """The centres of the two bores, across the road: one per carriageway.

    The bore is centred on the lanes it carries, so the roadway of a bore is
    the flat part of the circle and the walls stand clear of the traffic.
    """
    out = []
    for side in ("fwd", "back"):
        lanes = lay["lanes"][side]
        if not lanes:
            continue
        out.append((lanes[0][0] + lanes[-1][1]) * 0.5)
    return out


def _bore_arc(half_width, steps=16):
    """The inner surface of a bore: the vertical walls and the arc over the top.

    The bore is raised so that the crown is 4.5 m above the road over the whole
    roadway: a Ø 11 m bore whose centre is 1 m below the road only leaves 3 m
    of headroom at the edge of the carriageway (dossier §4).
    """
    r = BORE_RADIUS
    a0 = math.acos(max(-1.0, min(1.0, half_width / r)))
    cy = CLEARANCE - r * math.sin(a0)
    spring = cy + r * math.sin(a0)
    pts = [(half_width, 0.0), (half_width, spring)]
    for i in range(1, steps):
        # the arc is walked from the right springing over the crown to the left
        a = a0 + (math.pi - 2.0 * a0) * (float(i) / steps)
        pts.append((r * math.cos(a), cy + r * math.sin(a)))
    pts.append((-half_width, spring))
    pts.append((-half_width, 0.0))
    return pts


def _zone_segments(a, b, h_low, h_high):
    """Split the profile segment a->b at the two zone heights."""
    ts = [0.0, 1.0]
    for h in (h_low, h_high):
        if abs(b[1] - a[1]) > 1e-9:
            t = (h - a[1]) / (b[1] - a[1])
            if 0.0 < t < 1.0:
                ts.append(t)
    ts = sorted(set(ts))
    out = []
    for i in range(len(ts) - 1):
        t0, t1 = ts[i], ts[i + 1]
        p0 = (a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0)
        p1 = (a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1)
        mid = (p0[1] + p1[1]) * 0.5
        zone = 0 if mid < h_low else (1 if mid < h_high else 2)
        out.append((p0, p1, zone))
    return out


def _zone_profiles(points, h_low, h_high):
    """The profile split into three polylines: below, between and above the heights."""
    zones = [[], [], []]
    for i in range(len(points) - 1):
        for (p0, p1, zone) in _zone_segments(points[i], points[i + 1], h_low, h_high):
            poly = zones[zone]
            if not poly:
                poly.append(p0)
            poly.append(p1)
    return zones


def _sweep(builder, material, prof, path, closed=False):
    builder.add(material, meshkit.sweep(bmesh.new(), prof, path, closed_profile=closed))


def build_bores(road, idx, builder, lay):
    """The bores: the white enamel panels and the dark concrete above them.

    The two zones share no face: the enamel stops at 3.2 m and the dark
    concrete starts there (dossier §4).
    """
    path = [road.path[i] for i in idx]
    half = min(ROADWAY * 0.5, BORE_RADIUS - 0.6)
    for offset in bore_offsets(lay):
        zones = _zone_profiles(_bore_arc(half), ENAMEL_LOW, ENAMEL_HIGH)
        for zone, material in ((0, DARK), (1, ENAMEL), (2, DARK)):
            poly = zones[zone]
            if len(poly) < 2:
                continue
            prof = [(x + offset, y) for (x, y) in poly]
            _sweep(builder, material, prof, path)


def build_stripe(road, idx, builder, lay):
    """The 0.3 m colour stripe at 1.2 m on both walls of every bore."""
    path = [road.path[i] for i in idx]
    half = min(ROADWAY * 0.5, BORE_RADIUS - 0.6)
    for offset in bore_offsets(lay):
        for sign in (1.0, -1.0):
            prof = [(sign * half + offset, STRIPE_LOW), (sign * half + offset, STRIPE_HIGH)]
            _sweep(builder, STRIPE, prof, path)


def bore_spring(half_width):
    """The height where the wall of a bore meets its arc (4.5 m: the clearance)."""
    return CLEARANCE


def bore_crown(half_width):
    """The height of the crown of a bore over its centre."""
    r = BORE_RADIUS
    a0 = math.acos(max(-1.0, min(1.0, half_width / r)))
    return CLEARANCE - r * math.sin(a0) + r


def build_luminaires(road, idx, builder, lay):
    """1.2 m luminaires every 2.4 m at both ceiling corners."""
    path = [road.path[i] for i in idx]
    half = min(ROADWAY * 0.5, BORE_RADIUS - 0.6)
    spring = bore_spring(half)
    for offset in bore_offsets(lay):
        for sign in (1.0, -1.0):
            prof = [(sign * (half - 0.25) + offset, spring - 0.15),
                    (sign * (half - 0.25) + offset, spring - 0.02),
                    (sign * (half - 0.55) + offset, spring - 0.02),
                    (sign * (half - 0.55) + offset, spring - 0.15)]
            _sweep(builder, LED, prof, path, closed=True)


def build_fixtures(road, idx, builder, lay):
    """Jet-fan pairs, lane-control signals and the green exit signs."""
    half = min(ROADWAY * 0.5, BORE_RADIUS - 0.6)
    crown = bore_crown(half)
    s = 0.0
    while s < road.length:
        j = road.index_at(s)
        if j in idx:
            p = road.path[j]
            r = road.frames[j][1]
            t = road.frames[j][0]
            u = road.frames[j][2]
            for offset in bore_offsets(lay):
                # a pair of jet fans, one on each side of the carriageway
                for sign in (1.0, -1.0):
                    bm = bmesh.new()
                    _jet_fan(bm, p + r * (offset + sign * 1.9) + u * (crown - 0.7), r, t, u)
                    builder.add(STEEL, bm)
        s += JET_FAN_SPACING
    s = 0.0
    while s < road.length:
        j = road.index_at(s)
        if j in idx:
            p = road.path[j]
            r = road.frames[j][1]
            t = road.frames[j][0]
            for offset in bore_offsets(lay):
                bm = bmesh.new()
                _box(bm, p + r * (offset + half - 0.2) + Vector((0, 0, 2.6)), r, t,
                     0.3, 0.2, 0.5)
                builder.add(DARK, bm)
        s += SIGNAL_SPACING
    s = 0.0
    while s < road.length:
        j = road.index_at(s)
        if j in idx:
            p = road.path[j]
            r = road.frames[j][1]
            t = road.frames[j][0]
            for offset in bore_offsets(lay):
                bm = bmesh.new()
                _box(bm, p + r * (offset + half - 0.2) + Vector((0, 0, 2.9)), r, t,
                     0.1, 0.5, 0.3)
                builder.add(LED, bm)
        s += EXIT_SIGN_SPACING


def _jet_fan(bm, centre, right, tangent, up):
    """A jet fan: a Ø 1.2 m cylinder 5 m long under the crown."""
    rings = []
    for k in (-2.5, 2.5):
        ring = []
        for i in range(10):
            a = 2.0 * math.pi * i / 10
            ring.append(bm.verts.new(centre + tangent * k
                                     + right * (0.6 * math.cos(a)) + up * (0.6 * math.sin(a))))
        rings.append(ring)
    for i in range(10):
        j = (i + 1) % 10
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _box(bm, centre, right, tangent, along, across, up):
    hx, hy, hz = along * 0.5, across * 0.5, up * 0.5
    corners = []
    for a in (-hx, hx):
        for b in (-hy, hy):
            for c in (-hz, hz):
                p = centre + tangent * a + right * b + Vector((0, 0, c))
                corners.append(bm.verts.new(p))
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
             (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for f in faces:
        bm.faces.new([corners[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_wall_colliders(road, idx, builder, lay):
    """Thick closed colliders for the bore walls.

    The walls never rise above the ground: where the tunnel is shallow the
    portal is in a cutting and the street runs over it.
    """
    path = [road.path[i] for i in idx]
    half = min(ROADWAY * 0.5, BORE_RADIUS - 0.6)
    for offset in bore_offsets(lay):
        for sign in (1.0, -1.0):
            x = sign * (half + 0.35) + offset

            def prof(i, _along, x=x, path=path):
                top = min(4.0, -path[i].z)
                return [(x - 0.3, -0.5), (x + 0.3, -0.5), (x + 0.3, top), (x - 0.3, top)]

            builder.add_named("concrete-colonly",
                             meshkit.sweep(bmesh.new(), prof, path, closed_profile=True),
                             surface="concrete")


def build_portal(road, builder, lay, at_end):
    """Concrete U-trough and a height-limit gantry at a tunnel portal."""
    s = 0.0 if at_end else road.length
    p, t, r, u, _ = road.at(s)
    half = min(ROADWAY * 0.5, BORE_RADIUS - 0.6)
    for offset in bore_offsets(lay):
        for sign in (1.0, -1.0):
            x = sign * (half + 0.35) + offset
            wall = [(x - 0.6, -0.2), (x + 0.6, -0.2), (x + 0.6, PORTAL_CLEARANCE),
                    (x - 0.6, PORTAL_CLEARANCE)]
            builder.add(CONCRETE, meshkit.sweep(bmesh.new(), wall, [p - t * 0.4, p + t * 0.4],
                                                closed_profile=False))
    lintel = [(-half - 1.0, PORTAL_CLEARANCE), (half + 1.0, PORTAL_CLEARANCE),
               (half + 1.0, PORTAL_LINTEL), (-half - 1.0, PORTAL_LINTEL)]
    builder.add(CONCRETE, meshkit.sweep(bmesh.new(), lintel, [p - t * 0.4, p + t * 0.4],
                                        closed_profile=False))
    bar = [(-half - 0.5, HEIGHT_LIMIT), (half + 0.5, HEIGHT_LIMIT),
           (half + 0.5, HEIGHT_LIMIT + 0.3), (-half - 0.5, HEIGHT_LIMIT + 0.3)]
    builder.add(STEEL, meshkit.sweep(bmesh.new(), bar, [p - t * 0.2, p + t * 0.2],
                                     closed_profile=False))
    return p


def build(road, idx, builder, lay=None):
    """All tunnel geometry for the given path samples."""
    lay = lay or profiles.layout(road)
    build_bores(road, idx, builder, lay)
    build_stripe(road, idx, builder, lay)
    build_luminaires(road, idx, builder, lay)
    build_fixtures(road, idx, builder, lay)
    build_wall_colliders(road, idx, builder, lay)
