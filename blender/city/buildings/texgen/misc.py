"""Roof tiles, lacquered wood, brass, dirty glass, awning canvas, foliage and paving.

The roof is the 小青瓦 (small grey clay tile) of the shikumen and the old warehouses:
overlapping pan tiles running down the slope with a cover tile over every course.
"""
import numpy as np

from . import library, noise
from .height import mix_rgb, rgb

ROOF_M = 1.44
PAN_PITCH = 0.18
COVER_PITCH = 0.36
WOOD_M = 1.2
BRASS_M = 0.5
GLASS_M = 2.0
AWNING_M = 2.0
LEAF_M = 2.0
LAWN_M = 3.0
PAVING_M = 3.0


def roof_tile(size=(1024, 1024), seed=121, base_hex="#6B7074"):
    """小青瓦: grey clay pan tiles with a cover course, soot and moss.

    The cover course is a visible band in the albedo, not only in the normal map:
    a roof whose courses can only be seen in the bump is a flat grey plane from the
    air.  The pitch is 180 mm for the pan tiles and 360 mm for the cover course.
    """
    w, h = size
    u = (np.arange(w, dtype=np.float32) / float(w) * (ROOF_M / PAN_PITCH))[None, :]
    v = (np.arange(h, dtype=np.float32) / float(h) * (ROOF_M / COVER_PITCH))[:, None]
    pan_col = np.floor(u)
    pan_f = u - pan_col
    cover_row = np.floor(v)
    cover_f = v - cover_row
    # the pan tile is a shallow concave channel
    pan = np.clip(np.sin(pan_f * np.pi), 0.0, 1.0)[0] ** 0.7
    # the cover tile is a rounded ridge over the course
    cover = np.clip((cover_f - 0.04) / 0.34, 0.0, 1.0)
    cover = np.clip(np.sin(cover * np.pi), 0.0, 1.0) ** 0.5
    rng = np.random.default_rng(seed)
    tones = rng.random(256).astype(np.float32)
    key = (pan_col.astype(np.int64) * 13 + cover_row.astype(np.int64) * 31) % 256
    bvar = (tones[key] - 0.5) * 2.0 * 0.18
    grain = noise.fit(noise.fbm(max(w, h), seed + 3, octaves=4, base_freq=64), w, h)
    soot = noise.fit(noise.fbm(max(w, h), seed + 9, octaves=4, base_freq=6), w, h)
    moss = np.clip((noise.fit(noise.fbm(max(w, h), seed + 17, octaves=3, base_freq=10),
                              w, h) - 0.66) * 3.0, 0, 1)
    base = rgb(base_hex, (h, w))
    albedo = base * (1.0 + bvar[..., None] * 1.15 + grain[..., None] * 0.22)
    # the pan channel sits in its own shadow, the cover ridge catches the sky
    albedo *= (0.46 + 0.56 * pan[None, :, None])
    albedo *= (0.70 + 0.62 * cover[..., None])
    albedo *= (1.0 - (soot * 0.30)[..., None])
    albedo = mix_rgb(albedo, rgb("#4A5A38", (h, w)), moss * 0.45)
    height = pan[None, :] * 0.55 + cover * 0.65 + grain * 0.08
    rough = np.clip(0.88 - bvar * 0.3 + moss * 0.06, 0.55, 0.99)
    ao = np.clip(0.66 + 0.34 * pan[None, :] * (0.5 + 0.5 * cover), 0.35, 1.0)
    return albedo, height, rough, ao, 0.0


def wood_lacquer(size=(1024, 1024), seed=131, base_hex="#1E1A17"):
    """Black lacquered wood: the shikumen doors, the window casements, the signs."""
    w, h = size
    grain = noise.fbm(max(w, h), seed, octaves=5, base_freq=6)
    fine = noise.fbm(max(w, h), seed + 4, octaves=3, base_freq=90)
    wear = np.clip((noise.fbm(max(w, h), seed + 8, octaves=3, base_freq=14) - 0.58) * 2.4, 0, 1)
    base = rgb(base_hex, (h, w))
    albedo = base * (0.82 + 0.36 * grain[..., None])
    albedo = mix_rgb(albedo, rgb("#4A4038", (h, w)), wear * 0.35)
    height = grain * 0.4 + fine * 0.1
    rough = np.clip(0.30 + (grain - 0.5) * 0.18 + wear * 0.25, 0.12, 0.8)
    ao = np.clip(0.96 - wear * 0.12, 0.6, 1.0)
    return albedo, height, rough, ao, 0.0


def brass(size=(512, 512), seed=141, base_hex="#B08D57"):
    """Brass: the door knockers, the signage studs."""
    w, h = size
    grain = noise.fbm(max(w, h), seed, octaves=4, base_freq=40)
    patina = np.clip((noise.fbm(max(w, h), seed + 5, octaves=3, base_freq=8) - 0.62) * 3.0, 0, 1)
    base = rgb(base_hex, (h, w))
    albedo = base * (0.88 + 0.24 * grain[..., None])
    albedo = mix_rgb(albedo, rgb("#5E6B4C", (h, w)), patina * 0.35)
    height = grain * 0.3
    rough = np.clip(0.35 + (grain - 0.5) * 0.16 + patina * 0.3, 0.15, 0.8)
    ao = np.clip(0.97 - patina * 0.1, 0.6, 1.0)
    return albedo, height, rough, ao, 1.0


def glass_dirty(size=(1024, 1024), seed=151):
    """Unlit glass: dust and rain streaks over #0B0E13, never pure black."""
    w, h = size
    dust = noise.fbm(max(w, h), seed, octaves=4, base_freq=10)
    streak = library.streaks("Leaking016A", 512)
    st = np.zeros((h, w), dtype=np.float32) if streak is None else noise.fit(streak, w, h)
    base = rgb("#0B0E13", (h, w))
    albedo = base * (0.85 + 0.5 * dust[..., None])
    albedo += (st[..., None] * np.array([0.035, 0.040, 0.048], dtype=np.float32))
    height = dust * 0.2 + st * 0.2
    rough = np.clip(0.05 + dust * 0.16 + st * 0.06, 0.05, 0.25)
    ao = np.clip(1.0 - st * 0.1, 0.7, 1.0)
    return albedo, height, rough, ao, 0.0


def awning_canvas(size=(1024, 1024), seed=161):
    """Striped awning canvas with a sag stain and a frayed edge."""
    w, h = size
    u = (np.arange(w, dtype=np.float32) / float(w) * 8.0)[None, :]
    stripe = (np.floor(u) % 2.0) < 1.0
    base = rgb("#D8D2C4", (h, w))
    red = rgb("#A8323A", (h, w))
    albedo = np.where(stripe[..., None], base, red)
    weave = noise.fbm(max(w, h), seed, octaves=3, base_freq=120)
    stain = noise.fbm(max(w, h), seed + 5, octaves=3, base_freq=5)
    albedo *= (0.9 + 0.2 * weave[..., None])
    albedo *= (1.0 - (np.clip((stain - 0.55) * 2.0, 0, 1) * 0.22)[..., None])
    height = weave * 0.5
    rough = np.clip(0.86 + (weave - 0.5) * 0.1, 0.6, 0.99)
    ao = np.clip(0.96 - np.clip((stain - 0.55) * 2.0, 0, 1) * 0.12, 0.6, 1.0)
    return albedo, height, rough, ao, 0.0


def leaf_card(size=(1024, 1024), seed=171):
    """A dense cluster of dark green leaves for the plane-tree canopies."""
    w, h = size
    cells = noise.value_noise(max(w, h), 46, seed)
    leaf = np.clip((cells - 0.35) * 2.6, 0.0, 1.0)
    fine = noise.fbm(max(w, h), seed + 3, octaves=4, base_freq=40)
    base = rgb("#2E4A22", (h, w))
    light = rgb("#5A7A38", (h, w))
    albedo = mix_rgb(base, light, leaf * 0.7 * (0.6 + 0.6 * fine))
    height = leaf * 0.6 + fine * 0.2
    rough = np.clip(0.80 + (fine - 0.5) * 0.15, 0.55, 0.99)
    ao = np.clip(0.55 + 0.45 * leaf, 0.4, 1.0)
    return albedo, height, rough, ao, 0.0


def lawn(size=(1024, 1024), seed=181):
    """Grass: the park and plaza ground cover."""
    w, h = size
    blades = noise.fbm(max(w, h), seed, octaves=4, base_freq=90)
    patch = noise.fbm(max(w, h), seed + 3, octaves=3, base_freq=6)
    base = rgb("#3E6B2E", (h, w))
    dry = rgb("#7A7A3C", (h, w))
    albedo = mix_rgb(base, dry, np.clip((patch - 0.6) * 2.0, 0, 1) * 0.4)
    albedo *= (0.8 + 0.4 * blades[..., None])
    height = blades * 0.6
    rough = np.clip(0.9 - blades * 0.08, 0.6, 0.99)
    ao = np.clip(0.75 + 0.25 * blades, 0.5, 1.0)
    return albedo, height, rough, ao, 0.0


def paving_stone(size=(2048, 2048), seed=191):
    """Lane paving: the shared PavingStones144 scan, conditioned and jointed."""
    w, h = size
    albedo, height, rough, ao, metal = _library_paving(w, h)
    return albedo, height, rough, ao, metal


def _library_paving(w, h):
    """The library paving scan as a tileable surface, or a plain concrete fallback."""
    lib = library.load("PavingStones144", "diff", 1024)
    if lib is None:
        return (rgb("#8C8C86", (h, w)), np.zeros((h, w), dtype=np.float32),
                np.full((h, w), 0.85, dtype=np.float32), np.ones((h, w), dtype=np.float32), 0.0)
    lib = np.asarray(lib, dtype=np.float32)
    lib = noise.fit(lib.mean(axis=2), w, h)
    base = rgb("#8C8C86", (h, w))
    albedo = base * (0.55 + 0.9 * lib[..., None])
    grain = noise.fbm(max(w, h), 193, octaves=4, base_freq=30)
    albedo *= (0.88 + 0.24 * grain[..., None])
    height = grain * 0.5 + lib * 0.2
    rough = np.clip(0.88 - lib * 0.2, 0.5, 0.99)
    ao = np.clip(0.85 + 0.15 * lib, 0.5, 1.0)
    return albedo, height, rough, ao, 0.0
