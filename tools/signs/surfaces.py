"""Procedural PBR surface generator for SKYRUSH props (unit: props).

Builds tileable albedo / normal / roughness sets from value noise, so no prop
surface is ever a flat untextured colour (ART.md §5). Everything is deterministic
(seeded).  The generated boards go to a scratch folder: only the four boards the
city's lookdev uses as light-box art are copied into the game folder, so Godot
imports a handful of images instead of a hundred (lead note: IMPORT-CHURN).

    from surfaces import Surface
    s = Surface("galvanised", size=512, seed=7)
    s.paint_metal((0.56, 0.58, 0.60))
    s.save()
"""
import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.expanduser("~/m/skyrush")
# PROP_TEX_DIR lets the atlas builder render the boards into a scratch folder.
TEX_DIR = os.environ.get("PROP_TEX_DIR",
                         os.path.join(ROOT, "tmp", "props", "tex", "boards"))
# The boards the city's lookdev uses as light-box art (game/world/env/lookdev_city.gd).
LOOKDEV_BOARDS = ("billboard_ad", "bus_ad", "neon_blade", "roadname_nanjing")


def _grid(w, h, cells, rng):
    """Random lattice of `cells` x `cells` values, tileable."""
    g = rng.random((cells, cells)).astype(np.float32)
    return np.array(Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC),
                    dtype=np.float32) / 255.0


def fbm(w, h, cells, octaves, seed, gain=0.5):
    """Fractional Brownian motion: `octaves` noise layers, tileable in both axes."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w), dtype=np.float32)
    amp, total, c = 1.0, 0.0, cells
    for _ in range(octaves):
        out += amp * _grid(w, h, max(2, int(c)), rng)
        total += amp
        amp *= gain
        c *= 2
    return out / max(total, 1e-6)


def height_to_normal(height, strength=1.0):
    """Sobel a height field into a tangent-space normal map (RGB, blue = up)."""
    h = np.pad(height, 1, mode="wrap")
    dx = (h[1:-1, 2:] - h[1:-1, :-2]) * strength
    dy = (h[2:, 1:-1] - h[:-2, 1:-1]) * strength
    nx, ny, nz = -dx, -dy, np.ones_like(dx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / ln, ny / ln, nz / ln], axis=-1) * 0.5 + 0.5
    return Image.fromarray((rgb * 255).astype(np.uint8), "RGB")


def to_image(arr):
    """Float array 0..1 -> 8-bit L image."""
    return Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "L")


class Surface:
    """One tileable material set: <name>_diff.jpg / _nor_gl.jpg / _rough.jpg."""

    def __init__(self, name, size=512, seed=1):
        self.name = name
        self.size = size
        self.seed = seed
        self.albedo = None
        self.rough = None
        self.height = None

    # -- painters -------------------------------------------------------
    def paint_metal(self, base, sheen=0.10, grime=0.22, streaks=0.0):
        """Painted / galvanised metal: mottled value, vertical grime, hairline scratches."""
        w = h = self.size
        n = fbm(w, h, 6, 4, self.seed)
        fine = fbm(w, h, 48, 2, self.seed + 1)
        grain = fbm(w, h, 200, 1, self.seed + 9)
        dirt = fbm(w, h, 3, 3, self.seed + 2)
        col = np.zeros((h, w, 3), dtype=np.float32)
        for i in range(3):
            c = base[i] * (1.0 - sheen + sheen * n) * (1.0 - grime * 0.5 * dirt)
            col[:, :, i] = c * (0.93 + 0.14 * grain)
        if streaks > 0.0:
            st = fbm(w, h, 2, 3, self.seed + 3)
            streak = np.clip((st - 0.55) * 3.0, 0, 1) * streaks
            col *= (1.0 - streak[:, :, None] * 0.55)
        self.albedo = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
        self.rough = np.clip(0.30 + 0.35 * dirt + 0.20 * fine + 0.25 * n, 0.05, 0.95)
        self.height = fine * 0.30 + grain * 0.25 + n * 0.45
        return self

    def paint_concrete(self, base, grime=0.30, pits=0.5):
        """Cast concrete: broad blotches, aggregate pits, dirt gradient."""
        w = h = self.size
        blot = fbm(w, h, 4, 4, self.seed)
        fine = fbm(w, h, 40, 2, self.seed + 1)
        spec = fbm(w, h, 120, 1, self.seed + 2)
        dirt = fbm(w, h, 3, 3, self.seed + 3)
        col = np.zeros((h, w, 3), dtype=np.float32)
        for i in range(3):
            col[:, :, i] = base[i] * (0.78 + 0.34 * blot) * (1.0 - grime * dirt)
        self.albedo = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
        self.rough = np.clip(0.72 + 0.20 * dirt - 0.10 * blot, 0.35, 0.98)
        self.height = fine * 0.25 + spec * pits * 0.5 + blot * 0.25
        return self

    def paint_bark(self, cream, olive, grey):
        """London-plane mottled bark: cream / olive / grey patches, vertical fissures."""
        w = h = self.size
        patch = fbm(w, h, 5, 4, self.seed)
        patch2 = fbm(w, h, 11, 3, self.seed + 1)
        fis = fbm(w, h, 3, 4, self.seed + 2)
        mix = np.clip(patch * 1.4 - 0.15, 0, 1)
        col = np.zeros((h, w, 3), dtype=np.float32)
        for i in range(3):
            c = cream[i] * (1 - mix) + olive[i] * mix
            c = c * (1 - patch2) + grey[i] * patch2
            col[:, :, i] = c * (0.80 + 0.30 * np.clip((fis - 0.45) * 3, 0, 1))
        self.albedo = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
        self.rough = np.clip(0.80 + 0.15 * patch2, 0.5, 0.99)
        self.height = np.clip((fis - 0.42) * 2.4, 0, 1) * 0.8 + patch2 * 0.2
        return self

    def paint_asphalt(self, base, grime=0.24, wet=0.35):
        """Road asphalt: fine aggregate, no large-scale pattern (so it never tiles)."""
        w = h = self.size
        grain = fbm(w, h, 220, 1, self.seed)
        fine = fbm(w, h, 60, 2, self.seed + 1)
        dirt = fbm(w, h, 3, 3, self.seed + 2)
        col = np.zeros((h, w, 3), dtype=np.float32)
        for i in range(3):
            col[:, :, i] = base[i] * (0.86 + 0.28 * grain) * (1.0 - grime * dirt)
        self.albedo = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
        self.rough = np.clip(0.70 + 0.22 * dirt - wet * 0.35 * fine, 0.18, 0.95)
        self.height = grain * 0.75 + fine * 0.25
        return self

    def save(self):
        """Write the three maps into the props texture folder."""
        os.makedirs(TEX_DIR, exist_ok=True)
        self.albedo.save(os.path.join(TEX_DIR, "%s_diff.jpg" % self.name), quality=92)
        height_to_normal(self.height, 2.4).save(
            os.path.join(TEX_DIR, "%s_nor_gl.jpg" % self.name), quality=92)
        to_image(self.rough).save(os.path.join(TEX_DIR, "%s_rough.jpg" % self.name), quality=92)
        return os.path.join(TEX_DIR, "%s_diff.jpg" % self.name)


def srgb(hexstr):
    """'#RRGGBB' -> linear-ish 0..1 triple (kept in sRGB space, matches Blender base colour)."""
    h = hexstr.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


def hsv_shift(rgb, dh=0.0, ds=0.0, dv=0.0):
    """Shift an RGB triple in HSV space (hue in turns)."""
    import colorsys
    r, g, b = rgb
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    h = (h + dh) % 1.0
    s = max(0.0, min(1.0, s + ds))
    v = max(0.0, min(1.0, v + dv))
    return colorsys.hsv_to_rgb(h, s, v)


def kelvin_rgb(k):
    """Approximate blackbody colour for a colour temperature in kelvin (0..1 RGB)."""
    t = k / 100.0
    if t <= 66:
        r = 1.0
        g = min(1.0, max(0.0, 0.3900816 * math.log(t) - 0.6318414))
    else:
        r = min(1.0, max(0.0, 1.2929362 * ((t - 60) ** -0.1332047)))
        g = min(1.0, max(0.0, 1.1298909 * ((t - 60) ** -0.0755148)))
    b = 1.0 if t >= 66 else min(1.0, max(0.0, 0.5432068 * math.log(t - 10) - 1.1962541))
    return (r, g, b)
