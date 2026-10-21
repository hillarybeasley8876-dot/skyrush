"""The small shared maps of the SKYRUSH props unit.

    /usr/bin/python3 tools/signs/prop_maps.py

These are the maps that do not belong to a tileable family: the opal diffuser
of a lamp head, the LED dot array of a lens, the grime and rain-streak decals,
the tinted glass and the baked ground light pool of a canopy (families.py).
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fontlib as F  # noqa: E402
import imwrite as IW  # noqa: E402
import surf_lib as S  # noqa: E402

ROOT = os.path.expanduser("~/m/skyrush")
SCRATCH = os.path.join(ROOT, "tmp", "props", "tex")


def opal_map(out_dir=None, size=256):
    """The opal diffuser of a lamp head: bright core, dimmer rim, faint petal seams."""
    out_dir = out_dir or SCRATCH
    img = Image.new("RGB", (size, size), (255, 250, 240))
    px = img.load()
    for y in range(size):
        for x in range(size):
            u = (x / (size - 1.0)) * 2.0 - 1.0
            v = (y / (size - 1.0)) * 2.0 - 1.0
            r = math.sqrt(u * u + v * v)
            glow = max(0.0, 1.0 - r * 1.15)
            seam = 0.94 + 0.06 * math.cos(6.0 * math.atan2(v, u))
            k = (0.62 + 0.38 * glow) * seam
            px[x, y] = (int(255 * k), int(250 * k), int(240 * k))
    path = os.path.join(out_dir, "prop_opal.png")
    IW.save(img, path, format="PNG")
    return path


def lens_dots_normal(out_dir=None, size=64, cells=8):
    """The LED dot array of a traffic-light lens, as a normal map."""
    out_dir = out_dir or SCRATCH
    img = Image.new("RGB", (size, size), (128, 128, 255))
    d = ImageDraw.Draw(img)
    step = size / float(cells)
    r = step * 0.34
    for gy in range(cells):
        for gx in range(cells):
            cx = (gx + 0.5) * step
            cy = (gy + 0.5) * step
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(168, 168, 255))
            d.ellipse([cx - r * 0.5, cy - r * 0.5, cx + r * 0.5, cy + r * 0.5],
                      fill=(196, 196, 255))
    path = os.path.join(out_dir, "prop_lens_dots_nor_gl.jpg")
    IW.save(img, path, format="JPEG", quality=90)
    return path


def wear_map(out_dir=None, size=256):
    """An alpha-masked grime decal: rain streaks and a dirt band, fading upwards."""
    out_dir = out_dir or SCRATCH
    rng = np.random.default_rng(7)
    img = Image.new("RGBA", (size, size), (26, 24, 22, 0))
    d = ImageDraw.Draw(img)
    for _ in range(40):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size * 0.55)
        ln = rng.uniform(size * 0.15, size * 0.8)
        w = int(rng.integers(1, 5))
        d.line([(x, y), (x + rng.uniform(-3, 3), y + ln)],
               fill=(34, 31, 28, int(rng.integers(40, 120))), width=w)
    for _ in range(30):
        x = rng.uniform(0, size)
        y = rng.uniform(size * 0.6, size)
        r = rng.uniform(2, 9)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(30, 28, 25, int(rng.integers(30, 90))))
    arr = np.asarray(img, dtype=np.float32)
    grad = np.linspace(0.0, 1.0, size, dtype=np.float32) ** 1.4
    arr[:, :, 3] *= grad[None, :]
    path = os.path.join(out_dir, "prop_wear.png")
    IW.save(Image.fromarray(arr.astype(np.uint8), "RGBA"), path, format="PNG")
    return path


def glass_map(out_dir=None, size=256):
    """Dark tinted glass: smooth, with faint smears and dust."""
    out_dir = out_dir or SCRATCH
    fine = S.pnoise(size, size, 40, 2, 91)
    broad = S.pnoise(size, size, 6, 2, 92)
    value = 0.86 + (fine - 0.5) * 0.10 + (broad - 0.5) * 0.08
    col = np.stack([np.clip(value * c, 0, 1) for c in (0.42, 0.50, 0.58)], axis=-1)
    rough = np.clip(0.10 + 0.10 * broad + 0.05 * fine, 0.04, 0.35)
    height = fine * 0.6 + broad * 0.4
    out = os.path.join(out_dir, "prop_glass_diff.jpg")
    IW.save(S.to_image(col), out, format="JPEG", quality=92)
    IW.save(S.height_to_normal(height, 1.2),
            os.path.join(out_dir, "prop_glass_nor_gl.jpg"), format="JPEG", quality=90)
    IW.save(S.to_image(rough), os.path.join(out_dir, "prop_glass_rough.jpg"),
            format="JPEG", quality=90)
    return out


def streaks_map(out_dir=None, size=256):
    """Rain-streak decal for the underside of a canopy edge: strong at the top."""
    out_dir = out_dir or SCRATCH
    rng = np.random.default_rng(13)
    img = Image.new("RGBA", (size, size), (24, 22, 20, 0))
    d = ImageDraw.Draw(img)
    for _ in range(90):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size * 0.35)
        ln = rng.uniform(size * 0.25, size * 0.95)
        w = int(rng.integers(1, 4))
        d.line([(x, y), (x + rng.uniform(-2, 2), y + ln)],
               fill=(30, 28, 25, int(rng.integers(50, 130))), width=w)
    arr = np.asarray(img, dtype=np.float32)
    grad = np.linspace(1.0, 0.0, size, dtype=np.float32) ** 1.5
    arr[:, :, 3] *= grad[None, :]
    path = os.path.join(out_dir, "prop_streaks.png")
    IW.save(Image.fromarray(arr.astype(np.uint8), "RGBA"), path, format="PNG")
    return path


def bay_numbers_map(out_dir=None, cell=256, cols=4, rows=3):
    """The charging bay numbers: white digits on a transparent sheet.

    The numbers used to sit in the sign atlas, where the alpha was lost, so
    they showed as dark tiles on the green bay.  They get their own sheet with
    an alpha channel and an alpha-scissor material instead.
    """
    out_dir = out_dir or SCRATCH
    img = Image.new("RGBA", (cols * cell, rows * cell), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(cols * rows):
        cx = (i % cols) * cell
        cy = (i // cols) * cell
        F.fit_text(d, "%02d" % (i + 1), F.NOTO, int(cell * 0.72),
                   (cx, cy, cx + cell, cy + cell), weight=700, fill=(244, 246, 244, 255))
    path = os.path.join(out_dir, "prop_bay_numbers.png")
    IW.save(img, path, format="PNG")
    return path


def deck_text_map(out_dir=None, size=1024):
    """The sky-lane deck marking: 飞行航道 SKY LANE, white on transparent."""
    out_dir = out_dir or SCRATCH
    img = Image.new("RGBA", (size, size // 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w, h = img.size
    F.fit_text(d, "飞行航道", F.NOTO, int(h * 0.62), (w * 0.04, h * 0.04, w * 0.96, h * 0.60),
               weight=700, fill=(236, 238, 234, 255))
    F.fit_text(d, "SKY LANE", F.SMILEY, int(h * 0.34),
               (w * 0.04, h * 0.58, w * 0.96, h * 0.98), fill=(214, 226, 232, 255))
    path = os.path.join(out_dir, "prop_deck_text.png")
    IW.save(img, path, format="PNG")
    return path


def road_marks_map(out_dir=None, cell_w=512, cell_h=240, gap=8):
    """The painted road markings of the toll plaza.

    Two cells (each 512 x 240): a lane arrow that points along +u, the
    traffic direction, and the green ETC marking.  White on transparent, so
    the paint sits on the concrete instead of on a dark tile.
    """
    out_dir = out_dir or SCRATCH
    w = cell_w * 2
    h = cell_h + gap * 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    y0 = gap
    # the arrow: a shaft with a head, pointing to the right
    sx0, sx1 = cell_w * 0.08, cell_w * 0.58
    sy = y0 + cell_h * 0.5
    d.rectangle([sx0, sy - cell_h * 0.09, sx1, sy + cell_h * 0.09], fill=(238, 240, 236, 255))
    d.polygon([(sx1, sy - cell_h * 0.34), (cell_w * 0.92, sy), (sx1, sy + cell_h * 0.34)],
              fill=(238, 240, 236, 255))
    # the ETC marking
    F.fit_text(d, "ETC", F.SMILEY, int(cell_h * 0.46), (cell_w * 1.04, y0 + cell_h * 0.06,
                                                       cell_w * 1.96, y0 + cell_h * 0.56),
               fill=(0x2E, 0xC8, 0x7A, 255))
    F.fit_text(d, "专用", F.NOTO, int(cell_h * 0.38), (cell_w * 1.04, y0 + cell_h * 0.50,
                                                      cell_w * 1.96, y0 + cell_h * 0.96),
               weight=700, fill=(0x2E, 0xC8, 0x7A, 255))
    path = os.path.join(out_dir, "prop_road_marks.png")
    IW.save(img, path, format="PNG")
    return path


def hologram_map(out_dir=None, size=256):
    """The artwork of the hologram ring: a cyan wash with a soft vertical falloff.

    The shared `SH_hologram` shader samples the imported material's emission
    map, so the ring needs one (without it the shader has no texture and the
    ring does not render).
    """
    out_dir = out_dir or SCRATCH
    img = Image.new("RGB", (size, size), (0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(size):
        v = 0.55 + 0.45 * math.sin(math.pi * y / float(size - 1))
        d.line([(0, y), (size, y)], fill=(int(9 * v), int(44 * v), int(56 * v)))
    for i in range(26):
        x = int(size * i / 26.0)
        d.line([(x, 0), (x, size)], fill=(3, 18, 24))
    path = os.path.join(out_dir, "prop_hologram.png")
    IW.save(img, path, format="PNG")
    return path


def build_small(out_dir=None):
    """The small shared maps (opal, lens dots, wear, glass, streaks, markings)."""
    out_dir = out_dir or SCRATCH
    os.makedirs(out_dir, exist_ok=True)
    return [opal_map(out_dir), lens_dots_normal(out_dir), wear_map(out_dir),
            glass_map(out_dir), streaks_map(out_dir), bay_numbers_map(out_dir),
            deck_text_map(out_dir), road_marks_map(out_dir),
            hologram_map(out_dir)]


if __name__ == "__main__":
    for p in build_small():
        print("MAP %s" % p)
