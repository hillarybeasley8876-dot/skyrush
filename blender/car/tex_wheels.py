"""The wheel and metal maps: the tyres, the brake disc, the rim grain and the
machined metal of the nozzle rings and the gold throats.

The tyre map is drawn with v = the profile coordinate (0 = the inner bead,
0.72..1.0 = the OUTBOARD sidewall), so the raised lettering lands on the face
that is actually visible and the grooves stay on the tread.
"""
import math

import numpy as np
from PIL import Image, ImageDraw

from car import tex_common as tc

TREAD_LO, TREAD_HI = 0.40, 0.72
SIDEWALL_LO = 0.77


def tyre_map(tag, size_text):
    """One tyre map: 2 circumferential grooves, sipes, raised sidewall text."""
    w, h = 2048, 512
    d = tc.loft()["wheels"]
    R = d["rear" if tag == "R" else "front"]["tyre_diameter"] / 2.0
    px_u = w / (2.0 * math.pi * R)
    px_v = h / 0.50
    height = np.zeros((h, w), np.float32)
    base = np.zeros((h, w, 3), np.float32)
    base[:] = np.array([22, 22, 22], np.float32)
    rough = np.full((h, w), 0.85, np.float32)
    # the tread band (v 0.40..0.72) is the image rows 0.28h..0.60h
    r0 = int((1.0 - TREAD_HI) * h)
    r1 = int((1.0 - TREAD_LO) * h)
    for v0 in (TREAD_LO + (TREAD_HI - TREAD_LO) / 3.0,
               TREAD_LO + 2.0 * (TREAD_HI - TREAD_LO) / 3.0):
        c = int((1.0 - v0) * h)
        height[c - 4:c + 4, :] = -0.005
    for i in range(64):                      # 64 lateral sipes across the tread
        u = int(i * w / 64.0)
        height[r0:r1, u:u + 3] -= 0.002
    # the outboard sidewall band (v 0.77..1.0) is the image rows 0..0.23h
    band = np.zeros((h, w), np.float32)
    band[:int((1.0 - SIDEWALL_LO) * h) + 4, :] = 1.0
    rough[:int((1.0 - 0.93) * h), :] = 0.50  # the glossier ring near the rim
    img = Image.new("L", (w, h), 0)
    dr = ImageDraw.Draw(img)
    f = tc.font(46)
    for off in (0, w // 2):                  # the text twice around the tyre
        dr.text((170 + off, int(0.02 * h)), "SKYRUSH TROFEO", font=f, fill=255)
        dr.text((170 + off, int(0.11 * h)), size_text, font=f, fill=255)
    letter = (np.asarray(img, np.float32) / 255.0) * band
    height += letter * 0.0012                # the raised lettering
    base = base * (1.0 - letter[..., None]) + np.array([216, 216, 216], np.float32) * letter[..., None]
    tc.save("tyre_base_%s.png" % tag.lower(), base)
    tc.save("tyre_nor_%s.png" % tag.lower(),
            tc.height_to_normal(height, (px_v, px_u)), check_normal=True)
    tc.save("tyre_rough_%s.png" % tag.lower(),
            np.repeat((rough * 255.0)[:, :, None], 3, axis=2))


def disc_map():
    """The carbon-ceramic disc: a mottled base, a drilled ring, a rough map."""
    n = 512
    base = np.random.default_rng(11).normal(58.0, 9.0, (n, n)).astype(np.float32)
    base = np.asarray(Image.fromarray(base).resize((n, n), Image.BILINEAR), np.float32)
    rgb = np.stack([base, base, base * 1.02], axis=-1)
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8))
    dr = ImageDraw.Draw(img)
    for i in range(12):
        u = (i + 0.5) / 12.0
        v = 0.80
        cx, cy = u * n, (1.0 - v) * n
        dr.ellipse([cx - 11, cy - 11, cx + 11, cy + 11], fill=(14, 14, 15))
    tc.save("disc_base.png", np.asarray(img, np.float32))
    # the drilled holes and the turned surface in the normal map
    holes = np.zeros((n, n), np.float32)
    for i in range(12):
        u = (i + 0.5) / 12.0
        cx, cy = u * n, (1.0 - 0.80) * n
        yy, xx = np.mgrid[0:n, 0:n]
        d = np.hypot(xx - cx, yy - cy)
        holes -= 0.0008 * np.clip(12.0 - d, 0.0, 12.0)
    turn = np.sin(np.mgrid[0:n, 0:n][0] * 0.9) * 0.00004
    tc.save("disc_nor.png", tc.height_to_normal(holes + turn, n / 0.1), check_normal=True)
    rough = 0.45 + tc.noise(n, 16, 0.16, 31)
    tc.save("disc_rough.png", np.repeat((np.clip(rough, 0, 1) * 255.0)[:, :, None], 3, axis=2))


def metal_maps():
    """The titanium ring (concentric machining) and the gold (radial brushing).

    Both maps are sampled with a polar UV (u = angle, v = radius / depth), so
    the marks run in the right direction. The streaks have a varying length and
    the rings a varying pitch, so the maps are not perfectly periodic
    (review r3, synthetic maps).
    """
    n = 512
    yy, xx = np.mgrid[0:n, 0:n]
    # titanium: concentric rings with a wandering pitch -> a machined, not
    # printed, surface (10 small rings, so 512 px is plenty)
    wander = tc.noise(n, 6, 3.0, 71) * 0.5
    ring = np.sin(2.0 * math.pi * (yy + wander) / (n / 40.0)).astype(np.float32) * 0.000022
    ring += (np.random.default_rng(4).random((n, n)) - 0.5) * 0.000004
    tc.save("titanium_nor.png", tc.height_to_normal(ring, n / 0.04), check_normal=True)
    # gold: fine radial brushing, the streaks of a varying length
    rng = np.random.default_rng(8)
    base = (rng.random((n, n)).astype(np.float32) - 0.5)
    length = 0.35 + 0.6 * rng.random((1, n)).astype(np.float32)
    streak = np.empty((n, n), np.float32)
    acc = base[0].copy()
    streak[0] = acc
    for i in range(1, n):                    # a decaying filter along the radius
        acc = acc * 0.94 + base[i] * 0.06
        streak[i] = acc
    streak = streak * (0.4 + length) * 0.00012 + tc.noise(n, 8, 0.000020, 12)
    tc.save("gold_nor.png", tc.height_to_normal(streak, n / 0.04), check_normal=True)


def nozzle_gold_map():
    """The gold throat grading from #B08458 at the mouth to #2A1A0E inside."""
    n = 256
    top = np.array([0x2A, 0x1A, 0x0E], np.float32)     # the deep end (v = 1)
    bot = np.array([0xB0, 0x84, 0x58], np.float32)     # the mouth (v = 0)
    t = np.linspace(0.0, 1.0, n, dtype=np.float32)[:, None]
    rgb = (top[None, None, :] * (1.0 - t)[..., None] + bot[None, None, :] * t[..., None])
    rgb = np.repeat(rgb, n, axis=1)
    rgb += tc.noise(n, 16, 6.0, 21)[..., None]
    tc.save("nozzle_gold.png", np.clip(rgb, 0, 255))


def wheel_maps():
    """The rim blades: a fine turned grain and a matching roughness."""
    n = 512
    yy, xx = np.mgrid[0:n, 0:n]
    # the turned grain wanders, so the rim does not look like a printed grid
    wander = tc.noise(n, 8, 2.5, 72) * 0.4
    turn = np.sin(2.0 * math.pi * (yy + wander) / 5.0).astype(np.float32) * 0.000008
    turn += tc.noise(n, 64, 0.000004, 44)
    tc.save("wheel_nor.png", tc.height_to_normal(turn, n / 0.05), check_normal=True)
    rough = 0.30 + tc.noise(n, 24, 0.10, 45)
    tc.save("wheel_rough.png", np.repeat((np.clip(rough, 0, 1) * 255.0)[:, :, None], 3, axis=2))
