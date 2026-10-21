"""Detachable panels, split OUT of the lead's shell (lead note 3, review #2).

The lead's shell (lib/roadster_body.py) is one closed surface. Every detachable
panel is cut out of it with a face selection, so the panel IS the skin: there is
no duplicate surface floating over the body and no sign-inverted offset. Behind
each panel sits a dark inner surface 15 mm inside (along -normal), so the body
never shows a hole when a panel flies off in the damage system.

The pivots follow dossier §8.2; the cut lines come from the JSON (car/regions.py).
"""
import bmesh
import bpy
from mathutils import Vector

from car import cuts, materials, paths, regions, shapes
from lib import common

LIFT = 0.0004          # the panel stands 0.4 mm proud of the skin
INNER = 0.015          # the dark inner surface sits 15 mm inside


def _slot(mat_list, name):
    """The index of a material in the shell's material list."""
    for i, m in enumerate(mat_list):
        if m and m.name == name:
            return i
    return -1


def _extract(bm, keep):
    """A copy of `bm` with only the faces `keep` selects; `bm` keeps the rest."""
    other = bm.copy()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if keep(f)], context="FACES")
    bmesh.ops.delete(other, geom=[f for f in other.faces if not keep(f)], context="FACES")
    for part in (bm, other):
        bmesh.ops.delete(part, geom=[v for v in part.verts if not v.link_faces],
                         context="VERTS")
    return other


def _offset(bm, dist):
    """Move every vertex along its (averaged) normal."""
    bm.normal_update()
    for v in bm.verts:
        v.co = v.co + v.normal * dist


def _inner_surface(bm):
    """A dark plug 15 mm inside the panel, with side walls closing the gap.

    Returns the plug and the number of side walls that could not be built
    (a duplicate face): the count is printed, the error is not swallowed.
    """
    inner = bm.copy()
    for f in inner.faces:
        f.material_index = 0          # the inner surface is a single dark material
    boundary = [(e.verts[0], e.verts[1]) for e in inner.edges if len(e.link_faces) == 1]
    _offset(inner, -INNER)
    skipped = 0
    for a, b in boundary:
        ao = inner.verts.new(a.co)
        bo = inner.verts.new(b.co)
        try:
            inner.faces.new((ao, bo, b, a))
        except ValueError:
            skipped += 1
    bmesh.ops.recalc_face_normals(inner, faces=inner.faces)
    bmesh.ops.reverse_faces(inner, faces=inner.faces)
    return inner, skipped


def _object(name, bm, col, mat_list, pivot=None):
    ob = common.mesh_object(name, bm, col)
    for m in mat_list:
        ob.data.materials.append(m)
    if pivot is not None:
        common.set_origin(ob, pivot)
    return ob


def _panel(name, bm, col, root, mat_list, pivot, inner_name=None, seams=None):
    """A detachable panel plus its dark inner surface.

    `seams` are the dicts of the cut specs the panel's edge follows, so the
    build can print how far the seam is from the JSON line (review r3 #3).
    """
    if not len(bm.faces):
        bm.free()
        return None
    if seams:
        worst = max(e["err"] for e in seams)
        print("  %-16s seam %.1f mm off the JSON line (%s)"
              % (name, worst * 1000.0, ", ".join(e["name"] for e in seams)))
    _offset(bm, LIFT)
    inner, skipped = _inner_surface(bm)
    if skipped:
        print("  %-16s %d side walls skipped (duplicate face)" % (name, skipped))
    ob = _object(name, bm, col, mat_list, pivot)
    common.bevel(ob, width=0.004, segments=2, angle_deg=25.0)
    paths.parent_to(ob, root)
    ib = _object(inner_name or (name + "_Inner"), inner, col,
                 [materials.get("M_InnerDark")], pivot)
    paths.parent_to(ib, root)
    return ob


def _hood_pivot(bvh):
    """The cowl: the hood hinges at the base of the windscreen."""
    y = paths.loft()["panel_lines"]["cowl_y"]
    z = regions.surface_z(bvh, 0.0, y)
    return (0.0, y, z if z else 0.70)


def _front_edge(bm, axis=1):
    """The pivot of a flap: the middle of its front edge."""
    top = max(v.co[axis] for v in bm.verts)
    edge = [v.co for v in bm.verts if v.co[axis] > top - 0.02]
    n = len(edge)
    return tuple(sum(p[i] for p in edge) / n for i in range(3))


def build(col, root, body, glass):
    """Cut every detachable panel out of the body and the glass."""
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bvh = BVHTree.FromBMesh(bm)
    mats = list(body.data.materials)
    glass_mats = list(glass.data.materials)
    regions.trim_index = _slot(mats, "M_BlackTrim")
    regions.paint_index = _slot(mats, "SH_car_paint")
    gbm = bmesh.new()
    gbm.from_mesh(glass.data)
    # the shell is cut along the JSON lines FIRST, so the panels' seams are
    # the lines the dossier draws (review r3 #3)
    seams = cuts.cut_shell(bm)
    cuts.mark_seams(bm, seams)
    _doors(col, root, bm, gbm, mats, glass_mats, seams)
    _hood(col, root, bm, mats, bvh, seams)
    _bumpers(col, root, bm, mats)
    _skirts(col, root, bm, mats)
    _wing(col, root, bm, mats, seams)
    _headlamp_panels(col, root, bm, mats)
    bm.to_mesh(body.data)
    bm.free()
    gbm.to_mesh(glass.data)
    gbm.free()
    body.data.update()
    glass.data.update()


def _doors(col, root, bm, gbm, mats, glass_mats, seams):
    """Butterfly doors: the flank skin between the cut lines + the side glass."""
    sp = paths.loft()["side_profile"]
    pivot_y, pivot_z = sp["door_front_cut"][1][0], sp["door_front_cut"][1][1]
    front = [tuple(p) for p in sp["door_front_cut"]]
    rear = [tuple(p) for p in sp["door_rear_cut"]]
    lower = [front[-1], rear[-1]]
    for sign, tag in ((1, "R"), (-1, "L")):
        skin = _extract(bm, lambda f, s=sign: regions.in_door(f, s)
                        and f.normal.x * s > 0.25)
        glass_part = _extract(gbm, lambda f: regions.in_door_glass(f)
                              and f.normal.x * sign > 0.25)
        if not len(skin.faces):
            skin.free()
            continue
        pivot = (sign * 0.90, pivot_y, pivot_z)
        ob = _panel("Door_" + tag, skin, col, root, mats, pivot,
                    inner_name="Door_Inner_" + tag,
                    seams=cuts.pick(seams, ("door_front_0", "door_front_1",
                                            "door_rear_0", "door_lower")))
        if len(glass_part.faces):
            gob = _object("DoorGlass_" + tag, glass_part, col, glass_mats)
            common.join([ob, gob], "Door_" + tag)
            ob = bpy.data.objects["Door_" + tag]
            common.set_origin(ob, pivot)
        paths.parent_to(ob, root)


def _hood(col, root, bm, mats, bvh, seams):
    """The vent bonnet panel, hinged at the cowl."""
    pl = paths.loft()["panel_lines"]
    skin = _extract(bm, lambda f: regions.in_hood(f))
    _panel("Hood", skin, col, root, mats, _hood_pivot(bvh),
           seams=cuts.pick(seams, ("cowl", "vent_hood")))


def _bumpers(col, root, bm, mats):
    """The black front fascia and the black rear valance."""
    sp = paths.loft()["side_profile"]
    front = _extract(bm, lambda f: regions.in_bumper(f, True))
    pivot_f = (0.0, sp["nose_face"]["y"], 0.25)
    _panel("Bumper_F", front, col, root, mats, pivot_f)
    rear = _extract(bm, lambda f: regions.in_bumper(f, False))
    pivot_r = (0.0, sp["tail_face"]["y"], 0.30)
    _panel("Bumper_R", rear, col, root, mats, pivot_r)


def _skirts(col, root, bm, mats):
    """The black sill strips; they drop 80 mm in suction mode."""
    r = paths.loft()["side_profile"]["rocker"]
    for sign, tag in ((1, "R"), (-1, "L")):
        skin = _extract(bm, lambda f, s=sign: regions.in_skirt(f)
                        and f.normal.x * s > 0.25)
        pivot = (sign * 0.90, 0.0, r["white_lower_edge_z"])
        _panel("Skirt_" + tag, skin, col, root, mats, pivot,
               inner_name="Skirt_Inner_" + tag)


def _wing(col, root, bm, mats, seams):
    """The stowed main element is the deck lid; the parts hang off it."""
    data = paths.loft()["parts"]["wing"]
    skin = _extract(bm, lambda f: regions.in_wing(f))
    le = data["poses"]["stowed"]["le"]
    pivot = (0.0, le[0], le[1])
    ob = _panel("Wing", skin, col, root, mats, pivot,
                seams=cuts.pick(seams, ("wing_edge",)))
    if ob is None:
        return
    ob["poses"] = {k: float(v["pitch_deg"]) for k, v in data["poses"].items()}
    ob["span_half"] = float(data["main_span_half"])
    ob["deploy_contract"] = "rotate the local X axis by -pitch_deg; the slat, " \
                            "the struts and the end plates scale from 0.001 to 1"
    from car import wingparts
    wingparts.build(col, ob, data)


def _headlamp_panels(col, root, bm, mats):
    """The triangular flaps that drop 25 degrees to reveal the jewels."""
    for sign, tag in ((1, "R"), (-1, "L")):
        skin = _extract(bm, lambda f, s=sign: regions.in_headlamp(f, sign)
                        and f.normal.x * s > 0.4)
        if not len(skin.faces):
            skin.free()
            continue
        pivot = _front_edge(skin)
        _panel("HeadlampPanel_" + tag, skin, col, root, mats, pivot,
               inner_name="HeadlampPanel_Inner_" + tag)
