"""Elevated decks, ramps and bridge decks.

Section (SHANGHAI_DOSSIER §2.2): slab, a 0.25 m drip face, a cantilever wing
underside (max 3.5 m, 0.25 of the deck width) sloping from -0.25 at the tip to
-0.45 at the root, a web down to the 60 % bottom flange at -2.0. Only the two
wing undersides carry the blue soffit shader; the webs, the flange and the drip
faces are plain concrete, and an LED tube runs under each drip edge.
"""
import bmesh

from mathutils import Vector

from city.roads import collision, meshkit, planters, profiles, tiles

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
CHEVRON_SPACING = 6.0
CHEVRON_WIDTH = 0.45
CHEVRON_SKEW = 0.45     # the 45 degree skew of the bars
CUSHION_LENGTH = 3.2   # the crash cushion at the nose of the gore
CUSHION_WIDTH = 1.6


def build_chevrons(tileset, rows):
    """The 45 degree bars of the gore: they stay inside the wedge."""
    step = max(1, int(CHEVRON_SPACING / max(0.5, _wedge_length(rows) / max(1, len(rows) - 1))))
    for i in range(0, len(rows) - 1, step):
        (pa, ra, _d, along) = rows[i]
        (pb, rb, _e, _b) = rows[i + 1]
        if along.length < 0.2:
            continue
        along = along.normalized() * CHEVRON_WIDTH
        across = ra - pa
        if across.length < 0.6:
            continue
        # the bar is skewed by 45 degrees: it runs across the wedge and forward
        skew = along.normalized() * CHEVRON_SKEW
        width = across.normalized() * min(across.length - 0.4, 2.4)
        bm = bmesh.new()
        v0 = bm.verts.new(pa + skew * 0.5)
        v1 = bm.verts.new(pa + width + skew * 0.5)
        v2 = bm.verts.new(pb + width - skew * 0.5)
        v3 = bm.verts.new(pb - skew * 0.5)
        bm.faces.new((v0, v1, v2, v3))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        tileset.builder_at((pa + pb) * 0.5).add("SH_road_marking_white", bm)


def _wedge_length(rows):
    """The length of the gore's wedge."""
    total = 0.0
    for (pa, _ra, _d, _a), (pb, _rb, _e, _b) in zip(rows, rows[1:]):
        total += (pb - pa).length
    return total


def build_cushion(tileset, rows):
    """The crash cushion at the nose of the gore."""
    if not rows:
        return
    pa, _ra, across, along = rows[0]
    if along.length < 0.05:
        return
    along = along.normalized()
    bm = bmesh.new()
    v0 = bm.verts.new(pa + along * 0.2)
    v1 = bm.verts.new(pa + across * CUSHION_WIDTH + along * 0.2)
    v2 = bm.verts.new(pa + across * CUSHION_WIDTH - along * (CUSHION_LENGTH - 0.2))
    v3 = bm.verts.new(pa - along * (CUSHION_LENGTH - 0.2))
    bm.faces.new((v0, v1, v2, v3))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    tileset.builder_at(pa).add("SH_concrete_pier", bm)


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


def split_by_kind(road, idx, gaps, side):
    """The runs of path indices that are not in a gap, each with its kind.

    A run is "kerb" where a lane of the city runs under the edge of the deck:
    the parapet is low there, so the car of that lane passes it.  Everywhere
    else the parapet is the full one.
    """
    gap = gaps.get(side, ())
    kerb = gaps.get(side + "_kerb", ())
    out = []
    cur = []
    kind = None
    for i in idx:
        s = road.dist[i]
        if any(a <= s <= b for (a, b) in gap):
            if len(cur) > 1:
                out.append((cur, kind))
            cur = []
            kind = None
            continue
        k = "kerb" if any(a <= s <= b for (a, b) in kerb) else "full"
        if kind is None:
            kind = k
        elif k != kind:
            if len(cur) > 1:
                out.append((cur, kind))
            cur = []
            kind = k
        cur.append(i)
    if len(cur) > 1:
        out.append((cur, kind))
    return out


def build_parapets(road, idx, builder, lay, gaps=None):
    """The parapet on both edges of the deck.

    A ramp that leaves the road needs the parapet to give way: it would wall
    the ramp off.  The gaps are per side: only the side the ramp is on gives
    way, and the collider of the parapet is cut on the same gaps.

    Where a lane of the city runs under the edge of the deck the parapet is
    low: the car of that lane has to pass it, and the deck is fenced all the
    same.
    """
    style = road.style.get("parapet", "planter")
    if style == "none":
        return
    gaps = gaps or {}
    for side in ("fwd", "back"):
        mirror = side == "back"
        edge = lay["asphalt_fwd"] if side == "fwd" else lay["asphalt_back"]
        for run, kind in split_by_kind(road, idx, gaps, side):
            base = (profiles.low_parapet_profile() if kind == "kerb"
                    else profiles.parapet_profile())
            if mirror:
                prof = [(edge - x, z) for (x, z) in reversed(base)]
            else:
                prof = [(edge + x, z) for (x, z) in base]
            _sweep(builder, PARAPET, prof, [road.path[i] for i in run], closed=False)


def build_median(road, idx, builder, lay, gaps=None):
    """Median barrier on an elevated deck.

    The traffic of a ramp attach crosses the median, so the barrier gives way
    there: the same gaps cut the visible barrier and its collider.
    """
    if lay["median_half"] <= 0.0:
        return
    prof = profiles.median_barrier_profile(lay["median_half"])
    for run in split_by_gaps(road, idx, (gaps or {}).get("median", ())):
        _sweep(builder, PARAPET, prof, [road.path[i] for i in run])


def build_details(road, tileset, lay, gaps=None):
    """The expansion joints, the scuppers and the planted strip of a road.

    They are built in one pass over the whole road (not per tile run), so a
    joint or a pot is never built twice at a tile border.
    """
    gaps = gaps or {}
    # the planter row stands on the parapet: where the parapet is low there is
    # no room for it
    low = dict(gaps)
    for side in ("fwd", "back"):
        low[side] = list(gaps.get(side, ())) + list(gaps.get(side + "_kerb", ()))
    build_joints(road, tileset, lay)
    build_scuppers(road, tileset, lay)
    planters.build_pots(road, tileset, lay, low)
    planters.build_strip(road, tileset, lay, low)


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


TAPER_LENGTH = 150.0   # the acceleration lane before the attach
TAPER_WIDTH = 6.0      # the widening at the nose (150 m at 1:25)
STRIP_CLEAR = 4.0      # the fence of a strip keeps this far away from a ramp


def strip_rows(city, ramp, at_end):
    """The rows of the acceleration strip of one attach.

    The strip is the deck of the parent widened over the last 150 m before the
    attach (1:25), so the traffic of the ramp has a lane to speed up in.  Every
    row is (station, inner edge, outer edge, width) of the parent.
    """
    attach = ramp.data.get("attach_end" if at_end else "attach_start")
    parent = city.by_id.get(attach["road"])
    if parent is None:
        return None, [], 0.0
    lay_parent = profiles.layout(parent)
    r_index = len(ramp.path) - 1 if at_end else 0
    r_pt = ramp.path[r_index]
    _dist, pidx = parent.nearest(r_pt)
    s_attach = parent.dist[pidx]
    # the ramp runs along the parent's right or its left: the widening is on
    # that side and it ends at the attach in the traffic's direction
    p_r = parent.frames[pidx][1]
    if (r_pt - parent.path[pidx]).dot(p_r) > 0.0:
        edge, out = lay_parent["asphalt_fwd"], 1.0
    else:
        edge, out = lay_parent["asphalt_back"], -1.0
    rows = []
    for i in range(len(parent.path)):
        d = (parent.dist[i] - s_attach) * out
        if d > 0.0 or d < -TAPER_LENGTH:
            continue
        grow = TAPER_WIDTH * min(1.0, max(0.0, (d + TAPER_LENGTH) / TAPER_LENGTH))
        p = parent.path[i]
        r = parent.frames[i][1]
        rows.append((parent.dist[i], p + r * edge, p + r * (edge + out * grow), grow))
    return parent, rows, out


def build_acceleration(city, road, tileset, lay):
    """The acceleration lane: the parent's deck widens over the last 150 m.

    The widening is 1:25 (6 m over 150 m), so the traffic of the ramp has a
    lane to speed up in before it joins the parent.  It lies on the side of
    the parent the ramp runs along and it ends at the attach, so it is also
    drivable: it gets a collision surface of its own.  That surface follows
    the height of the parent, so it is dropped where the strip stands over
    the ramp's own lane: there it would be a roof over that lane.
    """
    for at_end, key in ((True, "attach_end"), (False, "attach_start")):
        attach = road.data.get(key)
        if not attach:
            continue
        parent, rows, _out = strip_rows(city, road, at_end)
        if parent is None or len(rows) < 2:
            continue
        # The strip runs along the ramp's lane at the parent's height: where
        # the two overlap in plan the strip would roof the ramp's lane, so
        # the quad gets no collider there.  Only a step is dropped: a strip
        # that stands more than a car's height above the ramp's lane is a
        # roof the car passes under.  The asphalt stays: only the collider
        # is dropped.
        grid = collision.lane_grid(city)
        for i in range(len(rows) - 1):
            _st, inner0, outer0, _g0 = rows[i]
            _st, inner1, outer1, _g1 = rows[i + 1]
            mid = (inner0 + inner1) * 0.5
            quad = [inner0, outer0, outer1, inner1]
            collide = not collision.roofs_lane(quad, grid, (), collision.CAR_HALF_LEN)
            collision.pave(tileset.builder_at(mid), inner0, outer0, outer1, inner1,
                           collide=collide)


def build_strip_parapets(city, road, tileset, lay):
    """The parapet on the outer edge of the acceleration strips of a road.

    The strip is the deck of the parent widened over the last 150 m before the
    attach, so its outer edge is the edge of the deck there: it needs a
    parapet like the deck's own edge, or the strip is a lane that ends in
    thin air.  The strips of one road can overlap (two ramps attach on the
    same side), so the fence follows the outermost edge of all of them.  It
    stops where the deck of a ramp stands there: from that point on the
    ramp's own parapet is the fence.
    """
    if not road.elevated:
        return
    sides = {"fwd": [], "back": []}
    for ramp in city.roads:
        if ramp.kind != "ramp":
            continue
        for at_end, key in ((True, "attach_end"), (False, "attach_start")):
            attach = ramp.data.get(key)
            if not attach or attach.get("road") != road.id:
                continue
            parent, rows, out = strip_rows(city, ramp, at_end)
            if parent is None or len(rows) < 2:
                continue
            sides["fwd" if out > 0.0 else "back"].append((ramp, rows, parent))
    for side, lst in sides.items():
        edge = (lay["asphalt_fwd"] if side == "fwd" else lay["asphalt_back"])
        out = 1.0 if side == "fwd" else -1.0
        cross = _crossings(city, lst, edge, out)
        for path in _strip_fences(lst, cross):
            builder = tileset.builder_at(path[0])
            prof = profiles.parapet_profile()
            if side == "back":
                prof = [(-x, z) for (x, z) in reversed(prof)]
            builder.add(PARAPET, meshkit.sweep(bmesh.new(), prof, path, closed_profile=False))
            collision.build_edge_barrier(builder, path, side == "back")


def _crossings(city, lst, edge, out):
    """The stations where the traffic of an attach crosses the outer edge of
    the acceleration strips of one side.

    The fence of the strip has to give way there: the traffic of the attach
    crosses the strip on its way from the road to the ramp.
    """
    out_st = []
    for (lane, lo, hi, cells) in collision.lane_index(city):
        if not lane.get("connector"):
            continue
        for (ramp, rows, parent) in lst:
            if ramp.id != lane.get("road"):
                continue
            for p in lane["points"]:
                q = Vector((p[0], -p[2], p[1]))
                lateral, station, height = collision.plan_offset(parent, q)
                grow = _grow_at(rows, station)
                if grow is None:
                    continue
                if abs(lateral - (edge + out * grow)) < 2.0:
                    out_st.append(station)
    return out_st


def _grow_at(rows, station):
    """The width of the strip at a station of its road."""
    for (st, _inner, _outer, grow) in rows:
        if abs(st - station) < 3.0:
            return grow
    return None


def _strip_fences(lst, cross=()):
    """The fences along the outer edges of the acceleration strips of one side.

    The widest strip wins at every station, so the fence never stands in the
    paved area of another strip.  Where the deck of a ramp stands there, the
    ramp's own parapet is the fence and the fence of the strip stops.  The
    fence gives way where the traffic of the attach crosses it.
    """
    ramps = [ramp for (ramp, _rows, _parent) in lst]
    best = {}
    for (ramp, rows, _parent) in lst:
        for (st, _inner, outer, grow) in rows:
            key = round(st, 2)
            if key not in best or grow > best[key][0]:
                best[key] = (grow, outer)
    runs = []
    cur = []
    last = None
    for st in sorted(best):
        outer = best[st][1]
        if _over_any(ramps, outer) or any(abs(st - c) < 2.0 for c in cross):
            if len(cur) > 1:
                runs.append(cur)
            cur = []
            last = st
            continue
        if last is not None and st - last > 20.0:
            if len(cur) > 1:
                runs.append(cur)
            cur = []
        cur.append(outer)
        last = st
    if len(cur) > 1:
        runs.append(cur)
    return runs


def _over_any(ramps, outer):
    """True when the outer edge of a strip comes too close to a ramp.

    The fence of the strip may not stand in the lane of a ramp: the ramp's own
    parapet is the fence from that point on.  The distance is generous, so the
    fence stops well before the ramp and never in front of a car.
    """
    for ramp in ramps:
        if collision.over_corridor(ramp, [outer], STRIP_CLEAR):
            return True
    return False


def build_cable_anchors(road, tileset, lay):
    """`CableAnchor_*` sockets on both edges of a cable-stayed bridge deck."""
    if not road.bridge:
        return
    offset = road.lanes_fwd * road.lane_width * 0.5 + road.median * 0.5 + 1.0
    s = 0.0
    while s <= road.length:
        j = road.index_at(s)
        p = road.path[j]
        r = road.frames[j][1]
        u = road.frames[j][2]
        builder = tileset.builder_at(p)
        for sign in (1.0, -1.0):
            name = "CableAnchor_%s_%d" % (road.id, int(s))
            builder.empty(name, p + r * (sign * offset) + u * 0.35, direction=u,
                          props={"kind": "cable_anchor", "road": road.id,
                                 "side": "right" if sign > 0 else "left",
                                 "distance_m": round(s, 1)})
        s += 9.6


def build(road, idx, builder, lay=None, gaps=None):
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
    build_median(road, idx, builder, lay, gaps)
