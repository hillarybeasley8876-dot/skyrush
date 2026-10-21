"""Oriental Pearl Tower (东方明珠) - 468 m, Lujiazui. Map anchor (637.5, -634.9).

Geometry per ref/shanghai/SHANGHAI_DOSSIER.md 6.1: three 9 m tubes in a
triangle, three 7 m braces at 60 deg, lower sphere D50 (centre 93 m), five
space-hotel spheres, upper sphere D45 (centre 272.5 m), 14 m space module
(335-349 m) and a 118 m antenna to 468 m.

Look (dossier 15): the spheres are glossy pink-magenta glass with a 1.2 m
honeycomb panel grid, wrapped in a separate LED dot skin (0.4 m pitch,
alpha-BLENDED so the glass shows between the dots and the skin does not
shimmer away past 40 m). The dot shell sits 0.6 m off the glass so the two
surfaces never z-fight. UVs are in METRES so one material fits every sphere.
"""
import math
import os
import sys

import bmesh

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender/landmarks"))
import lmenv  # noqa: E402
from lmenv import bpy, common, geo, lmlib, lmmat, mats, uv  # noqa: E402

TUBE_R = 4.5
TRI_R = 10.0                          # tube axis radius
FOOT_R = 30.0                         # where the splayed tube feet land
BRACE_FOOT_R = 48.5
TUBE_TOP = 252.0                      # the tubes reach the upper sphere
LOWER_R, LOWER_CZ = 25.0, 93.0
UPPER_R, UPPER_CZ = 22.5, 272.5
SMALL_R, SMALL_YS = 6.0, (130.0, 150.0, 170.0, 190.0, 210.0)
MOD_R, MOD_Y0, MOD_Y1 = 7.0, 335.0, 349.0
ANT_TOP = 468.0
POD_R, POD_H = 50.0, 12.0
SEG = 40
DOT_OFFSET = 0.6                      # the LED dot shell floats off the glass

LED_PITCH = 3.2        # metres per dot tile (8 x 8 dots of 0.4 m pitch)
HONEY_TILE = 4.8       # honeycomb panel sheet (1.2 m cells)
ALU_TILE = 2.4         # painted metal sheet
STRIP_W = 2.4          # tube light strip width (m), readable from the Bund


def build_body(col, mat):
    """Concrete structure: podium, three splayed tubes, braces, core, antenna."""
    bm = lmlib.merge()
    prof = [(0.0, 0.0), (POD_R + 2.0, 0.0), (POD_R + 2.0, 1.6), (POD_R, 2.4),
            (POD_R, POD_H - 1.0), (POD_R - 3.0, POD_H), (0.0, POD_H)]
    bm = lmlib.merge(bm, lmlib.lathe(prof, SEG, cap_bottom=False, cap_top=False))
    bm = lmlib.merge(bm, lmlib.lathe([(0.0, 0.0), (6.5, 0.0), (6.5, 100.0), (0.0, 100.0)], SEG))
    for k in range(3):
        a = 2 * math.pi * k / 3 + math.pi / 2
        cx, cy = math.cos(a), math.sin(a)
        # the leg splays out to the foot, the tube runs on to the upper sphere
        bm = lmlib.merge(bm, lmlib.tube((FOOT_R * cx, FOOT_R * cy, 0.0),
                                        (TRI_R * cx, TRI_R * cy, 55.0), 4.9, TUBE_R, 16))
        bm = lmlib.merge(bm, lmlib.tube((TRI_R * cx, TRI_R * cy, 52.0),
                                        (TRI_R * cx, TRI_R * cy, TUBE_TOP), TUBE_R, TUBE_R, 16))
        ba = a + math.pi / 3
        bx, by = math.cos(ba), math.sin(ba)
        bm = lmlib.merge(bm, lmlib.tube((BRACE_FOOT_R * bx, BRACE_FOOT_R * by, 0.0),
                                        (TRI_R * bx, TRI_R * by, 68.0), 3.6, 3.5, 14))
    bm = lmlib.merge(bm, lmlib.lathe([(0.0, 90.0), (5.6, 90.0), (5.6, 340.0), (0.0, 340.0)], SEG))
    mod = [(0.0, MOD_Y0), (MOD_R, MOD_Y0), (MOD_R, MOD_Y1 - 1.5), (MOD_R - 2.0, MOD_Y1),
           (0.0, MOD_Y1)]
    bm = lmlib.merge(bm, lmlib.lathe(mod, SEG))
    ant = [(0.0, 349.0), (2.6, 349.0), (1.6, 410.0), (0.9, 460.0), (0.35, ANT_TOP), (0.0, ANT_TOP)]
    bm = lmlib.merge(bm, lmlib.lathe(ant, 16))
    o = lmlib.obj("Body", bm, col, mat)
    uv.box_uv(o)
    return o


def build_podium(col, mat, glass_mat, col_mat):
    """Podium detail: glazing bands, three entrances and the ground spheres.

    Dossier 6.1: the podium is a 100 m drum with a ring of entrances and the
    three 8 m spheres that sit at the foot of the splayed columns."""
    bm = lmlib.merge()
    for k in range(3):
        a = 2 * math.pi * k / 3 + math.pi / 2
        cx, cy = math.cos(a), math.sin(a)
        # a glazed entrance bay on each of the three axes
        bm = lmlib.merge(bm, lmlib.box((cx * (POD_R - 0.4), cy * (POD_R - 0.4), 6.0),
                                       (14.0, 3.0, 8.0), rot_z=a))
    o = lmlib.obj("OPT_Entrances", bm, col, mat)
    uv.box_uv(o)
    # the three 8 m ground spheres at the foot of the columns
    spheres = lmlib.merge()
    for k in range(3):
        a = 2 * math.pi * k / 3 + math.pi / 2
        sp = lmlib.lathe(lmlib.sphere_profile(4.0, 0.0, 14), 16)
        bmesh.ops.translate(sp, verts=sp.verts,
                           vec=(FOOT_R * math.cos(a), FOOT_R * math.sin(a), 4.6))
        spheres = lmlib.merge(spheres, sp)
    gs = lmlib.obj("OPT_GroundSpheres", spheres, col, glass_mat)
    uv.box_uv(gs)
    # the glazing band: a ring of glass around the podium at 7.5 m
    band = lmlib.lathe([(POD_R - 0.3, 7.0), (POD_R - 0.3, 9.6), (POD_R - 2.6, 9.6),
                        (POD_R - 2.6, 7.0)], SEG, cap_bottom=False, cap_top=False)
    bo = lmlib.obj("OPT_GlazingBand", band, col, glass_mat)
    uv.box_uv(bo)
    # collision hull for the podium drum
    hull = lmlib.lathe([(0.0, 0.0), (POD_R, 0.0), (POD_R, POD_H), (0.0, POD_H)],
                       16, cap_bottom=False, cap_top=False)
    co = lmlib.obj("OPT_ColPodium-convcolonly", hull, col, col_mat)
    uv.box_uv(co)
    return o


def build_spheres(col, glass_mat, alu_mat, led_mat, band_mat):
    """Glass spheres + aluminium collars + the separate LED dot skin."""
    specs = [("Lower", LOWER_R, LOWER_CZ, [(LOWER_CZ - 18.0, 1.5), (LOWER_CZ, 1.5),
                                            (LOWER_CZ + 18.0, 1.5)]),
             ("Upper", UPPER_R, UPPER_CZ, [(UPPER_CZ - 12.0, 1.4), (UPPER_CZ, 1.4),
                                           (UPPER_CZ + 12.0, 1.4)])]
    for i, y in enumerate(SMALL_YS):
        specs.append(("Small%d" % (i + 1), SMALL_R, y, [(y, 1.1)]))
    for (name, r, cz, bands) in specs:
        go = lmlib.obj("Sphere_" + name, lmlib.lathe(lmlib.sphere_profile(r, cz, 26), SEG),
                       col, glass_mat)
        lmlib.uv_spherical_metres(go, r)
        common.smooth(go, 50.0)
        for j, (bz, bw) in enumerate(bands):
            band = lmlib.lathe(lmlib.sphere_band(r, cz, bz, bw, 0.10, 0.42), SEG)
            bo = lmlib.obj("Band_%s_%d" % (name, j + 1), band, col, alu_mat)
            lmlib.uv_spherical_metres(bo, r)
            common.smooth(bo, 40.0)
            # the lit edge of the silver band: without it the band reads as a
            # broken black dash across the sphere at night (L-NIGHT2)
            edge = lmlib.lathe(lmlib.sphere_band(r, cz, bz - bw * 0.92, bw * 0.16,
                                                 0.30, 0.45), SEG)
            eo = lmlib.obj("BandEdge_%s_%d" % (name, j + 1), edge, col, band_mat)
            lmlib.uv_spherical_metres(eo, r)
            common.smooth(eo, 40.0)
        # the LED dot skin: a SEPARATE shell 0.6 m off the glass, alpha blended
        shell = lmlib.lathe(lmlib.sphere_profile(r + DOT_OFFSET, cz, 26), SEG)
        lo = lmlib.obj("LED_Sphere_" + name, shell, col, led_mat)
        lmlib.uv_spherical_metres(lo, r)
        common.smooth(lo, 60.0)
        # collision hull: a low-poly sphere, convex
        hull = lmlib.lathe(lmlib.sphere_profile(r, cz, 10), 12)
        co = lmlib.obj("OPT_ColSphere_%s-convcolonly" % name, hull, col, glass_mat)
        uv.box_uv(co)


def build_colliders(col, col_mat):
    """Convex hulls for the legs, the tubes and the braces."""
    for k in range(3):
        a = 2 * math.pi * k / 3 + math.pi / 2
        cx, cy = math.cos(a), math.sin(a)
        leg = lmlib.tube((FOOT_R * cx, FOOT_R * cy, 0.0),
                         (TRI_R * cx, TRI_R * cy, 55.0), 4.9, TUBE_R, 8)
        lo = lmlib.obj("OPT_ColLeg_%d-convcolonly" % (k + 1), leg, col, col_mat)
        uv.box_uv(lo)
        tube = lmlib.tube((TRI_R * cx, TRI_R * cy, 52.0),
                          (TRI_R * cx, TRI_R * cy, TUBE_TOP), TUBE_R, TUBE_R, 8)
        to = lmlib.obj("OPT_ColTube_%d-convcolonly" % (k + 1), tube, col, col_mat)
        uv.box_uv(to)
        ba = a + math.pi / 3
        bx, by = math.cos(ba), math.sin(ba)
        brace = lmlib.tube((BRACE_FOOT_R * bx, BRACE_FOOT_R * by, 0.0),
                           (TRI_R * bx, TRI_R * by, 68.0), 3.6, 3.5, 8)
        bo = lmlib.obj("OPT_ColBrace_%d-convcolonly" % (k + 1), brace, col, col_mat)
        uv.box_uv(bo)


def build_lights(col, tube_mat, avia_mat, wash_warm, wash_violet, ring_mat, band_mat):
    """Vertical tube light strips, the lit columns, the rings, the aviation light.

    L-NIGHT2: the tubes were dark navy. They now carry a baked flood wash
    (warm at the foot, violet up the shafts), a light ring every 10 m and a
    2.4 m LED strip on the outer edge of each tube."""
    strips = lmlib.merge()
    wash_w = lmlib.merge()
    wash_v = lmlib.merge()
    rings = lmlib.merge()
    for k in range(3):
        a = 2 * math.pi * k / 3 + math.pi / 2
        cx, cy = math.cos(a), math.sin(a)
        r = TRI_R + TUBE_R + 0.15
        # the splayed leg (12-55 m): the strip follows the leg's outward face
        foot = (FOOT_R * cx + cx * 4.6, FOOT_R * cy + cy * 4.6, 12.0)
        top = (TRI_R * cx + cx * 4.6, TRI_R * cy + cy * 4.6, 55.0)
        strips = lmlib.merge(strips, lmlib.strut(foot, top, 0.30, STRIP_W))
        # the shaft between the two big spheres
        strips = lmlib.merge(strips, lmlib.strut(
            (r * cx, r * cy, 118.0), (r * cx, r * cy, 250.0), 0.30, STRIP_W))
        # the shaft above the upper sphere
        strips = lmlib.merge(strips, lmlib.strut(
            (r * cx, r * cy, 295.0), (r * cx, r * cy, 335.0), 0.30, STRIP_W))
        # the baked flood wash: warm at the foot, violet up the shafts
        wash_w = lmlib.merge(wash_w, lmlib.tube(
            (FOOT_R * cx, FOOT_R * cy, 6.0), (TRI_R * cx, TRI_R * cy, 55.0),
            5.1, 4.75, 14))
        wash_v = lmlib.merge(wash_v, lmlib.tube(
            (TRI_R * cx, TRI_R * cy, 60.0), (TRI_R * cx, TRI_R * cy, 250.0),
            4.66, 4.66, 14))
        wash_v = lmlib.merge(wash_v, lmlib.tube(
            (TRI_R * cx, TRI_R * cy, 296.0), (TRI_R * cx, TRI_R * cy, 334.0),
            4.66, 4.66, 14))
        # a light ring every 10 m between the spheres
        for y in range(120, 250, 10):
            ring = lmlib.lathe([(TUBE_R - 0.05, y - 0.25), (TUBE_R + 0.35, y - 0.25),
                                (TUBE_R + 0.35, y + 0.25), (TUBE_R - 0.05, y + 0.25)],
                               16, cap_bottom=False, cap_top=False)
            bmesh.ops.translate(ring, verts=ring.verts, vec=(TRI_R * cx, TRI_R * cy, 0.0))
            rings = lmlib.merge(rings, ring)
    lmlib.obj("LED_TubeStrips", strips, col, tube_mat)
    lmlib.obj("LED_TubeWashWarm", wash_w, col, wash_warm)
    lmlib.obj("LED_TubeWashViolet", wash_v, col, wash_violet)
    lmlib.obj("LED_TubeRings", rings, col, ring_mat)
    av = lmlib.lathe([(0.0, ANT_TOP - 1.6), (1.1, ANT_TOP - 1.6), (0.9, ANT_TOP),
                      (0.0, ANT_TOP)], 12)
    lmlib.obj("LED_Aviation_Tip", av, col, avia_mat)
    lmlib.empty("Aviation_Tip", (0.0, 0.0, ANT_TOP), direction=(0.0, 0.0, 1.0), col=col, size=6.0)
    for k in range(4):
        a = 2.0 * math.pi * k / 4 + math.pi / 4
        x, y = 62.0 * math.cos(a), 62.0 * math.sin(a)
        lmlib.empty("Flood_Base_%d" % (k + 1), (x, y, 1.0),
                    direction=(-x / 62.0, -y / 62.0, 0.42), col=col, size=4.0)


def main():
    common.reset()
    lmenv.ensure_textures()
    concrete = lmmat.tex_mat("LM_PEARL_Concrete", diff="formwork_diff.png",
                             normal="formwork_nor.png", rough="formwork_rough.png",
                             color=lmmat.hexcol("#D2D2D0"), roughness=0.62,
                             tile=(0.25, 0.25), normal_strength=0.8)
    glass = lmmat.tex_mat("LM_PEARL_Glass", diff="honeycomb_diff.png",
                          normal="honeycomb_nor.png", rough="honeycomb_rough.png",
                          color=lmmat.hexcol("#B0306A"), roughness=0.15, metallic=0.3,
                          tile=(1.0 / HONEY_TILE, 1.0 / HONEY_TILE), normal_strength=0.7)
    alu = lmmat.tex_mat("LM_PEARL_Alu", diff="metal_painted_diff.png",
                        normal="metal_painted_nor.png", rough="metal_painted_rough.png",
                        color=lmmat.hexcol("#C8CCD0"), roughness=0.32, metallic=0.85,
                        tile=(1.0 / ALU_TILE, 1.0 / ALU_TILE), normal_strength=0.8)
    led = lmmat.tex_mat("LED_OPT_Spheres", diff="led_dots_pink.png", alpha_blend=True,
                        color=lmmat.hexcol("#FF3FA4"), roughness=0.35,
                        emission=lmmat.hexcol("#FF3FA4"), emission_strength=4.0,
                        tile=(1.0 / LED_PITCH, 1.0 / LED_PITCH))
    tube_led = lmmat.glow("LED_OPT_Tubes", lmmat.hexcol("#7A4CFF"), strength=3.0)
    wash_warm = lmmat.glow("LED_OPT_WashWarm", lmmat.hexcol("#FFF1E0"), strength=1.2)
    wash_violet = lmmat.glow("LED_OPT_WashViolet", lmmat.hexcol("#7A4CFF"), strength=0.9)
    ring_mat = lmmat.glow("LED_OPT_Rings", lmmat.hexcol("#E8ECFF"), strength=2.2)
    band_edge = lmmat.glow("LED_OPT_BandEdges", lmmat.hexcol("#E8ECFF"), strength=2.0)
    avia = lmmat.glow("LED_Aviation_OPT", lmmat.hexcol("#FF2A3A"), strength=8.0)
    col_mat = lmmat.tex_mat("LM_PEARL_Collider", color=(0.1, 0.1, 0.1), roughness=0.9)

    col = common.collection("OrientalPearl")
    build_body(col, concrete)
    build_podium(col, concrete, glass, col_mat)
    build_spheres(col, glass, alu, led, band_edge)
    build_colliders(col, col_mat)
    build_lights(col, tube_led, avia, wash_warm, wash_violet, ring_mat, band_edge)
    lmlib.finish("oriental_pearl", col)


if __name__ == "__main__":
    main()
