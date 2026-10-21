"""Midrise facade textures: white/beige glazed tile and grey render with rain grime.

Tile sheet: 2.0 m tile -> 100 mm square tiles with 6 mm grout, the 1990s Shanghai
midrise look.  Render: 4.0 m tile of stucco with patchy repainting and the leaking
streaks of the shared library scan under the sills.
"""
import numpy as np

from . import library, noise
from .height import mix_rgb, rgb

TILE_M = 2.0
TILE_PITCH = 0.10
GROUT = 0.006
RENDER_M = 2.0


def glazed_tile(size=(2048, 2048), seed=51, base_hex="#C4C1B8"):
    """Glazed square tile cladding with grout lines and per-tile tone variation."""
    w, h = size
    n = TILE_M / TILE_PITCH
    u = (np.arange(w, dtype=np.float32) / float(w) * n)[None, :]
    v = (np.arange(h, dtype=np.float32) / float(h) * n)[:, None]
    col = np.floor(u)
    row = np.floor(v)
    fu = u - col
    fv = v - row
    j = (GROUT / TILE_PITCH) * 0.5
    edge_u = np.minimum(fu, 1.0 - fu)
    edge_v = np.minimum(fv, 1.0 - fv)
    in_tile = (edge_u > j) & (edge_v > j)
    rng = np.random.default_rng(seed)
    tones = rng.random(256).astype(np.float32)
    key = (col.astype(np.int64) * 7 + row.astype(np.int64) * 13) % 256
    tv = (tones[key] - 0.5) * 0.08
    grime = noise.fbm(max(w, h), seed + 7, octaves=4, base_freq=8)
    base = rgb(base_hex, (h, w))
    albedo = base * (1.0 + tv[..., None] + (grime - 0.5)[..., None] * 0.14)
    grout = rgb("#6E6B62", (h, w))
    mu = np.clip((j * 1.02 - edge_u) * 40.0 + 0.5, 0.0, 1.0)
    mv = np.clip((j * 1.02 - edge_v) * 40.0 + 0.5, 0.0, 1.0)
    m = np.maximum(mu, mv)
    albedo = mix_rgb(albedo, grout, m)
    # the rain streaks of the library scan run down from every joint
    streak = library.streaks("Leaking016A", 512)
    if streak is not None:
        st = np.asarray(noise.fit(streak, w, h), dtype=np.float32)
        albedo *= (1.0 - st[..., None] * 0.22)
    else:
        st = np.zeros((h, w), dtype=np.float32)
    height = np.where(in_tile, 1.0, 0.0) - m * 0.7 + (grime - 0.5) * 0.05
    # the glaze is 0.15-0.35 rough, the grout is duller
    rough = np.clip(0.25 + (grime - 0.5) * 0.18 + m * 0.5 - st * 0.10, 0.15, 0.9)
    ao = np.clip(1.0 - m * 0.35 - st * 0.14, 0.5, 1.0)
    return albedo, height, rough, ao, 0.0


def render(size=(1024, 1024), seed=61, base_hex="#9E9B92"):
    """Grey/beige stucco render: trowel marks, hairline cracks and rain staining.

    The tile is 2.00 m, so 1024 px are 512 px/m: the trowel arcs and the hairline
    cracks are readable at 5 m, which the 4 m tile was not.
    """
    w, h = size
    coarse = noise.fit(noise.fbm(max(w, h), seed, octaves=4, base_freq=4), w, h)
    fine = noise.fit(noise.fbm(max(w, h), seed + 2, octaves=4, base_freq=48), w, h)
    patch = noise.fit(noise.fbm(max(w, h), seed + 4, octaves=2, base_freq=2), w, h)
    base = rgb(base_hex, (h, w))
    lighter = rgb("#C2BEB2", (h, w))
    darker = rgb("#6E6C66", (h, w))
    m1 = np.clip((patch - 0.55) * 2.2, 0.0, 1.0)
    albedo = mix_rgb(base, lighter, m1 * 0.5)
    m2 = np.clip((coarse - 0.55) * 2.0, 0.0, 1.0)
    albedo = mix_rgb(albedo, darker, m2 * 0.45)
    albedo *= (0.9 + 0.2 * fine[..., None])
    # the trowel marks: broad arcs of the float, a few millimetres deep
    arcs = noise.fit(noise.ridged(max(w, h), seed + 8, octaves=3, base_freq=14), w, h)
    trowel = np.clip((arcs - 0.62) * 3.2, 0.0, 1.0)
    albedo *= (1.0 - trowel[..., None] * 0.24)
    # the hairline cracks: thin dark lines through the render
    crack = np.clip((noise.fit(noise.ridged(max(w, h), seed + 12, octaves=4, base_freq=9),
                               w, h) - 0.80) * 8.0, 0.0, 1.0)
    crack *= np.clip((fine - 0.45) * 3.0, 0.0, 1.0)
    albedo = mix_rgb(albedo, darker, crack * 0.85)
    # the rain streaks of the library scan run down the wall
    streak = library.streaks("Leaking004", 512)
    st = np.zeros((h, w), dtype=np.float32) if streak is None else noise.fit(streak, w, h)
    albedo *= (1.0 - st[..., None] * 0.30)
    # the surface imperfections break the roughness up
    imp = library.load_gray("SurfaceImperfections001", "diff", 512)
    im = np.zeros((h, w), dtype=np.float32) if imp is None else noise.fit(imp, w, h)
    height = fine * 0.5 + coarse * 0.2 + im * 0.15 - crack * 0.55 - trowel * 0.12
    rough = np.clip(0.82 + (fine - 0.5) * 0.16 + (im - 0.5) * 0.2 - st * 0.1, 0.5, 0.99)
    ao = np.clip(0.96 - m1 * 0.12 - m2 * 0.1 - st * 0.16 - crack * 0.35, 0.4, 1.0)
    return albedo, height, rough, ao, 0.0
