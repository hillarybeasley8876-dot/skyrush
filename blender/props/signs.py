"""Traffic and signage props for the SKYRUSH props unit.

Dossier §2.6 (gantries, guide signs, VMS) and §9 (traffic lights, road-name
plates, bus stop).

Contracts: the traffic-light lenses are `Lens_R` / `Lens_A` / `Lens_G` (one node
per colour), the guide gantry carries `SignMount_<n>` markers per lane, and the
toll-style lane signals ship both states (`LaneSignal_<n>_Red` / `_Green`).
"""
import math

import bmesh

from . import kit, materials as M

GALV = "galv"
DARK = "steel_dark"
BLACK = "black"
HIVIS = "hi_vis"


# ------------------------------------------------------------------ traffic light
def traffic_light_mast():
    """A dark steel mast with a 7 m reach, a vertical 3-aspect head and a
    countdown box (PR-INT2 of the lead).

    The mast and the arm are galvanised steel (they catch the city glow and read
    silver-grey), the head is black `#111113` and
    the head carries the yellow reflective back plate every signal head has.
    The lenses are 300 mm, red on top, and ship DARK: the world unit switches
    them on (the lenses are the meshes `Lens_R` / `Lens_A` / `Lens_G`).
    """
    p = kit.Prop("TrafficLightMast")
    reach = 7.0
    arm_z = 6.40
    head_z = arm_z - 1.15
    # the concrete plinth with its galvanised base flange and four bolts
    p.cyl("Plinth", (0.0, 0.0, 0.125), 0.35, 0.25, M.surface(), segments=16,
          surface="concrete")
    p.cyl("BaseFlange", (0.0, 0.0, 0.265), 0.26, 0.03, M.surface(), segments=16,
          surface=GALV)
    for i in range(4):
        a = math.tau * i / 4.0 + math.pi / 4.0
        p.cyl("Bolt%d" % (i + 1), (0.21 * math.cos(a), 0.21 * math.sin(a), 0.295),
              0.018, 0.04, M.surface(), segments=6, surface=GALV)
    p.cyl("Mast", (0.0, 0.0, 3.45), 0.135, 6.35, M.surface(), segments=16, r2=0.105,
          surface=GALV)
    p.tube("Arm", (0.0, 0.0, arm_z), (0.0, reach, arm_z), 0.105, M.surface(),
           segments=12, surface=GALV)
    p.tube("Stay", (0.0, 0.0, arm_z - 1.30), (0.0, reach * 0.62, arm_z), 0.055,
           M.surface(), segments=8, surface=GALV)
    p.box("ArmCap", (0.0, reach, arm_z), (0.20, 0.24, 0.24), M.surface(), bevel=0.02,
          surface=BLACK)

    # vertical three-aspect head hanging under the arm end, red on top
    hy = reach
    p.box("HeadBody", (0.0, hy, head_z), (0.36, 0.32, 1.24), M.surface(), bevel=0.03,
          surface=BLACK)
    p.box("HeadHanger", (0.0, hy, arm_z - 0.30), (0.10, 0.10, 0.40), M.surface(),
          surface=BLACK)
    # the reflective back plate: a 60 mm yellow border around a black field
    p.box("BackPlate", (0.0, hy + 0.22, head_z), (0.60, 0.04, 1.40), M.surface(),
          surface=HIVIS)
    p.box("BackPlateField", (0.0, hy + 0.19, head_z), (0.48, 0.02, 1.28), M.surface(),
          surface=BLACK)
    for name, dz, kind in (("Lens_R", 0.42, "R"), ("Lens_A", 0.0, "A"),
                           ("Lens_G", -0.42, "G")):
        p.cyl(name, (0.0, hy - 0.17, head_z + dz), 0.15, 0.04, M.lens(kind), axis="Y",
              segments=20, uv_unit=True)
        p.box(name + "_Visor", (0.0, hy - 0.22, head_z + dz + 0.165), (0.34, 0.26, 0.03),
              M.surface(), surface=BLACK)
    # countdown box beside the head, facing across the carriageway
    p.box("CountdownBox", (0.47, hy, head_z + 0.05), (0.22, 0.62, 0.36), M.surface(),
          bevel=0.02, surface=BLACK)
    p.quad("CountdownFace", 0.52, 0.28, M.sign_lit(), (0.335, hy, head_z + 0.05),
           rot=(0.0, 0.0, -math.pi / 2.0), board="countdown_23")
    p.empty("Light", (0.0, reach * 0.5, arm_z - 1.4), direction=(0.0, 0.0, -1.0), size=0.4)
    return p.finalize("TrafficLightMast")


# ------------------------------------------------------------------ road name sign
def road_name_sign():
    """路名牌 on a 2.6 m stainless post (dossier §9)."""
    p = kit.Prop("RoadNameSign")
    p.cyl("Post", (0.0, 0.0, 1.30), 0.055, 2.60, M.surface(), segments=12, surface="alu")
    p.cyl("PostBase", (0.0, 0.0, 0.06), 0.11, 0.12, M.surface(), segments=12,
          surface="alu")
    p.box("Cap", (0.0, 0.0, 2.62), (0.13, 0.13, 0.08), M.surface(), surface="alu")
    p.box("Bracket", (0.0, 0.0, 2.28), (0.07, 0.07, 0.26), M.surface(), surface="alu")
    p.sign("SignFace", (0.0, -0.02, 2.28), 1.80, 0.60, M.sign(), M.surface(),
           board="roadname_xianggang", frame=0.05, depth=0.06, frame_surface="alu")
    return p.finalize("RoadNameSign")


# ------------------------------------------------------------------ guide gantry
def _truss(p, name, x0, x1, y, z, depth=0.9, width=0.9, panels=None):
    """A 0.9 x 0.9 m box truss between two points along X (dossier §2.6)."""
    r = 0.055
    hz, hw = depth * 0.5, width * 0.5
    for sz in (-hz, hz):
        for sy in (-hw, hw):
            p.tube("%s_Chord" % name, (x0, y + sy, z + sz), (x1, y + sy, z + sz), r,
                   M.surface(), segments=4, surface=GALV, cap=False)
    span = x1 - x0
    panels = panels or max(2, int(round(span / 6.0)))
    step = span / panels
    for i in range(panels + 1):
        x = x0 + i * step
        for sy in (-hw, hw):
            p.tube("%s_Vert%d" % (name, i), (x, y + sy, z - hz), (x, y + sy, z + hz),
                   r * 0.8, M.surface(), segments=4, surface=GALV, cap=False)
        p.tube("%s_Top%d" % (name, i), (x, y - hw, z + hz), (x, y + hw, z + hz), r * 0.8,
               M.surface(), segments=4, surface=GALV, cap=False)
    for i in range(panels):
        xa, xb = x0 + i * step, x0 + (i + 1) * step
        for sy in (-hw, hw):
            p.tube("%s_Diag%d" % (name, i), (xa, y + sy, z - hz), (xb, y + sy, z + hz),
                   r * 0.75, M.surface(), segments=4, surface=GALV, cap=False)
        p.tube("%s_DiagT%d" % (name, i), (xa, y - hw, z + hz), (xb, y + hw, z + hz), r * 0.7,
               M.surface(), segments=4, surface=GALV, cap=False)


def _gantry(width_m, name, lanes, board="guide_yanan"):
    """A guide gantry: truss at 6.7 m with a sign panel and per-lane mount markers."""
    p = kit.Prop(name)
    half = width_m * 0.5
    truss_z = 6.70
    p.box("Post_L", (-half, 0.0, truss_z * 0.5), (0.42, 0.42, truss_z), M.surface(),
          bevel=0.03, surface=GALV)
    p.box("Post_R", (half, 0.0, truss_z * 0.5), (0.42, 0.42, truss_z), M.surface(),
          bevel=0.03, surface=GALV)
    for sx in (-half, half):
        p.box("Foot", (sx, 0.0, 0.10), (0.80, 0.80, 0.20), M.surface(), surface="concrete")
    _truss(p, "Truss", -half, half, 0.0, truss_z)
    # the sign hangs on the front face of the truss: its bottom stays at 5.5 m
    p.sign("SignFace", (0.0, -0.50, truss_z), 4.20, 2.40, M.sign(), M.surface(),
           board=board, frame=0.08, depth=0.10)
    for i, lx in enumerate(lanes):
        p.empty("SignMount_%d" % (i + 1), (lx, -0.50, truss_z), direction=(0.0, -1.0, 0.0),
                size=0.4)
    p.empty("Light", (0.0, 0.0, truss_z - 0.7), direction=(0.0, 0.0, -1.0), size=0.5)
    return p.finalize(name)


def guide_gantry_19():
    """Guide gantry over a 19 m carriageway (2+2 ring-road deck)."""
    return _gantry(19.0, "GuideGantry19", (-6.0, 0.0, 6.0))


def guide_gantry_27():
    """Guide gantry over a 27 m carriageway (3+3 elevated deck, dossier §2.2)."""
    return _gantry(27.0, "GuideGantry27", (-9.0, 0.0, 0.0, 9.0))


def guide_gantry_34():
    """Guide gantry over a 34 m carriageway (wide ramp / toll approach)."""
    return _gantry(34.0, "GuideGantry34", (-12.0, -4.0, 4.0, 12.0))


# ------------------------------------------------------------------ guide sign
def guide_sign():
    """A green guide panel (4.2 x 2.4 m) with a frame and rear bracing."""
    p = kit.Prop("GuideSign")
    w, h = 4.20, 2.40
    p.sign("SignFace", (0.0, 0.0, 0.0), w, h, M.sign(), M.surface(),
           board="guide_yanan", frame=0.08, depth=0.10)
    for sx in (-1.55, 0.0, 1.55):
        p.tube("Brace", (sx, 0.06, -h * 0.5), (sx, 0.55, -h * 0.5 - 0.9), 0.045,
               M.surface(), segments=6, surface=GALV)
        p.tube("Brace2", (sx, 0.06, h * 0.5), (sx, 0.55, h * 0.5), 0.04, M.surface(),
               segments=6, surface=GALV)
    return p.finalize("GuideSign")


# ------------------------------------------------------------------ VMS
def vms_board():
    """可变情报板: an 8 x 2.5 m black LED board on two posts."""
    p = kit.Prop("VmsBoard")
    w, h = 8.0, 2.5
    z0 = 4.4
    p.box("Frame", (0.0, 0.0, z0), (w + 0.24, 0.26, h + 0.24), M.surface(), bevel=0.03,
          surface=DARK)
    p.quad("Screen", w, h, M.sign_lit(), (0.0, -0.145, z0), board="vms_congestion")
    for sx in (-w * 0.35, w * 0.35):
        p.cyl("Post", (sx, 0.0, z0 * 0.5), 0.11, z0, M.surface(), segments=10, surface=GALV)
        p.box("Foot", (sx, 0.0, 0.08), (0.50, 0.50, 0.16), M.surface(), surface="concrete")
    p.box("Hood", (0.0, -0.34, z0 + h * 0.5 + 0.20), (w + 0.24, 0.60, 0.10), M.surface(),
          bevel=0.02, surface=DARK)
    return p.finalize("VmsBoard")


# ------------------------------------------------------------------ bus stop
def bus_stop():
    """Stainless and grey shelter, 8 x 1.6 x 2.6 m, with a backlit ad and route board."""
    p = kit.Prop("BusStop")
    w, d, h = 8.0, 1.60, 2.60
    for sx in (-w / 2 + 0.15, 0.0, w / 2 - 0.15):
        for sy in (-d / 2 + 0.12, d / 2 - 0.12):
            p.cyl("Post", (sx, sy, h * 0.5), 0.055, h, M.surface(), segments=8,
                  surface="alu")
    p.box("Roof", (0.0, 0.0, h + 0.05), (w, d + 0.30, 0.10), M.surface(), bevel=0.03,
          surface="alu")
    p.box("RoofGlass", (0.0, 0.0, h + 0.12), (w - 0.30, d - 0.10, 0.05), M.glass())
    # the back of the shelter is glass with a dirt film, not a solid panel
    p.box("BackGlass", (0.0, d / 2 - 0.10, 1.30), (w - 0.30, 0.05, 2.40), M.glass())
    p.box("BackFrame", (0.0, d / 2 - 0.08, 1.30), (w - 0.18, 0.04, 2.52), M.surface(),
          surface="alu")
    p.box("BackRail", (0.0, d / 2 - 0.10, 0.12), (w - 0.30, 0.10, 0.10), M.surface(),
          surface="alu")
    p.box("SideGlass", (-w / 2 + 0.12, 0.0, 1.30), (0.05, d - 0.20, 2.40), M.glass())
    p.box("Bench", (0.0, d / 2 - 0.45, 0.45), (w - 1.6, 0.40, 0.06), M.surface(),
          bevel=0.02, surface="alu")
    for sx in (-1.0, 1.0):
        p.box("BenchLeg", (sx, d / 2 - 0.45, 0.22), (0.06, 0.36, 0.44), M.surface(),
              surface="alu")
    p.sign("AdFace", (-w / 2 + 0.85, -d / 2 + 0.20, 1.35), 1.20, 1.80, M.sign_lit(),
           M.surface(), board="bus_ad", frame=0.07, depth=0.07, frame_surface="alu")
    p.sign("RouteBoard", (w / 2 - 0.80, -d / 2 + 0.20, 1.40), 1.10, 1.60, M.sign_lit(),
           M.surface(), board="bus_route", frame=0.06, depth=0.07, frame_surface="alu")
    p.box("ScreenBox", (w / 2 - 1.60, d / 2 - 0.16, 2.20), (0.80, 0.08, 0.34), M.surface(),
          surface=DARK)
    p.quad("ScreenFace", 0.72, 0.28, M.sign_lit(), (w / 2 - 1.60, d / 2 - 0.21, 2.20),
           board="countdown_08")
    return p.finalize("BusStop")


# ------------------------------------------------------------------ police board
def police_sign_board():
    """Portable police checkpoint board on a folding A-frame (parody livery)."""
    p = kit.Prop("PoliceSignBoard")
    for sx in (-0.50, 0.50):
        p.tube("Leg", (sx, -0.30, 0.0), (sx, 0.22, 1.35), 0.028, M.surface(), segments=6,
               surface=DARK)
        p.tube("LegRear", (sx, 0.34, 0.0), (sx, 0.22, 1.35), 0.028, M.surface(),
               segments=6, surface=DARK)
    p.tube("Hinge", (-0.50, 0.22, 1.35), (0.50, 0.22, 1.35), 0.026, M.surface(),
           segments=6, surface=DARK)
    p.sign("SignFace", (0.0, -0.12, 0.72), 1.20, 0.80, M.sign_lit(), M.surface(),
           board="police_board", frame=0.06, depth=0.06, frame_surface="steel_dark")
    p.box("Foot", (0.0, 0.10, 0.03), (1.10, 0.80, 0.06), M.surface(), bevel=0.01,
          surface=DARK)
    return p.finalize("PoliceSignBoard")


BUILDERS = {
    "traffic_light_mast": traffic_light_mast,
    "road_name_sign": road_name_sign,
    "guide_gantry_19": guide_gantry_19,
    "guide_gantry_27": guide_gantry_27,
    "guide_gantry_34": guide_gantry_34,
    "guide_sign": guide_sign,
    "vms_board": vms_board,
    "bus_stop": bus_stop,
    "police_sign_board": police_sign_board,
}
