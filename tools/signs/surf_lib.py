"""Noise and feature helpers for the props surface atlas (unit: props).

Everything here is *periodic*: a tile generated with these functions repeats
without a seam, which is what lets a 1 m tile be wrapped over a 30 m roof
without the join showing.
"""
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def _value_layer(w, h, cells, rng):
    """One octave of periodic value noise (bilinear, smoothstepped)."""
    g = rng.random((cells, cells)).astype(np.float32)
    xs = np.arange(w, dtype=np.float32) * (cells / float(w))
    ys = np.arange(h, dtype=np.float32) * (cells / float(h))
    x0 = np.floor(xs).astype(np.int32)
    y0 = np.floor(ys).astype(np.int32)
    fx = xs - x0
    fy = ys - y0
    fx = (fx * fx * (3.0 - 2.0 * fx))[None, :]
    fy = (fy * fy * (3.0 - 2.0 * fy))[:, None]
    x0m, x1m = x0 % cells, (x0 + 1) % cells
    y0m, y1m = y0 % cells, (y0 + 1) % cells
    v00 = g[np.ix_(y0m, x0m)]
    v01 = g[np.ix_(y0m, x1m)]
    v10 = g[np.ix_(y1m, x0m)]
    v11 = g[np.ix_(y1m, x1m)]
    top = v00 * (1.0 - fx) + v01 * fx
    bot = v10 * (1.0 - fx) + v11 * fx
    return top * (1.0 - fy) + bot * fy


def pnoise(w, h, cells, octaves, seed):
    """Periodic fbm: octaves of wrapping value noise, normalised to 0..1."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w), dtype=np.float32)
    amp, total, c = 1.0, 0.0, cells
    for _ in range(octaves):
        out += amp * _value_layer(w, h, max(2, int(c)), rng)
        total += amp
        amp *= 0.5
        c *= 2
    out /= max(total, 1e-6)
    out -= out.min()
    out /= max(out.max() - out.min(), 1e-6)
    return out


def voronoi(w, h, cells, seed):
    """Periodic jittered-grid Voronoi: returns (distance to the nearest seed, cell id).

    The jitter of every seed is taken from the seed's OWN cell, so the cells
    are really jittered and not a grid of straight stripes.
    """
    rng = np.random.default_rng(seed)
    jitter = rng.random((cells, cells, 2)).astype(np.float32)
    xs = (np.arange(w, dtype=np.float32) / float(w)) * cells
    ys = (np.arange(h, dtype=np.float32) / float(h)) * cells
    cx = np.floor(xs).astype(np.int32)
    cy = np.floor(ys).astype(np.int32)
    best = np.full((h, w), 1e9, dtype=np.float32)
    ids = np.zeros((h, w), dtype=np.int32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ni = (cx + dx)[None, :]                  # (1, w)
            nj = (cy + dy)[:, None]                  # (h, 1)
            im, jm = ni % cells, nj % cells
            sx = jitter[jm, im, 0] + ni              # (h, w)
            sy = jitter[jm, im, 1] + nj              # (h, w)
            d = (xs[None, :] - sx) ** 2 + (ys[:, None] - sy) ** 2
            hit = d < best
            best = np.where(hit, d, best)
            ids = np.where(hit, (jm * cells + im).astype(np.int32), ids)
    return np.sqrt(best), ids


def height_to_normal(height, strength=1.0):
    """Sobel a height field into a tangent-space normal map (RGB, blue = up)."""
    if height.ndim == 3:
        height = height[:, :, 0]
    h = np.pad(height, 1, mode="wrap")
    dx = (h[1:-1, 2:] - h[1:-1, :-2]) * strength
    dy = (h[2:, 1:-1] - h[:-2, 1:-1]) * strength
    nx, ny, nz = -dx, -dy, np.ones_like(dx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / ln, ny / ln, nz / ln], axis=-1) * 0.5 + 0.5
    return Image.fromarray((rgb * 255).astype(np.uint8), "RGB")


def to_image(arr):
    """Float array 0..1 -> 8-bit image."""
    if arr.ndim == 2:
        return Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "L")
    return Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGB")


def scratch_layer(w, h, count, seed, length=(0.2, 0.9), width=1, value=0.0):
    """Hairline scratches drawn with wrap-around so the tile stays seamless."""
    rng = np.random.default_rng(seed)
    layer = Image.new("L", (w, h), 128)
    d = ImageDraw.Draw(layer)
    for _ in range(count):
        x = rng.uniform(0, w)
        y = rng.uniform(0, h)
        ang = rng.uniform(0, math.tau)
        ln = rng.uniform(*length) * w
        x2 = x + math.cos(ang) * ln
        y2 = y + math.sin(ang) * ln
        for ox in (-w, 0, w):
            for oy in (-h, 0, h):
                d.line([(x + ox, y + oy), (x2 + ox, y2 + oy)],
                       fill=int(np.clip(128 + value * 127, 0, 255)), width=width)
    return layer


def streak_layer(w, h, count, seed, length=(0.1, 0.7), width=(1, 4)):
    """Vertical rain-streak / drip runs (wrap-around in x)."""
    rng = np.random.default_rng(seed)
    layer = Image.new("L", (w, h), 128)
    d = ImageDraw.Draw(layer)
    for _ in range(count):
        x = rng.uniform(0, w)
        y = rng.uniform(0, h)
        ln = rng.uniform(*length) * h
        wd = int(rng.integers(width[0], width[1] + 1))
        for ox in (-w, 0, w):
            d.line([(x + ox, y), (x + ox + rng.uniform(-2, 2), y + ln)],
                   fill=int(rng.integers(96, 126)), width=wd)
    return layer


def mask_to_array(layer):
    """A PIL L image -> float array 0..1 centred on 0.5."""
    return np.asarray(layer, dtype=np.float32) / 255.0


def blend(base, mask, amount):
    """base +/- amount*mask, mask centred on 0.5."""
    return np.clip(base + (mask - 0.5) * 2.0 * amount, 0.0, 1.0)


def blur(arr, radius):
    """Gaussian blur of a float array."""
    img = to_image(arr).filter(ImageFilter.GaussianBlur(radius))
    return np.asarray(img, dtype=np.float32) / 255.0
