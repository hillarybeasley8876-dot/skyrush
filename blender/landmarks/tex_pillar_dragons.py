"""The kui-dragon primitives of the Nine-Dragon Pillar relief (see tex_pillar.py).

Archaic angular dragons: a flowing S-shaped spine that climbs its panel
diagonally, a blocky head with a twice-bent crest, a square-hook upper lip, a
round eye in a deep socket, two legs with three hooked claws each, dorsal hook
fins every 0.4-0.5 m and a tail that ends in a square spiral.

    python3 -c "import tex_pillar_dragons"
"""
import math

import numpy as np

SCALE_PITCH = 0.09          # chevron scale spacing (m)
EYE_DEPTH = 0.04           # eye socket depth (m)
EYE_R = 0.075              # eye D 0.15 m
FIN_PITCH = 0.45           # dorsal hook fin spacing (m)
SEG_MAX = 0.8              # no straight run of the body may be longer (m)


def _rad(t, width):
    """Body radius at the normalised position t: thick at the shoulders."""
    return width * 0.5 * (0.58 + 0.42 * math.sin(math.pi * min(t * 1.15, 1.0)))


def _dir(a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    ln = math.hypot(dx, dy) or 1.0
    return dx / ln, dy / ln


def _perp(d):
    return -d[1], d[0]


def dragon_spine(a0_deg, y0, y1, width, seed, radius, handed=1, span_deg=108.0):
    """The flowing S spine of one kui-dragon.

    The dragon climbs its panel diagonally: it wraps `span_deg` around the
    column while rising from y0 to y1, with two S-bends so that no run of the
    body is longer than SEG_MAX. `handed` flips the direction of the wrap.
    Returns (points, length_m); the points are (angle_deg, y)."""
    rng = np.random.RandomState(seed)
    rise = y1 - y0
    n = 44
    phase = rng.rand() * 2.0 * math.pi
    wob = math.radians(5.0) * (0.75 + 0.5 * rng.rand())
    turns = 2.0 + rng.rand()
    amp = 0.28 + 0.16 * rng.rand()
    pts = []
    for i in range(n + 1):
        t = i / float(n)
        a = a0_deg + handed * span_deg * t + wob * math.sin(2.0 * math.pi * turns * t + phase)
        y = y0 + rise * t + amp * math.sin(2.0 * math.pi * turns * t + phase + 1.2)
        pts.append((a, y))
    length = 0.0
    for i in range(n):
        da = math.radians(pts[i + 1][0] - pts[i][0]) * radius
        dy = pts[i + 1][1] - pts[i][1]
        length += math.hypot(da, dy)
    return pts, length


def hook_path(p, d, size, bend=1):
    """Square hook: three straight runs ending in a right-angle tip.

    Used for the crest, the upper lip, the claws and the tail so the ends read
    as archaic bronze-vessel hooks and not as round sausages. Two bends."""
    ux, uy = d
    ln = math.hypot(ux, uy) or 1.0
    ux, uy = ux / ln, uy / ln
    nx, ny = -uy, ux
    a = (p[0] + ux * size, p[1] + uy * size)
    b = (a[0] + nx * size * bend, a[1] + ny * size * bend)
    c = (b[0] - ux * size * 0.9, b[1] - uy * size * 0.9)
    return [p, a, b, c]


def spiral_tail(p, d, width):
    """Square-spiral tail curl, starting at the body and ending in a hook."""
    ux, uy = d
    nx, ny = _perp((ux, uy))
    x, y = p[0] - ux * width * 0.30, p[1] - uy * width * 0.28
    pts = [(x, y)]
    size = width * 0.66
    for i in range(4):
        x += ux * size + nx * size * 0.0
        pts.append((x, y))
        y += uy * size + ny * size * 0.0
        pts.append((x, y))
        size *= 0.62
    # the last turn hooks back on itself: a square spiral
    pts.append((x - ux * size * 1.2, y - uy * size * 1.2))
    return pts


def dragon_prims(pts, width, seed, radius):
    """Primitives of one kui-dragon: body, head, crest, lip, limbs, fins.

    `pts` are (angle_deg, y); they are converted to arc metres here."""
    prims = []
    P = [(math.radians(a) * radius, y) for (a, y) in pts]
    n = len(P)
    for i in range(n - 1):
        t0 = i / float(n - 1)
        t1 = (i + 1) / float(n - 1)
        prims.append(("cap", P[i], P[i + 1], _rad(t0, width), _rad(t1, width)))
    # the tail: a square spiral off the foot of the body
    d0 = _dir(P[0], P[1])
    tail = spiral_tail(P[0], d0, width)
    for i in range(len(tail) - 1):
        prims.append(("cap", tail[i], tail[i + 1], 0.075, 0.05))
    # the head: a blocky skull 1.0-1.3 m long, a snout and a square crest
    hx, hy = P[-1]
    d = _dir(P[-2], P[-1])
    nx, ny = _perp(d)
    ang = math.atan2(d[1], d[0])
    hl = 1.0 + 0.15 * (seed % 3)
    prims.append(("box", (hx + d[0] * hl * 0.25, hy + d[1] * hl * 0.25),
                  (0.26, 0.19), ang))
    prims.append(("box", (hx + d[0] * hl * 0.68, hy + d[1] * hl * 0.68),
                  (0.19, 0.13), ang))
    # the crest: a horn bent twice at right angles
    crest = hook_path((hx + d[0] * hl * 0.12 + nx * 0.14,
                       hy + d[1] * hl * 0.12 + ny * 0.14), d, 0.32, bend=1)
    for i in range(len(crest) - 1):
        prims.append(("cap", crest[i], crest[i + 1], 0.06, 0.04))
    # the upper lip: a square hook curling back under the snout
    lip = hook_path((hx + d[0] * hl * 0.80 - nx * 0.06,
                     hy + d[1] * hl * 0.80 - ny * 0.06), (d[0], -d[1]), 0.20, bend=-1)
    for i in range(len(lip) - 1):
        prims.append(("cap", lip[i], lip[i + 1], 0.05, 0.035))
    # the round eye in its deep socket
    prims.append(("hole", (hx + d[0] * hl * 0.30 + nx * 0.10,
                           hy + d[1] * hl * 0.30 + ny * 0.10), EYE_R, EYE_DEPTH))
    # two legs, each with three hooked claws
    for k, side in ((3, 1.0), (7, -1.0)):
        bx, by = P[k]
        ex, ey = bx + side * 0.55, by + 0.10
        prims.append(("cap", (bx, by), (ex, ey), 0.10, 0.075))
        for c in range(3):
            fx = ex + side * (0.16 + 0.10 * c)
            fy = ey + 0.30 + 0.06 * c
            prims.append(("cap", (ex, ey), (fx, fy), 0.07, 0.045))
            claw = hook_path((fx, fy), (side * 0.5, 0.9), 0.14, bend=side)
            for i in range(len(claw) - 1):
                prims.append(("cap", claw[i], claw[i + 1], 0.042, 0.022))
    # the dorsal hook fins every 0.4-0.5 m
    for (fx, fy, fd) in _walk(P, FIN_PITCH):
        fnx, fny = _perp(fd)
        bx, by = fx + fnx * width * 0.46, fy + fny * width * 0.46
        prims.append(("box", (bx, by), (0.055, 0.055), math.atan2(fd[1], fd[0])))
        tip = hook_path((bx, by), (fnx, fny), 0.16, bend=1)
        for i in range(len(tip) - 1):
            prims.append(("cap", tip[i], tip[i + 1], 0.04, 0.022))
    return prims


def chevron_prims(pts, width, radius):
    """Carved V chevrons along the body, apex pointing toward the head."""
    prims = []
    P = [(math.radians(a) * radius, y) for (a, y) in pts]
    for i in range(len(P) - 1):
        ax, ay = P[i]
        bx, by = P[i + 1]
        seg = math.hypot(bx - ax, by - ay)
        if seg < 1e-4:
            continue
        ux, uy = (bx - ax) / seg, (by - ay) / seg
        nx, ny = -uy, ux
        count = max(1, int(seg / SCALE_PITCH))
        for k in range(count):
            t = (k + 0.5) / count
            cx = ax + (bx - ax) * t
            cy = ay + (by - ay) * t
            half = width * 0.40
            apex = (cx, cy)
            a1 = (cx - ux * 0.040 + nx * half, cy - uy * 0.040 + ny * half)
            a2 = (cx - ux * 0.040 - nx * half, cy - uy * 0.040 - ny * half)
            prims.append(("cap", apex, a1, 0.010, 0.010))
            prims.append(("cap", apex, a2, 0.010, 0.010))
    return prims


def _walk(P, pitch):
    """Positions along the polyline every `pitch` metres (for the dorsal fins)."""
    out = []
    acc = 0.0
    for i in range(len(P) - 1):
        a, b = P[i], P[i + 1]
        d = _dir(a, b)
        seg = math.hypot(b[0] - a[0], b[1] - a[1])
        t = 0.0
        while True:
            step = pitch - acc
            if step > seg - t:
                acc = 0.0
                break
            t += step
            acc = 0.0
            out.append((a[0] + d[0] * t, a[1] + d[1] * t, d))
    return out
