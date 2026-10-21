"""The rear valance: the recessed nozzle channel and the small round ports
(dossier §3 Rear, review r3 #9).

Photos 08 and 09 show the rear as a dark box: the four nozzles sit in ONE
horizontal recessed channel with five small black round ports between them,
the four suction fans sit deep inside the diffuser (they hardly show), and the
diffuser is a set of full-height vertical fins with a horizontal shelf, not a
row of spikes.

The channel is a real recess: the tail face is cut open, a dark trough is
built 28 mm behind it, and the nozzles stand in the trough. The four fans and
the diffuser are in `car/diffuser.py`.
"""
import math

import bmesh
import bpy
from mathutils import Vector

from car import diffuser, materials, paths, shapes
from lib import common

CHANNEL_W = 1.30       # the recessed channel around the four nozzles
CHANNEL_H = 0.11       # its height
CHANNEL_D = 0.028      # and its depth into the valance
PORT_D = 0.045         # the small round fan / camera ports
PORT_DEPTH = 0.020
PORT_COUNT = 5


def build_valance(col, root, valance, body=None):
    """The channel, the ports, the fans and the diffuser.

    Returns the channel object: the rear nozzles are bored through its floor.
    """
    data = paths.loft()["parts"]
    face_y = paths.loft()["side_profile"]["tail_face"]["y"]
    plug = bpy.data.objects.get("Bumper_R_Inner")
    channel = _channel(col, root, data, valance, body, plug, face_y)
    diffuser.build_fans(col, root, data, valance, plug, face_y)
    diffuser.build_diffuser(col, root)
    return channel


def _flip_normals(ob):
    """Turn every face of a mesh the other way round."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def _cut_box(target, centre, size, name="cut", flip=False):
    """Cut a rectangular pocket out of `target` with a boolean.

    `flip` turns the target's normals the other way round first: the dark
    inner surfaces behind the panels point inwards, and the exact solver
    does not cut a mesh whose normals are inverted.
    """
    bm = bmesh.new()
    shapes.box(bm, centre, size, 0)
    cutter = common.mesh_object(name, bm, target.users_collection[0])
    mod = target.modifiers.new(name, "BOOLEAN")
    mod.operation, mod.solver, mod.object = "DIFFERENCE", "EXACT", cutter
    mod.material_mode = "TRANSFER"
    bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
    bpy.context.view_layer.update()
    if flip:
        _flip_normals(target)
    ctx = {"object": target, "active_object": target, "selected_objects": [target],
           "selected_editable_objects": [target]}
    with bpy.context.temp_override(**ctx):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    if flip:
        _flip_normals(target)
    print("  cut %-10s %s: %d faces" % (name, target.name, len(target.data.polygons)))


def _cut_region(target, x0, x1, z0, z1, y_lo, y_hi):
    """Cut a rectangular hole in a flat panel.

    The panel is split with four bisect planes and the faces inside the
    rectangle are dropped. The split has to come first: the tail cap is one
    big n-gon, and its triangles are too coarse for the hole to be picked out
    by their centres. A boolean cannot be used instead: the dark inner
    surface behind the panel has its normals turned inwards, and the exact
    solver then does not cut it at all.
    """
    bm = bmesh.new()
    bm.from_mesh(target.data)
    inv = target.matrix_world.inverted()
    for co_world, no_world in (((x0, 0.0, 0.0), (1.0, 0.0, 0.0)),
                                ((x1, 0.0, 0.0), (1.0, 0.0, 0.0)),
                                ((0.0, 0.0, z0), (0.0, 0.0, 1.0)),
                                ((0.0, 0.0, z1), (0.0, 0.0, 1.0))):
        co = inv @ Vector(co_world)
        no = (inv.to_3x3() @ Vector(no_world)).normalized()
        geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=co, plane_no=no,
                                clear_inner=False, clear_outer=False)
    mid = inv @ Vector((0.5 * (x0 + x1), 0.5 * (y_lo + y_hi), 0.5 * (z0 + z1)))
    hx, hy, hz = 0.5 * (x1 - x0), 0.5 * (y_hi - y_lo), 0.5 * (z1 - z0)
    doomed = []
    for f in bm.faces:
        c = f.calc_center_median()          # the face centres are in local space
        if abs(c.x - mid.x) <= hx and abs(c.y - mid.y) <= hy and abs(c.z - mid.z) <= hz:
            doomed.append(f)
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(target.data)
    bm.free()
    target.data.update()
    print("  cut %-10s %s: %d faces (%d dropped)"
          % ("channel", target.name, len(target.data.polygons), len(doomed)))


def _port_positions(data):
    """The five small round ports: between the four nozzles and at both ends."""
    x = data["rear_main_nozzles"]["x"]
    out = [x[0] - 0.24]
    for a, b in zip(x[:-1], x[1:]):
        out.append((a + b) / 2.0)
    out.append(x[-1] + 0.24)
    return out[:PORT_COUNT]


def _channel(col, root, data, valance, body, plug, face_y):
    """The recessed horizontal channel that holds the four rear nozzles.

    The channel is a real pocket: the tail face is cut open and a dark trough
    (a floor, four walls and five small port recesses) is built 28 mm behind
    it. The trough is built by hand rather than with a boolean: the exact
    solver drops the floor when a pocket is cut out of a block.
    """
    z = data["rear_main_nozzles"]["z"]
    x = data["rear_main_nozzles"]["x"]
    half = max(abs(x[0]), abs(x[-1])) + 0.29        # the channel runs past the outer nozzle
    y_floor = face_y + CHANNEL_D
    # the tail face and the surface behind it are cut open over the channel
    # the flat black tail face belongs to the Bumper_R panel, the white upper
    # part of the tail cap belongs to the body
    for target in (valance, body, plug):
        if target is None:
            continue
        _cut_region(target, -half, half, z - CHANNEL_H / 2.0, z + CHANNEL_H / 2.0,
                    face_y - 0.05, face_y + 0.05)
    bm = bmesh.new()
    _trough(bm, half, z, face_y, y_floor, _port_positions(data))
    ob = common.mesh_object("NozzleChannel", bm, col)
    ob.data.materials.append(materials.get("M_InnerDark"))
    paths.parent_to(ob, root)
    _backing(col, root, half, z, face_y, y_floor)
    return ob


def _backing(col, root, half, z, face_y, y_floor):
    """The plate that closes the channel behind the trough.

    The trough's floor is a set of quads whose corners do not always meet, so
    the exporter's triangulation leaves small holes in it, and the cabin shows
    through them. The plate is a separate object with four vertices of its
    own, so it is triangulated cleanly and nothing of the car shows through
    the floor or the port holes.
    """
    z0 = z - CHANNEL_H / 2.0
    z1 = z + CHANNEL_H / 2.0
    y = y_floor + PORT_DEPTH + 0.005
    e = 0.002
    bm = bmesh.new()
    _floor_quad(bm, (-half - e, y, z0 - e), (half + e, y, z0 - e),
                (half + e, y, z1 + e), (-half - e, y, z1 + e))
    ob = common.mesh_object("ChannelBacking", bm, col)
    ob.data.materials.append(materials.get("M_InnerDark"))
    paths.parent_to(ob, root)
    return ob


def _quad(bm, a, b, c, d):
    """One quad, wound so that its normal points into the trough."""
    vs = [bm.verts.new(p) for p in (a, b, c, d)]
    try:
        bm.faces.new(vs)
    except ValueError:
        pass


def _floor_quad(bm, a, b, c, d):
    """One quad in the floor plane, wound so that its normal points at the camera.

    The camera is OUTSIDE the trough, so the floor and the port rings have to
    face back out of the tail (-Y). A face wound the other way is culled by
    Godot and the trough shows the inside of the car.
    """
    vs = [bm.verts.new(p) for p in (a, b, c, d)]
    try:
        f = bm.faces.new(vs)
    except ValueError:
        return
    # the normal is computed from the vertices: a fresh face has no normal yet
    n = (vs[1].co - vs[0].co).cross(vs[2].co - vs[0].co)
    if n.y > 0.0:
        bmesh.ops.reverse_faces(bm, faces=[f])


def _trough(bm, half, z, y_face, y_floor, ports):
    """The trough: a floor with five port holes, four walls and the recesses.

    Every face is wound so that its normal points at the camera, which is
    OUTSIDE the trough: the floor points back out of the tail (-Y), the
    bottom wall points up into the trough (+Z) and so on. A face wound the
    other way is culled by Godot, and the trough would show the inside of
    the car through its floor.
    """
    x0, x1 = -half, half
    z0, z1 = z - CHANNEL_H / 2.0, z + CHANNEL_H / 2.0
    r = PORT_D / 2.0
    rh = r * 0.72            # the hole is smaller than the band around it
    # the floor: the strips above and below the port band
    _floor_quad(bm, (x0, y_floor, z0), (x1, y_floor, z0),
                (x1, y_floor, z - r), (x0, y_floor, z - r))
    _floor_quad(bm, (x0, y_floor, z + r), (x1, y_floor, z + r),
                (x1, y_floor, z1), (x0, y_floor, z1))
    cursor = x0
    for px in ports:
        a, b = px - r, px + r
        if a > cursor + 1e-6:                       # the floor between two ports
            _floor_quad(bm, (cursor, y_floor, z - r), (a, y_floor, z - r),
                        (a, y_floor, z + r), (cursor, y_floor, z + r))
        h0, h1 = px - rh, px + rh
        _floor_quad(bm, (h0, y_floor, z - rh), (h1, y_floor, z - rh),
                    (h1, y_floor, z - r), (h0, y_floor, z - r))
        _floor_quad(bm, (h0, y_floor, z + r), (h1, y_floor, z + r),
                    (h1, y_floor, z + rh), (h0, y_floor, z + rh))
        _floor_quad(bm, (a, y_floor, z + r), (h0, y_floor, z + rh),
                    (h0, y_floor, z - rh), (a, y_floor, z - r))
        _floor_quad(bm, (b, y_floor, z - rh), (h1, y_floor, z - rh),
                    (h1, y_floor, z + rh), (b, y_floor, z + r))
        cursor = b
    if cursor < x1 - 1e-6:
        _floor_quad(bm, (cursor, y_floor, z - r), (x1, y_floor, z - r),
                    (x1, y_floor, z + r), (cursor, y_floor, z + r))
    # the four walls of the trough (from the tail face down to the floor)
    _quad(bm, (x0, y_floor, z0), (x1, y_floor, z0),
          (x1, y_face, z0), (x0, y_face, z0))
    _quad(bm, (x0, y_face, z1), (x0, y_floor, z1), (x1, y_floor, z1), (x1, y_face, z1))
    _quad(bm, (x0, y_face, z0), (x0, y_floor, z0), (x0, y_floor, z1), (x0, y_face, z1))
    _quad(bm, (x1, y_face, z0), (x1, y_floor, z1), (x1, y_floor, z0), (x1, y_face, z0))
    # the round ports: a collar on the floor and a cup behind it
    for px in ports:
        _port_cup(bm, px, z, r, rh, y_floor, PORT_DEPTH)
    # the port recesses: four walls and a back, so the ports read as holes
    y_back = y_floor + PORT_DEPTH
    for px in ports:
        h0, h1 = px - rh, px + rh
        _quad(bm, (h0, y_floor, z - rh), (h1, y_floor, z - rh),
              (h1, y_back, z - rh), (h0, y_back, z - rh))
        _quad(bm, (h0, y_back, z + rh), (h1, y_back, z + rh),
              (h1, y_floor, z + rh), (h0, y_floor, z + rh))
        _quad(bm, (h0, y_floor, z - rh), (h0, y_back, z - rh),
              (h0, y_back, z + rh), (h0, y_floor, z + rh))
        _quad(bm, (h1, y_floor, z - rh), (h1, y_floor, z + rh),
              (h1, y_back, z + rh), (h1, y_back, z - rh))
        _quad(bm, (h0, y_back, z - rh), (h1, y_back, z - rh),
              (h1, y_back, z + rh), (h0, y_back, z + rh))


def _port_cup(bm, x, z, r_out, r_in, y_floor, depth, seg=24):
    """A small round port in the channel floor: a collar and a dark cup.

    The collar covers the ragged edge of the hole in the floor and the cup
    gives the port its depth, so the five ports read as small black round
    holes (photo 09) instead of square patches.
    """
    out, inn = [], []
    for i in range(seg):
        a = 2.0 * math.pi * i / seg
        c, s = math.cos(a), math.sin(a)
        out.append((x + r_out * c, y_floor - 0.001, z + r_out * s))
        inn.append((x + r_in * c, y_floor - 0.001, z + r_in * s))
    for i in range(seg):
        j = (i + 1) % seg
        _floor_quad(bm, out[i], out[j], inn[j], inn[i])
    back = [(p[0], y_floor - 0.001 + depth, p[2]) for p in inn]
    for i in range(seg):
        j = (i + 1) % seg
        _inward_quad(bm, inn[i], inn[j], back[j], back[i], x, z)
    for i in range(1, seg - 1):
        _floor_quad(bm, back[0], back[i], back[i + 1], back[0])


def _inward_quad(bm, a, b, c, d, x, z):
    """A quad of a tube wall, wound so that its normal points at the axis."""
    vs = [bm.verts.new(p) for p in (a, b, c, d)]
    try:
        f = bm.faces.new(vs)
    except ValueError:
        return
    n = (vs[1].co - vs[0].co).cross(vs[2].co - vs[0].co)
    mid = (vs[0].co + vs[2].co) * 0.5
    if n.x * (mid.x - x) + n.z * (mid.z - z) > 0.0:
        bmesh.ops.reverse_faces(bm, faces=[f])
