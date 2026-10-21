"""Commercial vehicles for the NPC fleet: van, truck and city bus (unit: npc_cars).

One-box bodies: a bevelled shell with a rounded front cap, real wheel-arch
cut-outs with liners, a continuous dark glazed band, a raked cab screen with
real mirrors and pressed door panels.  Every dimension comes from the spec
tables in spec.py.
"""
import math

import bmesh
import bpy

from lib import common, geo, uv

from . import atlas, meshutil

GLASS_DEPTH = 0.05        # how deep the window recesses are cut into the flank
ARCH_MARGIN = 0.055       # clearance between the tyre and the arch cut-out
DOOR_DEPTH = 0.018        # pressed door panels
FRONT_RADIUS = 0.48       # the plan radius of the rounded front cap


def hex_box(name, pts, col, material, bevel=0.05, segments=2, uv_rect=None):
    """Box from 8 corner points (bottom ring then top ring)."""
    bm = bmesh.new()
    verts = [bm.verts.new(p) for p in pts]
    for q in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2),
              (2, 6, 7, 3), (3, 7, 4, 0)):
        bm.faces.new([verts[i] for i in q])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    common.link(obj, col)
    if material is not None:
        me.materials.append(material)
    if bevel > 0.0:
        meshutil.bevel(obj, bevel, segments, 40.0)
    if uv_rect is not None:
        meshutil.set_uv_rect(obj, uv_rect)
    return obj


def cut(obj, cutter):
    """Boolean difference with `cutter`, applied immediately (the cutter goes)."""
    mod = obj.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    ctx = {"active_object": obj, "object": obj, "selected_objects": [obj]}
    with bpy.context.temp_override(**ctx):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    return obj


def slab(y0, y1, z0, z1, x_half, rake=0.0, y_face=None):
    """8 corner points of a slab whose front face leans back by `rake`."""
    y_face = y1 if y_face is None else y_face
    return [
        (-x_half, y0, z0), (x_half, y0, z0), (x_half, y_face, z0), (-x_half, y_face, z0),
        (-x_half, y0, z1), (x_half, y0, z1), (x_half, y_face - rake, z1),
        (-x_half, y_face - rake, z1),
    ]


def _arch_cutters(sp, col, hw, extend=0.2):
    """One cylinder per wheel, used to cut the wheel arches."""
    out = []
    for (wy, wx, r, w) in sp["wheels"]:
        for side in (-1, 1):
            bm = bmesh.new()
            geo.cylinder(bm, (0.0, wy, r), r + ARCH_MARGIN, hw * 2.0 + extend * 2.0,
                         20, axis="X")
            me = bpy.data.meshes.new("arch_cut")
            bm.to_mesh(me)
            bm.free()
            obj = bpy.data.objects.new("arch_cut", me)
            common.link(obj, col)
            out.append((obj, wy, r, side, hw))
    return out


def _flat_panel(name, pts, side, col, material, flip=True):
    """A flat panel on a flank (a window, a sign, a livery) with UVs."""
    if side < 0:
        pts = list(reversed(pts))
    obj = meshutil.obj_from_faces(name, pts, [(0, 1, 2, 3)], col, [material],
                                  smooth=False, recalc=False)
    meshutil.planar_uv(obj, axis=0, flip=(side < 0 and flip))
    return obj


def _side_glass(sp, side, y0, y1, z0, z1, hw, col, mats):
    """A glazed panel set into the flank, with a black surround."""
    x = side * (hw + 0.004)
    frame = _flat_panel("WindowFrame",
                        [(side * (hw + 0.001), y0 - 0.05, z0 - 0.06),
                         (side * (hw + 0.001), y1 + 0.05, z0 - 0.06),
                         (side * (hw + 0.001), y1 + 0.05, z1 + 0.06),
                         (side * (hw + 0.001), y0 - 0.05, z1 + 0.06)],
                        side, col, mats["trim"])
    glass = _flat_panel("Glass",
                        [(x, y0, z0), (x, y1, z0), (x, y1, z1), (x, y0, z1)],
                        side, col, mats["glass"])
    return glass, frame


def _raked_face_y(sp, z):
    """The y of the raked cab front face at height z."""
    cy0, cy1 = sp["cab_y"]
    t = (z - sp["z0"]) / max(1e-5, sp["roof_cab"] - sp["z0"])
    return cy1 - sp["rake"] * t


def _bus_screen(sp, z0, z1, hw, col, mats):
    """The bus windscreen: a wide panel on the front face of the nose."""
    y_face = sp["L"] * 0.5
    x = hw - 0.22
    pts = [(-x, y_face + 0.005, z1), (x, y_face + 0.005, z1),
           (x, y_face + 0.005, z0), (-x, y_face + 0.005, z0)]
    obj = meshutil.obj_from_faces("Glass", pts, [(0, 1, 2, 3)], col,
                                  [mats["glass"]], smooth=False, recalc=False)
    meshutil.planar_uv(obj, axis=1, flip=True)
    return obj


def _cab_screen(sp, z0, z1, hw, col, mats):
    """The cab windscreen: a panel on the raked cab face."""
    cy0, cy1 = sp["cab_y"]
    x = hw * 0.98 - 0.18

    def face_y(z):
        return _raked_face_y(sp, z) + 0.01

    pts = [(-x, face_y(z1), z1), (x, face_y(z1), z1),
           (x, face_y(z0), z0), (-x, face_y(z0), z0)]
    obj = meshutil.obj_from_faces("Glass", pts, [(0, 1, 2, 3)], col,
                                  [mats["glass"]], smooth=False, recalc=False)
    meshutil.planar_uv(obj, axis=1, flip=True)
    return obj


def _round_front(body, sp, col, hw, z0, z1, radius=FRONT_RADIUS):
    """Round the front corners in plan (a modern city bus nose).

    The cutter axis sits one radius back from the front face, so the corner
    is cut away and the nose reads as a rounded cap, not a slab.
    """
    y_face = sp["L"] * 0.5
    for sx in (-1, 1):
        bm = bmesh.new()
        geo.cylinder(bm, (sx * (hw - radius), y_face - radius, (z0 + z1) * 0.5),
                     radius, (z1 - z0) + 0.6, 24, axis="Z")
        me = bpy.data.meshes.new("cut")
        bm.to_mesh(me)
        bm.free()
        cutter = bpy.data.objects.new("cut", me)
        common.link(cutter, col)
        cut(body, cutter)


def _arch_liner(sp, col, mats, wy, r, hw):
    """The black liner inside a wheel arch (a half arch, never below the road)."""
    bm = bmesh.new()
    inner = r + ARCH_MARGIN - 0.012
    steps = 14
    rings = []
    for s in range(steps + 1):
        t = math.pi * s / steps
        y = wy + inner * math.cos(t)
        z = r + inner * math.sin(t)
        rings.append((bm.verts.new((-hw * 0.99, y, z)),
                      bm.verts.new((hw * 0.99, y, z))))
    for s in range(steps):
        a, b = rings[s], rings[s + 1]
        bm.faces.new((a[0], b[0], b[1], a[1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("ArchLiner")
    bm.to_mesh(me)
    bm.free()
    liner = bpy.data.objects.new("ArchLiner", me)
    common.link(liner, col)
    me.materials.append(mats["well"])
    common.smooth(liner, 40.0)
    meshutil.set_uv_rect(liner, atlas.TRIM["plain"])
    return liner


def _glazed_doors(sp, col, mats, hw):
    """The passenger doors: glazed leaves in a black frame, on the right side."""
    out = []
    for index, entry in enumerate(sp.get("door", [])):
        dy0, dy1, dz0, dz1 = entry[:4]
        side = 1 if (len(entry) > 4 and entry[4] == "right") else -1
        name = "Door_FR" if index == 0 else "Door_RR"
        x = side * (hw + 0.006)
        pts = [(x, dy0, dz0), (x, dy1, dz0), (x, dy1, dz1), (x, dy0, dz1)]
        glass = meshutil.obj_from_faces(name, pts, [(0, 1, 2, 3)], col,
                                        [mats["glass"]], smooth=False, recalc=False)
        meshutil.planar_uv(glass, axis=0, flip=(side < 0))
        out.append(glass)
        frame = _flat_panel("WindowFrame",
                            [(side * (hw + 0.002), dy0 - 0.06, dz0 - 0.10),
                             (side * (hw + 0.002), dy1 + 0.06, dz0 - 0.10),
                             (side * (hw + 0.002), dy1 + 0.06, dz1 + 0.04),
                             (side * (hw + 0.002), dy0 - 0.06, dz1 + 0.04)],
                            side, col, mats["trim"])
        out.append(frame)
    return out


def build_box_vehicle(sp, mats, col):
    """Van / truck / bus: shell, cut-out windows, doors, cladding, lamps."""
    L, W = sp["L"], sp["W"]
    hw = W * 0.5
    z0, z1 = sp["z0"], sp["z1"]
    is_bus = sp["name"] == "bus"
    body = _body_shell(sp, mats, col, hw, z0, z1, is_bus)
    if is_bus:
        _round_front(body, sp, col, hw, z0, z1)
    _cut_arches(sp, col, mats, body, hw)
    _glazing(sp, col, mats, body, hw, is_bus)
    _skirt(sp, col, mats, hw, is_bus)
    return body


def _body_shell(sp, mats, col, hw, z0, z1, is_bus):
    """The main shell of a box vehicle (a cab and a cargo box)."""
    L = sp["L"]
    if is_bus:
        # the shell is rounded hard (0.14 m): a city bus has no sharp edges
        body = hex_box("Body", slab(-L * 0.5, L * 0.5, z0, z1 - 0.14, hw), col,
                       mats["paint"], bevel=0.14, segments=4,
                       uv_rect=atlas.TRIM["plain"])
        hex_box("Roof", slab(-L * 0.5 + 0.14, L * 0.5 - 0.14, z1 - 0.16, z1,
                              hw - 0.14), col, mats["paint"], bevel=0.10,
                segments=3, uv_rect=atlas.TRIM["plain"])
        return body
    cy0, cy1 = sp["cab_y"]
    cargo_y0, cargo_y1 = sp["cargo_y"]
    body = hex_box("Body", slab(cargo_y0, cargo_y1, z0, z1, hw), col,
                   mats["paint"], bevel=0.07, uv_rect=atlas.TRIM["plain"])
    cab = hex_box("Cab", slab(cy0, cy1, z0, sp["roof_cab"], hw * 0.98, sp["rake"]),
                  col, mats["paint"], bevel=0.07, uv_rect=atlas.TRIM["plain"])
    if sp["name"] == "truck":
        hex_box("Chassis", slab(-L * 0.5 + 0.2, cy1, z0 - 0.10, z0 + 0.24,
                                hw * 0.8), col, mats["trim"], bevel=0.02,
                uv_rect=atlas.TRIM["trim"])
    return body


def _cut_arches(sp, col, mats, body, hw):
    """Cut the wheel arches out of the shell and line them."""
    for cutter, wy, r, side, half_w in _arch_cutters(sp, col, hw):
        cut(body, cutter)
        _arch_liner(sp, col, mats, wy, r, hw)


def _glazed_band(sp, col, mats, hw):
    """The continuous glazed band of the bus, split by black pillars.

    The panes sit flush in the flank (1 mm proud of the black frame) and a
    black pillar every 1.4 m breaks the band up.
    """
    band = sp["band"]
    y0, y1, z0, z1 = band["y0"], band["y1"], band["z0"], band["z1"]
    step = band.get("pillar", 1.40)
    doors = sp.get("door", [])
    out = []
    y = y0
    while y < y1 - 0.20:
        y_next = min(y1, y + step)
        mid = 0.5 * (y + y_next)
        blocked = any(d[0] - 0.10 < mid < d[1] + 0.10 for d in doors)
        if not blocked and y_next - y > 0.35:
            for side in (-1, 1):
                glass = _flat_panel(
                    "Glass",
                    [(side * (hw + 0.003), y + 0.05, z0), (side * (hw + 0.003), y_next - 0.05, z0),
                     (side * (hw + 0.003), y_next - 0.05, z1), (side * (hw + 0.003), y + 0.05, z1)],
                    side, col, mats["glass"])
                out.append(glass)
        # the black pillar between the panes
        for side in (-1, 1):
            pts = [(side * (hw + 0.002), y_next - 0.05, z0 - 0.02),
                   (side * (hw + 0.002), y_next + 0.05, z0 - 0.02),
                   (side * (hw + 0.002), y_next + 0.05, z1 + 0.02),
                   (side * (hw + 0.002), y_next - 0.05, z1 + 0.02)]
            out.append(_flat_panel("WindowFrame", pts, side, col, mats["trim"]))
        y = y_next
    return out


def _glazing(sp, col, mats, body, hw, is_bus):
    """The side glass band and the windscreen."""
    glass_parts = []
    if is_bus and sp.get("band"):
        for obj in _glazed_band(sp, col, mats, hw):
            if obj.name.startswith("Glass"):
                glass_parts.append(obj)
    for (wy0, wy1, wz0, wz1) in sp["win"]:
        for side in (-1, 1):
            glass, frame = _side_glass(sp, side, wy0, wy1, wz0, wz1, hw, col, mats)
            glass_parts.append(glass)
    wz0, wz1 = sp.get("wind", (0.0, 0.0))
    if wz1 > wz0:
        if is_bus:
            glass_parts.append(_bus_screen(sp, wz0, wz1, hw, col, mats))
        else:
            glass_parts.append(_cab_screen(sp, wz0, wz1, hw, col, mats))
    if glass_parts:
        common.join(glass_parts, "Glass")
    # the passenger doors keep their own node names (Door_FR / Door_RR):
    # the damage unit needs them separate
    _glazed_doors(sp, col, mats, hw)


def _skirt(sp, col, mats, hw, is_bus):
    """The black lower cladding (cut with the arches, so the wheels stay out)."""
    L = sp["L"]
    skirt_y1 = L * 0.5 - 0.05 if is_bus else sp["cargo_y"][0] - 0.05
    skirt = hex_box("Skirt", slab(-L * 0.5 + 0.05, skirt_y1, sp["z0"] - 0.02,
                                  sp["skirt"], hw + 0.012), col, mats["trim"],
                    bevel=0.02, uv_rect=atlas.TRIM["trim"])
    for cutter, wy, r, side, half_w in _arch_cutters(sp, col, hw):
        cut(skirt, cutter)
    return skirt
