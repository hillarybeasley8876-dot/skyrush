"""Parks and plazas: lawn, paving, plane trees, lamp posts and benches."""
import math

from .. import plan, shapes
from ..parts2 import _cylinder


def _tree(ctx, x, z, h=8.0, rng=None):
    """A plane tree: pale trunk, two branches and a rounded canopy."""
    trunk_h = h * 0.42
    shapes.add_box(ctx.bag.bm("render"), (x, z), (0.42, 0.42), 0.0, trunk_h,
                   rot_deg=rng.uniform(0, 90) if rng else 0.0)
    shapes.add_blob(ctx.bag.bm("foliage"), (x, z), h * 0.68, h * 0.30, 0.85)
    shapes.add_blob(ctx.bag.bm("foliage"), (x + 0.4, z - 0.3), h * 0.52, h * 0.22, 0.8)


def _lamp(ctx, x, z, h=6.0):
    """A park lamp post with a warm head."""
    shapes.add_box(ctx.bag.bm("metal_dark"), (x, z), (0.16, 0.16), 0.0, h)
    shapes.add_box(ctx.bag.bm("emissive_warm"), (x, z), (0.55, 0.55), h, h + 0.22)
    shapes.add_box(ctx.bag.bm("metal_dark"), (x, z), (0.7, 0.7), h + 0.22, h + 0.34)


def _bench(ctx, x, z, ang=0.0):
    shapes.add_box(ctx.bag.bm("wood"), (x, z), (1.8, 0.5), 0.42, 0.52, rot_deg=ang)
    shapes.add_box(ctx.bag.bm("wood"), (x, z), (1.8, 0.12), 0.52, 0.95, rot_deg=ang)
    for dx in (-0.7, 0.7):
        shapes.add_box(ctx.bag.bm("metal_dark"), (x + dx * math.cos(math.radians(ang)),
                                                 z + dx * math.sin(math.radians(ang))),
                       (0.1, 0.5), 0.0, 0.42, rot_deg=ang)


def generate(ctx, block, frame, rng, records):
    """Lay out a park: lawn, a paved path along the frontage, trees, lamps and benches."""
    poly = [tuple(p) for p in block["polygon"]]
    s0, s1 = frame.s_range
    t0, t1 = frame.t_range
    # the lawn is laid tile by tile so it never covers a road or the water
    step = 8.0
    s = s0
    while s < s1 - 0.5:
        t = t0
        while t < t1 - 0.5:
            tile = plan.rectangle(frame, s, t, min(s + step, s1), min(t + step, t1))
            if plan.outside_water(tile, ctx.water) and plan.outside_roads(tile, ctx.roads, 0.0):
                shapes.add_prism(ctx.bag.bm("grass"), tile, 0.0, 0.14, cap_bottom=False)
            t += step
        s += step
    # a paved path along the frontage
    path = plan.rectangle(frame, s0, t0, s1, t0 + 4.0)
    if plan.outside_water(path, ctx.water) and plan.outside_roads(path, ctx.roads, 0.0):
        shapes.add_prism(ctx.bag.bm("paving"), path, 0.10, 0.22, cap_bottom=False)
    n_trees = max(3, int((s1 - s0) / 9.0))
    for i in range(n_trees):
        s = s0 + (s1 - s0) * (i + 0.5) / n_trees
        t = t0 + 6.0 + rng.uniform(0.0, max(1.0, t1 - t0 - 8.0))
        p = frame.to_city(s, t)
        _tree(ctx, p[0], p[1], rng.uniform(6.5, 9.5), rng)
    n_lamps = max(2, int((s1 - s0) / 22.0))
    for i in range(n_lamps):
        s = s0 + (s1 - s0) * (i + 0.5) / n_lamps
        p = frame.to_city(s, t0 + 2.0)
        _lamp(ctx, p[0], p[1], 5.5)
    for i in range(max(2, n_trees // 2)):
        s = s0 + (s1 - s0) * rng.uniform(0.05, 0.95)
        p = frame.to_city(s, t0 + 3.0)
        _bench(ctx, p[0], p[1], rng.uniform(0, 180))
    rec = {"style": block.get("style", "park"), "seed": rng.randrange(1, 9999),
           "ground": True, "poly":
           [[round(x, 2), round(z, 2)] for x, z in poly], "height": 0.2}
    rec["id"] = "%s_%d" % (block["id"], len(records))
    records.append(rec)
