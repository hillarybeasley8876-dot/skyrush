"""Body details: the light bars, the headlamp jewels, the plate, the markers,
the cameras and the front intake (dossier §3, lead notes 4-6).

Every position comes from the JSON `parts` block. The rear light bar is a
14 mm lens with a 6 mm core, sat in a black housing, with the brake light 1 mm
proud of it so the two never fight for the same pixels.
"""
import math

import bmesh
import bpy
from mathutils import Vector

from car import materials, paths, shapes, uv_car
from lib import common

M_EMIT, M_BLACK = 0, 1
BAR_LENS = (110, 10, 18)   # the smoked red lens (linear 0.155 x strength 10 = 1.55)
BAR_CORE = (255, 26, 42)   # the bright 6 mm core
FRONT_LENS = (150, 158, 170)
FRONT_CORE = (242, 246, 255)
BAR_BEVEL = 0.0025         # the emissive bevel above and below the lens
PLATE_FACE_Y = -2.094      # the plate sits 4 mm proud of the tail
PLATE_FRAME_Y = -2.097     # the frame's front face is 3 mm in front of the plate
PLATE_FRAME_D = 0.010      # the frame is 10 mm deep
PLATE_BORDER = 0.005       # the frame is a 5 mm wide ring


def _path_strip(bm, path, z0, z1, mat, uv_layer=None, v_range=None):
    """A vertical strip of height (z1-z0) following a plan poly-path [(x, y), ...].

    `v_range` maps the strip's height onto that part of the v axis of the
    material's map (the bevels of the light bar sample the lens, not the core).
    """
    rows = []
    for x, y in path:
        rows.append([bm.verts.new((x, y, z0)), bm.verts.new((x, y, z1))])
    lengths = [0.0]
    for a, b in zip(path, path[1:]):
        lengths.append(lengths[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    total = max(lengths[-1], 1e-6)
    if uv_layer is None:
        shapes.strip(bm, rows, mat)
        return bm
    v0, v1 = v_range if v_range else (0.0, 1.0)
    uv = bm.loops.layers.uv.get(uv_layer) or bm.loops.layers.uv.new(uv_layer)
    for i in range(len(rows) - 1):
        try:
            f = bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))
        except ValueError:
            continue
        f.material_index = mat
        u0, u1 = lengths[i] / total, lengths[i + 1] / total
        for loop, c in zip(f.loops, [(u0, v0), (u0, v1), (u1, v1), (u1, v0)]):
            loop[uv].uv = c
    return bm


def _mirror_path(path):
    """Mirror a plan path to the left half, keeping the order nose-to-tail."""
    return [(-x, y) for x, y in reversed(path)]


def build_details(col, root, body=None, valance=None):
    """All the surface furniture of the car."""
    d = paths.loft()["parts"]
    red = materials.get("M_LightBarRear")
    white = materials.get("M_LightBarFront")
    amber = materials.get("M_AmberMarker")
    reflector = materials.get("M_RedReflector")
    black = materials.get("M_BlackTrim")
    plate_mat = materials.get("M_Plate")
    _rear_bar(col, root, d, red, black)
    _front_bar(col, root, d, white, black)
    _jewels(col, root, white, black)
    _plate(col, root, d, plate_mat, black, body)
    _markers(col, root, d, amber, reflector, black)
    _intake(col, root, black, valance, bpy.data.objects.get("Bumper_F"))
    _cameras(col, root, black)
    for name, pos, direction in (("Light_Front", (0.0, 2.30, 0.44), (0.0, 1.0, 0.0)),
                                 ("Light_Rear", (0.0, -2.10, 0.85), (0.0, -1.0, 0.0)),
                                 ("Camera_Hood", (0.0, 1.0, 1.05), (0.0, 1.0, 0.0))):
        e = common.empty(name, pos, direction=direction, col=col, size=0.15)
        paths.parent_to(e, root)


def _rear_bar(col, root, d, red, black):
    """The full-width red rear light bar, wrapping around the tail chamfer.

    The lens is 14 mm high with a 6 mm core, and a 2.5 mm emissive bevel runs
    above and below it, so the bar still reads at grazing angles and in the
    chase camera (review r3 #8).
    """
    b = d["light_bar_rear"]
    z0 = b["z_centre"] - b["height"] / 2.0
    z1 = b["z_centre"] + b["height"] / 2.0
    y = b["y"] - 0.002
    half = float(b["x_half"])
    path = [(0.0, y), (0.40, y), (0.72, y), (0.79, y + 0.055), (half, y + 0.140)]
    bm = bmesh.new()
    _path_strip(bm, path, z0, z1, M_EMIT, uv_layer="UVMap")
    _path_strip(bm, _mirror_path(path), z0, z1, M_EMIT, uv_layer="UVMap")
    # the emissive bevels above and below the lens
    _path_strip(bm, path, z0 - BAR_BEVEL, z0, M_EMIT, uv_layer="UVMap", v_range=(0.02, 0.10))
    _path_strip(bm, _mirror_path(path), z0 - BAR_BEVEL, z0, M_EMIT, uv_layer="UVMap",
                v_range=(0.02, 0.10))
    _path_strip(bm, path, z1, z1 + BAR_BEVEL, M_EMIT, uv_layer="UVMap", v_range=(0.90, 0.98))
    _path_strip(bm, _mirror_path(path), z1, z1 + BAR_BEVEL, M_EMIT, uv_layer="UVMap",
                v_range=(0.90, 0.98))
    ob = common.mesh_object("LightBar_Rear", bm, col)
    ob.data.materials.append(red)
    paths.parent_to(ob, root)
    hb = bmesh.new()
    back = [(x, yy + 0.014) for x, yy in path]
    _path_strip(hb, back, z0 - 0.005, z1 + 0.005, M_BLACK)
    _path_strip(hb, _mirror_path(back), z0 - 0.005, z1 + 0.005, M_BLACK)
    hob = common.mesh_object("LightBar_RearHousing", hb, col)
    hob.data.materials.append(black)
    paths.parent_to(hob, root)
    # the brake light: the inner half of the bar, 1 mm proud so it never fights
    brake = materials.get("M_BrakeLight")
    bb = bmesh.new()
    inner = [(x * 0.55, yy - 0.001) for x, yy in path]
    _path_strip(bb, inner, z0 + 0.002, z1 - 0.002, M_EMIT, uv_layer="UVMap")
    _path_strip(bb, _mirror_path(inner), z0 + 0.002, z1 - 0.002, M_EMIT, uv_layer="UVMap")
    bob = common.mesh_object("Brake_Light", bb, col)
    bob.data.materials.append(brake)
    paths.parent_to(bob, root)


def _front_bar(col, root, d, white, black):
    """The thin white front light bar following the swept nose face."""
    b = d["light_bar_front"]
    z0 = b["z_centre"] - b["height"] / 2.0
    z1 = b["z_centre"] + b["height"] / 2.0
    path = [(0.0, 2.288), (0.30, 2.272), (0.46, 2.242), (0.56, 2.207), (0.665, 2.090),
            (0.70, 2.045)]
    bm = bmesh.new()
    _path_strip(bm, path, z0, z1, M_EMIT, uv_layer="UVMap")
    _path_strip(bm, _mirror_path(path), z0, z1, M_EMIT, uv_layer="UVMap")
    ob = common.mesh_object("Lamp_Front", bm, col)
    ob.data.materials.append(white)
    paths.parent_to(ob, root)


def _jewels(col, root, white, black):
    """The two triangular headlamp jewels behind the drop-down panels.

    `Lamp_FL`/`Lamp_FR` ARE the emissive jewels: the damage system dims the
    first lamp it finds by that name, so they must not be an empty black
    triangle (review r3 #5).
    """
    p = paths.loft()["parts"]["headlamps"]["pos"]
    for sign, tag in ((1, "R"), (-1, "L")):
        x, y, z = sign * p[0], p[1], p[2]
        # the dark housing behind the jewels
        bm = bmesh.new()
        pocket = [(y - 0.045, z - 0.020), (y + 0.045, z - 0.012), (y + 0.020, z + 0.022)]
        vs = [bm.verts.new((x - sign * 0.014, py, pz)) for py, pz in pocket]
        try:
            bm.faces.new(vs)
        except ValueError:
            pass
        ob = common.mesh_object("HeadlampHousing_F" + tag, bm, col)
        ob.data.materials.append(materials.get("M_BlackTrim"))
        paths.parent_to(ob, root)
        # the emissive jewels themselves
        cells = bmesh.new()
        for i in range(3):
            shapes.box(cells, (x + sign * 0.002, y - 0.022 + i * 0.022, z),
                       (0.012, 0.017, 0.017), 0)
        cob = common.mesh_object("Lamp_F" + tag, cells, col)
        cob.data.materials.append(materials.get("M_Jewel"))
        uv_car.cube_uv(cob)
        paths.parent_to(cob, root)


def _plate(col, root, d, plate_mat, black, body=None):
    """The Chinese new-energy plate in a black ring, 4 mm proud of the tail.

    The frame is a RING (a hole in the middle), not a solid box: the plate
    sits 3 mm behind the frame's front face, so the two never fight for the
    same pixels (review r3 #2).
    """
    size = (0.48, 0.14)
    z = d["plate"]["centre"][2]
    y = PLATE_FACE_Y
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in ((-size[0] / 2, y, z - size[1] / 2),
                                    (size[0] / 2, y, z - size[1] / 2),
                                    (size[0] / 2, y, z + size[1] / 2),
                                    (-size[0] / 2, y, z + size[1] / 2))]
    f = bm.faces.new(vs)
    uv = bm.loops.layers.uv.new("UVMap")
    for loop, c in zip(f.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        loop[uv].uv = c
    ob = common.mesh_object("Plate_Rear", bm, col)
    ob.data.materials.append(plate_mat)
    paths.parent_to(ob, root)
    frame = bmesh.new()
    _frame_ring(frame, size, PLATE_BORDER, PLATE_FRAME_Y, PLATE_FRAME_D, z)
    fob = common.mesh_object("Plate_Frame", frame, col)
    fob.data.materials.append(black)
    common.bevel(fob, width=0.001, segments=1, angle_deg=25.0)
    paths.parent_to(fob, root)


def _frame_ring(bm, size, border, y_front, depth, z):
    """A rectangular ring (a picture frame) around the plate."""
    w, h = size[0] + 2.0 * border, size[1] + 2.0 * border
    y_mid = y_front + depth / 2.0
    shapes.box(bm, (0.0, y_mid, z + h / 2.0 - border / 2.0), (w, depth, border), 0)
    shapes.box(bm, (0.0, y_mid, z - h / 2.0 + border / 2.0), (w, depth, border), 0)
    shapes.box(bm, (-(w / 2.0 - border / 2.0), y_mid, z), (border, depth, h - 2.0 * border), 0)
    shapes.box(bm, (w / 2.0 - border / 2.0, y_mid, z), (border, depth, h - 2.0 * border), 0)
    return bm


def _markers(col, root, d, amber, reflector, black):
    """Amber side markers on the front wings and red reflectors on the tail."""
    m = d["side_marker_amber"]
    for sign in (1, -1):
        x, y, z = sign * m["pos"][0], m["pos"][1], m["pos"][2]
        bm = bmesh.new()
        shapes.box(bm, (x, y, z), (0.010, m["size"][0], m["size"][1]), 0)
        ob = common.mesh_object("SideMarker_%s" % ("R" if sign > 0 else "L"), bm, col)
        ob.data.materials.append(amber)
        paths.parent_to(ob, root)
    r = d["rear_reflector_red"]
    # the reflector lies flat on the tail face, 1 mm proud of it (review r3 #5)
    for sign in (1, -1):
        x, z = sign * 0.60, r["pos"][2]
        bm = bmesh.new()
        shapes.box(bm, (x, -2.088, z), (r["size"][0], 0.002, r["size"][1]), 0)
        ob = common.mesh_object("Reflector_%s" % ("R" if sign > 0 else "L"), bm, col)
        ob.data.materials.append(reflector)
        paths.parent_to(ob, root)


def _intake(col, root, black, valance=None, front_bumper=None):
    """A 30 mm slot with a flush grille in the black front fascia."""
    sp = paths.loft()["side_profile"]
    y = sp["nose_face"]["y"]
    z0, z1 = 0.205, 0.235
    if valance is not None:
        _intake_slot(valance, y, z0, z1)
    gm = materials.get("M_Grille")
    gb = bmesh.new()
    vs = [gb.verts.new(p) for p in ((-0.15, y - 0.024, z0 + 0.003),
                                    (0.15, y - 0.024, z0 + 0.003),
                                    (0.15, y - 0.024, z1 - 0.003),
                                    (-0.15, y - 0.024, z1 - 0.003))]
    f = gb.faces.new(vs)
    gv = gb.loops.layers.uv.new("UVMap")
    for loop, c in zip(f.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        loop[gv].uv = c
    gob = common.mesh_object("Intake_Grille", gb, col)
    gob.data.materials.append(gm)
    paths.parent_to(gob, root)
    # the carbon splitter: a wide lip under the prow, across the whole fascia
    # (review r3 SHOULD-FIX: the old build was only 0.34 m wide)
    cb = bmesh.new()
    tip_y = sp["nose_face"]["splitter_tip_y"]
    z = sp["nose_face"]["z_bottom"]
    _splitter(cb, y, tip_y, z)
    cob = common.mesh_object("Splitter", cb, col)
    cob.data.materials.append(materials.get("M_Carbon"))
    paths.parent_to(cob, root)
    if front_bumper is not None:
        paths.parent_to(cob, front_bumper)
    # a flush charge-port flap on the haunch
    pb = bmesh.new()
    shapes.box(pb, (0.905, -0.77, 0.93), (0.010, 0.085, 0.030), 0)
    pob = common.mesh_object("ChargePort", pb, col)
    pob.data.materials.append(black)
    paths.parent_to(pob, root)


def _splitter(bm, y, tip_y, z):
    """The wide carbon lip under the prow: 1.10 m across, 10 mm thick.

    The front edge runs across the whole fascia and the prow overhangs in the
    middle, so the lip reads as a blade from the front and from the side
    (review r3 SHOULD-FIX: the old splitter was only 0.34 m wide).
    """
    half = 0.55
    xs = [-half, -0.30, 0.0, 0.30, half]
    front, back = [], []
    for x in xs:
        t = 1.0 - abs(x) / half
        fy = (y - 0.03) + (tip_y - (y - 0.03)) * (t ** 2)
        front.append(bm.verts.new((x, fy, z)))
        back.append(bm.verts.new((x, y - 0.10, z)))
    low = [bm.verts.new((v.co.x, v.co.y, v.co.z - 0.010)) for v in front + back]
    top = front + back
    n = len(xs)
    for i in range(n - 1):
        bm.faces.new((top[i], top[i + 1], top[n + i + 1], top[n + i]))
        bm.faces.new((low[i], low[n + i], low[n + i + 1], low[i + 1]))
    for i in range(n - 1):
        bm.faces.new((top[i], low[i], low[i + 1], top[i + 1]))
        bm.faces.new((top[n + i], top[n + i + 1], low[n + i + 1], low[n + i]))
    for i in (0, n - 1):
        bm.faces.new((top[i], top[n + i], low[n + i], low[i]))


def _intake_slot(valance, y, z0, z1):
    """Cut the 30 mm intake slot out of the front fascia."""
    bm = bmesh.new()
    shapes.box(bm, (0.0, y - 0.010, (z0 + z1) / 2.0), (0.32, 0.050, z1 - z0), 0)
    cutter = common.mesh_object("intake_cut", bm, valance.users_collection[0])
    cutter.data.materials.append(materials.get("M_InnerDark"))
    mod = valance.modifiers.new("intake_slot", "BOOLEAN")
    mod.operation, mod.solver, mod.object = "DIFFERENCE", "EXACT", cutter
    mod.material_mode = "TRANSFER"
    bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
    bpy.context.view_layer.update()
    ctx = {"object": valance, "active_object": valance, "selected_objects": [valance],
           "selected_editable_objects": [valance]}
    with bpy.context.temp_override(**ctx):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def _cameras(col, root, black):
    """The front camera in the fascia and a rear camera above the plate."""
    for name, pos, size in (("Camera_Front", (0.0, 2.278, 0.36), (0.030, 0.012, 0.020)),
                            ("Camera_Rear", (0.0, -2.086, 0.735), (0.026, 0.012, 0.018))):
        bm = bmesh.new()
        shapes.box(bm, pos, size, 0)
        ob = common.mesh_object(name, bm, col)
        ob.data.materials.append(black)
        paths.parent_to(ob, root)
