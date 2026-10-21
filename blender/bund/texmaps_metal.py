"""The metal, the paper and the light of the Bund (bund unit).

The cast iron, the clock dial, the copper of the Peace Hotel, the bronze of the bull,
the palace lantern's paper and the light curtains of the flood wall.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from bund.texbase import fbm, save, save_png, save_set, value_noise  # noqa: E402


# ---------------------------------------------------------------- the clock dial
ROMAN = {
    "I": [[(0.5, 0), (0.5, 1)]],
    "II": [[(0.25, 0), (0.25, 1)], [(0.75, 0), (0.75, 1)]],
    "III": [[(0.17, 0), (0.17, 1)], [(0.5, 0), (0.5, 1)], [(0.83, 0), (0.83, 1)]],
    "IV": [[(0.2, 0), (0.55, 1), (0.9, 0)], [(0.55, 0), (0.9, 1)]],
    "V": [[(0.1, 0), (0.5, 1)], [(0.5, 1), (0.9, 0)]],
    "VI": [[(0.2, 0), (0.2, 1)], [(0.5, 0), (0.85, 1)], [(0.5, 1), (0.85, 0)]],
    "VII": [[(0.12, 0), (0.12, 1)], [(0.35, 0), (0.72, 1)], [(0.35, 1), (0.72, 0)],
            [(0.9, 0), (0.9, 1)]],
    "VIII": [[(0.1, 0), (0.1, 1)], [(0.3, 1), (0.68, 0)], [(0.3, 0), (0.68, 1)],
             [(0.5, 0), (0.5, 1)], [(0.9, 0), (0.9, 1)]],
    "IX": [[(0.2, 0), (0.5, 1)], [(0.5, 0), (0.85, 1)], [(0.85, 0), (0.85, 1)]],
    "X": [[(0.1, 0), (0.9, 1)], [(0.1, 1), (0.9, 0)]],
    "XI": [[(0.15, 0), (0.9, 1)], [(0.15, 1), (0.9, 0)], [(0.45, 0), (0.45, 1)]],
    "XII": [[(0.1, 0), (0.1, 1)], [(0.1, 1), (0.9, 0)], [(0.5, 0), (0.5, 1)]],
}
NUMERALS = ["XII", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI"]


def make_iron(prefix="iron_dark", size=1024, seed=1929):
    """Black painted cast iron: orange peel, scratches, dust, paint chips and rust streaks.

    The chips and the streaks are the relief: the normal map has to read at 2 deg or more,
    or the balustrades and the lamp posts look like flat black cardboard."""
    rng = np.random.default_rng(seed)
    peel = fbm(size, 300, rng, 2) - 0.5
    scratch = np.clip(1.0 - np.abs(fbm(size, 14, rng, 3) - 0.5) * 22.0, 0.0, 1.0)
    chip = (value_noise(size, 90, rng) > 0.968).astype(float)
    dust = fbm(size, 8, rng, 3) - 0.5
    # the rust: a streak that runs down the surface from every chip
    rust = np.zeros((size, size))
    for _ in range(5):
        seed_row = rng.integers(0, size)
        col = rng.integers(0, size)
        length = rng.integers(size // 6, size // 2)
        width = rng.integers(2, 7)
        for k in range(length):
            row = (seed_row + k) % size
            c = (col + int(k * 0.12)) % size
            rust[row, max(0, c - width):c + width] = 1.0
    rust = np.maximum(rust * (value_noise(size, 40, rng) > 0.45), chip * 0.8)
    rust = np.clip(rust, 0.0, 1.0)
    base = np.array([28.0, 30.0, 32.0])
    v = peel * 9.0 + dust * 6.0
    diff = np.stack([base[0] + v, base[1] + v, base[2] + v], axis=-1)
    rust_col = np.array([104.0, 62.0, 38.0])
    diff = diff * (1 - chip[:, :, None] * 0.55) + rust_col[None, None, :] * chip[:, :, None] * 0.55
    diff = diff * (1 - rust[:, :, None] * 0.45) + rust_col[None, None, :] * rust[:, :, None] * 0.45
    diff += np.array([120.0, 122.0, 126.0]) * scratch[:, :, None] * 0.25
    height = peel * 0.18 + chip * 0.55 - scratch * 0.08 + rust * 0.30
    rough = np.clip(0.46 + 0.18 * (peel + 0.5) + 0.30 * chip + 0.25 * rust, 0.3, 0.95)
    save_set(prefix, diff, height, rough, strength=4.0, rough_size=1024)


def _glyph(mask, glyph, cx, cy, h, w, phi, thick):
    """Draw one Roman numeral: `right` runs along the dial, `up` points out of it."""
    rx, ry = math.cos(phi), math.sin(phi)        # the reading direction
    ux, uy = math.sin(phi), -math.cos(phi)       # outwards from the centre
    for stroke in ROMAN[glyph]:
        for (ax, ay), (bx, by) in zip(stroke[:-1], stroke[1:]):
            p0 = (cx + (ax - 0.5) * w * rx + ay * h * ux,
                  cy + (ax - 0.5) * w * ry + ay * h * uy)
            p1 = (cx + (bx - 0.5) * w * rx + by * h * ux,
                  cy + (bx - 0.5) * w * ry + by * h * uy)
            _line(mask, p0, p1, thick)


def _line(mask, p0, p1, thick):
    """A thick line into a boolean mask (the distance to the segment)."""
    h, w = mask.shape
    x0, y0 = p0
    x1, y1 = p1
    r = thick * 0.5
    ix0 = max(0, int(min(x0, x1) - r))
    ix1 = min(w, int(max(x0, x1) + r) + 1)
    iy0 = max(0, int(min(y0, y1) - r))
    iy1 = min(h, int(max(y0, y1) + r) + 1)
    if ix0 >= ix1 or iy0 >= iy1:
        return
    xs = np.arange(ix0, ix1)[None, :]
    ys = np.arange(iy0, iy1)[:, None]
    dx, dy = x1 - x0, y1 - y0
    l2 = dx * dx + dy * dy
    if l2 < 1e-9:
        t = np.zeros((ys.shape[0], xs.shape[1]))
    else:
        t = np.clip(((xs - x0) * dx + (ys - y0) * dy) / l2, 0.0, 1.0)
    px = x0 + t * dx
    py = y0 + t * dy
    mask[iy0:iy1, ix0:ix1] |= ((xs - px) ** 2 + (ys - py) ** 2) <= r * r


def make_clock_dial(prefix="clock_dial", size=1024, seed=1962):
    """The Customs House dial: Roman numerals, a minute ring and half-line hands."""
    rng = np.random.default_rng(seed)
    ss = 2                                     # the supersample of the drawing
    big = size * ss
    yy, xx = np.mgrid[0:big, 0:big]
    u = (xx / big - 0.5) * 2.0
    v = (yy / big - 0.5) * 2.0
    r = np.sqrt(u * u + v * v)
    face = np.array([255.0, 246.0, 224.0])
    diff = np.repeat(face[None, None, :], big, 0).repeat(big, 1).astype(float)
    ink = np.zeros((big, big), dtype=bool)
    # the two rings
    ink |= np.abs(r - 0.94) < 0.016
    ink |= np.abs(r - 0.88) < 0.008
    # the minute ticks
    for i in range(60):
        a = i * math.pi / 30.0
        long_mark = (i % 5 == 0)
        r0 = 0.80 if long_mark else 0.845
        p0 = (0.5 + r0 * math.cos(a) / 2.0, 0.5 + r0 * math.sin(a) / 2.0)
        p1 = (0.5 + 0.88 * math.cos(a) / 2.0, 0.5 + 0.88 * math.sin(a) / 2.0)
        _line(ink, (p0[0] * big, p0[1] * big), (p1[0] * big, p1[1] * big),
              (0.016 if long_mark else 0.007) * big)
    # the Roman numerals: each one stands upright on the dial, its top pointing out
    for i, glyph in enumerate(NUMERALS):
        phi = i * math.pi / 6.0                    # clockwise from 12 o'clock
        cx = (0.5 + 0.60 * math.sin(phi) / 2.0) * big
        cy = (0.5 - 0.60 * math.cos(phi) / 2.0) * big
        w = 0.26 * big / max(1, len(glyph))
        _glyph(ink, glyph, cx, cy, 0.125 * big, w, phi, 0.018 * big)
    # the hands: half lines from the centre (hour 0.45 R, minute 0.72 R), 10:10
    for a, ln, wd in ((math.radians(-145.0), 0.45, 0.030), (math.radians(-30.0), 0.72, 0.022)):
        d = np.array([math.cos(a), math.sin(a)])
        proj = u * d[0] + v * d[1]
        perp = -u * d[1] + v * d[0]
        ink |= (proj > 0.015) & (proj < ln) & (np.abs(perp) < wd)
    # the boss at the centre
    ink |= r < 0.045
    diff[ink] = np.array([28.0, 26.0, 24.0])
    diff = diff.reshape(size, ss, size, ss, 3).mean(axis=(1, 3))
    ink = ink.reshape(size, ss, size, ss).mean(axis=(1, 3)) > 0.35
    diff *= (1.0 - np.clip(fbm(size, 60, rng, 3), 0, 1) * 0.10)[:, :, None]
    save(prefix + "_diff.jpg", diff)


def make_copper_pyramid(prefix="copper_pyramid", size=1024, seed=1973):
    """The Peace Hotel pyramid: dark copper (#2E5E4E) with 0.25 m standing seams."""
    rng = np.random.default_rng(seed)
    u = np.arange(size)[None, :] / size
    # the texture covers 4.5 m of the pyramid, with a standing seam every 0.45 m
    seam = np.clip(1.0 - (u % 0.1) / 0.02, 0.0, 1.0)
    patina = np.clip(fbm(size, 12, rng, 4) * 1.6 - 0.25, 0.0, 1.0)
    grit = fbm(size, 240, rng, 2) - 0.5
    base = np.array([46.0, 94.0, 78.0])
    v0 = patina * 22.0 + grit * 12.0
    diff = np.stack([base[0] + v0 * 0.5, base[1] + v0, base[2] + v0 * 0.8], axis=-1)
    diff *= (1.0 - seam[:, :, None] * 0.45)
    height = seam * 1.6 + patina * 0.10 + grit * 0.08
    rough = np.clip(0.38 + 0.26 * patina + 0.12 * seam, 0.22, 0.9)
    save_set(prefix, diff, height, rough, strength=3.6, rough_size=1024)
    # the glow: bright at the base of the pyramid, fading to the apex (the image's top
    # row is v = 1, so the gradient is written upside down)
    grad = np.linspace(0.375, 1.0, size)[:, None]
    teal = np.array([0.13, 0.75, 0.55])
    glow = np.repeat((teal * 1.0)[None, None, :], size, 0).repeat(size, 1)
    glow = glow * grad[:, :, None]
    save("pyramid_glow_diff.jpg", np.clip(glow * 255.0, 0, 255))


def make_tile_teal(prefix="tile_teal", size=1024, seed=1993):
    """The Bank of China's roof: glazed blue-green cylinder tiles (#2E6E6A)."""
    rng = np.random.default_rng(seed)
    u = np.arange(size)[None, :] / size
    v = np.arange(size)[:, None] / size
    n = 8
    fu = (u * n) % 1.0
    fv = (v * n) % 1.0
    d = np.minimum(np.minimum(fu, 1 - fu), np.minimum(fv, 1 - fv)) / n
    joint = np.clip(1.0 - d / 0.012, 0.0, 1.0)
    round_ = np.sqrt((fu - 0.5) ** 2 + (fv - 0.5) ** 2)
    bulge = np.clip(1.0 - round_ * 2.2, 0.0, 1.0)
    grime = fbm(size, 16, rng, 4) - 0.5
    spec = fbm(size, 300, rng, 2) - 0.5
    base = np.array([46.0, 110.0, 106.0])
    vv = grime * 12.0 + spec * 8.0
    diff = np.stack([base[0] + vv, base[1] + vv, base[2] + vv * 0.9], axis=-1)
    m = joint[:, :, None]
    diff = diff * (1 - m) + np.array([26.0, 58.0, 56.0])[None, None, :] * m
    height = bulge * 0.7 - joint * 0.6 + spec * 0.05
    rough = np.clip(0.18 + 0.12 * (grime + 0.5) + 0.30 * joint, 0.10, 0.7)
    save_set(prefix, diff, height, rough, strength=1.8, rough_size=1024)


def make_flag(prefix="flag_red", size=1024, seed=1975):
    """Red flag cloth: a visible weave and the folds of the mesh."""
    rng = np.random.default_rng(seed)
    weave = (np.sin(np.arange(size)[:, None] * 1.6) * np.sin(np.arange(size)[None, :] * 1.6))
    cloth = fbm(size, 90, rng, 3) - 0.5
    base = np.array([176.0, 26.0, 30.0])
    v = weave * 6.0 + cloth * 14.0
    diff = np.stack([base[0] + v, base[1] + v * 0.5, base[2] + v * 0.5], axis=-1)
    height = weave * 0.35 + cloth * 0.25
    rough = np.clip(0.72 + 0.12 * (cloth + 0.5), 0.5, 0.95)
    save_set(prefix, diff, height, rough, strength=1.4, rough_size=1024)


def make_bronze(prefix="bronze", size=1024, seed=1978):
    """Cast bronze for the bull of the Financial Plaza.

    The patina (#3A3226 / #4C5A3E) sits in the hollows and the high points - the horns,
    the nose, the hooves - are polished (#B58B4F): the roughness separates them (0.6 in
    the patina, 0.25 on the metal), so the bull reads as a bronze and not as a lump."""
    rng = np.random.default_rng(seed)
    patina = np.clip(fbm(size, 22, rng, 4) * 1.8, 0.0, 1.0)
    fine = np.clip(fbm(size, 120, rng, 3) * 1.6, 0.0, 1.0)
    grit = fbm(size, 240, rng, 2) - 0.5
    # the polished patches: the places the handlers and the weather keep bright
    polish = np.clip((fbm(size, 9, rng, 3) * 1.7 - 0.55) * 2.2, 0.0, 1.0)
    base = np.array([92.0, 68.0, 36.0])
    v = patina * 18.0 + grit * 12.0
    diff = np.stack([base[0] + v * 0.4, base[1] + v * 0.9, base[2] + v], axis=-1)
    dark = np.array([0x3A, 0x32, 0x26], dtype=float)
    green = np.array([0x4C, 0x5A, 0x3E], dtype=float)
    diff = diff * (1 - patina[:, :, None] * 0.7) + green[None, None, :] * patina[:, :, None] * 0.7
    diff = diff * (1 - fine[:, :, None] * 0.25) + dark[None, None, :] * fine[:, :, None] * 0.25
    metal = np.array([0xB5, 0x8B, 0x4F], dtype=float)
    diff = diff * (1 - polish[:, :, None] * 0.8) + metal[None, None, :] * polish[:, :, None] * 0.8
    height = patina * 0.45 + fine * 0.20 + grit * 0.10 - polish * 0.25
    rough = np.clip(0.60 * patina + 0.25 * (1.0 - polish) + 0.12 * fine, 0.22, 0.85)
    save_set(prefix, diff, height, rough, strength=3.5, rough_size=1024)


def make_lantern(prefix="lantern_paper", size=1024, seed=1981):
    """The palace lantern's paper: warm panels, red and gold ribs, a tassel at the bottom."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size]
    u = xx / size
    v = yy / size
    rib = (np.abs(((u * 6.0) % 1.0) - 0.5) > 0.42) | (v < 0.08) | (v > 0.9)
    paper = np.array([255.0, 208.0, 150.0])
    diff = np.repeat(paper[None, None, :], size, 0).repeat(size, 1).astype(float)
    grain = fbm(size, 120, rng, 3) - 0.5
    diff += (grain * 16.0)[:, :, None]
    diff[rib] = np.array([150.0, 40.0, 34.0])
    save(prefix + "_diff.jpg", diff)


def make_cove(prefix="cove_gold", size=1024, seed=1987):
    """The warm LED cove strip under the cornices (a diffuser, not a lamp)."""
    u = np.broadcast_to(np.arange(size)[None, :] / size, (size, size))
    led = np.clip(1.0 - np.abs(((u * 8.0) % 1.0) - 0.5) * 3.2, 0.0, 1.0)
    diff = np.array([255.0, 206.0, 140.0]) * (0.5 + 0.5 * led)[:, :, None]
    save(prefix + "_diff.jpg", diff)


def make_flood(prefix="flood_cascade", width=1024, height=1024, seed=1990):
    """One 6 m module of the flood wall's light curtain.

    The wall reads as a continuous soft band with brighter vertical curtains in it, the
    way the reference photo shows it: the band is lit from the lip (y +2.5) down to the
    water (y -3), #29D3FF at the top and #1E8BFF at the foot, with a dimmer joint every
    6 m instead of a black gap (review r3: a row of blue rectangles reads as a fence)."""
    rng = np.random.default_rng(seed)
    u = np.arange(width)[None, :] / width
    v = np.arange(height)[:, None] / height          # 0 at the top row = the lip
    # the joint of the modules: a dimmer band, not a hole
    joint = np.clip((np.abs(u - 0.5) - 0.375) / 0.05, 0.0, 1.0)
    # two bright curtains per module, with a soft edge
    streak = (np.exp(-(((u - 0.32) / 0.17) ** 2)) + np.exp(-(((u - 0.68) / 0.17) ** 2)))
    noise = value_noise(width, 24, rng)
    for _ in range(2):
        noise = 0.5 * (noise + np.roll(noise, 5))
    noise = (noise - noise.min()) / (noise.ptp() + 1e-6)
    # the band is lit over its whole height, a little dimmer at the foot
    fade = 0.34 + 0.66 * np.clip(1.0 - v, 0.0, 1.0) ** 0.8
    amount = np.clip((0.18 + 0.85 * streak) * (0.55 + 0.55 * noise) * fade * (1.0 - joint * 0.55),
                     0.0, 1.0)
    top = np.array([0x29, 0xD3, 0xFF], dtype=float)
    bot = np.array([0x1E, 0x8B, 0xFF], dtype=float)
    col = top[None, None, :] * (1.0 - v[:, :, None]) + bot[None, None, :] * v[:, :, None]
    diff = np.clip(col * amount[:, :, None], 0, 255)
    save(prefix + "_diff.jpg", diff)


def make_wash_crown(prefix="wash_crown", width=16, height=128):
    """The crown wash ramp: the shell of a crown is brightest at its top.

    The image's top row is v = 1, so the ramp runs from 0.80 at the foot of the crown
    to 1.0 at its top."""
    row = (np.arange(height) / float(height - 1))[:, None]
    ramp = (0.80 + 0.20 * (1.0 - row)) ** (1.0 / 2.2)
    rgb = np.repeat((ramp * 255.0), width, axis=1)[:, :, None]
    rgba = np.concatenate([np.repeat(rgb, 3, axis=2),
                           np.full((height, width, 1), 255.0)], axis=2)
    save_png(prefix + ".png", rgba)
    return prefix
