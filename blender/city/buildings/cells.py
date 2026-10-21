"""128 m cell grid: the world-space cells a tile is split into.

Godot measures a visibility range (HLOD) to the INSTANCE CENTRE, so a 512 m tile whose
origin sits in a corner switches to its far proxy while the player is still 40 m from the
buildings in the far corner.  Splitting into 128 m cells puts the centre close to the
geometry it owns, and every cell is positioned in WORLD coordinates (like the roads
unit) so the world loader can add it without an offset.

A cell holds ALL the faces of one building, not a face-centre bucket: the facade shader
computes its window grid from the object-space position, so a building whose faces were
split over two cells would show its window grid jumping in the middle of a wall.
"""
import math

from mathutils import Vector

CELL_M = 128.0


def cell_of(x, z, cell_m=CELL_M):
    """The (i, j) cell index of a world XZ position (city space)."""
    return int(math.floor(x / cell_m)), int(math.floor(z / cell_m))


def cell_centre_city(i, j, cell_m=CELL_M):
    """The world centre of a cell, in CITY space (x, z)."""
    return ((i + 0.5) * cell_m, (j + 0.5) * cell_m)


def cell_centre_blender(i, j, cell_m=CELL_M):
    """The world centre of a cell, in Blender coordinates (city z is negated)."""
    x, z = cell_centre_city(i, j, cell_m)
    return Vector((x, -z, 0.0))
