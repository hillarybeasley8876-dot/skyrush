"""The roadside gas station (unit: props).

Dossier §8.1: a 60 x 30 m canopy with a red fascia, six breakable columns named
`Support_1..6`, three islands with two dispensers each, a 9 m price pylon and the
"易快 EZ-JOY" convenience store.

The canopy (roof, soffit, fascia, sign and downlights) is ONE node called
`Canopy`, so the world unit can drop the whole roof when a support breaks; the
`Support_1..6` columns hang under it.
"""
import math

import bmesh

from lib import geo

from . import kit, materials as M

CANOPY_W = 60.0
CANOPY_D = 30.0
UNDERSIDE = 6.0
FASCIA_H = 1.4
STORE_W, STORE_D, STORE_H = 25.0, 12.0, 4.5
PYLON_H = 9.0
SUPPORT_X = (-20.0, 0.0, 20.0)
SUPPORT_Y = (-8.0, 8.0)
ISLAND_X = (-20.0, 0.0, 20.0)
DISPENSER_DX = 3.4
# The brand is repeated on both long faces of the 60 m fascia.
BRAND_W = 16.0
BRAND_X = (-20.0, 0.0, 20.0)

ALU = "alu"
RED = "red_paint"
DARK = "steel_dark"
WHITE = "white_paint"


def _collider(p, name, center, size):
    bm = bmesh.new()
    geo.box(bm, center, size)
    return p.mesh(name + "-convcolonly", bm, None, box_map=True)


def _canopy(p):
    """The whole canopy as one node: roof, soffit, fascia, brand and downlights."""
    parts = []
    parts.append(p.box("Roof", (0.0, 0.0, UNDERSIDE + FASCIA_H + 0.10),
                       (CANOPY_W, CANOPY_D, 0.20), M.surface(), bevel=0.03,
                       surface="silver"))
    parts.append(p.quad("Soffit", CANOPY_W - 0.4, CANOPY_D - 0.4, M.soffit(),
                         (0.0, 0.0, UNDERSIDE - 0.01), rot=(math.pi / 2.0, 0.0, 0.0),
                         surface="soffit"))
    parts.append(p.box("Fascia_Front", (0.0, -CANOPY_D * 0.5 + 0.15, UNDERSIDE + FASCIA_H * 0.5),
                       (CANOPY_W, 0.30, FASCIA_H), M.surface(), bevel=0.02, surface=RED))
    parts.append(p.box("Fascia_Back", (0.0, CANOPY_D * 0.5 - 0.15, UNDERSIDE + FASCIA_H * 0.5),
                       (CANOPY_W, 0.30, FASCIA_H), M.surface(), bevel=0.02, surface=RED))
    for sx in (-1, 1):
        parts.append(p.box("Fascia_Side%d" % sx,
                           (sx * (CANOPY_W * 0.5 - 0.15), 0.0, UNDERSIDE + FASCIA_H * 0.5),
                           (0.30, CANOPY_D, FASCIA_H), M.surface(), bevel=0.02, surface=RED))
    # the brand, repeated on both long faces, with a logo end cap at each end
    for sx in (-1, 1):
        face_y = sx * (CANOPY_D * 0.5 + 0.02)
        for bx in BRAND_X:
            parts.append(p.quad("FasciaBrand_%d_%d" % (sx, int(bx)), BRAND_W, 0.95,
                                 M.sign_lit(), (bx, face_y, UNDERSIDE + 0.72),
                                 rot=(0.0, 0.0, math.pi if sx > 0 else 0.0),
                                 board="gas_fascia"))
        for ex in (-CANOPY_W * 0.5 + 2.0, CANOPY_W * 0.5 - 2.0):
            parts.append(p.quad("FasciaLogo_%d_%d" % (sx, int(ex)), 2.6, 0.95,
                                 M.sign_lit(), (ex, face_y, UNDERSIDE + 0.72),
                                 rot=(0.0, 0.0, math.pi if sx > 0 else 0.0),
                                 board="gas_logo"))
    # the red light strip along the fascia
    parts.append(p.quad("FasciaStrip", CANOPY_W - 2.0, 0.22, M.sign_lit(),
                         (0.0, -CANOPY_D * 0.5 - 0.01, UNDERSIDE + 0.20),
                         board="billboard_red"))
    lamps = []
    for ix in range(6):
        for iy in range(4):
            lamps.append((1.40, 1.40, (-25.0 + ix * 10.0, -11.25 + iy * 7.5,
                                         UNDERSIDE - 0.01)))
    parts.append(p.quads("Downlights", lamps, M.sign_lit(True), board="billboard_led"))
    p.join_parts("Canopy", parts)
    _collider(p, "Canopy", (0.0, 0.0, UNDERSIDE + FASCIA_H * 0.5),
              (CANOPY_W, CANOPY_D, FASCIA_H + 0.6))


def _supports(p):
    """The six canopy columns: `Support_1..6`, the pursuit-breaker handles."""
    for i, sx in enumerate(SUPPORT_X):
        for j, sy in enumerate(SUPPORT_Y):
            n = i * len(SUPPORT_Y) + j + 1
            p.box("Support_%d" % n, (sx, sy, UNDERSIDE * 0.5), (0.60, 0.60, UNDERSIDE),
                  M.surface(), bevel=0.03, surface=ALU)
            # the cladding panels of the column and its red base skirt
            for k in range(4):
                p.box("SupportPanel_%d_%d" % (n, k), (sx, sy, 1.10 + k * 1.20),
                      (0.64, 0.64, 0.04), M.surface(), surface="silver")
            p.box("SupportSkirt_%d" % n, (sx, sy, 0.55), (0.64, 0.64, 1.10),
                  M.surface(), bevel=0.02, surface=RED)
            p.box("SupportBase_%d" % n, (sx, sy, 0.15), (1.10, 1.10, 0.30), M.surface(),
                  surface="concrete")
            p.wear_band("SupportWear_%d" % n, (sx, sy, 0.0), 0.30)
            _collider(p, "Support_%d" % n, (sx, sy, UNDERSIDE * 0.5),
                      (0.60, 0.60, UNDERSIDE))


def _dispenser(p, name, x, y):
    """A fuel dispenser (dossier §8.1): 2.3 m tall, 0.5 x 1.0 m.

    A rounded white cabinet with a red brand panel, a lit topper, two nozzle
    holsters per side with looping hoses and a green LED price window.
    """
    p.box(name + "_Kerb", (x, y, 0.075), (2.30, 1.00, 0.15), M.surface(),
          surface="concrete")
    p.box(name, (x, y, 1.20), (0.50, 1.00, 2.10), M.surface(), bevel=0.10,
          surface=WHITE)
    p.box(name + "_Red", (x, y, 2.02), (0.54, 1.04, 0.36), M.surface(), bevel=0.05,
          surface=RED)
    # the lit topper with the brand
    p.box(name + "_Topper", (x, y, 2.32), (0.40, 1.04, 0.26), M.surface(),
          surface=DARK)
    p.quad(name + "_TopperFace", 0.90, 0.22, M.sign_lit(True), (x - 0.21, y, 2.32),
           rot=(0.0, 0.0, -math.pi / 2.0), board="gas_logo")
    # the green LED price window on the driver side
    p.quad(name + "_Price", 0.40, 0.24, M.sign_lit(True), (x - 0.28, y, 1.55),
           rot=(0.0, 0.0, -math.pi / 2.0), board="fuel_price")
    p.box(name + "_PriceFrame", (x - 0.255, y, 1.55), (0.03, 0.52, 0.34),
          M.surface(), surface=DARK)
    # two nozzle holsters per side, with the hose looping down and back up
    for sy in (-1, 1):
        for k in (-1, 1):
            hx = x + 0.30 * k
            hy = y + sy * 0.52
            p.box(name + "_Holster%d%d" % (sy, k), (hx, hy, 1.30), (0.14, 0.12, 0.34),
                  M.surface(), surface=DARK)
            p.tube(name + "_HoseA%d%d" % (sy, k), (hx, hy, 1.44),
                   (hx + 0.14 * k, hy + sy * 0.10, 0.75), 0.028, M.surface(),
                   segments=6, surface=DARK)
            p.tube(name + "_HoseB%d%d" % (sy, k), (hx + 0.14 * k, hy + sy * 0.10, 0.75),
                   (hx + 0.02 * k, hy + sy * 0.06, 1.10), 0.028, M.surface(),
                   segments=6, surface=DARK)
    p.wear_band(name + "_Wear", (x, y, 0.15), 0.30, height=0.5)
    _collider(p, name, (x, y, 1.05), (0.50, 1.00, 2.10))


def _islands(p):
    for i, ix in enumerate(ISLAND_X):
        p.box("Island_%d" % (i + 1), (ix, 0.0, 0.10), (13.0, 3.40, 0.20), M.surface(),
              bevel=0.03, surface="concrete")
        _collider(p, "Island_%d" % (i + 1), (ix, 0.0, 0.10), (13.0, 3.40, 0.20))
        for j, dx in enumerate((-DISPENSER_DX, DISPENSER_DX)):
            _dispenser(p, "Dispenser_%d_%d" % (i + 1, j + 1), ix + dx, 0.0)
        for sx in (-6.0, 6.0):
            _bollard(p, "Bollard_%d_%d" % (i + 1, int(sx > 0)), ix + sx, 2.0)


def _bollard(p, name, x, y):
    p.cyl(name, (x, y, 0.45), 0.09, 0.90, M.surface(), segments=10, surface="yellow")
    p.cyl(name + "_Band", (x, y, 0.60), 0.095, 0.22, M.surface(), segments=10,
          surface="cast_iron")
    p.cyl(name + "_Cap", (x, y, 0.91), 0.09, 0.05, M.surface(), segments=10, r2=0.03,
          surface=DARK)


def _pylon(p):
    """The 9 m price pylon with its red digits board."""
    px, py = -CANOPY_W * 0.5 - 4.0, -CANOPY_D * 0.5 + 2.0
    p.box("Pylon", (px, py, PYLON_H * 0.5), (2.20, 0.70, PYLON_H), M.surface(),
          bevel=0.04, surface=RED)
    p.box("PylonFoot", (px, py, 0.18), (2.80, 1.20, 0.36), M.surface(),
          surface="concrete")
    p.quad("PriceBoard", 1.80, 2.40, M.sign_lit(True), (px, py - 0.37, 5.20),
           board="gas_price_board")
    p.quad("PylonCrown", 1.90, 1.10, M.sign_lit(), (px, py - 0.37, 8.10),
           board="gas_pylon_crown")
    p.empty("Light", (px, py, 8.9), direction=(0.0, 0.0, -1.0), size=0.4)
    _collider(p, "Pylon", (px, py, PYLON_H * 0.5), (2.20, 0.70, PYLON_H))


def _store(p):
    """The convenience store: a glazed shop front with a lit interior.

    The front wall is built around the opening, so the shelves, the counter
    and the ceiling panels are really inside the shop and show through the
    glass (ART §11: shop fronts are lit).
    """
    sy = CANOPY_D * 0.5 + STORE_D * 0.5 + 1.0
    front = sy - STORE_D * 0.5
    open_w = STORE_W - 6.0
    open_z0, open_z1 = 0.50, 3.30
    p.box("StoreFloor", (0.0, sy, 0.05), (STORE_W, STORE_D, 0.10), M.surface(),
          surface="concrete")
    p.box("StoreBack", (0.0, sy + STORE_D * 0.5 - 0.15, STORE_H * 0.5),
          (STORE_W, 0.30, STORE_H), M.surface(), surface="facade")
    for sx in (-1, 1):
        p.box("StoreSide_%d" % sx, (sx * (STORE_W * 0.5 - 0.15), sy, STORE_H * 0.5),
              (0.30, STORE_D, STORE_H), M.surface(), surface="facade")
    # the front wall around the shop window
    p.box("StoreFrontLow", (0.0, front + 0.15, open_z0 * 0.5),
          (STORE_W, 0.30, open_z0), M.surface(), surface="facade")
    p.box("StoreFrontHigh", (0.0, front + 0.15, (open_z1 + STORE_H) * 0.5),
          (STORE_W, 0.30, STORE_H - open_z1), M.surface(), surface="facade")
    for sx in (-1, 1):
        p.box("StoreFrontSide_%d" % sx,
              (sx * (STORE_W * 0.5 - (STORE_W - open_w) * 0.25), front + 0.15,
               (open_z0 + open_z1) * 0.5),
              ((STORE_W - open_w) * 0.5, 0.30, open_z1 - open_z0), M.surface(),
              surface="facade")
    p.box("StoreGlass", (0.0, front - 0.04, (open_z0 + open_z1) * 0.5),
          (open_w, 0.08, open_z1 - open_z0), M.glass())
    p.box("StoreMullion", (0.0, front - 0.05, (open_z0 + open_z1) * 0.5),
          (0.10, 0.10, open_z1 - open_z0), M.surface(), surface="silver")
    # the warm lit interior: ceiling panels, shelves and a counter
    p.quad("StoreCeil", open_w - 1.0, 1.60, M.sign_lit(True),
           (0.0, front + 2.40, open_z1 - 0.15), rot=(math.pi / 2.0, 0.0, 0.0),
           board="warm_led")
    p.quad("StoreBackLit", open_w - 1.0, 2.40, M.sign_lit(),
           (0.0, sy + STORE_D * 0.5 - 0.40, 1.70), board="warm_led")
    for k in range(3):
        p.box("StoreShelf_%d" % k, (0.0, sy + 1.60, 1.05 + k * 0.75),
              (open_w - 2.0, 0.60, 0.06), M.surface(), surface="silver")
    p.box("StoreCounter", (0.0, front + 1.60, 0.55), (open_w - 3.0, 0.70, 1.10),
          M.surface(), bevel=0.03, surface="silver")
    p.box("StoreRoof", (0.0, sy, STORE_H + 0.15), (STORE_W + 0.8, STORE_D + 0.8, 0.30),
          M.surface(), bevel=0.03, surface=ALU)
    p.quad("StoreBand", 10.0, 0.95, M.sign_lit(), (0.0, front - 0.06, 3.90),
           board="gas_store_band")
    p.quad("StoreBandSide", 6.0, 0.95, M.sign_lit(), (-STORE_W * 0.5 - 0.04, sy, 3.80),
           rot=(0.0, 0.0, -math.pi / 2.0), board="gas_store_band")
    for sx in (-11.0, -6.0, 6.0, 11.0):
        _bollard(p, "StoreBollard_%d" % int(sx), sx, front - 2.2)
    _collider(p, "Store", (0.0, sy, STORE_H * 0.5), (STORE_W, STORE_D, STORE_H))


def _canopy_lights(p):
    """One `Light_<n>` marker per downlight under the canopy (6 x 3).

    The world unit turns them into real spot lights; without them the
    forecourt is black under a bright ceiling (ART.md §4).
    """
    n = 0
    for ix in range(6):
        for iy in range(3):
            n += 1
            p.empty("Light_%d" % n, (-25.0 + ix * 10.0, -10.0 + iy * 10.0,
                                     UNDERSIDE - 0.30),
                    direction=(0.0, 0.0, -1.0), size=0.8)


def _forecourt(p):
    """The concrete forecourt under the canopy (ART.md §4.10).

    The pool of light used to be an opaque white sheet over an empty floor;
    now the floor is real concrete with the stains of the pumps and the
    polished lanes of the traffic.
    """
    p.box("Forecourt", (0.0, 0.0, -0.04), (CANOPY_W + 22.0, CANOPY_D + 14.0, 0.12),
          M.surface(), surface="forecourt")
    for i, ix in enumerate(ISLAND_X):
        for j, dx in enumerate((-DISPENSER_DX, DISPENSER_DX)):
            p.quad("Oil_%d_%d" % (i + 1, j + 1), 3.40, 2.40, M.surface(),
                   (ix + dx, 0.0, 0.035), rot=kit.FLAT, surface="stain")
    for sy in (-9.5, 9.5):
        p.quad("Polish_%d" % int(sy), CANOPY_W + 4.0, 3.60, M.surface(),
               (0.0, sy, 0.030), rot=kit.FLAT, surface="polish")


def _light_pool(p):
    """The baked ground light pool of the canopy: additive, under everything."""
    p.quad("LightPool", CANOPY_W + 4.0, CANOPY_D + 4.0, M.light_pool("gas"),
           (0.0, 0.0, 0.025), rot=kit.FLAT)


def gas_station():
    """The whole gas station as one glb."""
    p = kit.Prop("GasStation")
    p.box("Apron", (0.0, 0.0, -0.05), (CANOPY_W + 30.0, CANOPY_D + 26.0, 0.10),
          M.surface(), surface="asphalt")
    _canopy(p)
    _supports(p)
    _islands(p)
    _pylon(p)
    _store(p)
    _canopy_lights(p)
    _forecourt(p)
    _light_pool(p)
    prop = p.finalize("GasStation")
    _hang_supports(prop)
    return prop


def _hang_supports(prop):
    """Parent the `Support_<n>` columns under the `Canopy` node.

    The world unit looks for the parent of the support nodes to find the
    structure it has to collapse (game/world/build/gameplay_sites.gd).
    """
    from lib import common
    canopy = None
    for obj in prop.parts:
        if obj.name == "Canopy":
            canopy = obj
    if canopy is None:
        return
    for obj in prop.parts:
        if obj.name.startswith("Support_"):
            common.set_parent(obj, canopy)


BUILDERS = {"gas_station": gas_station}
