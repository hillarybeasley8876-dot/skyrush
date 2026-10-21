"""Small helpers that touch the whole car after it is built.

* the arch lips get their own, slightly glossier material (M_ArchLip);
* every mesh must end up with a material (Godot draws its default white
  wherever a surface has none);
* the build prints the triangle budget of every part.
"""
import bpy

from car import materials
from lib import common


def arch_lips(liners):
    """Give the outer lip band of the arch liners the glossier M_ArchLip.

    The lead's builder makes the liners and the lips one mesh with the trim
    material. The lip is the outermost band (its vertices are further out
    than any other), so it is easy to find.
    """
    if liners is None or liners.type != "MESH":
        return None
    me = liners.data
    if not me.materials:
        return None
    lip = materials.get("M_ArchLip")
    if lip is None:
        return None
    me.materials.append(lip)
    outer = max(abs(v.co.x) for v in me.vertices)
    index = len(me.materials) - 1
    for poly in me.polygons:
        if all(abs(me.vertices[vi].co.x) > outer - 0.006 for vi in poly.vertices):
            poly.material_index = index
    return liners


def check_materials(collection):
    """Every mesh surface has a material; returns the list of the broken ones."""
    broken = []
    for ob in collection.all_objects:
        if ob.type != "MESH":
            continue
        if len(ob.data.materials) == 0:
            ob.data.materials.append(materials.get("M_InnerDark"))
            broken.append(ob.name)
            continue
        fixed = 0
        for poly in ob.data.polygons:
            if poly.material_index >= len(ob.data.materials):
                poly.material_index = 0
                fixed += 1
        if fixed:
            broken.append("%s (%d faces)" % (ob.name, fixed))
    return broken


def report(collection):
    """Print the triangle count of the biggest parts."""
    rows = []
    for ob in collection.all_objects:
        if ob.type != "MESH":
            continue
        rows.append((common.tri_count(ob), ob.name))
    rows.sort(reverse=True)
    print("TRIANGLES (top 12):")
    for n, name in rows[:30]:
        print("  %-28s %7d" % (name, n))
    return rows
