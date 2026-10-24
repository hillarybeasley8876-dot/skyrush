"""Walls on the edges of the decks that nothing else fences.

The parapets of the decks are built road by road, and they give way where a ramp leaves the deck, where the traffic of
another road crosses the edge, and where a collider is cut back to let a lane pass. Every one of those exceptions leaves
a stretch of the edge with no barrier at all and a drop of 5 to 40 m behind it: a random drive over the viaducts of the
city (tools/fuzz_drive.gd --elevated=1) left the deck in 65 % of the drives, and check_open_edges.py counted 903 open
edges. The parapet logic is the right place for the design (the look, the gaps a ramp needs), this pass is the safety net
under it:

  1. every edge of a surface collider that has a triangle on one side only is an edge of a surface (the tiles are welded
     by position: an edge between two tiles or two roads that share their vertices is not one);
  2. it is an edge of a DECK when the surface is at least MIN_DECK above the ground;
  3. it needs no wall when another surface goes on within a short reach behind it (a seam between two roads, the surface
     of a ramp that carries on), when a barrier of the roads stands at it already, or when a lane of the city crosses it
     (the traffic has to get through);
  4. every other edge gets a closed box of WALL_THICK on its outer side, from WALL_BOTTOM under the deck to WALL_TOP over it.

The walls are colliders only (the concrete collider of the tile): the visible parapets stay as they are, so the viaducts
look the same and a car that left the road now meets a wall where the parapet gave way.
"""
import math
import os
from collections import defaultdict

import bmesh

from mathutils import Vector

from city.roads import collision, meshkit, tiles

WELD = 0.004            # m: two vertices closer than this are one
MIN_DECK = 2.5          # m: a surface edge lower than this over the ground is no fall
CELL = 6.0              # m: the grid of the triangles
SEAM_REACH = (0.35, 0.9, 1.6)   # m: how far behind an edge another surface is looked for
SEAM_BELOW = 0.9        # m: the other surface may lie this far under the edge ...
SEAM_ABOVE = 0.7        # ... or this far over it
BARRIER_REACH = 1.0     # m: a barrier this close to the edge fences it
BARRIER_FROM = 0.05     # m over the edge: a barrier has to stand between these two heights ...
BARRIER_TO = 0.55       # ... to stop a car body
LANE_NEAR = 1.0         # m: a lane this close to an edge, running along it, is traffic: the box of a car (0.95 m) must clear the wall
ALONG_COS = 0.82        # the lane is parallel to the edge when the cosine of the angle is over this (35 degrees)
LANE_CROSS_MARGIN = 0.5 # m: a lane that crosses the line of an edge within this far of its ends is traffic that goes through
LANE_LEVEL = 2.0        # m: ... on the same level
WALL_THICK = 0.55       # m: thick enough that a car at 100 m/s does not tunnel
WALL_TOP = 1.35         # m over the deck
WALL_BOTTOM = 0.8       # m under the deck
WALL_OVERLAP = 0.12     # m: two walls overlap at their ends, no crack between them
MIN_EDGE = 0.05         # m: a shorter edge is a sliver

_STATS = {}


def _key(p):
    return (round(p[0] / WELD), round(p[1] / WELD), round(p[2] / WELD))


def _triangles(bm):
    """The triangles of a bmesh as tuples of three (x, y, z) points."""
    out = []
    for face in bm.faces:
        v = [tuple(vert.co) for vert in face.verts]
        for i in range(1, len(v) - 1):
            out.append((v[0], v[i], v[i + 1]))
    return out


def _cells(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return (int(math.floor(min(xs) / CELL)), int(math.floor(max(xs) / CELL)),
            int(math.floor(min(ys) / CELL)), int(math.floor(max(ys) / CELL)))


def _grid(items, points_of):
    grid = defaultdict(list)
    for index, item in enumerate(items):
        x0, x1, y0, y1 = _cells(points_of(item))
        for cx in range(x0, x1 + 1):
            for cy in range(y0, y1 + 1):
                grid[(cx, cy)].append(index)
    return grid


def _in_triangle(px, py, tri):
    """The height of the triangle at (px, py) when the point is inside it (plan), else None."""
    (ax, ay, az), (bx, by, bz), (cx, cy, cz) = tri
    den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(den) < 1e-9:
        return None
    u = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
    v = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
    w = 1.0 - u - v
    eps = -0.02
    if u < eps or v < eps or w < eps:
        return None
    return u * az + v * bz + w * cz


def _near_triangle(px, py, tri, reach):
    """True when (px, py) is within `reach` of the triangle in plan (inside counts)."""
    if _in_triangle(px, py, tri) is not None:
        return True
    for i in range(3):
        a, b = tri[i], tri[(i + 1) % 3]
        dx, dy = b[0] - a[0], b[1] - a[1]
        l2 = dx * dx + dy * dy
        t = 0.0 if l2 < 1e-12 else max(0.0, min(1.0, ((px - a[0]) * dx + (py - a[1]) * dy) / l2))
        qx, qy = a[0] + dx * t, a[1] + dy * t
        if (px - qx) ** 2 + (py - qy) ** 2 <= reach * reach:
            return True
    return False


def _lane_segments(lane_data):
    """The lane segments in Blender space (x east, y north, z up): [(ax, ay, az, bx, by, bz)]."""
    out = []
    for lane in (lane_data or {}).get("lanes", []):
        pts = lane.get("points", [])
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            # lanes.json is in Godot space (x east, y up, z south)
            out.append((a[0], -a[2], a[1], b[0], -b[2], b[1]))
    return out


def add(tileset, lane_data=None):
    """Adds the walls to the concrete collider of the tiles. Returns the statistics."""
    surface = []                    # triangles of every surface collider
    for builder in tileset.builders.values():
        bm = builder.named.get(collision.SURFACE_NAME)
        if bm is not None:
            surface.extend(_triangles(bm))
    barrier = []
    for builder in tileset.builders.values():
        for name in (collision.CONCRETE_NAME, collision.STEEL_NAME):
            bm = builder.named.get(name)
            if bm is not None:
                barrier.extend(_triangles(bm))
    surface_grid = _grid(surface, lambda t: t)
    barrier_grid = _grid(barrier, lambda t: t)
    lanes = _lane_segments(lane_data)
    lane_grid = _grid(lanes, lambda s: [(s[0], s[1]), (s[3], s[4])])

    # the edges of the surface: an edge that one triangle only has
    edges = {}
    for index, tri in enumerate(surface):
        keys = [_key(p) for p in tri]
        for i in range(3):
            k0, k1 = keys[i], keys[(i + 1) % 3]
            if k0 == k1:
                continue
            ek = (k0, k1) if k0 < k1 else (k1, k0)
            if ek in edges:
                edges[ek] = None        # two triangles: inside
            else:
                edges[ek] = (index, i)
    boundary = [v for v in edges.values() if v is not None]

    debug = None
    if os.environ.get("EDGEWALLS_DEBUG"):
        dx_, dz_, dr_ = [float(v) for v in os.environ["EDGEWALLS_DEBUG"].split(",")]
        debug = (dx_, -dz_, dr_)
    walled = 0
    seams = 0
    fenced = 0
    crossed = 0
    low = 0
    per_tile = defaultdict(list)
    for (index, i) in boundary:
        tri = surface[index]
        a, b, c = tri[i], tri[(i + 1) % 3], tri[(i + 2) % 3]
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        if length < MIN_EDGE:
            continue
        mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, (a[2] + b[2]) * 0.5)
        if mid[2] < MIN_DECK:
            low += 1
            continue
        dx, dy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
        nx, ny = dy, -dx
        if nx * (c[0] - a[0]) + ny * (c[1] - a[1]) > 0.0:
            nx, ny = -nx, -ny
        watch = debug is not None and math.hypot(mid[0] - debug[0], mid[1] - debug[1]) <= debug[2]
        # a lane that comes near the edge anywhere along it is traffic that the wall must leave alone
        if _lane_near_edge(a, b, lanes, lane_grid):
            crossed += 1
            if watch:
                print("EDGEDEBUG (%.1f %.1f %.1f)-(%.1f %.1f %.1f) len %.1f: a lane goes through or along it" % (
                    a[0], -a[1], a[2], b[0], -b[1], b[2], length))
            continue
        # three samples along the edge: a wall is needed where ANY of them is open
        open_edge = False
        reason = None
        for t in (0.25, 0.5, 0.75):
            sx, sy = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            sz = a[2] + (b[2] - a[2]) * t
            if _has_surface_behind(sx, sy, sz, nx, ny, index, surface, surface_grid):
                reason = "seam"
                continue
            if _has_barrier(sx, sy, sz, barrier, barrier_grid):
                reason = "fenced"
                continue
            open_edge = True
            break
        if watch:
            print("EDGEDEBUG (%.1f %.1f %.1f)-(%.1f %.1f %.1f) len %.1f: %s (last reason %s)" % (
                a[0], -a[1], a[2], b[0], -b[1], b[2], length, "WALL" if open_edge else "no wall", reason))
        if not open_edge:
            if reason == "seam":
                seams += 1
            elif reason == "fenced":
                fenced += 1
            continue
        walled += 1
        per_tile[tiles.tile_of(Vector(mid))].append((a, b, (nx, ny)))

    for key, items in per_tile.items():
        builder = tileset.builder(key)
        bm = bmesh.new()
        for (a, b, (nx, ny)) in items:
            length = math.hypot(b[0] - a[0], b[1] - a[1]) + WALL_OVERLAP * 2.0
            mx, my = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
            mz = (a[2] + b[2]) * 0.5
            centre = (mx + nx * (WALL_THICK * 0.5 + 0.02), my + ny * (WALL_THICK * 0.5 + 0.02),
                      mz + (WALL_TOP - WALL_BOTTOM) * 0.5)
            meshkit.box(bm, centre, (length, WALL_THICK, WALL_TOP + WALL_BOTTOM), math.atan2(b[1] - a[1], b[0] - a[0]))
        builder.add_named(collision.CONCRETE_NAME, bm)
    _STATS.update({"surface triangles": len(surface), "boundary edges": len(boundary), "low": low, "seams": seams,
                   "fenced": fenced, "crossed": crossed, "walls": walled})
    return dict(_STATS)


def _has_surface_behind(sx, sy, sz, nx, ny, own, surface, grid):
    for reach in SEAM_REACH:
        px, py = sx + nx * reach, sy + ny * reach
        for j in grid.get((int(math.floor(px / CELL)), int(math.floor(py / CELL))), ()):
            if j == own:
                continue
            z = _in_triangle(px, py, surface[j])
            if z is not None and -SEAM_BELOW <= z - sz <= SEAM_ABOVE:
                return True
    return False


def _has_barrier(sx, sy, sz, barrier, grid):
    for j in grid.get((int(math.floor(sx / CELL)), int(math.floor(sy / CELL))), ()):
        tri = barrier[j]
        lo = min(p[2] for p in tri)
        hi = max(p[2] for p in tri)
        if hi < sz + BARRIER_FROM or lo > sz + BARRIER_TO:
            continue
        if _near_triangle(sx, sy, tri, BARRIER_REACH):
            return True
    return False


def _segment_distance_2d(a, b, c, d):
    """The least plan distance between the segments a-b and c-d."""
    def point_segment(p, q, r):
        dx, dy = r[0] - q[0], r[1] - q[1]
        l2 = dx * dx + dy * dy
        t = 0.0 if l2 < 1e-12 else max(0.0, min(1.0, ((p[0] - q[0]) * dx + (p[1] - q[1]) * dy) / l2))
        return math.hypot(p[0] - (q[0] + dx * t), p[1] - (q[1] + dy * t))
    # the segments cross: distance 0
    def side(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    if side(a, b, c) * side(a, b, d) < 0.0 and side(c, d, a) * side(c, d, b) < 0.0:
        return 0.0
    return min(point_segment(a, c, d), point_segment(b, c, d), point_segment(c, a, b), point_segment(d, a, b))


def _crosses(a, b, c, d):
    """True when the segment c-d passes the line of the edge a-b between its (widened) ends: it goes through the edge."""
    ex, ey = b[0] - a[0], b[1] - a[1]
    length = math.hypot(ex, ey)
    if length < 1e-9:
        return False
    ex, ey = ex / length, ey / length
    # the lane end points in the frame of the edge: u along it, v across it
    cu = (c[0] - a[0]) * ex + (c[1] - a[1]) * ey
    cv = (c[0] - a[0]) * (-ey) + (c[1] - a[1]) * ex
    du = (d[0] - a[0]) * ex + (d[1] - a[1]) * ey
    dv = (d[0] - a[0]) * (-ey) + (d[1] - a[1]) * ex
    # a lane that stays on one side (or ends at the edge without going past it) does not go through
    if cv * dv >= 0.0 and min(abs(cv), abs(dv)) > 0.3:
        return False
    if max(abs(cv), abs(dv)) < 0.3:
        return False
    # where the lane meets the line of the edge
    t = cv / (cv - dv) if abs(cv - dv) > 1e-9 else 0.0
    u = cu + (du - cu) * t
    # it has to GO PAST the edge (to the other side by more than 0.3 m), not only touch it
    if not (cv * dv < 0.0 and min(abs(cv), abs(dv)) > 0.0 and max(abs(cv), abs(dv)) > 0.3):
        return False
    return -LANE_CROSS_MARGIN <= u <= length + LANE_CROSS_MARGIN


def _lane_near_edge(a, b, lanes, grid):
    """True when a lane of the same level goes through the edge a-b or runs along it closer than LANE_NEAR."""
    reach = LANE_NEAR + LANE_CROSS_MARGIN
    x0, x1, y0, y1 = _cells([(min(a[0], b[0]) - reach, min(a[1], b[1]) - reach), (max(a[0], b[0]) + reach, max(a[1], b[1]) + reach)])
    seen = set()
    z_edge = (a[2] + b[2]) * 0.5
    for cx in range(x0, x1 + 1):
        for cy in range(y0, y1 + 1):
            for j in grid.get((cx, cy), ()):
                if j in seen:
                    continue
                seen.add(j)
                seg = lanes[j]
                if abs((seg[2] + seg[5]) * 0.5 - z_edge) > LANE_LEVEL:
                    continue
                c, d = (seg[0], seg[1]), (seg[3], seg[4])
                if _crosses(a, b, c, d):
                    return True
                # a lane that runs ALONG the edge, closer than a car needs: the wall would stand in its box. A lane that ends at the
                # edge (a deck that stops: nothing goes on behind it) comes at the edge, it does not run along it
                ex, ey = b[0] - a[0], b[1] - a[1]
                lx, ly = d[0] - c[0], d[1] - c[1]
                norm = math.hypot(ex, ey) * math.hypot(lx, ly)
                if norm > 1e-9 and abs(ex * lx + ey * ly) / norm > ALONG_COS                         and _segment_distance_2d(a, b, c, d) <= LANE_NEAR:
                    return True
    return False
