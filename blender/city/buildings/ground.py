"""Ground cover: the paving of a block and the strip between the block and the kerb.

The map's block polygons start well behind the sidewalk, so the ground between the
buildings and the road was bare - a black void from the air (lead note BL-ART4).  The
ground cover now runs from the block polygon out to the back of the sidewalk, with
tree pits, planters, bike racks and bins along the kerb.
"""
import math

from . import plan, shapes
from .parts3 import add_bike_rack, add_bin, add_kiosk, add_planter

KERB_H = 0.145
BLOCK_H = 0.12
GAP_MAX = 32.0        # how far the kerb strip reaches from the road
CELL = 4.0            # the grid of the kerb strip
TREE_SPACING = 13.0
FURNITURE_SPACING = 26.0


def _inside_block(frame, x, z):
    return frame.contains(x, z)


def _road_gap(x, z, grid):
    """(distance to the road edge, distance to the road centre line) or None."""
    best = None
    for seg in grid.near(x, z):
        (ax, az, bx, bz, hw) = seg
        d = plan.dist_to_poly((x, z), [(ax, az), (bx, bz)])
        if best is None or d - hw < best[0]:
            best = (d - hw, d, hw)
    return best


def block_paving(ctx, frame):
    """The paving inside the block polygon, clipped around the roads and the water."""
    s0, s1 = frame.s_range
    t0, t1 = frame.t_range
    step = 18.0
    s = s0
    while s < s1 - 0.3:
        t = t0
        while t < t1 - 0.3:
            tile = plan.rectangle(frame, s, t, min(s + step, s1), min(t + step, t1))
            if plan.outside_water(tile, ctx.water) and plan.outside_roads(tile, ctx.roads,
                                                                         0.0):
                # a flat quad, not a slab: the ground is never seen from the side and
                # a slab per tile was a fifth of the geometry of the city
                shapes.add_ground_quad(ctx.bag.bm("paving"), tile, BLOCK_H)
            t += step
        s += step


def kerb_strip(ctx, frame, grid, furniture=True):
    """The paving between the block polygon and the back of the sidewalk.

    The strip is the ground the map left bare; without it the city reads as a black
    void from the air and the buildings float.  It is a band along the edges of the
    block - the old version scanned the whole bounding box of the block plus 64 m,
    which paved ten times the area it had to.
    """
    poly = frame.poly
    n = len(poly)
    placed = 0
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        if length < 1.0:
            continue
        fc = plan.facade(poly, i)
        nx, nz = fc["n"]
        ux, uz = (b[0] - a[0]) / length, (b[1] - a[1]) / length
        s = 0.0
        while s < length - 0.05:
            w = min(CELL, length - s)
            mx = a[0] + ux * (s + w * 0.5)
            mz = a[1] + uz * (s + w * 0.5)
            gap = _road_gap(mx, mz, grid)
            if gap is not None and 0.0 < gap[0] < GAP_MAX:
                if plan.outside_water([(mx, mz)], ctx.water):
                    depth = min(GAP_MAX, gap[0])
                    d = 0.0
                    while d < depth - 0.05:
                        dd = min(CELL, depth - d)
                        p0 = (a[0] + ux * s + nx * d, a[1] + uz * s + nz * d)
                        p1 = (a[0] + ux * (s + w) + nx * d, a[1] + uz * (s + w) + nz * d)
                        q1 = (p1[0] + nx * dd, p1[1] + nz * dd)
                        q0 = (p0[0] + nx * dd, p0[1] + nz * dd)
                        shapes.add_ground_quad(ctx.bag.bm("paving"), [p0, p1, q1, q0], KERB_H)
                        placed += 1
                        d += dd
            s += w
    if furniture and placed:
        _kerb_furniture(ctx, frame, grid)
    return placed


def _kerb_furniture(ctx, frame, grid):
    """Planters, bike rows, bins and kiosks along the kerb of the block.

    The strip between the buildings and the road is the first thing a driver sees,
    so it is not left empty: a planter every 26 m, a bike row, a bin, and now and
    then a newspaper kiosk.
    """
    poly = frame.poly
    n = len(poly)
    k = 0
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        if length < 4.0:
            continue
        fc = plan.facade(poly, i)
        nx, nz = fc["n"]
        ux, uz = (b[0] - a[0]) / length, (b[1] - a[1]) / length
        s = 2.0
        while s < length - 2.0:
            p = (a[0] + ux * s + nx * 1.6, a[1] + uz * s + nz * 1.6)
            gap = _road_gap(p[0], p[1], grid)
            if gap is not None and 0.0 < gap[0] < GAP_MAX:
                k += 1
                if k % 7 == 0:
                    add_kiosk(ctx, p, nx, nz)
                elif k % 3 == 0:
                    add_planter(ctx, p, 1.3, 0.7, 0.5)
                elif k % 3 == 1:
                    add_bike_rack(ctx, p, 3)
                else:
                    add_bin(ctx, p)
            s += FURNITURE_SPACING
