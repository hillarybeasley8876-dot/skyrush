"""The Bund promenade, flood wall and river edge (bund unit).

The cross-section follows dossier §5.2: facade | sidewalk | road | tree strip | lawn | stairs |
promenade deck at Y +2.5 | balustrade | water at Y -3.0. Everything is swept along the Bund
road centreline, so the promenade follows the curve of Zhongshan East 1st Road.
"""
import math

from lib import common, geo
from mathutils import Vector

from . import data
from .kit import assembly, parts

Z = data.DECK_Y
HEDGE_H = 0.8          # the clipped hedge along the foot of the deck wall
COPING = 0.30          # the coping on the deck's road face


def base_path(step=2.0, z0=-8.0, z1=-975.0):
    """The road centreline in Blender coordinates, ordered SOUTH -> NORTH.

    The game Z becomes -Y (glTF maps Blender +Y to Godot -Z), so a south->north path has a
    tangent with +Y and the sweep's right vector (t x up = (ty, -tx)) points EAST - which is
    what every +offset in the cross-section means."""
    pts = []
    # the interpolated start point at the southern end of the Bund (Yan'an Road)
    a, b = data.ROAD_PATH[0], data.ROAD_PATH[1]
    tx, tz = _unit(a, b)
    d = (z0 - a[1]) / tz
    pts.append((a[0] + tx * d, -z0, 0.0))
    for (x, z) in data.ROAD_PATH:
        if min(z0, z1) <= z <= max(z0, z1):
            pts.append((x, -z, 0.0))
    # the northern extension past Suzhou Creek
    a, b = data.ROAD_PATH[-2], data.ROAD_PATH[-1]
    tx, tz = _unit(a, b)
    d = (z1 - b[1]) / tz
    pts.append((b[0] + tx * d, -z1, 0.0))
    return _dedupe(_round_corners(geo.resample(pts, step)))


def _round_corners(pts, passes=4):
    """Smooth the polyline's corners while keeping the straight sections on the road.

    The dossier's cross-section offsets are measured from the centreline polyline, so the
    path has to follow it - a Catmull-Rom spline would cut the corners and pull the flood
    wall several metres away from the documented position."""
    out = [Vector(p) for p in pts]
    for _ in range(passes):
        nxt = [out[0]]
        for i in range(1, len(out) - 1):
            nxt.append((out[i - 1] + out[i] * 2.0 + out[i + 1]) * 0.25)
        nxt.append(out[-1])
        out = nxt
    return out


def _unit(a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    n = math.hypot(dx, dz)
    return dx / n, dz / n


def _dedupe(pts, min_d=0.05):
    """Drop points that are too close together (a zero-length segment breaks the frames)."""
    out = []
    for p in pts:
        if not out or math.dist(out[-1][:2], p[:2]) > min_d:
            out.append(p)
    return out


def offset_path(path, offset, z=0.0):
    """A path offset east (perpendicular to the tangent) by `offset` metres."""
    out = []
    n = len(path)
    for i, p in enumerate(path):
        a = path[max(0, i - 1)]
        b = path[min(n - 1, i + 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(tx, ty) or 1.0
        rx, ry = ty / ln, -tx / ln
        out.append(Vector((p[0] + rx * offset, p[1] + ry * offset, z)))
    return _dedupe(out)


def _sweep(asm, role, profile, path):
    """Sweep a closed 2D profile along a path into the assembly."""
    bm = geo.sweep(profile, _dedupe(path), closed_profile=True)
    parts.merge(asm.bm(role), bm)


def build(col, M):
    """Build the whole promenade; returns the objects and the lantern positions."""
    asm = assembly.Assembly("Bund_Promenade")
    base = base_path(step=2.0)
    edge = offset_path(base, data.OFF_BALUSTRADE)
    _ground(asm, base)
    _deck(asm, base)
    _stairs(asm, base)
    _wash(asm, offset_path(base, data.OFF_BALUSTRADE + 0.06))
    from . import promfurn, promplazas
    lamps = promfurn.build(asm, base, edge)
    promplazas.build(asm, base)
    roles = {"paving": M["paving"], "granite": M["granite"], "iron": M["iron"],
             "lantern": M["lantern"], "flood": M["flood"], "bronze": M["bronze"],
             "planter": M["planter"], "leaf": M["leaf"], "wall": M["wall"],
             "grass": M["grass"], "hedge": M["hedge"]}
    objs = asm.to_objects(col, roles)
    objs.append(_collider(edge, col))
    return objs, lamps


def _collider(edge, col):
    """A trimesh collider for the deck and the flood wall (-colonly)."""
    prof = [(-28.0, data.WALL_TOE), (3.0, data.WALL_TOE), (3.0, data.DECK_Y),
            (-28.0, data.DECK_Y)]
    bm = geo.sweep(prof, _dedupe(edge), closed_profile=True)
    obj = common.mesh_object("Bund_Promenade-colonly", bm, col)
    return obj


def _ground(asm, path):
    """The lawn strip between the road and the stairs, and the hedge at the wall foot."""
    prof = [(data.OFF_KERB, -0.8), (data.OFF_KERB, 0.06), (data.OFF_LAWN, 0.06),
            (data.OFF_LAWN, -0.8)]
    _sweep(asm, "grass", prof, path)
    # the granite kerb between the road and the lawn: the driver on the Bund road must
    # see a kerb line, not a bare edge (art dossier 6)
    kerb = [(data.OFF_KERB - 0.25, -0.8), (data.OFF_KERB - 0.25, 0.18),
            (data.OFF_KERB + 0.12, 0.18), (data.OFF_KERB + 0.12, -0.8)]
    _sweep(asm, "granite", kerb, path)
    # the clipped hedge along the kerb, so the road is not a bare strip
    hprof = [(data.OFF_KERB + 0.4, 0.06), (data.OFF_KERB + 0.4, 0.06 + HEDGE_H),
             (data.OFF_KERB + 1.3, 0.06 + HEDGE_H), (data.OFF_KERB + 1.3, 0.06)]
    _sweep(asm, "hedge", hprof, path)


def _deck(asm, path):
    """The deck slab, the flood wall and the river face.

    The deck's road face is clad in the granite ashlar with a coping on top - the driver
    on the Bund road must not look at a blank concrete wall (ART 6)."""
    prof = [(data.OFF_DECK, -0.8), (data.OFF_DECK, Z), (data.OFF_BALUSTRADE - 0.15, Z),
            (data.OFF_BALUSTRADE - 0.15, data.WALL_TOE), (data.OFF_DECK, data.WALL_TOE)]
    _sweep(asm, "wall", prof, path)
    # the granite paving on top of the deck
    pav = [(data.OFF_DECK + 0.2, Z), (data.OFF_BALUSTRADE - 0.15, Z),
           (data.OFF_BALUSTRADE - 0.15, Z - 0.12), (data.OFF_DECK + 0.2, Z - 0.12)]
    _sweep(asm, "paving", pav, path)
    # the coping along the river edge
    cop = [(data.OFF_BALUSTRADE - 0.15, Z), (data.OFF_BALUSTRADE, Z),
           (data.OFF_BALUSTRADE, Z - 0.3), (data.OFF_BALUSTRADE - 0.15, Z - 0.3)]
    _sweep(asm, "granite", cop, path)
    # the cladding of the road face and its coping
    clad = [(data.OFF_DECK, -0.8), (data.OFF_DECK, Z - COPING),
            (data.OFF_DECK - 0.12, Z - COPING), (data.OFF_DECK - 0.12, -0.8)]
    _sweep(asm, "granite", clad, path)
    cope = [(data.OFF_DECK - 0.30, Z - COPING), (data.OFF_DECK + 0.10, Z - COPING),
            (data.OFF_DECK + 0.10, Z), (data.OFF_DECK - 0.30, Z)]
    _sweep(asm, "granite", cope, path)


def frame_at(path, i):
    """(point, right-vector, heading) at path index i; right points east."""
    a = path[max(0, i - 1)]
    b = path[min(len(path) - 1, i + 1)]
    tx, ty = b[0] - a[0], b[1] - a[1]
    ln = math.hypot(tx, ty) or 1.0
    tx, ty = tx / ln, ty / ln
    return path[i], (ty, -tx), math.atan2(ty, tx)


def box_at(asm, role, path, i, east, z, size_along, size_east, height, extra_along=0.0):
    """A box aligned with the path: `east` = offset east of the centreline, z = base height."""
    p, right, rot = frame_at(path, i)
    cx = p[0] + right[0] * east + math.cos(rot) * extra_along
    cy = p[1] + right[1] * east + math.sin(rot) * extra_along
    asm.box(role, (cx, cy, z + height * 0.5), (size_along, size_east, height), rot)
    return (cx, cy, z)


def _stairs(asm, path):
    """Flights of steps from the lawn up to the deck (every 24 m)."""
    run, step = 0.0, 24.0
    for i in range(len(path) - 1):
        run += math.dist(path[i][:2], path[i + 1][:2])
        if run >= step:
            run = 0.0
            _stair_flight(asm, path, i)


def _stair_flight(asm, path, i):
    """One flight of 6 steps, 3.5 m deep, 0.42 m rise."""
    steps = 6
    depth = (data.OFF_DECK - data.OFF_LAWN) / steps
    for k in range(steps):
        east = data.OFF_LAWN + (k + 0.5) * depth
        z = 0.06 + (k + 1) * (Z - 0.06) / steps
        box_at(asm, "granite", path, i, east, z - 0.3, 2.8, depth * 1.05, 0.3)


def _wash(asm, edge):
    """The blue/cyan light wash on the river face of the flood wall.

    Built as a ribbon with its own UVs (v = 0 at the water line, 1 at the coping) so the
    emission gradient runs from #1E8BFF up to #29D3FF."""
    bm = asm.loose_bm("flood")
    layer = bm.loops.layers.uv.new("UVMap")
    z0, z1 = data.WATER_Y - 0.2, 2.40
    n = len(edge)
    rings = []
    run = 0.0
    for i, p in enumerate(edge):
        if i:
            run += math.dist(edge[i - 1][:2], p[:2])
        rings.append((p, run))
    for i in range(n - 1):
        (pa, ua), (pb, ub) = rings[i], rings[i + 1]
        a0 = bm.verts.new((pa.x, pa.y, z0))
        a1 = bm.verts.new((pa.x, pa.y, z1))
        b0 = bm.verts.new((pb.x, pb.y, z0))
        b1 = bm.verts.new((pb.x, pb.y, z1))
        f = bm.faces.new((a0, b0, b1, a1))
        # one 6 m curtain module per texture repeat
        for loop, uvv in zip(f.loops, ((ua / 6.0, 0.0), (ub / 6.0, 0.0),
                                       (ub / 6.0, 1.0), (ua / 6.0, 1.0))):
            loop[layer].uv = uvv
