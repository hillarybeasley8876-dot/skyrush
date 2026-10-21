"""Vehicle specific extras for the NPC fleet (unit: npc_cars).

Police light bar, taxi roof sign and door sticker, robotaxi sensor ring,
interceptor splitter and the police SUV ram bar. Kept apart from details.py so
both stay under the 400 line limit.
"""
import math

import bmesh
import bpy

from lib import common, geo, uv

from . import atlas, colors, materials, meshutil, palette

# the taxi roof light (metres)
ROOF_SIGN = {"w": 0.95, "d": 0.30, "h": 0.20}


def build_light_bar(pr, sp, mats, col):
    """Police light bar: housing plus the two named emissive halves."""
    pm = palette.police_materials()
    y = 0.05
    z = pr.top_z(y) + 0.035
    hw = pr.half_width(y) - 0.16
    bm = bmesh.new()
    geo.box(bm, (0.0, y, z), (hw * 2.0, 0.24, 0.055))
    me = bpy.data.meshes.new("LightBar")
    bm.to_mesh(me)
    bm.free()
    housing = bpy.data.objects.new("LightBar", me)
    common.link(housing, col)
    me.materials.append(mats["trim"])
    meshutil.bevel(housing, 0.012, 2, 40.0)
    meshutil.set_uv_rect(housing, atlas.TRIM["trim"])
    halves = []
    for sx, name, mat in ((-1, "LightBar_Red", pm["red"]), (1, "LightBar_Blue", pm["blue"])):
        bm = bmesh.new()
        geo.box(bm, (sx * hw * 0.46, y, z + 0.028), (hw * 0.80, 0.20, 0.035))
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(name, me)
        common.link(obj, col)
        me.materials.append(mat)
        meshutil.bevel(obj, 0.008, 2, 40.0)
        meshutil.set_uv_rect(obj, atlas.TRIM["lamp"])
        halves.append(obj)
    common.empty("Siren", (0.0, y, z + 0.06), direction=(0.0, 1.0, 0.0), col=col,
                 size=0.25)
    # roof number (readable from the drone view)
    number = materials.image_mat("NPC_roof_number", "roofnum_%s.png" % sp["name"],
                                 alpha_texture=True)
    ry = -0.95
    rz = pr.top_z(ry) + 0.012
    pts = [(-0.32, ry - 0.16, rz), (0.32, ry - 0.16, rz),
           (0.32, ry + 0.16, rz), (-0.32, ry + 0.16, rz)]
    decal = meshutil.obj_from_faces("RoofNumber", pts, [(0, 1, 2, 3)], col, [number],
                                    smooth=False, recalc=False)
    meshutil.planar_uv(decal, axis=2, flip=False)
    return [housing] + halves + [decal]


def build_roof_sign(pr, sp, mats, col):
    """Taxi roof light: a teal box with an emissive 申城出租 on the front and
    the rear face and TAXI on the sides."""
    y = -0.1
    z = pr.top_z(y) + 0.085
    bm = bmesh.new()
    geo.box(bm, (0.0, y, z), (ROOF_SIGN["w"], ROOF_SIGN["d"], ROOF_SIGN["h"]))
    me = bpy.data.meshes.new("RoofSign")
    bm.to_mesh(me)
    bm.free()
    body_obj = bpy.data.objects.new("RoofSign", me)
    common.link(body_obj, col)
    me.materials.append(materials.plain_mat(
        "NPC_taxi_sign", colors.hex_lin(colors.TAXI_TEAL), roughness=0.42,
        metallic=0.05, texture="npc_paint_rough.png"))
    meshutil.bevel(body_obj, 0.02, 2, 40.0)
    meshutil.set_uv_rect(body_obj, atlas.TRIM["trim"])
    sign_mat = materials.image_mat("NPC_sign_taxi", "sign_taxi_roof.png",
                                    emission=(1.0, 0.95, 0.85),
                                    emission_strength=3.0, alpha_texture=True)
    en_mat = materials.image_mat("NPC_sign_taxi_en", "sign_taxi_roof_en.png",
                                  emission=(1.0, 0.95, 0.85),
                                  emission_strength=3.0, alpha_texture=True)
    faces = []
    for sy in (-1, 1):
        bm = bmesh.new()
        geo.box(bm, (0.0, y + sy * (ROOF_SIGN["d"] * 0.5 + 0.003), z),
                (ROOF_SIGN["w"] * 0.94, 0.006, ROOF_SIGN["h"] * 0.62))
        me2 = bpy.data.meshes.new("RoofSignFace")
        bm.to_mesh(me2)
        bm.free()
        face = bpy.data.objects.new("RoofSignFace", me2)
        common.link(face, col)
        me2.materials.append(sign_mat)
        meshutil.planar_uv(face, axis=1, flip=(sy < 0))
        faces.append(face)
    for sx in (-1, 1):
        bm = bmesh.new()
        geo.box(bm, (sx * (ROOF_SIGN["w"] * 0.5 + 0.003), y, z),
                (0.006, ROOF_SIGN["d"] * 0.80, ROOF_SIGN["h"] * 0.55))
        me2 = bpy.data.meshes.new("RoofSignFaceEn")
        bm.to_mesh(me2)
        bm.free()
        face = bpy.data.objects.new("RoofSignFaceEn", me2)
        common.link(face, col)
        me2.materials.append(en_mat)
        meshutil.planar_uv(face, axis=0, flip=(sx < 0))
        faces.append(face)
    meshutil.join_objects(faces, "RoofSignFace")
    return [body_obj]


def build_taxi_decal(pr, sp, mats, col):
    """Teal 申城出租 door sticker, fleet number and phone on both flanks."""
    decal = materials.image_mat("NPC_decal_taxi", "decal_taxi.png",
                                 alpha_texture=True)
    out = []
    for sx in (-1, 1):
        hw = pr.half_width(0.6)
        x = sx * (hw + 0.006)
        y0, y1 = 0.22, 1.00
        z0, z1 = 0.46, 0.80
        pts = [(x, y0, z0), (x, y1, z0), (x, y1, z1), (x, y0, z1)]
        obj = meshutil.obj_from_faces("TaxiDecal", pts, [(0, 1, 2, 3)], col, [decal],
                                      smooth=False)
        meshutil.planar_uv(obj, axis=0, flip=(sx < 0))
        out.append(obj)
    return out


def build_lidar(pr, sp, mats, col):
    """Robotaxi sensor ring (emissive) plus the puck."""
    y = 0.15
    z = pr.top_z(y) + 0.06
    ring = meshutil.torus("LiDAR", (0.0, y, z + 0.035), 0.135, 0.020, col,
                          mats["lidar"], major_seg=28, minor_seg=6)
    meshutil.set_uv_rect(ring, atlas.TRIM["lamp"])
    bm = bmesh.new()
    geo.cylinder(bm, (0.0, y, z), 0.10, 0.07, 20, axis="Z")
    me = bpy.data.meshes.new("LiDAR_Base")
    bm.to_mesh(me)
    bm.free()
    base = bpy.data.objects.new("LiDAR_Base", me)
    common.link(base, col)
    me.materials.append(mats["trim"])
    meshutil.bevel(base, 0.006, 2, 40.0)
    meshutil.set_uv_rect(base, atlas.TRIM["trim"])
    return [ring, base]


def build_splitter(pr, sp, mats, col):
    """Low front splitter (police interceptor)."""
    hw = pr.half_width(sp["L"] * 0.5)
    y = sp["L"] * 0.5 - 0.10
    z = pr.floor_z(sp["L"] * 0.5) + 0.02
    bm = bmesh.new()
    geo.box(bm, (0.0, y, z), (hw * 1.92, 0.30, 0.045))
    me = bpy.data.meshes.new("Splitter")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("Splitter", me)
    common.link(obj, col)
    me.materials.append(mats["trim"])
    meshutil.bevel(obj, 0.012, 2, 40.0)
    meshutil.set_uv_rect(obj, atlas.TRIM["trim"])
    return [obj]


def build_ram_bar(pr, sp, mats, col):
    """Push bumper / ram bar (heavy police SUV): 1.7 m black textured bar."""
    hw = pr.half_width(sp["L"] * 0.5)
    y = sp["L"] * 0.5 - 0.06
    z = pr.floor_z(sp["L"] * 0.5) + 0.42
    bm = bmesh.new()
    geo.box(bm, (0.0, y, z), (1.70, 0.12, 0.20))
    for sx in (-1, 1):
        geo.box(bm, (sx * 0.72, y - 0.12, z - 0.06), (0.10, 0.30, 0.10))
    me = bpy.data.meshes.new("RamBar")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("RamBar", me)
    common.link(obj, col)
    me.materials.append(mats["trim"])
    meshutil.bevel(obj, 0.02, 2, 40.0)
    meshutil.set_uv_rect(obj, atlas.TRIM["mesh"])
    return [obj]
