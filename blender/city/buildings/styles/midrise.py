"""Midrise blocks: 6-12 storey 1980s-2000s walk-ups with ground-floor shops.

White/beige glazed tile or grey render above a hand-built shopfront band; AC units
under the windows, window security cages, small balconies, and a cluttered roof with
water tanks, antennas and the odd rooftop billboard frame.

The AC units and the cages are placed on the facade shader's own window grid, and the
grid origin is the 128 m cell of the building - the same origin the shader uses.
"""
import math

from .. import grid, plan, shapes
from ..parts import add_balcony, add_ground_floor
from ..parts2 import add_antenna, add_led_screen, add_parapet
from ..parts2 import add_roof_clutter, add_water_tank
from ..parts2 import edge_boxes
from ..parts3 import add_ac_unit, add_window_cage

GROUND_H = 3.4
FLOOR_H = 2.95
BAY_W = 3.3
WIN_FRAC = 0.55          # the shader's window fraction inside one bay
SILL_FRAC = 0.30
AC_GAP = 0.25            # the AC unit hangs 25 cm below the window sill
CAGE_PAD = 0.05          # the cage frames the window with 5 cm on each side


def _assert_on_facade(point, poly, limit):
    """Guard: a wall prop must sit on its own building's facade, not on a tile border."""
    d = plan.dist_to_poly(point, poly)
    if d > limit:
        raise AssertionError("clutter %.2f m from its facade (limit %.2f)" % (d, limit))


def _facade_clutter(ctx, poly, floors, rng, origin, wall_key):
    """AC units, cages and balconies placed on the facade shader's window grid.

    Only the street side and the back: the two sides of a building in a row are
    party walls, and an AC unit on a party wall is never seen.
    """
    for edge in (0, 2):
        fc = plan.facade(poly, edge)
        u0 = grid.wall_u(fc["a"][0], fc["a"][1], fc["n"], origin)
        u1 = grid.wall_u(fc["b"][0], fc["b"][1], fc["n"], origin)
        cells = grid.cell_range(u0, u1, BAY_W)
        for f in range(1, floors + 1):
            h0 = f * FLOOR_H
            sill = h0 + SILL_FRAC * FLOOR_H
            for k in cells:
                wu0, wu1 = grid.window_rect(k, BAY_W, WIN_FRAC, SILL_FRAC)
                if wu1 < min(u0, u1) or wu0 > max(u0, u1):
                    continue
                mid = (wu0 + wu1) * 0.5
                p = grid.point_on_wall(mid, fc, u0, u1)
                _assert_on_facade(p, poly, 0.6)
                # an AC unit hangs under the sill, centred on the window: the
                # street side carries most of them, the back a few
                rate = 0.20 if edge == 0 else 0.05
                if rng.random() < rate:
                    add_ac_unit(ctx, p, fc["n"], sill - AC_GAP - 0.62, 0.8)
                if rng.random() < 0.05:
                    add_window_cage(ctx, p, fc["n"], wu1 - wu0 + 2 * CAGE_PAD, sill,
                                    sill + WIN_FRAC * FLOOR_H)


def _balconies(ctx, poly, floors, rng, origin):
    """Small cantilevered balconies on the street facade."""
    fc = plan.facade(poly, 0)
    u0 = grid.wall_u(fc["a"][0], fc["a"][1], fc["n"], origin)
    u1 = grid.wall_u(fc["b"][0], fc["b"][1], fc["n"], origin)
    for f in range(1, floors + 1):
        if f > 2:
            # a balcony on the tenth floor is a dot from the street
            break
        if rng.random() > 0.55:
            continue
        h = GROUND_H + (f - 1) * FLOOR_H
        for k in grid.cell_range(u0, u1, BAY_W):
            wu0, wu1 = grid.window_rect(k, BAY_W, WIN_FRAC, SILL_FRAC)
            if wu1 < min(u0, u1) or wu0 > max(u0, u1):
                continue
            p = grid.point_on_wall((wu0 + wu1) * 0.5, fc, u0, u1)
            _assert_on_facade(p, poly, 1.4)
            add_balcony(ctx, p, fc["n"], wu1 - wu0, 1.1, 0.16)


def _roof(ctx, poly, top, rng):
    add_parapet(ctx, poly, top, 1.0, 0.22, "render")
    cx = sum(p[0] for p in poly) / len(poly)
    cz = sum(p[1] for p in poly) / len(poly)
    add_water_tank(ctx, (cx - 3.0, cz - 2.0), 1.0, 1.6, 0.8)
    if rng.random() < 0.6:
        add_antenna(ctx, (cx + 2.5, cz + 1.5), rng.uniform(3.0, 5.5), 3)
    add_roof_clutter(ctx, poly, top, rng, 3)
    # a lit rooftop billboard frame on every fifth roof
    if rng.random() < 0.2:
        fc = plan.facade(poly, 0)
        add_led_screen(ctx, fc["a"], fc["n"], rng.uniform(6.0, 9.0), rng.uniform(3.0, 4.5))


def generate(ctx, block, frame, rng, records):
    """Lay out a midrise block: a row of slab blocks along the frontage, maybe a back row."""
    from ..variety import NeighbourGuard
    s0, s1 = frame.s_range
    t0, t1 = frame.t_range
    setback = float(block.get("setback", 2.0))
    front_t = t0 + setback
    hmin, hmax = block.get("height_m", [18.0, 36.0])
    spans = plan.frontage_lots(frame, 24.0, 9.0, rng, 0.25)
    depth = min(rng.uniform(17.0, 25.0), max(8.0, t1 - front_t))
    rows = plan.depth_rows(front_t, t1, depth)
    for ri, (ta, tb, front_edge) in enumerate(rows):
        for (wa, wb) in spans:
            if tb - ta < 8.0 or not plan.fits(frame, wa, ta, wb, tb, margin=0.5,
                                              water=ctx.water, roads=ctx.roads):
                continue
            poly = plan.rectangle(frame, wa, ta, wb, tb)
            ctx.begin_building(poly)
            floors = int(rng.uniform(hmin, hmax) / FLOOR_H)
            # a small parcel cannot carry a 12 storey slab: the floors follow the
            # footprint (about 110 m2 of floor area per storey)
            area = (wb - wa) * (tb - ta)
            floors = max(4, min(12, floors, int(area / 110.0)))
            wall_key = "tile" if rng.random() < 0.55 else "render"
            rec = {"style": "midrise", "seed": rng.randrange(1, 9999), "floors": floors,
                   "wall": wall_key}
            top = GROUND_H + floors * FLOOR_H
            shapes.add_prism(ctx.bag.bm("facade_res"), poly, GROUND_H, top, cap_bottom=False)
            guard = getattr(ctx, "guard", None) or NeighbourGuard()
            # the rows behind the first are alleys: half the shopfronts
            units = (4.0, 6.5) if ri == 0 else (7.0, 11.0)
            add_ground_floor(ctx, poly, front_edge, GROUND_H, wall_key, rng,
                             units[0], units[1], guard=guard)
            _facade_clutter(ctx, poly, floors, rng, ctx.origin, wall_key)
            _balconies(ctx, poly, floors, rng, ctx.origin)
            _roof(ctx, poly, top, rng)
            rec["poly"] = [[round(x, 2), round(z, 2)] for x, z in poly]
            rec["height"] = top
            rec["id"] = "%s_%d" % (block["id"], len(records))
            records.append(rec)
            ctx.end_building()
