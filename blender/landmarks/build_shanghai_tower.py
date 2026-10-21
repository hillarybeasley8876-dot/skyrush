"""Shanghai Tower (上海中心) - 632 m, Lujiazui. Map anchor (1122.8, -42.5).

Dossier 6.2: 120 stacked rings 4.83 m each (0-580 m); ring i is rotated i/119 x
120 deg and scaled 1 - 0.5 x i/119; rounded-triangle plan with a V notch;
double skin; white floor-band dots; steel crown fins 546-632 m.
"""
import math
import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender/landmarks"))
import lmenv  # noqa: E402
from lmenv import bpy, common, geo, lmlib, lmmat, mats, uv  # noqa: E402

RINGS = 120
RING_H = 4.83
R_BASE = 42.0
TWIST = math.radians(120.0)
SKIN_TOP = RINGS * RING_H          # 579.6 m
CROWN_TOP = 632.0
NOTCH_DIR = 0.0
NOTCH_DEPTH = 3.6
NOTCH_HALF = math.radians(13.0)
NP = 108                           # plan points


def ring_params(i):
    f = i / float(RINGS - 1)
    return (1.0 - 0.5 * f, f * TWIST)


def plan_for(radius, angle, n=NP, notch=True):
    """Rounded-triangle plan, rotated, with the vertical V notch cut in world space."""
    base = lmlib.rounded_tri(radius, corner=0.20, per_corner=8)
    pts = lmlib.resample_closed(base, n)
    pts = lmlib.rot(pts, angle)
    if not notch:
        return pts
    out = []
    for (x, y) in pts:
        a = math.atan2(y, x)
        r = math.hypot(x, y)
        d = abs((a - NOTCH_DIR + math.pi) % (2.0 * math.pi) - math.pi)
        if d < NOTCH_HALF:
            r -= NOTCH_DEPTH * (1.0 - d / NOTCH_HALF)
        out.append((r * math.cos(a), r * math.sin(a)))
    return out


def build_skin(col, glass):
    plans, heights = [], []
    for i in range(RINGS):
        s, a = ring_params(i)
        plans.append(plan_for(R_BASE * s, a))
        heights.append(i * RING_H)
    bm = lmlib.loft_plans(plans, heights, cap_start=True, cap_end=True)
    o = lmlib.obj("Tower_Skin", bm, col, glass)
    uv.box_uv(o)
    return o


def build_core(col, core_mat):
    """Inner structure visible through the glass (double skin)."""
    plans, heights = [], []
    for i in range(RINGS):
        s, a = ring_params(i)
        plans.append(lmlib.rot(lmlib.rounded_tri(R_BASE * s * 0.52, corner=0.26, per_corner=4), a))
        heights.append(i * RING_H)
    bm = lmlib.loft_plans(plans, heights, cap_start=True, cap_end=True)
    o = lmlib.obj("Tower_Core", bm, col, core_mat)
    uv.box_uv(o)
    return o


def build_bands(col, band_mat):
    """White LED floor bands wrapping the outer skin (one per ring)."""
    import bmesh
    from mathutils import Vector
    bm = bmesh.new()
    for i in range(1, RINGS):
        s, a = ring_params(i)
        outer = lmlib.scale_plan(plan_for(R_BASE * s, a, n=NP), 1.005)
        z = i * RING_H
        low = [bm.verts.new(Vector((p[0], p[1], z - 0.20))) for p in outer]
        high = [bm.verts.new(Vector((p[0], p[1], z + 0.20))) for p in outer]
        for k in range(NP):
            k2 = (k + 1) % NP
            bm.faces.new((low[k], low[k2], high[k2], high[k]))
    bm.normal_update()
    o = lmlib.obj("LED_Tower_Bands", bm, col, band_mat)
    uv.box_uv(o)
    return o


def build_notch(col, notch_mat):
    """Continuous white line along the V-notch (reads from the Bund).

    2.0 m wide at E3.5: at 1.3 km one pixel is 0.76 m, so a line that has to
    read from the Bund must be at least 1.6 m."""
    strip = []
    heights = [i * SKIN_TOP / 40.0 for i in range(41)]
    for y in heights:
        s = 1.0 - 0.5 * min(y / SKIN_TOP, 1.0)
        r = R_BASE * s * 0.995
        strip.append([(r - 1.4, 0.0), (r + 1.4, 0.0)])
    o = lmlib.obj("LED_Tower_Notch", lmlib.loft_plans(strip, heights, closed=False), col,
                  notch_mat)
    uv.box_uv(o)
    return o


def build_corner_lines(col, line_mat):
    """Three twisting LED lines that follow the rounded corners.

    They are the tower's signature from the Bund: 1.6 m wide, white, E3."""
    bm = lmlib.merge()
    for k in range(3):
        strip = []
        heights = []
        for i in range(41):
            f = i / 40.0
            y = SKIN_TOP * f
            s = 1.0 - 0.5 * f
            ang = TWIST * f + math.pi / 2 + k * 2.0 * math.pi / 3.0
            r = R_BASE * s * 1.004
            px, py = r * math.cos(ang), r * math.sin(ang)
            tx, ty = -math.sin(ang), math.cos(ang)
            strip.append([(px - tx * 1.8, py - ty * 1.8), (px + tx * 1.8, py + ty * 1.8)])
            heights.append(y)
        bm = lmlib.merge(bm, lmlib.loft_plans(strip, heights, closed=False))
    o = lmlib.obj("LED_Tower_CornerLines", bm, col, line_mat)
    uv.box_uv(o)
    return o


def build_crown(col, crown_mat, edge_mat):
    """Steel crown fins 546-632 m, continuing the twist.

    The crown keeps the skin at about half scale (never a needle) and its top
    edge is cut by a plane that slopes about 25 m, rising towards the V-notch.
    The fins stand in a ring around the top."""
    import bmesh
    from mathutils import Vector
    fins = []
    edge = []
    n_fin = 44
    for k in range(n_fin):
        ang_top = TWIST + 2.0 * math.pi * k / n_fin + (CROWN_TOP - SKIN_TOP) * 0.010
        # the top edge slopes: the fin nearest the notch is the tallest
        to_notch = math.cos(ang_top - NOTCH_DIR)
        top_z = CROWN_TOP - 12.5 * (1.0 - to_notch)
        levels = [546.0 + (top_z - 546.0) * k2 / 9.0 for k2 in range(10)]
        strip = []
        for y in levels:
            f = min(y / SKIN_TOP, 1.0)
            s = 1.0 - 0.5 * f
            if y > SKIN_TOP:
                # the crown never shrinks below 0.42 of the base scale
                s = 0.5 * max(0.84, 1.0 - (y - SKIN_TOP) / 52.0)
            ang = TWIST * f + (y - SKIN_TOP) * 0.010 if y > SKIN_TOP else TWIST * f
            ang += 2.0 * math.pi * k / n_fin
            r = R_BASE * s * 0.97
            px, py = r * math.cos(ang), r * math.sin(ang)
            tx, ty = -math.sin(ang), math.cos(ang)
            strip.append([(px - tx * 0.55, py - ty * 0.55), (px + tx * 0.55, py + ty * 0.55)])
        fins.append((strip, levels))
    bm = lmlib.merge()
    for (strip, lv) in fins:
        bm = lmlib.merge(bm, lmlib.loft_plans(strip, lv, closed=False))
    o = lmlib.obj("Tower_CrownFins", bm, col, crown_mat)
    uv.box_uv(o)
    lmlib.empty("Aviation_Tower", (0.0, 0.0, CROWN_TOP), direction=(0.0, 0.0, 1.0),
                col=col, size=5.0)
    for k in range(3):
        a = 2.0 * math.pi * k / 3
        lmlib.empty("Flood_Crown_%d" % (k + 1),
                    (40.0 * math.cos(a), 40.0 * math.sin(a), 600.0),
                    direction=(-0.4 * math.cos(a), -0.4 * math.sin(a), -0.9),
                    col=col, size=5.0)
    return o


def build_crown_led(col, led_mat):
    """The crown's lit faces: the inner edge of every fin and the top ring.

    The steel crown fins (546-632 m) are grey metal; without this they read
    as a dead grey box from the air (ART.md 11)."""
    inner = lmlib.merge()
    top = lmlib.merge()
    n_fin = 44
    for k in range(n_fin):
        ang_top = TWIST + 2.0 * math.pi * k / n_fin + (CROWN_TOP - SKIN_TOP) * 0.010
        to_notch = math.cos(ang_top - NOTCH_DIR)
        top_z = CROWN_TOP - 12.5 * (1.0 - to_notch)
        levels = [546.0 + (top_z - 546.0) * k2 / 9.0 for k2 in range(10)]
        strip = []
        for y in levels:
            f = min(y / SKIN_TOP, 1.0)
            s = 1.0 - 0.5 * f
            if y > SKIN_TOP:
                s = 0.5 * max(0.84, 1.0 - (y - SKIN_TOP) / 52.0)
            ang = TWIST * f + (y - SKIN_TOP) * 0.010 if y > SKIN_TOP else TWIST * f
            ang += 2.0 * math.pi * k / n_fin
            r = R_BASE * s * 0.97
            px, py = r * math.cos(ang), r * math.sin(ang)
            tx, ty = -math.sin(ang), math.cos(ang)
            # the lit inner edge of the fin
            strip.append([(px - tx * 0.55, py - ty * 0.55), (px - tx * 0.30, py - ty * 0.30)])
        inner = lmlib.merge(inner, lmlib.loft_plans(strip, levels, closed=False))
        # the bar on the sloped top edge
        f = min(top_z / SKIN_TOP, 1.0)
        s = 0.5 * max(0.84, 1.0 - (top_z - SKIN_TOP) / 52.0)
        ang = TWIST * f + (top_z - SKIN_TOP) * 0.010 + 2.0 * math.pi * k / n_fin
        r = R_BASE * s * 0.97
        px, py = r * math.cos(ang), r * math.sin(ang)
        tx, ty = -math.sin(ang), math.cos(ang)
        top = lmlib.merge(top, lmlib.strut(
            (px - tx * 0.7, py - ty * 0.7, top_z + 0.2),
            (px + tx * 0.7, py + ty * 0.7, top_z + 0.2), 0.5, 0.5))
    # a solid lit band around the crown: at 1.3 km the crown has to be a
    # SURFACE, not a wire (the r3 review: "Crowns are lit surfaces")
    band_f = min(600.0 / SKIN_TOP, 1.0)
    band_s = 0.5 * max(0.84, 1.0 - (600.0 - SKIN_TOP) / 52.0)
    band_r = R_BASE * band_s * 0.99
    ring = lmlib.lathe([(band_r, 596.0), (band_r + 0.6, 596.0),
                        (band_r + 0.6, 604.0), (band_r, 604.0)], 40,
                       cap_bottom=False, cap_top=False)
    inner = lmlib.merge(inner, ring)
    o = lmlib.obj("LED_Tower_CrownInner", inner, col, led_mat)
    uv.box_uv(o)
    o2 = lmlib.obj("LED_Tower_CrownTop", top, col, led_mat)
    uv.box_uv(o2)
    return o


def main():
    common.reset()
    lmenv.ensure_textures()
    col = common.collection("ShanghaiTower")
    glass = lmmat.tex_mat("LM_TOWER_Glass", diff="facade_night_diff.png",
                          emit="facade_night_emit.png", normal="facade_night_nor.png",
                          color=lmmat.hexcol("#9DB7C6"), roughness=0.12, metallic=0.4,
                          tile=(0.14, 0.06), emit_strength=1.5)
    core = lmmat.tex_mat("LM_TOWER_Core", diff="metal_dark_diff.png",
                         normal="metal_dark_nor.png", rough="metal_dark_rough.png",
                         color=lmmat.hexcol("#2B3138"), roughness=0.7, metallic=0.2,
                         tile=(0.55, 0.55), normal_strength=0.9)
    band = lmmat.emit_mat("LED_Tower_Bands", "led_dots_band.png", lmmat.hexcol("#E6F2FF"),
                          strength=3.0, tile=(1.0, 1.0), base=(0.05, 0.07, 0.09))
    line = lmmat.glow("LED_Tower_CornerLines", lmmat.hexcol("#E6F2FF"), strength=3.0)
    notch = lmmat.glow("LED_Tower_Notch", lmmat.hexcol("#E6F2FF"), strength=3.5)
    crown_led = lmmat.glow("LED_Tower_Crown", lmmat.hexcol("#DDEEFF"), strength=2.5)
    avia = lmmat.glow("LED_Aviation_Tower", lmmat.hexcol("#FF2A3A"), strength=8.0)
    crown = lmmat.tex_mat("LM_TOWER_Crown", diff="metal_brushed_diff.png",
                          normal="metal_brushed_nor.png", rough="metal_brushed_rough.png",
                          color=lmmat.hexcol("#AEB6BC"), roughness=0.34, metallic=0.85,
                          tile=(0.42, 0.42), normal_strength=0.9)
    colmat = lmmat.tex_mat("LM_TOWER_Collider", color=(0.1, 0.1, 0.1), roughness=0.9)
    build_skin(col, glass)
    build_core(col, core)
    build_bands(col, band)
    build_notch(col, notch)
    build_corner_lines(col, line)
    build_crown(col, crown, band)
    build_crown_led(col, crown_led)
    lmlib.aviation_beacon(col, "LED_Aviation_Tower", 0.0, 0.0, CROWN_TOP, avia)
    build_collider(col, colmat)
    lmlib.finish("shanghai_tower", col)


def build_collider(col, col_mat):
    """A simplified collision hull of the tower (the twisted skin, 8 sections)."""
    hs = [0.0, 120.0, 240.0, 360.0, 470.0, 560.0, SKIN_TOP, CROWN_TOP]
    plans, heights = [], []
    for y in hs:
        f = min(y / SKIN_TOP, 1.0)
        s = 1.0 - 0.5 * f
        if y > SKIN_TOP:
            s = 0.5 * max(0.84, 1.0 - (y - SKIN_TOP) / 52.0)
        plans.append(lmlib.rot(lmlib.rounded_tri(R_BASE * s * 0.95, corner=0.22,
                                                  per_corner=3),
                               TWIST * f + (max(0.0, y - SKIN_TOP)) * 0.010))
        heights.append(y)
    bm = lmlib.loft_plans(plans, heights, cap_start=True, cap_end=True)
    o = lmlib.obj("Tower_ColBody-colonly", bm, col, col_mat)
    uv.box_uv(o)


if __name__ == "__main__":
    main()
