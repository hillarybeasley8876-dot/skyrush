"""Reading data/city/city.json: roads, blocks, water and the road-edge distance used for
deciding which buildings need a collider."""
import json
import math
import os


def load(path):
    """Load a city file (city.json or test_city.json)."""
    with open(path) as fh:
        return json.load(fh)


def road_half_width(road):
    """Half width of a road, including the median, shoulder and sidewalks."""
    lanes = float(road.get("lanes_fwd", 0)) + float(road.get("lanes_back", 0))
    w = lanes * float(road.get("lane_width", 3.5))
    w += float(road.get("median", 0.0))
    w += float(road.get("shoulder", 0.0)) * 2.0
    w += float(road.get("sidewalk", 0.0)) * 2.0
    return w * 0.5


def _catmull(points, step=6.0):
    """Sample a Catmull-Rom spline through [x, y, z] points (city.json "spline": "catmull")."""
    if len(points) < 3:
        return [tuple(p) for p in points]
    pts = [points[0]] + [tuple(p) for p in points] + [points[-1]]
    out = []
    for i in range(len(pts) - 3):
        p0, p1, p2, p3 = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
        seg = math.dist((p1[0], p1[2]), (p2[0], p2[2]))
        n = max(1, int(math.ceil(seg / step)))
        for k in range(n):
            t = k / float(n)
            t2, t3 = t * t, t * t * t
            out.append(tuple(
                0.5 * ((2 * p1[d]) + (-p0[d] + p2[d]) * t
                       + (2 * p0[d] - 5 * p1[d] + 4 * p2[d] - p3[d]) * t2
                       + (-p0[d] + 3 * p1[d] - 3 * p2[d] + p3[d]) * t3)
                for d in range(3)))
    out.append(tuple(points[-1]))
    return out


def road_segments(city, kinds=("surface",), step=6.0):
    """Road centre-line segments with their half widths, in the XZ plane.

    Only ground-level roads by default: an elevated deck (or a tunnel) passes OVER the
    blocks, so its centre line is not an obstacle for a building.  Road points are
    [x, y, z] - the ground position is (x, z), never (x, y).
    """
    out = []
    for road in city.get("roads", []):
        if kinds and road.get("kind", "surface") not in kinds:
            continue
        pts = road.get("points", [])
        if road.get("spline", "catmull") == "catmull":
            pts = _catmull(pts, step)
        hw = road_half_width(road)
        for i in range(len(pts) - 1):
            a = pts[i]
            b = pts[i + 1]
            ax, az = (a[0], a[2]) if len(a) > 2 else (a[0], a[1])
            bx, bz = (b[0], b[2]) if len(b) > 2 else (b[0], b[1])
            out.append((ax, az, bx, bz, hw))
    # Suzhou Creek: a centre line with a width instead of a polygon
    for water in city.get("water", []):
        line = water.get("centerline")
        if not line:
            continue
        hw = float(water.get("width", 70.0)) * 0.5
        for i in range(len(line) - 1):
            a = line[i]
            b = line[i + 1]
            out.append((a[0], a[1], b[0], b[1], hw))
    return out


def at_grade_elevated_segments(city, step=6.0):
    """The parts of the elevated roads that are still at grade (the ramp corridors).

    A ramp that has not climbed yet stands on the ground: the ground cover and the
    buildings have to keep out of it.  A deck that is already 30 m up passes over
    the blocks and is no obstacle.
    """
    out = []
    for road in city.get("roads", []):
        if road.get("kind", "surface") in ("surface", "tunnel"):
            continue
        pts = road.get("points", [])
        if road.get("spline", "catmull") == "catmull":
            pts = _catmull(pts, step)
        hw = road_half_width(road)
        for i in range(len(pts) - 1):
            a = pts[i]
            b = pts[i + 1]
            ax, az = (a[0], a[2]) if len(a) > 2 else (a[0], a[1])
            bx, bz = (b[0], b[2]) if len(b) > 2 else (b[0], b[1])
            ay = a[1] if len(a) > 2 else 0.0
            by = b[1] if len(b) > 2 else 0.0
            if max(ay, by) > 3.0:
                continue
            out.append((ax, az, bx, bz, hw))
    return out


def point_segment_distance(px, pz, ax, az, bx, bz):
    """Distance from a point to a segment in the XZ plane."""
    dx, dz = bx - ax, bz - az
    l2 = dx * dx + dz * dz
    if l2 < 1e-9:
        return math.hypot(px - ax, pz - az)
    t = ((px - ax) * dx + (pz - az) * dz) / l2
    t = max(0.0, min(1.0, t))
    return math.hypot(px - (ax + dx * t), pz - (az + dz * t))


def road_edge_distance(px, pz, segments):
    """Distance from a point to the nearest road EDGE (0 when on the road)."""
    best = 1e9
    for (ax, az, bx, bz, hw) in segments:
        d = point_segment_distance(px, pz, ax, az, bx, bz) - hw
        if d < best:
            best = d
    return best


def polygon_centroid(poly):
    n = len(poly)
    return (sum(p[0] for p in poly) / n, sum(p[1] for p in poly) / n)


def polygon_bounds(poly):
    xs = [p[0] for p in poly]
    zs = [p[1] for p in poly]
    return (min(xs), min(zs), max(xs), max(zs))


def blocks_in_tile(city, tx, tz, tile_m):
    """Blocks whose CENTRE falls in the tile (a block is built once, in one tile)."""
    out = []
    for block in city.get("blocks", []):
        cx, cz = polygon_centroid(block["polygon"])
        if int(cx // tile_m) != tx or int(cz // tile_m) != tz:
            continue
        out.append(block)
    return out


def water_polygons(city):
    """The water outlines as plain [x, z] polygon lists."""
    return [w["polygon"] for w in city.get("water", []) if w.get("polygon")]


def point_in_water(x, z, city):
    for poly in water_polygons(city):
        inside = False
        j = len(poly) - 1
        for i in range(len(poly)):
            xi, zi = poly[i]
            xj, zj = poly[j]
            if ((zi > z) != (zj > z)) and (x < (xj - xi) * (z - zi) / (zj - zi + 1e-12) + xi):
                inside = not inside
            j = i
        if inside:
            return True
    return False


def default_city_path():
    """The real city if it exists, otherwise the test city."""
    root = os.path.expanduser("~/m/skyrush/data/city")
    real = os.path.join(root, "city.json")
    return real if os.path.exists(real) else os.path.join(root, "test_city.json")
