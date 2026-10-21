"""Occluder boxes for the world unit.

The old occluder was the axis-aligned bounding box of the rotated footprint, so it
overhung the pavement by up to 25 m and could cull a car standing behind a corner.
The box is now the LARGEST AXIS-ALIGNED BOX that fits inside the real footprint, so
it never covers anything that is not the building.
"""
import math


def _inside(poly, x, z):
    """Even-odd point in polygon test."""
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if ((zi > z) != (zj > z)) and (x < (xj - xi) * (z - zi) / (zj - zi + 1e-12) + xi):
            inside = not inside
        j = i
    return inside


def _largest_rectangle(grid, rows, cols):
    """The largest all-ones rectangle of a binary grid: (area, i0, j0, w, h)."""
    best = (0, 0, 0, 0, 0)
    heights = [0] * cols
    for j in range(rows):
        for i in range(cols):
            heights[i] = heights[i] + 1 if grid[j][i] else 0
        stack = []
        for i in range(cols + 1):
            h = heights[i] if i < cols else 0
            start = i
            while stack and stack[-1][1] >= h:
                s, sh = stack.pop()
                area = sh * (i - s)
                if area > best[0]:
                    best = (area, s, j - sh + 1, i - s, sh)
                start = s
            stack.append((start, h))
    return best


def inscribed_box(poly, res=28):
    """(cx, cz, width, depth) of the largest axis-aligned box inside the polygon."""
    xs = [p[0] for p in poly]
    zs = [p[1] for p in poly]
    x0, x1 = min(xs), max(xs)
    z0, z1 = min(zs), max(zs)
    if x1 - x0 < 1e-6 or z1 - z0 < 1e-6:
        return (x0, z0, 0.0, 0.0)
    dx = (x1 - x0) / res
    dz = (z1 - z0) / res
    grid = []
    for j in range(res):
        z = z0 + (j + 0.5) * dz
        grid.append([1 if _inside(poly, x0 + (i + 0.5) * dx, z) else 0
                     for i in range(res)])
    area, i0, j0, w, h = _largest_rectangle(grid, res, res)
    if area == 0:
        return (x0, z0, x1 - x0, z1 - z0)
    cx = x0 + (i0 + w * 0.5) * dx
    cz = z0 + (j0 + h * 0.5) * dz
    return (cx, cz, w * dx, h * dz)
