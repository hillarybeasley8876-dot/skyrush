"""dragon — the Yan'an / N-S dragon-pillar interchange (dossier §1.3).

The pillar axis P = (-1299, 687).  Yan'an runs over it on L2 (Y 9.0) and the
N-S line on L5 (Y 31.0).  Four left-turn ramps sweep over the axis - two on
L3 (16.5 m) and two on L4 (23.9 m) - and four right-turn ramps swing
outside the T-piers (at least 51 m from the axis).

Geometry of a left turn
-----------------------
The ramp leaves its parent on the *carriageway edge* (never on the centre
line): the ramp's own centre-line sits at

    lateral = direction * (asphalt_half(parent) + asphalt_half(ramp))

to the right of the parent's points, so the ramp serves exactly one
carriageway and the parent's lanes stay clear.  The plan is two cubic
Hermite pieces:

    attach point -> M -> attach point

where M is 4.2 m from the pillar axis, on the inside of the turn, with the
heading that the two main lines make at the axis.  The two ramps of a level
therefore graze the axis anti-parallel, 8.4 m apart, and the decks abut.

Geometry of a right turn
------------------------
A right turn is a straight leg, a circular arc tangent to both legs and a
straight leg again (the classic highway ramp).  The arc's centre lies on the
outside of the turn, so the ramp stays clear of the pillar.
"""
import math

from city_geom import (adiff, arc_points, dir_of, heading_of, hermite,
                        left_normal, leg_mag, right_normal, scale, tangent_point)
from city_road import Road

PILLAR = (-1299.0, 687.0)
L2 = 9.0
L3 = 16.5
L4 = 23.9
L5 = 31.0

AXIS_PASS = 4.2        # the left turns graze the pillar axis this close
AXIS_CLEAR = 51.0      # the right turns stay at least this far from it
RIGHT_R = 180.0        # the radius of the right-turn arcs
RAMP_GRADE = 0.0495     # the design grade of the ramps (the brief allows 5 %)
FLAT_HALF = 20.0       # the level stretch around the axis, each way
RAMP_LANE_W = 3.75
RAMP_SHOULDER = 1.5
HERMITE_STEPS = 24     # samples per Hermite piece

RAMP_STYLE = {"parapet": "planter", "lamps": "barrier",
              "soffit_led": "#5A3DFF", "trees": "none"}


def closest_s(road, point):
    """The arc length of the station of `road` nearest to `point`."""
    best, best_s = 1e18, 0.0
    for p, s in zip(road.points, road.dist):
        d = math.hypot(p[0] - point[0], p[2] - point[1])
        if d < best:
            best, best_s = d, s
    return best_s


def asphalt_half(road):
    """Half the paved width of a road (the roads unit's `layout()` rule)."""
    get = road.get if isinstance(road, dict) else (
        lambda k, d=0.0: getattr(road, k, d))
    if get("lanes_back", 0) == 0:
        return (get("lanes_fwd", 0) * get("lane_width", RAMP_LANE_W) / 2.0
                + get("shoulder", 0.0))
    inner = 0.5 if (get("kind") in ("elevated", "ramp", "bridge")
                    and get("median", 0.0) > 0) else 0.0
    return (get("median", 0.0) / 2.0 + inner
            + get("lanes_fwd", 0) * get("lane_width", RAMP_LANE_W)
            + get("shoulder", 0.0))


# ---------------------------------------------------------------- the frame

class Frame:
    """The two main lines and the pillar they cross over."""

    def __init__(self, yanan, ns):
        self.yanan = yanan
        self.ns = ns
        self.sy = closest_s(yanan, PILLAR)
        self.sn = closest_s(ns, PILLAR)

    def road(self, which):
        """The main line called "yanan_elevated" or "ns_elevated"."""
        return self.yanan if which == "yanan_elevated" else self.ns

    def pillar_s(self, which):
        """The station of the pillar on a main line."""
        return self.sy if which == "yanan_elevated" else self.sn

    def station(self, which, offset):
        """A station `offset` metres from the pillar (positive = further along)."""
        return self.pillar_s(which) + offset

    def heading(self, which, s):
        """The heading of the centre-line at a station."""
        _p, tan = self.road(which).point_at(s)
        return heading_of(tan[0], tan[2])

    def flow_heading(self, which, s, direction):
        """The heading of the traffic that runs in `direction` on a main line."""
        h = self.heading(which, s)
        return h if direction > 0 else (h + 180.0) % 360.0

    def height(self, which, s):
        """The height of the deck at a station."""
        return self.road(which).point_at(s)[0][1]

    def attach(self, which, s, direction, ramp_half):
        """The point and traffic heading where a ramp meets a main line.

        The point sits on the edge of the carriageway the ramp serves: at
        `asphalt_half(parent) + ramp_half` to the right of the parent's
        points for a ramp that runs with them, to the left for one that runs
        against them.
        """
        road = self.road(which)
        p, tan = road.point_at(s)
        h = heading_of(tan[0], tan[2])
        lat = direction * (asphalt_half(road) + ramp_half)
        rn = right_normal(h)
        flow = h if direction > 0 else (h + 180.0) % 360.0
        return (p[0] + rn[0] * lat, p[2] + rn[1] * lat), flow

    def axis_heading(self, from_which, from_dir, to_which, to_dir):
        """The heading a ramp must carry over the pillar axis.

        It is the mean of the two main lines' traffic headings at the axis,
        so the ramp crosses the pillar the way the dossier sketches it.
        """
        hp_f = self.flow_heading(from_which, self.pillar_s(from_which), from_dir)
        hp_t = self.flow_heading(to_which, self.pillar_s(to_which), to_dir)
        return (hp_f + adiff(hp_f, hp_t) * 0.5) % 360.0


# ---------------------------------------------------------------- the ramps

def _road(rid, name, plan, anchors, lanes, attach_start, attach_end, notes):
    """A ramp road with its cross-section and its two attaches."""
    return Road(rid, name, name_en=name, kind="ramp", plan=plan, anchors=anchors,
                lanes_fwd=lanes, lanes_back=0, lane_width=RAMP_LANE_W, median=0.0,
                shoulder=RAMP_SHOULDER, sidewalk=0.0, speed_kmh=40,
                style=RAMP_STYLE, attach_start=attach_start, attach_end=attach_end,
                max_grade=RAMP_GRADE, notes=notes)


def _side(direction):
    """The schema's side name for a ramp that runs in `direction`."""
    return "right" if direction > 0 else "left"


def _flat_anchors(plan, level, y_start, y_end, flat_half=FLAT_HALF):
    """The height anchors: the parent's heights and the level stretch."""
    centre = _nearest(plan, PILLAR)
    before = _point_at_distance(plan, centre, -flat_half)
    after = _point_at_distance(plan, centre, flat_half)
    return [("start", y_start, 0.0),
            ("p", before[0], before[1], level, 0.0),
            ("p", after[0], after[1], level, 0.0),
            ("end", y_end, 0.0)]


def _nearest(plan, point):
    """The index of the plan point nearest to `point`."""
    best, best_i = 1e18, 0
    for i, p in enumerate(plan):
        d = math.hypot(p[0] - point[0], p[1] - point[1])
        if d < best:
            best, best_i = d, i
    return best_i


def _point_at_distance(plan, index, distance):
    """The plan point `distance` metres along the polyline from `index`."""
    if distance >= 0:
        i = index
        left = distance
        while i < len(plan) - 1:
            seg = math.dist(plan[i], plan[i + 1])
            if seg >= left:
                t = left / seg if seg else 0.0
                return (plan[i][0] + t * (plan[i + 1][0] - plan[i][0]),
                        plan[i][1] + t * (plan[i + 1][1] - plan[i][1]))
            left -= seg
            i += 1
        return plan[-1]
    i = index
    left = -distance
    while i > 0:
        seg = math.dist(plan[i - 1], plan[i])
        if seg >= left:
            t = left / seg if seg else 0.0
            return (plan[i][0] + t * (plan[i - 1][0] - plan[i][0]),
                    plan[i][1] + t * (plan[i - 1][1] - plan[i][1]))
        left -= seg
        i -= 1
    return plan[0]


def _left_plan(frame, spec, ramp_half):
    """The plan of a left turn: two Hermite pieces through the axis point."""
    p0, h0 = frame.attach(spec["from"], spec["from_s"], spec["from_dir"], ramp_half)
    p2, h1 = frame.attach(spec["to"], spec["to_s"], spec["to_dir"], ramp_half)
    mid = frame.axis_heading(spec["from"], spec["from_dir"], spec["to"], spec["to_dir"])
    ln = left_normal(mid)
    m = (PILLAR[0] + AXIS_PASS * ln[0], PILLAR[1] + AXIS_PASS * ln[1])
    m0 = leg_mag(p0, h0, m, mid)
    m1 = leg_mag(m, mid, p2, h1)
    a = hermite(p0, scale(dir_of(h0), m0), m, scale(dir_of(mid), m1))
    b = hermite(m, scale(dir_of(mid), m1), p2, scale(dir_of(h1), m1))
    return a + b[1:], mid


def _right_plan(frame, spec, ramp_half, radius=RIGHT_R):
    """The plan of a right turn: a leg, a tangent arc and a leg.

    The arc is tangent to both legs, so the ramp leaves and joins its
    parents without a kink: the centre is where the two legs, offset by the
    arc radius to the right of the traffic, meet.
    """
    p0, h0 = frame.attach(spec["from"], spec["from_s"], spec["from_dir"], ramp_half)
    p2, h1 = frame.attach(spec["to"], spec["to_s"], spec["to_dir"], ramp_half)
    turn = adiff(h0, h1)
    u0, u1 = dir_of(h0), dir_of(h1)
    n0, n1 = right_normal(h0), right_normal(h1)
    reach = 1.0 - math.cos(math.radians(turn))
    chord = (p2[0] - p0[0], p2[1] - p0[1])
    limit = min(-(chord[0] * n1[0] + chord[1] * n1[1]),
                chord[0] * n0[0] + chord[1] * n0[1]) / max(reach, 1e-6)
    r = max(20.0, min(radius, limit * 0.95))
    c0 = (p0[0] + r * n0[0], p0[1] + r * n0[1])
    c1 = (p2[0] + r * n1[0], p2[1] + r * n1[1])
    centre = tangent_point(c0, u0, c1, u1)
    t0 = (centre[0] - p0[0]) * u0[0] + (centre[1] - p0[1]) * u0[1]
    t1 = (centre[0] - p2[0]) * u1[0] + (centre[1] - p2[1]) * u1[1]
    a_start = (p0[0] + t0 * u0[0], p0[1] + t0 * u0[1])
    a_end = (p2[0] + t1 * u1[0], p2[1] + t1 * u1[1])
    arc = arc_points(centre, r, h0, h1)
    leg1 = _line_points(p0, a_start, HERMITE_STEPS // 2)
    leg2 = _line_points(a_end, p2, HERMITE_STEPS // 2)
    return leg1 + arc[1:] + leg2[1:], (h0 + turn * 0.5) % 360.0


def _line_points(p0, p1, n):
    """The straight line from p0 to p1, sampled."""
    return [(p0[0] + (p1[0] - p0[0]) * i / float(n),
             p0[1] + (p1[1] - p0[1]) * i / float(n)) for i in range(n + 1)]
