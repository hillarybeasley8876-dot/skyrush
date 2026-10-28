"""The turn round of a road that ends at a crossing.

A lane that arrives at a junction and that no movement leads out of is a dead
end: the traffic that drives into it stops there for good.  The way out is the
turn round: the road ends at the crossing, so the traffic turns round and
drives back the way it came.

A U-turn needs room.  A car turns on a radius of 6 m or more, so the two ends
of the U-turn have to be at least 12 m apart.  The lane of the other
carriageway that is nearest to the approach is often closer than that (the
inner lanes of Pudong South Rd lie 4.7 m apart): such a lane turns into an
outer lane of the other side, the first one that is at least 12 m away.

A road that ends at a crossing and that has no room to turn round (a street of
one lane in each direction) leaves the traffic nowhere to turn: the stretch of
the road between the crossing and the end of the road gets its lane back, and
the traffic carries on into it.  That lane ends at the end of the road, which
is the end of the network and not a crossing in the middle of it.
"""
import math

from mathutils import Vector

from city.roads import junction_fill
from city.roads import junctions as jn
from city.roads import lane_links
from city.roads import lane_paths
from city.roads import levels

MIN_RADIUS = 6.0      # a car turns on a radius of 6 m or more
MIN_CHORD = 12.0      # the two ends of a U-turn are at least this far apart
ROAD_END = 60.0       # how far a road may end beyond the lane that stops at a crossing
JUNCTION_NEAR = 30.0  # how near a junction a lane has to end to stop at one (lanes._mark_termini)
ROAD_EDGE = 15.0      # how near the end of its road a lane has to end to stop there (lanes._mark_termini)
OPPOSITE = -0.3       # how alike the directions of a lane and its turn round have to be


def turn_arounds(city, lanes, links):
    """Give every lane that arrives at a junction and that has no way on one.

    A lane that arrives at a junction and that no movement leads out of is a
    dead end.  It turns round: a U-turn onto the other carriageway of its own
    road, or, when the road is too narrow for that, on to the end of the road.
    Returns the number of lanes that got a way on.
    """
    by_road = {}
    for lane in lanes:
        by_road.setdefault(lane["road"], []).append(lane)
    seen = set(lane["id"] for lane in lanes)
    moved = set(link["from"] for link in links)
    made = 0
    for junction in city.junctions:
        arms, centre = jn.arm_geometry(city, junction)
        if len(arms) < 2 or jn.is_merge(arms):
            continue
        exits, approaches = lane_links.arm_lanes(arms, by_road, centre, junction["id"], city)
        fan = jn.fan(arms, centre)
        leaving = {}
        for a in arms:
            for lane in exits.get(id(a), []):
                leaving.setdefault(lane["id"], lane)
        leaving = list(leaving.values())
        for a in arms:
            for src in approaches.get(id(a), []):
                if src["id"] in moved or not _stops_at_junction(city, src):
                    continue
                if _uturn(lanes, links, seen, junction, src, leaving, fan):
                    moved.add(src["id"])
                    made += 1
                elif _to_road_end(city, lanes, links, seen, src):
                    moved.add(src["id"])
                    made += 1
    if made:
        print("LANES %d lanes that end at a junction got a way on" % made)
    return made


def _stops_at_junction(city, lane):
    """True when the lane ends at a crossing and not at the end of its road.

    The same test as lanes._mark_termini: a lane that ends within 30 m of a
    junction and more than 15 m from the end of its road stops at the
    crossing.
    """
    end = lane["points"][-1]
    best = None
    for junction in city.junctions:
        gap = math.hypot(end[0] - junction["x"], end[2] - junction["z"])
        if best is None or gap < best:
            best = gap
    if best is None or best >= JUNCTION_NEAR:
        return False
    road = city.by_id.get(lane["road"])
    if road is None or not road.path:
        return True
    for p in (road.path[0], road.path[-1]):
        if math.hypot(end[0] - p.x, end[2] + p.y) < ROAD_EDGE:
            return False
    return True


def _heading(lane, at_end):
    """The direction the lane is travelled in at its end (the plan of the junction)."""
    pts = lane["points"]
    if len(pts) < 2:
        return None
    a, b = (pts[-2], pts[-1]) if at_end else (pts[0], pts[1])
    d = Vector((float(b[0]) - float(a[0]), -(float(b[2]) - float(a[2])), 0.0))
    return d.normalized() if d.length > 1e-6 else None


def _gap(src, dst):
    """The plan distance between the end of the approach and the start of the exit."""
    a = src["points"][-1]
    b = dst["points"][0]
    return math.hypot(float(b[0]) - float(a[0]), float(b[2]) - float(a[2]))


def _uturn(lanes, links, seen, junction, src, exits, fan):
    """The U-turn of an approach lane: a connector into a lane of its own road.

    The lane of the other carriageway that is nearest to the approach is often
    too close for the turn (a car turns on a radius of 6 m), so the first lane
    of the other side that is at least MIN_CHORD away is the one it turns into.
    """
    head = _heading(src, True)
    if head is None:
        return False
    targets = []
    for lane in exits:
        if lane["road"] != src["road"]:
            continue
        out = _heading(lane, False)
        if out is None or out.dot(head) > OPPOSITE:
            continue     # the lane leaves the junction the way the approach came
        gap = _gap(src, lane)
        if gap >= MIN_CHORD:
            targets.append((gap, lane["id"], lane))
    targets.sort(key=lambda item: item[0])
    for _gap_m, _lid, lane in targets:
        if _add_uturn(lanes, links, seen, junction, src, lane, fan):
            return True
    return False


def _curve(src, dst, fan):
    """The curve of the U-turn: a Bezier with the arms of the arc that joins the two ends.

    The arms of the arc of the radius R are 4R/3 long, so the curve follows
    that arc: a car drives it without a sharp corner.
    """
    p0 = lane_paths.v3(src["points"][-1])
    p3 = lane_paths.v3(dst["points"][0])
    d0 = p0 - lane_paths.v3(src["points"][-2])
    d1 = lane_paths.v3(dst["points"][1]) - p3
    if d0.length < 1e-6 or d1.length < 1e-6:
        return []
    d0.normalize()
    d1.normalize()
    radius = max(MIN_RADIUS, (p3 - p0).length * 0.5)
    arm = 4.0 / 3.0 * radius
    pts = lane_paths.bezier(p0, p0 + d0 * arm, p3 - d1 * arm, p3, step=1.0)
    if fan is None:
        return lane_paths.resample(pts)
    wide = (fan[0], levels.offset_ring(fan[1], junction_fill.COLLIDER_MARGIN))
    return lane_paths.resample(lane_paths.fit_to_road(pts, wide, src, dst))


def _add_uturn(lanes, links, seen, junction, src, dst, fan):
    """The connector lane of the U-turn and its two links."""
    pts = _curve(src, dst, fan)
    if len(pts) < 2:
        return False
    cid = "%s_%s_uturn_%s" % (junction["id"], src["id"], dst["id"])
    n = 0
    while cid in seen:
        n += 1
        cid = "%s_%s_uturn_%s_%d" % (junction["id"], src["id"], dst["id"], n)
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
        "turn": "uturn",
        "points": pts,
        "next": [dst["id"]],
    })
    seen.add(cid)
    lane_links.MOVEMENTS[(src["id"], dst["id"])] = cid
    links.append({"from": src["id"], "to": cid, "turn": "uturn"})
    links.append({"from": cid, "to": dst["id"], "turn": "uturn"})
    return True


def _to_road_end(city, lanes, links, seen, src):
    """The lane that carries on to the end of the road.

    A road that ends at a crossing and that has no room to turn round (a street
    of one lane in each direction) leaves the traffic nowhere to turn.  The
    road ends a little further on: the stretch of the road between the
    crossing and its end gets its lane back, and the traffic carries on into
    it.  That lane ends at the end of the road, where the traffic stops at the
    end of the network and not in the middle of a crossing.
    """
    road = city.by_id.get(src["road"])
    if road is None or len(road.path) < 2:
        return False
    at_start = src["dir"] < 0     # the traffic drives against the path of the road
    last = road.path[0] if at_start else road.path[-1]
    end = src["points"][-1]
    gap = math.hypot(end[0] - last.x, end[2] + last.y)
    if gap < 2.0 or gap > ROAD_END:
        return False
    pts = _end_curve(road, src, at_start)
    if len(pts) < 2:
        return False
    lid = "end_%s" % src["id"]
    n = 0
    while lid in seen:
        n += 1
        lid = "end_%s_%d" % (src["id"], n)
    lanes.append({
        "id": lid,
        "road": src["road"],
        "segment": src.get("segment"),
        "dir": src["dir"],
        "index": src["index"],
        "leftmost": src["leftmost"],
        "rightmost": src["rightmost"],
        "offset": src["offset"],
        "width": src["width"],
        "speed_kmh": src["speed_kmh"],
        "elevated": src["elevated"],
        "points": pts,
        "start_junction": src.get("end_junction"),
        "end_junction": None,
        "next": [],
    })
    seen.add(lid)
    links.append({"from": src["id"], "to": lid, "turn": "straight"})
    return True


def _end_curve(road, src, at_start):
    """The curve of the lane that carries on to the end of the road.

    It follows the line of the lane (its offset from the centre line of the
    road) all the way to the end of the road.
    """
    p = lane_paths.v3(src["points"][-1])
    _dist, idx, t = road.closest(p)
    lateral = (p - road.path[idx]).dot(road.frames[idx][1])
    station = road.dist[idx] + t * (road.dist[idx + 1] - road.dist[idx])
    picks = [i for i in range(len(road.path))
             if (road.dist[i] <= station if at_start else road.dist[i] >= station)]
    if at_start:
        picks.reverse()
    pts = [list(src["points"][-1])]
    for i in picks:
        q = road.path[i] + road.frames[i][1] * lateral
        pts.append([round(q.x, 2), round(q.z, 2), round(-q.y, 2)])
    return lane_paths.resample(pts)
