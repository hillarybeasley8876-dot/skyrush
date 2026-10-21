"""The wing's parts: slat, end plates and struts (dossier §8.2, review r3 #4).

Every size comes from the JSON `parts.wing`; nothing is retyped. The parts are
built in the WING'S LOCAL SPACE (the wing's origin is the main element's
leading edge) and are children of `Wing`, so they follow the wing when the
vehicle unit pitches it.

Deploy contract (also in the README and in the `deploy_contract` property of
`Wing`): the game rotates the `Wing` about its local X by **-pitch_deg** (the
JSON's positive pitch lifts the trailing edge: the air_brake pose puts the
trailing edge at z 1.36, above the leading edge) and sets the local scale of
`Wing_Slat`, `Wing_Strut_L/R` and `Wing_EndPlate_L/R` from 0.001 (stowed, as
exported) to 1.0 (deployed). The parts are built at their full deployed size
and collapsed to a point in the stowed pose, so the stowed car keeps its
1.147 m height and shows no carbon on the deck.
"""
import math

import bmesh
from mathutils import Matrix, Vector

from car import materials, paths, shapes
from lib import common

COLLAPSED = 0.001        # the stowed local Z scale of the slat / struts / plates

# the construction offsets (named, so nothing is a magic number)
SLAT_LE_OFFSET = 0.02    # the slat starts 20 mm behind the leading edge
SLAT_DECK_CLEAR = 0.006  # and stands 6 mm above the deck when it is deployed
SLAT_T = 0.005           # the slat is a 5 mm carbon plate
PLATE_T = 0.006          # the end plates are 6 mm carbon plates
PLATE_BEVEL = 0.001      # with a 1 mm chamfer
STRUT_MOUNT_DROP = 0.11  # the deck mount is 110 mm under the leading edge
STRUT_ROOT_Y = 0.10      # the root of the swan neck is 100 mm behind the LE
STRUT_MID_Y = 0.05       # the neck leans forward to 50 mm
STRUT_MID_RISE = 0.06    # and rises 60 mm
STRUT_TOP_DROP = 0.004   # the head stops 4 mm under the wing's surface
STRUT_W = 0.020          # the swan neck is 20 mm wide
STRUT_H = 0.040          # and 40 mm deep


def build(col, wing, data):
    """Build the five wing parts and parent them to `wing`."""
    half = float(data["main_span_half"])
    chord = float(data["chord_total"])
    slat_chord = float(data["slat_chord"])
    strut_x = float(data["struts_x"])
    bottom_z = float(data["endplate_bottom_z"])
    cant = math.radians(float(data["endplate_cant_deg"]))
    le = data["poses"]["stowed"]["le"]
    origin = Vector(wing.matrix_world.translation)
    _slat(col, wing, origin, half - 0.01, slat_chord)
    for sign, tag in ((1, "R"), (-1, "L")):
        _endplate(col, wing, origin, sign, half, chord, bottom_z, le, cant)
        _strut(col, wing, origin, sign, strut_x, le)


def _to_world(bm, origin):
    """Move the geometry from the wing's local space into the world.

    The parts are built around the wing's origin (the main element's leading
    edge) and then moved into the world, so that the pivot can be set with the
    usual world-space helper.
    """
    bmesh.ops.translate(bm, verts=list(bm.verts), vec=Vector(origin))
    return bm


def _slat(col, wing, origin, span, chord):
    """The leading-edge slat: a thin plate over the main element's front edge.

    It is built in the wing's local space and collapsed in the stowed pose, so
    it does not lie on the deck as a black band (review r3 #4).
    """
    bm = bmesh.new()
    y0 = SLAT_LE_OFFSET
    y1 = y0 - chord
    z = SLAT_DECK_CLEAR
    quad = [(-span, y0, z), (span, y0, z), (span, y1, z), (-span, y1, z)]
    low = [(x, y, zz - SLAT_T) for x, y, zz in quad]
    for pts in (quad, low):
        vs = [bm.verts.new(p) for p in pts]
        bm.faces.new(vs)
    for i in range(4):
        a = quad[i]
        b = quad[(i + 1) % 4]
        c = low[(i + 1) % 4]
        d = low[i]
        bm.faces.new([bm.verts.new(p) for p in (a, b, c, d)])
    _to_world(bm, origin)
    ob = common.mesh_object("Wing_Slat", bm, col)
    ob.data.materials.append(materials.get("M_Carbon"))
    _attach(ob, wing, (origin.x, origin.y, origin.z))
    ob.scale = (COLLAPSED, COLLAPSED, COLLAPSED)


def _endplate(col, wing, origin, sign, half, chord, bottom_z, le, cant):
    """A canted 6 mm carbon end plate hanging below the main element.

    The plate is built from the wing's OWN leading edge: the chord runs
    `chord_total` behind it and the plate hangs to `endplate_bottom_z`. The
    geometry is in the wing's local space, so the plate follows the wing when
    it is pitched (the old build placed it in world space, which threw it
    under the floor as soon as the contract was applied).
    """
    height = le[1] - bottom_z
    rot = Matrix.Rotation(sign * cant, 3, "Y")
    outline = [(0.0, 0.0), (-chord, 0.0), (-chord, -height), (0.0, -height)]
    pts = []
    for dy, dz in outline:
        p = rot @ Vector((0.0, dy, dz))
        # the plate stands at the end of the span, in the wing's local space
        pts.append((p.x + sign * half, p.y, p.z))
    bm = bmesh.new()
    _solid_plate(bm, pts, PLATE_T)
    _to_world(bm, origin)
    ob = common.mesh_object("Wing_EndPlate_%s" % ("R" if sign > 0 else "L"), bm, col)
    ob.data.materials.append(materials.get("M_Carbon"))
    _attach(ob, wing, (origin.x + sign * half, origin.y, origin.z))
    ob.scale = (COLLAPSED, COLLAPSED, COLLAPSED)
    common.bevel(ob, width=PLATE_BEVEL, segments=1, angle_deg=25.0)


def _solid_plate(bm, pts, thickness):
    """A flat plate of `thickness` from four coplanar points (in the YZ plane)."""
    t = thickness / 2.0
    front = [bm.verts.new((x, y, z)) for x, y, z in pts]
    back = [bm.verts.new((x + t, y, z)) for x, y, z in pts]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((front[i], back[i], back[j], front[j]))


def _strut(col, wing, origin, sign, strut_x, le):
    """A swan-neck strut from the deck mount up to the main element.

    The section is 20 x 40 mm (the review asks for at least that), and the
    neck leans forward before it reaches the wing.
    """
    bm = bmesh.new()
    z0 = le[1] - STRUT_MOUNT_DROP              # the deck mount, just under the wing
    # the path is in the strut's local space (the origin is the deck mount)
    x = sign * strut_x
    # the path is in the wing's local space (the origin is the leading edge)
    path = [(x, STRUT_ROOT_Y, -STRUT_MOUNT_DROP),
            (x, STRUT_MID_Y, -STRUT_MOUNT_DROP + STRUT_MID_RISE),
            (x, -0.02, -STRUT_TOP_DROP)]
    section = [(-STRUT_W / 2.0, -STRUT_H / 2.0), (STRUT_W / 2.0, -STRUT_H / 2.0),
               (STRUT_W / 2.0, STRUT_H / 2.0), (-STRUT_W / 2.0, STRUT_H / 2.0)]
    shapes.sweep_profile(bm, section, path, 0, up=(1.0, 0.0, 0.0))
    _to_world(bm, origin)
    ob = common.mesh_object("Wing_Strut_%s" % ("R" if sign > 0 else "L"), bm, col)
    ob.data.materials.append(materials.get("M_Carbon"))
    _attach(ob, wing, (origin.x + sign * strut_x, origin.y + STRUT_ROOT_Y, z0))
    ob.scale = (COLLAPSED, COLLAPSED, COLLAPSED)


def _attach(ob, wing, pivot):
    """Put the origin at `pivot` (world) and parent it to the wing."""
    common.set_origin(ob, pivot)
    paths.parent_to(ob, wing)
