"""Procedural relief texture set for the Nine-Dragon Pillar (龙柱).

Wraps the D 5 m x 29.4 m column once: the raster is 4096 px around (15.708 m
circumference) by 8192 px up (29.4 m) - about 260 px/m both ways (dossier 15).

The composition (dossier 1.2, and the r3 review):

  * the column is brushed stainless; the relief sits in NINE panels, three
    tiers of three between the deck levels;
  * every panel is a recessed dark-bronze ground with a CONTINUOUS running
    fret (雷纹) engraved into it, angular cloud hooks standing proud of it
    and a patch of bare steel in the gaps between the hooks;
  * the nine kui-dragons climb their panel diagonally (30-45 deg) with
    S-bends, 6-8 m long, 0.45-0.60 m wide, each one different;
  * a sun disc east and a crescent moon west on the top band.

    python3 blender/landmarks/tex_pillar.py

Maps written (all LINEAR except the base colour):
    pillar_basecolor.png  2048 x 4096   sRGB
    pillar_normal.png     4096 x 8192   linear (tangent space)
    pillar_orm.png        2048 x 4096   linear, R = AO, G = roughness, B = metal
    pillar_height.png     2048 x 4096   linear, the DISPLACEMENT source
"""
import gc
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender/landmarks"))
import texgen
from texgen import write_png, srgb_to_bytes, data_to_bytes
from tex_pillar_sdf import (W, H, CIRC, COL_R, COL_H, PX, PY, BIG, px_of, py_of,
                            sdf_disc, stamp, stroke, box_stamp, path_stroke,
                            disc_mask, smoothstep, _u8)
from tex_pillar_dragons import dragon_spine, dragon_prims, chevron_prims
from tex_pillar_fret import fret_path, cloud_hooks, FRET_W

RELIEF = 0.12                   # the dragon relief depth above the ground (m)
BEVEL = 0.025                   # the relief shoulder (m)
SCALE_DEPTH = 0.014             # carved chevron scale depth (m)
SCALE_PITCH = 0.09              # chevron scale spacing (m)
EYE_DEPTH = 0.04                # eye socket depth (m)
GROUND_DEPTH = 0.02             # the recessed bronze ground (m)
FRET_DEPTH = 0.012              # the engraved fret groove (m)
HOOK_DEPTH = 0.04               # the cloud hooks stand proud of the ground (m)
SUN_DEPTH = 0.10                # the sun and the moon discs (m)
PANEL_Y = (8.4, 17.0, 25.3)     # the deck-level steel bands
TIERS = ((0.9, 7.3), (9.5, 15.9), (18.1, 24.5))   # the three relief tiers
SECTOR_DEG = 120.0              # the angular width of one panel
TIER_PHASE_DEG = 40.0           # the phase shift per tier (the spiral)
SPAN_DEG = 104.0                # the dragon's net wrap
GY = 0.95                       # the ground's inset at the panel top and bottom
GX = 0.28                       # the ground's inset at the panel sides
OUT = texgen.OUT

# output resolutions (dossier 15: ~260 px/m around, ~130 px/m up for the maps)
BC_W, BC_H = 2048, 4096
ORM_W, ORM_H = 2048, 4096
NOR_W, NOR_H = 4096, 8192
HEI_W, HEI_H = 2048, 4096


def panels():
    """The nine panels: (tier, index, a0_deg, handed, tier_y0, tier_y1).

    Every tier is rotated 40 deg against the one below, so the nine dragons
    read as one spiral up the column."""
    out = []
    for r, (ty0, ty1) in enumerate(TIERS):
        handed = 1.0 if r % 2 == 0 else -1.0
        for k in range(3):
            out.append((r, k, TIER_PHASE_DEG * r + SECTOR_DEG * k, handed, ty0, ty1))
    return out


def panel_sector(a0, handed):
    """The angular sector (deg) of the panel that holds a dragon."""
    mid = a0 + handed * SPAN_DEG * 0.5
    return mid - SECTOR_DEG * 0.5, mid + SECTOR_DEG * 0.5


def _xmask(xa, xb, width=W):
    """The raster columns whose arc position lies in [xa, xb] (wrapping).

    The column texture wraps, so the interval is taken modulo the
    circumference: every integer shift that brings a part of it onto the
    raster counts."""
    xm = (np.arange(width, dtype=np.float32) + 0.5) * CIRC / width
    k_lo = int(math.ceil((-CIRC - xb) / CIRC))
    k_hi = int(math.floor((CIRC - xa) / CIRC))
    inside = np.zeros(width, bool)
    for k in range(k_lo, k_hi + 1):
        v = xm - k * CIRC
        inside |= (v >= xa) & (v <= xb)
    return inside


def _ymask(ya, yb):
    ym = (np.arange(H, dtype=np.float32) + 0.5) / PY
    return (ym >= ya) & (ym <= yb)


def draw_dragon(field, hole_field, prims):
    """Stamp one dragon into the distance field."""
    for p in prims:
        if p[0] == "cap":
            _, a, b, ra, rb = p
            stroke(field, a, b, ra, rb)
        elif p[0] == "box":
            _, c, half, ang = p
            box_stamp(field, c, half, ang)
        elif p[0] == "hole":
            _, c, r, depth = p
            stamp(hole_field, c[0] - r - 0.1, c[0] + r + 0.1,
                  c[1] - r - 0.1, c[1] + r + 0.1,
                  lambda px, py, c=c, r=r, d=depth: -sdf_disc(px, py, c, r) - d,
                  op="max")


def sunmoon_field():
    """Distance field for the sun disc (east) and the crescent moon (west)."""
    field = np.full((H, W), BIG, np.float32)
    sun = (CIRC * 0.25, 26.8)
    moon = (CIRC * 0.75, 26.8)
    stamp(field, sun[0] - 1.4, sun[0] + 1.4, sun[1] - 1.4, sun[1] + 1.4,
          lambda px, py: sdf_disc(px, py, sun, 0.60))
    for k in range(12):
        a = 2.0 * math.pi * k / 12 + 0.13
        p0 = (sun[0] + 0.62 * math.cos(a), sun[1] + 0.62 * math.sin(a))
        p1 = (sun[0] + 1.00 * math.cos(a), sun[1] + 1.00 * math.sin(a))
        stroke(field, p0, p1, 0.085, 0.02)
    stamp(field, moon[0] - 1.0, moon[0] + 1.0, moon[1] - 1.0, moon[1] + 1.0,
          lambda px, py: sdf_disc(px, py, moon, 0.55))
    cut = (moon[0] + 0.30, moon[1] + 0.16)
    stamp(field, moon[0] - 1.0, moon[0] + 1.0, moon[1] - 1.0, moon[1] + 1.0,
          lambda px, py: -sdf_disc(px, py, cut, 0.50), op="max")
    return field


def downsample2(a):
    """2x2 box average of a float array."""
    h, w = a.shape[:2]
    hh, ww = h // 2 * 2, w // 2 * 2
    b = a[:hh, :ww].reshape(hh // 2, 2, ww // 2, 2).mean(axis=(1, 3))
    return b


def build_height():
    """Assemble the relief height field (metres) and the masks.

    Returns (h, masks) where h is the float32 height at the full 4096 x 8192
    raster and masks holds the uint8 masks the map assembly needs:
      dm the dragons, gm the recessed bronze ground, hm the cloud hooks,
      mm the engraved running fret, cc the carved scales, hole the eye
      sockets, sm the sun and the moon, bronze the dark-relief mask.
    """
    pans = panels()
    # --- the nine dragons ------------------------------------------------
    dd = np.full((H, W), BIG, np.float32)
    holes = np.full((H, W), -BIG, np.float32)
    cd = np.full((H, W), BIG, np.float32)
    for idx, (r, k, a0, handed, ty0, ty1) in enumerate(pans):
        rng = np.random.RandomState(1000 + idx)
        width = (0.47 + 0.11 * rng.rand()) * (0.90 + 0.20 * rng.rand())
        pts, length = dragon_spine(a0, ty0 + GY, ty1 - GY, width,
                                   1000 + idx, COL_R, handed)
        draw_dragon(dd, holes, dragon_prims(pts, width, 1000 + idx, COL_R))
        for p in chevron_prims(pts, width, COL_R):
            _, a, b, ra, rb = p
            stroke(cd, a, b, ra, rb)
        print("  dragon %d: len %.2f m, body %.2f m, %s"
              % (idx + 1, length, width, "cw" if handed > 0 else "ccw"))
    dm = _u8(smoothstep(np.clip(-dd / BEVEL, 0.0, 1.0)))
    del dd
    gc.collect()
    hole = _u8(smoothstep(np.clip(holes / 0.06, 0.0, 1.0)))
    del holes
    gc.collect()
    cc = _u8(smoothstep(np.clip((0.013 - cd) / 0.010, 0.0, 1.0)))
    del cd
    gc.collect()
    # --- the ground, the cloud hooks and the running fret -----------------
    gm = np.zeros((H, W), np.uint8)
    isl = np.zeros((H, W), bool)
    hf = np.full((H, W), BIG, np.float32)
    mf = np.full((H, W), BIG, np.float32)
    for idx, (r, k, a0, handed, ty0, ty1) in enumerate(pans):
        s0, s1 = panel_sector(a0, handed)
        xa = math.radians(s0) * COL_R + GX
        xb = math.radians(s1) * COL_R - GX
        ya, yb = ty0 + GY, ty1 - GY
        gm[np.ix_(_ymask(ya, yb), _xmask(xa, xb))] = 1
        for (path, cx, cy, rad) in cloud_hooks(xa, xb, ya, yb, 500 + idx):
            path_stroke(hf, path, 0.055, 0.055)
            disc_mask(isl, cx, cy, rad)
        path_stroke(mf, fret_path(xa, xb, ya, yb), FRET_W * 0.5, FRET_W * 0.5)
        print("  panel %d: ground x %.2f..%.2f, y %.2f..%.2f"
              % (idx + 1, xa, xb, ya, yb))
    gm = np.where(isl, np.uint8(0), gm)
    hm = _u8(smoothstep(np.clip(-hf / BEVEL, 0.0, 1.0)))
    del hf
    gc.collect()
    mm = _u8(smoothstep(np.clip((FRET_W * 0.5 - mf) / (FRET_W * 0.7), 0.0, 1.0)))
    del mf
    gc.collect()
    # the fret is engraved into the ground only, and it stops at the dragon
    mm = np.where((gm > 0) & (dm == 0), mm, np.uint8(0)).astype(np.uint8)
    # --- the sun and the moon --------------------------------------------
    sd = sunmoon_field()
    sm = _u8(smoothstep(np.clip(-sd / BEVEL, 0.0, 1.0)))
    del sd
    gc.collect()
    # --- the height field -------------------------------------------------
    dmf = dm.astype(np.float32) / 255.0
    hmf = hm.astype(np.float32) / 255.0
    gmf = gm.astype(np.float32) / 255.0
    mmf = mm.astype(np.float32) / 255.0
    ccf = cc.astype(np.float32) / 255.0
    holef = hole.astype(np.float32) / 255.0
    smf = sm.astype(np.float32) / 255.0
    h = (RELIEF * dmf + HOOK_DEPTH * hmf - GROUND_DEPTH * gmf
         - FRET_DEPTH * mmf - SCALE_DEPTH * ccf * dmf - EYE_DEPTH * holef
         + SUN_DEPTH * smf)
    ys = (np.arange(H, dtype=np.float32) / PY)[:, None]
    for lvl in PANEL_Y:
        h -= 0.05 * np.clip(1.0 - np.abs(ys - lvl) / 0.30, 0.0, 1.0)
    del dmf, hmf, gmf, mmf, ccf, holef, smf
    gc.collect()
    bronze = np.where((gm > 0) | (dm > 0) | (hm > 0) | (sm > 0),
                       np.uint8(255), np.uint8(0))
    masks = {"dm": dm, "gm": gm, "hm": hm, "mm": mm, "cc": cc,
             "hole": hole, "sm": sm, "bronze": bronze}
    return h, masks


def main():
    """Write the pillar map set (see tex_pillar_maps for the map assembly)."""
    import tex_pillar_maps
    tex_pillar_maps.main()


if __name__ == "__main__":
    main()
