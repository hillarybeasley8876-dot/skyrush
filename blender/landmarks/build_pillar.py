"""Nine-Dragon Pillar (龙柱) - the Yan'an / N-S elevated interchange column.

Dossier 1.2: D 5.0 m column from Y 0 to 29.4 m, dark granite plinth D 6.4 m x
0.6 m, brushed stainless steel with a generated dark archaic-bronze relief (nine
kui-dragons, 雷纹 thunder pattern, sun and moon discs).

The relief ships as a generated texture set (base colour + normal + a real ORM
with the AO in R, the roughness in G and the metalness in B) AND as a
displacement. The mesh uses the 60k budget: 192 x 150 quads = 57.6k triangles.

The four warm uplights stand on the plinth rim (r = 3.1 m, y = 0.65 m) and
graze the column at 86 deg, so the beam rakes the relief from the base to the
top; each one has an emissive housing lens and the plinth lip carries a warm
line.
"""
import math
import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender/landmarks"))
import lmenv  # noqa: E402
from lmenv import bpy, common, geo, lmlib, lmmat, mats, uv  # noqa: E402

COL_R = 2.5
COL_TOP = 29.4
PLINTH_R = 3.2
PLINTH_H = 0.6
SEGS = 192
ROWS = 150
RELIEF_M = 0.12
COL_SEGS = 24            # the collision hull is a 24-sided cylinder
FLOOD_R = 3.1            # the uplights stand on the plinth rim
FLOOD_Y = 0.65
FLOOD_ELEV = 87.0        # degrees above the horizon: the beam rakes the column
WASH_R = 6.0             # the wash lights stand 6 m out from the axis


def build_column(col, steel_mat, granite_mat, col_mat):
    body = lmlib.cylinder_mesh(COL_R, 0.0, COL_TOP, SEGS, cap_bottom=False,
                                cap_top=True, rows=ROWS)
    o = lmlib.obj("Pillar_Column", body, col, steel_mat)
    common.smooth(o, 35.0)      # shared vertices: the exporter keeps the file small
    # displace with the height map: the dragons, the hooks and the panel recess
    tex = bpy.data.textures.new("PillarRelief", type="IMAGE")
    tex.image = bpy.data.images.load(os.path.join(lmenv.TEXTURES, "pillar_height.png"),
                                     check_existing=True)
    mod = o.modifiers.new("Relief", "DISPLACE")
    mod.texture = tex
    mod.texture_coords = "UV"
    mod.direction = "NORMAL"
    mod.mid_level = 0.0
    mod.strength = RELIEF_M
    # plinth: a slightly tapered dark granite drum
    plinth = lmlib.lathe([(0.0, 0.0), (PLINTH_R + 0.12, 0.0), (PLINTH_R, 0.18),
                          (PLINTH_R, PLINTH_H), (COL_R + 0.05, PLINTH_H + 0.12),
                          (0.0, PLINTH_H + 0.12)], SEGS, cap_bottom=False)
    po = lmlib.obj("Pillar_Plinth", plinth, col, granite_mat)
    uv.box_uv(po)
    # collision hull: a 24-sided cylinder kept just inside the visible surface
    # (the column is 2.50 m and the relief pushes it out to 2.62 m), so the
    # hull never shows over the model in a preview render
    hull = lmlib.lathe([(0.0, 0.0), (COL_R - 0.12, 0.0), (COL_R - 0.12, COL_TOP),
                        (0.0, COL_TOP)], COL_SEGS, cap_bottom=False, cap_top=False)
    co = lmlib.obj("Pillar_ColColumn-colonly", hull, col, col_mat)
    uv.box_uv(co)
    return o


def build_lights(col, lens_mat, plinth_mat, housing_mat):
    """The four uplight housings on the plinth rim + the plinth lip line."""
    lens = lmlib.merge()
    body = lmlib.merge()
    el = math.radians(FLOOD_ELEV)
    for k in range(4):
        a = 2.0 * math.pi * k / 4 + math.pi / 4
        px, py = FLOOD_R * math.cos(a), FLOOD_R * math.sin(a)
        d = (-math.cos(a) * math.cos(el), -math.sin(a) * math.cos(el), math.sin(el))
        p0 = (px, py, FLOOD_Y)
        p1 = (px + d[0] * 0.07, py + d[1] * 0.07, FLOOD_Y + d[2] * 0.07)
        lens = lmlib.merge(lens, lmlib.strut(p0, p1, 0.35, 0.20))
        b0 = (px, py, FLOOD_Y)
        b1 = (px - d[0] * 0.22, py - d[1] * 0.22, FLOOD_Y - d[2] * 0.22)
        body = lmlib.merge(body, lmlib.strut(b0, b1, 0.42, 0.26))
    lo = lmlib.obj("LED_Pillar_Uplights", lens, col, lens_mat)
    uv.box_uv(lo)
    bo = lmlib.obj("Pillar_UplightHousings", body, col, housing_mat)
    uv.box_uv(bo)
    # the warm line under the plinth lip (3 cm)
    ring = lmlib.lathe([(PLINTH_R + 0.02, PLINTH_H - 0.10),
                        (PLINTH_R + 0.02, PLINTH_H - 0.07)], SEGS,
                       cap_bottom=False, cap_top=False)
    ro = lmlib.obj("LED_Pillar_Plinth", ring, col, plinth_mat)
    uv.box_uv(ro)


def main():
    common.reset()
    lmenv.ensure_textures()
    import tex_pillar
    import tex_pillar_maps
    _refresh_pillar_maps(tex_pillar, tex_pillar_maps)
    # a REAL ORM: R = AO, G = roughness, B = metalness (the r3 review: the
    # pillar ORM was wired as AO only, with a constant roughness and metal)
    steel = lmmat.orm_mat(
        "LM_PILLAR_Steel",
        diff=lmmat.jpeg_copy("pillar_basecolor.png", 88, 4096, "pillar_bc.jpg"),
        normal=lmmat.jpeg_copy("pillar_normal.png", 88, 0, "pillar_nor.jpg"),
        orm=lmmat.jpeg_copy("pillar_orm.png", 88, 4096, "pillar_orm.jpg"),
        color=(1.0, 1.0, 1.0), tile=(1.0, 1.0), normal_strength=1.4,
        metallic=1.0, roughness=0.30, pack=True)
    # plinth: library granite, tinted to #3A3A3C (core mats.pbr keeps the texture
    # and applies the tint as the baseColorFactor). 1024 px over 2 m = 512 px/m
    granite = mats.pbr("LM_PILLAR_Granite", tex="granite_tile_03",
                       color=(1.0, 1.0, 1.0), roughness=0.6, metallic=0.0, tile_m=2.0,
                       tint=(0.225, 0.225, 0.235))
    lmmat.shrink_material_images(granite, 1024, 85)
    col_mat = lmmat.tex_mat("LM_PILLAR_Collider", color=(0.1, 0.1, 0.1), roughness=0.9)
    lens_mat = lmmat.glow("LED_Pillar_Uplights", lmmat.hexcol("#FFC98A"), strength=3.0)
    plinth_led = lmmat.glow("LED_Pillar_Plinth", lmmat.hexcol("#FFC98A"), strength=1.5)
    col = common.collection("DragonPillar")
    build_column(col, steel, granite, col_mat)
    housing = lmmat.tex_mat("LM_Pillar_Housing", diff="metal_dark_diff.png",
                           normal="metal_dark_nor.png", rough="metal_dark_rough.png",
                           color=lmmat.hexcol("#0D0E10"), roughness=0.5, metallic=0.6,
                           tile=(0.8, 0.8), normal_strength=0.8)
    build_lights(col, lens_mat, plinth_led, housing)
    # four warm ground uplights on the plinth rim, aimed up the column
    el = math.radians(FLOOD_ELEV)
    for k in range(4):
        a = 2.0 * math.pi * k / 4 + math.pi / 4
        x, y = FLOOD_R * math.cos(a), FLOOD_R * math.sin(a)
        lmlib.empty("Flood_Base_%d" % (k + 1), (x, y, FLOOD_Y),
                    direction=(-math.cos(a) * math.cos(el),
                               -math.sin(a) * math.cos(el), math.sin(el)),
                    col=col, size=1.2)
    # the wash lights: a vertical beam on a vertical cylinder meets it at
    # 0.05 of the cosine, so four uplights can only reach the bottom third.
    # These eight sit 5 m out at two heights and light a 4 m band each, so
    # the column reads warm silver from the plinth to the top deck.
    for tag, (wy, elev) in (("Low", (4.0, 6.0)), ("Mid", (13.0, 0.0)),
                            ("High", (22.0, -6.0))):
        el2 = math.radians(elev)
        for k in range(4):
            a = 2.0 * math.pi * k / 4 + math.pi / 4
            x, y = WASH_R * math.cos(a), WASH_R * math.sin(a)
            lmlib.empty("Flood_Wash_%s_%d" % (tag, k + 1), (x, y, wy),
                        direction=(-math.cos(a) * math.cos(el2),
                                   -math.sin(a) * math.cos(el2), math.sin(el2)),
                        col=col, size=1.6)
    lmlib.empty("Flood_Under_Deck", (0.0, 0.0, COL_TOP - 0.4), direction=(0.0, 0.0, -1.0),
                col=col, size=1.2)
    lmlib.finish("dragon_pillar", col)


def _refresh_pillar_maps(tex_pillar, tex_pillar_maps):
    """Regenerate the pillar maps when the generator is newer than the files."""
    out = lmenv.TEXTURES
    names = ("pillar_basecolor.png", "pillar_normal.png", "pillar_orm.png",
             "pillar_height.png")
    srcs = [os.path.join(lmenv.BL, "landmarks", "tex_pillar.py"),
            os.path.join(lmenv.BL, "landmarks", "tex_pillar_maps.py")]
    newest_src = max(os.path.getmtime(s) for s in srcs)
    oldest_out = min(os.path.getmtime(os.path.join(out, n))
                     for n in names if os.path.exists(os.path.join(out, n)))
    if len([n for n in names if os.path.exists(os.path.join(out, n))]) != len(names) \
            or oldest_out < newest_src:
        print("  pillar maps are stale - regenerating")
        tex_pillar_maps.main()


if __name__ == "__main__":
    main()
