"""The stretches of a road that its junctions take (the holes the lanes, the kerbs and the surface are cut at).

A junction takes the path samples of an arm road within the radius of its centre in which that road is cut
(junctions.road_radius). A side street that ends at the kerb of a main road puts the centre of the junction beside the
main road (Henan Rd at the junction of st_d1_ns_3 and st_d2_ew_4: 18.5 m off its centre line), and the main road was
never cut there: its lanes ran through the junction and the cars on it could not turn off (tools/city/check_junction_exits.py).
Such a road is cut where the junction stands on it. The holes of all the junctions of a road are taken together, so the cut
of one junction does not eat the next one.
"""
from city.roads import junctions as jn

ONE_SAMPLE = 6.0        # m: the cut of a junction that does not reach the road
CROSS_TOLERANCE = 15.0  # m: how far a lane end may be from the kerb return
HOLES = {}               # (city, road) -> the samples every junction of the road takes


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
    out = HOLES[key] = {}
    near = []
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
        near.append((junction, centre))
    for (junction, centre) in near:
        if out[junction["id"]] or road.elevated:
            continue
        arms, _centre = jn.arm_geometry(city, junction)
        radius = jn.road_radius(arms, road.id)
        reach = max(radius, 40.0) + CROSS_TOLERANCE
        if _ends_near(road, centre, reach, out, junction["id"]):
            continue
        _dist, idx, t = road.closest(centre)
        anchor = road.path[idx].lerp(road.path[idx + 1], t)
        for i, p in enumerate(road.path):
            if (p - anchor).length <= ONE_SAMPLE:
                out[junction["id"]].add(i)
    # the cuts of two junctions that stand on the same stretch of road must not
    # eat each other: the road keeps a stretch of lane between them
    order = sorted(out.items(), key=lambda item: min(item[1]) if item[1] else 0)
    for k in range(1, len(order)):
        hole = order[k][1]
        before = order[k - 1][1]
        if not hole or not before:
            continue
        first = min(hole)
        if first <= max(before):
            for i in list(before):
                if i >= first - 2:
                    before.discard(i)
    return out
