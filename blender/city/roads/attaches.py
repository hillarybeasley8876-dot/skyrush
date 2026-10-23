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
GORE_STRIPS = 4        # the wedge is paved in strips across its width
NOSE_ROWS = 4          # the nose of the gore is paved in rows along the parent
GAP_MARGIN = 2.0       # the barrier gives way this far before and after the gore

# The parapet stands from PARAPET_BOTTOM under the deck to PARAPET_H above it,
# and a car stands from CAR_LIFT above its lane to CAR_ROOF above it.  A lane
# that meets the parapet in that span drives into it, so the parapet has to
# give way there: the traffic of the city comes first.  Below that span the
# car passes under the parapet: the fence stands, but its collider must not
# hang into the traffic, so the collider is cut short there.
GAP_DZ_LO = profiles.CAR_LIFT - profiles.PARAPET_H        # -0.70
GAP_DZ_HI = profiles.CAR_ROOF - profiles.PARAPET_BOTTOM  # 1.45
SHALLOW_DZ_HI = profiles.CAR_ROOF + collision.BARRIER_DEPTH  # 1.90
# A lane that runs under the edge of a deck at the level of the deck crosses
# it: the parapet has to give way there.  A lane that runs lower passes under
# the parapet, but not under a full one: the parapet gets lower there.  A car
# is 1.30 m tall above its lane, so the lane has to be more than 0.85 m below
# the deck for the car to pass a low parapet.
CROSS_DZ = 0.85        # the traffic at the level of the deck crosses the edge
GAP_SIDE = 1.45        # the traffic that meets the parapet of a side
# The car of a lane that runs under the edge of a deck passes the parapet
# beside it, so the parapet has to be narrow there: the low parapet is
# 0.28 m wide, and the car is 0.95 m wide.
KERB_SIDE = 1.30       # the traffic closer than this needs a gap of its own

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


def _nose_rows(city, parent, road, at_end, lay):
    """The nose of the gore: the pavement between the parent's edge and the
    end face of the ramp's deck.

    The end of a ramp lies beside its parent, not on it, so the traffic of
    the attach leaves the carriageway of the parent a dozen metres before the
    ramp starts, and that part of the attach is over nothing at all.  The
    nose carries it: it is the triangle between the edge of the parent and
    the end face of the ramp.

    Every row is a pair of points: the one on the edge of the parent and the
    one on the end face of the ramp.
    """
    parent_lay = profiles.layout(parent)
    r_index = len(road.path) - 1 if at_end else 0
    r_pt = road.path[r_index]
    r_r = road.frames[r_index][1]
    _dist, pidx = parent.nearest(r_pt)
    p_pt = parent.path[pidx]
    p_r = parent.frames[pidx][1]
    to_ramp = r_pt - p_pt
    direction = Vector((to_ramp.x, to_ramp.y, 0.0))
    if direction.length < 0.05:
        return []
    direction.normalize()
    # the parent's edge on the ramp's side and the ramp's end face
    p_off = _edge_offset(parent_lay, direction.dot(p_r) > 0.0)
    parent_edge = p_pt + p_r * p_off
    r_off = _edge_offset(lay, -direction.dot(r_r) > 0.0)
    face_far = r_pt - r_r * r_off
    # where the traffic of the attach leaves the carriageway of the parent
    crossing = None
    for lane in _attach_lanes(city, road, at_end):
        prev = None
        for p in lane["points"]:
            q = Vector((p[0], -p[2], p[1]))
            lateral, station, _height = _offset(parent, q)
            if prev is not None and (prev[0] - p_off) * (lateral - p_off) < 0.0:
                t = (p_off - prev[0]) / (lateral - prev[0])
                st = prev[1] + t * (station - prev[1])
                if crossing is None or st < crossing:
                    crossing = st
            prev = (lateral, station)
    if crossing is None:
        return []
    j = parent.index_at(crossing)
    p1 = parent.path[j] + parent.frames[j][1] * p_off
    rows = []
    for i in range(NOSE_ROWS + 1):
        t = i / NOSE_ROWS
        rows.append((p1.lerp(parent_edge, t), parent_edge.lerp(face_far, t)))
    return rows


def _gore_strips(pa, ra, pb, rb):
    """The wedge of one gore row, split into strips across its width.

    The wedge is not a rectangle: the parent's edge and the ramp's edge run
    apart as the gore reaches back from the attach, so the wedge is split
    into strips that follow both of them.  A strip that stands over the lane
    of another road can lose its collider on its own, without opening a hole
    in the whole wedge.
    """
    out = []
    for k in range(GORE_STRIPS):
        t0 = k / GORE_STRIPS
        t1 = (k + 1) / GORE_STRIPS
        out.append([pa + (ra - pa) * t0, pa + (ra - pa) * t1,
                    pb + (rb - pb) * t1, pb + (rb - pb) * t0])
    return out


def build_gore(city, road, tileset, lay):
    """The paved gore at the ramp's attach to its parent road.

    The gore is where the traffic of the attach crosses from the parent to
    the ramp, so it gets a collision surface: the same quads as the visible
    asphalt, dropped a centimetre under it.  The surface runs the whole width
    of the wedge, from the edge of the parent to the edge of the ramp: a hole
    there is a hole in the deck of the parent, and a car that drifts over the
    edge of the parent falls into it.  Only a part of the wedge that stands
    over the lane of another road loses its collider: there it would be a
    step in the lane that traffic drives on.
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
        # The wedge runs from the parent's edge to the ramp's edge, and its
        # collision surface has to run the whole way: where it is missing the
        # deck of the parent ends in a void and the car can fall off the edge
        # there.  A strip that stands over the lane of a road gets no
        # collider: there it would be a step in that lane.  The connector
        # lanes of this attach are the exception: the gore is the surface
        # they drive on.
        grid = collision.lane_grid(city)
        skip = tuple(l["id"] for l in _attach_lanes(city, road, at_end))
        # the nose of the gore: the pavement that carries the traffic of the
        # attach from the edge of the parent to the end of the ramp
        nose = _nose_rows(city, parent, road, at_end, lay)
        for i in range(len(nose) - 1):
            pa, ra = nose[i]
            pb, rb = nose[i + 1]
            for strip in _gore_strips(pa, ra, pb, rb):
                mid = (strip[0] + strip[2]) * 0.5
                collide = not collision.roofs_lane(strip, grid, skip, collision.CAR_HALF_LEN)
                collision.pave(tileset.builder_at(mid), strip[0], strip[1], strip[2], strip[3],
                               collide=collide)
        for i in range(len(rows) - 1):
            pa, ra, _d, _a = rows[i]
            pb, rb, _e, _b = rows[i + 1]
            mid = (pa + pb) * 0.5
            builder = tileset.builder_at(mid)
            for strip in _gore_strips(pa, ra, pb, rb):
                collide = not collision.roofs_lane(strip, grid, skip, collision.CAR_HALF_LEN)
                collision.pave(builder, strip[0], strip[1], strip[2], strip[3],
                               collide=collide)
        deck.build_chevrons(tileset, rows)
        deck.build_cushion(tileset, rows)
        # one deck can roof the lane of the other: the carriageway collider of
        # both is narrowed there, so the lane keeps its own road
        collision.roof_cut(city, road, parent, tileset, lay, found[3])
    collision.build_connectors(city, road, tileset)


def _stretches(hits):
    """The stretches of the road where the traffic meets it: [(side, lo, hi)]."""
    out = []
    for side in sorted(set(s for (s, _st) in hits)):
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
        side = GAP_SIDE
        prev = None
        for p in lane["points"]:
            q = Vector((p[0], -p[2], p[1]))
            lateral, station, height = collision.plan_offset(road, q)
            dz = height - q.z
            if lateral > 1e5:
                # the point is nowhere near the road: it is not a stretch of
                # the lane beside the deck
                prev = None
                continue
            if prev is not None and (q.x - prev[0].x) ** 2 + (q.y - prev[0].y) ** 2 < 9.0:
                # only the points of the lane that follow each other: a
                # connector lane jumps from one road to the next, and that
                # jump is not a stretch of the lane
                _lane_hits(hits, prev[1:], (lateral, station, dz), lay, side)
            prev = (q, lateral, station, dz)
    return _stretches(hits)


def _lane_hits(hits, a, b, lay, side):
    """The hits of the stretch of a lane between two of its points.

    The points of a lane are two metres apart and the lane can pass the edge
    of the deck between two of them: the whole stretch counts then, and not
    only the points.
    """
    lat_a, st_a, dz_a = a
    lat_b, st_b, dz_b = b
    dlo = min(dz_a, dz_b)
    dhi = max(dz_a, dz_b)
    if dlo < 0.85 and dhi > -0.8 and min(lat_a, lat_b) < side and max(lat_a, lat_b) > -side:
        hits.append(("median", st_a))
        hits.append(("median", st_b))
    for (name, edge) in (("fwd", lay["asphalt_fwd"]), ("back", lay["asphalt_back"])):
        # how close the stretch comes to the edge of the deck
        if edge <= min(lat_a, lat_b):
            near = min(lat_a, lat_b) - edge
        elif edge >= max(lat_a, lat_b):
            near = edge - max(lat_a, lat_b)
        else:
            near = 0.0
        if near > side:
            continue
        if dlo < CROSS_DZ and dhi > GAP_DZ_LO:
            # the traffic crosses the edge of the deck: the parapet gives way
            hits.append((name, st_a))
            hits.append((name, st_b))
        elif dlo < GAP_DZ_HI and dhi > CROSS_DZ:
            # the traffic runs under the edge of the deck: a low parapet lets
            # the car pass beside it, a full one would stand in the traffic
            if near < KERB_SIDE:
                hits.append((name, st_a))
                hits.append((name, st_b))
            else:
                hits.append((name + "_kerb", st_a))
                hits.append((name + "_kerb", st_b))
        elif dlo < SHALLOW_DZ_HI and dhi > GAP_DZ_HI:
            # the traffic runs well under the edge: the fence stands, but its
            # collider is cut short, or the collider would be a wall where
            # there is no fence to see
            hits.append((name + "_shallow", st_a))
            hits.append((name + "_shallow", st_b))


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
    out = {"fwd": [], "back": [], "median": [],
           "fwd_kerb": [], "back_kerb": [],
           "fwd_shallow": [], "back_shallow": []}
    for other in city.roads:
        if other.kind != "ramp":
            continue
        for at_end, key in ((True, "attach_end"), (False, "attach_start")):
            attach = other.data.get(key)
            if not attach or attach.get("road") != road.id:
                continue
            for (side, lo, hi) in _parent_gaps(city, road, other, at_end):
                out[side].append((lo - GAP_MARGIN, hi + GAP_MARGIN))
    # The ramp's own parapet stands over its gore: the outer edge of the gore
    # IS the edge of the ramp's deck, so the ramp's parapet is the fence of the
    # gore and of the ramp's lane beside it.
    for (side, lo, hi) in traffic_gaps(city, road):
        out[side].append((lo - GAP_MARGIN, hi + GAP_MARGIN))
    return out


def _parent_gaps(city, parent, ramp, at_end):
    """The stretches of the parent where its barrier has to give way.

    The traffic of the attach crosses the centre line of the parent: the
    median barrier has to give way there.

    The deck edge of the parent is not in this list.  The connector lane of
    the attach runs outside the carriageway of the parent over a long
    stretch, but it only crosses the edge of the deck over a few metres, and
    only there may the parapet go: everywhere else the parapet stands and
    fences the deck.  That crossing is the rule of traffic_gaps, which knows
    every lane of the city.
    """
    out = []
    for lane in _attach_lanes(city, ramp, at_end):
        for station in _centre_crossings(parent, lane):
            out.append(("median", station, station))
    return out


def _gore_stretch(parent, ramp, at_end):
    """The stretch of the parent that the gore of one attach lies along.

    The gore is paved and the traffic of the attach runs over it, so the
    parapet of the parent has to give way there: it would wall the ramp off.
    """
    rows = _gore_rows(parent, ramp, at_end, profiles.layout(ramp))
    if len(rows) < 2:
        return []
    stations = []
    side = None
    for (pe, _re, _d, _a) in rows:
        _dist, pidx = parent.nearest(pe)
        stations.append(parent.dist[pidx])
        lateral, _st, _h = _offset(parent, pe)
        side = "fwd" if lateral > 0.0 else "back"
    if side is None:
        return []
    return [(side, min(stations), max(stations))]


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
