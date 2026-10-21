"""Fascias and details of the NPC cars (unit: npc_cars).

The bodies come from `lib/car_body.py`; everything here is fitted to the
finished skin by ray-casting it, so a lamp follows the shape of the nose and
never floats off the car.

Front: a full width LED light bar, two headlamp units (a dark reflector with
an emissive strip), a lower honeycomb intake, fog lamps and the plate recess.
Rear: a full width red LED bar, side units, reverse lamps and a black
diffuser.
"""
import math

import bmesh
import bpy
from mathutils import Vector

from lib import common, geo, uv

from . import atlas, body, extras, interior, meshutil

DRL_W, DRL_H = 1.02, 0.030
HEAD_W, HEAD_H = 0.34, 0.090
TAIL_W, TAIL_H = 1.00, 0.038
BRAKE_W, BRAKE_H = 0.24, 0.070
PLATE_W, PLATE_H = 0.44, 0.14
BUMPER_H = 0.26
FOG_R = 0.045


def build_lamps(pr, sp, bvh, mats, col):
    """The head and tail lamps: emissive bars fitted to the nose and the tail."""
    nose = sp["nose_z"]
    tail = sp["tail_z"]
    half = min(0.52, sp["W"] * 0.28)
    parts = []
    # the full width LED light bar
    grid = body.end_grid(bvh, True, -half, half, nose - 0.030 - DRL_H,
                         nose - 0.030, nx=18, nz=2)
    parts.append(body.shell("Lamp_DRL", grid, col, mats["lamp_f"], None,
                             proud=0.002, depth=0.02,
                             uv_rect=atlas.TRIM["lamp"], uv_size=atlas.TRIM_SIZE))
    # the headlamp units: a dark reflector with an emissive strip in it
    for sx in (-1, 1):
        x = sx * (sp["W"] * 0.30)
        grid = body.end_grid(bvh, True, x - HEAD_W * 0.5, x + HEAD_W * 0.5,
                             nose - 0.215, nose - 0.215 + HEAD_H, nx=5, nz=2)
        parts.append(body.shell("Lamp_Reflector", grid, col, mats["gloss"], None,
                                 proud=-0.018, depth=0.012,
                                 uv_rect=atlas.TRIM["plain"], uv_size=atlas.TRIM_SIZE))
        grid = body.end_grid(bvh, True, x - HEAD_W * 0.5 + 0.012,
                             x + HEAD_W * 0.5 - 0.012,
                             nose - 0.215 + 0.012, nose - 0.215 + HEAD_H - 0.012,
                             nx=5, nz=2)
        parts.append(body.shell("Lamp_H", grid, col, mats["lamp_f"], None,
                                 proud=0.001, depth=0.02,
                                 uv_rect=atlas.TRIM["lamp"],
                                 uv_size=atlas.TRIM_SIZE))
    lamp_f = meshutil.join_objects(parts, "Lamp_F")

    parts = []
    grid = body.end_grid(bvh, False, -half, half, tail - 0.030 - TAIL_H,
                         tail - 0.030, nx=18, nz=2)
    parts.append(body.shell("Lamp_Bar", grid, col, mats["lamp_r"], None,
                             proud=0.002, depth=0.02,
                             uv_rect=atlas.TRIM["lamp_red"],
                             uv_size=atlas.TRIM_SIZE))
    for sx in (-1, 1):
        x = sx * (sp["W"] * 0.29)
        grid = body.end_grid(bvh, False, x - BRAKE_W * 0.5, x + BRAKE_W * 0.5,
                             tail - 0.225, tail - 0.225 + BRAKE_H, nx=4, nz=2)
        parts.append(body.shell("Lamp_T", grid, col, mats["lamp_brake"], None,
                                 proud=0.002, depth=0.02,
                                 uv_rect=atlas.TRIM["lamp_red"],
                                 uv_size=atlas.TRIM_SIZE))
        # the reverse lamp: a small white unit in the bumper
        grid = body.end_grid(bvh, False, x - 0.05, x + 0.05,
                             tail - 0.30, tail - 0.25, nx=3, nz=2)
        parts.append(body.shell("Lamp_Reverse", grid, col, mats["lamp_f"], None,
                                 proud=0.001, depth=0.01,
                                 uv_rect=atlas.TRIM["lamp"], uv_size=atlas.TRIM_SIZE))
    lamp_r = meshutil.join_objects(parts, "Lamp_R")
    return lamp_f, lamp_r


def build_front_fascia(pr, sp, bvh, mats, col):
    """The lower intake, the fog lamps and the plate recess of the nose."""
    z_f = pr.floor_z(sp["L"] * 0.5)
    parts = []
    # the honeycomb intake
    grid = body.end_grid(bvh, True, -sp["W"] * 0.26, sp["W"] * 0.26,
                         z_f + 0.030, z_f + 0.030 + 0.085, nx=10, nz=2)
    parts.append(body.shell("Intake", grid, col, mats["mesh"], None, proud=0.001,
                             depth=0.03, uv_rect=atlas.TRIM["mesh"],
                             uv_size=atlas.TRIM_SIZE))
    # the fog lamps in the outer corners
    for sx in (-1, 1):
        x = sx * (sp["W"] * 0.38)
        grid = body.end_grid(bvh, True, x - FOG_R, x + FOG_R,
                             z_f + 0.045, z_f + 0.045 + FOG_R * 2, nx=4, nz=3)
        parts.append(body.shell("FogLamp", grid, col, mats["lamp_f"], None,
                                 proud=0.001, depth=0.02,
                                 uv_rect=atlas.TRIM["lamp"], uv_size=atlas.TRIM_SIZE))
    meshutil.join_objects(parts, "Intake")
    return parts


def build_plates(pr, sp, bvh, mats, col):
    """Vertical number plates, front and rear, proud of the bumper."""
    z_f = pr.floor_z(sp["L"] * 0.5) + 0.155
    z_r = pr.floor_z(-sp["L"] * 0.5) + 0.145
    plates = []
    for front, z in ((True, z_f), (False, z_r)):
        grid = body.end_grid(bvh, front, -PLATE_W * 0.5, PLATE_W * 0.5,
                             z - PLATE_H * 0.5, z + PLATE_H * 0.5, nx=3, nz=2)
        frame = body.shell("PlateFrame", grid, col, mats["plate"], None,
                           proud=0.002, depth=0.012,
                           uv_rect=atlas.PLATE_BLANK, uv_size=mats["plate_atlas"],
                           flip_u=front)
        grid = body.end_grid(bvh, front, -PLATE_W * 0.5 + 0.012,
                             PLATE_W * 0.5 - 0.012, z - PLATE_H * 0.5 + 0.010,
                             z + PLATE_H * 0.5 - 0.010, nx=3, nz=2)
        plate = body.shell("Plate", grid, col, mats["plate"], None,
                           proud=0.006, depth=0.006,
                           uv_rect=mats["plate_rect"], uv_size=mats["plate_atlas"],
                           flip_u=front)
        plates += [frame, plate]
    return plates


def build_bumpers(pr, sp, bvh, mats, col):
    """The bumper covers: a wrap-around panel with a black lower intake."""
    z_f = pr.floor_z(sp["L"] * 0.5)
    z_r = pr.floor_z(-sp["L"] * 0.5)
    out = []
    for front, z, width in ((True, z_f, sp["W"] * 0.42),
                             (False, z_r, sp["W"] * 0.40)):
        grid = body.end_grid(bvh, front, -width, width, z + 0.010,
                             z + 0.010 + BUMPER_H, nx=22, nz=4,
                             limit=sp["W"] * 0.46)
        out.append(body.shell("Bumper_F" if front else "Bumper_R", grid, col,
                              mats["paint"], None, proud=0.003, depth=0.10))
    return out


def build_rear_fascia(pr, sp, bvh, mats, col):
    """The black diffuser under the tail."""
    z_r = pr.floor_z(-sp["L"] * 0.5)
    grid = body.end_grid(bvh, False, -sp["W"] * 0.28, sp["W"] * 0.28,
                         z_r + 0.025, z_r + 0.025 + 0.075, nx=10, nz=2)
    return [body.shell("Diffuser", grid, col, mats["trim"], None, proud=0.001,
                       depth=0.03, uv_rect=atlas.TRIM["trim"],
                       uv_size=atlas.TRIM_SIZE)]


def build_mirrors(pr, sp, mats, col):
    """Door mirrors: a cap, a dark glass face and an LED repeater strip."""
    out = []
    for sx, tag in ((-1, "L"), (1, "R")):
        y = sp["cowl_y"] - 0.16
        hw = pr.half_width(y)
        z = pr.belt_z(y) + 0.04
        bm = bmesh.new()
        # the stalk: from the shoulder of the door out to the cap
        geo.box(bm, (sx * (hw + 0.005), y, z - 0.020), (0.075, 0.030, 0.022))
        # the cap
        geo.box(bm, (sx * (hw + 0.048), y, z), (0.085, 0.080, 0.048))
        me = bpy.data.meshes.new("Mirror_%s" % tag)
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new("Mirror_%s" % tag, me)
        common.link(obj, col)
        me.materials.append(mats["gloss"])
        meshutil.bevel(obj, 0.008, 2, 40.0)
        meshutil.set_uv_rect(obj, atlas.TRIM["plain"])
        out.append(obj)
        # the mirror glass, looking backwards
        bm = bmesh.new()
        geo.box(bm, (sx * (hw + 0.048), y - 0.042, z), (0.070, 0.006, 0.036))
        me = bpy.data.meshes.new("Mirror_Glass_%s" % tag)
        bm.to_mesh(me)
        bm.free()
        glass = bpy.data.objects.new("Mirror_Glass_%s" % tag, me)
        common.link(glass, col)
        me.materials.append(mats["gloss"])
        meshutil.set_uv_rect(glass, atlas.TRIM["plain"])
        out.append(glass)
        # the LED repeater strip under the cap
        bm = bmesh.new()
        geo.box(bm, (sx * (hw + 0.048), y, z - 0.026), (0.060, 0.060, 0.006))
        me = bpy.data.meshes.new("Mirror_Lamp_%s" % tag)
        bm.to_mesh(me)
        bm.free()
        lamp = bpy.data.objects.new("Mirror_Lamp_%s" % tag, me)
        common.link(lamp, col)
        me.materials.append(mats["lamp_f"])
        meshutil.set_uv_rect(lamp, atlas.TRIM["lamp"])
        out.append(lamp)
    return out


def build_handles(pr, sp, mats, col):
    """Flush door handles, set in a shallow recess."""
    out = []
    for idx, (a, b) in enumerate(sp["doors"]):
        y = 0.5 * (a + b)
        for sx, tag in ((-1, "L"), (1, "R")):
            hw = pr.half_width(y)
            z = pr.belt_z(y) - 0.075
            bm = bmesh.new()
            geo.box(bm, (sx * (hw - 0.012), y, z), (0.030, 0.17, 0.030))
            me = bpy.data.meshes.new("Handle")
            bm.to_mesh(me)
            bm.free()
            obj = bpy.data.objects.new("Handle_%s%s" % ("F" if idx == 0 else "R", tag),
                                       me)
            common.link(obj, col)
            me.materials.append(mats["sill"])
            meshutil.bevel(obj, 0.008, 2, 40.0)
            meshutil.set_uv_rect(obj, atlas.TRIM["plain"])
            out.append(obj)
    return out


def build_details(pr, sp, mats, col, parts):
    """Interior, fascias, plates, mirrors, handles and the vehicle extras."""
    body_obj = parts["body"]
    interior.build_interior(sp, mats, col)
    bvh = body.body_bvh(body_obj)
    body.build_doors(pr, bvh, col, mats, sp)
    body.build_hood(pr, bvh, col, mats, sp)
    build_lamps(pr, sp, bvh, mats, col)
    build_front_fascia(pr, sp, bvh, mats, col)
    build_plates(pr, sp, bvh, mats, col)
    build_bumpers(pr, sp, bvh, mats, col)
    build_rear_fascia(pr, sp, bvh, mats, col)
    build_mirrors(pr, sp, mats, col)
    build_handles(pr, sp, mats, col)
    if sp["name"].startswith("police"):
        extras.build_light_bar(pr, sp, mats, col)
    if sp["name"] == "taxi":
        extras.build_roof_sign(pr, sp, mats, col)
        extras.build_taxi_decal(pr, sp, mats, col)
    if sp["name"] == "robotaxi":
        extras.build_lidar(pr, sp, mats, col)
    if sp["name"] == "police_interceptor":
        extras.build_splitter(pr, sp, mats, col)
    if sp["name"] == "police_suv":
        extras.build_ram_bar(pr, sp, mats, col)
    y_f = sp["L"] * 0.5 - 0.10
    y_r = -sp["L"] * 0.5 + 0.10
    z_l = sp["nose_z"] - 0.09
    common.empty("Light_Front", (0.0, y_f, z_l), direction=(0.0, 1.0, 0.0), col=col,
                 size=0.3)
    common.empty("Light_Rear", (0.0, y_r, z_l), direction=(0.0, -1.0, 0.0), col=col,
                 size=0.3)
