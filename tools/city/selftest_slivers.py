#!/usr/bin/env python3
"""selftest_slivers — the shape rule of the clipper: a piece must be wide enough for a building.

    python tools/city/selftest_slivers.py [city.json]

city_blocks.piece_width(poly)         -> the width of a piece in metres
city_blocks.piece_is_buildable(poly)  -> True when a building can stand on that piece

The width of a piece is twice its area over its perimeter: about the width of a strip, half
the side of a square.  A piece that the clipper cut off a lot is kept only when it is at
least MIN_PIECE_WIDTH wide, because the building planner snaps a lot to the 10 m lattice and
a strip narrower than that gets no building at all (or one that is bigger than the piece).

The cases:
  * an 8 m x 55 m strip is dropped          (width 6.98)
  * a 7 m x 20 m strip is dropped           (width 5.19)
  * a 30 m x 40 m rectangle is kept         (width 17.14)
  * an L-shaped piece with a 20 m wide arm is kept   (width 15.00)
  * a 12 m x 12 m square is dropped         (width 6.00 - a square is half as wide as it is
                                            long, so this one is a sliver under this rule)
  * the real map: after clear_of_roads no piece of a lot that the clipper cut is narrower
    than MIN_PIECE_WIDTH.  A lot the clipper did not cut is the lot itself and is kept as it
    is: the raster makes compact 10 m x 20 m lots (width 6.67) that the planner builds well.

Prints "selftest_slivers: N case(s) wrong" and exits 0 when every case is right.
"""
import contextlib
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import city_blocks  # noqa: E402

OUT_DIR = os.environ.get("SKYRUSH_OUT", "F:/dev/skyrush-out")
SCRATCH = os.path.join(OUT_DIR, "tmp", "city-slivers")


def rect(w, h):
    """A rectangle of w x h metres, counter-clockwise seen from above.

    The frame is x east and z south, so a counter-clockwise polygon has a
    NEGATIVE shoelace area in the (x, z) plane.
    """
    return [[0.0, 0.0], [0.0, h], [w, h], [w, 0.0]]


def base_id(lot_id):
    """The id of the lot a piece belongs to (b_d0_029_s12 -> b_d0_029)."""
    head, sep, tail = lot_id.rpartition("_s")
    if sep and tail.isdigit() and head:
        return head
    return lot_id


def judge(name, poly, expected, problems):
    """One synthetic case: the piece must be kept (or dropped) as expected."""
    try:
        kept = city_blocks.piece_is_buildable(poly)
    except Exception as exc:  # noqa: BLE001
        problems.append("%s: %s: %s" % (name, type(exc).__name__, exc))
        return False
    if kept != expected:
        problems.append("%s: %s, expected %s" %
                        (name, "kept" if kept else "dropped",
                         "kept" if expected else "dropped"))
        return False
    return True


def judge_shapes(problems):
    """The synthetic pieces: the strips are dropped, the blocks are kept."""
    l_shape = [[0.0, 0.0], [0.0, 40.0], [20.0, 40.0], [20.0, 20.0], [40.0, 20.0], [40.0, 0.0]]
    cases = [
        ("an 8 m x 55 m strip", rect(8.0, 55.0), False),
        ("a 7 m x 20 m strip", rect(7.0, 20.0), False),
        ("a 30 m x 40 m rectangle", rect(30.0, 40.0), True),
        ("an L-shaped piece with a 20 m wide arm", l_shape, True),
        ("a 12 m x 12 m square", rect(12.0, 12.0), False),
    ]
    ok = True
    for name, poly, expected in cases:
        right = judge(name, poly, expected, problems)
        ok &= right
        if right:
            print("PASS %s" % name)
    return ok


def build_the_map(path):
    """The real map, written by the generator itself."""
    import build_city
    if not os.path.isdir(os.path.dirname(path)):
        os.makedirs(os.path.dirname(path))
    report = io.StringIO()
    with contextlib.redirect_stdout(report):
        build_city.main(out=path)
    return path


def judge_the_map(city_path, problems):
    """The real map: no piece of a lot that the clipper cut is too narrow."""
    city = json.load(open(city_path, encoding="utf-8"))
    groups = {}
    for block in city["blocks"]:
        groups.setdefault(base_id(block["id"]), []).append(block)
    narrow = []
    pieces = 0
    for base, members in sorted(groups.items()):
        if len(members) < 2:
            continue                 # the clipper did not cut this lot
        pieces += len(members)
        for block in members:
            width = city_blocks.piece_width(block["polygon"])
            if width < city_blocks.MIN_PIECE_WIDTH:
                narrow.append("%s is %.2f m wide" % (block["id"], width))
    if narrow:
        problems.append("%d piece(s) of the real map are too narrow: %s"
                        % (len(narrow), ", ".join(narrow[:6])))
        return False
    print("the real map: %d lots, %d piece(s) of the cut lots, all of them at least %.1f m wide"
          % (len(city["blocks"]), pieces, city_blocks.MIN_PIECE_WIDTH))
    return True


def main(argv):
    problems = []
    judge_shapes(problems)
    if len(argv) > 1:
        city_path = argv[1]
    else:
        city_path = build_the_map(os.path.join(SCRATCH, "selftest_city.json"))
    try:
        judge_the_map(city_path, problems)
    except Exception as exc:  # noqa: BLE001
        problems.append("the real map: %s: %s" % (type(exc).__name__, exc))
    for line in problems:
        print("FAIL %s" % line)
    print("selftest_slivers: %d case(s) wrong" % len(problems))
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
