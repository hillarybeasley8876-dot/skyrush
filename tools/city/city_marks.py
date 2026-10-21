"""city_marks — the POIs, the sky lanes, the race routes and the spawns.

Every position is derived from the built road network, so a POI, a launch
pad, a checkpoint or a spawn always sits on a lane centre at the lane height
with the lane's heading.
"""
import math

import citylib

# the landmark plazas a sky lane threads (dossier 10.2)
TOWER_NOTES = ("landmark:dragon_pillar", "landmark:nanpu_tower_w",
                "landmark:nanpu_tower_e", "landmark:oriental_pearl",
                "landmark:swfc", "landmark:jin_mao",
                "landmark:shanghai_tower", "landmark:pearl_ring")


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
    """The height of the tallest block under the plan position.

    The landmark plazas are left out: a sky lane threads the towers of the
    dossier between their deck and their crossbeam.
    """
    for b in blocks_index.get((int(x // 200), int(z // 200)), ()):
        if b.get("notes") in TOWER_NOTES:
            continue
        if citylib.point_in_polygon((x, z), b["polygon"]):
            return b["height_m"][1]
    return 0.0


def _lane_profile(plan, pad_y, end_y, blocks, cruise=90.0, slope=0.34):
    """The height of a sky lane: it clears every block by 10 m and never
    climbs or dives faster than `slope`."""
    n = len(plan)
    cum = [0.0]
    for a, b in zip(plan, plan[1:]):
        cum.append(cum[-1] + math.dist(a, b))
    total = cum[-1]
    y = []
    for i, p in enumerate(plan):
        t = cum[i] / total if total else 0.0
        if i == 0:
            y.append(pad_y)
            continue
        # the climb, the cruise and the descent
        if t < 0.2:
            base = pad_y + (cruise - pad_y) * (t / 0.2)
        elif t < 0.75:
            base = cruise
        else:
            base = cruise + (end_y - cruise) * ((t - 0.75) / 0.25)
        need = _height_at(blocks, p[0], p[1]) + 10.0
        y.append(max(base, need))
    # enforce the slope limit with a forward and a backward pass
    for _ in range(60):
        for i in range(1, n):
            gap = slope * (cum[i] - cum[i - 1])
            y[i] = max(y[i], y[i - 1] - gap)
        for i in range(n - 2, -1, -1):
            gap = slope * (cum[i + 1] - cum[i])
            y[i] = max(y[i], y[i + 1] - gap)
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


def build_sky_lanes(by_id, blocks):
    """The flight corridors of the map (gameplay 5.6).

    Every lane has a launch pad on a lane centre with 300 m of straight
    run-up behind it, leaves in the direction of that lane, threads the
    towers of the dossier and lands over a drivable lane.
    """
    index = _block_index(blocks)
    out = []

    def make(lid, label, road_id, s_pad, direction, lane_index, waypoints,
             end_road, end_s, end_dir, end_lane, cruise=120.0, lift=8.0):
        road = by_id.get(road_id)
        endr = by_id.get(end_road)
        if road is None or endr is None:
            return
        pad_p, pad_h = _lane_at(road, s_pad, direction, lane_index)
        end_p, end_h = _lane_at(endr, end_s, end_dir, end_lane)
        plan = [[pad_p[0], pad_p[2]]] + [list(w) for w in waypoints] \
            + [[end_p[0], end_p[2]]]
        plan = _dedupe(plan)
        y = _lane_profile(plan, pad_p[1], end_p[1] + lift, index, cruise)
        points, ring_list, _cum = _lane_points(plan, y, pad_p, end_p)
        out.append({
            "id": lid,
            "label": label,
            "points": points,
            "pad": {"x": round(pad_p[0], 1), "y": round(pad_p[1], 1),
                    "z": round(pad_p[2], 1), "heading_deg": round(pad_h, 1)},
            "n2_rings_m": ring_list,
        })

    # the Huangpu jump: north up the Fujian Rd, over the river, down to the
    # Yincheng Rd on the Pudong side
    make("huangpu_jump", "黄浦江飞跃", "st_fujian_portal", 200.0, 1, 0,
         [(-300.0, 230.0), (0.0, 60.0), (300.0, -120.0), (600.0, -350.0)],
         "yincheng_rd", 245.0, -1, 0, cruise=70.0)
    # the dragon stack: up the N-S elevated, over the pillar, down again
    make("dragon_stack", "龙柱立交飞跃", "ns_elevated", 1730.0, 1, 1,
         [(-1394.0, 543.0), (-1299.0, 687.0), (-1200.0, 780.0)],
         "ns_elevated", 2150.0, 1, 1, cruise=60.0, lift=8.0)
    # the century canyon: along the Century Ave corridor, below the towers
    make("century_canyon", "世纪大道峡谷", "century_ave", 384.0, 1, 1,
         [(1250.0, -245.0), (1350.0, -200.0), (1450.0, -140.0)],
         "century_ave", 1050.0, 1, 1, cruise=70.0, lift=8.0)
    # the Nanpu cables: along the bridge deck, through the east tower
    make("nanpu_cables", "南浦大桥缆索", "nanpu_bridge", 492.0, 1, 0,
         [(1480.0, 1505.0), (1545.0, 1535.0)],
         "nanpu_pudong_loop", 60.0, 1, 0, cruise=60.0, lift=8.0)
    # the Bund riverside: south along the Bund, over the river, down to the
    # Lujiazui West Rd
    make("bund_riverside", "外滩江畔", "bund_zhongshan_e1", 300.0, -1, 1,
         [(-160.0, -760.0), (100.0, -750.0), (350.0, -700.0), (540.0, -790.0)],
         "lujiazui_w_rd", 0.0, 1, 0, cruise=60.0, lift=8.0)
    return out


def _dedupe(plan):
    """Drop the repeated points of a plan."""
    out = [list(plan[0])]
    for p in plan[1:]:
        if math.dist(out[-1], p) > 1.0:
            out.append(list(p))
    return out
