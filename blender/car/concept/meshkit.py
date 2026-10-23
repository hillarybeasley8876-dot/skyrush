"""Small mesh helpers for the hero car build: bmesh and the depsgraph only, no edit-mode operators.

Every function works in object mode on objects that are linked to the scene.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector


def link(ob, collection=None):
    """Links an object to the scene collection (or `collection`)."""
    target = collection if collection is not None else bpy.context.scene.collection
    if ob.name not in target.objects:
        target.objects.link(ob)
    return ob


def new_object(name, mesh=None):
    """A new object (empty when `mesh` is None) in the scene."""
    ob = bpy.data.objects.new(name, mesh)
    link(ob)
    return ob


def object_from_bm(name, bm, materials=()):
    """Turns a bmesh into a scene object with the given material slots."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    for mat in materials:
        me.materials.append(mat)
    return new_object(name, me)


def world_copy(ob, name=None):
    """A copy of a mesh object with its world transform baked into the vertices."""
    me = ob.data.copy()
    me.transform(ob.matrix_world)
    me.update()
    copy = new_object(name or ob.name, me)
    return copy


def transform(ob, matrix):
    """Bakes a matrix into the vertices of an object (the object transform stays identity)."""
    ob.data.transform(matrix)
    ob.data.update()


def strip_normals(me):
    """Drops the custom normals: the car is smoothed by angle instead."""
    for name in ("custom_normal",):
        attribute = me.attributes.get(name)
        if attribute is not None:
            me.attributes.remove(attribute)


def strip_uvs(me):
    """The hero car carries no UV: its paint is procedural and its other materials are plain colours."""
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])


def smooth_by_angle(me, degrees):
    """Smooth shading with a hard edge wherever two faces meet at more than `degrees`."""
    bm = bmesh.new()
    bm.from_mesh(me)
    limit = math.radians(degrees)
    for face in bm.faces:
        face.smooth = True
    for edge in bm.edges:
        if len(edge.link_faces) == 2:
            edge.smooth = edge.calc_face_angle(0.0) < limit
        else:
            edge.smooth = True
    bm.to_mesh(me)
    bm.free()
    me.update()


def tidy(ob, degrees=35.0):
    """Normals and UVs of a part, ready for the export."""
    strip_normals(ob.data)
    strip_uvs(ob.data)
    smooth_by_angle(ob.data, degrees)


def triangles(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def bounds(ob):
    """(low, high) corners of an object in world space."""
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    matrix = ob.matrix_world
    for v in ob.data.vertices:
        p = matrix @ v.co
        lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
        hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
    return lo, hi


def join(objects, name):
    """Joins mesh objects into one new object (materials are merged by the operator)."""
    objects = [o for o in objects if o is not None]
    if not objects:
        return None
    first = objects[0]
    with bpy.context.temp_override(active_object=first, object=first, selected_objects=objects,
                                   selected_editable_objects=objects):
        bpy.ops.object.join()
    first.name = name
    first.data.name = name
    return first


def decimate(ob, ratio, symmetry=None, angle=None):
    """Collapse-decimates a mesh object in place (the evaluated mesh replaces the data)."""
    mod = ob.modifiers.new("hero_decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    if symmetry:
        mod.use_symmetry = True
        mod.symmetry_axis = symmetry
    graph = bpy.context.evaluated_depsgraph_get()
    evaluated = ob.evaluated_get(graph)
    mesh = bpy.data.meshes.new_from_object(evaluated)
    ob.modifiers.remove(mod)
    old = ob.data
    ob.data = mesh
    bpy.data.meshes.remove(old)
    return ob


def split(ob, picker, name):
    """Moves the faces whose centre satisfies `picker(centre)` into a new object `name`.

    The faces are copied with their material indices; `ob` keeps the others. Returns the new
    object (None when no face was picked).
    """
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    picked = [f.index for f in bm.faces if picker(f.calc_center_median())]
    if not picked:
        bm.free()
        return None
    keep = bm.copy()
    keep.faces.ensure_lookup_table()
    drop = [keep.faces[i] for i in picked]
    bmesh.ops.delete(keep, geom=drop, context="FACES")
    chosen = set(picked)
    take = bm
    take.faces.ensure_lookup_table()
    rest = [take.faces[i] for i in range(len(take.faces)) if i not in chosen]
    bmesh.ops.delete(take, geom=rest, context="FACES")
    mats = list(ob.data.materials)
    new_mesh = bpy.data.meshes.new(name)
    take.to_mesh(new_mesh)
    take.free()
    for mat in mats:
        new_mesh.materials.append(mat)
    keep.to_mesh(ob.data)
    keep.free()
    ob.data.update()
    return new_object(name, new_mesh)


def drop_unused_materials(ob):
    """Removes the material slots no face uses (the join and the split leave them behind)."""
    used = {p.material_index for p in ob.data.polygons}
    if len(used) == len(ob.data.materials):
        return
    old = list(ob.data.materials)
    remap = {}
    new_list = []
    for index in sorted(used):
        remap[index] = len(new_list)
        new_list.append(old[index])
    for p in ob.data.polygons:
        p.material_index = remap[p.material_index]
    ob.data.materials.clear()
    for mat in new_list:
        ob.data.materials.append(mat)


def set_material(ob, material):
    """Gives the whole mesh one material."""
    ob.data.materials.clear()
    ob.data.materials.append(material)
    for p in ob.data.polygons:
        p.material_index = 0


def replace_material(ob, old_name, new_material):
    """Swaps the material slot called `old_name` for `new_material` (same slot index)."""
    for i, mat in enumerate(ob.data.materials):
        if mat is not None and mat.name == old_name:
            ob.data.materials[i] = new_material


def set_origin(ob, point):
    """Moves the object origin to `point` (world) without moving the geometry."""
    offset = Vector(point) - ob.location
    ob.data.transform(Matrix.Translation(-offset))
    ob.location = Vector(point)
    ob.data.update()


def centre_of(ob):
    lo, hi = bounds(ob)
    return (lo + hi) * 0.5
