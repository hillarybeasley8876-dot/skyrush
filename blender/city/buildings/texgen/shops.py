"""The shop interior atlas: what a lit shopfront shows from three metres away.

A 2048 sheet with 4 x 4 = 16 cells; every cell is 512 x 512 px, which at 256 px/m
covers a 2.0 x 2.0 m view into the shop.  Each cell is a shop interior in one-point
perspective with its own fittings, so a row of shopfronts never repeats.
"""
import random

from PIL import Image, ImageDraw, ImageFilter

from .atlas import slot
from .interiors import COOL, LAMPS, NEUTRAL, TV, WARM, _room, _shade_room, _tint

SHEET = 2048
COLS = 4
ROWS = 4
CELL = SHEET // COLS

SHOP_WALL = [
    ("#D6CBB6", "#6E6454", "#F0E8D6"),
    ("#C6CBD0", "#5E646A", "#E2E6EA"),
    ("#E0D2BE", "#77685A", "#F4ECDC"),
    ("#B9B2A6", "#5A544C", "#D4CEC2"),
]


def _counter(d, box, rng, top=(188, 178, 160), front=(120, 110, 96)):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    x = bx0 + w * 0.04
    y = by1 - (by1 - by0) * 0.38
    d.rectangle([x, y, x + w * 0.66, by1], fill=front)
    d.rectangle([x, y, x + w * 0.66, y + 14], fill=top)


def _stools(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    for i in range(3):
        x = bx0 + w * (0.12 + i * 0.26)
        d.rectangle([x, by1 - 34, x + 26, by1 - 22], fill=(126, 92, 70))
        d.rectangle([x + 4, by1 - 22, x + 8, by1], fill=(96, 96, 98))
        d.rectangle([x + 18, by1 - 22, x + 22, by1], fill=(96, 96, 98))


def _bowls(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    for i in range(4):
        x = bx0 + w * (0.10 + i * 0.14)
        d.ellipse([x, by1 - (by1 - by0) * 0.46, x + 34, by1 - (by1 - by0) * 0.46 + 18],
                  fill=(238, 236, 228))


def _menu(d, box, rng, colour=(196, 60, 44)):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    d.rectangle([bx0 + w * 0.50, by0 + 14, bx1 - 10, by0 + (by1 - by0) * 0.46], fill=colour)
    for i in range(5):
        y = by0 + 26 + i * 16
        d.rectangle([bx0 + w * 0.53, y, bx1 - 24 - (i % 3) * 30, y + 7], fill=(244, 238, 226))


def _shelves(d, box, rng, colour=(150, 120, 90), rows=4, bright=None):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    for row in range(rows):
        y = by0 + 16 + row * (by1 - by0) * 0.19
        d.rectangle([bx0 + 10, y, bx1 - 10, y + 7], fill=(96, 92, 84))
        x = bx0 + 16
        while x < bx1 - 24:
            bw = rng.randint(10, 24)
            hgt = rng.randint(16, 34)
            c = bright if bright else (colour[0] + rng.randint(-40, 40),
                                       colour[1] + rng.randint(-40, 40),
                                       colour[2] + rng.randint(-40, 40))
            d.rectangle([x, y - hgt, x + bw, y], fill=tuple(max(0, min(255, v)) for v in c))
            x += bw + 4


def _fridges(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    for i in range(3):
        x = bx0 + 10 + i * (w * 0.30)
        d.rectangle([x, by0 + 20, x + w * 0.26, by1 - 6], fill=(210, 226, 232))
        d.rectangle([x + 6, by0 + 30, x + w * 0.26 - 6, by1 - 26], fill=(236, 246, 250))
        d.rectangle([x + 6, by0 + 30, x + w * 0.26 - 6, by0 + 60], fill=(190, 220, 236))
        d.rectangle([x + w * 0.20, by0 + 70, x + w * 0.24, by0 + 110], fill=(120, 126, 130))


def _rail(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    d.rectangle([bx0 + 12, by0 + 40, bx1 - 12, by0 + 48], fill=(150, 152, 156))
    x = bx0 + 20
    palette = [(190, 60, 60), (60, 90, 160), (220, 210, 190), (70, 130, 90), (200, 160, 60)]
    while x < bx1 - 40:
        gw = rng.randint(16, 30)
        gh = rng.randint(70, 140)
        c = palette[rng.randrange(len(palette))]
        d.rectangle([x, by0 + 48, x + gw, by0 + 48 + gh], fill=c)
        x += gw + 4


def _mirror(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    d.rectangle([bx0 + w * 0.10, by0 + 20, bx0 + w * 0.46, by0 + (by1 - by0) * 0.52],
                fill=(196, 206, 214))
    d.rectangle([bx0 + w * 0.10, by0 + 20, bx0 + w * 0.46, by0 + (by1 - by0) * 0.52],
                outline=(90, 92, 96), width=4)
    for i in range(6):
        x = bx0 + w * 0.10 + i * (w * 0.36) / 6
        d.ellipse([x - 6, by0 + 6, x + 6, by0 + 18], fill=(255, 238, 200))


def _chairs(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    for i in range(2):
        x = bx0 + w * (0.16 + i * 0.36)
        d.ellipse([x, by1 - 66, x + 54, by1 - 26], fill=(70, 70, 74))
        d.rectangle([x + 4, by1 - 40, x + 50, by1 - 12], fill=(96, 60, 60))
        d.rectangle([x + 6, by1 - 26, x + 12, by1], fill=(150, 152, 156))


def _glass_case(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    x = bx0 + w * 0.06
    y = by1 - (by1 - by0) * 0.36
    d.rectangle([x, y, x + w * 0.70, by1], fill=(150, 158, 164))
    d.rectangle([x + 4, y - 30, x + w * 0.70 - 4, y], fill=(206, 226, 232))
    d.rectangle([x + 4, y - 30, x + w * 0.70 - 4, y], outline=(120, 140, 150), width=2)


def _bread(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    d.rectangle([bx0 + 12, by1 - 44, bx1 - 12, by1], fill=(198, 190, 174))
    for i in range(6):
        x = bx0 + 20 + i * (w - 50) / 6
        d.ellipse([x, by1 - 62, x + 26, by1 - 40], fill=(196, 152, 96))


def _crates(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    colours = [(186, 74, 52), (212, 168, 60), (96, 140, 62), (150, 92, 160)]
    for r in range(2):
        for c in range(3):
            x = bx0 + 14 + c * (w - 40) / 3
            y = by1 - 20 - r * 40
            d.rectangle([x, y - 34, x + 40, y], fill=wood_colour())
            for i in range(4):
                d.ellipse([x + 6 + i * 9, y - 44, x + 14 + i * 9, y - 34],
                          fill=colours[(r + c + i) % len(colours)])


def wood_colour():
    return (140, 112, 78)


def _jars(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    for row in range(3):
        y = by0 + 20 + row * (by1 - by0) * 0.18
        d.rectangle([bx0 + 10, y, bx1 - 10, y + 8], fill=(110, 90, 66))
        x = bx0 + 16
        while x < bx1 - 26:
            r = rng.randint(7, 13)
            c = (150 + rng.randint(-40, 40), 110 + rng.randint(-30, 30), 60 + rng.randint(-20, 30))
            d.ellipse([x, y - r * 2, x + r * 2, y], fill=tuple(max(0, min(255, v)) for v in c))
            x += r * 2 + 5


def _mannequin(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    x = bx0 + w * 0.24
    d.ellipse([x, by0 + 30, x + 34, by0 + 64], fill=(214, 198, 178))
    d.polygon([(x + 2, by0 + 64), (x + 32, by0 + 64), (x + 40, by1 - 20), (x - 6, by1 - 20)],
              fill=(96, 78, 96))
    d.rectangle([x + 12, by1 - 20, x + 20, by1], fill=(160, 156, 150))


def _boxes(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    for i in range(3):
        x = bx0 + 16 + i * (w - 60) / 3
        d.rectangle([x, by1 - 46 - i * 6, x + 52, by1], fill=(150, 132, 106))
        d.line([x, by1 - 46 - i * 6, x + 52, by1], fill=(110, 96, 78), width=2)


def _shoes(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    for row in range(3):
        y = by0 + 30 + row * (by1 - by0) * 0.20
        d.rectangle([bx0 + 12, y, bx1 - 12, y + 7], fill=(110, 100, 88))
        x = bx0 + 18
        while x < bx1 - 34:
            d.ellipse([x, y - 16, x + 34, y], fill=(60 + rng.randint(0, 90), 58, 62))
            x += 40


def _records(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    for i in range(4):
        x = bx0 + 14 + i * (w - 40) / 4
        d.rectangle([x, by1 - 60, x + 44, by1], fill=wood_colour())
        for j in range(4):
            d.rectangle([x + 6, by1 - 56 + j * 12, x + 38, by1 - 50 + j * 12],
                        fill=(40 + rng.randint(0, 120), 40, 40 + rng.randint(0, 120)))


def _tools(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    d.rectangle([bx0 + 12, by0 + 20, bx1 - 12, by0 + 90], fill=(96, 100, 104))
    for i in range(9):
        x = bx0 + 22 + i * (w - 60) / 9
        d.rectangle([x, by0 + 30, x + 6, by0 + 78], fill=(160, 164, 168))


DRAWERS = [
    ("noodle", lambda d, b, r: (_counter(d, b, r), _bowls(d, b, r), _stools(d, b, r),
                                 _menu(d, b, r))),
    ("pharmacy", lambda d, b, r: (_shelves(d, b, r, (200, 200, 206), 5, (232, 236, 240)),
                                  _counter(d, b, r, (226, 228, 230), (190, 194, 200)))),
    ("convenience", lambda d, b, r: (_fridges(d, b, r), _counter(d, b, r))),
    ("clothes", lambda d, b, r: (_rail(d, b, r), _mirror(d, b, r))),
    ("salon", lambda d, b, r: (_mirror(d, b, r), _chairs(d, b, r))),
    ("phones", lambda d, b, r: (_glass_case(d, b, r), _shelves(d, b, r, (60, 70, 90), 3))),
    ("jewellery", lambda d, b, r: (_glass_case(d, b, r), _shelves(d, b, r, (190, 160, 90), 3))),
    ("bakery", lambda d, b, r: (_bread(d, b, r), _counter(d, b, r, (214, 206, 190)))),
    ("tea", lambda d, b, r: (_jars(d, b, r), _counter(d, b, r, (120, 90, 62), (88, 66, 46)))),
    ("shoes", lambda d, b, r: (_shoes(d, b, r), _counter(d, b, r))),
    ("fruit", lambda d, b, r: (_crates(d, b, r), _counter(d, b, r, (176, 166, 148)))),
    ("repair", lambda d, b, r: (_tools(d, b, r), _counter(d, b, r, (110, 112, 116), (70, 72, 76)))),
    ("hardware", lambda d, b, r: (_shelves(d, b, r, (110, 120, 130), 5), _boxes(d, b, r))),
    ("tailor", lambda d, b, r: (_mannequin(d, b, r), _shelves(d, b, r, (140, 120, 150), 3))),
    ("records", lambda d, b, r: (_records(d, b, r), _counter(d, b, r, (110, 96, 78)))),
    ("empty", lambda d, b, r: (_boxes(d, b, r),)),
]


def build():
    """The shop interior atlas image and the manifest of its cells."""
    img = Image.new("RGB", (SHEET, SHEET), (0, 0, 0))
    entries = []
    for i, (name, drawer) in enumerate(DRAWERS):
        cx = (i % COLS) * CELL
        cy = (i // COLS) * CELL
        cell = Image.new("RGB", (CELL, CELL), (0, 0, 0))
        rng = random.Random(500 + i * 53)
        walls = SHOP_WALL[i % len(SHOP_WALL)]
        light = WARM if i % 2 == 0 else NEUTRAL
        d, box = _room(cell, walls[0], walls[1], walls[2], light, rng)
        # the lamp type and the position change with every cell
        lamp = LAMPS[(i * 5) % len(LAMPS)]
        lamp_xy = lamp(cell, box, light, rng)
        drawer(d, box, rng)
        cell = _tint(cell, light)
        # the light falls off from the lamp and the corners are in shadow
        cell = _shade_room(cell, lamp_xy, light)
        cell = cell.filter(ImageFilter.GaussianBlur(0.9))
        img.paste(cell, (cx, cy))
        u0, v0, u1, v1 = slot(SHEET, SHEET, cx, cy, CELL, CELL)
        entries.append({"id": "shop_%s" % name, "atlas": "shop_interiors", "u0": u0,
                        "v0": v0, "u1": u1, "v1": v1, "shop": name})
    return img, entries
