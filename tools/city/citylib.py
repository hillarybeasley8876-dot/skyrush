"""citylib — geometry helpers for the SKYRUSH city layout unit.

Pure Python 3.9 stdlib (no numpy). Frame: metres, X east, Z south, Y up
(Godot coords; north = -Z).  Origin = Bund x Yan'an E Rd at ground.

Used by build_city.py (writes data/city/city.json), validate.py (checks it) and
render_map.py (draws it).
"""
import math

from city_json import load_json, save_json

TAU = math.pi * 2.0


# ---------------------------------------------------------------- splines

def catmull_rom(points, step=2.0, closed=False):
    """Uniform Catmull-Rom through the control points, resampled every `step` m.

    Same formula as blender/lib/geo.py catmull_rom so the game mesh and the
    validation samples agree exactly.  Returns a list of [x, y, z] lists.
    """
    if len(points) < 2:
        return [list(p) for p in points]
    if closed:
        pts = [points[-1]] + list(points) + [points[0], points[1]]
    else:
        # Reflect the end points (same as blender/lib/geo.py) so the end
        # tangents match the mesh the roads unit will build.
        first = [2 * points[0][i] - points[1][i] for i in range(len(points[0]))]
        last = [2 * points[-1][i] - points[-2][i] for i in range(len(points[0]))]
        pts = [first] + list(points) + [last]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        seg = math.dist(p1, p2)
        n = max(1, int(math.ceil(seg / step)))
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append([
                0.5 * (2 * p1[0] + (-p0[0] + p2[0]) * t
                       + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                       + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3),
                0.5 * (2 * p1[1] + (-p0[1] + p2[1]) * t
                       + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                       + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3),
                0.5 * (2 * p1[2] + (-p0[2] + p2[2]) * t
                       + (2 * p0[2] - 5 * p1[2] + 4 * p2[2] - p3[2]) * t2
                       + (-p0[2] + 3 * p1[2] - 3 * p2[2] + p3[2]) * t3),
            ])
    if not closed:
        out.append(list(pts[-2]))
    return out


def resample(points, step):
    """Uniformly resample a polyline every `step` metres (keeps both ends)."""
    if len(points) < 2:
        return [list(p) for p in points]
    out = [list(points[0])]
    carry = 0.0
    for a, b in zip(points, points[1:]):
        seg = math.dist(a, b)
        if seg < 1e-9:
            continue
        d = step - carry
        while d <= seg:
            out.append([a[i] + (b[i] - a[i]) * (d / seg) for i in range(len(a))])
            d += step
        carry = seg - (d - step)
    if math.dist(out[-1], points[-1]) > 1e-4:
        out.append(list(points[-1]))
    return out


# ---------------------------------------------------------------- polylines

def polyline_length(points):
    """Total length of a polyline in metres."""
    return sum(math.dist(a, b) for a, b in zip(points, points[1:]))


def cumulative(points):
    """Distances along a polyline, one entry per point (0 for the first)."""
    out = [0.0]
    for a, b in zip(points, points[1:]):
        out.append(out[-1] + math.dist(a, b))
    return out


def point_at_distance(points, s):
    """Point and unit tangent at distance `s` along the polyline."""
    acc = 0.0
    for a, b in zip(points, points[1:]):
        seg = math.dist(a, b)
        if seg < 1e-9:
            continue
        if acc + seg >= s:
            t = (s - acc) / seg
            pt = [a[i] + (b[i] - a[i]) * t for i in range(len(a))]
            tan = [(b[i] - a[i]) / seg for i in range(len(a))]
            return pt, tan
        acc += seg
    a, b = points[-2], points[-1]
    seg = math.dist(a, b) or 1.0
    return list(b), [(b[i] - a[i]) / seg for i in range(len(a))]


def heading_deg(tan):
    """Heading in degrees: 0 = north (-Z), 90 = east (+X).

    The tangent is (x, z) in the plan or (x, y, z) in space.
    """
    north = tan[2] if len(tan) > 2 else tan[1]
    return math.degrees(math.atan2(tan[0], -north)) % 360.0


# ---------------------------------------------------------------- roads

PARAPET_W = 0.5


def road_width(road):
    """Total paved width of a road in metres (lanes + median + shoulders +
    sidewalks + parapets).  Elevated decks get the 0.5 m parapet on each side,
    surface roads get the sidewalk on each side.  Accepts a dict or a Road."""
    get = road.get if isinstance(road, dict) else (lambda k, d=0.0: getattr(road, k, d))
    lanes = (get("lanes_fwd", 0) + get("lanes_back", 0)) * get("lane_width", 3.75)
    width = lanes + get("median", 0.0) + 2.0 * get("shoulder", 0.0)
    kind = get("kind", "surface")
    style = get("style", {}) or {}
    if kind == "surface":
        width += 2.0 * get("sidewalk", 0.0)
    elif style.get("parapet", "none") != "none":
        width += 2.0 * PARAPET_W
    return width


def road_points(road, step=2.0):
    """Sampled centre-line of a road: Catmull-Rom for `spline: catmull`,
    otherwise the control points themselves."""
    pts = road["points"]
    if road.get("spline", "catmull") == "catmull":
        return catmull_rom(pts, step)
    return [list(p) for p in pts]


def edge_polylines(road, step=2.0):
    """Left and right edge polylines of a road (offset by half the width)."""
    pts = road_points(road, step)
    half = road_width(road) * 0.5
    left, right = [], []
    for i, p in enumerate(pts):
        a = pts[max(0, i - 1)]
        b = pts[min(len(pts) - 1, i + 1)]
        dx, dz = b[0] - a[0], b[2] - a[2]
        length = math.hypot(dx, dz) or 1.0
        nx, nz = -dz / length, dx / length
        left.append([p[0] + nx * half, p[1], p[2] + nz * half])
        right.append([p[0] - nx * half, p[1], p[2] - nz * half])
    return left, right


def polyline_offset(points, dist):
    """Offset a 2D polyline sideways by `dist` (positive = left of travel)."""
    out = []
    for i, p in enumerate(points):
        a = points[max(0, i - 1)]
        b = points[min(len(points) - 1, i + 1)]
        dx, dz = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dz) or 1.0
        out.append((p[0] - dz / length * dist, p[1] + dx / length * dist))
    return out


# ---------------------------------------------------------------- polygons

def polygon_area(poly):
    """Signed area (positive = counter-clockwise seen from above)."""
    total = 0.0
    for a, b in zip(poly, poly[1:] + poly[:1]):
        total += a[0] * b[1] - b[0] * a[1]
    return total * 0.5


def point_in_polygon(pt, poly):
    """Ray-casting point-in-polygon test for a 2D polygon [(x, z), ...]."""
    x, y = pt[0], pt[1]
    inside = False
    for a, b in zip(poly, poly[1:] + poly[:1]):
        if (a[1] > y) != (b[1] > y):
            t = (y - a[1]) / (b[1] - a[1])
            if x < a[0] + t * (b[0] - a[0]):
                inside = not inside
    return inside


def segments_intersect(a, b, c, d):
    """True if segment a-b crosses segment c-d (proper crossing or touch)."""
    def cross(o, p, q):
        return (p[0] - o[0]) * (q[1] - o[1]) - (p[1] - o[1]) * (q[0] - o[0])
    d1, d2 = cross(c, d, a), cross(c, d, b)
    d3, d4 = cross(a, b, c), cross(a, b, d)
    if ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0)):
        return True
    return False


def polygons_overlap(a, b):
    """True if two 2D polygons overlap (edge crossing or one contains the other)."""
    for p, q in zip(a, a[1:] + a[:1]):
        for r, s in zip(b, b[1:] + b[:1]):
            if segments_intersect(p, q, r, s):
                return True
    return point_in_polygon(a[0], b) or point_in_polygon(b[0], a)


def offset_polygon(poly, dist):
    """Offset a convex 2D polygon outward by `dist` (edge lines re-intersected)."""
    n = len(poly)
    area = polygon_area(poly)
    sign = 1.0 if area >= 0 else -1.0
    lines = []
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        dx, dz = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dz) or 1.0
        nx, nz = -dz / length * sign, dx / length * sign
        lines.append(((a[0] + nx * dist, a[1] + nz * dist),
                       (b[0] + nx * dist, b[1] + nz * dist)))
    out = []
    for i in range(n):
        p1, p2 = lines[i - 1]
        p3, p4 = lines[i]
        den = (p1[0] - p2[0]) * (p3[1] - p4[1]) - (p1[1] - p2[1]) * (p3[0] - p4[0])
        if abs(den) < 1e-9:
            out.append(poly[i])
            continue
        a1 = p2[0] - p1[0]
        b1 = p2[1] - p1[1]
        c1 = a1 * p1[0] + b1 * p1[1]
        a2 = p4[0] - p3[0]
        b2 = p4[1] - p3[1]
        c2 = a2 * p3[0] + b2 * p3[1]
        out.append(((b2 * c1 - b1 * c2) / den, (a1 * c2 - a2 * c1) / den))
    return out


def rect(x0, z0, x1, z1):
    """Counter-clockwise rectangle polygon (from above)."""
    return [[x0, z0], [x1, z0], [x1, z1], [x0, z1]]


def point_seg_distance(pt, a, b):
    """Distance from a 2D point to a 2D segment."""
    ax, ay = a[0], a[1]
    bx, by = b[0], b[1]
    dx, dy = bx - ax, by - ay
    den = dx * dx + dy * dy
    if den < 1e-12:
        return math.dist(pt, a)
    t = max(0.0, min(1.0, ((pt[0] - ax) * dx + (pt[1] - ay) * dy) / den))
    return math.dist(pt, (ax + t * dx, ay + t * dy))




class PolyIndex:
    """A spatial index over a set of polylines.

    `add(name, points)` registers a polyline; `nearest(p, radius)` returns the
    closest registered point within `radius` as (distance, name, index, point).
    """

    CELL = 120.0

    def __init__(self):
        self.cells = {}
        self.polys = {}

    def add(self, name, points):
        self.polys[name] = points
        for i, p in enumerate(points):
            key = (int(p[0] // self.CELL), int(p[1] // self.CELL))
            self.cells.setdefault(key, []).append((name, i, p))

    def within(self, point, radius):
        """Every registered point within `radius` of the query point."""
        out = []
        cx = int(point[0] // self.CELL)
        cz = int(point[1] // self.CELL)
        span = int(radius // self.CELL) + 1
        for i in range(cx - span, cx + span + 1):
            for j in range(cz - span, cz + span + 1):
                for name, idx, p in self.cells.get((i, j), ()):
                    if math.dist(point, p) <= radius:
                        out.append((name, idx, p))
        return out

    def distance_to(self, point, name):
        """The exact distance from a point to a named polyline."""
        poly = self.polys.get(name, [])
        if not poly:
            return 1e18
        best, best_i = 1e18, 0
        for i, p in enumerate(poly):
            d = math.dist(point, p)
            if d < best:
                best, best_i = d, i
        out = best
        for i in (best_i - 1, best_i):
            if 0 <= i < len(poly) - 1:
                out = min(out, point_seg_distance(point, poly[i], poly[i + 1]))
        return out

    def nearest(self, point, radius):
        """The closest registered point within `radius`."""
        best = (radius, None, -1, None)
        cx = int(point[0] // self.CELL)
        cz = int(point[1] // self.CELL)
        span = int(radius // self.CELL) + 1
        for i in range(cx - span, cx + span + 1):
            for j in range(cz - span, cz + span + 1):
                for name, idx, p in self.cells.get((i, j), ()):
                    d = math.dist(point, p)
                    if d < best[0]:
                        best = (d, name, idx, p)
        return best
