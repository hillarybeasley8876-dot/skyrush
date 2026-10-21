"""Promenade furniture (bund unit): balustrade, viewing balconies, palace lanterns,
granite lamp columns and bowl planters."""
import math

from . import data
from .promenade import box_at, frame_at

POST_STEP = 2.4       # the granite posts of the balustrade
POST_W = 0.35
RAIL_H = 1.10


def build(asm, base, edge):
    """All the furniture along the promenade; returns the lantern positions."""
    _balustrade(asm, base)
    _balconies(asm, base)
    lamps = _lanterns(asm, base)
    _lamp_columns(asm, base)
    _planters(asm, base)
    return lamps


def _walk(base, spacing, start=0.0):
    """Indices along the path every `spacing` metres."""
    out, run = [], start
    for i in range(len(base) - 1):
        run += math.dist(base[i][:2], base[i + 1][:2])
        if run >= spacing:
            run = 0.0
            out.append(i)
    return out


def _balustrade(asm, base):
    """The river balustrade: granite posts every 2.4 m with cast-iron panels (dossier 5.1)."""
    x = data.OFF_BALUSTRADE - 0.55
    for i in _walk(base, POST_STEP):
        box_at(asm, "granite", base, i, x, data.DECK_Y, POST_W, POST_W, RAIL_H + 0.16)
    # the cast-iron panels between the posts and the handrail
    for i in _walk(base, POST_STEP):
        p, right, rot = frame_at(base, i)
        cx = p[0] + right[0] * x
        cy = p[1] + right[1] * x
        seg = POST_STEP - POST_W
        asm.box("iron", (cx, cy, data.DECK_Y + 0.52), (seg, 0.05, 0.78), rot)
        asm.box("iron", (cx, cy, data.DECK_Y + 0.14), (seg, 0.09, 0.09), rot)
        asm.box("iron", (cx, cy, data.DECK_Y + 0.92), (seg, 0.09, 0.09), rot)
    # the handrail along the whole edge
    for i in _walk(base, 6.0):
        box_at(asm, "granite", base, i, x, data.DECK_Y + RAIL_H, 6.1, 0.42, 0.16)


def _balconies(asm, base):
    """32 semicircular viewing balconies cantilevered over the water."""
    idx = _walk(base, 30.0)
    step = max(1, len(idx) // data.BALCONIES)
    chosen = idx[::step][:data.BALCONIES]
    r = 3.4
    for i in chosen:
        p, right, rot = frame_at(base, i)
        cx = p[0] + right[0] * (data.OFF_BALUSTRADE - 0.1)
        cy = p[1] + right[1] * (data.OFF_BALUSTRADE - 0.1)
        ux, uy = math.cos(rot), math.sin(rot)          # along the promenade
        vx, vy = right                                # east
        _balcony_disc(asm, cx, cy, ux, uy, vx, vy, r, 16)
        _balcony_rail(asm, cx, cy, ux, uy, vx, vy, r, 16)


def _balcony_disc(asm, cx, cy, ux, uy, vx, vy, r, n):
    """The platform: a half disc east of the wall, with a fascia band."""
    bm = asm.bm("paving")
    top, bot = data.DECK_Y, data.DECK_Y - 0.3
    ct = bm.verts.new((cx, cy, top))
    cb = bm.verts.new((cx, cy, bot))
    ring_t, ring_b = [], []
    for k in range(n + 1):
        a = math.pi * k / n
        dx, dy = math.cos(a) * r, math.sin(a) * r
        px = cx + vx * dy + ux * dx
        py = cy + vy * dy + uy * dx
        ring_t.append(bm.verts.new((px, py, top)))
        ring_b.append(bm.verts.new((px, py, bot)))
    for k in range(n):
        bm.faces.new((ct, ring_t[k], ring_t[k + 1]))
        bm.faces.new((cb, ring_b[k + 1], ring_b[k]))
        bm.faces.new((ring_b[k], ring_t[k], ring_t[k + 1], ring_b[k + 1]))
    # the straight edge along the wall
    bm.faces.new((ct, ring_b[0], cb))
    bm.faces.new((ct, cb, ring_b[n]))
    bm.faces.new((ct, ring_t[0], ring_b[0]))
    bm.faces.new((ct, ring_b[n], ring_t[n]))


def _balcony_rail(asm, cx, cy, ux, uy, vx, vy, r, n):
    """The railing around the balcony arc."""
    for k in range(n + 1):
        a = math.pi * k / n
        dx, dy = math.cos(a) * r, math.sin(a) * r
        px = cx + vx * dy + ux * dx
        py = cy + vy * dy + uy * dx
        asm.box("iron", (px, py, data.DECK_Y + 0.48), (0.07, 0.07, 0.96),
                math.atan2(uy, ux) + a)
    for k in range(n):
        a0, a1 = math.pi * k / n, math.pi * (k + 1) / n
        am = (a0 + a1) * 0.5
        dx, dy = math.cos(am) * r, math.sin(am) * r
        px = cx + vx * dy + ux * dx
        py = cy + vy * dy + uy * dx
        seg = math.pi * r / n
        asm.box("iron", (px, py, data.DECK_Y + 0.98), (seg * 1.05, 0.14, 0.12),
                math.atan2(uy, ux) + am)


def _lanterns(asm, base):
    """64 palace lanterns (宫灯) on cast-iron posts along the promenade.

    Returns their world positions, so the preview can put its deck lamps on them."""
    idx = _walk(base, 15.0)
    step = max(1, len(idx) // data.LANTERNS)
    lamps = []
    for i in idx[::step][:data.LANTERNS]:
        x = data.OFF_BALUSTRADE - 2.4
        p, right, rot = frame_at(base, i)
        cx = p[0] + right[0] * x
        cy = p[1] + right[1] * x
        asm.box("iron", (cx, cy, data.DECK_Y + 1.7), (0.18, 0.18, 3.4),
                math.atan2(right[1], right[0]))
        # the bracket arm
        asm.box("iron", (cx + right[0] * 0.42, cy + right[1] * 0.42, data.DECK_Y + 3.25),
                (0.9, 0.10, 0.10), math.atan2(right[1], right[0]))
        hx, hy = cx + right[0] * 0.8, cy + right[1] * 0.8
        _lantern_head(asm, hx, hy, data.DECK_Y + 2.55, 0.30)
        lamps.append((hx, hy, data.DECK_Y + 2.8))
    return lamps


def _lantern_head(asm, x, y, z, r):
    """The paper lantern itself (emissive) with its cap and finial."""
    asm.lathe("lantern", [(0.0, 0.0), (r * 0.8, 0.0), (r, 0.12), (r, 0.5), (r * 0.75, 0.62),
                          (0.0, 0.62)], 6, (x, y, z))
    asm.lathe("iron", [(0.0, 0.0), (r * 1.2, 0.0), (0.0, 0.24)], 6, (x, y, z + 0.62))
    asm.box("iron", (x, y, z + 0.94), (0.05, 0.05, 0.24))


def _lamp_columns(asm, base):
    """8 granite art lamp columns with twin lanterns."""
    idx = _walk(base, 120.0)
    step = max(1, len(idx) // data.LAMP_COLUMNS)
    for i in idx[::step][:data.LAMP_COLUMNS]:
        x = data.OFF_DECK + 3.0
        p, right, rot = frame_at(base, i)
        cx = p[0] + right[0] * x
        cy = p[1] + right[1] * x
        asm.box("granite", (cx, cy, data.DECK_Y + 0.3), (1.0, 1.0, 0.6),
                math.atan2(right[1], right[0]))
        asm.lathe("granite", [(0.0, 0.0), (0.38, 0.0), (0.30, 0.3), (0.26, 3.0),
                              (0.34, 3.2), (0.0, 3.25)], 8, (cx, cy, data.DECK_Y + 0.6))
        for sy in (-1.0, 1.0):
            _lantern_head(asm, cx + right[0] * sy * 0.55, cy + right[1] * sy * 0.55,
                          data.DECK_Y + 3.85, 0.34)


def _planters(asm, base):
    """21 bowl planters with foliage along the promenade's road edge."""
    idx = _walk(base, 45.0)
    step = max(1, len(idx) // data.PLANTERS)
    for i in idx[::step][:data.PLANTERS]:
        x = data.OFF_DECK + 1.2
        p, right, rot = frame_at(base, i)
        cx = p[0] + right[0] * x
        cy = p[1] + right[1] * x
        asm.lathe("planter", [(0.0, 0.0), (0.95, 0.0), (1.05, 0.55), (1.0, 0.62),
                              (0.0, 0.62)], 12, (cx, cy, data.DECK_Y))
        asm.lathe("leaf", [(0.0, 0.0), (0.85, 0.1), (0.75, 0.55), (0.0, 0.75)], 10,
                  (cx, cy, data.DECK_Y + 0.55))
