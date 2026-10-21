"""The flash-charging station (unit: props).

Dossier §8.2: a 70 x 24 m white canopy with a continuous cyan LED line, 12 bays,
6 slim white "VOLTA" posts and 6 tall dispensers with overhead cable booms.

The `ChargeArea` empty carries the trigger volume in its extras (the world unit's
ChargeStation needs it).
"""
import math

import bmesh

from lib import geo

from . import kit, materials as M

CANOPY_W = 70.0
CANOPY_D = 24.0
UNDERSIDE = 5.0
FASCIA_H = 1.1
BAY_W = 3.0            # bay width (X)
BAY_L = 5.5            # bay length (Y)
BAYS_PER_SIDE = 6
BAY_Y = 5.8            # the centre of the painted bay
BAY_PITCH = 5.5           # the bays are spread over the canopy
POST_X = (-13.75, -8.25, -2.75, 2.75, 8.25, 13.75)
TOTEM_H = 7.0

WHITE = "white_paint"
ALU = "alu"
DARK = "steel_dark"
TEAL = "charge_teal"


def _collider(p, name, center, size):
    bm = bmesh.new()
    geo.box(bm, center, size)
    return p.mesh(name + "-convcolonly", bm, None, box_map=True)


def _canopy(p):
    """The canopy as one node: roof, soffit, fascia, cyan LED line and the panels."""
    parts = []
    parts.append(p.box("Roof", (0.0, 0.0, UNDERSIDE + FASCIA_H + 0.12),
                       (CANOPY_W, CANOPY_D, 0.24), M.surface(), bevel=0.03,
                       surface="silver"))
    parts.append(p.quad("Soffit", CANOPY_W - 0.4, CANOPY_D - 0.4, M.soffit(),
                         (0.0, 0.0, UNDERSIDE - 0.01), rot=(math.pi / 2.0, 0.0, 0.0),
                         surface="soffit"))
    for sy, rot in ((-CANOPY_D * 0.5, 0.0), (CANOPY_D * 0.5, math.pi)):
        parts.append(p.box("Fascia_%d" % int(sy),
                           (0.0, sy + (0.15 if sy < 0 else -0.15),
                            UNDERSIDE + FASCIA_H * 0.5),
                           (CANOPY_W, 0.30, FASCIA_H), M.surface(), bevel=0.02,
                           surface=WHITE))
        # the continuous cyan LED line, on the OUTER face of the fascia
        parts.append(p.quad("LedLine_%d" % int(sy), CANOPY_W - 2.0, 0.55,
                             M.sign_led_cyan(),
                             (0.0, sy + (0.02 if sy > 0 else -0.02),
                              UNDERSIDE + FASCIA_H * 0.5),
                             rot=(0.0, 0.0, rot), board="billboard_cyan"))
    # the cyan line wraps the two ends as well, so the hub reads from the approach
    for sx in (-1, 1):
        parts.append(p.quad("LedLine_End%d" % sx, CANOPY_D - 2.0, 0.55,
                             M.sign_led_cyan(),
                             (sx * (CANOPY_W * 0.5 + 0.02), 0.0, UNDERSIDE + FASCIA_H * 0.5),
                             rot=(0.0, 0.0, sx * math.pi / 2.0), board="billboard_cyan"))
    lamps = []
    for ix in range(10):
        for iy in range(3):
            lamps.append((1.20, 1.20, (-31.5 + ix * 7.0, -7.0 + iy * 7.0, UNDERSIDE - 0.01)))
    parts.append(p.quads("Downlights", lamps, M.sign_lit(True), board="billboard_led"))
    p.join_parts("Canopy", parts)
    _collider(p, "Canopy", (0.0, 0.0, UNDERSIDE + FASCIA_H * 0.5),
              (CANOPY_W, CANOPY_D, FASCIA_H + 0.6))


def _columns(p):
    for i, sx in enumerate((-30.0, -10.0, 10.0, 30.0)):
        for j, sy in enumerate((-CANOPY_D * 0.5 + 1.2, CANOPY_D * 0.5 - 1.2)):
            n = i * 2 + j + 1
            p.box("Column_%d" % n, (sx, sy, UNDERSIDE * 0.5), (0.45, 0.45, UNDERSIDE),
                  M.surface(), bevel=0.03, surface=WHITE)
            p.box("ColumnBase_%d" % n, (sx, sy, 0.12), (0.90, 0.90, 0.24), M.surface(),
                  surface="concrete")
            p.wear_band("ColumnWear_%d" % n, (sx, sy, 0.0), 0.225)
            _collider(p, "Column_%d" % n, (sx, sy, UNDERSIDE * 0.5), (0.45, 0.45, UNDERSIDE))


def _bay_x(i):
    """The x of the i-th bay: 2 rows of 6 at a 5.5 m pitch."""
    return (i - (BAYS_PER_SIDE - 1) * 0.5) * BAY_PITCH


def _bay_number_uv(n):
    """The UV box of one number in the bay-number sheet (4 columns x 3 rows)."""
    col = (n - 1) % 4
    row = (n - 1) // 4
    return (col / 4.0, 1.0 - (row + 1) / 3.0, (col + 1) / 4.0, 1.0 - row / 3.0)


def _bays(p):
    """12 painted bays with their numbers, readable from the driver's seat.

    The bays are spread over the canopy (a 5.5 m pitch), they are green with
    a 0.15 m white edge line, and the numbers are white glyphs with an alpha
    cut-out: no dark tile on the paint.
    """
    fill = bmesh.new()
    lines = bmesh.new()
    numbers = bmesh.new()
    for i in range(BAYS_PER_SIDE):
        x = _bay_x(i)
        for side, n in ((-1, i + 1), (1, i + 7)):
            kit.add_quad(fill, BAY_W, BAY_L, (x, side * BAY_Y, 0.032), kit.FLAT,
                         uv_scale=(BAY_W, BAY_L))
            for sx in (-1, 1):
                kit.add_quad(lines, 0.15, BAY_L, (x + sx * (BAY_W * 0.5 - 0.075),
                                                  side * BAY_Y, 0.034), kit.FLAT,
                             uv_scale=(0.15, BAY_L))
            kit.add_quad(numbers, 1.30, 1.30,
                         (x, side * (BAY_Y + BAY_L * 0.5 - 0.90), 0.036), kit.FLAT,
                         _bay_number_uv(n))
    p.mesh("Bays", fill, M.surface(), box_map=False, surface="bay_green")
    p.mesh("BayLines", lines, M.surface(), box_map=False, surface="bay_line")
    p.mesh("BayNumbers", numbers, M.bay_numbers(), box_map=False)


def _volta_post(p, name, x, y):
    """A slim white charging post with lit VOLTA lettering and a kW readout."""
    p.box(name + "_Body", (x, y, 0.95), (0.34, 0.60, 1.90), M.surface(), bevel=0.04,
          surface=WHITE)
    p.box(name + "_Base", (x, y, 0.06), (0.52, 0.80, 0.12), M.surface(), surface=DARK)
    p.quad(name + "_Logo", 0.34, 0.24, M.sign_lit(), (x, y - 0.31, 1.55),
           board="charge_post_volta")
    p.quad(name + "_Readout", 0.40, 0.22, M.sign_lit(), (x, y - 0.31, 1.15),
           board="charge_kw_500")
    p.tube(name + "_Cable", (x + 0.18, y, 1.30), (x + 0.34, y - 0.10, 0.35), 0.028,
           M.surface(), segments=6, surface=DARK)
    p.box(name + "_Gun", (x + 0.34, y - 0.10, 0.32), (0.10, 0.14, 0.24), M.surface(),
          surface=DARK)
    _collider(p, name, (x, y, 0.95), (0.34, 0.60, 1.90))


def _boom_dispenser(p, name, x, y):
    """A 2.2 m teal and white dispenser with an overhead cable boom."""
    p.box(name, (x, y, 1.10), (0.80, 0.60, 2.20), M.surface(), bevel=0.05,
          surface=WHITE)
    p.box(name + "_Trim", (x, y, 2.06), (0.84, 0.64, 0.30), M.surface(), surface=TEAL)
    p.box(name + "_Base", (x, y, 0.07), (1.00, 0.80, 0.14), M.surface(), surface=DARK)
    p.quad(name + "_Readout", 0.60, 0.30, M.sign_lit(True), (x, y - 0.31, 1.55),
           board="charge_kw_500")
    p.box(name + "_Boom", (x, y + 0.30, 2.55), (0.16, 1.10, 0.16), M.surface(),
          surface=TEAL)
    p.tube(name + "_Cable", (x, y + 0.75, 2.48), (x, y + 0.90, 1.20), 0.030, M.surface(),
           segments=6, surface=DARK)
    p.box(name + "_Gun", (x, y + 0.92, 1.12), (0.12, 0.16, 0.30), M.surface(),
          surface=DARK)
    _collider(p, name, (x, y, 1.10), (0.80, 0.60, 2.20))


def _totem(p):
    """The 7 m totem with its lit lightning bolt on both faces."""
    x = -CANOPY_W * 0.5 + 3.0
    p.box("Totem", (x, 0.0, TOTEM_H * 0.5), (1.20, 0.30, TOTEM_H), M.surface(),
          bevel=0.04, surface=WHITE)
    p.box("TotemBase", (x, 0.0, 0.12), (1.60, 0.80, 0.24), M.surface(),
          surface="concrete")
    p.quad("TotemFace", 1.16, 6.70, M.sign_lit(), (x, -0.16, TOTEM_H * 0.5),
           board="charge_totem")
    p.quad("TotemBolt", 1.30, 2.00, M.sign_led_cyan(), (x, -0.17, TOTEM_H * 0.5 + 2.10),
           board="charge_bolt")
    p.quad("TotemBoltBack", 1.30, 2.00, M.sign_led_cyan(), (x, 0.17, TOTEM_H * 0.5 + 2.10),
           rot=(0.0, 0.0, math.pi), board="charge_bolt")
    p.empty("Light", (x, 0.0, TOTEM_H - 0.2), direction=(0.0, 0.0, -1.0), size=0.5)
    _collider(p, "Totem", (x, 0.0, TOTEM_H * 0.5), (1.20, 0.30, TOTEM_H))


def _canopy_lights(p):
    """One `Light_<n>` marker per downlight under the canopy (7 x 2)."""
    n = 0
    for ix in range(7):
        for iy in range(2):
            n += 1
            p.empty("Light_%d" % n, (-30.0 + ix * 10.0, -6.0 + iy * 12.0,
                                     UNDERSIDE - 0.30),
                    direction=(0.0, 0.0, -1.0), size=0.8)


def _forecourt(p):
    """The concrete forecourt under the canopy (ART.md §4.10)."""
    p.box("Forecourt", (0.0, 0.0, -0.04), (CANOPY_W + 22.0, CANOPY_D + 14.0, 0.12),
          M.surface(), surface="forecourt")
    for i in range(BAYS_PER_SIDE):
        p.quad("Polish_%d" % (i + 1), 3.60, BAY_L + 1.0, M.surface(),
               (_bay_x(i), -BAY_Y, 0.030), rot=kit.FLAT, surface="polish")
    p.quad("PolishDrive", CANOPY_W, 4.20, M.surface(), (0.0, 0.0, 0.030),
           rot=kit.FLAT, surface="polish")


def _light_pool(p):
    """The baked ground light pool of the canopy: additive, under everything."""
    p.quad("LightPool", CANOPY_W + 4.0, CANOPY_D + 4.0, M.light_pool("charge"),
           (0.0, 0.0, 0.025), rot=kit.FLAT)


def charge_station():
    """The whole charging station as one glb."""
    p = kit.Prop("ChargeStation")
    p.box("Apron", (0.0, 0.0, -0.05), (CANOPY_W + 30.0, CANOPY_D + 26.0, 0.10),
          M.surface(), surface="asphalt")
    _canopy(p)
    _columns(p)
    _bays(p)
    for i, x in enumerate(POST_X):
        _volta_post(p, "Post_%d" % (i + 1), x, -2.6)
        _boom_dispenser(p, "Dispenser_%d" % (i + 1), x, 2.6)
    _totem(p)
    _canopy_lights(p)
    _forecourt(p)
    _light_pool(p)
    area = p.empty("ChargeArea", (0.0, 0.0, 1.20), direction=(0.0, 1.0, 0.0), size=1.2)
    area["charge_area_centre"] = [0.0, 0.0, 1.20]
    area["charge_area_size"] = [40.0, 18.0, 2.40]
    area["charge_area_id"] = "charge_station"
    return p.finalize("ChargeStation")


BUILDERS = {"charge_station": charge_station}
