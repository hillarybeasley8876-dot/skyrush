# SKYRUSH - bake Chinese road-text glyph decals + the GB 5768.3 straight arrow as white-on-transparent PNGs.
# Headless (never touches an open Blender session):
#   blender -b --factory-startup --python bake_road_glyphs.py -- --font NotoSansCJKsc-Bold.otf --out OUTDIR
# Each glyph is stretched to the GB 5768.3 table-4 box (width:height = 1:3, e.g. 200 x 600 cm on 60-80 km/h roads).
# Texture: px x 3px, glyph fills the box minus a 4 % margin. Up in the image = far from the driver.
import argparse
import os
import sys

import bpy

DEFAULT_CHARS = "公交专用慢出口匝道限速注意车距右转左转直行停让禁"


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--chars", default=DEFAULT_CHARS)
    ap.add_argument("--px", type=int, default=256)
    return ap.parse_args(argv)


def setup_scene(px):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_WORKBENCH"
    except TypeError as err:  # enum is dynamic; the message lists the valid engine ids
        scene.render.engine = next(t.strip("'\"(), ") for t in str(err).split() if "WORKBENCH" in t)
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "SINGLE"
    scene.display.shading.single_color = (1.0, 1.0, 1.0)
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.resolution_percentage = 100
    cam_data = bpy.data.cameras.new("glyph_cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("glyph_cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (0.0, 0.0, 10.0)
    scene.camera = cam
    return scene, cam_data


def fit_to_box(obj, box_w, box_h, margin):
    """Non-uniformly scale + centre obj so its bounding box fills box_w x box_h (metres) minus margin."""
    bpy.context.view_layer.update()
    xs = [v[0] for v in obj.bound_box]
    ys = [v[1] for v in obj.bound_box]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    sx, sy = box_w * (1 - 2 * margin) / w, box_h * (1 - 2 * margin) / h
    obj.scale = (sx, sy, 1.0)
    obj.location = (-(min(xs) + w / 2) * sx, -(min(ys) + h / 2) * sy, 0.0)


def render(scene, cam_data, obj, box_w, box_h, px, path):
    scene.render.resolution_x = px
    scene.render.resolution_y = int(px * box_h / box_w)
    cam_data.ortho_scale = max(box_w, box_h)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(obj, do_unlink=True)


def bake_glyph(scene, cam_data, font, ch, px, out_dir):
    cu = bpy.data.curves.new("glyph", "FONT")
    cu.body = ch
    cu.font = font
    obj = bpy.data.objects.new("glyph", cu)
    scene.collection.objects.link(obj)
    fit_to_box(obj, 2.0, 6.0, 0.04)
    render(scene, cam_data, obj, 2.0, 6.0, px, os.path.join(out_dir, "roadtext_u%04x.png" % ord(ch)))


def bake_straight_arrow(scene, cam_data, px, out_dir):
    # GB 5768.3-2009 fig. 44 (40-100 km/h), cm: total 600, head 240 long x 90 wide, shaft 30 wide.
    pts_cm = [(-15, 0), (15, 0), (15, 360), (45, 360), (0, 600), (-45, 360), (-15, 360)]
    verts = [(x / 100.0, y / 100.0 - 3.0, 0.0) for x, y in pts_cm]
    mesh = bpy.data.meshes.new("arrow")
    mesh.from_pydata(verts, [], [list(range(len(verts)))])
    obj = bpy.data.objects.new("arrow", mesh)
    scene.collection.objects.link(obj)
    # 1.0 x 6.0 m frame keeps the true 600 cm length; the decal node size must be (1.0, h, 6.0).
    render(scene, cam_data, obj, 1.0, 6.0, px, os.path.join(out_dir, "arrow_straight_600.png"))


def main():
    args = parse_args()
    os.makedirs(args.out, exist_ok=True)
    scene, cam_data = setup_scene(args.px)
    font = bpy.data.fonts.load(os.path.abspath(args.font))
    for ch in args.chars:
        bake_glyph(scene, cam_data, font, ch, args.px, args.out)
    bake_straight_arrow(scene, cam_data, args.px, args.out)
    print("BAKED %d glyphs + 1 arrow into %s" % (len(args.chars), args.out))


main()
