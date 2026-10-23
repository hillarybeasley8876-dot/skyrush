"""A tiny studio for Blender previews of the hero car (Cycles CPU, nothing on C:).

Used by build_hero.py and by the exploration scripts:
    import studio
    studio.render("out.png", yaw=35, elev=15, dist=7.0, target=(0, 0, 0.5), size=(960, 540))
The car faces +Y in the scene (the game contract); yaw 0 looks at the front from +Y, 90 from the right (+X).
"""
import math

import bpy
from mathutils import Vector


def _clear_rig():
    for ob in list(bpy.data.objects):
        if ob.name.startswith("_studio"):
            bpy.data.objects.remove(ob, do_unlink=True)


def clear():
    """Removes the studio rig (floor, lights, camera) so it never reaches an export."""
    _clear_rig()
    cam = bpy.data.objects.get("_studio_cam")
    if cam is not None:
        bpy.data.objects.remove(cam, do_unlink=True)


def setup(samples=32, background=(0.62, 0.64, 0.68), strength=1.0, floor=True):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = False
    scene.render.image_settings.file_format = "PNG"
    world = bpy.data.worlds.get("_studio_world") or bpy.data.worlds.new("_studio_world")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (background[0], background[1], background[2], 1.0)
    bg.inputs[1].default_value = strength
    _clear_rig()
    if floor:
        bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, -0.002))
        plane = bpy.context.active_object
        plane.name = "_studio_floor"
        mat = bpy.data.materials.get("_studio_floor_mat") or bpy.data.materials.new("_studio_floor_mat")
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs[0].default_value = (0.16, 0.16, 0.18, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.55
        plane.data.materials.clear()
        plane.data.materials.append(mat)
    for i, (pos, energy, size) in enumerate((((5.0, 6.0, 7.0), 1500.0, 6.0), ((-6.0, -4.0, 4.0), 700.0, 6.0), ((0.0, -7.0, 3.0), 500.0, 4.0))):
        light = bpy.data.lights.new("_studio_l%d" % i, "AREA")
        light.energy = energy
        light.size = size
        ob = bpy.data.objects.new("_studio_l%d" % i, light)
        bpy.context.scene.collection.objects.link(ob)
        ob.location = Vector(pos)
        ob.rotation_euler = (Vector((0, 0, 0.5)) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()


def render(out, yaw=35.0, elev=14.0, dist=7.0, target=(0.0, 0.0, 0.55), size=(960, 540), lens=45.0):
    scene = bpy.context.scene
    a = math.radians(yaw)
    e = math.radians(elev)
    t = Vector(target)
    pos = t + Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e))) * dist
    cam = bpy.data.objects.get("_studio_cam")
    if cam is None:
        data = bpy.data.cameras.new("_studio_cam")
        cam = bpy.data.objects.new("_studio_cam", data)
        scene.collection.objects.link(cam)
    cam.data.lens = lens
    cam.location = pos
    cam.rotation_euler = (t - pos).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)


def render_views(prefix, views, **kw):
    """views: list of (suffix, yaw, elev, dist, target)."""
    for suffix, yaw, elev, dist, target in views:
        render("%s_%s.png" % (prefix, suffix), yaw=yaw, elev=elev, dist=dist, target=target, **kw)
