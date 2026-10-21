"""Sheet metal: the 彩钢板 cladding, powder-coated steel and galvanised steel.

Real size: the corrugated sheet tiles every 2.7 m (100 mm ribs, a panel seam every
1.35 m); the steel panels tile every 1.6 m and carry the scratches and zinc spangle
that keep the AC units and the cages from reading as flat coloured boxes.
"""
import numpy as np

from . import library, noise
from .height import mix_rgb, rgb

TILE_M = 2.7
RIB_PITCH = 0.10
STEEL_M = 1.6
SHUTTER_M = 1.2       # 16 slats of 75 mm, so the tile is seamless
SHUTTER_RIB = 0.075


def corrugated(size=(2048, 2048), seed=71, base_hex="#9FC4D6"):
    """Light-blue painted corrugated steel with rust spots and panel seams."""
    w, h = size
    x = np.arange(w, dtype=np.float32)
    phase = (x / float(w) * (TILE_M / RIB_PITCH)) * 2.0 * np.pi
    rib = 0.5 + 0.5 * np.cos(phase)
    rib = rib ** 0.7
    y = np.arange(h, dtype=np.float32)
    seam_v = (y / float(h) * (TILE_M / 1.35))
    seam = np.clip((0.02 - np.abs(seam_v - np.round(seam_v))) * 30.0, 0.0, 1.0)
    grime = noise.fbm(max(w, h), seed, octaves=4, base_freq=10)
    rust = np.clip((noise.fbm(max(w, h), seed + 6, octaves=4, base_freq=16) - 0.66) * 4.0, 0.0, 1.0)
    base = rgb(base_hex, (h, w))
    ribc = (0.86 + 0.28 * rib)[None, :, None]
    albedo = base * ribc * (0.9 + 0.2 * grime[..., None])
    albedo = mix_rgb(albedo, rgb("#7A4A2C", (h, w)), rust * 0.75)
    height = rib[None, :] * 1.0 + grime * 0.06 - seam * 0.5
    rough = np.clip(0.42 + (grime - 0.5) * 0.25 + rust * 0.4 + seam * 0.1, 0.15, 0.95)
    ao = np.clip(0.95 - (1.0 - rib[None, :]) * 0.2 - rust * 0.12, 0.5, 1.0)
    return albedo, height, rough, ao, 0.0


def _scratches(size, seed, count=140):
    """A 0..1 mask of thin scratches, used by both steel finishes."""
    w, h = size
    rng = np.random.default_rng(seed)
    mask = np.zeros((h, w), dtype=np.float32)
    for _ in range(count):
        x0 = rng.uniform(0, w)
        y0 = rng.uniform(0, h)
        ang = rng.uniform(0, np.pi * 2.0)
        length = rng.uniform(w * 0.02, w * 0.25)
        depth = rng.uniform(0.4, 1.0)
        steps = int(length)
        for i in range(steps):
            t = i / max(1, steps - 1)
            x = int(x0 + np.cos(ang) * length * t) % w
            y = int(y0 + np.sin(ang) * length * t) % h
            mask[y, x] = max(mask[y, x], depth)
            if rng.random() < 0.3:
                mask[(y + 1) % h, x] = max(mask[(y + 1) % h, x], depth * 0.6)
    return mask


def steel_powder(size=(2048, 2048), seed=81, base_hex="#3A3C40"):
    """Powder-coated steel: the balcony slabs, the brackets, the poles."""
    w, h = size
    grime = noise.fbm(max(w, h), seed, octaves=4, base_freq=14)
    orange = noise.fbm(max(w, h), seed + 3, octaves=3, base_freq=40)
    scratch = _scratches((w, h), seed + 7)
    base = rgb(base_hex, (h, w))
    albedo = base * (0.88 + 0.24 * grime[..., None])
    albedo = mix_rgb(albedo, rgb("#6A4A32", (h, w)), np.clip((orange - 0.74) * 3.0, 0, 1) * 0.5)
    albedo = albedo * (1.0 - scratch[..., None] * 0.35)
    height = grime * 0.2 + orange * 0.1 - scratch * 0.25
    rough = np.clip(0.55 + (grime - 0.5) * 0.25 + scratch * 0.3, 0.2, 0.95)
    ao = np.clip(0.95 - (1.0 - grime) * 0.1, 0.6, 1.0)
    return albedo, height, rough, ao, 0.0


def steel_galv(size=(2048, 2048), seed=91, base_hex="#B7BDC2"):
    """Galvanised steel: the AC casings, the cages, the water tanks."""
    w, h = size
    grime = noise.fbm(max(w, h), seed, octaves=4, base_freq=12)
    spangle = noise.value_noise(max(w, h), 90, seed + 5)
    scratch = _scratches((w, h), seed + 9, count=90)
    rust = np.clip((noise.fbm(max(w, h), seed + 17, octaves=4, base_freq=20) - 0.72) * 4.0, 0, 1)
    base = rgb(base_hex, (h, w))
    albedo = base * (0.85 + 0.26 * grime[..., None]) * (0.9 + 0.2 * spangle[..., None])
    albedo = mix_rgb(albedo, rgb("#7A4A2C", (h, w)), rust * 0.6)
    albedo = albedo * (1.0 - scratch[..., None] * 0.3)
    height = grime * 0.18 + spangle * 0.08 - scratch * 0.2
    rough = np.clip(0.40 + (grime - 0.5) * 0.3 + rust * 0.4 + scratch * 0.25, 0.15, 0.95)
    ao = np.clip(0.95 - rust * 0.15, 0.55, 1.0)
    return albedo, height, rough, ao, 0.0


def shutter_steel(size=(1024, 1024), seed=101, base_hex="#9A9C98"):
    """A roller shutter (卷帘门): the 75 mm slats, the guide shadow and the grime.

    The shutter is a tiling surface and not an atlas cell: the slats have to run
    over the whole width of a 4 m shopfront.  1024 px over 1.20 m is 853 px/m.
    """
    w, h = size
    v = (np.arange(h, dtype=np.float32) / float(h) * (SHUTTER_M / SHUTTER_RIB))[:, None]
    f = v - np.floor(v)
    # the slat profile: a rounded face and a dark shadow under its lip
    face = np.clip(np.sin(f * np.pi), 0.0, 1.0) ** 0.6
    lip = np.clip((f - 0.72) / 0.28, 0.0, 1.0)
    grime = noise.fit(noise.fbm(max(w, h), seed, octaves=4, base_freq=12), w, h)
    streak = noise.fit(noise.ridged(max(w, h), seed + 4, octaves=3, base_freq=8), w, h)
    base = rgb(base_hex, (h, w))
    albedo = base * (0.80 + 0.34 * face) * (0.92 + 0.16 * grime[..., None])
    albedo *= (1.0 - (streak * 0.22)[..., None])
    height = face * 0.85 - lip * 0.55 + grime * 0.06
    rough = np.clip(0.46 + (grime - 0.5) * 0.22 + lip * 0.18, 0.2, 0.9)
    ao = np.clip(0.92 - lip * 0.45 - (1.0 - face) * 0.12, 0.4, 1.0)
    return albedo, height, rough, ao, 0.85
