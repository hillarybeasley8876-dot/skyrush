"""Build the Bund (bund unit).

    tools/blender.sh run blender/bund/build.py

Builds every building and the promenade, writes the light sidecar
game/assets/bund/bund_lights.json and exports the glTF files.
"""
import json
import os
import re
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))

from lib import common, export          # noqa: E402
from bund import data, lights, mats, promenade, buildings  # noqa: E402

WASH_TABLE = os.path.join(common.GAME, "assets", "bund", "textures", "wash_atlas.json")


def main():
    common.reset()
    col_buildings = common.collection("BundBuildings")
    col_prom = common.collection("BundPromenade")
    M = mats.build()
    cells = _wash_cells()
    for i, s in enumerate(data.SPECS):
        buildings.build_one(s, col_buildings, M, seed=1923 + i * 7, cell=cells.get(s["node"]))
        print("  built %s" % s["node"])
    _objs, lamps = promenade.build(col_prom, M)
    records = lights.build(col_buildings)
    lights.write_json(os.path.join(common.GAME, "assets", "bund", "bund_lights.json"),
                      records, lamps)
    export.export_glb("assets/bund/bund_buildings.glb", collection=col_buildings)
    export.export_glb("assets/bund/bund_promenade.glb", collection=col_prom)
    for name in ("bund_buildings.glb", "bund_promenade.glb"):
        _set_import_script(os.path.join(common.GAME, "assets", "bund", name))
    _check_watertight()
    _check_glass_facing()
    print("BUND BUILD DONE")


def _wash_cells():
    """The cell of every building in the baked wash atlas (texgen.py writes it).

    The table is what ties the geometry to the light map: the card of a facade samples
    the cell of its own building, so the wash and the wall can never drift apart."""
    if not os.path.exists(WASH_TABLE):
        raise RuntimeError("no wash atlas: run python3 blender/bund/texgen.py first")
    with open(WASH_TABLE) as fh:
        return json.load(fh)


def _check_watertight():
    """The revolved parts have to be closed: an open slot shows as a crack in the render.

    The check runs on the welded mesh, so it is exact (the glTF exporter splits the verts
    at the normal and UV seams, which would report every seam as an open edge)."""
    for obj in bpy.data.objects:
        if obj.type != "MESH" or "dome" not in obj.name:
            continue
        me = obj.data
        bm = bmesh.new()
        bm.from_mesh(me)
        counts = {}
        for face in bm.faces:
            for edge in face.edges:
                key = tuple(sorted(v.index for v in edge.verts))
                counts[key] = counts.get(key, 0) + 1
        open_edges = sum(1 for k in counts if counts[k] == 1)
        bm.free()
        print("  %s: %d open boundary edges" % (obj.name, open_edges))
        if open_edges > 0:
            raise RuntimeError("%s is not watertight (%d open edges)" % (obj.name, open_edges))


def _check_glass_facing():
    """Every pane of glass has to look out of the building.

    A pane that faces inwards is culled by the back-face culling and the opening shows
    the grey core of the mass behind it (review r3, MF2)."""
    for s in data.SPECS:
        parent = bpy.data.objects.get(s["node"])
        if parent is None:
            continue
        for obj in parent.children:
            if obj.type != "MESH":
                continue
            names = [m.name for m in obj.data.materials if m]
            if not any("Window" in n for n in names):
                continue
            for poly in obj.data.polygons:
                c, n = poly.center, poly.normal
                if abs(n.z) > 0.5:
                    continue
                want = None
                if c.x > -1.0:
                    want = (1.0, 0.0)              # the front facade
                elif c.x < -s["depth"] + 1.0:
                    want = (-1.0, 0.0)             # the rear wall
                elif abs(c.y) > s["frontage"] * 0.5 - 1.0:
                    want = (0.0, 1.0 if c.y > 0 else -1.0)   # the flanks
                if want is None:
                    continue
                if n.x * want[0] + n.y * want[1] < 0.5:
                    raise RuntimeError("%s/%s: a pane faces inwards at x %.2f y %.2f z %.2f"
                                       % (s["node"], obj.name, c.x, c.y, c.z))
    print("  every pane of glass looks out of the building")


def _set_import_script(path):
    """Point the glb's .import at the Bund's post-import script.

    glTF cannot carry the wash cards' additive blend and their distance fade, nor the
    vertex-colour multiply of the facade's AO, so the import runs a small script."""
    imp = path + ".import"
    if not os.path.exists(imp):
        print("  no .import for", os.path.basename(path))
        return
    with open(imp) as fh:
        text = fh.read()
    new = re.sub(r'import_script/path="[^"]*"',
                 'import_script/path="res://assets/bund/bund_import.gd"', text)
    if new != text:
        with open(imp, "w") as fh:
            fh.write(new)
        print("  import_script set on", os.path.basename(imp))


if __name__ == "__main__":
    main()
