"""The baked facade wash of the Bund (bund unit).

The pooled uplights fade out at 60-80 m (the light budget of the art dossier 3.4), so
beyond that the row would go grey. The far field is carried by a light map baked here
in metres: every uplight of a building is accumulated with the cosine of the incidence
and the inverse square of the distance, inside a 45 deg cone, and the result is written
into one atlas that the wash cards of the facades sample.

The bake follows the physics the art dossier 3.4 gives: a lamp 1 m off the wall aimed
80 deg up reaches the wall from 1.6 m, its axis lands at 5.7 m, and the pools of the
5 m spacing close at about 6 m - so the scallops live in the first few metres and the
wash is continuous above them, falling off with the distance.

The response is shaped so the base is the brightest band of the facade and the level at
25 m is about 35 % of it (dossier 5.4: the base and the crown are the brightest parts
of the elevation), and a cornice grazer lifts the band under the main cornice and the
attic to 1.35x the mid facade.
"""
import math

import numpy as np

from . import elev

PPM = 4.0               # pixels per metre (0.25 m per pixel)
GUTTER = 2              # the empty pixels around a cell, so the atlas never bleeds
COS_CONE = math.cos(math.radians(45.0))   # the lamp's cone (art dossier 3.4)
COS_EDGE = math.cos(math.radians(50.0))
LAMP_OUT = 1.0          # the lamp stands 1 m off the wall
LAMP_Z = 0.6            # ... at this height
PITCH = math.radians(80.0)
AXIS = np.array([-math.cos(PITCH), 0.0, math.sin(PITCH)])
BASE_Z = 2.0            # the level the response curve is normalised on
FAR_Z = 25.0            # the level that has to keep 35 % of the base
SHADOW = 0.4            # the shadow under a cornice
SHADOW_H = 0.8          # ... over this height
BAND = 1.80             # the cornice grazer, against the mid facade
BAND_H = 2.5            # ... over this height under the main cornice
FOOT = 0.70             # the light that bounces off the pavement
FOOT_Z = 1.0            # ... at this height
SCALLOP_H = 9.0         # the pools close at this height
FOOT_W = 1.2            # ... over this width


def _cell_px(s):
    """The pixel size of one cell (the facade's extent in the atlas)."""
    e = elev.elevation(s)
    w = max(1, int(round(e["width"] * PPM)))
    h = max(1, int(round(e["top"] * PPM)))
    return w, h, e


def _layout(specs):
    """Shelf-pack the cells into the atlas; returns (atlas_w, atlas_h, cells)."""
    cells = []
    for s in specs:
        w, h, e = _cell_px(s)
        cells.append({"spec": s, "w": w, "h": h, "e": e})
    width = max(c["w"] for c in cells) + 2 * GUTTER
    area = sum((c["w"] + 2 * GUTTER) * (c["h"] + 2 * GUTTER) for c in cells)
    atlas_w = 256
    while atlas_w < width or atlas_w * atlas_w < area * 1.15:
        atlas_w *= 2
    x, y, shelf = GUTTER, GUTTER, 0
    for c in cells:
        if x + c["w"] + GUTTER > atlas_w:
            x = GUTTER
            y += shelf + GUTTER
            shelf = 0
        c["x"] = x
        c["y"] = y
        x += c["w"] + GUTTER
        shelf = max(shelf, c["h"])
    atlas_h = 256
    while atlas_h < y + shelf + GUTTER:
        atlas_h *= 2
    return atlas_w, atlas_h, cells


def _raw_light(s, e):
    """The raw light of one facade: E = cos(incidence) / d^2 inside the lamp's cone.

    The lamp stands 1 m off the wall, so the cosine of the incidence is 1/d and the
    irradiance falls off with the cube of the distance - the pool of one lamp on the
    wall is four times as bright as the light of four lamps."""
    w, h = e["width"], e["top"]
    px_w = max(1, int(round(w * PPM)))
    px_h = max(1, int(round(h * PPM)))
    ys = -w * 0.5 + (np.arange(px_w) + 0.5) / PPM
    zs = (np.arange(px_h) + 0.5) / PPM
    grid_y, grid_z = np.meshgrid(ys, zs)
    out = np.zeros_like(grid_y)
    for (ly, lz) in elev.uplight_layout(s):
        vx = -LAMP_OUT
        vy = grid_y - ly
        vz = grid_z - lz
        d2 = vx * vx + vy * vy + vz * vz
        d = np.sqrt(d2)
        cos_t = (vx * AXIS[0] + vz * AXIS[2]) / np.maximum(d, 1e-6)
        t = np.clip((cos_t - COS_EDGE) / max(1e-6, COS_CONE - COS_EDGE), 0.0, 1.0)
        cone = t * t * (3.0 - 2.0 * t)
        # the cosine of the incidence on the wall (the lamp is in front of it)
        cos_inc = np.maximum(-vx, 0.0) / np.maximum(d, 1e-6)
        out += cos_inc * cone / np.maximum(d2, 1e-6)
    return ys, zs, out


def _row_median(field, zs, z):
    """The median of the field at the height z (the response curve's anchors)."""
    k = int(np.argmin(np.abs(zs - z)))
    row = field[k]
    return float(np.median(row)) if row.size else 0.0


def _shape(s, e, field, zs):
    """The response curve, the cornice grazer and the shadow lines.

    The falloff is shaped on the envelope (the median of each row) so the scallops of
    the individual pools keep their contrast, and the envelope is compressed so the
    level at 25 m keeps about 35 % of the base (dossier 5.4)."""
    base = _row_median(field, zs, BASE_Z)
    far = _row_median(field, zs, min(FAR_Z, e["top"] - 1.0))
    if base <= 1e-9:
        return np.zeros_like(field)
    ratio = max(1e-6, far / base)
    p = min(0.9, max(0.12, math.log(0.35) / math.log(ratio)))
    env = np.median(field, axis=1, keepdims=True)
    z = np.broadcast_to(zs[:, None], field.shape)
    # the scallops of the pools only live in the first few metres: above that the wash
    # is continuous, or the row would read as a picket fence of vertical spikes
    decay = np.clip(1.0 - z / SCALLOP_H, 0.0, 1.0) ** 1.5
    scallop = 1.0 + (field / np.maximum(env, 1e-12) - 1.0) * decay
    out = np.power(np.clip(env / base, 0.0, 8.0), p) * scallop
    # the light that bounces off the pavement fills the foot of the wall: the lamps
    # stand 0.6 m up and are aimed at the sky, so their cone only reaches the stone
    # from 1.6 m and the lowest metres are lit by the spill and not by the cone
    foot = FOOT * np.exp(-(((z - FOOT_Z) / FOOT_W) ** 2))
    out = np.maximum(out, foot)
    # the mid facade: the level the crown band has to beat
    mid_rows = (z > e["cornice"] * 0.4) & (z < e["cornice"] * 0.6)
    mid = float(np.median(out[mid_rows])) if mid_rows.any() else 0.4
    # the cornice grazer: the 2.5 m under the main cornice
    band = (z > e["cornice"] - BAND_H) & (z <= e["cornice"])
    out = np.where(band, np.maximum(out, BAND * mid), out)
    # the attic storey: the brightest band of the elevation
    z0 = e["cornice"] + e["cornice_h"]
    if e["attic_top"] > z0 + 0.1:
        attic = z > z0
        ramp = 1.0 + 0.30 * np.clip((z - z0) / (e["attic_top"] - z0), 0.0, 1.0)
        out = np.where(attic, np.maximum(out, BAND * mid * ramp), out)
    # the shadow lines under the cornices and the string courses
    for zs_line in list(e["strings"]) + [e["cornice"]]:
        shadow = (z > zs_line - SHADOW_H) & (z <= zs_line)
        out = np.where(shadow, out * SHADOW, out)
    return out


def _encode(field):
    """The intensity as an sRGB grey (the shader multiplies it with the lamp colour)."""
    v = np.clip(field, 0.0, 1.0) ** (1.0 / 2.2)
    return np.repeat((v * 255.0)[:, :, None], 3, axis=2)


def bake(specs, path="wash_atlas.png"):
    """Bake the facade wash of every building into one atlas; returns the cell table."""
    from . import texbase
    atlas_w, atlas_h, cells = _layout(specs)
    atlas = np.zeros((atlas_h, atlas_w, 3), dtype=np.float32)
    for c in cells:
        s, e = c["spec"], c["e"]
        _gy, gz, raw = _raw_light(s, e)
        field = _shape(s, e, raw, gz)
        patch = _encode(field)
        y0, x0 = c["y"], c["x"]
        atlas[y0:y0 + c["h"], x0:x0 + c["w"]] = patch
    texbase.save_png(path, atlas)
    table = {c["spec"]["node"]: {"u0": c["x"] / atlas_w,
                                 "u1": (c["x"] + c["w"]) / atlas_w,
                                 "v0": 1.0 - (c["y"] + c["h"]) / atlas_h,
                                 "v1": 1.0 - c["y"] / atlas_h,
                                 "w": c["w"], "h": c["h"], "atlas": (atlas_w, atlas_h)}
              for c in cells}
    texbase.save_json("wash_atlas.json", table)
    print("  wash atlas %dx%d -> %s" % (atlas_w, atlas_h, texbase.OUT))
    return table
