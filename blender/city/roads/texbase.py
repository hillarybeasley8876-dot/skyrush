"""The low level helpers of the road texture generator.

Tileable value noise, the normal and ORM packing and the image writer. The
images are written with the float buffer as it is (the image is not colour
managed), so the copy the glTF exporter makes is byte identical.
"""
import os

import numpy as np

# the pixel size of the small and the big maps
SMALL = 512
BIG = 1024

# the ORM packing: R = ambient occlusion, G = roughness, B = metallic
ORM_R = 0
ORM_G = 1
ORM_B = 2


def fbm(h, w, cells, octaves, seed, gain=0.5):
    """Tileable fractal noise in [0, 1]."""
    out = np.zeros((h, w), dtype=np.float32)
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        out += amp * _noise(h, w, cells * (2 ** o), seed + o * 17)
        total += amp
        amp *= gain
    return out / max(total, 1e-6)


def _noise(h, w, cells, seed):
    """Tileable value noise in [0, 1]."""
    rng = np.random.default_rng(seed)
    g = rng.random((cells, cells)).astype(np.float32)

    def axis(n):
        t = np.linspace(0.0, float(cells), n, endpoint=False)
        i = np.floor(t).astype(int)
        f = t - i
        u = f * f * (3.0 - 2.0 * f)
        return i % cells, (i + 1) % cells, u

    y0, y1, uy = axis(h)
    x0, x1, ux = axis(w)
    a = g[np.ix_(y0, x0)]
    b = g[np.ix_(y0, x1)]
    c = g[np.ix_(y1, x0)]
    d = g[np.ix_(y1, x1)]
    top = a * (1.0 - ux)[None, :] + b * ux[None, :]
    bot = c * (1.0 - ux)[None, :] + d * ux[None, :]
    return top * (1.0 - uy)[:, None] + bot * uy[:, None]


def grid(size, step):
    """The coordinate arrays of a repeated cell of `step` pixels."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    return x, y


def normal_from_height(height, strength=2.0):
    """A tangent-space normal map from a height field in [0, 1]."""
    h = height.astype(np.float32)
    dx = np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)
    dy = np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)
    n = np.stack((-dx * strength, -dy * strength, np.ones_like(h)), axis=-1)
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
    return n * 0.5 + 0.5


def orm_pack(ao, rough, metal):
    """The ORM image: R = ambient occlusion, G = roughness, B = metallic."""
    out = np.zeros(ao.shape + (4,), dtype=np.float32)
    out[..., ORM_R] = np.clip(ao, 0.0, 1.0)
    out[..., ORM_G] = np.clip(rough, 0.0, 1.0)
    out[..., ORM_B] = np.clip(metal, 0.0, 1.0)
    out[..., 3] = 1.0
    return out


def srgb(rgb):
    """Linear values to sRGB bytes (the images are stored as sRGB)."""
    c = np.clip(rgb, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def write(path, rgb, alpha=None):
    """Write an sRGB albedo or a data map to an image file; returns the path.

    The file is written as the float buffer holds it (the image is not colour
    managed), so the exported copy in the shared texture folder is identical.
    """
    import bpy
    h, w = rgb.shape[:2]
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[..., :3] = np.clip(rgb[..., :3], 0.0, 1.0)
    if alpha is not None:
        rgba[..., 3] = np.clip(alpha, 0.0, 1.0)
        rgba[..., :3] = np.where(rgba[..., 3:4] > 0.0, rgba[..., :3], 0.0)
    img = bpy.data.images.new(os.path.basename(path), width=w, height=h, alpha=True)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(np.clip(rgba, 0.0, 1.0).ravel())
    img.filepath_raw = path
    img.file_format = "PNG" if path.endswith(".png") else "JPEG"
    if img.file_format == "JPEG":
        try:
            bpy.context.scene.render.image_settings.quality = 92
        except AttributeError:
            pass
    img.save()
    bpy.data.images.remove(img)
    return path


# --- the albedos ------------------------------------------------------------
# Every generator returns (rgb, alpha, height, rough, ao): the colour, the
# alpha mask (None for an opaque surface), the height field the normal map is
# made of, the roughness and the ambient occlusion.
