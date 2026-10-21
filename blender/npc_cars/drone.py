"""Police drone for the NPC fleet (unit: npc_cars).

A quad rotor with a shaped shell, two-blade props with a motion blur disc, a
gimballed camera, a downward spotlight (the `Spot` marker) and red / blue
strobes.
"""
import math

import bmesh
import bpy

from lib import common, geo, uv

from . import atlas, materials, meshutil, palette

ARM = 0.72
ROTOR_R = 0.30
BLADE_CHORD = 0.055


def _prop(name, centre, mats, col, blur=True):
    """Two-blade prop plus a translucent blur disc."""
    parts = []
    for i in range(2):
        a = i * math.pi
        bm = bmesh.new()
        # the blade geometry is baked in the mesh, so the prop's origin stays
        # on the hub (spinning the prop must not orbit it)
        geo.box(bm, (math.cos(a) * ROTOR_R * 0.5, math.sin(a) * ROTOR_R * 0.5, 0.0),
                (ROTOR_R, BLADE_CHORD, 0.008), rot_z=a)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        blade = bpy.data.objects.new(name, me)
        common.link(blade, col)
        me.materials.append(mats["trim"])
        blade.location = centre
        common.smooth(blade, 40.0)
        uv.box_uv(blade)
        parts.append(blade)
    meshutil.join_objects(parts, name)
    if blur:
        bm = bmesh.new()
        geo.cylinder(bm, (0.0, 0.0, 0.0), ROTOR_R, 0.004, 28, axis="Z")
        me = bpy.data.meshes.new(name + "_blur")
        bm.to_mesh(me)
        bm.free()
        disc = bpy.data.objects.new(name + "_blur", me)
        common.link(disc, col)
        me.materials.append(mats["blur"])
        disc.location = centre
        common.smooth(disc, 60.0)
        uv.box_uv(disc)
        parts.append(disc)
    return parts


def build(spec, col):
    """Assemble the drone: shell, arms, props, gimbal, spotlight and strobes."""
    mats = palette.drone_materials()
    body = meshutil.box_mesh("Body", (0.0, 0.0, 0.0), (0.52, 0.62, 0.20), col,
                              mats["body"])
    meshutil.bevel(body, 0.05, 3, 40.0)
    uv.box_uv(body)
    # shell livery on both flanks
    livery = materials.image_mat("NPC_livery_drone", "decal_drone.png",
                                  alpha_texture=True)
    for sx in (-1, 1):
        pts = [(sx * 0.262, -0.28, -0.055), (sx * 0.262, 0.28, -0.055),
               (sx * 0.262, 0.28, 0.065), (sx * 0.262, -0.28, 0.065)]
        if sx < 0:
            pts = list(reversed(pts))
        obj = meshutil.obj_from_faces("DroneLivery", pts, [(0, 1, 2, 3)], col,
                                      [livery], smooth=False, recalc=False)
        meshutil.planar_uv(obj, axis=0, flip=(sx < 0))
    # arms, motor pods and props
    for sx in (-1, 1):
        for sy in (-1, 1):
            tag = "%s%s" % ("F" if sy > 0 else "R", "L" if sx < 0 else "R")
            bm = bmesh.new()
            geo.box(bm, (sx * ARM * 0.5, sy * ARM * 0.5, 0.0),
                    (ARM * 1.05, 0.075, 0.055))
            me = bpy.data.meshes.new("Arm_%s" % tag)
            bm.to_mesh(me)
            bm.free()
            arm = bpy.data.objects.new("Arm_%s" % tag, me)
            common.link(arm, col)
            me.materials.append(mats["trim"])
            arm.rotation_euler = (0.0, 0.0, math.radians(45.0 * sx * sy))
            meshutil.bevel(arm, 0.012, 2, 40.0)
            uv.box_uv(arm)
            pod = meshutil.box_mesh("Motor_%s" % tag,
                                    (sx * ARM * 0.707, sy * ARM * 0.707, 0.02),
                                    (0.11, 0.11, 0.09), col, mats["trim"])
            uv.box_uv(pod)
            _prop("Rotor_%s" % tag, (sx * ARM * 0.707, sy * ARM * 0.707, 0.075),
                  mats, col)
    # gimballed camera
    gim = meshutil.torus("Gimbal", (0.0, 0.20, -0.14), 0.085, 0.018, col,
                         mats["trim"], major_seg=16, minor_seg=5)
    uv.box_uv(gim)
    lens = meshutil.box_mesh("CameraLens", (0.0, 0.22, -0.16), (0.10, 0.12, 0.07),
                             col, mats["glass"])
    uv.box_uv(lens)
    # spotlight housing + marker
    spot = meshutil.box_mesh("Spotlight", (0.0, -0.02, -0.16), (0.13, 0.13, 0.09),
                              col, mats["trim"])
    uv.box_uv(spot)
    lens2 = meshutil.box_mesh("SpotLens", (0.0, -0.02, -0.205), (0.10, 0.10, 0.015),
                               col, mats["lamp_f"])
    uv.box_uv(lens2)
    # skids
    for sx in (-1, 1):
        skid = meshutil.box_mesh("Skid", (sx * 0.16, 0.0, -0.20),
                                 (0.035, 0.52, 0.035), col, mats["trim"])
        uv.box_uv(skid)
    # strobes and nav light
    for name, mat in (("Strobe_Red", mats["red"]), ("Strobe_Blue", mats["blue"])):
        lamp = meshutil.box_mesh(name, (-0.16 if "Red" in name else 0.16, -0.12, 0.11),
                                  (0.09, 0.16, 0.05), col, mat)
        uv.box_uv(lamp)
    nav = meshutil.box_mesh("NavLight", (0.0, 0.31, 0.02), (0.07, 0.05, 0.05), col,
                             mats["lamp_f"])
    uv.box_uv(nav)
    common.empty("Spot", (0.0, -0.02, -0.22), direction=(0.0, 0.0, -1.0), col=col,
                 size=0.35)
    common.empty("Light_Front", (0.0, 0.32, 0.0), direction=(0.0, 1.0, 0.0), col=col,
                 size=0.2)
    return mats
