"""Flemish-bond brick: the shikumen grey-blue brick and the red band courses.

Flemish bond alternates a course of stretchers (240 x 65 mm, 250 mm pitch) with a
course of headers (65 mm visible width, 240 mm tall, 75 mm pitch) with 10 mm lime
mortar joints.  The tile is 3.00 x 1.30 m, an exact number of stretcher pitches
(12) and header pitches (40) and four bond periods, so the wall tiles seamlessly.

The joints are cut in BOTH directions: the horizontal joint between the two courses
is a real 10 mm lime joint, recessed 4 mm, and not the brick colour.  (It used to be
missing, and a wall without its horizontal joints is a flat grey plane: the albedo
standard deviation of the brick was 0.017.)
"""
import numpy as np

from . import noise
from .height import mix_rgb, rgb

TILE_W = 3.00        # metres covered by the texture
TILE_H = 1.30
STRETCHER_PITCH = 0.25
HEADER_PITCH = 0.075
HEADER_H = 0.24
STRETCHER_H = 0.065
JOINT = 0.010
JOINT_DEPTH = 0.004     # the lime joint sits 4 mm behind the brick face
PERIOD = HEADER_H + JOINT + STRETCHER_H + JOINT
HEADER_OFFSET = 0.125     # the headers sit over the stretcher joints
CHIP = 0.006              # the arris is chipped over the last 6 mm of every brick
EDGE_SOFT = 0.0015        # the joint edge is softened over 1.5 mm


def _bands(h):
    """(period index, fraction inside the period) for every pixel row."""
    v = np.arange(h, dtype=np.float32) / float(h) * (TILE_H / PERIOD)
    p = np.floor(v)
    return p.astype(np.int64), (v - p).astype(np.float32)


def _joint_field(w, h):
    """(distance to the nearest brick edge in metres, the brick column index).

    The distance is the minimum of the distance to the vertical joint inside the
    course and the distance to the horizontal joint between the two courses.
    """
    u = (np.arange(w, dtype=np.float32) / float(w) * TILE_W)[None, :]
    per, frac = _bands(h)
    per = per[:, None]
    frac = frac[:, None]
    y = frac * PERIOD
    in_header = y < HEADER_H
    ys = y - (HEADER_H + JOINT)
    in_stretcher = (ys >= 0.0) & (ys < STRETCHER_H)
    # the distance to the horizontal joint (0 inside the joint itself)
    d_h = np.where(in_header, np.minimum(y, HEADER_H - y),
                   np.where(in_stretcher, np.minimum(ys, STRETCHER_H - ys), 0.0))
    # the horizontal cell of the brick and the distance to its vertical joint
    hx = np.floor((u + HEADER_OFFSET) / HEADER_PITCH)
    hfu = ((u + HEADER_OFFSET) / HEADER_PITCH) - hx
    sx = np.floor(u / STRETCHER_PITCH)
    sfu = (u / STRETCHER_PITCH) - sx
    h_edge = np.minimum(hfu, 1.0 - hfu) * HEADER_PITCH
    s_edge = np.minimum(sfu, 1.0 - sfu) * STRETCHER_PITCH
    v_edge = np.where(in_header, h_edge, np.where(in_stretcher, s_edge, 0.0))
    edge = np.minimum(v_edge, d_h)
    col = np.where(in_header, hx, sx)
    return edge, col, per


def _brick_field(size, seed, base_hex, mortar_hex, tone=0.10, soot=0.28):
    """Return (albedo, height, rough, ao, metal) for a Flemish bond wall."""
    w, h = size
    edge, col, per = _joint_field(w, h)
    in_brick = edge > JOINT * 0.5
    # per-brick tone: a hash of the brick index and the period
    rng = np.random.default_rng(seed)
    table = rng.random(256).astype(np.float32)
    key = (col.astype(np.int64) * 7 + per * 53) % 256
    bvar = (table[key] - 0.5) * 2.0 * tone
    grain = noise.fit(noise.fbm(max(w, h), seed + 11, octaves=4, base_freq=64), w, h)
    soot_field = noise.fit(noise.fbm(max(w, h), seed + 29, octaves=3, base_freq=6), w, h)
    base = rgb(base_hex, (h, w))
    albedo = base * (1.0 + bvar[..., None] * 1.25 + grain[..., None] * 0.26)
    albedo *= (1.0 - (soot_field * soot)[..., None])
    # the lime mortar joint: lighter than the brick and recessed
    joint = np.clip((JOINT * 0.5 - edge) / EDGE_SOFT + 0.5, 0.0, 1.0)
    albedo = mix_rgb(albedo, rgb(mortar_hex, (h, w)), joint)
    # the chipped arris: the brick edge is broken over the last CHIP metres
    chip = np.clip((edge - JOINT * 0.5) / CHIP, 0.0, 1.0)
    chip = np.where(in_brick, chip, 1.0)
    nchip = noise.fit(noise.fbm(max(w, h), seed + 61, octaves=3, base_freq=90), w, h)
    chipped = (1.0 - chip) * np.clip((nchip - 0.45) * 2.4, 0.0, 1.0)
    height = (np.where(in_brick, 1.0, 0.0) - joint * (JOINT_DEPTH / 0.010)
              - chipped * 0.5 + grain * 0.12)
    rough = np.clip(0.86 - bvar * 0.5 + grain * 0.10 + joint * 0.06 - chipped * 0.1,
                    0.4, 0.99)
    # the occlusion of the joint is gentle: the mortar is LIGHTER than the
    # brick, and a deep AO in the joint would cancel the contrast of the course
    ao = np.clip(1.0 - joint * 0.18 - chipped * 0.30 - (soot_field * 0.10), 0.45, 1.0)
    return albedo, height, rough, ao, 0.0


def grey_brick(size=(2048, 888), seed=11):
    """Shikumen grey-blue brick #59626B with pale lime mortar #A8A398."""
    return _brick_field(size, seed, "#59626B", "#A8A398", 0.10, 0.28)


def red_brick(size=(2048, 888), seed=23):
    """Red band courses #8A3B2E with a warm lime mortar."""
    return _brick_field(size, seed, "#8A3B2E", "#B0A48F", 0.11, 0.22)
