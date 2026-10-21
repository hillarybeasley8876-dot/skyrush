"""Street lamps for the SKYRUSH props unit.

Dossier §2.4 (deck lamps 11 m, 2.5 m arms, 32 m spacing, LED 4000 K) and §9
(street lamp, Bund heritage lamp, magnolia lamp 玉兰灯, shikumen wall bracket).

Every lamp head is an opal diffuser (E2-3, 3000-4000 K) rather than a bare
emissive disc, so it reads as a shade at 10 m and as a soft bloom at 40 m.
"""
import math

import bmesh
from mathutils import Vector

from . import kit, materials as M

GALV = "galv"
ALU = "alu"


def _pole(p, name, height, r_base=0.11, r_top=0.07, surface=GALV):
    """Tapered galvanised pole with a base flange."""
    p.cyl(name, (0.0, 0.0, height * 0.5), r_base, height, M.surface(),
          segments=12, r2=r_top, surface=surface)
    p.cyl(name + "_Base", (0.0, 0.0, 0.12), r_base * 2.1, 0.24, M.surface(),
          segments=12, surface=surface)
    p.cyl(name + "_Collar", (0.0, 0.0, 0.30), r_base * 1.25, 0.12, M.surface(),
          segments=12, surface=surface)


def _arm(p, name, top_z, reach, rise, r=0.055, surface=GALV):
    """A curved arm: a diagonal stay plus a horizontal tip."""
    p.tube(name + "_Stay", (0.0, 0.0, top_z), (reach * 0.42, 0.0, top_z + rise),
           r * 1.15, M.surface(), segments=8, surface=surface)
    p.tube(name + "_Tip", (reach * 0.42, 0.0, top_z + rise), (reach, 0.0, top_z + rise),
           r, M.surface(), segments=8, surface=surface)


def _head(p, name, pos, length=0.9, width=0.34, drop=0.16, surface=ALU):
    """A luminaire head: metal housing with an opal diffuser underneath."""
    p.box(name + "_Housing", pos, (length, width, 0.16), M.surface(), bevel=0.03,
          surface=surface)
    p.quad(name + "_Lens", length * 0.92, width * 0.80, M.opal(),
           (pos[0], pos[1], pos[2] - drop * 0.5 - 0.081))


# The magnolia shade profile: (radius, z) in metres, revolved around Z.
# It is a cup that opens UPWARD, with a rim that curls back a little.
SHADE_PROFILE = ((0.05, 0.0), (0.12, 0.06), (0.21, 0.17), (0.29, 0.29),
                 (0.325, 0.36), (0.30, 0.40))


def _shade(bm, profile, segments=20, lobes=5, lobe=0.09):
    """Revolve a profile into a shade whose rim is scalloped (a 5-lobe cup)."""
    rows = []
    zmax = profile[-1][1] or 1.0
    for r, z in profile:
        row = []
        for i in range(segments):
            a = math.tau * i / segments
            rr = r * (1.0 + lobe * math.cos(lobes * a) * (z / zmax))
            row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), z)))
        rows.append(row)
    for lo, hi in zip(rows, rows[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def _petal(p, name, pos, tilt=0.0, scale=1.0):
    """One magnolia shade: an opal cup on a dark cast socket."""
    bm = bmesh.new()
    _shade(bm, [(r * scale, z * scale) for r, z in SHADE_PROFILE])
    p.mesh(name, bm, M.opal(), loc=pos, rot=(tilt, 0.0, 0.0), smooth=True, uv_unit=True)
    # the dark cast cup the shade sits in
    bm = bmesh.new()
    kit.cone(bm, (0.0, 0.0, 0.0), 0.10 * scale, 0.15 * scale, 0.13 * scale, segments=12)
    p.mesh(name + "_Socket", bm, M.surface(), loc=(pos[0], pos[1], pos[2] - 0.10 * scale),
           smooth=True, surface="cast_iron")


def _curved_arm(p, name, top, tip, r, mid_lift=0.22):
    """A curved lamp arm: an elbow that rises and then reaches out."""
    top = Vector(top)
    tip = Vector(tip)
    mid = top.lerp(tip, 0.55) + Vector((0.0, 0.0, mid_lift))
    p.tube(name + "_A", top, mid, r, M.surface(), segments=8, surface=ALU)
    p.tube(name + "_B", mid, tip, r, M.surface(), segments=8, surface=ALU)


def lamp_deck_double():
    """Median double-arm lamp, 11 m, arms 2.5 m (dossier §2.4)."""
    p = kit.Prop("LampDeckDouble")
    _pole(p, "Pole", 11.0, 0.12, 0.075)
    for i, side in ((1, 1), (2, -1)):
        _arm(p, "Arm%d" % i, 10.4, 2.5 * side, 0.45)
        _head(p, "Head%d" % i, (2.5 * side, 0.0, 10.85), length=1.0, width=0.36)
    p.empty("Light_1", (2.5, 0.0, 10.7), direction=(0.0, 0.0, -1.0), size=0.4)
    p.empty("Light_2", (-2.5, 0.0, 10.7), direction=(0.0, 0.0, -1.0), size=0.4)
    return p.finalize("LampDeckDouble")


def lamp_street():
    """Standard 11 m street lamp with a single 2 m arm (dossier §9)."""
    p = kit.Prop("LampStreet")
    _pole(p, "Pole", 11.0, 0.115, 0.07)
    _arm(p, "Arm", 10.4, 2.0, 0.40)
    _head(p, "Head", (2.0, 0.0, 10.8), length=0.85, width=0.30)
    p.empty("Light", (2.0, 0.0, 10.65), direction=(0.0, 0.0, -1.0), size=0.4)
    return p.finalize("LampStreet")


def lamp_magnolia():
    """玉兰灯: 9 m pole, 9 cup shades (1 top + 8 around) on curved arms."""
    p = kit.Prop("LampMagnolia")
    _pole(p, "Pole", 9.0, 0.13, 0.08)
    ring_r = 1.15
    for i in range(8):
        a = math.tau * i / 8.0
        x, y = ring_r * math.cos(a), ring_r * math.sin(a)
        _curved_arm(p, "PetalArm%d" % (i + 1), (0.0, 0.0, 6.45), (x, y, 6.95), 0.05)
        _petal(p, "Petal_%d" % (i + 1), (x, y, 6.95), tilt=math.radians(9.0))
    p.tube("PetalArmTop", (0.0, 0.0, 8.05), (0.0, 0.0, 8.45), 0.05, M.surface(),
           segments=8, surface=ALU)
    _petal(p, "Petal_Top", (0.0, 0.0, 8.45), scale=1.12)
    p.empty("Light", (0.0, 0.0, 7.1), direction=(0.0, 0.0, -1.0), size=0.5)
    return p.finalize("LampMagnolia")


def _lantern(p, name, pos, glass_mat):
    """A cast-iron lantern head: tapered cage, glowing core, finial."""
    p.cyl(name + "_Cage", pos, 0.19, 0.42, M.surface(), segments=8, r2=0.25,
          surface="cast_iron")
    p.cyl(name + "_Core", (pos[0], pos[1], pos[2] - 0.10), 0.15, 0.30, glass_mat,
          segments=8)
    p.cyl(name + "_Cap", (pos[0], pos[1], pos[2] + 0.30), 0.26, 0.10, M.surface(),
          segments=8, surface="cast_iron")
    p.cyl(name + "_Finial", (pos[0], pos[1], pos[2] + 0.40), 0.05, 0.14, M.surface(),
          segments=6, r2=0.01, surface="cast_iron")
    for i in range(4):
        a = math.pi * 0.25 + math.pi * 0.5 * i
        p.tube(name + "_Bar%d" % i, (pos[0] + 0.22 * math.cos(a), pos[1] + 0.22 * math.sin(a),
                                     pos[2] + 0.22),
               (pos[0] + 0.16 * math.cos(a), pos[1] + 0.16 * math.sin(a), pos[2] - 0.26),
               0.018, M.surface(), segments=5, surface="cast_iron")


def lamp_heritage():
    """Bund heritage lamp: black cast-iron post 4.5 m, two arms, 0.5 m glass lanterns."""
    p = kit.Prop("LampHeritage")
    iron = "cast_iron"
    p.cyl("Post", (0.0, 0.0, 2.25), 0.09, 4.5, M.surface(), segments=12, r2=0.065,
          surface=iron)
    p.cyl("Base", (0.0, 0.0, 0.22), 0.22, 0.44, M.surface(), segments=12, r2=0.14,
          surface=iron)
    p.cyl("Base2", (0.0, 0.0, 0.55), 0.12, 0.30, M.surface(), segments=12, r2=0.085,
          surface=iron)
    p.cyl("Collar", (0.0, 0.0, 3.60), 0.11, 0.10, M.surface(), segments=12, surface=iron)
    warm = M.opal()
    for i, side in ((1, 1), (2, -1)):
        p.tube("Arm%d" % i, (0.0, 0.0, 3.62), (0.52 * side, 0.0, 4.02), 0.035,
               M.surface(), segments=8, surface=iron)
        p.tube("Arm%d_Stay" % i, (0.0, 0.0, 3.20), (0.30 * side, 0.0, 3.85), 0.025,
               M.surface(), segments=6, surface=iron)
        _lantern(p, "Lantern%d" % i, (0.58 * side, 0.0, 3.92), warm)
    p.empty("Light", (0.0, 0.0, 3.70), direction=(0.0, 0.0, -1.0), size=0.3)
    return p.finalize("LampHeritage")


def lamp_shikumen():
    """Shikumen wall bracket: a wrought-iron arm off the facade with a small lantern."""
    p = kit.Prop("LampShikumen")
    iron = "cast_iron"
    p.box("WallPlate", (0.0, 0.10, 2.85), (0.26, 0.06, 0.44), M.surface(), bevel=0.01,
          surface=iron)
    p.tube("Stay", (0.0, 0.08, 2.45), (0.0, -0.62, 2.98), 0.026, M.surface(), segments=6,
           surface=iron)
    p.tube("Arm", (0.0, 0.08, 3.00), (0.0, -0.72, 3.00), 0.032, M.surface(), segments=8,
           surface=iron)
    _lantern(p, "Lantern", (0.0, -0.78, 2.80), M.opal())
    p.empty("Light", (0.0, -0.78, 2.58), direction=(0.0, 0.0, -1.0), size=0.25)
    return p.finalize("LampShikumen")


BUILDERS = {
    "lamp_deck_double": lamp_deck_double,
    "lamp_street": lamp_street,
    "lamp_magnolia": lamp_magnolia,
    "lamp_heritage": lamp_heritage,
    "lamp_shikumen": lamp_shikumen,
}
