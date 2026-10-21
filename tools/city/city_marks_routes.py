"""city_marks_routes — the race routes and the spawn points of the map.

The itinerary of a route is a list of roads with the direction of the
traffic; the route enters and leaves every road at the point where it
meets the road before and the road after it.  The checkpoints lie on the
lane centres, every CHECKPOINT_SPACING metres along the driven path.
"""
import math

from city_marks import _nearest_s
from city_rules_graph import build_lane_graph, driven_distance


# ---------------------------------------------------------------- routes

ROUTE_SPECS = [
    # dossier 10.6: Bund S -> Yan'an E. Rd -> Yan'an Elevated W -> the
    # dragon's left turn ramp -> N-S S -> Inner Ring E -> the spiral ->
    # Nanpu -> the Pudong loop -> Pudong South Rd N -> Century Ave W ->
    # the tunnel W -> Henan Rd N -> Nanjing E. Rd E -> the Bund.
    ("grand_loop", "申城大环线", "race", [
        ("bund_zhongshan_e1", -1), ("yanan_rd_surface", -1),
        ("yanan_elevated", -1), ("ramp_l3_wb_sb", 1), ("ns_elevated", 1),
        ("inner_ring", 1), ("nanpu_spiral_upper", 1), ("nanpu_bridge", 1),
        ("nanpu_pudong_loop", 1), ("pudong_south_rd", -1),
        ("century_ave", -1), ("yanan_tunnel", -1), ("st_henan_portal", 1),
        ("st_henan_rd", 1), ("st_nanjing_e_rd", -1), ("bund_zhongshan_e1", 1)]),
    ("elevated_sprint", "高架冲刺", "sprint", [
        ("g50_west", 1), ("yanan_elevated", 1), ("ramp_l3_eb_nb", 1),
        ("ns_elevated", 1), ("ramp_l4_sb_eb", 1), ("yanan_elevated", 1),
        ("yanan_rd_surface", 1), ("bund_zhongshan_e1", 1)]),
    ("river_loop", "滨江环线", "pursuit", [
        ("bund_zhongshan_e1", -1), ("zhongshan_e2_s", 1),
        ("nanpu_spiral_lower", 1), ("nanpu_spiral_upper", 1),
        ("nanpu_bridge", 1), ("nanpu_pudong_loop", 1), ("pudong_south_rd", -1),
        ("century_ave", -1), ("yanan_tunnel", -1), ("st_henan_portal", 1),
        ("st_henan_rd", 1), ("st_nanjing_e_rd", -1), ("bund_zhongshan_e1", 1)]),
    ("bund_sprint", "外滩冲刺", "sprint", [
        ("bund_zhongshan_e1", -1), ("st_nanjing_e_rd", -1),
        ("st_henan_rd", -1), ("st_henan_portal", -1), ("yanan_tunnel", 1),
        ("century_ave", 1)]),
    ("lujiazui_ring", "陆家嘴环线", "race", [
        ("lujiazui_ring_rd", 1), ("century_ave", -1),
        ("lujiazui_ring_rd", -1)]),
]

CHECKPOINT_SPACING = 400.0
CHECKPOINT_MIN = 300.0    # the shortest leg of a route
SAMPLE_STEP = 20.0        # the step of the walk along the itinerary
GRID_MARGIN = 150.0      # the road that has to be behind the grid
FINISH_MARGIN = 60.0     # the road between the finish and the junction


def _lane_centre(road, s, direction):
    """The lane centre point and heading at the distance `s`."""
    index = 0
    if direction > 0:
        index = max(0, road.lanes_fwd // 2 - 1)
    else:
        index = max(0, road.lanes_back // 2 - 1)
    p = road.lane_point(s, direction, index)
    h = road.lane_heading(s, direction)
    return p, h


def _connect(a, b):
    """The point where two roads meet (the closest pair of points)."""
    best, best_p = 1e18, None
    for p in a.points:
        for q in b.points:
            d = math.hypot(p[0] - q[0], p[2] - q[2])
            if d < best:
                best, best_p = d, (p, q)
    return best, best_p


def _entry_s(prev, road):
    """The distance along `road` where a route enters it from `prev`."""
    att = road.attach_start
    if att and att["road"] == prev.id:
        return 0.0
    if prev.attach_end and prev.attach_end["road"] == road.id:
        return prev.attach_end["at"]
    d, pair = _connect(prev, road)
    return _nearest_s(road, (pair[1][0], pair[1][2]))


def _exit_s(road, nxt):
    """The distance along `road` where a route leaves it for `nxt`.

    The `at` of an attach is the distance along its *parent*, so the
    attach of the next road gives the place where the route leaves this
    one.
    """
    att = nxt.attach_start
    if att and att["road"] == road.id:
        return att["at"]
    if road.attach_end and road.attach_end["road"] == nxt.id:
        return road.length()
    d, pair = _connect(road, nxt)
    return _nearest_s(road, (pair[0][0], pair[0][2]))


def build_routes(by_id, junctions=None):
    """The race routes of the map (dossier 10.6).

    The itinerary is a list of roads with the direction of the traffic; the
    route enters and leaves every road at the point where it meets the
    road before and the road after it.  The checkpoints lie on the lane
    centres, every CHECKPOINT_SPACING metres along the *driven* path: the
    distance is measured on the lane graph, so a route that changes road
    pays for the way to the junction.
    """
    city = {"roads": [r.to_dict() for r in by_id.values()],
            "junctions": list(junctions or [])}
    adj, segments = build_lane_graph(city)
    out = []
    for rid, title, kind, seq in ROUTE_SPECS:
        route = _route(rid, title, kind, seq, by_id, adj, segments)
        if route:
            out.append(route)
    return out


def _route(rid, title, kind, seq, by_id, adj, segments):
    """One route of the map."""
    roads = [(by_id.get(r), d) for r, d in seq]
    roads = [(r, d) for r, d in roads if r is not None]
    if not roads:
        return None
    spans = _spans(roads)
    checkpoints = _checkpoints(spans, adj, segments)
    if len(checkpoints) < 2:
        return None
    return {
        "id": rid,
        "title": title,
        "laps": 1,
        "kind": kind,
        "checkpoints": checkpoints,
        "grid": list(checkpoints[0]),
        # the itinerary: [road id, direction of the traffic]
        "segments": [[road.id, direction] for road, direction, _s0, _s1
                     in spans],
    }


def _spans(roads):
    """The stretch of every road of the itinerary that the route drives."""
    spans = []
    for i, (road, direction) in enumerate(roads):
        if i == 0:
            # the grid stands back from the end of the road, so the
            # rivals have room behind it
            s_in = min(GRID_MARGIN, road.length() * 0.5) \
                if direction > 0 else max(road.length() - GRID_MARGIN,
                                          road.length() * 0.5)
        else:
            s_in = _entry_s(roads[i - 1][0], road)
        if i == len(roads) - 1:
            # the finish stands clear of the junction it comes from
            s_out = max(road.length() - FINISH_MARGIN, road.length() * 0.5) \
                if direction > 0 else min(FINISH_MARGIN, road.length() * 0.5)
        else:
            s_out = _exit_s(road, roads[i + 1][0])
        # the traffic drives forward: the exit lies ahead of the entry
        if direction > 0 and s_out < s_in:
            s_out = road.length()
        if direction < 0 and s_out > s_in:
            s_out = 0.0
        spans.append((road, direction, s_in, s_out))
    return spans


def _checkpoints(spans, adj, segments):
    """The checkpoints of a route, every CHECKPOINT_SPACING driven metres.

    The distance is the shortest driven path between two places, the same
    distance the world unit uses for the racing line, so the checkpoints
    are 400 m apart along the line the car really drives.
    """
    samples = _samples(spans)
    places = []
    last = None
    for place in samples:
        if last is None:
            last = place
            continue
        d = driven_distance(adj, segments, _place_id(last), _place_id(place))
        if d is None:
            continue
        if d >= CHECKPOINT_SPACING:
            spot = _refine(adj, segments, last, place, d)
            places.append(spot)
            last = spot
    if not places:
        return []
    end = samples[-1]
    tail = driven_distance(adj, segments, _place_id(places[-1]), _place_id(end))
    if tail is None or tail < CHECKPOINT_MIN:
        # the finish stands on the last checkpoint: the one before it has
        # to be far enough away
        if len(places) > 1:
            places.pop()
        places.append(end)
    else:
        places.append(end)
    out = []
    for road, direction, s in places:
        p, h = _lane_centre(road, s, direction)
        out.append([round(p[0], 1), round(p[1], 1), round(p[2], 1), round(h, 1)])
    return out


def _place_id(place):
    """The place as the graph wants it: (road id, direction, station)."""
    return (place[0].id, place[1], place[2])


def _samples(spans, step=SAMPLE_STEP):
    """The places along the route, every `step` metres of the itinerary."""
    out = []
    for road, direction, s_in, s_out in spans:
        length = abs(s_out - s_in)
        n = max(1, int(length / step))
        for k in range(n + 1):
            s = s_in + (s_out - s_in) * k / n
            out.append((road, direction, s))
    return out


def _refine(adj, segments, a, b, distance):
    """The place between two places where the driven distance is the
    spacing."""
    lo, hi = 0.0, 1.0
    for _ in range(12):
        mid = (lo + hi) * 0.5
        s = a[2] + (b[2] - a[2]) * mid
        d = driven_distance(adj, segments, _place_id(a), (a[0].id, a[1], s))
        if d is None or d < CHECKPOINT_SPACING:
            lo = mid
        else:
            hi = mid
    s = a[2] + (b[2] - a[2]) * (lo + hi) * 0.5
    return (a[0], a[1], s)


def build_spawns(by_id, pois):
    """The player and the police spawns (they sit on lane centres)."""
    bund = by_id.get("bund_zhongshan_e1")
    player = [0.0, 0.0, 0.0, 0.0]
    if bund is not None:
        s = _nearest_s(bund, (-118.0, -250.0))
        p, h = _lane_centre(bund, s, -1)
        player = [round(p[0], 1), round(p[1], 1), round(p[2], 1), round(h, 1)]
    police = []
    for poi in pois:
        if poi["kind"] != "police_station":
            continue
        road = _nearest_road(by_id, (poi["x"], poi["z"]))
        if road is None:
            continue
        s = _nearest_s(road, (poi["x"], poi["z"]))
        p, h = _lane_centre(road, s, 1)
        police.append([round(p[0], 1), round(p[1], 1), round(p[2], 1), round(h, 1)])
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
