"""Stage 2 of the hero car: the wheels, the body and the detachable parts, in the game frame.

Every function takes the `Concept` (world-space copies of the concept's meshes, already in the
game frame) and the materials, and returns the finished objects by their contract names.
"""
import math

import bpy
from mathutils import Matrix, Vector

import hero_materials
import meshkit

# decimation ratios (collapse): the numbers were tuned against the previews, see README
RIM_RATIO = 0.34
CALIPER_RATIO = 0.22
PILLAR_RATIO = 0.5
REAR_RATIO = 0.4
FRONT_RATIO = 0.4
PANEL_RATIO = 0.4
HOOD_RATIO = 0.36
GRILL_RATIO = 0.3
ROOF_RATIO = 0.3
DOOR_RATIO = 0.5
MIRROR_RATIO = 0.5
GLASS_RATIO = 0.35
SEAT_RATIO = 0.22
CALIPER_ANGLE = 25.0  # degrees above the horizontal, behind the axle


def _swap(ob, mats):
    hero_materials.remap(ob, mats)


def _decimated(ob, ratio):
    """Collapse decimation. No symmetry option: the concept is not exactly symmetric and the
    symmetric collapse tears holes along the creases."""
    meshkit.decimate(ob, ratio)
    return ob


# ---------------------------------------------------------------------------------------------
# wheels
# ---------------------------------------------------------------------------------------------

# the wheel centres the car gets: the concept's own numbers, made symmetric (the measured ones
# differ by a few millimetres from side to side)
TRACK_FRONT = 0.976
TRACK_REAR = 0.982
HALF_BASE = 1.40
TYRE_RADIUS = 0.384


def wheel_centre(tyre, key):
    """(centre, radius) of a wheel: measured on the tyre, snapped to the symmetric layout."""
    lo, hi = meshkit.bounds(tyre)
    radius = TYRE_RADIUS
    measured = Vector(((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, (hi.z - lo.z) * 0.5))
    side = -1.0 if key[1] == "L" else 1.0
    track = TRACK_FRONT if key[0] == "F" else TRACK_REAR
    snapped = Vector((side * track, HALF_BASE if key[0] == "F" else -HALF_BASE, radius))
    return measured, snapped, radius


def build_wheels(concept, mats):
    """Wheel_xx (tyre + rim + disc, origin at the wheel centre, spin axis X) and Caliper_xx."""
    out = {}
    info = {}
    for key in ("FL", "FR", "RL", "RR"):
        parts = concept.wheel_parts(key)
        measured, centre, radius = wheel_centre(parts["tyre"], key)
        info[key] = {"centre": centre, "radius": radius}
        shift = Matrix.Translation(-measured)
        for ob in parts.values():
            meshkit.transform(ob, shift)
        # the caliper: put it behind the axle, above the horizontal, whatever the pose it had
        pad = parts["pad"]
        c = meshkit.centre_of(pad)
        target = math.pi - math.radians(CALIPER_ANGLE)
        meshkit.transform(pad, Matrix.Rotation(target - math.atan2(c.z, c.y), 4, "X"))
        _swap(pad, mats)
        _decimated(pad, CALIPER_RATIO)
        meshkit.tidy(pad, 40.0)
        pad.name = "Caliper_" + key
        pad.location = centre
        out[pad.name] = pad
        # the wheel
        _swap(parts["tyre"], mats)
        _swap(parts["rim"], mats)
        _swap(parts["disc"], mats)
        _decimated(parts["rim"], RIM_RATIO)
        wheel = meshkit.join([parts["rim"], parts["tyre"], parts["disc"]], "Wheel_" + key)
        meshkit.tidy(wheel, 38.0)
        wheel.location = centre
        out[wheel.name] = wheel
        concept.release(wheel, pad)
    return out, info


# ---------------------------------------------------------------------------------------------
# the front: hood, nose, bumper
# ---------------------------------------------------------------------------------------------

def build_hood(concept, mats):
    """Hood (the lid between the fenders, with the black grille) and what stays on the car."""
    P = concept.parts
    shell = P.pop("BodyHood")
    grill = P.pop("BodyHoodTopgrill")
    for name in ("BodyHoodInterior01", "BodyHoodInterior02", "BodyHoodUnder"):
        bpy.data.objects.remove(P.pop(name), do_unlink=True)

    def on_hood(c):
        return abs(c.x) < 0.60 and c.z > 0.68 and c.y > 1.05

    hood = meshkit.split(shell, on_hood, "Hood")
    _swap(hood, mats)
    _swap(grill, mats)
    _swap(shell, mats)
    _decimated(hood, HOOD_RATIO)
    _decimated(grill, GRILL_RATIO)
    hood = meshkit.join([hood, grill], "Hood")
    meshkit.tidy(hood, 35.0)
    _decimated(shell, FRONT_RATIO)
    return hood, shell


def build_lower_panels(concept, mats):
    """The black lower panels: Bumper_F (the lip), Bumper_R (the rear valance), Skirt_L/R, the rest."""
    panels = concept.parts.pop("BodyPanelsColor2")
    _swap(panels, mats)
    out = {}
    out["Bumper_F"] = meshkit.split(panels, lambda c: c.y > 2.0, "Bumper_F")
    out["Bumper_R"] = meshkit.split(panels, lambda c: c.y < -1.65 and abs(c.x) < 1.05, "Bumper_R")
    out["Skirt_L"] = meshkit.split(panels, lambda c: c.x < -0.95 and -1.05 < c.y < 0.85 and c.z < 0.55, "Skirt_L")
    out["Skirt_R"] = meshkit.split(panels, lambda c: c.x > 0.95 and -1.05 < c.y < 0.85 and c.z < 0.55, "Skirt_R")
    for name, ob in list(out.items()):
        if ob is None:
            raise RuntimeError("no faces for " + name)
        _decimated(ob, PANEL_RATIO)
        meshkit.tidy(ob, 35.0)
    _decimated(panels, PANEL_RATIO)
    return out, panels


# ---------------------------------------------------------------------------------------------
# the doors and the mirrors
# ---------------------------------------------------------------------------------------------

def build_doors(concept, mats):
    """Door_L/R (origin on the hinge, the front edge) and Mirror_L/R."""
    P = concept.parts
    out = {}
    for side, sign in (("L", -1.0), ("R", 1.0)):
        panel = P.pop("BodyDoor%sColor1" % side)
        black = P.pop("BodyDoor%sColor2" % side)
        handle1 = P.pop("BodyDoor%sHandle01" % side)
        handle2 = P.pop("BodyDoor%sHandle02" % side)
        window = P.pop("BodyDoor%sWindow" % side)
        gasket = P.pop("BodyDoor%sWindowGasket" % side)
        mirror = P.pop("BodyDoor%sMirror" % side)
        mirror1 = P.pop("BodyDoor%sMirrorColor1" % side)
        mirror2 = P.pop("BodyDoor%sMirrorColor2" % side)
        for name in ("InteriorDoor%s01", "InteriorDoor%s02", "InteriorDoor%s03", "InteriorDoor%s04",
                     "InteriorDoor%s05", "InteriorDoor%s06"):
            bpy.data.objects.remove(P.pop(name % side), do_unlink=True)
        for ob in (panel, black, handle1, handle2, window, gasket, mirror, mirror1, mirror2):
            _swap(ob, mats)
        for ob in (panel, black):
            _decimated(ob, DOOR_RATIO)
        _decimated(window, 0.4)
        door = meshkit.join([panel, black, handle1, handle2, window, gasket], "Door_" + side)
        meshkit.tidy(door, 35.0)
        lo, hi = meshkit.bounds(door)
        # the hinge: the front edge of the door (the car faces +Y), halfway up
        meshkit.set_origin(door, Vector(((lo.x + hi.x) * 0.5, hi.y, (lo.z + hi.z) * 0.5)))
        out[door.name] = door
        for ob in (mirror1, mirror2):
            _decimated(ob, MIRROR_RATIO)
        mir = meshkit.join([mirror, mirror1, mirror2], "Mirror_" + side)
        meshkit.tidy(mir, 40.0)
        out[mir.name] = mir
    return out


# ---------------------------------------------------------------------------------------------
# the rest of the body, the glass, the lamps
# ---------------------------------------------------------------------------------------------

def build_body(concept, mats, front_shell, lower_panels):
    """Body: pillars, rear clamshell, the front shell, the lower trim, roof, floor and gaskets."""
    P = concept.parts
    pieces = [front_shell, lower_panels]
    for name, ratio in (("BodyPillars", PILLAR_RATIO), ("BodyRearPanelsColor1", REAR_RATIO),
                        ("BodyRoofPanel", ROOF_RATIO)):
        ob = P.pop(name)
        _swap(ob, mats)
        _decimated(ob, ratio)
        pieces.append(ob)
    for name in ("BodyUnderside", "BodyWindshieldGasket", "BodyTaillightsPanels"):
        ob = P.pop(name)
        _swap(ob, mats)
        pieces.append(ob)
    body = meshkit.join(pieces, "Body")
    meshkit.tidy(body, 35.0)
    meshkit.drop_unused_materials(body)
    return body


def build_glass(concept, mats):
    P = concept.parts
    pieces = [P.pop("BodyWindshield"), P.pop("BodyRearwindow"), P.pop("BodyWindowsRearSides")]
    for ob in pieces:
        _swap(ob, mats)
        _decimated(ob, GLASS_RATIO)
    glass = meshkit.join(pieces, "Glass")
    meshkit.tidy(glass, 60.0)
    return glass


def build_lamps(concept, mats):
    """Lamp_FL/Lamp_FR (the head lamp slits), LightBar_Rear (the tail bar), Plate_Rear."""
    P = concept.parts
    out = {}
    head = P.pop("BodyHeadlights")
    _swap(head, mats)
    out["Lamp_FL"] = head
    right = meshkit.split(head, lambda c: c.x > 0.0, "Lamp_FR")
    head.name = "Lamp_FL"
    for ob in (head, right):
        meshkit.tidy(ob, 60.0)
    out["Lamp_FR"] = right
    tail = P.pop("BodyTaillights")
    _swap(tail, mats)
    tail.name = "LightBar_Rear"
    meshkit.tidy(tail, 60.0)
    out["LightBar_Rear"] = tail
    plate = P.pop("License Plate")
    _swap(plate, mats)
    plate.name = "Plate_Rear"
    meshkit.tidy(plate, 60.0)
    out["Plate_Rear"] = plate
    bpy.data.objects.remove(P.pop("BodyTurnsignalsRear"), do_unlink=True)
    return out


def build_interior(concept, mats):
    """A light interior: seats, dash, steering wheel, mid panel and the pedals' floor."""
    P = concept.parts
    keep = ["InteriorSeatsColor1", "InteriorSeatsColor2", "InteriorDashMid", "InteriorDashSides",
            "InteriorSteeringWheel01", "InteriorSteeringWheel02", "InteriorSteeringWheel04",
            "InteriorSteeringDash", "InteriorMid", "InteriorFloormats"]
    pieces = []
    for name in keep:
        ob = P.pop(name)
        _swap(ob, mats)
        if name.startswith("InteriorSeats"):
            _decimated(ob, SEAT_RATIO)
        elif name == "InteriorMid":
            _decimated(ob, 0.2)
        pieces.append(ob)
    interior = meshkit.join(pieces, "Interior")
    meshkit.tidy(interior, 40.0)
    return interior


def discard_rest(concept):
    """Everything the game does not need: wipers, engine, axles, suspension, door cards, frames."""
    for name in list(concept.parts):
        ob = concept.parts.pop(name)
        try:
            bpy.data.objects.remove(ob, do_unlink=True)
        except ReferenceError:
            pass  # joined into another part already
