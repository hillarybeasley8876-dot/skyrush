"""Heritage stone blocks (1920s-30s Bund back rows): rusticated base, string courses,
cornices and warm window glow, all in granite.

The windows are real holes: the wall is built as pier and spandrel strips, the glass
sits 0.28 m inside the reveal and the granite architrave stands proud of the wall.
"""
import math

from .. import openings, plan, shapes
from ..parts2 import edge_boxes

FLOOR_H = 3.9
BASE_H = 3.6
REVEAL = 0.28          # how deep the window opening is
WALL_T = 0.50          # a heavy stone wall
ARCH_PROUD = 0.08
WIN_W = 1.35
WIN_H = 2.20
MIN_FLOORS = 6
MAX_FLOORS = 10


def _rustication(ctx, poly):
    """A rusticated stone base: three slightly proud courses."""
    for i in range(3):
        h0 = i * (BASE_H / 3.0)
        edge_boxes(ctx.bag.bm("granite"), poly, h0, h0 + BASE_H / 3.0 - 0.06,
                   0.22, offset=0.04 + 0.02 * i, edges=(0, 2))


def _windows(ctx, poly, floors, rng, skip=()):
    """Recessed windows with a real reveal, a granite architrave and warm interiors.

    The sides of a building in a row are party walls: they get no windows.
    """
    for edge in (0, 1, 2, 3):
        if edge in skip:
            continue
        fc = plan.facade(poly, edge)
        n_win = max(1, int(fc["w"] / 3.6))
        step = fc["w"] / n_win
        holes = []
        for f in range(floors):
            h0 = BASE_H + f * FLOOR_H + 0.75
            for i in range(n_win):
                u = step * (i + 0.5)
                holes.append(_window(ctx, fc, u, h0, rng))
        openings.build_facade(ctx.bag.bm("granite"), fc, holes, BASE_H,
                              BASE_H + floors * FLOOR_H, WALL_T)


def _window(ctx, fc, u, h0, rng):
    """One window: the pane 28 cm inside the reveal, the architrave 8 cm proud."""
    u0, u1 = u - WIN_W * 0.5, u + WIN_W * 0.5
    h1 = h0 + WIN_H
    lit = rng.random() < 0.32
    if lit:
        slot = ctx.random_cell("interior")
        uv = [(slot["u0"], slot["v0"]), (slot["u1"], slot["v0"]),
              (slot["u1"], slot["v1"]), (slot["u0"], slot["v1"])] if slot else None
        openings.add_pane(ctx, fc, u0, u1, h0, h1, REVEAL, "interior", uv=uv)
    else:
        openings.add_pane(ctx, fc, u0, u1, h0, h1, REVEAL, "glass")
    granite = ctx.bag.bm("granite")
    # the architrave: a sill, a head and two jambs, all proud of the wall
    openings.wall_slab(granite, fc, u0 - 0.20, u1 + 0.20, h0 - 0.22, h0 - 0.04,
                       -ARCH_PROUD, 0.02)
    openings.wall_slab(granite, fc, u0 - 0.20, u1 + 0.20, h1 + 0.04, h1 + 0.22,
                       -ARCH_PROUD, 0.02)
    if rng.random() < 0.35:
        # a keystone above the head
        openings.wall_slab(granite, fc, u - 0.22, u + 0.22, h1 + 0.22, h1 + 0.44,
                           -ARCH_PROUD - 0.02, 0.04)
    if lit:
        # a two-pane sash: two mullions beside the centre and a transom, so the glass
        # stays visible between them
        wood = ctx.bag.bm("wood")
        for side in (-1, 1):
            mu = u + side * WIN_W * 0.25
            openings.wall_slab(wood, fc, mu - 0.035, mu + 0.035, h0, h1,
                               REVEAL - 0.09, REVEAL - 0.02)
        openings.wall_slab(wood, fc, u0, u1, h0 + 1.32, h0 + 1.44, REVEAL - 0.09,
                           REVEAL - 0.02)
    return {"u0": u0, "u1": u1, "h0": h0, "h1": h1}


def _cornice(ctx, poly, top):
    """A deep cornice and a low attic parapet."""
    edge_boxes(ctx.bag.bm("granite"), poly, top - 0.4, top + 0.35, 0.55, offset=0.24)
    edge_boxes(ctx.bag.bm("granite"), poly, top + 0.35, top + 1.1, 0.3, offset=0.1)
    # the attic balustrade posts: the front and the back only, and one every 3 m
    # (a post every 1.2 m was 1600 triangles of granite per building)
    n = len(poly)
    cx = sum(p[0] for p in poly) / n
    cz = sum(p[1] for p in poly) / n
    for i in (0, 2):
        a = poly[i]
        b = poly[(i + 1) % n]
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        count = max(2, int(length / 1.2))
        for k in range(count + 1):
            t = k / float(count)
            px = a[0] + (b[0] - a[0]) * t
            pz = a[1] + (b[1] - a[1]) * t
            dx, dy = b[0] - a[0], b[1] - a[1]
            nx, nz = -dy / length, dx / length
            if (cx - px) * nx + (cz - pz) * nz < 0:
                nx, nz = -nx, -nz
            q = (px + nx * 0.1, pz + nz * 0.1)
            shapes.add_box(ctx.bag.bm("granite"), q, (0.12, 0.12), top + 0.35, top + 1.1,
                           rot_deg=math.degrees(math.atan2(dy, dx)))


def generate(ctx, block, frame, rng, records):
    """Lay out a heritage stone block along the frontage."""
    s0, s1 = frame.s_range
    t0, t1 = frame.t_range
    setback = float(block.get("setback", 1.5))
    hmin, hmax = block.get("height_m", [24.0, 40.0])
    front_t = t0 + setback
    spans = plan.frontage_lots(frame, 40.0, 9.0, rng, 0.2)
    depth = min(rng.uniform(16.0, 24.0), max(8.0, t1 - front_t))
    for (ta, tb, front_edge) in plan.depth_rows(front_t, t1, depth):
        for wi, (wa, wb) in enumerate(spans):
            if not plan.fits(frame, wa, ta, wb, tb, margin=0.5, water=ctx.water,
                             roads=ctx.roads):
                continue
            poly = plan.rectangle(frame, wa, ta, wb, tb)
            ctx.begin_building(poly)
            floors = int(rng.uniform(hmin, hmax) / FLOOR_H)
            area = (wb - wa) * (tb - ta)
            floors = max(4, min(MAX_FLOORS, floors, int(area / 150.0)))
            top = BASE_H + floors * FLOOR_H
            # the inner buildings of a row share their side walls with the neighbours
            skip = (1, 3) if len(spans) > 2 and 0 < wi < len(spans) - 1 else ()
            _rustication(ctx, poly)
            _windows(ctx, poly, floors, rng, skip)
            for f in range(1, floors):
                edge_boxes(ctx.bag.bm("granite"), poly, BASE_H + f * FLOOR_H - 0.12,
                           BASE_H + f * FLOOR_H + 0.12, 0.18, offset=0.05, edges=(0, 2))
            _cornice(ctx, poly, top)
            rec = {"style": "heritage", "seed": rng.randrange(1, 9999), "floors": floors}
            rec["poly"] = [[round(x, 2), round(z, 2)] for x, z in poly]
            rec["height"] = top + 1.1
            rec["id"] = "%s_%d" % (block["id"], len(records))
            records.append(rec)
            ctx.end_building()
