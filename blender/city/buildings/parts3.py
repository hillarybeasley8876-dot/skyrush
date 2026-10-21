"""Street clutter: AC units, window cages, roller shutters, laundry, lamps, planters.

The flat-faced props (the AC casing, the security cage, the roller shutter) are
mapped onto the prop sheet, so they really show a fan grille, a brand plate and
ribbed steel instead of being coloured boxes.
"""
import math

from . import shapes
from .parts import bpy_math_offset, _quad_uv, _rect_uv

AC_W = 0.80
AC_H = 0.62
AC_D = 0.55
CAGE_BAR = 0.05
SHUTTER_D = 0.06


def _prop_uv(ctx, name):
    """The UV rect of a named cell of the prop sheet."""
    return ctx.prop_uv(name)


def add_ac_unit(ctx, base, normal, h=2.6, w=AC_W, size="m"):
    """A wall-mounted split AC condenser under a window.

    The body is the louvred side of the casing and the front panel shows the fan
    grille, the brand plate and the rust drip.
    """
    t = shapes.wall_tangent(normal)
    ang = math.degrees(math.atan2(normal[1], normal[0]))
    c = bpy_math_offset(base, normal, AC_D * 0.5)
    body = ctx.bag.bm("prop")
    uv = _prop_uv(ctx, "ac_side")
    if uv is not None:
        shapes.add_uv_box(body, c, (w, AC_D), h, h + AC_H, rot_deg=ang, uv_rect=uv)
    else:
        shapes.add_box(ctx.bag.bm("metal_galv"), c, (w, AC_D), h, h + AC_H, rot_deg=ang)
    front = _prop_uv(ctx, "ac_front")
    if front is not None:
        fb = bpy_math_offset(base, normal, AC_D + 0.005)
        shapes.add_wall_quad(body, fb, normal, w, h, h + AC_H, uv=_rect_uv(front))
    return h


def add_window_cage(ctx, base, normal, width, h0, h1):
    """A steel security cage in front of a window (very Shanghai)."""
    t = shapes.wall_tangent(normal)
    ang = math.degrees(math.atan2(normal[1], normal[0]))
    bm = ctx.bag.bm("prop")
    uv = _prop_uv(ctx, "cage")
    c = bpy_math_offset(base, normal, 0.18)
    if uv is not None:
        shapes.add_wall_quad(bm, c, normal, width, h0, h1, uv=_rect_uv(uv))
    # a frame around the bars, so the cage has depth (the top and the bottom bar)
    frame = ctx.bag.bm("metal_dark")
    shapes.add_box(frame, c, (width, 0.07), h1 - CAGE_BAR, h1, rot_deg=ang)
    shapes.add_box(frame, c, (width, 0.07), h0, h0 + CAGE_BAR, rot_deg=ang)


def add_roller_shutter(ctx, base, normal, width, h0, h1):
    """A closed roller shutter (卷帘门) over a shopfront.

    The slats are a tiling surface (Shutter_Steel): 75 mm ribs over the whole
    width of the shop, not an atlas cell stretched over 4 m.
    """
    t = shapes.wall_tangent(normal)
    ang = math.degrees(math.atan2(normal[1], normal[0]))
    c = bpy_math_offset(base, normal, SHUTTER_D * 0.5)
    shapes.add_box(ctx.bag.bm("shutter"), c, (width, SHUTTER_D), h0, h1, rot_deg=ang)
    # the guide rails on both sides
    for side in (-1, 1):
        p = (c[0] + t[0] * side * width * 0.5, c[1] + t[1] * side * width * 0.5)
        shapes.add_box(ctx.bag.bm("metal_dark"), p, (0.08, 0.12), h0, h1 + 0.1, rot_deg=ang)


def add_laundry_pole(ctx, base, normal, length=2.0, h=3.4, count=4):
    """A bamboo pole across the lane with garments hanging from the cloth atlas.

    The pole runs PERPENDICULAR to the wall on a bracket under the window, and every
    garment hangs inside the pole's length.
    """
    t = shapes.wall_tangent(normal)
    ang = math.degrees(math.atan2(normal[1], normal[0]))
    c = bpy_math_offset(base, normal, length * 0.5)
    shapes.add_box(ctx.bag.bm("metal_galv"), c, (length, 0.05), h, h + 0.05, rot_deg=ang)
    # the bracket back to the wall
    b = bpy_math_offset(base, normal, 0.18)
    shapes.add_box(ctx.bag.bm("metal_dark"), b, (0.36, 0.10), h - 0.06, h + 0.06,
                   rot_deg=ang)
    cloth = ctx.bag.bm("cloth")
    for i in range(count):
        s = length * (0.12 + 0.76 * (i / max(1, count - 1)))
        gw = ctx.rng.uniform(0.42, 0.62)
        gh = ctx.rng.uniform(0.65, 1.05)
        p = bpy_math_offset(base, normal, s)
        slot = ctx.random_cell("cloth")
        uv = _quad_uv(slot) if slot else None
        shapes.add_wall_quad(cloth, p, normal, gw, h - gh, h, uv=uv)
    return length


KNOCKER_R = 0.06
KNOCKER_SEG = 10


def add_ring_knocker(ctx, base, normal, h=1.10):
    """A brass ring knocker (门环) hanging from a round backplate.

    The ring is a flat annulus in the plane of the door: 12 facets of a 120 mm
    ring, 6 mm from the plate.  A solid torus would cost 192 triangles per door
    and there are 550 doors in the 弄堂 district alone.
    """
    t = shapes.wall_tangent(normal)
    ang = math.degrees(math.atan2(normal[1], normal[0]))
    bm = ctx.bag.bm("brass")
    # the backplate: a disc, not a box
    plate = bpy_math_offset(base, normal, 0.02)
    t2 = shapes.wall_tangent(normal)
    shapes.add_quad(bm, [(plate[0] - t2[0] * 0.05, plate[1] - t2[1] * 0.05, h - 0.05),
                         (plate[0] + t2[0] * 0.05, plate[1] + t2[1] * 0.05, h - 0.05),
                         (plate[0] + t2[0] * 0.05, plate[1] + t2[1] * 0.05, h + 0.05),
                         (plate[0] - t2[0] * 0.05, plate[1] - t2[1] * 0.05, h + 0.05)])
    # the ring
    centre = bpy_math_offset(base, normal, 0.045)
    cy = h - KNOCKER_R - 0.04
    r_in = KNOCKER_R - 0.012
    r_out = KNOCKER_R
    for i in range(KNOCKER_SEG):
        a0 = 2.0 * math.pi * i / KNOCKER_SEG
        a1 = 2.0 * math.pi * (i + 1) / KNOCKER_SEG
        def pt(a, r):
            return (centre[0] + t[0] * math.cos(a) * r,
                    centre[1] + t[1] * math.cos(a) * r, cy + math.sin(a) * r)
        shapes.add_quad(bm, [pt(a0, r_in), pt(a0, r_out), pt(a1, r_out), pt(a1, r_in)])
    return h


def add_drain_pipe(ctx, base, normal, h0=0.0, h1=6.0):
    """A cast-iron drain pipe down the corner of a building."""
    t = shapes.wall_tangent(normal)
    ang = math.degrees(math.atan2(normal[1], normal[0]))
    c = bpy_math_offset(base, normal, 0.07)
    shapes.add_box(ctx.bag.bm("metal_dark"), c, (0.11, 0.11), h0, h1, rot_deg=ang)
    for h in (h0 + 1.0, h1 - 0.6):
        shapes.add_box(ctx.bag.bm("metal_dark"), c, (0.17, 0.17), h, h + 0.08, rot_deg=ang)


def add_wall_lamp(ctx, base, normal, h=3.2):
    """A bulkhead lamp over a door."""
    c = bpy_math_offset(base, normal, 0.14)
    shapes.add_box(ctx.bag.bm("metal_dark"), c, (0.34, 0.24), h, h + 0.22,
                   rot_deg=math.degrees(math.atan2(normal[1], normal[0])))


def add_satellite_dish(ctx, base, normal, h=4.0):
    """A satellite dish on a bracket."""
    t = shapes.wall_tangent(normal)
    ang = math.degrees(math.atan2(normal[1], normal[0]))
    c = bpy_math_offset(base, normal, 0.30)
    shapes.add_box(ctx.bag.bm("metal_dark"), c, (0.08, 0.60), h, h + 0.08, rot_deg=ang)
    dish = bpy_math_offset(base, normal, 0.62)
    shapes.add_box(ctx.bag.bm("metal_galv"), dish, (0.55, 0.12), h - 0.05, h + 0.45,
                   rot_deg=ang + 18.0)


def add_planter(ctx, center, w=1.4, d=0.7, h=0.55):
    """A concrete planter with a shrub."""
    shapes.add_box(ctx.bag.bm("render"), center, (w, d), 0.0, h)
    shapes.add_box(ctx.bag.bm("render"), center, (w + 0.08, d + 0.08), h - 0.08, h)
    shapes.add_blob(ctx.bag.bm("foliage"), center, h + 0.35, 0.42, 0.9, 0)


def add_bike_rack(ctx, center, count=3):
    """A row of bicycle hoops."""
    bm = ctx.bag.bm("metal_galv")
    for i in range(count):
        x = center[0] + i * 0.9
        shapes.add_box(bm, (x, center[1]), (0.07, 0.07), 0.0, 0.75)
        shapes.add_box(bm, (x, center[1] - 0.35), (0.07, 0.07), 0.0, 0.75)
        shapes.add_box(bm, (x, center[1] - 0.18), (0.07, 0.42), 0.75, 0.82)


def add_bin(ctx, center):
    """A galvanised rubbish bin."""
    shapes.add_box(ctx.bag.bm("metal_galv"), center, (0.55, 0.45), 0.0, 0.85)
    shapes.add_box(ctx.bag.bm("metal_dark"), center, (0.60, 0.50), 0.85, 0.92)


def add_potted_plant(ctx, base, normal, w=0.34):
    """A small pot with a plant on a window sill."""
    c = bpy_math_offset(base, normal, 0.10)
    shapes.add_box(ctx.bag.bm("stone_pale"), c, (w, w * 0.8), 0.0, 0.22)
    shapes.add_blob(ctx.bag.bm("foliage"), c, 0.34, 0.16, 1.0, 0)


KIOSK_W = 1.9
KIOSK_D = 1.3
KIOSK_H = 2.35


def add_kiosk(ctx, center, nx, nz):
    """A newspaper kiosk (报刊亭) on the kerb: a lit box with a canopy.

    The kerb strip of a shopping street is never empty in Shanghai, and the kiosks
    are the small warm lights that read from 100 m.
    """
    ang = math.degrees(math.atan2(nz, nx)) + 90.0
    body = ctx.bag.bm("render")
    shapes.add_box(body, center, (KIOSK_W, KIOSK_D), 0.0, KIOSK_H, rot_deg=ang)
    # the lit sign band and the glazing on the street side
    sign = ctx.bag.bm("emissive_warm")
    shapes.add_box(sign, (center[0] - nx * (KIOSK_D * 0.5 + 0.02),
                          center[1] - nz * (KIOSK_D * 0.5 + 0.02)),
                   (KIOSK_W * 0.82, 0.06), KIOSK_H * 0.62, KIOSK_H * 0.86, rot_deg=ang)
    glass = ctx.bag.bm("shop_glass")
    shapes.add_box(glass, (center[0] - nx * (KIOSK_D * 0.5 + 0.01),
                           center[1] - nz * (KIOSK_D * 0.5 + 0.01)),
                   (KIOSK_W * 0.78, 0.04), 0.9, KIOSK_H * 0.58, rot_deg=ang)
    # the canopy over the front
    shapes.add_box(ctx.bag.bm("metal_galv"),
                   (center[0] - nx * (KIOSK_D * 0.5 + 0.25),
                    center[1] - nz * (KIOSK_D * 0.5 + 0.25)),
                   (KIOSK_W * 1.05, 0.6), KIOSK_H, KIOSK_H + 0.08, rot_deg=ang)
