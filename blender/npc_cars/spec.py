"""Vehicle specifications for the SKYRUSH NPC fleet (unit: npc_cars).

Metres, Blender axes (CONTRACTS.md §1): +Y forward, +X right, Z up, ground at z = 0.
y = 0 is the middle of the wheelbase; the nose is at +y.

`car` kind: the N-ART5 parameters of the lofted body generator
(`lib/car_body.py`). `box` kind: a one-box commercial body. `drone` kind: a quad
rotor. Paint colours are sRGB hex tokens (colors.py).
"""
try:
    from . import colors
except ImportError:          # run as a plain script (texture generator)
    import colors


def K(*pairs):
    """Knot list from pairs."""
    return [(float(a), float(b)) for a, b in pairs]


# ---------------------------------------------------------------- cars
# N-ART5 parameters: the side profile (nose -> hood -> windscreen -> roof ->
# backlight -> deck -> tail), the belt line, the plan view and the glass house.

def _car(name, L, W, H, wb, wr, ww, track, clear, nose_z, hood_z, cowl_y,
         roof_front_y, roof_z, roof_rear_y, deck_y, deck_z, tail_z,
         belt_front, belt_rear, tumble, rc_front, rc_rear, bulge,
         doors, paint=colors.PAINT_WHITE, livery=None, arch_clad=False,
         wrap=False, crown_y=None, roof_drop=0.0, dlo_rear=None,
         dlo_rail_end=None, dlo_front=None):
    return {
        "name": name, "kind": "car", "L": L, "W": W, "H": H, "wb": wb,
        "axle_f": wb * 0.5, "axle_r": -wb * 0.5,
        "wr": wr, "ww": ww, "track": track, "clear": clear,
        "nose_z": nose_z, "hood_z": hood_z, "cowl_y": cowl_y,
        "roof_front_y": roof_front_y, "roof_z": roof_z,
        "crown_y": crown_y, "roof_drop": roof_drop,
        "roof_rear_y": roof_rear_y, "deck_y": deck_y, "deck_z": deck_z,
        "tail_z": tail_z, "belt_front": belt_front, "belt_rear": belt_rear,
        "tumble": tumble,
        "rc_front": rc_front, "rc_rear": rc_rear, "bulge": bulge,
        "doors": doors, "paint": paint, "livery": livery, "arch_clad": arch_clad,
        "wrap": wrap, "dlo_rear": dlo_rear, "dlo_rail_end": dlo_rail_end,
        "dlo_front": dlo_front,
    }


# Fastback sedan: the roof crowns 1.47 m at 20 % of the length from the nose
# and falls 70 mm to the backlight, which drops 28 deg to the boot lid.
SEDAN = _car(
    "sedan_ev", 4.85, 1.90, 1.47, 2.98, 0.347, 0.235, 0.795, 0.155,
    0.76, 0.98, 1.30, 0.45, 1.465, -0.75, -1.78, 1.04, 0.98,
    0.92, 0.96, 0.16, 0.28, 0.26, 0.005,
    [(0.10, 1.16), (-0.92, -0.02)],
    crown_y=0.10, roof_drop=0.05,
    dlo_rear=-0.85, dlo_rail_end=-1.10,
)

# Mid SUV: taller, a flat roof with a 30 mm drop, an upright rear and
# chunky arch cladding.
SUV = _car(
    "suv_ev", 4.75, 1.93, 1.68, 2.85, 0.375, 0.255, 0.800, 0.200,
    0.86, 1.10, 1.32, 0.50, 1.665, -1.90, -2.20, 1.30, 1.10,
    1.02, 1.08, 0.13, 0.30, 0.24, 0.008,
    [(0.08, 1.18), (-0.98, -0.04)],
    arch_clad=True, crown_y=0.10, roof_drop=0.03,
    dlo_rear=-1.62, dlo_rail_end=-1.70,
)

# Rounded 2-box city hatch: short bonnet, tall cabin, an upright tailgate.
HATCH = _car(
    "hatch_ev", 3.95, 1.77, 1.55, 2.50, 0.330, 0.205, 0.745, 0.160,
    0.80, 0.98, 1.00, 0.30, 1.545, -1.20, -1.38, 1.08, 0.95,
    0.90, 0.95, 0.17, 0.46, 0.46, 0.004,
    [(0.05, 0.86), (-0.72, -0.06)],
    crown_y=0.05, roof_drop=0.02,
    dlo_rear=-1.02, dlo_rail_end=-1.10,
)

# Robotaxi pod: no bonnet, a wrap-around canopy, short overhangs.
ROBOTAXI = _car(
    "robotaxi", 4.20, 1.90, 1.55, 2.80, 0.350, 0.225, 0.800, 0.145,
    1.05, 1.05, 1.95, 0.85, 1.545, -1.35, -1.75, 1.12, 1.02,
    0.94, 0.98, 0.24, 0.46, 0.44, 0.004,
    [(-0.60, 1.30)],
    wrap=True, crown_y=0.20, roof_drop=0.02,
    dlo_rear=-1.28, dlo_rail_end=-1.35,
)

# Low, wide police interceptor: long bonnet, fast roof, wide stance.
INTERCEPTOR = _car(
    "police_interceptor", 4.70, 1.98, 1.25, 2.90, 0.360, 0.295, 0.815, 0.115,
    0.72, 0.88, 1.22, 0.40, 1.245, -0.55, -1.75, 0.95, 0.88,
    0.87, 0.91, 0.17, 0.32, 0.28, 0.012,
    [(0.05, 1.05), (-0.85, -0.02)],
    paint=colors.POLICE_WHITE, livery="police",
    crown_y=0.0, roof_drop=0.04,
    dlo_rear=-0.98, dlo_rail_end=-0.60,
)

# Heavy armoured police SUV: high floor, flat roof, ram bar.
POLICE_SUV = _car(
    "police_suv", 5.20, 2.10, 1.95, 3.05, 0.410, 0.285, 0.845, 0.250,
    1.02, 1.20, 1.45, 0.65, 1.935, -2.10, -2.35, 1.45, 1.25,
    1.12, 1.16, 0.10, 0.30, 0.24, 0.010,
    [(0.10, 1.28), (-1.05, -0.05)],
    paint=colors.POLICE_WHITE, livery="police", arch_clad=True,
    crown_y=0.20, roof_drop=0.03,
    dlo_rear=-1.78, dlo_rail_end=-1.88,
)

# ---------------------------------------------------------------- traffic
TAXI = dict(SEDAN, name="taxi", paint=colors.TAXI_TEAL, livery="taxi",
            skirt_z=0.66)
PATROL = dict(SEDAN, name="police_patrol", paint=colors.POLICE_WHITE,
              livery="police")


# ---------------------------------------------------------------- box vehicles
# kind "box": one-piece commercial body (van / truck / bus). Wheels are
# (y, x_offset, radius, width); `win` are side glass rectangles
# (y0, y1, z0, z1); `door` are the glazed door recesses; the small tables
# hold the lamp / sign / mirror / plate placements so the builder holds no
# magic numbers.

VAN = {
    "name": "van", "kind": "box", "L": 5.30, "W": 2.00, "H": 2.10,
    "z0": 0.34, "z1": 2.10, "skirt": 0.62,
    "cab_y": (1.28, 2.65), "roof_cab": 1.94, "rake": 0.34,
    "cargo_y": (1.28, -2.67),
    "wheels": [(1.62, 0.80, 0.375, 0.215), (-1.60, 0.80, 0.375, 0.215)],
    "win": [(1.42, 2.24, 1.12, 1.62)],
    "wind": (1.06, 1.62),
    "lamp": {"z": 0.78, "h": 0.20, "w": 0.34, "inset": 0.10},
    "sign": None,
    "mirror": {"y": 2.20, "z": 1.60, "arm": 0.16, "size": 0.26},
    "plate": {"z": 0.66},
    "livery": "van", "paint": colors.PAINT_WHITE,
    "livery_box": {"y0": -2.30, "y1": 0.90, "z0": 0.95, "z1": 1.85},
}

TRUCK = {
    "name": "truck", "kind": "box", "L": 7.50, "W": 2.35, "H": 3.30,
    "z0": 0.62, "z1": 3.30, "skirt": 1.02,
    "cab_y": (1.88, 3.75), "roof_cab": 2.86, "rake": 0.42,
    "cargo_y": (1.88, -3.75),
    "wheels": [(2.75, 0.92, 0.450, 0.240), (-1.85, 0.92, 0.450, 0.240)],
    "tandem": 0.30,
    "win": [(2.15, 3.35, 1.62, 2.34)],
    "wind": (1.56, 2.34),
    "lamp": {"z": 1.20, "h": 0.24, "w": 0.38, "inset": 0.12},
    "sign": None,
    "mirror": {"y": 3.30, "z": 2.30, "arm": 0.20, "size": 0.30},
    "plate": {"z": 0.96},
    "livery": None, "paint": colors.PAINT_SILVER,
}

# 12 m battery bus, 2 axles (6.0 m wheelbase, 2.6 m front / 3.4 m rear
# overhang - ref/shanghai bus_yutong_e10_2018.jpg).
BUS = {
    "name": "bus", "kind": "box", "L": 12.00, "W": 2.55, "H": 3.20,
    "z0": 0.46, "z1": 3.20, "skirt": 0.92,
    "cab_y": (4.60, 6.00), "roof_cab": 3.20, "rake": 0.30,
    "cargo_y": (6.00, -6.00),
    "wheels": [(3.40, 1.03, 0.500, 0.290), (-2.60, 1.03, 0.500, 0.290)],
    # one continuous glazed band, split by black pillars every 1.4 m; the
    # passenger doors interrupt it on the right hand side
    "band": {"y0": -5.60, "y1": 5.80, "z0": 1.58, "z1": 2.58, "pillar": 1.40},
    "win": [],
    "wind": (1.34, 2.68),
    "door": [(4.30, 5.20, 0.70, 2.58, "right"), (-0.45, 0.35, 0.70, 2.58, "right")],
    "lamp": {"z": 1.05, "h": 0.26, "w": 0.44, "inset": 0.14},
    "sign": {"front": (1.30, 0.325, 2.74, 3.05),
             "rear": (1.10, 0.28, 2.62, 2.90),
             "side": (0.60, 0.30, 2.72, 3.02, 4.75)},
    "mirror": {"y": 5.30, "z": 2.50, "arm": 0.22, "size": 0.30},
    "plate": {"z": 0.80},
    "route": "71", "livery": "bus", "paint": colors.PAINT_WHITE,
}

DRONE = {
    "name": "police_drone", "kind": "drone", "dia": 1.60,
    "body": (0.52, 0.62, 0.20), "rotor_r": 0.30, "arm": 0.72,
    "paint": colors.POLICE_WHITE,
}

SPECS = [SEDAN, SUV, HATCH, TAXI, ROBOTAXI, VAN, TRUCK, BUS,
         PATROL, INTERCEPTOR, POLICE_SUV, DRONE]
BY_NAME = {s["name"]: s for s in SPECS}
PLATE_ORDER = ["sedan_ev", "suv_ev", "hatch_ev", "taxi", "robotaxi",
               "police_patrol", "police_interceptor", "police_suv",
               "van", "truck", "bus", "police_drone"]


