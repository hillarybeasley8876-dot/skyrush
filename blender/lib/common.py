"""Scene helpers shared by every SKYRUSH Blender build script (core-owned).

Every build script starts with:
    import sys, os; sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))
    from lib import common, mats, uv, geo, export
    common.reset()
Conventions (CONTRACTS.md): metres, Z up, +Y forward, +X right; deterministic (seeded) builds.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.expanduser("~/m/skyrush")
GAME = os.path.join(ROOT, "game")


def reset():
    """Empty scene with metric units and AgX view (for previews)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    try:
        scene.view_settings.view_transform = "AgX"
    except TypeError:
        pass
    return scene


def collection(name, parent=None):
    """Get or create a collection linked under parent (default: scene root)."""
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(col)
    return col


def link(obj, col=None):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    (col or bpy.context.scene.collection).objects.link(obj)
    return obj


def mesh_object(name, bm_or_mesh, col=None, material=None):
    """Create an object from a bmesh (freed afterwards) or an existing mesh datablock."""
    if isinstance(bm_or_mesh, bmesh.types.BMesh):
        me = bpy.data.meshes.new(name)
        bm_or_mesh.to_mesh(me)
        bm_or_mesh.free()
    else:
        me = bm_or_mesh
    obj = bpy.data.objects.new(name, me)
    link(obj, col)
    if material is not None:
        me.materials.append(material)
    return obj


def empty(name, location, direction=(0.0, 1.0, 0.0), up=(0.0, 0.0, 1.0), col=None, size=0.1, parent=None):
    """Marker Empty whose local +Y points along `direction` (the effect direction, CONTRACTS §2)."""
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "SINGLE_ARROW"
    obj.empty_display_size = size
    y = Vector(direction).normalized()
    z = Vector(up)
    x = y.cross(z)
    if x.length < 1e-6:
        x = y.cross(Vector((1.0, 0.0, 0.0)))
    x.normalize()
    z = x.cross(y).normalized()
    obj.matrix_world = Matrix.Translation(Vector(location)) @ Matrix((x, y, z)).transposed().to_4x4()
    link(obj, col)
    if parent is not None:
        set_parent(obj, parent)
    return obj


def set_parent(child, parent):
    """Parent keeping the world transform."""
    mw = child.matrix_world.copy()
    child.parent = parent
    child.matrix_world = mw
    return child


def apply_transforms(obj):
    """Bake location/rotation/scale into the mesh, leaving an identity transform at the origin."""
    if obj.type == "MESH":
        obj.data.transform(obj.matrix_basis)
    obj.matrix_basis = Matrix.Identity(4)
    return obj


def set_origin(obj, point):
    """Move the object origin to a world-space point without moving the geometry."""
    p = Vector(point)
    offset = obj.matrix_world.inverted() @ p
    obj.data.transform(Matrix.Translation(-offset))
    obj.matrix_world = obj.matrix_world @ Matrix.Translation(offset)
    return obj


def smooth(obj, angle_deg=35.0):
    """Smooth shading with sharp edges above angle (keeps hard creases on panels)."""
    me = obj.data
    for poly in me.polygons:
        poly.use_smooth = True
    bm = bmesh.new()
    bm.from_mesh(me)
    limit = math.radians(angle_deg)
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > limit:
            e.smooth = False
    bm.to_mesh(me)
    bm.free()
    return obj


def bevel(obj, width=0.01, segments=2, angle_deg=30.0):
    """Add (not apply) an angle-limited bevel modifier; export.py applies modifiers."""
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle_deg)
    mod.harden_normals = True
    return mod


def join(objects, name):
    """Join meshes into the first one (materials are merged)."""
    objects = [o for o in objects if o is not None]
    if len(objects) == 1:
        objects[0].name = name
        return objects[0]
    ctx = {"active_object": objects[0], "selected_editable_objects": objects}
    with bpy.context.temp_override(**ctx):
        bpy.ops.object.join()
    objects[0].name = name
    return objects[0]


def tri_count(obj):
    me = obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    me.calc_loop_triangles()
    n = len(me.loop_triangles)
    obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
    return n
