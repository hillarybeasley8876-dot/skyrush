"""The body and glass maps, generated on the real mesh inside Blender.

The lead's shell uses a smart UV projection, so the maps that must follow the
body (the 4 mm panel-gap normal + AO and the ceramic frit band on the canopy)
are drawn in the mesh's own UV space, projected from the 3D surface.

Outputs (game/assets/cars/roadster/textures/):
    body_panel_base.png   the paint base with the gap AO
    body_panel_nor.png    the panel-gap normal map (4 mm grooves)
    body_rough.png        the paint roughness (0.26..0.30)
    glass_base.png        the bronze canopy with the black frit band
    glass_nor.png         the faint canopy smudge
"""
import os

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from car import paths, regions, uvtool

SIZE = 4096
GLASS_SIZE = 1024
GAP_MM = 0.004          # 4 mm panel gaps (dossier §7.1)
GAP_DEPTH = 0.0015      # the groove depth in the normal map
FRIT_M = 0.030          # the 30 mm ceramic frit band
WRITTEN = [0]
UNCHANGED = [0]


def save_png(name, arr):
    """Write a numpy RGB(A) array (0..255, top row first) as a PNG.

    The PNG is written to the scratch folder first and only copied into the
    texture folder when its bytes differ from the file on disk, so a rebuild
    never touches an unchanged map (lead note IMPORT-CHURN).
    """
    a = np.asarray(arr, np.float32)
    if a.ndim == 2:
        a = np.repeat(a[:, :, None], 3, axis=2)
    h, w = a.shape[:2]
    img = bpy.data.images.new(name, width=w, height=h, alpha=(a.shape[2] == 4))
    img.colorspace_settings.name = "Non-Color"      # the bytes are written verbatim
    rgba = np.ones((h, w, 4), np.float32)
    rgba[:, :, :a.shape[2]] = a[:, :, :3] / 255.0
    img.pixels.foreach_set(rgba[::-1].ravel())      # Blender stores the rows bottom up
    scratch = os.path.join(paths.SCRATCH, "tex")
    os.makedirs(scratch, exist_ok=True)
    tmp = os.path.join(scratch, name)
    img.filepath_raw = tmp
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    with open(tmp, "rb") as f:
        data = f.read()
    dest = paths.tex(name)
    if os.path.exists(dest) and open(dest, "rb").read() == data:
        UNCHANGED[0] += 1
    else:
        with open(dest, "wb") as f:
            f.write(data)
        WRITTEN[0] += 1
    os.remove(tmp)


def _bvh(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    return tree


def _flank_line(bvh, poly, sign):
    """A polyline in the (y, z) plane pushed onto the flank of the skin."""
    pts = []
    for y, z in poly:
        x = regions.surface_x(bvh, y, z, sign)
        if x is None:
            return []
        pts.append((x, y, z))
    return pts


def _top_line(bvh, y, half_x, z0=None):
    """A straight line across the upper skin at a given y."""
    pts = []
    steps = 24
    for i in range(steps + 1):
        x = -half_x + 2.0 * half_x * i / steps
        z = regions.surface_z(bvh, x, y)
        if z is None:
            continue
        pts.append((x, y, z))
    return pts


def _gap_lines(bvh):
    """Every panel-gap line of the dossier, as 3D polylines on the skin."""
    d = paths.loft()
    sp, pl = d["side_profile"], d["panel_lines"]
    lines = []
    for poly in (sp["door_front_cut"], sp["door_rear_cut"]):
        for sign in (1, -1):
            pts = _flank_line(bvh, poly, sign)
            if len(pts) > 1:
                lines.append(pts)
    # the door's lower cut (the sill line under the door)
    lower = [sp["door_front_cut"][-1], sp["door_rear_cut"][-1]]
    for sign in (1, -1):
        pts = _flank_line(bvh, lower, sign)
        if len(pts) > 1:
            lines.append(pts)
    # the cowl and the vent-hood lines across the bonnet
    for key in ("cowl_y", "vent_hood_front_y"):
        y = pl[key]
        pts = _top_line(bvh, y, regions.hood_half_width(y))
        if len(pts) > 1:
            lines.append(pts)
    # the wing's leading edge on the deck
    y = pl["wing_front_edge_y"]
    pts = _top_line(bvh, y, 0.60)
    if len(pts) > 1:
        lines.append(pts)
    # the two T-top lines on the roof
    for key in ("t_top_front_y", "t_top_rear_y"):
        pts = _top_line(bvh, d["roof"][key], d["roof"]["t_bar_half_width"])
        if len(pts) > 1:
            lines.append(pts)
    # the headlamp panel's rear edge on the flank
    y = pl["headlamp_panel_rear_y"]
    for sign in (1, -1):
        pts = _flank_line(bvh, [(y, 0.42), (y, 0.52)], sign)
        if len(pts) > 1:
            lines.append(pts)
    return lines


def _density_map(proj, size):
    """The local texel density (pixels per metre) of every pixel of the UV map."""
    verts_uv, verts_val = [], []
    for i, (ids, uvs) in enumerate(proj.tris):
        px = proj.uv_per_m(i) * size
        for uv in uvs:
            verts_uv.append((uv.x, uv.y))
            verts_val.append((px,))
    return uvtool.rasterize(verts_uv, verts_val, size)


def _draw_grooves(body, bvh, proj):
    """Carve the panel gaps into the height field and paint the AO line."""
    height = np.zeros((SIZE, SIZE), np.float32)
    rgb = np.full((SIZE, SIZE, 3), 255.0, np.float32)
    rgb += _value_noise(SIZE, 32, 10.0, 7)[..., None]
    count = 0
    for line in _gap_lines(bvh):
        samples = uvtool.polyline(line, 0.006)
        prev = None
        for p in samples:
            uv = proj.uv_at(p)
            if uv is None:
                prev = None
                continue
            idx = proj.nearest_index(p)
            px = uv[0] * SIZE
            py = (1.0 - uv[1]) * SIZE
            if prev is not None:
                w = max(1.5, GAP_MM * proj.uv_per_m(idx) * SIZE)
                uvtool.draw_line(height, prev, (px, py), GAP_DEPTH, w)
                uvtool.paint_line(rgb, prev, (px, py), (26, 26, 30), w * 0.95)
                count += 1
            prev = (px, py)
    print("  panel-gap grooves drawn: %d segments" % count)
    return height, rgb


def body_maps(body):
    """The body base colour, the gap normal map and the paint roughness."""
    bvh = _bvh(body)
    proj = uvtool.Projector(body)
    height, rgb = _draw_grooves(body, bvh, proj)
    density = _density_map(proj, SIZE)
    save_png("body_panel_base.png", np.clip(rgb, 0, 255))
    save_png("body_panel_nor.png", np.clip(height_to_normal(height, density), 0, 255))
    rough = np.full((1024, 1024), 0.28, np.float32)
    rough += _value_noise(1024, 64, 0.05, 13) + _value_noise(1024, 16, 0.03, 17)
    save_png("body_rough.png", np.repeat((np.clip(rough, 0, 1) * 255.0)[:, :, None], 3, axis=2))
    print("  body maps written (gap normal + base + roughness)")


def _value_noise(size, cells, amp, seed):
    """Smooth value noise in -amp/2..amp/2, `cells` cells across the map."""
    small = (np.random.default_rng(seed).random((cells, cells)) - 0.5) * amp
    xs = np.linspace(0.0, cells - 1, size)
    rows = np.clip(np.round(xs).astype(int), 0, cells - 1)
    out = np.empty((size, size), np.float32)
    grid = np.arange(cells, dtype=np.float32)
    for i in range(size):
        out[i] = np.interp(xs, grid, small[rows[i]])
    return out


def height_to_normal(h_m, density):
    """Normal map from a height field in metres and the local texel density."""
    h = np.asarray(h_m, np.float32)
    gy, gx = np.gradient(h)
    nx = -gx * density
    ny = gy * density
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    out = np.empty(h.shape + (3,), np.float32)
    out[..., 0] = nx / ln * 0.5 + 0.5
    out[..., 1] = ny / ln * 0.5 + 0.5
    out[..., 2] = nz / ln * 0.5 + 0.5
    return out * 255.0


def glass_maps(glass):
    """The bronze canopy with the black ceramic frit band around every edge.

    The band is measured in 3D (30 mm from the edge of the glass), so it is
    computed per pixel: the mesh's vertices are too coarse for a 30 mm band.
    """
    me = glass.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    seeds = []
    for v in bm.verts:
        for e in v.link_edges:
            if len(e.link_faces) == 1:
                other = e.other_vert(v)
                seeds.append(v.co.copy())
                seeds.append((v.co + other.co) * 0.5)
                break
    bm.free()
    layer = me.uv_layers["UVMap"]
    me.calc_loop_triangles()
    verts_uv, verts_pos = [], []
    for t in me.loop_triangles:
        for li in t.loops:
            vi = me.loops[li].vertex_index
            verts_uv.append((layer.data[li].uv[0], layer.data[li].uv[1]))
            verts_pos.append(tuple(me.vertices[vi].co))
    pos = uvtool.rasterize(verts_uv, verts_pos, GLASS_SIZE, comps=3)
    covered = np.abs(pos).sum(axis=2) > 1e-6
    dist = uvtool.distance_to_points(pos, seeds)
    band = np.clip((FRIT_M + 0.003 - dist) / 0.003, 0.0, 1.0) * covered
    base = np.zeros((GLASS_SIZE, GLASS_SIZE, 3), np.float32)
    base[:] = np.array([0x3A, 0x27, 0x18], np.float32)   # the dark bronze of photo 03
    frit = np.array([0x0A, 0x08, 0x06], np.float32)
    m = band[..., None]
    base = base * (1.0 - m) + frit * m
    save_png("glass_base.png", np.clip(base, 0, 255))
    smudge = _value_noise(GLASS_SIZE, 32, 1.0, 23)
    save_png("glass_nor.png", np.clip(height_to_normal(smudge * 0.00008, 2048.0), 0, 255))
    print("  glass maps written (frit band %.1f mm, %d boundary vertices)"
          % (FRIT_M * 1000.0, len(seeds)))


def build(body, glass):
    """Write every map that depends on the mesh."""
    body_maps(body)
    glass_maps(glass)
    print("  shell maps: written %d / unchanged %d"
          % (WRITTEN[0], UNCHANGED[0]))
