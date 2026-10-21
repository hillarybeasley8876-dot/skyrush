"""Street-kit lineup sheet for the SKYRUSH props unit.

Builds every street prop in three rows with a 1.75 m human figure for scale and
renders a studio and a night banner:

    tools/blender.sh run blender/props/lineup.py

Output: captures/blender/street_kit_lineup_<studio|night>.jpg

The night sheet is a real night: the world is almost black, the city glow is a
dim blue dome, and the only light on the props is their own emissive (lamps,
signs, neon) plus the pools the lamp heads throw on the asphalt.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.expanduser("~/m/skyrush")
sys.path.insert(0, os.path.join(ROOT, "blender"))

from lib import common  # noqa: E402

common.reset()

from props import build as B  # noqa: E402
from props import kit, materials as M  # noqa: E402

OUT_DIR = os.path.join(ROOT, "captures", "blender")

# Three rows, front to back. The figure stands in front for scale.
# The camera sits at -Y, the side the sign faces look towards, so every board in
# the sheet shows its printed face.
ROWS = (
    (0.0, ("lamp_deck_double", "plane_tree_1", "metro_entrance", "guide_gantry_27",
           "vms_board", "guide_sign", "billboard_pole", "scaffold", "bus_stop",
           "traffic_light_mast", "noise_wall", "lamp_magnolia")),
    (13.0, ("lamp_street", "lamp_heritage", "lamp_shikumen", "road_name_sign",
            "crash_barrier", "crowd_barrier", "roadblock_barrier", "spike_strip",
            "hologram_projector", "neon_blade_frame", "ac_unit", "bike_share")),
    (25.0, ("planter_pot_bougainvillea", "planter_pot_privet", "cone", "bin",
            "bollard", "hydrant", "e_scooter", "guide_gantry_19", "guide_gantry_34")),
)
SPACING = 6.4
FIGURE = 1.75
# where the lamp heads are, so the night sheet can put a pool of light under them
LAMP_HEADS = ((2.5, 0.0, 10.6), (-2.5, 0.0, 10.6), (8.4, 13.0, 10.6),
              (2.4, 13.0, 10.6), (31.2, 0.0, 10.6), (37.6, 0.0, 10.6))


def _figure(x, y):
    """A simple 1.75 m mannequin so the sheet reads at the right scale."""
    p = kit.Prop("figure")
    skin = M.family("mineral")
    tint = (0.34 / 0.75, 0.33 / 0.75, 0.36 / 0.75)
    bm = bmesh.new()
    kit.sphere(bm, (0.0, 0.0, 1.62), 0.115, subdivisions=2, scale=(1.0, 0.92, 1.15))
    p.mesh("Head", bm, skin, smooth=True, tint=tint)
    p.box("Torso", (0.0, 0.0, 1.17), (0.40, 0.22, 0.66), skin, bevel=0.06, tint=tint)
    p.box("Hips", (0.0, 0.0, 0.82), (0.34, 0.22, 0.22), skin, bevel=0.05, tint=tint)
    for sx in (-0.11, 0.11):
        p.box("Leg%d" % int(sx > 0), (sx, 0.0, 0.42), (0.15, 0.18, 0.84), skin,
              bevel=0.05, tint=tint)
        p.box("Foot%d" % int(sx > 0), (sx, 0.05, 0.045), (0.15, 0.28, 0.09), skin,
              bevel=0.02, tint=tint)
    for sx in (-0.25, 0.25):
        p.box("Arm%d" % int(sx > 0), (sx, 0.0, 1.12), (0.11, 0.14, 0.66), skin,
              bevel=0.04, tint=tint)
    p.translate((x, y, 0.0))
    return p


def _build_rows():
    builders = {}
    for module, _folder in B.GROUPS:
        for name, builder in module.BUILDERS.items():
            builders[name] = builder
    placed = 0
    for row_index, (y, names) in enumerate(ROWS):
        for i, name in enumerate(names):
            builder = builders.get(name)
            if builder is None:
                continue
            prop = builder()
            prop.translate((i * SPACING, y, 0.0))
            placed += 1
    _figure(3.0, -7.0)
    print("LINEUP placed %d props" % placed)


def _ground():
    """Wet asphalt the props stand on, with a kerb line and lane dashes."""
    p = kit.Prop("LineupGround")
    p.box("Road", (30.0, 12.0, -0.06), (160.0, 90.0, 0.12), M.surface(),
          surface="asphalt")
    p.box("Kerb", (30.0, -14.0, 0.02), (160.0, 0.30, 0.16), M.surface(),
          surface="kerb")
    dashes = []
    for i in range(24):
        dashes.append((2.4, 0.16, (2.0 + i * 6.0, -6.0, 0.012), kit.FLAT))
    p.quads("Dashes", dashes, M.surface(), surface="white_paint")
    return p


def _light_rig(night):
    """Studio: a broad key. Night: a dim city dome and the lamps' own pools."""
    world = bpy.context.scene.world or bpy.data.worlds.new("LineupWorld")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = ((0.010, 0.013, 0.030, 1.0) if night
                                        else (0.030, 0.032, 0.038, 1.0))
    bg.inputs["Strength"].default_value = 1.0
    rig = []
    if night:
        # the city glow: a dim blue dome from behind, a warm one from the front
        lights = (((-40.0, 60.0, 70.0), 2.4e4, (0.36, 0.46, 1.0), 80.0),
                  ((120.0, 70.0, 45.0), 9.0e3, (0.55, 0.42, 0.95), 70.0),
                  ((40.0, -70.0, 20.0), 5.0e3, (1.0, 0.52, 0.22), 50.0))
    else:
        lights = (((-40.0, 60.0, 60.0), 2.4e5, (1.0, 0.97, 0.93), 60.0),
                  ((120.0, 80.0, 40.0), 1.2e5, (0.82, 0.88, 1.0), 70.0),
                  ((50.0, -60.0, 30.0), 9.0e4, (1.0, 0.72, 0.45), 50.0))
    for i, (loc, energy, col, size) in enumerate(lights):
        data = bpy.data.lights.new("LineupLight%d" % i, "AREA")
        data.energy, data.color, data.size = energy, col, size
        obj = bpy.data.objects.new("LineupLight%d" % i, data)
        bpy.context.scene.collection.objects.link(obj)
        obj.location = loc
        obj.rotation_euler = (Vector((30.0, 12.0, 4.0)) - Vector(loc)).to_track_quat(
            "-Z", "Y").to_euler()
        rig.append(obj)
    if night:
        # the pools the lamp heads throw on the asphalt (3000 K)
        for i, loc in enumerate(LAMP_HEADS):
            data = bpy.data.lights.new("LampPool%d" % i, "POINT")
            data.energy, data.color, data.shadow_soft_size = 2.2e3, (1.0, 0.86, 0.66), 0.8
            obj = bpy.data.objects.new("LampPool%d" % i, data)
            bpy.context.scene.collection.objects.link(obj)
            obj.location = loc
            rig.append(obj)
    return rig


def _camera(night):
    data = bpy.data.cameras.new("LineupCam")
    data.lens = 28.0
    data.clip_end = 2000.0
    cam = bpy.data.objects.new("LineupCam", data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = (24.0, -58.0, 12.0)
    target = Vector((28.0, 12.0, 4.5))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    _build_rows()
    _ground()
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 3200, 1150
    scene.render.image_settings.file_format = "PNG"
    try:
        scene.view_settings.view_transform = "AgX"
    except TypeError:
        pass
    for night in (False, True):
        rig = _light_rig(night)
        cam = _camera(night)
        name = "street_kit_lineup_%s" % ("night" if night else "studio")
        scene.render.filepath = os.path.join(OUT_DIR, name + ".png")
        bpy.ops.render.render(write_still=True)
        print("LINEUP RENDER %s" % scene.render.filepath)
        for obj in rig + [cam]:
            bpy.data.objects.remove(obj, do_unlink=True)


main()
