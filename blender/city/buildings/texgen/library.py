"""Access to the shared CC0 texture library (game/assets/textures).

The building texture set reuses the library scans the brief names: the granite
(`granite_tile_03`, conditioned to #ABAAA3), the leaking grime (`Leaking004`,
`Leaking016A`), the surface imperfections (`SurfaceImperfections001`) and the lane
paving (`PavingStones144`).  Everything is read as numpy so the generators can
resample, tint and re-tile it.
"""
import os

import numpy as np
from PIL import Image

LIB_DIR = os.path.expanduser("~/m/skyrush/game/assets/textures")
_CACHE = {}


def lib_path(tid, kind):
    """Path of a library map, or None."""
    for ext in ("jpg", "png"):
        p = os.path.join(LIB_DIR, tid, "%s_%s.%s" % (tid, kind, ext))
        if os.path.exists(p):
            return p
    return None


def load(tid, kind="diff", size=None):
    """A library map as a float array in [0, 1] (sRGB encoded values, not linear)."""
    key = (tid, kind, size)
    if key in _CACHE:
        return _CACHE[key]
    path = lib_path(tid, kind)
    if path is None:
        return None
    img = Image.open(path).convert("RGB")
    if size is not None and img.size != (size, size):
        img = img.resize((size, size), Image.LANCZOS)
    arr = np.asarray(img).astype(np.float32) / 255.0
    _CACHE[key] = arr
    return arr


def load_gray(tid, kind="diff", size=None):
    """A library map as a float array in [0, 1] (one channel)."""
    key = (tid, kind, size, "gray")
    if key in _CACHE:
        return _CACHE[key]
    arr = load(tid, kind, size)
    if arr is None:
        return None
    out = arr.mean(axis=2)
    _CACHE[key] = out
    return out


def to_linear(arr):
    """sRGB values (0..1) -> linear (0..1)."""
    a = np.clip(arr, 0.0, 1.0)
    return np.where(a <= 0.04045, a / 12.92, np.power((a + 0.055) / 1.055, 2.4))


def condition(arr, mean_hex):
    """Scale a colour map so its mean is `mean_hex` (the dossier's granite tone)."""
    h = mean_hex.lstrip("#")
    target = np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)
    mean = arr.reshape(-1, 3).mean(axis=0)
    scale = np.where(mean > 1e-4, target / np.maximum(mean, 1e-4), 1.0)
    return np.clip(arr * scale[None, None, :], 0.0, 1.0)


def streaks(tid="Leaking004", size=512, columns=48):
    """A 0..1 mask of vertical rain streaks from a leaking scan.

    The mask is the per-column darkness of the scan, smeared sideways, so the grime
    runs down the wall the way the dossier asks for.
    """
    arr = load_gray(tid, "diff", size)
    if arr is None:
        return None
    h, w = arr.shape
    col = arr.mean(axis=0)
    col = (col - col.min()) / max(float(col.max() - col.min()), 1e-5)
    # smear the column profile sideways into streaks
    acc = np.zeros((h, w), dtype=np.float32)
    for i in range(w):
        lo = max(0, i - w // columns)
        hi = min(w, i + w // columns)
        acc[:, i] = col[lo:hi].mean()
    mask = 1.0 - acc
    mask = np.clip((mask - 0.45) * 2.2, 0.0, 1.0)
    return mask

