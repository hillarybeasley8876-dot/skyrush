"""Ramp attaches: the gore, the acceleration lane, the chevrons and the cushion.

A ramp leaves its parent road at a gore: the paved wedge between the parent's
outer edge and the ramp's own edge. The parent's deck widens over the last
150 m before the attach (1:25), so the traffic has an acceleration lane, and
the gore itself carries the 45 degree chevrons of a Chinese expressway.

The gore is where the two decks meet, and the traffic of the attach crosses it
on a connector lane. So the gore carries a collision surface of its own: both
edges are taken in their own road's frame, so the wedge lies on the decks
without a step, and a collider just under the visible asphalt keeps the car on
the road at the joint.

The parent's parapet and its planter row are cut over the attach: they would
otherwise wall the ramp off.
"""
import bmesh
import contextlib
import io

from mathutils import Vector

from city.roads import collision, lanes as lane_graph, profiles

ASPHALT = "SH_wet_asphalt"
WHITE = "SH_road_marking_white"
CONCRETE = "SH_concrete_pier"

GORE_LENGTH = 45.0     # how far the gore reaches back from the attach
TAPER_LENGTH = 150.0   # the acceleration lane before the attach
TAPER_WIDTH = 6.0      # the widening at the nose (150 m at 1:25)
TAPER_TAIL = 40.0      # the gore closes again after the attach
CHEVRON_SPACING = 6.0
CHEVRON_WIDTH = 0.45
CHEVRON_SKEW = 0.45     # the 45 degree skew of the bars
CUSHION_LENGTH = 3.2   # the crash cushion at the nose of the gore
CUSHION_WIDTH = 1.6
RIBBON_SHIFT = 1.0     # the connector strip is a step ahead of its lane

_GORES = {}            # id(road) -> road: the gores of a road are built once
_LANE_GRAPH = {}       # id(city) -> (city, lane graph): the graph is built once


def _gore_built(road):
    """True when the gores of this road have been built already.

    The build calls build_gore once per attach and the function builds the
    gores of both ends, so without this the gore would be built twice.
    """
    if id(road) in _GORES:
        return True
    _GORES[id(road)] = road
    return False


def _lane_graph_of(city):
    """The lane graph of the city, built once.

    The connector lanes of the attaches are the curves the traffic takes over
    the joint, so the joint needs a surface under them.
    """
    entry = _LANE_GRAPH.get(id(city))
    if entry is not None:
        return entry[1]
    quiet = io.StringIO()
    with contextlib.redirect_stdout(quiet):
        data = lane_graph.build_lanes(city)
    _LANE_GRAPH[id(city)] = (city, data)
    return data


def attach_point(city, road, attach):
    """(parent road, parent point, parent right, ramp end point, ramp right).

    `attach_end` is the end of the ramp's path, `attach_start` its beginning
    (the same convention as load.py and lane_links.py).
    """
    parent = city.by_id.get(attach["road"])
    if parent is None:
        return None
    r_index = len(road.path) - 1 if attach.get("end") else 0
    r_pt = road.path[r_index]
    _dist, pidx = parent.nearest(r_pt)
    p_pt = parent.path[pidx]
    p_r = parent.frames[pidx][1]
    r_r = road.frames[r_index][1]
    return parent, p_pt, p_r, r_pt, r_r


def _gore_stations(road, at_end, lay):
    """The gore's two edge polylines (parent edge, ramp edge) from the attach."""
    total = road.length
    stations = []
    steps = 12
    for i in range(steps + 1):
        d = GORE_LENGTH * i / steps
        s = (total - d) if at_end else d
        j = road.index_at(s)
        stations.append((road.path[j], road.frames[j][1], road.frames[j][0]))
    return stations


def _edge_offset(lay, right):
    """The offset of a road's outer edge: on its right or on its left."""
    return lay["asphalt_fwd"] if right else lay["asphalt_back"]


def _gore_rows(parent, road, at_end, lay):
    """The gore's two edge polylines: the parent's edge and the ramp's edge.

    The gore is the paved wedge between the two decks, so its edges are taken
    in the frame of the road they belong to: the parent's outer edge on the
    ramp's side and the ramp's edge that faces the parent.  Both frames are
    horizontal, so the wedge lies on the decks without a step.

    Every row carries the two directions of the gore: `across` points from the
    parent to the ramp, `along` points into the gore, away from the attach.
    """
    parent_lay = profiles.layout(parent)
    rows = []
    for (rp, rr, rt) in _gore_stations(road, at_end, lay):
        _dist, pidx = parent.nearest(rp)
        pp = parent.path[pidx]
        p_r = parent.frames[pidx][1]
        to_ramp = rp - pp
        direction = Vector((to_ramp.x, to_ramp.y, 0.0))
        if direction.length < 0.05:
            continue
        direction.normalize()
        # the parent's outer edge on the ramp's side
        p_off = _edge_offset(parent_lay, direction.dot(p_r) > 0.0)
        parent_edge = pp + p_r * p_off
        # the ramp's edge that faces the parent
        r_off = _edge_offset(lay, -direction.dot(rr) > 0.0)
        ramp_edge = rp + rr * r_off
        # into the gore, away from the attach
        along = Vector((rt.x, rt.y, 0.0))
        if along.length < 0.05:
            continue
        along.normalize()
        if at_end:
            along = -along
        rows.append((parent_edge, ramp_edge, direction, along))
    return rows


def _quad(pa, ra, rb, pb, drop=0.0):
    """One quad of the gore: the parent's edge, the ramp's edge and back.

    The normal of the quad points up: a collider is one sided, so a car that
    is below it would fall through it.
    """
    bm = bmesh.new()
    verts = []
    for p in (pa, ra, rb, pb):
        v = bm.verts.new(p)
        v.co.z -= drop
        verts.append(v)
    face = bm.faces.new(verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if face.normal.z < 0.0:
        face.normal_flip()
    return bm


def _pave(builder, pa, ra, rb, pb):
    """The visible asphalt of a quad and the collision surface under it."""
    builder.add(ASPHALT, _quad(pa, ra, rb, pb))
    builder.add_named(collision.SURFACE_NAME, _quad(pa, ra, rb, pb, drop=collision.SURFACE_DROP),
                      surface="asphalt")


def build_gore(city, road, tileset, lay):
    """The paved gore at the ramp's attach to its parent road.

    The gore is where the traffic of the attach crosses from the parent to
    the ramp, so it gets a collision surface: the same quads as the visible
    asphalt, dropped a centimetre under it.
    """
    if _gore_built(road):
        return
    for at_end, key in ((True, "attach_end"), (False, "attach_start")):
        attach = road.data.get(key)
        if not attach:
            continue
        found = attach_point(city, road, dict(attach, end=at_end))
        if found is None:
            continue
        parent = found[0]
        rows = _gore_rows(parent, road, at_end, lay)
        if len(rows) < 2:
            continue
        # every quad goes into the tile it lies on: the gore can be far from the
        # end of the ramp when the ramp does not reach its parent
        for i in range(len(rows) - 1):
            pa, ra, _d, _a = rows[i]
            pb, rb, _e, _b = rows[i + 1]
            mid = (pa + pb) * 0.5
            _pave(tileset.builder_at(mid), pa, ra, rb, pb)
        _build_chevrons(tileset, rows)
        _build_cushion(tileset, rows)
    build_connectors(city, road, tileset, lay)


def build_connectors(city, road, tileset, lay):
    """The collision surface under the connector lanes of the ramp's attaches.

    A connector lane is the curve the traffic takes from the parent to the
    ramp.  It crosses the wedge between the two decks, where there is no
    asphalt at all: without a surface of its own the car falls through the
    world at the joint.
    """
    for lane in _lane_graph_of(city)["lanes"]:
        if lane.get("road") != road.id or not lane["id"].startswith("attach_"):
            continue
        _ribbon(tileset, lane)


def _ribbon(tileset, lane):
    """A collision strip under one connector lane."""
    pts = [Vector((p[0], -p[2], p[1])) for p in lane["points"]]
    if len(pts) < 2:
        return
    half = max(1.0, float(lane.get("width", 3.5)) * 0.5)
    stations = []
    for i, p in enumerate(pts):
        if i == 0:
            step = pts[1] - pts[0]
        elif i == len(pts) - 1:
            step = pts[-1] - pts[-2]
        else:
            step = pts[i + 1] - pts[i - 1]
        step.z = 0.0
        if step.length < 1e-6:
            step = Vector((1.0, 0.0, 0.0))
        step.normalize()
        stations.append(p + step * RIBBON_SHIFT)
    # the strip starts a step ahead of the lane, so every sample of the lane
    # lies inside the strip and not on the edge of one of its quads
    stations.insert(0, pts[0] - (stations[0] - pts[0]))
    for i in range(len(stations) - 1):
        a, b = stations[i], stations[i + 1]
        across = b - a
        across.z = 0.0
        if across.length < 1e-6:
            continue
        across.normalize()
        right = Vector((across.y, -across.x, 0.0))
        v0 = a + right * half
        v1 = a - right * half
        v2 = b - right * half
        v3 = b + right * half
        tileset.builder_at((a + b) * 0.5).add_named(
            collision.SURFACE_NAME,
            _quad(v0, v1, v2, v3, drop=collision.SURFACE_DROP), surface="asphalt")


def _build_chevrons(tileset, rows):
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
        tileset.builder_at((pa + pb) * 0.5).add(WHITE, bm)


def _wedge_length(rows):
    """The length of the gore's wedge."""
    total = 0.0
    for (pa, _ra, _d, _a), (pb, _rb, _e, _b) in zip(rows, rows[1:]):
        total += (pb - pa).length
    return total


def _build_cushion(tileset, rows):
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
    tileset.builder_at(pa).add(CONCRETE, bm)


def build_acceleration(city, road, tileset, lay):
    """The acceleration lane: the parent's deck widens over the last 150 m.

    The widening is 1:25 (6 m over 150 m), so the traffic of the ramp has a
    lane to speed up in before it joins the parent.  It lies on the side of
    the parent the ramp runs along and it ends at the attach, so it is also
    drivable: it gets a collision surface of its own.
    """
    for at_end, key in ((True, "attach_end"), (False, "attach_start")):
        attach = road.data.get(key)
        if not attach:
            continue
        parent = city.by_id.get(attach["road"])
        if parent is None:
            continue
        r_index = len(road.path) - 1 if at_end else 0
        r_pt = road.path[r_index]
        _dist, pidx = parent.nearest(r_pt)
        s_attach = parent.dist[pidx]
        # the ramp runs along the parent's right or its left: the widening is on
        # that side and it ends at the attach in the traffic's direction
        lay_parent = profiles.layout(parent)
        p_r = parent.frames[pidx][1]
        if (r_pt - parent.path[pidx]).dot(p_r) > 0.0:
            edge, out, sign = lay_parent["asphalt_fwd"], 1.0, 1.0
        else:
            edge, out, sign = lay_parent["asphalt_back"], -1.0, -1.0
        rows = []
        for i in range(len(parent.path)):
            d = (parent.dist[i] - s_attach) * sign
            if d > 0.0 or d < -TAPER_LENGTH:
                continue
            grow = TAPER_WIDTH * min(1.0, max(0.0, (d + TAPER_LENGTH) / TAPER_LENGTH))
            p = parent.path[i]
            r = parent.frames[i][1]
            inner = p + r * edge
            outer = p + r * (edge + out * grow)
            rows.append((inner, outer, p.z))
        if len(rows) < 2:
            continue
        # every quad goes into the tile it lies on
        for i in range(len(rows) - 1):
            inner0, outer0, _z0 = rows[i]
            inner1, outer1, _z1 = rows[i + 1]
            mid = (inner0 + inner1) * 0.5
            _pave(tileset.builder_at(mid), inner0, outer0, outer1, inner1)


def parapet_gaps(city, road):
    """The stretches of a parent road where its parapet has to give way.

    A ramp that leaves the parent needs the parapet (and the planter row) to
    stop before the gore: they would wall the ramp off.
    """
    out = []
    for other in city.roads:
        if other.kind != "ramp":
            continue
        for at_end, key in ((True, "attach_end"), (False, "attach_start")):
            attach = other.data.get(key)
            if not attach or attach.get("road") != road.id:
                continue
            r_index = 0 if at_end else len(other.path) - 1
            _dist, pidx = road.nearest(other.path[r_index])
            s = road.dist[pidx]
            out.append((s - GORE_LENGTH, s + 12.0))
    return out


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
