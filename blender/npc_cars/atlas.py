"""Shared texture-atlas layout for the npc_cars unit (no dependencies, imported by
both the PIL generator `gen_textures.py` and the Blender builders).

Rects are (x0, y0, x1, y1) in image pixels with y measured downwards from the top.
`uv_rect(rect, size)` converts one to the GL UV box (v flipped).
"""
import os

TEXTURE_DIR = os.path.expanduser("~/m/skyrush/game/assets/cars/npc/textures")

TRIM_SIZE = 1024
TRIM = {
    "rim":    (0, 0, 512, 512),        # dark machined alloy, radial brushing
    "trim":   (512, 0, 1024, 256),     # matte black plastic, fine grain
    "mesh":   (512, 256, 1024, 512),   # grille / intake mesh
    "lamp":   (512, 512, 768, 640),    # emissive DRL strip pattern (white)
    "lamp_red": (768, 512, 1024, 640),  # emissive tail strip (red, 50 % duty)
    "rubber": (0, 512, 512, 1024),     # tyre sidewall (albedo)
    "plain":  (768, 640, 1024, 768),   # flat dark grey
}

WHEEL_SIZE = 1024
WHEEL_SHEET = (1024, 2048)            # the wheel sheet: rim, tread, brake
WHEEL = {
    "rim": (0, 0, 1024, 1024),          # machined alloy face with the pockets
    "tyre": (0, 1024, 768, 2048),       # rubber with the tread normal
    "brake": (768, 1024, 1024, 1280),   # the brake disc behind the spokes
    "caliper": (768, 1280, 1024, 1536),  # the caliper
}

# an unused (dark) slot of the plate atlas, for the plate frames
PLATE_BLANK = (0, 320, 512, 480)

INTERIOR_SIZE = 1024
INTERIOR = {
    "seat":      (0, 0, 512, 512),     # dark leather with perforation + stitch
    "dash":      (512, 0, 1024, 512),  # soft-touch dash with a display
    "headliner": (0, 512, 512, 768),   # pale grey fabric weave
    "trim":      (512, 512, 1024, 768),  # dark matte plastics
    "screen":    (768, 512, 1024, 768),  # instrument cluster
    "belt":      (0, 768, 512, 1024),  # seat belt webbing
}


def uv_rect(rect, size):
    """Image-pixel rect -> (u0, v0, u1, v1) with v pointing up.

    `size` is either a single number (square atlas) or a (width, height) pair.
    """
    x0, y0, x1, y1 = rect
    w, h = size if isinstance(size, (tuple, list)) else (size, size)
    return (x0 / w, 1.0 - y1 / h, x1 / w, 1.0 - y0 / h)


