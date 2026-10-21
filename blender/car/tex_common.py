"""Shared helpers for the Roadster's generated textures (numpy + PIL only).

Run outside Blender:  /usr/bin/python3 blender/car/gen_textures.py
Every normal map is built from a height field in METRES and converted with the
texel density of its own map, so the encoded normals really vary (the build
fails if a normal map comes out flat - see the gate in save()).
"""
import io
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.expanduser("~/m/skyrush")
OUT = os.path.join(ROOT, "blender", "car", "textures")
LIB = os.path.join(ROOT, "game", "assets", "textures")
FONT = os.path.join(ROOT, "game", "assets", "fonts", "NotoSansSC-Variable.ttf")
LOFT = os.path.join(ROOT, "ref", "roadster", "roadster_loft.json")
STATS = []
WRITTEN = [0]
UNCHANGED = [0]


def loft():
    """The parsed roadster_loft.json."""
    with open(LOFT) as f:
        return json.load(f)


def save(name, arr, check_normal=False):
    """Write a PNG; normal maps must show real variation or the build fails.

    The PNG is encoded in memory and compared with the file on disk: an
    identical file is NOT rewritten, so a rebuild never touches a texture that
    has not changed (lead note IMPORT-CHURN: Godot re-imports every file whose
    mtime moves).
    """
    os.makedirs(OUT, exist_ok=True)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    data = buf.getvalue()
    path = os.path.join(OUT, name)
    if os.path.exists(path) and open(path, "rb").read() == data:
        UNCHANGED[0] += 1
    else:
        with open(path, "wb") as f:
            f.write(data)
        WRITTEN[0] += 1
    if check_normal:
        a = np.asarray(img, np.float32)
        rg = a[:, :, :2]
        std = float(rg.std())
        flat = float((np.abs(rg - 127.5) <= 0.5).all(axis=2).mean())
        changed = 1.0 - flat
        STATS.append((name, std, changed, len(np.unique(a[:, :, 0]))))
        print("  %-24s %dx%d  std(RG)=%.2f  changed=%.2f%%  unique(R)=%d"
              % (name, img.size[0], img.size[1], std, changed * 100.0,
                 len(np.unique(a[:, :, 0]))))
        if std < 3.0 or changed < 0.05:
            raise SystemExit("FAIL %s is flat (std %.2f, changed %.3f%%) - the normal "
                             "map is not being generated" % (name, std, changed * 100.0))
    return path


def report():
    """Print the written/unchanged tally of this run."""
    print("textures: written %d / unchanged %d" % (WRITTEN[0], UNCHANGED[0]))
    return WRITTEN[0], UNCHANGED[0]


def height_to_normal(h_m, px_per_m):
    """Normal map from a height field in metres.

    `px_per_m` is the texel density of the map (scalar or (rows, cols)); the
    per-pixel difference is multiplied by it to get the true slope.
    """
    h = np.asarray(h_m, np.float32)
    gy, gx = np.gradient(h)
    if isinstance(px_per_m, (tuple, list)):
        py, px = px_per_m
    else:
        py = px = px_per_m
    nx = -gx * px
    ny = -gy * py
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    out = np.empty(h.shape + (3,), np.float32)
    out[..., 0] = nx / ln * 0.5 + 0.5
    out[..., 1] = ny / ln * 0.5 + 0.5
    out[..., 2] = nz / ln * 0.5 + 0.5
    return out * 255.0


def blur(a, sigma=1.2):
    """Small gaussian blur (separable, numpy only)."""
    if sigma <= 0:
        return a
    r = max(1, int(sigma * 2.5))
    x = np.arange(-r, r + 1, dtype=np.float32)
    k = np.exp(-(x ** 2) / (2 * sigma * sigma))
    k /= k.sum()
    out = np.apply_along_axis(lambda m: np.convolve(m, k, mode="same"), 0, a)
    out = np.apply_along_axis(lambda m: np.convolve(m, k, mode="same"), 1, out)
    return out


def noise(n, cells, amp, seed):
    """Smooth value noise in 0..amp, `cells` cells across the map."""
    small = (np.random.default_rng(seed).random((cells, cells)) - 0.5) * amp
    return np.asarray(Image.fromarray(small.astype(np.float32)).resize(
        (n, n), Image.BILINEAR), np.float32)


def font(size):
    """The project font (bold) for the plate and the tyre lettering."""
    from PIL import ImageFont
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_name("Bold")
    except Exception:
        pass
    return f
