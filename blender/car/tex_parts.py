"""The trim, carbon and interior maps.

The black trim uses the ambientCG "Plastic 006" set from the shared library
(fetched with tools/textures/fetch.py); the carbon is a 2x2 twill woven from
4 mm tows; the interior maps are the seat weave, the microsuede, the cabin
grain, the dark inner surface and the COPV filament winding.
"""
import math
import os

import numpy as np
from PIL import Image

from car import tex_common as tc

LIB_TRIM = ("Plastic006", "blacktrim")


def carbon_maps(tile_m=0.1):
    """2x2 twill weave, 4 mm tows, two tones (ambientCG-style carbon)."""
    n = 1024
    px = n / tile_m
    tows = int(round(tile_m / 0.004))          # 4 mm tows
    cell = n / tows
    yy, xx = np.mgrid[0:n, 0:n]
    ci = (xx // cell).astype(int)
    cj = (yy // cell).astype(int)
    over = ((ci + cj) % 4) < 2                 # 2x2 twill
    ridge = np.sin(np.pi * (xx % cell) / cell) * np.sin(np.pi * (yy % cell) / cell)
    height = np.where(over, ridge, -ridge * 0.35) * 0.0004
    tone = np.where(over, 0x23, 0x14).astype(np.float32) / 255.0
    base = np.repeat((tone * 255.0)[:, :, None], 3, axis=2)
    base += tc.noise(n, 64, 6.0, 5)[..., None]
    tc.save("carbon_base.png", base)
    tc.save("carbon_nor.png", tc.height_to_normal(height, px), check_normal=True)
    rough = 0.35 + tc.noise(n, 16, 0.14, 6)     # the weave is not uniformly glossy
    tc.save("carbon_rough.png", np.repeat((np.clip(rough, 0, 1) * 255.0)[:, :, None], 3, axis=2))


def trim_maps():
    """The satin black trim: the ambientCG Plastic 006 grain from the library.

    The library normal is used at NATIVE strength (review r3 #10: the old code
    multiplied the R/G spread by up to 8, which turned the satin into coarse
    granite). The roughness gets a subtle large-scale breakup so the trim is
    not a flat value at 5 m either.
    """
    src = os.path.join(tc.LIB, LIB_TRIM[0], "%s_nor_gl.jpg" % LIB_TRIM[0])
    rough_src = os.path.join(tc.LIB, LIB_TRIM[0], "%s_rough.jpg" % LIB_TRIM[0])
    if os.path.exists(src):
        img = Image.open(src).convert("RGB").resize((512, 512), Image.LANCZOS)
        arr = np.asarray(img, np.float32).copy()
        # native strength: a gentle lift (gain <= 1.5) of the library's own R/G
        for c in (0, 1):
            lo, hi = float(arr[:, :, c].min()), float(arr[:, :, c].max())
            if hi - lo > 1e-3:
                arr[:, :, c] = 128.0 + (arr[:, :, c] - 128.0) * min(20.0 / (hi - lo), 1.0)
        tc.save("%s_nor.png" % LIB_TRIM[1], arr)
    else:                                   # the library is not there: fall back to noise
        n = 512
        g = np.random.default_rng(3).normal(0.0, 0.00012, (n, n)).astype(np.float32)
        g = tc.blur(g, 1.2) + 0.45 * tc.blur(g, 2.4)
        tc.save("%s_nor.png" % LIB_TRIM[1], tc.height_to_normal(g, n / 0.05), check_normal=True)
    if os.path.exists(rough_src):
        img = Image.open(rough_src).convert("L").resize((512, 512), Image.LANCZOS)
        arr = np.asarray(img, np.float32) / 255.0
    else:
        n = 512
        arr = 0.50 + tc.noise(n, 64, 0.10, 9)
    # the satin range (ART §5): 0.45..0.55 with a slow large-scale breakup
    arr = 0.50 + (arr - 0.50) * 0.6
    arr = np.clip(arr + tc.noise(512, 8, 0.05, 41), 0.45, 0.55)
    tc.save("%s_rough.png" % LIB_TRIM[1], np.repeat((arr * 255.0)[:, :, None], 3, axis=2))


def interior_maps():
    """The seat weave, the microsuede, the cabin grain, the COPV and the screen."""
    n = 512
    yy, xx = np.mgrid[0:n, 0:n]
    s = 8.0
    # the weave jitters: a perfectly regular grid reads as a printed pattern
    jx = tc.noise(n, 16, 1.6, 61)
    jy = tc.noise(n, 16, 1.6, 62)
    h = (np.sin(2 * math.pi * (xx + jx) / s) * np.sin(2 * math.pi * (yy + jy) / s)).astype(np.float32)
    h += 0.4 * np.sin(2 * math.pi * (xx + yy + jx + jy) / (s * 2.0))
    h += tc.noise(n, 32, 0.25, 63)
    tc.save("seat_weave_nor.png", tc.height_to_normal(h * 0.0004, n / 0.25), check_normal=True)
    suede = tc.blur(np.random.default_rng(17).normal(0.0, 0.00035, (n, n)).astype(np.float32), 1.6)
    tc.save("microsuede_nor.png", tc.height_to_normal(suede, n / 0.05), check_normal=True)
    cabin = tc.blur(np.random.default_rng(19).normal(0.0, 0.00025, (n, n)).astype(np.float32), 1.1)
    tc.save("cabin_nor.png", tc.height_to_normal(cabin, n / 0.06), check_normal=True)
    inner = tc.blur(np.random.default_rng(27).normal(0.0, 0.0009, (n, n)).astype(np.float32), 2.2)
    tc.save("innerdark_nor.png", tc.height_to_normal(inner, n / 0.04), check_normal=True)
    # the COPV filament: a winding of a varying pitch, not a printed stripe
    wind = tc.noise(n, 10, 2.4, 64)
    fil = np.sin(2 * math.pi * (xx * 0.6 + yy * 0.25 + wind) / 9.0).astype(np.float32)
    tc.save("copv_nor.png", tc.height_to_normal(fil * 0.0006, n / 0.4), check_normal=True)


def screen_map(w=512, h=256):
    """The dark red cockpit UI on black."""
    from PIL import ImageDraw
    img = Image.new("RGB", (w, h), (10, 6, 8))
    dr = ImageDraw.Draw(img)
    f = tc.font(26)
    for i, line in enumerate(("0-60  0.81 s", "DOWNFORCE  4698 KG", "PITCH  170 DEG",
                              "ALTITUDE  68.0 FT", "THRUSTER  5,500 PSI")):
        dr.text((20, 16 + i * 40), line, font=f, fill=(255, 42, 42))
    for i in range(0, w, 24):
        dr.line([(i, h - 30), (i, h - 10)], fill=(120, 20, 24))
    dr.line([(0, h - 20), (w, h - 20)], fill=(200, 40, 44))
    tc.save("screen_ui.png", np.asarray(img, np.float32))
