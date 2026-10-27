"""The shape of a movement through a junction.

A movement is a cubic Bezier from the end of the approach lane to the start of
the exit lane.  Its two control arms decide the shape: the arms of the
circular arc through the two ends turn the smoothest, a shorter arm turns
tighter (and stays inside the kerb return of the junction), a longer one turns
gently (and leaves the fill).

The old code pulled the control points towards the centre of the junction until
every sample lay inside the fill, and moved every sample that still lay
outside onto the outline of the fill.  Consecutive samples landed on different
edges of that outline: the curve became a zigzag along the kerb, it backed up
and it turned corners (1093 connectors of 7261).

This module searches the arms instead: every candidate is one smooth curve, and
the one that is the smoothest and still stays on the asphalt of the junction
wins.  Where no curve of the family fits, the caller keeps the old curve: it
is covered by the asphalt of the junction, it only drives badly.

The points are Blender vectors: x and y are the plan, z is the height.
"""
import math

from city.roads import junction_fill, levels

SCALES = (0.3, 0.45, 0.6, 0.75, 0.9, 1.0, 1.15, 1.32, 1.55)
CORNERS = (0.2, 0.4, 0.6, 0.8, 1.0, 1.3)
PULLS = (0.2, 0.4, 0.6, 0.8)
LOOP_DEG = 60.0     # degrees of turning beyond the net turn: a curve that winds back and forth
STRETCH = 1.6       # length over chord
STRETCH_PAD = 6.0   # m
KINK_DEG = 50.0     # degrees in one step: a corner no car drives
CORRIDOR = 6.0      # m: how far a sample may leave the line of its lane before it is off the road
STEP = 2.0          # the samples of a curve are this far apart


def arms(chord, turn):
    """The arms of the circular arc that joins two points with that turn."""
    s = abs(math.sin(turn * 0.5))
    if s < 1e-3:
        return chord / 3.0     # a straight movement: the arms lie on the line
    radius = chord / (2.0 * s)
    return (4.0 / 3.0) * radius * math.tan(abs(turn) * 0.25)


def _plan_dist(a, b):
    """The distance of two points in the plane of the junction."""
    return math.hypot(b.x - a.x, b.y - a.y)


def resample(pts, step=STEP):
    """The points every `step` metres along the curve, keeping both ends."""
    if len(pts) < 2:
        return pts
    out = [pts[0]]
    carry = 0.0
    for a, b in zip(pts, pts[1:]):
        seg = _plan_dist(a, b)
        d = step - carry
        while d <= seg:
            t = d / seg if seg > 1e-6 else 0.0
            point = a.lerp(b, t)
            if _plan_dist(out[-1], point) > 0.6:
                out.append(point)
            d += step
        carry = seg - (d - step)
    if _plan_dist(out[-1], pts[-1]) > 1e-4:
        if len(out) > 1 and _plan_dist(out[-1], pts[-1]) < 0.6:
            out.pop()
        out.append(pts[-1])
    return out


def curve(p0, p3, d0, d1, a, b, step=STEP):
    """The Bezier with the arms `a` and `b`, sampled every `step` metres."""
    return bezier(p0, p0 + d0 * a, p3 - d1 * b, p3, step)


def bezier(p0, p1, p2, p3, step=STEP):
    """A cubic Bezier sampled every `step` metres."""
    count = max(2, int(math.ceil(_plan_dist(p0, p3) / step)))
    out = []
    for i in range(count + 1):
        t = i / float(count)
        u = 1.0 - t
        out.append(p0 * (u ** 3) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t ** 3))
    return resample(out, step)


def shape(pts):
    """(length, chord, net turn, turning both ways, worst step) of a curve, in degrees."""
    if len(pts) < 2:
        return (0.0, 0.0, 0.0, 0.0, 0.0)
    heads = []
    length = 0.0
    for a, b in zip(pts, pts[1:]):
        dx = b.x - a.x
        dy = b.y - a.y
        step = math.hypot(dx, dy)
        length += step
        if step > 0.05:
            heads.append(math.atan2(dy, dx))
    turns = []
    for a, b in zip(heads, heads[1:]):
        t = b - a
        while t > math.pi:
            t -= 2.0 * math.pi
        while t < -math.pi:
            t += 2.0 * math.pi
        turns.append(t)
    net = math.degrees(sum(turns))
    both = math.degrees(sum(abs(t) for t in turns))
    worst = math.degrees(max((abs(t) for t in turns), default=0.0))
    chord = math.hypot(pts[-1].x - pts[0].x, pts[-1].y - pts[0].y)
    return (length, chord, net, both, worst)


def defects(pts):
    """(loop, stretch, kink, worst step): how far the curve is from a driven path."""
    length, chord, net, both, worst = shape(pts)
    return (max(0.0, both - abs(net) - LOOP_DEG),
            max(0.0, length - STRETCH * chord - STRETCH_PAD),
            max(0.0, worst - KINK_DEG),
            worst)


def smooth(pts):
    """True when the curve is the path a car could drive: no loop, no corner."""
    return all(d == 0.0 for d in defects(pts)[:3])


def nearest_on_ring(ring, p):
    """The point of the ring closest to `p`."""
    best = None
    for i in range(len(ring)):
        a = ring[i]
        b = ring[(i + 1) % len(ring)]
        ab = b - a
        l2 = ab.length_squared
        t = 0.0 if l2 < 1e-9 else max(0.0, min(1.0, (p - a).dot(ab) / l2))
        q = a + ab * t
        d = (q - p).length_squared
        if best is None or d < best[0]:
            best = (d, q)
    return best[1] if best else None


def corner(p0, p3, d0, d1):
    """The vertex where the two lanes meet, and the distances to it.

    The two lanes of a movement are lines that cross somewhere: the traffic
    drives along one of them into the junction and leaves along the other one.
    The vertex is where the turn happens, and the distances to it say how much
    of the road a car drives on before it turns.
    """
    det = d0.x * (-d1.y) - d0.y * (-d1.x)
    if abs(det) < 1e-6:
        return None
    rhs = p3 - p0
    t = (rhs.x * (-d1.y) - rhs.y * (-d1.x)) / det
    c = p0 + d0 * t
    return (c, t, (p3 - c).dot(d1))


def _controls(p0, p3, d0, d1, turn, hub):
    """The control points of every candidate curve of the movement.

    Three families:
    the scale family, the arms of the circular arc through the two ends, made
    shorter (a tighter turn that stays inside the kerb return) or longer;
    the corner family, the curve that follows the lane into the junction and
    turns at the corner of the two lanes: the fillet of that corner, with the
    arms of the Bezier that draws it;
    the pulled family, the control points drawn towards the centre of the
    junction, which keeps the curve in the middle of the asphalt.
    """
    out = []
    base = arms(_plan_dist(p0, p3), turn)
    for s in SCALES:
        out.append((p0 + d0 * (base * s), p3 - d1 * (base * s)))
    at = corner(p0, p3, d0, d1)
    if at is not None:
        _c, ta, tb = at
        half = abs(math.tan(turn * 0.5))
        if half > 1e-3 and ta > 0.0 and tb > 0.0:
            # the corner is ahead of the car and behind the lane it joins
            reach = min(ta, tb)
            for f in CORNERS:
                t = reach * f
                k = (4.0 / 3.0) * (t / half) * math.tan(abs(turn) * 0.25)
                out.append((p0 + d0 * (ta - t + k), p3 - d1 * (tb - t + k)))
    if hub is not None:
        for pull in PULLS:
            out.append(((p0 + d0 * base).lerp(hub, pull), (p3 - d1 * base).lerp(hub, pull)))
    return out


def _deviation(pts, ref):
    """How far a curve is from another one: the mean distance of its samples to it."""
    if not ref or len(ref) < 2:
        return 0.0
    total = 0.0
    for p in pts:
        best = 1e9
        for a, b in zip(ref, ref[1:]):
            abx = b.x - a.x
            aby = b.y - a.y
            l2 = abx * abx + aby * aby
            t = 0.0 if l2 < 1e-9 else max(0.0, min(1.0, ((p.x - a.x) * abx + (p.y - a.y) * aby) / l2))
            dx = p.x - (a.x + abx * t)
            dy = p.y - (a.y + aby * t)
            d = math.hypot(dx, dy)
            if d < best:
                best = d
        total += best
    return total / len(pts)


def _edges(ring):
    """The edges of the ring as plain numbers: the inside test is done a lot."""
    out = []
    n = len(ring)
    for i in range(n):
        a = ring[i]
        b = ring[(i + 1) % n]
        out.append((a.x, a.y, b.x, b.y))
    return out


def _inside(px, py, edges):
    """True when the plan point lies inside the polygon."""
    inside = False
    for x0, y0, x1, y1 in edges:
        if (y0 > py) != (y1 > py):
            if px < x0 + (py - y0) * (x1 - x0) / (y1 - y0):
                inside = not inside
    return inside


def _flags(pts, edges):
    """Which samples lie inside the polygon."""
    return [_inside(p.x, p.y, edges) for p in pts]


def _one_run(flags):
    """The first and the last sample inside the polygon, or None when they are not one run."""
    first = None
    last = -1
    for i, f in enumerate(flags):
        if f:
            if first is None:
                first = i
            last = i
    if first is None:
        return None
    for i in range(first, last + 1):
        if not flags[i]:
            return None
    return (first, last)


def _along_lane(p, origin, direction, behind):
    """True when the point runs along the line of the lane it belongs to."""
    vx = p.x - origin.x
    vy = p.y - origin.y
    along = vx * direction.x + vy * direction.y
    if behind:
        if along > 0.0:
            return False
    elif along < 0.0:
        return False
    return abs(vx * direction.y - vy * direction.x) <= CORRIDOR


def _on_road(pts, p0, d0, p3, d1, run):
    """The samples outside the fill must run along the lanes they come from."""
    first, last = run
    for p in pts[:first]:
        if not _along_lane(p, p0, d0, False):
            return False
    for p in pts[last + 1:]:
        if not _along_lane(p, p3, d1, True):
            return False
    return True


def _tier(pts, p0, d0, p3, d1, edges, wide, ring):
    """(tier, escape): 0 = on the asphalt, 1 = on the collision, 2 = off the junction."""
    if edges is None:
        return 0, 0.0
    run = _one_run(_flags(pts, edges))
    if run is not None and _on_road(pts, p0, d0, p3, d1, run):
        return 0, 0.0
    run = _one_run(_flags(pts, wide))
    if run is not None and _on_road(pts, p0, d0, p3, d1, run):
        return 1, 0.0
    escape = 0.0
    for p in pts:
        if _inside(p.x, p.y, wide):
            continue
        near = nearest_on_ring(ring, p)
        if near is not None:
            escape = max(escape, (near - p).length)
    return 2, escape


def choose(p0, p3, d0, d1, fan=None, straight=False, hub=None, old=None):
    """The plan of the movement: the smoothest curve that stays on the fill.

    `p0` is the end of the approach lane, `p3` the start of the exit lane and
    `d0`/`d1` their directions.  `old` is the plan of the curve the movement
    had before, the yardstick of a merge: two roads that meet without a fill
    have no asphalt between them, and a curve that leaves the roads drives on
    the ground.  The result is the list of the points of the curve and the
    tier it reaches: 0 on the asphalt of the junction, 1 on its collision, 2
    off the junction.
    """
    turn = math.atan2(d0.x * d1.y - d0.y * d1.x, d0.x * d1.x + d0.y * d1.y)
    base = arms(_plan_dist(p0, p3), turn)
    edges = None
    wide = None
    ring = None
    if fan is not None:
        ring = fan[1]
        edges = _edges(ring)
        wide = _edges(levels.offset_ring(ring, junction_fill.COLLIDER_MARGIN))
    plain = curve(p0, p3, d0, d1, base, base)
    if straight and d0.dot(d1) > 0.95 and smooth(plain):
        # a straight movement keeps its plain curve: the fill of a junction does
        # not reach the far lanes of a wide road that passes it, and every curve
        # that bends into the fill cuts across the other lanes of that road
        return plain, 0
    # the candidates: the smoothest ones first, so the first one that stays on
    # the asphalt of the junction is the one that drives the best
    cands = []
    for p1, p2 in _controls(p0, p3, d0, d1, turn, hub):
        pts = bezier(p0, p1, p2, p3)
        if len(pts) < 2:
            continue
        d = defects(pts)
        cands.append((d[0] + d[1] + d[2], d[3], pts))
    cands.sort(key=lambda c: (c[0] > 0.0, c[0], c[1]))
    if edges is None:
        # a merge has no fill: the curve has to stay on the roads, and the
        # curve it had is the one that stays on them
        good = [c for c in cands if c[0] == 0.0]
        pool = good if good else cands
        best = min(pool, key=lambda c: (_deviation(c[2], old), c[0], c[1]))
        return best[2], 0
    best = None
    for viol, worst, pts in cands:
        tier, escape = _tier(pts, p0, d0, p3, d1, edges, wide, ring)
        cost = (1 if viol > 0.0 else 0, tier, viol, worst, escape)
        if best is None or cost < best[0]:
            best = (cost, pts, tier)
        if tier == 0 and viol == 0.0:
            break       # the smoothest curve on the asphalt: nothing can beat it
    if best is None:
        return [], 2
    return best[1], best[2]
