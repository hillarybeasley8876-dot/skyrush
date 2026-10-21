"""Granite and pale stone: the heritage blocks, the shikumen door frames, the kerbs.

The granite is the shared library scan (`granite_tile_03`) conditioned to the
dossier tone #ABAAA3 and cut into rusticated blocks 0.60 x 1.20 m with 10 mm joints.
The tile is 2.40 m, so two blocks sit across it and the block grid repeats exactly.
"""
import numpy as np

from . import library, noise
from .height import mix_rgb, rgb

TILE_M = 2.40
BLOCK_W = 1.20
BLOCK_H = 0.60
JOINT = 0.010
MEAN_HEX = "#ABAAA3"


def _block_field(w, h, seed, base_hex, joint_hex, rough_base=0.72, metal=0.0):
    """(albedo, height, rough, ao) of an ashlar wall of 1.20 x 0.60 m blocks."""
    u = (np.arange(w, dtype=np.float32) / float(w) * (TILE_M / BLOCK_W))[None, :]
    v = (np.arange(h, dtype=np.float32) / float(h) * (TILE_M / BLOCK_H))[:, None]
    col = np.floor(u)
    row = np.floor(v)
    fu = u - col
    fv = v - row
    edge_u = np.minimum(fu, 1.0 - fu) * BLOCK_W
    edge_v = np.minimum(fv, 1.0 - fv) * BLOCK_H
    edge = np.minimum(edge_u, edge_v)
    in_block = edge > JOINT * 0.5
    rng = np.random.default_rng(seed)
    tones = rng.random(256).astype(np.float32)
    key = (col.astype(np.int64) * 11 + row.astype(np.int64) * 29) % 256
    bvar = (tones[key] - 0.5) * 2.0 * 0.07
    grain = noise.fbm(max(w, h), seed + 5, octaves=4, base_freq=48)
    base = rgb(base_hex, (h, w))
    albedo = base * (1.0 + bvar[..., None] * 1.1 + grain[..., None] * 0.18)
    joint = np.clip((JOINT * 0.55 - edge) * 120.0 + 0.5, 0.0, 1.0)
    albedo = mix_rgb(albedo, rgb(joint_hex, (h, w)), joint)
    # the chamfer of the block edge
    chamfer = np.clip((edge - JOINT * 0.5) / 0.02, 0.0, 1.0)
    height = np.where(in_block, 1.0, 0.0) - joint * 0.7 - (1.0 - chamfer) * 0.25 + grain * 0.18
    rough = np.clip(rough_base - bvar * 0.4 + grain * 0.12 + joint * 0.08, 0.25, 0.98)
    ao = np.clip(1.0 - joint * 0.5 - (1.0 - chamfer) * 0.2, 0.4, 1.0)
    return albedo, height, rough, ao


def granite(size=(2048, 2048), seed=31):
    """Rusticated granite from the library scan, conditioned to #ABAAA3."""
    w, h = size
    albedo, height, rough, ao = _block_field(w, h, seed, MEAN_HEX, "#6F6E68", 0.66)
    lib = library.load("granite_tile_03", "diff", size=1024)
    if lib is not None:
        lib = library.condition(lib, MEAN_HEX)
        lib = np.asarray(lib, dtype=np.float32)
        if lib.shape[0] != h or lib.shape[1] != w:
            from PIL import Image
            img = Image.fromarray((lib * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS)
            lib = np.asarray(img).astype(np.float32) / 255.0
        # the scan provides the mineral grain; the block pattern provides the course
        albedo = albedo * (0.45 + 0.9 * lib)
        albedo = np.clip(albedo, 0.0, 1.4)
        rough = np.clip(rough - (lib.mean(axis=2) - 0.5) * 0.25, 0.2, 0.98)
    metal = 0.0
    return albedo, height, rough, ao, metal


def pale_stone(size=(2048, 2048), seed=41):
    """Carved pale stone for the shikumen door frames and pediments (#D9D2C0)."""
    w, h = size
    speck = noise.fbm(max(w, h), seed, octaves=4, base_freq=64)
    stain = noise.fbm(max(w, h), seed + 3, octaves=3, base_freq=7)
    base = rgb("#D9D2C0", (h, w))
    dark = rgb("#9E9482", (h, w))
    m = np.clip((stain - 0.5) * 1.6, 0.0, 1.0)
    albedo = mix_rgb(base, dark, m * 0.7)
    albedo *= (0.93 + 0.14 * speck[..., None])
    height = speck * 0.3
    rough = np.clip(0.78 + (speck - 0.5) * 0.16, 0.5, 0.95)
    ao = np.clip(0.95 - m * 0.2, 0.55, 1.0)
    return albedo, height, rough, ao, 0.0
