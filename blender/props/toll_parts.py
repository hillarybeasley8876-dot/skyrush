"""The heavy parts of the toll plaza (unit: props): the pavement, the toll
booth and the crash cushion of an island nose.

Dossier §7.2 and art dossier §4.10: the booth is glazed on all four sides
with a door, a roof overhang and a lit ceiling panel; the cushion is a
segmented yellow block with black 45 degree stripes and bolted end plates.

These three live in their own module so `toll.py` stays readable.
"""
import math

import bmesh
from mathutils import Euler, Vector

from lib import geo

from . import atlas, kit, materials as M

KERB_H = 0.25
BOOTH_W = 1.80
BOOTH_D = 3.00
BOOTH_H = 2.80
BOOTH_X = 0.0

WHITE = "white_paint"
RED = "red_paint"
DARK = "steel_dark"
YELLOW = "yellow"
GALV = "galv"

# the cushion of an island nose (dossier §7.1)
CUSHION_SEGS = 4
CUSHION_LEN = 2.50
CUSHION_W = 0.90
CUSHION_H = 0.80
CUSHION_X = -13.60


ARROW_UV = atlas.ARROW_UV
ETC_UV = atlas.ETC_UV


def _box(bm, center, size, rot=(0.0, 0.0, 0.0)):
    """A box with any rotation, added to a bmesh (the core geo.box is Z only)."""
    res = bmesh.ops.create_cube(bm, size=1.0)
    mat = Euler(rot, "XYZ").to_matrix().to_4x4()
    for v in res["verts"]:
        local = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        v.co = Vector(center) + (mat @ local)
    return res["verts"]


def pavement(p, canopy_depth, canopy_y, lanes):
    """The concrete plaza: a joint grid, tyre-polish paths, oil drips and paint.

    The joints are 20 mm sealant lines (not 10 cm black stripes), the lanes
    that the traffic uses are polished by the tyres, and the islands stand on
    oil-stained patches.
    """
    p.box("Apron", (0.0, 0.0, -0.09), (canopy_depth + 140.0, 2 * canopy_y + 120.0, 0.10),
          M.surface(), surface="asphalt")
    p.box("Plaza", (0.0, 0.0, -0.04), (canopy_depth + 60.0, 2 * canopy_y, 0.08),
          M.surface(), surface="pavement")
    joints = []
    for x in range(-60, 61, 4):
        joints.append((0.02, 2 * canopy_y, (float(x), 0.0, 0.005), kit.FLAT))
    for y in range(-56, 57, 4):
        joints.append((canopy_depth + 60.0, 0.02, (0.0, float(y), 0.005), kit.FLAT))
    p.quads("Joints", joints, M.surface(), surface="stain")
    # the polished lanes: the tyres rub the concrete shiny
    for i, (lane_y, _island, _side, _dir) in enumerate(lanes):
        p.quad("Polish_%d" % (i + 1), 26.0, 2.40, M.surface(),
               (-2.0, lane_y, 0.006), rot=kit.FLAT, surface="polish")
    # oil drips on the lane in front of every island
    for i, (lane_y, island_y, _side, _dir) in enumerate(lanes):
        p.quad("Oil_%d" % (i + 1), 3.20, 1.60, M.surface(),
               (-9.0, (lane_y + island_y) * 0.5, 0.008), rot=kit.FLAT, surface="stain")
    # the lane arrows and the ETC paint in front of the islands: real markings
    # (an alpha cut-out sheet), not white rectangles
    marks = bmesh.new()
    for i, (lane_y, _island, _side, _dir) in enumerate(lanes):
        kit.add_quad(marks, 1.40, 3.00, (-19.0, lane_y, 0.008), kit.FLAT, ARROW_UV)
    for i in range(0, len(lanes), 3):
        lane_y = lanes[i][0]
        kit.add_quad(marks, 1.60, 0.75, (-16.0, lane_y, 0.008), kit.FLAT, ETC_UV)
    p.mesh("LaneMarks", marks, M.road_marks(), box_map=False)


def booth(p, n, by, direction):
    """A toll booth: a white cabin glazed on all four sides, with a door.

    The glazing is the upper 1.4 m of the cabin, with mullions on every
    side; the roof overhangs with a red band and carries an air-conditioning
    unit, and a lit ceiling panel shows through the glass.
    """
    wx = -direction * (BOOTH_D * 0.5 + 0.03)      # the window faces the driver
    sill = 1.40
    head = 2.80
    p.box("Booth_%d" % n, (BOOTH_X, by, sill * 0.5), (BOOTH_D, BOOTH_W, sill),
          M.surface(), bevel=0.04, surface=WHITE)
    # four corner posts and the glazing between them
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box("BoothPost_%d_%d_%d" % (n, sx, sy),
                  (BOOTH_X + sx * (BOOTH_D * 0.5 - 0.06),
                   by + sy * (BOOTH_W * 0.5 - 0.06), (sill + head) * 0.5),
                  (0.12, 0.12, head - sill), M.surface(), surface=WHITE)
    glass_h = head - sill - 0.16
    glass_z = sill + (head - sill) * 0.5
    p.box("BoothGlassX_%d" % n, (wx - direction * 0.02, by, glass_z),
          (0.05, BOOTH_W - 0.20, glass_h), M.glass())
    p.box("BoothGlassY_%d" % n, (BOOTH_X, by - (BOOTH_W * 0.5 - 0.03), glass_z),
          (BOOTH_D - 0.20, 0.05, glass_h), M.glass())
    p.box("BoothGlassY2_%d" % n, (BOOTH_X, by + (BOOTH_W * 0.5 - 0.03), glass_z),
          (BOOTH_D - 0.20, 0.05, glass_h), M.glass())
    p.box("BoothGlassX2_%d" % n, (BOOTH_X + direction * (BOOTH_D * 0.5 - 0.03), by,
                                  glass_z),
          (0.05, BOOTH_W - 0.20, glass_h), M.glass())
    # the mullions: three per long side, one per short side
    for k in range(3):
        p.box("BoothMullion_%d_%d" % (n, k),
              (wx - direction * 0.04, by - 1.20 + k * 0.80, glass_z),
              (0.05, 0.06, glass_h), M.surface(), surface=DARK)
    for sy in (-1, 1):
        p.box("BoothMullionY_%d_%d" % (n, sy),
              (BOOTH_X, by + sy * (BOOTH_W * 0.5 - 0.06), glass_z),
              (0.06, 0.05, glass_h), M.surface(), surface=DARK)
    # the door on the back side of the cabin
    p.box("BoothDoor_%d" % n, (BOOTH_X + direction * (BOOTH_D * 0.5 + 0.01), by, 1.05),
          (0.05, 0.80, 2.00), M.surface(), bevel=0.02, surface=DARK)
    p.cyl("BoothHandle_%d" % n,
          (BOOTH_X + direction * (BOOTH_D * 0.5 + 0.06), by - 0.28, 1.05), 0.02, 0.30,
          M.surface(), segments=6, surface=GALV)
    # the roof: an overhang with the red band, and an air-conditioning unit
    p.box("BoothRoof_%d" % n, (BOOTH_X, by, head + 0.09),
          (BOOTH_D + 0.36, BOOTH_W + 0.36, 0.18), M.surface(), bevel=0.03, surface=WHITE)
    p.box("BoothRoofBand_%d" % n, (BOOTH_X, by - (BOOTH_W * 0.5 + 0.17), head + 0.02),
          (BOOTH_D + 0.36, 0.04, 0.22), M.surface(), surface=RED)
    p.box("BoothAC_%d" % n, (BOOTH_X - 0.55, by + 0.30, head + 0.36),
          (0.70, 0.50, 0.36), M.surface(), bevel=0.03, surface=GALV)
    p.cyl("BoothACFan_%d" % n, (BOOTH_X - 0.55, by + 0.30, head + 0.55), 0.20, 0.04,
          M.surface(), segments=14, surface=DARK)
    # the lit ceiling panel of the cabin, seen through the glass
    p.quad("BoothInterior_%d" % n, 1.10, 0.80, M.sign_lit(),
           (wx + direction * 0.90, by, 1.30),
           rot=(0.0, 0.0, -math.pi / 2.0 * direction), board="warm_led")


def cushion(p, n, iy):
    """The crash cushion on the nose of an island.

    Four yellow segments with black 45 degree stripes, bolted end plates and
    a reflective chevron on the face that meets the traffic.
    """
    yellow = bmesh.new()
    black = bmesh.new()
    white = bmesh.new()
    base = 0.30
    step = CUSHION_LEN / CUSHION_SEGS
    for k in range(CUSHION_SEGS):
        x = CUSHION_X - CUSHION_LEN * 0.5 + (k + 0.5) * step
        geo.box(yellow, (x, iy, base + CUSHION_H * 0.5),
                (step - 0.04, CUSHION_W, CUSHION_H))
    # the black 45 degree stripes on both long faces
    for sy in (-1, 1):
        for k in range(3):
            x = CUSHION_X - CUSHION_LEN * 0.5 + (k + 0.5) * step
            _box(black, (x, iy + sy * (CUSHION_W * 0.5 + 0.012), base + CUSHION_H * 0.5),
                 (0.80, 0.03, 0.20), (0.0, sy * math.pi / 4.0, 0.0))
    # the bolted end plates
    for sx in (-1, 1):
        x = CUSHION_X + sx * (CUSHION_LEN * 0.5 + 0.03)
        geo.box(black, (x, iy, base + CUSHION_H * 0.5),
                (0.06, CUSHION_W + 0.04, CUSHION_H))
        for sy in (-1, 1):
            geo.cylinder(black, (x + sx * 0.05, iy + sy * 0.28, base + CUSHION_H * 0.5),
                         0.03, 0.10, segments=6, axis="X")
    # the reflective chevron on the face that meets the traffic
    face = CUSHION_X - CUSHION_LEN * 0.5 - 0.05
    for sy in (-1, 1):
        _box(white, (face, iy + sy * 0.20, base + CUSHION_H * 0.42),
             (0.03, 0.62, 0.14), (sy * 0.72, 0.0, 0.0))
    p.mesh("Cushion_%d" % n, yellow, M.surface(), surface=YELLOW)
    p.mesh("CushionTrim_%d" % n, black, M.surface(), surface="black_plastic")
    p.mesh("CushionChevron_%d" % n, white, M.surface(), surface="bay_line")
