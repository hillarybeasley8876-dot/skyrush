"""Columns, pilasters and balusters for the Bund kit (bund unit).

Orders are stylised approximations of Doric / Ionic / Corinthian — at the distance the player
sees the Bund from (10-60 m) the silhouette of the capital and the entasis of the shaft are
what read, not the fluting count.
"""
import math

from lib import geo

from . import parts


def _ring(radius_fn, z, segments, cx, cy):
    return [(cx + radius_fn(a) * math.cos(a), cy + radius_fn(a) * math.sin(a), z)
            for a in [2.0 * math.pi * i / segments for i in range(segments)]]


def _shaft(asm, mat, x, y, z0, z1, r_bot, r_top, flutes=0, segments=20, rings=5):
    """Tapered (optionally fluted) shaft built as a stack of lofted rings."""
    sections = []
    for i in range(rings + 1):
        t = i / rings
        z = z0 + (z1 - z0) * t
        r = r_bot + (r_top - r_bot) * t
        if flutes:
            def rf(a, r=r, f=flutes):
                return r * (1.0 - 0.075 * (0.5 + 0.5 * math.cos(f * a)))
        else:
            def rf(a, r=r):
                return r
        sections.append(_ring(rf, z, segments, x, y))
    parts.merge(asm.bm(mat), geo.loft(sections, closed_sections=True,
                                cap_start=True, cap_end=True))


def column(asm, mat, x, y, z0, height, order="ionic", fluted=True, segments=48):
    """A free-standing column: base, shaft and capital.

    The order sets the height / diameter ratio (Ionic 9, Doric 8, Corinthian 10) and the
    shaft is fluted with 24 flutes, so the segments have to resolve them."""
    from .. import data
    r = height / data.COL_RATIO.get(order, 9.0)
    # plinth + base torus
    asm.box(mat, (x, y, z0 + 0.09), (r * 2.5, r * 2.5, 0.18))
    base_prof = [(0.0, 0.0), (r * 1.12, 0.0), (r * 1.04, 0.24), (r * 0.96, 0.30), (0.0, 0.30)]
    asm.lathe(mat, base_prof, min(segments, 24), (x, y, z0 + 0.18))
    shaft_h = height * 0.80
    z_shaft0 = z0 + 0.18 + 0.30
    _shaft(asm, mat, x, y, z_shaft0, z_shaft0 + shaft_h, r, r * 0.84,
           flutes=data.FLUTES if fluted else 0, segments=segments)
    z_cap = z_shaft0 + shaft_h
    from . import profiles
    if order == "doric":
        cap_prof = [(0.0, 0.0), (r * 0.84, 0.0), (r * 1.30, height * 0.11), (0.0, height * 0.11)]
        asm.lathe_trim("trim", cap_prof, min(segments, 24), (x, y, z_cap),
                       profiles.BAND_CAPITAL)
        asm.box("trim", (x, y, z_cap + height * 0.11 + 0.09), (r * 2.7, r * 2.7, 0.18))
    elif order == "corinthian":
        cap_prof = [(0.0, 0.0), (r * 0.84, 0.0), (r * 1.18, height * 0.10),
                    (r * 1.34, height * 0.15), (0.0, height * 0.15)]
        asm.lathe_trim("trim", cap_prof, min(segments, 24), (x, y, z_cap),
                       profiles.BAND_CAPITAL)
        asm.box("trim", (x, y, z_cap + height * 0.15 + 0.10), (r * 2.9, r * 2.9, 0.20))
    else:  # ionic
        asm.lathe_trim("trim", [(0.0, 0.0), (r * 0.84, 0.0), (r * 1.12, height * 0.10),
                                (0.0, height * 0.10)],
                       min(segments, 24), (x, y, z_cap), profiles.BAND_CAPITAL)
        # the two volutes, read as a pair of rolls at the sides
        for s in (-1.0, 1.0):
            asm.lathe(mat, [(0.0, 0.0), (r * 0.42, 0.0), (r * 0.42, r * 0.30), (0.0, r * 0.30)],
                      10, (x, y + s * r * 0.92, z_cap + height * 0.02))
        asm.box("trim", (x, y, z_cap + height * 0.10 + 0.09), (r * 2.8, r * 2.8, 0.18))
    return z_cap + height


def pilaster(asm, mat, x, y, z0, z1, width=1.6, out=0.45, capital=True, base=True):
    """A flat pilaster attached to the facade plane (x = 0 is the wall face)."""
    asm.box(mat, (x + out * 0.5, y, (z0 + z1) * 0.5), (out, width, z1 - z0))
    if base:
        asm.box(mat, (x + out * 0.55, y, z0 + 0.22), (out * 1.12, width * 1.12, 0.44))
    if capital:
        asm.box(mat, (x + out * 0.55, y, z1 - 0.30), (out * 1.14, width * 1.16, 0.26))
        asm.box(mat, (x + out * 0.60, y, z1 - 0.09), (out * 1.26, width * 1.26, 0.18))
    return z1


def baluster_profile(r, h):
    """The vase-shaped baluster of the promenade balustrade."""
    return [(0.0, 0.0), (r * 1.0, 0.0), (r * 0.72, h * 0.16), (r * 0.55, h * 0.34),
            (r * 0.80, h * 0.56), (r * 0.55, h * 0.82), (r * 1.0, h * 0.96),
            (r * 1.0, h), (0.0, h)]


def baluster(asm, mat, x, y, z0, h=0.62, r=0.11):
    asm.lathe(mat, baluster_profile(r, h), 6, (x, y, z0))
