"""Suspension: double wishbone, coilover and upright at each corner.

Only the inboard half of each corner is modelled (the wheel covers the rest);
it is visible through the open wheel arches and adds the mechanical detail the
reveal car's twin-wishbone front end has (dossier §1, photo 25).
"""
import math

import bmesh
from mathutils import Vector

from car import materials, paths, shapes
from lib import common

M_DARK, M_METAL = 0, 0


def _helix(p0, p1, turns, radius, samples):
    """Points of a helical spring axis between p0 and p1."""
    a, b = Vector(p0), Vector(p1)
    axis = (b - a)
    length = axis.length
    axis.normalize()
    ref = Vector((0.0, 0.0, 1.0))
    if abs(axis.dot(ref)) > 0.9:
        ref = Vector((1.0, 0.0, 0.0))
    u = (ref - axis * ref.dot(axis)).normalized()
    v = axis.cross(u).normalized()
    pts = []
    for i in range(samples + 1):
        t = i / samples
        ang = 2.0 * math.pi * turns * t
        p = a + axis * (length * t) + (u * math.cos(ang) + v * math.sin(ang)) * radius
        pts.append(tuple(p))
    return pts


def build_suspension(col, root):
    """Wishbones, coilover and upright for the four corners."""
    d = paths.loft()["wheels"]
    steel = materials.get("M_Suspension")
    for key, tag in (("front", "F"), ("rear", "R")):
        w = d[key]
        cx, cy, cz = w["centre"]
        for sign, sname in ((1, "R"), (-1, "L")):
            bm = bmesh.new()
            hub_x = sign * (cx - 0.145)
            # upright
            shapes.box(bm, (hub_x, cy, cz), (0.05, 0.09, 0.30), M_DARK)
            shapes.box(bm, (hub_x - sign * 0.02, cy, cz + 0.14), (0.07, 0.12, 0.06), M_DARK)
            # lower and upper wishbone (tapered plates)
            for z0, z1, w0 in ((cz - 0.10, cz - 0.11, 0.07), (cz + 0.13, cz + 0.16, 0.05)):
                shapes.box(bm, (sign * (cx - 0.30), cy, (z0 + z1) / 2.0),
                           (0.34, w0, 0.035), M_DARK)
            # coilover: damper body + helical spring
            top = (sign * (cx - 0.26), cy - 0.10, cz + 0.30)
            bottom = (sign * (cx - 0.24), cy - 0.02, cz - 0.16)
            shapes.tube(bm, [top, bottom], 0.026, 8, M_METAL)
            shapes.tube(bm, _helix(top, bottom, 10, 0.055, 120), 0.011, 8, M_DARK)
            # brake line from the caliper to the upright
            shapes.tube(bm, [(sign * (cx - 0.10), cy + 0.06, cz + 0.10),
                             (sign * (cx - 0.22), cy + 0.02, cz + 0.16),
                             (sign * (cx - 0.32), cy - 0.04, cz + 0.22)], 0.006, 6, M_METAL)
            ob = common.mesh_object("Suspension_%s%s" % (tag, sname), bm, col)
            ob.data.materials.append(steel)
            paths.parent_to(ob, root)
