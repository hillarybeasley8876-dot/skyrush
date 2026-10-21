"""Night close-up render of the Nine-Dragon Pillar with four warm uplights.

    tools/blender.sh run blender/landmarks/preview_pillar.py

Writes ~/m/skyrush/captures/blender/pillar_night_up*.jpg
"""
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.expanduser("~/m/skyrush")
OUT = os.path.join(ROOT, "captures", "blender")
GLB = os.path.join(ROOT, "game", "assets", "landmarks", "dragon_pillar.glb")


def add_spot(name, loc, target, energy, color, angle=25.0):
    data = bpy.data.lights.new(name, type="SPOT")
    data.energy = energy
    data.color = color
    data.spot_size = math.radians(angle)
    data.spot_blend = 0.45
    data.shadow_soft_size = 0.35
    ob = bpy.data.objects.new(name, data)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(ob)
    return ob


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB)
    scene = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            continue
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 1300
    scene.render.film_transparent = False
    try:
        scene.view_settings.view_transform = "AgX"
    except TypeError:
        pass
    # night sky: deep indigo with a warm city glow low on the horizon
    world = bpy.data.worlds.new("night")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.012, 0.014, 0.035, 1.0)
    bg.inputs[1].default_value = 1.0
    # ground
    bpy.ops.mesh.primitive_plane_add(size=120.0, location=(0, 0, 0))
    ground = bpy.context.object
    ground.name = "Ground"
    gmat = bpy.data.materials.new("Ground")
    gmat.use_nodes = True
    gb = next(n for n in gmat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    gb.inputs["Base Color"].default_value = (0.035, 0.035, 0.045, 1.0)
    gb.inputs["Roughness"].default_value = 0.45
    ground.data.materials.append(gmat)
    # four warm uplights at the plinth, 3000 K, 25 deg beams
    for k in range(4):
        a = 2.0 * math.pi * k / 4 + math.pi / 4
        add_spot("Uplight_%d" % (k + 1),
                 (7.4 * math.cos(a), 7.4 * math.sin(a), 0.4),
                 (0.0, 0.0, 12.0), 9000.0, (1.0, 0.78, 0.52), 25.0)
    # cool fill from the sky so the steel keeps some shape
    add_spot("Sky_Fill", (0.0, 0.0, 40.0), (0.0, 0.0, 0.0), 4000.0, (0.55, 0.68, 1.0), 70.0)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 55.0
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    os.makedirs(OUT, exist_ok=True)
    views = [("up_close", 8.2, 7.0, 5.6), ("up_wide", 13.0, 9.0, 7.0)]
    for (name, dist, height, target_z) in views:
        for k in range(3):
            a = math.radians(40.0 + 120.0 * k)
            cam.location = (dist * math.cos(a), dist * math.sin(a), height)
            cam.rotation_euler = (Vector((0.0, 0.0, target_z)) - cam.location) \
                .to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = os.path.join(OUT, "pillar_night_up_%s_%d.png" % (name, k))
            bpy.ops.render.render(write_still=True)
            print("  wrote", scene.render.filepath)


if __name__ == "__main__":
    main()
