"""Lineup render for the npc_cars unit: every vehicle side by side with a
1.75 m human figure for scale.

    tools/blender.sh run blender/npc_cars/lineup.py

Writes captures/blender/lineup_side.jpg and lineup_34.jpg.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))
from lib import geo  # noqa: E402

from npc_cars import colors  # noqa: E402

ROOT = os.path.expanduser("~/m/skyrush")
NPC = os.path.join(ROOT, "game", "assets", "cars", "npc")
OUT = os.path.join(ROOT, "captures", "blender")

ORDER = ["sedan_ev", "suv_ev", "hatch_ev", "taxi", "robotaxi",
         "police_patrol", "police_interceptor", "police_suv",
         "van", "truck", "bus", "police_drone"]

# body colours from the ref/art §4.7 traffic mix (the police cars keep their
# livery, which lives in the second UV set)
PAINT = {
    "sedan_ev": colors.hex_lin(colors.PAINT_WHITE),
    "suv_ev": colors.hex_lin(colors.PAINT_SILVER),
    "hatch_ev": colors.hex_lin(colors.PAINT_BLUE),
    "taxi": colors.hex_lin(colors.TAXI_TEAL),
    "robotaxi": colors.hex_lin(colors.PAINT_BLACK),
    "police_patrol": colors.hex_lin(colors.POLICE_WHITE),
    "police_interceptor": colors.hex_lin(colors.POLICE_WHITE),
    "police_suv": colors.hex_lin(colors.POLICE_WHITE),
    "van": colors.hex_lin(colors.PAINT_WHITE),
    "truck": colors.hex_lin(colors.PAINT_GREY),
    "bus": colors.hex_lin(colors.PAINT_WHITE),
    "police_drone": colors.hex_lin(colors.PAINT_BLACK),
}


def _tint(objects, colour):
    """Paint the imported traffic cars in the fleet colour mix.

    The imported paint drives its base colour through a mix node, so the whole
    material is swapped for a clean Principled of the mix colour (the police
    cars keep their livery material).
    """
    if colour is None:
        return
    for ob in objects:
        if ob.type != "MESH":
            continue
        for i, mat in enumerate(ob.data.materials):
            if mat is None or not mat.name.startswith("SH_car_paint"):
                continue
            new = bpy.data.materials.new("Lineup_" + mat.name)
            new.use_nodes = True
            bsdf = next(n for n in new.node_tree.nodes
                        if n.type == "BSDF_PRINCIPLED")
            bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.30
            bsdf.inputs["Metallic"].default_value = 0.10
            ob.data.materials[i] = new


def human(col):
    """A 1.75 m scale figure: a flat silhouette of a standing person.

    The outline is drawn in the XZ plane (facing the camera), so it reads as
    a person in a side view and not as a grey post.
    """
    import bmesh
    outline = [
        # head and neck
        (-0.07, 1.60), (-0.09, 1.68), (-0.08, 1.75), (-0.04, 1.79),
        (0.03, 1.79), (0.08, 1.74), (0.09, 1.66), (0.07, 1.60),
        # shoulders and arms
        (0.20, 1.56), (0.24, 1.44), (0.21, 1.24), (0.16, 1.06),
        (0.17, 0.98), (0.13, 0.96), (0.11, 1.08),
        # hips and legs
        (0.12, 0.92), (0.13, 0.50), (0.11, 0.02), (0.02, 0.02),
        (0.01, 0.52), (0.00, 0.92),
        (-0.12, 0.92), (-0.14, 0.50), (-0.15, 0.02), (-0.24, 0.02),
        (-0.22, 0.50), (-0.22, 0.92),
        # the other arm
        (-0.19, 0.96), (-0.24, 1.00), (-0.28, 1.20), (-0.30, 1.44),
        (-0.26, 1.56), (-0.07, 1.60),
    ]
    bm = bmesh.new()
    verts = [bm.verts.new((0.0, x, z)) for x, z in outline]
    bm.faces.new(verts)
    me = bpy.data.meshes.new("ScaleFigure")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("ScaleFigure", me)
    bpy.context.scene.collection.objects.link(obj)
    mat = bpy.data.materials.new("Figure")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.045, 0.05, 0.062, 1)
    bsdf.inputs["Roughness"].default_value = 0.7
    me.materials.append(mat)
    return obj


def grid(x0, x1, step=1.0):
    """A one metre grid on the ground, so the sizes can be read off."""
    import bmesh
    bm = bmesh.new()
    depth = 3.2
    y = x0
    while y <= x1:
        v = [bm.verts.new((-depth, y, 0.004)), bm.verts.new((depth, y, 0.004)),
             bm.verts.new((depth, y + 0.02, 0.004)), bm.verts.new((-depth, y + 0.02, 0.004))]
        bm.faces.new(v)
        y += step
    gx = -depth
    while gx <= depth:
        v = [bm.verts.new((gx, x0, 0.004)), bm.verts.new((gx, x1, 0.004)),
             bm.verts.new((gx + 0.02, x1, 0.004)), bm.verts.new((gx + 0.02, x0, 0.004))]
        bm.faces.new(v)
        gx += step
    me = bpy.data.meshes.new("Grid")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("Grid", me)
    bpy.context.scene.collection.objects.link(obj)
    mat = bpy.data.materials.new("Grid")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.22, 0.23, 0.26, 1)
    bsdf.inputs["Roughness"].default_value = 0.6
    me.materials.append(mat)
    return obj


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            continue
    try:
        scene.view_settings.view_transform = "AgX"
    except TypeError:
        pass
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    mode = argv[0] if argv else "fleet"
    order = ORDER[:5] if mode == "five" else ORDER
    x = 0.0
    loaded = []
    for name in order:
        path = os.path.join(NPC, "%s.glb" % name)
        if not os.path.exists(path):
            print("skip missing", name)
            continue
        before = set(bpy.context.scene.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        new = [o for o in bpy.context.scene.objects if o not in before]
        # the glTF is Y-up: the length of the vehicle is along Z.  Turn the
        # whole model so it stands along the row (X) and can be seen in
        # profile.
        raw = []
        for ob in new:
            if ob.type == "MESH":
                for c in ob.bound_box:
                    raw.append(ob.matrix_world @ Vector(c))
        print("RAW", name, "x=%.2f y=%.2f z=%.2f" % (
            max(p.x for p in raw) - min(p.x for p in raw),
            max(p.y for p in raw) - min(p.y for p in raw),
            max(p.z for p in raw) - min(p.z for p in raw)))
        bpy.context.view_layer.update()
        lo = Vector((1e9, 1e9, 1e9))
        hi = Vector((-1e9, -1e9, -1e9))
        for ob in new:
            if ob.type != "MESH":
                continue
            for c in ob.bound_box:
                w = ob.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
        length = hi.y - lo.y
        shift = x - (lo.y + hi.y) * 0.5
        for ob in new:
            if ob.parent is None:
                ob.location.y += shift
        bpy.context.view_layer.update()
        x += length + 1.4
        loaded.append((name, length, x - length * 0.5 - 0.7))
        print("lineup %-22s length %.2f" % (name, length))
    fig = human(None)
    grid(0.0, x)
    # the scale figure stands in front of the sedan (the brief's requirement)
    sedan_x = 0.0
    for entry in loaded:
        if entry[0] == "sedan_ev":
            sedan_x = entry[2]
    fig.location = (3.4, sedan_x, 0.0)
    total = x + 3.0

    ground = bpy.data.meshes.new("Ground")
    ground.from_pydata([(-total * 3, -total * 3, 0.0), (total * 3, -total * 3, 0.0),
                        (total * 3, total * 3, 0.0), (-total * 3, total * 3, 0.0)],
                       [], [(0, 1, 2, 3)])
    ground.update()
    gobj = bpy.data.objects.new("Ground", ground)
    scene.collection.objects.link(gobj)
    gmat = bpy.data.materials.new("Asphalt")
    gmat.use_nodes = True
    bsdf = next(n for n in gmat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.035, 0.036, 0.040, 1)
    bsdf.inputs["Roughness"].default_value = 0.35
    ground.materials.append(gmat)

    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.22, 0.24, 0.30, 1)
    for i, (loc, energy, col, size) in enumerate((
            ((x * 0.15, -18, 20), 2600, (1.0, 0.95, 0.9), 30),
            ((x * 0.55, 18, 16), 2200, (0.8, 0.88, 1.0), 30),
            ((x * 0.9, -8, 14), 2000, (1.0, 1.0, 1.0), 28),
            ((x * 0.35, 10, 24), 1800, (0.9, 0.95, 1.0), 32))):
        data = bpy.data.lights.new("L%d" % i, "AREA")
        data.energy, data.color, data.size = energy, col, size
        ob = bpy.data.objects.new("L%d" % i, data)
        scene.collection.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = (Vector((0, 0, 1.0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()

    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 6.5
    sun_data.angle = 0.25
    sun = bpy.data.objects.new("Sun", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(52.0), 0.0, math.radians(35.0))
    if mode == "night":
        bg.inputs["Color"].default_value = (0.03, 0.04, 0.07, 1)
        sun_data.energy = 0.9
        for i, (loc, energy, col, size) in enumerate((
                ((x * 0.15, -18, 20), 2400, (1.0, 0.72, 0.42), 26),
                ((x * 0.55, 18, 16), 2200, (0.45, 0.72, 1.0), 26),
                ((x * 0.9, -8, 14), 1800, (0.9, 0.35, 0.6), 24),
                ((x * 0.35, 10, 24), 1600, (0.4, 0.9, 1.0), 28))):
            bpy.data.lights["L%d" % i].energy = energy
            bpy.data.lights["L%d" % i].color = col
    centre = Vector((x * 0.5, 0.0, 0.8))
    bpy.context.view_layer.update()
    corners = []
    for ob in scene.objects:
        if ob.type != "MESH" or ob.name in ("Ground", "Grid"):
            continue
        for c in ob.bound_box:
            corners.append(ob.matrix_world @ Vector(c))
    if mode == "five":
        views = (("five", 62.0, 8.0, (2600, 700)),)
    elif mode == "night":
        views = (("fleet_night", 52.0, 20.0, (3000, 1100)),)
    elif mode == "side":
        views = (("side", 90.0, 7.0, (3600, 620)),)
    else:
        views = (("fleet", 52.0, 20.0, (3000, 1100)),)
    for name, az, elev, res in views:
        a, e = math.radians(az), math.radians(elev)
        d = Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))
        right = Vector((math.cos(a), -math.sin(a), 0.0)).normalized()
        up = right.cross(d).normalized()
        us = [p.dot(right) for p in corners]
        vs = [p.dot(up) for p in corners]
        w = max(us) - min(us)
        h = max(vs) - min(vs)
        cu = 0.5 * (max(us) + min(us))
        cv = 0.5 * (max(vs) + min(vs))
        target = right * cu + up * cv + d * centre.dot(d)
        data = bpy.data.cameras.new("C")
        data.type = "ORTHO"
        data.ortho_scale = max(w, h * res[0] / res[1]) * 1.05
        data.clip_end = 500.0
        cam = bpy.data.objects.new("C", data)
        scene.collection.objects.link(cam)
        cam.location = target + d * 90.0
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.camera = cam
        scene.render.resolution_x, scene.render.resolution_y = res
        scene.render.image_settings.file_format = "PNG"
        scene.render.filepath = os.path.join(OUT, "lineup_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        print("lineup shot", name)


main()
