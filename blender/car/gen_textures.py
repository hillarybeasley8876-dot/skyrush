"""Generate the hero car's image textures (deterministic, numpy + PIL).

Run:  /usr/bin/python3 blender/car/gen_textures.py
Output: game/assets/cars/roadster/textures/*.png

The maps that depend on the shell itself (the panel-gap normal map and the
canopy frit band) are generated inside Blender from the real mesh, because the
lead's shell uses a smart UV projection: see blender/car/texmaps.py.
"""
import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))

from car import tex_body, tex_common as tc, tex_parts, tex_wheels  # noqa: E402


def main():
    os.makedirs(tc.OUT, exist_ok=True)
    print("generating textures in", tc.OUT)
    d = tc.loft()
    wheels = d["wheels"]
    tex_wheels.tyre_map("F", wheels["front"]["size"])
    tex_wheels.tyre_map("R", wheels["rear"]["size"])
    tex_wheels.disc_map()
    tex_wheels.metal_maps()
    tex_wheels.nozzle_gold_map()
    tex_wheels.wheel_maps()
    tex_body.plate_map()
    lb = d["parts"]["light_bar_rear"]
    # the brief's values: the lens is (110,10,18) and only the 6 mm core is
    # (255,26,42). At the strength of 10 the lens reaches 1.55 and the core 10,
    # so both bloom (ART §4: the HDR threshold is 1.1) and the bar reads as a
    # pink-white core inside a red halo, as in photo 19.
    tex_body.lightbar_map("lightbar_rear.png", (255, 26, 42), (110, 10, 18),
                          6.0, lb["height"] * 1000.0, 280, 4)
    tex_body.brakelight_map()
    fb = d["parts"]["light_bar_front"]
    tex_body.lightbar_map("lightbar_front.png", (242, 246, 255), (150, 158, 170),
                          4.0, fb["height"] * 1000.0, 230, 4)
    tex_body.grille_map()
    tex_body.lens_map()
    tex_body.redstrip_map()
    tex_parts.carbon_maps()
    tex_parts.trim_maps()
    tex_parts.interior_maps()
    tex_parts.screen_map()
    print("normal map statistics (std of R/G in levels, %% pixels changed, unique R):")
    for name, std, changed, uniq in tc.STATS:
        print("  %-24s std %6.2f  changed %6.2f%%  unique %d" % (name, std, changed * 100, uniq))
    tc.report()
    print("done")


if __name__ == "__main__":
    main()
