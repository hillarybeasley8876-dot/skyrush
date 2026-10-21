"""Shared bootstrap for the SKYRUSH landmark build scripts.

    import os, sys
    sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender/landmarks"))
    import lmenv
    from lmenv import bpy, common, geo, lmlib, lmmat, mats, uv

Puts blender/ and blender/landmarks/ on sys.path and re-exports the core lib
plus the landmark helpers, so every build script starts with three lines.
"""
import os
import sys

BL = os.path.expanduser("~/m/skyrush/blender")
for _p in (BL, os.path.join(BL, "landmarks")):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import bpy  # noqa: E402
from lib import common, export, geo, mats, uv  # noqa: E402

import lmlib  # noqa: E402
import lmmat  # noqa: E402

TEXTURES = os.path.join(BL, "landmarks", "src_tex")

_REQUIRED = ("glass_rough.png", "facade_night_diff.png", "led_dots.png",
             "steel_paint_diff.png", "rivets_nor.png", "glass_bands_diff.png")


def ensure_textures():
    """Generate the procedural texture set if it is missing (deterministic)."""
    if all(os.path.exists(os.path.join(TEXTURES, n)) for n in _REQUIRED):
        return
    import texgen
    texgen.write_all()

