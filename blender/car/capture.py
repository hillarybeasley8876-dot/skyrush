"""The review captures of the hero Roadster (lead note 5, review #5, #9, #11).

Run:  tools/blender.sh run blender/car/capture.py
Writes captures/car_model/<name>.jpg and the side-by-side comparisons with the
reference photos (photo 09 for the rear, 03 for the front, 13 for the wheel).
"""
import math
import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

from car import paths  # noqa: E402

OUT = os.path.join(paths.ROOT, "captures", "car_model")
GLB = os.path.join(paths.ASSETS, "roadster.glb")
REF = os.path.join(paths.ROOT, "ref", "roadster", "img")

# name: (camera position, look-at, focal length in mm)
SHOTS = {
    "rear_valance": ((0.0, -3.55, 0.52), (0.0, -2.0, 0.48), 55),
    "rear_close": ((1.60, -3.80, 0.70), (0.0, -2.05, 0.45), 50),
    "front34_low": ((4.20, 4.60, 1.05), (0.0, 0.90, 0.45), 50),
    "front_low": ((0.0, 5.20, 0.80), (0.0, 1.60, 0.42), 50),
    "wheel": ((1.90, 0.95, 0.46), (0.78, 1.41, 0.34), 45),
    "wheel09": ((1.52, 1.05, 0.50), (0.78, 1.41, 0.34), 50),
    "tyre_front": ((1.30, 1.30, 0.40), (0.78, 1.41, 0.30), 85),
    "tyre_rear": ((1.35, -1.30, 0.42), (0.82, -1.41, 0.32), 85),
    "door_line": ((2.30, 0.98, 1.05), (0.85, 0.70, 0.78), 85),
    "deck_line": ((1.20, -0.90, 1.55), (0.10, -1.74, 0.93), 70),
    "deck_stowed": ((0.10, -0.60, 2.35), (0.05, -1.72, 0.92), 55),
    "cockpit": ((1.10, 0.95, 1.35), (0.05, 0.20, 0.60), 70),
    "canopy": ((2.10, 1.20, 1.35), (0.10, 0.30, 0.95), 70),
}
# the side-by-side comparisons: (capture, reference photo)
PAIRS = (("rear_close", "09_rear_closeup_nozzles_plate.jpg"),
         ("front34_low", "03_front_3q_low.jpg"),
         ("wheel09", "13_wheel_closeup_stage.jpg"))


def _engine(scene):
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = eng
            return
        except TypeError:
            continue


def _lights(scene):
    world = bpy.data.worlds.new("CapWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.035, 0.036, 0.04, 1)
    rig = [((3.4, 3.0, 4.2), 1100, 3.0), ((-3.6, 1.2, 2.6), 420, 3.0),
           ((0.0, -4.2, 3.2), 620, 2.5), ((0.0, 0.0, 5.0), 300, 5.0),
           ((-1.2, -4.6, 1.6), 380, 1.6), ((1.6, -4.4, 1.2), 260, 1.4),
           ((0.0, -5.0, 0.55), 300, 1.2)]
    for i, (loc, energy, size) in enumerate(rig):
        data = bpy.data.lights.new("CapLight%d" % i, "AREA")
        data.energy, data.size = energy, size
        ob = bpy.data.objects.new("CapLight%d" % i, data)
        scene.collection.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = (Vector((0, 0, 0.6)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()


def main():
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB)
    scene = bpy.context.scene
    _engine(scene)
    scene.render.resolution_x, scene.render.resolution_y = 1100, 750
    scene.render.image_settings.file_format = "PNG"
    try:
        scene.view_settings.view_transform = "AgX"
    except TypeError:
        pass
    _lights(scene)
    cam_data = bpy.data.cameras.new("CapCam")
    cam = bpy.data.objects.new("CapCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for name, (loc, look, lens) in SHOTS.items():
        cam_data.lens = lens
        cam.location = Vector(loc)
        cam.rotation_euler = (Vector(look) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        path = os.path.join(OUT, name + ".png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("SHOT %s" % path)
    _wing_deployed(scene, cam)
    print("captures written to", OUT)


def _wing_deployed(sc, cam):
    """The wing in the high-downforce pose (the JSON `parts.wing.poses`)."""
    import json
    wing = bpy.data.objects.get("Wing")
    if wing is None:
        return
    with open(os.path.join(paths.ROOT, "ref", "roadster", "roadster_loft.json")) as f:
        pose = json.load(f)["parts"]["wing"]["poses"]["high_downforce"]
    le = pose["le"]
    pitch = float(pose["pitch_deg"])
    wing.location = (0.0, le[0], le[1])
    wing.rotation_euler = (0.0, 0.0, 0.0)
    wing.rotation_euler.x = -math.radians(pitch)
    # the deploy contract: the slat, the struts and the end plates scale from
    # 0.001 (stowed) to 1.0 (deployed)
    for n in ("Wing_Slat", "Wing_Strut_L", "Wing_Strut_R",
              "Wing_EndPlate_L", "Wing_EndPlate_R"):
        ob = bpy.data.objects.get(n)
        if ob:
            ob.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()
    cam_data = cam.data
    cam_data.lens = 60
    loc = Vector((2.6, -3.0, 1.55))
    cam.location = loc
    cam.rotation_euler = (Vector((0.0, -1.9, 1.05)) - loc).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, "wing_deployed.png")
    bpy.ops.render.render(write_still=True)
    print("SHOT", sc.render.filepath)


main()
