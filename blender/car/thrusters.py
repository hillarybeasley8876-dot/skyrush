"""Thrusters: the four rear nozzles R1-R4 and the perimeter nozzles P1-P6.

The nozzle meshes are named NozzleMesh_*; the effect markers are Empties
Nozzle_* whose local +Y is the jet direction (CONTRACTS.md §2/§6). Every size
comes from the JSON `parts` block.

The bezels are chamfered rings (a 3.5 mm lip, not a flat washer) and every
nozzle has a real bore: the hole is punched through the panel AND through the
dark surface behind it, so the gold throat is visible through the hole.
"""
import math

import bmesh
import bpy
from mathutils import Vector

from car import materials, paths, shapes
from lib import common

M_RING, M_THROAT, M_DARK, M_CARBON = 0, 1, 2, 3
THROAT_GOLD, THROAT_DARK = 0, 1   # the throat object's own material slots

CHANNEL_D = 0.028      # the depth of the recessed nozzle channel (car/valance.py)
BEZEL_PROUD = 0.002      # the ring stands 2 mm proud of the panel
BEZEL_LIP = 0.0035       # the chamfer of the ring's outer edge
BORE_CHAMFER = 0.002     # the small chamfer where the ring rolls into the bore
RING_SEG = 64            # the segments of a rear ring
SMALL_RING_SEG = 48      # the segments of a perimeter ring


def _ring_uv(bm, r_max, name="UVMap"):
    """Polar UVs for a bezel ring (u = angle, v = radius) -> the machining marks."""
    layer = bm.loops.layers.uv.get(name) or bm.loops.layers.uv.new(name)
    for f in bm.faces:
        for loop in f.loops:
            co = loop.vert.co
            r = math.hypot(co.x, co.y)
            a = math.atan2(co.y, co.x)
            loop[layer].uv = ((a / (2.0 * math.pi)) % 1.0, min(r / r_max, 1.0))
    return bm


def _throat_uv(bm, d_max, proud=0.0, name="UVMap"):
    """UVs for a throat (u = angle, v = depth) -> the gold gradient downwards."""
    layer = bm.loops.layers.uv.get(name) or bm.loops.layers.uv.new(name)
    for f in bm.faces:
        for loop in f.loops:
            co = loop.vert.co
            a = math.atan2(co.y, co.x)
            loop[layer].uv = ((a / (2.0 * math.pi)) % 1.0,
                              min(max((co.z + proud) / d_max, 0.0), 1.0))
    return bm


def _ring(bm, bezel_od, bore_d, proud=BEZEL_PROUD, seg=RING_SEG):
    """The titanium bezel ring: a chamfered lip around the bore.

    The section is a closed loop: the outer wall stands `proud` of the panel,
    the outer edge rolls over with a 3.5 mm chamfer and the bore entry has a
    2 mm chamfer, so the ring catches a highlight instead of reading as a
    flat washer (review r3 #11).
    """
    r_out = bezel_od / 2.0
    r_bore = bore_d / 2.0
    prof = [(r_out, 0.0),
            (r_out, -proud),
            (r_out - 0.0015, -proud - 0.0016),
            (r_out - BEZEL_LIP, -proud - 0.0018),
            (r_bore + 0.0035, -proud + 0.0004),
            (r_bore + 0.0012, -proud),
            (r_bore, -proud + BORE_CHAMFER),
            (r_bore, 0.0)]
    shapes.revolve(bm, prof, seg=seg, mat=[M_RING] * len(prof), axis="Z", close=True)
    return bm


def _throat(bm, bore_d, recess, proud=0.002, seg=96):
    """The gold throat: a cone from the bore down to the dark bottom.

    The mouth is `proud` of the panel, so the funnel hides the panel behind it
    (no hole has to be cut in the panel). The faces are reversed: the throat is
    looked INTO, so its surface has to face the opening or it would render as a
    black hole.
    """
    r_bore = bore_d / 2.0
    # the lip at the mouth is 1.5 mm wider than the bore: it covers the edge of
    # the hole that is cut in the panel, and the bore itself is the full
    # 55 mm down to the 30 mm deep bottom
    prof = [(r_bore + 0.0015, -proud), (r_bore, 0.0), (r_bore, recess),
            (0.0, recess + 0.006)]
    shapes.revolve(bm, prof, seg=seg, mat=[THROAT_GOLD] * 3, axis="Z")
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    return bm


def _place(ob, pos, into):
    """Point the object's local +Z along `into` (the body side) and move it to `pos`."""
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(Vector(into).normalized())
    ob.rotation_euler = rot.to_euler()
    ob.location = pos


def _punch(target, centre, r, axis, tag, depth=0.03, wall="M_BlackTrim"):
    """Cut a round bore of radius `r` into `target`, centred at `centre`.

    `axis` is the direction of the bore (the unit vector it runs along). The
    boolean leaves a "keyhole" n-gon (the outer boundary with the hole
    traversed twice). Triangulating that n-gon fills the hole again - the
    exporter would do the same - so the triangles that lie inside the bore are
    dropped here. What is left is a clean round hole.

    The wall of the bore takes `wall`: without it the boolean gives the new
    faces the material of slot 0, and the fan ports in the black valance came
    out in white body paint (review r3 #9a).
    """
    col = target.users_collection[0]
    cutter = _cylinder(col, centre, r, 0.2, axis)
    if wall:
        cutter.data.materials.append(materials.get(wall))
    mod = target.modifiers.new("bore", 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.object = cutter
    try:
        mod.solver = 'EXACT'
    except TypeError:
        pass
    try:
        mod.material_mode = 'TRANSFER'
    except (AttributeError, TypeError):
        pass
    bpy.context.view_layer.objects.active = target
    target.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    me = target.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.verts.ensure_lookup_table()
    inv = target.matrix_world.inverted()
    centre_l = inv @ Vector(centre)
    axis_l = (inv.to_3x3() @ Vector(axis)).normalized()
    doomed = [f for f in bm.faces if _in_bore(f, centre_l, axis_l, r, depth)]
    bmesh.ops.delete(bm, geom=doomed, context='FACES')
    bm.to_mesh(me)
    bm.free()
    me.update()
    print("  bored %s at %s r=%.1f mm (%d faces dropped)"
          % (tag, tuple(round(c, 3) for c in centre), r * 1000.0, len(doomed)))


def _in_bore(face, centre, axis, r, depth):
    """True when every corner of the face lies inside the bore."""
    for v in face.verts:
        d = v.co - centre
        radial = (d - d.dot(axis) * axis).length
        if radial > r * 1.02 or abs(d.dot(axis)) > depth:
            return False
    return True


def _cylinder(col, pos, radius, depth, axis):
    """A cutter cylinder (a hole through the shell)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=32, radius1=radius,
                          radius2=radius, depth=depth)
    for v in bm.verts:
        x, y, z = v.co
        if axis == "Y":
            v.co = Vector((x + pos[0], z + pos[1], y + pos[2]))
        elif axis == "Z":
            v.co = Vector((x + pos[0], y + pos[1], z + pos[2]))
        else:
            v.co = Vector((z + pos[0], x + pos[1], y + pos[2]))
    return common.mesh_object("cutter", bm, col)


def build_thrusters(col, root, body=None, valance=None, channel=None):
    """All nozzles and their markers."""
    data = paths.loft()["parts"]
    mats = [materials.get("M_Titanium"), materials.get("M_NozzleGold"),
            materials.get("M_InnerDark"), materials.get("M_Carbon")]
    _rear_nozzles(col, root, data, mats, valance, channel)
    _perimeter_nozzles(col, root, data, mats, body)
    intake = common.empty("Fan_Intake", (0.0, 2.15, 0.13), direction=(0.0, 0.0, -1.0),
                           col=col, size=0.12)
    paths.parent_to(intake, root)


def _rear_nozzles(col, root, data, mats, valance, channel=None):
    """R1-R4: titanium rings in the recessed channel with gold throats."""
    n = data["rear_main_nozzles"]
    face_y = paths.loft()["side_profile"]["tail_face"]["y"]
    plug = bpy.data.objects.get("Bumper_R_Inner")
    # the nozzles stand in the 28 mm deep channel, so their bores go through
    # the floor of the channel and not through the tail face
    y_face = face_y + CHANNEL_D if channel is not None else face_y
    for i, name in enumerate(n["names"]):
        pos = (n["x"][i], n["y"], n["z"])
        for target in (channel, plug):
            if target is not None:
                _punch(target, (pos[0], y_face, pos[2]), n["bore_d"] / 2.0,
                       (0.0, 1.0, 0.0), name, depth=0.03, wall="M_InnerDark")
        _nozzle_pair(col, root, "NozzleMesh_" + name.replace("Nozzle_", ""),
                     (pos[0], y_face, pos[2]), (0.0, 1.0, 0.0),
                     n["bezel_od"], n["bore_d"], n["recess"], mats, RING_SEG, 96)
        marker = common.empty(name, pos, direction=tuple(n["dir"]), col=col, size=0.12)
        paths.parent_to(marker, root)


def _nozzle_pair(col, root, name, pos, into, bezel_od, bore_d, recess, mats, seg,
                 throat_seg=96):
    """The bezel ring and the gold throat of one nozzle (two objects, one UV each)."""
    rb = bmesh.new()
    _ring(rb, bezel_od, bore_d, seg=seg)
    _ring_uv(rb, bezel_od / 2.0)
    ring = common.mesh_object(name, rb, col)
    ring.data.materials.append(mats[0])
    _place(ring, pos, into)
    paths.parent_to(ring, root)
    tb = bmesh.new()
    _throat(tb, bore_d, recess, seg=throat_seg)
    _throat_uv(tb, recess + 0.006, proud=0.002)
    throat = common.mesh_object(name.replace("NozzleMesh_", "NozzleThroat_"), tb, col)
    throat.data.materials.append(mats[1])      # the gold gradient down the bore
    _place(throat, pos, into)
    paths.parent_to(throat, root)
    return ring


def _perimeter_nozzles(col, root, data, mats, body=None):
    """P1-P6: the corner thruster ports (down-facing P1-P4, yaw P5-P6).

    Every port has a real bore: the hole is punched through the panel that
    carries the surface (the shell, the front fascia or the rear valance), so
    the gold throat is not a disc on a closed skin (review r3 #9e).
    """
    for p in data["perimeter_nozzles"]:
        d = Vector(tuple(p["dir"]))
        into = -d
        pos = Vector(tuple(p["pos"]))
        axis = d.normalized()
        target, hit = _surface_hit(body, pos, axis)
        if hit is not None:
            pos = hit
            _punch(target, tuple(pos), 0.055 / 2.0, tuple(axis), p["name"], depth=0.06,
                   wall="M_InnerDark")
        _nozzle_pair(col, root, "NozzleMesh_" + p["name"].replace("Nozzle_", ""),
                     tuple(pos), tuple(into), 0.080, 0.055, 0.030, mats,
                     SMALL_RING_SEG, 64)
        marker = common.empty(p["name"], tuple(p["pos"]), direction=tuple(d),
                              col=col, size=0.12)
        paths.parent_to(marker, root)


def _surface_hit(body, pos, axis):
    """The surface of the car along the jet axis: returns (object, point).

    The ray starts 0.8 m outside the shell and runs against the jet, so the
    first hit is the panel that carries the port.
    """
    from mathutils.bvhtree import BVHTree
    if body is None:
        return None, None
    origin = Vector(pos) + axis * 0.8
    direction = -axis
    best, best_d = None, 1e9
    deps = bpy.context.evaluated_depsgraph_get()
    for ob in bpy.data.collections["Roadster"].all_objects:
        if ob.type != "MESH" or ob.name in ("cutter",):
            continue
        inv = ob.matrix_world.inverted()
        o = inv @ origin
        d = (inv.to_3x3() @ direction).normalized()
        tree = BVHTree.FromObject(ob, deps)
        loc, _n, _i, dist = tree.ray_cast(o, d)
        if loc is not None and dist < best_d:
            best_d = dist
            best = (ob, ob.matrix_world @ loc)
    if best is None:
        return None, None
    return best
