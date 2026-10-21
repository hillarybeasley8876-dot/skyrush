"""The running fret (雷纹) and the cloud hooks of the pillar relief.

The fret is a CONTINUOUS meander band: one path that snakes through the panel
in rows of FRET_CELL pitch, every row a square wave, the rows joined by a
square turn. It is engraved into the recessed bronze ground, not printed on
the steel (the r2 version tiled the whole column with separate spirals, which
read as a checkerboard of bathroom tiles).

The cloud hooks are the archaic C/S scrolls that stand proud of the ground;
each one sits on a patch of bare steel, so the plain steel shows in the gaps
between the hooks.

    python3 -c "import tex_pillar_fret"
"""
import math

import numpy as np

FRET_CELL = 0.18        # meander cell (m)
FRET_AMP = 0.09         # the square wave's amplitude (m)
FRET_W = 0.02           # the engraved line width (m)
HOOK_DEPTH = 0.04       # the cloud hooks stand 0.04 m proud of the ground


def _row(x0, x1, yb, amp, c):
    """One square-wave row of the meander band, running in +x."""
    pts = [(x0, yb)]
    x = x0
    level = 0
    while x < x1 - 1e-6:
        if level == 0:
            pts.append((x, yb + amp))
            level = 1
        else:
            pts.append((x, yb))
            level = 0
        x = min(x + c, x1)
        pts.append((x, yb + level * amp))
    return pts


def fret_path(x0, x1, y0, y1):
    """The continuous running fret inside the panel rect (x0, y1)-(x1, y1).

    The rows run back and forth (boustrophedon), so the whole band is one
    path: the square turn at the end of a row joins it to the next."""
    rows = []
    j = 0
    yb = y0
    while yb < y1 - 1e-6:
        amp = min(FRET_AMP, max(0.02, (y1 - yb) * 0.5))
        row = _row(x0, x1, yb, amp, FRET_CELL)
        if j % 2 == 1:
            row = list(reversed(row))
        rows.append(row)
        yb += FRET_CELL
        j += 1
    path = []
    for i, row in enumerate(rows):
        if i > 0:
            prev = rows[i - 1]
            path.append((row[0][0], row[0][1]))
        path.extend(row)
    return path


def _square_spiral(cx, cy, size, turns=2):
    """An angular C/S scroll: straight runs around a centre."""
    s = size
    x, y = cx - size, cy - size
    pts = [(x, y)]
    for i in range(turns * 4):
        if i % 4 == 0:
            x += 2.0 * s
        elif i % 4 == 1:
            y += 2.0 * s
        elif i % 4 == 2:
            x -= 2.0 * s
        else:
            y -= 2.0 * s
        pts.append((x, y))
        s *= 0.55
    return pts


def cloud_hooks(x0, x1, y0, y1, seed, count=17):
    """The cloud hooks of one panel and the bare-steel islands they stand on.

    Returns a list of (path, cx, cy, radius). The radius is the island of
    plain steel around the hook."""
    rng = np.random.RandomState(seed)
    out = []
    w, h = x1 - x0, y1 - y0
    cols = 5
    rows = max(1, int(round(count / float(cols))))
    for i in range(count):
        gx = i % cols
        gy = i // cols
        cx = x0 + 0.40 + (w - 0.8) * (gx + 0.5 + 0.5 * (rng.rand() - 0.5)) / cols
        cy = y0 + 0.40 + (h - 0.8) * (gy + 0.5 + 0.5 * (rng.rand() - 0.5)) / rows
        size = 0.13 + 0.17 * rng.rand()          # half size -> 0.26-0.60 m
        ang = rng.rand() * math.pi
        path = _square_spiral(cx, cy, size, 2)
        ca, sa = math.cos(ang), math.sin(ang)
        path = [(cx + (p[0] - cx) * ca - (p[1] - cy) * sa,
                 cy + (p[0] - cx) * sa + (p[1] - cy) * ca) for p in path]
        out.append((path, cx, cy, size * 0.85 + 0.04))
    return out
