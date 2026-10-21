"""Road markings: lane lines, edge lines, median lines, guide arrows and gore chevrons.

GB 5768.3 (dossier §2.6): lane lines white 15 cm, dashed 6 m / 9 m gap on roads
of 60 km/h and over, 2 m / 4 m below; edge lines solid white 20 cm; solid yellow
15 cm next to the median. Every marking is a thin strip 5 mm above the asphalt,
built on the same 4 m geometry path as the road so it can never sink into it. The
dash phase is carried from the road's own distance, so a dash pattern runs
unbroken across tile and junction seams.
"""
import bmesh
import math

from mathutils import Vector

from city.roads import profiles

WHITE = "SH_road_marking_white"
YELLOW = "SH_road_marking_yellow"
Z = 0.005              # 5 mm above the asphalt
LANE_LINE_W = 0.15
EDGE_LINE_W = 0.20
YELLOW_W = 0.15
UP = Vector((0.0, 0.0, 1.0))


class Path:
    """The road's geometry path with distance lookup and interpolation."""

    def __init__(self, road):
        self.points = road.path
        self.rights = [f[1] for f in road.frames]
        self.dist = road.dist

    def interp(self, i, t):
        """(point, right) between the samples i and i+1."""
        p = self.points[i].lerp(self.points[i + 1], t)
        r = self.rights[i].lerp(self.rights[i + 1], t)
        if r.length > 1e-6:
            r.normalize()
        return p, r

    def at(self, s):
        """(point, right) at a distance along the path."""
        i = 0
        d = self.dist
        while i + 1 < len(d) and d[i + 1] < s:
            i += 1
        seg = d[i + 1] - d[i] if i + 1 < len(d) else 1.0
        t = 0.0 if seg <= 1e-6 else (s - d[i]) / seg
        return self.interp(i, max(0.0, min(1.0, t)))


def add_span(bm, path, s0, s1, across, width, z=Z):
    """A marking strip between two distances along the path."""
    half = width * 0.5
    for i in range(len(path.dist) - 1):
        d0, d1 = path.dist[i], path.dist[i + 1]
        lo, hi = max(s0, d0), min(s1, d1)
        if hi <= lo:
            continue
        span = d1 - d0
        if span <= 1e-6:
            continue
        p0, r0 = path.interp(i, (lo - d0) / span)
        p1, r1 = path.interp(i, (hi - d0) / span)
        a = bm.verts.new(p0 + r0 * (across - half) + UP * z)
        b = bm.verts.new(p0 + r0 * (across + half) + UP * z)
        c = bm.verts.new(p1 + r1 * (across + half) + UP * z)
        d = bm.verts.new(p1 + r1 * (across - half) + UP * z)
        bm.faces.new((a, b, c, d))
    return bm


def dash_spans(s0, s1, dash, gap):
    """The dash spans inside [s0, s1], phased on the road's own distance."""
    out = []
    period = dash + gap
    t = math.floor(s0 / period) * period
    while t < s1:
        lo, hi = max(t, s0), min(t + dash, s1)
        if hi > lo:
            out.append((lo, hi))
        t += period
    return out


def dash_pattern(speed_kmh):
    """(dash, gap) in metres for the road's speed (GB 5768.3)."""
    return (6.0, 9.0) if speed_kmh >= 60 else (2.0, 4.0)


def build_lane_markings(road, lay, builder, idx):
    """All markings that follow the road, over the path samples `idx`."""
    path = Path(road)
    s0, s1 = road.dist[idx[0]], road.dist[idx[-1]]
    dash, gap = dash_pattern(road.speed_kmh)
    for side in ("fwd", "back"):
        lanes = lay["lanes"][side]
        for i in range(len(lanes) - 1):
            across = lanes[i][1] if side == "fwd" else lanes[i][0]
            bm = bmesh.new()
            for (a, b) in dash_spans(s0, s1, dash, gap):
                add_span(bm, path, a, b, across, LANE_LINE_W)
            builder.add(WHITE, bm)
        # edge line along the outer kerb
        edge = lay["asphalt_fwd"] if side == "fwd" else lay["asphalt_back"]
        out = 1.0 if side == "fwd" else -1.0
        bm = bmesh.new()
        add_span(bm, path, s0, s1, edge - out * 0.22, EDGE_LINE_W)
        builder.add(WHITE, bm)
        # solid yellow line next to the median
        inner = lay["asphalt_inner_fwd"] if side == "fwd" else lay["asphalt_inner_back"]
        if road.median > 0.0 or lay["inner_strip"] > 0.0:
            bm = bmesh.new()
            add_span(bm, path, s0, s1, inner + out * 0.18, YELLOW_W)
            builder.add(YELLOW, bm)
    if road.median <= 0.0 and road.lanes_back > 0:
        for off in (-0.15, 0.15):
            bm = bmesh.new()
            add_span(bm, path, s0, s1, off, YELLOW_W)
            builder.add(YELLOW, bm)


def _band(p0, p1, width):
    """A rectangle along the 2D segment p0->p1."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    length = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / length * width * 0.5, dx / length * width * 0.5
    return [(p0[0] - nx, p0[1] - ny), (p1[0] - nx, p1[1] - ny),
            (p1[0] + nx, p1[1] + ny), (p0[0] + nx, p0[1] + ny)]


def _head(base0, base1, tip):
    """A triangle: the arrow head, base between base0 and base1, point at tip."""
    return [(base0[0], base0[1]), (base1[0], base1[1]), (tip[0], tip[1])]


# GB 5768.3 figure 44, 6 m system: 30 cm shaft, 90 cm head, 240 cm head length.
ARROW_STRAIGHT = [
    _band((0.0, 0.0), (0.0, 3.6), 0.30),
    _head((-0.45, 3.6), (0.45, 3.6), (0.0, 6.0)),
]
ARROW_RIGHT = [
    _band((0.0, 0.0), (0.0, 2.2), 0.30),
    _band((0.0, 2.2), (2.2, 4.4), 0.30),
    _head((1.76, 4.84), (2.64, 3.96), (3.90, 6.10)),
]


def build_arrow(tileset, origin, right, forward, kind="straight"):
    """A flat GB guide arrow (6 m long) painted on the road.

    Every piece goes into the tile it lies on: an arrow can reach over the
    border of the tile of the junction.
    """
    polys = ARROW_STRAIGHT if kind == "straight" else ARROW_RIGHT
    for poly in polys:
        bm = bmesh.new()
        verts = [bm.verts.new(origin + right * x + forward * y) for (x, y) in poly]
        bm.faces.new(verts)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mid = sum((v.co for v in verts), Vector()) / len(verts)
        tileset.builder_at(mid).add(WHITE, bm)
