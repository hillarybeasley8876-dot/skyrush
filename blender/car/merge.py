"""Merge the static detail objects, so the car draws in fewer surfaces.

The contract meshes keep their own names (CONTRACTS.md §6), but the small
static details - the fan rims, the grilles, the nozzle throats, the
suspension, the cabin, the markers - are joined per material
(review r3 SHOULD-FIX: "merge the static, non-contract details per material").

The join happens AFTER the UVs are laid out, so every merged part keeps the
UVs it was built with, and the geometry is baked into the root's space first,
so the merged object sits at the origin like the parts it replaces.
"""
import bpy
from mathutils import Matrix

from car import paths
from lib import common

NOZZLE_THROATS = (["NozzleThroat_R%d" % i for i in range(1, 5)] +
                  ["NozzleThroat_P%d" % i for i in range(1, 7)])

# (the objects, the name of the merged object)
GROUPS = (
    (["Camera_Front", "Camera_Rear", "ChargePort", "Diffuser_Shelf",
      "Fan_R1_Rim", "Fan_R2_Rim", "Fan_R3_Rim", "Fan_R4_Rim",
      "HeadlampHousing_FL", "HeadlampHousing_FR", "LightBar_RearHousing"],
     "TrimDetails"),
    (["Fan_R1_Grille", "Fan_R2_Grille", "Fan_R3_Grille", "Fan_R4_Grille",
      "Intake_Grille"], "Grilles"),
    (NOZZLE_THROATS, "NozzleThroats"),
    (["Suspension_FL", "Suspension_FR", "Suspension_RL", "Suspension_RR"],
     "Suspension"),
    (["Cockpit", "COPV_Strap_L", "COPV_Strap_R", "DoorCard_L", "DoorCard_R",
      "Yoke"], "Cabin"),
    (["NozzleChannel", "Wing_Inner"], "InnerDark"),
    (["AmbientStrip_L", "AmbientStrip_R", "COPV_Band"], "RedAccents"),
    (["Screen_Centre", "Screen_Driver"], "Screens"),
    (["SideMarker_L", "SideMarker_R"], "SideMarkers"),
    (["Reflector_L", "Reflector_R"], "Reflectors"),
)


def _bake(ob):
    """Move the geometry into the root's space and put the object at the origin."""
    ob.data.transform(ob.matrix_world)
    ob.parent = None
    ob.matrix_world = Matrix.Identity(4)


def merge_details(root):
    """Join every group of static details; returns the number of saved objects."""
    saved = 0
    for names, name in GROUPS:
        objs = [bpy.data.objects.get(n) for n in names]
        objs = [o for o in objs if o is not None and o.type == "MESH"]
        if len(objs) < 2:
            continue
        for o in objs:
            _bake(o)
        first = objs[0]
        common.join(objs, name)
        first.location = (0.0, 0.0, 0.0)
        paths.parent_to(first, root)
        if len(first.data.materials) > 1:
            print("  %s has %d materials" % (name, len(first.data.materials)))
        saved += len(objs) - 1
    print("MERGED %d detail objects into %d groups" % (saved, len(GROUPS)))
    return saved
