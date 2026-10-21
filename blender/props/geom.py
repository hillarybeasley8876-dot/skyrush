"""Low level mesh primitives and UV mapping for the SKYRUSH props unit.

Frame (CONTRACTS.md §1): metres, Z up, +Y forward, +X right.
"""
import math

import bmesh
from mathutils import Euler, Matrix, Vector

from . import atlas

def cone(bm, center, r1, r2, depth, segments=12, axis="Z", cap=True):
    """Truncated cone (r1 at -depth/2, r2 at +depth/2) along X, Y or Z."""
    res = bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segments,
                                radius1=r1, radius2=r2, depth=depth)
    for v in res["verts"]:
        x, y, z = v.co
        if axis == "X":
            x, y, z = z, y, -x
        elif axis == "Y":
            x, y, z = x, z, -y
        v.co = Vector((center[0] + x, center[1] + y, center[2] + z))
    return res["verts"]


def tube(bm, p0, p1, r, segments=10, cap=True):
    """Cylinder between two arbitrary points (a pipe, a stay, a cable)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    length = d.length
    if length < 1e-6:
        return []
    res = bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segments,
                                radius1=r, radius2=r, depth=length)
    quat = d.to_track_quat("Z", "Y")
    mat = Matrix.Translation(p0 + d * 0.5) @ quat.to_matrix().to_4x4()
    for v in res["verts"]:
        v.co = mat @ v.co
    return res["verts"]


def ring(bm, center, radius, thickness, height, segments=24, axis="Z"):
    """Flat annulus (a tyre, a halo, a light ring) extruded `height` along `axis`."""
    inner = radius - thickness * 0.5
    outer = radius + thickness * 0.5
    verts = []
    for z in (-height * 0.5, height * 0.5):
        for r in (inner, outer):
            for i in range(segments):
                a = 2.0 * math.pi * i / segments
                verts.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
    n = segments
    bi0, bo0, bi1, bo1 = verts[0:n], verts[n:2 * n], verts[2 * n:3 * n], verts[3 * n:4 * n]
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bi0[i], bo0[i], bo0[j], bi0[j]))
        bm.faces.new((bo1[i], bi1[i], bi1[j], bo1[j]))
        bm.faces.new((bi0[i], bi0[j], bi1[j], bi1[i]))
        bm.faces.new((bo0[j], bo0[i], bo1[i], bo1[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for v in verts:
        if axis == "X":
            v.co = Vector((v.co.z, v.co.y, -v.co.x))
        elif axis == "Y":
            v.co = Vector((v.co.x, v.co.z, -v.co.y))
        v.co += Vector(center)
    return verts


def torus(bm, center, major_r, minor_r, major_seg=24, minor_seg=6, axis="Z"):
    """A torus (a tyre): a ring of `major_seg` segments with `minor_seg` sides."""
    verts = []
    for i in range(major_seg):
        a = 2.0 * math.pi * i / major_seg
        ring = []
        for j in range(minor_seg):
            b = 2.0 * math.pi * j / minor_seg
            r = major_r + minor_r * math.cos(b)
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a),
                                      minor_r * math.sin(b))))
        verts.append(ring)
    for i in range(major_seg):
        nxt = verts[(i + 1) % major_seg]
        cur = verts[i]
        for j in range(minor_seg):
            k = (j + 1) % minor_seg
            bm.faces.new((cur[j], nxt[j], nxt[k], cur[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for v in bm.verts:
        if axis == "X":
            v.co = Vector((v.co.z, v.co.y, -v.co.x))
        elif axis == "Y":
            v.co = Vector((v.co.x, v.co.z, -v.co.y))
        v.co += Vector(center)
    return verts


def sign_quad(bm, width, height, uv_rect=(0.0, 0.0, 1.0, 1.0)):
    """A single quad in the XZ plane at y = 0, normal -Y, with an explicit UV rect."""
    hw, hh = width * 0.5, height * 0.5
    v = [bm.verts.new(p) for p in ((-hw, 0, -hh), (hw, 0, -hh), (hw, 0, hh), (-hw, 0, hh))]
    face = bm.faces.new((v[0], v[1], v[2], v[3]))
    layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    u0, v0, u1, v1 = uv_rect
    for loop, co in zip(face.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
        loop[layer].uv = co
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return v


def add_quad(bm, width, height, center=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0),
             uv_rect=(0.0, 0.0, 1.0, 1.0), uv_scale=None):
    """Append one UV-mapped quad to an existing bmesh, transformed into place.

    `uv_scale` multiplies the written UVs: pass (width, height) to write the
    quad's size in metres, so a surface tile keeps its detail scale.
    """
    hw, hh = width * 0.5, height * 0.5
    verts = [bm.verts.new(p) for p in ((-hw, 0.0, -hh), (hw, 0.0, -hh), (hw, 0.0, hh),
                                       (-hw, 0.0, hh))]
    face = bm.faces.new((verts[0], verts[1], verts[2], verts[3]))
    layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    u0, v0, u1, v1 = uv_rect
    if uv_scale is not None:
        su, sv = uv_scale
        u0, u1, v0, v1 = u0 * su, u1 * su, v0 * sv, v1 * sv
    for loop, co in zip(face.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
        loop[layer].uv = co
    mat = Matrix.Translation(Vector(center)) @ Euler(rot, "XYZ").to_matrix().to_4x4()
    for v in verts:
        v.co = mat @ v.co
    return face


def sphere(bm, center, radius, subdivisions=2, scale=(1.0, 1.0, 1.0)):
    """Icosphere (a globe, a bollard cap, a planter shrub ball)."""
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    for v in res["verts"]:
        v.co = Vector((center[0] + v.co.x * scale[0], center[1] + v.co.y * scale[1],
                       center[2] + v.co.z * scale[2]))
    return res["verts"]


def _axis_ends(center, depth, axis):
    """The two ends of a cylinder along the given axis."""
    c = Vector(center)
    half = depth * 0.5
    if axis == "X":
        return c - Vector((half, 0.0, 0.0)), c + Vector((half, 0.0, 0.0))
    if axis == "Y":
        return c - Vector((0.0, half, 0.0)), c + Vector((0.0, half, 0.0))
    return c - Vector((0.0, 0.0, half)), c + Vector((0.0, 0.0, half))


def cyl_uv(obj, axis_vec, radius, length, tile_m=None):
    """Cylindrical UVs in the LOCAL space of the mesh.

    The box projection in lib/uv.py stretches a vertical cylinder into horizontal
    bands, so poles and columns get this instead.

    `axis_vec` is the unit vector of the cylinder axis in the LOCAL space of
    the mesh (the mesh is always built along its own axis and then rotated),
    so the cap test and the projection stay in one space.

    With `tile_m` the u is closed on the seam: the round number of tile repeats
    that fits around the circumference, so the texture does not cut the tube in
    the middle of a tile.
    """
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    axis = Vector(axis_vec).normalized()
    ref = Vector((0.0, 0.0, 1.0)) if abs(axis.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    u_axis = axis.cross(ref).normalized()
    v_axis = u_axis.cross(axis).normalized()
    centre = Vector((0.0, 0.0, 0.0))
    repeats = 1
    if tile_m:
        repeats = max(1, int(round(math.tau * radius / tile_m)))
    for face in bm.faces:
        if abs(face.normal.dot(axis)) > 0.85:      # cap: planar projection
            for loop in face.loops:
                p = loop.vert.co - centre
                if tile_m:
                    loop[layer].uv = (p.dot(u_axis) / tile_m, p.dot(v_axis) / tile_m)
                else:
                    loop[layer].uv = (p.dot(u_axis), p.dot(v_axis))
            continue
        for loop in face.loops:
            p = loop.vert.co - centre
            t = p.dot(axis)
            radial = p - axis * t
            ang = math.atan2(radial.dot(v_axis), radial.dot(u_axis))
            if tile_m:
                loop[layer].uv = (ang / math.tau * repeats, t / tile_m)
            else:
                loop[layer].uv = (ang * radius, t)
    bm.to_mesh(me)
    bm.free()
    return obj


def scale_uv(obj, s):
    """Scale the UVs of an object (metre coordinates -> tile units)."""
    me = obj.data
    layer = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    for data in layer.data:
        data.uv = (data.uv[0] * s, data.uv[1] * s)
    return obj


def set_tint(obj, colour, name="Col"):
    """Write a flat colour into a CORNER colour attribute (the vertex tint).

    Every part of every prop carries the attribute, so joining parts never
    loses it and the tint survives into the exported COLOR_0.
    """
    me = obj.data
    attr = me.color_attributes.get(name)
    if attr is None:
        attr = me.color_attributes.new(name=name, type="FLOAT_COLOR", domain="CORNER")
    rgba = (colour[0], colour[1], colour[2], 1.0)
    for i in range(len(attr.data)):
        attr.data[i].color = rgba
    return obj


def lathe(bm, profile, segments=16, centre=(0.0, 0.0, 0.0)):
    """Revolve a (radius, z) profile around Z: a bud, a bollard, a shade."""
    verts = [bm.verts.new((r, 0.0, z)) for r, z in profile]
    edges = [bm.edges.new((verts[i], verts[i + 1])) for i in range(len(verts) - 1)]
    bmesh.ops.spin(bm, geom=verts + edges, cent=(0.0, 0.0, 0.0), axis=(0.0, 0.0, 1.0),
                   dvec=(0.0, 0.0, 0.0), angle=math.tau, steps=segments, use_duplicate=False)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    for v in bm.verts:
        v.co = Vector((v.co.x + centre[0], v.co.y + centre[1], v.co.z + centre[2]))
    return bm


def add_card(bm, centre, outward, width, height, uv_rect, up=(0.0, 0.0, 1.0)):
    """A quad with an explicit outward-facing normal (a leaf cluster card)."""
    c = Vector(centre)
    n = Vector(outward).normalized()
    u = Vector(up)
    u = (u - n * u.dot(n))
    if u.length < 1e-5:
        u = Vector((1.0, 0.0, 0.0))
    u = u.normalized()
    r = u.cross(n).normalized()
    hw, hh = width * 0.5, height * 0.5
    verts = [bm.verts.new(c - r * hw - u * hh), bm.verts.new(c + r * hw - u * hh),
             bm.verts.new(c + r * hw + u * hh), bm.verts.new(c - r * hw + u * hh)]
    face = bm.faces.new(verts)
    layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    u0, v0, u1, v1 = uv_rect
    for loop, co in zip(face.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
        loop[layer].uv = co
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return face


def unit_uv(obj):
    """Map the object's UVs to 0..1 over its bounding box (a whole-object image)."""
    me = obj.data
    layer = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    co = [v.co for v in me.vertices]
    lo = [min(c[i] for c in co) for i in range(3)]
    hi = [max(c[i] for c in co) for i in range(3)]
    span = [max(1e-5, hi[i] - lo[i]) for i in range(3)]
    for poly in me.polygons:
        ax = max(range(3), key=lambda i: abs(poly.normal[i]))
        ia, ib = {0: (1, 2), 1: (0, 2), 2: (0, 1)}[ax]
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            layer.data[li].uv = ((v[ia] - lo[ia]) / span[ia], (v[ib] - lo[ib]) / span[ib])
    return obj


def map_strip_uv(obj, length, board, axis=1):
    """Map a bar so the board's U runs along its length (a barrier arm).

    The board's V runs across the bar, so the whole band pattern shows on the
    long faces instead of a single row of texels.
    """
    u0, v0, u1, v1 = atlas.sign_uv(board)
    me = obj.data
    layer = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    lo = [0.0, 0.0, 0.0]
    hi = [0.0, 0.0, 0.0]
    for v in me.vertices:
        for i in range(3):
            lo[i] = min(lo[i], v.co[i])
            hi[i] = max(hi[i], v.co[i])
    for poly in me.polygons:
        ax = max(range(3), key=lambda i: abs(poly.normal[i]))
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            if ax == axis:                       # the end caps
                u, w = 0.03, 0.5
            else:
                u = abs(v[axis]) / length
                cross = 3 - ax - axis             # the third axis
                span = max(hi[cross] - lo[cross], 1e-6)
                w = 0.12 + 0.76 * (v[cross] - lo[cross]) / span
            layer.data[li].uv = (u0 + u * (u1 - u0), v0 + w * (v1 - v0))
    return obj


def map_rect_uv(obj, u0, v0, u1, v1):
    """Map the object's 0..1 UVs into a rectangle of the sign atlas."""
    me = obj.data
    layer = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        u, v = layer.data[loop.index].uv
        layer.data[loop.index].uv = (u0 + u * (u1 - u0), v0 + v * (v1 - v0))
    return obj


