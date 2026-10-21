"""Step 2: compose the GAME map layout -> build/map_layout_v1.json

Real polylines below were read off OSM (2026-10-19 extract, see dl/osm_*) and simplified
by hand; they are passed through maplib.T. Items marked design=True are game-only.

usage: python3 -E -s build_map.py <river.json> <out.json>
"""
import json
import math
import sys

import maplib as M

river_path, out_path = sys.argv[1], sys.argv[2]
river = json.load(open(river_path, encoding="utf-8"))

WINDOW = {"x_min": -2200, "x_max": 1800, "z_min": -1200, "z_max": 1800}

REAL_POLYLINES = {
    # centrelines of dual carriageways (average of both directions), real frame
    "yanan_elevated": [(-3176, 1036), (-2715, 1030), (-2447, 1040), (-2370, 1043), (-2212, 1002),
                       (-2013, 909), (-1660, 742), (-912, 277), (-681, 215), (-453, 236), (-338, 170)],
    "ns_elevated": [(-2835, -1199), (-2641, -557), (-2448, -137), (-2384, 238), (-2354, 646),
                    (-2321, 769), (-2266, 863), (-2040, 1118), (-1983, 1197), (-1934, 1334),
                    (-1904, 1453), (-1936, 1648), (-2036, 2093), (-1970, 2366), (-1825, 2600)],
    "yanan_east_rd_surface": [(-338, 170), (-192, 139), (-104, 96), (0, 0)],
    "yanan_tunnel": [(-541, 217), (-416, 246), (-192, 139), (-44, 99), (2, 31), (483, -391),
                     (726, -535), (893, -544)],
    "bund_zhongshan_e1": [(5, -12), (-131, -289), (-171, -617), (-159, -739), (-151, -832),
                          (-180, -988), (-173.6, -1075.8)],
    "waibaidu_bridge": [(-173.6, -1075.8), (-155.8, -1197.2)],  # real 104.4 m after T (game ends)
    "zhongshan_e2_s": [(0, 0), (125, 116), (334, 350), (659, 670), (765, 848), (1062, 1189),
                       (1417, 1972), (1404, 2142), (1343, 2250), (1115, 2447), (943, 2559)],
    "century_ave": [(880, -575), (925, -559), (1174, -448), (1294, -364), (1471, -293),
                    (1633, -230), (1731, -213), (2030, -92), (2400, 60)],
    "lujiazui_ring_rd": [(856, -587), (945, -742), (1259, -987), (1407, -803), (1486, -680),
                         (1574, -497), (1648, -271), (1675, -34), (1616, 3), (925, -122),
                         (859, -227), (844, -326), (832, -485), (856, -587)],
}

LANDMARKS_REAL = {
    "dragon_pillar": (-2178, 954),
    "oriental_pearl_tower": (750, -747),
    "pearl_ring_skybridge_center": (880, -575),
    "jin_mao_tower": (1333, -235),
    "swfc": (1485, -160),
    "shanghai_tower": (1321, -50),
    "customs_house_clock_tower": (-187, -386),
    "hsbc_building_dome": (-175, -315),
    "peace_hotel_north_pyramid": (-215, -660),
    "bank_of_china_bund": (-204, -706),
    "waibaidu_bridge_mid": (-164.7, -1136.5),
    "broadway_mansions": (-184, -1237),
    "yanan_tunnel_puxi_portal": (-541, 217),
    "yanan_tunnel_pudong_portal": (893, -544),
}

# ---- game-only design (already in GAME frame) ----
U = (0.901, 0.434)                     # Nanpu bridge axis (perpendicular to the river here)
MID = (1330.0, 1430.0)                 # main-span midpoint, on the river centreline
def along(p, d): return [round(p[0] + U[0] * d, 1), round(p[1] + U[1] * d, 1)]
N_NORTH = (U[1], -U[0])
P0 = along(MID, -211.5 - 199.0)        # where the straight approach leaves the spiral
R_UPPER = 141.0                         # upper-loop centreline radius; the straight approach leaves it tangentially at P0
SPIRAL_C = [round(P0[0] + R_UPPER * N_NORTH[0], 1), round(P0[1] + R_UPPER * N_NORTH[1], 1)]
SPIRAL_JOIN_S = [SPIRAL_C[0], round(SPIRAL_C[1] + R_UPPER, 1)]   # inner ring joins here heading east
DESIGN = {
    "nanpu_bridge": {"axis_unit": list(U), "main_span_mid": list(MID),
                     "puxi_tower": along(MID, -211.5), "pudong_tower": along(MID, 211.5),
                     "puxi_deck_end": along(MID, -211.5 - 199.0), "pudong_deck_end": along(MID, 211.5 + 150.0)},
    "nanpu_pudong_loop": {"center": [round(along(MID, 361.5)[0] + 100 * N_NORTH[0], 1), round(along(MID, 361.5)[1] + 100 * N_NORTH[1], 1)],
                          "radius": 100.0, "sweep_deg": 540, "y_from": 42.5, "y_to": 0.0,
                          "circulation": "counter-clockwise seen from above (north up)",
                          "exit_point": [round(along(MID, 361.5)[0] + 100 * N_NORTH[0] + 100 * N_NORTH[0], 1),
                                         round(along(MID, 361.5)[1] + 100 * N_NORTH[1] + 100 * N_NORTH[1], 1)],
                          "exit_heading": [-U[0], -U[1]], "then": "right-hand curve R 80 m to heading north, join pudong_south_rd at (1690,1280)"},
    "nanpu_spiral_center": SPIRAL_C,
    "nanpu_spiral": {"upper_loop_radius": R_UPPER, "upper_loop_join_south_point": SPIRAL_JOIN_S,
                     "upper_loop_exit_tangent_point": P0, "upper_loop_sweep_deg": 334,
                     "lower_loop_radius": 95.0, "circulation": "counter-clockwise seen from above (north up)"},
    "inner_ring_elevated": [[-1122.5, 1510], [-1000, 1640], [-600, 1680], [200, 1660], [600, 1560],
                            [780, 1380], [900, 1290], SPIRAL_JOIN_S],
    "pudong_south_rd": [[1540, -78], [1600, 100], [1650, 500], [1680, 900], [1690, 1280]],
    "g50_expressway_at_grade": [[-2200, 728], [-1990, 728]],
    "yanan_elevated_west_ramp": {"from": [-1990, 728], "to": [-1740, 728], "y_from": 0, "y_to": 10},
    "ns_elevated_north_ext": [[-1627.5, -1019.1], [-1660, -1200]],
    "ns_elevated_south_ext": [[-1122.5, 1510], [-1000, 1640]],
    "toll_plaza": {"center": [-2070, 728], "length_x": 160, "lanes_each_way": 10, "design": True},
    "gas_station": {"rect_x": [-1940, -1860], "rect_z": [760, 830], "entry_from": "frontage road z=752"},
    "charging_station": {"rect_x": [1700, 1780], "rect_z": [380, 460], "entry_from": "pudong_south_rd"},
    "bund_tunnel_optional": [[-180, 120], [-60, 20], [-60, -300], [-95, -700], [-110, -1100], [-120, -1200]],
    "puxi_street_grid": {
        "ns_streets_x": {"sichuan_rd": -255, "henan_rd": -408, "fujian_rd": -535, "xizang_rd": -720},
        "ns_z_range": [-950, 150],
        "ew_streets_z": {"guangdong_rd": -110, "fuzhou_rd": -230, "jiujiang_rd": -430, "nanjing_e_rd": -540,
                         "beijing_e_rd": -703},
        "ew_x_range": ["bund_road", -900], "lanes": "2+2", "width_m": 16},
    "y_profiles": {
        "yanan_elevated": "0 at x=-1990 -> 10 at x=-1740; 9 within 150 m of dragon pillar; 10 to (-500,190); 0 at (-287,144)",
        "ns_elevated": "12 north of (-1402,202) -> 31 at pillar -> 12 at (-1228,1256) -> 10 at (-1122,1510)",
        "inner_ring_elevated": "10",
        "nanpu": "spiral upper loop 10 -> 42.5; bridge 42.5 (W deck end) / 44.0 (towers) / 45.5 (mid-span)",
        "yanan_tunnel": "0 at portals, -28 under river, grades <= 4.5 %",
        "water_surface": -3.0, "bund_promenade": 2.5, "pearl_ring_deck": 6.5},
    # Bund front row: [No., name, z_centre, front_x, frontage_m, depth_m, height_m, roof cue]  (see dossier 5.3)
    "bund_buildings": [
        [1, "Asia Bldg", -32, -22.5, 38, 40, 31, "attic+pediment"],
        [2, "Shanghai Club / Waldorf", -59, -35.7, 27, 40, 30, "two corner cupolas"],
        [3, "Union Bldg", -91, -51.4, 38, 38, 30, "flat"],
        [5, "Nisshin Bldg", -120, -65.7, 22, 30, 28, "flat"],
        [6, "Commercial Bank of China", -140, -75.5, 21, 25, 20, "gothic gables, red brick"],
        [7, "Great Northern Telegraph", -181, -95.6, 19, 25, 22, "small corner dome"],
        [9, "China Merchants", -207, -108.3, 17, 22, 20, "flat"],
        [12, "HSBC Bldg", -268, -130.0, 76, 70, 50, "dome on drum (cornice 32)"],
        [13, "Customs House", -328, -137.3, 42, 60, 79.2, "clock tower (main 36.2)"],
        [14, "Bank of Communications", -366, -142.0, 34, 40, 36, "art deco"],
        [15, "Russo-Chinese Bank", -418, -148.3, 34, 35, 20, "flat"],
        [16, "Bank of Taiwan", -447, -151.9, 20, 30, 22, "flat"],
        [17, "North China Daily News", -465, -154.1, 26, 35, 46, "two rooftop towers (roof 40)"],
        [18, "Bund 18", -488, -156.9, 26, 40, 26, "flat"],
        [19, "Palace Hotel", -518, -160.5, 30, 75, 30, "corner turret"],
        [20, "Sassoon House / Peace Hotel N", -569, -157.0, 42, 90, 77, "19 m green copper pyramid"],
        [23, "Bank of China", -600, -153.9, 24, 60, 77, "chinese hipped pyramid roof"],
        [24, "Yokohama Specie Bank", -628, -151.2, 34, 45, 30, "flat"],
        [26, "Yangtze Insurance", -655, -148.9, 18, 25, 30, "flat"],
        [27, "Jardine Matheson", -683, -146.4, 34, 45, 32, "flat"],
        [28, "Glen Line Bldg", -720, -146.7, 24, 30, 27.5, "flat"],
        [29, "Banque de l'Indochine", -744, -151.2, 20, 25, 18, "baroque attic"],
        [33, "former British Consulate", -808, -163.1, 30, 20, 12, "colonial, set back 40 m"],
        [32, "The Peninsula", -837, -168.5, 40, 50, 60, "modern art deco"],
    ],
    "waibaidu_bridge": {"center": [-140, -966], "dir": [0.145, -0.989], "length_m": 104.4,
                        "ends": [[-147.6, -914.4], [-132.4, -1017.6]]},
    "districts": {  # [x_min, x_max, z_min, z_max] in GAME frame; filler style per district (see dossier 10.5)
        "D1_bund_heritage_blocks": [-420, -170, -1000, 0],
        "D2_nanjing_rd_neon": [-900, -170, -560, -520],
        "D3_huangpu_midrise": [-1150, -420, -900, 100],
        "D4_shikumen_planetrees": [-1200, -320, 250, 1150],
        "D5_jingan_towers": [-2200, -1650, -1200, 400],
        "D6_south_bund_oldcity": [-300, 850, 150, 1350],
        "D7_lujiazui_cbd": [500, 1800, -1150, 120],
        "D8_pudong_residential": [1500, 1800, 120, 1800],
        "D9_west_edge_industrial": [-2200, -1650, 450, 1800],
    },
}

def g(poly):
    return [list(M.T(p)) for p in poly]

layout = {
    "frame": "GAME metres. X east, Z south (Godot: north = -Z), Y up. Origin (0,0) = junction of "
             "Yan'an East Rd and Zhongshan East-1 Rd (the Bund). Ground level Y = 0.",
    "compression": {"x": "x<-600: -510+0.5*(x+600); -600..1500: 0.85*x; >1500: 1275+0.5*(x-1500)",
                    "z": "z<=600: 0.85*z; >600: 510+0.5*(z-600)",
                    "note": "applied to anchors/polylines only; buildings/bridges keep real size"},
    "window": WINDOW,
    "river": river,
    "roads": {k: g(v) for k, v in REAL_POLYLINES.items()},
    "landmarks": {k: list(M.T(v)) for k, v in LANDMARKS_REAL.items()},
    "design": DESIGN,
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(layout, f, ensure_ascii=False, indent=1)
for k, v in layout["roads"].items():
    print(k, v)
for k, v in layout["landmarks"].items():
    print(k, v)
for k, v in DESIGN.items():
    print(k, v)
