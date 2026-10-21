"""Cornices, entrances, attic storeys and roof furniture for the Bund kit (bund unit)."""
import math

from .. import data
from . import columns, profiles, walls


def cornice(asm, s, scale=1.0):
    """The main entablature: a projected moulding along the whole facade."""
    w = s["frontage"]
    big = s["cornice"] > data.CORNICE_BIG_ABOVE
    h = data.CORNICE_H_BIG if big else data.CORNICE_H_SMALL
    p = data.CORNICE_PROJ_BIG if big else data.CORNICE_PROJ_SMALL
    prof = profiles.cornice(h * scale, p * scale)
    asm.prism_trim("trim", prof, -w * 0.5, w * 0.5, profiles.BAND_CORNICE,
                   tile=2.0, z_off=s["cornice"])
    # a thin shadow reveal under the cornice
    asm.box("stone", (0.05, 0.0, s["cornice"] - 0.16), (0.12, w, 0.14))
    # the hidden cove light under the cornice: the warm line that makes the row read gold
    asm.box("goldstrip", (p * 0.55, 0.0, s["cornice"] - 0.05), (0.22, w - 0.4, 0.16))


def entrance(asm, s):
    """The central portal: a deep notch in the rusticated base with a canopy and steps."""
    w = s["frontage"]
    pw = min(5.0, w * 0.22)
    base_h = s["base_h"]
    dw = (pw - 0.9) * 0.5
    # the doors: two glazed leaves in a bronze frame, showing a cell of the interior atlas
    for k, sy in enumerate((-1.0, 1.0)):
        yc = sy * dw * 0.5
        cell = 12 + k
        u0 = (cell % 4) * 0.25
        v0 = (cell // 4) * 0.25
        asm.quad_uv("glasslit",
                    [(-0.30, yc - dw * 0.5, 0.25), (-0.30, yc + dw * 0.5, 0.25),
                     (-0.30, yc + dw * 0.5, base_h * 0.80), (-0.30, yc - dw * 0.5, base_h * 0.80)],
                    [(u0, v0), (u0 + 0.25, v0), (u0 + 0.25, v0 + 0.25), (u0, v0 + 0.25)])
    for sy in (-1.0, 1.0):
        asm.box("iron", (-0.28, sy * dw, base_h * 0.52), (0.10, 0.12, base_h * 0.56))
    asm.box("iron", (-0.28, 0.0, base_h * 0.80), (0.10, dw * 2.0, 0.14))
    for sy in (-1.0, 1.0):
        asm.box("stone", (-0.12, sy * (pw * 0.5 - 0.22), base_h * 0.42), (0.5, 0.44, base_h * 0.84))
    asm.box("stone", (-0.05, 0.0, base_h * 0.86), (0.6, pw, 0.5))
    # canopy
    asm.box("iron", (0.9, 0.0, base_h * 0.72), (1.8, pw * 0.92, 0.12))
    for sy in (-1.0, 1.0):
        asm.box("iron", (1.6, sy * pw * 0.40, base_h * 0.36), (0.10, 0.10, base_h * 0.72))
    # steps down to the pavement
    for i in range(3):
        asm.box("stone", (0.55 + i * 0.55, 0.0, 0.09 * (3 - i)), (0.55, pw + 1.4 - i * 0.3, 0.18))


def portico(asm, s, order="ionic"):
    """A free-standing colonnade in front of the facade (HSBC).

    The six columns stand single-double-double-single, as the dossier has it."""
    w = s["frontage"]
    n = s["opts"].get("portico", 6)
    span = min(w * 0.46, 6.2 * (n - 1))
    y0 = -span * 0.5
    x = data.PORTICO_OFFSET
    # stylobate
    asm.box("stone", (x * 0.5 + 0.2, 0.0, 0.35), (x + 2.2, span + 5.0, 0.7))
    ch = s["base_h"] + 8.0
    bays = _portico_bays(y0, span, n)
    s["portico_bays"] = [round(v, 3) for v in bays]
    for y in bays:
        columns.column(asm, "stone", x, y, 0.7, ch, order, fluted=True)
    # entablature over the colonnade
    prof = profiles.cornice(1.5, 1.2)
    asm.prism("stone", prof, y0 - 2.0, y0 + span + 2.0, x_off=x, z_off=0.7 + ch)
    asm.box("stone", (x, 0.0, 0.7 + ch + 0.55), (1.3, span + 4.0, 1.1))
    # the pediment over the central bay
    from . import crowns
    pw = span * 0.55
    crowns.gable(asm, 0.0, x - 0.35, x + 0.35, 0.7 + ch + 1.1, pw, pw * 0.34)
    asm.box("stone", (x + 0.45, 0.0, 0.7 + ch + 1.2), (0.7, pw + 0.5, 0.3))


def _portico_bays(y0, span, n):
    """The column positions of a portico: single-double-double-single (dossier 5.3).

    Six columns stand in five gaps - a wide one, the narrow pair on the left, the wide
    centre, the narrow pair on the right and a wide one - so the row is symmetric about
    the centre of the facade."""
    if n != 6:
        return [y0 + i * (span / max(1, n - 1)) for i in range(n)]
    gaps = [0.30, 0.06, 0.28, 0.06, 0.30]
    total = sum(gaps)
    out, y = [], y0
    for g in gaps:
        out.append(y)
        y += g * span / total
    out.append(y)
    return out


def attic(asm, s, rng, height=4.0):
    """A low attic storey above the cornice, with small windows and its own cap."""
    w = s["frontage"]
    z0 = s["cornice"]
    height = min(height, max(1.5, s["height"] - s["cornice"] - 0.6))
    # the attic mass behind its own front wall
    asm.gbox("stone", (-0.62, 0.0, z0 + height * 0.5), (0.55, w, height), 1.5)
    holes = []
    n = max(3, int(w / 4.0))
    for i in range(n):
        yc = -w * 0.5 + (i + 0.5) * (w / n)
        holes.append((yc, 0.62, z0 + height * 0.28, z0 + height * 0.74))
    walls.opening_wall(asm, "stone", "glasslit", 0.0, "X", 1.0, -w * 0.5, w * 0.5,
                       z0, z0 + height, holes, rng=rng,
                       lit_fraction=data.ATTIC_LIT_FRACTION, cell_base=5)
    asm.prism("stone", profiles.cornice(0.8, 0.6), -w * 0.5, w * 0.5, z_off=z0 + height)


def balustrade_run(asm, x, y0, y1, z, step=0.55, h=0.75, mat="stone"):
    """A balustrade: a rail on a row of small balusters.

    The rail is a real moulding (the trim sheet's band), not a plain box."""
    n = max(2, int(abs(y1 - y0) / step))
    for i in range(n + 1):
        y = y0 + (y1 - y0) * i / n
        columns.baluster(asm, mat, x, y, z, h * 0.78, 0.10)
    asm.prism_trim("trim", profiles.rail(0.34, 0.16), y0, y1, profiles.BAND_RAIL,
                   tile=1.2, x_off=x - 0.17, z_off=z + h * 0.78)
    asm.box(mat, (x, (y0 + y1) * 0.5, z + 0.06), (0.42, abs(y1 - y0), 0.12))


def flag(asm, x, y, z, h=9.0, size=(2.4, 1.5)):
    """A flag pole with a red flag that has a slight wave in the mesh."""
    asm.lathe("iron", [(0.0, 0.0), (0.12, 0.0), (0.10, 0.5), (0.06, h), (0.0, h)], 8, (x, y, z))
    n, m = 6, 3
    verts = []
    for i in range(n + 1):
        row = []
        for j in range(m + 1):
            u = i / n
            v = j / m
            wave = math.sin(u * 5.0) * 0.22 * v
            row.append((x + u * size[0], y + wave, z + h - 0.9 - v * size[1]))
        verts.append(row)
    bm = asm.loose_bm("red")
    for i in range(n):
        for j in range(m):
            a = bm.verts.new(verts[i][j])
            b = bm.verts.new(verts[i + 1][j])
            c = bm.verts.new(verts[i + 1][j + 1])
            d = bm.verts.new(verts[i][j + 1])
            bm.faces.new((a, b, c, d))
    return bm


def roof_clutter(asm, s, rng):
    """Water tanks, vents and lift houses on a flat roof."""
    w, d = s["frontage"], s["depth"]
    z = s["cornice"] + 0.2
    for i in range(rng.randint(3, 6)):
        x = -(rng.uniform(2.0, max(3.0, d - 4.0)))
        y = rng.uniform(-w * 0.4, w * 0.4)
        if rng.random() < 0.5:
            asm.box("iron", (x, y, z + 1.1), (1.8, 1.8, 2.2))
        else:
            asm.lathe("iron", [(0.0, 0.0), (0.9, 0.0), (0.9, 1.8), (0.0, 1.8)], 10, (x, y, z))
    # parapet
    for sy in (-1.0, 1.0):
        asm.box("stone", (-d * 0.5, sy * (w * 0.5 - 0.2), z + 0.45), (d, 0.4, 0.9))
    asm.box("stone", (-d + 0.2, 0.0, z + 0.45), (0.4, w, 0.9))
