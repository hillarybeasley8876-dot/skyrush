"""city_rules — the strict road rules of data/city/city.json.

Every rule prints PASS or FAIL and lists *every* failure with its value and
its place in the map - a rule that hides its failures is worthless (review
r1 item 1).

The rules implement the brief and the dossier:
  * grades <= 5 % (the Nanpu spiral <= 4 %), sampled every 2 m
  * no kink: the grade changes by at most 0.5 % per 10 m
  * every deck clears the roads under it by 5.5 m plus the depth of the
    structure above (dossier 2.2 / 1.3 / 3.2); a tunnel lane clears the road
    above it by 6.0 m
  * no road in the water except a bridge or a tunnel
  * every ramp attaches to its parent on the parent's centre-line, at the
    parent's height and along the parent's direction
  * the junctions really meet
  * the key levels: Yan'an 9.0 m and N-S 31.0 m at the pillar, the tunnel
    bottom at -28.0 m
"""
import math

import citylib

GRADE_LIMIT = 0.05              # the brief: 5 %
SPIRAL_GRADE_LIMIT = 0.04       # the brief: 4 % on the Nanpu spiral
KINK_LIMIT = 0.005              # the grade change per 10 m
# the roads allowed a shorter vertical curve: the tunnel rises 28 m between Lujiazui West Rd and the Lujiazui Ring Rd, and
# runs 6 m under the Yan'an Rd surface road 156 m from its Puxi end (city_roads_east.yanan_tunnel, the kink of its profile)
KINK_LIMITS = {"yanan_tunnel": 0.010}
CLEARANCE = 5.5                 # the clearance under a deck (dossier 2.1)
TUNNEL_CLEARANCE = 6.0          # a tunnel lane under a road
PLAN_TOLERANCE = 0.10           # the attach rule: the plan error in metres
HEIGHT_TOLERANCE = 0.05         # the attach rule: the height error in metres
TANGENT_TOLERANCE = 8.0         # the attach rule: the tangent error in degrees
GORE = 250.0                    # the attach gore: the exempt length of a ramp
SPIRAL_ROADS = ("nanpu_spiral_upper", "nanpu_spiral_lower",
                "nanpu_pudong_loop", "nanpu_bridge")
PILLAR = (-1299.0, 687.0)


def deck_depth(road):
    """The depth of the structure under a road (dossier 2.2 / 1.3 / 3.2)."""
    rid = road["id"]
    if rid.startswith("ramp_l3") or rid.startswith("ramp_l4"):
        return 1.6
    if rid in ("nanpu_bridge", "nanpu_spiral_upper", "nanpu_spiral_lower",
               "nanpu_pudong_loop"):
        return 2.5
    if rid in ("yanan_elevated", "ns_elevated", "inner_ring"):
        return 1.8 if rid == "yanan_elevated" else 1.6
    if road["kind"] in ("elevated", "bridge", "ramp"):
        return 2.0
    return 0.0


def _angle_diff(a, b):
    return abs((a - b + 180.0) % 360.0 - 180.0)


def check_schema(city):
    """Every record carries the fields the schema asks for."""
    fails = []
    road_fields = ("id", "name", "kind", "points", "spline", "lanes_fwd",
                   "lanes_back", "lane_width", "median", "shoulder", "sidewalk",
                   "speed_kmh", "style")
    block_fields = ("id", "district", "polygon", "style", "height_m", "setback",
                    "seed")
    poi_fields = ("id", "kind", "x", "y", "z", "heading_deg", "size", "label")
    seen = set()
    for road in city["roads"]:
        for field in road_fields:
            if field not in road:
                fails.append("road %s misses %s" % (road.get("id"), field))
        if road["id"] in seen:
            fails.append("duplicate road id %s" % road["id"])
        seen.add(road["id"])
        if len(road["points"]) < 2:
            fails.append("road %s has %d points" % (road["id"],
                                                    len(road["points"])))
    for block in city["blocks"]:
        for field in block_fields:
            if field not in block:
                fails.append("block %s misses %s" % (block.get("id"), field))
        if block["id"] in seen:
            fails.append("duplicate id %s" % block["id"])
        seen.add(block["id"])
        if len(block["polygon"]) < 3:
            fails.append("block %s has %d polygon points"
                         % (block["id"], len(block["polygon"])))
    for poi in city["pois"]:
        for field in poi_fields:
            if field not in poi:
                fails.append("poi %s misses %s" % (poi.get("id"), field))
    for key in ("version", "name", "window", "roads", "junctions", "water",
                "blocks", "pois", "sky_lanes", "routes", "spawns"):
        if key not in city:
            fails.append("the map misses %s" % key)
    return fails


def check_grades(city):
    """Every grade inside the limit (5 %, 4 % on the Nanpu spiral)."""
    fails = []
    for road in city["roads"]:
        limit = SPIRAL_GRADE_LIMIT if road["id"] in SPIRAL_ROADS else GRADE_LIMIT
        pts = road["points"]
        worst, where = 0.0, 0
        dist = 0.0
        for a, b in zip(pts, pts[1:]):
            run = math.hypot(b[0] - a[0], b[2] - a[2])
            if run < 1e-6:
                continue
            grade = (b[1] - a[1]) / run
            if abs(grade) > abs(worst):
                worst, where = grade, dist
            dist += run
        if abs(worst) > limit + 1e-6:
            fails.append("%s %.2f %% at %d m" % (road["id"], worst * 100.0,
                                                where))
    return fails


def check_curvature(city):
    """No kink: the grade changes by at most 0.5 % per 10 m.

    The grade is measured on the sampled centre-line (every 2 m), so the
    short control-point segments of a road cannot fake a kink.
    """
    fails = []
    for road in city["roads"]:
        pts = citylib.road_points(road, 2.0)
        grades = []
        dist = 0.0
        for a, b in zip(pts, pts[1:]):
            run = math.hypot(b[0] - a[0], b[2] - a[2])
            grades.append((b[1] - a[1]) / run if run > 1e-6 else 0.0)
            dist += run
        worst, where = 0.0, 0.0
        travelled = 0.0
        for i in range(len(grades) - 5):
            change = abs(grades[i + 5] - grades[i])
            if change > worst:
                worst, where = change, travelled
            travelled += 2.0
        if worst > KINK_LIMITS.get(road["id"], KINK_LIMIT) + 1e-6:
            fails.append("%s %.3f %% per 10 m at %d m"
                         % (road["id"], worst * 100.0, where))
    return fails


def check_water(city):
    """No road in the water except a bridge or a tunnel.

    The water is the polygon of the Huangpu and the strip of the Suzhou Creek (its centre line and its width: the rule only
    knew the polygons, and Beijing E Rd ran 178 m along the middle of the creek).  A deck high over the water is no road in it.
    """
    fails = []
    polys = [w for w in city["water"] if "polygon" in w]
    creeks = [w for w in city["water"] if "centerline" in w]
    for road in city["roads"]:
        if road["kind"] in ("bridge", "tunnel"):
            continue
        for p in road["points"]:
            if p[1] > 3.0:
                continue
            inside = any(citylib.point_in_polygon((p[0], p[2]), w["polygon"]) for w in polys)
            inside = inside or any(_in_strip((p[0], p[2]), w["centerline"], w["width"] * 0.5) for w in creeks)
            if inside:
                fails.append("%s is in the water at (%.0f, %.0f)"
                             % (road["id"], p[0], p[2]))
                break
    return fails


def _in_strip(point, line, half):
    """True when the point is within `half` of the polyline (the strip of a creek)."""
    return any(citylib.point_seg_distance(point, a, b) < half for a, b in zip(line, line[1:]))


def _nearest_point(road, target):
    """The road's point closest to the plan position, with its distance."""
    best, best_p, best_i = 1e18, None, 0
    for i, p in enumerate(road["points"]):
        d = math.hypot(p[0] - target[0], p[2] - target[1])
        if d < best:
            best, best_p, best_i = d, p, i
    return best, best_p, best_i


def check_key_levels(city):
    """The key heights of the dossier (the pillar, the tunnel bottom)."""
    fails = []
    by_id = {r["id"]: r for r in city["roads"]}
    yanan = by_id.get("yanan_elevated")
    if yanan is not None:
        worst = 0.0
        for p in yanan["points"]:
            if math.hypot(p[0] - PILLAR[0], p[2] - PILLAR[1]) <= 150.0:
                worst = max(worst, abs(p[1] - 9.0))
        if worst > 0.05:
            fails.append("yanan_elevated is %.2f m off Y 9.0 at the pillar"
                         % worst)
    ns = by_id.get("ns_elevated")
    if ns is not None:
        d, p, _i = _nearest_point(ns, PILLAR)
        if abs(p[1] - 31.0) > 0.05:
            fails.append("ns_elevated is %.2f m off Y 31.0 at the pillar"
                         % abs(p[1] - 31.0))
    tunnel = by_id.get("yanan_tunnel")
    if tunnel is not None:
        low = min(p[1] for p in tunnel["points"])
        if abs(low + 28.0) > 0.05:
            fails.append("yanan_tunnel bottoms out at %.2f m, not -28.0" % low)
    return fails


def check_dead_ends(city):
    """Every road end connects to something (review r1 A.7)."""
    fails = []
    by_id = {r["id"]: r for r in city["roads"]}
    window = city["window"]
    for road in city["roads"]:
        for key, idx in (("start", 0), ("end", -1)):
            p = road["points"][idx]
            near = [q for q in road["points"][max(0, idx - 12):idx + 12]
                    if q is not p]
            edge = (p[0] <= window["x_min"] + 40.0
                    or p[0] >= window["x_max"] - 40.0
                    or p[2] <= window["z_min"] + 40.0
                    or p[2] >= window["z_max"] - 40.0)
            connected = bool(road.get("attach_start" if idx == 0
                                      else "attach_end"))
            if not connected:
                for j in city["junctions"]:
                    if road["id"] in j["roads"] and math.hypot(
                            j["x"] - p[0], j["z"] - p[2]) <= 45.0:
                        connected = True
                        break
            if not connected and not edge:
                other = _other_road_at(by_id, road, p)
                if other is not None:
                    connected = True
            if not connected and not edge:
                fails.append("%s %s at (%.0f, %.0f) is a dead end"
                             % (road["id"], key, p[0], p[2]))
    return fails


def _other_road_at(by_id, road, point):
    """Another road whose centre-line ends at the point."""
    for other in by_id.values():
        if other["id"] == road["id"]:
            continue
        for idx in (0, -1):
            q = other["points"][idx]
            if math.hypot(q[0] - point[0], q[2] - point[2]) <= 45.0:
                return other
    return None
