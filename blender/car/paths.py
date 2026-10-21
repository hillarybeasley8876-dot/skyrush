"""Shared paths, colour helpers and the loft data for the SKYRUSH hero Roadster.

Frame (CONTRACTS.md §1): metres, Z up, +Y forward, +X right, origin on the ground
midway between the axles. All numbers come from ref/roadster/roadster_loft.json.
"""
import json
import os
import sys

ROOT = os.path.expanduser("~/m/skyrush")
sys.path.insert(0, os.path.join(ROOT, "blender"))

GAME = os.path.join(ROOT, "game")
ASSETS = os.path.join(GAME, "assets", "cars", "roadster")
# The generated maps are BLENDER INPUTS only: the glb embeds them and Godot
# extracts its own copies, so nothing in game/ loads them (lead note
# IMPORT-CHURN: every PNG in game/ costs a second Godot import).
TEXDIR = os.path.join(ROOT, "blender", "car", "textures")
# scratch: everything temporary belongs here (never /tmp, never inside game/)
SCRATCH = os.path.join(ROOT, "tmp", "car_model")
LOFT_JSON = os.path.join(ROOT, "ref", "roadster", "roadster_loft.json")
REF_IMG = os.path.join(ROOT, "ref", "roadster", "img")

# ---------------------------------------------------------------- colours
def srgb(hexstr, alpha=1.0):
    """'#ECEDEF' -> linear RGBA tuple for Blender/GLSL inputs."""
    h = hexstr.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], alpha)


def hex2rgb(hexstr):
    """'#ECEDEF' -> (r,g,b) in 0..1, sRGB encoded (for PIL work)."""
    h = hexstr.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


# ---------------------------------------------------------------- palette (ART.md §3, dossier §7)
WHITE = "#ECEDEF"        # Ano White body paint
BLACK_TRIM = "#111113"   # sills, fascia, valance, arch lips
INNER_DARK = "#141416"   # inner surface behind detachable panels
GLASS_GOLD = "#5A3F2A"   # canopy tint
CARBON = "#141416"
TITANIUM = "#9B958E"
GOLD = "#B08458"
WHEEL_WHITE = "#E6E6E8"
WHEEL_DARK = "#2A2B2E"
RUBBER = "#161616"
CALIPER = "#6E4A2E"
DISC = "#3A3A3C"
SEAT_WHITE = "#E4E4E6"
MICROSUEDE = "#464551"
CABIN_BLACK = "#12141A"
RED = "#FF2A2A"
RED_BAR = "#FF1A2A"
WHITE_BAR = "#F2F6FF"
AMBER = "#FF8A00"

# the normalised box projection covers the whole model: one UV unit is this many
# metres (the length of the car, from the JSON dims).
UV_EXTENT = 4.38


# ---------------------------------------------------------------- loft data
_CACHE = {}


def loft():
    """The parsed roadster_loft.json (cached)."""
    if "d" not in _CACHE:
        with open(LOFT_JSON) as f:
            _CACHE["d"] = json.load(f)
    return _CACHE["d"]


def tex(name):
    """Absolute path of a generated texture in the car's own texture folder."""
    return os.path.join(TEXDIR, name)


def parent_to(child, parent):
    """Parent an object keeping its world transform.

    bpy's matrix_world is only refreshed on depsgraph evaluation, so a freshly
    assigned location would be lost by lib.common.set_parent; update first.
    """
    import bpy
    bpy.context.view_layer.update()
    from lib import common
    common.set_parent(child, parent)
    return child


def parent_local(child, parent):
    """Parent a child whose geometry already lives in the parent's local space.

    The child's world transform is set to the parent's before parenting, so the
    local matrix stays the identity and the child follows the parent exactly.
    """
    import bpy
    bpy.context.view_layer.update()
    child.matrix_world = parent.matrix_world.copy()
    from lib import common
    common.set_parent(child, parent)
    return child
