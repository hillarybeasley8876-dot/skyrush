"""Shading helpers: smooth panels with crisp creases (lead note 1).

The shell is shaded smooth with the K-row creases and the material borders kept
sharp; a Weighted Normal modifier (face-area mode, keep sharp) then flattens the
big panels so no triangle seam shows. A Triangulate modifier at the end of the
stack gives the glTF exporter the triangles it needs for the tangents.
"""
import math

import bmesh
import bpy

SHARP_ANGLE = 25.0


def shade_smooth_sharp(ob, angle=SHARP_ANGLE):
    """Smooth shading, sharp edges above the angle (and the material borders)."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    limit = math.radians(angle)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) != 2:
            e.smooth = False
            continue
        f1, f2 = e.link_faces
        mats_differ = f1.material_index != f2.material_index
        e.smooth = not (mats_differ or e.calc_face_angle(0.0) > limit)
    bm.to_mesh(me)
    bm.free()
    me.update()
    return ob


def finish_shading(ob, weight=40):
    """Weighted normals (keeps the sharp edges) + a triangulate for the tangents."""
    for m in list(ob.modifiers):
        if m.type in {"WEIGHTED_NORMAL", "TRIANGULATE"}:
            ob.modifiers.remove(m)
    wn = ob.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    wn.keep_sharp = True
    wn.weight = weight
    wn.mode = "FACE_AREA"
    tr = ob.modifiers.new("Triangulate", "TRIANGULATE")
    tr.quad_method = "SHORTEST_DIAGONAL"
    tr.ngon_method = "BEAUTY"
    return ob


def small_faces(ob, limit=0.001):
    """Faces smaller than `limit` m^2 (the sliver check of lead note 1)."""
    me = ob.data
    bad = 0
    for p in me.polygons:
        if p.area < limit:
            bad += 1
    return bad


def non_manifold_edges(ob):
    """Edges that do not have exactly two faces."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    count = sum(1 for e in bm.edges if len(e.link_faces) != 2)
    bm.free()
    return count


def face_stats(ob, limits=(0.0001, 0.001, 0.01)):
    """How many faces are below each area limit (m^2) and the median area."""
    areas = sorted(p.area for p in ob.data.polygons)
    n = len(areas)
    out = [sum(1 for a in areas if a < lim) for lim in limits]
    return {"faces": n, "under": out, "median": areas[n // 2] if n else 0.0}
