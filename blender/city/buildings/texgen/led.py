"""LED screen ad panels (baked): colourful parody ads with a visible LED dot grid.

Four panels in a 2048x2048 atlas (2x2 of 1024).  Content is our own parody advertising
(art dossier 7.1) - no real brands.
"""
import os

import numpy as np
from PIL import Image, ImageDraw

from . import atlas_neon as an

CELL = 1024
PANELS = [
    {"text": "飞驰申城", "sub": "申城夜赛", "bg": (14, 10, 40), "fg": (255, 43, 214),
     "accent": (25, 230, 255)},
    {"text": "申城闪充", "sub": "一秒充满", "bg": (6, 30, 38), "fg": (32, 224, 255),
     "accent": (255, 176, 0)},
    {"text": "东方霓虹", "sub": "浦江夜色", "bg": (38, 8, 24), "fg": (255, 63, 216),
     "accent": (155, 92, 255)},
    {"text": "海派百货", "sub": "南京东路", "bg": (30, 20, 6), "fg": (255, 176, 0),
     "accent": (255, 42, 58)},
    {"text": "夜行巴士", "sub": "末班三路", "bg": (10, 24, 16), "fg": (120, 255, 160),
     "accent": (255, 214, 92)},
    {"text": "洋河老窖", "sub": "绵柔好酒", "bg": (36, 18, 10), "fg": (255, 198, 120),
     "accent": (220, 60, 40)},
    {"text": "沪上阿姨", "sub": "五谷现磨", "bg": (24, 12, 30), "fg": (250, 150, 220),
     "accent": (120, 220, 255)},
    {"text": "明日广场", "sub": "九点开门", "bg": (8, 18, 34), "fg": (140, 220, 255),
     "accent": (255, 120, 60)},
]


def _panel(spec, seed=0):
    img = Image.new("RGB", (CELL, CELL), spec["bg"])
    d = ImageDraw.Draw(img)
    # diagonal colour bands
    for i in range(6):
        x = -CELL + i * (CELL // 3)
        d.polygon([(x, 0), (x + 90, 0), (x + 90 + CELL, CELL), (x + CELL, CELL)],
                  fill=tuple(int(c * 0.22) for c in spec["accent"]))
    # a big roundel
    d.ellipse([120, 120, 520, 520], outline=spec["accent"], width=14)
    d.ellipse([200, 200, 440, 440], fill=tuple(int(c * 0.35) for c in spec["fg"]))
    # headline
    font = an.font(an.FONT_BOLD, 190)
    bb = d.textbbox((0, 0), spec["text"], font=font)
    d.text(((CELL - (bb[2] - bb[0])) * 0.5 - bb[0], 560), spec["text"], font=font,
           fill=spec["fg"])
    sub = an.font(an.FONT_BOLD, 96)
    bb = d.textbbox((0, 0), spec["sub"], font=sub)
    d.text(((CELL - (bb[2] - bb[0])) * 0.5 - bb[0], 790), spec["sub"], font=sub,
           fill=(240, 240, 250))
    # bottom rule and ticks
    d.rectangle([0, 930, CELL, 946], fill=spec["accent"])
    for i in range(16):
        d.rectangle([20 + i * 62, 960, 52 + i * 62, 1000], fill=spec["fg"])
    return img


def build(out_dir):
    """Write led_ads.jpg plus the slot list (eight panels in a 4 x 2 atlas)."""
    os.makedirs(out_dir, exist_ok=True)
    cols = 4
    rows = 2
    width = CELL * cols
    height = CELL * rows
    img = Image.new("RGB", (width, height), (0, 0, 0))
    manifest = []
    for i, spec in enumerate(PANELS):
        cx = (i % cols) * CELL
        cy = (i // cols) * CELL
        img.paste(_panel(spec), (cx, cy))
        u0, u1 = cx / float(width), (cx + CELL) / float(width)
        v1, v0 = 1.0 - cy / float(height), 1.0 - (cy + CELL) / float(height)
        manifest.append({"id": "led_%d" % i, "atlas": "led_ads", "text": spec["text"],
                         "color": "screen", "u0": u0, "v0": v0, "u1": u1, "v1": v1,
                         "aspect": 1.0, "style": "led"})
    # LED dot grid: darken every 8th pixel column/row
    arr = np.asarray(img).astype(np.float32)
    mask = np.zeros(arr.shape[:2], dtype=np.float32)
    mask[::8, :] = 1.0
    mask[:, ::8] = 1.0
    arr *= (1.0 - mask[..., None] * 0.42)
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(
        os.path.join(out_dir, "led_ads.jpg"), quality=92)
    return manifest
