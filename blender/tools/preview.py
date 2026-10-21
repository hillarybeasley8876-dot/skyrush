"""Headless preview renderer for SKYRUSH assets (called by tools/blender.sh preview).

Loads a .glb/.gltf or .blend, frames it from several views under studio and/or night-neon lighting,
renders EEVEE PNGs to <out>_<light>_<view>.png and prints mesh / material / texture stats.
"""
import argparse
import math
import sys

import bpy
from mathutils import Vector

VIEWS = {  # name: (azimuth deg from +Y front, elevation deg, zoom)
    "front34": (35, 14, 1.0), "rear34": (145, 16, 1.0), "side": (90, 4, 1.0), "front": (0, 6, 1.0),
    "rear": (180, 8, 1.0), "top": (0, 88, 1.0), "under": (20, -35, 1.0),
    "close_front34": (30, 10, 2.6), "close_side": (90, 6, 2.8), "close_rear": (180, 10, 2.6),
}
DEFAULT_VIEWS = "front34,rear34,side,front,rear,top,close_front34,close_side"


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--in", dest="src", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--views", default=DEFAULT_VIEWS)
    p.add_argument("--light", default="both", choices=["studio", "night", "both"])
    p.add_argument("--size", default="1280x800")
    p.add_argument("--target-height", type=float, default=0.0, help="assert model height (m)")
    return p.parse_args(argv)


def load(src):
    if src.endswith(".blend"):
        bpy.ops.wm.open_mainfile(filepath=src)
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)


def mesh_bounds():
    lo, hi = Vector((1e9, 1e9, 1e9)), Vector((-1e9, -1e9, -1e9))
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH" or ob.hide_render:
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def set_engine(scene):
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = eng
            return
        except TypeError:
            continue


def add_area(name, loc, target, energy, color, size):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.color, data.size = energy, color, size
    ob = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return ob


def ground(lo, r, night):
    bpy.ops.mesh.primitive_plane_add(size=r * 12, location=(0, 0, lo.z - 0.002))
    plane = bpy.context.active_object
    mat = bpy.data.materials.new("PreviewGround")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.012, 0.013, 0.016, 1) if night else (0.09, 0.09, 0.095, 1)
    bsdf.inputs["Roughness"].default_value = 0.12 if night else 0.45
    plane.data.materials.append(mat)
    return plane


def light_rig(c, r, night):
    world = bpy.context.scene.world or bpy.data.worlds.new("PreviewWorld")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.004, 0.006, 0.016, 1) if night else (0.035, 0.036, 0.04, 1)
    bg.inputs["Strength"].default_value = 1.0
    s = r * r
    if night:
        rig = [((-r * 2.2, r * 0.6, r * 0.9), 110 * s, (1.0, 0.16, 0.55), r * 1.2),
               ((r * 2.2, -r * 0.4, r * 0.8), 90 * s, (0.1, 0.85, 1.0), r * 1.2),
               ((0, -r * 2.5, r * 2.4), 120 * s, (1.0, 0.62, 0.25), r * 2.0)]
    else:
        rig = [((r * 1.8, r * 1.6, r * 2.2), 380 * s, (1.0, 0.97, 0.93), r * 2.5),
               ((-r * 2.4, r * 0.5, r * 1.2), 140 * s, (0.85, 0.9, 1.0), r * 3.0),
               ((0, -r * 2.6, r * 1.6), 220 * s, (1.0, 1.0, 1.0), r * 2.0)]
    lights = []
    for i, (loc, energy, col, size) in enumerate(rig):
        lights.append(add_area("PreviewLight%d" % i, c + Vector(loc), c, energy, col, size))
    return lights


def camera_for(c, r, view, aspect):
    az, el, zoom = VIEWS[view]
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 50 * zoom  # close views zoom with the lens, never by moving inside the model
    cam_data.clip_end = r * 100
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    a, e = math.radians(az), math.radians(el)
    d = r * (2.7 if aspect >= 1 else 3.4)
    direction = Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))
    cam.location = c + direction * d
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def material_stats():
    print("PREVIEW materials:")
    for mat in bpy.data.materials:
        if mat.name.startswith("Preview") or not mat.users:
            continue
        imgs, procedural = [], []
        if mat.use_nodes:
            for n in mat.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image:
                    imgs.append("%s(%dx%d)" % (n.image.name, n.image.size[0], n.image.size[1]))
                elif n.type.startswith("TEX_"):
                    procedural.append(n.type)
        flag = "" if (imgs or procedural) else "  <-- UNTEXTURED"
        print("  %-28s images=%s procedural=%s%s" % (mat.name, imgs, sorted(set(procedural)), flag))


def mesh_stats(lo, hi, target_h):
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and not o.name.startswith("Plane")]
    tris = 0
    for ob in meshes:
        ob.data.calc_loop_triangles()
        tris += len(ob.data.loop_triangles)
    size = hi - lo
    print("PREVIEW objects=%d tris=%d size(m) x=%.2f y=%.2f z=%.2f" % (len(meshes), tris, size.x, size.y, size.z))
    print("PREVIEW nodes: " + ", ".join(sorted(o.name for o in bpy.context.scene.objects
                                               if not o.name.startswith("Preview"))[:80]))
    if target_h and abs(size.z - target_h) / target_h > 0.05:
        print("PREVIEW WARN height %.2f m differs from target %.2f m" % (size.z, target_h))


def main():
    args = parse_args()
    load(args.src)
    scene = bpy.context.scene
    set_engine(scene)
    w, h = (int(v) for v in args.size.split("x"))
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.image_settings.file_format = "PNG"
    try:
        scene.view_settings.view_transform = "AgX"
    except TypeError:
        pass
    lo, hi = mesh_bounds()
    c, r = (lo + hi) / 2, max((hi - lo).length / 2, 0.01)
    mesh_stats(lo, hi, args.target_height)
    material_stats()
    lights = ["studio", "night"] if args.light == "both" else [args.light]
    for light in lights:
        night = light == "night"
        temp = [ground(lo, r, night)] + light_rig(c, r, night)
        for view in args.views.split(","):
            cam = camera_for(c, r, view, w / h)
            scene.render.filepath = "%s_%s_%s.png" % (args.out, light, view)
            bpy.ops.render.render(write_still=True)
            bpy.data.objects.remove(cam)
        for ob in temp:
            bpy.data.objects.remove(ob)


main()
