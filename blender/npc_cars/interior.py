"""Car interior for the NPC fleet (unit: npc_cars): seats, dash, wheel, console.

Kept separate from details.py so both stay under the 400 line limit. Every part
is mapped onto its rectangle of the shared interior atlas.
"""
import math

import bmesh
import bpy

from lib import common, geo

from . import atlas, meshutil


def _seat(name, col, mats, x, y, z, width=0.48, depth=0.46, height=0.62):
    """A simple seat: squab plus backrest."""
    bm = bmesh.new()
    geo.box(bm, (x, y, z + 0.08), (width, depth, 0.14))
    geo.box(bm, (x, y - depth * 0.45, z + 0.30), (width, 0.14, height * 0.75))
    geo.box(bm, (x, y - depth * 0.30, z + height * 0.82), (width * 0.55, 0.12, 0.20))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    common.link(obj, col)
    me.materials.append(mats["seat"])
    meshutil.bevel(obj, 0.02, 2, 40.0)
    meshutil.set_uv_rect(obj, atlas.INTERIOR["seat"])
    return obj


def build_interior(sp, mats, col):
    """Seats, dash, steering wheel and console - visible through the glass."""
    im = {"seat": mats["seat"], "dash": mats["dash"],
          "trim": mats["interior_trim"]}
    z_floor = sp["clear"] + 0.22
    y_front = sp["cowl_y"] - 0.20
    parts = []
    parts.append(_seat("Seat_Driver", col, im, -0.36, y_front - 0.75, z_floor))
    parts.append(_seat("Seat_Passenger", col, im, 0.36, y_front - 0.75, z_floor))
    if len(sp["doors"]) > 1:
        parts.append(_seat("Seat_RearL", col, im, -0.36, y_front - 1.35, z_floor))
        parts.append(_seat("Seat_RearR", col, im, 0.36, y_front - 1.35, z_floor))
    # dashboard
    bm = bmesh.new()
    geo.box(bm, (0.0, y_front - 0.12, z_floor + 0.42), (1.55, 0.34, 0.26))
    geo.box(bm, (0.0, y_front - 0.02, z_floor + 0.56), (1.45, 0.16, 0.06))
    me = bpy.data.meshes.new("Dashboard")
    bm.to_mesh(me)
    bm.free()
    dash = bpy.data.objects.new("Dashboard", me)
    common.link(dash, col)
    me.materials.append(im["dash"])
    meshutil.bevel(dash, 0.02, 2, 40.0)
    meshutil.set_uv_rect(dash, atlas.INTERIOR["dash"])
    parts.append(dash)
    # centre console
    bm = bmesh.new()
    geo.box(bm, (0.0, y_front - 0.75, z_floor + 0.14), (0.30, 0.70, 0.20))
    me = bpy.data.meshes.new("Console")
    bm.to_mesh(me)
    bm.free()
    console = bpy.data.objects.new("Console", me)
    common.link(console, col)
    me.materials.append(im["trim"])
    meshutil.bevel(console, 0.02, 2, 40.0)
    meshutil.set_uv_rect(console, atlas.INTERIOR["trim"])
    parts.append(console)
    # steering wheel
    wheel = meshutil.torus("SteeringWheel", (-0.36, y_front - 0.32, z_floor + 0.58),
                            0.165, 0.018, col, im["trim"], major_seg=20, minor_seg=6,
                            rot=(math.radians(66.0), 0.0, 0.0))
    meshutil.set_uv_rect(wheel, atlas.INTERIOR["trim"])
    parts.append(wheel)
    return parts
