"""Generate the Bund's texture set (bund unit).

    python3 blender/bund/texgen.py

The shared texture library has no granite / brick / glazed tile and ART.md forbids flat
untextured surfaces, so the unit generates its own maps (numpy + PIL) into
game/assets/bund/textures/. Every map is tileable and 1 UV unit = 1 metre in the material.

The generator only writes a file when its bytes change, so a second run is a no-op and
Godot does not re-import the district (the lead's IMPORT-CHURN note).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from bund import (data, texbase, texmaps, texmaps2, texmaps3,  # noqa: E402
                  texmaps_metal, washmap)


def main():
    print("generating Bund textures ->", texbase.OUT)
    # the stone family: 3 seed variants of the neutral ashlar, the buildings pick one
    for i, seed in enumerate((1916, 1937, 1951)):
        texmaps.make_ashlar("granite_%d" % i, base=(185.0, 184.0, 176.0), seed=seed)
    # the brick family (No. 6 / 9 / 33) and the red band of the Palace Hotel
    texmaps.make_brick("brick_0", base=(162.0, 73.0, 58.0), seed=1897)
    # the glazed tile (No. 15 / 19) and the coffee tile of Broadway Mansions
    texmaps.make_glazed_tile("tile_white", base=(236.0, 232.0, 222.0))
    texmaps.make_glazed_tile("tile_coffee", base=(122.0, 74.0, 50.0),
                              grout=(70.0, 52.0, 42.0), soot=0.7)
    # the window interiors (the atlas and its emissive twin)
    texmaps.make_interior_atlas("interior_atlas")
    # the surfaces
    texmaps2.make_paving()
    texmaps2.make_wall()
    texmaps2.make_roof_tar()
    texmaps2.make_grass()
    texmaps2.make_hedge()
    texmaps2.make_foliage()
    # the metal, the paper and the light
    texmaps_metal.make_iron()
    texmaps_metal.make_clock_dial()
    texmaps_metal.make_copper_pyramid()
    texmaps_metal.make_tile_teal()
    texmaps_metal.make_flag()
    texmaps_metal.make_bronze()
    texmaps_metal.make_lantern()
    texmaps_metal.make_cove()
    texmaps_metal.make_flood()
    # the crown wash ramp and the shared moulding trim sheet
    texmaps_metal.make_wash_crown()
    texmaps3.make_trim_sheet()
    # the baked facade wash: one atlas with a cell per building
    washmap.bake(data.SPECS)
    texbase.report()
    # the art numbers of every map: the grain of the surface and the tilt of the relief
    texbase.print_stats([
        "granite_0_diff.jpg", "granite_1_diff.jpg", "granite_2_diff.jpg",
        "brick_0_diff.jpg", "tile_white_diff.jpg", "tile_coffee_diff.jpg",
        "interior_atlas_diff.jpg", "paving_diff.jpg", "wall_diff.jpg",
        "roof_tar_diff.jpg", "grass_diff.jpg", "hedge_diff.jpg", "foliage_diff.jpg",
        "iron_dark_diff.jpg", "clock_dial_diff.jpg", "copper_pyramid_diff.jpg",
        "tile_teal_diff.jpg", "flag_red_diff.jpg", "bronze_diff.jpg",
        "lantern_paper_diff.jpg", "trim_sheet_diff.jpg",
    ])
    print("done")


if __name__ == "__main__":
    main()
