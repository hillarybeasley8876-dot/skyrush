"""Bund data: the building table of ref/shanghai/SHANGHAI_DOSSIER.md §5.3, the Bund road
centreline (§5.2). The palette tokens live in ao.HUE.

Coordinates: Blender Z up, +Y south == game Z south, +X east == game X east (CONTRACTS §1).
Building `front_x` is the x of the facade centre; `z` is the facade-centre game Z.
"""
import math

# ---------------------------------------------------------------- road / river line
# bund_zhongshan_e1 centreline, dossier §5.2 (game X, Z).
ROAD_PATH = [
    (4.2, -10.2), (-111.3, -245.7), (-145.3, -524.4), (-135.2, -628.1),
    (-128.3, -707.2), (-153.0, -839.8), (-147.6, -914.4),
]

# Cross-section offsets from the road centreline, dossier §5.2 (metres, east = +X).
OFF_KERB = 10.0          # kerb (road half width)
OFF_LAWN = 17.5          # end of the lawn / foot of the stairs
OFF_DECK = 21.0          # promenade deck inner edge
OFF_BALUSTRADE = 49.0    # flood wall river face (the balustrade line)
DECK_Y = 2.5             # promenade deck level
WATER_Y = -3.0           # river surface
WALL_TOE = -6.0          # bottom of the flood wall
BALCONIES = 32           # semicircular viewing balconies
LANTERNS = 64            # palace lanterns (宫灯)
LAMP_COLUMNS = 8         # granite art lamp columns
PLANTERS = 21            # bowl planters

# ---------------------------------------------------------------- named constants
# Which generated map each dossier facade colour uses (the hue itself lives in ao.HUE).
STONE_FAMILY = {
    "granite": "granite", "granite_grey": "granite", "granite_dark": "granite",
    "granite_light": "granite", "granite_pale": "granite", "granite_warm": "granite",
    "cream": "granite", "white": "granite", "pearl": "granite",
    "tile_white": "tile", "brick_red": "brick", "coffee": "coffee",
}

LIT_FRACTION = 0.25           # the share of lit windows on a facade
SIDE_LIT_FRACTION = 0.16      # the share of lit windows on a side elevation
ATTIC_LIT_FRACTION = 0.22     # the share of lit windows in an attic storey

BASE_COURSE_H = 0.85          # the height of a rusticated course
BASE_PROJ_A = 0.45            # the projection of the lower course
BASE_PROJ_B = 0.36            # the projection of the upper course (the V-groove)
BASE_V_GROOVE = 0.15          # the width of the V-groove between the blocks
BASE_V_DEPTH = 0.09           # the depth of the V-groove

WIN_W = 1.45                  # the classical window width
WIN_H = 2.60                  # the classical window height
WIN_SILL = 0.90               # the sill above the floor
WIN_RECESS = 0.30             # the glass behind the wall face
MULLION = 0.06                # the dark bronze glazing bars

COL_RATIO = {"ionic": 9.0, "doric": 8.0, "corinthian": 10.0}   # the height / diameter
UPLIGHT_EVERY = 5.0               # the spacing of the ground uplights
FLUTES = 24                   # the flutes on a classical shaft

CORNICE_PROJ_BIG = 1.25       # the main cornice projection
CORNICE_PROJ_SMALL = 0.75
CORNICE_H_BIG = 1.55
CORNICE_H_SMALL = 1.0
CORNICE_BIG_ABOVE = 25.0      # the cornice height that decides big vs small
PORTICO_OFFSET = 3.2          # how far the colonnade stands off the facade
JAMB = 0.26                  # the width of a window surround jamb
SETBACK_LIT_FRACTION = 0.30  # the share of lit windows on a Broadway Mansions stage

# ---------------------------------------------------------------- the 25 buildings
# (no, key, name, z, front_x, frontage, depth, height, cornice_h, floors,
#  style, roof, colour, opts)
#   height  : real height in m (dome / tower / pyramid top included)
#   cornice : height of the main cornice (the top of the principal block)
#   floors  : number of storeys above the rusticated base
B = lambda *a: a
BUILDINGS = [
    B(1, "Asia", "Asia Bldg", -32, -22.5, 38, 40, 31, 28.0, 6,
      "baroque", "attic_pediment", "granite_grey", {"attic": 3.0}),
    B(2, "ShanghaiClub", "Shanghai Club", -59, -35.7, 27, 40, 30, 27.0, 6,
      "classic", "cupolas", "cream", {"cupolas": 2}),
    B(3, "Union", "Union Bldg", -91, -51.4, 38, 38, 30, 27.0, 6,
      "renaissance", "attic_flat", "granite_dark", {}),
    B(5, "Nisshin", "Nisshin Bldg", -120, -65.7, 22, 30, 28, 25.0, 6,
      "jwest", "flat", "granite_grey", {}),
    B(6, "CommBankChina", "Commercial Bank of China", -140, -75.5, 21, 25, 20, 15.5, 3,
      "gothic", "gables", "brick_red", {"bands": "white", "balcony": True}),
    B(7, "GreatNorthern", "Great Northern Telegraph", -181, -95.6, 19, 25, 22, 19.5, 4,
      "renaissance", "dome_small", "white", {}),
    B(9, "ChinaMerchants", "China Merchants Steamship", -207, -108.3, 17, 22, 20, 17.5, 4,
      "renaissance", "flat", "brick_red", {"bands": "white"}),
    B(12, "HSBC", "HSBC Building", -268, -130.0, 76, 70, 50, 32.0, 6,
      "neoclassic", "dome_drum", "granite_light",
      {"portico": 6, "columns": "ionic", "attic": 4.0, "balustrade": True, "bays": 13}),
    B(13, "CustomsHouse", "Customs House", -328, -137.3, 42, 60, 79.2, 36.2, 5,
      "neoclassic", "clock_tower", "granite_light",
      {"tower": True, "bays": 7, "pilasters": True}),
    B(14, "BankComm", "Bank of Communications", -366, -142.0, 34, 40, 36, 33.0, 8,
      "deco", "deco_fins", "granite_pale", {"setback": 0.0, "bays": 8}),
    B(15, "RussoChinese", "Russo-Chinese Bank", -418, -148.3, 34, 35, 20, 17.0, 3,
      "classic", "flat", "tile_white", {"columns": "doric", "col_bays": 6}),
    B(16, "BankTaiwan", "Bank of Taiwan", -447, -151.9, 20, 30, 22, 18.5, 4,
      "neoclassic", "flat", "granite", {"columns": "ionic", "col_bays": 4}),
    B(17, "NorthChinaDaily", "North China Daily News", -465, -154.1, 26, 35, 40, 36.0, 9,
      "classic", "towers2", "granite", {"towers": 2}),
    B(18, "Bund18", "Chartered Bank", -488, -156.9, 26, 40, 26, 23.0, 6,
      "renaissance", "flat", "granite", {"columns": "ionic", "col_bays": 2}),
    B(19, "PalaceHotel", "Palace Hotel", -518, -160.5, 30, 75, 30, 27.0, 6,
      "renaissance", "flat", "tile_white", {"bands": "brick_band", "arched": True}),
    B(20, "SassoonHouse", "Sassoon House", -569, -157.0, 42, 90, 77, 45.0, 13,
      "deco", "pyramid", "granite_warm", {"pyramid": 19.0, "tower_h": 13.0, "bays": 9}),
    B(23, "BankOfChina", "Bank of China", -600, -153.9, 24, 60, 77, 68.0, 15,
      "deco", "chinese_hip", "granite_warm", {"chinese_roof": 7.0, "bays": 5}),
    B(24, "YokohamaSpecie", "Yokohama Specie Bank", -628, -151.2, 34, 45, 30, 26.0, 6,
      "neoclassic", "flat", "granite", {"columns": "ionic", "col_bays": 6}),
    B(26, "Yangtze", "Yangtze Insurance", -655, -148.9, 18, 25, 30, 27.0, 6,
      "eclectic", "flat", "granite", {}),
    B(27, "Jardine", "Jardine Matheson", -683, -146.4, 34, 45, 32, 28.0, 8,
      "renaissance", "flat", "granite", {"rough_base": True}),
    B(28, "GlenLine", "Glen Line Building", -720, -146.7, 24, 30, 27.5, 24.0, 7,
      "renaissance", "flat", "granite", {"balcony": True, "quartz": True}),
    B(29, "Indochine", "Banque de l'Indochine", -744, -151.2, 20, 25, 18, 15.5, 3,
      "baroque", "flat", "white", {"arched": True}),
    B(33, "BritishConsulate", "British Consulate", -808, -163.1, 30, 20, 12, 9.0, 2,
      "colonial", "hip_low", "brick_red", {"bands": "white", "veranda": True}),
    B(32, "Peninsula", "The Peninsula", -837, -168.5, 40, 50, 60, 56.0, 14,
      "deco_modern", "flat", "pearl", {"bays": 9}),
    B(0, "BroadwayMansions", "Broadway Mansions", -1051, -156.0, 60, 40, 77, 40.0, 21,
      "deco", "ziggurat", "coffee", {"setback": 11, "bays": 10, "red_base": True}),
]
assert len(BUILDINGS) == 25, len(BUILDINGS)

_KEYS = ("no", "key", "name", "z", "front_x", "frontage", "depth", "height", "cornice",
         "floors", "style", "roof", "colour", "opts")


def as_dict(b):
    """Turn a BUILDINGS row into a dict with the derived storey geometry."""
    d = dict(zip(_KEYS, b))
    d["opts"] = dict(d["opts"] or {})
    d["base_h"] = min(5.0, max(3.6, d["cornice"] * 0.17)) if d["floors"] >= 5 else 3.8
    d["floor_h"] = max(3.1, min(5.2, (d["cornice"] - d["base_h"]) / max(1, d["floors"])))
    d["bays"] = d["opts"].get("bays") or max(3, int(round(d["frontage"] / 4.2)))
    d["node"] = "Bund_%d_%s" % (d["no"], d["key"])
    d["stone_family"] = STONE_FAMILY.get(d["colour"], "granite")
    return d


SPECS = [as_dict(b) for b in BUILDINGS]


def _resolve_overlaps(specs):
    """The dossier compresses frontages (x0.85) but not the positions, so a few neighbours
    would interpenetrate. Share the overlap between the two buildings so the row stays
    contiguous without any geometry crossing a neighbour's wall."""
    for a, b in zip(specs, specs[1:]):
        dist = abs(a["z"] - b["z"])
        hw_a, hw_b = a["frontage"] * 0.5, b["frontage"] * 0.5
        over = hw_a + hw_b - dist
        if over <= 0.01:
            continue
        share = hw_a / max(1e-6, hw_a + hw_b)
        a["frontage"] = max(6.0, a["frontage"] - 2.0 * over * share)
        b["frontage"] = max(6.0, b["frontage"] - 2.0 * over * (1.0 - share))
    for s in specs:
        s["bays"] = s["opts"].get("bays") or max(3, int(round(s["frontage"] / 4.2)))
    return specs


_resolve_overlaps(SPECS)


# ---------------------------------------------------------------- path helpers
def _seg_tangents(path):
    """Unit tangent (x, z) of every segment of a polyline."""
    out = []
    for a, b in zip(path, path[1:]):
        dx, dz = b[0] - a[0], b[1] - a[1]
        n = math.hypot(dx, dz)
        out.append((dx / n, dz / n))
    return out


def road_point(z):
    """Point on the road centreline at game Z `z` (linear interpolation along the polyline)."""
    for a, b in zip(ROAD_PATH, ROAD_PATH[1:]):
        if a[1] >= z >= b[1]:
            t = (a[1] - z) / (a[1] - b[1])
            return (a[0] + t * (b[0] - a[0]), z)
    # north of the surveyed polyline: continue along the last tangent
    a, b = ROAD_PATH[-2], ROAD_PATH[-1]
    tx, tz = _seg_tangents(ROAD_PATH)[-1]
    d = (z - b[1]) / tz
    return (b[0] + tx * d, z)


def road_tangent(z):
    """Unit tangent of the road at game Z `z`, pointing NORTH (towards -Z).

    The polyline is ordered south -> north, so the segment direction already points north."""
    for a, b in zip(ROAD_PATH, ROAD_PATH[1:]):
        if a[1] >= z >= b[1]:
            dx, dz = b[0] - a[0], b[1] - a[1]
            n = math.hypot(dx, dz)
            return (dx / n, dz / n)
    a, b = ROAD_PATH[-2], ROAD_PATH[-1]
    tx, tz = _seg_tangents(ROAD_PATH)[-1]
    return (tx, tz)


def facade_yaw(z):
    """Yaw (radians) of a building in the BLENDER frame: the facade normal (local +X) points
    east, local +Y runs south along the row.

    The glTF exporter maps Blender +Y to Godot -Z, so the Blender Y of a game Z is -Z."""
    tx, tz = road_tangent(z)                   # game space, pointing north
    nb = (-tz, -tx)                            # the east normal in Blender coordinates
    return math.atan2(nb[1], nb[0])


def to_blender(x, z):
    """A game (X, Z) point in Blender coordinates (Y = -Z)."""
    return (x, -z)


def river_path(z0, z1, step=6.0):
    """Polyline of the river edge (the balustrade line) from z0 to z1 (south -> north)."""
    pts, z = [], z0
    while z >= z1:
        x, _ = road_point(z)
        tx, tz = road_tangent(z)
        nx, nz = -tz, tx
        pts.append((x + nx * OFF_BALUSTRADE, z + nz * OFF_BALUSTRADE))
        z -= step
    return pts
