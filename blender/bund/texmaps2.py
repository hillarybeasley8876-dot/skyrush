"""The surfaces of the Bund: the promenade paving, the flood wall, the roof felt, the
lawn, the hedge and the planters (bund unit).

The concrete and the paving are built on the CC0 scans of the shared library, so the
flood wall and the promenade read as real surfaces.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from bund.texbase import fbm, save_set, value_noise  # noqa: E402
from bund.texmaps import scan_blocks  # noqa: E402


def make_paving(prefix="paving", size=2048, tile_m=1.8, seed=1910):
    """Sawn granite promenade slabs: the CC0 paving scan, gum spots, stains and a joint."""
    rng = np.random.default_rng(seed)
    stone = scan_blocks("PavingStones144/PavingStones144_diff.jpg", size, tile_m,
                        (tile_m, tile_m), seed, src=512)
    base = stone.mean(axis=2)
    px_m = size / tile_m
    u = np.arange(size)[None, :] / px_m
    v = np.arange(size)[:, None] / px_m
    n = 3
    fx = (u * n) % 1.0
    fy = (v * n) % 1.0
    d = np.minimum(np.minimum(fx, 1 - fx), np.minimum(fy, 1 - fy)) / n
    joint = np.clip(1.0 - d / 0.014, 0.0, 1.0)
    grit = fbm(size, 320, rng, 3) - 0.5
    blotch = fbm(size, 7, rng, 3) - 0.5
    gum = (value_noise(size, 40, rng) > 0.955).astype(float)
    stain = fbm(size, 5, rng, 4) - 0.5
    b = np.array([118.0, 116.0, 110.0])
    # the low frequency content of the scan carries a dark strip that repeats as black
    # rectangles over the deck, so only its fine grain is kept and every slab gets its
    # own tone instead
    tone = (base - base.mean()) * 0.25
    slab_u = np.floor(u * 3.0)
    slab_v = np.floor(v * 3.0)
    slab_tone = np.sin(slab_u * 12.9 + slab_v * 78.2) * 7.0
    v0 = tone + slab_tone + blotch * 12.0 + grit * 13.0
    diff = np.stack([b[0] + v0, b[1] + v0, b[2] + v0 * 0.96], axis=-1)
    diff *= (1.0 - stain[:, :, None] * 0.22)
    diff *= (1.0 - gum[:, :, None] * 0.30)
    m = joint[:, :, None]
    diff = diff * (1 - m) + np.array([72.0, 70.0, 66.0])[None, None, :] * m
    relief = fbm(size, 80, rng, 2) - 0.5
    height = -joint * 0.7 + relief * 0.95 + grit * 0.14
    rough = np.clip(0.60 + 0.14 * (grit + 0.5) + 0.20 * joint, 0.4, 0.9)
    save_set(prefix, diff, height, rough, strength=3.0, rough_size=1024)


def make_wall(prefix="wall", size=2048, tile_m=2.4, seed=1989):
    """The flood wall's concrete: the CC0 wall scan, the formwork panels, the tie holes,
    the salt bloom and the run-off streaks."""
    rng = np.random.default_rng(seed)
    stone = scan_blocks("concrete_wall_008/concrete_wall_008_diff.jpg", size, tile_m,
                        (tile_m, tile_m), seed, src=512)
    base = stone.mean(axis=2)
    px_m = size / tile_m
    u = np.arange(size)[None, :] / px_m
    v = np.arange(size)[:, None] / px_m
    fx = (u / 1.2) % 1.0
    fy = (v / 2.4) % 1.0
    edge = np.minimum(np.minimum(fx, 1 - fx) * 1.2, np.minimum(fy, 1 - fy) * 2.4)
    form = np.clip(1.0 - edge / 0.015, 0.0, 1.0)          # the formwork board lines
    tie = np.zeros((size, size))
    yy, xx = np.mgrid[0:size, 0:size]
    for ty in (0.4, 1.2, 2.0):
        for tx in (0.3, 0.9):
            px = int(tx / tile_m * size) % size
            py = int(ty / tile_m * size) % size
            dd = np.sqrt((xx - px) ** 2 + (yy - py) ** 2) / px_m
            tie = np.maximum(tie, np.clip(1.0 - (dd - 0.015) / 0.01, 0.0, 1.0))
    grit = fbm(size, 260, rng, 3) - 0.5
    fine = fbm(size, 560, rng, 2) - 0.5
    efflo = np.clip(fbm(size, 40, rng, 4) * 1.6 - 0.25, 0.0, 1.0)   # salt bloom
    streak = value_noise(size, 6, rng)
    for _ in range(9):
        streak = 0.5 * (streak + np.roll(streak, size // 14, axis=0))
    streak = (streak - streak.min()) / (streak.ptp() + 1e-6)
    fall = np.linspace(1.0, 0.0, size)[:, None]
    # the dossier's concrete is #7A7874; the scan is brighter, so it is pulled down
    tone = 122.0 - base.mean()
    v0 = tone + grit * 32.0 + fine * 38.0 - streak * 18.0 * fall[:, 0][:, None]
    diff = np.stack([122.0 + v0, 120.0 + v0, 116.0 + v0 * 0.92], axis=-1)
    diff = diff * (1.0 - form[:, :, None] * 0.20)
    diff = diff * (1.0 - tie[:, :, None] * 0.45)
    diff += np.array([196.0, 196.0, 192.0]) * (efflo * 0.16)[:, :, None]
    relief = fbm(size, 70, rng, 2) - 0.5
    height = -form * 0.5 - tie * 0.8 + relief * 1.0 + grit * 0.30 + fine * 0.25
    rough = np.clip(0.80 + 0.10 * (grit + 0.5) + 0.10 * efflo, 0.5, 0.98)
    save_set(prefix, diff, height, rough, strength=3.4, rough_size=1024)


def make_roof_tar(prefix="roof_tar", size=1024, seed=1954):
    """Dark roofing felt: the lapping seams of the rolls, the gravel and the patches."""
    rng = np.random.default_rng(seed)
    grit = fbm(size, 120, rng, 3) - 0.5
    gravel = np.clip(fbm(size, 220, rng, 2) * 2.2, 0.0, 1.0)
    patch = np.clip(fbm(size, 8, rng, 3) * 1.8, 0.0, 1.0)
    # the lapping seams of the felt rolls, every 1 m
    seam = np.zeros((size, size))
    for k in range(0, size, size // 2):
        seam[k:k + 3, :] = 1.0
    seam = np.clip(seam + np.clip((value_noise(size, 60, rng) - 0.8) * 6.0, 0.0, 1.0), 0.0, 1.0)
    base = np.array([54.0, 53.0, 52.0])
    v = grit * 18.0 + patch * 14.0 + gravel * 12.0
    diff = np.stack([base[0] + v, base[1] + v, base[2] + v], axis=-1)
    diff = diff * (1 - seam[:, :, None] * 0.35)
    height = grit * 0.25 + patch * 0.12 + gravel * 0.55 - seam * 0.6
    rough = np.clip(0.90 - 0.08 * patch + 0.06 * gravel, 0.6, 1.0)
    save_set(prefix, diff, height, rough, strength=4.0, rough_size=1024)


def make_grass(prefix="grass", size=1024, seed=1995):
    """The lawn between the road and the stairs: mown grass with clumps and worn patches."""
    rng = np.random.default_rng(seed)
    blade = fbm(size, 420, rng, 3) - 0.5
    clump = np.clip(fbm(size, 60, rng, 4) * 2.2, 0.0, 1.0)
    patch = fbm(size, 9, rng, 3) - 0.5
    dry = fbm(size, 22, rng, 3) - 0.5
    base = np.array([58.0, 86.0, 44.0])
    v = blade * 26.0 + patch * 16.0 + dry * 12.0 + clump * 20.0
    diff = np.stack([base[0] + v * 0.7, base[1] + v, base[2] + v * 0.5], axis=-1)
    height = blade * 0.6 + clump * 0.7 + patch * 0.15
    rough = np.clip(0.82 + 0.12 * (blade + 0.5), 0.6, 1.0)
    save_set(prefix, diff, height, rough, strength=3.0, rough_size=1024)


def make_hedge(prefix="hedge", size=1024, seed=1996):
    """A clipped hedge: dense small leaves."""
    rng = np.random.default_rng(seed)
    leaf = np.clip(fbm(size, 90, rng, 4) * 2.6, 0.0, 1.0)
    veins = np.clip(1.0 - np.abs(fbm(size, 200, rng, 3) - 0.5) * 11.0, 0.0, 1.0)
    base = np.array([42.0, 68.0, 34.0])
    v = leaf * 34.0 - veins * 20.0
    diff = np.stack([base[0] + v * 0.6, base[1] + v, base[2] + v * 0.4], axis=-1)
    height = veins * 0.4 + leaf * 0.3
    rough = np.clip(0.80 + 0.14 * leaf, 0.5, 1.0)
    save_set(prefix, diff, height, rough, strength=1.2, rough_size=1024)


def make_foliage(prefix="foliage", size=1024, seed=1984):
    """A leaf atlas for the planters."""
    rng = np.random.default_rng(seed)
    leaf = np.clip(fbm(size, 24, rng, 4) * 2.4, 0.0, 1.0)
    veins = np.clip(1.0 - np.abs(fbm(size, 60, rng, 3) - 0.5) * 9.0, 0.0, 1.0)
    base = np.array([58.0, 92.0, 40.0])
    v = leaf * 40.0 - veins * 18.0
    diff = np.stack([base[0] + v * 0.5, base[1] + v, base[2] + v * 0.4], axis=-1)
    height = veins * 0.3 + leaf * 0.2
    rough = np.clip(0.75 + 0.15 * leaf, 0.5, 1.0)
    save_set(prefix, diff, height, rough, strength=1.0, rough_size=1024)
