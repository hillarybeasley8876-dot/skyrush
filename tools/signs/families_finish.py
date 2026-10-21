"""The paint and bark families of the props unit (unit: props).

`paint` is a painted finish: orange peel, roller bands and chips that show the
grey primer (a dielectric, so a painted booth keeps its value under a canopy
instead of mirroring the night sky).

`bark` is the London plane trunk: irregular exfoliating plates of 5-30 cm, a
domain warp, a soft 1-2 cm transition with a thin peeled rim and a vertical
fibre in the normal map.

    /usr/bin/python3 tools/signs/families_finish.py
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import surf_lib as S  # noqa: E402
from families_base import (_chips_irregular, _grime, _norm_albedo, _scratches,
                           _voronoi_warped)  # noqa: E402

sys.path.insert(0, os.path.join(os.path.expanduser("~/m/skyrush"), "blender"))
from props import atlas  # noqa: E402

TILE = 1024

# ------------------------------------------------------------------ paint
def paint_family(seed=501):
    """A painted finish: orange peel, roller streaks and chips of grey primer.

    The paint is a DIELECTRIC (the material has metallic 0.0), so a white booth
    keeps its value under a canopy instead of mirroring the night sky.  The
    chips are 45 % of the base value: on a white paint they read as the grey
    primer of the sheet metal underneath.
    """
    peel = S.pnoise(TILE, TILE, 190, 2, seed)
    broad = S.pnoise(TILE, TILE, 6, 3, seed + 1)
    # the roller leaves faint vertical bands
    rng = np.random.default_rng(seed + 9)
    bands = rng.random(64).astype(np.float32)
    bands = np.convolve(np.concatenate([bands, bands, bands]), np.ones(9) / 9.0,
                        mode="same")[64:128]
    roller = np.repeat(np.tile(bands, TILE // 64)[None, :], TILE, axis=0)
    roller = roller * (0.85 + 0.30 * S.pnoise(TILE, TILE, 3, 2, seed + 2))
    value = np.ones((TILE, TILE), dtype=np.float32)
    value += (peel - 0.5) * 0.070
    value += (broad - 0.5) * 0.075
    value += (roller - 0.5) * 0.060
    scr = _scratches(160, seed + 3, length=(0.02, 0.12), width=2)
    value += scr * 0.10
    # the chips: small patches where the paint has come off
    chip = _chips_irregular(seed + 4, count=70, radius=(3.0, 14.0))
    chip = np.clip(S.blur(chip, 0.8) * 1.9, 0.0, 1.0)
    value = np.clip(value * (1.0 - chip * 0.55), 0.0, 1.0)
    grime = _grime(seed + 5, cells=3, amount=0.20)
    value = np.clip(value * (1.0 - grime), 0.0, 1.0)
    albedo = _norm_albedo(value, atlas.BASE_LINEAR["paint"])
    col = np.repeat(albedo[:, :, None], 3, axis=2)

    rough = np.clip(0.40 + 0.10 * (peel - 0.5) * 2.0 + 0.10 * chip
                    + np.abs(scr) * 0.5 + grime * 2.0, 0.26, 0.82)
    height = np.clip(peel * 0.35 + (1.0 - chip) * 0.0 + chip * 0.25
                     + np.abs(scr) * 0.4, 0.0, 1.0)
    return col, rough, height


# ------------------------------------------------------------------ bark
def bark_family(seed=401):
    """London plane bark: irregular exfoliating plates, not camouflage.

    The plates are 5-30 cm across and come in three colours (cream, olive,
    grey); the border between two plates is a soft 1-2 cm transition with a
    thin peeled rim, and a vertical fibre runs over the whole trunk.
    """
    dist, second, ids = _voronoi_warped(22, seed, strength=0.55, jitter=0.80)
    palette = np.array([[0.81, 0.78, 0.66],   # cream  #CFC7A8
                         [0.55, 0.53, 0.41],   # olive  #7D7A5A
                         [0.62, 0.62, 0.57]],  # grey   #9A9A8E
                        dtype=np.float32)
    rng = np.random.default_rng(seed + 2)
    pick = rng.integers(0, 3, size=int(ids.max()) + 1).astype(np.int32)
    tone = 0.86 + 0.28 * rng.random(size=int(ids.max()) + 1).astype(np.float32)
    col = palette[pick[ids]] * tone[ids][:, :, None]
    # the border: the gap between the nearest and the second nearest seed
    edge = np.clip((second - dist) / max(float(np.percentile(second - dist, 88)), 1e-4),
                   0.0, 1.0)
    # the plates are slightly domed, the rim between them is a thin peeled edge
    dome = np.clip(1.0 - (dist / (TILE / 11.0)) ** 2, 0.0, 1.0)
    col = np.clip(col * (0.88 + 0.16 * dome)[:, :, None], 0.0, 1.0)
    rim = np.clip((1.0 - edge) * 6.0, 0.0, 1.0)
    col = np.clip(col * (1.0 - 0.16 * rim[:, :, None]) + 0.08 * rim[:, :, None],
                   0.0, 1.0)
    # the vertical fibre of the trunk: fine in u, stretched along v
    fibre = S.pnoise(TILE, TILE, 240, 2, seed + 4)
    col = np.clip(col * (0.92 + 0.16 * fibre)[:, :, None], 0.0, 1.0)
    rough = np.clip(0.84 + 0.10 * fibre + 0.08 * (1.0 - edge), 0.6, 0.99)
    height = np.clip(dome * 0.55 + fibre * 0.30 - rim * 0.35, 0.0, 1.0)
    return col, rough, height
