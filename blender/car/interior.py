"""Cockpit: driver seat, COPV tank, yoke, horizontal screen, dash, red strips.

The interior is read through the gold canopy, so it is simplified but tidy: a
moulded bucket seat, a squircle yoke, a low dash with the centre screen, the
white carbon-wrapped COPV in the passenger space and the red ambient strips.
Everything below the belt line is dark (#12141A) or grey (#464551) and nothing
touches the glass (review #7).
"""
import math

import bmesh

from car import materials, paths, shapes, uv_car
from lib import common

BELT_Z = 0.80          # nothing may reach above the belt line


def _mats():
    m = materials
    return {
        "seat": m.get("M_SeatWhite"),
        "suede": m.get("M_Microsuede"),
        "black": m.get("M_CabinBlack"),
        "red": m.get("M_RedAccent"),
        "tank": m.get("M_Copv"),
        "screen": m.get("M_Screen"),
    }


def build_interior(col, root):
    """Seat, tank, yoke, screen and the red ambient strips."""
    m = _mats()
    _seat(col, root, m)
    _tank(col, root, m)
    _cockpit(col, root, m)
    _door_cards(col, root, m)
    seat = common.empty("Seat_Driver", (-0.30, 0.0, 0.45), direction=(0.0, 1.0, 0.0),
                        col=col, size=0.12)
    paths.parent_to(seat, root)


def _seat(col, root, m):
    """The moulded driver bucket: cushion, bolsters, backrest, headrest, frame."""
    bm = bmesh.new()
    x = -0.30
    shapes.box(bm, (x, -0.10, 0.255), (0.42, 0.48, 0.06), 0)
    shapes.box(bm, (x, -0.08, 0.325), (0.40, 0.46, 0.09), 1)
    for sx in (-1, 1):
        shapes.box(bm, (x + sx * 0.205, -0.06, 0.345), (0.07, 0.42, 0.12), 1)
        shapes.box(bm, (x + sx * 0.19, -0.30, 0.58), (0.07, 0.14, 0.46), 1)
    shapes.box(bm, (x, -0.34, 0.58), (0.42, 0.13, 0.46), 1)
    shapes.box(bm, (x, -0.285, 0.58), (0.26, 0.05, 0.38), 2)
    shapes.box(bm, (x, -0.40, 0.865), (0.22, 0.11, 0.13), 1)
    for sx in (-1, 1):
        shapes.box(bm, (x + sx * 0.22, -0.08, 0.215), (0.05, 0.52, 0.05), 0)
    ob = common.mesh_object("Interior", bm, col)
    for key in ("seat", "suede", "black"):
        ob.data.materials.append(m[key])
    common.bevel(ob, width=0.012, segments=2, angle_deg=40)
    paths.parent_to(ob, root)


def _tank(col, root, m):
    """White carbon-wrapped COPV cylinder (0.42 m dia, 0.95 m long) by the driver."""
    bm = bmesh.new()
    r, length = 0.21, 0.95
    shapes.revolve(bm, [(0.0, -length / 2), (r - 0.035, -length / 2), (r, -length / 2 + 0.035),
                        (r, length / 2 - 0.035), (r - 0.035, length / 2), (0.0, length / 2)],
                   seg=64, mat=[0] * 5, axis="X")
    ob = common.mesh_object("COPV_Tank", bm, col)
    ob.data.materials.append(m["tank"])
    ob.location = (0.12, -0.62, 0.52)
    paths.parent_to(ob, root)
    band = bmesh.new()
    shapes.revolve(band, [(r + 0.0015, -0.018), (r + 0.0015, 0.018)], seg=64, mat=[0], axis="X")
    bob = common.mesh_object("COPV_Band", band, col)
    bob.data.materials.append(m["red"])
    bob.location = (0.12, -0.62, 0.52)
    paths.parent_to(bob, root)
    for sign in (1, -1):
        strap = bmesh.new()
        shapes.revolve(strap, [(r + 0.003, -0.012), (r + 0.003, 0.012)], seg=64, mat=[0], axis="X")
        sob = common.mesh_object("COPV_Strap_%s" % ("R" if sign > 0 else "L"), strap, col)
        sob.data.materials.append(m["black"])
        sob.location = (0.12 + sign * 0.33, -0.62, 0.52)
        paths.parent_to(sob, root)


def _cockpit(col, root, m):
    """Yoke, horizontal centre screen, dash, tunnel and pedals."""
    bm = bmesh.new()
    cowl = [(i * 1.34 / 24.0 - 0.67, 0.90, BELT_Z - 0.07 + 0.018 * math.cos(3.0 * (i * 1.34 / 24.0 - 0.67)))
            for i in range(25)]
    shapes.tube(bm, cowl, 0.032, 8, 0)
    shapes.box(bm, (-0.30, 0.78, 0.705), (0.26, 0.14, 0.06), 0)
    shapes.box(bm, (0.02, 0.35, 0.28), (0.34, 1.10, 0.22), 0)
    shapes.box(bm, (0.02, 0.20, 0.42), (0.30, 0.42, 0.10), 0)
    shapes.box(bm, (-0.34, 0.70, 0.235), (0.07, 0.03, 0.12), 0)
    shapes.box(bm, (-0.24, 0.70, 0.235), (0.07, 0.03, 0.12), 0)
    shapes.box(bm, (-0.25, 0.45, 0.16), (0.70, 0.80, 0.03), 0)
    shapes.box(bm, (-0.25, 0.82, 0.18), (0.60, 0.30, 0.05), 0)
    shapes.box(bm, (0.02, 0.42, 0.40), (0.24, 0.26, 0.06), 0)
    shapes.box(bm, (0.02, 0.30, 0.46), (0.05, 0.05, 0.10), 0)
    for i in range(6):
        shapes.box(bm, (0.13, 0.10 + i * 0.045, 0.48), (0.02, 0.02, 0.015), 0)
    for i in range(3):
        shapes.box(bm, (-0.10 + i * 0.10, 0.90, 0.74), (0.06, 0.02, 0.03), 0)
    for sx in (-1, 1):
        shapes.box(bm, (sx * 0.24, 0.58, 0.70), (0.05, 0.06, 0.24), 0)
    shapes.box(bm, (-0.30, -0.62, 0.42), (0.44, 0.06, 0.20), 0)
    shapes.box(bm, (0.0, -0.72, 0.50), (1.20, 0.05, 0.36), 0)
    shapes.box(bm, (0.0, -0.66, 0.68), (1.10, 0.18, 0.03), 0)
    for sx in (-1, 1):
        shapes.box(bm, (sx * 0.62, 0.05, 0.42), (0.06, 1.10, 0.08), 0)
        shapes.box(bm, (sx * 0.50, 0.05, 0.28), (0.04, 0.90, 0.05), 0)
    shapes.box(bm, (-0.30, 0.05, 0.20), (0.46, 0.54, 0.04), 0)
    shapes.box(bm, (0.12, -0.62, 0.34), (0.40, 0.20, 0.10), 0)
    shapes.box(bm, (0.12, -0.62, 0.44), (0.36, 0.16, 0.04), 0)
    ob = common.mesh_object("Cockpit", bm, col)
    ob.data.materials.append(m["black"])
    common.bevel(ob, width=0.005, segments=1, angle_deg=40)
    paths.parent_to(ob, root)
    yb = bmesh.new()
    shapes.tube(yb, shapes.rounded_rect(-0.30, 0.545, 0.700, 0.30, 0.20, 0.055, "XZ"),
                0.018, 8, 0, closed=True)
    shapes.box(yb, (-0.30, 0.545, 0.700), (0.07, 0.05, 0.05), 0)
    shapes.tube(yb, [(-0.30, 0.545, 0.700), (-0.30, 0.68, 0.700), (-0.30, 0.78, 0.700)],
                0.022, 8, 0)
    yob = common.mesh_object("Yoke", yb, col)
    yob.data.materials.append(m["black"])
    common.bevel(yob, width=0.004, segments=2, angle_deg=40)
    paths.parent_to(yob, root)
    sb = bmesh.new()
    shapes.box(sb, (0.10, 0.86, 0.745), (0.44, 0.02, 0.13), 0)
    uv = sb.loops.layers.uv.new("UVMap")
    for f in sb.faces:
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (0.5 + (co.x - 0.10) / 0.44, 0.5 + (co.z - 0.745) / 0.13)
    sob = common.mesh_object("Screen_Centre", sb, col)
    sob.data.materials.append(m["screen"])
    paths.parent_to(sob, root)
    db = bmesh.new()
    shapes.box(db, (-0.30, 0.72, 0.755), (0.20, 0.02, 0.08), 0)
    dob = common.mesh_object("Screen_Driver", db, col)
    dob.data.materials.append(m["screen"])
    uv_car.cube_uv(dob)
    paths.parent_to(dob, root)


def _door_cards(col, root, m):
    """Dark door cards with the red ambient strips, all below the belt line."""
    for sign in (1, -1):
        bm = bmesh.new()
        shapes.box(bm, (sign * 0.76, 0.02, 0.46), (0.04, 1.20, 0.30), 0)
        shapes.box(bm, (sign * 0.73, -0.20, 0.40), (0.10, 0.34, 0.05), 0)
        ob = common.mesh_object("DoorCard_%s" % ("R" if sign > 0 else "L"), bm, col)
        ob.data.materials.append(m["black"])
        common.bevel(ob, width=0.008, segments=2, angle_deg=40)
        paths.parent_to(ob, root)
        rb = bmesh.new()
        shapes.box(rb, (sign * 0.735, 0.10, 0.545), (0.02, 1.00, 0.012), 0)
        rob = common.mesh_object("AmbientStrip_%s" % ("R" if sign > 0 else "L"), rb, col)
        rob.data.materials.append(m["red"])
        paths.parent_to(rob, root)
