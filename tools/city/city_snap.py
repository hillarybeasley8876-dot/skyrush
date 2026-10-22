"""city_snap — the street ends are snapped onto the roads they meet.

The surface network has no dead ends: every street either ends on another
road (a junction) or at the window edge (the map lists those in `dead_ends`).

Two rules decide where a street end stops:
  * a street that *crosses* a road ends on that road's centre-line, so the
    junction sits where the two roads really meet;
  * a street that *runs along* a road (less than 35 deg between them) is cut
    at the road's edge and ends there, so the two footprints never overlap.

The searches run on a coarse index (the roads every 20 m) and the exact
geometry is used for the answer.

The module also carries the repair of the ends that reach nothing: the
lattice is cut by the district borders and by the corridors of the
arterials, so a street sometimes stops where the neighbouring district
has no street of its own.  `Net` holds the geometry of the map and the
searches below find the road such an end may reach.
"""
import math

import city_marks_routes
import citylib
from city_water import is_water, on_land

REACH = 400.0            # how far a street end looks for a road
STEP = 20.0              # the step of the walk along the street's line
CROSS_ANGLE = 35.0       # below this the street runs along the road
KEEP_OUT = 1.0           # the gap between a street end and the road's edge
T_JUNCTION = 14.0        # how close a street end must be to a road's
                         # centre-line to count as a T junction
COARSE = 10              # one point every 20 m in the search index

JUNCTION_GAP = 16.0      # the gap a street end may leave to a road and
                         # still make a junction (city_junctions)
AT_GRADE = 0.3           # the height a road must have to meet at grade
EXTEND_REACH = 900.0     # how far a street end may look for a road
CROSS_MIN = 60.0         # the angle a street may meet a road at
LINK_REACH = 250.0       # the longest link street a dead end may get
LINK_MIN = 25.0          # the shortest link street
LINK_ANGLE = 40.0        # the smallest angle a link meets its road at
JUNCTION_RADIUS = 45.0   # the radius the rule looks for a junction in
TRIM_REACH = 250.0       # the longest stub that may be cut back
DECK_CLEAR = 8.0         # the height a deck must have over a street
                         # (5.5 m of clearance plus the depth of the deck)
TUNNEL_CLEAR = 6.0       # the clearance over a tunnel lane
ROUTE_CHECKPOINTS = 10    # a route with more checkpoints can afford a new
                         # junction on one of its roads


def direction(plan, end):
    """The unit direction of a plan polyline at one of its ends."""
    if end == 0:
        a, b = plan[0], plan[1]
    else:
        a, b = plan[-2], plan[-1]
    dx, dz = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dz) or 1.0
    return (dx / length, dz / length)


def angle_between(a, b):
    """The angle between two directions, in degrees (0-90)."""
    dot = abs(a[0] * b[0] + a[1] * b[1])
    return math.degrees(math.acos(max(-1.0, min(1.0, dot))))


def poly_direction(poly, index):
    """The unit direction of a polyline at one of its points."""
    a = poly[max(0, index - 1)]
    b = poly[min(len(poly) - 1, index + 1)]
    dx, dz = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dz) or 1.0
    return (dx / length, dz / length)


def nearest_on(poly, point):
    """The distance from a point to a polyline and the index of its point."""
    best, best_i = 1e18, 0
    for i, p in enumerate(poly):
        d = math.dist(point, p)
        if d < best:
            best, best_i = d, i
    for j in (best_i - 1, best_i):
        if 0 <= j < len(poly) - 1:
            best = min(best, citylib.point_seg_distance(
                point, poly[j], poly[j + 1]))
    return best, best_i


def seg_hit(origin, direction, poly, limit=1e18):
    """The first point where the ray meets a polyline (None if it misses)."""
    best = None
    for a, b in zip(poly, poly[1:]):
        ex, ez = b[0] - a[0], b[1] - a[1]
        den = direction[0] * ez - direction[1] * ex
        if abs(den) < 1e-6:
            continue
        t = ((a[0] - origin[0]) * ez - (a[1] - origin[1]) * ex) / den
        u = ((a[0] - origin[0]) * direction[1]
             - (a[1] - origin[1]) * direction[0]) / den
        if t < -1.0 or u < 0.0 or u > 1.0 or t > limit:
            continue
        t = max(0.0, t)
        if best is None or t < best[0]:
            best = (t, (origin[0] + direction[0] * t,
                        origin[1] + direction[1] * t))
    return best[1] if best else None


def inside_window(point, window):
    """True if the plan position is inside the map window."""
    return (window["x_min"] <= point[0] <= window["x_max"]
            and window["z_min"] <= point[1] <= window["z_max"])


def coarse_index(polys, widths):
    """A search index with one point every 20 m of every road."""
    index = citylib.PolyIndex()
    for name, poly in polys.items():
        index.add(name, poly[::COARSE] + poly[-1:])
    return index


def scan(plan, end, index, polys, widths, own_id, window, reach=REACH):
    """The first road a street end meets along its own line.

    The result says what happened: "t" (the end is already on the road),
    "cross" (the street crosses the road and stops on its centre-line),
    "along" (the street runs along the road and stops at its edge),
    "window" (the line leaves the map window) or "none" (no road within
    `reach` metres).
    """
    point = (plan[end][0], plan[end][1])
    head = direction(plan, end)
    half = widths.get(own_id, 12.0) * 0.5
    for i in range(int(reach / STEP) + 1):
        s = i * STEP
        sample = (point[0] + head[0] * s, point[1] + head[1] * s)
        if not inside_window(sample, window):
            return {"kind": "window", "road": None, "point": sample, "s": s}
        best = None
        for name, _idx, _q in index.within(sample, 60.0):
            if name == own_id:
                continue
            poly = polys[name]
            other = widths.get(name, 0.0) * 0.5
            dist, pidx = nearest_on(poly, sample)
            if dist > other + half + KEEP_OUT:
                continue
            if best is None or dist < best[0]:
                best = (dist, name, poly, pidx)
        if best is None:
            continue
        dist, name, poly, pidx = best
        other = widths.get(name, 0.0) * 0.5
        if s == 0.0 and dist <= other + T_JUNCTION:
            return {"kind": "t", "road": name, "point": point, "s": s}
        if angle_between(head, poly_direction(poly, pidx)) >= CROSS_ANGLE:
            hit = seg_hit(point, head, poly, reach)
            return {"kind": "cross", "road": name,
                    "point": hit if hit else sample, "s": s}
        # the street runs along the road: it stops at the road's edge
        back = max(0.0, s - STEP)
        return {"kind": "along", "road": name,
                "point": (point[0] + head[0] * back, point[1] + head[1] * back),
                "s": s}
    return {"kind": "none", "road": None, "point": None, "s": reach}


def snap_end(plan, end, index, polys, widths, own_id, window):
    """Where a street end must stop, and the road it meets (or None).

    The end walks along its own line until it reaches a road: on the
    centre-line of a road it crosses, at the edge of a road it runs along.
    """
    hit = scan(plan, end, index, polys, widths, own_id, window, REACH)
    if hit["kind"] == "none":
        return None, None
    return hit["point"], hit["road"]


def seg_hits(a, b, poly):
    """The points where the segment a-b crosses a polyline."""
    dx, dz = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dz)
    if length < 1e-9:
        return []
    out = []
    for c, d in zip(poly, poly[1:]):
        if (max(a[0], b[0]) < min(c[0], d[0]) or max(c[0], d[0]) < min(a[0], b[0])
                or max(a[1], b[1]) < min(c[1], d[1])
                or max(c[1], d[1]) < min(a[1], b[1])):
            continue
        hit = _seg_hit(a, (dx / length, dz / length), [c, d], length)
        if hit is not None:
            out.append((hit[0], hit))
    out.sort()
    return out


def _seg_hit(origin, direction, poly, limit=1e18):
    """The first point where the ray meets a polyline (None if it misses)."""
    best = None
    for a, b in zip(poly, poly[1:]):
        ex, ez = b[0] - a[0], b[1] - a[1]
        den = direction[0] * ez - direction[1] * ex
        if abs(den) < 1e-6:
            continue
        t = ((a[0] - origin[0]) * ez - (a[1] - origin[1]) * ex) / den
        u = ((a[0] - origin[0]) * direction[1]
             - (a[1] - origin[1]) * direction[0]) / den
        if t < -1.0 or u < 0.0 or u > 1.0 or t > limit:
            continue
        t = max(0.0, t)
        if best is None or t < best[0]:
            best = (t, (origin[0] + direction[0] * t,
                        origin[1] + direction[1] * t))
    return best[1] if best else None


def closest_point(poly, point):
    """The point of a polyline closest to a point, and the distance."""
    best, best_i = 1e18, 0
    for i, p in enumerate(poly):
        d = math.dist(point, p)
        if d < best:
            best, best_i = d, i
    best_point = poly[best_i]
    for j in (best_i - 1, best_i):
        if 0 <= j < len(poly) - 1:
            a, b = poly[j], poly[j + 1]
            ab = (b[0] - a[0], b[1] - a[1])
            den = ab[0] ** 2 + ab[1] ** 2
            if den < 1e-9:
                continue
            t = max(0.0, min(1.0, ((point[0] - a[0]) * ab[0]
                                    + (point[1] - a[1]) * ab[1]) / den))
            q = (a[0] + ab[0] * t, a[1] + ab[1] * t)
            d = math.dist(point, q)
            if d < best:
                best = d
                best_point = q
    return best, best_point


# ---------------------------------------------------------------- the repairs

def resample(poly, step=15.0):
    """The points of a polyline, every `step` metres."""
    out = [poly[0]]
    for a, b in zip(poly, poly[1:]):
        length = math.dist(a, b)
        n = max(1, int(length / step))
        for k in range(1, n + 1):
            t = k / n
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


class Net:
    """The roads of the map and the geometry the end search needs.

    The plans are the (x, z) pairs of the roads, the heights tell
    whether a road runs at grade where a street end meets it: a deck
    that flies over a street is not an intersection.
    """

    def __init__(self, roads):
        self.roads = []
        self.by_id = {}
        self.poly = {}
        self.height = {}
        self.width = {}
        self.index = citylib.PolyIndex()
        for road in roads:
            self.add(road)

    def add(self, road):
        """Take a road into the net (and into its search index)."""
        self.poly[road.id] = [(p[0], p[2]) for p in road.points]
        self.height[road.id] = [p[1] for p in road.points]
        self.width[road.id] = citylib.road_width(road)
        if road.id not in self.by_id:
            self.roads.append(road)
        self.by_id[road.id] = road
        self.index.add(road.id, resample(self.poly[road.id]))

    def end_point(self, road, end):
        """The plan position of one end of a road."""
        pts = road.points
        p = pts[0] if end == 0 else pts[-1]
        return (p[0], p[2])

    def grade(self, road_id, point):
        """The height of a road at a plan position."""
        best, best_y = 1e18, 0.0
        for p, y in zip(self.poly[road_id], self.height[road_id]):
            d = math.hypot(p[0] - point[0], p[1] - point[1])
            if d < best:
                best, best_y = d, y
        return best_y

    def at_grade(self, road_id, point):
        """True if the road runs at ground level where it passes a point."""
        return abs(self.grade(road_id, point)) <= AT_GRADE


def outward(plan, end):
    """The unit direction a street end walks in, away from the street."""
    if end == 0:
        dx, dz = plan[0][0] - plan[1][0], plan[0][1] - plan[1][1]
    else:
        dx, dz = plan[-1][0] - plan[-2][0], plan[-1][1] - plan[-2][1]
    length = math.hypot(dx, dz) or 1.0
    return (dx / length, dz / length)


def touches(net, road, end, other_id):
    """True if the end of the road meets the other road."""
    point = net.end_point(road, end)
    dist, _near = closest_point(net.poly[other_id], point)
    return dist <= net.width[other_id] * 0.5 + JUNCTION_GAP


def junction_lands(net, road, end, other_id):
    """True if the junction of the two roads is made at this end.

    The junction builder looks at the two ends of a road in turn and
    stops at the first one that meets the other road, so the second end
    of a street that meets the same road twice gets no junction of its
    own.  Such an end has to reach a different road.
    """
    if end == 0:
        return True
    return not touches(net, road, 0, other_id)


def meet_angle(poly, point, near):
    """The angle between the direction to a road and the road's own line."""
    dist = math.dist(point, near)
    if dist < 1e-6:
        return 0.0
    link = ((near[0] - point[0]) / dist, (near[1] - point[1]) / dist)
    _d, pidx = nearest_on(poly, near)
    return angle_between(link, poly_direction(poly, pidx))


def near_roads(net, point, reach):
    """The roads near a point: (distance, id, the point on the road)."""
    out = []
    seen = set()
    for name, _idx, _q in net.index.within(point, reach):
        if name in seen:
            continue
        seen.add(name)
        poly = net.poly[name]
        dist, near = closest_point(poly, point)
        if dist <= reach:
            out.append((dist, name, near))
    out.sort()
    return out


def extend_target(net, road, end, lots=(), off_limits=()):
    """The road a street end reaches by going on along its own line.

    The end walks away from the street until it meets a road that it
    may end on: a road at grade (a deck that flies over the street is
    not an intersection) and one that gives the end a junction of its
    own.  The run must stay on land, keep clear of the landmark lots
    and pass under no deck that is too low.
    """
    point = net.end_point(road, end)
    head = outward(road.plan, end)
    half = net.width.get(road.id, 12.0) * 0.5
    skipped = set()
    s = 0.0
    while s <= EXTEND_REACH:
        sample = (point[0] + head[0] * s, point[1] + head[1] * s)
        best = None
        for name, _idx, _q in net.index.within(sample, 60.0):
            if name == road.id or name in skipped:
                continue
            poly = net.poly[name]
            other = net.width.get(name, 0.0) * 0.5
            dist, pidx = nearest_on(poly, sample)
            if dist > other + half + KEEP_OUT:
                continue
            if best is None or dist < best[0]:
                best = (dist, name, poly, pidx)
        if best is not None:
            dist, name, poly, pidx = best
            angle = angle_between(head, poly_direction(poly, pidx))
            if (angle >= CROSS_MIN and net.at_grade(name, sample)
                    and name not in off_limits
                    and junction_lands(net, road, end, name)):
                hit = seg_hit(point, head, poly, EXTEND_REACH)
                if (hit is not None and on_land(point, hit)
                        and clear_under(net, point, hit, road.id)
                        and not clears_routes(net, point, hit, name, road.id,
                                              off_limits)
                        and clear_of_lots(point, hit, lots,
                                          net.width[name] * 0.5 + 1.0)):
                    return hit
            skipped.add(name)
        s += STEP
    return None


def extend_plan(plan, end, target, step=20.0):
    """The plan of a street that goes on to the target.

    The new points lie on the line of the last stretch, so the street
    keeps its shape and only grows.
    """
    head = outward(plan, end)
    start = (plan[end][0], plan[end][1])
    length = math.dist(start, target)
    n = max(1, int(length / step))
    pts = [(start[0] + head[0] * length * k / n,
            start[1] + head[1] * length * k / n) for k in range(1, n + 1)]
    if end == 0:
        return list(reversed(pts)) + [list(p) for p in plan]
    return [list(p) for p in plan] + pts


def clear_under(net, p0, p1, own_id):
    """True if the run passes under no deck that is too low."""
    reach = math.dist(p0, p1) + 60.0
    for name, _idx, _q in net.index.within(p0, reach):
        if name == own_id:
            continue
        for _t, hit in seg_hits(p0, p1, net.poly[name]):
            height = net.grade(name, hit)
            if abs(height) <= AT_GRADE:
                continue
            if height > 0.0:
                if height < DECK_CLEAR:
                    return False
            elif -height < TUNNEL_CLEAR:
                return False
    return True


def route_roads(roads, junctions):
    """The roads of the race routes that the repair may not touch.

    A junction in the middle of a road changes the length of the legs
    of a route, and a route with few checkpoints may lose one of them
    and fall below the three the rule asks for.  A route with plenty of
    checkpoints can afford it.
    """
    try:
        routes = city_marks_routes.build_routes(
            {road.id: road for road in roads}, junctions)
    except Exception:
        return set()
    out = set()
    for route in routes:
        if len(route["checkpoints"]) >= ROUTE_CHECKPOINTS:
            continue
        for road_id, _direction in route["segments"]:
            out.add(road_id)
    return out


def link_target(net, road, end, lots=(), junctions=(), off_limits=()):
    """The point of the nearest road a link street may reach.

    The link is short, it stays on land, it misses the landmark lots
    and it meets the road it joins at a real angle, so the two roads
    share no pavement.  The road it joins must also be out of reach
    of the end itself: the junction builder gives the first end of a
    road that meets the other one the junction, and the link needs
    the junction at its own far end.
    """
    point = net.end_point(road, end)
    for dist, name, near in near_roads(net, point, LINK_REACH):
        if name == road.id or dist < LINK_MIN:
            continue
        if name in off_limits:
            continue        # a junction there would change the routes
        if not net.at_grade(name, near):
            continue
        if meet_angle(net.poly[name], point, near) < LINK_ANGLE:
            continue
        for target in _link_points(net, name, near, point):
            if math.dist(point, target) < LINK_MIN:
                continue
            if (math.dist(point, target) <= net.width[name] * 0.5 + JUNCTION_GAP
                    and math.dist(point, target) > JUNCTION_RADIUS):
                continue    # the far end of the link would stand alone
            if not clear_of_lots(point, target, lots,
                                 net.width[name] * 0.5 + 1.0):
                continue
            if not clears_routes(net, point, target, name, road.id,
                                 off_limits):
                continue
            if not on_land(point, target):
                continue
            return target
    return None


def _link_points(net, name, near, point, step=20.0):
    """The points of a road a link may join, the closest one first.

    The link may join the road a little away from the closest point:
    the closest one may lie in a lot that must not be cut.
    """
    out = [near]
    poly = net.poly[name]
    _d, pidx = nearest_on(poly, near)
    head = poly_direction(poly, pidx)
    for way in (1.0, -1.0):
        for k in range(1, 4):
            q = (near[0] + head[0] * step * k * way,
                 near[1] + head[1] * step * k * way)
            if math.dist(point, q) > LINK_REACH:
                continue
            out.append(q)
    return out


def clears_routes(net, p0, p1, target_id, own_id, off_limits):
    """True if the run keeps clear of the roads of the race routes.

    A junction in the middle of one of them changes the length of the
    legs of the routes, and a street that runs along one of them shares
    its pavement with it.
    """
    length = math.dist(p0, p1)
    for name, _idx, _q in net.index.within(p0, length + 60.0):
        if name in (target_id, own_id) or name not in off_limits:
            continue
        poly = net.poly[name]
        need = net.width[name] * 0.5 + 8.0
        n = max(1, int(length / 10.0))
        for i in range(n + 1):
            t = i / n
            q = (p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t)
            dist, _near = closest_point(poly, q)
            if dist < need:
                return False
    return True


def clear_of_lots(point, target, lots, margin):
    """True if the straight run between two points misses the lots.

    A lot that the street end already stands in is not the fault of the
    new road: the run may not come any closer to it, but it may leave.
    """
    for poly in lots:
        here = _poly_distance(point, poly)
        run = _run_distance(point, target, poly)
        if run < margin and run < here - 0.5:
            return False
    return True


def _poly_distance(point, poly):
    """The distance from a point to a polygon."""
    return min(citylib.point_seg_distance(point, poly[i], poly[(i + 1) % len(poly)])
               for i in range(len(poly)))


def _run_distance(p0, p1, poly):
    """The distance from a run to a polygon."""
    n = max(1, int(math.dist(p0, p1) / 10.0))
    best = 1e18
    for i in range(n + 1):
        t = i / n
        q = (p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t)
        best = min(best, _poly_distance(q, poly))
    return best


def trim_target(net, road, end, junctions):
    """The point of the last junction the road had before this end."""
    point = net.end_point(road, end)
    best = None
    for j in junctions:
        if road.id not in j["roads"]:
            continue
        d = math.dist((j["x"], j["z"]), point)
        if d < 10.0 or d > TRIM_REACH:
            continue
        if best is None or d < best[0]:
            best = (d, j)
    if best is None:
        return None
    _dist, near = closest_point(net.poly[road.id], (best[1]["x"], best[1]["z"]))
    return near


def trim_plan(plan, end, target):
    """The plan of a street cut back to the target.

    The points behind the target are dropped: the street ends where it
    had its last junction.
    """
    best = min(range(len(plan)),
               key=lambda i: math.dist(plan[i][:2], target))
    if end == 0:
        return [[target[0], target[1]]] + [list(p) for p in plan[best + 1:]]
    return [list(p) for p in plan[:best]] + [[target[0], target[1]]]


def dry(road):
    """True if the built road stays out of the water."""
    for p in road.points:
        if is_water((p[0], p[2])):
            return False
    return True


def replan(road, plan, net):
    """Give the road a new plan, if the built road stays out of the water."""
    old = road.plan
    road.plan = plan
    road.build()
    if not dry(road):
        road.plan = old
        road.build()
        return False
    net.add(road)
    return True


def fix_end(net, road, end, junctions, add, name, movable, lots=(),
            off_limits=()):
    """Give one dead end a road to meet.  True when it worked.

    The end is first joined to the nearest road by a short link, then
    extended along its own line to the next road, and last of all -
    when it is only a short stub - cut back to the last junction the
    road had.  A main road is never moved: it gets a link.

    The roads of the race routes are left alone as long as another
    road is within reach: a junction in the middle of one of them
    changes the length of the legs of the route.  When nothing else is
    within reach, the route road is used all the same - a street that
    reaches nothing is worse than a route that loses a checkpoint.
    """
    point = net.end_point(road, end)

    def link_to(limits):
        """A link street from the end to the road it may reach."""
        target = link_target(net, road, end, lots, junctions, limits)
        if target is None:
            return False
        link = add(name, road.name, road.name_en,
                   [point[0], point[1]], [target[0], target[1]],
                   1, 3.0, 30, road.style)
        if link is None:
            return False
        link.build()
        net.add(link)
        return True

    if link_to(off_limits):
        return True
    if movable:
        target = extend_target(net, road, end, lots, off_limits)
        if target is not None:
            if replan(road, extend_plan(road.plan, end, target), net):
                return True
        target = trim_target(net, road, end, junctions)
        if target is not None:
            plan = trim_plan(road.plan, end, target)
            if len(plan) < 2 or math.dist((plan[0][0], plan[0][1]),
                                         (plan[-1][0], plan[-1][1])) < 25.0:
                # the stub carries nothing: the street is dropped, the
                # way the snapped streets that collapsed into a stub are
                # dropped
                road.plan = plan
                return True
            if replan(road, plan, net):
                return True
    # the last resort: the road of a race route, when nothing else is
    # within reach
    return link_to(())
