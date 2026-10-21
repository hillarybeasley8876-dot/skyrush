"""The carved stone reliefs: the shikumen pediment panels and the heritage lintels.

Four cells of 512 px in a 1024 sheet, drawn as a relief (white = raised, black =
recessed) so that the normal map is a real carving and not a bump.  The motifs are
the ones of a 石库门 pediment: a 福 medallion, a ruyi scroll, a lotus and a fret.
"""
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from .atlas import slot

SHEET = 1024
COLS = 2
ROWS = 2
CELL = SHEET // COLS

STONE = (216, 208, 190)
STONE_DARK = (168, 158, 140)

FONT = "~/Library/Fonts/NotoSansCJKsc-Bold.otf"


def _font(size):
    import os
    from PIL import ImageFont
    return ImageFont.truetype(os.path.expanduser(FONT), size)


def _medallion(cell):
    """A 福 medallion in a ring: the classic carved panel."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=0)
    d.ellipse([w * 0.12, h * 0.10, w * 0.88, h * 0.90], fill=255)
    d.ellipse([w * 0.20, h * 0.18, w * 0.80, h * 0.82], fill=0)
    d.text((w * 0.30, h * 0.26), "福", font=_font(int(h * 0.42)), fill=255)
    # the ring beads
    for i in range(24):
        a = i * 2.0 * math.pi / 24.0
        cx = w * 0.5 + math.cos(a) * w * 0.34
        cy = h * 0.5 + math.sin(a) * h * 0.34
        d.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], fill=255)
    return cell


def _scroll(cell):
    """A ruyi cloud scroll."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=0)
    d.arc([w * 0.10, h * 0.28, w * 0.52, h * 0.72], 200, 20, fill=255, width=26)
    d.arc([w * 0.48, h * 0.28, w * 0.90, h * 0.72], 160, 340, fill=255, width=26)
    d.ellipse([w * 0.42, h * 0.40, w * 0.58, h * 0.60], fill=255)
    d.polygon([(w * 0.20, h * 0.46), (w * 0.34, h * 0.40), (w * 0.30, h * 0.58)], fill=255)
    d.polygon([(w * 0.80, h * 0.46), (w * 0.66, h * 0.40), (w * 0.70, h * 0.58)], fill=255)
    return cell


def _lotus(cell):
    """A lotus flower: eight petals around a seed pod."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=0)
    cx, cy = w * 0.5, h * 0.52
    for i in range(8):
        a = i * math.pi / 4.0 - math.pi / 2.0
        px = cx + math.cos(a) * w * 0.20
        py = cy + math.sin(a) * h * 0.22
        d.ellipse([px - w * 0.11, py - h * 0.14, px + w * 0.11, py + h * 0.14], fill=255)
    d.ellipse([cx - w * 0.09, cy - h * 0.11, cx + w * 0.09, cy + h * 0.11], fill=0)
    d.ellipse([cx - w * 0.07, cy - h * 0.09, cx + w * 0.07, cy + h * 0.09], fill=255)
    return cell


def _fret(cell):
    """A 回 fret band: the geometric border of a carved lintel."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=0)
    unit = w / 4.0
    for i in range(4):
        x = i * unit
        d.rectangle([x + unit * 0.12, h * 0.18, x + unit * 0.88, h * 0.82], outline=255,
                    width=22)
        d.rectangle([x + unit * 0.34, h * 0.38, x + unit * 0.66, h * 0.62], fill=255)
    d.rectangle([0, h * 0.06, w - 1, h * 0.16], fill=255)
    d.rectangle([0, h * 0.84, w - 1, h * 0.94], fill=255)
    return cell


DRAWERS = [_medallion, _scroll, _lotus, _fret]
ORDER = ["medallion", "scroll", "lotus", "fret"]


def build():
    """The carving atlas: the albedo, the relief height and the cell manifest."""
    relief = Image.new("L", (SHEET, SHEET), 0)
    entries = []
    for i, name in enumerate(ORDER):
        cx = (i % COLS) * CELL
        cy = (i // COLS) * CELL
        cell = Image.new("L", (CELL, CELL), 0)
        DRAWERS[i](cell)
        cell = cell.filter(ImageFilter.GaussianBlur(1.6))
        relief.paste(cell, (cx, cy))
        u0, v0, u1, v1 = slot(SHEET, SHEET, cx, cy, CELL, CELL)
        entries.append({"id": "carving_%s" % name, "atlas": "carvings", "u0": u0, "v0": v0,
                        "u1": u1, "v1": v1, "carving": name})
    height = np.asarray(relief, dtype=np.float32) / 255.0
    # the albedo: the stone, with the recess of the carving a little darker
    albedo = np.zeros((SHEET, SHEET, 3), dtype=np.float32)
    base = np.array(STONE, dtype=np.float32) / 255.0
    dark = np.array(STONE_DARK, dtype=np.float32) / 255.0
    m = height[..., None]
    albedo = base[None, None, :] * (0.82 + 0.18 * m) + dark[None, None, :] * (1.0 - m) * 0.5
    return Image.fromarray((np.clip(albedo, 0, 1) * 255).astype(np.uint8)), entries, height
