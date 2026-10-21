"""Colliders for the buildings that stand close to a road.

The brief's rule: a collider for every building whose NEAREST footprint point is
within 25 m of a road edge - not its centroid, which left 613 near-road buildings
without any collision.  The collider is the footprint prism itself (the convex hull
of the real polygon, extruded to the building's height), so a rotated building no
longer gets an axis-aligned box that overhangs the pavement by up to 25 m.

Parks and plazas are ground cover: they never get a collider, so no invisible kerb
stands in the middle of a carriageway.
"""
import bmesh
import bpy

from . import citydata, shapes

COLLIDER_RANGE = 25.0
SAMPLE_STEP = 1.0       # the footprint edges are sampled every metre


def footprint_points(poly, step=SAMPLE_STEP):
    """The corners of a footprint and a point every `step` metres along its edges."""
    out = []
    n = len(poly)
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        out.append((a[0], a[1]))
        length = ((b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2) ** 0.5
        count = max(1, int(length / step))
        for k in range(1, count):
            t = k / float(count)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def nearest_road_distance(poly, grid):
    """The distance from the nearest point of the footprint to a road edge."""
    best = 1e9
    for (x, z) in footprint_points(poly):
        d = grid.edge_distance(x, z)
        if d < best:
            best = d
            if best <= 0.0:
                break
    return best


def is_near_road(rec, grid, range_m=COLLIDER_RANGE):
    """True when the building stands within `range_m` of a road edge."""
    if rec.get("style") in ("park", "plaza"):
        return False
    poly = rec.get("poly") or []
    if len(poly) < 3:
        return False
    return nearest_road_distance(poly, grid) <= range_m


def convex_hull(points):
    """The convex hull of a list of (x, z) points (Andrew's monotone chain)."""
    pts = sorted(set((round(p[0], 4), round(p[1], 4)) for p in points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def collider_object(rec, col):
    """The collider of one building: the footprint prism, at the footprint's centre."""
    poly = [(p[0], p[1]) for p in rec["poly"]]
    hull = convex_hull(poly)
    if len(hull) < 3:
        return None
    h = float(rec.get("height", 10.0))
    cx = sum(p[0] for p in hull) / len(hull)
    cz = sum(p[1] for p in hull) / len(hull)
    bm = bmesh.new()
    lower = [bm.verts.new(shapes.to_blender(x - cx, z - cz, 0.0)) for x, z in hull]
    upper = [bm.verts.new(shapes.to_blender(x - cx, z - cz, h)) for x, z in hull]
    n = len(hull)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
    bm.faces.new(list(reversed(lower)))
    bm.faces.new(upper)
    name = "%s-convcolonly" % rec["id"]
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.location = (cx, -cz, 0.0)
    col.objects.link(obj)
    obj["building_seed"] = rec.get("seed", 0)
    obj["style"] = rec.get("style", "")
    obj["block_id"] = rec.get("id", "")
    return obj


def collider_objects(records, grid, col, range_m=COLLIDER_RANGE):
    """The colliders of every near-road building; returns (objects, near_flags)."""
    objs = []
    flags = {}
    for rec in records:
        near = is_near_road(rec, grid, range_m)
        flags[rec.get("id")] = near
        if not near:
            continue
        obj = collider_object(rec, col)
        if obj is not None:
            objs.append(obj)
    return objs, flags
