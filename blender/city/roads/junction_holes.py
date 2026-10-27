"""The stretches of a road that its junctions take (the holes the lanes, the kerbs and the surface are cut at).

A junction takes the path samples of an arm road within the radius of its centre in which that road is cut
(junctions.road_radius). A side street that ends at the kerb of a main road puts the centre of the junction beside the
main road (Henan Rd at the junction of st_d1_ns_3 and st_d2_ew_4: 18.5 m off its centre line), and the main road was
never cut there: its lanes ran through the junction and the cars on it could not turn off (tools/city/check_junction_exits.py).
Such a road is cut where the junction stands on it. The holes of all the junctions of a road are taken together, so the cut
of one junction does not eat the next one.

Two junctions that stand close together on the same road are cut once: the road is cut from the first junction to the last
(the stretch of road between the two cuts would be a lane shorter than a car: 6 m of the Lujiazui ring road between the
junctions of st_d7_ns_8 and st_d7_ew_8). The junctions of such a cut form a group: they share the lanes before and after
the cut, so the traffic that arrives at the cut can turn into the side streets of every junction of it, and no road runs
through any of them.
"""
from city.roads import junctions as jn

ONE_SAMPLE = 6.0        # m: the cut of a junction that does not reach the road
CROSS_TOLERANCE = 15.0  # m: how far a lane end may be from the kerb return
MIN_LANE = 10.0         # m: a road lane shorter than this cannot hold a car and its gap
HOLES = {}               # (city, road) -> the samples every junction of the road takes
GROUPS = {}              # (city, road) -> the junctions that share a cut, by junction id


def _ends_near(road, centre, reach, holes, jid):
    """True when a lane of the road already ends near the centre of a junction."""
    ends = [0, len(road.path) - 1]
    for (other, hole) in holes.items():
        if other != jid and hole:
            ends += [min(hole) - 1, max(hole) + 1]
    return any(0 <= i < len(road.path) and (road.path[i] - centre).length <= reach
               for i in ends)


def road_holes(city, road):
    """The samples of a road that every junction of it takes: {junction id: set}.

    A road that a junction does not reach is cut anyway, where the junction
    stands on the road: without that cut its lanes run through the junction
    and the cars on it cannot turn off.
    """
    key = (id(city), road.id)
    if key in HOLES:
        return HOLES[key]
    out = {}
    near = []
    reach = {}
    for junction in city.junctions_of(road):
        arms, centre = jn.arm_geometry(city, junction)
        if not arms or not any(a["road"].id == road.id for a in arms):
            continue
        jn.boundary(arms, centre)
        radius = jn.road_radius(arms, road.id)
        if radius <= 0.0:
            continue
        hole = {i for i, p in enumerate(road.path) if (p - centre).length <= radius}
        out[junction["id"]] = hole
        reach[junction["id"]] = (centre, radius)
        near.append((junction, centre))
    for (junction, centre) in near:
        if out[junction["id"]] or road.elevated:
            continue
        arms, _centre = jn.arm_geometry(city, junction)
        radius = jn.road_radius(arms, road.id)
        far = max(radius, 40.0) + CROSS_TOLERANCE
        if _ends_near(road, centre, far, out, junction["id"]):
            continue
        reach[junction["id"]] = (centre, radius)
        _dist, idx, t = road.closest(centre)
        anchor = road.path[idx].lerp(road.path[idx + 1], t)
        for i, p in enumerate(road.path):
            if (p - anchor).length <= ONE_SAMPLE:
                out[junction["id"]].add(i)
    # the cuts of two junctions that stand on the same stretch of road must not
    # eat each other: the road keeps a stretch of lane between them, unless
    # that stretch is too short for a lane, then the cuts meet
    HOLES[key] = _merge(road, out, reach)
    return HOLES[key]


def _merge(road, holes, reach):
    """The cuts of the junctions of a road that stand closer than a lane become one cut.

    The road is then cut once, from the first junction to the last, and every
    junction of that cut takes the same samples: they share the lanes before
    and after the cut (see cut_group).

    Two crossings that stand apart keep their own cuts: the road between them
    is a stretch of road with a lane of its own, even when that lane is short.
    """
    items = sorted((min(h), max(h), jid, set(h)) for (jid, h) in holes.items() if h)
    out = {}
    group = None
    for (first, last, jid, hole) in items:
        if group is not None and _within(road, group[1], first) and _overlap(reach, group[4], jid):
            # the two cuts meet: the short stretch of road between them is cut too
            gap = set(range(group[1] + 1, first))
            group = (min(group[0], first), max(group[1], last),
                     group[2] + [jid], group[3] | hole | gap, jid)
            continue
        if group is not None:
            _apply(out, group)
        group = (first, last, [jid], set(hole), jid)
    if group is not None:
        _apply(out, group)
    return out


def _overlap(reach, jid, other):
    """True when the crossings of two junctions stand close enough to share a cut.

    The cut of a junction reaches as far as the kerb return of the road
    (junctions.road_radius): two crossings whose cuts reach each other are
    one crossing, and the road between them is one cut.
    """
    if jid not in reach or other not in reach:
        return False
    (centre, radius) = reach[jid]
    (other_centre, other_radius) = reach[other]
    return (centre - other_centre).length <= radius + other_radius


def _apply(out, group):
    """Give every junction of a cut the samples of that cut."""
    for jid in group[2]:
        out[jid] = set(group[3])


def _within(road, last, first):
    """True when the stretch of road between two cuts is too short for a lane.

    The lane between the cuts runs from the sample after the first cut to the
    sample before the second one.  Two cuts that touch leave no lane at all.
    """
    if first - last <= 2:
        return True
    if last + 1 >= len(road.path) or first - 1 < 0:
        return False
    return (road.dist[first - 1] - road.dist[last + 1]) < MIN_LANE


def cut_group(city, road, junction_id):
    """The junctions of a road that share its cut with this one: [junction ids].

    A road that is cut once for several junctions close together has one set
    of lanes before the cut and one after it: every junction of the cut uses
    them, so the traffic that arrives there can turn into the side streets of
    any of them.
    """
    holes = road_holes(city, road)
    hole = holes.get(junction_id)
    if not hole:
        return []
    key = (id(city), road.id)
    groups = GROUPS.setdefault(key, {})
    if junction_id not in groups:
        groups[junction_id] = sorted(jid for (jid, h) in holes.items() if h and h == hole)
    return groups[junction_id]
