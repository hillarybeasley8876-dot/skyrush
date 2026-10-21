"""Print the triangle / material / object statistics of the Bund build (bund unit)."""
import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))

import bpy  # noqa: E402

from lib import common  # noqa: E402


def main():
    path = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else None
    common.reset()
    if path:
        bpy.ops.import_scene.gltf(filepath=path)
    total = 0
    per = {}
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        me = obj.data
        me.calc_loop_triangles()
        n = len(me.loop_triangles)
        total += n
        key = obj.name.split("_")[-1]
        per[key] = per.get(key, 0) + n
    print("OBJECTS %d" % len(bpy.data.objects))
    print("TOTAL TRIS %d" % total)
    for k in sorted(per, key=lambda k: -per[k]):
        print("   %-12s %8d" % (k, per[k]))


if __name__ == "__main__":
    main()
