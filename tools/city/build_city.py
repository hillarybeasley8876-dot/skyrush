#!/usr/bin/env python3
"""build_city — writes data/city/city.json (the playable map of SKYRUSH).

Deterministic: re-running it reproduces the same file.  Never hand-edit the
JSON; change the generator in tools/city/ and run

    python3 tools/city/build_city.py
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

import city_blocks        # noqa: E402
import city_grid          # noqa: E402
import city_junctions     # noqa: E402
import city_landmarks     # noqa: E402
import city_marks         # noqa: E402
import city_marks_routes  # noqa: E402
import city_ramps         # noqa: E402
import city_roads         # noqa: E402
import city_roads_east    # noqa: E402
import citylib            # noqa: E402
import dragon             # noqa: E402
import dragon_ramps       # noqa: E402

OUT = os.path.join(ROOT, "data", "city", "city.json")
WINDOW = {"x_min": -2200, "x_max": 1800, "z_min": -1200, "z_max": 1800}

# end to end links: (child id, child key, parent id, parent key, target)
CONNECTIONS = [
    ("g50_west", "attach_end", "yanan_elevated", "attach_start",
     (-1990.0, 728.0)),
    ("yanan_elevated", "attach_end", "yanan_rd_surface", None,
     (-515.66, 219.57)),
    ("inner_ring", "attach_start", "ns_elevated", "attach_end",
     (-1122.0, 1510.0)),
    ("nanpu_spiral_upper", "attach_start", "inner_ring", "attach_end",
     (1021.3, 1277.0)),
    ("nanpu_spiral_lower", "attach_end", "nanpu_spiral_upper", None,
     (1073.0, 1268.0)),
    ("nanpu_spiral_upper", "attach_end", "nanpu_bridge", "attach_start",
     (982.0, 1272.0)),
    ("nanpu_bridge", "attach_end", "nanpu_pudong_loop", "attach_start",
     (1654.0, 1590.0)),
    ("nanpu_pudong_loop", "attach_end", "pudong_south_rd", None,
     (1690.0, 1280.0)),
    ("yanan_tunnel", "attach_start", "st_fujian_portal", None,
     (-459.8, 184.4)),
    ("yanan_tunnel", "attach_end", "yincheng_rd", None, (759.0, -462.4)),
    ("century_ave", "attach_start", "yanan_tunnel", "attach_end",
     (759.0, -462.4)),
    ("zhongshan_e2_s", "attach_end", "lujiabang_rd", "attach_start",
     (802.0, 1490.0)),
    ("bund_zhongshan_e1", "attach_end", "waibaidu_bridge", "attach_start",
     (-147.6, -914.4)),
    ("waibaidu_bridge", "attach_end", "bund_north", "attach_start",
     (-132.4, -1017.6)),
    ("bund_zhongshan_e1", "attach_start", "zhongshan_e2_s", "attach_start",
     (0.0, 0.0)),
    ("st_henan_portal", "attach_start", "yanan_tunnel", "attach_start",
     (-459.8, 184.4)),
    ("st_henan_portal", "attach_end", "st_henan_rd", None, (-408.0, 195.7)),
]


def build_main_roads():
    """Every named road of the map, in build order."""
    roads = []
    roads.append(city_roads.g50_west())
    roads.append(city_roads.yanan_elevated())
    roads.append(city_roads.yanan_rd_surface())
    roads.append(city_roads.yanan_frontage_south())
    roads.append(city_roads.yanan_frontage_north())
    roads.append(city_roads.ns_elevated())
    roads.append(city_roads.inner_ring())
    roads.append(city_roads.nanpu_spiral_lower())
    roads.append(city_roads.nanpu_spiral_upper())
    roads.append(city_roads.nanpu_bridge())
    roads.append(city_roads.nanpu_pudong_loop())
    roads.append(city_roads.bund_road())
    roads.append(city_roads.bund_north())
    roads.append(city_roads.waibaidu_bridge())
    roads.append(city_roads.zhongshan_e2_s())
    roads.append(city_roads_east.century_ave())
    roads.append(city_roads_east.lujiazui_ring_rd())
    roads.append(city_roads_east.pudong_south_rd())
    roads.append(city_roads_east.yanan_tunnel())
    roads.append(city_roads_east.lujiabang_rd())
    roads.append(city_roads_east.lujiazui_w_rd())
    roads.append(city_roads_east.dongchang_rd())
    roads.append(city_roads_east.yincheng_rd())
    roads.append(city_roads_east.fujian_rd_puxi())
    roads.append(city_roads_east.henan_portal_link())
    for road in roads:
        road.build()
    return roads


def link_roads(roads):
    """Declare the end to end links between the named roads."""
    by_id = {r.id: r for r in roads}
    for child_id, child_key, parent_id, parent_key, target in CONNECTIONS:
        child = by_id.get(child_id)
        parent = by_id.get(parent_id)
        if child is None or parent is None:
            continue
        s = _closest_s(parent, target)
        att = {"road": parent_id, "at": round(s, 2), "side": _side(parent, s, target)}
        if child_key:
            setattr(child, child_key, att)
        if parent_key and getattr(parent, parent_key, None) is None:
            cs = _closest_s(child, target)
            setattr(parent, parent_key,
                    {"road": child_id, "at": round(cs, 2), "side": "right"})


def _closest_s(road, point):
    best, best_s = 1e18, 0.0
    for p, s in zip(road.points, road.dist):
        d = math.hypot(p[0] - point[0], p[2] - point[1])
        if d < best:
            best, best_s = d, s
    return best_s


def _side(road, s, target):
    p, t = road.point_at(s)
    cross = t[0] * (target[1] - p[2]) - t[2] * (target[0] - p[0])
    return "left" if cross > 0 else "right"


def main(out=None):
    out = out or OUT
    roads = build_main_roads()
    streets, dead_ends = city_grid.build_streets(roads)
    for st in streets:
        st.build()
    by_id = {r.id: r for r in roads + streets}
    frame = dragon.Frame(by_id["yanan_elevated"], by_id["ns_elevated"])
    dragon_roads = dragon_ramps.build(frame)
    ramps = city_ramps.surface_ramps(by_id["yanan_elevated"], streets,
                                    dragon_ramps.budget(dragon_roads),
                                    roads + streets)
    ramps += dragon_roads
    for ramp in ramps:
        ramp.build()
    link_roads(roads + streets + ramps)
    junctions = city_junctions.build_junctions(roads + streets + ramps)
    all_roads = roads + streets + ramps
    by_id = {r.id: r for r in all_roads}
    pois = city_marks.build_pois(by_id) + city_marks.build_landmark_pois()
    specials = city_blocks.special_blocks(all_roads, pois)
    for poly in [s["polygon"] for s in specials]:
        pass
    blocks = city_blocks.build_blocks(
        all_roads, WINDOW, [city_grid.HUANGPU, city_grid.CREEK], pois,
        [s["polygon"] for s in specials])
    blocks += city_landmarks.landmark_blocks(all_roads)
    blocks += city_landmarks.park_blocks(all_roads)
    blocks += specials
    blocks = city_blocks.clear_of_roads(blocks, all_roads)
    sky_lanes = city_marks.build_sky_lanes(by_id, blocks)
    routes = city_marks_routes.build_routes(by_id, junctions)
    spawns = city_marks_routes.build_spawns(by_id, pois)
    city = assemble(roads + streets + ramps, junctions, blocks, pois,
                    sky_lanes, routes, spawns, dead_ends)
    citylib.save_json(out, city)
    report(city, all_roads, out)
    return 0


def assemble(roads, junctions, blocks, pois, sky_lanes, routes, spawns,
             dead_ends):
    """Build the city.json document."""
    city = {
        "version": 1,
        "name": "申城 Neon Shanghai",
        "window": WINDOW,
        "roads": [r.to_dict() for r in roads],
        "junctions": junctions,
        "water": [
            {"id": "huangpu",
             "polygon": [[round(p[0], 1), round(p[1], 1)]
                         for p in city_grid.HUANGPU],
             "y": -3.0, "bank": "floodwall"},
            {"id": "suzhou_creek",
             "centerline": [[round(p[0], 1), round(p[1], 1)] for p in
                            city_grid._LAYOUT_RIVER["suzhou_creek_centerline"]],
             "width": 70, "y": -3.0, "bank": "wall"},
        ],
        "blocks": blocks,
        "pois": pois,
        "sky_lanes": sky_lanes,
        "routes": routes,
        "spawns": spawns,
        "notes": ("SKYRUSH city map, built by tools/city/build_city.py - do not "
                  "hand-edit. The L3 and L4 decks of the dragon interchange "
                  "cross the pillar axis at Y=16.5 and Y=23.9, so the pillar "
                  "asset must stop below Y=14.9 m or carry the decks on portal "
                  "frames. Dead ends at the window edge: %s."
                  % ", ".join("%s(%.0f,%.0f)" % d for d in dead_ends)),
    }
    return city


def report(city, roads, out=None):
    """Print the map statistics."""
    total = 0.0
    lanes_total = 0.0
    for road in roads:
        total += road.length()
        lanes_total += road.length() * max(1, road.lanes_fwd + road.lanes_back)
    size = os.path.getsize(out or OUT)
    print("roads      : %d" % len(roads))
    print("blocks     : %d" % len(city["blocks"]))
    print("junctions  : %d" % len(city["junctions"]))
    print("pois       : %d" % len(city["pois"]))
    print("sky lanes  : %d" % len(city["sky_lanes"]))
    print("routes     : %d" % len(city["routes"]))
    print("drivable   : %.1f km of road (%.1f km of lanes)"
          % (total / 1000.0, lanes_total / 1000.0))
    print("json size  : %.2f MB" % (size / 1048576.0))


if __name__ == "__main__":
    target = None
    if "--out" in sys.argv:
        target = os.path.abspath(sys.argv[sys.argv.index("--out") + 1])
        os.makedirs(os.path.dirname(target), exist_ok=True)
    sys.exit(main(target))
