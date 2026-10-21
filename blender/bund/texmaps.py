"""Stone, brick, tile, glass and window-interior maps for the Bund (bund unit).

The ashlar is the district's signature surface: 1.2 x 0.6 m granite blocks in a 2.4 m tile
at 2048 px. Every block takes its colour from a crop of the CC0 granite scan in the shared
library (game/assets/textures/granite_bund), so the stone reads as real quarried granite
and not as a flat procedural field, and the fine grain, the sooty joints, the chamfered
arrises and the rain streaks are layered on top.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from bund.texbase import fbm, save, save_set, value_noise  # noqa: E402

LIB = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), "game", "assets", "textures")


def load_scan(name, size=None):
    """A CC0 scan from the shared library as a float array in 0..1."""
    from PIL import Image
    im = Image.open(os.path.join(LIB, name)).convert("RGB")
    if size is not None and im.size != (size, size):
        im = im.resize((size, size), Image.BILINEAR)
    return np.asarray(im, dtype=float) / 255.0


def scan_blocks(scan_name, size, tile_m, block, seed, src=256):
    """Tile a CC0 scan with one crop per block: the real stone, one crop per block.

    The crop is resized to the block's pixel size, so the scan's own grain (and not a
    procedural field) is what the facade shows."""
    from PIL import Image
    rng = np.random.default_rng(seed)
    im = Image.open(os.path.join(LIB, scan_name)).convert("RGB")
    sw, sh = im.size
    out = np.zeros((size, size, 3), dtype=float)
    px_m = size / tile_m
    bw, bh = block
    ncol = max(1, int(round(tile_m / bw)))
    nrow = max(1, int(round(tile_m / bh)))
    for r in range(nrow):
        for c in range(ncol):
            ox = int(rng.integers(0, max(1, sw - src)))
            oy = int(rng.integers(0, max(1, sh - src)))
            crop = im.crop((ox, oy, ox + src, oy + src)).resize(
                (int(bw * px_m), int(bh * px_m)), Image.BILINEAR)
            x0 = int(c * bw * px_m)
            y0 = int(r * bh * px_m)
            w = min(int(bw * px_m), size - x0)
            h = min(int(bh * px_m), size - y0)
            if w <= 0 or h <= 0:
                continue
            out[y0:y0 + h, x0:x0 + w] = np.asarray(crop, dtype=float)[:h, :w]
    return out


def _hash2(a, b):
    """A deterministic pseudo-random value in [0,1) per integer cell."""
    return np.abs(np.sin(a * 12.9898 + b * 78.233) * 43758.5453) % 1.0


def make_ashlar(prefix, base=(171.0, 170.0, 163.0), size=2048, tile_m=2.4,
                block=(1.2, 0.6), joint_m=0.02, soot=0.55, seed=1916, strength=3.6):
    """Granite ashlar: every block is a crop of the CC0 granite scan, with 2 cm sooty
    joints, chamfered arrises, a per-block tone and the rain streaks of Leaking004."""
    rng = np.random.default_rng(seed)
    stone = scan_blocks("granite_bund/granite_bund_diff.jpg", size, tile_m, block, seed)
    px_m = size / tile_m
    bw, bh = block
    u = np.arange(size)[None, :] / px_m
    v = np.arange(size)[:, None] / px_m
    row = np.floor(v / bh)
    col = np.floor(u / bw + (row % 2.0) * 0.5).astype(int)
    tone = (_hash2(col, row) - 0.5) * 2.0            # the per-block albedo +-5 %
    # the block colours are matched to the dossier's mean (#ABAAA3)
    gain = np.array(base) / np.maximum(1e-6, stone.reshape(-1, 3).mean(axis=0))
    block_col = stone * gain
    # the fine grain, the chips and the dark flecks
    grain = fbm(size, 220, rng, 3) - 0.5
    speck = (value_noise(size, 900, rng) - 0.5) * 0.9
    dark = (value_noise(size, 700, rng) > 0.972).astype(float)
    light = (value_noise(size, 640, rng) > 0.982).astype(float)
    v0 = tone * 9.0 + grain * 22.0 + speck * 14.0 - dark * 30.0 + light * 26.0
    # the joint geometry
    fx = (u / bw + (row % 2.0) * 0.5) % 1.0
    fy = (v / bh) % 1.0
    d = np.minimum(np.minimum(fx, 1.0 - fx) * bw, np.minimum(fy, 1.0 - fy) * bh)
    joint = np.clip(1.0 - d / joint_m, 0.0, 1.0)                    # 1 inside the joint
    arris = np.clip(1.0 - d / 0.022, 0.0, 1.0)                    # 2.2 cm chamfer
    # the rain streaks: the opacity of the Leaking004 scan is the mask
    leak = load_scan("Leaking004/Leaking004_opacity.jpg", size).mean(axis=2)
    fall = np.linspace(1.0, 0.0, size)[:, None]
    # the grime of the SurfaceImperfections scan
    grime = load_scan("SurfaceImperfections001/SurfaceImperfections001_diff.jpg", size)
    grime = grime.mean(axis=2)
    diff = block_col + v0[:, :, None] * np.array([1.0, 0.97, 0.9])[None, None, :]
    diff *= (1.0 - joint[:, :, None] * (1.0 - soot))          # soot in the joints
    diff *= (1.0 - arris[:, :, None] * 0.06)                 # the arris catches the light
    diff *= (1.0 - 0.16 * (leak * fall)[:, :, None])         # drip streaks
    diff *= (1.0 - 0.12 * (grime - grime.mean())[:, :, None])
    # the height carries the joints and a mid-scale relief; the fine grain stays in the
    # albedo, or the normal map would be sandpaper
    relief = fbm(size, 90, rng, 2) - 0.5
    height = -joint * 0.9 + arris * 0.55 + relief * 1.05 - dark * 0.10
    rough = np.clip(0.50 + tone * 0.08 + 0.12 * (grain + 0.5) + 0.22 * joint, 0.4, 0.85)
    save_set(prefix, diff, height, rough, strength=strength, rough_size=1024)


def make_brick(prefix, base=(162.0, 73.0, 58.0), size=2048, tile_m=1.2,
               brick=(0.24, 0.07), joint_m=0.012, seed=1897, strength=3.2):
    """Red brick: per-brick hue +-8 %, a mortar recessed 10 mm, chipped arrises and soot."""
    rng = np.random.default_rng(seed)
    px_m = size / tile_m
    bw, bh = brick
    u = np.arange(size)[None, :] / px_m
    v = np.arange(size)[:, None] / px_m
    row = np.floor(v / bh)
    col = np.floor(u / bw + (row % 2.0) * 0.5)
    # the per-brick hue: the red channel wanders, the mortar stays neutral
    hue = (_hash2(col, row) - 0.5) * 2.0
    tone = (_hash2(col + 31, row + 7) - 0.5) * 2.0
    tone2 = (_hash2(col * 3 + 11, row * 5 + 2) - 0.5) * 2.0
    fx = (u / bw + (row % 2.0) * 0.5) % 1.0
    fy = (v / bh) % 1.0
    d = np.minimum(np.minimum(fx, 1.0 - fx) * bw, np.minimum(fy, 1.0 - fy) * bh)
    joint = np.clip(1.0 - d / joint_m, 0.0, 1.0)
    chip = np.clip((value_noise(size, 400, rng) - 0.62) * 4.0, 0.0, 1.0) * (1.0 - joint)
    speck = fbm(size, 260, rng, 3) - 0.5
    fine = fbm(size, 620, rng, 2) - 0.5
    b = np.array(base, dtype=float)
    vv = tone * 22.0 + tone2 * 14.0 + speck * 32.0 + fine * 32.0
    diff = np.stack([b[0] * (1.0 + hue * 0.12) + vv,
                     b[1] * (1.0 - hue * 0.07) + vv * 0.8,
                     b[2] * (1.0 - hue * 0.06) + vv * 0.7], axis=-1)
    mortar = np.array([136.0, 133.0, 128.0])
    m = joint[:, :, None]
    diff = diff * (1 - m) + mortar[None, None, :] * m
    diff *= (1.0 - joint[:, :, None] * 0.42)                  # soot
    diff *= (1.0 - chip[:, :, None] * 0.35)                  # the chipped arrises
    relief = fbm(size, 80, rng, 2) - 0.5
    height = -joint * 0.85 + relief * 0.75 + speck * 0.45 + fine * 0.35 - chip * 0.30
    rough = np.clip(0.74 + 0.10 * (speck + 0.5) - 0.10 * joint + 0.10 * chip, 0.5, 0.95)
    save_set(prefix, diff, height, rough, strength=strength, rough_size=1024)


def make_glazed_tile(prefix, base=(236.0, 232.0, 222.0), size=1024, tile_m=1.0,
                     grout=(150.0, 146.0, 138.0), seed=1924, soot=0.0):
    """Small glazed tiles (0.2 m) with grime in the joints.

    Every tile gets its own tone (the hue shifts by up to 8 %), the joints are recessed
    and the soot of the city (the Broadway Mansions is a brown brick block) settles in
    the hollows."""
    rng = np.random.default_rng(seed)
    px_m = size / tile_m
    u = np.arange(size)[None, :] / px_m
    v = np.arange(size)[:, None] / px_m
    n = 5
    fx = (u * n) % 1.0
    fy = (v * n) % 1.0
    d = np.minimum(np.minimum(fx, 1 - fx), np.minimum(fy, 1 - fy)) / n
    joint = np.clip(1.0 - d / 0.008, 0.0, 1.0)
    grime = fbm(size, 14, rng, 4) - 0.5
    spec = fbm(size, 260, rng, 2) - 0.5
    relief = fbm(size, 80, rng, 2) - 0.5
    # one tone per tile: the hue of a fired tile is never exactly the same
    tile_u = np.floor(u * n)
    tile_v = np.floor(v * n)
    hue = np.sin(tile_u * 12.9 + tile_v * 78.2) * 0.08
    tone = np.repeat(hue, 1, axis=0)
    b = np.array(base, dtype=float)
    vv = grime * 15.0 + spec * 9.0
    diff = np.stack([b[0] * (1.0 + tone) + vv, b[1] * (1.0 + tone * 0.6) + vv,
                     b[2] * (1.0 + tone * 0.3) + vv * 1.1], axis=-1)
    m = joint[:, :, None]
    diff = diff * (1 - m) + np.array(grout)[None, None, :] * m
    # the soot: it settles in the joints and in the low spots
    if soot > 0.0:
        dirt = np.clip(fbm(size, 6, rng, 4) * 1.6 - 0.2, 0.0, 1.0)
        diff = diff * (1.0 - soot * 0.55 * (dirt * 0.6 + joint * 0.7)[:, :, None])
    height = -joint * 0.75 + spec * 0.22 + relief * 0.7
    rough = np.clip(0.26 + 0.14 * (grime + 0.5) + 0.34 * joint, 0.15, 0.8)
    save_set(prefix, diff, height, rough, strength=3.0, rough_size=1024)


def make_interior_atlas(prefix, size=2048, cells=4, seed=1955):
    """A 4x4 atlas of window interiors: curtains, blinds, ceiling lamps, shelves, desks.

    One cell per window (UV offset), seen through the glass. Warm lamps in a third of them."""
    rng = np.random.default_rng(seed)
    cs = size // cells
    atlas = np.zeros((size, size, 3), dtype=float)
    height = np.zeros((size, size))
    kinds = ["curtain", "blind", "lamp", "desk", "shelf", "curtain", "lamp", "blind",
             "desk", "shelf", "curtain", "lamp", "blind", "desk", "shelf", "lamp"]
    for idx in range(cells * cells):
        kind = kinds[idx % len(kinds)]
        r0, c0 = (idx // cells) * cs, (idx % cells) * cs
        u = np.arange(cs)[None, :] / cs
        v = np.arange(cs)[:, None] / cs
        warm = np.array([255.0, 176.0, 92.0])
        cool = np.array([132.0, 114.0, 92.0])
        if kind == "curtain":
            fold = 0.5 + 0.5 * np.sin(u * 34.0)
            col = cool * (0.25 + 0.5 * fold)[:, :, None] * np.ones((cs, cs, 1))
            col = col * 0.7 + warm * 0.10
        elif kind == "blind":
            slat = (v * 26.0) % 1.0
            col = cool * (0.30 + 0.35 * (slat < 0.5))[:, :, None] * np.ones((cs, cs, 1))
        elif kind == "lamp":
            glow = np.exp(-(((u - 0.5) ** 2 + (v - 0.35) ** 2) * 26.0))
            col = cool * 0.22 + warm * (0.95 * glow)[:, :, None]
        elif kind == "desk":
            col = np.array([70.0, 56.0, 44.0]) * np.ones((cs, cs, 1))
            desk = np.broadcast_to((v > 0.55) & (v < 0.75), (cs, cs))
            col[desk] = np.array([126.0, 98.0, 66.0])
            glow = np.exp(-(((u - 0.5) ** 2 + (v - 0.3) ** 2) * 30.0))
            col += warm * (0.5 * glow)[:, :, None]
        else:                                    # shelf
            col = np.array([58.0, 46.0, 38.0]) * np.ones((cs, cs, 1))
            shelf = (v * 9.0) % 1.0
            col[np.broadcast_to(shelf < 0.12, (cs, cs))] = np.array([104.0, 82.0, 58.0])
        col = col + (rng.random() - 0.5) * 5.0
        atlas[r0:r0 + cs, c0:c0 + cs] = col
        height[r0:r0 + cs, c0:c0 + cs] = 0.4 + 0.1 * rng.random((cs, cs))
    atlas = np.clip(atlas * 1.4, 0, 255)
    rough = np.full((size, size), 0.85)
    save_set(prefix, atlas, height, rough, strength=0.4, rough_size=1024)
    # the emissive twin: the same atlas lit warm (#FF9F40), which is what a lit pane shows
    glow = atlas * np.array([1.0, 0.62, 0.25]) * 1.9
    save("interior_glow_diff.jpg", np.clip(glow, 0, 255))
