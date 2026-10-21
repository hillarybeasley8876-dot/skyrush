"""Details of the commercial vehicles: wheels, lamps, plates, mirrors, signs.

The body shell lives in `boxcar.py`; this module dresses it (the wheels, the
lamp clusters, the number plates, the mirrors, the route signs and the
courier livery).  Every dimension comes from the spec tables in spec.py.
"""
import bmesh
import bpy
from mathutils import Vector

from lib import common, geo

from . import atlas, materials, meshutil, wheels
from .boxcar import hex_box, slab


def _raked_face(sp, z):
    """(y, normal) of a raked cab front face at height z."""
    cy0, cy1 = sp["cab_y"]
    t = (z - sp["z0"]) / max(1e-5, sp["roof_cab"] - sp["z0"])
    y = cy1 - sp["rake"] * t
    nor = Vector((0.0, sp["roof_cab"] - sp["z0"], sp["rake"])).normalized()
    return y, nor


def _panel(name, centre, right, up, width, height, col, material, uv_rect=None,
           normal=None, uv_size=1024):
    """Oriented quad (a lamp, a plate, a sign) with an atlas UV rectangle."""
    if normal is not None:
        up = up - normal * up.dot(normal)
        up.normalize()
        right = right - normal * right.dot(normal)
        right.normalize()
    hw, hh = width * 0.5, height * 0.5
    pts = []
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        p = centre + right * (sx * hw) + up * (sz * hh)
        pts.append((p.x, p.y, p.z))
    obj = meshutil.obj_from_faces(name, pts, [(0, 1, 2, 3)], col, [material],
                                  smooth=False, recalc=False)
    if uv_rect is not None:
        meshutil.set_uv_quad(obj, uv_rect, uv_size)
    return obj


def _box_wheels(sp, mats, col):
    """The wheels of the box fleet (a tandem rear axle on the truck)."""
    tandem = sp.get("tandem", 0.0)
    for (wy, wx, r, w) in sp["wheels"]:
        for side in (-1, 1):
            tag = "%s%s" % ("F" if wy > 0 else "R", "L" if side < 0 else "R")
            inner = -side * tandem if (tandem and wy < 0.0) else 0.0
            wheels.build_wheel_at("Wheel_%s" % tag, r, w, mats, col,
                                  side * wx, wy, face=side, inner=inner)


def _box_lamps(sp, mats, col):
    """The lamp clusters: on the cab face at the front, on the tail at the rear."""
    L = sp["L"]
    hw = sp["W"] * 0.5
    lamp = sp["lamp"]
    for front in (True, False):
        if front and sp["name"] == "bus":
            centre = Vector((0.0, L * 0.5 + 0.005, lamp["z"] + lamp["h"] * 0.5))
            nor = Vector((0.0, 1.0, 0.0))
        elif front:
            y, nor = _raked_face(sp, lamp["z"] + lamp["h"] * 0.5)
            centre = Vector((0.0, y, lamp["z"] + lamp["h"] * 0.5))
        else:
            centre = Vector((0.0, -L * 0.5 - 0.005, lamp["z"] + lamp["h"] * 0.5))
            nor = Vector((0.0, -1.0, 0.0))
        right = Vector((-1.0, 0.0, 0.0)) if front else Vector((1.0, 0.0, 0.0))
        for sx in (-1, 1):
            c = centre + right * (sx * hw * 0.62)
            _panel("Lamp_F" if front else "Lamp_R", c, right, Vector((0, 0, 1)),
                   lamp["w"], lamp["h"], col,
                   mats["lamp_f"] if front else mats["lamp_r"],
                   atlas.TRIM["lamp"] if front else atlas.TRIM["lamp_red"],
                   normal=nor)


def _box_plates(sp, mats, col):
    """The number plates, front and rear."""
    L = sp["L"]
    hw = sp["W"] * 0.5
    z = sp["plate"]["z"]
    for front in (True, False):
        if front and sp["name"] == "bus":
            centre = Vector((0.0, L * 0.5 + 0.006, z))
            nor = Vector((0.0, 1.0, 0.0))
        elif front:
            y, nor = _raked_face(sp, z)
            centre = Vector((0.0, y, z))
        else:
            centre = Vector((0.0, -L * 0.5 - 0.006, z))
            nor = Vector((0.0, -1.0, 0.0))
        right = Vector((-1.0, 0.0, 0.0)) if front else Vector((1.0, 0.0, 0.0))
        _panel("Plate", centre, right, Vector((0, 0, 1)), 0.44, 0.14, col,
               mats["plate"], mats["plate_rect"], normal=nor,
               uv_size=mats["plate_atlas"])


def _box_mirrors(sp, mats, col):
    """The mirrors on their arms."""
    hw = sp["W"] * 0.5
    mir = sp["mirror"]
    for side in (-1, 1):
        bm = bmesh.new()
        geo.box(bm, (side * (hw + mir["arm"] * 0.5), mir["y"], mir["z"]),
                (mir["arm"], 0.05, 0.05))
        geo.box(bm, (side * (hw + mir["arm"]), mir["y"], mir["z"]),
                (mir["size"] * 0.35, 0.10, mir["size"] * 0.5))
        me = bpy.data.meshes.new("Mirror")
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new("Mirror_%s" % ("L" if side < 0 else "R"), me)
        common.link(obj, col)
        me.materials.append(mats["trim"])
        meshutil.bevel(obj, 0.012, 2, 40.0)
        meshutil.set_uv_rect(obj, atlas.TRIM["trim"])


def _route_signs(sp, mats, col):
    """The amber LED route signs: front, side and rear."""
    sign = sp.get("sign")
    if not sign:
        return
    L = sp["L"]
    hw = sp["W"] * 0.5
    sign_mat = materials.image_mat("NPC_sign_bus", "sign_bus_front.png",
                                   emission=(1.0, 0.72, 0.26),
                                   emission_strength=4.0)
    w, h, sz0, sz1 = sign["front"]
    _panel("SignRoute", Vector((0.0, L * 0.5 + 0.006, (sz0 + sz1) * 0.5)),
           Vector((-1.0, 0.0, 0.0)), Vector((0, 0, 1)), w, h,
           col, sign_mat, (0, 0, 1024, 256), uv_size=(1024, 256))
    rear = sign.get("rear")
    if rear:
        rw, rh, rz0, rz1 = rear
        _panel("SignRouteRear", Vector((0.0, -L * 0.5 - 0.006, (rz0 + rz1) * 0.5)),
               Vector((1.0, 0.0, 0.0)), Vector((0, 0, 1)), rw, rh,
               col, sign_mat, (0, 0, 1024, 256), uv_size=(1024, 256))
    side_mat = materials.image_mat("NPC_sign_bus_side", "sign_bus_side.png",
                                   emission=(1.0, 0.72, 0.26),
                                   emission_strength=3.0)
    sw, sh, sz0, sz1, sy = sign["side"]
    for side in (-1, 1):
        pts = [(side * (hw + 0.006), sy - sw * 0.5, sz0),
               (side * (hw + 0.006), sy + sw * 0.5, sz0),
               (side * (hw + 0.006), sy + sw * 0.5, sz1),
               (side * (hw + 0.006), sy - sw * 0.5, sz1)]
        obj = meshutil.obj_from_faces("SignRouteSide", pts, [(0, 1, 2, 3)], col,
                                      [side_mat], smooth=False, recalc=False)
        meshutil.planar_uv(obj, axis=0, flip=(side < 0))


def _van_livery(sp, mats, col):
    """The courier livery of the van (申城快递)."""
    livery = materials.image_mat("NPC_livery_van", "decal_van.png",
                                 alpha_texture=True)
    hw = sp["W"] * 0.5
    box = sp["livery_box"]
    for side in (-1, 1):
        pts = [(side * (hw + 0.008), box["y0"], box["z0"]),
               (side * (hw + 0.008), box["y1"], box["z0"]),
               (side * (hw + 0.008), box["y1"], box["z1"]),
               (side * (hw + 0.008), box["y0"], box["z1"])]
        obj = meshutil.obj_from_faces("Livery", pts, [(0, 1, 2, 3)], col, [livery],
                                      smooth=False, recalc=False)
        meshutil.planar_uv(obj, axis=0, flip=(side < 0))


def _cab_doors(sp, mats, col):
    """The pressed cab doors of the van and the truck."""
    hw = sp["W"] * 0.5
    cy0, cy1 = sp["cab_y"]
    for side in (-1, 1):
        bm = bmesh.new()
        geo.box(bm, (side * (hw * 0.99), (cy0 + cy1) * 0.5, sp["z0"] + 0.55),
                (0.02, 0.85, 0.90))
        me = bpy.data.meshes.new("Door")
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new("Door_F%s" % ("R" if side > 0 else "L"), me)
        common.link(obj, col)
        me.materials.append(mats["paint"])
        meshutil.bevel(obj, 0.01, 2, 40.0)
        meshutil.set_uv_rect(obj, atlas.TRIM["plain"])


def _box_bumpers(sp, mats, col):
    """The bumper bars: low on the cab face, at the tail."""
    L = sp["L"]
    hw = sp["W"] * 0.5
    z0 = sp["z0"]
    is_bus = sp["name"] == "bus"
    for front in (True, False):
        if front and not is_bus:
            y, _ = _raked_face(sp, z0 + 0.10)
            hex_box("Bumper_F",
                    slab(y - 0.10, y + 0.02, z0 - 0.02, z0 + 0.22, hw, 0.05,
                         y_face=y),
                    col, mats["trim"], bevel=0.02, uv_rect=atlas.TRIM["trim"])
            continue
        y = (L * 0.5 - 0.03) if front else (-L * 0.5 + 0.03)
        hex_box("Bumper_F" if front else "Bumper_R",
                [(-hw, y - 0.06, z0 - 0.02), (hw, y - 0.06, z0 - 0.02),
                 (hw, y + 0.06, z0 - 0.02), (-hw, y + 0.06, z0 - 0.02),
                 (-hw, y - 0.06, z0 + 0.22), (hw, y - 0.06, z0 + 0.22),
                 (hw, y + 0.06, z0 + 0.22), (-hw, y + 0.06, z0 + 0.22)],
                col, mats["trim"], bevel=0.02, uv_rect=atlas.TRIM["trim"])


def _bus_seats(sp, mats, col):
    """The passenger benches of the bus."""
    z_floor = sp["z0"] + 0.45
    for i in range(6):
        y = -4.2 + i * 1.5
        bm = bmesh.new()
        geo.box(bm, (0.0, y, z_floor + 0.10), (2.05, 0.50, 0.18))
        geo.box(bm, (0.0, y - 0.28, z_floor + 0.42), (2.05, 0.16, 0.55))
        me = bpy.data.meshes.new("Seat")
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new("Seat_Row%d" % i, me)
        common.link(obj, col)
        me.materials.append(mats["seat"])
        meshutil.bevel(obj, 0.02, 2, 40.0)
        meshutil.set_uv_rect(obj, atlas.INTERIOR["seat"])


def _cab_seats(sp, mats, col):
    """The cab seats of the van and the truck."""
    z_floor = sp["z0"] + 0.55
    cy = (sp["cab_y"][0] + sp["cab_y"][1]) * 0.5
    for sx in (-1, 1):
        bm = bmesh.new()
        geo.box(bm, (sx * 0.36, cy - 0.35, z_floor + 0.08), (0.48, 0.46, 0.14))
        geo.box(bm, (sx * 0.36, cy - 0.58, z_floor + 0.34), (0.48, 0.14, 0.46))
        me = bpy.data.meshes.new("Seat")
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new("Seat_Driver" if sx < 0 else "Seat_Passenger",
                                   me)
        common.link(obj, col)
        me.materials.append(mats["seat"])
        meshutil.bevel(obj, 0.02, 2, 40.0)
        meshutil.set_uv_rect(obj, atlas.INTERIOR["seat"])


def _light_markers(sp, col):
    """The light marker empties (CONTRACTS §6)."""
    L = sp["L"]
    lamp = sp["lamp"]
    common.empty("Light_Front", (0.0, L * 0.5 - 0.15, lamp["z"]),
                 direction=(0.0, 1.0, 0.0), col=col, size=0.3)
    common.empty("Light_Rear", (0.0, -L * 0.5 + 0.15, lamp["z"]),
                 direction=(0.0, -1.0, 0.0), col=col, size=0.3)


def build_box_details(sp, mats, col):
    """Wheels, lamps, plates, mirrors, route signs and livery for the box fleet."""
    is_bus = sp["name"] == "bus"
    _box_wheels(sp, mats, col)
    _box_lamps(sp, mats, col)
    _box_plates(sp, mats, col)
    _box_mirrors(sp, mats, col)
    _route_signs(sp, mats, col)
    if sp.get("livery") == "van":
        _van_livery(sp, mats, col)
    if not is_bus:
        _cab_doors(sp, mats, col)
    _box_bumpers(sp, mats, col)
    if is_bus:
        _bus_seats(sp, mats, col)
    else:
        _cab_seats(sp, mats, col)
    _light_markers(sp, col)
