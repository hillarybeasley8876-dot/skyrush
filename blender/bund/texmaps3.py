"""The moulding trim sheet (bund unit).

A 2048 px sheet with ten bands, one per moulding family, so the cornices, the string
courses, the sills, the capitals, the keystones and the rails of the row carry real
carved detail instead of a plain stone texture (the brief asks for a shared trim sheet:
egg-and-dart, dentils, bead-and-reel, acanthus, flutes, a carved keystone, an Ionic
volute, a guilloche and a sunken panel).

The bands are laid out so that one UV unit of the sheet is one moulding: the u axis is
the girth of the profile (the cross-section) and the v axis runs along the length, so a
carving is drawn once across the girth and repeated along the run.

    band 0  v 0.00 - 0.10   the cornice: the egg-and-dart, the dentils, the fillet
    band 1  v 0.10 - 0.20   the string course: the bead-and-reel and the guilloche
    band 2  v 0.20 - 0.30   the sill: the ogee and the drip bead
    band 3  v 0.30 - 0.40   the capital: the Ionic volute and the Corinthian acanthus
    band 4  v 0.40 - 0.50   the keystone and the console
    band 5  v 0.50 - 0.60   the base mould: the torus and the astragal
    band 6  v 0.60 - 0.70   the archivolt: the roll and the fillet
    band 7  v 0.70 - 0.80   the rail and the baluster
    band 8  v 0.80 - 0.90   the fielded panel
    band 9  v 0.90 - 1.00   the plain ashlar of the frieze
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from bund.texbase import OUT, fbm, normal_from_height, save  # noqa: E402

SIZE = 2048
GRANITE = np.array([171.0, 170.0, 163.0])
BRASS = np.array([150.0, 116.0, 58.0])
NORMAL_STRENGTH = 17.0
GRAIN = 0.030            # the height of the granite grain (a fine tooling)


def _shape(u, kind):
    """The cross-section of a feature, as a function of the u fraction in [0, 1]."""
    x = 2.0 * u - 1.0
    if kind == "blob":
        return np.sqrt(np.clip(1.0 - x * x, 0.0, 1.0)) ** 0.45
    if kind == "bead":
        return np.sqrt(np.clip(1.0 - x * x, 0.0, 1.0))
    if kind == "leaf":
        return np.clip(1.0 - np.abs(x) ** 1.6, 0.0, 1.0)
    if kind == "ogee":
        return np.clip(1.0 - np.abs(x) ** 2.2, 0.0, 1.0) ** 0.6
    return np.ones_like(u)


def _draw(h, b0, b1, u0, u1, vper, kind, depth):
    """One raised feature: the girth range u0..u1, repeated along the run every vper px.

    The feature is the product of its cross-section (across the girth) and its window
    (along the run), so an egg-and-dart reads as a row of eggs."""
    size = h.shape[1]
    c0, c1 = int(u0 * size), int(u1 * size)
    if c1 - c0 < 2 or b1 - b0 < 2:
        return
    uu = (np.arange(c0, c1) + 0.5 - c0) / float(c1 - c0)
    prof = _shape(uu, kind)
    vv = np.arange(b0, b1, dtype=float)
    f = (vv % vper) / vper
    if kind in ("blob", "leaf"):
        win = np.sqrt(np.clip(1.0 - (2.0 * f - 1.0) ** 2, 0.0, 1.0)) ** 0.5
    elif kind == "block":
        win = ((f > 0.18) & (f < 0.82)).astype(float)
    elif kind == "bead":
        win = np.sqrt(np.clip(1.0 - (2.0 * f - 1.0) ** 2, 0.0, 1.0))
    else:
        win = np.ones_like(f)
    patch = (prof[None, :] * win[:, None]) * depth
    h[b0:b1, c0:c1] = np.maximum(h[b0:b1, c0:c1], patch)


def _spiral(h, b0, b1, u0, u1, depth, turns=2.4):
    """The Ionic volute: an Archimedean spiral in the (girth, run) plane of the band."""
    size = h.shape[1]
    c0, c1 = int(u0 * size), int(u1 * size)
    if c1 - c0 < 4 or b1 - b0 < 4:
        return
    yy, xx = np.mgrid[b0:b1, c0:c1]
    cy = (b0 + b1) * 0.5
    cx = (c0 + c1) * 0.5
    ry = (b1 - b0) * 0.45
    rx = (c1 - c0) * 0.45
    r = np.sqrt(((yy - cy) / ry) ** 2 + ((xx - cx) / rx) ** 2)
    ang = np.arctan2((yy - cy) / ry, (xx - cx) / rx)
    want = 0.12 + 0.30 * (ang + math.pi) / (2.0 * math.pi) * turns
    band = np.abs(r - want) < 0.10
    h[b0:b1, c0:c1] = np.where(band, depth, h[b0:b1, c0:c1])


def _blur(field, radius):
    """A cheap box blur (the ambient occlusion of the crevices)."""
    out = field.copy()
    for _ in range(2):
        pad = np.pad(out, radius, mode="edge")
        acc = np.zeros_like(out)
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                acc += pad[radius + dy:radius + dy + out.shape[0],
                           radius + dx:radius + dx + out.shape[1]]
        out = acc / ((2 * radius + 1) ** 2)
    return out


def make_trim_sheet(prefix="trim_sheet", size=SIZE, seed=2001):
    """The shared trim sheet: ten bands of carved mouldings, with a normal map."""
    rng = np.random.default_rng(seed)
    h = np.zeros((size, size), dtype=np.float32)
    col = np.repeat(GRANITE[None, None, :], size, 0).repeat(size, 1).astype(np.float32)
    band = size // 10
    # 0: the cornice - the egg-and-dart, the dentils, the fillet
    b = 0
    _draw(h, b * band, (b + 1) * band, 0.02, 0.24, int(band * 0.85), "blob", 0.55)
    _draw(h, b * band, (b + 1) * band, 0.27, 0.45, int(band * 0.34), "block", 0.45)
    _draw(h, b * band, (b + 1) * band, 0.47, 0.55, int(band * 0.42), "bead", 0.30)
    # 1: the string course - the bead-and-reel and the guilloche
    b = 1
    _draw(h, b * band, (b + 1) * band, 0.04, 0.30, int(band * 0.50), "bead", 0.45)
    _draw(h, b * band, (b + 1) * band, 0.32, 0.44, int(band * 0.50), "bead", 0.28)
    _draw(h, b * band, (b + 1) * band, 0.52, 0.94, int(band * 0.50), "bead", 0.34)
    # 2: the sill - the ogee and the drip bead
    b = 2
    _draw(h, b * band, (b + 1) * band, 0.03, 0.45, int(band * 0.70), "ogee", 0.40)
    _draw(h, b * band, (b + 1) * band, 0.47, 0.58, int(band * 0.36), "bead", 0.35)
    # 3: the capital - the Ionic volute and the Corinthian acanthus
    b = 3
    _spiral(h, b * band, (b + 1) * band, 0.03, 0.45, 0.60)
    _draw(h, b * band, (b + 1) * band, 0.50, 0.96, int(band * 0.42), "leaf", 0.48)
    # 4: the keystone and the console
    b = 4
    _draw(h, b * band, (b + 1) * band, 0.06, 0.40, int(band * 0.60), "blob", 0.50)
    _draw(h, b * band, (b + 1) * band, 0.44, 0.54, int(band * 0.40), "bead", 0.30)
    _draw(h, b * band, (b + 1) * band, 0.58, 0.94, int(band * 0.60), "leaf", 0.38)
    # 5: the base mould - the torus and the astragal
    b = 5
    _draw(h, b * band, (b + 1) * band, 0.05, 0.42, int(band * 0.80), "bead", 0.42)
    _draw(h, b * band, (b + 1) * band, 0.46, 0.58, int(band * 0.30), "block", 0.32)
    # 6: the archivolt - the roll and the fillet
    b = 6
    _draw(h, b * band, (b + 1) * band, 0.05, 0.38, int(band * 0.90), "bead", 0.40)
    _draw(h, b * band, (b + 1) * band, 0.40, 0.50, int(band * 0.90), "ogee", 0.22)
    # 7: the rail and the baluster
    b = 7
    _draw(h, b * band, (b + 1) * band, 0.08, 0.52, int(band * 0.75), "bead", 0.38)
    _draw(h, b * band, (b + 1) * band, 0.58, 0.90, int(band * 0.45), "bead", 0.26)
    # 8: the fielded panel
    b = 8
    _draw(h, b * band, (b + 1) * band, 0.10, 0.30, int(band * 0.90), "bead", 0.30)
    _draw(h, b * band, (b + 1) * band, 0.34, 0.62, int(band * 0.90), "ogee", 0.18)
    _draw(h, b * band, (b + 1) * band, 0.70, 0.92, int(band * 0.90), "bead", 0.30)
    # 9: the plain frieze - a fine tooling and a chamfered margin
    b = 9
    _draw(h, b * band, (b + 1) * band, 0.02, 0.10, int(band * 0.90), "ogee", 0.12)
    _draw(h, b * band, (b + 1) * band, 0.90, 0.98, int(band * 0.90), "ogee", 0.12)
    # the brass door frame of the keystone band
    col[4 * band:5 * band, int(size * 0.44):int(size * 0.54)] = BRASS[None, None, :]
    # ---- the granite grain and the shading
    grain = fbm(size, 260, rng, 3) - 0.5
    h = h + grain.astype(np.float32) * GRAIN
    shade = np.clip(1.0 + np.clip(h, -0.5, 0.9) * 0.62, 0.50, 1.28)[:, :, None]
    col = col * shade
    col += (grain[:, :, None] * 120.0)
    # the ambient occlusion in the crevices: where the surface is below its surroundings
    low = _blur(h, 3)
    ao = np.clip(1.0 - np.clip(low - h, 0.0, 1.0) * 1.15, 0.45, 1.0)
    col *= ao[:, :, None]
    diff = np.clip(col, 0, 255)
    normal = normal_from_height(h.astype(float), NORMAL_STRENGTH)
    rough = np.clip(0.62 - h * 0.10, 0.35, 0.85)
    save(prefix + "_diff.jpg", diff, quality=92)
    save(prefix + "_nor_gl.jpg", normal)
    save(prefix + "_rough.jpg", np.repeat((rough * 255.0)[:, :, None], 3, axis=2))
    print("  trim sheet written to", OUT)
    return prefix
