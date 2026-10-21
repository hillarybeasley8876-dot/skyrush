"""Build every SKYRUSH landmark asset (one command, deterministic).

    tools/blender.sh run blender/landmarks/build_all.py

Runs the procedural texture generators first, then each builder script in its
own module namespace (they call common.reset() themselves).
"""
import os
import runpy
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
for p in (os.path.join(HERE, ".."), HERE):
    if p not in sys.path:
        sys.path.insert(0, p)

import texgen  # noqa: E402
import texsets  # noqa: E402
import tex_pillar  # noqa: E402
import tex_pillar_maps  # noqa: E402

SCRIPTS = [
    "build_pearl.py",
    "build_towers.py",
    "build_shanghai_tower.py",
    "build_lujiazui.py",
    "build_bridges.py",
    "build_pillar.py",
]


def main():
    print("== textures ==")
    texgen.write_all()
    texsets.main()
    tex_pillar.main()
    for s in SCRIPTS:
        print("== %s ==" % s)
        runpy.run_path(os.path.join(HERE, s), run_name="__main__")


if __name__ == "__main__":
    main()
