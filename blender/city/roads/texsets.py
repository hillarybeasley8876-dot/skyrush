"""The texture sets of the road kit: one albedo per surface.

Every generator returns (rgb, alpha, height, rough, ao): the colour, the alpha
mask (None for an opaque surface), the height field the normal map is made of,
the roughness and the ambient occlusion.
"""
import os

import numpy as np

from city.roads.texbase import BIG, SMALL, fbm, grid


def pot(size=SMALL):
    """The white plastic planter pot: a moulded rim and soil stains on the face."""
    n = fbm(size, size, 16, 4, 131)
    fine = fbm(size, size, 64, 2, 132)
    v = 0.88 + 0.12 * n
    rgb = np.stack([v, v * 0.995, v * 0.965], axis=-1)
    # the rim: a raised band at the top of the pot
    x, y = grid(size, size)
    rim = (y < size * 0.18).astype(np.float32)
    rgb *= (1.0 - 0.10 * rim)[..., None]
    # the soil stains run down the outer face
    stain = np.clip((fbm(size, size, 10, 3, 133) - 0.58) * 2.4, 0.0, 1.0)
    stain *= np.clip(y / size, 0.0, 1.0)
    rgb *= (1.0 - 0.40 * stain[..., None])
    height = (0.5 + 0.5 * n) * 0.25 + rim * 0.75
    rough = np.clip(0.42 + 0.22 * n + 0.25 * stain, 0.05, 1.0)
    ao = 1.0 - 0.18 * stain
    return rgb, None, height, rough, ao


def soil(size=SMALL):
    """Planter soil: dark compost with bark chips."""
    n = fbm(size, size, 30, 4, 141)
    chip = fbm(size, size, 80, 2, 142)
    base = np.array([0.20, 0.155, 0.115], dtype=np.float32)
    rgb = np.broadcast_to(base, (size, size, 3)).copy()
    rgb *= (0.55 + 0.9 * n)[..., None]
    rgb[chip > 0.74] = np.array([0.34, 0.26, 0.17], dtype=np.float32)
    height = 0.35 + 0.65 * n
    rough = np.clip(0.85 + 0.12 * n, 0.05, 1.0)
    return rgb, None, height, rough, 0.75 + 0.25 * n


def foliage(base, accent, accent_ratio, seed, size=SMALL):
    """A cluster of leaf blobs with bright bracts: the alpha mask is the coverage.

    The colours are baked into the albedo (a magenta bract cannot come from a
    grey factor), so this material keeps a white baseColorFactor on purpose.
    """
    n = fbm(size, size, 16, 4, seed)
    leaf = fbm(size, size, 48, 3, seed + 5)
    base_c = np.array(base, dtype=np.float32)
    acc_c = np.array(accent, dtype=np.float32)
    rgb = np.broadcast_to(base_c, (size, size, 3)).copy()
    rgb *= (0.70 + 0.55 * leaf)[..., None]
    alpha = np.zeros((size, size), dtype=np.float32)
    height = np.zeros((size, size), dtype=np.float32)
    rng = np.random.default_rng(seed + 3)
    for _ in range(90):
        cx = int(rng.integers(0, size))
        cy = int(rng.integers(0, size))
        r = int(rng.integers(6, 26))
        yy, xx = np.mgrid[-r:r + 1, -r:r + 1]
        d = np.sqrt(xx * xx + yy * yy) / float(r)
        m = np.clip(1.0 - d, 0.0, 1.0) ** 1.6
        ys = (np.arange(cy - r, cy + r + 1)) % size
        xs = (np.arange(cx - r, cx + r + 1)) % size
        sub = rgb[np.ix_(ys, xs)]
        nl = n[np.ix_(ys, xs)]
        ll = leaf[np.ix_(ys, xs)]
        pick = (rng.random(m.shape) < accent_ratio) & (m > 0.05)
        sub[pick] = acc_c[None, :] * (0.75 + 0.50 * nl[pick])[:, None]
        sub[~pick] = base_c[None, :] * (0.60 + 0.60 * ll[~pick])[:, None]
        rgb[np.ix_(ys, xs)] = sub
        alpha[np.ix_(ys, xs)] = np.maximum(alpha[np.ix_(ys, xs)], m)
        height[np.ix_(ys, xs)] = np.maximum(height[np.ix_(ys, xs)], m * 0.8)
    rough = np.clip(0.68 + 0.20 * leaf, 0.05, 1.0)
    return rgb, np.clip(alpha * 1.6, 0.0, 1.0), height, rough, 0.6 + 0.4 * alpha


def ivy(size=SMALL):
    """Virginia creeper on a pier: dark green leaves over vertical strands."""
    n = fbm(size, size, 10, 4, 31)
    leaf = fbm(size, size, 40, 3, 32)
    strand = fbm(size, size, 6, 3, 33)
    green = np.array([0.16, 0.34, 0.14], dtype=np.float32)
    rgb = np.broadcast_to(green, (size, size, 3)).copy()
    rgb *= (0.55 + 0.95 * leaf)[..., None]
    rgb = np.clip(rgb + (0.12 * n)[..., None] * np.array([0.4, 0.9, 0.3]), 0.0, 1.0)
    rgb *= (0.70 + 0.45 * strand)[..., None]
    # the ivy thins out at the top: the alpha mask ends in an organic edge
    x, y = grid(size, size)
    edge = np.clip((fbm(size, size, 5, 3, 34) - 0.30) * 2.2, 0.0, 1.0)
    alpha = np.clip(edge * (1.0 - 0.55 * (y / size)) * 1.4, 0.0, 1.0)
    height = 0.4 + 0.6 * leaf
    rough = np.clip(0.72 + 0.20 * n, 0.05, 1.0)
    return rgb, alpha, height, rough, 0.55 + 0.45 * alpha


def steel(size=BIG):
    """Painted structural steel: plate seams, bolt rows, chipped paint, rust."""
    n = fbm(size, size, 12, 4, 41)
    grain = fbm(size, size, 90, 2, 42)
    x, y = grid(size, size)
    seam = (np.abs((y % (size // 4)) - 0.0) < 1.5).astype(np.float32)
    rivet = np.zeros((size, size), dtype=np.float32)
    step = max(6, size // 24)
    for ry in range(0, size, size // 8):
        for rx in range(step, size, step):
            yy, xx = np.mgrid[ry - 2:ry + 3, rx - 2:rx + 3]
            d = np.sqrt((yy - ry) ** 2 + (xx - rx) ** 2)
            rivet[yy % size, xx % size] = np.maximum(rivet[yy % size, xx % size],
                                                    (d <= 2.2).astype(np.float32))
    base = np.array([0.60, 0.64, 0.68], dtype=np.float32)
    rgb = np.broadcast_to(base, (size, size, 3)).copy()
    rgb *= (0.86 + 0.22 * grain)[..., None]
    rgb *= (1.0 - 0.28 * seam)[..., None]
    rgb += (rivet * 0.10)[..., None]
    rust = np.clip((fbm(size, size, 8, 4, 43) - 0.58) * 3.0, 0.0, 1.0) * np.clip(y / size, 0.0, 1.0)
    rgb = rgb * (1.0 - rust[..., None] * 0.55) + rust[..., None] * np.array([0.32, 0.16, 0.08])
    # the paint is chipped: bare metal shows through
    chip = np.clip((fbm(size, size, 22, 3, 44) - 0.70) * 5.0, 0.0, 1.0)
    rgb = rgb * (1.0 - chip[..., None]) + chip[..., None] * np.array([0.42, 0.43, 0.45])
    height = 0.5 + 0.35 * grain - 0.35 * seam + 0.5 * rivet
    rough = np.clip(0.36 + 0.30 * rust + 0.20 * chip + 0.10 * grain, 0.05, 1.0)
    ao = 1.0 - 0.30 * seam - 0.20 * rust
    return rgb, None, height, rough, ao


def joint(size=SMALL):
    """The expansion joint: the finger teeth of a comb and the rubber strip."""
    n = fbm(size, size, 24, 3, 151)
    x, y = grid(size, size)
    period = size // 4
    tooth = ((y % period) < period * 0.42).astype(np.float32)
    base = np.array([0.30, 0.31, 0.33], dtype=np.float32)
    rgb = np.broadcast_to(base, (size, size, 3)).copy()
    rgb *= (0.85 + 0.30 * n)[..., None]
    # the steel fingers catch the light
    rgb += (tooth * 0.22)[..., None]
    # the rubber strip in the middle of the joint
    strip = (np.abs(y - size * 0.5) < size * 0.06).astype(np.float32)
    rgb *= (1.0 - 0.65 * strip)[..., None]
    height = 0.35 + 0.5 * tooth - 0.6 * strip
    rough = np.clip(0.55 - 0.20 * tooth + 0.30 * strip + 0.10 * n, 0.05, 1.0)
    return rgb, None, height, rough, 1.0 - 0.45 * strip


def enamel(w=BIG, h=BIG // 2):
    """The tunnel wall: white enamel panels with recessed joints and grime.

    The map covers 1.2 m along the tunnel and 0.6 m up, so the panel joints sit
    every 1.2 m across and every 0.6 m up (dossier §4).
    """
    n = fbm(h, w, 16, 4, 51)
    fine = fbm(h, w, 64, 2, 53)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    joint_x = ((xx < 2.0) | (xx > w - 3.0)).astype(np.float32)
    joint_y = (np.abs((yy % (h // 2)) - 0.0) < 2.0).astype(np.float32)
    joint = np.maximum(joint_x, joint_y)
    base = np.array([0.90, 0.92, 0.93], dtype=np.float32)
    rgb = np.broadcast_to(base, (h, w, 3)).copy()
    rgb *= (0.93 + 0.10 * n)[..., None]
    rgb *= (1.0 - 0.30 * joint)[..., None]
    grime = np.clip((fbm(h, w, 6, 3, 52) - 0.55) * 2.2, 0.0, 1.0) * np.clip(yy / h, 0.0, 1.0)
    rgb = rgb * (1.0 - 0.38 * grime[..., None])
    rgb *= (0.97 + 0.06 * fine)[..., None]
    height = 0.75 - 0.75 * joint + 0.08 * n
    rough = np.clip(0.30 + 0.25 * grime + 0.10 * fine, 0.05, 1.0)
    return rgb, None, height, rough, 1.0 - 0.35 * joint - 0.20 * grime


def dark(w=SMALL, h=SMALL):
    """The upper tunnel wall: dark concrete with the stains of the road below."""
    n = fbm(h, w, 14, 4, 61)
    fine = fbm(h, w, 70, 2, 62)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    base = np.array([0.34, 0.35, 0.37], dtype=np.float32)
    rgb = np.broadcast_to(base, (h, w, 3)).copy()
    rgb *= (0.80 + 0.40 * n)[..., None]
    streak = np.clip((fbm(h, w, 8, 3, 63) - 0.50) * 2.0, 0.0, 1.0) * np.clip(1.0 - yy / h, 0.0, 1.0)
    rgb = rgb * (1.0 - 0.45 * streak[..., None])
    rgb *= (0.94 + 0.12 * fine)[..., None]
    height = 0.5 + 0.4 * n + 0.1 * fine
    rough = np.clip(0.78 + 0.15 * n + 0.10 * streak, 0.05, 1.0)
    return rgb, None, height, rough, 1.0 - 0.30 * streak


def stripe(w=SMALL, h=SMALL // 2):
    """The 0.3 m colour stripe of the tunnel wall (dossier §4)."""
    n = fbm(h, w, 20, 3, 71)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    base = np.array([0.17, 0.42, 0.85], dtype=np.float32)
    rgb = np.broadcast_to(base, (h, w, 3)).copy()
    rgb *= (0.88 + 0.22 * n)[..., None]
    # the stripe is chipped at its lower edge
    edge = (yy > h * 0.72).astype(np.float32)
    rgb *= (1.0 - 0.35 * edge)[..., None]
    height = 0.6 - 0.4 * edge + 0.1 * n
    rough = np.clip(0.36 + 0.22 * n, 0.05, 1.0)
    return rgb, None, height, rough, 1.0 - 0.25 * edge


def row(w=2048, h=256):
    """The planted strip on the parapet: fifteen pots over nine metres.

    The band is the far LOD of the planter row: from 80 m the row reads as a
    continuous white band with green and magenta plants on top of it. The
    canvas covers 9.3 m along the parapet and 0.22 m up.
    """
    slots = 15
    slot_w = w / slots
    leaf = fbm(h, w, 48, 3, 92)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # the top of the plants is irregular: every plant is a little different
    top = 0.58 + 0.42 * fbm(1, w, 30, 3, 93)[0][None, :]
    body = np.clip((top - yy / float(h)) * 7.0, 0.0, 1.0)
    base = np.broadcast_to(np.array([0.16, 0.31, 0.13], np.float32), (h, w, 3)).copy()
    base *= (0.66 + 0.62 * leaf)[..., None]
    for i in range(slots):
        magenta = i < 10
        col = np.array([0.86, 0.14, 0.44] if magenta else [0.64, 0.72, 0.20], np.float32)
        x0 = int(round(i * slot_w))
        x1 = int(round((i + 1) * slot_w))
        xs = np.arange(x0, x1)
        ys = np.arange(h)
        sub = base[np.ix_(ys, xs)]
        ll = leaf[np.ix_(ys, xs)]
        strength = 0.70 if magenta else 0.38
        mix = (0.10 + 0.60 * ll) * strength
        sub = sub * (1.0 - mix[..., None] * 0.85) + col * (mix[..., None] * 0.85)
        base[np.ix_(ys, xs)] = sub
    # the white pot below the plants
    pot_top = h * 0.34
    pot = np.clip((pot_top - yy) / (h * 0.10), 0.0, 1.0)
    base = base * (1.0 - pot[..., None]) + 0.88 * pot[..., None]
    # the plants stand on the pot: the lower edge of the green is cut
    base *= (0.25 + 0.75 * body)[..., None]
    for i in range(1, slots):
        x = int(round(i * slot_w))
        base[:, max(0, x - 2):x + 2] *= 0.45
    height = 0.4 + 0.6 * body
    rough = np.clip(0.70 + 0.2 * leaf, 0.05, 1.0)
    return base, None, height, rough, 0.7 + 0.3 * body


# --- the shared normal and ORM maps -----------------------------------------

LIBRARY_TACTILE = os.path.expanduser("~/m/skyrush/game/assets/textures/TactilePaving003")


def _load_gray(path, w, h):
    """A library image as a grayscale array (the pixels stay in Blender's order)."""
    import bpy
    img = bpy.data.images.load(path, check_existing=False)
    img.scale(w, h)
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    arr = px.reshape(h, w, 4)
    return arr[..., 0] * 0.30 + arr[..., 1] * 0.59 + arr[..., 2] * 0.11


def _load_rgb(path, w, h):
    """A library image as an RGB array (the pixels stay in Blender's order)."""
    import bpy
    img = bpy.data.images.load(path, check_existing=False)
    img.scale(w, h)
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[..., :3]


def tactile(w=SMALL, h=SMALL):
    """The tactile paving strip: the CC0 library maps, neutral and re-tiled."""
    diff = _load_rgb(os.path.join(LIBRARY_TACTILE, "TactilePaving003_diff.jpg"), w, h)
    nor = _load_gray(os.path.join(LIBRARY_TACTILE, "TactilePaving003_nor_gl.jpg"), w, h)
    rough = _load_gray(os.path.join(LIBRARY_TACTILE, "TactilePaving003_rough.jpg"), w, h)
    grey = diff.mean(axis=-1)
    rgb = np.repeat(grey[..., None], 3, axis=-1)
    height = 0.5 + 0.5 * nor
    return rgb, None, height, np.clip(rough, 0.05, 1.0), 0.75 + 0.25 * (1.0 - rough)
