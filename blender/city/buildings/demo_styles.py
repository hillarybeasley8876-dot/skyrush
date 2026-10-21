"""Demo scene: one block of every building style along a street, for look-dev previews.

    tools/blender.sh run blender/city/buildings/demo_styles.py
    tools/blender.sh preview ~/m/skyrush/tmp/buildings/styles.glb styles
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))

from lib import common, export  # noqa: E402

from city.buildings import kit, plan  # noqa: E402
from city.buildings.ctx import Ctx  # noqa: E402
from city.buildings.styles import heritage, industrial, midrise, neon  # noqa: E402
from city.buildings.styles import office, park, residential, shikumen  # noqa: E402

OUT = os.path.expanduser("~/m/skyrush/tmp/buildings/styles.glb")

STYLES = [
    ("shikumen", shikumen, [8, 12], 2.0),
    ("midrise", midrise, [18, 36], 2.0),
    ("neon_street", neon, [18, 42], 1.0),
    ("residential_slab", residential, [54, 90], 3.0),
    ("office_tower", office, [80, 200], 3.0),
    ("heritage", heritage, [24, 40], 1.5),
    ("industrial", industrial, [10, 18], 4.0),
    ("park", park, [0, 0], 2.0),
]

BLOCK_W = 90.0
BLOCK_D = 70.0


def main():
    common.reset()
    materials = kit.build_materials()
    bag = kit.Bag(materials)
    records = []
    col = common.collection("demo")
    for i, (style, module, heights, setback) in enumerate(STYLES):
        x0 = i * (BLOCK_W + 12.0)
        poly = [[x0, 0.0], [x0 + BLOCK_W, 0.0], [x0 + BLOCK_W, BLOCK_D], [x0, BLOCK_D]]
        block = {"id": "demo_%s" % style, "style": style, "polygon": poly,
                 "height_m": heights, "setback": setback, "seed": 17 + i * 3}
        rng = random.Random(block["seed"])
        ctx = Ctx(block["seed"], bag)
        ctx.origin = (0.0, 0.0)
        ctx.reset_pool()
        frame = plan.Frame(poly)
        module.generate(ctx, block, frame, rng, records)
        print("style %s -> %d records" % (style, len(records)))
    objs = bag.emit(col, "demo")
    # a ground plane so the scene is not floating in the void
    ground = materials["paving"]
    me = bpy.data.meshes.new("ground")
    verts = [(-20.0, -20.0, 0.0), (len(STYLES) * (BLOCK_W + 12.0) + 20.0, -20.0, 0.0),
             (len(STYLES) * (BLOCK_W + 12.0) + 20.0, BLOCK_D + 40.0, 0.0),
             (-20.0, BLOCK_D + 40.0, 0.0)]
    me.from_pydata(verts, [], [(0, 1, 2, 3)])
    g = bpy.data.objects.new("ground", me)
    col.objects.link(g)
    me.materials.append(ground)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    export.export_glb(OUT, objects=objs + [g])
    print("wrote %s" % OUT)


if __name__ == "__main__":
    main()
