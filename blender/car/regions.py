"""Where the detachable panels and the panel-gap lines are (all numbers from the JSON).

Every region is a predicate on a face centre, so the panels can be split OUT of
the lead's shell (review #2). The gap lines are 3D polylines ON the skin, used to
bake the 4 mm panel-gap normal map (lead note 4, review #11).

No number is retyped here: the door cuts, the cowl / vent-hood / wing-edge lines,
the T-top lines, the rocker band and the headlamp position all come from
ref/roadster/roadster_loft.json.
"""
import math

from mathutils import Vector
from mathutils.bvhtree import BVHTree

from car import paths


# the material indices in the shell's material list; the lead's shell builder
# (lib/roadster_body.py) decides the order, so they are looked up at build time.
trim_index = 1
paint_index = 0


def _loft():
    return paths.loft()


def poly_contains(poly, p):
    """Point in polygon (even-odd rule); `poly` is a list of (a, b)."""
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > p[1]) != (yj > p[1]) and p[0] < (xj - xi) * (p[1] - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def door_poly():
    """The door outline in the (y, z) plane: front cut, sill, rear cut."""
    sp = _loft()["side_profile"]
    front = [tuple(p) for p in sp["door_front_cut"]]
    rear = [tuple(p) for p in sp["door_rear_cut"]]
    return front + [rear[-1], rear[0]]


def dlo_poly():
    """The side window (DLO) outline in the (y, z) plane."""
    sp = _loft()["side_profile"]
    top = [tuple(p) for p in sp["dlo_top"]]
    bot = [tuple(p) for p in sp["dlo_bottom"]]
    return top + list(reversed(bot))


def a_pillar_y(z):
    """The A-pillar line (the door's front edge) in the (y, z) plane."""
    sp = _loft()["side_profile"]
    (y0, z0), (y1, z1) = [tuple(p) for p in sp["door_front_cut"][:2]]
    if z <= z0:
        if abs(z0 - z1) < 1e-9:
            return y0
        return y0 + (z0 - z) * (y1 - y0) / (z0 - z1)
    return y0 - (z - z0) * 0.5          # above the cut the pillar leans back


def b_pillar_y(z):
    """The B-pillar line (the door's rear edge) in the (y, z) plane."""
    sp = _loft()["side_profile"]
    (y0, z0), (y1, z1) = [tuple(p) for p in sp["door_rear_cut"]]
    if z <= z0:
        if abs(z0 - z1) < 1e-9:
            return y0
        return y0 + (z0 - z) * (y1 - y0) / (z0 - z1)
    return y0 - (z - z0) * 0.5


def hood_half_width(y):
    """Half width of the vent hood at a given y (the hood_side_edge line)."""
    edge = _loft()["panel_lines"]["hood_side_edge"]
    (x0, y0), (x1, y1) = [tuple(p) for p in edge]
    t = (y - y0) / (y1 - y0) if abs(y1 - y0) > 1e-9 else 0.0
    return x0 + (x1 - x0) * t


def in_door(f, sign):
    """The door's flank skin: between the two cut lines, on one side."""
    sp = _loft()["side_profile"]
    c = f.calc_center_median()
    y, z = c.y, c.z
    if z < sp["door_front_cut"][-1][1] - 1e-6 or z > sp["door_front_cut"][0][1] + 1e-6:
        return False
    if abs(c.x) < 0.5:
        return False
    if f.normal.x * sign < 0.25:
        return False
    return b_pillar_y(z) <= y <= a_pillar_y(z)


def in_door_glass(f):
    """The side glass that belongs to the door (the DLO behind the A-pillar)."""
    c = f.calc_center_median()
    y, z = c.y, c.z
    if not poly_contains(dlo_poly(), (y, z)):
        return False
    if y < b_pillar_y(z) - 1e-6:
        return False
    return y <= a_pillar_y(z) + 1e-6


def in_hood(f):
    """The vent bonnet panel: between the cowl and the vent-hood line."""
    c = f.calc_center_median()
    pl = _loft()["panel_lines"]
    if not (pl["cowl_y"] - 1e-6 <= c.y <= pl["vent_hood_front_y"] + 1e-6):
        return False
    if f.normal.z < 0.3:
        return False
    return abs(c.x) <= hood_half_width(c.y) + 1e-6


def in_wing(f):
    """The stowed wing: the deck behind the wing's leading edge."""
    c = f.calc_center_median()
    y_edge = _loft()["panel_lines"]["wing_front_edge_y"]
    return c.y <= y_edge + 1e-6 and f.normal.z > 0.3


def in_skirt(f):
    """The black sill strip on one flank."""
    c = f.calc_center_median()
    r = _loft()["side_profile"]["rocker"]
    if not (r["y_to"] - 1e-6 <= c.y <= r["y_from"] + 1e-6):
        return False
    if not (r["black_sill_bottom_z"] - 1e-6 <= c.z <= r["white_lower_edge_z"] + 1e-6):
        return False
    if abs(c.x) < 0.5 or f.normal.z < -0.5:
        return False
    return f.material_index == trim_index


def in_bumper(f, front=True):
    """The black front fascia / rear valance.

    The black lower body is split at the rocker's ends (side_profile.rocker), so
    the three black parts (front bumper, sill skirts, rear valance) tile the
    black band without overlapping.
    """
    c = f.calc_center_median()
    r = _loft()["side_profile"]["rocker"]
    if f.normal.z < -0.5 or f.material_index != trim_index:
        return False
    if front:
        return c.y >= r["y_from"] - 1e-6
    return c.y <= r["y_to"] + 1e-6


def in_headlamp(f, sign):
    """The triangular headlamp flap on the fender tip."""
    c = f.calc_center_median()
    p = _loft()["parts"]["headlamps"]["pos"]
    d = Vector((c.x - sign * p[0], c.y - p[1], c.z - p[2]))
    return d.length < 0.17 and f.material_index == paint_index


def surface_x(bvh, y, z, sign):
    """X of the outer skin at (y, z) on one side, or None if the ray misses."""
    hit = bvh.ray_cast(Vector((3.0 * sign, y, z)), Vector((-float(sign), 0.0, 0.0)))
    return hit[0].x if hit[0] is not None else None


def surface_z(bvh, x, y):
    """Z of the upper skin at (x, y), or None if the ray misses."""
    hit = bvh.ray_cast(Vector((x, y, 3.0)), Vector((0.0, 0.0, -1.0)))
    return hit[0].z if hit[0] is not None else None
