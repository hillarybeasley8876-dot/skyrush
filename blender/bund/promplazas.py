"""Bund plazas and set pieces (bund unit): the Financial Plaza bronze bull, Chen Yi Square
and the Meteorological Signal Tower."""
import math

from . import bull as bullmod
from . import data
from .promenade import box_at, frame_at


# The three squares of the dossier 5.1 (game Z): the Meteorological Signal Tower at the
# Yan'an Road end, the Bund Financial Plaza with the bull in the Fuzhou Road gap between
# No. 9 and No. 12, and Chen Yi Square opposite Nanjing East Road.
SIGNAL_TOWER_Z = -25.0
FINANCIAL_PLAZA_Z = -222.0
CHEN_YI_Z = -540.0


def build(asm, base):
    """The squares and the signal tower."""
    _bull(asm, base, target_z=FINANCIAL_PLAZA_Z)
    _chen_yi_square(asm, base, target_z=CHEN_YI_Z)
    _signal_tower(asm, base)


def _index_at(base, target_z):
    """The path index closest to a given game Z (the path is in Blender coordinates)."""
    best, bi = 1e9, 0
    want = -target_z
    for i, p in enumerate(base):
        d = abs(p[1] - want)
        if d < best:
            best, bi = d, i
    return bi


def _bull(asm, base, target_z):
    """A stylised bronze bull on a granite plinth (Bund Financial Plaza).

    Generic animal form - deliberately not a copy of the real sculpture. The plinth stands
    on the deck, so the animal is above the flood wall and reads from the river."""
    i = _index_at(base, target_z)
    p, right, rot = frame_at(base, i)
    x = data.OFF_DECK + 9.0
    cx = p[0] + right[0] * x
    cy = p[1] + right[1] * x
    ang = math.atan2(right[1], right[0]) + math.radians(-25.0)
    # the granite plinth, 0.55 m high, standing on the deck
    asm.box("granite", (cx, cy, data.DECK_Y + 0.275), (4.4, 2.6, 0.55), ang)
    asm.box("granite", (cx, cy, data.DECK_Y + 0.60), (3.8, 2.1, 0.12), ang)
    bullmod.build(asm.bm("bronze"), (cx, cy, data.DECK_Y + 0.66), ang)


def _chen_yi_square(asm, base, target_z):
    """A paved square with bollards and a flagpole."""
    i = _index_at(base, target_z)
    p, right, rot = frame_at(base, i)
    x = data.OFF_DECK + 7.0
    for k in range(4):
        box_at(asm, "granite", base, i, x + k * 4.0, data.DECK_Y, 22.0, 4.0, 0.06)
    for k in range(8):
        ang = k * math.pi / 4.0
        px = p[0] + right[0] * (x + 8.0) + math.cos(ang) * 9.0
        py = p[1] + right[1] * (x + 8.0) + math.sin(ang) * 9.0
        asm.lathe("iron", [(0.0, 0.0), (0.20, 0.0), (0.16, 0.85), (0.22, 0.95), (0.0, 1.0)],
                  8, (px, py, data.DECK_Y))
    # a tall flagpole
    fx = p[0] + right[0] * (x + 1.0)
    fy = p[1] + right[1] * (x + 1.0)
    asm.lathe("iron", [(0.0, 0.0), (0.30, 0.0), (0.16, 0.6), (0.10, 12.0), (0.0, 12.0)],
              8, (fx, fy, data.DECK_Y))


def _signal_tower(asm, base):
    """The Meteorological Signal Tower at Yan'an Road.

    A slim Art Deco tower: a stepped shaft with vertical fins, three platforms with their
    railings and the signal mast with its yard and the anemometer ball on top."""
    i = _index_at(base, SIGNAL_TOWER_Z)
    p, right, rot = frame_at(base, i)
    x = data.OFF_DECK + 2.5
    cx = p[0] + right[0] * x
    cy = p[1] + right[1] * x
    ang = math.atan2(right[1], right[0])
    z = data.DECK_Y
    # the stepped shaft
    for k, (zz, hh, w) in enumerate(((z + 0.6, 1.2, 7.0), (z + 6.0, 9.0, 5.4),
                                     (z + 13.0, 8.0, 5.0), (z + 21.0, 6.0, 4.6),
                                     (z + 27.0, 3.0, 4.0))):
        asm.box("granite", (cx, cy, zz), (w, w, hh), ang)
    # the Art Deco fins: vertical blades on the four faces
    for face in range(4):
        a = ang + face * math.pi * 0.5
        nx, ny = math.cos(a), math.sin(a)
        for k in range(7):
            t = (k - 3) * 0.62
            fx = cx + nx * 2.75 - math.sin(a) * t
            fy = cy + ny * 2.75 + math.cos(a) * t
            asm.box("granite", (fx, fy, z + 13.5), (0.30, 0.70, 15.0), ang)
    # the platforms and their railings
    for zz, w in ((z + 7.6, 6.6), (z + 16.6, 6.2), (z + 23.6, 5.8)):
        asm.box("granite", (cx, cy, zz), (w, w, 0.5), ang)
        for k in range(8):
            a = k * math.pi / 4.0
            asm.box("iron", (cx + math.cos(a) * w * 0.45, cy + math.sin(a) * w * 0.45,
                             zz + 0.75), (0.08, 0.08, 1.0), ang)
        asm.box("iron", (cx, cy, zz + 1.25), (w * 0.92, w * 0.92, 0.08), ang)
    # the signal mast with its yard and the ball
    asm.lathe("iron", [(0.0, 0.0), (0.22, 0.0), (0.14, 8.0), (0.0, 8.0)], 8, (cx, cy, z + 28.0))
    asm.box("iron", (cx, cy, z + 33.0), (2.6, 0.12, 0.12), ang)
    asm.lathe("iron", [(0.0, 0.0), (0.42, 0.0), (0.42, 0.5), (0.0, 0.5)], 10, (cx, cy, z + 35.4))
    asm.lathe("iron", [(0.0, 0.0), (0.30, 0.0), (0.30, 0.4), (0.0, 0.4)], 10,
              (cx + math.cos(ang) * 1.3, cy + math.sin(ang) * 1.3, z + 33.0))
