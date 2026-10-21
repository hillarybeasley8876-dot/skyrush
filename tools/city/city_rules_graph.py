"""city_rules_graph — the directed lane graph of the map.

Every road is split at its junctions and attaches.  A node is a segment of
a road in one direction: the node is where the traffic *enters* the
segment, so the traffic of a segment runs from its node to the node of the
next segment.  The edges are the driving movements: along a road, through
a junction and over an attach.  Every edge carries the length that is
driven, so the graph can measure the distance between two places and tell
whether one place can be reached from another in the driving direction.
"""
import heapq
import math

DIRECTIONS = (1, -1)
TURN_LIMIT = 100.0        # degrees: a turn sharper than this is a u-turn


def _angle_diff(a, b):
    """The angle between two headings, in degrees."""
    return abs((a - b + 180.0) % 360.0 - 180.0)


def _cumulative(points):
    """The arc length at every point of a polyline."""
    out = [0.0]
    for a, b in zip(points, points[1:]):
        out.append(out[-1] + math.dist(a, b))
    return out


def _s_of_point(road, x, z):
    """The arc length of the road's point closest to the plan position."""
    best, best_s = 1e18, 0.0
    acc = 0.0
    for a, b in zip(road["points"], road["points"][1:]):
        run = math.dist(a, b)
        if run < 1e-9:
            continue
        ab = (b[0] - a[0], b[2] - a[2])
        den = ab[0] ** 2 + ab[1] ** 2
        t = max(0.0, min(1.0, ((x - a[0]) * ab[0]
                                + (z - a[2]) * ab[1]) / den))
        d = math.dist((x, z), (a[0] + ab[0] * t, a[2] + ab[1] * t))
        if d < best:
            best, best_s = d, acc + run * t
        acc += run
    return best_s


def _point_at(road, s):
    """The plan position of a road at the distance `s`."""
    acc = 0.0
    pts = road["points"]
    for a, b in zip(pts, pts[1:]):
        run = math.dist(a, b)
        if acc + run >= s:
            t = (s - acc) / run if run > 1e-9 else 0.0
            return (a[0] + t * (b[0] - a[0]), a[2] + t * (b[2] - a[2]))
        acc += run
    return (pts[-1][0], pts[-1][2])


def _heading_at(road, s):
    """The heading of a road at the distance `s` (0 = north)."""
    acc = 0.0
    pts = road["points"]
    for a, b in zip(pts, pts[1:]):
        run = math.dist(a, b)
        if acc + run >= s:
            t = (s - acc) / run if run > 1e-9 else 0.0
            return math.degrees(math.atan2(b[0] - a[0],
                                           -(b[2] - a[2]))) % 360.0
        acc += run
    a, b = pts[-2], pts[-1]
    return math.degrees(math.atan2(b[0] - a[0], -(b[2] - a[2]))) % 360.0


def _point_and_tangent(road, s):
    """The point and the tangent of a road at the distance `s`."""
    acc = 0.0
    pts = road["points"]
    for a, b in zip(pts, pts[1:]):
        run = math.dist(a, b)
        if acc + run >= s:
            t = (s - acc) / run if run > 1e-9 else 0.0
            return (a[0] + t * (b[0] - a[0]), a[2] + t * (b[2] - a[2])), \
                (b[0] - a[0], b[2] - a[2])
        acc += run
    a, b = pts[-2], pts[-1]
    return (b[0], b[2]), (b[0] - a[0], b[2] - a[2])


def _split_points(road, city):
    """The arc lengths where the road is split: the junctions and attaches."""
    pts = road["points"]
    cum = _cumulative(pts)
    splits = {0.0, cum[-1]}
    for j in city["junctions"]:
        if road["id"] not in j["roads"]:
            continue
        if min(math.hypot(p[0] - j["x"], p[2] - j["z"]) for p in pts) < 45.0:
            splits.add(round(_s_of_point(road, j["x"], j["z"]), 2))
    for key in ("attach_start", "attach_end"):
        att = road.get(key)
        if att:
            splits.add(round(att["at"], 2))
    # the ramps that leave or meet this road split it as well
    for other in city["roads"]:
        if other["id"] == road["id"]:
            continue
        for key in ("attach_start", "attach_end"):
            att = other.get(key)
            if att and att["road"] == road["id"]:
                splits.add(round(att["at"], 2))
    return sorted(splits)


def _segments(road, city):
    """The segments of a road: the stretches between the splits."""
    splits = _split_points(road, city)
    return [(a, b) for a, b in zip(splits, splits[1:]) if b - a >= 0.5]


def build_lane_graph(city):
    """The directed lane graph of the map."""
    by_id = {r["id"]: r for r in city["roads"]}
    segments = {r["id"]: _segments(r, city) for r in city["roads"]}
    adj = {}

    def add_edge(frm, to, length=0.0):
        adj.setdefault(frm, []).append((to, length))
        adj.setdefault(to, [])

    for road in city["roads"]:
        rid = road["id"]
        segs = segments[rid]
        for i, (a, b) in enumerate(segs):
            if i + 1 < len(segs):
                add_edge((rid, 1, i), (rid, 1, i + 1), b - a)
            if i > 0:
                add_edge((rid, -1, i), (rid, -1, i - 1), b - a)
    _junction_edges(city, by_id, segments, add_edge)
    _attach_edges(city, by_id, segments, add_edge)
    return adj, segments


def _around(segments, rid, s):
    """The segments around the station `s`: (before, after).

    `before` is the segment that ends at `s`, `after` the one that starts
    there.  One of them can be None at the ends of a road.
    """
    before = after = None
    for i, (a, b) in enumerate(segments.get(rid, [])):
        if abs(b - s) < 2.5:
            before = i
        if abs(a - s) < 2.5:
            after = i
    return before, after


def _junction_node(before, after, direction):
    """The node of a road at a junction.

    The traffic reaches the junction at the end of the segment it comes
    from, so the node it stands on is the entry of the segment that
    follows in the direction of the traffic.
    """
    if direction > 0:
        return after if after is not None else before
    return before if before is not None else after


def _junction_edges(city, by_id, segments, add_edge):
    """The movements through the junctions: every road can be left for
    every other one, but a car never turns back on itself."""
    for j in city["junctions"]:
        roads = [r for r in j["roads"] if r in by_id]
        if len(roads) < 2:
            continue
        info = {}
        for rid in roads:
            road = by_id[rid]
            s = _s_of_point(road, j["x"], j["z"])
            before, after = _around(segments, rid, s)
            if before is None and after is None:
                info = {}
                break
            info[rid] = (s, before, after)
        if len(info) < 2:
            continue
        for rid in info:
            for other in info:
                if other == rid:
                    continue
                for direction in DIRECTIONS:
                    for odirection in DIRECTIONS:
                        edge = _movement(by_id, info, rid, other, direction,
                                         odirection)
                        if edge is None:
                            continue
                        add_edge(*edge)


def _movement(by_id, info, rid, other, direction, odirection):
    """The edge of one movement through a junction."""
    s_a, before, after = info[rid]
    s_b, obefore, oafter = info[other]
    index_a = _junction_node(before, after, direction)
    index_b = _junction_node(obefore, oafter, odirection)
    if index_a is None or index_b is None:
        return None
    head_a = _heading_at(by_id[rid], s_a)
    head_b = _heading_at(by_id[other], s_b)
    flow_a = head_a if direction > 0 else (head_a + 180.0) % 360.0
    flow_b = head_b if odirection > 0 else (head_b + 180.0) % 360.0
    if _angle_diff(flow_a, flow_b) > TURN_LIMIT:
        return None
    return ((rid, direction, index_a), (other, odirection, index_b), 0.0)


def _attach_edges(city, by_id, segments, add_edge):
    """The movements at the attaches: a ramp leaves and meets its parent."""
    for road in city["roads"]:
        for key, at_start in (("attach_start", True), ("attach_end", False)):
            att = road.get(key)
            if not att:
                continue
            parent = by_id.get(att["road"])
            segs = segments.get(road["id"])
            if parent is None or not segs:
                continue
            before, after = _around(segments, parent["id"], att["at"])
            if before is None and after is None:
                continue
            direction = _attach_direction(road, parent, att["at"], at_start)
            index = _junction_node(before, after, direction)
            if index is None:
                continue
            p_pt = _point_at(parent, att["at"])
            if at_start:
                frm = (parent["id"], direction, index)
                to = (road["id"], 1, 0)
                gap = math.hypot(road["points"][0][0] - p_pt[0],
                                 road["points"][0][2] - p_pt[1])
            else:
                frm = (road["id"], 1, len(segs) - 1)
                to = (parent["id"], direction, index)
                gap = math.hypot(road["points"][-1][0] - p_pt[0],
                                 road["points"][-1][2] - p_pt[1])
            add_edge(frm, to, gap)


def _attach_direction(road, parent, s, at_start):
    """The direction the traffic flows on the parent at the attach."""
    if at_start:
        child = road["points"][0]
        nxt = road["points"][1]
    else:
        child = road["points"][-1]
        nxt = road["points"][-2]
    ct = (nxt[0] - child[0], nxt[2] - child[2])
    if not at_start:
        ct = (-ct[0], -ct[1])
    ch = math.degrees(math.atan2(ct[0], -ct[1])) % 360.0
    ph = _heading_at(parent, s)
    return 1 if _angle_diff(ph, ch) < 90.0 else -1


def shortest_path(adj, frm, to):
    """The length of the shortest driven path from `frm` to `to`.

    None when there is no path: the two places are not connected in the
    driving direction.
    """
    if frm == to:
        return 0.0
    dist = {frm: 0.0}
    heap = [(0.0, frm)]
    while heap:
        d, cur = heapq.heappop(heap)
        if d > dist.get(cur, 1e18):
            continue
        if cur == to:
            return d
        for nxt, length in adj.get(cur, ()):
            nd = d + length
            if nd < dist.get(nxt, 1e18):
                dist[nxt] = nd
                heapq.heappush(heap, (nd, nxt))
    return None


def segment_index(segments, road_id, s):
    """The index of the segment that holds the station `s`."""
    for i, (a, b) in enumerate(segments.get(road_id, [])):
        if a - 0.5 <= s <= b + 0.5:
            return i
    return None


def driven_distance(adj, segments, a, b):
    """The distance driven between two places.

    A place is (road id, direction, station).  The distance is the length
    of the shortest driven path: what is still to be driven on the first
    road, the path of the lane graph and what has been driven on the last
    road.
    """
    if a[0] == b[0] and a[1] == b[1]:
        # the same road in the same direction: the distance along it
        return (b[2] - a[2]) if a[1] > 0 else (a[2] - b[2])
    node_a = _next_node(segments, a)
    node_b = _previous_node(segments, b)
    if node_a is None or node_b is None:
        return None
    path = shortest_path(adj, node_a[0], node_b[0])
    if path is None:
        return None
    return node_a[1] + path + node_b[1]


def _next_node(segments, place):
    """The node the traffic reaches next and the distance to it."""
    rid, direction, s = place
    index = segment_index(segments, rid, s)
    if index is None:
        return None
    segs = segments[rid]
    if direction > 0:
        if index + 1 >= len(segs):
            return None
        return ((rid, 1, index + 1), segs[index][1] - s)
    if index == 0:
        return None
    return ((rid, -1, index - 1), s - segs[index][0])


def _previous_node(segments, place):
    """The node the traffic came from and the distance from it."""
    rid, direction, s = place
    index = segment_index(segments, rid, s)
    if index is None:
        return None
    segs = segments[rid]
    if direction > 0:
        return ((rid, 1, index), s - segs[index][0])
    return ((rid, -1, index), segs[index][1] - s)
