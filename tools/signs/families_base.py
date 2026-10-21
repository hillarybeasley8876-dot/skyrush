"""The shared base of the props surface families (unit: props).

The colour helpers and the noise features every family is built from: the
seamless blend of a photo set, the scratches, the paint chips and the
domain-warped Voronoi of the bark plates.

    /usr/bin/python3 tools/signs/families_base.py
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import imwrite as IW  # noqa: E402
import surf_lib as S  # noqa: E402

ROOT = os.path.expanduser("~/m/skyrush")
sys.path.insert(0, os.path.join(ROOT, "blender"))
from props import atlas  # noqa: E402

TILE = 1024
METRES = atlas.FAMILY_METRES          # metres one tile covers
PX_PER_M = TILE / METRES
CORE_TEX = os.path.join(ROOT, "game", "assets", "textures")

# ------------------------------------------------------------------ colour
def srgb_to_linear(c):
    """sRGB 0..1 -> linear 0..1 (the value a vertex tint has to carry)."""
    c = np.asarray(c, dtype=np.float32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    """linear 0..1 -> sRGB 0..1."""
    c = np.clip(np.asarray(c, dtype=np.float32), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1.0 / 2.4) - 0.055)


def _norm_mean(arr, target):
    """Scale a linear array so its mean equals `target`."""
    mean = float(arr.mean())
    if mean < 1e-6:
        return arr * target
    return arr * (target / mean)


def _norm_albedo(linear, target_linear=atlas.BASE_LINEAR["metal"]):
    """Normalise a linear albedo and return it ready to store (sRGB values).

    The base of a family is a light grey: the colour of a part comes from its
    vertex tint, so the base must be bright enough for the tint to be exact.
    The loop converges on the DECODED mean (what Godot and Blender see), not on
    the mean of the stored bytes.
    """
    a = np.clip(np.asarray(linear, dtype=np.float32), 0.0, 4.0)
    for _ in range(4):
        s = linear_to_srgb(a)
        decoded = float(srgb_to_linear(s).mean())
        if decoded < 1e-6:
            break
        a = a * (target_linear / decoded)
    return linear_to_srgb(a)


# ------------------------------------------------------------------ helpers
def _seamless(arr, size=TILE):
    """Make an image tile: cross-fade it with a half-shifted copy.

    The photo sets are not seamless, so they are blended with a rolled copy in
    a feathered border band.  The result repeats without a visible join.
    """
    gray = arr.ndim == 2
    if gray:
        arr = arr[:, :, None]
    if arr.shape[2] == 1:
        arr = np.repeat(arr, 3, axis=2)
    src = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGB")
    a = np.asarray(src.resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0
    rolled = np.roll(a, (size // 2, size // 2), axis=(0, 1))
    band = size // 4
    ramp = np.linspace(0.0, 1.0, band, dtype=np.float32)
    ramp = ramp * ramp * (3.0 - 2.0 * ramp)
    m = np.zeros((size, size), dtype=np.float32)
    m[:band, :] = ramp[:, None]
    m[-band:, :] = ramp[::-1, None]
    m[:, :band] = np.maximum(m[:, :band], ramp[None, :])
    m[:, -band:] = np.maximum(m[:, -band:], ramp[None, ::-1])
    out = a * (1.0 - m[:, :, None]) + rolled * m[:, :, None]
    return out[:, :, 0] if gray else out


def _core_gray(tid, kind):
    """One channel of a core CC0 map as a float array (0..1), or None."""
    for ext in ("jpg", "png"):
        path = os.path.join(CORE_TEX, tid, "%s_%s.%s" % (tid, kind, ext))
        if os.path.exists(path):
            img = Image.open(path).convert("L")
            return np.asarray(img, dtype=np.float32) / 255.0
    return None


def _core_rgb(tid, kind):
    """One CC0 map as a float RGB array (0..1), or None."""
    for ext in ("jpg", "png"):
        path = os.path.join(CORE_TEX, tid, "%s_%s.%s" % (tid, kind, ext))
        if os.path.exists(path):
            img = Image.open(path).convert("RGB")
            return np.asarray(img, dtype=np.float32) / 255.0
    return None


def _scratches(count, seed, length=(0.05, 0.35), width=1):
    """Hairline scratches as a signed layer (bright and dark lines)."""
    layer = S.scratch_layer(TILE, TILE, count, seed, length=length, width=width, value=0.8)
    return S.mask_to_array(layer) - 0.5


def _chips(seed, count=90, radius=(1.0, 4.0), coverage=0.02):
    """A mask of small paint chips: bare metal shows through."""
    rng = np.random.default_rng(seed)
    img = Image.new("L", (TILE, TILE), 0)
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    for _ in range(count):
        x = rng.uniform(0, TILE)
        y = rng.uniform(0, TILE)
        r = rng.uniform(*radius)
        for ox in (-TILE, 0, TILE):
            for oy in (-TILE, 0, TILE):
                d.ellipse([x + ox - r, y + oy - r, x + ox + r, y + oy + r], fill=255)
    return S.mask_to_array(img)


def _chips_irregular(seed, count=60, radius=(3.0, 12.0)):
    """A mask of paint chips with a torn, irregular outline."""
    rng = np.random.default_rng(seed)
    img = Image.new("L", (TILE, TILE), 0)
    d = ImageDraw.Draw(img)
    for _ in range(count):
        cx = rng.uniform(0, TILE)
        cy = rng.uniform(0, TILE)
        r = rng.uniform(*radius)
        sides = rng.integers(5, 8)
        ang0 = rng.uniform(0.0, math.tau)
        pts = []
        for i in range(sides):
            a = ang0 + math.tau * i / sides
            rr = r * rng.uniform(0.55, 1.25)
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        for ox in (-TILE, 0, TILE):
            for oy in (-TILE, 0, TILE):
                d.polygon([(px + ox, py + oy) for px, py in pts], fill=255)
    return S.mask_to_array(img)


def _grime(seed, cells=4, amount=0.22):
    """Low frequency dirt: the macro variation that breaks up a tiled surface."""
    blotch = S.pnoise(TILE, TILE, cells, 4, seed)
    mask = np.clip((blotch - 0.40) * 1.8, 0.0, 1.0)
    return mask * amount


def _cell_warp(cells, seed, strength=0.45):
    """A periodic displacement (in cell units) for every cell of a grid.

    The displacement is a function of the WRAPPED cell, so the Voronoi of the
    warped seeds still tiles: the cell at the edge of the tile is the same cell
    as the one at the other edge.
    """
    wx = S.pnoise(cells, cells, 3, 2, seed)
    wy = S.pnoise(cells, cells, 3, 2, seed + 17)
    return ((wx - 0.5) * 2.0 * strength, (wy - 0.5) * 2.0 * strength)


def _voronoi_warped(cells, seed, strength=0.45, jitter=0.85):
    """Voronoi of domain-warped seeds.

    Returns (distance to the nearest seed, distance to the second nearest,
    cell id).  The second distance is small at the cell borders, which is where
    the peeled rim of a bark plate sits.
    """
    rng = np.random.default_rng(seed)
    jit = rng.random((cells, cells, 2)).astype(np.float32) * jitter
    wx, wy = _cell_warp(cells, seed + 31, strength)
    xs = (np.arange(TILE, dtype=np.float32) / float(TILE)) * cells
    ys = (np.arange(TILE, dtype=np.float32) / float(TILE)) * cells
    cx = np.floor(xs).astype(np.int32)
    cy = np.floor(ys).astype(np.int32)
    best = np.full((TILE, TILE), 1e9, dtype=np.float32)
    second = np.full((TILE, TILE), 1e9, dtype=np.float32)
    ids = np.zeros((TILE, TILE), dtype=np.int32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ni = (cx + dx)[None, :]
            nj = (cy + dy)[:, None]
            im, jm = ni % cells, nj % cells
            sx = jit[jm, im, 0] + wx[jm, im] + ni
            sy = jit[jm, im, 1] + wy[jm, im] + nj
            d = (xs[None, :] - sx) ** 2 + (ys[:, None] - sy) ** 2
            hit = d < best
            second = np.where(hit, best, np.minimum(second, best))
            best = np.where(hit, d, best)
            ids = np.where(hit, (jm * cells + im).astype(np.int32), ids)
    return np.sqrt(best), np.sqrt(second), ids

