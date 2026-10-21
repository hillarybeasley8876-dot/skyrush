"""Font + text helpers for the SKYRUSH sign generators (unit: props).

Fonts are the OFL faces already vendored in game/assets/fonts/:
  NotoSansSC-Variable.ttf  - body text, Chinese + Latin (SIL OFL 1.1)
  SmileySans-Oblique.ttf   - display text, condensed oblique (SIL OFL 1.1)

Nothing here touches the network; the faces are local.
"""
import os

from PIL import ImageFont

ROOT = os.path.expanduser("~/m/skyrush")
FONT_DIR = os.path.join(ROOT, "game", "assets", "fonts")

NOTO = os.path.join(FONT_DIR, "NotoSansSC-Variable.ttf")
SMILEY = os.path.join(FONT_DIR, "SmileySans-Oblique.ttf")

# Noto Sans SC variable-font axis order: wght, wdth, opsz.
_NOTO_BOLD = 700
_cache = {}


def font(path, size, weight=None):
    """Cached ImageFont. `weight` (100..900) only applies to the variable Noto face."""
    key = (path, size, weight)
    if key in _cache:
        return _cache[key]
    f = ImageFont.truetype(path, size)
    if weight is not None and path == NOTO:
        try:
            f.set_variation_by_axes([weight])
        except OSError:
            pass
    _cache[key] = f
    return f


def noto(size, bold=False):
    """Noto Sans SC at `size` px; bold=True uses the 700 weight axis."""
    return font(NOTO, size, _NOTO_BOLD if bold else 400)


def smiley(size):
    """Smiley Sans (得意黑) — display / headline face."""
    return font(SMILEY, size)


def text_size(draw, text, fnt):
    """(width, height) of `text` in pixels."""
    box = draw.textbbox((0, 0), text, font=fnt)
    return box[2] - box[0], box[3] - box[1]


def draw_text(draw, xy, text, fnt, fill, anchor="la"):
    """Draw `text`; `anchor` uses PIL semantics (first char = h-align, second = v-align)."""
    draw.text(xy, text, font=fnt, fill=fill, anchor=anchor)


def fit_size(draw, text, path, start, min_size, weight=None, max_w=None, max_h=None):
    """Largest font size (<= start) that fits `text` into max_w/max_h."""
    size = start
    while size > min_size:
        f = font(path, size, weight)
        w, h = text_size(draw, text, f)
        if (max_w is None or w <= max_w) and (max_h is None or h <= max_h):
            return size
        size -= max(1, size // 12)
    return min_size


def triangle(draw, cx, cy, size, fill, up=True):
    """Solid triangle (used for ▲ / ▼ / arrow heads — the fonts have no usable glyph)."""
    half = size / 2.0
    if up:
        pts = [(cx, cy - half), (cx + half, cy + half * 0.8), (cx - half, cy + half * 0.8)]
    else:
        pts = [(cx, cy + half), (cx + half, cy - half * 0.8), (cx - half, cy - half * 0.8)]
    draw.polygon(pts, fill=fill)


def arrow(draw, x, y, length, width, fill, direction="right", head=0.42):
    """Guide-sign lane arrow drawn as polygons (straight / left / right)."""
    hl = length * head
    sw = width * 0.34
    if direction == "right":
        shaft = [(x, y - sw), (x + length - hl, y - sw), (x + length - hl, y - width / 2),
                 (x + length, y), (x + length - hl, y + width / 2), (x + length - hl, y + sw),
                 (x, y + sw)]
    elif direction == "left":
        shaft = [(x + length, y - sw), (x + hl, y - sw), (x + hl, y - width / 2),
                 (x, y), (x + hl, y + width / 2), (x + hl, y + sw), (x + length, y + sw)]
    else:  # up
        shaft = [(x - sw, y + length), (x - sw, y + hl), (x - width / 2, y + hl),
                 (x, y), (x + width / 2, y + hl), (x + sw, y + hl), (x + sw, y + length)]
    draw.polygon(shaft, fill=fill)


def fit_text(draw, text, path, size, box, weight=None, fill="white", align="center",
             v_center=True):
    """Draw `text` inside `box` = (x0, y0, x1, y1) corners, shrinking the font until it fits.

    Uses PIL middle-anchors so the ink is centred on the box, not just the layout box."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    s = size
    while s > 8:
        f = font(path, s, weight)
        tw, th = text_size(draw, text, f)
        if tw <= w and th <= h:
            break
        s -= max(1, s // 10)
    f = font(path, s, weight)
    h_align = {"left": "l", "center": "m", "right": "r"}[align]
    v_align = "m" if v_center else "a"
    cx = x0 + w / 2.0 if align == "center" else (x1 if align == "right" else x0)
    cy = y0 + h / 2.0
    draw.text((cx, cy), text, font=f, fill=fill, anchor=h_align + v_align)
    return s
