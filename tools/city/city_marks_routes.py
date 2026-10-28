"""city_marks_routes — the race routes and the spawn points of the map.

The itinerary of a route is a list of roads with the direction of the
traffic; the route enters and leaves every road where it meets the road
before and the road after it.  The checkpoints lie on the lane centres,
every CHECKPOINT_SPACING metres along the itinerary of the route: the
distance is the one the race drives, not the shortest way through the
map, or a route that comes back near itself would lose the gates of the
whole loop to a cross street.

The game builds the racing line of a leg from the **shortest lane path**
between the two gates (game/world/api/route_builder.gd), so the search
has to know what the game drives:  `_game_graph` builds the lane graph of
the game (every turn of a junction has a connector, a turn of more than
100 degrees costs the hairpin cost of the game) and the search keeps the
legs whose way stays on the itinerary, whose gates stand clear of the
junctions (the game cuts the lanes of a road around a junction) and that
drive every road of the itinerary.
"""
import heapq
import math
import sys

from city_marks import _nearest_s
from city_rules_lanes import lane_at, lane_centres
from citylib import point_at_distance
from city_rules_graph import (build_lane_graph, _angle_diff, _heading_at,
                              _next_node, _previous_node, _s_of_point)


# ---------------------------------------------------------------- routes

ROUTE_SPECS = [
    # the Yan'an elevated road, the dragon interchange, the N-S elevated
    # road, the inner ring, the Nanpu spiral and bridge, the Pudong loop,
    # the Century Ave, the tunnel, the Henan Rd, the D1 E-W street, the
    # Dongchang Rd, the Nanjing E. Rd, the Bund, the Beijing Rd, the
    # Fujian Rd, the Yan'an Rd and the D9 grid, back to the G50
    ("grand_loop", "申城大环线", "race", [
        ("yanan_elevated", 1), ("ramp_rt_eb_sb", 1), ("ns_elevated", 1),
        ("inner_ring", 1), ("nanpu_spiral_upper", 1), ("nanpu_bridge", 1),
        ("nanpu_pudong_loop", 1), ("pudong_south_rd", -1),
        ("century_ave", -1), ("yanan_tunnel", -1), ("st_fujian_portal", -1),
        ("st_henan_rd", 1), ("st_d1_ew_7", 1), ("dongchang_rd", 1),
        ("st_nanjing_e_rd", -1), ("bund_zhongshan_e1", 1),
        ("st_beijing_e_rd", 1), ("st_fujian_rd", -1),
        ("yanan_rd_surface", -1), ("st_d3b_ns_5", 1), ("st_d3b_ew_16", -1),
        ("st_d9_ns_8", 1), ("st_d9_ew_8", -1),
        ("st_d9_ns_2", -1), ("g50_west", 1)]),
    # the elevated road, the dragon interchange, the N-S elevated road,
    # the inner ring, the Nanpu spiral and bridge and the tunnel
    ("elevated_sprint", "高架冲刺", "sprint", [
        ("yanan_elevated", 1), ("ramp_rt_eb_sb", 1), ("ns_elevated", 1),
        ("inner_ring", 1), ("nanpu_spiral_upper", 1), ("nanpu_bridge", 1),
        ("nanpu_pudong_loop", 1), ("pudong_south_rd", -1),
        ("century_ave", -1), ("yanan_tunnel", -1)]),
    # the Pudong south road, the Century Ave, the tunnel under the river,
    # the Henan Rd, the D1 E-W street, the Dongchang Rd, the Nanjing E. Rd
    # and the Bund.  The Lujiazui ring road is not in it: the game has no
    # lane from the ring road to the Yincheng Rd, the road that joins it to
    # the tunnel (the ring road has its own race)
    ("river_loop", "滨江环线", "pursuit", [
        ("pudong_south_rd", -1), ("century_ave", -1),
        ("yanan_tunnel", -1),
        ("st_fujian_portal", -1), ("st_henan_rd", 1), ("st_d1_ew_7", 1),
        ("dongchang_rd", 1), ("st_nanjing_e_rd", -1),
        ("bund_zhongshan_e1", 1)]),
    # the Bund, the Nanjing E. Rd, the Dongchang Rd, the D1 E-W street, the
    # Henan Rd, the Fujian portal and the tunnel
    ("bund_sprint", "外滩冲刺", "sprint", [
        ("bund_zhongshan_e1", -1), ("st_nanjing_e_rd", 1),
        ("dongchang_rd", -1), ("st_d1_ew_7", -1), ("st_henan_rd", -1),
        ("st_fujian_portal", 1), ("yanan_tunnel", 1)]),
    # the Lujiazui ring road, a closed loop: a lap ends where it began, so the race can run
    # more than one lap (the closing leg of a circuit is a few hundred metres, not a drive across the district)
    ("lujiazui_ring", "陆家嘴环线", "race", [
        ("lujiazui_ring_rd", -1)]),
]

CHECKPOINT_SPACING = 400.0
CHECKPOINT_MIN = 300.0
CHECKPOINT_MAX = 500.0
SAMPLE_STEP = 20.0
GRID_MARGIN = 150.0
FINISH_MARGIN = 60.0
GATE_STATES = 2000        # the places the search for the gates may try
TRIM = 25.0                # the game trims the lanes at the ends of a road
JUNCTION_CLEAR = 16.0      # the game cuts the lanes around a junction
JUNCTION_COST = 200.0       # what a gate in the cut of a junction costs
MISSED_COST = 200.0         # what a road of the itinerary the race does not drive costs
GATE_RADIUS = 8.0          # the lanes the game finds around a gate
_nudged = {}                # the places whose gate would have to move
GAME_TURN_LIMIT = 179.0   # the game has a connector for every turn of a junction
CONNECTOR_COST = 8.0     # the length of the connector of a junction, in metres
TURN_COST = 25.0         # the plan gap and the connector of a turn, in metres
HAIRPIN_COST = 600.0      # the hairpin cost of the game
HAIRPIN_FREE = 100.0      # a turn below this costs nothing
TWIN_DISTANCE = 2.0       # the junctions of a road that meet this close
TWIN_SHARE = 0.75         # the turn of the connector the game builds there


# ---------------------------------------------------------------- geometry

def _lane_centre(road, s, direction):
    """The lane centre point and heading at the distance `s`."""
    count = road.lanes_fwd if direction > 0 else road.lanes_back
    # the lane in the middle of the carriageway (the left of the two middle lanes when the count is even): the gate is then within
    # a lane width of every lane of its direction and all of them can serve it
    index = max(0, (count - 1) // 2)
    lines = [line for line, d in lane_centres(road) if d == direction]
    if len(lines) > index:
        line = lines[index]
        i = _station_index(road, s)
        a, b = line[i], line[i + 1]
        span = road.dist[i + 1] - road.dist[i]
        t = 0.0 if span <= 0.0 else min(1.0, max(0.0, (s - road.dist[i]) / span))
        p = [a[k] + (b[k] - a[k]) * t for k in range(3)]
        h = math.degrees(math.atan2(b[0] - a[0], -(b[2] - a[2]))) % 360.0
        if direction < 0:
            h = (h + 180.0) % 360.0
        return p, h
    return road.lane_point(s, direction, index), road.lane_heading(s, direction)


def _station_index(road, s):
    """The index of the point of the road that holds the station `s`."""
    for i in range(len(road.dist) - 1):
        if s < road.dist[i + 1]:
            return i
    return len(road.dist) - 2


def _grid(road, direction):
    """The station of the grid: GRID_MARGIN behind the start of the road."""
    if direction > 0:
        return min(GRID_MARGIN, road.length() * 0.5)
    return max(road.length() - GRID_MARGIN, road.length() * 0.5)


def _finish(road, direction):
    """The station of the finish: FINISH_MARGIN before the end of the road."""
    if direction > 0:
        return max(road.length() - FINISH_MARGIN, road.length() * 0.5)
    return min(FINISH_MARGIN, road.length() * 0.5)


def _mark(road, s, direction):
    """The mark on a lane: x, y, z and the heading."""
    p, h = _lane_centre(road, s, direction)
    return [round(p[0], 1), round(p[1], 1), round(p[2], 1), round(h, 1)]


def _node_pos(segments, node):
    """The station of a graph node: the junction the traffic stands on.

    The traffic of a stretch in the direction 1 runs from its start to its
    end; in the direction -1 it runs from its end to its start.  The node
    is the stretch the traffic enters at the junction, so the station of
    the node is where the traffic enters it.  A junction at the end of a
    road has no stretch after it: the node is the stretch before it.
    """
    rid, direction, index = node
    segs = segments.get(rid) or []
    if index >= len(segs):
        return segs[-1][1] if segs else 0.0
    if direction > 0:
        if index + 1 >= len(segs):
            return segs[index][1]
        return segs[index][0]
    if index == 0:
        return segs[index][0]
    return segs[index][1]


def _transition(a, dir_a, b, dir_b, adj, segments, rid, junctions):
    """The stations where the route changes from road a to road b.

    The station of a junction on a road is the place where the road meets
    it.  The node of the lane graph is the stretch the traffic enters at
    the junction, and a road that ends at a junction has no stretch after
    it: the node is then the stretch before it and its station is not the
    junction.
    """
    for junction in junctions:
        if a.id in junction["roads"] and b.id in junction["roads"]:
            if not _moves(a, dir_a, b, dir_b, adj):
                sys.stderr.write("route %s: %s -> %s is not a crossing of "
                                 "the plan, the map drives it the other "
                                 "way\n" % (rid, a.id, b.id))
                return None
            return (_s_of_point(a, junction["x"], junction["z"]),
                    _s_of_point(b, junction["x"], junction["z"]))
    # the roads do not meet at a junction: one of them is attached to the
    # other (a ramp, the spiral, the bridge)
    for key, at_start in (("attach_start", True), ("attach_end", False)):
        att = b.get(key)
        if att and att.get("road") == a.id:
            return (att["at"], _attached(road=b, at_start=at_start,
                                         direction=dir_b))
        att = a.get(key)
        if att and att.get("road") == b.id:
            return (_attached(road=a, at_start=at_start, direction=dir_a),
                    att["at"])
    sys.stderr.write("route %s: %s -> %s is not a crossing of the "
                     "plan, the map drives it the other way\n"
                     % (rid, a.id, b.id))
    return None


def _moves(a, dir_a, b, dir_b, adj):
    """True when the lane graph drives from road a to road b."""
    for node_a, dsts in adj.items():
        if node_a[0] != a.id or node_a[1] != dir_a:
            continue
        for node_b, _length in dsts:
            if node_b[0] == b.id and node_b[1] == dir_b:
                return True
    return False


def _attached(road, at_start, direction):
    """The station of an attached road where the traffic of the route is.

    The traffic of a road in the direction 1 enters it at its start and
    leaves it at its end; in the direction -1 it is the other way round.
    """
    if direction > 0:
        return 0.0 if at_start else road.length()
    return road.length() if at_start else 0.0


def _spans(roads, segments, adj, rid, junctions):
    """The stretch of every road of the itinerary that the route drives."""
    spans = []
    last = len(roads) - 1
    for i, (road, direction) in enumerate(roads):
        entry = exit_ = None
        if i:
            entry = _transition(roads[i - 1][0], roads[i - 1][1], road,
                                direction, adj, segments, rid, junctions)
        if i < last:
            exit_ = _transition(road, direction, roads[i + 1][0],
                                roads[i + 1][1], adj, segments, rid, junctions)
        if (i and entry is None) or (i < last and exit_ is None):
            sys.stderr.write("route %s: %s has no crossing in the map, "
                             "the road is left out\n" % (rid, road.id))
            continue
        s_in = _grid(road, direction) if i == 0 else entry[1]
        s_out = _finish(road, direction) if i == last else exit_[0]
        s_in = min(max(s_in, 0.0), road.length())
        s_out = min(max(s_out, 0.0), road.length())
        if direction > 0 and s_out < s_in:
            s_out = s_in
        if direction < 0 and s_out > s_in:
            s_out = s_in
        spans.append((road, direction, s_in, s_out))
    return spans


def _leg_samples(span, segments, step=SAMPLE_STEP):
    """The places of one stretch of road, every `step` metres.

    The traffic of a road in the direction -1 runs from the end of the road
    to its start: the first place of the stretch is just before the entry
    and the last one just after the exit.
    """
    road, direction, s_in, s_out = span
    if direction > 0:
        start, end = s_in + 0.6, s_out - 0.6
    else:
        start, end = max(s_in - 0.6, 0.0), s_out + 0.6
    if direction > 0 and end < start:
        end = start
    if direction < 0 and end > start:
        end = start
    n = max(1, int(abs(end - start) / step))
    out = []
    for k in range(n + 1):
        s = start + (end - start) * k / n
        for a, b in segments.get(road.id) or []:
            if abs(s - a) <= 0.5:
                s = _clear_of(road, a, direction)
                break
            if abs(s - b) <= 0.5:
                s = _clear_of(road, b, direction)
                break
        out.append((road, direction, s))
    return out


def _clear_of(road, s, direction):
    """The station beside a split of the road, on the side the traffic
    comes from."""
    if direction > 0:
        return min(s + 0.6, road.length())
    return max(s - 0.6, 0.0)


def _place_id(place):
    """The place as the graph wants it: (road id, direction, station)."""
    return (place[0].id, place[1], place[2])


# ---------------------------------------------------------------- the itinerary

def _itinerary_stations(spans, segments):
    """The stations of the itinerary, their distance along it and the
    indices of the corners (the places where the itinerary changes road).

    The distance is the one the race drives: the length of the road
    between two stations of the same stretch.  A junction costs nothing:
    the traffic of the two roads meets there.
    """
    out = []
    corners = []
    total = 0.0
    prev = None
    for span in spans:
        corners.append(len(out))
        for sample in _leg_samples(span, segments):
            if prev is not None:
                total += _step(prev, sample)
            out.append((sample, total))
            prev = sample
    return out, corners


def _step(a, b):
    """The distance of the itinerary between two neighbouring stations."""
    if a[0] is b[0] and a[1] == b[1]:
        return abs(b[2] - a[2])
    return 0.0


# ---------------------------------------------------------------- the route

def _checkpoints(spans, adj, segments, game, rid, by_id=None):
    """The places of the route.

    The race drives the shortest way through the map between two gates, so
    every leg of the route is 300 to 500 m long and the way the race takes
    is the way of the itinerary: a gate stands where the itinerary turns, so
    the race turns there too.  The distance is measured along the itinerary
    and not along the shortest way, or a route that comes back near itself
    would lose the gates of the whole loop to a cross street.
    """
    stations, _corners = _itinerary_stations(spans, segments)
    if not stations:
        return []
    roads = set(span[0].id for span in spans)
    places = _gates(stations, adj, segments, game, roads, by_id)
    return [(p[0], p[1], _nudge_clear(p[0], p[2], p[1])) for p in places]


def _gates(stations, adj, segments, game, roads, by_id=None):
    """The places of the gates.

    The search walks the itinerary and takes, for every leg, the place
    where the way the race drives is the way of the itinerary and the leg
    is 300 to 500 m long.  A leg the map can shorten (a side street that is
    shorter than the corner the itinerary turns) is the last resort.
    """
    last = len(stations) - 1
    memo = {}

    def from_here(i):
        """The gates from the station i to the end of the route, and the
        parts of the way that leave the itinerary, or None."""
        if i in memo:
            return memo[i]
        memo[i] = None
        if len(memo) > GATE_STATES:
            return None
        std = _reach(adj, segments, stations[i][0])
        mod = _reach(game, segments, stations[i][0], _crossing_cost, by_id)
        best = None
        for j, missed in _candidates(stations, i, std, mod, segments, roads):
            rest = from_here(j)
            if rest is None:
                continue
            off = _off_route(_leg(mod, stations[j][0], segments,
                                  straight=False)[1], roads, segments)
            cost = (off + _junction_penalty(stations[j][0], segments) +
                    MISSED_COST * missed + rest[0])
            if best is None or cost < best[0]:
                best = (cost, [i] + rest[1])
        if best is None:
            # the route ends before the end of the last road
            if last != i and stations[last][1] - stations[i][1] < CHECKPOINT_MIN:
                memo[i] = (0, [i])
                return memo[i]
            return None
        memo[i] = best
        return best

    out = from_here(0)
    if out is None:
        return _even_places(stations)
    return [stations[i][0] for i in out[1]]


def _candidates(stations, i, std, mod, segments, roads):
    """The stations a leg from the station i can end at, the best first.

    The rule measures the shortest way through the map between two gates
    and wants it 300 to 500 m long: a leg the map can shorten is a leg the
    race does not drive on the itinerary.  A leg is better when the way the
    race drives is the way of the itinerary and when the gates are
    CHECKPOINT_SPACING metres apart on the itinerary.
    """
    out = []
    arc_roads = set()
    d0 = stations[i][1]
    for j in range(i + 1, len(stations)):
        arc = stations[j][1] - d0
        if arc < CHECKPOINT_MIN:
            continue
        if arc > CHECKPOINT_MAX + 100.0:
            break
        d, _path = _leg(std, stations[j][0], segments)
        if d is None or not (CHECKPOINT_MIN + 2.0 <= d <= CHECKPOINT_MAX - 2.0):
            # the rule measures the shortest way through the map: a leg
            # shorter than CHECKPOINT_MIN is a leg the map can shorten
            continue
        if not _clear(stations[j][0]):
            # the gate would have to move to find a lane: the move would
            # change the length of the leg
            continue
        _d2, path = _leg(mod, stations[j][0], segments, straight=False)
        arc_roads.add(stations[j][0][0].id)
        missed = len(arc_roads - _roads_of(path))
        out.append((_off_route(path, roads, segments) +
                    _junction_penalty(stations[j][0], segments) +
                    MISSED_COST * missed,
                    abs(arc - CHECKPOINT_SPACING), j, missed))
    out.sort()
    return [(j, missed) for _cost, _gap, j, missed in out]


def _even_places(stations):
    """The places of the gates every CHECKPOINT_SPACING metres of the
    itinerary: the last resort, when no leg can be kept on the itinerary."""
    places = [stations[0][0]]
    last_d = 0.0
    index = 1
    while index < len(stations):
        if stations[index][1] - last_d < CHECKPOINT_SPACING:
            index += 1
            continue
        spot, last_d, index = _refine(stations, index, last_d + CHECKPOINT_SPACING)
        places.append(spot)
    return places


def _reach(adj, segments, place, crossings=None, by_id=None):
    """The driven distances and the ways from a place to every node.

    The place lies inside a stretch of road: the traffic drives the rest of
    the stretch to the junction at its end and goes on there, straight ahead
    or onto one of the other roads of the junction.  The cost of that
    junction (the connector of the game) is part of the way.
    """
    node = _next_node(segments, _place_id(place))
    if node is None:
        return None
    base = node[1]
    cross = 0.0
    if crossings is not None:
        cross = crossings(adj, segments, place, node[0])
    dist = {node[0]: cross}
    prev = {}
    heap = [(cross, node[0])]
    for nxt, extra in _turns(adj, segments, place, by_id):
        if extra < dist.get(nxt, 1e18):
            dist[nxt] = extra
            heapq.heappush(heap, (extra, nxt))
    while heap:
        d, cur = heapq.heappop(heap)
        if d > dist.get(cur, 1e18):
            continue
        for nxt, length in adj.get(cur, ()):
            nd = d + length
            if nd < dist.get(nxt, 1e18):
                dist[nxt] = nd
                prev[nxt] = cur
                heapq.heappush(heap, (nd, nxt))
    return place, base, dist, prev


def _turns(adj, segments, place, by_id=None):
    """The roads the traffic may turn onto at the junctions around a place,
    and what the turn costs.

    The traffic stands in a stretch of road and drives to the junction at
    its end: the way of the game builds a connector there, and the
    connector of a turn is not the connector of a crossing.  A gate that
    stands at a junction is on the connector of that junction: the race
    starts there and the way from the connector is free.
    """
    rid, direction, station = _place_id(place)
    segs = segments.get(rid) or []
    index = _segment_index(segments, rid, station)
    if index is None or index >= len(segs):
        return []
    a, b = segs[index]
    span = abs(b - a)
    ahead = b if direction > 0 else a
    back = a if direction > 0 else b
    out = []
    for nxt, cost in adj.get((rid, direction, index), ()):
        if nxt[0] == rid:
            continue        # straight on: the reach pays for it
        extra = max(0.0, cost - span)
        if by_id and abs(station - ahead) <= GATE_RADIUS:
            # the race starts on the connector of the junction: it does not
            # drive the stretch in front of the gate
            extra -= abs(ahead - station)
        out.append((nxt, extra))
    # the gate may stand at the junction behind it as well: the race starts
    # on the connector of that junction and drives on from there
    behind = index - 1 if direction > 0 else index + 1
    if not by_id or abs(station - back) > GATE_RADIUS or             behind < 0 or behind >= len(segs):
        return out
    for nxt, cost in adj.get((rid, direction, behind), ()):
        if nxt[0] == rid:
            continue
        # the race starts on the connector of the junction behind the gate:
        # it does not drive the stretch in front of the gate, and it does
        # not drive the connector either
        gap = _gap(by_id, segments, (rid, direction, behind), nxt) if by_id else 0.0
        out.append((nxt, -abs(ahead - station) - gap))
    return out


def _gap(by_id, segments, node, nxt):
    """The distance between the ends of the two lanes a connector joins."""
    here = _cut_point(by_id, segments, node, False)
    there = _cut_point(by_id, segments, nxt, True)
    if here is None or there is None:
        return 0.0
    return math.hypot(there[0] - here[0], there[1] - here[1])


def _cut_point(by_id, segments, node, at_start):
    """The point where the traffic of a node enters or leaves its stretch."""
    rid, direction, index = node
    segs = segments.get(rid) or []
    if index >= len(segs):
        return None
    a, b = segs[index]
    if direction > 0:
        s = a if at_start else b
    else:
        s = b if at_start else a
    return _point_at(by_id[rid], s)


def _leg(reach, place, segments, straight=True):
    """The driven distance from a gate to a place and the roads of the way.

    With `straight` the way of one road is the road itself, the way the
    rule measures; without it the way may leave the road, the way the game
    drives.
    """
    if reach is None:
        return None, None
    last, base, dist, prev = reach
    if straight and place[0] is last[0] and place[1] == last[1]:
        d = (place[2] - last[2]) if place[1] > 0 else (last[2] - place[2])
        return d, [last[0].id]
    node = _previous_node(segments, _place_id(place))
    if node is None or node[0] not in dist:
        return None, None
    seq = [node[0]]
    while seq[-1] in prev:
        seq.append(prev[seq[-1]])
    seq.reverse()
    return base + dist[node[0]] + node[1], seq


def _roads_of(path):
    """The roads a way drives."""
    out = set()
    for node in path or ():
        out.add(node if isinstance(node, str) else node[0])
    return out


def _off_route(path, roads, segments=None):
    """The metres of the driven way that are not on the roads of the route.

    The dead-end links of the map join two roads: the race may drive
    through one, but it is not a road of the route and the way that uses
    it leaves the route.
    """
    if path is None:
        return 1e9
    off = 0.0
    for node in path:
        if isinstance(node, str):
            if node not in roads:
                off += 1.0
            continue
        if node[0] in roads:
            continue
        off += _segment_length(segments, node)
    return off


def _segment_length(segments, node):
    """The length of the stretch of road the traffic drives on the node."""
    if segments is None:
        return 0.0
    segs = segments.get(node[0]) or []
    if node[2] >= len(segs):
        return 0.0
    a, b = segs[node[2]]
    return abs(b - a)


def _refine(stations, index, target):
    """The place of the gate at the itinerary distance `target`.

    The place and the distance along the itinerary, and the station the
    search for the next gate starts at.
    """
    j = index
    while j < len(stations) - 1 and stations[j][1] < target:
        j += 1
    if j == 0:
        return stations[0][0], stations[0][1], 1
    before, after = stations[j - 1], stations[j]
    road, direction = before[0][0], before[0][1]
    if road is not after[0][0] or direction != after[0][1]:
        # the target falls in a junction: the gate stands on the road after it
        return after[0], after[1], j + 1
    return (road, direction, _bisect(before, after, target)), target, j + 1


def _bisect(before, after, target):
    """The station between two stations where the itinerary distance is the
    target.  `before` is the end where the distance is still short."""
    s0, s1 = before[0][2], after[0][2]
    step = 1.0 if s1 >= s0 else -1.0
    s = s0 + step * (target - before[1])
    return min(max(s, min(s0, s1)), max(s0, s1))


def _clear(place):
    """True when the gate of the place stands on a lane where it is."""
    road, direction, s = place
    if _nudged.get((road.id, direction, s)) is None:
        _nudged[(road.id, direction, s)] = (_nudge_clear(road, s, direction) == s)
    return _nudged[(road.id, direction, s)]


def _junction_clear(road):
    """How far from a junction the game cuts the lanes of a road.

    The kerb of a road stops where the junction takes over: the cut reaches
    a little past the kerb line, so the lanes of the road are gone for a
    distance that grows with the width of the road.
    """
    half = 0.5 * (road.lanes_fwd + road.lanes_back) * road.lane_width
    return half + 0.5 * road.get("median", 0.0) + JUNCTION_CLEAR


def _near_junction(place, segments):
    """How far the gate stands from the nearest junction of its road."""
    road, direction, s = place
    best = 1e18
    for a, b in segments.get(road.id) or ():
        best = min(best, abs(s - a), abs(s - b))
    return best


def _junction_penalty(place, segments):
    """What a gate near a junction costs: the game cuts the lanes there.

    A gate that stands in the cut has no lane to sit on, and the race
    cannot reach it, so the search avoids the junctions when it can.
    """
    clear = _junction_clear(place[0])
    near = _near_junction(place, segments)
    if near >= clear:
        return 0.0
    return JUNCTION_COST * (clear - near) / clear


def _nudge_clear(road, s, direction):
    """The station moved to a place where the lane under the mark is
    clear and inside the map window."""
    import build_city
    win = build_city.WINDOW
    # the station itself first (step 0): a mark that is already clear and inside the window stays where it is
    for step in (0.0, 2.0, 4.0, 8.0, 14.0, 22.0, 32.0, 45.0):
        for sign in (-1.0, 1.0):
            if step == 0.0 and sign > 0.0:
                continue
            t = s + sign * step
            if not TRIM <= t <= road.length() - TRIM:
                continue
            p, h = _lane_centre(road, t, direction)
            found = lane_at(road, (p[0], p[2]), p[1], h)
            if found is None or found[0] >= 0.5:
                continue
            if abs((found[3] - h + 180.0) % 360.0 - 180.0) >= 10.0:
                continue
            if not (win["x_min"] <= p[0] <= win["x_max"]
                    and win["z_min"] <= p[2] <= win["z_max"]):
                continue
            return t
    return s


def _route(rid, title, kind, seq, by_id, adj, segments, game, junctions):
    """One route of the map."""
    roads = [(by_id.get(r), d) for r, d in seq]
    roads = [(r, d) for r, d in roads if r is not None]
    if not roads:
        return None
    spans = _spans(roads, segments, adj, rid, junctions)
    places = _checkpoints(spans, adj, segments, game, rid, by_id)
    if len(places) < 2:
        return None
    out = [_mark(road, s, direction) for road, direction, s in places]
    return {
        "id": rid, "title": title, "laps": 1, "kind": kind,
        "checkpoints": out,
        "grid": list(out[0]),
        # the itinerary: [road id, direction of the traffic]
        "segments": [[road.id, direction] for road, direction, _s0, _s1
                     in spans],
    }


def build_routes(by_id, junctions=None):
    """The race routes of the map."""
    city = {"roads": [r.to_dict() for r in by_id.values()],
            "junctions": list(junctions or [])}
    adj, segments = build_lane_graph(city)
    game, _segments = _game_graph(city, by_id)
    out = []
    for rid, title, kind, seq in ROUTE_SPECS:
        route = _route(rid, title, kind, seq, by_id, adj, segments, game,
                       city["junctions"])
        if route:
            out.append(route)
    return out


# ------------------------------------------------------- the way the game drives

def _game_graph(city, by_id):
    """The lane graph of the game, and the segments of the roads.

    The game has a connector for every turn of a junction, so the sharp
    turns the Python graph refuses are driven; every junction costs the
    plan gap of the connector and a turn of more than 100 degrees costs the
    hairpin cost of the game.  Where two junctions of a road meet within a
    metre, the connector of the game turns back on itself and costs the
    hairpin too.
    """
    import city_rules_graph
    old = city_rules_graph.TURN_LIMIT
    city_rules_graph.TURN_LIMIT = GAME_TURN_LIMIT
    try:
        adj, segments = build_lane_graph(city)
    finally:
        city_rules_graph.TURN_LIMIT = old
    twins = _twinned(city, by_id)
    return _junction_costs(adj, segments, by_id, twins), segments


def _twinned(city, by_id):
    """The stations of the junctions where two junctions of a road meet.

    The game joins such a pair into one connector that turns back on
    itself: the traffic that drives on pays the hairpin cost.
    """
    out = {}
    for road in by_id.values():
        spots = []
        for junction in city.get("junctions", ()):
            if road.id not in junction["roads"]:
                continue
            spots.append(_s_of_point(road, junction["x"], junction["z"]))
        spots.sort()
        for a, b in zip(spots, spots[1:]):
            if b - a < TWIN_DISTANCE:
                out.setdefault(road.id, []).append((a + b) / 2.0)
    return out


def _junction_costs(adj, segments, by_id, twins):
    """The lane graph with the cost of the game."""
    out = {}
    for node, dsts in adj.items():
        row = []
        for nxt, length in dsts:
            if length:
                # along a road: the edge crosses a junction
                cost = length
                if nxt[0] == node[0]:
                    cost += CONNECTOR_COST
                    if _twin(segments, node, nxt, twins):
                        cost += HAIRPIN_COST * TWIN_SHARE * TWIN_SHARE
                row.append((nxt, cost))
                continue
            angle = _angle_diff(_flow(by_id, segments, node),
                                _flow(by_id, segments, nxt))
            share = max(0.0, min(1.0, (angle - HAIRPIN_FREE) /
                                 (180.0 - HAIRPIN_FREE)))
            # the traffic drives the stretch it leaves before it turns
            row.append((nxt, _segment_span(segments, node) + TURN_COST +
                        HAIRPIN_COST * share * share))
        out[node] = row
    return out


def _lane_end(by_id, segments, node):
    """The point where the traffic leaves the stretch of a node."""
    rid, direction, index = node
    segs = segments.get(rid) or []
    if index >= len(segs):
        return None
    a, b = segs[index]
    s = b if direction > 0 else a
    return _point_at(by_id[rid], s)


def _lane_start(by_id, segments, node):
    """The point where the traffic enters the stretch of a node."""
    rid, direction, index = node
    segs = segments.get(rid) or []
    if index >= len(segs):
        return None
    a, b = segs[index]
    s = a if direction > 0 else b
    return _point_at(by_id[rid], s)


def _point_at(road, s):
    """The point of a road at the distance `s`, as a pair of coordinates."""
    point = point_at_distance(road["points"], s)[0]
    return point[0], point[2]


def _lane_heading(by_id, segments, node, at_end):
    """The heading of the traffic of a node at the end of its stretch."""
    rid, direction, index = node
    segs = segments.get(rid) or []
    if index >= len(segs):
        return None
    a, b = segs[index]
    if at_end:
        s = b if direction > 0 else a
    else:
        s = a if direction > 0 else b
    heading = _heading_at(by_id[rid], s)
    if direction < 0:
        heading = (heading + 180.0) % 360.0
    return heading


def _segment_span(segments, node):
    """The length of the stretch of road the traffic drives on a node."""
    segs = segments.get(node[0]) or []
    if node[2] >= len(segs):
        return 0.0
    a, b = segs[node[2]]
    return abs(b - a)


def _crossing_cost(adj, segments, place, node):
    """The cost of the connector the game builds at the junction a place
    leaves.

    The place lies inside a stretch of road; the traffic drives the rest of
    the stretch and crosses the junction at its end.  The Python graph
    gives the junction for free, so the cost is nothing there.
    """
    rid, direction, station = _place_id(place)
    segs = segments.get(rid) or []
    if not segs:
        return 0.0
    index = _segment_index(segments, rid, station)
    if index is None or index >= len(segs):
        return 0.0
    length = abs(segs[index][1] - segs[index][0])
    for nxt, cost in adj.get((rid, direction, index), ()):
        if nxt == node:
            return max(0.0, cost - length)
    return 0.0


def _segment_index(segments, rid, station):
    """The index of the stretch of road that holds the station."""
    for i, (a, b) in enumerate(segments.get(rid) or ()):
        if a - 0.5 <= station <= b + 0.5:
            return i
    return None


def _twin(segments, node, nxt, twins):
    """True when the edge crosses a junction where two junctions meet."""
    spots = twins.get(node[0])
    if not spots:
        return False
    segs = segments.get(node[0]) or []
    if node[1] > 0:
        station = segs[node[2]][1]
    else:
        station = segs[node[2]][0]
    for spot in spots:
        if abs(spot - station) < TWIN_DISTANCE:
            return True
    return False


def _flow(by_id, segments, node):
    """The heading of the traffic of a node where it leaves its segment."""
    rid, direction, index = node
    segs = segments.get(rid) or []
    if index >= len(segs):
        return 0.0
    a, b = segs[index]
    heading = _heading_at(by_id[rid], b if direction > 0 else a)
    if direction > 0:
        return heading
    return (heading + 180.0) % 360.0


def build_spawns(by_id, pois):
    """The player and the police spawns (they sit on lane centres)."""
    bund = by_id.get("bund_zhongshan_e1")
    player = [0.0, 0.0, 0.0, 0.0]
    if bund is not None:
        player = _mark(bund, _nearest_s(bund, (-118.0, -250.0)), -1)
    police = []
    for poi in pois:
        if poi["kind"] != "police_station":
            continue
        road = _nearest_road(by_id, (poi["x"], poi["z"]))
        if road is None:
            continue
        s = _nearest_s(road, (poi["x"], poi["z"]))
        police.append(_mark(road, s, 1))
    return {"player": player, "police": police, "traffic_density": 1.0}


def _nearest_road(by_id, point):
    """The road whose centre-line is closest to the plan position."""
    best, best_road = 1e18, None
    for road in by_id.values():
        d = _nearest_s(road, point)
        p = road.point_at(d)[0]
        dist = math.hypot(p[0] - point[0], p[2] - point[1])
        if dist < best:
            best, best_road = dist, road
    return best_road
