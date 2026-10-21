"""The distance-field helpers of the Nine-Dragon Pillar relief (tex_pillar.py).

The relief is drawn into signed distance fields: a capsule, a rotated box and
a disc, combined with min / max. The column texture WRAPS, so every stroke is
split at the x=0 seam and each piece is shifted back onto the raster.

    python3 -c "import tex_pillar_sdf"
"""
import math

import numpy as np

W, H = 4096, 8192
CIRC = math.pi * 5.0            # 15.708 m
COL_R = 2.5
COL_H = 29.4
PX = W / CIRC                   # 260.8 px per metre around
PY = H / COL_H                  # 278.7 px per metre up
BIG = 1.0e9


def px_of(x):
    return int(x * PX)


def py_of(y):
    return int(y * PY)


def sdf_capsule(px, py, a, b, ra, rb):
    """Signed distance to a tapered capsule (negative inside)."""
    abx, aby = b[0] - a[0], b[1] - a[1]
    apx, apy = px - a[0], py - a[1]
    denom = max(abx * abx + aby * aby, 1e-9)
    t = np.clip((apx * abx + apy * aby) / denom, 0.0, 1.0)
    cx = a[0] + abx * t
    cy = a[1] + aby * t
    r = ra + (rb - ra) * t
    return np.sqrt((px - cx) ** 2 + (py - cy) ** 2) - r


def sdf_box(px, py, c, half, ang):
    """Signed distance to a rotated box."""
    dx, dy = px - c[0], py - c[1]
    ca, sa = math.cos(ang), math.sin(ang)
    lx = dx * ca + dy * sa
    ly = -dx * sa + dy * ca
    qx = np.abs(lx) - half[0]
    qy = np.abs(ly) - half[1]
    return (np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2)
            + np.minimum(np.maximum(qx, qy), 0.0))


def sdf_disc(px, py, c, r):
    return np.sqrt((px - c[0]) ** 2 + (py - c[1]) ** 2) - r


def stamp(field, x0, x1, y0, y1, fn, op="min"):
    """Evaluate `fn(px, py)` over a pixel bbox and combine into `field`."""
    ix0, ix1 = max(0, px_of(x0)), min(W, px_of(x1) + 1)
    iy0, iy1 = max(0, py_of(y0)), min(H, py_of(y1) + 1)
    if ix0 >= ix1 or iy0 >= iy1:
        return
    px = (np.arange(ix0, ix1, dtype=np.float32) + 0.5) / PX
    py = (np.arange(iy0, iy1, dtype=np.float32) + 0.5) / PY
    val = fn(px[None, :], py[:, None])
    tgt = field[iy0:iy1, ix0:ix1]
    if op == "min":
        np.minimum(tgt, val, out=tgt)
    else:
        np.maximum(tgt, val, out=tgt)


def _split_at_seam(a, b):
    """Split a segment that crosses the x=0 seam into pieces."""
    dx = b[0] - a[0]
    if abs(dx) < 1e-9:
        return [(a, b)]
    lo, hi = min(a[0], b[0]), max(a[0], b[0])
    k = math.floor(lo / CIRC) + 1
    cuts = []
    while k * CIRC < hi:
        t = (k * CIRC - a[0]) / dx
        if 0.0 < t < 1.0:
            cuts.append(t)
        k += 1
    if not cuts:
        return [(a, b)]
    cuts.sort()
    out = []
    prev = 0.0
    dy = b[1] - a[1]
    for t in cuts:
        p0 = (a[0] + dx * prev, a[1] + dy * prev)
        p1 = (a[0] + dx * t, a[1] + dy * t)
        out.append((p0, p1))
        prev = t
    out.append(((a[0] + dx * prev, a[1] + dy * prev), b))
    return out


def stroke(field, a, b, ra, rb):
    """Draw a tapered capsule into a distance field, wrapping the column."""
    for (p, q) in _split_at_seam(a, b):
        m = max(ra, rb) + 0.15
        x0 = min(p[0], q[0]) - m
        x1 = max(p[0], q[0]) + m
        sh = 0.0
        if x1 < 0.0:
            sh = CIRC
        elif x0 > CIRC:
            sh = -CIRC
        if sh:
            p = (p[0] + sh, p[1])
            q = (q[0] + sh, q[1])
            x0 += sh
            x1 += sh
        if x1 < 0.0 or x0 > CIRC:
            continue
        stamp(field, x0, x1, min(p[1], q[1]) - m, max(p[1], q[1]) + m,
              lambda px, py, p=p, q=q, ra=ra, rb=rb: sdf_capsule(px, py, p, q, ra, rb))


def box_stamp(field, c, half, ang):
    m = max(half) + 0.15
    c = list(c)
    x0, x1 = c[0] - m, c[0] + m
    if x1 < 0.0:
        c[0] += CIRC
        x0 += CIRC
        x1 += CIRC
    elif x0 > CIRC:
        c[0] -= CIRC
        x0 -= CIRC
        x1 -= CIRC
    if x1 < 0.0 or x0 > CIRC:
        return
    stamp(field, x0, x1, c[1] - m, c[1] + m,
          lambda px, py, c=c, half=half, ang=ang: sdf_box(px, py, c, half, ang))


def path_stroke(field, pts, ra, rb):
    """Stroke a whole path (a list of points) into a distance field."""
    for i in range(len(pts) - 1):
        stroke(field, pts[i], pts[i + 1], ra, rb)


def disc_mask(mask, cx, cy, r):
    """OR a disc into a boolean mask (the column wraps, so try all three)."""
    for off in (0.0, -CIRC, CIRC):
        x = cx + off
        ix0, ix1 = max(0, px_of(x - r)), min(W, px_of(x + r) + 1)
        iy0, iy1 = max(0, py_of(cy - r)), min(H, py_of(cy + r) + 1)
        if ix0 >= ix1 or iy0 >= iy1:
            continue
        px = (np.arange(ix0, ix1, dtype=np.float32) + 0.5) / PX
        py = (np.arange(iy0, iy1, dtype=np.float32) + 0.5) / PY
        d = np.sqrt((px[None, :] - x) ** 2 + (py[:, None] - cy) ** 2) - r
        mask[iy0:iy1, ix0:ix1] |= (d < 0.0)


def smoothstep(a):
    return a * a * (3.0 - 2.0 * a)


def _u8(a):
    return np.clip(a * 255.0, 0, 255).astype(np.uint8)
