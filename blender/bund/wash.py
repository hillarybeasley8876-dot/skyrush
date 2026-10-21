"""The far-field wash of the Bund (bund unit).

The pooled uplights fade out at 60-80 m (the light budget of the art dossier 3.4), so
beyond that the row would go grey. The far field is carried by a light map baked in
metres (washmap.py) and sampled by a card that stands in front of every facade; the
card has the shape of the wall (the openings are real holes in it), so no light ever
falls inside a window.

The crowns do not get a card: a flat card floats outside the silhouette of a dome and
reads as a halo. They get a shell - the crown's own form, 2 % bigger, with the additive
wash shader and a base-to-top gradient, so the glow follows the form from every side.
"""
import math

from . import elev
from .kit import roofs, walls

WASH_X = 0.60          # in front of the pediments (0.30) and the rustication (0.45)
SHELL = 1.02           # the crown shells stand this much outside the form they hug


def build(asm, s, cell):
    """The wash of one building: the facade cards and the crown shells."""
    e = elev.elevation(s)
    _facade_card(asm, s, cell, e, 0.0, e["cornice"],
                 e["windows"] + e["shopfronts"])
    attic_z0 = e["cornice"] + e["cornice_h"]
    if e["attic_top"] > attic_z0 + 0.2:
        _facade_card(asm, s, cell, e, attic_z0, e["attic_top"], e["attic"])
    for prim in s.get("shell", ()):
        _shell(asm, prim)


# ---------------------------------------------------------------- the facade cards
def _uv(cell, e, y, z):
    """The atlas UV of a point of the facade (the cell is in metres).

    The cell's v runs from the foot of the facade (z = 0) at the bottom of the cell to
    the top of the elevation at the top of it."""
    u = (y + e["width"] * 0.5) / e["width"]
    v = z / e["top"]
    return (cell["u0"] + u * (cell["u1"] - cell["u0"]),
            cell["v0"] + v * (cell["v1"] - cell["v0"]))


def _facade_card(asm, s, cell, e, z0, z1, holes):
    """One card in front of the facade, with the openings cut out of it.

    The card is built from the wall's own solid parts (the piers, the spandrels and the
    header), so the light can never fall into a window or a shopfront."""
    w = e["width"]
    rects = _rects(-w * 0.5, w * 0.5, z0, z1, holes)
    for (ya, yb, za, zb) in rects:
        pts = [(WASH_X, ya, za), (WASH_X, yb, za), (WASH_X, yb, zb), (WASH_X, ya, zb)]
        uvs = [_uv(cell, e, ya, za), _uv(cell, e, yb, za),
               _uv(cell, e, yb, zb), _uv(cell, e, ya, zb)]
        asm.quad_uv("wash", pts, uvs)


def _rects(u0, u1, z0, z1, holes):
    """The solid parts of a wall panel: the piers, the spandrels and the header."""
    out = []
    for ua, ub in walls._columns(u0, u1, holes):
        mid = (ua + ub) * 0.5
        cuts = [(hz0, hz1) for (uc, uh, hz0, hz1) in holes
                if uc - uh < mid < uc + uh]
        for za, zb in walls._subtract(z0, z1, cuts):
            if ub - ua > 0.02 and zb - za > 0.02:
                out.append((ua, ub, za, zb))
    return out


# ---------------------------------------------------------------- the crown shells
def _shell(asm, prim):
    """One shell of a crown form, with the wash's base-to-top gradient in its UVs.

    The last two numbers of a primitive are the v range: they let a crown put its
    brightest band where the crown itself is brightest (the clock stage, the dome)."""
    kind = prim[0]
    v0 = prim[-2]
    v1 = prim[-1]
    if kind == "cyl":
        _tube(asm, prim[1], prim[2], prim[3], prim[4] * SHELL, prim[5], v0, v1)
    elif kind == "dome":
        _dome(asm, prim[1], prim[2], prim[3], prim[4] * SHELL, prim[5], v0, v1)
    elif kind == "box":
        _box(asm, prim[1], prim[2], prim[3], prim[4] * SHELL, prim[5] * SHELL, prim[6], v0, v1)
    elif kind == "boxb":
        # a box that is only washed along its top band: a stepped tower keeps its
        # windows and its brick, and only the ledge of every step is lit
        _box_band(asm, prim[1], prim[2], prim[3], prim[4] * SHELL, prim[5] * SHELL,
                  prim[6], prim[7], v0, v1)
    elif kind == "pyr":
        _pyramid(asm, prim[1], prim[2], prim[3], prim[4] * SHELL, prim[5] * SHELL,
                 prim[6], v0, v1)


def _uvs(bm, face, heights):
    """Set the UVs of a face: u is constant, v is the height fraction of each corner.

    The crown wash texture is a vertical ramp, so only v matters."""
    layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    for loop, v in zip(face.loops, heights):
        loop[layer].uv = (0.5, v)


def _tube(asm, cx, cy, z0, radius, height, v0=0.0, v1=1.0, segments=24):
    """An open cylinder: the shell of a drum or a tower stage."""
    bm = asm.loose_bm("washcrown")
    rings = []
    for i in range(segments + 1):
        a = 2.0 * math.pi * i / segments
        rings.append((bm.verts.new((cx + radius * math.cos(a), cy + radius * math.sin(a), z0)),
                      bm.verts.new((cx + radius * math.cos(a), cy + radius * math.sin(a),
                                    z0 + height))))
    for i in range(segments):
        a0, a1 = rings[i], rings[i + 1]
        # wound so the face looks outwards: the shell is a skin, not a solid
        _uvs(bm, bm.faces.new((a0[0], a1[0], a1[1], a0[1])), (v0, v1, v1, v0))


def _dome(asm, cx, cy, z0, radius, height, v0=0.0, v1=1.0, segments=28, rings=9):
    """The shell of a dome: the same profile as the dome itself, 2 % bigger."""
    bm = asm.loose_bm("washcrown")
    prof = roofs.dome_profile(radius, height, rings)
    rows = []
    for i in range(segments + 1):
        a = 2.0 * math.pi * i / segments
        row = []
        for (r, z) in prof:
            row.append(bm.verts.new((cx + r * math.cos(a), cy + r * math.sin(a), z0 + z)))
        rows.append(row)
    for i in range(segments):
        for k in range(len(prof) - 1):
            a = prof[k][1] / max(1e-6, height)
            b = prof[k + 1][1] / max(1e-6, height)
            _uvs(bm, bm.faces.new((rows[i][k], rows[i + 1][k], rows[i + 1][k + 1],
                                   rows[i][k + 1])), (v0 + (v1 - v0) * a, v0 + (v1 - v0) * a,
                                                     v0 + (v1 - v0) * b, v0 + (v1 - v0) * b))


def _box(asm, cx, cy, z0, sx, sy, sz, v0=0.0, v1=1.0):
    """The shell of a box: the four sides and the top."""
    bm = asm.loose_bm("washcrown")
    hx, hy = sx * 0.5, sy * 0.5
    corners = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
    for i in range(4):
        a = corners[i]
        b = corners[(i + 1) % 4]
        p0 = [bm.verts.new((cx + a[0], cy + a[1], z0)),
              bm.verts.new((cx + b[0], cy + b[1], z0))]
        p1 = [bm.verts.new((cx + a[0], cy + a[1], z0 + sz)),
              bm.verts.new((cx + b[0], cy + b[1], z0 + sz))]
        _uvs(bm, bm.faces.new((p0[0], p0[1], p1[1], p1[0])), (v0, v0, v1, v1))
    top = [bm.verts.new((cx + a[0], cy + a[1], z0 + sz)) for a in corners]
    _uvs(bm, bm.faces.new(top), (v1, v1, v1, v1))


def _box_band(asm, cx, cy, z0, sx, sy, sz, band, v0=0.0, v1=1.0):
    """The shell of the top band of a box: the four sides above the band and the top."""
    bm = asm.loose_bm("washcrown")
    hx, hy = sx * 0.5, sy * 0.5
    zb = z0 + sz * (1.0 - band)
    corners = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
    for i in range(4):
        a = corners[i]
        b = corners[(i + 1) % 4]
        p0 = [bm.verts.new((cx + a[0], cy + a[1], zb)),
              bm.verts.new((cx + b[0], cy + b[1], zb))]
        p1 = [bm.verts.new((cx + a[0], cy + a[1], z0 + sz)),
              bm.verts.new((cx + b[0], cy + b[1], z0 + sz))]
        _uvs(bm, bm.faces.new((p0[0], p0[1], p1[1], p1[0])), (v0, v0, v1, v1))
    top = [bm.verts.new((cx + a[0], cy + a[1], z0 + sz)) for a in corners]
    _uvs(bm, bm.faces.new(top), (v1, v1, v1, v1))


def _pyramid(asm, cx, cy, z0, hx, hy, height, v0=0.0, v1=1.0):
    """The shell of a pyramid: the four slopes."""
    bm = asm.loose_bm("washcrown")
    bot = [(cx - hx, cy - hy), (cx + hx, cy - hy), (cx + hx, cy + hy), (cx - hx, cy + hy)]
    apex = bm.verts.new((cx, cy, z0 + height))
    for i in range(4):
        a = bot[i]
        b = bot[(i + 1) % 4]
        va = bm.verts.new((a[0], a[1], z0))
        vb = bm.verts.new((b[0], b[1], z0))
        _uvs(bm, bm.faces.new((va, vb, apex)), (v0, v0, v1))
