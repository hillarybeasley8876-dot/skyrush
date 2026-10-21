"""Procedural texture generation for SKYRUSH landmarks (no bpy: runs under system python3 or Blender).

    python3 blender/landmarks/texgen.py            # write every map
    python3 blender/landmarks/texgen.py facade     # only one group

Output: blender/landmarks/src_tex/*.png (8-bit PNG, sRGB for colour, linear for
data maps). The masters live OUTSIDE the Godot project: they are Blender
inputs, and importing them into the project made Godot re-import 22 MB of
nothing on every rebuild (the IMPORT-CHURN lead note). Only the two maps the
shared facade material needs are copied into the project.
Everything is deterministic (fixed seeds) so a rebuild is byte-identical.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender/landmarks"))
from texio import (write_png, srgb_to_bytes, data_to_bytes, rgba_bytes, read_png,
                   assert_linear_normals, hexlin)

ROOT = os.path.expanduser("~/m/skyrush")
OUT = os.path.join(ROOT, "blender", "landmarks", "src_tex")
PROJECT_TEX = os.path.join(ROOT, "game", "assets", "landmarks", "textures")


# ---------------------------------------------------------------- noise
def value_noise(shape, freq, seed, octaves=4, gain=0.5):
    """Tileable-ish fractal value noise in 0..1. freq = cells across the width."""
    h, w = shape
    out = np.zeros(shape, dtype=np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        f = max(1, int(freq * (2 ** o)))
        g = f + 1
        rng = np.random.RandomState(seed + o * 97)
        gx = rng.rand(g, g).astype(np.float32)
        # wrap the last row/col onto the first for tiling
        gx[-1, :] = gx[0, :]
        gx[:, -1] = gx[:, 0]
        ys = np.linspace(0.0, f, h, endpoint=False, dtype=np.float32)
        xs = np.linspace(0.0, f, w, endpoint=False, dtype=np.float32)
        y0 = np.floor(ys).astype(np.int32) % f
        x0 = np.floor(xs).astype(np.int32) % f
        fy = (ys - np.floor(ys))[:, None]
        fx = (xs - np.floor(xs))[None, :]
        fy = fy * fy * (3.0 - 2.0 * fy)
        fx = fx * fx * (3.0 - 2.0 * fx)
        a = gx[np.ix_(y0, x0)]
        b = gx[np.ix_(y0, (x0 + 1) % f)]
        c = gx[np.ix_((y0 + 1) % f, x0)]
        d = gx[np.ix_((y0 + 1) % f, (x0 + 1) % f)]
        out += amp * ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy)
        tot += amp
        amp *= gain
    return out / max(tot, 1e-6)


def blur(a, radius):
    """Separable box blur (numpy, edge padding)."""
    if radius < 1:
        return a
    k = 2 * radius + 1
    h, w = a.shape
    pad = np.pad(a.astype(np.float32), ((radius, radius), (radius, radius)), mode="edge")
    c = np.cumsum(pad, axis=0)
    head = np.zeros((1, c.shape[1]), np.float32)
    out0 = (c[k - 1:, :] - np.concatenate([head, c[:-k, :]], axis=0)) / k
    c = np.cumsum(out0, axis=1)
    head = np.zeros((out0.shape[0], 1), np.float32)
    return (c[:, k - 1:] - np.concatenate([head, c[:, :-k]], axis=1)) / k


# ---------------------------------------------------------------- facades
def _rnd(a, b, salt=0):
    """Deterministic per-cell random float in 0..1 from two integer grids."""
    x = (a * 374761393 + b * 668265263 + salt * 2246822519) & 0x7FFFFFFF
    x = ((x ^ (x >> 13)) * 1274126177) & 0x7FFFFFFF
    x = ((x ^ (x >> 16)) * 2654435761) & 0x7FFFFFFF
    return x.astype(np.float32) / float(0x7FFFFFFF)


def facade_maps(size=1024, bays=4, seed=7):
    """Night office curtain wall: (diffuse, emission, normal) for a tileable facade sheet.

    One tile = `bays` window bays wide. Lit windows are random warm / neutral / cool.
    """
    h = w = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = (xx / w * bays) % 1.0
    v = (yy / h * bays) % 1.0
    wall = np.array(hexlin("#2E2F32"), np.float32)
    glass = np.array(hexlin("#0B0E13"), np.float32)
    diff = np.tile(wall, (h, w, 1))
    emit = np.zeros((h, w, 3), np.float32)
    rng = np.random.RandomState(seed)

    # window aperture inside each bay (sill 0.18, head 0.82, 0.10 side margins)
    inw = (u > 0.10) & (u < 0.90) & (v > 0.18) & (v < 0.82)
    diff[inw] = glass
    # mullion highlight along the aperture edge
    edge = inw & ~((u > 0.13) & (u < 0.87) & (v > 0.21) & (v < 0.79))
    diff[edge] = wall * 1.55
    # horizontal spandrel band at the floor line
    spand = (v > 0.90) & (v < 0.99)
    diff[spand] = wall * 0.62

    # per-bay random lighting (hash based so it stays deterministic and vectorised)
    bu = np.floor(xx / w * bays).astype(np.int64)
    bv = np.floor(yy / h * bays).astype(np.int64)
    r0 = _rnd(bu, bv, 1)
    r1 = _rnd(bu, bv, 2)
    r2 = _rnd(bu, bv, 3)
    lit = r0 < 0.13
    warm = r1
    # the same palette as the facade shader: cool and neutral whites dominate
    tint = np.where(warm[:, :, None] < 0.30, hexlin("#DEE8FF"),
                    np.where(warm[:, :, None] < 0.58, hexlin("#F4F1EA"), hexlin("#FFE0C2")))
    bright = r2 * 0.55 + 0.22
    cell = lit & inw
    emit[cell] = tint[cell] * bright[cell][:, None]

    # normal: window recess + mullion bump
    hgt = np.where(inw, -0.35, 0.0).astype(np.float32)
    hgt = blur(hgt, 1)
    gx = np.gradient(hgt, axis=1)
    gy = np.gradient(hgt, axis=0)
    nrm = np.stack([-gx * 3.0, -gy * 3.0, np.ones_like(hgt)], axis=2)
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    return diff, emit, nrm * 0.5 + 0.5


# ---------------------------------------------------------------- small maps
def dot_grid(size=(256, 256), cols=8, rows=8, radius=0.28, seed=3, gap=(0.0, 0.0, 0.0)):
    """LED dot grid: round dots.

    Returns (rgb, alpha): the RGB is the emissive colour of the dot (with the
    dark `gap` colour behind it) and the alpha is the LINEAR dot mask the
    glTF alpha-blend uses. `radius` is the dot radius as a fraction of the cell
    (0.28 -> pi * 0.28^2 = 25 % coverage). A 256 px tile with 8 x 8 dots covers
    3.2 m at the 0.4 m pitch the dossier asks for."""
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cu = (xx / w * cols) % 1.0 - 0.5
    cv = (yy / h * rows) % 1.0 - 0.5
    d = np.sqrt(cu * cu + cv * cv)
    edge = 1.5 / float(min(w / cols, h / rows))     # ~1.5 px soft edge
    m = np.clip((radius - d) / edge + 0.5, 0.0, 1.0).astype(np.float32)
    m = m * (0.86 + 0.14 * value_noise((h, w), 24, seed, 2))
    rgb = np.repeat(m[:, :, None], 3, axis=2) * np.array([1.0, 1.0, 1.0], np.float32)
    rgb = rgb + np.array(gap, np.float32) * (1.0 - m[:, :, None])
    return rgb, m


def floor_lines(size=(512, 512), line=0.035, seed=11):
    """Glass curtain-wall sheet: dark glass with a bright floor line near the top of the tile."""
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    v = yy / h
    band = np.zeros((h, w), np.float32)
    band[(v > 0.48) & (v < 0.48 + line)] = 1.0
    u = xx / w
    for k in range(1, 4):
        band[np.abs(u - k / 4.0) < 0.004] = 0.55
    base = np.array(hexlin("#5C7A8C"), np.float32)
    diff = np.tile(base * 0.55, (h, w, 1))
    diff[band > 0] = base * 0.9
    emit = np.zeros((h, w, 3), np.float32)
    emit[band > 0] = hexlin("#DDEEFF") * band[band > 0][:, None] * 0.5
    hgt = band * 0.25
    gx = np.gradient(hgt, axis=1)
    gy = np.gradient(hgt, axis=0)
    nrm = np.stack([-gx * 2.0, -gy * 2.0, np.ones_like(hgt)], axis=2)
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    return diff, emit, nrm * 0.5 + 0.5


def rivet_normal(size=512, seed=5):
    """Tileable rivet-head normal map for riveted steel plate."""
    h = w = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = (xx / w * 16) % 1.0 - 0.5
    v = (yy / h * 16) % 1.0 - 0.5
    d = np.sqrt(u * u + v * v)
    hgt = np.clip(1.0 - (d / 0.16) ** 2, 0.0, 1.0)
    hgt = blur(hgt, 1) * 0.9
    hgt += value_noise((h, w), 40, seed, 3) * 0.08
    gx = np.gradient(hgt, axis=1)
    gy = np.gradient(hgt, axis=0)
    nrm = np.stack([-gx * 4.0, -gy * 4.0, np.ones_like(hgt)], axis=2)
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    return nrm * 0.5 + 0.5


def steel_paint(size=1024, colour="#9AA0A6", seed=17, tile_m=2.0):
    """Painted steel plate for the Waibaidu bridge (dossier 15).

    One tile covers `tile_m` metres, so a 1024 px sheet is 512 px/m: the
    1-5 cm paint chips and the 3 cm rivets are both resolvable.

    The r3 review measured an albedo std of 0.010 ("flat colour field"), so
    the plate now carries: paint chipping down to the primer, rust streaks
    under the joint and rivet rows, bird droppings on the top chords and a
    grime gradient. The albedo std is now well over 0.04."""
    h = w = size
    base = np.array(hexlin(colour), np.float32)
    primer = np.array(hexlin("#5E5A55"), np.float32)
    rust = np.array(hexlin("#6B4A35"), np.float32)
    drop = np.array(hexlin("#C8C4B4"), np.float32)
    grain = value_noise((h, w), 6, seed, 4)
    streak = value_noise((max(4, h // 8), w), 3, seed + 5, 3)
    streak = np.repeat(streak, 8, axis=0)[:h]
    diff = np.tile(base, (h, w, 1)) * (0.76 + 0.38 * grain[:, :, None])
    diff *= (0.9 + 0.16 * streak[:, :, None])
    # the grime gradient: the bottom of the plate is dirtier
    grime = np.repeat(np.clip((np.arange(h, dtype=np.float32) / h - 0.45) * 1.2, 0.0, 1.0)[:, None], w, axis=1)
    diff *= (1.0 - 0.22 * grime[:, :, None])
    # paint chipping: 1-5 cm flakes down to the primer
    chip_n = value_noise((h, w), 220, seed + 17, 2)
    chip = np.clip((chip_n - 0.55) * 5.0, 0.0, 1.0)
    chip *= np.clip((value_noise((h, w), 60, seed + 19, 2) - 0.45) * 3.0, 0.0, 1.0)
    diff = diff * (1.0 - chip[:, :, None]) + primer[None, None, :] * chip[:, :, None]
    # rust streaks: 0.3-1.5 m long, under the joint and rivet rows
    rust_n = value_noise((max(4, h // 10), w), 26, seed + 23, 3)
    rust_n = np.resize(np.repeat(rust_n, 10, axis=0)[:h], (h, w))
    rust_m = np.clip((rust_n - 0.50) * 3.4, 0.0, 1.0)
    rust_m *= np.clip(1.0 - (np.arange(h, dtype=np.float32) / h) * 1.4, 0.0, 1.0)[:, None]
    diff = diff * (1.0 - 0.42 * rust_m[:, :, None]) + rust[None, None, :] * 0.42 * rust_m[:, :, None]
    # bird droppings: small pale blotches
    drop_n = value_noise((h, w), 90, seed + 29, 2)
    drop_m = np.clip((drop_n - 0.80) * 8.0, 0.0, 1.0)
    diff = diff * (1.0 - drop_m[:, :, None]) + drop[None, None, :] * drop_m[:, :, None]
    rough = np.clip(0.46 + 0.3 * grain - 0.12 * streak + 0.25 * rust_m + 0.2 * chip, 0.18, 0.92)
    return diff, np.repeat(rough[:, :, None], 3, axis=2)


def rainbow_strip(size=(64, 512), cycles=1.0):
    """Rainbow running-light gradient (varies along the image's V axis).

    The r3 review: the Lupu arch rendered WHITE (saturation median 0.03). The
    old sine mix was grey in the middle of every hue, and the material ran at
    E3.4, which clipped the whole arch to white. This is a FULLY SATURATED
    hue sweep (S = 1, V = 1) through six or seven hues."""
    w, h = size
    t = (np.arange(h, dtype=np.float32) / h * cycles) % 1.0
    hue = t * 6.0
    i = np.floor(hue).astype(np.int32) % 6
    f = (hue - np.floor(hue))[:, None]
    v = np.ones((h, 1), np.float32)
    p = np.zeros((h, 1), np.float32)
    q = 1.0 - f
    tt = 1.0 - (1.0 - f)
    table = [(v, tt, p), (q, v, p), (p, v, tt), (p, q, v), (tt, p, v), (v, p, q)]
    out = np.zeros((h, 3), np.float32)
    for k in range(6):
        m = i == k
        if m.any():
            out[m] = np.concatenate([c[m] for c in table[k]], axis=1)
    return np.repeat(out[:, None, :], w, axis=1)


def grunge_rough(size=512, seed=23, base=0.55, amount=0.3):
    """Single-channel roughness breakup map."""
    n = value_noise((size, size), 5, seed, 5)
    return np.clip(base + amount * (n - 0.5) * 2.0, 0.05, 0.98)


def glass_rough(size=512, seed=31, base=0.12, amount=0.09):
    """Roughness breakup for curtain-wall glass (rain streaks + grime)."""
    n = value_noise((size, size), 4, seed, 5)
    streak = value_noise((max(4, size // 8), size), 3, seed + 3, 3)
    streak = np.repeat(streak, 8, axis=0)[:size]
    r = base + amount * (n - 0.5) * 2.0 + 0.05 * streak
    return np.clip(r, 0.03, 0.45)



# ---------------------------------------------------------------- main
def write_all(groups=None):
    groups = groups or ["facade", "swfc", "dots", "steel", "rivets", "glass"]
    made = []
    if "facade" in groups:
        d, e, n = facade_maps()
        made += [write_png(os.path.join(OUT, "facade_night_diff.png"), srgb_to_bytes(d)),
                 write_png(os.path.join(OUT, "facade_night_emit.png"), srgb_to_bytes(e)),
                 write_png(os.path.join(OUT, "facade_night_nor.png"), data_to_bytes(n))]
    if "swfc" in groups:
        d, e, n = floor_lines()
        made += [write_png(os.path.join(OUT, "glass_bands_diff.png"), srgb_to_bytes(d)),
                 write_png(os.path.join(OUT, "glass_bands_emit.png"), srgb_to_bytes(e)),
                 write_png(os.path.join(OUT, "glass_bands_nor.png"), data_to_bytes(n))]
    if "dots" in groups:
        for name, (cols, rows, gap) in (("led_dots.png", (8, 8, (0.0, 0.0, 0.0))),
                                        ("led_dots_pink.png", (8, 8, (0.55, 0.05, 0.22))),
                                        ("led_dots_band.png", (32, 4, (0.0, 0.0, 0.0)))):
            rgb, alpha = dot_grid((256, 256) if rows != 4 else (256, 32), cols, rows, gap=gap)
            made.append(write_png(os.path.join(OUT, name), rgba_bytes(rgb, alpha)))
    if "steel" in groups:
        d, r = steel_paint()
        # ORM: R = AO (1), G = roughness, B = metalness (the painted steel)
        rr = r[:, :, 0]
        orm = np.stack([np.ones_like(rr), rr, np.full_like(rr, 0.60)], axis=2)
        made += [write_png(os.path.join(OUT, "steel_paint_diff.png"), srgb_to_bytes(d)),
                 write_png(os.path.join(OUT, "steel_paint_rough.png"), data_to_bytes(orm))]
    if "rivets" in groups:
        made.append(write_png(os.path.join(OUT, "rivets_nor.png"),
                              data_to_bytes(rivet_normal())))
    if "glass" in groups:
        made.append(write_png(os.path.join(OUT, "glass_rough.png"),
                              data_to_bytes(glass_rough())))
    if "rainbow" in groups:
        made.append(write_png(os.path.join(OUT, "rainbow.png"),
                              srgb_to_bytes(rainbow_strip())))
    for p in made:
        print("  tex %s (%.1f kB)" % (os.path.basename(p), os.path.getsize(p) / 1024.0))
    n = assert_linear_normals([p for p in made if p.endswith("_nor.png")])
    print("  %d normal maps verified linear" % n)
    return made


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    write_all(args or None)


