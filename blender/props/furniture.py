"""Small street furniture for the SKYRUSH props unit: litter bins, bollards,
hydrants, the bike-share dock, an e-scooter and an air-conditioning condenser.

Dossier §6 (detail density rule) and §9. These are the objects the camera
passes at 2-20 m, so they carry small readable detail.
"""
import math

import bmesh

from . import kit, materials as M

ALU = "alu"
GALV = "galv"
DARK = "steel_dark"
WHITE_PLATE = "white_paint"


def bin():
    """A 0.9 m litter bin with a swing lid and a liner ring."""
    p = kit.Prop("Bin")
    p.cyl("Body", (0.0, 0.0, 0.32), 0.26, 0.64, M.surface(), segments=16, r2=0.245,
          surface="green")
    p.ring("Rim", (0.0, 0.0, 0.64), 0.26, 0.03, 0.05, M.surface(), segments=16,
           surface="green")
    p.cyl("Lid", (0.0, 0.0, 0.66), 0.28, 0.06, M.surface(), segments=16, r2=0.20,
           surface="black_plastic")
    p.box("LidHandle", (0.0, 0.0, 0.72), (0.16, 0.05, 0.06), M.surface(), bevel=0.01,
          surface="black_plastic")
    p.cyl("Post", (0.0, 0.0, 0.30), 0.035, 0.60, M.surface(), segments=8,
          surface="black_plastic")
    p.box("Base", (0.0, 0.0, 0.03), (0.40, 0.40, 0.06), M.surface(), surface="concrete")
    p.quad("Label", 0.22, 0.14, M.sign(), (0.0, -0.262, 0.40), board="bin_label")
    return p.finalize("Bin")


def bollard():
    """A 0.9 m steel bollard with a reflective band (kerb protection)."""
    p = kit.Prop("Bollard")
    p.cyl("Post", (0.0, 0.0, 0.45), 0.065, 0.90, M.surface(), segments=12, r2=0.058,
          surface=GALV)
    p.cyl("Cap", (0.0, 0.0, 0.91), 0.058, 0.06, M.surface(), segments=12, r2=0.02,
          surface=DARK)
    p.cyl("Band", (0.0, 0.0, 0.72), 0.064, 0.10, M.surface(), segments=12,
          surface="yellow")
    p.cyl("Base", (0.0, 0.0, 0.04), 0.11, 0.08, M.surface(), segments=12,
          surface="concrete")
    return p.finalize("Bollard")


def hydrant():
    """A fire hydrant: 0.9 m, red barrel, side outlets, chain cap."""
    p = kit.Prop("Hydrant")
    p.cyl("Barrel", (0.0, 0.0, 0.40), 0.11, 0.72, M.surface(), segments=12, r2=0.10,
          surface="red_paint")
    p.cyl("Foot", (0.0, 0.0, 0.05), 0.17, 0.10, M.surface(), segments=12, r2=0.14,
          surface="red_paint")
    p.cyl("Shoulder", (0.0, 0.0, 0.78), 0.10, 0.10, M.surface(), segments=12, r2=0.07,
          surface="red_paint")
    p.cyl("Cap", (0.0, 0.0, 0.85), 0.075, 0.06, M.surface(), segments=10, surface=GALV)
    p.cyl("CapNut", (0.0, 0.0, 0.90), 0.035, 0.05, M.surface(), segments=6, surface=GALV)
    for sx in (-1, 1):
        p.cyl("Outlet%d" % sx, (0.16 * sx, 0.0, 0.52), 0.055, 0.12, M.surface(),
              axis="X", segments=10, surface="red_paint")
        p.cyl("OutletCap%d" % sx, (0.23 * sx, 0.0, 0.52), 0.065, 0.04, M.surface(),
              axis="X", segments=10, surface=GALV)
    p.cyl("Rear", (0.0, -0.15, 0.52), 0.05, 0.10, M.surface(), axis="Y", segments=10,
          surface="red_paint")
    p.tube("Chain", (0.0, 0.0, 0.88), (0.12, 0.0, 0.56), 0.008, M.surface(), segments=5,
           surface=GALV)
    return p.finalize("Hydrant")


def _bike_wheel(p, name, wx, wheel_z, colour, chrome="white_plastic"):
    """One wheel: a torus tyre, a rim, a hub, six spokes and a mudguard."""
    bm = bmesh.new()
    kit.torus(bm, (0.0, 0.0, 0.0), 0.315, 0.022, major_seg=24, minor_seg=6, axis="Y")
    p.mesh(name + "_Tyre", bm, M.surface(), loc=(wx, 0.0, wheel_z), smooth=True,
           surface="rubber")
    bm = bmesh.new()
    kit.torus(bm, (0.0, 0.0, 0.0), 0.285, 0.010, major_seg=16, minor_seg=3, axis="Y")
    p.mesh(name + "_Rim", bm, M.surface(), loc=(wx, 0.0, wheel_z), smooth=True,
           surface=chrome)
    p.cyl(name + "_Hub", (wx, 0.0, wheel_z), 0.028, 0.10, M.surface(), axis="Y",
          segments=8, surface=chrome)
    for i in range(4):
        a = math.tau * i / 4.0
        p.tube(name + "_Spoke%d" % i, (wx, 0.0, wheel_z),
               (wx + 0.28 * math.cos(a), 0.0, wheel_z + 0.28 * math.sin(a)), 0.004,
               M.surface(), segments=4, surface=chrome)
    bm = bmesh.new()
    for i in range(4):
        a0 = math.radians(35.0 + i * 30.0)
        a1 = math.radians(35.0 + (i + 1) * 30.0)
        kit.tube(bm, (0.35 * math.cos(a0), 0.0, 0.35 * math.sin(a0)),
                 (0.35 * math.cos(a1), 0.0, 0.35 * math.sin(a1)), 0.030, segments=3,
                 cap=False)
    p.mesh(name + "_Guard", bm, M.surface(), loc=(wx, 0.0, wheel_z), smooth=True,
           surface=colour)


def _bike_basket(p, name, bx, bz, chrome="white_plastic"):
    """The wire basket on the front: a cage of thin rods."""
    for i in range(4):
        t = i / 3.0
        p.tube(name + "_BasketV%d" % i, (bx - 0.16 + 0.32 * t, -0.13, bz - 0.10),
               (bx - 0.16 + 0.32 * t, 0.13, bz - 0.10), 0.006, M.surface(), segments=3,
               surface=chrome, cap=False)
    for j in range(2):
        z = bz - 0.10 + j * 0.14
        p.tube(name + "_BasketH%d" % j, (bx - 0.16, -0.13, z), (bx - 0.16, 0.13, z),
               0.006, M.surface(), segments=3, surface=chrome, cap=False)
        p.tube(name + "_BasketF%d" % j, (bx + 0.16, -0.13, z), (bx + 0.16, 0.13, z),
               0.006, M.surface(), segments=3, surface=chrome, cap=False)
    p.tube(name + "_BasketRim", (bx - 0.16, -0.13, bz), (bx + 0.16, -0.13, bz), 0.006,
           M.surface(), segments=3, surface=chrome, cap=False)
    p.tube(name + "_BasketRim2", (bx - 0.16, 0.13, bz), (bx + 0.16, 0.13, bz), 0.006,
           M.surface(), segments=3, surface=chrome, cap=False)


def _bike(p, name, x, colour, chrome="white_plastic"):
    """One share bike: a step-through frame, torus tyres and a wire basket.

    The frame is the city bike of the dock: a curved down tube from the head
    tube to the bottom bracket, a seat tube, chain stays and seat stays, and a
    rear carrier.  The tyres are real tori (24 x 6), so they read as round at
    2 m instead of as octagons.
    """
    wheel_z = 0.34
    _bike_wheel(p, name + "F", x + 0.52, wheel_z, colour, chrome)
    _bike_wheel(p, name + "R", x - 0.52, wheel_z, colour, chrome)
    # the step-through frame: head tube, curved down tube, seat tube, stays
    p.tube(name + "_Head", (x + 0.34, 0.0, 0.72), (x + 0.40, 0.0, 1.02), 0.026,
           M.surface(), segments=8, surface=colour)
    p.tube(name + "_Down", (x + 0.38, 0.0, 0.98), (x + 0.05, 0.0, 0.50), 0.028,
           M.surface(), segments=8, surface=colour)
    p.tube(name + "_Bottom", (x + 0.05, 0.0, 0.50), (x - 0.30, 0.0, 0.42), 0.028,
           M.surface(), segments=8, surface=colour)
    p.tube(name + "_SeatTube", (x - 0.30, 0.0, 0.42), (x - 0.26, 0.0, 0.92), 0.026,
           M.surface(), segments=8, surface=colour)
    for sy in (-0.055, 0.055):
        p.tube(name + "_Chain", (x - 0.52, sy, wheel_z), (x - 0.30, sy, 0.42), 0.014,
               M.surface(), segments=6, surface=colour)
        p.tube(name + "_SeatStay", (x - 0.52, sy, wheel_z), (x - 0.27, sy, 0.90), 0.014,
               M.surface(), segments=6, surface=colour)
    p.cyl(name + "_Crank", (x + 0.05, 0.0, 0.42), 0.055, 0.03, M.surface(), axis="Y",
          segments=10, surface=chrome)
    p.tube(name + "_Pedal", (x + 0.05, -0.09, 0.42), (x + 0.05, 0.09, 0.42), 0.010,
           M.surface(), segments=6, surface=chrome)
    # the bars, the grips and the saddle
    p.tube(name + "_Bar", (x + 0.40, -0.22, 1.04), (x + 0.40, 0.22, 1.04), 0.016,
           M.surface(), segments=8, surface=chrome)
    for sy in (-0.20, 0.20):
        p.cyl(name + "_Grip", (x + 0.40, sy, 1.04), 0.019, 0.10, M.surface(), axis="Y",
              segments=8, surface="black_plastic")
    p.box(name + "_Saddle", (x - 0.28, 0.0, 0.96), (0.26, 0.10, 0.05), M.surface(),
          bevel=0.02, surface="black_plastic")
    _bike_basket(p, name, x + 0.60, 0.80, chrome)
    # the QR plate on the bar and the rear carrier
    p.box(name + "_QR", (x + 0.40, -0.02, 0.96), (0.02, 0.07, 0.05), M.surface(),
          surface=WHITE_PLATE)
    p.tube(name + "_Carrier", (x - 0.50, -0.09, 0.62), (x - 0.50, 0.09, 0.62), 0.010,
           M.surface(), segments=5, surface=colour, cap=False)


def bike_share():
    """A bike-share dock: a rail with two parody bicycles in different colours.

    Two bikes, not three: the tyres are real 24 x 6 tori (the review), and the
    prop has to stay under 3 000 triangles.
    """
    p = kit.Prop("BikeShare")
    p.box("Kerb", (0.0, 0.0, 0.04), (3.60, 0.90, 0.08), M.surface(), surface="concrete")
    p.box("Dock", (0.0, 0.0, 0.12), (3.40, 0.24, 0.16), M.surface(), bevel=0.02,
          surface="white_plastic")
    colours = ("teal", "gold")
    for i, colour in enumerate(colours):
        x = -0.80 + i * 1.60
        p.cyl("DockPost%d" % i, (x, -0.20, 0.70), 0.035, 0.90, M.surface(), segments=8,
              surface="white_plastic")
        p.box("DockHead%d" % i, (x, -0.20, 1.12), (0.10, 0.16, 0.10), M.surface(),
              bevel=0.01, surface="black_plastic")
        p.quad("DockScreen%d" % i, 0.09, 0.07, M.sign_lit(), (x, -0.205, 1.18),
               board="digital_battery")
        _bike(p, "Bike%d" % i, x, colour)
    return p.finalize("BikeShare")


def e_scooter():
    """A parked e-scooter: deck, stem, bar and two small wheels."""
    p = kit.Prop("EScooter")
    p.box("Deck", (0.0, 0.0, 0.11), (0.16, 0.62, 0.05), M.surface(), bevel=0.02,
          surface="black_plastic")
    p.cyl("WheelF", (0.0, -0.42, 0.10), 0.10, 0.05, M.surface(), axis="Y", segments=12,
          surface="rubber")
    p.cyl("WheelR", (0.0, 0.42, 0.10), 0.10, 0.05, M.surface(), axis="Y", segments=12,
          surface="rubber")
    p.tube("Stem", (0.0, -0.30, 0.13), (0.0, -0.36, 1.02), 0.035, M.surface(),
           segments=6, surface="black_plastic")
    p.tube("Bar", (-0.24, -0.36, 1.04), (0.24, -0.36, 1.04), 0.025, M.surface(),
           segments=5, surface="black_plastic")
    for sx in (-0.24, 0.24):
        p.cyl("Grip%d" % int(sx > 0), (sx, -0.36, 1.04), 0.032, 0.11, M.surface(),
              axis="X", segments=6, surface="black_plastic")
    p.box("Display", (0.0, -0.30, 1.00), (0.12, 0.04, 0.09), M.surface(), bevel=0.01,
          surface="black_plastic")
    p.quad("DisplayFace", 0.09, 0.06, M.sign_lit(), (0.0, -0.325, 1.00),
           board="digital_battery")
    p.box("Stand", (0.0, 0.34, 0.06), (0.12, 0.10, 0.12), M.surface(), bevel=0.01,
          surface="black_plastic")
    return p.finalize("EScooter")


def ac_unit():
    """A wall-mounted air-conditioning condenser with a fan grille and pipes."""
    p = kit.Prop("AcUnit")
    p.box("Shell", (0.0, 0.0, 0.40), (0.80, 0.36, 0.60), M.surface(), bevel=0.02,
          surface=ALU)
    p.box("GrilleFrame", (0.0, -0.19, 0.40), (0.62, 0.03, 0.44), M.surface(),
          bevel=0.01, surface=DARK)
    for i in range(7):
        p.box("GrilleBar%d" % i, (0.0, -0.205, 0.22 + i * 0.06), (0.58, 0.02, 0.018),
              M.surface(), surface=GALV)
    p.cyl("Fan", (0.0, -0.16, 0.40), 0.16, 0.05, M.surface(), axis="Y", segments=14,
          surface=DARK)
    p.box("Bracket", (0.0, 0.24, 0.10), (0.70, 0.14, 0.08), M.surface(), surface=GALV)
    p.tube("Pipe", (0.30, 0.14, 0.22), (0.30, 0.14, -0.60), 0.035, M.surface(),
           segments=8, surface="rusty")
    p.tube("Pipe2", (0.22, 0.14, 0.18), (0.22, 0.14, -0.60), 0.028, M.surface(),
           segments=8, surface="rusty")
    p.box("Wall", (0.0, 0.30, 0.30), (1.20, 0.08, 1.40), M.surface(), surface="concrete")
    return p.finalize("AcUnit")


BUILDERS = {
    "bin": bin,
    "bollard": bollard,
    "hydrant": hydrant,
    "bike_share": bike_share,
    "e_scooter": e_scooter,
    "ac_unit": ac_unit,
}
