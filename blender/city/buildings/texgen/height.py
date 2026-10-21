"""Height -> normal map conversion and ORM packing for the building texture set."""
import numpy as np


def normal_from_height(height, strength=1.0):
    """(h, w) float height -> (h, w, 3) uint8 OpenGL-style tangent normal map."""
    h = height.astype(np.float32)
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nz = np.ones_like(h)
    n = np.stack((-dx * strength, -dy * strength, nz), axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return np.clip(n * 0.5 + 0.5, 0, 1)


def orm_pack(ao, rough, metal=0.0):
    """(h, w) float arrays -> (h, w, 3) uint8 ORM texture (R ao, G rough, B metal)."""
    ao = np.clip(np.broadcast_to(ao, rough.shape).astype(np.float32), 0.0, 1.0)
    rough = np.clip(rough, 0.0, 1.0)
    metal = np.clip(np.broadcast_to(np.float32(metal), rough.shape), 0.0, 1.0)
    out = np.stack((ao, rough, metal), axis=-1)
    return np.clip(out * 255.0 + 0.5, 0, 255).astype(np.uint8)


def mix_rgb(base, other, mask):
    """base (h, w, 3) float + other (h, w, 3) float, mask (h, w) float -> mixed float rgb."""
    if mask.ndim != 2:
        raise ValueError("mix_rgb: mask must be (h, w), got %r" % (mask.shape,))
    m = mask[..., None]
    return base * (1.0 - m) + other * m


def rgb(base_hex, shape):
    """hex string -> (h, w, 3) float linear array filled with that colour."""
    from . import noise
    c = noise.hex_to_srgb(base_hex)
    return np.ones((shape[0], shape[1], 3), dtype=np.float32) * c[None, None, :]
