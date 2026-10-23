"""Ramp attaches: the gore, the chevrons and the cushion.

A ramp leaves its parent road at a gore: the paved wedge between the parent's
outer edge and the ramp's own edge. The parent's deck widens over the last
150 m before the attach (1:25), so the traffic has an acceleration lane (the
deck module builds it), and the gore itself carries the 45 degree chevrons of
a Chinese expressway.

The gore is where the two decks meet, and the traffic of the attach crosses it
on a connector lane. So the gore carries a collision surface of its own: both
edges are taken in their own road's frame, so the wedge lies on the decks
without a step, and a collider just under the visible asphalt keeps the car on
the road at the joint. The parent's parapet and its planter row are cut over
the attach: they would otherwise wall the ramp off.
"""
import bmesh

from mathutils import Vector

from city.roads import collision, deck, profiles


GORE_LENGTH = 45.0     # how far the gore reaches back from the attach
GAP_MARGIN = 12.0      # the barrier gives way this far before and after the gore

_GORES = {}            # id(road) -> road: the gores of a road are built once
_CELL = 32.0           # the grid of the gap rules, in metres


def _gore_built(road):
    """True when the gores of this road have been built already.

    The build calls build_gore once per attach and the function builds the
    gores of both ends, so without this the gore would be built twice.
    """
    if id(road) in _GORES:
        return True
    _GORES[id(road)] = road
    return False


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
        s = (total - GORE_LENGTH * i / steps) if at_end else GORE_LENGTH * i / steps
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


def build_gore(city, road, tileset, lay):
    """The paved gore at the ramp's attach to its parent road.

    The gore is where the traffic of the attach crosses from the parent to
    the ramp, so it gets a collision surface: the same quads as the visible
    asphalt, dropped a centimetre under it.  The surface is dropped where the
    wedge stands over the ramp's own lane: there it would be a step in the
    lane the traffic of the attach drives on.
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
        # The wedge runs from the parent's edge to the ramp's edge, so it
        # reaches into the ramp's own corridor: a collider there would stand
        # over the ramp's lane, so the quad gets none.
        clear = lay["asphalt_half"] + collision.CORRIDOR_MARGIN
        # every quad goes into the tile it lies on: the gore can be far from the
        # end of the ramp when the ramp does not reach its parent
        for i in range(len(rows) - 1):
            pa, ra, _d, _a = rows[i]
            pb, rb, _e, _b = rows[i + 1]
            mid = (pa + pb) * 0.5
            quad = [pa, ra, rb, pb]
            collision.pave(tileset.builder_at(mid), pa, ra, rb, pb,
                           collide=not collision.over_corridor(road, quad, clear))
        deck.build_chevrons(tileset, rows)
        deck.build_cushion(tileset, rows)
        # one deck can roof the lane of the other: the carriageway collider of
        # both is narrowed there, so the lane keeps its own road
        collision.roof_cut(city, road, parent, tileset, lay, found[3])
    collision.build_connectors(city, road, tileset)


def _stretches(hits):
    """The stretches of the road where the traffic meets it: [(side, lo, hi)]."""
    out = []
    for side in ("fwd", "back", "median"):
        stations = sorted(set(st for (s, st) in hits if s == side))
        if not stations:
            continue
        lo = hi = stations[0]
        for st in stations[1:]:
            if st - hi > 20.0:
                out.append((side, lo, hi))
                lo = st
            hi = max(hi, st)
        out.append((side, lo, hi))
    return out


def traffic_gaps(city, road):
    """The stretches of the road where the traffic of the city meets it.

    A lane that crosses the centre line of the road needs a gap in the median
    barrier, and one that runs under the deck edge needs a gap in the parapet
    of that side: the collider of the parapet reaches 0.75 m below the deck,
    into the traffic of the road that runs underneath.
    """
    lay = profiles.layout(road)
    z_lo = min(p.z for p in road.path) - 2.05
    z_hi = max(p.z for p in road.path) + 2.05
    cells = set((int(p.x // _CELL), int(p.y // _CELL)) for p in road.path)
    hits = []
    for (lane, lo, hi, lane_cells) in collision.lane_index(city):
        if lane.get("road") == road.id and not lane.get("connector"):
            continue
        if hi < z_lo or lo > z_hi or not (cells & lane_cells):
            continue
        for p in lane["points"]:
            q = Vector((p[0], -p[2], p[1]))
            lateral, station, height = collision.plan_offset(road, q)
            if not -0.8 < height - q.z < 2.05:
                continue
            if abs(lateral) < 1.45:
                hits.append(("median", station))
            for (side, edge) in (("fwd", lay["asphalt_fwd"]), ("back", lay["asphalt_back"])):
                if abs(lateral - edge) <= 1.45:
                    hits.append((side, station))
    return _stretches(hits)


def parapet_gaps(city, road):
    """The stretches of a road where its parapet has to give way.

    Returns {"fwd": [(a, b), ...], "back": [(a, b), ...], "median": [...]}: the
    station stretches of each side of the deck where the parapet (and its
    collider) is missing, and the stretches where the median barrier has to
    give way.  A ramp that leaves the road needs the parapet (and the planter
    row) to stop before the gore: they would wall the ramp off, and the
    traffic of the attach crosses the deck edge there.  The same gaps cut the
    visible parapet and its collider: a collider that stands where the parapet
    is gone is an invisible wall.
    """
    out = {"fwd": [], "back": [], "median": []}
    for other in city.roads:
        if other.kind != "ramp":
            continue
        for at_end, key in ((True, "attach_end"), (False, "attach_start")):
            attach = other.data.get(key)
            if not attach or attach.get("road") != road.id:
                continue
            for (side, lo, hi) in _parent_gaps(city, road, other, at_end):
                out[side].append((lo - GAP_MARGIN, hi + GAP_MARGIN))
    if road.kind == "ramp":
        for at_end, key in ((True, "attach_end"), (False, "attach_start")):
            if not road.data.get(key):
                continue
            for (side, gap) in _ramp_gap(city, road, at_end):
                out[side].append(gap)
    for (side, lo, hi) in traffic_gaps(city, road):
        out[side].append((lo - GAP_MARGIN, hi + GAP_MARGIN))
    return out


def _parent_gaps(city, parent, ramp, at_end):
    """The stretches of the parent where its barrier has to give way.

    Two sources say where the traffic of the attach crosses the deck edge: the
    gore (the paved wedge between the two decks) and the connector lanes (the
    curves the traffic takes over the joint).  Each gives a side and a stretch.
    """
    out = []
    rows = _gore_rows(parent, ramp, at_end, profiles.layout(ramp))
    if rows:
        stations = [parent.dist[parent.nearest(pe)[1]] for (pe, _re, _d, _a) in rows]
        _dd, pidx = parent.nearest(rows[0][0])
        pr = parent.frames[pidx][1]
        side = "fwd" if rows[0][2].dot(pr) > 0.0 else "back"
        out.append((side, min(stations), max(stations)))
    lay = profiles.layout(parent)
    for lane in _attach_lanes(city, ramp, at_end):
        out += _outside_stretch(parent, lane, lay)
        for station in _centre_crossings(parent, lane):
            out.append(("median", station, station))
    return out


def _ramp_gap(city, ramp, at_end):
    """The stretches of the ramp where its parapet has to give way.

    The gore is the last (or the first) GORE_LENGTH metres of the ramp: the
    ramp's own parapet stands on the edge of the gore and would wall the
    traffic of the attach off.  And where the parent's traffic runs under the
    ramp's edge, the parapet stands in that traffic.
    """
    attach = ramp.data.get("attach_end" if at_end else "attach_start")
    parent = city.by_id.get(attach["road"])
    if parent is None:
        return []
    r_index = len(ramp.path) - 1 if at_end else 0
    r_pt = ramp.path[r_index]
    _dist, pidx = parent.nearest(r_pt)
    to_parent = parent.path[pidx] - r_pt
    side = "fwd" if to_parent.dot(ramp.frames[r_index][1]) > 0.0 else "back"
    lo = ramp.length - GORE_LENGTH if at_end else 0.0
    hi = ramp.length if at_end else GORE_LENGTH
    out = [(side, (lo - GAP_MARGIN, hi + GAP_MARGIN))]
    return out


def _attach_lanes(city, ramp, at_end):
    """The connector lanes of one attach of the ramp.

    A connector lane is named after the two lanes it joins, so the ramp's own
    lane says which end of the ramp the connector leaves from: the ramp joins
    the parent at its far end and leaves the parent at its start.
    """
    graph = collision.lane_graph_of(city)
    mine = [l["id"] for l in graph["lanes"]
            if l.get("road") == ramp.id and not l.get("connector")]
    out = []
    for lane in graph["lanes"]:
        cid = lane["id"]
        if not cid.startswith("attach_"):
            continue
        if at_end and any(cid.startswith("attach_" + rid) for rid in mine):
            out.append(lane)
        elif not at_end and any(cid.endswith("_" + rid) for rid in mine):
            out.append(lane)
    return out


def _outside_stretch(parent, lane, lay):
    """The stretches of the parent where a connector lane runs outside the road.

    The traffic of the attach is off the carriageway there, so the barrier of
    that side has to give way: [(side, first station, last station)].
    """
    out = []
    run = None
    for p in lane["points"]:
        lateral, station, _h = _offset(parent, Vector((p[0], -p[2], p[1])))
        if abs(lateral) > lay["asphalt_half"]:
            side = "fwd" if lateral > 0.0 else "back"
            if run is not None and run[0] == side:
                run = (side, min(run[1], station), max(run[2], station))
            else:
                if run is not None:
                    out.append(run)
                run = (side, station, station)
        elif run is not None:
            out.append(run)
            run = None
    if run is not None:
        out.append(run)
    return out


def _offset(road, q):
    """(signed lateral offset, station, height) of a point in the plan of a road."""
    _dist, idx, t = road.closest(q)
    a = road.path[idx]
    b = road.path[idx + 1]
    seg = b - a
    seg.z = 0.0
    right = Vector((seg.y, -seg.x, 0.0))
    if right.length < 1e-6:
        right = road.frames[idx][1]
    else:
        right.normalize()
    station = road.dist[idx] + t * (road.dist[idx + 1] - road.dist[idx])
    return (q - a).dot(right), station, a.z + (b.z - a.z) * t


def _centre_crossings(parent, lane):
    """The stations where a connector lane crosses the centre line of the parent.

    The traffic of the attach crosses the median there, so the median barrier
    has to give way.
    """
    out = []
    prev = None
    for p in lane["points"]:
        q = Vector((p[0], -p[2], p[1]))
        lateral, station, height = _offset(parent, q)
        if prev is not None and prev[0] * lateral < 0.0:
            t = prev[0] / (prev[0] - lateral)
            if abs(q.z - height) < 2.0:
                out.append(prev[1] + t * (station - prev[1]))
        prev = (lateral, station)
    return out
