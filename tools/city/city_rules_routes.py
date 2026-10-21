"""city_rules_routes — the race routes and the sky lanes.

The route checkpoints must lie on the lane centres, be 300-500 m apart along
the driven path and be reachable; the sky lanes need a pad with a straight
run-up, a first segment on the pad's heading and an end over a drivable lane.
"""
import math

import citylib

ROAD_CLEARANCE = 1.0             # the blocks keep 1 m from a road edge
DECK_CLEARANCE = 2.0             # and 2 m from an elevated deck footprint
LANE_TOLERANCE = 0.5             # a spawn / checkpoint on a lane centre
HEADING_TOLERANCE = 10.0         # degrees
CHECKPOINT_MIN = 300.0           # the distance between two checkpoints
CHECKPOINT_MAX = 500.0
RUN_UP = 300.0                   # the straight run-up of a launch pad
RUN_UP_TURN = 3.0                # degrees of heading change over the run-up
PITCH_LIMIT = 20.0               # degrees over 50 m
SKY_CLEARANCE = 10.0             # the sky lanes clear the blocks by 10 m
RING_SPACING = 250.0             # the N2 rings along a sky lane
LANDMARK_EXEMPT = ("landmark:dragon_pillar", "landmark:nanpu_tower_w",
                   "landmark:nanpu_tower_e")

from city_rules_graph import (_point_and_tangent, _s_of_point,
                              build_lane_graph, driven_distance)
from city_rules_lanes import (_angle_diff, _block_height, lane_at,
                              lane_centres, nearest_lane)


def _segment_of(segments, road_id, s):
    """The segment of the road that holds the station `s`."""
    for a, b in segments.get(road_id, []):
        if a - 0.5 <= s <= b + 0.5:
            return (a, b)
    return None


def check_routes(city):
    """The route checkpoints sit on the lanes, 300-500 m apart, and are
    reachable in the driving direction (review r1 A.5 / A.7 / r2 4c).

    The distance between two checkpoints is the distance *driven* between
    them, measured on the directed lane graph: the graph knows the moves
    of the junctions and of the attaches, so a route that follows a curve
    is as long as the curve and a route that changes road pays for the
    way to the junction.
    """
    fails = []
    adj, segments = build_lane_graph(city)
    by_id = {r["id"]: r for r in city["roads"]}
    for route in city["routes"]:
        fails += _route_fails(route, by_id, adj, segments)
    return fails


def _route_fails(route, by_id, adj, segments):
    """The failures of one route."""
    fails = []
    cps = route["checkpoints"]
    if len(cps) < 3:
        return ["route %s has %d checkpoints" % (route["id"], len(cps))]
    places = []
    for i, cp in enumerate(cps):
        place, msgs = _place_on_lane(route, i, cp, by_id)
        fails += msgs
        places.append(place)
    for i in range(len(places) - 1):
        fails += _leg_fails(route, i, places[i], places[i + 1], adj, segments)
    fails += _itinerary_fails(route, places)
    return fails


def _place_on_lane(route, index, cp, by_id):
    """The lane a checkpoint stands on, and the failures it causes."""
    msgs = []
    best = None
    for road in by_id.values():
        found = lane_at(road, (cp[0], cp[2]), cp[1], cp[3])
        if found is None:
            continue
        key = (_angle_diff(found[3], cp[3]), abs(found[2][1] - cp[1]), found[0])
        if best is None or key < best[0]:
            best = (key, found + (road["id"],))
    if best is None:
        return None, ["route %s cp%02d is not on a lane" % (route["id"], index)]
    found = best[1]
    if found[0] > LANE_TOLERANCE:
        msgs.append("route %s cp%02d is %.2f m from a lane centre"
                    % (route["id"], index, found[0]))
    if abs(found[2][1] - cp[1]) > 0.5:
        msgs.append("route %s cp%02d is %.2f m off the lane height"
                    % (route["id"], index, abs(found[2][1] - cp[1])))
    if _angle_diff(found[3], cp[3]) > HEADING_TOLERANCE:
        msgs.append("route %s cp%02d heads %.0f deg, the lane %.0f"
                    % (route["id"], index, cp[3], found[3]))
    if msgs:
        return None, msgs
    return (found[6], found[4], found[5]), msgs


def _leg_fails(route, index, a, b, adj, segments):
    """The failures of one leg of a route: the distance and the reach."""
    if a is None or b is None:
        return []
    distance = driven_distance(adj, segments, a, b)
    if distance is None:
        return ["route %s: cp%02d cannot be reached from cp%02d"
                % (route["id"], index + 1, index)]
    if distance < 0.0:
        return ["route %s: cp%02d is behind cp%02d"
                % (route["id"], index + 1, index)]
    if distance < CHECKPOINT_MIN - 1.0 or distance > CHECKPOINT_MAX + 1.0:
        return ["route %s: %.0f m between cp%02d and cp%02d"
                % (route["id"], distance, index, index + 1)]
    return []


def _itinerary_fails(route, places):
    """The checkpoints have to follow the itinerary of the route."""
    fails = []
    itinerary = [(rid, direction) for rid, direction in route.get("segments", [])]
    pointer = 0
    for i, place in enumerate(places):
        if place is None:
            continue
        key = (place[0], place[1])
        while pointer < len(itinerary) and itinerary[pointer] != key:
            pointer += 1
        if pointer >= len(itinerary):
            fails.append("route %s: cp%02d is not on the itinerary "
                         "(%s in direction %d)"
                         % (route["id"], i, place[0], place[1]))
    return fails


def check_sky_lanes(city):
    """The sky lanes: the pad, the run-up, the exit and the clearance."""
    fails = []
    by_id = {r["id"]: r for r in city["roads"]}
    for lane in city["sky_lanes"]:
        fails += _pad_fails(lane, by_id)
        fails += _lane_fails(lane)
        fails += _clearance_fails(lane, city)
        fails += _rings_fails(lane)
    return fails


def _pad_fails(lane, by_id):
    """The pad stands on a lane, with a straight run-up behind it."""
    fails = []
    pad = lane["pad"]
    road = None
    best = None
    for r in by_id.values():
        found = nearest_lane(r, (pad["x"], pad["z"]))
        if found and (best is None or found[0] < best[0]):
            best, road = found, r
    if best is None or best[0] > LANE_TOLERANCE:
        return ["lane %s: the pad is %.2f m from a lane centre"
                % (lane["id"], best[0] if best else -1.0)]
    if abs(best[2][1] - pad["y"]) > 0.5:
        fails.append("lane %s: the pad is %.2f m off the lane height"
                     % (lane["id"], abs(best[2][1] - pad["y"])))
    if _angle_diff(best[3], pad["heading_deg"]) > HEADING_TOLERANCE:
        fails.append("lane %s: the pad heads %.0f deg, the lane %.0f"
                     % (lane["id"], pad["heading_deg"], best[3]))
    fails += _run_up_fails(lane, road, pad)
    return fails


def _run_up_fails(lane, road, pad):
    """The straight run-up: 300 m of lane behind the pad that barely turns."""
    fails = []
    s_pad = _s_of_point(road, pad["x"], pad["z"])
    s_start = max(0.0, s_pad - RUN_UP)
    if s_pad - s_start < RUN_UP - 1.0:
        fails.append("lane %s: only %.0f m of run-up behind the pad"
                     % (lane["id"], s_pad - s_start))
    p0, t0 = _point_and_tangent(road, s_start)
    p1, t1 = _point_and_tangent(road, s_pad)
    h0 = math.degrees(math.atan2(t0[0], -t0[1]))
    h1 = math.degrees(math.atan2(t1[0], -t1[1]))
    if _angle_diff(h0, h1) > RUN_UP_TURN:
        fails.append("lane %s: the run-up turns %.1f deg over %.0f m"
                     % (lane["id"], _angle_diff(h0, h1), RUN_UP))
    return fails


def _lane_fails(lane):
    """The shape of the lane: the start at the pad, the pitch, the end."""
    fails = []
    pts = lane["points"]
    a, b = pts[0], pts[1]
    pad = lane["pad"]
    if math.dist((a[0], a[1], a[2]), (pad["x"], pad["y"], pad["z"])) > 1.0:
        fails.append("lane %s: the lane starts %.1f m from the pad"
                     % (lane["id"],
                        math.dist((a[0], a[1], a[2]),
                                  (pad["x"], pad["y"], pad["z"]))))
    head = math.degrees(math.atan2(b[0] - a[0], -(b[2] - a[2]))) % 360.0
    if _angle_diff(head, pad["heading_deg"]) > HEADING_TOLERANCE:
        fails.append("lane %s: the first segment heads %.0f deg, the pad %.0f"
                     % (lane["id"], head, pad["heading_deg"]))
    for i in range(len(pts) - 1):
        run = math.hypot(pts[i + 1][0] - pts[i][0],
                         pts[i + 1][2] - pts[i][2])
        if run < 1.0:
            continue
        rise = pts[i + 1][1] - pts[i][1]
        if run > 60.0:
            pitch = abs(math.degrees(math.atan2(rise, run)))
            if pitch > PITCH_LIMIT:
                fails.append("lane %s: %.0f deg pitch at %.0f m"
                             % (lane["id"], pitch, i))
                break
    return fails


def _clearance_fails(lane, city):
    """The lane clears the lots and ends over a drivable lane."""
    fails = []
    pts = lane["points"]
    blocks = city.get("blocks", [])
    exempt = set(LANDMARK_EXEMPT)
    for i in range(0, len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        run = math.hypot(b[0] - a[0], b[2] - a[2])
        steps = max(1, int(run / 5.0))
        for k in range(steps + 1):
            t = k / steps
            x = a[0] + (b[0] - a[0]) * t
            z = a[2] + (b[2] - a[2]) * t
            y = a[1] + (b[1] - a[1]) * t
            top = _block_height(blocks, x, z, exempt)
            if top and y < top + SKY_CLEARANCE - 0.05:
                fails.append("lane %s: %.0f m over a lot of %.0f m at "
                             "(%.0f, %.0f)"
                             % (lane["id"], y, top, x, z))
                break
        else:
            continue
        break
    end = pts[-1]
    best = None
    for r in city["roads"]:
        if r["kind"] in ("tunnel",):
            continue
        found = lane_at(r, (end[0], end[2]), end[1])
        if found is None:
            continue
        key = (abs(found[2][1] - end[1]), found[0])
        if best is None or key < best[0]:
            best = (key, found)
    best = best[1] if best else None
    if best is None or best[0] > 7.0:
        fails.append("lane %s: the end is %.1f m from a lane"
                     % (lane["id"], best[0] if best else -1.0))
    elif end[1] - best[2][1] > 15.0 or end[1] - best[2][1] < -5.0:
        fails.append("lane %s: the end is %.1f m above the lane"
                     % (lane["id"], end[1] - best[2][1]))
    return fails


def _rings_fails(lane):
    """The N2 rings along the lane."""
    fails = []
    pts = lane["points"]
    rings = lane.get("n2_rings_m", [])
    total = 0.0
    for a, b in zip(pts, pts[1:]):
        total += math.dist((a[0], a[2]), (b[0], b[2]))
    if not rings:
        return ["lane %s has no N2 rings" % lane["id"]]
    if rings[0] > RING_SPACING + 1.0:
        fails.append("lane %s: the first ring is at %.0f m"
                     % (lane["id"], rings[0]))
    for a, b in zip(rings, rings[1:]):
        if b - a > RING_SPACING + 1.0:
            fails.append("lane %s: %.0f m between the rings"
                         % (lane["id"], b - a))
    if total - rings[-1] > RING_SPACING + 60.0:
        fails.append("lane %s: %.0f m after the last ring"
                     % (lane["id"], total - rings[-1]))
    return fails
