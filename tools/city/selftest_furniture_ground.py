#!/usr/bin/env python3
"""selftest_furniture_ground — check_furniture_ground.py tells the asphalt from the sidewalk under a prop.

    python tools/city/selftest_furniture_ground.py [<road tiles dir> <road_furniture.json>]

Synthetic ground (an asphalt square, a sidewalk strip beside it, a planter, a deck 6 m up) and props on each; with the two files,
the roads build must find most of the trees of the Blender placement on the asphalt (furniture.py puts them half a carriageway
out, in the outer lane: the game moves them onto the sidewalk). Prints one line per case and "SELFTEST_FURNITURE_GROUND OK" or
"... FAIL n".
"""
import collections
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_furniture_ground as cfg  # noqa: E402

failed = 0


def case(name, ok):
    global failed
    print("%s %s" % ("PASS" if ok else "FAIL", name))
    if not ok:
        failed += 1


def square(index, kind, x0, z0, x1, z1, y=0.0):
    cfg.add(index, kind, ((x0, y, z0), (x1, y, z0), (x1, y, z1)))
    cfg.add(index, kind, ((x0, y, z0), (x1, y, z1), (x0, y, z1)))


index = collections.defaultdict(list)
square(index, "asphalt", 0.0, 0.0, 20.0, 20.0)            # a junction
square(index, "sidewalk", 20.0, 0.0, 24.0, 20.0, 0.15)   # the sidewalk beside it, a kerb higher
square(index, "planter", 30.0, 0.0, 32.0, 20.0, 0.3)
square(index, "asphalt", 40.0, 0.0, 60.0, 20.0, 6.0)     # a deck 6 m up, nothing under it

case("a point on the asphalt is asphalt", cfg.ground_at(index, 10.0, 0.0, 10.0) == {"asphalt"})
case("a point on the sidewalk is sidewalk", cfg.ground_at(index, 22.0, 0.15, 10.0) == {"sidewalk"})
case("a point on the planter is planter", cfg.ground_at(index, 31.0, 0.3, 10.0) == {"planter"})
case("a point under a deck 6 m up stands on nothing", cfg.ground_at(index, 50.0, 0.0, 10.0) == set())
case("a point on the deck is asphalt", cfg.ground_at(index, 50.0, 6.0, 10.0) == {"asphalt"})
case("a point beside everything stands on nothing", cfg.ground_at(index, 70.0, 0.0, 10.0) == set())

props = [("tree", 10.0, 0.0, 10.0, "a"), ("tree", 22.0, 0.15, 5.0, "a"), ("lamp", 31.0, 0.3, 5.0, "a"),
         ("bin", 10.0, 0.0, 12.0, "a"), ("sign", 70.0, 0.0, 10.0, "a")]
by_kind, bad = cfg.classify(index, props)
case("the tree in the junction is ON_ASPHALT, the one on the sidewalk is not",
     [p[1] for p in bad] == [10.0] and by_kind["tree"]["sidewalk"] == 1)
case("a lamp in a planter is fine", by_kind["lamp"]["planter"] == 1)
case("a bin is not a solid prop (not judged)", "bin" not in by_kind)
case("a sign on nothing counts as none", by_kind["sign"]["none"] == 1)

if len(sys.argv) == 3:
    real = cfg.ground_index(sys.argv[1])
    by_kind, bad = cfg.classify(real, cfg.load_props(sys.argv[2]))
    trees = by_kind["tree"]
    case("the Blender placement puts most trees on the asphalt (the game moves them)",
         trees["asphalt"] > 0.9 * sum(trees.values()))

print("SELFTEST_FURNITURE_GROUND OK" if failed == 0 else "SELFTEST_FURNITURE_GROUND FAIL %d" % failed)
sys.exit(1 if failed else 0)
