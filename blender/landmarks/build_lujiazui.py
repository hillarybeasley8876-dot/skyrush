"""Lujiazui backdrop towers and the Pearl Ring skybridge (明珠环).

- lujiazui_backdrop.glb: 12 generic but distinct glass towers 150-260 m with
  lit crowns, anchored on the Lujiazui core centre (748, -489). Nothing stands
  in the corridor between the Bund promenade and the Oriental Pearl.
- pearl_ring.glb: circular steel skybridge, D 117.5 m, deck top Y = 6.7 m (the
  girder soffit stays above 5.5 m), 9.7 m wide, 1.0 m deep white box girder,
  glass balustrade, 8 stout Y-columns, stairs and escalators on the ground.
"""
import math
import os
import sys

import bmesh

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender/landmarks"))
import lmenv  # noqa: E402
from lmenv import bpy, common, geo, lmlib, lmmat, mats, uv  # noqa: E402
import lmbackdrop  # noqa: E402
from mathutils import Vector  # noqa: E402

CORE = (748.0, -488.8)
RING_R = 58.75
DECK_Y = 6.7                  # deck top (soffit 5.7 m > 5.5 m clearance)
GIRDER_D = 1.0
DECK_W = 9.7
BALUSTRADE_H = 1.3
COL_R = 1.15                  # Y-column shaft radius
COL_COUNT = 8

# name, map x, map z, width, depth, height, crown, plan
def balustrade_uv(obj, radius, y0, height):
    """UVs for the balustrade: 1.5 m panels around, one panel up.

    The V axis runs 0..1 over the panel height so the glass sheet's dirt band
    lands on the bottom 10 cm above the deck."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    for face in bm.faces:
        for loop in face.loops:
            co = loop.vert.co
            a = math.atan2(co.y, co.x)
            if a < 0.0:
                a += 2.0 * math.pi
            loop[layer].uv = (a * radius / 1.5, (co.z - y0) / height)
    bm.to_mesh(me)
    bm.free()
    return obj


def build_ring(col, steel, glass, rail_mat, col_mat, downlight_mat):
    r_in = RING_R - DECK_W * 0.5
    r_out = RING_R
    soffit = DECK_Y - GIRDER_D
    # deck: white steel box girder with a rounded fascia
    deck = lmlib.lathe([(r_in, soffit), (r_out - 0.6, soffit), (r_out, soffit + 0.45),
                        (r_out, DECK_Y - 0.35), (r_out - 0.45, DECK_Y),
                        (r_in, DECK_Y)], 72, cap_bottom=False, cap_top=False)
    do = lmlib.obj("PearlRing_Deck", deck, col, steel)
    uv.box_uv(do)
    # collision only copy covering the full girder volume
    colmesh = lmlib.lathe([(r_in, soffit), (r_out, soffit), (r_out, DECK_Y),
                           (r_in, DECK_Y), (r_in, soffit)], 48,
                          cap_bottom=False, cap_top=False)
    co = lmlib.obj("PearlRing_ColDeck-colonly", colmesh, col, col_mat)
    uv.box_uv(co)
    # glass balustrade on the outer edge
    bal = lmlib.lathe([(r_out - 0.12, DECK_Y), (r_out - 0.12, DECK_Y + BALUSTRADE_H),
                       (r_out + 0.02, DECK_Y + BALUSTRADE_H), (r_out + 0.02, DECK_Y),
                       (r_out - 0.12, DECK_Y)], 64, cap_bottom=False, cap_top=False)
    bo = lmlib.obj("PearlRing_Balustrade", bal, col, glass)
    balustrade_uv(bo, r_out, DECK_Y, BALUSTRADE_H)
    # LED handrail
    rail = lmlib.lathe([(r_out - 0.05, DECK_Y + BALUSTRADE_H),
                        (r_out + 0.09, DECK_Y + BALUSTRADE_H),
                        (r_out + 0.09, DECK_Y + BALUSTRADE_H + 0.25),
                        (r_out - 0.05, DECK_Y + BALUSTRADE_H + 0.25),
                        (r_out - 0.05, DECK_Y + BALUSTRADE_H)], 64,
                       cap_bottom=False, cap_top=False)
    ro = lmlib.obj("LED_PearlRing_Handrail", rail, col, rail_mat)
    uv.box_uv(ro)
    # 8 stout Y-columns: one shaft, a flared Y head under the deck
    cols = lmlib.merge()
    for k in range(COL_COUNT):
        a = 2.0 * math.pi * k / COL_COUNT + math.pi / COL_COUNT
        r = (r_in + r_out) * 0.5
        cx, cy = r * math.cos(a), r * math.sin(a)
        cols = lmlib.merge(cols, lmlib.tube((cx, cy, 0.0), (cx, cy, DECK_Y - 2.6),
                                             COL_R, COL_R * 0.85, 14))
        for sgn in (-1.0, 1.0):
            cols = lmlib.merge(cols, lmlib.tube(
                (cx, cy, DECK_Y - 2.6),
                (cx + sgn * 2.3 * math.cos(a + math.pi / 2),
                 cy + sgn * 2.3 * math.sin(a + math.pi / 2), soffit + 0.1),
                COL_R * 0.8, COL_R * 0.5, 10))
    clo = lmlib.obj("PearlRing_Columns", cols, col, steel)
    uv.box_uv(clo)
    # collision hulls: one per Y-column and one per stair tower
    ccols = lmlib.merge()
    for k in range(COL_COUNT):
        a = 2.0 * math.pi * k / COL_COUNT + math.pi / COL_COUNT
        r = (r_in + r_out) * 0.5
        cx, cy = r * math.cos(a), r * math.sin(a)
        ccols = lmlib.merge(ccols, lmlib.tube((cx, cy, 0.0), (cx, cy, DECK_Y - 2.6),
                                              COL_R + 0.2, COL_R + 0.2, 8))
    cco = lmlib.obj("PearlRing_ColColumns-colonly", ccols, col, col_mat)
    uv.box_uv(cco)
    cst = lmlib.merge()
    for k in range(4):
        a = 2.0 * math.pi * k / 4 + math.pi / 4
        r = r_out - 1.2
        px, py = r * math.cos(a), r * math.sin(a)
        rot = a + math.pi / 2.0
        cst = lmlib.merge(cst, lmlib.box((px, py, DECK_Y * 0.5), (1.8, 3.2, DECK_Y * 0.5),
                                         rot_z=rot))
    cso = lmlib.obj("PearlRing_ColStairs-colonly", cst, col, col_mat)
    uv.box_uv(cso)
    # stairs, escalator truss, handrails and a canopy at 4 points (on the ground)
    st = lmlib.merge()
    for k in range(4):
        a = 2.0 * math.pi * k / 4 + math.pi / 4
        r = r_out - 1.2
        px, py = r * math.cos(a), r * math.sin(a)
        rot = a + math.pi / 2.0
        steps = 12
        run = (DECK_Y - 0.4) / steps
        for s in range(steps):
            st = lmlib.merge(st, lmlib.box(
                (px, py, 0.2 + run * (s + 0.5)), (3.0, 0.34, 0.1), rot_z=rot))
        # stringers + handrails
        for sgn in (-1.0, 1.0):
            st = lmlib.merge(st, lmlib.box(
                (px - sgn * 1.5 * math.cos(rot), py - sgn * 1.5 * math.sin(rot),
                 DECK_Y * 0.5), (0.12, 0.12, DECK_Y + 0.9), rot_z=rot))
        # escalator truss with glass sides
        st = lmlib.merge(st, lmlib.box(
            (px + 2.6 * math.cos(rot), py + 2.6 * math.sin(rot), DECK_Y * 0.5),
            (1.4, 0.5, DECK_Y), rot_z=rot))
        # canopy
        st = lmlib.merge(st, lmlib.box(
            (px + 1.0 * math.cos(rot), py + 1.0 * math.sin(rot), DECK_Y + 2.4),
            (7.0, 4.0, 0.18), rot_z=rot))
        for sgn in (-1.0, 1.0):
            st = lmlib.merge(st, lmlib.box(
                (px + 1.0 * math.cos(rot) - sgn * 3.0 * math.cos(rot),
                 py + 1.0 * math.sin(rot) - sgn * 3.0 * math.sin(rot), DECK_Y + 1.2),
                (0.14, 0.14, 2.4), rot_z=rot))
    so = lmlib.obj("PearlRing_Stairs", st, col, steel)
    uv.box_uv(so)
    # under-deck downlights
    dl = lmlib.merge()
    for k in range(COL_COUNT * 3):
        a = 2.0 * math.pi * k / (COL_COUNT * 3)
        r = (r_in + r_out) * 0.5
        lx, ly = r * math.cos(a), r * math.sin(a)
        lamp = lmlib.lathe([(0.0, 0.0), (0.3, 0.0), (0.26, -0.18), (0.0, -0.18)], 10)
        for v in lamp.verts:
            v.co += Vector((lx, ly, soffit - 0.02))
        dl = lmlib.merge(dl, lamp)
    lmlib.obj("LED_PearlRing_Downlights", dl, col, downlight_mat)


def main():
    common.reset()
    lmenv.ensure_textures()
    glass = lmmat.tex_mat("LM_Backdrop_Glass", diff="facade_night_diff.png",
                          emit="facade_night_emit.png", normal="facade_night_nor.png",
                          color=lmmat.hexcol("#4A545E"), roughness=0.16, metallic=0.35,
                          tile=(0.17, 0.07), emit_strength=1.3)
    crown = lmmat.glow("LED_Backdrop_Crown", lmmat.hexcol("#DCE8FF"), strength=3.0)
    plate = lmmat.tex_mat("LM_Ad_Plate", diff="metal_dark_diff.png",
                          normal="metal_dark_nor.png", rough="metal_dark_rough.png",
                          color=lmmat.hexcol("#141416"), roughness=0.45, metallic=0.1,
                          tile=(0.55, 0.55), normal_strength=0.8)
    ad_mats = {}
    for (name, (image, _h)) in lmbackdrop.ADS.items():
        ad_mats[name] = lmmat.emit_mat("LED_Ad_" + name, image,
                                       lmmat.hexcol("#FFFFFF"), strength=2.5,
                                       base=(0.02, 0.02, 0.03))
    col = common.collection("LujiazuiBackdrop")
    colmat = lmmat.tex_mat("LM_BACKDROP_Collider", color=(0.1, 0.1, 0.1), roughness=0.9)
    led = lmmat.glow("LED_Crown_Backdrop", lmmat.hexcol("#DCE8FF"), strength=3.0)
    avia = lmmat.glow("LED_Aviation_Backdrop", lmmat.hexcol("#FF2A3A"), strength=8.0)
    lmbackdrop.build_backdrop(col, glass, crown, ad_mats, plate, colmat, led, avia)
    lmlib.finish("lujiazui_backdrop", col)

    steel = lmmat.tex_mat("LM_RING_Steel", diff="metal_white_diff.png",
                          normal="metal_white_nor.png", rough="metal_white_rough.png",
                          color=lmmat.hexcol("#F0F0EE"), roughness=0.36, metallic=0.25,
                          tile=(0.42, 0.42), normal_strength=0.8)
    bal = lmmat.tex_mat("LM_RING_Glass", diff="ring_glass_diff.png",
                        normal="ring_glass_nor.png", rough="ring_glass_rough.png",
                        color=lmmat.hexcol("#CFE6F0"), roughness=0.05, metallic=0.0,
                        tile=(1.0 / 1.5, 1.0 / BALUSTRADE_H), normal_strength=0.5,
                        alpha_value=0.3)
    rail = lmmat.glow("LED_PearlRing_Handrail", lmmat.hexcol("#E6F2FF"), strength=2.6)
    downlight = lmmat.glow("LED_PearlRing_Downlights", lmmat.hexcol("#FFE9C8"), strength=2.0)
    colmat = lmmat.tex_mat("LM_RING_Collider", color=(0.1, 0.1, 0.1), roughness=0.9)
    col = common.collection("PearlRing")
    build_ring(col, steel, bal, rail, colmat, downlight)
    lmlib.finish("pearl_ring", col)


if __name__ == "__main__":
    main()
