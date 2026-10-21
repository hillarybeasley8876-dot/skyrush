"""Foliage atlas for the props unit: one 2048 px image with four plant types.

Quadrants: plane-tree leaves, bougainvillea, golden privet, rose.  The leaves
are drawn as real shapes (5-lobed plane leaves with veins and value variation)
so the canopy cards read as foliage at 10 m instead of flat clip art.

The atlas is drawn at 2x and downsampled, so the alpha edge of every leaf and
bract is 2-4 px soft instead of a stair step (the review of the deck planters).

One quadrant covers 1.6 m of real plant, so a leaf keeps its real size when a
cluster card shows the whole quadrant.
"""
import math
import os
import random

from PIL import Image, ImageDraw

import imwrite as IW
from surfaces import TEX_DIR

ATLAS = 1024
QUAD = 512
ATLAS2 = ATLAS * 2              # the render size (2x, downsampled at the end)
QUAD2 = QUAD * 2
# One quadrant covers this many metres of real plant.
QUAD_METRES = 1.6
PX_PER_M = QUAD2 / QUAD_METRES

LEAF_YELLOW = (0xB7, 0xA8, 0x4A)
LEAF_GREEN = (0x3E, 0x7D, 0x32)
LEAF_PRIVET = (0xB5, 0xC5, 0x34)
LEAF_DEEP = (0x2C, 0x5C, 0x28)
BRACT = (0xC2, 0x18, 0x5B)
BRACT_LIGHT = (0xE0, 0x3A, 0x7E)

# Quadrant rects (x0, y0, x1, y1) in atlas pixels.
QUADS = {
    "plane": (0, 0, QUAD, QUAD),
    "bougainvillea": (QUAD, 0, 2 * QUAD, QUAD),
    "privet": (0, QUAD, QUAD, 2 * QUAD),
    "rose": (QUAD, QUAD, 2 * QUAD, 2 * QUAD),
}


def _plane_leaf(d, cx, cy, length, colour, angle, lobes=5):
    """A five-lobed London-plane leaf with a toothed edge and radiating veins."""
    ca, sa = math.cos(angle), math.sin(angle)
    pts = []
    steps = 60
    for i in range(steps):
        t = i / float(steps)
        r = length * (0.12 + 0.88 * math.sin(math.pi * t) ** 0.55)
        # five lobes: the radius ripples with the lobe count
        ripple = 0.80 + 0.20 * abs(math.cos(lobes * math.pi * t))
        a = -math.pi * 0.5 + t * math.pi
        x = math.cos(a) * r * ripple
        y = math.sin(a) * r * 0.62
        pts.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    d.polygon(pts, fill=colour)
    for k in range(1, lobes + 1):
        a = -math.pi * 0.5 + math.pi * k / (lobes + 1.0)
        ln = length * 0.82
        x, y = math.cos(a) * ln, math.sin(a) * ln * 0.62
        d.line([(cx, cy), (cx + x * ca - y * sa, cy + x * sa + y * ca)],
               fill=tuple(max(0, c - 26) for c in colour), width=3)


def _bract(d, cx, cy, r, colour):
    """A bougainvillea bract: a rounded triangle with a veined centre."""
    d.polygon([(cx, cy - r), (cx + r * 0.72, cy + r * 0.55),
               (cx - r * 0.72, cy + r * 0.55)], fill=colour)
    d.line([(cx, cy - r * 0.8), (cx, cy + r * 0.45)],
           fill=tuple(max(0, c - 30) for c in colour), width=2)


def _elliptic_leaf(d, cx, cy, length, width, colour, angle):
    ca, sa = math.cos(angle), math.sin(angle)
    pts = []
    for i in range(24):
        t = i / 23.0
        r = math.sin(math.pi * t) ** 0.7
        x, y = (t - 0.5) * length, 0.0
        px = cx + x * ca - 0.0 * sa
        py = cy + x * sa
        pts.append((px, py - r * width * 0.5))
    for i in range(23, -1, -1):
        t = i / 23.0
        r = math.sin(math.pi * t) ** 0.7
        x = (t - 0.5) * length
        px = cx + x * ca
        py = cy + x * sa
        pts.append((px, py + r * width * 0.5))
    d.polygon(pts, fill=colour)


def _plane_quadrant(rng):
    """Five-lobed leaves, October yellow-green mixed with green."""
    qd = Image.new("RGBA", (QUAD2, QUAD2), (0, 0, 0, 0))
    dd = ImageDraw.Draw(qd)
    # the October mix of the dossier: 70 % #6A7A2E olive and 30 % #9C8A3A ochre
    palette = [(0x6A, 0x7A, 0x2E)] * 5 + [(0x62, 0x71, 0x2A), (0x74, 0x84, 0x34),
                                          (0x5C, 0x6B, 0x27)] + \
              [(0x9C, 0x8A, 0x3A)] * 2 + [(0x8E, 0x7C, 0x33), (0xA8, 0x95, 0x42)]
    for _ in range(1500):
        cx = rng.uniform(0, QUAD2)
        cy = rng.uniform(0, QUAD2)
        _plane_leaf(dd, cx, cy, rng.uniform(55, 95),
                    palette[rng.randrange(len(palette))], rng.uniform(0, math.tau))
    return qd


def _bougainvillea_quadrant(rng):
    """Green leaves with a dense mass of small magenta bracts (3-5 cm each)."""
    qd = Image.new("RGBA", (QUAD2, QUAD2), (0, 0, 0, 0))
    dd = ImageDraw.Draw(qd)
    for _ in range(900):
        cx = rng.uniform(0, QUAD2)
        cy = rng.uniform(0, QUAD2)
        _elliptic_leaf(dd, cx, cy, rng.uniform(45, 80), rng.uniform(26, 44),
                       LEAF_GREEN if rng.random() < 0.6 else LEAF_DEEP,
                       rng.uniform(0, math.tau))
    for _ in range(2400):
        cx = rng.uniform(0, QUAD2)
        cy = rng.uniform(0, QUAD2)
        _bract(dd, cx, cy, rng.uniform(17, 27), BRACT if rng.random() < 0.7 else BRACT_LIGHT)
    return qd


def _privet_quadrant(rng):
    """Dense small leaves of golden privet."""
    qd = Image.new("RGBA", (QUAD2, QUAD2), (0, 0, 0, 0))
    dd = ImageDraw.Draw(qd)
    shades = [LEAF_PRIVET, (0x9B, 0xAD, 0x2B), (0xC8, 0xD4, 0x54), (0x6F, 0x86, 0x2A)]
    for _ in range(2600):
        cx = rng.uniform(0, QUAD2)
        cy = rng.uniform(0, QUAD2)
        _elliptic_leaf(dd, cx, cy, rng.uniform(26, 46), rng.uniform(13, 21),
                       shades[rng.randrange(len(shades))], rng.uniform(0, math.tau))
    return qd


def _rose_quadrant(rng):
    """Small leaves with double pink heads."""
    qd = Image.new("RGBA", (QUAD2, QUAD2), (0, 0, 0, 0))
    dd = ImageDraw.Draw(qd)
    for _ in range(700):
        cx = rng.uniform(0, QUAD2)
        cy = rng.uniform(0, QUAD2)
        _elliptic_leaf(dd, cx, cy, rng.uniform(34, 56), rng.uniform(18, 28),
                       LEAF_GREEN if rng.random() < 0.6 else LEAF_DEEP,
                       rng.uniform(0, math.tau))
    for _ in range(190):
        cx = rng.uniform(0, QUAD2)
        cy = rng.uniform(0, QUAD2)
        r = rng.uniform(16, 28)
        dd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(0xF0, 0x6C, 0xA8))
        dd.ellipse([cx - r * 0.55, cy - r * 0.55, cx + r * 0.55, cy + r * 0.55],
                   fill=(0xFF, 0x9C, 0xC4))
    return qd


def build(out_dir=None):
    """Draw the four quadrants and write the atlas.

    The atlas goes to `out_dir` (a scratch folder by default): the .glb files
    reference the copy the Blender exporter writes into the game folder.
    """
    out_dir = out_dir or TEX_DIR
    big = Image.new("RGBA", (ATLAS2, ATLAS2), (0, 0, 0, 0))
    rng = random.Random(20261020)
    for name, maker in (("plane", _plane_quadrant), ("bougainvillea", _bougainvillea_quadrant),
                        ("privet", _privet_quadrant), ("rose", _rose_quadrant)):
        q = QUADS[name]
        qd = maker(rng)
        big.paste(qd, (q[0] * 2, q[1] * 2))
    img = big.resize((ATLAS, ATLAS), Image.LANCZOS)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "prop_foliage.png")
    IW.save(img, path, format="PNG")
    return path


if __name__ == "__main__":
    print("FOLIAGE %s" % build())
