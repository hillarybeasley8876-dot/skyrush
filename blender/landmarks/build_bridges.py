"""Shanghai bridges: Nanpu (南浦大桥) and Lupu (卢浦大桥, far silhouette).

Both are modelled in a bridge-local frame: origin at the map anchor, +Y along
the deck axis, Y up. The map anchor and the Godot Y rotation for each are
listed in lmlib.BRIDGE_FRAMES and in landmarks_manifest.json. The Waibaidu
bridge lives in build_waibaidu.py.
"""
import math
import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender/landmarks"))
import lmenv  # noqa: E402
from lmenv import bpy, common, geo, lmlib, lmmat, uv  # noqa: E402
from mathutils import Vector  # noqa: E402

import build_waibaidu

FONT = os.path.join(common.GAME, "assets", "fonts", "NotoSansSC-Variable.ttf")

# ---------------------------------------------------------------- Nanpu (dossier 3.2)
NP_TOWER_Y = 211.5          # main span 423 m
NP_END_W = -410.6
NP_END_E = 361.5
NP_TOWER_H = 150.0
NP_TOWER_FOOT = -3.0        # the towers start below the water line
NP_LEG_TOP = 17.2           # leg axis offset above the deck
NP_LEG_BASE = 21.0          # leg axis offset at the footing (splayed)
NP_LEG_BX, NP_LEG_BY = 3.0, 2.25    # leg section at the base (6.0 x 4.5 m)
NP_LEG_TX, NP_LEG_TY = 2.0, 1.75    # leg section at the top (4.0 x 3.5 m)
NP_DECK_MID = 45.5
NP_DECK_TOWER = 44.0
NP_DECK_W = 30.35
NP_LOW_BEAM_Y = 40.5        # lower crossbeam just under the deck
NP_SIGN_Y = 131.0           # upper crossbeam carrying the name sign
NP_SIGN_H = 4.0             # character size
NP_CABLE_DECK_X = 14.9      # cable plane at the deck (on the edge girder)
NP_CABLE_TOWER_X = 15.6     # cable anchor inside the leg section
NP_CABLE_R = 0.06           # cable radius (D 0.12 m): a thin lit line, not a plank
NP_CABLE_TOP = 95.0         # first tower anchor height
NP_CABLE_STEP = 2.3         # tower anchor spacing
NP_CABLE_SPACING = 9.6      # deck anchor spacing

# ---------------------------------------------------------------- Lupu (dossier 3.4)
LU_SPAN = 550.0
LU_RISE = 100.0
LU_WIDTH = 28.75
LU_RIB_W = 5.0
LU_RIB_D = 9.0
LU_LED_W = 5.7              # rainbow stroke width (5.7 m reads at 2.2 km)

def np_deck_y(along):
    """Road level along the bridge (local +Y)."""
    if abs(along) >= NP_TOWER_Y:
        t = (abs(along) - NP_TOWER_Y) / (abs(NP_END_W) - NP_TOWER_Y)
        return NP_DECK_TOWER + (42.5 - NP_DECK_TOWER) * t
    t = abs(along) / NP_TOWER_Y
    return NP_DECK_TOWER + (NP_DECK_MID - NP_DECK_TOWER) * (1.0 - t * t)


def _offset(plan, cx, cy):
    return [(x + cx, y + cy) for (x, y) in plan]


def _tapered_box(z0, z1, c0, c1, hx0, hy0, hx1, hy1, chamfer=0.3):
    """A rectangular leg: 6.0 x 4.5 m at the base tapering to 4.0 x 3.5 m, chamfered."""
    p0 = _offset(lmlib.rect(hx0, hy0, chamfer), c0[0], c0[1])
    p1 = _offset(lmlib.rect(hx1, hy1, chamfer), c1[0], c1[1])
    return lmlib.loft_plans([p0, p1], [z0, z1], cap_start=True, cap_end=True)


def build_nanpu(col, concrete, cable_mat, sign_mat, back_mat, deck_led, col_mat,
                wash_mat, wash_dim_mat, under_mat, avia_mat):
    """Two H-towers with bent legs, 180 cables, name sign, deck edge lights."""
    bm = lmlib.merge()
    for tsign in (-1.0, 1.0):
        along = tsign * NP_TOWER_Y
        for lsign in (-1.0, 1.0):
            base_c = (lsign * NP_LEG_BASE, along)
            deck_c = (lsign * NP_LEG_TOP, along)
            top_c = (lsign * NP_LEG_TOP, along)
            # splayed leg below the deck, vertical above
            bm = lmlib.merge(bm, _tapered_box(NP_TOWER_FOOT, NP_DECK_TOWER - 2.0,
                                               base_c, deck_c,
                                               NP_LEG_BX, NP_LEG_BY,
                                               NP_LEG_TX, NP_LEG_TY))
            bm = lmlib.merge(bm, _tapered_box(NP_DECK_TOWER - 3.0, NP_TOWER_H - 3.0,
                                               deck_c, top_c,
                                               NP_LEG_TX, NP_LEG_TY,
                                               NP_LEG_TX * 0.85, NP_LEG_TY * 0.85))
            # cable anchor blocks on the inner face of each leg
            for k in range(0, 22, 2):
                y = NP_CABLE_TOP + k * NP_CABLE_STEP
                bm = lmlib.merge(bm, lmlib.box(
                    (lsign * (NP_CABLE_TOWER_X - 0.4), along, y), (1.2, 2.6, 1.1)))
        # lower crossbeam just under the deck
        bm = lmlib.merge(bm, _tapered_box(NP_LOW_BEAM_Y - 1.6, NP_LOW_BEAM_Y + 1.6,
                                           (0.0, along), (0.0, along),
                                           NP_LEG_TOP, 1.8, NP_LEG_TOP, 1.6))
        # upper crossbeam carrying the name sign
        bm = lmlib.merge(bm, _tapered_box(NP_SIGN_Y - 3.0, NP_SIGN_Y + 3.0,
                                           (0.0, along), (0.0, along),
                                           NP_LEG_TOP, 1.8, NP_LEG_TOP, 1.6))
        # tower cap
        bm = lmlib.merge(bm, lmlib.box((0.0, along, NP_TOWER_H - 2.6),
                                        (2.0 * NP_LEG_TOP, 4.4, 1.2)))
    tower = lmlib.obj("Nanpu_Towers", bm, col, concrete)
    uv.box_uv(tower)
    # the baked flood wash (L-NIGHT3): the real floods are 12.5 deg beams at
    # deck level and never reach the 150 m tops, so the legs and the
    # crossbeams carry their own wash - warm white, stronger under the beams
    wash_lo = lmlib.merge()
    wash_hi = lmlib.merge()
    for tsign in (-1.0, 1.0):
        along = tsign * NP_TOWER_Y
        for lsign in (-1.0, 1.0):
            base_c = (lsign * NP_LEG_BASE, along)
            deck_c = (lsign * NP_LEG_TOP, along)
            wash_lo = lmlib.merge(wash_lo, _tapered_box(
                NP_TOWER_FOOT, NP_DECK_TOWER - 2.0, base_c, deck_c,
                NP_LEG_BX + 0.06, NP_LEG_BY + 0.06,
                NP_LEG_TX + 0.06, NP_LEG_TY + 0.06))
            wash_hi = lmlib.merge(wash_hi, _tapered_box(
                NP_DECK_TOWER - 3.0, NP_TOWER_H - 3.0, deck_c, deck_c,
                NP_LEG_TX + 0.06, NP_LEG_TY + 0.06,
                NP_LEG_TX * 0.85 + 0.06, NP_LEG_TY * 0.85 + 0.06))
        wash_lo = lmlib.merge(wash_lo, _tapered_box(
            NP_LOW_BEAM_Y - 1.6, NP_LOW_BEAM_Y + 1.6, (0.0, along), (0.0, along),
            NP_LEG_TOP + 0.06, 1.86, NP_LEG_TOP + 0.06, 1.66))
    lmlib.obj("LED_Nanpu_WashLow", wash_lo, col, wash_mat)
    lmlib.obj("LED_Nanpu_WashHigh", wash_hi, col, wash_dim_mat)
    # cables: 2 planes x 2 sides per tower (the dossier's 180 in total)
    cables = lmlib.merge()
    for tsign in (-1.0, 1.0):
        along = tsign * NP_TOWER_Y
        for side in (-1.0, 1.0):
            if side * tsign < 0:
                reach = NP_TOWER_Y
            else:
                reach = (abs(NP_END_W) if tsign < 0 else NP_END_E) - NP_TOWER_Y
            count = max(4, min(22, int(reach / NP_CABLE_SPACING)))
            for plane in (-1.0, 1.0):
                for k in range(count):
                    y_tower = NP_CABLE_TOP + k * NP_CABLE_STEP
                    d = along + side * (k + 1) * NP_CABLE_SPACING
                    cables = lmlib.merge(cables, lmlib.tube(
                        (plane * NP_CABLE_TOWER_X, along, y_tower),
                        (plane * NP_CABLE_DECK_X, d, np_deck_y(d) + 0.4),
                        NP_CABLE_R, NP_CABLE_R, 5))
    co = lmlib.obj("LED_Nanpu_Cables", cables, col, cable_mat)
    uv.box_uv(co)
    # deck edge LED lines
    edge = lmlib.merge()
    for sgn in (-1.0, 1.0):
        pts = []
        n = 40
        for i in range(n + 1):
            u = NP_END_W + (NP_END_E - NP_END_W) * i / n
            pts.append((sgn * (NP_DECK_W * 0.5 - 0.6), u, np_deck_y(u) + 0.2))
        edge = lmlib.merge(edge, _ribbon(pts, 0.5))
    eo = lmlib.obj("LED_Nanpu_DeckEdge", edge, col, deck_led)
    uv.box_uv(eo)
    # the orange under-deck strip
    under = lmlib.merge()
    for sgn in (-1.0, 1.0):
        pts = []
        n = 40
        for i in range(n + 1):
            u = NP_END_W + (NP_END_E - NP_END_W) * i / n
            pts.append((sgn * (NP_DECK_W * 0.5 - 1.4), u, np_deck_y(u) - 0.9))
        under = lmlib.merge(under, _ribbon(pts, 0.4))
    uo = lmlib.obj("LED_Nanpu_UnderStrip", under, col, under_mat)
    uv.box_uv(uo)
    # name signs on both upper crossbeams (each facing the main span)
    for tsign in (-1.0, 1.0):
        tag = "W" if tsign < 0 else "E"
        plate = lmlib.box((0.0, tsign * NP_TOWER_Y - tsign * 1.85, NP_SIGN_Y),
                          (9.55, 0.35, 3.0))
        lmlib.obj("Nanpu_SignPlate_" + tag, plate, col, back_mat)
        sign = lmlib.text_mesh("LED_Nanpu_Sign_" + tag, "南浦大桥", NP_SIGN_H, FONT, col,
                               extrude=0.22)
        sign.location = (0.0, tsign * NP_TOWER_Y - tsign * 2.1, NP_SIGN_Y)
        # the W sign faces +Y (the main span): rotate 180 deg about Z
        sign.rotation_euler = (math.radians(90.0), 0.0, math.pi if tsign < 0 else 0.0)
        sign.data.materials.append(sign_mat)
    # tower floods: 4 per tower, 3 m outboard of each leg face, aimed up the leg
    for tsign in (-1.0, 1.0):
        for lsign in (-1.0, 1.0):
            for fsign in (-1.0, 1.0):
                lmlib.empty("Flood_Nanpu_Leg_%s%d%d" % ("WE"[tsign > 0],
                                                        1 if lsign < 0 else 2,
                                                        1 if fsign < 0 else 2),
                            (lsign * NP_LEG_TX + fsign * 3.0,
                             tsign * NP_TOWER_Y, NP_DECK_TOWER),
                            direction=(-fsign * 0.22, 0.0, 0.97), col=col, size=3.0)
    lmlib.empty("Flood_Nanpu_Under_W", (0.0, -NP_TOWER_Y, NP_DECK_TOWER - 2.0),
                direction=(0.0, 0.0, -1.0), col=col, size=3.0)
    lmlib.empty("Flood_Nanpu_Under_E", (0.0, NP_TOWER_Y, NP_DECK_TOWER - 2.0),
                direction=(0.0, 0.0, -1.0), col=col, size=3.0)
    for tsign in (-1.0, 1.0):
        tag = "W" if tsign < 0 else "E"
        lmlib.aviation_beacon(col, "LED_Aviation_Nanpu_" + tag, 0.0,
                               tsign * NP_TOWER_Y, NP_TOWER_H, avia_mat)
    # collision hulls: one per leg
    legs = lmlib.merge()
    for tsign in (-1.0, 1.0):
        along = tsign * NP_TOWER_Y
        for lsign in (-1.0, 1.0):
            legs = lmlib.merge(legs, _tapered_box(NP_DECK_TOWER - 3.0, NP_TOWER_H - 3.0,
                                                  (lsign * NP_LEG_BASE, along),
                                                  (lsign * NP_LEG_TOP, along),
                                                  NP_LEG_BX, NP_LEG_BY,
                                                  NP_LEG_TX, NP_LEG_TY))
    lco = lmlib.obj("Nanpu_ColLegs-colonly", legs, col, col_mat)
    uv.box_uv(lco)


def _ribbon(pts, width):
    """A flat ribbon strip through 3D points (deck edge light)."""
    import bmesh
    bm = bmesh.new()
    left, right = [], []
    for i, p in enumerate(pts):
        a = Vector(pts[max(i - 1, 0)])
        b = Vector(pts[min(i + 1, len(pts) - 1)])
        t = (b - a)
        t = t.normalized() if t.length > 1e-6 else Vector((0, 1, 0))
        n = Vector((t.z, 0.0, -t.x))
        if n.length < 1e-6:
            n = Vector((1, 0, 0))
        n = n.normalized() * (width * 0.5)
        c = Vector(p)
        left.append(bm.verts.new(c + n))
        right.append(bm.verts.new(c - n))
    for i in range(len(pts) - 1):
        bm.faces.new((left[i], right[i], right[i + 1], left[i + 1]))
    bm.normal_update()
    return bm


# ---------------------------------------------------------------- Lupu
def lu_arch_y(u):
    """Parabolic arch: springing at +-275, crown at +100."""
    return LU_RISE * (1.0 - (u / (LU_SPAN * 0.5)) ** 2)


def build_lupu(col, steel, rainbow_mats, sign_mat):
    """Low-poly half-through arch with a rainbow LED lining and hangers."""
    n = 44
    arch_pts = []
    for i in range(n + 1):
        u = -LU_SPAN * 0.5 + LU_SPAN * i / n
        arch_pts.append(Vector((0.0, u, lu_arch_y(u))))
    ribs = lmlib.merge()
    for sgn in (-1.0, 1.0):
        path = [Vector((sgn * (LU_WIDTH * 0.5 - LU_RIB_W * 0.5), p.y, p.z)) for p in arch_pts]
        prof = [(-LU_RIB_W * 0.5, -LU_RIB_D * 0.5), (LU_RIB_W * 0.5, -LU_RIB_D * 0.5),
                (LU_RIB_W * 0.5, LU_RIB_D * 0.5), (-LU_RIB_W * 0.5, LU_RIB_D * 0.5)]
        ribs = lmlib.merge(ribs, geo.sweep(prof, path, closed_profile=True, closed_path=False))
    ao = lmlib.obj("Lupu_Arch", ribs, col, steel)
    uv.box_uv(ao)
    # The rainbow: seven fully saturated bands along the arch (the r3 arch
    # rendered WHITE - the emissive texture was mipped away into grey). Each
    # band is a real strip with its own colour, so the arch reads as a
    # rainbow from the Nanpu deck 2.2 km away.
    for i, mat in enumerate(rainbow_mats):
        i0 = int(round(n * i / float(len(rainbow_mats))))
        i1 = int(round(n * (i + 1) / float(len(rainbow_mats))))
        seg = arch_pts[i0:i1 + 1]
        if len(seg) < 2:
            continue
        for sgn, tag in ((-1.0, "W"), (1.0, "E")):
            path = [Vector((sgn * (LU_WIDTH * 0.5 - LU_RIB_W * 0.5), p.y, p.z)) for p in seg]
            for fsign, side in ((-1.0, "a"), (1.0, "b")):
                # the band stands 0.6 m PROUD of the rib's side face, otherwise
                # it is buried inside the rib and never renders
                x0 = fsign * (LU_RIB_W * 0.5 + 0.60)
                prof = [(x0, -LU_RIB_D * 0.5), (x0 - fsign * 0.60, -LU_RIB_D * 0.5),
                        (x0 - fsign * 0.60, LU_RIB_D * 0.5), (x0, LU_RIB_D * 0.5)]
                bm = geo.sweep(prof, path, closed_profile=True)
                lo = lmlib.obj("LED_Lupu_Arch_%s%s_%d" % (tag, side, i + 1), bm, col, mat)
                uv.strip_uv(lo, along_axis="length")
    # hangers from the arch down to the deck
    hang = lmlib.merge()
    for i in range(2, n - 1, 2):
        u = arch_pts[i].y
        z = lu_arch_y(u)
        if z < 6.0:
            continue
        for sgn in (-1.0, 1.0):
            hang = lmlib.merge(hang, lmlib.tube(
                (sgn * (LU_WIDTH * 0.5 - 1.0), u, 0.0), (sgn * (LU_WIDTH * 0.5 - 1.0), u, z - 4.0),
                0.22, 0.22, 5))
    ho = lmlib.obj("Lupu_Hangers", hang, col, steel)
    uv.box_uv(ho)
    # deck slab
    deck = lmlib.box((0.0, 0.0, -1.2), (LU_WIDTH, LU_SPAN + 200.0, 2.4))
    do = lmlib.obj("Lupu_Deck", deck, col, steel)
    uv.box_uv(do)
    sign = lmlib.text_mesh("LED_Lupu_Sign", "卢浦大桥", 6.0, FONT, col, extrude=0.25)
    sign.location = (0.0, -LU_SPAN * 0.18, LU_RISE * 0.72)
    sign.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    sign.data.materials.append(sign_mat)


def main():
    common.reset()
    lmenv.ensure_textures()
    mats = lmmat.bridge_materials()
    concrete = mats["nanpu_concrete"]
    cable = mats["nanpu_cable"]
    sign_red = mats["sign_red"]
    back = mats["sign_back"]
    deck_led = mats["nanpu_deck_led"]
    steel_w = mats["lupu_steel"]
    rainbows = mats["rainbow_bands"]
    lupu_sign = mats["lupu_sign"]
    wb_steel = mats["waibaidu_steel"]
    wb_granite = mats["waibaidu_granite"]
    timber = mats["timber"]
    wb_led = mats["waibaidu_led"]

    col = common.collection("NanpuBridge")
    build_nanpu(col, concrete, cable, sign_red, back, deck_led, mats["collider"],
                mats["nanpu_wash"], mats["nanpu_wash_dim"], mats["nanpu_under"],
                mats["nanpu_avia"])
    lmlib.finish("nanpu_bridge", col)

    col = common.collection("LupuBridge")
    build_lupu(col, steel_w, rainbows, lupu_sign)
    lmlib.finish("lupu_bridge_far", col)

    col = common.collection("WaibaiduBridge")
    build_waibaidu.build_waibaidu(col, wb_steel, wb_granite, timber, wb_led, mats["collider"])
    lmlib.finish("waibaidu_bridge", col)


if __name__ == "__main__":
    main()
