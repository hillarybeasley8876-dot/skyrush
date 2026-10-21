"""Extra procedural texture sets for SKYRUSH landmarks (numpy only, no bpy).

    python3 blender/landmarks/texsets.py

Every set returns (albedo RGB, normal RGB, roughness RGB) float arrays in 0..1
(albedo in linear space, the others ready to be written as PNGs). Dossier 15:
no flat colours anywhere - every metal gets panel seams, brushing and rain
streaks, every timber gets planks, joints and a worn path.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender/landmarks"))
import texgen
import texio
from texgen import blur, hexlin, value_noise, write_png, srgb_to_bytes, data_to_bytes

OUT = texgen.OUT

# The glTF metallicRoughness texture packs metalness in BLUE and roughness in
# GREEN, so every "rough" map is written as an ORM (R = AO = 1, G = roughness,
# B = metalness). The metalness of the set decides how the surface reads.
ORM_METAL = {
    "metal_brushed": 1.0,
    "metal_painted": 0.85,
    "metal_white": 0.85,
    "metal_dark": 0.90,
    "timber": 0.0,
    "honeycomb": 0.30,
    "ring_glass": 0.0,
    "formwork": 0.0,
}


def _normals(hgt, tile_m, strength=1.0):
    """Tangent-space normal from a height field in METRES over a `tile_m` tile."""
    dx = tile_m / float(hgt.shape[1])
    dy = tile_m / float(hgt.shape[0])
    gx = np.gradient(hgt, axis=1) / dx
    gy = np.gradient(hgt, axis=0) / dy
    nrm = np.stack([-gx * strength, -gy * strength, np.ones_like(hgt)], axis=2)
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    return nrm * 0.5 + 0.5


def _grid_lines(shape, cells_x, cells_y, width_px, depth=1.0):
    """Groove mask on a cell grid (0 outside, -depth inside the groove)."""
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    ux = (xx / w * cells_x) % 1.0
    uy = (yy / h * cells_y) % 1.0
    dx = np.minimum(ux, 1.0 - ux) * (w / cells_x)
    dy = np.minimum(uy, 1.0 - uy) * (h / cells_y)
    d = np.minimum(dx, dy)
    return -depth * np.clip((width_px - d) / max(width_px, 0.5), 0.0, 1.0)


def metal_set(colour="#B7BCC0", size=1024, tile_m=2.4, seam_m=1.2, brush=0.5, seed=1,
              streak=0.45, rough_base=0.32):
    """Brushed / painted metal sheet with a panel grid, rain streaks and edge wear.

    One tile covers `tile_m` metres; panel seams every `seam_m` (x) and 2 x seam_m (y)."""
    h = w = size
    base = np.array(hexlin(colour), np.float32)
    grain = value_noise((h, w), 6, seed, 4)
    # fine vertical brushing: noise stretched along y (2 mm x 300 mm in world terms)
    brush_n = value_noise((max(4, h // 64), w), 220, seed + 3, 2)
    brush_n = np.repeat(brush_n, 64, axis=0)[:h]
    if brush_n.shape != (h, w):
        brush_n = np.resize(brush_n, (h, w))
    seams = _grid_lines((h, w), max(1, int(round(tile_m / seam_m))),
                        max(1, int(round(tile_m / (seam_m * 2)))), 6.0, 1.0)
    hgt = seams * 0.007 + brush_n * 0.0016 * brush
    # rain streaks running down
    st = value_noise((max(4, h // 24), w), 40, seed + 11, 3)
    st = np.repeat(st, 24, axis=0)[:h]
    if st.shape != (h, w):
        st = np.resize(st, (h, w))
    streak = np.clip((st - 0.55) * 3.0, 0.0, 1.0)
    albedo = np.tile(base, (h, w, 1)) * (0.80 + 0.38 * grain[:, :, None])
    albedo *= (1.0 - 0.30 * streak[:, :, None])
    # edges catch a little wear (brighter)
    wear = np.clip(-seams * 1.6, 0.0, 1.0)[:, :, None]
    albedo = albedo * (1.0 - wear) + np.minimum(albedo * 1.5, 1.0) * wear
    rough = np.clip(rough_base + 0.18 * (grain - 0.5) * 2.0
                    + 0.26 * streak * streak + 0.22 * brush_n * brush, 0.08, 0.85)
    return albedo, _normals(hgt, tile_m, 1.0), np.repeat(rough[:, :, None], 3, axis=2)


def timber_set(size=1024, tile_m=2.0, seed=2):
    """Timber sidewalk: 0.20 m planks, 9 cm thick, staggered butt joints, grain, gaps."""
    h = w = size
    plank_px = max(2.0, 0.20 / tile_m * w)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    row = np.floor(xx / plank_px)
    within = (xx / plank_px) % 1.0
    # staggered butt joints: every other plank offset by half a plank length
    length_px = 1.2 / tile_m * w
    off = np.where(row % 2 == 0, 0.0, 0.5) * length_px
    joint_x = ((yy + off) % length_px)
    gap = np.clip((plank_px * 0.09 - np.minimum(within, 1.0 - within) * plank_px)
                  / max(plank_px * 0.09, 1.0), 0.0, 1.0)
    jg = np.clip((length_px * 0.03 - np.minimum(joint_x, length_px - joint_x))
                 / max(length_px * 0.03, 1.0), 0.0, 1.0)
    grain = value_noise((h, w), 3, seed, 4)
    fine = value_noise((max(4, h // 8), w), 90, seed + 5, 2)
    fine = np.resize(np.repeat(fine, 8, axis=0)[:h], (h, w))
    tone = 0.75 + 0.5 * ((row * 0.37) % 1.0)
    base = np.array(hexlin("#6B5741"), np.float32)
    albedo = np.tile(base, (h, w, 1)) * tone[:, :, None] * (0.82 + 0.30 * grain[:, :, None])
    albedo *= (0.88 + 0.22 * fine[:, :, None])
    # worn foot path down the middle of the tile
    path = np.exp(-((xx / w - 0.5) ** 2) / 0.012)
    albedo = albedo * (1.0 - 0.25 * path[:, :, None]) + albedo * 1.25 * path[:, :, None]
    dark = np.clip(1.0 - np.minimum(gap, jg), 0.0, 1.0)
    albedo *= (1.0 - 0.7 * dark[:, :, None])
    hgt = -dark * 0.02 + fine * 0.0015 + grain * 0.001
    rough = np.clip(0.72 - 0.22 * path + 0.14 * (grain - 0.5) * 2.0 + 0.2 * dark, 0.25, 0.95)
    return albedo, _normals(hgt, tile_m, 1.0), np.repeat(rough[:, :, None], 3, axis=2)


def honeycomb_set(size=1024, tile_m=4.8, pitch=1.2, colour="#B0306A", seed=3):
    """Triangulated panel grid for the OPT glass: +/-6 % albedo per panel."""
    h = w = size
    cell = max(4.0, pitch / tile_m * w)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    gx = (xx % cell) / cell
    gy = (yy % cell) / cell
    # triangulated hex-ish cells: distance to the nearest cell edge in a hex grid
    ex = np.abs(gx - 0.5)
    ey = np.abs(gy - 0.5)
    edge = np.minimum(ex, ey)
    seam = np.clip((0.045 - edge) / 0.045, 0.0, 1.0)
    ci = np.floor(xx / cell)
    cj = np.floor(yy / cell)
    tone = texgen._rnd(ci.astype(np.int64), cj.astype(np.int64), 7)
    base = np.array(hexlin(colour), np.float32)
    albedo = np.tile(base, (h, w, 1)) * (0.94 + 0.12 * tone[:, :, None])
    albedo *= (1.0 - 0.35 * seam[:, :, None])
    hgt = -seam * 0.004 + 0.0004 * tone
    rough = np.clip(0.12 + 0.06 * tone + 0.20 * seam, 0.05, 0.5)
    return albedo, _normals(hgt, tile_m, 1.0), np.repeat(rough[:, :, None], 3, axis=2)


def glass_set(size=512, tile_m=1.5, colour="#CFE6F0", seed=5):
    """Balustrade glass: 1.5 m panels with 4 cm frames and a dirt band.

    The V axis runs over the panel height, so the bottom 8 % carries the grime
    that collects on a 10 cm band above the deck."""
    h = w = size
    base = np.array(hexlin(colour), np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cell = max(4.0, tile_m / tile_m * w)
    ex = np.minimum((xx % cell) / cell, 1.0 - (xx % cell) / cell)
    ey = np.minimum((yy % cell) / cell, 1.0 - (yy % cell) / cell)
    frame = np.clip((0.026 - np.minimum(ex, ey)) / 0.026, 0.0, 1.0)   # 4 cm frames
    grain = value_noise((h, w), 6, seed, 4)
    albedo = np.tile(base, (h, w, 1)) * (0.95 + 0.08 * grain[:, :, None])
    albedo *= (1.0 - 0.30 * frame[:, :, None])
    # the dirt band along the bottom of the panel
    v = yy / h
    dirt = np.clip(1.0 - v / 0.08, 0.0, 1.0) * (0.55 + 0.45 * grain)
    albedo *= (1.0 - 0.55 * dirt[:, :, None])
    hgt = -frame * 0.006 + grain * 0.0006
    rough = np.clip(0.05 + 0.05 * grain + 0.30 * frame + 0.45 * dirt, 0.03, 0.85)
    return albedo, _normals(hgt, tile_m, 1.0), np.repeat(rough[:, :, None], 3, axis=2)


def formwork_set(size=1024, tile_m=4.8, colour="#D8D8D2", seed=4):
    """Fair-faced concrete: 1.2 x 2.4 m formwork panels, tie holes, pour lines, rain streaks."""
    h = w = size
    base = np.array(hexlin(colour), np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    grain = value_noise((h, w), 8, seed, 5)
    seams = _grid_lines((h, w), max(1, int(round(tile_m / 1.2))),
                        max(1, int(round(tile_m / 2.4))), 2.0, 1.0)
    # tie holes: 3 cm, one per panel
    cellx = w / max(1, int(round(tile_m / 1.2)))
    celly = h / max(1, int(round(tile_m / 2.4)))
    thx = (xx % cellx) - cellx * 0.5
    thy = (yy % celly) - celly * 0.5
    hole = np.clip((0.06 - np.sqrt(thx ** 2 + thy ** 2)) / 0.06, 0.0, 1.0)
    st = value_noise((max(4, h // 24), w), 30, seed + 7, 3)
    st = np.resize(np.repeat(st, 24, axis=0)[:h], (h, w))
    streak = np.clip((st - 0.5) * 2.6, 0.0, 1.0)
    albedo = np.tile(base, (h, w, 1)) * (0.84 + 0.28 * grain[:, :, None])
    # the rain streaks: 2-4 m long, running down the face
    albedo *= (1.0 - 0.30 * streak[:, :, None])
    # the efflorescence at the joints: a pale bloom along the seams
    effl = np.clip(-seams, 0, 1) * np.clip((value_noise((h, w), 18, seed + 13, 3) - 0.45) * 3.0, 0.0, 1.0)
    albedo = albedo * (1.0 - 0.55 * effl[:, :, None]) \
        + np.array(hexlin("#E8E6DC"), np.float32)[None, None, :] * 0.55 * effl[:, :, None]
    # a darker band at the base of every pour
    band = np.clip((np.arange(h, dtype=np.float32) / h - 0.78) * 4.0, 0.0, 1.0)
    albedo *= (1.0 - 0.30 * band[:, None, None])
    albedo *= (1.0 - 0.25 * np.clip(-seams, 0, 1)[:, :, None])
    albedo *= (1.0 - 0.45 * hole[:, :, None])
    hgt = seams * 0.006 - hole * 0.02 + grain * 0.0012
    rough = np.clip(0.66 + 0.12 * (grain - 0.5) * 2.0 + 0.18 * streak, 0.4, 0.95)
    return albedo, _normals(hgt, tile_m, 1.0), np.repeat(rough[:, :, None], 3, axis=2)


def main():
    sets = [
        ("metal_brushed", metal_set("#B9BCBE", 1024, 2.4, 1.2, brush=1.0, rough_base=0.30)),
        ("metal_painted", metal_set("#C8CCD0", 1024, 2.4, 1.2, brush=0.3, rough_base=0.28)),
        ("metal_white", metal_set("#F0F0EE", 1024, 2.4, 1.2, brush=0.2, rough_base=0.34)),
        ("metal_dark", metal_set("#8C9298", 1024, 1.8, 0.9, brush=0.6, rough_base=0.38)),
        ("timber", timber_set(1024, 2.0)),
        ("honeycomb", honeycomb_set(1024, 4.8, 1.2, "#B0306A")),
        ("ring_glass", glass_set(512, 1.5, "#CFE6F0")),
        ("formwork", formwork_set(1024, 2.4, "#D8D8D2")),
    ]
    normals = []
    for (name, (alb, nrm, rgh)) in sets:
        # albedo is colour (sRGB); normal and roughness are DATA (linear)
        p = os.path.join(OUT, "%s_diff.png" % name)
        write_png(p, srgb_to_bytes(alb))
        print("  tex %s (%.1f kB)" % (os.path.basename(p), os.path.getsize(p) / 1024.0))
        pn = os.path.join(OUT, "%s_nor.png" % name)
        write_png(pn, data_to_bytes(nrm))
        normals.append(pn)
        print("  tex %s (%.1f kB)" % (os.path.basename(pn), os.path.getsize(pn) / 1024.0))
        pr = os.path.join(OUT, "%s_rough.png" % name)
        metal = ORM_METAL.get(name, 0.0)
        rr = rgh[:, :, 0]
        orm = np.stack([np.ones_like(rr), rr, np.full_like(rr, metal)], axis=2)
        write_png(pr, data_to_bytes(orm))
        print("  tex %s (%.1f kB)" % (os.path.basename(pr), os.path.getsize(pr) / 1024.0))
    n = texgen.assert_linear_normals(normals)
    print("  %d normal maps verified linear" % n)
    # the shared facade material needs two of these INSIDE the Godot project
    for name in ("metal_dark_diff.png", "metal_dark_nor.png"):
        src = os.path.join(OUT, name)
        if os.path.exists(src):
            texio.copy_if_changed(src, os.path.join(texgen.PROJECT_TEX, name))


if __name__ == "__main__":
    main()
