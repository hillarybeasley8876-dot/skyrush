"""The Lujiazui backdrop towers (12 generic high-rises) and the LED ads.

Split out of build_lujiazui.py to keep both files under 400 lines.

    python3 blender/landmarks/lmbackdrop.py
"""
import math
import os
import sys

import bmesh

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender/landmarks"))
import lmenv  # noqa: E402
from lmenv import bpy, common, geo, lmlib, lmmat, mats, uv  # noqa: E402
from mathutils import Vector  # noqa: E402

CORE = (748.0, -488.8)
AD_W, AD_H = 60.0, 120.0
AD_BOTTOM = 26.0

BACKDROP = [
    ("IFC_A", 1012, -566, 46, 46, 250, "twin", "chamfer"),
    ("IFC_B", 1036, -524, 46, 46, 248, "twin", "chamfer"),
    ("HSBC", 826, -706, 44, 54, 186, "dome", "round"),
    ("CMB", 902, -386, 38, 38, 230, "mast", "taper"),
    ("BoCom", 688, -302, 44, 32, 158, "band", "step"),
    ("BOC", 604, -424, 32, 38, 176, "band", "box"),
    ("Citi", 556, -258, 36, 36, 196, "mast", "ellipse"),
    ("Aurora", 1004, -252, 40, 44, 212, "twin", "L"),
    ("IFC_C", 1122, -626, 38, 42, 198, "band", "box"),
    ("One", 862, -178, 32, 32, 150, "band", "step"),
    ("StdCh", 830, -800, 30, 38, 156, "dome", "round"),
    ("Mirae", 500, -420, 34, 34, 162, "mast", "ellipse"),
]

# the three giant LED ad facades (lead note L-ART3): 60 x 120 m screens on a
# dark back-plate, facing the Bund
ADS = {
    "IFC_C": ("ad_dongfang.png", 198),
    "CMB": ("ad_pujiang.png", 230),
    "Aurora": ("ad_shencheng.png", 212),
}
AD_W, AD_H = 60.0, 120.0
AD_BOTTOM = 26.0

# the setback profile of every plan: (plan scale, height fraction 0, fraction 1)
SECTIONS = {
    "taper": [(1.0, 0.0, 0.55), (0.70, 0.55, 0.86), (0.55, 0.86, 1.0)],
    "step": [(1.0, 0.0, 0.42), (0.80, 0.42, 0.72), (0.58, 0.72, 0.90), (0.45, 0.90, 1.0)],
    "box": [(1.0, 0.0, 0.70), (0.86, 0.70, 0.90), (0.74, 0.90, 1.0)],
    "round": [(1.0, 0.0, 0.80), (0.88, 0.80, 0.94), (0.70, 0.94, 1.0)],
    "ellipse": [(1.0, 0.0, 0.60), (0.85, 0.60, 0.85), (0.66, 0.85, 1.0)],
    "chamfer": [(1.0, 0.0, 0.62), (0.88, 0.62, 0.86), (0.72, 0.86, 1.0)],
    "L": [(1.0, 0.0, 0.68), (0.85, 0.68, 0.90), (0.70, 0.90, 1.0)],
}

# ART.md 11: cool white LED edge lines on 50 % of the generic towers
LED_TOWERS = ("IFC_A", "IFC_B", "HSBC", "CMB", "Aurora", "IFC_C", "Citi")


def ad_quad(col, name, w, h, mat, loc):
    """A flat screen quad with 0..1 UVs so the ad image maps exactly once."""
    bm = bmesh.new()
    vs = [bm.verts.new((0.0, -w * 0.5, 0.0)), bm.verts.new((0.0, w * 0.5, 0.0)),
          bm.verts.new((0.0, w * 0.5, h)), bm.verts.new((0.0, -w * 0.5, h))]
    f = bm.faces.new(vs)
    layer = bm.loops.layers.uv.new("UVMap")
    for loop, tex in zip(f.loops, [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]):
        loop[layer].uv = tex
    bm.normal_update()
    o = lmlib.obj(name, bm, col, mat)
    o.location = loc
    return o


def plan_for(style, w, d, n=16):
    """Distinct plan outlines so no two backdrop towers read alike."""
    if style == "round":
        return [(w * 0.5 * math.cos(2 * math.pi * i / n),
                 w * 0.5 * math.sin(2 * math.pi * i / n)) for i in range(n)]
    if style == "ellipse":
        return [(w * 0.5 * math.cos(2 * math.pi * i / n),
                 d * 0.5 * math.sin(2 * math.pi * i / n)) for i in range(n)]
    if style == "chamfer":
        c = min(w, d) * 0.18
        return lmlib.rect(w * 0.5, d * 0.5, c)
    if style == "L":
        a = w * 0.5
        b = d * 0.5
        k = w * 0.26
        return [(-a, -b), (a, -b), (a, -b + d * 0.45), (a - k, -b + d * 0.45),
                (a - k, b), (-a, b)]
    return lmlib.rect(w * 0.5, d * 0.5)


def backdrop_tower(name, x, z, w, d, h, style, plan, glass, crown_mat, col,
                   ad_mats=None, plate_mat=None, col_mat=None, led_mat=None,
                   avia_mat=None):
    """One generic glass tower: three setbacks, a crown cap, an antenna.

    The r3 review: the 12 towers were 133 triangles each and read as plain
    boxes. Every tower now steps in three times, wears a crown cap and an
    antenna, and seven of them carry cool-white LED edge lines (ART.md 11:
    50 % of the generic towers)."""
    bm = lmlib.merge()
    p = plan_for(plan, w, d)
    sections = SECTIONS.get(plan, SECTIONS["box"])
    top = p
    for k, (scale, f0, f1) in enumerate(sections):
        sp = lmlib.scale_plan(p, scale)
        top = sp
        bm = lmlib.merge(bm, lmlib.loft_plans(
            [sp, sp], [h * f0, h * f1],
            cap_start=(k == 0), cap_end=(k == len(sections) - 1)))
    o = lmlib.obj("Tower_" + name, bm, col, glass)
    # Blender (x, y, z) -> Godot (x, z, -y): a map offset in Z is a Blender -Y offset
    o.location = (x - CORE[0], -(z - CORE[1]), 0.0)
    # per-tower UV offset so the shared facade sheet does not repeat visibly
    seed = sum(ord(c) for c in name)
    uv.box_uv(o, offset=(seed * 0.37 % 11.0, seed * 0.71 % 9.0, seed * 0.53 % 13.0))
    crown = lmlib.merge()
    if style == "band":
        crown = lmlib.merge(crown, lmlib.loft_plans(
            [lmlib.scale_plan(top, 1.06), lmlib.scale_plan(top, 1.06)],
            [h - 2.8, h + 1.4], cap_start=True, cap_end=True))
    elif style == "twin":
        for sgn in (-1.0, 1.0):
            crown = lmlib.merge(crown, lmlib.box(
                (sgn * w * 0.30, 0.0, h + 3.0), (w * 0.16, d * 0.16, 6.0)))
    elif style == "mast":
        crown = lmlib.merge(crown, lmlib.lathe(
            [(0.0, h), (2.2, h), (1.1, h + 14.0), (0.3, h + 26.0)], 10))
    elif style == "dome":
        crown = lmlib.merge(crown, lmlib.lathe(
            [(0.0, h), (w * 0.36, h), (w * 0.30, h + 9.0), (w * 0.16, h + 15.0),
             (0.0, h + 16.5)], 20))
    else:
        crown = lmlib.merge(crown, lmlib.loft_plans(
            [lmlib.scale_plan(top, 1.04), lmlib.scale_plan(top, 0.92)],
            [h, h + 5.0], cap_start=True, cap_end=True))
    # every tower gets an antenna
    ant_h = 5.0 + 10.0 * ((seed % 7) / 6.0)
    crown = lmlib.merge(crown, lmlib.lathe(
        [(0.0, h + 2.0), (0.9, h + 2.0), (0.45, h + ant_h), (0.0, h + ant_h)], 8))
    co = lmlib.obj("Crown_" + name, crown, col, crown_mat)
    co.location = (x - CORE[0], -(z - CORE[1]), 0.0)
    uv.box_uv(co, offset=(seed * 0.37 % 11.0, seed * 0.71 % 9.0, seed * 0.53 % 13.0))
    # the cool white LED edge lines (seven of the twelve towers)
    if led_mat is not None:
        lines = lmlib.merge()
        for (scale, f0, f1) in sections:
            sp = lmlib.scale_plan(p, scale)
            pts = lmlib.resample_closed(sp, 24)
            cx = sum(q[0] for q in pts) / 24.0
            cy = sum(q[1] for q in pts) / 24.0
            for k in range(4):
                i = int(k * 6) + 1
                q0, q1 = pts[i], pts[(i + 1) % 24]
                mx, my = (q0[0] + q1[0]) * 0.5, (q0[1] + q1[1]) * 0.5
                nx, ny = mx - cx, my - cy
                ln = math.hypot(nx, ny) or 1.0
                nx, ny = nx / ln, ny / ln
                tx, ty = -ny, nx
                a = (mx - tx * 1.7 + nx * 0.30, my - ty * 1.7 + ny * 0.30)
                b = (mx + tx * 1.7 + nx * 0.30, my + ty * 1.7 + ny * 0.30)
                lines = lmlib.merge(lines, lmlib.loft_plans(
                    [[a, b], [a, b]], [h * f0, h * f1], closed=False))
        # the crown ring
        ring = lmlib.scale_plan(top, 1.10)
        lines = lmlib.merge(lines, lmlib.loft_plans(
            [ring, ring], [h + 0.8, h + 4.0], cap_start=True, cap_end=True))
        lo = lmlib.obj("LED_Crown_" + name, lines, col, led_mat)
        lo.location = (x - CORE[0], -(z - CORE[1]), 0.0)
    # the aviation beacon on every roof above 100 m
    if avia_mat is not None:
        lmlib.aviation_beacon(col, "LED_Aviation_" + name, 0.0, 0.0, h + ant_h + 1.0,
                               avia_mat)
        ab = bpy.data.objects.get("LED_Aviation_" + name)
        if ab is not None:
            ab.location = (x - CORE[0], -(z - CORE[1]), 0.0)
    lmlib.empty("Flood_Crown_" + name, (x - CORE[0], -(z - CORE[1]), 0.0),
                direction=(0.0, 0.0, 1.0), col=col, size=3.0)
    if ad_mats and name in ad_mats:
        build_ad(col, name, w, h, ad_mats[name], plate_mat, (x - CORE[0], -(z - CORE[1]), 0.0))
    if col_mat is not None:
        # a simple collision box so the car cannot drive through the tower
        cb = lmlib.box((0.0, 0.0, h * 0.5), (w * 0.5, d * 0.5, h * 0.5))
        co2 = lmlib.obj("Tower_Col_" + name + "-colonly", cb, col, col_mat)
        uv.box_uv(co2)
        co2.location = (x - CORE[0], -(z - CORE[1]), 0.0)


def build_ad(col, name, w, h, screen_mat, plate_mat, loc):
    """The giant LED ad facade: a dark back-plate, the screen and its brackets."""
    x_face = -w * 0.5
    plate = lmlib.box((x_face - 1.15, 0.0, AD_BOTTOM + AD_H * 0.5),
                      (0.40, AD_W * 0.5, AD_H * 0.5))
    po = lmlib.obj("AdPlate_" + name, plate, col, plate_mat)
    uv.box_uv(po)
    po.location = loc
    screen = ad_quad(col, "LED_Ad_" + name, AD_W, AD_H, screen_mat,
                     (x_face - 0.70, 0.0, AD_BOTTOM))
    screen.location = loc
    # four brackets back to the tower face
    br = lmlib.merge()
    for zz in (AD_BOTTOM + 8.0, AD_BOTTOM + AD_H * 0.5, AD_BOTTOM + AD_H - 8.0):
        for sgn in (-1.0, 1.0):
            br = lmlib.merge(br, lmlib.strut(
                (x_face - 0.72, sgn * AD_W * 0.35, zz), (x_face + 0.4, sgn * AD_W * 0.3, zz),
                0.35, 0.35))
    bo = lmlib.obj("AdBrackets_" + name, br, col, plate_mat)
    uv.box_uv(bo)
    bo.location = loc


def build_backdrop(col, glass, crown_mat, ad_mats=None, plate_mat=None, col_mat=None,
                   led_mat=None, avia_mat=None):
    for (name, x, z, w, d, h, style, plan) in BACKDROP:
        lm = led_mat if (led_mat is not None and name in LED_TOWERS) else None
        # every roof gets its OWN beacon material, so the 1 Hz blink can carry
        # a per-tower phase (the world unit animates emission_energy_multiplier)
        av = None
        if avia_mat is not None:
            av = lmmat.glow("LED_Aviation_" + name, lmmat.hexcol("#FF2A3A"), strength=8.0)
        backdrop_tower(name, x, z, w, d, h, style, plan, glass, crown_mat, col,
                       ad_mats, plate_mat, col_mat, lm, av)

