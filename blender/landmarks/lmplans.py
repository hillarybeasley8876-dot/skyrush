"""Plan (2D outline) helpers for SKYRUSH landmarks: octagons, rounded triangles,
rectangles with chamfers, resampling and lofting a stack of plans into a solid.

    from lmplans import octagon, loft_plans

Split out of lmlib.py to keep both files under the 400 line budget.
"""
import math

from lib import geo


# ------------------------------------------------------------------ plans
def rot(plan, angle):
    c, s = math.cos(angle), math.sin(angle)
    return [(x * c - y * s, x * s + y * c) for (x, y) in plan]


def scale_plan(plan, s, origin=(0.0, 0.0)):
    ox, oy = origin
    return [(ox + (x - ox) * s, oy + (y - oy) * s) for (x, y) in plan]


def octagon(half, phase=0.0):
    """Regular octagon with across-flats = 2*half (Jin Mao plan)."""
    r = half / math.cos(math.pi / 8.0)
    return [(r * math.cos(math.pi / 8 + i * math.pi / 4 + phase),
             r * math.sin(math.pi / 8 + i * math.pi / 4 + phase)) for i in range(8)]


def rect(hx, hy, chamfer=0.0):
    """Rectangle (optionally with 45 deg chamfered corners) as 8 points."""
    cx, cy = max(0.0, hx - chamfer), max(0.0, hy - chamfer)
    return [(-cx, -hy), (cx, -hy), (hx, -cy), (hx, cy), (cx, hy), (-cx, hy), (-hx, cy), (-hx, -cy)]


def rounded_tri(radius, corner=0.20, per_corner=8):
    """Rounded equilateral-triangle plan with outer circumradius `radius`.

    The corner arcs are tangent to the three sides; `corner` is the rounding
    radius as a fraction of the circumradius."""
    c = corner * radius
    d = radius - c
    out = []
    for k in range(3):
        a = math.pi / 2 + k * 2.0 * math.pi / 3.0
        cx, cy = d * math.cos(a), d * math.sin(a)
        for i in range(per_corner + 1):
            t = a - math.pi / 3 + (2.0 * math.pi / 3) * i / per_corner
            out.append((cx + c * math.cos(t), cy + c * math.sin(t)))
    return out


def resample_closed(plan, n):
    """Resample a closed 2D polygon to n points (even arc-length spacing)."""
    m = len(plan)
    seg = []
    total = 0.0
    for i in range(m):
        a, b = plan[i], plan[(i + 1) % m]
        d = math.hypot(b[0] - a[0], b[1] - a[1])
        seg.append(d)
        total += d
    out = []
    step = total / n
    acc = 0.0
    idx = 0
    walked = 0.0
    for k in range(n):
        target = k * step
        while walked + seg[idx] < target and idx < m - 1:
            walked += seg[idx]
            idx += 1
        t = 0.0 if seg[idx] < 1e-9 else (target - walked) / seg[idx]
        a, b = plan[idx], plan[(idx + 1) % m]
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def loft_plans(plans, heights, cap_start=False, cap_end=False, closed=True):
    """Skin a stack of equal-length plans into a solid."""
    sections = [[(x, y, z) for (x, y) in p] for p, z in zip(plans, heights)]
    return geo.loft(sections, closed_sections=closed, cap_start=cap_start, cap_end=cap_end)


def arc_pts(cx, cy, r, a0, a1, n, z=0.0):
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / (n - 1)),
             cy + r * math.sin(a0 + (a1 - a0) * i / (n - 1)), z) for i in range(n)]
