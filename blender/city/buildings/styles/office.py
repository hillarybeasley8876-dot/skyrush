"""Office towers: 20-60 storey curtain-wall blocks with a podium, setbacks and a lit crown.

The shaft uses the office preset of the procedural facade shader (dark spandrel, cool
LED windows, dark whole floors); the podium, the crown edge lines and the aviation
light are real geometry.
"""
import math

from .. import plan, shapes
from ..parts2 import add_antenna, add_aviation_light, add_crown_strip
from ..parts2 import add_led_screen, add_mechanical_floor, add_parapet

PODIUM_H = 7.8
FLOOR_H = 3.9
CROWN_H = 0.9          # the crown strip must be readable at 300 m (art dossier 4.5)
AVIATION_MIN_H = 100.0  # every roof above this gets a red aviation light (ART.md 11)
MECHANICAL_H = 5.0     # the service band under the crown
WHITE_CROWN_SHARE = 0.5  # half of the generic towers wear the cool white LED crown

# Crown colour per district (brief: white/cyan/magenta per district palette).
DISTRICT_CROWN = {
    "D7": "emissive_cyan",      # Lujiazui - cool white/cyan
    "D5": "emissive_warm",      # Jing'an - warm gold
    "D3": "emissive_magenta",   # Huangpu - magenta accents
    "D2": "emissive_magenta",
}
DEFAULT_CROWN = "emissive_cyan"


def _podium(ctx, poly, rng, rec):
    """The podium: dark stone base, a glazed lobby band and a canopy."""
    ctx.wall_key = "granite"
    base = plan.facade(poly, 0)
    shapes.add_prism(ctx.bag.bm("granite"), poly, 0.0, 1.2, cap_bottom=False)
    shapes.add_prism(ctx.bag.bm("facade_office"), poly, 1.2, PODIUM_H, cap_bottom=False)
    # glazed lobby on the street side
    glass = ctx.bag.bm("glass")
    n_units = max(1, int(base["w"] / 6.0))
    unit = base["w"] / n_units
    for i in range(n_units):
        p = (base["a"][0] + base["t"][0] * unit * i, base["a"][1] + base["t"][1] * unit * i)
        shapes.add_wall_quad(glass, p, base["n"], unit - 0.3, 0.6, 4.2)
        # canopy over the entrance
        if i == n_units // 2:
            c = (p[0] + base["n"][0] * 1.4, p[1] + base["n"][1] * 1.4)
            shapes.add_box(ctx.bag.bm("metal_galv"), c, (unit - 0.6, 3.0), 4.2, 4.4,
                           rot_deg=math.degrees(math.atan2(base["t"][1], base["t"][0])))
    # a banner sign on the podium
    if rng.random() < 0.5:
        add_led_screen(ctx, base["a"], base["n"], min(9.0, base["w"] * 0.5), 3.4)


def _setback_poly(poly, factor):
    """Shrink a rectangle towards its centre."""
    cx = sum(p[0] for p in poly) / len(poly)
    cz = sum(p[1] for p in poly) / len(poly)
    return [(cx + (x - cx) * factor, cz + (z - cz) * factor) for x, z in poly]


def generate(ctx, block, frame, rng, records):
    """Lay out an office tower block: 1-3 towers with lit crowns."""
    s0, s1 = frame.s_range
    t0, t1 = frame.t_range
    setback = float(block.get("setback", 3.0))
    hmin, hmax = block.get("height_m", [80.0, 240.0])
    crown_key = DISTRICT_CROWN.get(block.get("district", ""), DEFAULT_CROWN)
    span = s1 - s0
    n_towers = 3 if span > 80.0 else (2 if span > 50.0 else 1)
    for tower in range(n_towers):
        _tower(ctx, block, frame, rng, records, tower, n_towers, crown_key, s0, s1, t0, t1,
               setback, hmin, hmax)


def _tower(ctx, block, frame, rng, records, index, count, crown_key, s0, s1, t0, t1,
           setback, hmin, hmax):
    """One office tower of the block."""
    span = (s1 - s0) / count
    cx0 = s0 + span * (index + 0.5)
    cz0 = t0 + setback + (t1 - t0 - setback) * 0.42
    avail = t1 - t0 - setback
    w = min(rng.uniform(26.0, 46.0), span - 6.0)
    d = min(rng.uniform(24.0, 42.0), avail * 0.85)
    if avail > span:
        # the parcel is deeper than it is wide: the tower turns 90 degrees
        w, d = d, w
    if w < 14.0 or d < 14.0:
        # a small parcel: a smaller tower, but never nothing at all
        w = min(max(span - 4.0, 10.0), span)
        d = min(max(avail * 0.8, 10.0), avail)
        if w < 8.0 or d < 8.0:
            return
    poly = plan.rectangle(frame, cx0 - w * 0.5, cz0 - d * 0.5, cx0 + w * 0.5, cz0 + d * 0.5)
    if not plan.fits(frame, cx0 - w * 0.5, cz0 - d * 0.5, cx0 + w * 0.5, cz0 + d * 0.5, margin=1.0, water=ctx.water, roads=ctx.roads):
        return
    ctx.begin_building(poly)
    floors = int(rng.uniform(hmin, hmax) / FLOOR_H)
    # a small parcel cannot carry a 60 storey tower on 200 m2
    floors = max(8, min(60, floors, int(w * d / 220.0)))
    _podium(ctx, poly, rng, {})
    # shaft with one or two setbacks
    top = PODIUM_H
    cur = poly
    remaining = floors
    steps = 2 if rng.random() < 0.55 else 1
    heights = []
    if steps == 1:
        heights = [remaining]
    else:
        first = int(remaining * rng.uniform(0.45, 0.6))
        heights = [first, remaining - first]
    section_bottom = top
    for i, fl in enumerate(heights):
        h = top + fl * FLOOR_H
        if i == len(heights) - 1:
            section_bottom = top
        shapes.add_prism(ctx.bag.bm("facade_office"), cur, top, h, cap_bottom=False)
        top = h
        if i < len(heights) - 1:
            cur = _setback_poly(cur, rng.uniform(0.72, 0.86))
    # half of the generic towers wear the cool white LED crown and edge lines
    white = rng.random() < WHITE_CROWN_SHARE
    if white:
        crown_key = "emissive_white"
        for (px, pz) in cur:
            shapes.add_box(ctx.bag.bm(crown_key), (px, pz), (0.4, 0.4),
                           section_bottom, top + 1.2)
    # the mechanical floor: a service band, not a pale cap
    add_mechanical_floor(ctx, cur, top - MECHANICAL_H, MECHANICAL_H, crown_key)
    # crown: a proud cap and a wide emissive edge line (readable at 300 m)
    shapes.add_prism(ctx.bag.bm("granite"), cur, top, top + 1.2, cap_bottom=False)
    add_crown_strip(ctx, cur, top + 1.2, CROWN_H, 0.5, crown_key)
    add_crown_strip(ctx, cur, top, 0.3, 0.35, crown_key)
    add_parapet(ctx, cur, top, 0.8, 0.2, "granite")
    cx = sum(p[0] for p in cur) / len(cur)
    cz = sum(p[1] for p in cur) / len(cur)
    if top > AVIATION_MIN_H:
        add_aviation_light(ctx, (cx, cz), top + 1.2)
    if rng.random() < 0.6:
        add_antenna(ctx, (cx + 2.0, cz), rng.uniform(4.0, 9.0), 4)
    rec = {"style": "office_tower", "seed": rng.randrange(1, 9999), "floors": floors,
           "crown": crown_key, "district": block.get("district", "")}
    rec["poly"] = [[round(x, 2), round(z, 2)] for x, z in poly]
    rec["height"] = top + 1.7
    rec["id"] = "%s_%d" % (block["id"], len(records))
    records.append(rec)
    ctx.end_building()
