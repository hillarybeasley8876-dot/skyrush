"""Jin Mao (金茂大厦, 420.5 m) and SWFC (环球金融中心, 492 m) - Lujiazui super-tall duo.

Geometry per ref/shanghai/SHANGHAI_DOSSIER.md 6.2: Jin Mao is 13 octagonal
tiers stepping in like a pagoda with 1.5 m aluminium mullions and a gold
emissive line on every setback; SWFC is a square prism cut by two sweeping arcs
narrowing to a blade, with an inverted-trapezoid aperture at 440-472 m.
"""
import math
import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender/landmarks"))
import lmenv  # noqa: E402
from lmenv import bpy, common, geo, lmlib, lmmat, mats, uv  # noqa: E402

JM_TIERS = [64, 56, 49, 42, 35, 28, 21, 17, 14, 11, 8, 6, 4]   # = 355 m
JM_HALF0 = 27.0          # across-flats 54 m
JM_STEP = 1.25           # half-width shrinks 1.25 m per tier (2.5 m across)
JM_SPIRE = 65.5          # 355 -> 420.5

SWF_HALF = 29.0          # square 58 m
SWF_H = 492.0
SWF_AP_Y0, SWF_AP_Y1 = 440.0, 472.0
SWF_AP_W0, SWF_AP_W1 = 15.0, 25.0    # half width of the slot


def faces_of(plan):
    """(mid, normal, tangent, length) for every edge of a closed plan polygon."""
    out = []
    n = len(plan)
    for i in range(n):
        a, b = plan[i], plan[(i + 1) % n]
        mx, my = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy)
        out.append(((mx, my), (dy / ln, -dx / ln), (dx / ln, dy / ln), ln))
    return out


def _lattice_ring(radius, z0, taper, height, sides=8):
    """One open lattice ring: a bottom chord, leaning posts and diagonals.

    The Jin Mao spire is a stack of these, not a solid cone."""
    bm = lmlib.merge()
    r1 = radius - taper
    for k in range(sides):
        a0 = 2.0 * math.pi * k / sides
        a1 = 2.0 * math.pi * (k + 1) / sides
        b0 = (radius * math.cos(a0), radius * math.sin(a0), z0)
        b1 = (radius * math.cos(a1), radius * math.sin(a1), z0)
        t0 = (r1 * math.cos(a0), r1 * math.sin(a0), z0 + height)
        t1 = (r1 * math.cos(a1), r1 * math.sin(a1), z0 + height)
        bm = lmlib.merge(bm, lmlib.strut(b0, b1, 0.30, 0.30))     # bottom chord
        bm = lmlib.merge(bm, lmlib.strut(b0, t0, 0.20, 0.20))     # leaning post
        bm = lmlib.merge(bm, lmlib.strut(b0, t1, 0.14, 0.14))     # diagonal
        bm = lmlib.merge(bm, lmlib.strut(t0, t1, 0.26, 0.26))     # top chord
    return bm


def build_jinmao(col, glass, fin_mat, gold, crown_mat, crown_led, col_mat, avia):
    bm = lmlib.merge()
    fins = lmlib.merge()
    edges = lmlib.merge()
    colbm = lmlib.merge()
    z = 0.0
    for i, h in enumerate(JM_TIERS):
        half = JM_HALF0 - JM_STEP * i
        plan = lmlib.octagon(half)
        bm = lmlib.merge(bm, lmlib.loft_plans([plan, plan], [z, z + h], cap_start=True,
                                               cap_end=True))
        # the stepped silhouette, as a simple collision hull
        colbm = lmlib.merge(colbm, lmlib.loft_plans([plan, plan], [z, z + h]))
        # cornice at the setback
        cor = lmlib.octagon(half + 0.9)
        bm = lmlib.merge(bm, lmlib.loft_plans([cor, cor], [z + h - 1.4, z + h], cap_start=True,
                                               cap_end=True))
        # gold emissive line on the setback
        edges = lmlib.merge(edges, lmlib.loft_plans(
            [lmlib.octagon(half + 1.05), lmlib.octagon(half + 1.05)],
            [z + h - 3.2, z + h], cap_start=True, cap_end=True))
        # vertical aluminium mullions, 1.5 m apart
        for (mid, nrm, tan, ln) in faces_of(plan):
            count = max(2, int(ln / 1.5))
            for k in range(count):
                t = (k + 0.5) / count - 0.5
                fx = mid[0] + tan[0] * t * ln + nrm[0] * 0.16
                fy = mid[1] + tan[1] * t * ln + nrm[1] * 0.16
                fins = lmlib.merge(fins, lmlib.box(
                    (fx, fy, z + h * 0.5), (0.34, 0.22, h),
                    rot_z=math.atan2(nrm[1], nrm[0])))
        z += h
    body = lmlib.obj("JinMao_Body", bm, col, glass)
    uv.box_uv(body)
    fo = lmlib.obj("JinMao_Fins", fins, col, fin_mat)
    uv.box_uv(fo)
    eo = lmlib.obj("LED_JinMao_Edges", edges, col, gold)
    uv.box_uv(eo)
    # crown: stacked octagonal LATTICE rings (355 -> 377 m) + a slim lattice
    # mast, the way the real Jin Mao spire is built (no solid cone). The
    # lattice glows gold-white (ART.md 11) - a grey metal spire reads as a
    # dead pylon from 1.3 km.
    crown = lmlib.merge()
    cz = z
    rings = 5
    for i in range(rings):
        r0 = 12.0 - i * 1.55
        y0 = cz + i * 4.4
        crown = lmlib.merge(crown, _lattice_ring(r0, y0, 1.55, 4.4))
    # the lattice mast above the rings
    for i in range(4):
        y0 = cz + rings * 4.4 + i * 6.0
        crown = lmlib.merge(crown, _lattice_ring(4.25 - i * 0.85, y0, 0.85, 6.0, sides=4))
    # a solid lit band at the top of the crown: from 1.3 km the crown has to
    # be a SURFACE, not a wire (r3 review)
    crown = lmlib.merge(crown, lmlib.lathe(
        [(12.6, cz + rings * 4.4 - 2.0), (13.4, cz + rings * 4.4 - 2.0),
         (13.4, cz + rings * 4.4 + 1.5), (12.6, cz + rings * 4.4 + 1.5)], 24,
        cap_bottom=False, cap_top=False))
    co = lmlib.obj("JinMao_Crown", crown, col, crown_led)
    uv.box_uv(co)
    mast = lmlib.lathe(
        [(0.0, cz + rings * 4.4 + 24.0), (1.2, cz + rings * 4.4 + 24.0),
         (0.6, cz + rings * 4.4 + 45.0), (0.25, 420.5)], 10)
    mo = lmlib.obj("JinMao_Mast", mast, col, crown_mat)
    uv.box_uv(mo)
    # collision hull: the stepped silhouette plus the crown
    colbm = lmlib.merge(colbm, lmlib.loft_plans(
        [lmlib.octagon(12.0), lmlib.octagon(4.25)], [cz, cz + 22.0], cap_start=False))
    colbm = lmlib.merge(colbm, lmlib.lathe(
        [(0.0, cz + 22.0), (4.25, cz + 22.0), (1.2, cz + 46.0), (0.25, 420.5)], 8))
    cco = lmlib.obj("JinMao_ColBody-colonly", colbm, col, col_mat)
    uv.box_uv(cco)
    lmlib.empty("Aviation_JinMao", (0.0, 0.0, 420.5), direction=(0.0, 0.0, 1.0), col=col, size=4.0)
    lmlib.aviation_beacon(col, "LED_Aviation_JinMao", 0.0, 0.0, 420.5, avia)
    # crown floods: wash the upper tiers (E3-E4) so the tower reads from 1.3 km
    for k in range(3):
        a = 2.0 * math.pi * k / 3
        lmlib.empty("Flood_Crown_%d" % (k + 1),
                    (26.0 * math.cos(a), 26.0 * math.sin(a), 372.0),
                    direction=(-0.42 * math.cos(a), -0.42 * math.sin(a), -0.9),
                    col=col, size=4.0)
    return body


def swf_ax(y):
    """Half thickness of the SWFC in the blade direction (sweeping arc)."""
    t = min(max(y / SWF_H, 0.0), 1.0)
    return 6.0 + 23.0 * (1.0 - t) ** 1.1


def swf_az(y):
    """Half width of the SWFC across the aperture direction."""
    if y <= 455.0:
        return SWF_HALF
    t = (y - 455.0) / (SWF_H - 455.0)
    return SWF_HALF - 4.0 * t ** 1.3


def swf_plan(y, chamfer=1.6):
    ax, az = swf_ax(y), swf_az(y)
    cx, cy = max(0.0, ax - chamfer), max(0.0, az - chamfer)
    return [(-cx, -az), (cx, -az), (ax, -cy), (ax, cy), (cx, az), (-cx, az),
            (-ax, cy), (-ax, -cy)]


def swf_sections(ys):
    return [swf_plan(y) for y in ys]


def build_swfc(col, glass, edge_mat, beam_mat, col_mat, avia):
    ys = [SWF_H * i / 48.0 for i in range(49)]
    ys += [SWF_AP_Y0, SWF_AP_Y1, 455.0, 460.0, 470.0, 480.0, SWF_H]
    ys = sorted(set(round(y, 3) for y in ys))
    lower = [y for y in ys if y <= SWF_AP_Y0]
    band = [y for y in ys if SWF_AP_Y0 <= y <= SWF_AP_Y1]
    upper = [y for y in ys if y >= SWF_AP_Y1]
    bm = lmlib.merge()
    # lower shaft 0 -> 440
    bm = lmlib.merge(bm, lmlib.loft_plans(swf_sections(lower), lower, cap_start=True,
                                           cap_end=True))
    # aperture band 440 -> 472: two side walls, slot widens 30 -> 50 m
    walls = lmlib.merge()
    steps = 6
    h0 = (SWF_AP_Y1 - SWF_AP_Y0) / steps
    for i in range(steps):
        ya = SWF_AP_Y0 + i * h0
        yb = ya + h0
        sa0 = SWF_AP_W0 + (SWF_AP_W1 - SWF_AP_W0) * i / steps
        sb0 = SWF_AP_W0 + (SWF_AP_W1 - SWF_AP_W0) * (i + 1) / steps
        axa, aza = swf_ax(ya), swf_az(ya)
        axb, azb = swf_ax(yb), swf_az(yb)
        for sgn in (1.0, -1.0):
            sa, sb = sa0 * sgn, sb0 * sgn
            pts_a = [(-axa, sa), (axa, sa), (axa, aza), (-axa, aza)]
            pts_b = [(-axb, sb), (axb, sb), (axb, azb), (-axb, azb)]
            walls = lmlib.merge(walls, lmlib.loft_plans([pts_a, pts_b], [ya, yb]))
            # cap the two ends of the wall so the slot reads as a through opening
            for fx in (1.0, -1.0):
                cap_a = [(fx * axa, sa), (fx * axa, aza)]
                cap_b = [(fx * axb, sb), (fx * axb, azb)]
                walls = lmlib.merge(walls, lmlib.loft_plans([cap_a, cap_b], [ya, yb],
                                                             closed=False))
    bm = lmlib.merge(bm, walls)
    # top beam 472 -> 492
    bm = lmlib.merge(bm, lmlib.loft_plans(swf_sections(upper), upper, cap_start=True,
                                           cap_end=True))
    # 4-floor podium, 15.8 m (dossier 6.2)
    pod = lmlib.loft_plans([swf_plan(0.0, chamfer=2.0), swf_plan(0.0, chamfer=2.0)],
                           [0.0, 15.8], cap_start=True, cap_end=True)
    bm = lmlib.merge(bm, pod)
    body = lmlib.obj("SWFC_Body", bm, col, glass)
    uv.box_uv(body)
    # collision hull: the blade silhouette, simplified
    ch = [0.0, 120.0, 260.0, 380.0, SWF_AP_Y0, SWF_AP_Y1, SWF_H]
    colbm = lmlib.merge()
    for i in range(len(ch) - 1):
        colbm = lmlib.merge(colbm, lmlib.loft_plans(
            [swf_plan(ch[i]), swf_plan(ch[i + 1])], [ch[i], ch[i + 1]]))
    cco = lmlib.obj("SWFC_ColBody-colonly", colbm, col, col_mat)
    uv.box_uv(cco)
    # 100F skywalk beam inside the aperture
    sk = lmlib.box((0.0, 0.0, 474.0), (5.0, 52.0, 3.2))
    so = lmlib.obj("SWFC_Skywalk", sk, col, beam_mat)
    uv.box_uv(so)
    # white edge lines: the four corner arrises (lofted strips) + the aperture outline
    edges = lmlib.merge()
    for k in (2, 3, 6, 7):
        strips = []
        for y in ys:
            plan = swf_plan(y)
            px, py = plan[k]
            nxt = plan[(k + 1) % 8]
            prv = plan[(k - 1) % 8]
            tx = nxt[0] - prv[0]
            ty = nxt[1] - prv[1]
            ln = math.hypot(tx, ty) or 1.0
            tx, ty = tx / ln, ty / ln
            strips.append([(px - tx * 1.2, py - ty * 1.2), (px + tx * 1.2, py + ty * 1.2)])
        edges = lmlib.merge(edges, lmlib.loft_plans(strips, ys, closed=False))
    for (yy, sw) in ((SWF_AP_Y0, SWF_AP_W0), (SWF_AP_Y1, SWF_AP_W1)):
        ax = swf_ax(yy)
        edges = lmlib.merge(edges, lmlib.box((0.0, 0.0, yy), (2.0 * ax + 2.4, 2.0 * sw + 2.4, 2.4)))
    # the two sloped sides of the opening, outlined on both broad faces
    steps = 8
    for fx in (1.0, -1.0):
        for sgn in (1.0, -1.0):
            pts = []
            for i in range(steps + 1):
                yy = SWF_AP_Y0 + (SWF_AP_Y1 - SWF_AP_Y0) * i / steps
                sa = SWF_AP_W0 + (SWF_AP_W1 - SWF_AP_W0) * i / steps
                pts.append((fx * swf_ax(yy), sgn * sa, yy))
            for i in range(len(pts) - 1):
                edges = lmlib.merge(edges, lmlib.strut(pts[i], pts[i + 1], 2.4, 2.4))
    eo = lmlib.obj("LED_SWFC_Edges", edges, col, edge_mat)
    uv.box_uv(eo)
    lmlib.empty("Aviation_SWFC", (0.0, 0.0, SWF_H), direction=(0.0, 0.0, 1.0), col=col, size=4.0)
    lmlib.aviation_beacon(col, "LED_Aviation_SWFC", 0.0, 0.0, SWF_H, avia)
    for k in range(3):
        a = 2.0 * math.pi * k / 3 + 0.5
        lmlib.empty("Flood_Crown_%d" % (k + 1),
                    (30.0 * math.cos(a), 30.0 * math.sin(a), 486.0),
                    direction=(-0.4 * math.cos(a), -0.4 * math.sin(a), -0.9),
                    col=col, size=4.0)
    return body


def main():
    common.reset()
    lmenv.ensure_textures()
    jm_glass = lmmat.tex_mat("LM_JINMAO_Glass", diff="facade_night_diff.png",
                              emit="facade_night_emit.png", normal="facade_night_nor.png",
                              color=lmmat.hexcol("#3E4A52"), roughness=0.22, metallic=0.25,
                              tile=(0.16, 0.07), emit_strength=1.0)
    jm_fin = lmmat.tex_mat("LM_JINMAO_Fin", diff="metal_painted_diff.png",
                           normal="metal_painted_nor.png", rough="metal_painted_rough.png",
                           color=lmmat.hexcol("#B7BCC0"), roughness=0.34, metallic=0.85,
                           tile=(0.42, 0.42), normal_strength=0.8)
    jm_gold = lmmat.glow("LED_JinMao_Edge", lmmat.hexcol("#FFD27A"), strength=3.4)
    jm_crown_led = lmmat.glow("LED_JinMao_Crown", lmmat.hexcol("#FFE6A8"), strength=3.5)
    jm_crown = lmmat.tex_mat("LM_JINMAO_Crown", diff="metal_dark_diff.png",
                              normal="metal_dark_nor.png", rough="metal_dark_rough.png",
                              color=lmmat.hexcol("#8C9298"), roughness=0.42, metallic=0.9,
                              tile=(0.55, 0.55), normal_strength=0.9)
    swf_glass = lmmat.tex_mat("LM_SWFC_Glass", diff="glass_bands_diff.png",
                              emit="glass_bands_emit.png", normal="glass_bands_nor.png",
                              color=lmmat.hexcol("#5C7A8C"), roughness=0.08, metallic=0.5,
                              tile=(0.17, 0.26), emit_strength=1.2)
    swf_edge = lmmat.glow("LED_SWFC_Edge", lmmat.hexcol("#CFE6FF"), strength=3.5)
    swf_beam = lmmat.tex_mat("LM_SWFC_Beam", diff="metal_painted_diff.png",
                             normal="metal_painted_nor.png", rough="metal_painted_rough.png",
                             color=lmmat.hexcol("#C8CCD0"), roughness=0.35, metallic=0.7,
                             tile=(0.42, 0.42), normal_strength=0.8)

    col = common.collection("JinMao")
    col_mat = lmmat.tex_mat("LM_TOWER_Collider", color=(0.1, 0.1, 0.1), roughness=0.9)
    jm_avia = lmmat.glow("LED_Aviation_JinMao", lmmat.hexcol("#FF2A3A"), strength=8.0)
    build_jinmao(col, jm_glass, jm_fin, jm_gold, jm_crown, jm_crown_led, col_mat, jm_avia)
    lmlib.finish("jin_mao", col)

    col = common.collection("SWFC")
    swf_avia = lmmat.glow("LED_Aviation_SWFC", lmmat.hexcol("#FF2A3A"), strength=8.0)
    build_swfc(col, swf_glass, swf_edge, swf_beam, col_mat, swf_avia)
    lmlib.finish("swfc", col)


if __name__ == "__main__":
    main()
