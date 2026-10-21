"""The body's own maps: the plate, the light bars, the grille and the lenses.

Everything here is drawn in a 0..1 UV space that matches the object it belongs
to (the plate is 0.48 x 0.14 m, the light bar is 14 mm tall with a 6 mm core).
"""
import math

import numpy as np
from PIL import Image, ImageDraw

from car import tex_common as tc

PLATE_W, PLATE_H = 0.48, 0.14
PLATE_TEXT = "沪A·D2049R"


def plate_map():
    """Chinese new-energy plate: white->green gradient, black 沪A·D2049R."""
    w, h = 512, 150
    top = np.array([244, 251, 246], np.float32)
    bot = np.array([72, 199, 126], np.float32)
    t = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
    rgb = (top[None, None, :] * (1.0 - t)[..., None] + bot[None, None, :] * t[..., None])
    rgb = np.repeat(rgb, w, axis=1)
    img = Image.fromarray(rgb.astype(np.uint8))
    dr = ImageDraw.Draw(img)
    dr.text((34, 44), PLATE_TEXT, font=tc.font(58), fill=(18, 18, 20))
    dr.rounded_rectangle([4, 4, w - 5, h - 5], radius=10, outline=(18, 18, 20), width=4)
    tc.save("plate.png", np.asarray(img, np.float32))
    # the 3 mm embossed relief of the text (dossier §7.1)
    mask = np.asarray(img.convert("L"), np.float32) / 255.0
    relief = (1.0 - mask) * 0.003
    tc.save("plate_nor.png", tc.height_to_normal(relief, h / PLATE_H))


def lightbar_map(name, core, lens, core_mm, bar_mm, segs, pitch_px):
    """The emission map of a light bar: a bright core line inside a smoked lens.

    `bar_mm` is the height of the lens in MILLIMETRES and `core_mm` the width of
    the core line, so the core is really 6 mm inside a 14 mm lens.
    """
    w, h = 1024, 32
    rgb = np.zeros((h, w, 3), np.float32)
    rgb[:] = np.array(lens, np.float32)
    c0 = int((0.5 - core_mm / bar_mm / 2.0) * h)
    c1 = int((0.5 + core_mm / bar_mm / 2.0) * h)
    rgb[max(0, c0):min(h, c1), :] = np.array(core, np.float32)
    for i in range(0, w, max(1, pitch_px)):
        rgb[max(0, c0):min(h, c1), i:i + 1] *= 0.85
    tc.save(name, rgb)


def brakelight_map(w=512, h=32):
    """The brake lamp: the red lens WITHOUT the bright core of the bar.

    The brake light sits 1 mm proud of the middle of the rear bar, so it needs
    its own map: with the bar's map it would carry the bar's 6 mm core and
    read as a second bright line.
    """
    rgb = np.zeros((h, w, 3), np.float32)
    rgb[:] = np.array((150, 12, 20), np.float32)
    for i in range(0, w, 4):
        rgb[:, i:i + 1] *= 0.88
    tc.save("brakelight.png", rgb)


def grille_map():
    """The 6 mm hexagonal mesh for the fan shrouds (alpha in the A channel)."""
    n = 256
    img = Image.new("RGBA", (n, n), (11, 11, 12, 255))
    dr = ImageDraw.Draw(img)
    step = 16.0
    for row in range(-1, n // int(step) + 2):
        for col in range(-1, n // int(step) + 2):
            x = col * step + (step / 2 if row % 2 else 0)
            y = row * step * 0.87
            pts = [(x + step * 0.5 * math.cos(math.radians(60 * k)),
                    y + step * 0.5 * math.sin(math.radians(60 * k))) for k in range(6)]
            dr.polygon(pts, fill=(0, 0, 0, 0))
    tc.save("fan_grille.png", np.asarray(img, np.float32))


def lens_map():
    """The fresnel prism pattern of the amber marker and the red reflector."""
    n = 256
    yy, xx = np.mgrid[0:n, 0:n]
    cell = n / 8.0
    h = (np.sin(2 * math.pi * (xx % cell) / cell) *
         np.sin(2 * math.pi * (yy % cell) / cell)).astype(np.float32) * 0.0004
    tc.save("lens_nor.png", tc.height_to_normal(h, n / 0.02), check_normal=True)


def redstrip_map():
    """The soft glow of the red ambient strips."""
    n = 256
    img = Image.new("RGB", (n, n), (255, 42, 42))
    tc.save("redstrip.png", np.asarray(img, np.float32))
