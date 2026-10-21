"""Shared helpers for the NPC texture generator (PIL + numpy, system python3)."""
import io
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

FONT_PATH = os.path.expanduser("~/m/skyrush/game/assets/fonts/NotoSansSC-Variable.ttf")
RNG = np.random.default_rng(20310)


def font(size, weight=None):
    """Noto Sans SC variable instance (weight: 'Bold' / 'Medium' / None)."""
    f = ImageFont.truetype(FONT_PATH, size)
    if weight:
        try:
            f.set_variation_by_name(weight)
        except Exception as exc:               # pragma: no cover - font sanity
            raise RuntimeError("variable font weight %r unavailable" % weight) from exc
    return f


def fit_font(text, size, max_w, max_h, weight="Bold"):
    """Largest font size at or below `size` that fits the text in the box."""
    probe = ImageDraw.Draw(Image.new("L", (8, 8), 0))
    for s in range(size, 8, -2):
        f = font(s, weight)
        b = probe.textbbox((0, 0), text, font=f)
        if (b[2] - b[0]) <= max_w and (b[3] - b[1]) <= max_h:
            return f
    return font(10, weight)


def text_size(draw, text, f):
    b = draw.textbbox((0, 0), text, font=f)
    return b[2] - b[0], b[3] - b[1]


def draw_centered(draw, box, text, f, fill):
    """Draw text centred in `box` = (x0, y0, x1, y1)."""
    x0, y0, x1, y1 = box
    w, h = text_size(draw, text, f)
    draw.text((x0 + (x1 - x0 - w) * 0.5, y0 + (y1 - y0 - h) * 0.5), text, font=f,
              fill=fill)


def save(img, name, out_dir):
    """Write the sheet only when its bytes changed.

    A rebuild that produces the same image must not touch the file: Godot
    would re-import it and the whole team waits behind the import lock.
    """
    path = os.path.join(out_dir, name)
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    data = buf.getvalue()
    if os.path.exists(path):
        with open(path, "rb") as fh:
            if fh.read() == data:
                print("  %-28s %s unchanged" % (name, img.size))
                return path
    with open(path, "wb") as fh:
        fh.write(data)
    print("  %-28s %s" % (name, img.size))
    return path


def value_noise(size, cells, seed=0):
    """Smooth value noise in [0, 1]."""
    rng = np.random.default_rng(seed)
    small = rng.random((cells + 1, cells + 1))
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 255.0


def fbm(size, cells, octaves=3, seed=0):
    """Fractal value noise in [0, 1]."""
    out = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    total = 0.0
    for i in range(octaves):
        out += value_noise(size, cells * (2 ** i), seed + i * 17) * amp
        total += amp
        amp *= 0.5
    return out / total


def normal_from_height(height, strength=1.0):
    """Height field (numpy, rows = v down) -> tangent-space normal map image."""
    hx = np.gradient(height, axis=1)
    hy = np.gradient(height, axis=0)
    nx = -hx * strength
    ny = -hy * strength
    nz = np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / length, ny / length, nz / length
    rgb = np.stack([(nx * 0.5 + 0.5), (ny * 0.5 + 0.5), (nz * 0.5 + 0.5)], axis=-1)
    return Image.fromarray((rgb * 255).astype(np.uint8), "RGB")


def hex_rgb(token):
    """'#RRGGBB' -> (r, g, b) bytes."""
    t = token.lstrip("#")
    return tuple(int(t[i:i + 2], 16) for i in (0, 2, 4))


def noise_overlay(img, amount=10, seed=3):
    """Add fine grain to an RGB image."""
    arr = np.asarray(img, dtype=np.float32)
    rng = np.random.default_rng(seed)
    arr += (rng.random(arr.shape) - 0.5) * amount
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
