"""Geometry helpers for SKYRUSH landmarks (unit-owned). Metres, Z up, +Y forward.

Everything returns bmesh fragments or objects; the builders in this package own
the composition. Core lib/geo.py provides sweep/loft/box/cylinder - this module
adds the landmark-specific solids (lathe, prism, tapered tubes, plan polygons).
"""
import math
import os

import bmesh
from mathutils import Vector

import bpy

from lib import common, export, geo, uv
from lmplans import (arc_pts, loft_plans, octagon, rect, resample_closed,
                    rounded_tri, rot, scale_plan)


# ------------------------------------------------------------------ anchors
ANCHORS = {
    "oriental_pearl": (637.5, -634.9),
    "pearl_ring": (748.0, -488.8),
    "jin_mao": (1133.0, -199.8),
    "swfc": (1262.2, -136.0),
    "shanghai_tower": (1122.8, -42.5),
    "dragon_pillar": (-1299.0, 687.0),
    "nanpu_mid": (1330.0, 1430.0),
    "nanpu_tower_w": (1139.4, 1338.2),
    "nanpu_tower_e": (1520.6, 1521.8),
    "waibaidu": (-140.0, -966.0),
    "lupu": (-300.0, 2900.0),
    "lujiazui_core": (748.0, -488.8),
}

# bridges are modelled in a local frame: origin at the anchor, +Y along the deck
BRIDGE_FRAMES = {
    "nanpu_bridge": {"axis": (0.901, 0.434), "rotation_y": -2.0203},
    "waibaidu_bridge": {"axis": (0.145, -0.989), "rotation_y": -0.1456},
    "lupu_bridge_far": {"axis": (1.0, 0.0), "rotation_y": -math.pi / 2.0},
}


# ------------------------------------------------------------------ objects
def obj(name, bm, col, mat=None):
    o = common.mesh_object(name, bm, col, mat)
    return o


def empty(name, loc, direction=(0.0, 1.0, 0.0), col=None, size=0.5):
    """Marker empty (CONTRACTS 2): local +Y is the effect direction."""
    return common.empty(name, loc, direction=direction, col=col, size=size)


def triangulate_ngons(obj):
    """Turn n-gons into triangles so the exporter can compute tangents."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    ngons = [f for f in bm.faces if len(f.verts) > 4]
    if ngons:
        bmesh.ops.triangulate(bm, faces=ngons)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


_FONT_RATIO = {}


def _font_ratio(font_path):
    """How many Blender units of `size` one unit of real height gives.

    The CJK variable font does not fill its em box, so `curve.size` alone
    would give 1.3 m tall characters for a requested 4 m. This probes the
    font once and returns the correction factor."""
    key = font_path or ""
    if key in _FONT_RATIO:
        return _FONT_RATIO[key]
    cu = bpy.data.curves.new("_font_probe", type='FONT')
    cu.body = "南浦大桥"
    cu.size = 1.0
    if font_path and os.path.exists(font_path):
        cu.font = bpy.data.fonts.load(font_path)
    ob = bpy.data.objects.new("_font_probe", cu)
    bpy.context.scene.collection.objects.link(ob)
    ctx = {"active_object": ob, "selected_editable_objects": [ob], "object": ob}
    with bpy.context.temp_override(**ctx):
        bpy.ops.object.convert(target='MESH')
    ob = bpy.data.objects.get("_font_probe")
    ys = [v.co.y for v in ob.data.vertices] if ob else []
    height = (max(ys) - min(ys)) if ys else 1.0
    if ob:
        bpy.data.objects.remove(ob, do_unlink=True)
    _FONT_RATIO[key] = (1.0 / height) if height > 1e-6 else 1.0
    return _FONT_RATIO[key]


def text_mesh(name, body, size, font_path, col, extrude=0.12, align='CENTER'):
    """Chinese/latin sign text as real geometry (font: Noto Sans SC, OFL).

    `size` is the real character height in metres."""
    cu = bpy.data.curves.new(name, type='FONT')
    cu.body = body
    cu.size = size * _font_ratio(font_path)
    cu.extrude = extrude
    cu.align_x = align
    cu.align_y = 'CENTER'
    if font_path and os.path.exists(font_path):
        cu.font = bpy.data.fonts.load(font_path)
    ob = bpy.data.objects.new(name, cu)
    col.objects.link(ob)
    ctx = {"active_object": ob, "selected_editable_objects": [ob], "object": ob}
    with bpy.context.temp_override(**ctx):
        bpy.ops.object.convert(target='MESH')
    ob = bpy.data.objects.get(name) or ob
    return ob


def uv_spherical_metres(obj, radius):
    """UV in METRES on a sphere: U = arc length around, V = height (seam-safe per face)."""
    me = obj.data
    uv = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    two_pi = 2.0 * math.pi
    for poly in me.polygons:
        angles = []
        for li in poly.loop_indices:
            p = me.vertices[me.loops[li].vertex_index].co
            angles.append(math.atan2(p.y, p.x) % two_pi)
        if angles and max(angles) - min(angles) > math.pi:
            angles = [a + two_pi if a < math.pi else a for a in angles]
        for li, a in zip(poly.loop_indices, angles):
            p = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = (a * radius, p.z)
    return obj


def cylinder_mesh(radius, z0, z1, segs=48, cap_bottom=True, cap_top=True, uv_scale=(1.0, 1.0),
                 rows=1):
    """Cylinder with a seam-free cylindrical UV (U around, V up).

    `rows` splits the height into that many quads (for displacement relief)."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    rings = []
    for j in range(rows + 1):
        z = z0 + (z1 - z0) * j / float(rows)
        ring = []
        for i in range(segs + 1):
            a = 2.0 * math.pi * i / segs
            ring.append(bm.verts.new((radius * math.cos(a), radius * math.sin(a), z)))
        rings.append(ring)
    for j in range(rows):
        for i in range(segs):
            f = bm.faces.new((rings[j][i], rings[j][i + 1], rings[j + 1][i + 1], rings[j + 1][i]))
            u0 = i / float(segs) * uv_scale[0]
            u1 = (i + 1) / float(segs) * uv_scale[0]
            v0 = j / float(rows) * uv_scale[1]
            v1 = (j + 1) / float(rows) * uv_scale[1]
            f.loops[0][uvl].uv = (u0, v0)
            f.loops[1][uvl].uv = (u1, v0)
            f.loops[2][uvl].uv = (u1, v1)
            f.loops[3][uvl].uv = (u0, v1)
    if cap_bottom:
        f = bm.faces.new(list(reversed(rings[0][:-1])))
        for lp in f.loops:
            lp[uvl].uv = (0.5, 0.0)
    if cap_top:
        f = bm.faces.new(rings[-1][:-1])
        for lp in f.loops:
            lp[uvl].uv = (0.5, 1.0)
    bm.normal_update()
    for ring in rings:
        ring[-1].normal = ring[0].normal.copy()
    return bm


def finish(name, col, path=None):
    """Export the collection to game/assets/landmarks/<name>.glb.

    The export goes to a scratch file first and is only copied into the
    project when its bytes differ from the shipped glb: Godot re-imports
    every file whose mtime changes, and a rebuild must not touch the assets
    that did not change (the IMPORT-CHURN lead note)."""
    for o in col.all_objects:
        if o.type == "MESH":
            triangulate_ngons(o)
    path = path or os.path.join(common.GAME, "assets", "landmarks", "%s.glb" % name)
    tmp_dir = os.path.expanduser("~/m/skyrush/tmp/landmarks/export")
    os.makedirs(tmp_dir, exist_ok=True)
    tmp = os.path.join(tmp_dir, "%s.glb" % name)
    export.export_glb(tmp, collection=col, jpeg_quality=78)
    import texio
    texio.copy_if_changed(tmp, path)
    try:
        os.remove(tmp)
    except OSError:
        pass
    return path


# ------------------------------------------------------------------ solids
def lathe(profile, segments=32, cap_bottom=True, cap_top=True):
    """Revolve a (radius, z) profile around the Z axis. Returns a bmesh.

    The seam column is duplicated so a (u, v) UV map can run 0..1 without a
    reversed strip; the duplicated normals are copied so shading stays smooth."""
    bm = bmesh.new()
    rings = []
    for (r, z) in profile:
        if abs(r) < 1e-6:
            rings.append([bm.verts.new((0.0, 0.0, z))])
            continue
        ring = []
        for i in range(segments + 1):
            a = 2.0 * math.pi * i / segments
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    for ra, rb in zip(rings, rings[1:]):
        if len(ra) == 1 and len(rb) > 1:
            for i in range(segments):
                bm.faces.new((ra[0], rb[i + 1], rb[i]))
        elif len(rb) == 1 and len(ra) > 1:
            for i in range(segments):
                bm.faces.new((ra[i], ra[i + 1], rb[0]))
        elif len(ra) > 1 and len(rb) > 1:
            for i in range(segments):
                bm.faces.new((ra[i], ra[i + 1], rb[i + 1], rb[i]))
    if cap_bottom and len(rings[0]) > 2:
        bm.faces.new(list(reversed(rings[0][:-1])))
    if cap_top and len(rings[-1]) > 2:
        bm.faces.new(rings[-1][:-1])
    bm.normal_update()
    for ring in rings:
        if len(ring) > 2:
            ring[-1].normal = ring[0].normal.copy()
    return bm


def prism(poly2d, z0, z1, cap=True):
    """Extrude a closed 2D polygon (x, y) between two heights."""
    bm = bmesh.new()
    bot = [bm.verts.new((x, y, z0)) for (x, y) in poly2d]
    top = [bm.verts.new((x, y, z1)) for (x, y) in poly2d]
    n = len(poly2d)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    if cap:
        bm.faces.new(list(reversed(bot)))
        bm.faces.new(top)
    bm.normal_update()
    return bm


def tube(p0, p1, r0, r1=None, segments=8):
    """Tapered cylinder between two 3D points (cables, struts, masts)."""
    r1 = r0 if r1 is None else r1
    a, b = Vector(p0), Vector(p1)
    d = b - a
    length = d.length
    if length < 1e-6:
        return bmesh.new()
    bm = bmesh.new()
    rings = []
    for (p, r) in ((a, r0), (b, r1)):
        ring = []
        for i in range(segments):
            t = 2.0 * math.pi * i / segments
            ring.append(bm.verts.new((r * math.cos(t), r * math.sin(t), 0.0)))
        rings.append(ring)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                     matrix=Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix())
    for (p, ring) in zip((a, b), rings):
        for v in ring:
            v.co += p
    for i in range(segments):
        j = (i + 1) % segments
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[1])
    bm.normal_update()
    return bm


def box(center, size, rot_z=0.0):
    """Axis box as a standalone bmesh."""
    bm = bmesh.new()
    geo.box(bm, center, size, rot_z)
    return bm


def strut(p0, p1, w=0.2, h=0.2):
    """A rectangular member (box section) between two 3D points."""
    a, b = Vector(p0), Vector(p1)
    d = b - a
    length = d.length
    if length < 1e-6:
        return bmesh.new()
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    quat = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized())
    for v in bm.verts:
        v.co = quat @ Vector((v.co.x * w, v.co.y * h, v.co.z * length)) + (a + b) * 0.5
    bm.normal_update()
    return bm


def merge(*bms):
    """Append bmesh fragments into one bmesh."""
    out = bmesh.new()
    for bm in bms:
        vmap = {}
        for v in bm.verts:
            vmap[v] = out.verts.new(v.co)
        for f in bm.faces:
            try:
                out.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                pass
    out.normal_update()
    return out


def uv_project(obj, mode="spherical", zmin=0.0, zmax=1.0):
    """Assign a UV layer from object-space position (metres for planar modes)."""
    me = obj.data
    uv = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        p = obj.data.vertices[loop.vertex_index].co
        if mode == "spherical":
            u = (math.atan2(p.y, p.x) / (2.0 * math.pi)) % 1.0
            v = (p.z - zmin) / max(zmax - zmin, 1e-6)
        elif mode == "planar_xz":
            u, v = p.x, p.z
        else:
            u, v = p.x, p.y
        uv.data[loop.index].uv = (u, v)
    return obj


def assign_by_height(obj, bands, slot=1):
    """Give faces whose centre height falls in a band a different material slot.

    `bands` = [(z_lo, z_hi), ...]"""
    for poly in obj.data.polygons:
        z = poly.center.z
        for lo, hi in bands:
            if lo <= z <= hi:
                poly.material_index = slot
                break
    return obj


def sphere_profile(radius, z0, steps=28, bands=()):
    """(radius, z) profile of a sphere centred at z0 with optional raised bands.

    `bands` = [(z_of_band, half_width, bump)] - the profile bulges outward there."""
    cz = z0
    pts = []
    for i in range(steps + 1):
        t = math.pi * i / steps
        z = cz - radius * math.cos(t)
        r = radius * math.sin(t)
        for (bz, bw, bump) in bands:
            d = abs(z - bz)
            if d < bw:
                r += bump * (1.0 - d / bw) ** 0.6
        pts.append((max(r, 0.0), z))
    return pts


def sphere_band(radius, cz, bz, half_w, inner, outer, steps=6):
    """(radius, z) profile of a collar hugging a sphere: inner..outer proud of it."""
    pts = []
    for i in range(steps + 1):
        z = bz - half_w + 2.0 * half_w * i / steps
        r = math.sqrt(max(radius * radius - (z - cz) ** 2, 0.0))
        pts.append((r + inner, z))
    for i in range(steps, -1, -1):
        z = bz - half_w + 2.0 * half_w * i / steps
        r = math.sqrt(max(radius * radius - (z - cz) ** 2, 0.0))
        pts.append((r + outer, z))
    return pts




def aviation_beacon(col, name, x, y, z, mat, radius=0.75, segments=12):
    """A red aviation beacon (ART.md 11): a D 1.5 m emissive ball on the roof.

    Every beacon gets its OWN material, so the world unit can blink them at
    1 Hz with a per-tower phase."""
    bm = lathe([(0.0, z - radius * 0.8), (radius * 0.85, z - radius * 0.45),
                (radius, z), (radius * 0.85, z + radius * 0.45), (0.0, z + radius * 0.8)],
               segments)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(x, y, 0.0))
    o = obj(name, bm, col, mat)
    uv.box_uv(o)
    return o
