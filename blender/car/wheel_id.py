"""The wheel face's area fractions from a flat ID render (review r3 #7).

The rim's three materials are given flat ID colours (white = red, dark = blue,
gold = green), the car is rendered orthographically head-on and the pixels are
counted. The review wants white >= 55 %, dark <= 30 % and gold 5..10 %.

    tools/blender.sh run blender/car/wheel_id.py
"""
import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))

import bpy
import numpy as np
from mathutils import Vector

from car import paths

GLB = os.path.join(paths.ASSETS, "roadster.glb")
OUT = os.path.join(paths.SCRATCH, "wheel_id")
COL = {"M_WheelWhite": (1, 0, 0), "M_WheelDark": (0, 0, 1), "M_GoldWheel": (0, 1, 0)}


def _id_colours():
    """Give the three rim materials flat, unlit ID colours."""
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH":
            continue
        for slot in ob.material_slots:
            m = slot.material
            if m is None or m.name not in COL:
                continue
            c = COL[m.name]
            b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
            b.inputs["Base Color"].default_value = (c[0], c[1], c[2], 1)
            b.inputs["Emission Color"].default_value = (c[0], c[1], c[2], 1)
            b.inputs["Emission Strength"].default_value = 1.0
            b.inputs["Roughness"].default_value = 1.0
            b.inputs["Metallic"].default_value = 0.0


def _hide_everything_but(keep):
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            ob.hide_render = ob.name not in keep


def _fractions(path):
    im = bpy.data.images.load(path)
    px = np.array(im.pixels[:]).reshape(im.size[1], im.size[0], 4)[::-1]
    r, g, b = px[:, :, 0], px[:, :, 1], px[:, :, 2]
    white = (r > 0.5) & (g < 0.5) & (b < 0.5)
    dark = (b > 0.5) & (r < 0.5) & (g < 0.5)
    gold = (g > 0.5) & (r < 0.5) & (b < 0.5)
    tot = max(white.sum() + dark.sum() + gold.sum(), 1)
    return (100.0 * white.sum() / tot, 100.0 * dark.sum() / tot, 100.0 * gold.sum() / tot)


def main():
    os.makedirs(paths.SCRATCH, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 512
    sc.view_settings.view_transform = "Standard"     # the ID colours stay exact
    _id_colours()
    cam_data = bpy.data.cameras.new("C")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 0.58
    cam = bpy.data.objects.new("C", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    ok = True
    for name in ("Wheel_FR", "Wheel_RR"):
        wheel = bpy.data.objects[name]
        _hide_everything_but({name})
        cam.location = (wheel.location.x + 0.9, wheel.location.y, wheel.location.z)
        cam.rotation_euler = Vector((-1, 0, 0)).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = OUT + "_" + name
        bpy.ops.render.render(write_still=True)
        w, d, g = _fractions(OUT + "_" + name + ".png")
        good = w >= 55.0 and d <= 30.0 and 5.0 <= g <= 10.0
        ok = ok and good
        print("%s face: white %.1f %%  dark %.1f %%  gold %.1f %%  %s"
              % (name, w, d, g, "OK" if good else "OUT OF RANGE"))
    print("target: white >= 55 %, dark <= 30 %, gold 5..10 %")
    print("wheel face: %s" % ("PASS" if ok else "FAIL"))


if __name__ == "__main__":
    main()
