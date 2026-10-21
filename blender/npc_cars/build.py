"""Build the SKYRUSH NPC fleet (unit: npc_cars).

    tools/blender.sh run blender/npc_cars/build.py            (all 12 models)
    tools/blender.sh run blender/npc_cars/build.py -- sedan_ev (one model)

Rebuilds every model from scratch (deterministic) and exports
game/assets/cars/npc/<name>.glb. The build fails if a textured surface has no
UV map or if the lamps are not where they belong.
"""
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))

from lib import car_body, common, export, uv  # noqa: E402
from lib.car_profile import Profile  # noqa: E402

from npc_cars import (body, boxcar, boxdetail, details, drone, meshutil,  # noqa: E402
                    palette, spec, wheels)

OUT = os.path.join(common.GAME, "assets", "cars", "npc")

# The subdivision level of the car bodies: level 2 is 23 k triangles for the
# shell alone, level 1 keeps the whole car inside the 30 k budget of the
# brief and still reads as a smooth panel (the cage is dense).
SUBDIV_LEVELS = 1


def export_glb(path, collection):
    """Export one model (Y-up, tangents on, modifiers applied).

    The export goes through the shared library (CONTRACTS §2).  The file is
    only written when the bytes changed: a rebuild that produces the same
    model must not touch the .glb, or Godot re-imports it and the whole team
    waits behind the import lock.
    """
    tmp = path + ".tmp.glb"
    _prepare_images()
    export.export_glb(tmp, collection=collection)
    if _same_bytes(tmp, path):
        os.remove(tmp)
        print("EXPORT %s unchanged" % path)
        return path
    os.replace(tmp, path)   # atomic: consumers never see a half-written file
    print("EXPORT %s (%d objects)" % (path, len(collection.all_objects)))
    return path


TEXTURE_CACHE = os.path.join(os.path.expanduser("~/m/skyrush"), "tmp", "npc_cars",
                             "tex")


def _prepare_images():
    """Let the exporter embed the sheets as WEBP (alpha) or JPEG (opaque).

    The library exports with `export_image_format="AUTO"`, which keeps the
    format of the source file, so every sheet is written to the scratch
    folder in the compressed format and the image is pointed at it.
    """
    os.makedirs(TEXTURE_CACHE, exist_ok=True)
    for img in bpy.data.images:
        if img.source != "FILE" or not img.filepath:
            continue
        alpha = img.alpha_mode != "NONE"
        ext = "webp" if alpha else "jpg"
        base = os.path.splitext(os.path.basename(img.filepath))[0]
        out = os.path.join(TEXTURE_CACHE, "%s.%s" % (base, ext))
        if not os.path.exists(out):
            img.save(filepath=out)
        img.filepath = out
        img.reload()
        img.alpha_mode = "STRAIGHT" if alpha else "NONE"


def _same_bytes(a, b):
    """True when two files hold exactly the same bytes."""
    if not os.path.exists(b) or os.path.getsize(a) != os.path.getsize(b):
        return False
    with open(a, "rb") as fa, open(b, "rb") as fb:
        return fa.read() == fb.read()


def _uv_source(node):
    """UV map name feeding an image node (through a Mapping node), or None."""
    for link in node.inputs["Vector"].links:
        src = link.from_node
        if src.type == "UV_MAP":
            return src.uv_map
        if src.type == "MAPPING":
            for inner in src.inputs["Vector"].links:
                if inner.from_node.type == "UV_MAP":
                    return inner.from_node.uv_map
    return None


def check_assets(col, name):
    """Return a list of contract violations (empty = the model is good)."""
    problems = []
    for obj in col.all_objects:
        if obj.type != "MESH":
            continue
        layers = {l.name for l in obj.data.uv_layers}
        for mat in obj.data.materials:
            if mat is None or not mat.use_nodes:
                continue
            for node in mat.node_tree.nodes:
                if node.type != "TEX_IMAGE" or node.image is None:
                    continue
                uv_name = _uv_source(node)
                if uv_name and uv_name not in layers:
                    problems.append("%s/%s wants UV map %r" % (obj.name, mat.name,
                                                             uv_name))
    lamps = () if name == "police_drone" else (("Lamp_F", 1.0), ("Lamp_R", -1.0))
    for lamp_name, sign in lamps:
        obj = col.objects.get(lamp_name)
        if obj is None:
            problems.append("missing %s" % lamp_name)
            continue
        me = obj.data
        if not me.vertices:
            problems.append("%s has no vertices" % lamp_name)
            continue
        centre = Vector((0.0, 0.0, 0.0))
        for v in me.vertices:
            centre += obj.matrix_world @ v.co
        centre /= len(me.vertices)
        if centre.y * sign <= 0.0:
            problems.append("%s is on the wrong end (y=%.2f)" % (lamp_name, centre.y))
        best = 0.0
        for poly in me.polygons:
            n = (obj.matrix_world.to_3x3() @ poly.normal).normalized()
            best = max(best, n.y * sign)
        if best < 0.6:
            problems.append("%s faces away from the road" % lamp_name)
    return problems


# parts that are merged into one node after the build (draw-call budget)
MERGE_GROUPS = {
    "Interior": ("Seat_", "Dashboard", "Console", "SteeringWheel", "CabinLiner"),
    "Trim": ("Mirror_", "Handle_", "Inner_", "ArchLiner", "Chassis", "Skirt",
             "Intake", "Diffuser", "WindowFrame"),
    "Flares": ("ArchFlare",),
    "Plate": ("Plate", "PlateFrame"),
    "Lamp_F": ("Lamp_F",),
    "Lamp_R": ("Lamp_R",),
    "Livery": ("Livery",),
    "TaxiDecal": ("TaxiDecal",),
    "SignRouteSide": ("SignRouteSide",),
    "Drone_Frame": ("Arm_", "Motor_", "Skid", "Gimbal", "Spotlight", "NavLight"),
}


def merge_groups(col):
    """Join the static parts that share a node name into one mesh each."""
    for name, prefixes in MERGE_GROUPS.items():
        group = [ob for ob in col.all_objects
                 if ob.type == "MESH"
                 and any(ob.name.split(".")[0].startswith(p) for p in prefixes)]
        if len(group) < 2:
            continue
        meshutil.join_objects(group, name)


def build_car(sp, col):
    """Assemble one car: the shared body, the details, the wheels, the cabin."""
    police = sp.get("livery") == "police"
    index = spec.PLATE_ORDER.index(sp["name"])
    mats = palette.vehicle_materials(sp, police, index)
    pr = Profile(sp)
    parts = car_body.build(sp, col, materials=[mats["paint"], mats["trim"],
                                                mats["glass"], mats["gloss"]],
                            levels=SUBDIV_LEVELS)
    # the tiling detail textures (paint, trim, glass grime) want metre UVs,
    # so the noise never stretches over a panel
    uv.box_uv(parts["body"])
    uv.box_uv(parts["glass"])
    meshutil.round_mesh(parts["body"])
    meshutil.round_mesh(parts["glass"])
    details.build_details(pr, sp, mats, col, parts)
    for x, y, z in parts["anchors"]["wheels"]:
        tag = "%s%s" % ("F" if y > 0.0 else "R", "R" if x > 0.0 else "L")
        wheels.build_wheel_at("Wheel_%s" % tag, sp["wr"], sp["ww"], mats, col,
                              x, y, face=1.0 if x > 0.0 else -1.0)
    if sp.get("livery"):
        for obj in col.all_objects:
            if obj.type == "MESH" and mats["paint"].name in \
                    [m.name for m in obj.data.materials if m]:
                body.add_livery_uv(obj, sp)
    return mats


def build_box(sp, col):
    """Van / truck / bus."""
    index = spec.PLATE_ORDER.index(sp["name"])
    mats = palette.vehicle_materials(sp, False, index)
    boxcar.build_box_vehicle(sp, mats, col)
    boxdetail.build_box_details(sp, mats, col)
    return mats


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    want = [a for a in args if not a.startswith("-")]
    common.reset()
    os.makedirs(OUT, exist_ok=True)
    failed = []
    for sp in spec.SPECS:
        if want and sp["name"] not in want:
            continue
        common.reset()
        col = common.collection(sp["name"])
        print("BUILD %s" % sp["name"])
        if sp["kind"] == "drone":
            drone.build(sp, col)
        elif sp["kind"] == "box":
            build_box(sp, col)
        else:
            build_car(sp, col)
        merge_groups(col)
        # split the n-gons (the boolean cuts leave some) so the glTF exporter
        # can build the tangents for the normal maps, and apply every
        # modifier: a modifier that is evaluated at export time is not
        # bit-exact, so the .glb would change on every rebuild
        for obj in col.all_objects:
            if obj.type == "MESH":
                meshutil.apply_modifiers(obj)
                meshutil.triangulate(obj)
        problems = check_assets(col, sp["name"])
        if problems:
            failed.append(sp["name"])
            for p in problems:
                print("  CHECK FAIL %s: %s" % (sp["name"], p))
        root = bpy.data.objects.new(sp["name"], None)
        root.empty_display_type = "PLAIN_AXES"
        root.empty_display_size = 0.4
        common.link(root, col)
        bpy.context.view_layer.update()
        for obj in list(col.all_objects):
            if obj is root:
                continue
            meshutil.set_parent(obj, root)
        path = os.path.join(OUT, "%s.glb" % sp["name"])
        export_glb(path, col)
    if failed:
        print("BUILD FAILED: %s" % ", ".join(failed))
        raise SystemExit(1)
    print("NPC BUILD DONE")


if __name__ == "__main__":
    main()
