"""Build the whole hero Roadster and export the glb.

Run:  tools/blender.sh run blender/car/build_all.py
The shell comes from the lead's builder (lib/roadster_body.py); the detachable
panels are cut out of it (car/panels.py) and everything else is added here.
"""
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))
import bpy  # noqa: E402

from car import (details, finishing, interior, matset, merge, mesh_utils, panels,  # noqa: E402
                 paths, suspension, texmaps, thrusters, uv_car, valance, wheels)
from lib import common, export, roadster_body  # noqa: E402

OUT = os.path.join(paths.ASSETS, "roadster.glb")
# the maps gen_textures.py makes (the shell's own maps are made inside Blender
# by car/texmaps.py, because they follow the smart UV projection)
TEXTURES = ("tyre_base_f.png", "plate.png", "lightbar_rear.png", "carbon_nor.png",
            "blacktrim_nor.png", "gold_nor.png", "titanium_nor.png")


def ensure_textures():
    """Generate the image textures if they are not there yet (deterministic)."""
    if all(os.path.exists(paths.tex(n)) for n in TEXTURES):
        return
    gen = os.path.join(paths.ROOT, "blender", "car", "gen_textures.py")
    subprocess.run(["/usr/bin/python3", gen], check=True)


def main():
    ensure_textures()
    common.reset()
    col = common.collection("Roadster")
    root = common.empty("Roadster", (0.0, 0.0, 0.0), col=col, size=0.5)
    matset.build_all()
    body, glass, liners = roadster_body.build(col)
    for ob in (body, glass, liners):
        paths.parent_to(ob, root)
    finishing.arch_lips(liners)
    panels.build(col, root, body, glass)
    rear_valance = bpy.data.objects.get("Bumper_R")
    channel = valance.build_valance(col, root, rear_valance, body)
    thrusters.build_thrusters(col, root, body, rear_valance, channel)
    details.build_details(col, root, body, rear_valance)
    wheels.build_wheels(col, root)
    interior.build_interior(col, root)
    suspension.build_suspension(col, root)
    _uvs(col, body, glass)
    merge.merge_details(root)
    texmaps.build(body, glass)
    broken = finishing.check_materials(col)
    if broken:
        print("MATERIALS FIXED (no material): %s" % ", ".join(broken))
    finishing.report(col)
    _export(col)
    tris = sum(common.tri_count(o) for o in col.objects if o.type == "MESH")
    print("TRIS %d objects %d" % (tris, len(col.objects)))


def _export(col):
    """Export the glb and only copy it into game/ when its bytes changed.

    Godot re-imports the glb (and every texture it carries) whenever the file
    moves, so an unchanged model must not touch the game folder (lead note
    IMPORT-CHURN).
    """
    os.makedirs(paths.SCRATCH, exist_ok=True)
    tmp = os.path.join(paths.SCRATCH, "roadster.glb")
    export.export_glb(tmp, collection=col)
    with open(tmp, "rb") as f:
        data = f.read()
    if os.path.exists(OUT) and open(OUT, "rb").read() == data:
        print("glb unchanged (%d bytes)" % len(data))
    else:
        with open(OUT, "wb") as f:
            f.write(data)
        print("glb written (%d bytes)" % len(data))


def _uvs(col, body, glass):
    """The UV layers each material expects, and the shading of every mesh."""
    for ob in list(col.objects):
        if ob.type != "MESH":
            continue
        uv_car.apply(ob)
        if ob not in (body, glass):
            mesh_utils.shade_smooth_sharp(ob)
        mesh_utils.finish_shading(ob)


main()
