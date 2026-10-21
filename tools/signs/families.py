"""The tileable PBR families of the SKYRUSH props unit.

Every family is one 1024 px texture set covering 2 m of surface (512 px/m,
ART.md §5).  The UVs of a prop part are metres divided by the tile size, so a
texture repeats without a seam and the detail density never changes with the
size of the part - the bug that made every long pole read as a wood grain.

    metal    galvanised, painted and brushed steel: spangle, hairline scratches,
             chipped paint, grime, roughness breakup
    mineral  concrete, kerb and pavement, built from the CC0 photo sets in
             game/assets/textures/ (rough_concrete), with wet patches
    panel    aluminium composite panel: 6 mm seams, rivet heads, drip streaks
    paint    painted finish: orange peel, roller streaks, chips that show the
             grey primer (a dielectric: a painted booth must not mirror the sky)
    bark     London plane bark: irregular exfoliating patches, vertical fibre

The albedo of every family is a NEUTRAL light grey: the colour of a part comes
from its vertex tint (blender/props/atlas.py), so a grey base keeps the tints
accurate.  `BASE_LINEAR` is the mean linear luminance the generator normalises
each family to; the tints in blender/props/atlas.py divide by it.

The shared helpers live in `families_base.py`, the paint and the bark in
`families_finish.py`.

    /usr/bin/python3 tools/signs/families.py
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import imwrite as IW  # noqa: E402
import surf_lib as S  # noqa: E402
from families_base import (TILE, PX_PER_M, _chips, _core_gray, _core_rgb,  # noqa: E402
                           _grime, _norm_albedo, _scratches, _seamless)
from families_finish import bark_family, paint_family  # noqa: E402

sys.path.insert(0, os.path.join(os.path.expanduser("~/m/skyrush"), "blender"))
from props import atlas  # noqa: E402

# ------------------------------------------------------------------ metal
def metal_family(seed=101):
    """Galvanised / painted steel: spangle, scratches, chips, grime.

    The albedo is a neutral light grey; the part's colour comes from its
    vertex tint.  The chips are bare metal, so they read as bright specks on
    any paint colour.
    """
    dist, ids = S.voronoi(TILE, TILE, 120, seed)         # spangle crystals (17 mm)
    rng = np.random.default_rng(seed + 1)
    crystal = rng.uniform(-0.038, 0.038, size=int(ids.max()) + 1)
    facet = crystal[ids]
    fine = S.pnoise(TILE, TILE, 160, 3, seed + 2)
    broad = S.pnoise(TILE, TILE, 9, 3, seed + 3)
    value = np.ones((TILE, TILE), dtype=np.float32)
    value += facet
    value += (fine - 0.5) * 0.110
    value += (broad - 0.5) * 0.07
    scr = _scratches(420, seed + 4, length=(0.008, 0.05), width=2)
    value += scr * 0.30
    chip = _chips(seed + 5, count=150, radius=(2.0, 7.0))
    value = np.clip(value + chip * 0.42, 0.0, 1.0)
    grime = _grime(seed + 6, cells=4, amount=0.34)
    value = np.clip(value * (1.0 - grime), 0.0, 1.0)
    albedo = _norm_albedo(value, atlas.BASE_LINEAR["metal"])
    col = np.repeat(albedo[:, :, None], 3, axis=2)

    # roughness: strong breakup (the review asks for sigma >= 0.08)
    rough = np.clip(0.34 + 0.20 * (fine - 0.5) * 2.0 + 0.12 * facet * 8.0
                    + 0.10 * grime * 5.0 + np.abs(scr) * 0.9
                    + chip * 0.25, 0.16, 0.92)
    # height: the crystal facets, the scratches and the chip edges
    edge = np.clip(1.0 - dist / (TILE / 120.0) * 2.2, 0.0, 1.0)
    height = np.clip((1.0 - edge) * 0.45 + fine * 0.30 + np.abs(scr) * 0.5
                     - chip * 0.35, 0.0, 1.0)
    return col, rough, height


# ------------------------------------------------------------------ mineral
def mineral_family(seed=201):
    """Concrete, kerb and pavement, built from the CC0 photo sets.

    The albedo keeps the photograph's luminance structure but is neutralised,
    so the vertex tint decides the colour.  The normal map is the photograph's
    own: real aggregate, formwork pits and pores.
    """
    photo = _core_rgb("rough_concrete", "diff")
    if photo is None:                      # no core set: fall back to fbm
        luma = S.pnoise(TILE, TILE, 90, 4, seed)
    else:
        luma = _seamless(photo @ np.array([0.2126, 0.7152, 0.0722], np.float32), TILE)
    luma = np.clip(luma, 0.05, 1.0)
    luma = luma / max(float(luma.mean()), 1e-6)
    fine = S.pnoise(TILE, TILE, 220, 2, seed + 1)
    luma = luma * (0.92 + 0.16 * fine)
    imperf = _core_gray("SurfaceImperfections001", "opacity")
    if imperf is not None:
        mask = _seamless(imperf, TILE)
        mask = np.clip((mask - 0.45) * 1.6, 0.0, 1.0)
        luma = luma * (1.0 - 0.18 * mask)
    else:
        mask = np.zeros((TILE, TILE), dtype=np.float32)
    luma = np.clip(luma, 0.05, 1.6)
    albedo = _norm_albedo(luma, atlas.BASE_LINEAR["mineral"])
    col = np.repeat(albedo[:, :, None], 3, axis=2)

    # the wet patches of a street after the rain: the concrete stays matte and
    # the puddles turn glossy (ART.md §1 and §5b)
    wet = np.clip((S.pnoise(TILE, TILE, 2, 3, seed + 7) - 0.58) * 3.0, 0.0, 1.0)
    wet = np.clip(wet * (0.35 + 0.65 * S.pnoise(TILE, TILE, 6, 3, seed + 8)), 0.0, 1.0)
    rough = np.clip(0.78 + 0.16 * (fine - 0.5) * 2.0 + 0.12 * mask, 0.45, 0.99)
    rough = rough * (1.0 - wet) + wet * 0.45
    photo_n = _core_rgb("rough_concrete", "nor_gl")
    if photo_n is not None:
        nrm = _seamless(photo_n, TILE)
        height = nrm[:, :, 2]
    else:
        height = fine
    height = np.clip(height * 0.75 + fine * 0.45, 0.0, 1.0)
    return col, rough, height


# ------------------------------------------------------------------ panel
def panel_family(seed=301):
    """Aluminium composite panel: 0.5 m panels, 6 mm seams, rivet heads, drips."""
    from PIL import ImageDraw
    col = np.zeros((TILE, TILE, 3), dtype=np.float32)
    grain = S.pnoise(TILE, TILE, 130, 3, seed)
    broad = S.pnoise(TILE, TILE, 7, 3, seed + 1)
    value = np.ones((TILE, TILE), dtype=np.float32)
    value += (grain - 0.5) * 0.10
    value += (broad - 0.5) * 0.06
    value = np.clip(value, 0.0, 1.0)
    img = Image.fromarray((np.clip(value, 0, 1) * 255).astype(np.uint8), "L").convert("RGB")
    d = ImageDraw.Draw(img)
    seam = max(2, int(round(0.006 * PX_PER_M)))            # 6 mm
    half = TILE // 2
    for k in (0, 1):
        d.rectangle([k * half, 0, k * half + seam - 1, TILE - 1], fill=(58, 60, 64))
        d.rectangle([0, k * half, TILE - 1, k * half + seam - 1], fill=(58, 60, 64))
    rr = max(2, int(round(0.009 * PX_PER_M)))             # 9 mm rivet head
    for gx in (0, 1):
        for gy in (0, 1):
            for px in (0.07, 0.93):
                for py in (0.07, 0.93):
                    x = gx * half + px * half
                    y = gy * half + py * half
                    d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(120, 123, 128))
                    d.ellipse([x - rr * 0.42, y - rr * 0.42, x + rr * 0.42, y + rr * 0.42],
                              fill=(74, 76, 80))
    col = np.asarray(img, dtype=np.float32) / 255.0
    # faint drip streaks below the seams
    drip = S.mask_to_array(S.streak_layer(TILE, TILE, 26, seed + 3,
                                           length=(0.05, 0.22), width=(1, 3)))
    col = np.clip(col * (1.0 - drip[:, :, None] * 0.10), 0.0, 1.0)
    grime = _grime(seed + 4, cells=4, amount=0.16)
    col = np.clip(col * (1.0 - grime[:, :, None]), 0.0, 1.0)
    albedo = _norm_albedo(col[:, :, 0], atlas.BASE_LINEAR["panel"])
    col = np.repeat(albedo[:, :, None], 3, axis=2)

    height = np.zeros((TILE, TILE), dtype=np.float32)
    height[:, :] = grain * 0.25
    for k in (0, 1):
        height[k * half:k * half + seam, :] = 0.0
        height[:, k * half:k * half + seam] = 0.0
    height = np.clip(height - drip * 0.10, 0.0, 1.0)
    rough = np.clip(0.38 + 0.14 * grain + 0.10 * drip + 0.14 * grime * 5.0,
                    0.18, 0.86)
    return col, rough, height


# ------------------------------------------------------------------ output
FAMILIES = ("metal", "mineral", "panel", "paint", "bark")

NORMAL_STRENGTH = {"metal": 1.5, "mineral": 1.5, "panel": 2.4, "paint": 0.9, "bark": 3.0}

BUILDERS = {
    "metal": metal_family,
    "mineral": mineral_family,
    "panel": panel_family,
    "paint": paint_family,
    "bark": bark_family,
}


def build(out_dir=None):
    """Write the four family texture sets into `out_dir`."""
    out_dir = out_dir or os.path.join(ROOT, "tmp", "props", "tex")
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for name in FAMILIES:
        col, rough, height = BUILDERS[name]()
        written.append(IW.save(S.to_image(col), os.path.join(out_dir, "prop_%s_diff.jpg" % name),
                                format="JPEG", quality=90))
        nrm = S.height_to_normal(height, NORMAL_STRENGTH[name])
        written.append(IW.save(nrm, os.path.join(out_dir, "prop_%s_nor_gl.jpg" % name),
                                format="JPEG", quality=82))
        # the roughness is half resolution: it is low frequency, and the
        # exporter re-encodes it as a PNG
        small = S.to_image(rough).resize((TILE // 2, TILE // 2), Image.LANCZOS)
        written.append(IW.save(small, os.path.join(out_dir, "prop_%s_rough.jpg" % name),
                                format="JPEG", quality=88))
    return written


# ------------------------------------------------------------------ LED panel
def led_panel(out_dir=None, name="chevron", cells=8, size=128):
    """The LED segment texture of a hero emissive strip (the sky-lane chevrons).

    A grid of square emitters on a dark board: the emission of the strip is
    the texture, so the strip reads as a lit LED band and not as flat colour
    (ART.md §2.3: E4 at most, for one or two hero signs).
    """
    out_dir = out_dir or os.path.join(ROOT, "tmp", "props", "tex")
    os.makedirs(out_dir, exist_ok=True)
    img = Image.new("L", (size, size), 18)
    d = ImageDraw.Draw(img)
    step = size / float(cells)
    pad = max(1, int(step * 0.18))
    for iy in range(cells):
        for ix in range(cells):
            x0 = int(ix * step) + pad
            y0 = int(iy * step) + pad
            x1 = int((ix + 1) * step) - pad
            y1 = int((iy + 1) * step) - pad
            d.rectangle([x0, y0, x1, y1], fill=255)
    arr = np.asarray(img, dtype=np.float32) / 255.0
    arr = np.asarray(Image.fromarray((arr * 255).astype(np.uint8), "L")
                     .filter(ImageFilter.GaussianBlur(0.8)), dtype=np.float32) / 255.0
    path = os.path.join(out_dir, "prop_led_%s.png" % name)
    IW.save(S.to_image(arr), path, format="PNG")
    return path

# ------------------------------------------------------------------ light pool
def light_pool(out_dir=None, name="gas", size=512, canopy_w=60.0, canopy_d=30.0,
               bays=(6, 3),
               warm=(1.0, 0.957, 0.910)):
    """The baked ground light pool of a canopy (ART.md §4).

    A soft rectangle the size of the canopy, with a hot spot under every
    downlight, fading to nothing about 2 m past the canopy edge.  The image is
    greyscale in RGB (so it can drive an emission) and carries the same
    profile in its alpha.
    """
    out_dir = out_dir or os.path.join(ROOT, "tmp", "props", "tex")
    os.makedirs(out_dir, exist_ok=True)
    pad = 2.0                                   # metres of falloff past the edge
    total_w = canopy_w + pad * 2.0
    total_d = canopy_d + pad * 2.0
    xs = (np.arange(size, dtype=np.float32) + 0.5) / size * total_w - total_w * 0.5
    ys = (np.arange(size, dtype=np.float32) + 0.5) / size * total_d - total_d * 0.5
    gx, gy = np.meshgrid(xs, ys)
    # the pool is flat under the canopy and fades out over the 2 m band that
    # lies past its edge (ART.md §4: "fading to 0 about 2 m past the edge")
    inside_x = np.clip((canopy_w * 0.5 + pad - np.abs(gx)) / pad, 0.0, 1.0)
    inside_y = np.clip((canopy_d * 0.5 + pad - np.abs(gy)) / pad, 0.0, 1.0)
    pool = inside_x * inside_y
    # the hot spot under every downlight
    hot = np.zeros((size, size), dtype=np.float32)
    nx, ny = bays
    for i in range(nx):
        for j in range(ny):
            cx = -canopy_w * 0.5 + (i + 0.5) * canopy_w / nx
            cy = -canopy_d * 0.5 + (j + 0.5) * canopy_d / ny
            d = np.sqrt((gx - cx) ** 2 + (gy - cy) ** 2)
            hot += np.clip(1.0 - d / (canopy_w / nx * 0.62), 0.0, 1.0) ** 2
    hot = np.clip(hot, 0.0, 1.0)
    profile = np.clip(pool * 0.62 + hot * 0.45, 0.0, 1.0)
    rgb = np.stack([profile * warm[0], profile * warm[1], profile * warm[2]], axis=-1)
    arr = np.concatenate([rgb, profile[:, :, None]], axis=2)
    path = os.path.join(out_dir, "prop_lightpool_%s.png" % name)
    IW.save(Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA"), path,
            format="PNG")
    return path


if __name__ == "__main__":
    for p in build() + [light_pool()]:
        print("FAMILY %s" % p)
