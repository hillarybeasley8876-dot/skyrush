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
ATTACH_TOLERANCE = 25.0  # how far a lane's end may be from an attach point:
                        # the tolerance the lane link checker measures with
SAME_WAY = 0.3          # how alike the directions of two lanes have to be


def attach_stations(city, road):
    """The ramps that attach to this road: [(parent path index, ramp, at_end)].

    The ramp's end lies beside the parent, not on it: the index is the
    parent's own path sample closest to it.  The cut of the parent and the
    link of the ramp both use it, so the two agree on where the attach is.
    """
    out = []
    for ramp in city.roads:
        if ramp.kind != "ramp":
            continue
        for at_end, key in ((True, "attach_end"), (False, "attach_start")):
            att = ramp.data.get(key)
            if not att or att.get("road") != road.id:
                continue
            idx = len(ramp.path) - 1 if at_end else 0
            _dist, pidx = road.nearest(ramp.path[idx])
            out.append((pidx, ramp, at_end))
    return sorted(out, key=lambda item: item[0])


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


def _of(by_road, road, seg, direction):
    """The lanes of a road in one segment and one direction."""
    if seg is None:
        return []
    number = seg.get("number")
    out = [lane for lane in by_road.get(road.id, [])
           if lane["road"] == road.id and not lane.get("connector")
           and lane["segment"] == number and lane["dir"] == direction]
    return sorted(out, key=lambda lane: lane["index"])


def _end_segment(segs, road, at_end):
    """The segment of a road that holds the end of its path."""
    want = len(road.path) - 1 if at_end else 0
    best = None
    for seg in segs:
        if not seg["indices"]:
            continue
        first, last = seg["indices"][0], seg["indices"][-1]
        if (last if at_end else first) == want:
            return seg
        gap = (want - last) if at_end else (first - want)
        if best is None or gap < best[0]:
            best = (gap, seg)
    return best[1] if best else None


def _same_way(a, a_end, b, b_end):
    """True when the two lanes are travelled the same way where they meet."""
    da = _travel(a, a_end)
    db = _travel(b, b_end)
    return da is not None and db is not None and da.dot(db) > SAME_WAY


def _travel(lane, end):
    """The direction the lane is travelled in at its given end (Blender XY)."""
    pts = lane["points"]
    if len(pts) < 2:
        return None
    a, b = (pts[-2], pts[-1]) if end == 1 else (pts[0], pts[1])
    v = Vector((float(b[0]) - float(a[0]), -(float(b[2]) - float(a[2])), 0.0))
    return v.normalized() if v.length > 1e-6 else None


def link_attaches(city, lanes, segments, links):
    """Link the lanes of a ramp to the lanes of its parent at the attach.

    The segment of the parent that meets the attach carries the marker of the
    ramp: the lanes of the segment before the cut are the ones the traffic
    leaves the parent by, the lanes of the segment after the cut the ones it
    enters the parent by.
    """
    by_road = {}
    for lane in lanes:
        by_road.setdefault(lane["road"], []).append(lane)
    for road in city.roads:
        segs = segments.get(road.id, [])
        for seg in segs:
            att = seg.get("attach")
            if not att:
                continue
            ramp = city.by_id.get(att[0])
            if ramp is None:
                continue
            at_end = att[1]
            # the segment after the cut: the one that shares its path index
            after = _after(segs, seg)
            # the parent's lanes that meet the attach: the ones the traffic
            # leaves the parent by and the ones it enters the parent by
            leave = _of(by_road, road, seg, 1) + _of(by_road, road, after, -1)
            entry = _of(by_road, road, after, 1) + _of(by_road, road, seg, -1)
            # the ramp's lane that meets the attach
            rseg = _end_segment(segments.get(ramp.id, []), ramp, at_end)
            ramp_lanes = _of(by_road, ramp, rseg, 1)
            if at_end:
                # the ramp joins the parent: the traffic leaves the ramp and
                # enters the parent
                parent_side, parent_end, ramp_end = entry, 0, 1
            else:
                # the ramp leaves the parent: the traffic leaves the parent
                # and enters the ramp
                parent_side, parent_end, ramp_end = leave, 1, 0
            if not ramp_lanes or not parent_side:
                continue
            # the parent's lane of the carriageway that the ramp runs along
            same = [lane for lane in parent_side
                    if _same_way(lane, parent_end, ramp_lanes[0], ramp_end)]
            parent_side = sorted(same or parent_side, key=lambda lane: lane["index"])
            # the outermost lane of the ramp joins the outermost lane of the
            # parent, so the traffic does not have to cross the other lanes
            count = len(parent_side)
            for i, ramp_lane in enumerate(ramp_lanes[:count]):
                parent_lane = parent_side[count - len(ramp_lanes) + i]
                ramp_lane["attach"] = True
                # the traffic runs from the exit end of one lane to the entry
                # end of the other, whichever of the two that is
                if at_end:
                    first, second = ramp_lane, parent_lane
                else:
                    first, second = parent_lane, ramp_lane
                _link_attach(first, second, ramp, lanes, links)


def _after(segs, seg):
    """The segment after a cut: the one that shares its path index."""
    cut = seg["indices"][-1]
    for other in segs:
        if other is not seg and other["indices"] and other["indices"][0] == cut:
            return other
    return None


def _link_attach(first, second, road, lanes, links):
    """Link the end of one lane to the start of the other."""
    a = lane_paths.v3(first["points"][-1])
    b = lane_paths.v3(second["points"][0])
    if (a - b).length <= 0.5:
        links.append({"from": first["id"], "to": second["id"], "turn": "straight"})
        return
    # the ramp does not touch its parent: bridge the gap with a connector
    pts = lane_paths.connector_points(first, second)
    if len(pts) < 2:
        return
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
