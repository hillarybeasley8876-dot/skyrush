"""The four suction fans and the diffuser of the rear valance.

Photos 08 and 09 show the fans deep inside dark diffuser boxes, so the whole
fan is matte M_InnerDark, its rim is satin black and the grille in front of
it is dark. The diffuser is a set of full-height carbon fins with a
horizontal shelf (review r3 #9a, #9c).
"""
import math

import bmesh
from mathutils import Matrix, Vector

from car import materials, paths, shapes
from lib import common

FAN_TUNNEL = 0.150     # the fan disc sits 150 mm deep in the valance
FAN_BLADES = 11
SHELF_Z = 0.42         # the horizontal shelf above the fans
SHELF_T = 0.020
FIN_T = 0.009          # the diffuser strakes are 9 mm thick
FIN_BOTTOM_Z = 0.10
STRUT_X = (0.0, 0.30, 0.58)     # the JSON's five strakes (one half, mirrored)


def build_fans(col, root, data, valance, plug, face_y):
    """R1-R4: the suction fans, deep inside the diffuser (photos 08/09)."""
    f = data["fans"]
    r = f["d"] / 2.0
    grille = materials.get("M_Grille")
    dark = materials.get("M_InnerDark")
    for i, name in enumerate(f["names"]):
        x, z = f["x"][i], f["z"]
        for target in (valance, plug):
            if target is not None:
                _bore(target, x, z, r - 0.004, face_y, name)
        bm = bmesh.new()
        _fan_disc(bm, r, FAN_TUNNEL)
        ob = common.mesh_object(name, bm, col)
        ob.data.materials.append(dark)
        ob.location = (x, face_y + FAN_TUNNEL, z)
        ob.rotation_euler = Vector((0.0, -1.0, 0.0)).to_track_quat("Z", "Y").to_euler()
        paths.parent_to(ob, root)
        # the satin black rim at the mouth of the port
        rim = bmesh.new()
        _rim_ring(rim, r * 2.0 + 0.006, r * 2.0 - 0.012)
        rob = common.mesh_object(name + "_Rim", rim, col)
        rob.data.materials.append(materials.get("M_BlackTrim"))
        rob.location = (x, face_y - 0.001, z)
        rob.rotation_euler = ob.rotation_euler
        paths.parent_to(rob, root)
        # the dark grille in front of the fan
        gob = common.mesh_object(name + "_Grille", _grille(r), col)
        gob.data.materials.append(grille)
        gob.location = (x, face_y + 0.12, z)
        gob.rotation_euler = ob.rotation_euler
        paths.parent_to(gob, root)


def _bore(target, x, z, r, face_y, tag):
    """Cut the fan port out of the valance (and the surface behind it).

    The wall of the port is M_InnerDark (the tunnel walls of photos 08/09),
    never the white body paint (review r3 #9a).
    """
    from car import thrusters
    thrusters._punch(target, (x, face_y, z), r, (0.0, 1.0, 0.0), tag, depth=0.03,
                     wall="M_InnerDark")


def _fan_disc(bm, r, depth):
    """The fan: a deep shroud, a hub, 11 twisted blades and a dark back plate.

    The local +Z of the fan runs from the disc (z 0) towards the mouth of the
    port (z depth), so the disc sits deep inside the valance. The whole fan is
    matte M_InnerDark: in photos 08/09 the fans sit deep inside dark diffuser
    boxes and hardly show, and the carbon twill stays on the fins
    (review r3 #9a, #9c).
    """
    shapes.revolve(bm, [(r, 0.0), (r, depth), (r - 0.012, depth), (r - 0.012, 0.0)],
                   seg=64, mat=[0] * 3, axis="Z")
    # the back plate: the tunnel is closed, so nothing of the car shows through.
    # The profile runs anticlockwise, so the face towards the mouth points at
    # the camera: with the other winding the plate is culled and the port
    # shows the inside of the car.
    shapes.revolve(bm, [(0.0, -0.001), (r - 0.010, -0.001),
                        (r - 0.010, -0.006), (0.0, -0.006)],
                   seg=64, mat=[0] * 3, axis="Z")
    shapes.revolve(bm, [(0.0, 0.012), (0.030, 0.012), (0.030, 0.05), (0.0, 0.05)],
                   seg=16, mat=[0] * 3, axis="Z")
    for b in range(FAN_BLADES):
        a0 = 2.0 * math.pi * b / FAN_BLADES
        rows = []
        for rr, tw in ((0.026, 0.0), (0.038, 0.03), (0.050, 0.06), (0.062, 0.09),
                       (0.072, 0.12), (0.085, 0.15), (0.098, 0.18), (r - 0.014, 0.22)):
            a = a0 + tw
            hw = 0.30
            rows.append([bm.verts.new((rr * math.cos(a - hw), rr * math.sin(a - hw),
                                        0.014 + 0.022 * (rr / r))),
                         bm.verts.new((rr * math.cos(a + hw), rr * math.sin(a + hw),
                                        0.014 + 0.022 * (rr / r)))])
        for k in range(len(rows) - 1):
            try:
                fa = bm.faces.new((rows[k][0], rows[k + 1][0], rows[k + 1][1], rows[k][1]))
                fa.material_index = 0
            except ValueError:
                pass


def _rim_ring(bm, od, idia):
    """The satin black ring at the mouth of a fan port."""
    r_out, r_in = od / 2.0, idia / 2.0
    prof = [(r_out, 0.0), (r_out, -0.002), (r_in, -0.002), (r_in, 0.0)]
    shapes.revolve(bm, prof, seg=40, mat=[0] * 4, axis="Z", close=True)
    return bm


def _grille(r):
    """The 6 mm hexagonal grille over the fan."""
    gb = bmesh.new()
    centre = gb.verts.new((0.0, 0.0, 0.0))
    ring = []
    for i in range(28):
        a = 2.0 * math.pi * i / 28
        ring.append(gb.verts.new((r * math.cos(a), r * math.sin(a), 0.0)))
    for i in range(28):
        gf = gb.faces.new((centre, ring[i], ring[(i + 1) % 28]))
        gf.material_index = 0
    gv = gb.loops.layers.uv.new("UVMap")
    for gf in gb.faces:
        for loop in gf.loops:
            co = loop.vert.co
            loop[gv].uv = (0.5 + co.x / (2 * r), 0.5 + co.y / (2 * r))
    return gb


def build_diffuser(col, root):
    """Five vertical carbon strakes and the horizontal shelf above the fans."""
    carbon = materials.get("M_Carbon")
    sp = paths.loft()["side_profile"]
    tail_y = sp["tail_face"]["y"]
    tip_y = sp["tail_face"]["diffuser_fin_tip_y"]
    bm = bmesh.new()
    for x in STRUT_X:
        _strake(bm, x, tail_y, tip_y)
    bmesh.ops.mirror(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                     matrix=Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0)), merge_dist=0.0005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = common.mesh_object("Diffuser", bm, col)
    ob.data.materials.append(carbon)
    common.bevel(ob, width=0.002, segments=2, angle_deg=25.0)
    paths.parent_to(ob, root)
    # the origin of a detachable panel is its own centroid (review r3 #5)
    common.set_origin(ob, (0.0, (tail_y + tip_y) / 2.0, (FIN_BOTTOM_Z + SHELF_Z) / 2.0))
    # the horizontal shelf: it closes the top of the four fan boxes
    sb = bmesh.new()
    shapes.box(sb, (0.0, (tail_y + tip_y) / 2.0, SHELF_Z + SHELF_T / 2.0),
               (2.0 * STRUT_X[-1], tip_y - tail_y, SHELF_T), 0)
    sob = common.mesh_object("Diffuser_Shelf", sb, col)
    sob.data.materials.append(materials.get("M_BlackTrim"))
    common.bevel(sob, width=0.002, segments=2, angle_deg=25.0)
    paths.parent_to(sob, root)


def _strake(bm, x, tail_y, tip_y):
    """A full height fin: 9 mm thick, z 0.10 -> 0.42, the tip at tip_y.

    The leading edge is rounded (photo 08), so the fin is built from a
    rounded profile instead of a sharp triangle.
    """
    t = FIN_T / 2.0
    z_lo, z_hi = FIN_BOTTOM_Z, SHELF_Z
    z_mid = (z_lo + z_hi) / 2.0
    outline = [(tail_y, z_lo)]
    steps = 6
    for i in range(steps + 1):               # the rounded tip
        a = math.pi * i / steps
        outline.append((tip_y - (tip_y - tail_y) * 0.35 * (1.0 - math.cos(a)),
                        z_mid + (z_hi - z_mid) * math.sin(a)))
    outline.append((tail_y, z_hi))
    front = [bm.verts.new((x - t, y, z)) for y, z in outline]
    back = [bm.verts.new((x + t, y, z)) for y, z in outline]
    n = len(outline)
    for i in range(n - 1):
        try:
            bm.faces.new((front[i], front[i + 1], back[i + 1], back[i]))
        except ValueError:
            pass
    try:
        bm.faces.new(list(reversed(front)))
        bm.faces.new(back)
    except ValueError:
        pass
