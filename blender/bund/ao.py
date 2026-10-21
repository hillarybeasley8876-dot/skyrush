"""Per-vertex ambient occlusion, dirt and macro variation for the Bund facades (bund unit).

The lead's brief asks for the facades to be lit by the uplights, not by emission, and for the
relief to read: so every stone vertex carries an AO / dirt / macro-variation value in a
colour attribute (COLOR_0) that multiplies the granite texture. The terms below are
geometric - the cornice overhang, the string courses, the window reveals, the ground line -
so they land exactly where the geometry darkens.
"""
import math

# The dossier's facade colours as multipliers on the neutral #ABAAA3 granite: the value stays
# within +-8 % so the row reads as one quarry (the hue carries the difference).
HUE = {
    "granite": (1.00, 1.00, 1.00),
    "granite_grey": (1.05, 1.04, 1.02),
    "granite_dark": (1.04, 1.03, 1.00),
    "granite_light": (1.06, 1.04, 1.00),
    "granite_pale": (1.06, 1.05, 1.02),
    "granite_warm": (1.04, 1.00, 0.94),
    "cream": (1.06, 1.05, 1.00),
    "white": (1.08, 1.07, 1.05),
    "pearl": (1.04, 1.02, 0.98),
    "brick_red": (1.02, 0.98, 0.96),
    "brick_band": (1.00, 0.95, 0.93),
    "tile_white": (1.00, 1.00, 1.00),
    "coffee": (1.00, 1.00, 1.00),
}

CORNICE_SHADOW = 0.60      # the 1.6 m band under the main cornice
STRING_SHADOW = 0.30        # the shadow under each string course
BASE_DIRT = 0.18            # the 0.5 m of dirt at the foot of the wall
REVEAL_SHADOW = 0.30        # the window reveals
MACRO = 0.10                # the 12-30 m world-space variation


def _macro(x, y, z):
    """A smooth pseudo-random field in [-1, 1] (30 m and 13 m scales)."""
    a = math.sin(x * 0.083 + 1.7) * math.sin(y * 0.071 + 0.4) * math.sin(z * 0.061 + 2.2)
    b = math.sin(x * 0.211 + 0.3) * math.sin(y * 0.193 + 2.6) * math.sin(z * 0.177 + 1.1)
    return 0.72 * a + 0.28 * b


def facade_tint(s, co, hue=None):
    """The AO / dirt / macro value for a vertex of the facade (0.3 - 1.0).

    The per-building hue is NOT here: it is the material's base colour tint, because
    glTF clamps COLOR_0 to 1.0 and the hue multipliers would be lost (the review's MF5)."""
    x, y, z = co[0], co[1], co[2]
    cornice = s["cornice"]
    base_h = s["base_h"]
    fh = s["floor_h"]
    ao = 1.0
    # the main cornice overhang
    if cornice - 1.6 < z < cornice + 0.1 and x < 0.25:
        ao *= 1.0 - CORNICE_SHADOW * (1.0 - (cornice - z) / 1.6)
    # the string course under every floor
    if x < 0.25:
        for f in range(s["floors"] + 1):
            fz = base_h + f * fh
            if fz - 0.45 < z < fz + 0.35:
                ao *= 1.0 - STRING_SHADOW * (1.0 - abs(z - fz) / 0.45)
    # the ground line: dirt and splash
    if z < 1.2:
        ao *= 1.0 - BASE_DIRT * math.exp(-max(z, 0.0) / 0.5)
    # the window reveals and soffits are in shadow
    if x < -0.04:
        ao *= 1.0 - REVEAL_SHADOW
    # the world-space macro variation
    ao *= 1.0 + MACRO * _macro(x, y, z)
    v = min(1.0, ao)
    return (v, v, v)
