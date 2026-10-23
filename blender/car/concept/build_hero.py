"""Builds the hero car (the black and white Roadster) from the Khronos Car Concept.

    python tools/gd.py blender run blender/car/concept/build_hero.py -- --out F:/dev/skyrush-out/tmp/car/roadster.glb
    options:  --out FILE      write the glb (copy it to game/assets/cars/roadster/roadster.glb)
              --preview PFX   render studio views to PFX_<view>.png (Cycles, CPU)
              --stage N       1 = import and game frame, 2 = + wheels, body and parts, 3 = + wing,
                              nozzles, markers (default: everything)

The stages are in concept_import.py (the concept into the game frame), concept_body.py (wheels,
body, detachable parts, glass, interior, lamps) and concept_extras.py (wing, nozzles, markers, root,
export). The materials are in hero_materials.py, the mesh helpers in meshkit.py, the preview
studio in studio.py. README.md explains the choices.
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import concept_body
import concept_extras
import concept_import
import hero_materials
import meshkit
import studio

SOURCE = os.path.join(HERE, "source", "CarConcept.glb")

# the preview views: name, yaw, elevation, distance, target (yaw 0 looks at the nose, 90 at the right side)
VIEWS = [
    ("front", 24, 12, 7.5, (0, 0.1, 0.5)),
    ("rear", 204, 12, 7.5, (0, 0.1, 0.5)),
    ("side", 90, 2, 8.5, (0, 0.1, 0.5)),
    ("top", 0, 82, 9.0, (0, 0.1, 0.5)),
    ("wheel", 90, 2, 2.4, (0.98, 1.4, 0.4)),
    ("nose", 35, 18, 3.6, (0.0, 1.9, 0.55)),
    ("tail", 215, 15, 3.8, (0.0, -1.9, 0.6)),
]


def arguments():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"preview": None, "stage": 3, "out": None, "source": SOURCE}
    i = 0
    while i < len(argv):
        key = argv[i].lstrip("-")
        if key in opts and i + 1 < len(argv):
            opts[key] = argv[i + 1]
            i += 2
        else:
            i += 1
    opts["stage"] = int(opts["stage"])
    return opts


def report(objects):
    total = 0
    for name in sorted(objects):
        ob = objects[name]
        if ob.type == "MESH":
            total += meshkit.triangles(ob)
            print("  %-16s %6d tris  %s" % (name, meshkit.triangles(ob), [m.name for m in ob.data.materials]))
    print("TOTAL tris", total)


def main():
    opts = arguments()
    concept = concept_import.Concept(opts["source"])
    mats = hero_materials.make_all()
    concept.straighten_wheels()
    concept.to_game_frame()
    parts = {}
    if opts["stage"] >= 2:
        wheels, _info = concept_body.build_wheels(concept, mats)
        parts.update(wheels)
        hood, front_shell = concept_body.build_hood(concept, mats)
        parts["Hood"] = hood
        lower, panels = concept_body.build_lower_panels(concept, mats)
        parts.update(lower)
        parts.update(concept_body.build_doors(concept, mats))
        parts["Glass"] = concept_body.build_glass(concept, mats)
        parts.update(concept_body.build_lamps(concept, mats))
        parts["Interior"] = concept_body.build_interior(concept, mats)
        parts["Body"] = concept_body.build_body(concept, mats, front_shell, panels)
        concept_body.discard_rest(concept)
    if opts["stage"] >= 3:
        wing, posts = concept_extras.build_wing(mats)
        nozzles, points = concept_extras.build_nozzles(mats)
        parts["Wing"] = wing
        parts["Brake_Light"] = concept_extras.build_brake_light(mats)
        parts["Body"] = meshkit.join([parts["Body"], posts] + nozzles, "Body")
        meshkit.drop_unused_materials(parts["Body"])
        markers = concept_extras.build_markers(points)
        concept_extras.make_root(list(parts.values()) + list(markers.values()))
    if opts["stage"] >= 2:
        report(parts)
    if opts["preview"]:
        studio.setup(samples=32)
        studio.render_views(opts["preview"], VIEWS, size=(1100, 620))
    if opts["out"]:
        studio.clear()
        concept_extras.export(opts["out"])
        print("EXPORTED", opts["out"], os.path.getsize(opts["out"]))
    print("BUILD DONE")


main()
