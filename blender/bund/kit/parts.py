"""Solid-of-revolution and prism helpers for the Bund kit (bund unit).

Everything works in the building's local frame: +X = facade normal (towards the river),
+Y = south along the row, +Z = up, origin at the centre of the facade on the ground.
"""
import math

import bmesh
import bpy

from lib import geo



def merge(dst, src):
    """Append the geometry of bmesh `src` into bmesh `dst` and free `src`."""
    me = bpy.data.meshes.new("_bund_tmp")
    src.to_mesh(me)
    src.free()
    dst.from_mesh(me)
    bpy.data.meshes.remove(me)
    return dst


def prism_trim(dst, profile, y0, y1, band, tile=2.0, x_off=0.0, z_off=0.0):
    """Extrude a profile along Y with the trim sheet's UVs (the cornices, the sills)."""
    from .trim_uv import prism_trim as _prism_trim
    return _prism_trim(dst, profile, y0, y1, band, tile, x_off, z_off)


def lathe_trim(dst, profile, segments, center, band):
    """Revolve a profile around Z with the trim sheet's UVs (the capitals)."""
    from .trim_uv import lathe_trim as _lathe_trim
    return _lathe_trim(dst, profile, segments, center, band)


def _axis_dir(axis):
    """The unit vector of an axis (used to give the dial discs their thickness)."""
    return {"X": (1.0, 0.0, 0.0), "Y": (0.0, 1.0, 0.0), "Z": (0.0, 0.0, 1.0)}[axis]


def prism(dst, profile, y0, y1, x_off=0.0, z_off=0.0):
    """Extrude a closed 2D profile [(x, z), ...] along Y from y0 to y1 into `dst`."""
    sec0 = [(x + x_off, y0, z + z_off) for (x, z) in profile]
    sec1 = [(x + x_off, y1, z + z_off) for (x, z) in profile]
    return merge(dst, geo.loft([sec0, sec1], closed_sections=True, cap_start=True, cap_end=True))


def prism_x(dst, profile, x0, x1, y_off=0.0, z_off=0.0):
    """Extrude a closed 2D profile [(y, z), ...] along X from x0 to x1 into `dst`.

    The counterpart of `prism`: a pediment or an arch head is drawn in the (y, z) plane
    of the elevation and pushed out of the wall along X."""
    sec0 = [(x0, y + y_off, z + z_off) for (y, z) in profile]
    sec1 = [(x1, y + y_off, z + z_off) for (y, z) in profile]
    return merge(dst, geo.loft([sec0, sec1], closed_sections=True, cap_start=True, cap_end=True))


def lathe(dst, profile, segments=16, center=(0.0, 0.0, 0.0)):
    """Revolve a 2D profile [(radius, z), ...] around the Z axis at `center`.

    The profile is closed along the axis if it does not already reach it, so the revolved
    solid is watertight: no open slot around the revolve and no stray cap. The last
    slice is welded onto the first (the UV seam is the sheet's own)."""
    prof = list(profile)
    if prof[0][0] > 1e-6:
        prof.insert(0, (0.0, prof[0][1]))
    if prof[-1][0] > 1e-6:
        prof.append((0.0, prof[-1][1]))
    sections = []
    for i in range(segments + 1):
        a = 2.0 * math.pi * i / segments
        ca, sa = math.cos(a), math.sin(a)
        sections.append([(center[0] + r * ca, center[1] + r * sa, center[2] + z)
                         for (r, z) in prof])
    out = geo.loft(sections, closed_sections=True, cap_start=False, cap_end=False)
    bmesh.ops.remove_doubles(out, verts=out.verts, dist=1e-4)
    return merge(dst, out)


def chamfered_box(dst, center, size, chamfer=0.075, axis="X", depth=None):
    """A box whose face on `axis` (+X or +Y) is chamfered on all four arrises.

    The chamfer insets the face by `chamfer` and pulls it back by `depth`, so the joint
    between two blocks reads as a V-groove of the given width and depth - the rustication
    of the Bund's base course."""
    c = min(chamfer, size[0] * 0.45, size[1] * 0.45, size[2] * 0.45)
    d = c if depth is None else min(depth, size[0] * 0.45)
    cx, cy, cz = center
    sx, sy, sz = size
    if axis == "X":
        half_a, half_b, back, front = sy * 0.5, sz * 0.5, cx - sx * 0.5, cx + sx * 0.5
        ring_x, face_x = front - d, front
        quad = [(back, cy - half_a, cz - half_b), (back, cy + half_a, cz - half_b),
                (back, cy + half_a, cz + half_b), (back, cy - half_a, cz + half_b)]
        ring = [(ring_x, cy - half_a, cz - half_b), (ring_x, cy + half_a, cz - half_b),
                (ring_x, cy + half_a, cz + half_b), (ring_x, cy - half_a, cz + half_b)]
        face = [(face_x, cy - half_a + c, cz - half_b + c), (face_x, cy + half_a - c, cz - half_b + c),
                (face_x, cy + half_a - c, cz + half_b - c), (face_x, cy - half_a + c, cz + half_b - c)]
    else:
        half_a, half_b, back, front = sx * 0.5, sz * 0.5, cy - sy * 0.5, cy + sy * 0.5
        ring_y, face_y = front - d, front
        quad = [(cx - half_a, back, cz - half_b), (cx + half_a, back, cz - half_b),
                (cx + half_a, back, cz + half_b), (cx - half_a, back, cz + half_b)]
        ring = [(cx - half_a, ring_y, cz - half_b), (cx + half_a, ring_y, cz - half_b),
                (cx + half_a, ring_y, cz + half_b), (cx - half_a, ring_y, cz + half_b)]
        face = [(cx - half_a + c, face_y, cz - half_b + c), (cx + half_a - c, face_y, cz - half_b + c),
                (cx + half_a - c, face_y, cz + half_b - c), (cx - half_a + c, face_y, cz + half_b - c)]
    vs = [[dst.verts.new(p) for p in group] for group in (quad, ring, face)]
    dst.faces.new(vs[0])
    dst.faces.new(vs[2])
    for k in range(4):
        k2 = (k + 1) % 4
        dst.faces.new((vs[0][k], vs[0][k2], vs[1][k2], vs[1][k]))
        dst.faces.new((vs[1][k], vs[1][k2], vs[2][k2], vs[2][k]))
    return dst


def pyramid(dst, base, height, top_scale=0.0, center=(0.0, 0.0, 0.0)):
    """Square pyramid (top_scale=0) or frustum, built face by face (a loft would degenerate)."""
    hx, hy = base
    cx, cy, z0 = center
    bot = [(cx - hx, cy - hy, z0), (cx + hx, cy - hy, z0),
           (cx + hx, cy + hy, z0), (cx - hx, cy + hy, z0)]
    if top_scale <= 1e-6:
        top = [(cx, cy, z0 + height)]
    else:
        tx, ty = hx * top_scale, hy * top_scale
        top = [(cx - tx, cy - ty, z0 + height), (cx + tx, cy - ty, z0 + height),
               (cx + tx, cy + ty, z0 + height), (cx - tx, cy + ty, z0 + height)]
    bv = [dst.verts.new(p) for p in bot]
    dst.faces.new(bv)
    if len(top) == 1:
        av = dst.verts.new(top[0])
        for i in range(4):
            dst.faces.new((bv[i], bv[(i + 1) % 4], av))
    else:
        tv = [dst.verts.new(p) for p in top]
        dst.faces.new(tv)
        for i in range(4):
            dst.faces.new((bv[i], bv[(i + 1) % 4], tv[(i + 1) % 4], tv[i]))
    return dst


def pyramid_lit(dst, base, height, center=(0.0, 0.0, 0.0)):
    """A square pyramid with the UVs the Peace Hotel's copper roof needs.

    u runs along the base edge in metres (so the standing seams keep a real 0.45 m
    spacing) and v runs from 0 at the base to 1 at the apex (so the glow gradient climbs
    the pyramid instead of tiling over it)."""
    hx, hy = base
    cx, cy, z0 = center
    bot = [(cx - hx, cy - hy, z0), (cx + hx, cy - hy, z0),
           (cx + hx, cy + hy, z0), (cx - hx, cy + hy, z0)]
    bv = [dst.verts.new(p) for p in bot]
    dst.faces.new(bv)
    av = dst.verts.new((cx, cy, z0 + height))
    layer = dst.loops.layers.uv.get("UVMap") or dst.loops.layers.uv.new("UVMap")
    for i in range(4):
        j = (i + 1) % 4
        f = dst.faces.new((bv[i], bv[j], av))
        elen = math.hypot(bot[j][0] - bot[i][0], bot[j][1] - bot[i][1])
        uvs = {bv[i].index: (0.0, 0.0), bv[j].index: (elen, 0.0),
               av.index: (elen * 0.5, 1.0)}
        for loop in f.loops:
            loop[layer].uv = uvs[loop.vert.index]
    return dst


def box(dst, center, size):
    """Axis-aligned box into `dst` (centre + full size)."""
    geo.box(dst, center, size)
    return dst


def grid_box(dst, center, size, step=4.0):
    """A box whose faces are diced into cells of at most `step` metres.

    The Bund's tint (AO, dirt, macro variation) is carried per vertex, so an uncut
    70 m face would hold one flat value along its whole length. The cells share their
    vertices, so the box still shades as one solid."""
    cx, cy, cz = center
    sx, sy, sz = size
    nx, ny, nz = [max(1, int(math.ceil(s / step))) for s in (sx, sy, sz)]
    hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
    g = {}
    for i in range(nx + 1):
        for j in range(ny + 1):
            for k in range(nz + 1):
                g[(i, j, k)] = dst.verts.new(
                    (cx - hx + sx * i / nx, cy - hy + sy * j / ny, cz - hz + sz * k / nz))
    for i in range(nx):
        for j in range(ny):
            dst.faces.new((g[(i, j, 0)], g[(i + 1, j, 0)], g[(i + 1, j + 1, 0)], g[(i, j + 1, 0)]))
            dst.faces.new((g[(i, j + 1, nz)], g[(i + 1, j + 1, nz)], g[(i + 1, j, nz)], g[(i, j, nz)]))
    for i in range(nx):
        for k in range(nz):
            dst.faces.new((g[(i, 0, k + 1)], g[(i, 0, k)], g[(i + 1, 0, k)], g[(i + 1, 0, k + 1)]))
            dst.faces.new((g[(i, ny, k)], g[(i, ny, k + 1)], g[(i + 1, ny, k + 1)], g[(i + 1, ny, k)]))
    for j in range(ny):
        for k in range(nz):
            dst.faces.new((g[(0, j, k)], g[(0, j, k + 1)], g[(0, j + 1, k + 1)], g[(0, j + 1, k)]))
            dst.faces.new((g[(nx, j + 1, k)], g[(nx, j + 1, k + 1)], g[(nx, j, k + 1)], g[(nx, j, k)]))
    return dst


def plate(dst, x, y0, y1, z0, z1, out=0.0, back=0.0):
    """A flat slab on the facade plane: from x-back (inside) to x+out (proud)."""
    cx = x + (out - back) * 0.5
    sx = abs(out - back) if (out - back) != 0 else 0.02
    geo.box(dst, (cx, (y0 + y1) * 0.5, (z0 + z1) * 0.5), (sx, abs(y1 - y0), abs(z1 - z0)))
    return dst


def quad(dst, p0, p1, p2, p3):
    """A single quad (used for glass panes and flat panels). Returns the face."""
    vs = [dst.verts.new(p) for p in (p0, p1, p2, p3)]
    return dst.faces.new(vs)


def arch_glass(dst, x, yc, z_spring, r, bottom, segs=10):
    """A round-headed glass panel in the (y, z) plane at x."""
    pts = [(x, yc - r, bottom), (x, yc + r, bottom)]
    for i in range(segs + 1):
        a = math.pi * i / segs
        pts.append((x, yc + r * math.cos(a), z_spring + r * math.sin(a)))
    vs = [dst.verts.new(p) for p in pts]
    dst.faces.new(vs)
    return dst


def voussoirs(dst, x0, x1, yc, z_spring, r, n=9, thick=0.30, depth=0.18):
    """The wedge stones of a round arch, standing on the springing line."""
    for k in range(n):
        a0 = math.pi * k / n
        a1 = math.pi * (k + 1) / n
        c0, s0 = math.cos(a0), math.sin(a0)
        c1, s1 = math.cos(a1), math.sin(a1)
        quad_pts = [(x0, yc + r * c0, z_spring + r * s0), (x0, yc + r * c1, z_spring + r * s1),
                    (x0, yc + (r + thick) * c1, z_spring + (r + thick) * s1),
                    (x0, yc + (r + thick) * c0, z_spring + (r + thick) * s0)]
        a = [dst.verts.new((x0, p[1], p[2])) for p in quad_pts]
        b = [dst.verts.new((x1, p[1], p[2])) for p in quad_pts]
        dst.faces.new((a[0], a[1], a[2], a[3]))
        dst.faces.new((b[3], b[2], b[1], b[0]))
        for i in range(4):
            j = (i + 1) % 4
            dst.faces.new((a[i], b[i], b[j], a[j]))
    return dst


