"""Reusable building parts: shopfronts, awnings, balconies and the ground floor.

The ground floor is a real alcove: the shopfront glazing sits RECESS behind the
building's face, with side reveals and a soffit, so the street reads as depth and
the three closed sides of the building stay closed.

A shopfront is one of six templates (open glass with an interior card, a closed
roller shutter, a half shutter, a grille gate, a kiosk window, a restaurant with
stools) - the neighbouring guard makes sure two modules in a row are never the same.
"""
import math

import bmesh

from . import shapes
from .kit import MATS

RECESS = 1.05          # how deep the shopfront sits behind the building face
FASCIA_H = 1.1         # the wall band above the shop glazing
GLASS_BOTTOM = 0.45    # stall riser height
GLASS_TOP = 0.30       # glazing height below the fascia
GLASS_DEPTH = 0.10     # the glass sits 10 cm behind the face
CARD_GAP = 0.70        # the interior card is 70 cm behind the glass
# the shopfront templates and their weights (a closed shop is ~30 % at 1 a.m.)
TEMPLATES = (("glass", 45), ("restaurant", 15), ("kiosk", 10), ("grille", 12),
             ("half_shutter", 10), ("shutter", 8))


def _quad_uv(slot, flip_v=False):
    """UV rect of an atlas slot as 4 (u, v) pairs (bottom-left, bottom-right, top-right, top-left)."""
    u0, v0, u1, v1 = slot["u0"], slot["v0"], slot["u1"], slot["v1"]
    if flip_v:
        v0, v1 = v1, v0
    return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]


def _rect_uv(rect):
    """The 4 (u, v) pairs of an atlas rect (u0, v0, u1, v1)."""
    u0, v0, u1, v1 = rect
    return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]


def bpy_math_offset(base, normal, d):
    """Move a city point `d` metres along a 2D normal."""
    return (base[0] + normal[0] * d, base[1] + normal[1] * d)


def _weighted_choice(rng, options):
    """A weighted random pick from ((name, weight), ...)."""
    total = sum(w for _n, w in options)
    pick = rng.uniform(0.0, total)
    acc = 0.0
    for name, weight in options:
        acc += weight
        if pick <= acc:
            return name
    return options[-1][0]


def add_shopfront(ctx, base, normal, width, ground_h=3.4, sign_key="neon_h",
                  template="glass", recess=RECESS, fascia="lightbox"):
    """One shop in a recessed bay.

    `base` is the city (x, z) of the LEFT edge of the unit on the building face; the
    glazing is `recess` metres behind that face.  The template decides whether the
    shop is open (a glass front with an interior card 70 cm behind it), a closed
    roller shutter, a half shutter, a grille gate, a kiosk window or a restaurant.
    """
    tm = shapes.wall_tangent(normal)
    ang = math.degrees(math.atan2(tm[1], tm[0]))
    shop_h = ground_h - FASCIA_H
    glass_h = shop_h - GLASS_TOP - GLASS_BOTTOM
    glass_top = GLASS_BOTTOM + glass_h
    # The interior card: a shop interior, not a flat panel.  A wide shopfront is
    # split into several cards of at most 2.0 m, so the atlas cell always covers
    # 2.0 m and the shop reaches 256 px/m (one cell over 5 m was 79 px/m).
    card_depth = GLASS_DEPTH + CARD_GAP
    span = width - 0.1
    n_cards = max(1, int(math.ceil(span / 2.0)))
    card_w = span / n_cards
    for k in range(n_cards):
        slot = ctx.random_cell("shop_interior")
        uv = _quad_uv(slot) if slot else None
        cbase = (base[0] + tm[0] * k * card_w, base[1] + tm[1] * k * card_w)
        gbase = bpy_math_offset(cbase, normal, -card_depth)
        shapes.add_wall_quad(ctx.bag.bm("shop_interior"), gbase, normal, card_w,
                             GLASS_BOTTOM, glass_top - 0.05, uv=uv)
    # the glass, the shutter or the grille in the opening
    if template == "shutter":
        _shutter(ctx, base, normal, width, 0.0, shop_h)
    elif template == "half_shutter":
        _shutter(ctx, base, normal, width, 0.0, GLASS_BOTTOM + glass_h * 0.55)
        _glass(ctx, base, normal, width, GLASS_BOTTOM + glass_h * 0.55, shop_h)
    elif template == "grille":
        _glass(ctx, base, normal, width, GLASS_BOTTOM, glass_top)
        _grille(ctx, base, normal, width, GLASS_BOTTOM, glass_top)
    elif template == "kiosk":
        kw = min(width - 0.6, 1.2)
        kbase = bpy_math_offset(base, normal, -GLASS_DEPTH)
        kbase = (kbase[0] + tm[0] * (width - kw) * 0.5, kbase[1] + tm[1] * (width - kw) * 0.5)
        shapes.add_wall_quad(ctx.bag.bm("shop_glass"), kbase, normal, kw, GLASS_BOTTOM + 0.5,
                             glass_top, uv=None)
        shapes.add_box(ctx.bag.bm("render"),
                       bpy_math_offset(base, normal, -GLASS_DEPTH - 0.18),
                       (width, 0.36), GLASS_BOTTOM, GLASS_BOTTOM + 0.5, rot_deg=ang)
    elif template == "restaurant":
        _glass(ctx, base, normal, width, GLASS_BOTTOM, glass_top)
        # a counter and two stools in the opening
        shapes.add_box(ctx.bag.bm("render"), bpy_math_offset(base, normal, -0.35),
                       (width - 0.3, 0.5), GLASS_BOTTOM, GLASS_BOTTOM + 0.95, rot_deg=ang)
        for i in range(2):
            p = bpy_math_offset((base[0] + tm[0] * width * (0.3 + 0.4 * i),
                                 base[1] + tm[1] * width * (0.3 + 0.4 * i)), normal, -0.75)
            shapes.add_box(ctx.bag.bm("wood"), p, (0.34, 0.34), 0.0, 0.62, rot_deg=ang)
    else:
        _glass(ctx, base, normal, width, GLASS_BOTTOM, glass_top)
    # the stall riser and the side reveals - they close the alcove and show its depth
    shapes.add_box(ctx.bag.bm("render"), bpy_math_offset(base, normal, -recess * 0.5),
                   (width, recess), 0.0, GLASS_BOTTOM, rot_deg=ang)
    for side in (-1, 1):
        p = (base[0] + tm[0] * (width * 0.5 * side + width * 0.5),
             base[1] + tm[1] * (width * 0.5 * side + width * 0.5))
        shapes.add_box(ctx.bag.bm(ctx.wall_key), bpy_math_offset(p, normal, -recess * 0.5),
                       (0.14, recess), 0.0, shop_h, rot_deg=ang)
    # the door, recessed behind the glazing line
    door_w = min(1.1, width * 0.35)
    door_x = base[0] + tm[0] * (width - door_w - 0.25)
    door_z = base[1] + tm[1] * (width - door_w - 0.25)
    dbase = bpy_math_offset((door_x, door_z), normal, -(recess - 0.15))
    shapes.add_box(ctx.bag.bm("wood"), dbase, (door_w, 0.12), 0.0, 2.35, rot_deg=ang)
    _fascia(ctx, base, normal, width, ground_h, sign_key, fascia)
    return shop_h


# the fascia templates: the sign band above the shopfront.  A street of shops in
# Shanghai carries all of them, and two neighbouring shops never share one.
FASCIA_TEMPLATES = (("lightbox", 30), ("red_board", 22), ("channel", 18),
                    ("led_strip", 16), ("painted", 14))


def _fascia(ctx, base, normal, width, ground_h, sign_key, template):
    """The sign band above a shopfront, in one of five templates."""
    sign_key = "neon_red" if template == "red_board" else sign_key
    slot = ctx.next_sign(sign_key)
    if slot is None:
        return
    aspect = float(slot.get("aspect", 4.0))
    sign_w = max(1.0, width - 0.3)
    sign_h = min(FASCIA_H - 0.12, sign_w / aspect)
    t = shapes.wall_tangent(normal)
    ang = math.degrees(math.atan2(t[1], t[0]))
    if template == "channel":
        # 3D channel letters on a rail: the letters stand 9 cm off the rail
        rail = bpy_math_offset(base, normal, 0.05)
        shapes.add_box(ctx.bag.bm("metal_dark"), rail, (sign_w + 0.1, 0.10),
                       ground_h - sign_h - 0.14, ground_h - 0.02, rot_deg=ang)
        sbase = bpy_math_offset(base, normal, 0.12)
        shapes.add_wall_quad(ctx.bag.bm(sign_key), sbase, normal, sign_w,
                             ground_h - sign_h - 0.06, ground_h - 0.06, uv=_quad_uv(slot))
        return
    if template == "led_strip":
        # an LED strip in a metal channel
        strip = bpy_math_offset(base, normal, 0.05)
        shapes.add_box(ctx.bag.bm("emissive_white"), strip, (sign_w + 0.06, 0.06),
                       ground_h - sign_h - 0.10, ground_h - 0.10, rot_deg=ang)
        sbase = bpy_math_offset(base, normal, 0.09)
        shapes.add_wall_quad(ctx.bag.bm(sign_key), sbase, normal, sign_w,
                             ground_h - sign_h - 0.06, ground_h - 0.06, uv=_quad_uv(slot))
        return
    if template == "painted":
        # a painted board with a small projecting sign box on it
        board = bpy_math_offset(base, normal, 0.04)
        shapes.add_box(ctx.bag.bm(ctx.wall_key), board, (sign_w + 0.1, 0.06),
                       ground_h - sign_h - 0.12, ground_h - 0.02, rot_deg=ang)
        sbase = bpy_math_offset(base, normal, 0.10)
        shapes.add_wall_quad(ctx.bag.bm(sign_key), sbase, normal, sign_w * 0.8,
                             ground_h - sign_h - 0.02, ground_h - 0.02, uv=_quad_uv(slot))
        return
    # the lightbox and the red board: a box body with the printed panel on it
    body = bpy_math_offset(base, normal, 0.05)
    shapes.add_box(ctx.bag.bm("metal_dark"), body, (sign_w + 0.08, 0.10),
                   ground_h - sign_h - 0.10, ground_h - 0.02, rot_deg=ang)
    sbase = bpy_math_offset(base, normal, 0.11)
    shapes.add_wall_quad(ctx.bag.bm(sign_key), sbase, normal, sign_w,
                         ground_h - sign_h - 0.06, ground_h - 0.06, uv=_quad_uv(slot))


def _glass(ctx, base, normal, width, h0, h1):
    """The shop glazing: a dirty-glass quad in front of the interior card."""
    gbase = bpy_math_offset(base, normal, -GLASS_DEPTH)
    shapes.add_wall_quad(ctx.bag.bm("shop_glass"), gbase, normal, width - 0.08, h0, h1)


def _shutter(ctx, base, normal, width, h0, h1):
    """A roller shutter (卷帘门) rolled down over the shopfront."""
    from .parts3 import add_roller_shutter
    add_roller_shutter(ctx, base, normal, width - 0.06, h0, h1)


def _grille(ctx, base, normal, width, h0, h1):
    """A security grille (拉闸门) over the shop window."""
    from .parts3 import add_window_cage
    add_window_cage(ctx, base, normal, width - 0.12, h0, h1)


def add_frontage_band(ctx, fc, ground_h, wall_key, recess=RECESS):
    """The wall band above the shopfronts plus the soffit that closes the alcove."""
    from mathutils import Vector
    shop_h = ground_h - FASCIA_H
    shapes.add_wall_quad(ctx.bag.bm(wall_key), fc["a"], fc["n"], fc["w"], shop_h, ground_h)
    # the soffit: a horizontal quad under the band, facing down, from the face to the glass line
    t = shapes.wall_tangent(fc["n"])
    inner = bpy_math_offset(fc["a"], fc["n"], -recess)
    corners = [
        (fc["a"][0], fc["a"][1], shop_h),
        (fc["a"][0] + t[0] * fc["w"], fc["a"][1] + t[1] * fc["w"], shop_h),
        (inner[0] + t[0] * fc["w"], inner[1] + t[1] * fc["w"], shop_h),
        (inner[0], inner[1], shop_h),
    ]
    bm = ctx.bag.bm(wall_key)
    verts = [bm.verts.new(shapes.to_blender(*c)) for c in corners]
    face = bm.faces.new(verts)
    shapes.ensure_normal([face], Vector((0.0, 0.0, -1.0)))


def add_ground_floor(ctx, poly, front_edge, ground_h, wall_key, rng, unit_min=4.0,
                     unit_max=6.5, sign_key="neon_h", shops=True, guard=None):
    """The hand-built ground floor of a block.

    A wall mass covers the whole footprint with the street edge pushed in, so the three
    closed sides stay closed; the street side is an alcove with the shopfronts inside it.
    """
    from . import plan
    from .variety import NeighbourGuard
    mass = plan.recess_front(poly, front_edge, RECESS)
    # no bottom cap: the mass stands on the ground and the cap is never seen
    shapes.add_prism(ctx.bag.bm(wall_key), mass, 0.0, ground_h, cap_bottom=False)
    fc = plan.facade(poly, front_edge)
    add_frontage_band(ctx, fc, ground_h, wall_key)
    if not shops:
        return
    if guard is None:
        guard = getattr(ctx, "guard", None) or NeighbourGuard()
    n_units = max(1, int(fc["w"] / rng.uniform(unit_min, unit_max)))
    unit = fc["w"] / n_units
    for i in range(n_units):
        base = (fc["a"][0] + fc["t"][0] * unit * i, fc["a"][1] + fc["t"][1] * unit * i)
        ctx.wall_key = wall_key
        template = guard.choose(lambda: _weighted_choice(rng, TEMPLATES), salt="shop")
        fascia = guard.choose(lambda: _weighted_choice(rng, FASCIA_TEMPLATES), salt="fascia")
        add_shopfront(ctx, base, fc["n"], unit - 0.12, ground_h, sign_key, template,
                      fascia=fascia)
        if rng.random() < 0.50:
            add_awning(ctx, base, fc["n"], unit - 0.4, 1.0, ground_h - 0.9)
        # a security grille over the shop window (the "grille" template already has one)
    ctx.guard = guard


def add_awning(ctx, base, normal, width, drop=1.1, z=3.0):
    """A flat projecting canopy over a shopfront, with two support bars."""
    t = shapes.wall_tangent(normal)
    ang = math.degrees(math.atan2(t[1], t[0]))
    c = bpy_math_offset(base, normal, drop * 0.5)
    shapes.add_box(ctx.bag.bm("awning"), c, (width, drop), z - 0.10, z, rot_deg=ang)
    for i in range(2):
        t2 = width * (i + 1) / 3.0
        p = bpy_math_offset((base[0] + t[0] * t2, base[1] + t[1] * t2), normal, drop * 0.5)
        shapes.add_box(ctx.bag.bm("metal_dark"), p, (0.05, drop), z - 0.24, z - 0.10, rot_deg=ang)


def add_balcony(ctx, base, normal, width, depth=1.3, slab_h=0.18):
    """Balcony slab with a solid parapet (reads the same as a railing, costs 3 boxes)."""
    t = shapes.wall_tangent(normal)
    ang = math.degrees(math.atan2(t[1], t[0]))
    c = bpy_math_offset(base, normal, depth * 0.5)
    shapes.add_box(ctx.bag.bm("render"), c, (width, depth), 0.0, slab_h, rot_deg=ang)
    bm = ctx.bag.bm("metal_dark")
    outer = bpy_math_offset(base, normal, depth)
    shapes.add_box(bm, outer, (width, 0.07), 0.0, 0.95, rot_deg=ang)
    shapes.add_box(bm, outer, (width, 0.12), 0.95, 1.02, rot_deg=ang)
