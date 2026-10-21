"""Nanjing-Rd style neon street: midrise blocks buried under vertical neon blades.

Blades are 1.0-1.5 m wide and 3-8 m tall, stacked on both sides of the street, with the
shop names baked into the neon atlas.  Big LED screens sit above the shopfronts.
"""
import math

from .. import plan, shapes
from ..parts import add_ground_floor
from ..parts2 import add_blade_sign, add_led_screen, add_parapet, add_roof_clutter
from ..parts2 import add_water_tank
from . import midrise

BLADE_COLORS = ("red", "magenta", "cyan", "yellow", "green")


def _blades_on_wall(ctx, fc, floors, rng, face="both"):
    """Stacked vertical blade signs on one facade.

    2-4 blades per 10 m of frontage, bottom at 3.6 m, stacked up to the 4th-6th floor.
    """
    n_blades = max(2, int(fc["w"] / 10.0 * 3.0))
    for i in range(n_blades):
        u = fc["w"] * (i + 0.5) / n_blades
        p = (fc["a"][0] + fc["t"][0] * u, fc["a"][1] + fc["t"][1] * u)
        bottom = 3.6
        for _ in range(rng.randint(1, 3)):
            height = rng.uniform(3.0, 8.0)
            if bottom + height > floors * 2.95:
                break
            add_blade_sign(ctx, p, fc["n"], rng.uniform(1.0, 1.5), height, bottom)
            bottom += height + 0.35


def _signage(ctx, poly, rng, floors):
    """Blade signs and LED screens on the two street-facing walls."""
    for edge in (0, 1):
        fc = plan.facade(poly, edge)
        if fc["w"] < 8.0:
            continue
        _blades_on_wall(ctx, fc, floors, rng)
        if rng.random() < 0.6:
            add_led_screen(ctx, fc["a"], fc["n"], rng.uniform(8.0, 16.0), rng.uniform(6.0, 14.0))


def add_frontage_neon(ctx, poly, front_edge, floors, rng):
    """Give a block of another style the Nanjing-Rd neon frontage (dossier D2)."""
    fc = plan.facade(poly, front_edge)
    if fc["w"] < 8.0:
        return
    _blades_on_wall(ctx, fc, floors, rng)
    if rng.random() < 0.6:
        add_led_screen(ctx, fc["a"], fc["n"], rng.uniform(8.0, 16.0), rng.uniform(6.0, 14.0))


def generate(ctx, block, frame, rng, records):
    """Lay out a neon street block."""
    s0, s1 = frame.s_range
    t0, t1 = frame.t_range
    setback = float(block.get("setback", 1.0))
    front_t = t0 + setback
    hmin, hmax = block.get("height_m", [18.0, 42.0])
    spans = plan.frontage_lots(frame, 20.0, 8.0, rng, 0.25)
    depth = min(rng.uniform(16.0, 24.0), max(8.0, t1 - front_t))
    for ri, (ta, tb, front_edge) in enumerate(plan.depth_rows(front_t, t1, depth)):
        for (wa, wb) in spans:
            if not plan.fits(frame, wa, ta, wb, tb, margin=0.4, water=ctx.water, roads=ctx.roads):
                continue
            poly = plan.rectangle(frame, wa, ta, wb, tb)
            ctx.begin_building(poly)
            floors = int(rng.uniform(hmin, hmax) / midrise.FLOOR_H)
            area = (wb - wa) * (tb - ta)
            floors = max(4, min(12, floors, int(area / 110.0)))
            top = midrise.GROUND_H + floors * midrise.FLOOR_H
            ctx.wall_key = "tile"
            shapes.add_prism(ctx.bag.bm("facade_res"), poly, midrise.GROUND_H, top, cap_bottom=False)
            units = (4.0, 6.0) if ri == 0 else (7.0, 11.0)
            add_ground_floor(ctx, poly, front_edge, midrise.GROUND_H, "tile", rng,
                             units[0], units[1])
            _signage(ctx, poly, rng, floors)
            add_parapet(ctx, poly, top, 0.9, 0.22, "render")
            cx = sum(p[0] for p in poly) / len(poly)
            cz = sum(p[1] for p in poly) / len(poly)
            add_water_tank(ctx, (cx - 2.0, cz - 1.0), 0.9, 1.4, 0.6)
            add_roof_clutter(ctx, poly, top, rng, 2)
            rec = {"style": "neon_street", "seed": rng.randrange(1, 9999), "floors": floors}
            rec["poly"] = [[round(x, 2), round(z, 2)] for x, z in poly]
            rec["height"] = top
            rec["id"] = "%s_%d" % (block["id"], len(records))
            records.append(rec)
            ctx.end_building()
