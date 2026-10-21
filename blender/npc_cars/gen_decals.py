"""Decal, livery and sign textures for the NPC fleet (PIL + numpy).

    python3 blender/npc_cars/gen_textures.py

Runs as part of gen_textures.py; kept separate so both stay under 400 lines.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas  # noqa: E402
import texlib  # noqa: E402
from texlib import draw_centered, fit_font, font, noise_overlay  # noqa: E402


# ------------------------------------------------------------------- decals

PLATE_TEXT = {
    "sedan_ev": ("nev", "沪A·D71345"),
    "suv_ev": ("nev", "沪A·D52806"),
    "hatch_ev": ("nev", "沪A·D2M664"),
    "taxi": ("nev", "沪A·D3X882"),
    "robotaxi": ("nev", "沪A·D0R421"),
    "police_patrol": ("nev", "沪A·D00007"),
    "police_interceptor": ("nev", "沪A·D00111"),
    "police_suv": ("nev", "沪A·D00033"),
    "van": ("blue", "沪B·44127"),
    "truck": ("blue", "沪B·90834"),
    "bus": ("large", "沪A·12345D"),
    "police_drone": ("blue", "沪A·77019"),
}


def plate_image(kind, text, size=(512, 160)):
    """Shanghai plate: blue (fuel), green gradient (EV), yellow-green (large EV)."""
    w, h = size
    img = Image.new("RGB", size, (30, 62, 128))
    d = ImageDraw.Draw(img)
    if kind == "nev":
        top, bottom = (86, 196, 140), (16, 112, 70)
        ink = (14, 18, 16)
    elif kind == "large":
        top, bottom = (226, 190, 40), (16, 112, 70)
        ink = (14, 18, 16)
    else:
        top, bottom = (48, 92, 190), (20, 52, 126)
        ink = (244, 246, 250)
    for y in range(h):
        t = y / float(h - 1)
        d.line([(0, y), (w, y)], fill=(int(top[0] + (bottom[0] - top[0]) * t),
                                        int(top[1] + (bottom[1] - top[1]) * t),
                                        int(top[2] + (bottom[2] - top[2]) * t)))
    d.rectangle([0, 0, w - 1, h - 1], outline=(236, 240, 244), width=5)
    f = fit_font(text, 104, w * 0.86, h * 0.62)
    draw_centered(d, (0, 0, w, h), text, f, ink)
    for cx, cy in ((26, 26), (w - 26, 26), (26, h - 26), (w - 26, h - 26)):
        d.ellipse([cx - 6, cy - 6, cx + 6, cy + 6], fill=(200, 204, 208))
    return noise_overlay(img, 12, 91)


def plates_atlas():
    """One atlas with every vehicle's plate (4 columns x 6 rows)."""
    import spec as specs
    cols, rows = 4, 3
    w, h = 512, 160
    sheet = Image.new("RGB", (cols * w, rows * h), (12, 12, 14))
    for i, name in enumerate(specs.PLATE_ORDER):
        kind, text = PLATE_TEXT[name]
        sheet.paste(plate_image(kind, text, (w, h)), ((i % cols) * w, (i // cols) * h))
    return sheet


def police_livery(name, door_y, rear_y, length, size=(2048, 1024)):
    """Police livery sheet (RGBA, transparent where the body paint shows).

    The sheet spans `length` metres along the car and 2 m in height; u = 0.5 is
    the front door, so the door text lands on the front door of both flanks.
    """
    w, h = size
    img = Image.new("RGBA", size, (242, 244, 245, 0))
    d = ImageDraw.Draw(img)

    def row(z):
        return int((1.0 - z / 2.0) * h)

    span = length + 0.1

    def col(y):
        return int((y - door_y + span * 0.5) / span * w)

    band_top, band_bot = row(0.85), row(0.40)
    d.rectangle([0, band_top, w, band_bot], fill=(27, 42, 78, 255))
    d.rectangle([0, row(0.90), w, row(0.865)], fill=(245, 196, 0, 255))
    img.alpha_composite(_road_grime(w, band_bot - band_top), (0, band_top))
    f = fit_font("天巡 SKYPOL", 96, 330, 80)
    draw_centered(d, (col(door_y) - 300, row(0.78), col(door_y) + 300, row(0.55)),
                  "天巡 SKYPOL", f, (242, 246, 250, 255))
    draw_centered(d, (col(rear_y) - 170, row(0.62), col(rear_y) + 170, row(0.50)),
                  "沪-07", fit_font("沪-07", 54, 200, 56), (176, 198, 230, 255))
    return img


def _road_grime(w, h, seed=4):
    """Road film: fine wheel-spray speckle and vertical drips (no discs)."""
    grime = Image.new("RGBA", (w, max(1, h)), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grime)
    rng = np.random.default_rng(seed)
    for _ in range(int(w * h / 900)):
        x = int(rng.integers(0, w))
        y = int(rng.integers(int(h * 0.45), h))
        s = int(rng.integers(1, 4))
        gd.rectangle([x, y, x + s, y + s], fill=(46, 42, 38, 60))
    for _ in range(int(w / 90)):
        x = int(rng.integers(0, w))
        top = int(h * rng.uniform(0.35, 0.75))
        gd.line([(x, top), (x, h)], fill=(46, 42, 38, 40), width=2)
    for i in range(h):
        t = i / float(max(1, h - 1))
        if t > 0.70:
            gd.line([(0, i), (w, i)], fill=(40, 36, 32, int(50 * (t - 0.70) / 0.30)))
    return grime


def taxi_livery(length, size=(2048, 1024)):
    """Taxi UV2 livery: the silver-grey lower skirt every Shanghai taxi wears."""
    w, h = size
    img = Image.new("RGBA", size, (242, 244, 245, 0))
    d = ImageDraw.Draw(img)

    def row(z):
        return int((1.0 - z / 2.0) * h)

    d.rectangle([0, row(0.40), w, row(0.10)], fill=(169, 173, 177, 255))
    d.rectangle([0, row(0.435), w, row(0.405)], fill=(236, 238, 240, 255))
    img.alpha_composite(_road_grime(w, row(0.10) - row(0.40), seed=9),
                        (0, row(0.40)))
    return img


def decal_taxi(size=(1024, 512)):
    """Taxi door sticker: 申城出租, the fleet number and the phone."""
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([8, 8, size[0] - 8, size[1] - 8], radius=26,
                        fill=(30, 140, 138, 255))
    d.rounded_rectangle([18, 18, size[0] - 18, size[1] - 18], radius=20,
                        outline=(226, 240, 238, 255), width=4)
    draw_centered(d, (40, 40, size[0] - 40, 300), "申城出租",
                  fit_font("申城出租", 190, size[0] - 120, 240), (255, 255, 255, 255))
    draw_centered(d, (40, 300, size[0] - 40, 400), "沪交 T-0731",
                  fit_font("沪交 T-0731", 78, size[0] - 160, 90), (226, 240, 238, 255))
    draw_centered(d, (40, 396, size[0] - 40, 480), "6688 1234",
                  fit_font("6688 1234", 60, size[0] - 240, 70), (188, 214, 212, 255))
    return img


def decal_van(size=(1024, 512)):
    """Courier livery: 申城快递, the latin line, a stripe and a phone number."""
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, size[0], 96], fill=(24, 120, 140, 255))
    d.rectangle([0, 96, size[0], 132], fill=(232, 168, 42, 255))
    draw_centered(d, (40, 150, size[0] - 40, 330), "申城快递",
                  fit_font("申城快递", 150, size[0] - 140, 170), (32, 40, 46, 255))
    draw_centered(d, (40, 320, size[0] - 40, 400), "SHENCHENG EXPRESS",
                  fit_font("SHENCHENG EXPRESS", 62, size[0] - 200, 72),
                  (24, 120, 140, 255))
    draw_centered(d, (40, 396, size[0] - 40, 480), "400-6688-0000",
                  fit_font("400-6688-0000", 60, size[0] - 240, 70),
                  (60, 70, 78, 255))
    return img


def sign_roof(size=(512, 256)):
    """Taxi roof light face (emissive)."""
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_centered(d, (10, 10, size[0] - 10, size[1] - 10), "申城出租",
                  fit_font("申城出租", 150, size[0] - 40, size[1] - 40),
                  (255, 252, 240, 255))
    return img


def sign_roof_en(size=(512, 256)):
    """Taxi roof light side face (TAXI, emissive)."""
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_centered(d, (10, 10, size[0] - 10, size[1] - 10), "TAXI",
                  fit_font("TAXI", 150, size[0] - 40, size[1] - 40),
                  (255, 252, 240, 255))
    return img


def sign_roof_number(text, size=(512, 256)):
    """Police roof number (沪-07)."""
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_centered(d, (10, 10, size[0] - 10, size[1] - 10), text,
                  fit_font(text, 150, size[0] - 60, size[1] - 60),
                  (28, 32, 40, 255))
    return img


def dot_matrix(text, size, fg=(255, 186, 64), bg=(6, 6, 8), cell=6):
    """Amber LED dot-matrix sign."""
    w, h = size
    img = Image.new("RGB", size, bg)
    tmp = Image.new("L", (w, h), 0)
    font = fit_font(text, int(h * 0.62), w * 0.92, h * 0.7)
    probe = ImageDraw.Draw(tmp)
    box = probe.textbbox((0, 0), text, font=font)
    probe.text(((w - (box[2] - box[0])) * 0.5, (h - (box[3] - box[1])) * 0.5 - box[1]),
               text, font=font, fill=255)
    px = np.asarray(tmp)
    d = ImageDraw.Draw(img)
    for y in range(0, h, cell):
        for x in range(0, w, cell):
            if px[y, x] > 100:
                d.rectangle([x, y, x + cell - 2, y + cell - 2], fill=fg)
    return img




def decal_drone(size=(512, 256)):
    """Drone shell livery: navy band with the 天巡 unit mark."""
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, int(size[1] * 0.42), size[0], size[1]], fill=(27, 42, 78, 235))
    draw_centered(d, (10, int(size[1] * 0.48), size[0] - 10, int(size[1] * 0.96)),
                  "天巡 SKYPOL", fit_font("天巡 SKYPOL", 84, size[0] - 40, 110),
                  (242, 246, 250, 255))
    return img
