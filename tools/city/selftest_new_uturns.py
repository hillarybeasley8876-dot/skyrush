#!/usr/bin/env python3
"""selftest_new_uturns — check_new_uturns.py finds the new U-turns and the narrow ones.

    python tools/city/selftest_new_uturns.py [<lanes.json>]

Synthetic connectors: a wide U-turn (ends 14 m apart), a narrow one (4.5 m), a right turn, an old U-turn of the reference; with a
lanes.json, the file against itself has no new U-turn. Prints one line per case and "SELFTEST_NEW_UTURNS OK" or "... FAIL n".
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_new_uturns as cnu  # noqa: E402

failed = 0


def case(name, ok):
    global failed
    print("%s %s" % ("PASS" if ok else "FAIL", name))
    if not ok:
        failed += 1


def arc(cid, radius, degrees, n=24):
    pts = [[radius * math.sin(math.radians(degrees * k / n)), 0.0, radius * (1 - math.cos(math.radians(degrees * k / n)))]
           for k in range(n + 1)]
    return {"id": cid, "connector": True, "points": pts, "next": []}


ref = [arc("old_u", 7.0, 180.0)]
lanes = ref + [arc("wide_u", 7.0, 180.0), arc("narrow_u", 2.25, 180.0), arc("right", 10.0, 90.0)]
found = dict(cnu.new_uturns(lanes, ref))
case("the wide U-turn is found, 14 m between its ends", abs(found.get("wide_u", 0) - 14.0) < 0.1)
case("the narrow U-turn is found, 4.5 m between its ends", abs(found.get("narrow_u", 0) - 4.5) < 0.1)
case("a right turn is no U-turn", "right" not in found)
case("a U-turn of the reference is not new", "old_u" not in found)
case("an arc of 160 degrees is a U-turn (the first and the last step of the samples count)", bool(cnu.new_uturns([arc("u160", 7.0, 160.0)], [])))
case("an arc of 140 degrees is not", not cnu.new_uturns([arc("u140", 7.0, 140.0)], []))

if len(sys.argv) > 1:
    real = json.load(open(sys.argv[1], encoding="utf-8"))["lanes"]
    case("a lanes.json against itself has no new U-turn", cnu.new_uturns(real, real) == [])

print("SELFTEST_NEW_UTURNS OK" if failed == 0 else "SELFTEST_NEW_UTURNS FAIL %d" % failed)
sys.exit(1 if failed else 0)
