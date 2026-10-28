"""The lanes that a junction leaves but that no car can drive onto.

A lane that leaves a junction and that no movement leads into cannot be driven
onto: the traffic that would drive there has no way in.  That is what happens
where two junctions stand close together on a road: their cuts meet (the road
is cut once, junction_holes.cut_group) and the lanes of that cut are the ones
before and after it, so the lane that leaves the cut has to be fed by a turn
of one of the junctions of the cut.

This module gives every lane that leaves a junction the movement that leads
into it: the lane that arrives at the same junction on the same lane index
turns into it, so the traffic keeps the lane it was in.
"""
import math

from city.roads import junctions as jn
from city.roads import buildingcut, lane_links


def feed_exits(city, lanes, links):
    """Give every lane that leaves a junction a movement that leads into it.

    A lane that no movement leads into is a lane no car can drive onto.  The
    lane that arrives at the same junction on the same lane index turns into
    it.  Returns the number of movements that were added.
    """
    by_road = {}
    for lane in lanes:
        by_road.setdefault(lane["road"], []).append(lane)
    by_id = {lane["id"]: lane for lane in lanes}
    fed = set(link["to"] for link in links)
    seen = set(lane["id"] for lane in lanes)
    left = _left_roads(links, by_id)
    # the movements are added after the lanes were cut at the buildings of the Bund (buildingcut): a movement
    # that runs through a building is not added (a left turn of Nanjing E Rd into Sichuan Rd ran 36 m through
    # the back of Sassoon House)
    boxes = buildingcut.footprints() if "bund_zhongshan_e1" in city.by_id else []
    made = 0
    for junction in city.junctions:
        arms, centre = jn.arm_geometry(city, junction)
        if len(arms) < 2:
            continue
        merge = jn.is_merge(arms)
        fan = None if merge else jn.fan(arms, centre)
        exits, approaches = lane_links.arm_lanes(arms, by_road, centre, junction["id"], city)
        for a in arms:
            for dst in exits.get(id(a), []):
                if dst["id"] in fed:
                    continue
                if dst["road"] not in left.get(junction["id"], ()):
                    continue     # the road does not reach the junction: nothing to feed
                src, b = _feeder(arms, approaches, a, dst)
                if src is None:
                    continue
                kind = lane_links.turn(-b["dir"], a["dir"])
                before = len(links)
                lane_links.add_movement(lanes, links, seen, junction, src, dst, kind, centre, fan)
                if len(links) == before:
                    continue      # the movement could not be built
                if _through_building(boxes, lanes[-1]):
                    lanes.pop()
                    del links[before:]
                    continue
                src["next"].append(links[before]["to"])
                fed.add(dst["id"])
                made += 1
    if made:
        print("LANES %d lanes that leave a junction got a movement" % made)
    return made


def _through_building(boxes, lane):
    """True when a point of the lane lies in (or within buildingcut.MARGIN of) a building of the Bund."""
    if not boxes:
        return False
    pts = lane["points"]
    if pts[0][1] > buildingcut.ELEVATED and pts[-1][1] > buildingcut.ELEVATED:
        return False
    return any(buildingcut._inside(boxes, p[0], p[2]) is not None for p in pts)


def _left_roads(links, by_id):
    """The roads that leave every junction: {junction id: the roads of its lanes}.

    A road that reaches a junction and leaves it again is in the set: the
    traffic of that road arrives at the junction and drives on.  A road that
    only reaches the junction runs through it, and nothing of it can be fed.
    """
    out = {}
    for link in links:
        con = by_id.get(link["to"])
        if con is None or not con.get("connector"):
            continue
        lane = by_id.get(link["from"])
        if lane is None or lane.get("connector"):
            continue
        out.setdefault(con.get("junction"), set()).add(lane["road"])
    return out


def _feeder(arms, approaches, a, dst):
    """The lane that can turn into the exit lane `dst`: (lane, arm).

    The lane that arrives at the junction on the same lane index keeps the
    traffic in the same lane of the road it turns onto.  The other arm of the
    same road does not count: that would be a turn round.
    """
    best = None
    for b in arms:
        if b is a or b["road"].id == a["road"].id:
            continue
        angle = math.degrees(math.acos(max(-1.0, min(1.0, (-b["dir"]).dot(a["dir"])))))
        for lane in approaches.get(id(b), []):
            key = (abs(lane["index"] - dst["index"]), angle)
            if best is None or key < best[0]:
                best = (key, lane, b)
    if best is None:
        return None, None
    return best[1], best[2]
