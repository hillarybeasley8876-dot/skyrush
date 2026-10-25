"""The links of the lane graph: the movements through a junction, the
attaches of a ramp and the joints of two roads that meet end to end.

Every approach lane gets at least one movement: a middle lane goes straight
on, with no straight arm it takes the nearer turn, and a one-lane approach may
take every movement. A merge (two arms that run almost parallel) links the
lanes of the two roads without a junction box.

Two roads that meet end to end (the end of one is the start of the other, no
junction between them) are linked as well: the traffic that arrives at such a
joint carries on into the lanes of the next road.
"""
import math

from mathutils import Vector

from city.roads import junctions as jn
from city.roads import lane_paths

CROSS_TOLERANCE = 15.0  # how far a lane end may be from the kerb return
SAME_WAY = 0.3          # how alike the directions of two lanes have to be
DIRECT_LINK = 0.5       # two lanes this close may be linked without a connector
CHAIN_JOINT = 20.0    # the two road ends have to be this close to be one chain
CHAIN_REACH = 6.0     # how far a lane end may be from the next road's lane start
CHAIN_HEIGHT = 1.5    # how much the two lanes may differ in height
CHAIN_HEAD = 40.0     # how alike the directions of the two lanes have to be
CHAIN_ALIGN = 1.6     # two lanes this close have to be linked to each other
CHAIN_MAX = 2         # a lane may not have more than two successors
CHAIN_SPAN = 4.0      # the handle of the curve that joins the two roads
CHAIN_STEP = 0.5      # how finely a chain curve is sampled
CHAIN_MIN = 0.3       # two points of a chain curve are at least this far apart


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
                    if dst is None or dst is src:
                        # A lane is no exit of its own junction: the fallback pool of an arm (the lanes of
                        # its road nearest to the centre) holds the approach itself when it passes it, and 79
                        # lanes were linked "straight on" into their own start (the car turned round at the
                        # end of the lane and drove back along it).
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
            pool = _nearest_lanes(b, by_road, centre)
        if not pool:
            continue
        kind = turn(-a["dir"], b["dir"])
        angle = math.degrees(math.acos(max(-1.0, min(1.0, (-a["dir"]).dot(b["dir"])))))
        out.append((kind, angle, pool))
    return out


def _starts_along(lane, arm):
    """True when the first metres of the lane run along the arm's outward direction (the chord of a long
    curved lane does not tell where it starts out to)."""
    pts = lane["points"]
    k = min(len(pts) - 1, 3)
    d = Vector((float(pts[k][0]) - float(pts[0][0]), -(float(pts[k][2]) - float(pts[0][2])), 0.0))
    return d.length > 0.01 and d.normalized().dot(arm["dir"]) > SAME_WAY


# why a movement could not be built (a diagnostic of the lane graph)
SKIPPED = {}


def _nearest_lanes(arm, by_road, centre, count=3):
    """The lanes of the road of an arm that leave a point along the arm, the nearest first (a fallback
    for an arm whose exits are not found).

    A lane whose end is nearer to the point than its start runs towards it, and a lane of the other
    carriageway starts out against the arm: neither is an exit. Both were: 117 movements led into the
    far start of a lane that runs towards the junction (85 m on the median, up to 146 m: the car drove
    down the road against its traffic and turned round there; the game dropped most of those links, and
    the connector stayed a dead end in the middle of the junction), 79 into the start of the approach
    itself, and the other carriageway would make a U-turn of "straight on".
    """
    scored = []
    for lane in by_road.get(arm["road"].id, []):
        if lane.get("connector"):
            continue
        pts = lane["points"]
        if len(pts) < 2:
            continue
        df = math.hypot(pts[0][0] - centre.x, pts[0][2] + centre.y)
        dl = math.hypot(pts[-1][0] - centre.x, pts[-1][2] + centre.y)
        if dl < df or not _starts_along(lane, arm):
            continue
        scored.append((df, lane))
    scored.sort(key=lambda item: item[0])
    return [lane for (_d, lane) in scored[:count]]


def _add_movement(lanes, links, seen_ids, junction, src, dst, kind, centre, fan):
    """Add the connector lane of one movement and its two links."""
    pts = lane_paths.connector_points(src, dst, centre, fan, straight=kind == "straight")
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
        gap = (want - last) if at_end else first
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
    ramp: the lanes before the cut are the ones the traffic leaves the parent
    by, the ones after it the ones it enters the parent by.
    """
    by_road = {}
    for lane in lanes:
        by_road.setdefault(lane["road"], []).append(lane)
    for road in city.roads:
        segs = segments.get(road.id, [])
        for seg in segs:
            for att in seg.get("attach", []):
                _link_at(city, by_road, segments, links, lanes, road, segs, seg, att)


def _link_at(city, by_road, segments, links, lanes, road, segs, seg, att):
    """Link the ramp of one attach to the lanes of the parent."""
    ramp = city.by_id.get(att[0])
    if ramp is None:
        return
    at_end = att[1]
    after = _after(segs, seg)
    # the parent's lanes that meet the attach: the ones the traffic leaves the
    # parent by and the ones it enters the parent by
    leave = _of(by_road, road, seg, 1) + _of(by_road, road, after, -1)
    entry = _of(by_road, road, after, 1) + _of(by_road, road, seg, -1)
    # the ramp's lane that meets the attach
    rseg = _end_segment(segments.get(ramp.id, []), ramp, at_end)
    ramp_lanes = _of(by_road, ramp, rseg, 1)
    if at_end:
        # the ramp joins the parent: the traffic leaves the ramp and enters
        # the parent
        parent_side, parent_end, ramp_end = entry, 0, 1
    else:
        # the ramp leaves the parent: the traffic leaves the parent and enters
        # the ramp
        parent_side, parent_end, ramp_end = leave, 1, 0
    if not ramp_lanes or not parent_side:
        return
    # the parent's lane of the carriageway that the ramp runs along
    same = [lane for lane in parent_side
            if _same_way(lane, parent_end, ramp_lanes[0], ramp_end)]
    parent_side = sorted(same or parent_side, key=lambda lane: lane["index"])
    # the outermost lane of the ramp joins the outermost lane of the parent,
    # so the traffic does not have to cross the other lanes
    count = len(parent_side)
    for i, ramp_lane in enumerate(ramp_lanes[:count]):
        parent_lane = parent_side[count - len(ramp_lanes) + i]
        ramp_lane["attach"] = True
        # the traffic runs from the exit end of one lane to the entry end of
        # the other, whichever of the two that is
        if at_end:
            first, second = ramp_lane, parent_lane
        else:
            first, second = parent_lane, ramp_lane
        _link_attach(first, second, ramp, lanes, links)


def _connector(first, second):
    """The curve that joins the end of one lane to the start of the other.

    A cubic Bezier whose end tangents are the headings of the two lanes it
    joins and whose handles are half the length of the curve: the traffic
    keeps its direction over the whole connector (a car can follow it).
    """
    p0 = lane_paths.v3(first["points"][-1])
    p3 = lane_paths.v3(second["points"][0])
    d0 = p0 - lane_paths.v3(first["points"][-2])
    d1 = lane_paths.v3(second["points"][1]) - p3
    if d0.length < 1e-6 or d1.length < 1e-6:
        return []
    d0.normalize()
    d1.normalize()
    span = max(4.0, (p3 - p0).length * 0.5)
    p1 = p0 + d0 * span
    p2 = p3 - d1 * span
    return lane_paths.resample(lane_paths.bezier(p0, p1, p2, p3))


def _chain_connector(first, second):
    """The curve that joins the end of one lane to the start of the other.

    The same cubic Bezier as the ramp attach, but sampled every half metre
    along its length: the two roads of a joint meet at an angle, so the lane
    that continues the traffic can start a metre BEHIND the lane that
    arrives, and the curve has to loop back to reach it.  Only a fine
    sampling keeps the heading of the two lanes at the ends of the curve.
    """
    p0 = lane_paths.v3(first["points"][-1])
    p3 = lane_paths.v3(second["points"][0])
    d0 = p0 - lane_paths.v3(first["points"][-2])
    d1 = lane_paths.v3(second["points"][1]) - p3
    if d0.length < 1e-6 or d1.length < 1e-6:
        return []
    d0.normalize()
    d1.normalize()
    span = max(CHAIN_SPAN, (p3 - p0).length * 0.5)
    out = []
    for p in _chain_curve(p0, p0 + d0 * span, p3 - d1 * span, p3):
        if not out or (p - out[-1]).length >= CHAIN_MIN:
            out.append(p)
    if not out or (out[-1] - p3).length > 1e-4:
        if len(out) > 1 and (out[-1] - p3).length < CHAIN_MIN:
            out[-1] = p3   # the last sample is too close to the end: the end replaces it (the points keep their spacing)
        else:
            out.append(p3)     # the curve ends at the start of the next lane
    return [[round(p.x, 2), round(p.z, 2), round(-p.y, 2)] for p in out]


def _chain_curve(p0, p1, p2, p3, count=256):
    """The cubic Bezier, sampled every half metre along its length."""
    raw = []
    for i in range(count + 1):
        t = i / float(count)
        u = 1.0 - t
        raw.append(p0 * (u ** 3) + p1 * (3 * u * u * t)
                   + p2 * (3 * u * t * t) + p3 * (t ** 3))
    out = [raw[0]]
    carry = 0.0
    for a, b in zip(raw, raw[1:]):
        seg = (b - a).length
        d = CHAIN_STEP - carry
        while d <= seg:
            out.append(a.lerp(b, d / seg))
            d += CHAIN_STEP
        carry = seg - (d - CHAIN_STEP)
    if (out[-1] - raw[-1]).length > 0.05:
        out.append(raw[-1])
    else:
        out[-1] = raw[-1]     # the curve ends at the point it has to reach
    return out


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
    if (a - b).length <= DIRECT_LINK:
        links.append({"from": first["id"], "to": second["id"], "turn": "straight"})
        return
    # the ramp does not touch its parent: bridge the gap with a connector
    pts = _connector(first, second)
    if len(pts) < 2:
        return
    cid = "attach_%s_%s" % (first["id"], second["id"])
    lane = _connector_lane(cid, first, road.id, pts, second)
    lane["attach"] = True
    lanes.append(lane)
    links.append({"from": first["id"], "to": cid, "turn": "straight"})
    links.append({"from": cid, "to": second["id"], "turn": "straight"})


def _connector_lane(cid, first, road, pts, second):
    """The lane that carries the traffic from one lane into the other."""
    return {
        "id": cid, "road": road,
        "dir": first["dir"], "index": first["index"],
        "leftmost": first["leftmost"], "rightmost": first["rightmost"],
        "offset": 0.0,
        "width": first["width"], "speed_kmh": first["speed_kmh"],
        "elevated": first["elevated"], "connector": True, "turn": "straight",
        "points": pts, "next": [second["id"]],
    }


def link_chains(city, lanes, segments, links):
    """Link the lanes of two roads that meet end to end, with no junction between.

    The elevated chain (ns_elevated -> inner_ring -> nanpu_spiral_upper ->
    nanpu_bridge) ends in the air without this: the lane builder links the
    junctions and the ramp attaches only.  Every lane that arrives at such a
    joint now carries on into the lanes of the next road, and every lane that
    leaves the joint is fed by the lanes that arrive.
    """
    by_road = {}
    for lane in lanes:
        by_road.setdefault(lane["road"], []).append(lane)
    succ = {}
    fed = set()
    for link in links:
        succ.setdefault(link["from"], set()).add(link["to"])
        fed.add(link["to"])
    for road, here, parent, there in _chain_joints(city):
        _chain_joint(by_road, segments, lanes, links, succ, fed,
                     road, here, parent, there)


def _chain_joints(city):
    """The pairs of road ends that meet without a junction between them.

    A road that is not a ramp names the road it continues in `attach_start` or
    `attach_end`; the joint is where the two ends meet.  Both roads name the
    same joint, so it is used once.
    """
    out = []
    seen = set()
    for road in city.roads:
        if road.kind == "ramp":
            continue
        for at_end, key in ((True, "attach_end"), (False, "attach_start")):
            att = road.data.get(key)
            parent = city.by_id.get(att.get("road")) if att else None
            if parent is None or parent.kind == "ramp":
                continue    # a ramp is linked by link_attaches
            point = road.path[-1] if at_end else road.path[0]
            gap, there = min(((point - parent.path[0]).length, "start"),
                              ((point - parent.path[-1]).length, "end"),
                              key=lambda item: item[0])
            if gap > CHAIN_JOINT:
                continue
            here = "end" if at_end else "start"
            tag = frozenset(((road.id, here), (parent.id, there)))
            if tag in seen:
                continue
            seen.add(tag)
            out.append((road, here, parent, there))
    return out


def _chain_joint(by_road, segments, lanes, links, succ, fed, a, a_end, b, b_end):
    """Link the lanes that arrive at a joint to the lanes that leave it.

    Two flows meet at a joint: the traffic that arrives along one road leaves
    along the other, and the traffic that arrives along the other leaves back.
    """
    for src, se, dst, de in ((a, a_end, b, b_end), (b, b_end, a, a_end)):
        arr = _chain_lanes(by_road, segments, src, se, True)
        dep = _chain_lanes(by_road, segments, dst, de, False)
        pairs = [(gap, x, y) for x in arr for y in dep
                 for gap in [_chain_gap(x, y)] if gap is not None]
        if not pairs:
            continue
        made = _chain_match(arr, dep, pairs, lanes, links, succ, fed)
        print("CHAIN %s.%s -> %s.%s: %d lanes in, %d out, %d links" % (
            src.id, se, dst.id, de, len(arr), len(dep), made))


def _chain_lanes(by_road, segments, road, end, arrive):
    """The lanes of a road that arrive at (or leave) one of its ends.

    The lanes of the last segment travel with the path (the "fwd" ones) and
    against it (the "back" ones), so the last segment holds both the lanes
    that arrive at the end of the road and the ones that leave it.
    """
    seg = _end_segment(segments.get(road.id, []), road, end == "end")
    if seg is None:
        return []
    if end == "end":
        direction = 1 if arrive else -1
    else:
        direction = -1 if arrive else 1
    return _of(by_road, road, seg, direction)


def _chain_gap(a, b):
    """The plan distance between the end of one lane and the start of the other.

    None when the two lanes do not meet: too far apart, at another height, or
    against the traffic.
    """
    end, start = a["points"][-1], b["points"][0]
    if abs(end[1] - start[1]) > CHAIN_HEIGHT:
        return None
    da, db = _travel(a, 1), _travel(b, 0)
    if da is None or db is None:
        return None
    if da.dot(db) < math.cos(math.radians(CHAIN_HEAD)):
        return None
    gap = math.hypot(end[0] - start[0], end[2] - start[2])
    return gap if gap <= CHAIN_REACH else None


def _chain_match(arr, dep, pairs, lanes, links, succ, fed):
    """Match the lanes that arrive at a joint to the lanes that leave it.

    The lanes that stand side by side (the same lane index) are linked to each
    other, a lane that arrives without a successor takes the nearest lane that
    leaves, and a lane that leaves without a feeder is fed by the lane that
    arrives nearest to it: a road with three lanes merges into the road with
    two, a road with two splits into the road with three.
    """
    made = 0
    for gap, a, d in sorted(pairs, key=lambda item: item[0]):
        if gap <= CHAIN_ALIGN:
            made += _chain_link(a, d, lanes, links, succ, fed)
    for a in arr:
        if succ.get(a["id"]):
            continue
        best = min((p for p in pairs if p[1] is a), key=lambda p: p[0], default=None)
        if best is not None:
            made += _chain_link(a, best[2], lanes, links, succ, fed)
    for d in dep:
        if d["id"] in fed:
            continue
        best = min((p for p in pairs if p[2] is d), key=lambda p: p[0], default=None)
        if best is not None:
            made += _chain_link(best[1], d, lanes, links, succ, fed)
    return made


def _chain_link(first, second, lanes, links, succ, fed):
    """Link the end of one lane to the start of the other.

    A copy of the ramp attach: the connector is named `chain_...`, so the
    attach checkers do not mistake it for a ramp.  Returns the number of
    links that were made.
    """
    if second["id"] in succ.get(first["id"], ()):
        return 0
    if len(succ.get(first["id"], ())) >= CHAIN_MAX:
        return 0
    a = lane_paths.v3(first["points"][-1])
    b = lane_paths.v3(second["points"][0])
    if (a - b).length <= DIRECT_LINK:
        links.append({"from": first["id"], "to": second["id"], "turn": "straight"})
        succ.setdefault(first["id"], set()).add(second["id"])
        fed.add(second["id"])
        return 1
    # the two roads do not touch: bridge the gap with a connector
    pts = _chain_connector(first, second)
    if len(pts) < 2:
        return 0
    cid = "chain_%s_%s" % (first["id"], second["id"])
    lane = _connector_lane(cid, first, first["road"], pts, second)
    lane["chain"] = True
    lanes.append(lane)
    links.append({"from": first["id"], "to": cid, "turn": "straight"})
    links.append({"from": cid, "to": second["id"], "turn": "straight"})
    succ.setdefault(first["id"], set()).add(cid)
    succ.setdefault(cid, set()).add(second["id"])
    fed.add(second["id"])
    return 1
