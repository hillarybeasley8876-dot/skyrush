"""Night renders of the Bund for the art review (bund unit).

    tools/blender.sh run blender/bund/shot.py -- --out captures/bund/row.jpg \
        --cam 60,-300,24 --target -130,-320,25 --lens 55 --glb game/assets/bund/bund_buildings.glb

Renders with the Bund's own uplights (game/assets/bund/bund_lights.json) so the shot shows
the real night look, not a studio light.
"""
import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))

from lib import common  # noqa: E402

LIGHTS_JSON = os.path.join(common.GAME, "assets", "bund", "bund_lights.json")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--glb", action="append", default=[])
    p.add_argument("--out", required=True)
    p.add_argument("--cam", default="0,0,10")
    p.add_argument("--target", default="0,0,10")
    p.add_argument("--lens", type=float, default=50.0)
    p.add_argument("--size", default="1600x900")
    p.add_argument("--lightstep", type=int, default=3)
    p.add_argument("--exposure", type=float, default=1.0)
    p.add_argument("--day", action="store_true", help="flat daylight instead of the night rig")
    p.add_argument("--boost", type=float, default=6.0, help="uplight energy multiplier for the render")
    p.add_argument("--only", default="", help="show only objects whose name contains this")
    p.add_argument("--workbench", action="store_true", help="flat workbench render, colour per object")
    return p.parse_args(argv)


def night_world():
    world = bpy.context.scene.world or bpy.data.worlds.new("ShotWorld")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.006, 0.008, 0.020, 1)
    bg.inputs["Strength"].default_value = 1.0


def add_spot(name, pos, direction, color, energy, angle_deg, size=0.6):
    data = bpy.data.lights.new(name, "SPOT")
    data.energy = energy
    data.color = color
    data.spot_size = math.radians(angle_deg)
    data.spot_blend = 0.45
    data.shadow_soft_size = size
    ob = bpy.data.objects.new(name, data)
    ob.location = pos
    ob.rotation_euler = (Vector(direction).normalized() * -1.0).to_track_quat("Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(ob)
    return ob


def add_uplights(step, boost=1.0):
    """The Bund's facade uplights, thinned out for render speed."""
    if not os.path.exists(LIGHTS_JSON):
        return 0
    data = json.load(open(LIGHTS_JSON))
    n = 0
    for i, rec in enumerate(data["lights"]):
        if i % step:
            continue
        # the sidecar is in game axes (x east, y up, z south); the scene is Blender (x, y, z up)
        pos = Vector(rec["position"])
        dirv = Vector(rec["direction"])
        bpy_pos = Vector((pos.x, -pos.z, pos.y))
        bpy_dir = Vector((dirv.x, -dirv.z, dirv.y))
        add_spot(rec["name"], bpy_pos, bpy_dir,
                 tuple(rec["color"]), rec["energy"] * boost, rec["angle"], 0.5)
        n += 1
    return n


def add_glow():
    """A simple glare so the emissives read like the game's bloom (Blender 5 compositor)."""
    scene = bpy.context.scene
    try:
        ng = bpy.data.node_groups.new("ShotComp", "CompositorNodeTree")
        ng.interface.new_socket("Image", in_out="INPUT", socket_type="NodeSocketColor")
        ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        gi = ng.nodes.new("NodeGroupInput")
        go = ng.nodes.new("NodeGroupOutput")
        glare = ng.nodes.new("CompositorNodeGlare")
        glare.glare_type = "FOG_GLOW"
        glare.quality = "MEDIUM"
        glare.threshold = 0.9
        glare.size = 7
        ng.links.new(gi.outputs[0], glare.inputs[0])
        ng.links.new(glare.outputs[0], go.inputs[0])
        scene.compositing_node_group = ng
        scene.use_nodes = True
    except Exception as exc:            # older Blender or a missing node
        print("GLOW SKIPPED: %s" % exc)


def main():
    args = parse_args()
    common.reset()
    for g in args.glb:
        path = os.path.abspath(os.path.expanduser(g))
        print("IMPORT %s exists=%s" % (path, os.path.exists(path)))
        bpy.ops.import_scene.gltf(filepath=path)
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH":
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    print("SCENE bounds %s .. %s  objects=%d" % (lo, hi, len(bpy.context.scene.objects)))
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH":
            continue
        if ob.name.endswith("-convcolonly") or ob.name.endswith("-colonly"):
            ob.hide_render = True          # collision proxies are not art
        elif args.only and args.only not in ob.name:
            ob.hide_render = True
    scene = bpy.context.scene
    if args.workbench:
        scene.render.engine = "BLENDER_WORKBENCH"
        sh = scene.display.shading
        sh.light = "STUDIO"
        sh.color_type = "OBJECT"
        sh.show_cavity = True
        import random as _r
        _r.seed(7)
        for i, ob in enumerate(bpy.context.scene.objects):
            if ob.type == "MESH":
                ob.color = (_r.random(), _r.random(), _r.random(), 1.0)
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.eevee.taa_render_samples = 32
            if not args.workbench:
                scene.render.engine = eng
            break
        except TypeError:
            continue
    w, h = (int(v) for v in args.size.split("x"))
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.image_settings.file_format = "PNG"
    try:
        scene.view_settings.view_transform = "AgX"
    except TypeError:
        pass
    scene.view_settings.exposure = args.exposure
    night_world()
    if args.day:
        sun = bpy.data.lights.new("DaySun", "SUN")
        sun.energy = 3.0
        sun.color = (1.0, 0.97, 0.92)
        so = bpy.data.objects.new("DaySun", sun)
        so.rotation_euler = (0.9, 0.2, 0.6)
        bpy.context.scene.collection.objects.link(so)
        bg = next(n for n in bpy.context.scene.world.node_tree.nodes if n.type == "BACKGROUND")
        bg.inputs["Color"].default_value = (0.10, 0.12, 0.16, 1)
    else:
        add_uplights(args.lightstep, args.boost)
        add_glow()
        # a soft fill from the river, standing in for the environment unit's night sky
        fill = bpy.data.lights.new("Fill", "SUN")
        fill.energy = 0.25
        fill.color = (1.0, 0.72, 0.42)
        fo = bpy.data.objects.new("Fill", fill)
        fo.rotation_euler = (1.15, 0.0, 1.5)
        bpy.context.scene.collection.objects.link(fo)
    cam_data = bpy.data.cameras.new("ShotCam")
    cam_data.lens = args.lens
    cam_data.clip_end = 5000.0
    cam = bpy.data.objects.new("ShotCam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = Vector([float(v) for v in args.cam.split(",")])
    target = Vector([float(v) for v in args.target.split(",")])
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    out = os.path.expanduser(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("SHOT %s" % out)


if __name__ == "__main__":
    main()
