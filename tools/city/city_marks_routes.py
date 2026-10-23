"""city_marks_routes — the race routes and the spawn points of the map.

The itinerary of a route is a list of roads with the direction of the
traffic; the route enters and leaves every road where it meets the road
before and the road after it.  The checkpoints lie on the lane centres,
every CHECKPOINT_SPACING metres along the driven path of the lane graph.
"""
import math
import sys

from city_marks import _nearest_s
from city_rules_lanes import lane_at, lane_centres
from city_rules_graph import build_lane_graph, driven_distance


# ---------------------------------------------------------------- routes

ROUTE_SPECS = [
    # the Yan'an elevated road, the dragon interchange, the N-S elevated
    # road, the inner ring, the Nanpu spiral and bridge, the Pudong loop,
    # the Century Ave, the tunnel, the Henan Rd and the Bund
    ("grand_loop", "申城大环线", "race", [
        ("yanan_elevated", 1), ("ramp_rt_eb_sb", 1), ("ns_elevated", 1),
        ("inner_ring", 1), ("nanpu_spiral_upper", 1), ("nanpu_bridge", 1),
        ("nanpu_pudong_loop", 1), ("pudong_south_rd", -1),
        ("century_ave", -1), ("yanan_tunnel", -1), ("st_henan_portal", -1),
        ("st_henan_rd", 1), ("st_d2_ew_4", 1), ("st_nanjing_e_rd", -1),
        ("bund_zhongshan_e1", 1)]),
    # the elevated road, the dragon interchange, the N-S elevated road,
    # the inner ring, the Nanpu spiral and bridge and the tunnel
    ("elevated_sprint", "高架冲刺", "sprint", [
        ("yanan_elevated", 1), ("ramp_rt_eb_sb", 1), ("ns_elevated", 1),
        ("inner_ring", 1), ("nanpu_spiral_upper", 1), ("nanpu_bridge", 1),
        ("nanpu_pudong_loop", 1), ("pudong_south_rd", -1),
        ("century_ave", -1), ("yanan_tunnel", -1)]),
    # the Pudong south road, the Century Ave, the Lujiazui ring road, the
    # Yincheng Rd, the tunnel under the river and the Bund
    ("river_loop", "滨江环线", "pursuit", [
        ("pudong_south_rd", -1), ("century_ave", -1),
        ("lujiazui_ring_rd", -1), ("yincheng_rd", 1),
        ("yanan_tunnel", -1), ("st_henan_portal", -1),
        ("st_henan_rd", 1), ("st_d2_ew_4", 1), ("st_nanjing_e_rd", -1),
        ("bund_zhongshan_e1", 1)]),
    # the Bund, the Nanjing E. Rd, the Henan Rd and the tunnel
    ("bund_sprint", "外滩冲刺", "sprint", [
        ("bund_zhongshan_e1", -1), ("st_nanjing_e_rd", 1),
        ("st_d2_ew_4", -1), ("st_henan_rd", -1), ("st_fujian_portal", 1),
        ("yanan_tunnel", 1)]),
    # the Lujiazui ring road, a closed loop: a lap ends where it began, so the race can run
    # more than one lap (the closing leg of a circuit is a few hundred metres, not a drive across the district)
    ("lujiazui_ring", "陆家嘴环线", "race", [
        ("lujiazui_ring_rd", 1)]),
]

CHECKPOINT_SPACING = 400.0
CHECKPOINT_MIN = 300.0
CHECKPOINT_MAX = 500.0
SAMPLE_STEP = 20.0
GRID_MARGIN = 150.0
FINISH_MARGIN = 60.0


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
    """The station of a graph node: the place the traffic stands on."""
    rid, direction, index = node
    segs = segments.get(rid) or []
    if index >= len(segs):
        return segs[-1][1] if segs else 0.0
    return segs[index][0] if direction > 0 else segs[index][1]


def _transition(a, dir_a, b, dir_b, adj, segments, rid):
    """The stations where the route changes from road a to road b."""
    fallback = None
    for node_a, dsts in adj.items():
        if node_a[0] != a.id:
            continue
        for node_b, _length in dsts:
            if node_b[0] != b.id:
                continue
            if node_b[1] == dir_b and node_a[1] == dir_a:
                return (_node_pos(segments, node_a),
                        _node_pos(segments, node_b))
            if fallback is None:
                fallback = (_node_pos(segments, node_a),
                            _node_pos(segments, node_b))
    if fallback is not None:
        sys.stderr.write("route %s: %s -> %s is not a crossing of the "
                         "plan, the map drives it the other way\n"
                         % (rid, a.id, b.id))
    return fallback


def _spans(roads, segments, adj, rid):
    """The stretch of every road of the itinerary that the route drives."""
    spans = []
    last = len(roads) - 1
    for i, (road, direction) in enumerate(roads):
        entry = exit_ = None
        if i:
            entry = _transition(roads[i - 1][0], roads[i - 1][1], road,
                                direction, adj, segments, rid)
        if i < last:
            exit_ = _transition(road, direction, roads[i + 1][0],
                                roads[i + 1][1], adj, segments, rid)
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
    """The places of one stretch of road, every `step` metres."""
    road, direction, s_in, s_out = span
    if direction > 0:
        start, end = s_in + 0.6, s_out - 0.6
    else:
        start, end = min(s_in + 0.6, road.length()), s_out + 0.6
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
                s = min(a + 0.6, road.length())
                break
            if abs(s - b) <= 0.5:
                s = min(b + 0.6, road.length())
                break
        out.append((road, direction, s))
    return out


def _place_id(place):
    """The place as the graph wants it: (road id, direction, station)."""
    return (place[0].id, place[1], place[2])


# ---------------------------------------------------------------- the route

def _checkpoints(spans, adj, segments, rid):
    """The places of the route, every CHECKPOINT_SPACING driven metres."""
    samples = []
    starts = []
    for span in spans:
        starts.append(len(samples))
        samples.extend(_leg_samples(span, segments))
    places = [samples[0]]
    last = samples[0]
    leg = 0
    for i in range(1, len(samples)):
        while leg + 1 < len(starts) and i >= starts[leg + 1]:
            leg += 1
        cur = samples[i]
        d = driven_distance(adj, segments, _place_id(last), _place_id(cur))
        if d is None:
            _warn(rid, last, cur, "the leg cannot be driven")
            last = cur
            continue
        if d < CHECKPOINT_SPACING:
            continue
        spot = _refine(last, samples, i, spans, leg, adj, segments)
        if spot is None and i:
            # the graph drives a corner cut here: the place before the
            # cut is the checkpoint that fits
            prev = samples[i - 1]
            d = driven_distance(adj, segments, _place_id(last),
                                _place_id(prev))
            if d is not None and CHECKPOINT_MIN <= d <= CHECKPOINT_MAX:
                spot = prev
        if spot is None:
            _warn(rid, last, cur, "no room for a checkpoint")
            last = cur
            continue
        spot = (spot[0], spot[1], _nudge_clear(spot[0], spot[2], spot[1]))
        places.append(spot)
        last = spot
    return places


def _refine(last, samples, i, spans, leg, adj, segments):
    """The place between two samples where the driven distance is the
    spacing, on the road of the sample."""
    cur = samples[i]
    prev = samples[i - 1] if i else last
    road, direction = cur[0], cur[1]
    if prev[0] is road and prev[1] == direction:
        a, b = prev[2], cur[2]
    else:
        # the route changes road: the checkpoint stands on the road of
        # the sample, behind the junction
        a, b = spans[leg][2], cur[2]
    if direction > 0:
        lo, hi = min(a, b), max(a, b)
    else:
        lo, hi = max(a, b), min(a, b)
    d_lo = driven_distance(adj, segments, _place_id(last),
                           (road.id, direction, lo))
    d_hi = driven_distance(adj, segments, _place_id(last),
                           (road.id, direction, hi))
    if d_lo is None or d_hi is None:
        return None
    if d_lo > d_hi:
        lo, hi = hi, lo
        d_lo, d_hi = d_hi, d_lo
    if d_lo >= CHECKPOINT_SPACING or d_hi < CHECKPOINT_SPACING:
        # the spacing does not fit on this stretch: the graph drives a
        # corner cut there and the checkpoint has to wait
        return None
    return _bisect(last, road, direction, lo, hi, adj, segments)


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
            if not 0.0 <= t <= road.length():
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


def _bisect(last, road, direction, lo, hi, adj, segments):
    """The station between lo and hi where the driven distance is the
    spacing.  `lo` is the end where the distance is still short."""
    for _ in range(18):
        mid = (lo + hi) * 0.5
        d = driven_distance(adj, segments, _place_id(last),
                            (road.id, direction, mid))
        if d is None:
            break
        if d < CHECKPOINT_SPACING:
            lo = mid
        else:
            hi = mid
    return (road, direction, (lo + hi) * 0.5)


def _warn(rid, a, b, why):
    """One line on stderr about a leg of the route."""
    sys.stderr.write("route %s: %s -> %s (%s) %s\n"
                     % (rid, a[0].id, b[0].id, why, _place_id(a)[2:]))


def _with_finish(places, spans, adj, segments, rid):
    """The checkpoints of a route, the finish on the last one."""
    end = _leg_samples(spans[-1], segments)[-1]
    if not places:
        return [end]
    tail = driven_distance(adj, segments, _place_id(places[-1]), _place_id(end))
    if tail is None:
        return places
    if tail < CHECKPOINT_MIN:
        sys.stderr.write("route %s: the last leg is %.0f m, the route ends "
                         "on the checkpoint before it\n" % (rid, tail))
        return places
    return places + [end]


def _route(rid, title, kind, seq, by_id, adj, segments):
    """One route of the map."""
    roads = [(by_id.get(r), d) for r, d in seq]
    roads = [(r, d) for r, d in roads if r is not None]
    if not roads:
        return None
    spans = _spans(roads, segments, adj, rid)
    places = _checkpoints(spans, adj, segments, rid)
    places = _with_finish(places, spans, adj, segments, rid)
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
    out = []
    for rid, title, kind, seq in ROUTE_SPECS:
        route = _route(rid, title, kind, seq, by_id, adj, segments)
        if route:
            out.append(route)
    return out


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
