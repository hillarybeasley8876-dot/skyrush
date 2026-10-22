"""city_roads — the main road network of SKYRUSH (dossier §10.3).

Every road is authored here as plan control points plus height anchors; the
generator (build_city.py) collects them into data/city/city.json.  The
geometry comes from ref/shanghai/build/map_layout_v1.json (river banks, road
centrelines, anchors) and the dossier §10.3.

Anchor forms (see city_road.Road):
    ("start", y, g)          the first station
    ("end", y, g)            the last station
    ("p", x, z, y, g)        at the plan position nearest to (x, z)
    ("near", x, z, d, y, g)  d metres along the road from the plan position
                             nearest to (x, z) (d may be negative)
"""
import math

import city_attach
import city_roads_east
import citylib
from city_geom import arc_points, dir_of, right_normal
from city_road import Road

PILLAR = (-1299.0, 687.0)          # dragon pillar axis (dossier §10.2)
SPIRAL_C = (1021.3, 1124.8)        # Nanpu spiral centre
SP_UPPER_R = 152.0                 # upper loop radius (brief: 150)
SP_LOWER_R = 100.0                 # lower loop radius (brief, R 100 +- 5)
PD_LOOP_C = (1699.1, 1496.8)       # Pudong descending loop centre
PD_LOOP_R = 100.0
PD_LOOP_A0 = 244.3                 # the loop starts at the bridge's end
PD_LOOP_A1 = 784.3                 # ... and unwinds 540 deg before it lands
PD_LOOP_GROWTH = 18.0              # the loop spirals out over the turn

SP_MERGE_AT = (1073.0, 1268.0)     # the lower loop's merge (build_city.py)
PD_LANDING = (1690.0, 1280.0)      # the Pudong loop's landing (build_city.py)

# the lower loop's cross-section (the paved half width comes from it)
LOWER_HALF = city_attach.asphalt_half(
    {"kind": "ramp", "lanes_fwd": 2, "lanes_back": 0, "lane_width": 3.75,
     "shoulder": 1.0, "median": 0.0})

ELEV_STYLE = {"parapet": "planter", "lamps": "median_double",
              "soffit_led": "#5A3DFF", "trees": "none"}
NANPU_STYLE = {"parapet": "planter", "lamps": "median_double",
               "soffit_led": "#3D7BFF", "trees": "none"}


def surface_style(lamp="side", trees="none"):
    return {"parapet": "none", "lamps": lamp, "trees": trees}


def elevated_style(extra=None):
    out = dict(ELEV_STYLE)
    if extra:
        out.update(extra)
    return out


# ---------------------------------------------------------------- main lines

def g50_west():
    """G50 expressway at grade at the west end, through the toll plaza."""
    plan = [(-2200.0, 728.0), (-2150.0, 728.0), (-1990.0, 728.0)]
    return Road("g50_west", "G50 沪渝高速", "G50 Huyu Expressway", "surface", plan,
                [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=3, lanes_back=3, lane_width=3.75, median=2.0,
                shoulder=0.5, sidewalk=0.0, speed_kmh=100,
                style=surface_style("side"),
                notes="Toll plaza at x = -2070; the deck of the Yan'an elevated "
                      "starts at x = -1990.")


def yanan_elevated():
    """Yan'an Elevated Rd: at grade -> climb -> L2 (Y 9) over the pillar -> Y 10."""
    plan = [(-1990.0, 728.0), (-1798.0, 728.0), (-1740.0, 728.0),
            (-1568.0, 725.0), (-1434.0, 730.0), (-1395.0, 732.0),
            (-1316.0, 711.0), (-1216.0, 664.0), (-1040.0, 581.0),
            (-666.0, 235.0), (-560.0, 185.0), (-460.0, 165.0), (-380.0, 152.0),
            (-320.0, 146.0), (-287.0, 144.0)]
    anchors = [
        ("start", 0.0, 0.0),
        ("p", -1660.0, 728.0, 10.0, 0.0),      # Y 10 (see notes)
        ("near", PILLAR[0], PILLAR[1], -150.0, 9.0, 0.0),
        ("near", PILLAR[0], PILLAR[1], 0.0, 9.0, 0.0),
        ("near", PILLAR[0], PILLAR[1], 150.0, 9.0, 0.0),
        ("p", -666.0, 235.0, 10.0, 0.0),
        ("end", 0.0, 0.0),
    ]
    return Road("yanan_elevated", "延安高架路", "Yan'an Elevated Rd", "elevated",
                plan, anchors, lanes_fwd=3, lanes_back=3, lane_width=3.75,
                median=1.0, shoulder=1.25, speed_kmh=80,
                style=elevated_style({"noise_walls": [[300.0, 900.0, "left"],
                                                      [1500.0, 2100.0, "right"]]}),
                pier_spacing=30.0, max_grade=0.049,
                notes="L2 (Y=9.0) for 300 m around the dragon pillar, Y=10 "
                      "elsewhere; the 0 -> 10 m climb needs 340 m, so the deck "
                      "is level 10 from x=-1660 (the dossier says -1740). The "
                      "east end descends to grade at (-287, 144) over 410 m.")



def yanan_rd_surface():
    """Surface Yan'an Rd, under the elevated from x=-1700 on."""
    plan = [(-1700.0, 740.0), (-1567.5, 737.0), (-1433.5, 742.0),
            (-1395.0, 743.0), (-1316.0, 722.0), (-1216.5, 675.0),
            (-1040.0, 592.0), (-666.0, 246.0), (-560.0, 228.0),
            (-460.0, 208.0), (-380.0, 188.0), (-320.0, 168.0),
            (-287.0, 144.0), (-163.0, 118.0), (-88.0, 82.0), (0.0, 0.0)]
    return Road("yanan_rd_surface", "延安东路", "Yan'an Rd (surface)", "surface",
                plan, [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=3, lanes_back=3, lane_width=3.75, median=1.0,
                shoulder=0.5, sidewalk=3.0, speed_kmh=60,
                style=surface_style("magnolia", "plane"),
                notes="Runs under the Yan'an elevated from x=-1700 eastward and "
                      "peels off south of the descending deck before the "
                      "merge at (-287, 144).")


def yanan_frontage_south():
    """One-way service road south of the G50, the gas station frontage."""
    plan = [(-2200.0, 752.0), (-1990.0, 752.0), (-1860.0, 752.0),
            (-1760.0, 752.0), (-1700.0, 752.0)]
    return Road("yanan_frontage_s", "延安路辅道", "Yan'an Rd Frontage (south)",
                "surface", plan, [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=1, lanes_back=0, lane_width=4.0, median=0.0,
                shoulder=0.5, sidewalk=2.0, speed_kmh=40,
                style=surface_style("side"),
                notes="One-way eastbound service road; the gas station (8.1) "
                      "opens onto it at x=-1900.")


def yanan_frontage_north():
    """One-way service road north of the G50."""
    plan = [(-2200.0, 700.0), (-1990.0, 700.0), (-1860.0, 700.0),
            (-1760.0, 706.0), (-1700.0, 726.0)]
    return Road("yanan_frontage_n", "延安路辅道北", "Yan'an Rd Frontage (north)",
                "surface", plan, [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=0, lanes_back=1, lane_width=4.0, median=0.0,
                shoulder=0.5, sidewalk=2.0, speed_kmh=40,
                style=surface_style("side"),
                notes="One-way westbound service road.")


def ns_elevated():
    """N-S Elevated Rd (Chengdu Rd): 12 m -> 31 m over the pillar -> down south."""
    plan = [(-1660.0, -1200.0), (-1628.0, -1019.0), (-1530.0, -473.0),
            (-1434.0, -116.0), (-1402.0, 202.0), (-1387.0, 533.0),
            (-1370.0, 594.0), (-1343.0, 642.0), (-1301.0, 689.0),
            (-1274.0, 719.0), (-1230.0, 769.0), (-1202.0, 808.0),
            (-1177.0, 877.0), (-1162.0, 936.0), (-1178.0, 1034.0),
            (-1228.0, 1256.0), (-1195.0, 1393.0), (-1122.0, 1510.0)]
    anchors = [
        ("start", 12.0, 0.0),
        ("p", -1402.0, 202.0, 12.0, 0.0),
        ("near", PILLAR[0], PILLAR[1], -12.0, 31.0, 0.0),
        ("near", PILLAR[0], PILLAR[1], 0.0, 31.0, 0.0),
        ("near", PILLAR[0], PILLAR[1], 12.0, 31.0, 0.0),
        ("p", -1228.0, 1256.0, 12.0, 0.0),
        ("end", 10.0, 0.0),
    ]
    return Road("ns_elevated", "南北高架路", "N-S Elevated Rd", "elevated", plan,
                anchors, lanes_fwd=3, lanes_back=3, lane_width=3.75,
                median=1.0, shoulder=1.25, speed_kmh=80, style=elevated_style(),
                pier_spacing=30.0, max_grade=0.049,
                no_piers=[[1180.0, 1420.0]],
                notes="L5 (Y=31) at the dragon pillar; the flat is 24 m long "
                      "because the 0.5 %/10 m kink rule and the 5 % grade limit "
                      "leave no room for more.")


def inner_ring():
    """Inner Ring Elevated (re-routed along the south edge) to the spiral."""
    plan = [(-1122.0, 1510.0), (-1000.0, 1640.0), (-600.0, 1680.0),
            (200.0, 1660.0), (600.0, 1560.0), (780.0, 1380.0),
            (900.0, 1290.0), spiral_point(SPIRAL_C, SP_UPPER_R, 270.0)]
    return Road("inner_ring", "内环高架路", "Inner Ring Elevated", "elevated", plan,
                [("start", 10.0, 0.0), ("end", 10.0, 0.0)],
                lanes_fwd=2, lanes_back=2, lane_width=3.75, median=1.0,
                shoulder=1.0, speed_kmh=80, style=elevated_style(),
                pier_spacing=30.0,
                notes="Y=10 throughout; joins the spiral upper loop at its south "
                      "point (1021, 1277).")


# ---------------------------------------------------------------- Nanpu

def spiral_point(centre, radius, angle_deg):
    """A point of the Nanpu spiral (the angle grows counter-clockwise)."""
    a = math.radians(angle_deg)
    return [centre[0] + radius * math.cos(a), centre[1] - radius * math.sin(a)]


def _circle_points(centre, radius, a0_deg, a1_deg, n):
    """Points on a circle; the angle grows counter-clockwise seen from above."""
    out = []
    for i in range(n + 1):
        a = math.radians(a0_deg + (a1_deg - a0_deg) * i / n)
        out.append([centre[0] + radius * math.cos(a), centre[1] - radius * math.sin(a)])
    return out


def _loop_start_angle():
    """The angle where the lower spiral loop leaves Zhongshan E-2/S.

    The loop starts at grade on the riverside road (dossier 3.3), so its
    first point has to lie on that road.
    """
    line = [(p[0], p[1]) for p in zhongshan_e2_s().plan]
    best, best_a = 1e18, 20.0
    for i in range(0, 3600):
        angle = i * 0.1
        p = spiral_point(SPIRAL_C, SP_LOWER_R, angle)
        d = min(citylib.point_seg_distance(p, a, b)
                for a, b in zip(line, line[1:]))
        if d < best:
            best, best_a = d, angle
    return best_a


def _spiral_points(centre, a0, a1, r0, r1, n, out_at=0.62):
    """The plan of a spiral that grows from the radius r0 to r1.

    The radius is constant over the first part of the turn and then grows
    with a smoothstep, so the ramp leaves the spiral along the circle's
    tangent and merges into the loop without a kink.
    """
    a_out = a0 + (a1 - a0) * out_at
    out = []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        t = max(0.0, (a - a_out) / (a1 - a_out))
        r = r0 + (r1 - r0) * (3.0 * t * t - 2.0 * t * t * t)
        rad = math.radians(a)
        out.append([centre[0] + r * math.cos(rad), centre[1] - r * math.sin(rad)])
    return out


def nanpu_spiral_lower():
    """Puxi spiral lower loop: R 100, 3/4 turn, Y 0 -> 12, merges into L3."""
    upper = nanpu_spiral_upper()      # the loop the ramp merges into
    upper.build()
    # the ramp ends on the inner edge of the upper loop's carriageway (the
    # loop runs counter-clockwise, so its inner edge is to the left)
    lateral = -(city_attach.asphalt_half(upper) + LOWER_HALF)
    pts = [tuple(p) for p in upper.points]
    i = min(range(len(pts)),
            key=lambda j: math.hypot(pts[j][0] - SP_MERGE_AT[0],
                                     pts[j][2] - SP_MERGE_AT[1]))
    p = pts[i]
    a, b = pts[max(0, i - 2)], pts[min(len(pts) - 1, i + 2)]
    heading = math.degrees(math.atan2(b[0] - a[0], -(b[2] - a[2]))) % 360.0
    rn = right_normal(heading)
    merge = (p[0] + rn[0] * lateral, p[2] + rn[1] * lateral)
    # the radius spirals out to the merge radius over the last third of
    # the turn, so the ramp reaches the loop's edge along its direction
    start = _loop_start_angle()
    a_end = math.degrees(math.atan2(SPIRAL_C[1] - merge[1],
                                     merge[0] - SPIRAL_C[0])) % 360.0
    if a_end < start:
        a_end += 360.0
    r_end = math.hypot(merge[0] - SPIRAL_C[0], merge[1] - SPIRAL_C[1])
    plan = _spiral_points(SPIRAL_C, start, a_end, SP_LOWER_R, r_end, 50)
    return Road("nanpu_spiral_lower", "南浦大桥下层环道", "Nanpu Spiral Lower Loop",
                "ramp", plan, [("start", 0.0, 0.0), ("end", p[1], 0.0)],
                lanes_fwd=2, lanes_back=0, lane_width=3.75, median=0.0,
                shoulder=1.0, speed_kmh=40,
                style={"parapet": "planter", "lamps": "barrier",
                       "soffit_led": "#3D7BFF", "trees": "none"},
                max_grade=0.038,
                notes="R=100 m, 3/4 turn counter-clockwise, Y 0 -> 12; the "
                      "radius spirals out to %.1f m over the last third of "
                      "the turn and merges onto the L3 loop's inner edge, "
                      "along its direction." % r_end)


def nanpu_spiral_upper():
    """Puxi spiral upper loop: R 150, 341 deg, Y 10 -> 42.5 (4.0 %)."""
    pts = _circle_points(SPIRAL_C, SP_UPPER_R, 270.0, 615.0, 60)
    return Road("nanpu_spiral_upper", "南浦大桥上层环道", "Nanpu Spiral Upper Loop",
                "elevated", pts, [("start", 10.0, 0.0), ("end", 42.5, 0.0)],
                lanes_fwd=2, lanes_back=2, lane_width=3.75, median=1.0,
                shoulder=1.0, speed_kmh=40, style=NANPU_STYLE, pier_spacing=30.0,
                max_grade=0.040,
                notes="R=152 m, 345 deg counter-clockwise, 3.9 % climb to the "
                      "bridge deck (42.5 m).")


def nanpu_bridge():
    """Nanpu Bridge deck: spiral exit -> Puxi tower -> mid-span -> Pudong tower."""
    plan = [spiral_point(SPIRAL_C, SP_UPPER_R, 615.0), [1050.0, 1300.0],
            [1139.4, 1338.2],
            [1234.7, 1384.1], [1330.0, 1430.0], [1425.5, 1476.0],
            [1520.6, 1521.8], spiral_point(PD_LOOP_C, PD_LOOP_R + 4.0, 244.3)]
    anchors = [("start", 42.5, 0.0), ("p", 1139.4, 1338.2, 44.0, 0.0),
               ("p", 1330.0, 1430.0, 45.5, 0.0),
               ("p", 1520.6, 1521.8, 44.0, 0.0), ("end", 42.5, 0.0)]
    return Road("nanpu_bridge", "南浦大桥", "Nanpu Bridge", "bridge", plan, anchors,
                lanes_fwd=3, lanes_back=3, lane_width=3.75, median=1.0,
                shoulder=1.75, speed_kmh=60, style=NANPU_STYLE, pier_spacing=30.0,
                no_piers=[[0.0, 720.0]],
                notes="Main span 423 m between the two H towers, 45.5 m at "
                      "mid-span, 42.5 m at both deck ends.")


def nanpu_pudong_loop():
    """Pudong descending loop: R 104 -> 122, 540 deg, Y 42.5 -> 0, then S Rd."""
    loop = _spiral_points(PD_LOOP_C, PD_LOOP_A0, PD_LOOP_A1, PD_LOOP_R + 4.0,
                           PD_LOOP_R + 4.0 + PD_LOOP_GROWTH, 58, out_at=0.0)
    # the landing: the direction of Pudong South Rd at its end, over its
    # last 10 m.  The loop runs against the road's points, so it joins the
    # northbound lanes.
    parent = city_roads_east.pudong_south_rd()
    parent.build()
    a, b = parent.points[-6], parent.points[-1]
    h_line = math.degrees(math.atan2(b[0] - a[0], -(b[2] - a[2]))) % 360.0
    h_end = (h_line + 180.0) % 360.0
    h_start = (-PD_LOOP_A1) % 360.0
    # the exit: a right-hand arc off the loop and a straight that merges
    # into the road along its own direction
    rn0, rn1 = right_normal(h_start), right_normal(h_end)
    u = dir_of(h_end)
    det = (rn0[0] - rn1[0]) * u[1] - (rn0[1] - rn1[1]) * u[0]
    dx = PD_LANDING[0] - loop[-1][0]
    dz = PD_LANDING[1] - loop[-1][1]
    radius = (dx * u[1] - dz * u[0]) / det
    straight = ((rn0[0] - rn1[0]) * dz - (rn0[1] - rn1[1]) * dx) / det
    if radius <= 0.0 or straight < 0.0:
        raise ValueError("the Pudong loop does not reach Pudong South Rd")
    centre = (loop[-1][0] + radius * rn0[0], loop[-1][1] + radius * rn0[1])
    exit_pts = [list(p) for p in arc_points(centre, radius, h_start, h_end, 12)]
    last = exit_pts[-1]
    m = max(1, int(straight / 8.0))
    exit_pts += [[last[0] + (PD_LANDING[0] - last[0]) * i / m,
                  last[1] + (PD_LANDING[1] - last[1]) * i / m]
                 for i in range(1, m + 1)]
    plan = loop + exit_pts[1:]
    return Road("nanpu_pudong_loop", "南浦大桥浦东下行环道",
                "Nanpu Pudong Descending Loop", "ramp", plan,
                [("start", 42.5, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=2, lanes_back=0, lane_width=3.75, median=0.0,
                shoulder=1.0, speed_kmh=40,
                style={"parapet": "planter", "lamps": "barrier",
                       "soffit_led": "#3D7BFF", "trees": "none"},
                max_grade=0.048,
                notes="R 104 -> 122 m over 540 deg counter-clockwise (the "
                      "42.5 m descent needs 3.9 % with the 0.5 %/10 m kink "
                      "rule); the exit curves right and runs straight into "
                      "Pudong South Rd along the road's own direction.")


# ---------------------------------------------------------------- the Bund

def bund_road():
    """Zhongshan E-1 Rd (the Bund): 3+3 lanes, 6 m sidewalks, heritage lamps."""
    plan = [(0.0, 0.0), (-111.3, -245.7), (-145.3, -524.4), (-135.2, -628.1),
            (-128.3, -707.2), (-153.0, -839.8), (-147.6, -914.4)]
    return Road("bund_zhongshan_e1", "中山东一路", "Zhongshan E-1 Rd (the Bund)",
                "surface", plan, [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=3, lanes_back=3, lane_width=3.35, median=0.0,
                shoulder=0.5, sidewalk=6.0, speed_kmh=50,
                style=surface_style("heritage"),
                notes="3+3 lanes of 3.35 m, 6 m sidewalks (dossier 5.2).")


def bund_north():
    """North of Waibaidu Bridge, towards Broadway Mansions."""
    plan = [(-132.4, -1017.6), (-125.0, -1110.0), (-118.0, -1200.0)]
    return Road("bund_north", "中山东一路北段", "Zhongshan E-1 Rd North", "surface",
                plan, [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=3, lanes_back=3, lane_width=3.35, median=0.0,
                shoulder=0.5, sidewalk=4.0, speed_kmh=50,
                style=surface_style("heritage"))


def waibaidu_bridge():
    """Waibaidu (Garden) Bridge: real 104.4 m steel through-truss."""
    plan = [(-147.6, -914.4), (-140.0, -966.0), (-132.4, -1017.6)]
    return Road("waibaidu_bridge", "外白渡桥", "Waibaidu Bridge", "bridge", plan,
                [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=2, lanes_back=1, lane_width=3.73, median=0.0,
                shoulder=0.5, sidewalk=3.0, speed_kmh=40,
                style=surface_style("heritage"),
                notes="104.4 m truss; the +2.1 m camber of the dossier is not "
                      "buildable inside the 5 % grade limit and the 0.5 %/10 m "
                      "kink rule, so the deck runs flat.")


def zhongshan_e2_s():
    """Zhongshan E-2 / S Rd (riverside surface road) down to the spiral."""
    plan = [(0.0, 0.0), (60.0, 56.0), (106.0, 99.0), (284.0, 298.0),
            (560.0, 545.0),
            (650.0, 634.0), (903.0, 804.0), (1204.0, 1196.0), (1193.0, 1281.0),
            (1142.0, 1335.0), (948.0, 1434.0), (802.0, 1490.0)]
    return Road("zhongshan_e2_s", "中山东二路", "Zhongshan E-2 / S Rd", "surface",
                plan, [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=3, lanes_back=3, lane_width=3.75, median=1.0,
                shoulder=0.5, sidewalk=3.0, speed_kmh=60,
                style=surface_style("magnolia"),
                notes="Passes under the spiral loops at grade (dossier 3.3).")
