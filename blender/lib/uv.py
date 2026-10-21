"""UV helpers (core-owned). Tiling materials expect UVs in metres; see mats.pbr(tile_m=...)."""
import bmesh
from mathutils import Vector


def box_uv(obj, scale=1.0, offset=(0.0, 0.0, 0.0), name="UVMap"):
    """Cube projection in world-aligned object space: each face takes the two axes orthogonal to its
    dominant normal axis; 1 UV unit = 1 m / scale. Call after the final shape, before export."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    layer = bm.loops.layers.uv.get(name) or bm.loops.layers.uv.new(name)
    off = Vector(offset)
    for face in bm.faces:
        n = face.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in face.loops:
            p = (loop.vert.co + off) * scale
            if ax == 0:
                uv = (p.y if n.x > 0 else -p.y, p.z)
            elif ax == 1:
                uv = (-p.x if n.y > 0 else p.x, p.z)
            else:
                uv = (p.x, p.y if n.z > 0 else -p.y)
            loop[layer].uv = uv
    bm.to_mesh(me)
    bm.free()
    return obj


def strip_uv(obj, along_axis="length", name="UVMap"):
    """For swept meshes built by geo.sweep (which stores metres along the path in vertex attribute
    'along' and across the profile in 'across'): U = across (m), V = along (m)."""
    me = obj.data
    along = me.attributes.get("along")
    across = me.attributes.get("across")
    if along is None or across is None:
        raise ValueError("strip_uv: mesh has no 'along'/'across' attributes (build it with geo.sweep)")
    uv = me.uv_layers.get(name) or me.uv_layers.new(name=name)
    for loop in me.loops:
        v = loop.vertex_index
        uv.data[loop.index].uv = (across.data[v].value, along.data[v].value)
    return obj


def smart_project(obj, angle_deg=66.0, margin=0.01):
    """Smart UV project (edit-mode operator); falls back to metre-based box UVs without a context."""
    import math
    import bpy
    try:
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(angle_deg), island_margin=margin)
        bpy.ops.object.mode_set(mode="OBJECT")
    except RuntimeError as exc:
        print("uv.smart_project: operator unavailable (%s); using box UVs" % exc)
        box_uv(obj)
