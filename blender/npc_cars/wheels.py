"""Wheels for the NPC fleet (unit: npc_cars).

Each wheel is one object (tyre + rim + brake disc + caliper) with its origin
at the wheel centre and its spin axis along X (CONTRACTS.md §6).

The rim is a five twin spoke alloy face: the spoke faces stand 2 cm proud of
the barrel, the gaps between the spokes show the brake disc and its caliper.
The tyre is a revolved profile with rounded shoulders; the tread and the
sidewall lettering come from the shared normal map.
"""
import math

import bmesh
import bpy
from mathutils import Vector

from lib import common, geo

from . import meshutil

SPOKES = 5                # twin spokes per wheel
SPOKE_HALF = 0.11         # the angular half width of one spoke
PAIR_OFFSET = 0.19        # the angular distance between the twins of a spoke
SPOKE_DEPTH = 0.020       # the spoke face stands this far proud of the barrel
RIM_FACE_RATIO = 0.66     # the rim radius as a fraction of the tyre radius


def _revolve(profile, segments, offset=(0.0, 0.0, 0.0)):
    """Revolve a profile of (x, radius) pairs around the X axis -> bmesh."""
    bm = bmesh.new()
    rings = []
    for s in range(segments):
        a = 2.0 * math.pi * s / segments
        ca, sa = math.cos(a), math.sin(a)
        ring = []
        for x, r in profile:
            ring.append(bm.verts.new((x + offset[0], r * ca + offset[1],
                                       r * sa + offset[2])))
        rings.append(ring)
    n = len(profile)
    for s in range(segments):
        a, b = rings[s], rings[(s + 1) % segments]
        for k in range(n):
            k2 = (k + 1) % n
            bm.faces.new((a[k], a[k2], b[k2], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _tyre_profile(radius, width, rim_r):
    """Cross-section of the tyre: inner bead -> shoulder -> tread -> bead.

    The shoulders are rounded, so the tyre does not read as a black disc.
    """
    hw = width * 0.5
    return [
        (-hw, rim_r), (-hw, rim_r + 0.020), (-hw + 0.020, radius - 0.060),
        (-hw + 0.045, radius - 0.020), (-hw + 0.070, radius - 0.004),
        (-hw + 0.090, radius), (hw - 0.090, radius),
        (hw - 0.070, radius - 0.004), (hw - 0.045, radius - 0.020),
        (hw - 0.020, radius - 0.060), (hw, rim_r + 0.020), (hw, rim_r),
    ]


def _set_tyre_uv(obj, width):
    """u = around the circumference, v = across the section (the normal map)."""
    me = obj.data
    uv_layer = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            a = math.atan2(v.z, v.y)
            u = (a / (2.0 * math.pi)) % 1.0
            t = (v.x + width * 0.5) / max(width, 1e-5)
            uv_layer.data[li].uv = (u, t)


def _spoke(bm, x_face, angle, r0, r1, w0, w1):
    """One tapered spoke of the rim face (a flat wedge with a real depth)."""
    v = []
    for px in (x_face, x_face - SPOKE_DEPTH):
        for rr, ww in ((r0, w0), (r1, w1)):
            for s in (-1, 1):
                ang = angle + s * SPOKE_HALF
                v.append(bm.verts.new((px, rr * math.cos(ang), rr * math.sin(ang))))
    bm.faces.new((v[0], v[1], v[3], v[2]))
    bm.faces.new((v[4], v[6], v[7], v[5]))
    bm.faces.new((v[0], v[2], v[6], v[4]))
    bm.faces.new((v[1], v[5], v[7], v[3]))
    bm.faces.new((v[0], v[4], v[5], v[1]))
    bm.faces.new((v[2], v[3], v[7], v[6]))


def _tube(bm, x0, x1, r_in, r_out, segments=28):
    """A hollow ring (a tube wall) around the X axis."""
    rings = []
    for x in (x0, x1):
        for r in (r_in, r_out):
            rings.append([bm.verts.new((x, r * math.cos(2.0 * math.pi * s / segments),
                                        r * math.sin(2.0 * math.pi * s / segments)))
                          for s in range(segments)])
    a0, a1, b0, b1 = rings
    for s in range(segments):
        t = (s + 1) % segments
        bm.faces.new((a0[s], a0[t], a1[t], a1[s]))      # the outer wall
        bm.faces.new((b0[s], b0[t], b1[t], b1[s]))      # the inner wall
        bm.faces.new((a1[s], a1[t], b1[t], b1[s]))      # the front rim
        bm.faces.new((b0[s], b0[t], a0[t], a0[s]))      # the back rim
    return bm


def _rim_bmesh(face_x, rim_r, width):
    """The rim: the barrel, five twin spokes, the outer lip and the hub cap."""
    bm = bmesh.new()
    # the barrel: a hollow tube, so the spokes and the brake disc show through
    _tube(bm, face_x - width * 0.58, face_x - width * 0.02,
          rim_r - 0.018, rim_r, 28)
    # the outer lip: a narrow ring that closes the barrel
    _tube(bm, face_x - 0.016, face_x, rim_r - 0.016, rim_r, 28)
    for i in range(SPOKES):
        angle = 2.0 * math.pi * i / SPOKES
        for side in (-1, 1):
            _spoke(bm, face_x, angle + side * PAIR_OFFSET,
                   rim_r * 0.20, rim_r * 0.97, rim_r * 0.115, rim_r * 0.060)
    # the hub cap
    geo.cylinder(bm, (face_x - 0.012, 0, 0), rim_r * 0.24, 0.030, 18, axis="X")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _brake_bmesh(face_x, rim_r):
    """The brake disc and its caliper, seen through the gaps of the spokes."""
    bm = bmesh.new()
    geo.cylinder(bm, (face_x - 0.055, 0, 0), rim_r * 0.70, 0.024, 22, axis="X")
    geo.box(bm, (face_x - 0.055, -rim_r * 0.58, rim_r * 0.20),
            (0.055, rim_r * 0.26, rim_r * 0.40))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_wheel(name, spec, mats, col, x, y, side, spokes=SPOKES):
    """One wheel object; origin at the wheel centre."""
    return build_wheel_at(name, spec["wr"], spec["ww"], mats, col, x, y,
                          face=-1.0 if x < 0.0 else 1.0)


def build_wheel_at(name, radius, width, mats, col, x, y, face=1.0, inner=0.0):
    """One wheel object; origin at the wheel centre.

    `face` is the side the rim face points to (+1 = +X), so the left wheels
    show their spokes outwards as well.  `inner` adds a second tyre inboard
    (the truck's tandem rear axle).
    """
    rim_r = radius * RIM_FACE_RATIO
    face_x = face * (width * 0.5 - 0.012)
    parts = []
    tyre = _object(name, _revolve(_tyre_profile(radius, width, rim_r), 32),
                   mats["wheel_tyre"], col)
    _set_tyre_uv(tyre, width)
    meshutil.shade_smooth(tyre, 42.0)
    parts.append(tyre)
    if inner:
        dual = _object(name + "_dual",
                       _revolve(_tyre_profile(radius, width, rim_r), 32),
                       mats["wheel_tyre"], col)
        _set_tyre_uv(dual, width)
        meshutil.shade_smooth(dual, 42.0)
        dual.location = (inner, 0.0, 0.0)
        parts.append(dual)
    rim = _object(name + "_rim", _rim_bmesh(face_x, rim_r, width),
                  mats["wheel_rim"], col)
    meshutil.shade_smooth(rim, 35.0)
    parts.append(rim)
    brake = _object(name + "_brake", _brake_bmesh(face_x, rim_r),
                    mats["trim"], col)
    meshutil.shade_smooth(brake, 35.0)
    parts.append(brake)
    wheel = common.join(parts, name)
    meshutil.triangulate(wheel)
    wheel.location = (x, y, radius)
    return wheel


def _object(name, bm, material, col):
    """A mesh object from a bmesh with one material."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    common.link(obj, col)
    me.materials.append(material)
    return obj
