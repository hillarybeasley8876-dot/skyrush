"""The home / office interior atlas: what a lit window actually shows.

A 2048 sheet with 8 x 8 = 64 cells of 256 px.  A cell covers ONE metre of window at
256 px/m, so a shikumen window (1.0 m) shows a whole room and the pixels are dense
enough to read at 5 m.  Each cell is drawn as a room in one-point perspective -
ceiling, two side walls, a back wall, a floor - with a lamp, the falloff of its
light, the corner occlusion and the furniture of that kind of room.  There are six
lamp types and no two cells share a lamp or a ceiling.  The colours are the
dossier's: warm #FFA757, neutral #FFC18D, cool #DEE8FF and the TV blue #9DB4FF.
"""
import random

from PIL import Image, ImageDraw, ImageFilter

from .atlas import slot

SHEET = 2048
COLS = 8
ROWS = 8
CELL_W = SHEET // COLS      # 256
CELL_H = SHEET // ROWS      # 256

WARM = (255, 167, 87)
NEUTRAL = (255, 193, 141)
COOL = (222, 232, 255)
TV = (157, 180, 255)

ROOM_WALLS = [
    ("#C8B49A", "#8A6E52", "#E8DCC8"),   # warm plaster
    ("#B9BFC6", "#6E767E", "#DDE3E8"),   # cool office
    ("#D6CBB6", "#8E8270", "#F0E8D6"),   # cream flat
    ("#A8AEB4", "#5E666C", "#C8CFD4"),   # grey concrete
]


def _shade(hex_colour, f):
    """Scale a hex colour by a factor."""
    h = hex_colour.lstrip("#")
    c = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    return tuple(max(0, min(255, int(v * f))) for v in c)


def _room(cell, wall_hex, floor_hex, ceil_hex, light_col, rng):
    """Draw a room in one-point perspective; returns the drawing context."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    bx0, bx1 = int(w * 0.22), int(w * 0.78)
    by0, by1 = int(h * 0.22), int(h * 0.76)
    d.rectangle([0, 0, w - 1, h - 1], fill=ceil_hex)
    d.polygon([(0, 0), (w, 0), (bx1, by0), (bx0, by0)], fill=_shade(ceil_hex, 0.82))
    d.polygon([(0, 0), (bx0, by0), (bx0, by1), (0, h)], fill=_shade(wall_hex, 0.68))
    d.polygon([(w, 0), (bx1, by0), (bx1, by1), (w, h)], fill=_shade(wall_hex, 0.52))
    d.rectangle([bx0, by0, bx1, by1], fill=wall_hex)
    d.polygon([(0, h), (w, h), (bx1, by1), (bx0, by1)], fill=floor_hex)
    # the corner lines
    for a, b in (((0, 0), (bx0, by0)), ((w, 0), (bx1, by0)), ((0, h), (bx0, by1)),
                 ((w, h), (bx1, by1))):
        d.line([a, b], fill=_shade(wall_hex, 0.55), width=2)
    d.rectangle([bx0, by0, bx1, by1], outline=_shade(wall_hex, 0.5), width=2)
    return d, (bx0, by0, bx1, by1)


def _glow(cell, cx, cy, r, colour):
    """The halo of a lamp: a soft radial falloff, not a painted disc."""
    import numpy as np
    w, h = cell.size
    arr = np.asarray(cell).astype(np.float32)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    dist = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) / float(max(r, 1))
    a = np.clip(1.0 - dist, 0.0, 1.0) ** 2.4
    col = np.array(colour, dtype=np.float32)
    out = arr * (1.0 - a[..., None] * 0.7) + col[None, None, :] * a[..., None] * 0.85
    core = np.clip(1.0 - dist * 2.4, 0.0, 1.0) ** 2
    out = out * (1.0 - core[..., None] * 0.5) + 255.0 * core[..., None]
    cell.paste(Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)))


def _lamp_pendant(cell, box, colour, rng):
    d = ImageDraw.Draw(cell)
    """A pendant lamp on a cord."""
    bx0, by0, bx1, by1 = box
    cx = (bx0 + bx1) * 0.5 + rng.uniform(-24, 24)
    cy = by0 + 40
    d.line([(cx, by0 - 2), (cx, cy - 12)], fill=(70, 70, 74), width=3)
    d.polygon([(cx - 26, cy + 6), (cx + 26, cy + 6), (cx + 14, cy - 12),
               (cx - 14, cy - 12)], fill=(226, 220, 206))
    _glow(cell, cx, cy + 10, 15, colour)
    d.ellipse([cx - 15, cy + 2, cx + 15, cy + 16], fill=(255, 250, 240))
    return cx, cy + 8


def _lamp_tube(cell, box, colour, rng):
    d = ImageDraw.Draw(cell)
    """A fluorescent tube in a ceiling fitting."""
    bx0, by0, bx1, by1 = box
    cx = (bx0 + bx1) * 0.5
    cy = by0 + 12
    d.rectangle([cx - 60, cy - 8, cx + 60, cy + 8], fill=(226, 226, 222))
    d.rectangle([cx - 58, cy - 2, cx + 58, cy + 6], fill=(255, 252, 244))
    _glow(cell, cx, cy, 20, colour)
    return cx, cy


def _lamp_bulb(cell, box, colour, rng):
    d = ImageDraw.Draw(cell)
    """A bare bulb on a flex."""
    bx0, by0, bx1, by1 = box
    cx = bx0 + (bx1 - bx0) * rng.uniform(0.3, 0.7)
    cy = by0 + 30
    d.line([(cx, by0 - 2), (cx, cy - 10)], fill=(60, 60, 64), width=2)
    _glow(cell, cx, cy, 13, colour)
    d.ellipse([cx - 12, cy - 12, cx + 12, cy + 12], fill=(255, 250, 236))
    return cx, cy


def _lamp_chandelier(cell, box, colour, rng):
    d = ImageDraw.Draw(cell)
    """A three-arm chandelier over a dining table."""
    bx0, by0, bx1, by1 = box
    cx = (bx0 + bx1) * 0.5
    cy = by0 + 44
    d.line([(cx, by0 - 2), (cx, cy - 18)], fill=(96, 84, 60), width=3)
    d.line([(cx - 44, cy), (cx + 44, cy)], fill=(120, 104, 70), width=4)
    for dx in (-44, 0, 44):
        d.polygon([(cx + dx - 9, cy - 8), (cx + dx + 9, cy - 8), (cx + dx + 5, cy - 20),
                   (cx + dx - 5, cy - 20)], fill=(238, 226, 196))
        d.ellipse([cx + dx - 7, cy - 8, cx + dx + 7, cy + 6], fill=(255, 248, 228))
    _glow(cell, cx, cy, 22, colour)
    return cx, cy


def _lamp_floor(cell, box, colour, rng):
    d = ImageDraw.Draw(cell)
    """A floor lamp in the corner of the room."""
    bx0, by0, bx1, by1 = box
    side = -1 if rng.random() < 0.5 else 1
    cx = (bx0 + bx1) * 0.5 + side * (bx1 - bx0) * 0.34
    cy = by1 - (by1 - by0) * 0.45
    d.line([(cx, by1 - 6), (cx, cy - 20)], fill=(70, 70, 74), width=4)
    d.ellipse([cx - 18, by1 - 16, cx + 18, by1 - 2], fill=(60, 60, 64))
    d.polygon([(cx - 24, cy - 6), (cx + 24, cy - 6), (cx + 15, cy - 26),
               (cx - 15, cy - 26)], fill=(236, 226, 202))
    _glow(cell, cx, cy - 10, 16, colour)
    d.ellipse([cx - 16, cy - 16, cx + 16, cy + 4], fill=(255, 250, 236))
    return cx, cy - 8


def _lamp_desk(cell, box, colour, rng):
    d = ImageDraw.Draw(cell)
    """A desk lamp: a small pool of light on the table."""
    bx0, by0, bx1, by1 = box
    cx = bx0 + (bx1 - bx0) * rng.uniform(0.25, 0.75)
    cy = by1 - (by1 - by0) * 0.30
    d.rectangle([cx - 14, cy, cx + 14, cy + 4], fill=(48, 48, 52))
    d.line([(cx, cy), (cx + 10, cy - 22)], fill=(64, 64, 68), width=3)
    d.polygon([(cx + 2, cy - 34), (cx + 26, cy - 22), (cx + 14, cy - 12),
               (cx - 2, cy - 22)], fill=(226, 216, 190))
    _glow(cell, cx + 12, cy - 18, 12, colour)
    d.ellipse([cx + 4, cy - 28, cx + 20, cy - 12], fill=(255, 250, 238))
    return cx + 12, cy - 18


LAMPS = [_lamp_pendant, _lamp_tube, _lamp_bulb, _lamp_chandelier, _lamp_floor, _lamp_desk]


def _sofa(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    x = bx0 + w * 0.10
    y = by1 - (by1 - by0) * 0.42
    d.rectangle([x + 4, by1 - 10, x + w * 0.46 + 10, by1 + 4], fill=(70, 62, 56))
    d.rectangle([x, y, x + w * 0.46, by1 - 4], fill=(96, 84, 74))
    d.rectangle([x, y, x + w * 0.46, y + 14], fill=(126, 112, 98))
    d.rectangle([x + 6, y + 18, x + w * 0.20, by1 - 14], fill=(112, 98, 86))
    d.rectangle([x + w * 0.24, y + 18, x + w * 0.40, by1 - 14], fill=(86, 76, 68))
    d.rectangle([x + 8, y + 20, x + w * 0.18, y + 26], fill=(146, 130, 114))


def _bed(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    x = bx0 + w * 0.12
    y = by1 - (by1 - by0) * 0.55
    d.rectangle([x + 4, by1 - 10, x + w * 0.52 + 8, by1 + 4], fill=(128, 122, 114))
    d.rectangle([x, y, x + w * 0.52, by1], fill=(210, 206, 196))
    d.rectangle([x, y, x + w * 0.52, y + 22], fill=(238, 234, 226))
    d.rectangle([x, y + 22, x + w * 0.52, y + 28], fill=(184, 180, 172))
    d.rectangle([x + 6, y - 16, x + w * 0.20, y + 4], fill=(240, 238, 230))
    d.rectangle([x, by1 - 16, x + w * 0.52, by1], fill=(150, 146, 138))


def _counter(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    x = bx0 + w * 0.05
    y = by1 - (by1 - by0) * 0.40
    d.rectangle([x + 4, by1 - 10, x + w * 0.60 + 8, by1 + 4], fill=(116, 110, 100))
    d.rectangle([x, y, x + w * 0.60, by1], fill=(176, 168, 152))
    d.rectangle([x, y, x + w * 0.60, y + 12], fill=(214, 208, 192))
    d.rectangle([x, y + 12, x + w * 0.60, y + 17], fill=(150, 143, 130))
    for i in range(3):
        d.rectangle([x + 8, y + 20 + i * 22, x + w * 0.54, y + 34 + i * 22],
                    fill=(120, 114, 104))


def _shelves(d, box, rng, colour=(150, 96, 70)):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    for row in range(4):
        y = by0 + 10 + row * (by1 - by0) * 0.16
        d.rectangle([bx0 + 8, y, bx1 - 8, y + 6], fill=(120, 108, 92))
        x = bx0 + 14
        while x < bx1 - 20:
            bw = rng.randint(8, 18)
            hgt = rng.randint(14, 30)
            c = (colour[0] + rng.randint(-30, 30), colour[1] + rng.randint(-30, 30),
                 colour[2] + rng.randint(-30, 30))
            d.rectangle([x, y - hgt, x + bw, y], fill=tuple(max(0, min(255, v)) for v in c))
            x += bw + 3


def _tv(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    x = bx0 + w * 0.56
    y = by0 + (by1 - by0) * 0.18
    d.rectangle([x, y, x + w * 0.30, y + (by1 - by0) * 0.26], fill=(24, 26, 32))
    d.rectangle([x + 4, y + 4, x + w * 0.30 - 4, y + (by1 - by0) * 0.26 - 4], fill=TV)


def _stairs(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    for i in range(7):
        y = by1 - i * ((by1 - by0) * 0.12)
        d.rectangle([bx0 + 6, y, bx1 - 6 - i * 6, y + 10], fill=(178, 172, 162))
    d.polygon([(bx0 + 6, by1), (bx1 - 6, by1), (bx1 - 48, by0 + 10), (bx0 + 48, by0 + 10)],
              fill=(96, 96, 98))


def _desk(d, box, rng):
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    x = bx0 + w * 0.14
    y = by1 - (by1 - by0) * 0.34
    d.rectangle([x, y, x + w * 0.50, y + 10], fill=(158, 124, 90))
    d.rectangle([x, y + 10, x + w * 0.50, by1], fill=(92, 74, 56))
    d.rectangle([x, y + 10, x + w * 0.50, y + 14], fill=(120, 98, 72))
    d.rectangle([x + w * 0.14, y - 34, x + w * 0.40, y], fill=(30, 32, 38))
    d.rectangle([x + w * 0.16, y - 31, x + w * 0.38, y - 3], fill=COOL)


def _window(d, box, rng, light_col):
    """A window on the back wall: the light source of a dark flat."""
    bx0, by0, bx1, by1 = box
    w = bx1 - bx0
    d.rectangle([bx0 + w * 0.08, by0 + 18, bx0 + w * 0.34, by0 + 90],
                fill=_shade("#%02X%02X%02X" % light_col, 0.9))
    d.rectangle([bx0 + w * 0.08, by0 + 18, bx0 + w * 0.34, by0 + 90],
                outline=(40, 40, 44), width=3)


FURNITURE = [_sofa, _bed, _counter, _shelves, _tv, _stairs, _desk]

# the ceiling of every cell: no two neighbours share one
CEILINGS = ["#E8DCC8", "#DDE3E8", "#F0E8D6", "#C8CFD4", "#E4DED2", "#D2D6D8"]


def _tint(cell, light):
    """Pull the room towards its lamp colour: a lit interior is warm, not grey."""
    import numpy as np
    arr = np.asarray(cell).astype(np.float32)
    tint = np.array(light, dtype=np.float32) / 255.0
    arr = arr * 0.78 + arr * tint[None, None, :] * 0.9
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def _plaster(cell, seed):
    """The plaster grain of the walls: a fine noise over the whole cell."""
    import numpy as np
    rng = np.random.default_rng(seed)
    w, h = cell.size
    n = rng.normal(0.0, 1.0, (h, w)).astype(np.float32)
    # a cheap blur so the grain is not white noise
    k = np.array([0.25, 0.5, 0.25], dtype=np.float32)
    for axis in (0, 1):
        n = np.apply_along_axis(lambda m: np.convolve(m, k, mode="same"), axis, n)
    arr = np.asarray(cell).astype(np.float32)
    arr *= (1.0 + n[..., None] * 0.055)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def _shade_room(cell, lamp_xy, light):
    """The falloff of the lamp light and the occlusion of the corners.

    A room lit evenly reads as a flat picture; the light has to fall off from the
    lamp and the corners have to be darker than the walls.
    """
    import numpy as np
    w, h = cell.size
    arr = np.asarray(cell).astype(np.float32) / 255.0
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    lx, ly = lamp_xy
    d = np.sqrt((xs - lx) ** 2 + (ys - ly) ** 2) / float(max(w, h))
    # the light falls off with the square of the distance
    fall = np.clip(1.05 - 0.80 * d, 0.40, 1.02)
    # the corners of the room are in shadow
    vx = np.minimum(xs, w - 1 - xs) / (w * 0.5)
    vy = np.minimum(ys, h - 1 - ys) / (h * 0.5)
    corner = np.clip(np.minimum(vx, vy) * 1.5, 0.0, 1.0)
    ao = 0.62 + 0.38 * corner
    tint = np.array(light, dtype=np.float32) / 255.0
    out = arr * (fall * ao)[..., None]
    # the light itself is warmer than the room
    out *= (1.0 + 0.25 * (fall - 0.6).clip(0, 1)[..., None] * tint[None, None, :])
    return Image.fromarray(np.clip(out * 255.0, 0, 255).astype(np.uint8))


def build():
    """The home / office atlas image and the manifest of its cells."""
    img = Image.new("RGB", (SHEET, SHEET), (0, 0, 0))
    entries = []
    for i in range(COLS * ROWS):
        cx = (i % COLS) * CELL_W
        cy = (i // COLS) * CELL_H
        cell = Image.new("RGB", (CELL_W, CELL_H), (0, 0, 0))
        rng = random.Random(1000 + i * 37)
        # the lamp and the ceiling change with every cell, and never with the
        # neighbour: 5 and 6 are coprime, so the sequence walks through all of them
        walls = ROOM_WALLS[i % len(ROOM_WALLS)]
        warm = i % 3 == 0
        light = WARM if warm else (NEUTRAL if i % 3 == 1 else COOL)
        ceil_hex = CEILINGS[(i * 5) % len(CEILINGS)]
        d, box = _room(cell, walls[0], walls[1], ceil_hex, light, rng)
        # no two cells share a lamp: the type and the position both vary
        lamp = LAMPS[(i * 5) % len(LAMPS)]
        lamp_xy = lamp(cell, box, light, rng)
        furn = FURNITURE[i % len(FURNITURE)]
        furn(d, box, rng)
        if i % 4 == 1:
            _window(d, box, rng, light)
        if i % 7 == 3:
            _tv(d, box, rng)
        cell = _tint(cell, light)
        cell = _shade_room(cell, lamp_xy, light)
        cell = _plaster(cell, 900 + i * 13)
        cell = cell.filter(ImageFilter.GaussianBlur(0.8))
        img.paste(cell, (cx, cy))
        u0, v0, u1, v1 = slot(SHEET, SHEET, cx, cy, CELL_W, CELL_H)
        entries.append({"id": "room_%02d" % i, "atlas": "interiors", "u0": u0, "v0": v0,
                        "u1": u1, "v1": v1, "light": "#%02X%02X%02X" % light,
                        "lamp": lamp.__name__})
    return img, entries
