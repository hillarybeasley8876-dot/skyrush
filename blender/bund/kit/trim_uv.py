"""The trim sheet's UV helpers (bund unit).

The mouldings of the Bund share one 4096 px sheet: every piece has to know where its
band sits on that sheet, and how the profile's girth maps onto it. These helpers draw
the piece and give it the right UVs, so the sheet is used instead of a flat texture.
"""
import math


def _girth(profile):
    """The cumulative arc length of a 2D profile and its normalised fractions."""
    g = [0.0]
    for (x0, z0), (x1, z1) in zip(profile[:-1], profile[1:]):
        g.append(g[-1] + math.hypot(x1 - x0, z1 - z0))
    total = g[-1] if g[-1] > 1e-6 else 1.0
    return [v / total for v in g]


def prism_trim(dst, profile, y0, y1, band, tile=2.0, x_off=0.0, z_off=0.0):
    """Extrude a profile along Y with the trim sheet's UVs.

    `band` is (u0, uw, v0, vh): the region of the trim sheet this piece uses. u runs
    along the profile's girth, v along the length of the piece (one tile per `tile` m).
    The piece is split into tiles, so no face is stretched across a texture wrap."""
    u0, uw, v0, vh = band
    frac = _girth(profile)
    n = len(profile)
    segs = max(1, int(math.ceil(abs(y1 - y0) / tile)))
    for s in range(segs):
        ya = y0 + (y1 - y0) * s / segs
        yb = y0 + (y1 - y0) * (s + 1) / segs
        va, vb = (0.0, 1.0)
        sec0 = [(x + x_off, ya, z + z_off) for (x, z) in profile]
        sec1 = [(x + x_off, yb, z + z_off) for (x, z) in profile]
        a = [dst.verts.new(p) for p in sec0]
        b = [dst.verts.new(p) for p in sec1]
        layer = dst.loops.layers.uv.get("UVMap") or dst.loops.layers.uv.new("UVMap")
        for k in range(n):
            k2 = (k + 1) % n
            f = dst.faces.new((a[k], a[k2], b[k2], b[k]))
            uvs = ((u0 + uw * frac[k], v0 + vh * va), (u0 + uw * frac[k2], v0 + vh * va),
                   (u0 + uw * frac[k2], v0 + vh * vb), (u0 + uw * frac[k], v0 + vh * vb))
            for loop, uv in zip(f.loops, uvs):
                loop[layer].uv = uv
        for ring, vv in ((a, va), (b, vb)):
            f = dst.faces.new(ring)
            for loop, k in zip(f.loops, range(n)):
                loop[layer].uv = (u0 + uw * frac[k], v0 + vh * vv)
    return dst


def lathe_trim(dst, profile, segments, center, band):
    """Revolve a profile around Z with the trim sheet's UVs (the capitals).

    u runs along the profile's girth, v once around the revolve."""
    u0, uw, v0, vh = band
    frac = _girth(profile)
    n = len(profile)
    layer = dst.loops.layers.uv.get("UVMap") or dst.loops.layers.uv.new("UVMap")
    rings = []
    for i in range(segments + 1):
        a = 2.0 * math.pi * i / segments
        ca, sa = math.cos(a), math.sin(a)
        ring = [dst.verts.new((center[0] + r * ca, center[1] + r * sa, center[2] + z))
                for (r, z) in profile]
        rings.append(ring)
    for i in range(segments):
        ra, rb = rings[i], rings[i + 1]
        va = vh * i / segments
        vb = vh * (i + 1) / segments
        for k in range(n - 1):
            f = dst.faces.new((ra[k], ra[k + 1], rb[k + 1], rb[k]))
            uvs = ((u0 + uw * frac[k], v0 + va), (u0 + uw * frac[k + 1], v0 + va),
                   (u0 + uw * frac[k + 1], v0 + vb), (u0 + uw * frac[k], v0 + vb))
            for loop, uv in zip(f.loops, uvs):
                loop[layer].uv = uv
    return dst
