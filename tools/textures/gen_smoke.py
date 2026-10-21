#!/usr/bin/env python3
"""Soft billow smoke / vapour sprite atlas (core-owned) shared by every particle effect.

    python3 tools/textures/gen_smoke.py

Writes game/assets/textures/fx/smoke_billow.png (4 x 4 variants, 2048^2 RGBA: white, alpha =
density), smoke_billow_n.png (OpenGL normal map of the density height field, so scene lights shade
the billows) and the review sheet captures/lead/smoke_atlas.jpg.

Each variant is a domain-warped round mass whose rim breaks up into wisps, filled with cauliflower
billows (turbulence fBm), soft everywhere and exactly zero at the cell border. Particles should use
ONE RANDOM frame each (no flipbook animation: anim_offset random, anim_speed 0), random rotation,
and grow/fade through the particle curves; a few overlapping sprites then read as one volume.
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "assets" / "textures" / "fx"
SHEET = ROOT / "captures" / "lead" / "smoke_atlas.jpg"
SEED = 7
GRID = 4
FRAME = 512
WARP = 0.24            # domain warp amplitude (fraction of the frame half-size)
RIM = (0.18, 0.80)     # radial falloff: full density inside RIM[0], zero beyond RIM[1]
BILLOW_SCALE = 3.0     # cauliflower size: billows per frame
NORMAL_STRENGTH = 3.0
PEAK_ALPHA = 0.90       # even the core lets some light through; overlap builds the volume
SHADE_DARK = 0.45


def value_noise(rng, res, cells):
    """Smooth value noise: a random grid upsampled bicubically to res x res, in [0, 1]."""
    grid = rng.random((cells + 3, cells + 3)).astype(np.float32)
    big = Image.fromarray(grid).resize((res * (cells + 3) // cells,) * 2, Image.BICUBIC)
    return np.clip(np.asarray(big, dtype=np.float32)[:res, :res], 0.0, 1.0)


def fbm(rng, res, base_cells, octaves, turbulence=False):
    total, amp, norm = np.zeros((res, res), np.float32), 1.0, 0.0
    for o in range(octaves):
        n = value_noise(rng, res, base_cells * 2 ** o)
        if turbulence:
            n = np.abs(2.0 * n - 1.0)          # billow: round bumps split by dark creases
        total += amp * n
        norm += amp
        amp *= 0.5
    return total / norm


def sample(field, x, y):
    """Bilinear sample of `field` at float pixel coordinates (clamped)."""
    h, w = field.shape
    x = np.clip(x, 0, w - 1.001)
    y = np.clip(y, 0, h - 1.001)
    x0, y0 = x.astype(np.int32), y.astype(np.int32)
    fx, fy = x - x0, y - y0
    a = field[y0, x0] * (1 - fx) + field[y0, x0 + 1] * fx
    b = field[y0 + 1, x0] * (1 - fx) + field[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def blur(a, passes=3):
    for _ in range(passes):
        a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5.0
    return a


def puff(rng, stretch):
    """(density, height) for one frame; stretch > 1 elongates it horizontally (wisps)."""
    res = FRAME
    yy, xx = np.mgrid[0:res, 0:res].astype(np.float32)
    u = (xx / (res - 1)) * 2.0 - 1.0
    v = (yy / (res - 1)) * 2.0 - 1.0
    wx = fbm(rng, res, 3, 4) - 0.5
    wy = fbm(rng, res, 3, 4) - 0.5
    uw = (u + WARP * wx * 2.0) / stretch
    vw = v + WARP * wy * 2.0
    r = np.sqrt(uw * uw + vw * vw)
    mass = smoothstep(RIM[1], RIM[0], r)
    billow = fbm(rng, res, int(BILLOW_SCALE), 4, turbulence=True)
    bx = (u * 0.5 + 0.5) * (res - 1) + wx * res * 0.15
    by = (v * 0.5 + 0.5) * (res - 1) + wy * res * 0.15
    billow = sample(billow, bx, by)
    wisps = fbm(rng, res, 6, 4)
    # Inside: dense with billow shading; rim: eaten away by the wisp noise so the edge frays.
    density = mass * (0.45 + 0.55 * billow)
    density *= smoothstep(0.15, 0.75, wisps + mass * 0.6)
    border = smoothstep(1.0, 0.86, np.maximum(np.abs(u), np.abs(v)))   # exactly 0 at the cell edge
    density = np.clip(density * border, 0.0, 1.0)
    dome = np.sqrt(np.clip(1.0 - r * r, 0.0, 1.0))
    height = blur(density * 0.6 + dome * 0.4 + billow * 0.25 * mass)
    return density, height


def normal_map(height):
    gy, gx = np.gradient(height)
    nx, ny = -gx * NORMAL_STRENGTH * FRAME / 64.0, gy * NORMAL_STRENGTH * FRAME / 64.0
    nz = np.ones_like(nx)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / length, ny / length, nz / length], -1) * 0.5 + 0.5


def main():
    rng = np.random.default_rng(SEED)
    size = FRAME * GRID
    rgba = np.zeros((size, size, 4), np.float32)
    nrm = np.zeros((size, size, 3), np.float32)
    for i in range(GRID * GRID):
        stretch = 1.5 if i % 5 == 3 else 1.0
        density, height = puff(rng, stretch)
        r0, c0 = (i // GRID) * FRAME, (i % GRID) * FRAME
        alpha = np.clip(density, 0.0, 1.0) * PEAK_ALPHA
        hn = np.clip(height / max(height.max(), 1e-6), 0.0, 1.0)
        shade = SHADE_DARK + (1.0 - SHADE_DARK) * hn       # crevices darker: billows read unlit too
        rgba[r0:r0 + FRAME, c0:c0 + FRAME, 0:3] = shade[..., None]
        rgba[r0:r0 + FRAME, c0:c0 + FRAME, 3] = alpha
        nrm[r0:r0 + FRAME, c0:c0 + FRAME] = normal_map(height)
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8)).save(OUT / "smoke_billow.png", optimize=True)
    Image.fromarray((nrm * 255 + 0.5).astype(np.uint8)).save(OUT / "smoke_billow_n.png", optimize=True)
    preview = Image.new("RGB", (size, size), (16, 24, 40))
    preview.paste(Image.fromarray((rgba * 255).astype(np.uint8)), (0, 0),
                  Image.fromarray((rgba[..., 3] * 255).astype(np.uint8)))
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    preview.resize((1024, 1024), Image.LANCZOS).save(SHEET, quality=88)
    print("smoke atlas ->", OUT / "smoke_billow.png", "| sheet", SHEET)


if __name__ == "__main__":
    main()
