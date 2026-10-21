"""Map assembly for the Nine-Dragon Pillar relief (see tex_pillar.py).

Turns the height field into the shipped maps: the tangent-space normal at
4096 x 8192, the base colour and the ORM (R = AO, G = roughness, B = metal)
at 2048 x 4096 and the normalised displacement source.

The ORM is a real one (the r3 review: "the pillar ORM is wired as AO only,
with constant roughness and metal"): the steel is 0.28-0.34 rough with
vertical brushing, the bronze 0.42-0.50, the raised edges 0.32, and the
metalness is 1.0 on the steel and the bronze and about 0.6 in the patina
cavities.

    python3 blender/landmarks/tex_pillar_maps.py
"""
import gc
import os
import sys

import numpy as np

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender/landmarks"))
import texgen
import tex_pillar
from texgen import blur, hexlin, value_noise, write_png, srgb_to_bytes, data_to_bytes
from tex_pillar import (BC_W, BC_H, ORM_W, ORM_H, NOR_W, NOR_H, HEI_W, HEI_H,
                        RELIEF, CIRC, COL_H, H, W, OUT, downsample2, _u8,
                        build_height)

STEEL = "#B9BCBE"
BRONZE = "#3B2F25"
CAVITY = "#241C16"
EDGE = "#8A6A3E"
DUST = "#7A7468"


def normal_map(h, block=512):
    """Tangent-space normal from the height field, computed in row blocks.

    The map is 4096 x 8192 (the shipped resolution) and LINEAR: a flat normal
    is (128, 128, 255), never (188, 188, 255)."""
    out = np.empty((H, W, 3), np.uint8)
    dx = CIRC / W
    dy = COL_H / H
    for r0 in range(0, H, block):
        r1 = min(H, r0 + block)
        a = max(0, r0 - 2)
        b = min(H, r1 + 2)
        seg = h[a:b]
        gx = np.gradient(seg, axis=1) / dx
        gy = np.gradient(seg, axis=0) / dy
        nrm = np.stack([-gx, -gy, np.ones_like(seg)], axis=2)
        nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
        nrm = nrm * 0.5 + 0.5
        out[r0:r1] = np.clip(nrm[max(0, r0 - a):max(0, r0 - a) + (r1 - r0)] * 255.0 + 0.5,
                             0, 255).astype(np.uint8)
        del seg, gx, gy, nrm
    return out


def downsample2_u8(a):
    """2x2 box average of a uint8 array."""
    h, w = a.shape[:2]
    hh, ww = h // 2 * 2, w // 2 * 2
    b = a[:hh, :ww].reshape(hh // 2, 2, ww // 2, 2).mean(axis=(1, 3))
    return b.astype(np.uint8)


def brushing_field(h, w):
    """The vertical brushing: streaks a few millimetres wide, 5-40 cm long.

    The map raster cannot carry a 1-3 mm streak, so the finest the 4096 px
    normal can hold is one pixel (3.8 mm); the streaks are drawn at that
    width and are 13-105 px long."""
    n = value_noise((48, 1024), 24, 91, 3)
    yi = (np.arange(h) * 48 // h).clip(0, 47)
    xi = (np.arange(w) * 1024 // w).clip(0, 1023)
    return n[np.ix_(yi, xi)]


def _panel_coverage(masks, pans):
    """The dark-bronze coverage of every panel (the r3 review wants >= 15 %).

    The second number is the coverage that survives a 0.30 m erosion."""
    br_all = masks["bronze"] > 0
    eroded = _erode(br_all, int(0.30 * 130.0))
    mh, mw = br_all.shape
    out = []
    for idx, (r, k, a0, handed, ty0, ty1) in enumerate(pans):
        s0, s1 = tex_pillar.panel_sector(a0, handed)
        xa = np.radians(s0) * tex_pillar.COL_R
        xb = np.radians(s1) * tex_pillar.COL_R
        xs = tex_pillar._xmask(xa, xb, mw)
        ym = (np.arange(mh, dtype=np.float32) + 0.5) * COL_H / mh
        ys = (ym >= ty0) & (ym <= ty1)
        sel = np.ix_(ys, xs)
        out.append((idx + 1, 100.0 * br_all[sel].mean(), 100.0 * eroded[sel].mean()))
    return out


def build_maps():
    """Height field -> normal, ORM (AO/rough/metal), albedo, displacement."""
    h, masks = build_height()
    brush = brushing_field(H, W)
    brush_half = downsample2(brush)
    h += (0.0005 * (brush - 0.5)).astype(np.float32)
    del brush
    gc.collect()
    normal = normal_map(h)
    hh = downsample2(h)
    del h
    gc.collect()
    m = {}
    for key, val in masks.items():
        m[key] = downsample2_u8(val).astype(np.float32) / 255.0
    del masks
    gc.collect()
    for idx, pct, epct in _panel_coverage(m, tex_pillar.panels()):
        print("  panel %d bronze coverage: %.1f %% (eroded 0.30 m: %.1f %%)"
              % (idx, pct, epct))
    bronze = m["bronze"]
    dm, gm, hm = m["dm"], m["gm"], m["hm"]
    mm, cc, hole, sm = m["mm"], m["cc"], m["hole"], m["sm"]
    avg = blur(hh, 2)
    ao = np.clip(1.0 - 2.4 * np.clip(avg - hh, 0.0, None) / RELIEF, 0.18, 1.0)
    convex = np.clip((hh - avg) / 0.010, 0.0, 1.0)
    concave = np.clip((avg - hh) / 0.010, 0.0, 1.0)
    del avg, hh
    gc.collect()
    h2, w2 = bronze.shape
    grain = value_noise((h2, w2), 6, 33, 4)
    steel_c = np.array(hexlin(STEEL), np.float32)
    bronze_c = np.array(hexlin(BRONZE), np.float32)
    cav_c = np.array(hexlin(CAVITY), np.float32)
    edge_c = np.array(hexlin(EDGE), np.float32)
    dust_c = np.array(hexlin(DUST), np.float32)
    # --- the base colour
    base = steel_c[None, None, :] * (0.93 + 0.11 * grain[:, :, None])
    base = base * (1.0 - 0.07 * (brush_half[:, :, None] - 0.5) * 2.0)
    albedo = base * (1.0 - bronze[:, :, None]) + bronze_c[None, None, :] * bronze[:, :, None]
    # the patina cavities: the fret grooves and the eye sockets
    cav = np.clip(mm * 1.25 + hole * 1.4, 0.0, 1.0)[:, :, None]
    albedo = albedo * (1.0 - cav) + cav_c[None, None, :] * cav
    # the raised edges of the relief
    edge = (np.clip((convex - 0.30) * 2.4, 0.0, 1.0) * bronze)
    edge3 = edge[:, :, None]
    albedo = albedo * (1.0 - edge3) + edge_c[None, None, :] * edge3
    # the dust on the upward-facing ledges
    ng = normal[::2, ::2, 1].astype(np.float32) / 255.0
    ledge = np.clip((ng - 0.72) / 0.22, 0.0, 1.0)[:, :, None]
    albedo = albedo * (1.0 - ledge * 0.45) + dust_c[None, None, :] * ledge * 0.45
    albedo = albedo * ao[:, :, None]
    del base, edge3, ledge, convex, concave, ng
    gc.collect()
    # --- the ORM
    rough = 0.31 + 0.035 * (brush_half - 0.5) * 2.0 + 0.025 * grain
    rough = rough * (1.0 - bronze) + (0.46 + 0.04 * grain) * bronze
    rough = rough * (1.0 - edge) + 0.32 * edge
    rough = np.clip(rough, 0.20, 0.72)
    cav2 = cav[:, :, 0]
    # the steel is a brushed, slightly oxidised finish. At a metalness of 1.0
    # the column is a black mirror at night and the four uplights cannot read
    # on it (measured P50 0.09 with the r3 rig), so the steel sits at 0.62 and
    # the bronze relief stays fully metallic.
    metal = np.ones_like(rough) * bronze + 0.62 * (1.0 - bronze)
    metal = metal * (1.0 - cav2) + 0.60 * cav2
    orm = np.stack([ao, rough, metal], axis=2)
    del rough, metal, ao, edge, cav2
    gc.collect()
    # --- the displacement source
    disp = (tex_pillar.GROUND_DEPTH * (1.0 - gm) + RELIEF * dm
            + tex_pillar.HOOK_DEPTH * hm + tex_pillar.SUN_DEPTH * sm) / RELIEF
    disp = np.clip(disp, 0.0, 1.0)
    return albedo, normal, orm, disp


def _erode(mask, r):
    """A chamfer erosion by `r` pixels (the 8 directions at the radius)."""
    out = mask.copy()
    for dx, dy in ((r, 0), (-r, 0), (0, r), (0, -r),
                   (r, r), (-r, r), (r, -r), (-r, -r)):
        out &= np.roll(np.roll(mask, dy, axis=0), dx, axis=1)
    return out


def main():
    albedo, normal, orm, disp = build_maps()
    files = {
        "pillar_basecolor.png": (srgb_to_bytes(albedo), BC_W, BC_H),
        "pillar_normal.png": (normal, NOR_W, NOR_H),
        "pillar_orm.png": (data_to_bytes(orm), ORM_W, ORM_H),
        "pillar_height.png": (data_to_bytes(np.repeat(disp[:, :, None], 3, axis=2)),
                              HEI_W, HEI_H),
    }
    for name, (arr, w, h) in files.items():
        path = os.path.join(OUT, name)
        write_png(path, np.flipud(arr))
        print("  tex %s %dx%d (%.1f kB)" % (name, w, h, os.path.getsize(path) / 1024.0))
        del arr
        gc.collect()
    n = texgen.assert_linear_normals([os.path.join(OUT, "pillar_normal.png")])
    print("  %d normal maps verified linear" % n)


if __name__ == "__main__":
    main()
