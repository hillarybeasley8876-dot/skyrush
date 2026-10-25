"""city_skylanes — the flight path of a sky lane (gameplay 5.6).

The car flies a sky lane on rails: the shape of the path is the feel of the flight. A lane is planned from the road of the pad
(the lead-in), the gates and the road of the landing (the lead-out). Joined with straight lines they turned up to 111 degrees in
one point (4,285 deg/s of yaw and 322 g in the game, game/tools/flight_probe.gd); the height was straight lines with corners and
rose 10 m in the 8 m after the pad (51 degrees).

Here the plan becomes straight legs and circular arcs. Its corners (Douglas-Peucker) may merge with their neighbours into the one
corner where the legs before and after them meet; every corner gets the widest arc its legs give room for. An arc is narrowed while
it passes less than CLEAR over a lot or, off the plan, closer than LATERAL_CLEAR beside a lot the tube reaches; of the ways to
merge the corners the one with the widest tightest turn wins (then the widest next tightest, and so on). The height climbs from the pad, cruises and dives to the landing; the
slope ramps in and out over SLOPE_RAMP metres, so the pitch of the car turns gently at the pad, the cruise and the landing.
"""
import math

import citylib

STEP = 2.0               # m: the path is sampled this fine
KEEP_START = 30.0        # m of the road of the pad the lane flies straight on (the first segment heads along the pad)
KEEP_END = 40.0          # m of the road of the landing the lane flies straight on
SIMPLIFY = 2.0           # m: the corners of a plan (Douglas-Peucker): a leg keeps within OFF_PLAN of its road
MAX_RADIUS = 400.0       # m: the widest arc a corner gets
NARROW = 0.85            # an arc that passes too close to a lot is narrowed by this factor
MIN_ARC = 6.0            # m: a corner whose arc must be narrower than this fails
SLOPE_RAMP = 80.0        # m over which the slope of the climb and of the dive ramps in and out
CLEAR = 10.0             # m over every lot under the lane
LATERAL_CLEAR = 9.0      # m beside a lot the tube reaches (7.5 m of tube to each side and the car), off the plan
TUBE_DOWN = 4.0          # m: the tube reaches 3 m under the lane, the car 1 m more
OFF_PLAN = 2.0           # m: a point of the lane this far from the plan is a new stretch
LAND_LIFT = 1.0          # m: the lane ends this far over the road of the landing (the exit descends the car from there at 3 m/s)
OUT_STEP = 4.0           # m: the spacing of the points of the lane
MAX_LONGER = 1.1         # the legs of a corner list are at most this much longer than the plan (merged corners must not make a detour)
MAX_DEVIATION = 150.0    # m: the farthest a smooth lane strays from its plan
CELL = 50.0              # m: the cells of the lot index


def resample(plan, step=STEP):
    """The plan [[x, z]] with a point every `step` metres (the last point kept), and the distance of every point."""
    out = [list(plan[0])]
    cum = [0.0]
    carry = 0.0
    for a, b in zip(plan, plan[1:]):
        seg = math.dist(a, b)
        if seg < 1e-6:
            continue
        d = step - carry
        while d <= seg + 1e-9:
            t = d / seg
            out.append([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t])
            cum.append(cum[-1] + step)
            d += step
        carry = seg - (d - step)
    last = list(plan[-1])
    if math.dist(out[-1], last) > 1e-3:
        cum.append(cum[-1] + math.dist(out[-1], last))
        out.append(last)
    return out, cum


def _direction(a, b):
    d = [b[0] - a[0], b[1] - a[1]]
    n = math.hypot(*d) or 1.0
    return [d[0] / n, d[1] / n]


def _turn(u, v):
    """The signed angle from the direction u to the direction v (radians)."""
    return math.atan2(u[0] * v[1] - u[1] * v[0], u[0] * v[0] + u[1] * v[1])


def _segment_distance(p, a, b):
    ax, az = b[0] - a[0], b[1] - a[1]
    den = ax * ax + az * az
    t = 0.0 if den < 1e-12 else max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * az) / den))
    return math.hypot(p[0] - a[0] - ax * t, p[1] - a[1] - az * t)


def simplify(plan, tol):
    """Douglas-Peucker on the ground plane: the corners of the plan (the first and the last point stay)."""
    if len(plan) < 3:
        return [list(p) for p in plan]
    a, b = plan[0], plan[-1]
    L = math.dist(a, b) or 1e-9
    worst, idx = -1.0, 0
    for i in range(1, len(plan) - 1):
        p = plan[i]
        d = abs((b[0] - a[0]) * (a[1] - p[1]) - (a[0] - p[0]) * (b[1] - a[1])) / L
        if d > worst:
            worst, idx = d, i
    if worst <= tol:
        return [list(a), list(b)]
    return simplify(plan[: idx + 1], tol)[:-1] + simplify(plan[idx:], tol)


def _meet(a, b, c, d):
    """Where the line a->b meets the line c->d: (the point, how far ahead of a, how far ahead of c), or None when they are
    parallel."""
    u = _direction(a, b)
    v = _direction(c, d)
    den = u[0] * v[1] - u[1] * v[0]
    if abs(den) < 1e-6:
        return None
    wx, wz = c[0] - a[0], c[1] - a[1]
    t = (wx * v[1] - wz * v[0]) / den
    s = (wx * u[1] - wz * u[0]) / den
    return [a[0] + u[0] * t, a[1] + u[1] * t], t, s


def corner_sets(corners):
    """The corner lists of a plan: its corners, and every way to merge runs of neighbouring inner corners into the corner where
    the leg before the run and the leg after it meet. Each list comes with the names of its corners (the merged ones joined)."""
    inner = len(corners) - 2
    if inner < 2:
        return [(corners, [str(i) for i in range(1, inner + 1)])]
    out = []
    for mask in range(1 << (inner - 1)):
        groups = [[1]]
        for k in range(inner - 1):
            if mask >> k & 1:
                groups[-1].append(k + 2)
            else:
                groups.append([k + 2])
        new = [list(corners[0])]
        names = []
        lines = []      # the plan leg every new leg lies on: (from, to)
        ok = True
        prev_end = 0
        for g in groups:
            first, last = g[0], g[-1]
            lines.append((prev_end, first))
            if len(g) == 1:
                new.append(list(corners[first]))
            else:
                m = _meet(corners[first - 1], corners[first], corners[last], corners[last + 1])
                if m is None or m[1] <= 1.0 or m[2] >= math.dist(corners[last], corners[last + 1]) - 1.0:
                    ok = False
                    break
                new.append(m[0])
            names.append("+".join(str(i) for i in g))
            prev_end = last
        if not ok:
            continue
        lines.append((prev_end, len(corners) - 1))
        new.append(list(corners[-1]))
        # every leg runs the way its plan leg runs, and no corner turns back
        for i in range(len(new) - 1):
            a, b = lines[i]
            u = _direction(corners[a], corners[b])
            if (new[i + 1][0] - new[i][0]) * u[0] + (new[i + 1][1] - new[i][1]) * u[1] < 1.0:
                ok = False
        for i in range(1, len(new) - 1):
            if abs(_turn(_direction(new[i - 1], new[i]), _direction(new[i], new[i + 1]))) > math.radians(170.0):
                ok = False
        if ok:
            out.append((new, names))
    return out


def _turns(corners):
    """The signed turn at every inner corner (radians)."""
    return [_turn(_direction(corners[k - 1], corners[k]), _direction(corners[k], corners[k + 1]))
            for k in range(1, len(corners) - 1)]


def allocate(corners, caps):
    """The radius of every inner corner: the tightest one as wide as the legs give room for, then the next tightest, and so
    on (the first leg keeps KEEP_START metres straight and the last KEEP_END, at least half of them; a leg between two corners
    holds both their tangents), at most `caps[k]` each."""
    n = len(corners)
    inner = n - 2
    tans = []
    for k in range(1, n - 1):
        theta = abs(_turn(_direction(corners[k - 1], corners[k]), _direction(corners[k], corners[k + 1])))
        tans.append(math.tan(theta / 2.0))
    room = [math.dist(corners[j], corners[j + 1]) for j in range(n - 1)]
    room[0] -= min(KEEP_START, room[0] / 2.0)
    room[-1] -= min(KEEP_END, room[-1] / 2.0)
    radius = [None] * inner

    def on_leg(j):
        # leg j runs from corner j to corner j + 1: the inner corners j - 1 and j (0-based) sit at its ends
        return [k for k in (j - 1, j) if 0 <= k < inner]

    while any(r is None for r in radius):
        free = [k for k in range(inner) if radius[k] is None]
        level = min(caps[k] for k in free)
        tight = []
        for j in range(n - 1):
            used = sum(radius[k] * tans[k] for k in on_leg(j) if radius[k] is not None)
            coef = sum(tans[k] for k in on_leg(j) if radius[k] is None)
            if coef > 1e-9:
                fit = (room[j] - used) / coef
                if fit < level - 1e-9:
                    level, tight = fit, [j]
                elif abs(fit - level) <= 1e-9:
                    tight.append(j)
        level = max(level, 0.0)
        froze = False
        for k in free:
            if caps[k] <= level + 1e-9:
                radius[k] = caps[k]
                froze = True
        for j in tight:
            for k in on_leg(j):
                if radius[k] is None:
                    radius[k] = level
                    froze = True
        if not froze:
            for k in free:
                radius[k] = level
    return radius


def arc_path(corners, radii):
    """The corners joined by straight legs and arcs: (the points every STEP metres, their distances, the span of every arc along
    the path or None for a corner without one)."""
    out = [list(corners[0])]
    marks = []
    for k in range(1, len(corners) - 1):
        p = corners[k]
        u = _direction(corners[k - 1], p)
        v = _direction(p, corners[k + 1])
        theta = abs(_turn(u, v))
        r = radii[k - 1]
        t = r * math.tan(theta / 2.0)
        if theta < math.radians(0.5) or t < 0.5:
            out.append(list(p))
            marks.append(None)
            continue
        a = [p[0] - u[0] * t, p[1] - u[1] * t]
        side = 1.0 if u[0] * v[1] - u[1] * v[0] > 0.0 else -1.0
        c = [a[0] - u[1] * side * r, a[1] + u[0] * side * r]
        start = len(out)
        out.append(a)
        a0 = math.atan2(a[1] - c[1], a[0] - c[0])
        steps = max(2, int(math.ceil(r * theta / STEP)))
        for i in range(1, steps + 1):
            ang = a0 + side * theta * i / steps
            out.append([c[0] + r * math.cos(ang), c[1] + r * math.sin(ang)])
        marks.append((start, len(out) - 1))
    out.append(list(corners[-1]))
    dist = [0.0]
    for a, b in zip(out, out[1:]):
        dist.append(dist[-1] + math.dist(a, b))
    spans = [None if m is None else (dist[m[0]], dist[m[1]]) for m in marks]
    path, cum = resample(out)
    return path, cum, spans


def _ramp_integral(d, length, ramp):
    """The integral of a slope that ramps from 0 to 1 over `ramp` metres (smoothstep), holds and ramps back to 0 at `length`."""
    ramp = min(ramp, length / 2.0)
    if d <= 0.0:
        return 0.0
    if d >= length:
        return length - ramp
    if d < ramp:
        x = d / ramp
        return ramp * (x ** 3 - x ** 4 / 2.0)
    if d <= length - ramp:
        return ramp / 2.0 + (d - ramp)
    x = (d - (length - ramp)) / ramp
    return ramp / 2.0 + (length - 2.0 * ramp) + ramp * (x - x ** 3 + x ** 4 / 2.0)


def height_profile(cum, pad_y, cruise, end_y, climb, dive, slope):
    """The height of every point: up from the pad, the cruise, down to `end_y`. The climb is never steeper than `slope` (the
    slope ramps in and out over SLOPE_RAMP metres) and spreads over `climb` metres when the lane has the room (the road of the
    pad), the dive likewise over `dive` metres; a lane too short to climb to the cruise at the full slope cruises lower.
    Returns (heights, cruise)."""
    total = cum[-1]

    def shortest(c):
        return max(c - pad_y, 0.0) / slope + SLOPE_RAMP, max(c - end_y, 0.0) / slope + SLOPE_RAMP

    cruise = max(cruise, pad_y, end_y)
    lo = max(pad_y, end_y)
    if sum(shortest(cruise)) > total:
        hi = cruise
        for _ in range(40):
            mid = (lo + hi) / 2.0
            if sum(shortest(mid)) > total:
                hi = mid
            else:
                lo = mid
        cruise = lo
    s1, s2 = shortest(cruise)
    if s1 + s2 > total:
        s1, s2 = s1 * total / (s1 + s2), s2 * total / (s1 + s2)
    # the room left goes to the gentle climb over the road of the pad and the dive over the road of the landing
    want1, want2 = max(climb - s1, 0.0), max(dive - s2, 0.0)
    room = max(total - s1 - s2, 0.0)
    share = 1.0 if want1 + want2 <= room else room / (want1 + want2)
    d1, d2 = s1 + want1 * share, s2 + want2 * share
    h1 = cruise - pad_y
    h2 = cruise - end_y
    y = []
    for d in cum:
        up = h1 * _ramp_integral(d, d1, SLOPE_RAMP) / max(_ramp_integral(d1, d1, SLOPE_RAMP), 1e-9)
        down = h2 * (1.0 - _ramp_integral(total - d, d2, SLOPE_RAMP) / max(_ramp_integral(d2, d2, SLOPE_RAMP), 1e-9))
        y.append(pad_y + up - down)
    return y, cruise


class Lots:
    """The lots a lane must clear: their tops and polygons, in cells of CELL metres (a lot is in every cell within
    LATERAL_CLEAR of its bounds)."""

    def __init__(self, lots):
        self.cells = {}
        for top, poly in lots:
            xs = [p[0] for p in poly]
            zs = [p[1] for p in poly]
            box = (min(xs), max(xs), min(zs), max(zs))
            lot = (top, poly, box)
            for i in range(int((box[0] - LATERAL_CLEAR) // CELL), int((box[1] + LATERAL_CLEAR) // CELL) + 1):
                for j in range(int((box[2] - LATERAL_CLEAR) // CELL), int((box[3] + LATERAL_CLEAR) // CELL) + 1):
                    self.cells.setdefault((i, j), []).append(lot)
        self._cache = {}

    def near(self, x, z):
        """(the top of the lot under the point or 0, [(top, distance)] of the lots within LATERAL_CLEAR beside it)."""
        key = (round(x, 1), round(z, 1))
        hit = self._cache.get(key)
        if hit is not None:
            return hit
        under = 0.0
        beside = []
        for top, poly, box in self.cells.get((int(x // CELL), int(z // CELL)), ()):
            if x < box[0] - LATERAL_CLEAR or x > box[1] + LATERAL_CLEAR or z < box[2] - LATERAL_CLEAR \
                    or z > box[3] + LATERAL_CLEAR:
                continue
            if box[0] <= x <= box[1] and box[2] <= z <= box[3] and citylib.point_in_polygon((x, z), poly):
                under = max(under, top)
                beside.append((top, 0.0))
                continue
            d = min(_segment_distance((x, z), a, b) for a, b in zip(poly, poly[1:] + poly[:1]))
            if d < LATERAL_CLEAR:
                beside.append((top, d))
        hit = (under, beside)
        self._cache[key] = hit
        return hit


class Plan:
    """The plan of a lane (a polyline), in cells of CELL metres: how far a point is from it, up to OFF_PLAN and a bit."""

    REACH = OFF_PLAN + 1.0

    def __init__(self, plan):
        self.cells = {}
        for a, b in zip(plan, plan[1:]):
            x0, x1 = min(a[0], b[0]) - self.REACH, max(a[0], b[0]) + self.REACH
            z0, z1 = min(a[1], b[1]) - self.REACH, max(a[1], b[1]) + self.REACH
            for i in range(int(x0 // CELL), int(x1 // CELL) + 1):
                for j in range(int(z0 // CELL), int(z1 // CELL) + 1):
                    self.cells.setdefault((i, j), []).append((a, b))

    def off(self, p):
        """The distance of the point from the plan (infinity beyond REACH)."""
        best = float("inf")
        for a, b in self.cells.get((int(p[0] // CELL), int(p[1] // CELL)), ()):
            best = min(best, _segment_distance(p, a, b))
        return best if best <= self.REACH else float("inf")


def _violations(path, cum, y, plan_off, lots):
    """The points of the lane that pass too close to a lot: (index, the lot passes under it) for every point less than CLEAR
    over a lot, and for every point off the plan with a lot the tube reaches less than LATERAL_CLEAR beside it."""
    out = []
    for i, p in enumerate(path):
        under, beside = lots.near(p[0], p[1])
        if under > 0.0 and y[i] < under + CLEAR - 0.05:
            out.append((i, True))
            continue
        if plan_off[i] > OFF_PLAN:
            for top, d in beside:
                if top > y[i] - TUBE_DOWN and d < LATERAL_CLEAR:
                    out.append((i, False))
                    break
    return out


def _detour(corners, plan, plan_length):
    """Why a corner list strays from its plan (its legs are longer than MAX_LONGER of the plan, or a corner is more than
    MAX_DEVIATION from it), or "". The arcs only cut the corners: the legs are the longest the lane can be."""
    legs = sum(math.dist(a, b) for a, b in zip(corners, corners[1:]))
    if legs > plan_length * MAX_LONGER:
        return "a detour: %.0f m of legs for %.0f m of plan" % (legs, plan_length)
    for c in corners[1:-1]:
        away = min(_segment_distance(c, a, b) for a, b in zip(plan, plan[1:]))
        if away > MAX_DEVIATION:
            return "a corner %.0f m from the plan" % away
    return ""


def _arc_of(d, spans):
    """The corner whose arc holds the distance d along the path, or None (a straight leg)."""
    for k, span in enumerate(spans):
        if span is not None and span[0] - 1e-6 <= d <= span[1] + 1e-6:
            return k
    return None


def flight_plan(plan, pad_y, cruise, end_y, lots, climb, dive, slope):
    """The smooth plan of a lane and its height: the corner list (merged or not) with the widest tightest turn whose arcs keep
    clear of the lots. Returns (points every STEP, distances, heights, report)."""
    corners = simplify(plan, SIMPLIFY)
    line = Plan(plan)
    plan_length = sum(math.dist(a, b) for a, b in zip(plan, plan[1:]))
    best = None
    tried = []
    for cand, names in corner_sets(corners):
        caps = [MAX_RADIUS] * (len(cand) - 2)
        fail = _detour(cand, plan, plan_length)
        if fail:
            tried.append((names, [], fail))
            continue
        for _ in range(200):
            radii = allocate(cand, caps)
            path, cum, spans = arc_path(cand, radii)
            y, cruise_used = height_profile(cum, pad_y, cruise, end_y, climb, dive, slope)
            off = [line.off(p) for p in path]
            bad = _violations(path, cum, y, off, lots)
            narrowed = set()
            for i, _under in bad:
                if off[i] <= OFF_PLAN:
                    # on the plan the old lane flew there too: the height lifts the lane over the lot
                    continue
                k = _arc_of(cum[i], spans)
                if k is None:
                    fail = "a straight leg off the plan passes a lot at %.0f m" % cum[i]
                    break
                narrowed.add(k)
            if fail:
                break
            if not narrowed:
                break
            for k in narrowed:
                caps[k] = radii[k] * NARROW
                if caps[k] < MIN_ARC:
                    fail = "corner %s needs an arc under %.0f m" % (names[k], MIN_ARC)
            if fail:
                break
        else:
            fail = "no clear arcs after 200 tries"
        # every corner that turns counts, with the arc it got (none is 0 m)
        turning = [r if s is not None else 0.0 for r, s, t in zip(radii, spans, _turns(cand)) if abs(t) >= math.radians(0.5)]
        tried.append((names, radii, fail))
        if fail:
            continue
        # the tightest turn first, then the next tightest, and so on
        score = tuple(sorted(turning))
        if best is None or score > best[0]:
            best = (score, cand, names, radii, path, cum, y, cruise_used)
    if best is None:
        raise ValueError("no corner list of the lane keeps clear of the lots: %s" % tried)
    _score, cand, names, radii, path, cum, y, cruise_used = best
    # the plan legs the old lane flew over a lot on: the height lifts them (never steeper than the slope)
    need = []
    for p in path:
        under, _beside = lots.near(p[0], p[1])
        need.append(under + CLEAR if under > 0.0 else -1e9)
    lifted = sum(1 for a, b in zip(y, need) if b > a)
    if lifted:
        n = len(y)
        y = [max(a, b) for a, b in zip(y, need)]
        for _ in range(4):
            for i in range(1, n):
                y[i] = max(y[i], y[i - 1] - slope * (cum[i] - cum[i - 1]))
            for i in range(n - 2, 0, -1):
                y[i] = max(y[i], y[i + 1] - slope * (cum[i + 1] - cum[i]))
    report = {"corners": names, "radii": [r for r in radii], "cruise": cruise_used, "lifted": lifted,
              "length": cum[-1], "tried": len(tried)}
    return path, cum, y, report


def lane_points(plan, cum, y, step=OUT_STEP):
    """The points of the lane every `step` metres along the plan (the last point kept)."""
    out = []
    d = 0.0
    i = 0
    total = cum[-1]
    while d < total - step * 0.25:
        while i < len(cum) - 2 and cum[i + 1] < d:
            i += 1
        span = (cum[i + 1] - cum[i]) or 1.0
        t = (d - cum[i]) / span
        x = plan[i][0] + (plan[i + 1][0] - plan[i][0]) * t
        z = plan[i][1] + (plan[i + 1][1] - plan[i][1]) * t
        h = y[i] + (y[i + 1] - y[i]) * t
        out.append([round(x, 2), round(h, 2), round(z, 2)])
        d += step
    out.append([round(plan[-1][0], 2), round(y[-1], 2), round(plan[-1][1], 2)])
    return out


def rings(points, spacing=250.0):
    """The distances of the N2 rings along the lane."""
    total = sum(math.dist((a[0], a[2]), (b[0], b[2])) for a, b in zip(points, points[1:]))
    out = []
    d = spacing
    while d < total - 40.0:
        out.append(d)
        d += spacing
    return out


def flight_lane(plan, pad_y, cruise, end_y, lots, climb, dive, slope):
    """The points and the N2 rings of a sky lane from its plan [[x, z]] (the road of the pad, the gates, the road of the
    landing) and the lots it must clear [(top, polygon)]. Returns (points, rings, report)."""
    path, cum, y, report = flight_plan(plan, pad_y, cruise, end_y, Lots(lots), climb, dive, slope)
    points = lane_points(path, cum, y)
    return points, rings(points), report
