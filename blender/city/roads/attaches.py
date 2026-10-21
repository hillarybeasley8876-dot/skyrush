"""Ramp attaches: the gore, the acceleration lane, the chevrons and the cushion.

A ramp leaves its parent road at a gore: the paved wedge between the parent's
outer edge and the ramp's own edge. The parent's deck widens over the last
150 m before the attach (1:25), so the traffic has an acceleration lane, and
the gore itself carries the 45 degree chevrons of a Chinese expressway.

The parent's parapet and its planter row are cut over the attach: they would
otherwise wall the ramp off.
"""
import bmesh
import math

from mathutils import Vector

from city.roads import meshkit, profiles

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


def attach_point(city, road, attach):
    """(parent road, parent point, parent right, ramp end point, ramp right)."""
    parent = city.by_id.get(attach["road"])
    if parent is None:
        return None
    r_index = 0 if attach.get("end") else len(road.path) - 1
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


def build_gore(city, road, tileset, lay):
    """The paved gore at the ramp's attach to its parent road."""
    for at_end, key in ((True, "attach_end"), (False, "attach_start")):
        attach = road.data.get(key)
        if not attach:
            continue
        found = attach_point(city, road, dict(attach, end=at_end))
        if found is None:
            continue
        parent, p_pt, p_r, r_pt, r_r = found
        parent_half = profiles.layout(parent)["asphalt_half"]
        rows = []
        for (rp, rr, rt) in _gore_stations(road, at_end, lay):
            dist, pidx = parent.nearest(rp)
            pp = parent.path[pidx]
            to_ramp = rp - pp
            if to_ramp.length < 0.05:
                to_ramp = (rp - p_pt)
            if to_ramp.length < 0.05:
                continue
            direction = to_ramp.normalized()
            parent_edge = pp + direction * parent_half
            ramp_edge = rp + direction * lay["asphalt_half"]
            rows.append((parent_edge, ramp_edge))
        if len(rows) < 2:
            continue
        # every quad goes into the tile it lies on: the gore can be far from the
        # end of the ramp when the ramp does not reach its parent
        for i in range(len(rows) - 1):
            pa, ra = rows[i]
            pb, rb = rows[i + 1]
            mid = (pa + pb) * 0.5
            bm = bmesh.new()
            v0 = bm.verts.new(pa)
            v1 = bm.verts.new(ra)
            v2 = bm.verts.new(rb)
            v3 = bm.verts.new(pb)
            bm.faces.new((v0, v1, v2, v3))
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            tileset.builder_at(mid).add(ASPHALT, bm)
        _build_chevrons(tileset, rows)
        _build_cushion(tileset, rows)


def _build_chevrons(tileset, rows):
    """The 45 degree bars of the gore: they stay inside the wedge."""
    step = max(1, int(CHEVRON_SPACING / max(0.5, _wedge_length(rows) / max(1, len(rows) - 1))))
    for i in range(0, len(rows) - 1, step):
        (pa, ra) = rows[i]
        (pb, rb) = rows[i + 1]
        along = pb - pa
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
    for (pa, _ra), (pb, _rb) in zip(rows, rows[1:]):
        total += (pb - pa).length
    return total


def _build_cushion(tileset, rows):
    """The crash cushion at the nose of the gore."""
    if not rows:
        return
    pa, ra = rows[0]
    along = (rows[1][0] - pa) if len(rows) > 1 else Vector((1.0, 0.0, 0.0))
    if along.length < 0.05:
        return
    along = along.normalized()
    across = (ra - pa)
    if across.length < 0.6:
        return
    across = across.normalized() * CUSHION_WIDTH
    bm = bmesh.new()
    v0 = bm.verts.new(pa + along * 0.2)
    v1 = bm.verts.new(pa + across + along * 0.2)
    v2 = bm.verts.new(pa + across - along * (CUSHION_LENGTH - 0.2))
    v3 = bm.verts.new(pa - along * (CUSHION_LENGTH - 0.2))
    bm.faces.new((v0, v1, v2, v3))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    tileset.builder_at(pa).add(CONCRETE, bm)


def build_acceleration(city, road, tileset, lay):
    """The acceleration lane: the parent's deck widens over the last 150 m.

    The widening is 1:25 (6 m over 150 m), so the traffic of the ramp has a
    lane to speed up in before it joins the parent.
    """
    for at_end, key in ((True, "attach_end"), (False, "attach_start")):
        attach = road.data.get(key)
        if not attach:
            continue
        parent = city.by_id.get(attach["road"])
        if parent is None:
            continue
        r_index = 0 if at_end else len(road.path) - 1
        _dist, pidx = parent.nearest(road.path[r_index])
        s_attach = parent.dist[pidx]
        sign = -1.0 if at_end else 1.0
        lay_parent = profiles.layout(parent)
        edge = lay_parent["asphalt_fwd"] if sign > 0 else lay_parent["asphalt_back"]
        out = 1.0 if sign > 0 else -1.0
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
            bm = bmesh.new()
            v0 = bm.verts.new(inner0)
            v1 = bm.verts.new(outer0)
            v2 = bm.verts.new(outer1)
            v3 = bm.verts.new(inner1)
            bm.faces.new((v0, v1, v2, v3))
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            tileset.builder_at(mid).add(ASPHALT, bm)


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
