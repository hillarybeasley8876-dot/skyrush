"""The cloth atlas: the garments that hang on the laundry poles.

A 512 sheet with 4 x 2 = 8 cells of 128 x 256 px.  Every cell is one garment seen
flat: a shirt, a sheet, a towel, trousers, a jacket, a bedsheet, a dress, a shirt.
The cells are used with explicit UVs so the laundry never reads as two red rectangles.
"""
import random

from PIL import Image, ImageDraw, ImageFilter

from .atlas import slot

SHEET = 512
COLS = 4
ROWS = 2
CELL_W = SHEET // COLS      # 128
CELL_H = SHEET // ROWS      # 256

PALETTE = [(198, 64, 58), (232, 226, 214), (72, 104, 168), (236, 168, 60),
           (96, 150, 108), (128, 86, 156), (236, 236, 236), (70, 74, 82)]


def _shirt(d, w, h, colour, rng):
    d.rectangle([0, 0, w - 1, h - 1], fill=colour)
    d.polygon([(w * 0.30, 0), (w * 0.70, 0), (w * 0.86, h * 0.16), (w * 0.14, h * 0.16)],
              fill=colour)
    d.ellipse([w * 0.38, h * 0.02, w * 0.62, h * 0.10], fill=(232, 228, 220))
    for i in range(3):
        y = h * (0.40 + i * 0.16)
        d.line([w * 0.20, y, w * 0.80, y], fill=tuple(max(0, c - 30) for c in colour),
               width=2)


def _sheet(d, w, h, colour, rng):
    d.rectangle([0, 0, w - 1, h - 1], fill=colour)
    for i in range(6):
        y = h * i / 6.0
        d.line([0, y, w, y], fill=tuple(max(0, c - 18) for c in colour), width=3)
    d.rectangle([0, 0, w - 1, 10], fill=tuple(max(0, c - 40) for c in colour))


def _towel(d, w, h, colour, rng):
    d.rectangle([0, 0, w - 1, h - 1], fill=colour)
    for i in range(0, w, 6):
        d.line([i, 0, i, h], fill=tuple(max(0, c - 24) for c in colour), width=2)
    d.rectangle([0, h - 30, w - 1, h - 1], fill=tuple(max(0, c - 40) for c in colour))


def _trousers(d, w, h, colour, rng):
    d.rectangle([w * 0.18, 0, w * 0.82, h * 0.44], fill=colour)
    d.rectangle([w * 0.18, h * 0.44, w * 0.48, h], fill=colour)
    d.rectangle([w * 0.52, h * 0.44, w * 0.82, h], fill=colour)
    d.rectangle([w * 0.18, 0, w * 0.82, h * 0.08],
                fill=tuple(max(0, c - 34) for c in colour))


def _jacket(d, w, h, colour, rng):
    d.rectangle([w * 0.16, 0, w * 0.84, h * 0.86], fill=colour)
    d.polygon([(w * 0.16, 0), (w * 0.40, 0), (w * 0.50, h * 0.30), (w * 0.60, 0),
               (w * 0.84, 0), (w * 0.84, h * 0.20), (w * 0.62, h * 0.30),
               (w * 0.56, h * 0.86), (w * 0.44, h * 0.86), (w * 0.38, h * 0.30),
               (w * 0.16, h * 0.20)], fill=colour)
    d.line([w * 0.50, h * 0.24, w * 0.50, h * 0.84],
           fill=tuple(max(0, c - 40) for c in colour), width=3)


def _dress(d, w, h, colour, rng):
    d.polygon([(w * 0.34, 0), (w * 0.66, 0), (w * 0.92, h), (w * 0.08, h)], fill=colour)
    d.rectangle([w * 0.34, 0, w * 0.66, h * 0.10],
                fill=tuple(max(0, c - 30) for c in colour))


DRAWERS = [_shirt, _sheet, _towel, _trousers, _shirt, _sheet, _dress, _jacket]
NAMES = ["shirt", "sheet", "towel", "trousers", "shirt2", "bedsheet", "dress", "jacket"]


def build():
    """The cloth atlas image and the manifest of its cells."""
    img = Image.new("RGB", (SHEET, SHEET), (0, 0, 0))
    entries = []
    for i, drawer in enumerate(DRAWERS):
        cx = (i % COLS) * CELL_W
        cy = (i // COLS) * CELL_H
        cell = Image.new("RGB", (CELL_W, CELL_H), PALETTE[i % len(PALETTE)])
        rng = random.Random(900 + i * 29)
        d = ImageDraw.Draw(cell)
        drawer(d, CELL_W, CELL_H, PALETTE[i % len(PALETTE)], rng)
        cell = cell.filter(ImageFilter.GaussianBlur(0.8))
        img.paste(cell, (cx, cy))
        u0, v0, u1, v1 = slot(SHEET, SHEET, cx, cy, CELL_W, CELL_H)
        entries.append({"id": "cloth_%s" % NAMES[i], "atlas": "cloth", "u0": u0, "v0": v0,
                        "u1": u1, "v1": v1})
    return img, entries
