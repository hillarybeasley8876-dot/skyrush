"""Industrial blocks (west edge): warehouses in blue corrugated steel, sound walls and
billboards on poles."""
import math

from .. import plan, shapes
from ..parts2 import add_antenna, add_led_screen, edge_boxes


def _warehouse(ctx, poly, rng, rec):
    """A corrugated steel shed with a shallow gable roof and a roller shutter."""
    top = rng.uniform(8.0, 14.0)
    shapes.add_prism(ctx.bag.bm("corrugated"), poly, 0.0, top, cap_bottom=False)
    w = math.hypot(poly[1][0] - poly[0][0], poly[1][1] - poly[0][1])
    d = math.hypot(poly[2][0] - poly[1][0], poly[2][1] - poly[1][1])
    ridge = top + rng.uniform(1.2, 2.4)
    shapes.add_gable_roof(ctx.bag.bm("metal_galv"), poly, top, ridge,
                          ridge_edge=0 if w >= d else 1, overhang=0.5)
    # roller shutter door on the street side
    fc = plan.facade(poly, 0)
    door_w = min(6.0, fc["w"] * 0.5)
    u = (fc["w"] - door_w) * 0.5
    p = (fc["a"][0] + fc["t"][0] * u, fc["a"][1] + fc["t"][1] * u)
    ang = math.degrees(math.atan2(fc["t"][1], fc["t"][0]))
    shapes.add_box(ctx.bag.bm("metal_galv"), p, (door_w, 0.12), 0.0, 4.2, rot_deg=ang)
    shapes.add_box(ctx.bag.bm("metal_dark"), p, (door_w + 0.3, 0.2), 4.2, 4.6, rot_deg=ang)
    # wall vents
    for i in range(3):
        u = fc["w"] * (0.2 + 0.3 * i)
        q = (fc["a"][0] + fc["t"][0] * u, fc["a"][1] + fc["t"][1] * u)
        shapes.add_box(ctx.bag.bm("metal_galv"), q, (1.2, 0.1), top - 1.6, top - 0.9,
                       rot_deg=ang)
    rec["height"] = ridge


def _billboard(ctx, frame, rng):
    """A tall pole with a big advertising board at the block edge."""
    s0, s1 = frame.s_range
    t0, t1 = frame.t_range
    s = s0 + (s1 - s0) * rng.uniform(0.2, 0.8)
    t = t0 + (t1 - t0) * 0.12
    px, pz = frame.to_city(s, t)
    h = rng.uniform(9.0, 14.0)
    shapes.add_box(ctx.bag.bm("metal_dark"), (px, pz), (0.55, 0.55), 0.0, h)
    normal = (0.0, -1.0)
    add_led_screen(ctx, (px, pz), normal, rng.uniform(8.0, 13.0), rng.uniform(4.0, 6.0))


def generate(ctx, block, frame, rng, records):
    """Lay out an industrial block: warehouses plus roadside billboards."""
    s0, s1 = frame.s_range
    t0, t1 = frame.t_range
    setback = float(block.get("setback", 4.0))
    front_t = t0 + setback
    spans = plan.frontage_lots(frame, 50.0, 9.0, rng, 0.2)
    depth = min(rng.uniform(20.0, 40.0), max(8.0, t1 - front_t))
    for (ta, tb, front_edge) in plan.depth_rows(front_t, t1, depth):
        for (wa, wb) in spans:
            if not plan.fits(frame, wa, ta, wb, tb, margin=1.0, water=ctx.water, roads=ctx.roads):
                continue
            poly = plan.rectangle(frame, wa, ta, wb, tb)
            ctx.begin_building(poly)
            rec = {"style": "industrial", "seed": rng.randrange(1, 9999)}
            _warehouse(ctx, poly, rng, rec)
            rec["poly"] = [[round(x, 2), round(z, 2)] for x, z in poly]
            rec["id"] = "%s_%d" % (block["id"], len(records))
            records.append(rec)
            ctx.end_building()
    # a sound wall along the street edge
    if rng.random() < 0.6 and t1 - t0 > 12.0:
        wall = plan.rectangle(frame, s0 + 2.0, t0 + 1.0, s1 - 2.0, t0 + 1.5)
        edge_boxes(ctx.bag.bm("corrugated"), wall, 0.0, rng.uniform(3.0, 5.0), 0.4, offset=0.0)
    for _ in range(rng.randint(1, 3)):
        _billboard(ctx, frame, rng)
