"""dragon_ramps — the eight ramps of the dragon-pillar interchange.

The interchange is the Yan'an / N-S crossing over the pillar at
(-1299, 687): Yan'an runs over it on L2 (Y 9.0) and the N-S line on L5
(Y 31.0).  Four left-turn ramps sweep over the axis - two on L3 (16.5 m)
and two on L4 (23.9 m) - and four right-turn ramps swing outside the
T-piers (at least 51 m from the axis).
"""
import math

import city_geom
from city_road import Road
from dragon import (AXIS_PASS, FLAT_HALF, HERMITE_STEPS, L3, L4, PILLAR,
                    RAMP_GRADE, RAMP_LANE_W, RAMP_SHOULDER, RAMP_STYLE, RIGHT_R,
                    Frame, adiff, arc_points, asphalt_half, closest_s,
                    dir_of, heading_of, hermite, left_normal, leg_mag,
                    right_normal, scale, tangent_point)

# ---------------------------------------------------------------- the eight

# The eight movements of the interchange.  The stations are given as an
# offset from the pillar on the main line the ramp leaves or joins, so the
# layout follows the main lines when they move.
#
#   id              from            dir  offset   to             dir  offset  level  lanes
#
# The right-turn ramps leave the main line far enough away that their long
# straight legs do not run under the left-turn ramps' carriageway edges: a
# right turn that leaves the Yan'an elevated 300 m before the pillar runs
# right past the point where the L3 left-turn ramp joins it, and the two decks
# would be 4 m apart over 200 m.
MOVES = [
    ("ramp_l3_eb_nb", "yanan_elevated", +1, -300.0, "ns_elevated", -1, -380.0, L3, 1),
    ("ramp_l3_wb_sb", "yanan_elevated", -1, +320.0, "ns_elevated", +1, +440.0, L3, 1),
    ("ramp_l4_nb_wb", "ns_elevated", -1, +200.0, "yanan_elevated", -1, -450.0, L4, 1),
    ("ramp_l4_sb_eb", "ns_elevated", +1, -180.0, "yanan_elevated", +1, +480.0, L4, 1),
    ("ramp_rt_eb_sb", "yanan_elevated", +1, -200.0, "ns_elevated", +1, +700.0, None, 2),
    ("ramp_rt_sb_wb", "ns_elevated", +1, -340.0, "yanan_elevated", -1, -200.0, None, 2),
    ("ramp_rt_wb_nb", "yanan_elevated", -1, +440.0, "ns_elevated", -1, -880.0, None, 2),
    ("ramp_rt_nb_eb", "ns_elevated", -1, +360.0, "yanan_elevated", +1, +300.0, None, 2),
]

LEAD_IN = 30.0                    # the straight merge into the main line

NAMES = {
    "ramp_l3_eb_nb": "延安高架左转匝道 EB>NB",
    "ramp_l3_wb_sb": "延安高架左转匝道 WB>SB",
    "ramp_l4_nb_wb": "南北高架左转匝道 NB>WB",
    "ramp_l4_sb_eb": "南北高架左转匝道 SB>EB",
    "ramp_rt_eb_sb": "延安高架右转匝道 EB>SB",
    "ramp_rt_sb_wb": "南北高架右转匝道 SB>WB",
    "ramp_rt_wb_nb": "延安高架右转匝道 WB>NB",
    "ramp_rt_nb_eb": "南北高架右转匝道 NB>EB",
}


def _resample(plan, step=8.0):
    """Resample a 2D polyline at a uniform spacing (the plan's points)."""
    if len(plan) < 2:
        return list(plan)
    out = [plan[0]]
    carry = 0.0
    for a, b in zip(plan, plan[1:]):
        seg = math.dist(a, b)
        if seg < 1e-9:
            continue
        d = step - carry
        while d <= seg:
            out.append((a[0] + (b[0] - a[0]) * d / seg,
                        a[1] + (b[1] - a[1]) * d / seg))
            d += step
        carry = seg - (d - step)
    if math.dist(out[-1], plan[-1]) > 1e-6:
        out.append(plan[-1])
    return out


def _spec(frame, move):
    """The movement record with the stations resolved on the main lines."""
    rid, frm, fdir, foff, to, tdir, toff, level, lanes = move
    return {"id": rid, "from": frm, "from_dir": fdir,
            "from_s": frame.station(frm, foff), "to": to, "to_dir": tdir,
            "to_s": frame.station(to, toff), "level": level, "lanes": lanes}


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
    # the last stretch runs straight along the main line's direction, so the
    # ramp joins it without a kink: a plain Hermite is still turning at its
    # end, and the rule measures the direction over the last metres.
    d = dir_of(h1)
    p1 = (p2[0] - d[0] * LEAD_IN, p2[1] - d[1] * LEAD_IN)
    b = hermite(m, scale(dir_of(mid), m1), p1, scale(dir_of(h1), m1))
    c = _line_points(p1, p2, 4)
    return a + b[1:] + c[1:], mid


def _right_plan(frame, spec, ramp_half, radius=None):
    """The plan of a right turn: a leg, a tangent arc and a leg.

    The arc is tangent to both legs, so the ramp leaves and joins its
    parents without a kink: the centre is where the two legs, offset by
    the arc radius to the right of the traffic, meet.
    """
    radius = RIGHT_R if radius is None else radius
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


def build(frame):
    """The eight ramp roads of the interchange."""
    roads = []
    for move in MOVES:
        spec = _spec(frame, move)
        lanes = spec["lanes"]
        ramp_half = lanes * RAMP_LANE_W / 2.0 + RAMP_SHOULDER
        if spec["level"] is not None:
            plan, mid = _left_plan(frame, spec, ramp_half)
            anchors = _flat_anchors(plan, spec["level"],
                                    frame.height(spec["from"], spec["from_s"]),
                                    frame.height(spec["to"], spec["to_s"]))
            notes = ("L%d left turn over the pillar axis (dossier 1.3); the "
                     "ramp grazes the axis %.1f m from it."
                     % (int(spec["level"]), AXIS_PASS))
        else:
            plan, mid = _right_plan(frame, spec, ramp_half)
            anchors = [("start", frame.height(spec["from"], spec["from_s"]), 0.0),
                       ("end", frame.height(spec["to"], spec["to_s"]), 0.0)]
            notes = "Right turn around the T-piers, outside the pillar axis."
        plan = _resample(plan)
        ramp = _road(spec["id"], NAMES[spec["id"]], plan, anchors, lanes,
                     {"road": spec["from"], "at": round(spec["from_s"], 2),
                      "side": _side(spec["from_dir"])},
                     {"road": spec["to"], "at": round(spec["to_s"], 2),
                      "side": _side(spec["to_dir"])},
                     notes)
        ramp.build()
        fix_attaches(ramp, frame)
        roads.append(ramp)
    return roads


def fix_attaches(ramp, frame):
    """Store the exact station of each attach (the projection of the ramp end)."""
    for key in ("attach_start", "attach_end"):
        att = getattr(ramp, key)
        if not att:
            continue
        parent = frame.road(att["road"])
        point = ramp.points[0] if key == "attach_start" else ramp.points[-1]
        att["at"] = round(_project_s(parent, point), 2)


def _project_s(road, point):
    """The station of the centre-line of `road` nearest to `point`."""
    best, best_s = 1e18, 0.0
    for p, s in zip(road.points, road.dist):
        d = math.hypot(p[0] - point[0], p[2] - point[2])
        if d < best:
            best, best_s = d, s
    return best_s


def table(frame, ramps):
    """The interchange table the lead asked for."""
    rows = []
    for ramp in ramps:
        best, best_y, best_hd = 1e18, 0.0, 0.0
        for i, p in enumerate(ramp.points):
            d = math.hypot(p[0] - PILLAR[0], p[2] - PILLAR[1])
            if d < best:
                best, best_y = d, p[1]
                nxt = ramp.points[min(i + 1, len(ramp.points) - 1)]
                best_hd = heading_of(nxt[0] - p[0], nxt[2] - p[2])
        rows.append((ramp.id, ramp.attach_start["road"], ramp.attach_start["at"],
                     ramp.attach_end["road"], ramp.attach_end["at"],
                     round(best, 1), round(best_y, 1), round(best_hd, 1),
                     round(ramp.length(), 1)))
    return rows


def budget(ramps):
    """The ramp ends that already use the Yan'an elevated.

    The list holds (direction, station) pairs: a new ramp has to keep
    WEAVE_GAP metres from the ramps that share its carriageway.
    """
    out = []
    for ramp in ramps:
        for key in ("attach_start", "attach_end"):
            att = getattr(ramp, key, None)
            if not att or att["road"] != "yanan_elevated":
                continue
            out.append((1 if att["side"] == "right" else -1, att["at"]))
    return out
