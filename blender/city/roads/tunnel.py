"""Tunnel interiors (dossier §4).

Two Ø 11 m bores, one per carriageway, each centred on its carriageway:
7.5 m roadway + 0.3 m concrete kerbs. The walls are white enamel panels
(#ECEFF0) from 0.5 to 3.2 m with a 0.3 m colour stripe at 1.2 m and dark
concrete above; 1.2 m luminaires every 2.4 m at both ceiling corners, jet-fan
pairs every 250 m, lane-control signals every 150 m and a portal face with a
height-limit gantry.

The bore is a bore only where the ground covers it.  The depth of a path
sample is -road.path[i].z (the ground is at 0): under 0.3 m the road is a
street, between 0.3 m and 5.98 m it runs in an open trough (a wall on each
side of each carriageway, a parapet on the outer walls), deeper it is a bore.
"""
import math

import bmesh
from mathutils import Vector

from city.roads import meshkit, profiles, surface, tiles

ENAMEL = "Road_Tunnel_Enamel"
STRIPE = "Road_Tunnel_Stripe"
DARK = "Road_Tunnel_Dark"
LED = "Road_Led_Tunnel"
CONCRETE = "SH_concrete_pier"
STEEL = "Road_Steel_Girder"

BORE_RADIUS = 5.5
CLEARANCE = 4.5          # road surface to the crown of the bore
ROADWAY = 7.5            # the roadway of one bore
ENAMEL_LOW = 0.5
ENAMEL_HIGH = 3.2
STRIPE_LOW = 1.05
STRIPE_HIGH = 1.35
JET_FAN_SPACING = 250.0
SIGNAL_SPACING = 150.0
EXIT_SIGN_SPACING = 80.0
HEIGHT_LIMIT = 4.2
AT_GRADE_DEPTH = 0.3     # the road is a street until it is 0.3 m under the ground
COVER_DEPTH = 5.98       # the crown of the bore: from here the bore is under the ground
TROUGH_BOTTOM = -0.5     # the wall of the trough reaches this far under the road
PARAPET_HEIGHT = 1.0     # the parapet over the ground on the outer walls of the trough
FACE_THICK = 0.6         # the thickness of the face of a portal along the road


def kind_at(road, i, margin=0.0):
    """What the road is at a path sample: AT_GRADE, OPEN (the trough) or COVERED.

    The margin is the depth the sample keeps to the crown of the bore.
    """
    d = -road.path[i].z
    if d <= AT_GRADE_DEPTH + margin:
        return "AT_GRADE"
    if d < COVER_DEPTH + margin:
        return "OPEN"
    return "COVERED"


def split_by_depth(road, idx):
    """The runs of `idx` by depth: the kind of the road and its samples."""
    groups = []
    for i in idx:
        kind = kind_at(road, i)
        if groups and groups[-1][0] == kind:
            groups[-1][1].append(i)
        else:
            groups.append((kind, [i]))
    return groups


def _face(road, a, b):
    """The face of a portal: where the road crosses the depth of the crown.

    The bore fits under the ground from there and the trough runs from there.
    The face is the point of the road there, its frame, the depth and the
    two samples it lies between.
    """
    pa, pb = road.path[a], road.path[b]
    da, db = -pa.z, -pb.z
    t = 0.5 if abs(da - db) < 1e-9 else max(0.0, min(1.0, (da - COVER_DEPTH) / (da - db)))
    point = pa.lerp(pb, t)
    tangent = (pb - pa)
    if tangent.length < 1e-6:
        tangent = road.frames[a][0]
    tangent = tangent.normalized()
    right = tangent.cross(Vector((0.0, 0.0, 1.0)))
    if right.length < 1e-6:
        right = road.frames[a][1]
    return {"point": point, "tangent": tangent, "right": right.normalized(),
            "depth": -point.z, "a": a, "b": b}


def portal_faces(road):
    """The faces of the portals of a road: where the trough meets the bore."""
    out = []
    kinds = [kind_at(road, i) for i in range(len(road.path))]
    for n in range(1, len(kinds)):
        if kinds[n] == kinds[n - 1] or "COVERED" not in (kinds[n], kinds[n - 1]):
            continue
        out.append(_face(road, n - 1, n))
    return out


def bore_offsets(lay):
    """The centres of the two bores, across the road: one per carriageway."""
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
    """The profile split into three zones, each of them a list of separate pieces.

    A zone is not always one piece: the enamel of a bore is one zone in two
    pieces, the one on each wall.  The pieces are never joined to each other:
    the join would be a sheet across the carriageway, and the cars drive
    through it.
    """
    zones = [[], [], []]
    ends = [None, None, None]
    for i in range(len(points) - 1):
        for (p0, p1, zone) in _zone_segments(points[i], points[i + 1], h_low, h_high):
            piece = zones[zone]
            end = ends[zone]
            if not piece or end is None or abs(end[0] - p0[0]) > 1e-6 or abs(end[1] - p0[1]) > 1e-6:
                piece.append([p0])
            piece[-1].append(p1)
            ends[zone] = p1
    return zones


def _sweep(builder, material, prof, path, closed=False):
    builder.add(material, meshkit.sweep(bmesh.new(), prof, path, closed_profile=closed))


def build_bores(path, builder, lay):
    """The bores: the white enamel panels and the dark concrete above them.

    Every piece of a zone is swept on its own, so no sheet ever crosses the
    carriageway.
    """
    half = min(ROADWAY * 0.5, BORE_RADIUS - 0.6)
    for offset in bore_offsets(lay):
        zones = _zone_profiles(_bore_arc(half), ENAMEL_LOW, ENAMEL_HIGH)
        for zone, material in ((0, DARK), (1, ENAMEL), (2, DARK)):
            for poly in zones[zone]:
                if len(poly) < 2:
                    continue
                prof = [(x + offset, y) for (x, y) in poly]
                _sweep(builder, material, prof, path)


def build_stripe(path, builder, lay):
    """The 0.3 m colour stripe at 1.2 m on both walls of every bore."""
    half = min(ROADWAY * 0.5, BORE_RADIUS - 0.6)
    for offset in bore_offsets(lay):
        for sign in (1.0, -1.0):
            prof = [(sign * half + offset, STRIPE_LOW), (sign * half + offset, STRIPE_HIGH)]
            _sweep(builder, STRIPE, prof, path)


def bore_crown(half_width):
    """The height of the crown of a bore over its centre."""
    r = BORE_RADIUS
    a0 = math.acos(max(-1.0, min(1.0, half_width / r)))
    return CLEARANCE - r * math.sin(a0) + r


def build_luminaires(path, builder, lay):
    """1.2 m luminaires every 2.4 m at both ceiling corners."""
    half = min(ROADWAY * 0.5, BORE_RADIUS - 0.6)
    spring = CLEARANCE
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
    offsets = bore_offsets(lay)
    s = 0.0
    while s < road.length:
        j = road.index_at(s)
        if j in idx:
            p, r, t, u = (road.path[j], road.frames[j][1], road.frames[j][0],
                          road.frames[j][2])
            for offset in offsets:
                # a pair of jet fans, one on each side of the carriageway
                bm = bmesh.new()
                for sign in (1.0, -1.0):
                    _jet_fan(bm, p + r * (offset + sign * 1.9) + u * (crown - 0.7), r, t, u)
                builder.add(STEEL, bm)
        s += JET_FAN_SPACING
    for spacing, height, size, material in ((SIGNAL_SPACING, 2.6, (0.3, 0.2, 0.5), DARK),
                                            (EXIT_SIGN_SPACING, 2.9, (0.1, 0.5, 0.3), LED)):
        s = 0.0
        while s < road.length:
            j = road.index_at(s)
            if j in idx:
                p, r, t = (road.path[j], road.frames[j][1], road.frames[j][0])
                for offset in offsets:
                    bm = bmesh.new()
                    _box(bm, p + r * (offset + half - 0.2) + Vector((0, 0, height)),
                         r, t, *size)
                    builder.add(material, bm)
            s += spacing


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


def build_wall_colliders(path, builder, lay):
    """Thick closed colliders for the bore walls.

    The walls of the bore stay inside the bore: they hold the shoulder of the
    road and they never rise above the ground.
    """
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


def build_trough(path, builder, lay):
    """The open trough: the walls that hold the ground beside the road.

    The wall stands where the wall of the bore stands (the ground of the game
    is cut exactly between them) and it goes from under the road up to the
    ground.  The outer wall goes on up to a parapet 1 m over the ground: a car
    on the street must not fall into the trough.
    """
    half = min(ROADWAY * 0.5, BORE_RADIUS - 0.6)
    for offset in bore_offsets(lay):
        for sign in (1.0, -1.0):
            x = sign * (half + 0.35) + offset
            parapet = PARAPET_HEIGHT if sign * offset > 0.0 else 0.0

            def prof(i, _along, x=x, parapet=parapet, path=path):
                top = -path[i].z + parapet
                return [(x - 0.3, TROUGH_BOTTOM), (x + 0.3, TROUGH_BOTTOM),
                        (x + 0.3, top), (x - 0.3, top)]

            builder.add_named("concrete-colonly",
                              meshkit.sweep(bmesh.new(), prof, path, closed_profile=True),
                              surface="concrete")
            builder.add(CONCRETE,
                        meshkit.sweep(bmesh.new(), prof, path, closed_profile=True))


def build_portal(road, builder, lay, face):
    """The face of a portal and the height-limit gantry in front of it.

    The face is a beam across each carriageway that closes the trough where it
    meets the bore: a car on the ground over the bore must not drive into the
    trough.  The gantry tells the driver how high he may go.
    """
    p, t, r, d = face["point"], face["tangent"], face["right"], face["depth"]
    half = min(ROADWAY * 0.5, BORE_RADIUS - 0.6)
    bottom = max(d - 0.3, 5.0)
    top = d + PARAPET_HEIGHT
    for offset in bore_offsets(lay):
        # the face runs from the inner wall to the outer one
        side = 1.0 if offset > 0.0 else -1.0
        reach = half + 0.35 + 0.3
        x0, x1 = offset - side * reach, offset + side * reach
        mid = (x0 + x1) * 0.5
        beam = p + r * mid + Vector((0.0, 0.0, (bottom + top) * 0.5))
        bm = bmesh.new()
        _box(bm, beam, r, t, FACE_THICK, abs(x1 - x0), top - bottom)
        builder.add_named("concrete-colonly", bm, surface="concrete")
        drawn = bmesh.new()
        _box(drawn, beam, r, t, FACE_THICK, abs(x1 - x0), top - bottom)
        builder.add(CONCRETE, drawn)
        bar = p + r * mid + Vector((0.0, 0.0, HEIGHT_LIMIT + 0.15))
        gantry = bmesh.new()
        _box(gantry, bar, r, t, 0.3, abs(x1 - x0), 0.3)
        builder.add(STEEL, gantry)


def build(road, idx, builder, lay=None, excluded=None):
    """All tunnel geometry for the given path samples.

    The depth of every sample decides what the road is there."""
    lay = lay or profiles.layout(road)
    excluded = excluded or set()
    # the floor of the road: the asphalt of a street, in the bore and in the trough
    surface.build_asphalt(road, idx, builder, lay)
    faces = portal_faces(road)
    for kind, run in split_by_depth(road, idx):
        for sub in tiles.split_runs(run, excluded):
            path = [road.path[i] for i in sub]
            # the trough and the bore meet at the face of a portal: both of
            # them hold the point of the face, their meshes meet there
            for face in faces:
                if face["b"] == sub[0]:
                    path.insert(0, face["point"])
                if face["a"] == sub[-1]:
                    path.append(face["point"])
            if kind == "COVERED":
                build_bores(path, builder, lay)
                build_stripe(path, builder, lay)
                build_luminaires(path, builder, lay)
                build_fixtures(road, sub, builder, lay)
                build_wall_colliders(path, builder, lay)
            elif kind == "OPEN":
                build_trough(path, builder, lay)
