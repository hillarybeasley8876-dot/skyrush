"""Wheel wells for lofted car bodies (core-owned): exact boolean pockets + black arch liners.

    from lib import wells
    spec = [wells.Well(y=1.49, z=0.347, r=0.39, x_in=0.55, x_side=0.93), ...]   # one per axle
    wells.cut(body, spec, trim_mat)                     # both sides, pocket walls get trim_mat
    liners = wells.liners("ArchLiners", spec, col, trim_mat, clad=0.0)

The cutter is a cylinder along X from x_in (the inner wall of the pocket) to beyond the body side;
the boolean transfers its material, so the pocket reads as a black wheel well. The liner is an
arc shell inside the pocket plus a thin lip (or, with clad > 0, a wide plastic arch cladding) on
the body side, so the opening has a visible edge instead of a raw cut.
"""
import math
from dataclasses import dataclass

import bmesh
import bpy
from mathutils import Vector

from . import common


@dataclass
class Well:
    y: float          # axle station
    z: float          # axle height (wheel radius for a car on the ground)
    r: float          # arch radius (wheel radius + clearance)
    x_in: float       # inner wall of the pocket (|x|)
    x_side: float     # body side at the arch (|x|), where the lip sits


def _cutter(name, w, x0, x1, segments=72):
    bm = bmesh.new()
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=w.r, radius2=w.r,
                                depth=abs(x1 - x0))
    mid = (x0 + x1) * 0.5
    for v in res["verts"]:
        x, y, z = v.co
        v.co = Vector((mid + z, w.y + x, w.z + y))  # cone axis Z -> world X
    obj = common.mesh_object(name, bm)
    obj.hide_render = True
    return obj


def cut(body, spec, trim_mat, x_out=1.6):
    """Cut both pockets of every well out of `body` (modifiers applied into a new mesh)."""
    cutters = []
    for i, w in enumerate(spec):
        for side in (1, -1):
            x0, x1 = side * w.x_in, side * x_out
            c = _cutter("Cut_%d_%d" % (i, side), w, min(x0, x1), max(x0, x1))
            c.data.materials.append(trim_mat)
            mod = body.modifiers.new("Well_%d_%d" % (i, side), "BOOLEAN")
            mod.operation, mod.solver, mod.object = "DIFFERENCE", "EXACT", c
            mod.material_mode = "TRANSFER"
            cutters.append(c)
    bake_modifiers(body)
    for c in cutters:
        bpy.data.objects.remove(c)


def bake_modifiers(obj):
    """Replace obj's mesh by its evaluated mesh (all modifiers applied), without operators."""
    dg = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    old = obj.data
    obj.modifiers.clear()
    obj.data = mesh
    bpy.data.meshes.remove(old)


def liners(name, spec, col, trim_mat, lip=0.016, clad=0.0, arc_deg=(-12, 192), step_deg=6):
    """Inner arc shells + lips (or claddings `clad` metres wide) for every well, both sides."""
    bm = bmesh.new()
    arc = [math.radians(a) for a in range(arc_deg[0], arc_deg[1] + 1, step_deg)]
    rim = max(lip, clad)
    for w in spec:
        for side in (1, -1):
            def ring(x, rr):
                return [bm.verts.new((side * x, w.y + rr * math.cos(a), w.z + rr * math.sin(a))) for a in arc]
            inner = ring(w.x_in, w.r)
            outer = ring(w.x_side - 0.01, w.r)
            lip_o = ring(w.x_side + 0.008, w.r + rim)
            for i in range(len(arc) - 1):
                q = (inner[i], inner[i + 1], outer[i + 1], outer[i])
                bm.faces.new(q if side < 0 else tuple(reversed(q)))
                lq = (outer[i], outer[i + 1], lip_o[i + 1], lip_o[i])
                bm.faces.new(lq if side > 0 else tuple(reversed(lq)))
    return common.mesh_object(name, bm, col, trim_mat)
