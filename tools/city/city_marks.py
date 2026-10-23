"""city_marks — the POIs, the sky lanes, the race routes and the spawns.

Every position is derived from the built road network, so a POI, a launch
pad, a checkpoint or a spawn always sits on a lane centre at the lane height
with the lane's heading.
"""
import math

import citylib


def _road(by_id, rid):
    return by_id.get(rid)


def _lane_at(road, s, direction, index=0):
    """The lane centre point and heading at the distance `s`."""
    p = road.lane_point(s, direction, index)
    h = road.lane_heading(s, direction)
    return p, h


def _nearest_s(road, point):
    """The arc length of the point on the road closest to `point`."""
    best, best_s = 1e18, 0.0
    for p, s in zip(road.points, road.dist):
        d = math.hypot(p[0] - point[0], p[2] - point[1])
        if d < best:
            best, best_s = d, s
    return best_s


# ---------------------------------------------------------------- POIs

def build_pois(by_id):
    """The POIs of the map (dossier 7.2, 8.1, 8.2 and the gameplay rules)."""
    pois = []

    def add(pid, kind, x, y, z, heading, size, label, asset):
        pois.append({"id": pid, "kind": kind, "x": round(x, 1), "y": round(y, 1),
                     "z": round(z, 1), "heading_deg": round(heading % 360.0, 1),
                     "size": [round(size[0], 1), round(size[1], 1)],
                     "label": label, "asset": asset})

    # the toll plaza on the G50 (dossier 7.2)
    g50 = by_id.get("g50_west")
    if g50 is not None:
        s = _nearest_s(g50, (-2070.0, 728.0))
        p, h = _lane_at(g50, s, 1, 1)
        add("toll_west", "toll", p[0], p[1], p[2], h, (160.0, 60.0),
            "申城西收费站", "toll_plaza")
    # the gas station on the frontage road (dossier 8.1)
    add("gas_sinopex", "gas", -1900.0, 0.0, 790.0, 90.0, (80.0, 64.0),
        "中石华加油站", "gas_station")
    add("gas_petrochino", "gas", 830.0, 0.0, 707.0, 134.0, (70.0, 50.0),
        "申油加油站", "gas_station")
    # the EV charging stations (dossier 8.2)
    add("charge_sky", "charge", 1680.0, 0.0, 420.0, 0.0, (80.0, 80.0),
        "申城闪充·浦东站", "charge_station")
    add("charge_bund", "charge", -700.0, 0.0, 230.0, 115.0, (60.0, 50.0),
        "申城闪充·西藏路站", "charge_station")
    add("charge_nanjing", "charge", -330.0, 0.0, -520.0, 270.0, (60.0, 50.0),
        "申城闪充·南京路站", "charge_station")
    # the police stations
    add("police_bund", "police_station", -160.0, 0.0, -520.0, 154.0,
        (40.0, 40.0), "外滩警察局", "police_station")
    add("police_lujiazui", "police_station", 1290.0, 0.0, -422.0, 62.0,
        (40.0, 40.0), "陆家嘴警察局", "police_station")
    # the hiding spots (gameplay 3.4: under a deck or in a tunnel)
    add("hide_dragon", "hiding_spot", -1310.0, 0.0, 700.0, 76.0, (30.0, 30.0),
        "龙柱下躲藏点", None)
    add("hide_under_deck", "hiding_spot", -1394.0, 0.0, 400.0, 177.0,
        (30.0, 30.0), "高架下躲藏点", None)
    add("hide_tunnel", "hiding_spot", 150.0, -25.0, -150.0, 125.0, (30.0, 30.0),
        "隧道躲藏点", None)
    add("hide_inner_ring", "hiding_spot", 200.0, 0.0, 1660.0, 90.0, (30.0, 30.0),
        "内环下躲藏点", None)
    # the roadblock sites: on their road, at its height, in the lane direction
    for pid, rid, target, label in (
            ("block_toll", "g50_west", (-2070.0, 728.0), "收费站路障"),
            ("block_yanan", "yanan_elevated", (-1800.0, 728.0), "延安路障"),
            ("block_ns", "ns_elevated", (-1394.0, 400.0), "南北高架路障"),
            ("block_spiral", "nanpu_spiral_upper", None, "南浦大桥路障")):
        road = by_id.get(rid)
        if road is None:
            continue
        if target is None:
            s = road.length() * 0.5
        else:
            s = _nearest_s(road, target)
        p, h = _lane_at(road, s, 1, 0)
        add(pid, "roadblock_site", p[0], p[1], p[2], h, (24.0, 4.0), label, None)
    return pois


def build_landmark_pois():
    """The landmark POIs (the anchors of dossier 10.2)."""
    import city_landmarks
    out = []
    for lid, x, z, (w, d), district, label, height in \
            city_landmarks.placed_landmarks():
        out.append({"id": "lm_%s" % lid, "kind": "landmark",
                    "x": round(x, 1), "y": round(height, 1), "z": round(z, 1),
                    "heading_deg": 0.0, "size": [round(w, 1), round(d, 1)],
                    "label": label, "asset": None})
    return out


# ---------------------------------------------------------------- sky lanes

BLOCK_INDEX = None
SKY_SLOPE = 0.34           # the most a sky lane climbs or dives
SKY_STEP = 10.0            # the spacing of the plan points of a sky lane
SKY_CLEAR = 10.0           # the sky lanes clear the lots by 10 m
SKY_LIFT = 8.0             # a sky lane lands 8 m above the road

# the landmark plazas a sky lane may thread: the pillar and the cables of
# the Nanpu bridge.  The other towers are obstacles, like any other lot.
SKY_EXEMPT = ("landmark:dragon_pillar", "landmark:nanpu_tower_w",
              "landmark:nanpu_tower_e")

# the five flight corridors: id, label, the road and the station of the pad,
# the direction of the traffic, the lane of the pad, the length of the
# lead-in, the road and the station of the landing, its direction and its
# lane, the length of the lead-out, the wanted cruise height and the gates
# of the flight.  The Huangpu jump climbs the Fujian Rd and leaps the river
# to the Lujiazui West Rd; the dragon stack flies over the pillar of the
# interchange; the century canyon runs along the Century Ave corridor below
# the towers; the Nanpu cables follow the deck of the bridge through its
# east tower; the Bund riverside leaves the Bund and crosses the river to
# the Lujiazui.  The gates of a flight are the points it passes between
# the lead-in and the lead-out: they keep the lane clear of the towers.
SKY_LANES = [
    ("huangpu_jump", "黄浦江飞跃", "st_fujian_rd", 300.0, 1, 0, 300.0,
     "lujiazui_w_rd", 400.0, 1, 0, 300.0, 100.0, []),
    ("dragon_stack", "龙柱立交飞跃", "ns_elevated", 1730.0, 1, 1, 120.0,
     "ns_elevated", 2150.0, 1, 1, 120.0, 60.0, []),
    ("century_canyon", "世纪大道峡谷", "st_d7_ns_15", 300.0, -1, 0, 250.0,
     "century_ave", 1050.0, 1, 1, 250.0, 90.0,
     [(1345.8, -88.8), (1357.8, -136.8), (1381.8, -160.8), (1441.8, -136.8)]),
    ("nanpu_cables", "南浦大桥缆索", "nanpu_bridge", 492.0, 1, 0, 250.0,
     "nanpu_pudong_loop", 60.0, 1, 0, 60.0, 60.0, []),
    ("bund_riverside", "外滩江畔", "st_jiujiang_rd", 300.0, -1, 0, 300.0,
     "lujiazui_w_rd", 500.0, 1, 0, 300.0, 100.0, []),
]


def _block_index(blocks):
    """A spatial index of the blocks (for the sky lane clearance)."""
    global BLOCK_INDEX
    if BLOCK_INDEX is None or BLOCK_INDEX[0] is not blocks:
        cells = {}
        for b in blocks:
            xs = [p[0] for p in b["polygon"]]
            zs = [p[1] for p in b["polygon"]]
            x0, x1 = min(xs), max(xs)
            z0, z1 = min(zs), max(zs)
            for i in range(int(x0 // 200), int(x1 // 200) + 1):
                for j in range(int(z0 // 200), int(z1 // 200) + 1):
                    cells.setdefault((i, j), []).append(b)
        BLOCK_INDEX = (blocks, cells)
    return BLOCK_INDEX[1]


def _height_at(blocks_index, x, z):
    """The height of the tallest lot under the plan position.

    The landmark plazas a sky lane is meant to thread are left out; every
    other lot is an obstacle, the towers of the dossier included.
    """
    best = 0.0
    for b in blocks_index.get((int(x // 200), int(z // 200)), ()):
        if b.get("notes") in SKY_EXEMPT:
            continue
        if citylib.point_in_polygon((x, z), b["polygon"]):
            best = max(best, b["height_m"][1])
    return best


def _densify(plan, step=SKY_STEP):
    """The plan with a point at least every `step` metres."""
    out = [[plan[0][0], plan[0][1]]]
    for a, b in zip(plan, plan[1:]):
        n = max(1, int(math.ceil(math.dist(a, b) / step)))
        for k in range(1, n + 1):
            t = float(k) / n
            out.append([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t])
    return out


def _lane_profile(plan, pad_y, cruise, end_y, blocks, climb_end, cruise_end,
                  slope=SKY_SLOPE):
    """The height of every plan point of a sky lane.

    The lane climbs over the lead-in, cruises over the flight and dives
    over the lead-out.  It clears every lot by 10 m and never climbs or
    dives faster than `slope`; the first point stays on the pad.
    """
    n = len(plan)
    cum = [0.0]
    for a, b in zip(plan, plan[1:]):
        cum.append(cum[-1] + math.dist(a, b))
    climb = cum[climb_end] or 1.0
    dive = (cum[-1] - cum[cruise_end]) or 1.0
    y = []
    for i in range(n):
        if cum[i] <= cum[climb_end]:
            base = pad_y + (cruise - pad_y) * (cum[i] / climb)
        elif cum[i] <= cum[cruise_end]:
            base = cruise
        else:
            base = cruise + (end_y - cruise) * ((cum[i] - cum[cruise_end]) / dive)
        y.append(base)
    # a segment takes the height of the tallest lot under it, so the line
    # between two points never dives into a roof
    for i in range(n - 1):
        a, b = plan[i], plan[i + 1]
        steps = max(1, int(math.dist(a, b) / 2.5))
        need = 0.0
        for k in range(steps + 1):
            t = float(k) / steps
            need = max(need, _height_at(blocks, a[0] + (b[0] - a[0]) * t,
                                        a[1] + (b[1] - a[1]) * t))
        need += SKY_CLEAR
        y[i] = max(y[i], need)
        y[i + 1] = max(y[i + 1], need)
    # the slope limit, forward and backward; the backward pass never lifts
    # the first point: the lane starts on the pad
    for _ in range(40):
        for i in range(1, n):
            y[i] = max(y[i], y[i - 1] - slope * (cum[i] - cum[i - 1]))
        for i in range(n - 2, 0, -1):
            y[i] = max(y[i], y[i + 1] - slope * (cum[i + 1] - cum[i]))
    y[0] = pad_y
    return y


def _lane_points(plan, y, pad, end, rings=250.0):
    """The lane points, the N2 ring distances and the end point."""
    cum = [0.0]
    for a, b in zip(plan, plan[1:]):
        cum.append(cum[-1] + math.dist(a, b))
    points = [[round(p[0], 1), round(h, 1), round(p[1], 1)]
              for p, h in zip(plan, y)]
    ring_list = []
    total = cum[-1]
    d = rings
    while d < total - 40.0:
        ring_list.append(d)
        d += rings
    return points, ring_list, cum


def straight_runup(road, direction, lo=0.0, hi=None, min_runup=300.0):
    """The station with the straightest run-up of `min_runup` metres.

    The run-up is measured in the direction the traffic runs, so a pad
    always has a straight approach behind it.
    """
    pts = road.points
    cum = [0.0]
    for a, b in zip(pts, pts[1:]):
        cum.append(cum[-1] + math.dist(a[:2], b[:2]))
    hi = cum[-1] if hi is None else hi
    best = None
    for i in range(len(pts) - 1):
        if not (lo <= cum[i] <= hi):
            continue
        if direction > 0:
            j = i
            while j > 0 and cum[i] - cum[j] < min_runup:
                j -= 1
        else:
            j = i
            while j < len(pts) - 1 and cum[j] - cum[i] < min_runup:
                j += 1
        if abs(cum[j] - cum[i]) < min_runup - 5.0:
            continue
        rng = range(j, i) if direction > 0 else range(i, j)
        h0 = road.lane_heading(cum[i], direction)
        dev = 0.0
        for m in rng:
            dev = max(dev, abs((road.lane_heading(cum[m], direction) - h0
                                + 540.0) % 360.0 - 180.0))
        if best is None or dev < best[0]:
            best = (dev, cum[i])
    return None if best is None else best[1]


def _road_run(road, s0, length, direction, lane_index, step=8.0):
    """The plan points of `length` metres of a lane, from the station `s0`
    in the direction of the traffic."""
    out = []
    n = max(1, int(round(length / step)))
    for k in range(n + 1):
        s = s0 + direction * min(length, k * step)
        p, _h = _lane_at(road, s, direction, lane_index)
        out.append([p[0], p[2]])
    return out


def _sky_lane(by_id, blocks, spec):
    """One sky lane: the pad, the lead-in, the flight and the landing.

    The lane leaves the pad along the road, climbs over the lead-in,
    flies over the city clear of the tall lots and dives over the road
    that carries the landing.
    """
    (lid, label, road_id, s_pad, direction, lane_index, lead_in,
     goal_road, goal_s, goal_dir, goal_lane, lead_out, cruise, gates) = spec
    road = by_id.get(road_id)
    goalr = by_id.get(goal_road)
    if road is None or goalr is None:
        return None
    # the pad sits at the straightest station of its run-up
    s_pad = straight_runup(road, direction, max(300.0, s_pad - 40.0),
                           s_pad + 40.0) or s_pad
    pad_p, pad_h = _lane_at(road, s_pad, direction, lane_index)
    goal_p, _goal_h = _lane_at(goalr, goal_s, goal_dir, goal_lane)
    end_y = goal_p[1] + SKY_LIFT
    # the lead-in: the road ahead of the pad, where the lane climbs; the
    # lead-out: the road behind the landing, where the lane dives
    lead = _road_run(road, s_pad, lead_in, direction, lane_index)
    tail = _road_run(goalr, goal_s - goal_dir * lead_out, lead_out,
                     goal_dir, goal_lane)
    cruise = min(cruise, pad_p[1] + SKY_SLOPE * lead_in,
                 end_y + SKY_SLOPE * lead_out)
    # the flight between the two: the gates keep it clear of the towers
    mid = [[g[0], g[1]] for g in gates]
    parts = [_densify(lead), _densify(mid) if mid else [], _densify(tail)]
    plan = parts[0] + parts[1] + parts[2]
    climb_end = len(parts[0]) - 1
    y = _lane_profile(plan, pad_p[1], cruise, end_y, _block_index(blocks),
                      climb_end, climb_end + len(parts[1]))
    points, rings, _cum = _lane_points(plan, y, pad_p, goal_p)
    return {"id": lid, "label": label, "points": points,
            "pad": {"x": round(pad_p[0], 1), "y": round(pad_p[1], 1),
                    "z": round(pad_p[2], 1), "heading_deg": round(pad_h, 1)},
            "n2_rings_m": rings}


def build_sky_lanes(by_id, blocks):
    """The flight corridors of the map (gameplay 5.6).

    Every lane has a launch pad on a lane centre with 300 m of straight
    run-up behind it, leaves in the direction of that lane, threads the
    towers of the dossier and lands over a drivable lane.
    """
    out = []
    for spec in SKY_LANES:
        lane = _sky_lane(by_id, blocks, spec)
        if lane is not None:
            out.append(lane)
    return out

