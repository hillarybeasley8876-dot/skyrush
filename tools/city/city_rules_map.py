"""city_rules_map — the map content rules of data/city/city.json.

The blocks, the spawns, the POIs and the land coverage.  Every rule lists
every failure (review r1 item 1) and measures what it claims to measure
(review r2 item 4): the block rules test the whole lot against the road
footprint, not only its vertices, and the coverage rule uses a raster of
the land instead of a sum of areas.
"""
import collections
import math

import citylib

ROAD_CLEARANCE = 1.0             # the blocks keep 1 m from a road edge
DECK_CLEARANCE = 2.0             # and 2 m from an elevated deck footprint
LANE_TOLERANCE = 0.5             # a spawn / checkpoint on a lane centre
HEADING_TOLERANCE = 10.0         # degrees
CHECKPOINT_MIN = 300.0           # the distance between two checkpoints
CHECKPOINT_MAX = 500.0
RUN_UP = 300.0                   # the straight run-up of a launch pad
RUN_UP_TURN = 3.0                # degrees of heading change over the run-up
PITCH_LIMIT = 20.0               # degrees over 50 m
SKY_CLEARANCE = 10.0             # the sky lanes clear the blocks by 10 m
RING_SPACING = 250.0             # the N2 rings along a sky lane
COVERAGE_STEP = 10.0             # the raster of the coverage rule
COVERAGE_MIN = 0.95              # the share of the land that has to be built
TUNNEL_FLOOR = -7.0              # below this a tunnel trough is a tunnel
LANDMARK_EXEMPT = ("landmark:dragon_pillar", "landmark:nanpu_tower_w",
                   "landmark:nanpu_tower_e")

from city_rules_lanes import (_angle_diff, lane_at, lane_centres,
                               nearest_lane)


# ---------------------------------------------------------------- geometry

def _inside(point, poly):
    """True if the point is inside the polygon (ray casting)."""
    x, y = point[0], point[1]
    inside = False
    for a, b in zip(poly, poly[1:] + poly[:1]):
        if (a[1] > y) != (b[1] > y):
            t = (y - a[1]) / (b[1] - a[1])
            if x < a[0] + t * (b[0] - a[0]):
                inside = not inside
    return inside


def _edge_distance(point, poly):
    """The distance from a point to the edge of the polygon."""
    best = 1e18
    for a, b in zip(poly, poly[1:] + poly[:1]):
        best = min(best, citylib.point_seg_distance(point, a, b))
    return best


def _block_grid(city, cell=50.0):
    """The blocks in a grid of `cell` metres, for the quick lookups."""
    grid = collections.defaultdict(list)
    for bi, block in enumerate(city["blocks"]):
        xs = [p[0] for p in block["polygon"]]
        zs = [p[1] for p in block["polygon"]]
        for i in range(int(min(xs) // cell) - 1, int(max(xs) // cell) + 2):
            for j in range(int(min(zs) // cell) - 1, int(max(zs) // cell) + 2):
                grid[(i, j)].append(bi)
    return grid


def _road_block_gaps(city, deck):
    """The lots that are too close to a road, with the worst gap each.

    A road sample inside the lot counts as a gap of zero, so a lot that
    swallows a street is caught as well as a lot that only touches it.
    """
    grid = _block_grid(city)
    hits = {}
    for road in city["roads"]:
        half = citylib.road_width(road) * 0.5
        for p in citylib.road_points(road, 2.0):
            y = p[1]
            if road["kind"] == "tunnel" and y < TUNNEL_FLOOR:
                continue
            is_deck = (road["kind"] in ("elevated", "ramp", "bridge")
                       and y >= 1.0)
            if is_deck != deck:
                continue
            need = half + (DECK_CLEARANCE if deck else ROAD_CLEARANCE)
            for bi in grid.get((int(p[0] // 50.0), int(p[2] // 50.0)), ()):
                block = city["blocks"][bi]
                poly = block["polygon"]
                dist = 0.0 if _inside((p[0], p[2]), poly) \
                    else _edge_distance((p[0], p[2]), poly)
                if dist >= need:
                    continue
                key = (block["id"], road["id"])
                if key not in hits or dist < hits[key][0]:
                    hits[key] = (dist, p[0], p[2], y, block.get("notes", ""),
                                 block.get("style", ""))
    return hits


def check_blocks(city):
    """The lots keep 1 m from the ground road edges and stay out of the water.
    """
    fails = []
    polys = [w for w in city["water"] if "polygon" in w]
    for block in city["blocks"]:
        for p in block["polygon"]:
            for w in polys:
                if citylib.point_in_polygon((p[0], p[1]), w["polygon"]):
                    fails.append("%s is in the water at (%.0f, %.0f)"
                                 % (block["id"], p[0], p[1]))
                    break
    for (bid, rid), (dist, x, z, _y, _notes, _style) in \
            sorted(_road_block_gaps(city, False).items(), key=lambda kv: kv[1][0]):
        fails.append("%s is %.1f m from the edge of %s at (%.0f, %.0f)"
                     % (bid, dist - 1.0, rid, x, z))
    return fails


def check_decks(city):
    """The lots keep 2 m from the elevated deck footprints (lead note 2)."""
    fails = []
    exempt = []
    for (bid, rid), (dist, x, z, _y, notes, _style) in \
            sorted(_road_block_gaps(city, True).items(), key=lambda kv: kv[1][0]):
        if notes in LANDMARK_EXEMPT:
            exempt.append("%s under %s (landmark)" % (bid, rid))
            continue
        fails.append("%s is %.1f m from the deck of %s at (%.0f, %.0f)"
                     % (bid, dist - 2.0, rid, x, z))
    return fails, exempt


def check_spawns(city):
    """Every spawn sits on a lane centre, at the lane height (lead C-INT1)."""
    fails = []
    by_id = {r["id"]: r for r in city["roads"]}
    spawns = city["spawns"]
    entries = [("player", spawns.get("player"))]
    entries += [("police %d" % i, p)
                for i, p in enumerate(spawns.get("police", []))]
    for name, spawn in entries:
        if not spawn:
            fails.append("the %s spawn is missing" % name)
            continue
        best = None
        for road in by_id.values():
            found = nearest_lane(road, (spawn[0], spawn[2]))
            if found and (best is None or found[0] < best[0]):
                best = found + (road["id"],)
        if best is None or best[0] > LANE_TOLERANCE:
            fails.append("the %s spawn is %.2f m from a lane centre"
                         % (name, best[0] if best else -1.0))
            continue
        if abs(best[2][1] - spawn[1]) > 0.5:
            fails.append("the %s spawn is %.2f m off the lane height"
                         % (name, abs(best[2][1] - spawn[1])))
        if _angle_diff(best[3], spawn[3]) > HEADING_TOLERANCE:
            fails.append("the %s spawn heads %.1f deg, the lane %.1f"
                         % (name, spawn[3], best[3]))
    return fails


def check_pois(city):
    """The POIs: the roadblocks on their road, the stations next to one."""
    fails = []
    by_id = {r["id"]: r for r in city["roads"]}
    for poi in city["pois"]:
        kind = poi["kind"]
        if kind == "roadblock_site":
            best = None
            for road in by_id.values():
                found = nearest_lane(road, (poi["x"], poi["z"]))
                if found and (best is None or found[0] < best[0]):
                    best = found + (road["id"],)
            if best is None or best[0] > 1.0:
                fails.append("poi %s is %.2f m from a lane centre"
                             % (poi["id"], best[0] if best else -1.0))
            elif abs(best[2][1] - poi["y"]) > 0.5:
                fails.append("poi %s is %.2f m off the road height"
                             % (poi["id"], abs(best[2][1] - poi["y"])))
            elif _angle_diff(best[3], poi["heading_deg"]) > 15.0:
                fails.append("poi %s heads %.0f deg, the lane %.0f"
                             % (poi["id"], poi["heading_deg"], best[3]))
        elif kind in ("gas", "charge", "toll", "police_station"):
            best = 1e18
            for road in by_id.values():
                d = min(math.hypot(p[0] - poi["x"], p[2] - poi["z"])
                        for p in road["points"])
                best = min(best, d)
            if best > 40.0:
                fails.append("poi %s is %.0f m from a road" % (poi["id"], best))
        elif kind == "hiding_spot":
            under = False
            for road in by_id.values():
                if road["kind"] not in ("elevated", "bridge", "ramp", "tunnel"):
                    continue
                half = citylib.road_width(road) * 0.5
                d = min(math.hypot(p[0] - poi["x"], p[2] - poi["z"])
                        for p in road["points"])
                if d < half:
                    under = True
            if not under:
                fails.append("poi %s is not under a deck or in a tunnel"
                             % poi["id"])
        if kind == "police_station" and poi.get("asset") != "police_station":
            fails.append("poi %s has the asset %r" % (poi["id"],
                                                       poi.get("asset")))
    return fails


def _land_cells(city, step=COVERAGE_STEP):
    """The raster of the land: the window without the water and the roads."""
    window = city["window"]
    water = [w for w in city["water"] if "polygon" in w]
    creek = [w for w in city["water"] if "centerline" in w]
    roads = set()
    for road in city["roads"]:
        if road["kind"] == "tunnel":
            continue
        half = citylib.road_width(road) * 0.5 + 1.0
        for p in citylib.road_points(road, 2.0):
            if road["kind"] == "tunnel" and p[1] < TUNNEL_FLOOR:
                continue
            span = int(math.ceil(half / step))
            cx = int(math.floor(p[0] / step))
            cz = int(math.floor(p[2] / step))
            for i in range(cx - span, cx + span + 1):
                for j in range(cz - span, cz + span + 1):
                    if math.hypot((i + 0.5) * step - p[0],
                                  (j + 0.5) * step - p[2]) <= half:
                        roads.add((i, j))
    cells = []
    x = window["x_min"] + step / 2.0
    while x < window["x_max"]:
        z = window["z_min"] + step / 2.0
        while z < window["z_max"]:
            key = (int(math.floor(x / step)), int(math.floor(z / step)))
            if key not in roads and not any(
                    citylib.point_in_polygon((x, z), w["polygon"])
                    for w in water):
                wet = False
                for cr in creek:
                    line = cr["centerline"]
                    if min(citylib.point_seg_distance((x, z), tuple(line[i]),
                                                      tuple(line[i + 1]))
                           for i in range(len(line) - 1)) < cr["width"] / 2.0:
                        wet = True
                        break
                if not wet:
                    cells.append((x, z))
            z += step
        x += step
    return cells


def check_coverage(city):
    """The lots cover the land (the brief: every space between roads).

    The rule rasterises the land - the window without the water and
    without the road footprints - and counts the cells that fall inside a
    lot.  The brief wants 95 % of them covered.
    """
    grid = _block_grid(city, 50.0)
    cells = _land_cells(city)
    if not cells:
        return ["the map has no land to build on"]
    inside = 0
    for x, z in cells:
        for bi in grid.get((int(x // 50.0), int(z // 50.0)), ()):
            if citylib.point_in_polygon((x, z), city["blocks"][bi]["polygon"]):
                inside += 1
                break
    ratio = inside / float(len(cells))
    if ratio < COVERAGE_MIN:
        return ["the lots cover %.1f %% of the land between the roads "
                "(%d of %d cells, %.2f km2 empty)"
                % (ratio * 100.0, inside, len(cells),
                   (len(cells) - inside) * COVERAGE_STEP ** 2 / 1e6)]
    return []


def check_winding(city):
    """The lots run counter-clockwise seen from above (the schema).

    The frame is x east and z south, so a counter-clockwise polygon from
    above has a negative area in the (x, z) plane.
    """
    fails = []
    for block in city["blocks"]:
        area = citylib.polygon_area(block["polygon"])
        if area > 0:
            fails.append("%s runs clockwise seen from above (area %.0f m2)"
                         % (block["id"], area))
    return fails
