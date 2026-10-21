"""Object helpers shared by the npc_cars builders (thin wrappers over lib/common)."""
import math

import bmesh
import bpy
from mathutils import Vector

from lib import common


def bevel(obj, width=0.01, segments=2, angle_deg=30.0):
    """Bevel the sharp edges of a mesh, applied at once.

    The shared library adds a Bevel *modifier*; its evaluation is not
    bit-exact between two runs, so the exported .glb would change on every
    rebuild and Godot would re-import it.  A bmesh bevel is deterministic.
    """
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    limit = math.radians(angle_deg)
    edges = [e for e in bm.edges
             if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > limit]
    if edges:
        bmesh.ops.bevel(bm, geom=edges, offset=width, offset_type="OFFSET",
                        segments=segments, profile=0.5, affect="EDGES",
                        clamp_overlap=True, miter_outer="SHARP")
    bm.to_mesh(me)
    bm.free()
    me.update()
    return obj


def round_mesh(obj, places=6):
    """Round the vertex positions and normals.

    The boolean of the wheel wells and the ray cast of the fitted panels can
    differ in the last bits between two runs; rounding keeps the exported
    .glb byte identical, so a rebuild does not trigger a Godot re-import.
    """
    me = obj.data
    for v in me.vertices:
        v.co = Vector((round(v.co.x, places), round(v.co.y, places),
                       round(v.co.z, places)))
    me.update()
    return obj


def apply_modifiers(obj):
    """Apply every modifier of an object (so the export has nothing to do)."""
    for mod in list(obj.modifiers):
        bpy.context.view_layer.objects.active = obj
        with bpy.context.temp_override(active_object=obj, object=obj,
                                       selected_objects=[obj]):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def shade_smooth(obj, angle_deg=35.0):
    """Smooth shading with sharp edges above `angle_deg` (the hard creases).

    Blender 4.1+ stores the shading in the `sharp_edge` attribute, so this
    is the modern equivalent of the old "auto smooth": the panels are smooth
    and only the real creases stay hard.
    """
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


def obj_from_faces(name, verts, faces, col, materials=None, mat_index=None, smooth=True,
                   recalc=True):
    """Create a mesh object from a vert list and face index tuples."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.update()
    if recalc and len(me.polygons):
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        # n-gons stop the glTF exporter from computing tangents
        ngons = [f for f in bm.faces if len(f.verts) > 4]
        if ngons:
            bmesh.ops.triangulate(bm, faces=ngons)
        bm.to_mesh(me)
        bm.free()
    obj = bpy.data.objects.new(name, me)
    common.link(obj, col)
    for m in (materials or []):
        me.materials.append(m)
    if mat_index is not None:
        for i, poly in enumerate(me.polygons):
            poly.material_index = mat_index[i] if i < len(mat_index) else 0
    if smooth:
        common.smooth(obj, 40.0)
    return obj


def box_mesh(name, centre, size, col, material=None, rot_z=0.0, rot_y=0.0):
    """Axis-aligned (optionally rotated) box object."""
    import math
    bm = bmesh.new()
    from lib import geo
    geo.box(bm, (0, 0, 0), size)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    common.link(obj, col)
    if material is not None:
        me.materials.append(material)
    obj.location = centre
    obj.rotation_euler = (0.0, rot_y, rot_z)
    return obj


def triangulate(obj):
    """Turn the n-gons into triangles (the glTF exporter needs them for tangents)."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    ngons = [f for f in bm.faces if len(f.verts) > 4]
    if ngons:
        bmesh.ops.triangulate(bm, faces=ngons)
    bm.to_mesh(me)
    bm.free()
    return obj


def join_objects(objects, name):
    """Join meshes into one node (the view layer's active object survives)."""
    objects = [o for o in objects if o is not None]
    if not objects:
        return None
    if len(objects) == 1:
        objects[0].name = name
        return objects[0]
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    return objects[0]


def set_parent(child, parent):
    """Parent without moving the child (the parent's inverse is kept in the matrix).

    Unlike lib/common.set_parent this does not depend on matrix_world being
    evaluated, so freshly created objects keep their local transform.
    """
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()
    return child


def set_uv_quad(obj, rect, size=1024):
    """Map a four-vertex quad onto one rectangle of a shared atlas."""
    from . import atlas
    u0, v0, u1, v1 = atlas.uv_rect(rect, size)
    layer = obj.data.uv_layers.get("UVMap") or obj.data.uv_layers.new(name="UVMap")
    corners = ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
    for i, li in enumerate(range(len(obj.data.loops))):
        layer.data[li].uv = corners[min(i, 3)]
    return obj


def planar_uv(obj, axis=None, flip=False):
    """Map every face to the full 0..1 image space (signs, plates, liveries).

    `flip` mirrors u, which is what the -X / +Y facing sides need so the text
    reads the right way round for the viewer.
    """
    me = obj.data
    layer = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    co = [v.co for v in me.vertices]
    lo = [min(c[i] for c in co) for i in range(3)]
    hi = [max(c[i] for c in co) for i in range(3)]
    span = [max(1e-5, hi[i] - lo[i]) for i in range(3)]
    for poly in me.polygons:
        n = poly.normal
        ax = axis if axis is not None else max(range(3), key=lambda i: abs(n[i]))
        ia, ib = {0: (1, 2), 1: (0, 2), 2: (0, 1)}[ax]
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            u = (v[ia] - lo[ia]) / span[ia]
            if flip:
                u = 1.0 - u
            layer.data[li].uv = (u, (v[ib] - lo[ib]) / span[ib])
    return obj


def set_uv_rect(obj, rect, size=1024):
    """Map an object onto one rectangle of a shared atlas (box projection)."""
    from . import atlas
    u0, v0, u1, v1 = atlas.uv_rect(rect, size)
    me = obj.data
    layer = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    co = [v.co for v in me.vertices]
    lo = [min(c[i] for c in co) for i in range(3)]
    hi = [max(c[i] for c in co) for i in range(3)]
    span = [max(1e-5, hi[i] - lo[i]) for i in range(3)]

    def frac(value, i):
        return (value - lo[i]) / span[i]

    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                a, b = frac(v.y, 1), frac(v.z, 2)
            elif ax == 1:
                a, b = frac(v.x, 0), frac(v.z, 2)
            else:
                a, b = frac(v.x, 0), frac(v.y, 1)
            layer.data[li].uv = (u0 + a * (u1 - u0), v0 + b * (v1 - v0))
    return obj


def torus(name, centre, major_r, minor_r, col, material=None, major_seg=24,
          minor_seg=8, rot=(0.0, 0.0, 0.0)):
    """Torus object (axis Z before rotation)."""
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=False, segments=minor_seg, radius=minor_r)
    for v in bm.verts:
        x, y, z = v.co
        v.co = Vector((major_r + x, 0.0, y))
    bmesh.ops.spin(bm, geom=bm.verts[:] + bm.edges[:], cent=(0.0, 0.0, 0.0),
                   axis=(0.0, 0.0, 1.0), dvec=(0.0, 0.0, 0.0), angle=2.0 * math.pi,
                   steps=major_seg, use_duplicate=False)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    common.link(obj, col)
    if material is not None:
        me.materials.append(material)
    obj.location = centre
    obj.rotation_euler = rot
    common.smooth(obj, 50.0)
    return obj
