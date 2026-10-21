"""Barriers, breakers and construction props for the SKYRUSH props unit.

Dossier §7.1 (crash cushions), gameplay dossier §3.4 (pursuit breakers: gas
canopy, scaffolding, billboard on poles) and §5.7 (the spike strip a police
drone drops).

The spike strip ships a glTF animation called `Deploy`: the spike lattice folds
up out of its case over 0.6 s.
"""
import math

import bmesh
import bpy

from . import kit, materials as M

GALV = "galv"
DARK = "steel_dark"
ALU = "alu"
FOLD = 0.030           # the height of the concertina fold of the spike strip


def cone():
    """A 0.75 m traffic cone with a reflective band."""
    p = kit.Prop("Cone")
    p.box("Base", (0.0, 0.0, 0.025), (0.36, 0.36, 0.05), M.surface(), bevel=0.015,
          surface="orange")
    p.cyl("Cone", (0.0, 0.0, 0.36), 0.16, 0.68, M.surface(), segments=12, r2=0.045,
          surface="orange")
    p.cyl("Band", (0.0, 0.0, 0.44), 0.115, 0.10, M.surface(), segments=12,
          surface="white_paint")
    p.cyl("Tip", (0.0, 0.0, 0.71), 0.045, 0.06, M.surface(), segments=10, r2=0.02,
          surface="orange")
    return p.finalize("Cone")


def crash_barrier():
    """A segmented yellow crash cushion for an island nose (dossier §7.1).

    Three segments with black 45 degree stripes, a reflective chevron on the
    face that meets the traffic and bolted end plates.
    """
    p = kit.Prop("CrashBarrier")
    w, h, d = 2.00, 0.85, 0.90
    segs = 3
    step = w / segs
    for i in range(segs):
        x = -w * 0.5 + (i + 0.5) * step
        p.box("Seg%d" % i, (x, 0.0, h * 0.5), (step - 0.04, d, h), M.surface(),
              bevel=0.04, surface="yellow")
    # the black 45 degree stripes on both long faces
    for sy in (-1, 1):
        for i in range(2):
            x = -w * 0.5 + (i + 0.5) * w / 2.0
            p.box("Stripe%d%d" % (sy, i), (x, sy * (d * 0.5 + 0.015), h * 0.5),
                  (0.75, 0.03, 0.20), M.surface(), surface="cast_iron",
                  rot=(0.0, sy * math.pi / 4.0, 0.0))
    # the end plates and their bolts
    for sx in (-1, 1):
        p.box("EndPlate%d" % sx, (sx * (w * 0.5 + 0.03), 0.0, h * 0.5),
              (0.06, d + 0.04, h), M.surface(), surface="cast_iron")
        for sy in (-1, 1):
            p.cyl("Bolt%d%d" % (sx, sy), (sx * (w * 0.5 + 0.06), sy * 0.28, h * 0.5),
                  0.03, 0.10, M.surface(), axis="X", segments=6, surface=GALV)
    # the reflective chevron on the face that meets the traffic
    for sy in (-1, 1):
        p.box("Chevron%d" % sy, (-w * 0.5 - 0.05, sy * 0.20, h * 0.42),
              (0.03, 0.60, 0.14), M.surface(), surface="white_plastic",
              rot=(sy * 0.72, 0.0, 0.0))
    p.box("Base", (0.0, 0.0, 0.05), (w + 0.10, d + 0.10, 0.10), M.surface(),
          surface=GALV)
    for sx in (-0.55, 0.55):
        p.cyl("Reflector%d" % int(sx > 0), (sx, -d * 0.5 - 0.02, h * 0.72), 0.07, 0.04,
              M.surface(), axis="Y", segments=10, surface="red_paint")
    return p.finalize("CrashBarrier")


def crowd_barrier():
    """A 2 m pedestrian crowd-control railing."""
    p = kit.Prop("CrowdBarrier")
    p.tube("Top", (-1.0, 0.0, 1.05), (1.0, 0.0, 1.05), 0.028, M.surface(), segments=6,
           surface=GALV)
    p.tube("Mid", (-1.0, 0.0, 0.60), (1.0, 0.0, 0.60), 0.022, M.surface(), segments=6,
           surface=GALV)
    p.tube("Low", (-1.0, 0.0, 0.20), (1.0, 0.0, 0.20), 0.022, M.surface(), segments=6,
           surface=GALV)
    for i in range(7):
        x = -1.0 + i * (2.0 / 6.0)
        p.tube("Bar%d" % i, (x, 0.0, 0.14), (x, 0.0, 1.05), 0.018, M.surface(), segments=5,
               surface=GALV)
    for sx in (-0.94, 0.94):
        p.tube("Leg", (sx, 0.0, 1.05), (sx, 0.0, 0.02), 0.026, M.surface(), segments=6,
               surface=GALV)
        p.box("Foot", (sx, 0.0, 0.02), (0.10, 0.60, 0.04), M.surface(), bevel=0.01,
              surface=GALV)
    return p.finalize("CrowdBarrier")


def roadblock_barrier():
    """A heavy police roadblock barrier: red/white stripes, warning lamp on top."""
    p = kit.Prop("RoadblockBarrier")
    w, h = 2.50, 1.05
    p.box("Panel", (0.0, 0.0, h * 0.5), (w, 0.10, h * 0.62), M.surface(), surface="white_paint")
    for i in range(6):
        x = -w * 0.5 + (i + 0.5) * w / 6.0
        p.box("Stripe%d" % i, (x, -0.055, h * 0.5), (w / 12.0, 0.04, h * 0.60),
              M.surface(), surface="red_paint")
    p.tube("LegL", (-w * 0.42, 0.0, h * 0.42), (-w * 0.36, 0.0, 0.02), 0.035, M.surface(),
           segments=6, surface=GALV)
    p.tube("LegR", (w * 0.42, 0.0, h * 0.42), (w * 0.36, 0.0, 0.02), 0.035, M.surface(),
           segments=6, surface=GALV)
    p.tube("BraceL", (-w * 0.42, 0.0, h * 0.42), (-w * 0.36, 0.45, 0.02), 0.028,
           M.surface(), segments=6, surface=GALV)
    p.tube("BraceR", (w * 0.42, 0.0, h * 0.42), (w * 0.36, 0.45, 0.02), 0.028,
           M.surface(), segments=6, surface=GALV)
    p.box("FootL", (-w * 0.36, 0.22, 0.03), (0.30, 0.90, 0.06), M.surface(),
          surface=GALV)
    p.box("FootR", (w * 0.36, 0.22, 0.03), (0.30, 0.90, 0.06), M.surface(), surface=GALV)
    p.cyl("LampBase", (0.0, 0.0, h * 0.80), 0.07, 0.08, M.surface(), segments=10,
          surface=DARK)
    p.cyl("Lamp", (0.0, 0.0, h * 0.86), 0.075, 0.10, M.surface(), segments=10, r2=0.05,
          surface="yellow")
    p.empty("Light", (0.0, 0.0, h * 0.92), direction=(0.0, 0.0, -1.0), size=0.25)
    return p.finalize("RoadblockBarrier")


def spike_strip():
    """A police drone spike strip: a 4 m case with a folding spike lattice.

    The `Spikes` node carries the glTF animation `Deploy` (0.6 s): the lattice
    hinges up out of the case.
    """
    p = kit.Prop("SpikeStrip")
    length = 4.00
    p.box("Case", (0.0, 0.0, 0.07), (0.30, length, 0.14), M.surface(), bevel=0.02,
          surface=DARK)
    p.box("Lid", (0.0, 0.0, 0.145), (0.26, length - 0.04, 0.02), M.surface(),
          bevel=0.005, surface=ALU)
    for sy in (-length * 0.5 + 0.2, length * 0.5 - 0.2):
        p.box("Mount", (0.0, sy, 0.02), (0.36, 0.14, 0.04), M.surface(), surface=GALV)

    # The folding lattice: four concertina panels, each hinged on the next, so
    # the strip reads as an accordion that unrolls out of the case.  The node
    # origin is the hinge, and the police unit scales the node along its
    # length to deploy it (game/ai/police/police_spike_strip.gd).
    bm = bmesh.new()
    panels = 4
    panel_len = (length - 0.20) / panels
    for k in range(panels):
        y0 = 0.10 + k * panel_len
        z0 = 0.0 if k % 2 == 0 else FOLD
        z1 = FOLD if k % 2 == 0 else 0.0
        for sx in (-0.10, 0.10):
            kit.tube(bm, (sx, y0, z0), (sx, y0 + panel_len, z1), 0.014, segments=5,
                     cap=False)
        for j in range(3):
            y = y0 + (j + 0.5) * panel_len / 3.0
            z = z0 + (z1 - z0) * (j + 0.5) / 3.0
            kit.tube(bm, (-0.10, y, z), (0.10, y, z), 0.010, segments=4, cap=False)
        for j in range(8):
            y = y0 + (j + 0.5) * panel_len / 8.0
            z = z0 + (z1 - z0) * (j + 0.5) / 8.0
            for sx in (-0.10, 0.10):
                kit.cone(bm, (sx, y, z + 0.028), 0.014, 0.003, 0.048, segments=5)
    spikes = p.mesh("Spikes", bm, M.surface(), loc=(0.0, -length * 0.5, 0.10),
                     surface=ALU, box_map=True)
    _animate_deploy(spikes)
    p.quad("Label", 0.30, 0.08, M.sign(), (0.0, -0.152, 0.07), board="spike_label")
    return p.finalize("SpikeStrip")


def _animate_deploy(obj, frames=18):
    """Key the lattice so the glTF exporter writes the `Deploy` animation.

    18 frames at 30 fps = 0.6 s: the concertina unrolls out of its case along
    its length.  The police unit drives the same motion at runtime (it scales
    the `Spikes` node, game/ai/police/police_spike_strip.gd).
    """
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = frames
    scene.render.fps = 30
    for frame, scale in ((1, 0.02), (frames, 1.0)):
        obj.scale = (1.0, scale, 1.0)
        obj.keyframe_insert("scale", frame=frame)
    if obj.animation_data and obj.animation_data.action:
        obj.animation_data.action.name = "Deploy"
    scene.frame_set(1)


def billboard_pole():
    """An 8 x 4 m LED billboard on two poles (pursuit breaker).

    The two supports are named `Support_1` and `Support_2` so the world unit can
    drop the board when they are hit (gameplay dossier §3.4).
    """
    p = kit.Prop("BillboardPole")
    w, h, z = 8.00, 4.00, 6.00
    for i, sx in enumerate((-w * 0.34, w * 0.34)):
        p.cyl("Support_%d" % (i + 1), (sx, 0.0, z * 0.5), 0.20, z, M.surface(),
              segments=12, r2=0.16, surface=GALV)
        p.box("SupportFoot_%d" % (i + 1), (sx, 0.0, 0.16), (0.70, 0.70, 0.32), M.surface(),
              surface="concrete")
    p.box("Frame", (0.0, 0.0, z), (w + 0.30, 0.30, h + 0.30), M.surface(), bevel=0.04,
          surface=DARK)
    p.quad("Face", w, h, M.sign_lit(), (0.0, -0.16, z), board="billboard_ad")
    p.box("Hood", (0.0, -0.34, z + h * 0.5 + 0.20), (w + 0.30, 0.60, 0.10), M.surface(),
          bevel=0.02, surface=DARK)
    for i in range(3):
        p.cyl("Lamp%d" % i, (-2.0 + i * 2.0, -0.30, z + h * 0.5 + 0.30), 0.14, 0.10,
              M.surface(), segments=10, r2=0.16, surface=ALU)
    p.tube("Cable", (-w * 0.34, 0.10, z - 0.4), (w * 0.34, 0.10, z - 0.4), 0.03,
           M.surface(), segments=6, surface=DARK)
    return p.finalize("BillboardPole")


def scaffold():
    """A 6 x 4 x 8 m tube-and-board scaffold (pursuit breaker)."""
    p = kit.Prop("Scaffold")
    w, d, h = 6.0, 4.0, 8.0
    for sx in (-w / 2, 0.0, w / 2):
        for sy in (-d / 2, d / 2):
            p.cyl("Standard", (sx, sy, h * 0.5), 0.024, h, M.surface(), segments=6,
                  surface=GALV)
    for level in range(1, 4):
        z = level * (h / 4.0)
        for sy in (-d / 2, d / 2):
            p.tube("Ledger%d" % level, (-w / 2, sy, z), (w / 2, sy, z), 0.022, M.surface(),
                   segments=6, surface=GALV)
        for sx in (-w / 2, 0.0, w / 2):
            p.tube("Transom%d" % level, (sx, -d / 2, z), (sx, d / 2, z), 0.022, M.surface(),
                   segments=6, surface=GALV)
    for level in range(1, 4):
        z = level * (h / 4.0)
        for i in range(3):
            y = -d / 2 + 0.5 + i * 1.5
            p.box("Plank%d_%d" % (level, i), (0.0, y, z + 0.05), (w, 0.45, 0.05), M.surface(),
                  bevel=0.01, surface="white_plastic")
    p.tube("Brace", (-w / 2, -d / 2, 0.2), (w / 2, -d / 2, h / 2), 0.024, M.surface(),
           segments=6, surface=GALV)
    p.box("ToeBoard", (0.0, -d / 2 + 0.03, h / 4.0 + 0.20), (w, 0.04, 0.30), M.surface(),
          surface="white_plastic")
    p.box("Netting", (0.0, -d / 2 - 0.02, h * 0.62), (w, 0.02, h * 0.72), M.surface(),
          surface="plastic")
    p.box("Debris", (0.0, 0.0, 0.12), (1.6, 1.2, 0.24), M.surface(), bevel=0.03,
          surface="concrete")
    return p.finalize("Scaffold")


BUILDERS = {
    "cone": cone,
    "crash_barrier": crash_barrier,
    "crowd_barrier": crowd_barrier,
    "roadblock_barrier": roadblock_barrier,
    "spike_strip": spike_strip,
    "billboard_pole": billboard_pole,
    "scaffold": scaffold,
}
