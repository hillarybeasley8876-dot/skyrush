#!/usr/bin/env python3
"""Generates the textures of the race gates of SKYRUSH.

The textures are generated once, offline, and committed: the game never writes into res://
(a packaged game has a read-only project folder) and the headless tests see the same art as
the windowed run.

    python3 game/modes/tools/gen_gate_textures.py

Output (res://modes/textures/):
    gate_board_<kind>_<index>_<total>.png   the LED sign panel of a gate (the text as LED dots)
    gate_ground_chevrons.png                 the chevrons of the tarmac under a gate
    gate_plinth_hazard.png                   the hazard stripes of the plinth of a pylon
    gate_checker_band.png                    the black/white band of a start/finish line
"""

import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT = os.path.join(ROOT, "game", "modes", "textures")
FONT = os.path.join(ROOT, "game", "assets", "fonts", "NotoSansSC-Variable.ttf")

# The sign panel: 2048 x 256 px over a 9 m x 1.12 m panel (about 227 px/m).
BOARD_W = 2048
BOARD_H = 256
DOT = 6  # the pitch of the LED dots (px)
PANEL = (10, 15, 30)  # #0A0F1E
RING = (26, 36, 58)  # the unlit dots of the panel

TINTS = {
    "start": (255, 176, 0),
    "finish": (255, 45, 85),
    "start_finish": (255, 176, 0),
    "checkpoint": (25, 230, 255),
}


def font(size):
    return ImageFont.truetype(FONT, size)


def board_text(kind, index, total):
    """The text of a board: the Chinese first, the English behind it."""
    if kind == "start":
        return "起点  START", "起点", "START"
    if kind == "finish":
        return "终点  FINISH", "终点", "FINISH"
    if kind == "start_finish":
        return "起点/终点  START/FINISH", "起点/终点", "START/FINISH"
    return "检查点 %d/%d  CHECKPOINT" % (index + 1, total), "检查点 %d/%d" % (index + 1, total), "CHECKPOINT"


def lit_mask(size, text_cn, text_en):
    """The mask of the letters: the Chinese big, the English small and dim."""
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    fnt_cn = font(150)
    fnt_en = font(104)
    box_cn = draw.textbbox((0, 0), text_cn, font=fnt_cn)
    box_en = draw.textbbox((0, 0), text_en, font=fnt_en)
    width = (box_cn[2] - box_cn[0]) + 46 + (box_en[2] - box_en[0])
    x = (size[0] - width) * 0.5
    base = (size[1] - (box_cn[3] - box_cn[1])) * 0.5 - box_cn[1]
    draw.text((x, base), text_cn, font=fnt_cn, fill=255)
    draw.text((x + (box_cn[2] - box_cn[0]) + 46, base + 34), text_en, font=fnt_en, fill=255)
    return mask


def dot_pattern(mask, cell):
    """The dots of the panel: a cell is lit when the letters cover it."""
    w, h = mask.size
    cols = w // cell
    rows = h // cell
    small = mask.resize((cols, rows), Image.LANCZOS)
    return small.point(lambda v: 255 if v > 95 else 0)


def draw_board(kind, index, total):
    tint = TINTS[kind]
    text_cn, cn, en = board_text(kind, index, total)
    mask = lit_mask((BOARD_W, BOARD_H), cn, en)
    dots = dot_pattern(mask, DOT)

    panel = Image.new("RGB", (BOARD_W, BOARD_H), PANEL)
    draw = ImageDraw.Draw(panel)
    # The unlit dots of the panel: a grid of dark pixels behind the letters.
    for cy in range(BOARD_H // DOT):
        for cx in range(BOARD_W // DOT):
            x = cx * DOT + DOT // 2
            y = cy * DOT + DOT // 2
            draw.ellipse([x - 1, y - 1, x + 1, y + 1], fill=RING)
    # The lit dots: the letters as a matrix of LEDs.
    lit = Image.new("RGB", (BOARD_W, BOARD_H), (0, 0, 0))
    lit_draw = ImageDraw.Draw(lit)
    dot_mask = Image.new("L", (BOARD_W, BOARD_H), 0)
    mask_draw = ImageDraw.Draw(dot_mask)
    for cy in range(BOARD_H // DOT):
        for cx in range(BOARD_W // DOT):
            if dots.getpixel((cx, cy)) < 128:
                continue
            x = cx * DOT + DOT // 2
            y = cy * DOT + DOT // 2
            lit_draw.ellipse([x - 2, y - 2, x + 2, y + 2], fill=tint)
            mask_draw.ellipse([x - 2, y - 2, x + 2, y + 2], fill=255)
    # The halo of the letters: the bloom does the rest in the engine.
    halo = lit.filter(ImageFilter.GaussianBlur(4.0))
    panel = ImageChops.screen(panel, halo)
    panel.paste(lit, (0, 0), dot_mask)
    path = os.path.join(OUT, "gate_board_%s_%d_%d.png" % (kind, index, total))
    panel.save(path)
    return path


def supersampled(size, factor=4):
    """A canvas that is drawn big and reduced afterwards: the edges come out smooth."""
    return Image.new("RGBA", (size[0] * factor, size[1] * factor), (0, 0, 0, 0))


def draw_ground_chevrons():
    """The chevrons of the tarmac under a gate (the arrows point along the road)."""
    w, h = 2048, 512
    canvas = supersampled((w, h), 2)
    draw = ImageDraw.Draw(canvas)
    yellow = (242, 194, 0, 255)
    dark = (17, 17, 19, 255)
    # Three nested chevrons that point along the road (the apex is up in the image).
    for i, top in enumerate((0.06, 0.38, 0.70)):
        apex = (w, h * 2 * top)
        left = (0, h * 2 * (top + 0.30))
        right = (w * 2, h * 2 * (top + 0.30))
        draw.line([left, apex, right], fill=dark, width=int(h * 0.09), joint="curve")
        draw.line([left, apex, right], fill=yellow, width=int(h * 0.055), joint="curve")
    image = canvas.resize((w, h), Image.LANCZOS)
    # The chevrons fade out at the sides of the road.
    alpha = image.getchannel("A")
    ramp = Image.new("L", (w, h), 0)
    ramp_draw = ImageDraw.Draw(ramp)
    for x in range(w):
        edge = min(x, w - 1 - x) / float(w * 0.12)
        ramp_draw.line([(x, 0), (x, h)], fill=int(255 * min(1.0, max(0.0, edge))))
    image.putalpha(Image.composite(alpha, Image.new("L", (w, h), 0), ramp))
    path = os.path.join(OUT, "gate_ground_chevrons.png")
    image.save(path)
    return path


def draw_plinth_hazard():
    """The hazard stripes of the plinth of a pylon (#F2C200 on #111113)."""
    w = h = 512
    canvas = supersampled((w, h), 2)
    draw = ImageDraw.Draw(canvas)
    yellow = (242, 194, 0, 255)
    black = (17, 17, 19, 255)
    draw.rectangle([0, 0, w * 2, h * 2], fill=black)
    band = h * 2 // 6
    for i in range(-h * 2, w * 2 * 2, band * 2):
        draw.polygon(
            [(i, h * 2), (i + band, h * 2), (i + band + h * 2, 0), (i + h * 2, 0)], fill=yellow
        )
    image = canvas.resize((w, h), Image.LANCZOS)
    path = os.path.join(OUT, "gate_plinth_hazard.png")
    image.save(path)
    return path


def draw_checker_band():
    """The black/white band of a start/finish line."""
    w, h = 512, 64
    image = Image.new("RGB", (w, h), (17, 17, 19))
    draw = ImageDraw.Draw(image)
    cell = 32
    for y in range(h // cell):
        for x in range(w // cell):
            if (x + y) % 2 == 0:
                draw.rectangle(
                    [x * cell, y * cell, (x + 1) * cell - 1, (y + 1) * cell - 1], fill=(242, 246, 255)
                )
    path = os.path.join(OUT, "gate_checker_band.png")
    image.save(path)
    return path


def route_gates():
    """The number of gates of every route of the city and of the sandbox."""
    import json

    out = []
    city = os.path.join(ROOT, "data", "city", "city.json")
    with open(city, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    for route in data.get("routes", []):
        count = len(route.get("checkpoints", []))
        if count > 1:
            out.append(count)
    out.append(8)  # the sandbox loop of the core
    return out


def main():
    if not os.path.isdir(OUT):
        os.makedirs(OUT)
    written = 0
    for count in route_gates():
        for index in range(count):
            for kind in ("checkpoint",):
                draw_board(kind, index, count)
                written += 1
        # The start, the finish and the start/finish of the same route.
        draw_board("start", 0, count)
        draw_board("finish", count - 1, count)
        draw_board("start_finish", 0, count)
        written += 3
    draw_ground_chevrons()
    draw_plinth_hazard()
    draw_checker_band()
    print("gate textures: %d boards + 3 panels written to %s" % (written, OUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
