"""Residential slabs: 18-30 storey blocks with repetitive balconies.

The facade uses the residential preset of the procedural shader (lit windows, blinds,
TV flicker); the balconies, the stair core and the roof aviation light are real geometry.
"""
import math

from .. import grid, plan, shapes
from ..parts import add_ground_floor
from ..parts2 import add_antenna, add_parapet, add_water_tank
from ..parts2 import add_aviation_light, edge_boxes
from ..parts3 import add_laundry_pole

GROUND_H = 3.4
FLOOR_H = 2.95
BAY_W = 3.3


def _balcony_band(ctx, fc, floors, origin):
    """A continuous balcony slab and railing on every floor of the street facade."""
    u0 = grid.wall_u(fc["a"][0], fc["a"][1], fc["n"], origin)
    u1 = grid.wall_u(fc["b"][0], fc["b"][1], fc["n"], origin)
    lo, hi = min(u0, u1), max(u0, u1)
    cells = list(grid.cell_range(lo, hi, BAY_W))
    if not cells:
        return
    a = grid.point_on_wall(cells[0] * BAY_W, fc, u0, u1)
    b = grid.point_on_wall((cells[-1] + 1) * BAY_W, fc, u0, u1)
    ang = math.degrees(math.atan2(fc["t"][1], fc["t"][0]))
    width = abs(u1 - u0)
    for f in range(1, floors):
        h = GROUND_H + (f - 1) * FLOOR_H
        mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
        c = (mid[0] + fc["n"][0] * 0.65, mid[1] + fc["n"][1] * 0.65)
        shapes.add_box(ctx.bag.bm("render"), c, (width, 1.3), h - 0.16, h, rot_deg=ang)
        outer = (mid[0] + fc["n"][0] * 1.25, mid[1] + fc["n"][1] * 1.25)
        # solid parapet with a thin capping rail
        shapes.add_box(ctx.bag.bm("metal_dark"), outer, (width, 0.08), h - 0.1, h + 0.95,
                       rot_deg=ang)
        shapes.add_box(ctx.bag.bm("metal_dark"), outer, (width, 0.14), h + 0.95, h + 1.02,
                       rot_deg=ang)
        # three balusters per balcony: the full row of balusters was 12 boxes
        # per floor and 50 % of the triangles of a residential block
        nbar = max(2, int(width / 12.0))
        for i in range(nbar + 1):
            p = grid.point_on_wall(lo + width * i / nbar, fc, u0, u1)
            shapes.add_box(ctx.bag.bm("metal_dark"), p, (0.09, 0.09), h - 0.1, h + 0.98)
        # laundry pole on some balconies
        if (f + cells[0]) % 5 == 0:
            p = grid.point_on_wall((cells[0] + 0.5) * BAY_W, fc, u0, u1)
            add_laundry_pole(ctx, p, fc["n"], 1.5, h + 0.25, 3)


def _core(ctx, poly, top, origin, rng):
    """A stair / lift core expressed as a slightly proud shaft on the facade."""
    fc = plan.facade(poly, 2)
    u0 = grid.wall_u(fc["a"][0], fc["a"][1], fc["n"], origin)
    u1 = grid.wall_u(fc["b"][0], fc["b"][1], fc["n"], origin)
    mid_u = (u0 + u1) * 0.5
    p = grid.point_on_wall(mid_u, fc, u0, u1)
    c = (p[0] + fc["n"][0] * 0.3, p[1] + fc["n"][1] * 0.3)
    ang = math.degrees(math.atan2(fc["t"][1], fc["t"][0]))
    shapes.add_box(ctx.bag.bm("render"), c, (5.0, 0.6), GROUND_H, top, rot_deg=ang)


def generate(ctx, block, frame, rng, records):
    """Lay out a residential slab block."""
    s0, s1 = frame.s_range
    t0, t1 = frame.t_range
    setback = float(block.get("setback", 3.0))
    front_t = t0 + setback
    hmin, hmax = block.get("height_m", [54.0, 90.0])
    spans = plan.frontage_lots(frame, 46.0, 9.0, rng, 0.2)
    depth = min(rng.uniform(15.0, 22.0), max(8.0, t1 - front_t))
    for ri, (ta, tb, front_edge) in enumerate(plan.depth_rows(front_t, t1, depth)):
        for (wa, wb) in spans:
            if not plan.fits(frame, wa, ta, wb, tb, margin=0.8, water=ctx.water, roads=ctx.roads):
                continue
            poly = plan.rectangle(frame, wa, ta, wb, tb)
            ctx.begin_building(poly)
            floors = int(rng.uniform(hmin, hmax) / FLOOR_H)
            area = (wb - wa) * (tb - ta)
            floors = max(6, min(30, floors, int(area / 130.0)))
            top = GROUND_H + floors * FLOOR_H
            shapes.add_prism(ctx.bag.bm("facade_res"), poly, GROUND_H, top, cap_bottom=False)
            # ground floor: lobby glazing and a couple of shop units
            fc = plan.facade(poly, 0)
            units = (6.0, 8.0) if ri == 0 else (10.0, 14.0)
            add_ground_floor(ctx, poly, front_edge, GROUND_H, "render", rng,
                             units[0], units[1])
            _balcony_band(ctx, fc, floors, ctx.origin)
            _core(ctx, poly, top, ctx.origin, rng)
            # roof: parapet, tanks, mast and the red aviation light
            add_parapet(ctx, poly, top, 1.1, 0.24, "render")
            cx = sum(p[0] for p in poly) / len(poly)
            cz = sum(p[1] for p in poly) / len(poly)
            add_water_tank(ctx, (cx - 2.0, cz - 1.5), 1.0, 1.5, 0.7)
            add_antenna(ctx, (cx + 2.0, cz + 1.0), 5.0, 3)
            add_aviation_light(ctx, (cx, cz), top + 1.1)
            rec = {"style": "residential_slab", "seed": rng.randrange(1, 9999), "floors": floors}
            rec["poly"] = [[round(x, 2), round(z, 2)] for x, z in poly]
            rec["height"] = top
            rec["id"] = "%s_%d" % (block["id"], len(records))
            records.append(rec)
            ctx.end_building()
