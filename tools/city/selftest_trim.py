#!/usr/bin/env python3
"""selftest_trim — the streets cut under the Nanpu ramps stay cut.

    python tools/city/selftest_trim.py [data/city/city.json]

The lattice streets that run under the two Nanpu ramps are cut by
`city_trim.trim_under_decks`: the part of the street under the ramp is
dropped and the rest keeps its ends.  This checks the three promises of
that cut on a built map:

  * the rule "deck clearance" names no lattice street under the two
    Nanpu ramps any more (the cut did its job);
  * every piece of a cut street is at least 25 m long and keeps the id
    of its street (the `b`, `bb`, ... pieces are its continuations);
  * no two roads of the map share an id (the pieces did not collide).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import citylib          # noqa: E402
import city_rules_attach  # noqa: E402
import city_trim        # noqa: E402

DECKS = ("nanpu_spiral_lower", "nanpu_pudong_loop")
PIECE = re.compile(r"^(.*?)(b+)$")


def _lattice(road_id):
    """True for a lattice street (the named streets are never cut)."""
    return road_id.startswith(city_trim.PREFIXES)


def _length(road):
    """The length of a road of city.json."""
    total = 0.0
    for a, b in zip(road["points"], road["points"][1:]):
        total += ((b[0] - a[0]) ** 2 + (b[2] - a[2]) ** 2) ** 0.5
    return total


def main(argv):
    path = argv[1] if len(argv) > 1 else os.path.join(HERE, "..", "..",
                                                       "data", "city", "city.json")
    city = citylib.load_json(path)
    bad = 0

    ids = [r["id"] for r in city["roads"]]
    dupes = sorted(set(i for i in ids if ids.count(i) > 1))
    ok = not dupes
    bad += 0 if ok else 1
    print("%s no two roads share an id" % ("PASS" if ok else "FAIL"))
    if not ok:
        print("       %s" % ", ".join(dupes[:6]))

    named = []
    for line in city_rules_attach.check_clearance(city):
        pair = line.split(":")[0].split(" x ")
        if any(d in DECKS for d in pair) and any(_lattice(p) for p in pair):
            named.append(line)
    ok = not named
    bad += 0 if ok else 1
    print("%s no lattice street runs under the Nanpu ramps any more"
          % ("PASS" if ok else "FAIL"))
    for line in named[:6]:
        print("       %s" % line)

    short = []
    for road in city["roads"]:
        match = PIECE.match(road["id"])
        if not match or not _lattice(match.group(1)):
            continue
        if _length(road) < city_trim.MIN_PIECE - 0.05:
            short.append("%s is %.1f m" % (road["id"], _length(road)))
    ok = not short
    bad += 0 if ok else 1
    print("%s every piece of a cut street is at least %.0f m"
          % ("PASS" if ok else "FAIL", city_trim.MIN_PIECE))
    for line in short[:6]:
        print("       %s" % line)

    print("selftest_trim: %d case(s) wrong" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
