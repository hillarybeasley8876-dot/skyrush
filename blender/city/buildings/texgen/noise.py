"""Tileable procedural noise helpers (numpy only) for the building texture set."""
import numpy as np


def _upscale(grid, size):
    """Bilinear, wrap-around upscale of a (f, f) grid to (size, size) - keeps it tileable."""
    f = grid.shape[0]
    t = np.arange(size, dtype=np.float32) / float(size) * f
    i0 = np.floor(t).astype(np.int32) % f
    i1 = (i0 + 1) % f
    fr = t - np.floor(t)
    fr = fr * fr * (3.0 - 2.0 * fr)
    rows = grid[:, i0] * (1.0 - fr)[None, :] + grid[:, i1] * fr[None, :]
    j0 = np.floor(t).astype(np.int32) % f
    j1 = (j0 + 1) % f
    fu = t - np.floor(t)
    fu = fu * fu * (3.0 - 2.0 * fu)
    return rows[j0] * (1.0 - fu)[:, None] + rows[j1] * fu[:, None]


def value_noise(size, freq, seed):
    """Tileable value noise in [0, 1] with `freq` cells across the image."""
    rng = np.random.default_rng(seed)
    grid = rng.random((max(2, int(freq)), max(2, int(freq)))).astype(np.float32)
    return _upscale(grid, size)


def fbm(size, seed, octaves=5, base_freq=4, gain=0.5, lacunarity=2.0):
    """Fractal sum of tileable value noise, normalised to [0, 1]."""
    total = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    freq = float(base_freq)
    norm = 0.0
    for o in range(octaves):
        total += amp * value_noise(size, freq, seed + o * 977)
        norm += amp
        amp *= gain
        freq *= lacunarity
    return total / max(norm, 1e-6)


def ridged(size, seed, octaves=4, base_freq=6):
    """Ridged noise (sharp creases) in [0, 1]."""
    n = fbm(size, seed, octaves=octaves, base_freq=base_freq)
    return 1.0 - np.abs(n * 2.0 - 1.0)


def normalize(a, lo=0.0, hi=1.0):
    a = a.astype(np.float32)
    mn = float(a.min())
    mx = float(a.max())
    if mx - mn < 1e-6:
        return np.full_like(a, (lo + hi) * 0.5)
    return lo + (hi - lo) * (a - mn) / (mx - mn)


def fit(arr, w, h):
    """Resample a float array to (h, w) with a smooth filter."""
    from PIL import Image
    img = Image.fromarray((np.clip(arr, 0.0, 1.0) * 255).astype(np.uint8)).resize(
        (w, h), Image.LANCZOS)
    return np.asarray(img).astype(np.float32) / 255.0



_SRGB_LUT = None


def _srgb_lut(n=4096):
    """sRGB encode lookup table (linear 0..1 -> sRGB 0..1), built once."""
    global _SRGB_LUT
    if _SRGB_LUT is None:
        x = np.linspace(0.0, 1.0, n, dtype=np.float32)
        _SRGB_LUT = np.where(x <= 0.0031308, x * 12.92,
                             1.055 * np.power(x, 1.0 / 2.4) - 0.055).astype(np.float32)
    return _SRGB_LUT


def to_srgb(linear):
    """Approximate sRGB encode of a linear 0..1 array (table lookup, no per-element pow)."""
    a = np.clip(linear, 0.0, 1.0).astype(np.float32, copy=False)
    lut = _srgb_lut()
    n = lut.size - 1
    pos = a * n
    i = pos.astype(np.int32)
    i = np.clip(i, 0, n - 1)
    frac = (pos - i).astype(np.float32)
    return lut[i] * (1.0 - frac) + lut[i + 1] * frac


def hex_to_srgb(hexstr):
    """'#RRGGBB' -> linear float array (3,) for mixing in linear space."""
    h = hexstr.lstrip("#")
    c = np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)
    return np.where(c <= 0.04045, c / 12.92, np.power((c + 0.055) / 1.055, 2.4)).astype(np.float32)


def to_srgb_bytes(rgb):
    """(h, w, 3) linear float -> (h, w, 3) uint8 sRGB."""
    s = to_srgb(rgb)
    return np.clip(s * 255.0 + 0.5, 0, 255).astype(np.uint8)
