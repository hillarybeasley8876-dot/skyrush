"""Bund lighting data (bund unit).

Ground uplights every 5 m along each facade (1 m from the wall, 80 deg up, BUND_2500K) and
crown floods on the domes, towers, attics and pyramids, as Empties in the scene (CONTRACTS
§2: local +Y is the direction the effect points) plus the sidecar
game/assets/bund/bund_lights.json that the world unit pools into real Godot lights.

The crown floods stand on the roof behind the parapet, so the row reads as lit stone and
not as a row of visible lamps (见光不见灯, art dossier 1.2).
"""
import json
import math
import os

import bpy
from mathutils import Matrix, Vector

from lib import common

from . import data, elev

UPLIGHT_COLOR = (0xFF, 0x9F, 0x46)     # BUND_2500K
CROWN_COLOR = (0xFF, 0xCF, 0x87)       # gold lamps
UPLIGHT_ENERGY = 12.0
UPLIGHT_RANGE = 24.0
UPLIGHT_ANGLE = 45.0
CROWN_ENERGY = 18.0
CROWN_RANGE = 48.0
CROWN_ANGLE = 55.0
PITCH = math.radians(80.0)


def _basis(direction):
    """A rotation matrix whose local +Y points along `direction` (up stays +Z)."""
    y = Vector(direction).normalized()
    z = Vector((0.0, 0.0, 1.0))
    x = y.cross(z)
    if x.length < 1e-6:
        x = Vector((1.0, 0.0, 0.0))
    x.normalize()
    z = x.cross(y).normalized()
    return Matrix((x, y, z)).transposed().to_4x4()


def _add_empty(name, world_matrix, col):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "SINGLE_ARROW"
    obj.empty_display_size = 0.8
    obj.matrix_world = world_matrix
    common.link(obj, col)
    return obj


def uplights_of(s):
    """The ground uplights of one building: (name, local position, local direction)."""
    d = Vector((-math.cos(PITCH), 0.0, math.sin(PITCH)))
    out = []
    for i, (y, z) in enumerate(elev.uplight_layout(s)):
        out.append(("Uplight_%s_%02d" % (s["key"], i), Vector((1.0, y, z)), d))
    return out


def crown_lights_of(s):
    """The crown floods of one building: (name, local position, local direction)."""
    out = []
    for k, c in enumerate(s.get("crown", [])):
        pos = Vector(c["pos"])
        aim = Vector(c["aim"])
        out.append(("Crown_%s_%d" % (s["key"], k), pos, (aim - pos).normalized()))
    return out


def build(col):
    """Create the Uplight_* / Crown_* empties; returns the light records."""
    records = []
    for s in data.SPECS:
        parent = bpy.data.objects.get(s["node"])
        if parent is None:
            continue
        for name, pos, d in uplights_of(s) + crown_lights_of(s):
            local = Matrix.Translation(pos) @ _basis(d)
            world = parent.matrix_world @ local
            _add_empty(name, world, col)
            wpos = world.translation
            wdir = (world.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()
            crown = name.startswith("Crown_")
            records.append({
                "name": name, "type": "spot", "building": s["node"],
                "position": to_game((wpos.x, wpos.y, wpos.z)),
                "direction": to_game((wdir.x, wdir.y, wdir.z)),
                "color": _rgb(CROWN_COLOR if crown else UPLIGHT_COLOR),
                "energy": CROWN_ENERGY if crown else UPLIGHT_ENERGY,
                "range": CROWN_RANGE if crown else UPLIGHT_RANGE,
                "angle": CROWN_ANGLE if crown else UPLIGHT_ANGLE,
            })
    return records


def _rgb(hexcol):
    return [round(hexcol[0] / 255.0, 4), round(hexcol[1] / 255.0, 4), round(hexcol[2] / 255.0, 4)]


def to_game(v):
    """A Blender vector (x, y=along the row, z=up) in game axes (x east, y up, z south)."""
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def write_json(path, records, deck_lamps=()):
    """Write the light sidecar the world unit reads (game axes).

    `deck_lamps` are the promenade lanterns: the preview puts its soft deck lights on
    them, so the paving is lit where the lanterns actually stand.

    The sidecar also carries the two lines the preview needs to stand the road and the
    river in the right place: the centreline of the Bund road and the river face of the
    flood wall (dossier 5.2)."""
    payload = {"unit": "bund",
               "deck_lamps": [{"position": to_game(l)} for l in deck_lamps],
               "road": [[round(x, 3), round(z, 3)] for (x, z) in data.ROAD_PATH],
               "river": [[round(x, 3), round(z, 3)] for (x, z) in data.river_path(-30, -1080)],
               "uplight": {"color": _rgb(UPLIGHT_COLOR), "energy": UPLIGHT_ENERGY,
                           "range": UPLIGHT_RANGE, "angle": UPLIGHT_ANGLE},
               "crown": {"color": _rgb(CROWN_COLOR), "energy": CROWN_ENERGY,
                         "range": CROWN_RANGE, "angle": CROWN_ANGLE},
               "portico": {s["node"]: s.get("portico_bays", []) for s in data.SPECS
                           if s.get("portico_bays")},
               "lights": records}
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        json.dump(payload, fh, indent=1, sort_keys=True)
    print("WROTE %s (%d lights)" % (path, len(records)))
    return path
