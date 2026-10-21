"""Render orthographic silhouettes of the Roadster for the photo overlay check.

Writes three masks (side / top / rear) into tmp/car_model/ at the press photos'
own scale, so they can be composited over photos 01, 12 and 08.
"""
import math
import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

from lib import common  # noqa: E402

OUT = os.path.expanduser("~/m/skyrush/tmp/car_model")
GLB = os.path.expanduser("~/m/skyrush/game/assets/cars/roadster/roadster.glb")

# calibration of the resized press photos (1600 px long side)
#   side  : photo 01, ground line at y=730 px, centreline at x=812.5 px, 5.432 mm/px
#   top   : photo 12, origin at (803, 530.6) px, 8.187 mm/px
#   rear  : photo 08, 2.224 mm/px (from the US plate: 305 mm = 137 px)
VIEWS = {
    # side: camera on -X looking +X (the nose points to the image left)
    "side": dict(res=(1600, 1067), mm=5.432, eye=(-8.0, 0.0679, 1.068),
                 rot=((0.0, -1.0, 0.0), (0.0, 0.0, 1.0), (-1.0, 0.0, 0.0))),
    # top: camera above looking down, the nose points to the image left
    "top": dict(res=(1600, 1065), mm=8.187, eye=(0.0155, 0.0246, 9.0),
                rot=((0.0, -1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0))),
    # rear: camera behind the tail looking forward
    "rear": dict(res=(1600, 1067), mm=2.224, eye=(-0.003, -8.0, 0.830),
                 rot=((1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0))),
}


def look_at(obj, target):
    d = (Vector(target) - obj.location).normalized()
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT" if hasattr(sc, "BLENDER_EEVEE_NEXT") else "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    for name, v in VIEWS.items():
        w, h = v["res"]
        sc.render.resolution_x, sc.render.resolution_y = w, h
        cam_data = bpy.data.cameras.new("Cam")
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = w * v["mm"] / 1000.0
        cam = bpy.data.objects.new("Cam", cam_data)
        sc.collection.objects.link(cam)
        cam.location = Vector(v["eye"])
        r = v["rot"]
        cam.rotation_euler = Matrix(((r[0][0], r[1][0], r[2][0]),
                                     (r[0][1], r[1][1], r[2][1]),
                                     (r[0][2], r[1][2], r[2][2]))).to_euler()
        sc.camera = cam
        # flat white emission so the mask is the silhouette
        mat = bpy.data.materials.new("Mask")
        mat.use_nodes = True
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
        bsdf.inputs["Emission Color"].default_value = (1.0, 1.0, 1.0, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.0
        for ob in sc.objects:
            if ob.type == "MESH":
                ob.data.materials.clear()
                ob.data.materials.append(mat)
                # the top view compares the white body: the tyres and the arch lips
                # are black in the photo, so they are left out of the mask
                ob.hide_render = name == "top" and ob.name.startswith(("Tyre", "ArchLip"))
        sc.render.filepath = os.path.join(OUT, "sil_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        print("mask", name, w, h)
    _bar_mask(sc)


def _bar_mask(sc):
    """A mask of the rear light bar alone, so the overlay check can measure it.

    The bar is the sharpest reference in photo 08: its row and its span can be
    compared with the model's, and a wrong car really does fail the check.
    """
    v = VIEWS["rear"]
    w, h = v["res"]
    sc.render.resolution_x, sc.render.resolution_y = w, h
    cam_data = bpy.data.cameras.new("CamBar")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = w * v["mm"] / 1000.0
    cam = bpy.data.objects.new("CamBar", cam_data)
    sc.collection.objects.link(cam)
    cam.location = Vector(v["eye"])
    r = v["rot"]
    cam.rotation_euler = Matrix(((r[0][0], r[1][0], r[2][0]),
                                 (r[0][1], r[1][1], r[2][1]),
                                 (r[0][2], r[1][2], r[2][2]))).to_euler()
    sc.camera = cam
    for ob in sc.objects:
        if ob.type == "MESH":
            ob.hide_render = not ob.name.startswith("LightBar_Rear")
    sc.render.filepath = os.path.join(OUT, "sil_rear_bar.png")
    bpy.ops.render.render(write_still=True)
    print("mask rear_bar", w, h)


main()
