"""Classical moulding profiles for the Bund kit (bund unit).

A profile is a closed 2D outline [(x, z), ...] in the facade's local frame:
x = outward from the wall face (0 = the wall), z = up from the bottom of the moulding.
`parts.prism` extrudes such an outline along the row, which is how every cornice, band and
sill in the kit is built.
"""
import math


# The regions of the shared trim sheet: (u0, uw, v0, vh). The sheet has ten bands, one
# per moulding family (texmaps3.py).
BAND_CORNICE = (0.0, 1.0, 0.00, 0.10)   # the egg-and-dart and the dentils
BAND_STRING = (0.0, 1.0, 0.10, 0.10)    # the bead-and-reel band
BAND_SILL = (0.0, 1.0, 0.20, 0.10)      # the ogee and the drip bead
BAND_CAPITAL = (0.0, 1.0, 0.30, 0.10)   # the Ionic volute and the Corinthian acanthus
BAND_KEY = (0.0, 1.0, 0.40, 0.10)       # the keystone, the door frame, the console
BAND_BASE = (0.0, 1.0, 0.50, 0.10)      # the torus and the astragal
BAND_ARCH = (0.0, 1.0, 0.60, 0.10)      # the archivolt: the roll and the fillet
BAND_RAIL = (0.0, 1.0, 0.70, 0.10)      # the rail and the baluster
BAND_PANEL = (0.0, 1.0, 0.80, 0.10)     # the fielded panel
BAND_PLAIN = (0.0, 1.0, 0.90, 0.10)     # the plain frieze


def arc(cx, cz, r, a0, a1, n=5):
    """Points of a circular arc (angles in degrees, CCW)."""
    return [(cx + r * math.cos(math.radians(a)), cz + r * math.sin(math.radians(a)))
            for a in [a0 + (a1 - a0) * i / (n - 1) for i in range(n)]]


def cornice(height=1.4, proj=1.1):
    """Entablature cornice: bed mould, corona and fillet (the classic Bund silhouette)."""
    p = []
    p.append((0.0, 0.0))
    p.append((0.12, 0.0))
    p += arc(0.30, 0.0, 0.30, -80, 0, 5)            # cyma recta (under-side quarter round)
    p.append((proj * 0.62, height * 0.40))
    p.append((proj * 0.66, height * 0.46))           # corona bed
    p.append((proj, height * 0.50))
    p.append((proj, height * 0.76))                  # corona face
    p.append((proj * 0.94, height * 0.80))
    p.append((proj * 0.88, height * 0.86))           # fillet
    p.append((proj * 0.80, height * 0.90))
    p.append((proj * 0.76, height))                  # top
    p.append((0.0, height))
    return p


def string_course(height=0.32, proj=0.22):
    """Thin band between floors."""
    return [(0.0, 0.0), (proj * 0.5, 0.0), (proj, height * 0.35), (proj, height * 0.7),
            (proj * 0.6, height), (0.0, height)]


def rail(width=0.34, height=0.14):
    """The handrail of a balustrade: a fillet over a cyma (the cross-section)."""
    return [(0.0, 0.0), (width, 0.0), (width, height * 0.55),
            (width * 0.86, height * 0.75), (width * 0.92, height), (0.0, height)]


def base_mould(height=0.6, proj=0.45):
    """Plinth at the foot of the rusticated storey."""
    return [(0.0, 0.0), (proj * 0.7, 0.0), (proj, height * 0.45), (proj * 0.9, height),
            (0.0, height)]


def sill(depth=0.30, height=0.16, over=0.10):
    """Window sill with a drip: x = 0 is the wall face."""
    return [(0.0, height), (-over, height * 0.9), (-over, 0.0), (depth * 0.9, 0.0),
            (depth, height * 0.25), (depth * 0.55, height * 0.55), (0.0, height * 0.7)]


def surround(w, h, depth=0.22, thick=0.28):
    """Window surround (archivolt) as a rectangular frame: outer edge at x=0, rebate to x=-depth."""
    t = thick
    return [(0.0, 0.0), (depth, 0.0), (depth, h - t), (depth - t * 0.4, h), (0.0, h),
            (-t, h), (-t, 0.0)]


def arch_surround(w, h, depth=0.22, thick=0.28):
    """Round-headed window surround."""
    t = thick
    spring = h - w * 0.5
    p = [(0.0, 0.0), (depth, 0.0), (depth, spring), (depth - t * 0.4, spring)]
    p += arc(w * 0.5, spring, w * 0.5 - t * 0.4, 0, 90, 6)
    p += [(0.0, h), (-t, h), (-t, 0.0)]
    return p


def pediment(width, height, depth=0.5, cornice_h=0.35):
    """Triangular pediment outline in the facade plane, as a prism profile in (x, z)."""
    hw = width * 0.5
    return [(0.0, 0.0), (depth, 0.0), (depth, cornice_h), (hw, height), (0.0, cornice_h)]


def _arc(y0, y1, z0, rise, n=9):
    """The points of a segmental (half-ellipse) arch from y0 to y1."""
    yc, hw = (y0 + y1) * 0.5, (y1 - y0) * 0.5
    return [(yc + hw * math.cos(math.pi * i / (n - 1)), z0 + rise * math.sin(math.pi * i / (n - 1)))
            for i in range(n)]


def segmental_band(y0, y1, z0, rise, thick=0.20, n=9):
    """The raised band of a segmental arch head, as a closed (y, z) outline."""
    outer = _arc(y0, y1, z0, rise, n)
    inner = list(reversed([(y, z - thick) for (y, z) in outer]))
    return outer + inner


def segmental_fill(y0, y1, z0, rise, n=9):
    """The tympanum under a segmental arch, as a closed (y, z) outline."""
    arc = _arc(y0, y1, z0, rise, n)
    return arc + [(y1, z0 - 0.06), (y0, z0 - 0.06)]


def pedestal(w, h, d):
    """Plinth for a statue or urn: (x = depth direction, y = width)."""
    return [(0.0, 0.0), (d, 0.0), (d, h * 0.12), (d * 0.86, h * 0.18), (d * 0.86, h * 0.86),
            (d, h * 0.9), (d, h), (0.0, h)]
