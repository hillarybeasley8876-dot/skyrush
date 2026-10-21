"""Shared helpers for the Bund's procedural textures (bund unit).

Pure numpy/PIL - no Blender needed, so the maps can be regenerated in seconds.
Every map is tileable and 1 UV unit = 1 metre in the material.
"""
import io
import json
import os

import numpy as np

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), "game", "assets", "bund", "textures")

WRITTEN = [0]
UNCHANGED = [0]


def value_noise(size, cells, rng):
    """Tileable value noise in [0,1], `cells` cells across the image."""
    g = rng.random((cells + 1, cells + 1))
    g[-1, :] = g[0, :]
    g[:, -1] = g[:, 0]
    t = np.arange(size) / size * cells
    t0 = np.floor(t).astype(int)
    ft = t - t0
    ft = ft * ft * (3.0 - 2.0 * ft)
    a = g[np.ix_(t0, t0)]
    b = g[np.ix_(t0, t0 + 1)]
    c = g[np.ix_(t0 + 1, t0)]
    d = g[np.ix_(t0 + 1, t0 + 1)]
    fx = ft[None, :]
    fy = ft[:, None]
    return (a * (1 - fx) * (1 - fy) + b * fx * (1 - fy)
            + c * (1 - fx) * fy + d * fx * fy)


def fbm(size, cells, rng, octaves=4, gain=0.5):
    """Fractal value noise in [0,1]."""
    out = np.zeros((size, size))
    amp, tot, c = 1.0, 0.0, cells
    for _ in range(octaves):
        out += amp * value_noise(size, c, rng)
        tot += amp
        amp *= gain
        c *= 2
    return out / tot


def save(name, arr, quality=90):
    """Save a uint8 RGB array as JPEG in the unit texture folder.

    The file is only written when its bytes change: a re-run of the generator must not
    touch the texture files, or Godot re-imports the whole district for nothing (the
    import churn the lead's note is about)."""
    from PIL import Image          # Blender's python has no PIL; the maps are written outside
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    buf = io.BytesIO()
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(buf, format="JPEG",
                                                                quality=quality)
    data = buf.getvalue()
    if _same(path, data):
        UNCHANGED[0] += 1
        return path
    with open(path, "wb") as fh:
        fh.write(data)
    WRITTEN[0] += 1
    print("  %-26s %s" % (name, path))
    return path


def save_png(name, arr):
    """Save a uint8 RGB(A) array as PNG (the wash atlas), only when it changes."""
    from PIL import Image
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    buf = io.BytesIO()
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(buf, format="PNG")
    data = buf.getvalue()
    if _same(path, data):
        UNCHANGED[0] += 1
        return path
    with open(path, "wb") as fh:
        fh.write(data)
    WRITTEN[0] += 1
    print("  %-26s %s" % (name, path))
    return path


def save_json(name, payload):
    """Write a JSON sidecar next to the maps, only when it changes."""
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    data = (json.dumps(payload, indent=1, sort_keys=True) + "\n").encode("utf-8")
    if _same(path, data):
        UNCHANGED[0] += 1
        return path
    with open(path, "wb") as fh:
        fh.write(data)
    WRITTEN[0] += 1
    print("  %-26s %s" % (name, path))
    return path


def _same(path, data):
    """Does the file on disk already hold these bytes?"""
    if not os.path.exists(path):
        return False
    with open(path, "rb") as fh:
        return fh.read() == data


def report():
    """The summary the generator prints: how many maps changed and how many did not."""
    print("  maps: %d written, %d unchanged" % (WRITTEN[0], UNCHANGED[0]))
    return WRITTEN[0], UNCHANGED[0]


def measure(name):
    """Measure a map: the grain of the diffuse and the tilt of the normal.

    The review asks the generator to print both for every map, so the art numbers (the
    grain of the granite, the tilt of the mouldings) are checked and not assumed."""
    from PIL import Image
    base = name.split("_diff")[0]
    diff_path = os.path.join(OUT, name)
    if not os.path.exists(diff_path):
        return None
    diff = np.asarray(Image.open(diff_path).convert("L")).astype(float)
    # the high pass of the diffuse: the grain of the surface
    blur = diff.copy()
    for _ in range(3):
        pad = np.pad(blur, 2, mode="edge")
        acc = np.zeros_like(blur)
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                acc += pad[2 + dy:2 + dy + blur.shape[0], 2 + dx:2 + dx + blur.shape[1]]
        blur = acc / 25.0
    grain = float((diff - blur).std())
    tilt = 0.0
    nor_path = os.path.join(OUT, base + "_nor_gl.jpg")
    if os.path.exists(nor_path):
        n = np.asarray(Image.open(nor_path).convert("RGB")).astype(float) / 255.0
        nx = n[:, :, 0] * 2.0 - 1.0
        ny = n[:, :, 1] * 2.0 - 1.0
        nz = np.maximum(n[:, :, 2] * 2.0 - 1.0, 1e-3)
        tilt = float(np.degrees(np.arctan(np.sqrt(nx * nx + ny * ny) / nz)).mean())
    return grain, tilt


def print_stats(names):
    """Print the grain and the tilt of every map, and the worst of them."""
    rows = []
    for name in names:
        got = measure(name)
        if got is None:
            continue
        rows.append((name, got[0], got[1]))
    if not rows:
        return
    print("  %-26s %8s %8s" % ("map", "grain", "tilt"))
    for name, grain, tilt in rows:
        print("  %-26s %8.1f %7.1f deg" % (name, grain, tilt))
    worst = min(rows, key=lambda r: r[2])
    print("  the flattest normal: %s at %.1f deg" % (worst[0], worst[2]))
    return rows


def normal_from_height(h, strength=2.0):
    """Tangent-space normal map (RGB) from a height field in [0,1], OpenGL (green up)."""
    gy, gx = np.gradient(h)
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(h)
    n = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([(nx / n) * 0.5 + 0.5, (ny / n) * 0.5 + 0.5, (nz / n) * 0.5 + 0.5], axis=-1) * 255.0


def save_set(prefix, diff, height, rough, strength=2.0, rough_size=1024, maps="all"):
    """Write <prefix>_diff / _nor_gl / _rough - the naming the core material library expects
    (lib/mats.py looks up <id>_nor_gl.* for the normal map).

    `maps` picks the set: "all" for a surface, "nrm" without the roughness, "diff" for a
    material that only uses its colour (the emissive maps - the clock dial, the cove, the
    flood curtain, the window glow, the lantern paper, the pyramid glow).

    The roughness map is written at a lower resolution: it is low frequency data and the
    glTF exporter keeps it as a lossless PNG, so a 2048 map would cost megabytes."""
    save(prefix + "_diff.jpg", diff)
    if maps in ("all", "nrm"):
        save(prefix + "_nor_gl.jpg", normal_from_height(height, strength))
    if maps == "all":
        small = rough
        if rough.shape[0] > rough_size:
            step = rough.shape[0] // rough_size
            small = rough[::step, ::step]
        save(prefix + "_rough.jpg", np.repeat((small * 255.0)[:, :, None], 3, axis=2))


def srgb(r, g, b):
    """An sRGB triple (0-255) as a float array."""
    return np.array([r, g, b], dtype=float)
