"""Elevated decks, ramps and bridge decks.

Section (SHANGHAI_DOSSIER §2.2): slab, a 0.25 m drip face, a cantilever wing
underside (max 3.5 m, 0.25 of the deck width) sloping from -0.25 at the tip to
-0.45 at the root, a web down to the 60 % bottom flange at -2.0. Only the two
wing undersides carry the blue soffit shader; the webs, the flange and the drip
faces are plain concrete, and an LED tube runs under each drip edge.
"""
import bmesh

from mathutils import Vector

from city.roads import meshkit, planters, profiles, tiles

ASPHALT = "SH_wet_asphalt"
STRUCT = "SH_concrete_pier"
SOFFIT = "SH_soffit_blue"
PARAPET = "SH_concrete_barrier"
LED = "Road_Led_Soffit"
JOINT = "Road_Expansion_Joint"
STEEL = "Road_Steel_Girder"
LED_BRIDGE = "Road_Led_Bridge"

WING_WIDTH = 3.5         # max cantilever wing (dossier §2.2)
WING_TIP_Z = -0.25       # the wing tip, just under the drip face
WING_ROOT_Z = -0.45      # the wing root
LED_TUBE = 0.06          # the LED tube under the drip edge
LED_OFFSET = 0.15        # inboard of the deck edge
LED_ENERGY = 4.5         # dossier §2.3 emission tier E3
SCUPPER_SPACING = 15.0
SCUPPER_SIZE = (0.25, 0.08, 0.18)


def section(half):
    """(wing width, flange half width) of the deck section."""
    width = half * 2.0
    return min(WING_WIDTH, width * 0.25), half * profiles.FLANGE


def girder_profile(half, depth=profiles.GIRDER_DEPTH):
    """Closed outline of the girder (slab, drip, wing, web, flange)."""
    wing, flange = section(half)
    return [(-half, 0.0), (half, 0.0), (half, WING_TIP_Z), (half - wing, WING_ROOT_Z),
            (flange, -depth), (-flange, -depth), (-(half - wing), WING_ROOT_Z),
            (-half, WING_TIP_Z)]


def structure_ribbons(half, depth=profiles.GIRDER_DEPTH):
    """The concrete ribbons of the girder: everything except the wing undersides."""
    wing, flange = section(half)
    return [
        [(-half, 0.0), (half, 0.0), (half, WING_TIP_Z)],
        [(half - wing, WING_ROOT_Z), (flange, -depth)],
        [(flange, -depth), (-flange, -depth)],
        [(-flange, -depth), (-(half - wing), WING_ROOT_Z)],
        [(-half, WING_TIP_Z), (-half, 0.0)],
    ]


def wing_columns(half):
    """The two wing underside strips: [(columns, v_at_first, v_at_second)].

    v = 0 at the left drip edge, 0.5 at the wing roots, 1 at the right drip edge:
    the soffit shader draws its LED strips at v = 0 and v = 1.
    """
    wing, _flange = section(half)
    return [([(-half, WING_TIP_Z), (-(half - wing), WING_ROOT_Z)], 0.0, 0.5),
            ([(half - wing, WING_ROOT_Z), (half, WING_TIP_Z)], 0.5, 1.0)]


def _sweep(builder, material, prof, path, closed=True):
    builder.add(material, meshkit.sweep(bmesh.new(), prof, path, closed_profile=closed))


def build_asphalt(road, idx, builder, lay):
    """Asphalt for both carriageways of a deck."""
    path = [road.path[i] for i in idx]
    frames = [road.frames[i] for i in idx]
    for side in ("back", "fwd"):
        tmpl = profiles.carriageway_template(road, lay, side)
        bm = bmesh.new()
        meshkit.strip(bm, path, frames, tmpl)
        builder.add(ASPHALT, bm)


def build_structure(road, idx, builder, lay):
    """The concrete girder under the carriageway (webs, flange, drip faces)."""
    path = [road.path[i] for i in idx]
    for prof in structure_ribbons(lay["half_width"]):
        _sweep(builder, STRUCT, prof, path, closed=False)


def build_soffit(road, idx, builder, lay):
    """The two wing undersides: the only blue part of the deck."""
    path = [road.path[i] for i in idx]
    frames = [road.frames[i] for i in idx]
    along = [road.dist[i] for i in idx]
    for (columns, v0, v1) in wing_columns(lay["half_width"]):
        bm = bmesh.new()
        meshkit.strip_columns(bm, path, frames, columns, [v0, v1], along)
        builder.add(SOFFIT, bm)


def build_led(road, idx, builder, lay):
    """The LED tube under each drip edge."""
    path = [road.path[i] for i in idx]
    half = lay["half_width"]
    z0 = WING_TIP_Z - 0.07
    z1 = WING_TIP_Z - 0.01
    for side in (1.0, -1.0):
        x = side * (half - LED_OFFSET)
        prof = [(x - LED_TUBE * 0.5, z0), (x + LED_TUBE * 0.5, z0),
                (x + LED_TUBE * 0.5, z1), (x - LED_TUBE * 0.5, z1)]
        _sweep(builder, LED, prof, path)


def split_by_gaps(road, idx, gaps):
    """The runs of path indices that are not inside a gap (a ramp attach)."""
    if not gaps:
        return [idx]
    out = []
    cur = []
    for i in idx:
        s = road.dist[i]
        if any(a <= s <= b for (a, b) in gaps):
            if len(cur) > 1:
                out.append(cur)
            cur = []
        else:
            cur.append(i)
    if len(cur) > 1:
        out.append(cur)
    return out


def build_parapets(road, idx, builder, lay, gaps=()):
    """The parapet on both edges of the deck.

    A ramp that leaves the road needs the parapet to give way: it would wall
    the ramp off.
    """
    style = road.style.get("parapet", "planter")
    if style == "none":
        return
    for side in ("fwd", "back"):
        mirror = side == "back"
        edge = lay["asphalt_fwd"] if side == "fwd" else lay["asphalt_back"]
        prof = [(edge - x if mirror else edge + x, z)
                for (x, z) in (reversed(profiles.parapet_profile()) if mirror
                               else profiles.parapet_profile())]
        for run in split_by_gaps(road, idx, gaps):
            _sweep(builder, PARAPET, prof, [road.path[i] for i in run], closed=False)


def build_median(road, idx, builder, lay):
    """Median barrier on an elevated deck."""
    if lay["median_half"] <= 0.0:
        return
    path = [road.path[i] for i in idx]
    prof = profiles.median_barrier_profile(lay["median_half"])
    _sweep(builder, PARAPET, prof, path)


def build_details(road, tileset, lay, gaps=()):
    """The expansion joints, the scuppers and the planted strip of a road.

    They are built in one pass over the whole road (not per tile run), so a
    joint or a pot is never built twice at a tile border.
    """
    build_joints(road, tileset, lay)
    build_scuppers(road, tileset, lay)
    planters.build_pots(road, tileset, lay, gaps)
    planters.build_strip(road, tileset, lay, gaps)


def build_joints(road, tileset, lay):
    """The expansion joints: a steel strip across the carriageway every 30 m."""
    spacing = max(5.0, road.pier_spacing)
    s = 0.0
    while s <= road.length:
        j = road.index_at(s)
        p = road.path[j]
        r = road.frames[j][1]
        t = road.frames[j][0]
        z = road.path[j].z
        bm = bmesh.new()
        geo_box(bm, p, (0.30, lay["asphalt_half"] * 2.0, 0.012), r, t, z - 0.004, z + 0.008)
        tileset.builder_at(p).add_named("joint_%s" % road.id, bm,
                                        material=JOINT, surface="steel")
        s += spacing


def build_scuppers(road, tileset, lay):
    """The drainage outlets on the drip face, every 15 m."""
    s = 0.0
    while s <= road.length:
        j = road.index_at(s)
        p = road.path[j]
        r = road.frames[j][1]
        t = road.frames[j][0]
        bm = bmesh.new()
        for side in (1.0, -1.0):
            x = side * (lay["half_width"] - 0.04)
            centre = p + r * x
            geo_box(bm, centre, SCUPPER_SIZE, r, t, WING_TIP_Z - 0.20, WING_TIP_Z - 0.02)
        tileset.builder_at(p).add_named("scupper_%s" % road.id, bm,
                                        material=JOINT, surface="steel")
        s += SCUPPER_SPACING


def geo_box(bm, centre, size, right, tangent, z0=None, z1=None):
    """A box in the road frame at ABSOLUTE heights z0..z1 (size = along, across, up)."""
    hx, hy = size[0] * 0.5, size[1] * 0.5
    if z0 is None:
        z0 = centre.z - size[2] * 0.5
        z1 = centre.z + size[2] * 0.5
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


def build_bridge_edges(road, idx, builder, lay):
    """Nanpu-style steel edge girders (2.5 m) and the blue deck edge light line."""
    path = [road.path[i] for i in idx]
    for side in ("fwd", "back"):
        edge = lay["asphalt_fwd"] if side == "fwd" else lay["asphalt_back"]
        out = 1.0 if side == "fwd" else -1.0
        inner = edge - out * 1.20
        outer = edge
        g = [(inner, -2.50), (outer, -2.50), (outer, -0.60), (inner, -0.60)]
        _sweep(builder, STEEL, g, path)
        led = [(outer, -0.38), (outer + out * 0.08, -0.38),
               (outer + out * 0.08, -0.12), (outer, -0.12)]
        _sweep(builder, LED_BRIDGE, led, path)


def build(road, idx, builder, lay=None, gaps=()):
    """All elevated geometry for the given path samples."""
    lay = lay or profiles.layout(road)
    build_asphalt(road, idx, builder, lay)
    if road.bridge:
        half = lay["half_width"]
        _sweep(builder, STRUCT, [(-half, 0.0), (half, 0.0), (half, -0.60), (-half, -0.60)],
               [road.path[i] for i in idx])
        build_bridge_edges(road, idx, builder, lay)
    else:
        build_structure(road, idx, builder, lay)
        build_soffit(road, idx, builder, lay)
        build_led(road, idx, builder, lay)
    build_parapets(road, idx, builder, lay, gaps)
    build_median(road, idx, builder, lay)
