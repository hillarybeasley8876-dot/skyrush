"""The links of the lane graph: the movements through a junction and the
attaches of a ramp.

Every approach lane gets at least one movement: a middle lane goes straight
on, with no straight arm it takes the nearer turn, and a one-lane approach may
take every movement. A merge (two arms that run almost parallel) links the
lanes of the two roads without a junction box.
"""
import math

from mathutils import Vector

from city.roads import junctions as jn
from city.roads import lane_paths

CROSS_TOLERANCE = 15.0  # how far a lane end may be from the kerb return
ATTACH_TOLERANCE = 25.0  # how far a lane's end may be from an attach point


def travels_along(lane, arm):
    """True when the lane is travelled in the arm's outward direction."""
    pts = lane["points"]
    d = Vector((float(pts[-1][0]) - float(pts[0][0]),
                -(float(pts[-1][2]) - float(pts[0][2])), 0.0))
    if d.length < 0.01:
        return False
    return d.normalized().dot(arm["dir"]) > 0.3


def turn(a, b):
    """straight / left / right between two directions (Blender XY)."""
    cross = a.x * b.y - a.y * b.x
    dot = a.x * b.x + a.y * b.y
    if abs(cross) < 0.35 and dot > 0:
        return "straight"
    return "left" if cross > 0 else "right"


def pick_exit(kind, src, exits):
    """The exit lane a movement may use: right lane -> right, left lane -> left."""
    if not exits:
        return None
    if kind == "left":
        want = [lane for lane in exits if lane["leftmost"]]
        pool = want or exits
        return min(pool, key=lambda lane: lane["index"])
    if kind == "right":
        want = [lane for lane in exits if lane["rightmost"]]
        pool = want or exits
        return max(pool, key=lambda lane: lane["index"])
    # straight on: the same lane index if it exists, otherwise the nearest one
    best = None
    for lane in exits:
        gap = abs(lane["index"] - src["index"])
        if best is None or gap < best[0]:
            best = (gap, lane)
    return best[1] if best else None


def movements(src, options):
    """The movements a lane of an approach may take.

    `options` is [(turn, angle, exits)] of the arms the approach can reach.
    """
    straight = [o for o in options if o[0] == "straight"]
    left = [o for o in options if o[0] == "left"]
    right = [o for o in options if o[0] == "right"]
    middle = not src["leftmost"] and not src["rightmost"]
    if middle:
        if straight:
            return straight
        turns = left + right
        if not turns:
            return []
        return [min(turns, key=lambda o: o[1])]
    out = list(straight)
    if src["leftmost"]:
        out += left
    if src["rightmost"]:
        out += right
    return out if out else list(options)


def link_junctions(city, lanes, links):
    """Connector lanes for the movements through every junction."""
    by_road = {}
    for lane in lanes:
        by_road.setdefault(lane["road"], []).append(lane)
    seen_ids = set(l["id"] for l in lanes)
    for junction in city.junctions:
        arms, centre = jn.arm_geometry(city, junction)
        if len(arms) < 2:
            continue
        merge = jn.is_merge(arms)
        fan = None if merge else jn.fan(arms, centre)
        exits, approaches = _arm_lanes(arms, by_road, centre, junction["id"])
        for a in arms:
            options = _options(a, arms, exits, by_road, centre)
            for src in approaches.get(id(a), []):
                for (kind, _angle, pool) in movements(src, options):
                    dst = pick_exit(kind, src, pool)
                    if dst is None:
                        continue
                    _add_movement(lanes, links, seen_ids, junction, src, dst, kind,
                                  centre, fan)


def _arm_lanes(arms, by_road, centre, jid):
    """The lanes that leave a junction along an arm and the ones that arrive.

    A lane belongs to the arm it is travelled along: it leaves the junction
    when its start is the end that is near the junction, and it arrives when
    its end is.
    """
    exits, approaches = {}, {}
    for a in arms:
        road = a["road"]
        # the lane ends at the kerb return, one sample beyond the cut: a wide
        # road has its lanes 60 m away from the middle of the crossing
        reach = max(jn.road_radius(arms, road.id), 40.0) + CROSS_TOLERANCE
        for lane in by_road.get(road.id, []):
            if lane.get("connector"):
                continue
            pts = lane["points"]
            if len(pts) < 2:
                continue
            df = math.hypot(pts[0][0] - centre.x, pts[0][2] + centre.y)
            dl = math.hypot(pts[-1][0] - centre.x, pts[-1][2] + centre.y)
            if travels_along(lane, a):
                # the lane starts at the junction: it leaves along this arm
                if df <= reach and df <= dl:
                    exits.setdefault(id(a), []).append(lane)
            else:
                # the lane ends at the junction: it arrives along this arm
                if dl <= reach and dl <= df:
                    approaches.setdefault(id(a), []).append(lane)
    return exits, approaches


def _options(a, arms, exits, by_road=None, centre=None):
    """The arms the approach `a` may reach: [(turn, angle, exits)].

    An arm whose exits are not detected (a ramp that reaches its parent at an
    angle, a road that is trimmed further away) still offers its nearest
    lanes: an approach without a movement would be a dead end.
    """
    out = []
    for b in arms:
        if b is a:
            continue
        pool = exits.get(id(b), [])
        if not pool and by_road is not None and centre is not None:
            pool = _nearest_lanes(b["road"], by_road, centre)
        if not pool:
            continue
        kind = turn(-a["dir"], b["dir"])
        angle = math.degrees(math.acos(max(-1.0, min(1.0, (-a["dir"]).dot(b["dir"])))))
        out.append((kind, angle, pool))
    return out


# why a movement could not be built (a diagnostic of the lane graph)
SKIPPED = {}


def _nearest_lanes(road, by_road, centre, count=3):
    """The lanes of a road that lie closest to a point (a fallback for an arm)."""
    scored = []
    for lane in by_road.get(road.id, []):
        if lane.get("connector"):
            continue
        pts = lane["points"]
        if len(pts) < 2:
            continue
        d = min(math.hypot(pts[0][0] - centre.x, pts[0][2] + centre.y),
                math.hypot(pts[-1][0] - centre.x, pts[-1][2] + centre.y))
        scored.append((d, lane))
    scored.sort(key=lambda item: item[0])
    return [lane for (_d, lane) in scored[:count]]


def _add_movement(lanes, links, seen_ids, junction, src, dst, kind, centre, fan):
    """Add the connector lane of one movement and its two links."""
    pts = lane_paths.connector_points(src, dst, centre, fan)
    if len(pts) < 2:
        gap = (lane_paths.v3(dst["points"][0]) - lane_paths.v3(src["points"][-1])).length
        key = "%s %.0f m" % (junction["id"], gap)
        SKIPPED[key] = SKIPPED.get(key, 0) + 1
        return
    cid = "%s_%s_%s_%s" % (junction["id"], src["id"], kind, dst["id"])
    n = 0
    while cid in seen_ids:
        n += 1
        cid = "%s_%s_%s_%s_%d" % (junction["id"], src["id"], kind, dst["id"], n)
    lanes.append({
        "id": cid,
        "road": src["road"],
        "junction": junction["id"],
        "dir": src["dir"],
        "index": src["index"],
        "leftmost": src["leftmost"],
        "rightmost": src["rightmost"],
        "offset": 0.0,
        "width": src["width"],
        "speed_kmh": src["speed_kmh"],
        "elevated": src["elevated"],
        "connector": True,
        "turn": kind,
        "points": pts,
        "next": [dst["id"]],
    })
    seen_ids.add(cid)
    links.append({"from": src["id"], "to": cid, "turn": kind})
    links.append({"from": cid, "to": dst["id"], "turn": kind})


def lane_at(lanes, road, path_index, segments):
    """The lanes of `road` that end at the given path sample, and where.

    A back carriageway runs against the path order, so the lane that meets a
    sample is the back lane's FIRST point, not its last. The candidates are
    returned as (lane, end) with end 0 for the first point and 1 for the last.
    """
    best_seg = None
    best_gap = None
    for si, seg in enumerate(segments.get(road.id, [])):
        if not seg["indices"]:
            continue
        first, last = seg["indices"][0], seg["indices"][-1]
        if first <= path_index <= last:
            best_seg = si
            break
        gap = min(abs(path_index - first), abs(path_index - last))
        if best_gap is None or gap < best_gap:
            best_gap = gap
            best_seg = si
    if best_seg is None:
        return []
    out = []
    for lane in lanes:
        if lane["road"] != road.id or lane.get("connector"):
            continue
        if lane["segment"] != best_seg:
            continue
        pts = lane["points"]
        if len(pts) < 2:
            continue
        out.append((lane, 0))
        out.append((lane, 1))
    return out


def _attach_pair(parent_cands, ramp_cands):
    """The (parent lane, parent end, ramp lane, ramp end) that can carry traffic.

    A lane's traffic always enters at its first point and leaves at its last,
    so the two lanes of an attach must meet end to end: one lane's exit end
    and the other one's entry end.
    """
    best = None
    for (src, src_end) in parent_cands:
        for (dst, dst_end) in ramp_cands:
            if src_end == dst_end:
                continue      # two exits (or two entries) cannot be joined
            d = math.dist(src["points"][src_end], dst["points"][dst_end])
            if best is None or d < best[0]:
                best = (d, src, src_end, dst, dst_end)
    return best


def link_attaches(city, lanes, segments, links):
    """Link a ramp's lane to the parent's lane at the attach."""
    by_road = {}
    for lane in lanes:
        by_road.setdefault(lane["road"], []).append(lane)
    for road in city.roads:
        if road.kind != "ramp":
            continue
        for at_end, key in ((True, "attach_end"), (False, "attach_start")):
            attach = road.data.get(key)
            if not attach:
                continue
            parent = city.by_id.get(attach["road"])
            if parent is None:
                continue
            end_point = road.path[-1] if at_end else road.path[0]
            _dist, pidx = parent.nearest(end_point)
            ramp_index = len(road.path) - 1 if at_end else 0
            parent_cands = _cands_at(lane_at(by_road.get(parent.id, []), parent, pidx,
                                             segments), parent.path[pidx])
            ramp_cands = _cands_at(lane_at(by_road.get(road.id, []), road, ramp_index,
                                           segments), road.path[ramp_index])
            if not parent_cands or not ramp_cands:
                continue
            pair = _attach_pair(parent_cands, ramp_cands)
            if pair is None:
                continue
            _dist, src, src_end, dst, dst_end = pair
            dst["attach"] = True      # the ramp's lane that meets its parent
            # the traffic runs from the exit end of one lane to the entry end
            # of the other, whichever of the two that is
            if src_end == 1:
                first, second = src, dst
            else:
                first, second = dst, src
            a = lane_paths.v3(first["points"][-1])
            b = lane_paths.v3(second["points"][0])
            if (a - b).length <= 0.5:
                links.append({"from": first["id"], "to": second["id"], "turn": "straight"})
                continue
            # the ramp does not touch its parent: bridge the gap with a connector
            pts = lane_paths.connector_points(first, second)
            if len(pts) < 2:
                continue
            cid = "attach_%s_%s" % (first["id"], second["id"])
            lanes.append({
                "id": cid, "road": road.id, "attach": True,
                "dir": first["dir"], "index": first["index"],
                "leftmost": first["leftmost"], "rightmost": first["rightmost"],
                "offset": 0.0,
                "width": first["width"], "speed_kmh": first["speed_kmh"],
                "elevated": first["elevated"], "connector": True, "turn": "straight",
                "points": pts, "next": [second["id"]],
            })
            links.append({"from": first["id"], "to": cid, "turn": "straight"})
            links.append({"from": cid, "to": second["id"], "turn": "straight"})


def _cands_at(cands, point):
    """The (lane, end) candidates whose end is near a path sample.

    A lane's end is offset from the road's centre line by its own width, so
    the tolerance has to be a lane's width or more.
    """
    out = []
    for (lane, end) in cands:
        d = math.dist(lane["points"][end], point)
        if d <= ATTACH_TOLERANCE:
            out.append((lane, end))
    return out
