#!/usr/bin/env python3
"""Generate the thruster plumes' own textures.

    python3 game/fx/thrusters/textures/gen_textures.py

Writes:
  ring_decal.png     the faint ground ring under a landing
  vapour_noise.png   the seamless fbm the vapour column scrolls (review MUST-FIX 3)

The vapour sprites are the lead's shared smoke atlas (res://assets/textures/fx/smoke_billow.png,
tools/textures/gen_smoke.py), so this unit owns the ground ring and the column's noise.
"""
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent
SEED = 20261020
RING = 256
NOISE = 256


def _grid(rng, h, w, fy, fx):
    """Smoothly interpolated random lattice -> one octave of value noise."""
    g = rng.random((fy + 1, fx + 1))
    ys = np.linspace(0.0, fy, h, endpoint=False)
    xs = np.linspace(0.0, fx, w, endpoint=False)
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    ty = (ys - y0)[:, None]
    tx = (xs - x0)[None, :]
    ty = ty * ty * (3.0 - 2.0 * ty)
    tx = tx * tx * (3.0 - 2.0 * tx)
    a = g[np.ix_(y0, x0)]
    b = g[np.ix_(y0, x0 + 1)]
    c = g[np.ix_(y0 + 1, x0)]
    d = g[np.ix_(y0 + 1, x0 + 1)]
    return (a * (1 - tx) * (1 - ty) + b * tx * (1 - ty)
            + c * (1 - tx) * ty + d * tx * ty)


def fbm(rng, h, w, base=4, octaves=4):
    """Fractal value noise, normalised to 0..1."""
    out = np.zeros((h, w))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        f = base * (2 ** o)
        out += amp * _grid(rng, h, w, f, f)
        total += amp
        amp *= 0.55
    return out / total


def _smoothstep(lo, hi, x):
    t = np.clip((x - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def make_ring(rng):
    """Faint annulus for the landing ground decal, with a zero border."""
    n = RING
    c = (np.arange(n) + 0.5) / n * 2.0 - 1.0
    rx, ry = np.meshgrid(c, c)
    r = np.sqrt(rx * rx + ry * ry)
    noise = fbm(rng, 64, 64)
    noise = np.asarray(
        Image.fromarray((noise * 255.0).astype(np.uint8)).resize((n, n), Image.BILINEAR),
        dtype=np.float32) / 255.0
    band = np.exp(-((r - 0.78) / 0.13) ** 2)
    edge = _smoothstep(1.0, 0.88, r)
    return np.clip(band * (0.6 + 0.55 * noise), 0.0, 1.0) * edge


def _seamless_grid(rng, h, w, fy, fx):
    """One octave of value noise that tiles: the lattice wraps in both axes."""
    g = rng.random((fy, fx))
    ys = np.linspace(0.0, fy, h, endpoint=False)
    xs = np.linspace(0.0, fx, w, endpoint=False)
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    ty = (ys - y0)[:, None]
    tx = (xs - x0)[None, :]
    ty = ty * ty * (3.0 - 2.0 * ty)
    tx = tx * tx * (3.0 - 2.0 * tx)
    a = g[np.ix_(y0 % fy, x0 % fx)]
    b = g[np.ix_(y0 % fy, (x0 + 1) % fx)]
    c = g[np.ix_((y0 + 1) % fy, x0 % fx)]
    d = g[np.ix_((y0 + 1) % fy, (x0 + 1) % fx)]
    return (a * (1 - tx) * (1 - ty) + b * tx * (1 - ty)
            + c * (1 - tx) * ty + d * tx * ty)


def seamless_fbm(rng, h, w, base=2, octaves=5):
    """Fractal value noise that tiles, normalised to 0..1."""
    out = np.zeros((h, w))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        f = base * (2 ** o)
        out += amp * _seamless_grid(rng, h, w, f, f)
        total += amp
        amp *= 0.55
    return out / total


def make_vapour_noise(rng):
    """The scrolling noise of the vapour column: seamless fbm, full contrast.

    Two octaves on purpose: the fine octaves of a five octave fbm are 4 cm across, and they
    bead the column (the review asks for no luminance swing with a period under 60 px)."""
    n = seamless_fbm(rng, NOISE, NOISE, base=2, octaves=2)
    lo, hi = float(n.min()), float(n.max())
    return np.clip((n - lo) / max(hi - lo, 1e-6), 0.0, 1.0)


def main():
    rng = np.random.default_rng(SEED)
    ring = make_ring(rng)
    ring_rgba = np.dstack([np.ones_like(ring)[..., None], ring])
    Image.fromarray((ring_rgba * 255.0).astype(np.uint8)).save(
        OUT / "ring_decal.png", optimize=True)
    print("ring_decal.png border alpha = %.3f" % float(ring[[0, -1], :].max()))
    noise = make_vapour_noise(rng)
    Image.fromarray((noise * 255.0).astype(np.uint8)).save(
        OUT / "vapour_noise.png", optimize=True)
    # The seam check: wrapping column 0 after the last column must be as smooth as any
    # other neighbour step, otherwise the scrolling column shows a hard vertical line.
    seam_x = float(np.abs(noise[:, 0] - noise[:, -1]).mean())
    step_x = float(np.abs(np.diff(noise, axis=1)).mean())
    seam_y = float(np.abs(noise[0, :] - noise[-1, :]).mean())
    step_y = float(np.abs(np.diff(noise, axis=0)).mean())
    print("vapour_noise.png %dx%d seam_x=%.4f (step %.4f) seam_y=%.4f (step %.4f)"
          % (NOISE, NOISE, seam_x, step_x, seam_y, step_y))


if __name__ == "__main__":
    main()
