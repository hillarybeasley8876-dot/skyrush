#!/usr/bin/env python3
"""selftest_test_city — check_test_city.py lets a circuit of link roads through and catches a road drawn over another one.

    python tools/city/selftest_test_city.py

Synthetic cities: two roads (main_ew on the ground, elev_ew 10 m up between its ramps) and the route test_loop; every case changes
one thing and must give exactly the verdict it names. Prints one line per case and "SELFTEST_TEST_CITY OK" or "... FAIL n".
"""
import copy
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_test_city as ctc  # noqa: E402

failed = 0


def case(name, ok):
    global failed
    print("%s %s" % ("PASS" if ok else "FAIL", name))
    if not ok:
        failed += 1


def kinds(city, ref):
    return sorted(set(p.split()[0] for p in ctc.check(city, ref)))


REF = {
    "roads": [
        {"id": "main_ew", "points": [[-500, 0, 0], [0, 0, 0], [500, 0, 0]]},
        {"id": "elev_ew", "points": [[-480, 0, 60], [-300, 10, 60], [300, 10, 60], [480, 0, 60]]},
    ],
    "junctions": [], "blocks": [], "pois": [], "sky_lanes": [], "spawns": {"player": [-450, 0, -5, 90]},
    "routes": [{"id": "test_loop", "kind": "race", "laps": 2, "grid": [-450, 0, -5, 90],
                "checkpoints": [[-400, 0, -5, 90], [0, 0, -5, 90], [400, 0, -5, 90], [0, 10, 64, 270]]}],
}
LINK_E = {"id": "link_e", "points": [[500, 0, 0], [520, 0, 30], [480, 0, 60]]}
LINK_W = {"id": "link_w", "points": [[-480, 0, 60], [-520, 0, 30], [-500, 0, 0]]}
JUNCTIONS = [{"id": "j_e1", "x": 500, "z": 0, "roads": ["main_ew", "link_e"]},
             {"id": "j_e2", "x": 480, "z": 60, "roads": ["elev_ew", "link_e"]},
             {"id": "j_w1", "x": -480, "z": 60, "roads": ["elev_ew", "link_w"]},
             {"id": "j_w2", "x": -500, "z": 0, "roads": ["main_ew", "link_w"]}]

case("the reference passes", kinds(REF, REF) == [])

good = copy.deepcopy(REF)
good["roads"] += [copy.deepcopy(LINK_E), copy.deepcopy(LINK_W)]
good["junctions"] += copy.deepcopy(JUNCTIONS)
case("two link roads joined by junction records pass", kinds(good, REF) == [])

loose = copy.deepcopy(good)
loose["junctions"] = loose["junctions"][1:]
case("a link whose end is in no junction record is a LOOSE_END", kinds(loose, REF) == ["LOOSE_END"])

attached = copy.deepcopy(loose)
next(r for r in attached["roads"] if r["id"] == "link_e")["attach_start"] = {"road": "main_ew", "at": 1000, "side": "right"}
case("an attach to an existing road joins it", kinds(attached, REF) == [])

over = copy.deepcopy(good)
over["roads"].append({"id": "ghost", "points": [[-300, 0, 2], [300, 0, 2]]})
over["junctions"].append({"id": "j_g1", "x": -300, "z": 2, "roads": ["main_ew", "ghost"]})
over["junctions"].append({"id": "j_g2", "x": 300, "z": 2, "roads": ["main_ew", "ghost"]})
case("a road drawn along main_ew is ALONG (and LONG at 600 m)", kinds(over, REF) == ["ALONG", "LONG"])

up = copy.deepcopy(good)
up["roads"].append({"id": "ghost_up", "points": [[-200, 10, 62], [100, 10, 62]]})
up["junctions"].append({"id": "j_u1", "x": -200, "z": 62, "roads": ["elev_ew", "ghost_up"]})
up["junctions"].append({"id": "j_u2", "x": 100, "z": 62, "roads": ["elev_ew", "ghost_up"]})
case("a road drawn along the deck of elev_ew is ALONG", kinds(up, REF) == ["ALONG"])

under = copy.deepcopy(good)
under["roads"].append({"id": "below", "points": [[-200, 0, 62], [100, 0, 62]]})
under["junctions"].append({"id": "j_b1", "x": -200, "z": 62, "roads": ["elev_ew", "below"]})
under["junctions"].append({"id": "j_b2", "x": 100, "z": 62, "roads": ["elev_ew", "below"]})
case("a street on the ground under the deck is not ALONG (another level)", kinds(under, REF) == [])

gates = copy.deepcopy(good)
gates["routes"][0]["checkpoints"][3] = [0, 0, 30, 270]
case("no gate on the elevated part of elev_ew is GATES", kinds(gates, REF) == ["GATES"])

sprint = copy.deepcopy(good)
sprint["routes"][0]["kind"] = "sprint"
case("a sprint instead of the race is GATES", kinds(sprint, REF) == ["GATES"])

moved = copy.deepcopy(good)
moved["roads"][0]["points"][1] = [0, 0, 5]
case("a moved point of main_ew is CHANGED", "CHANGED" in kinds(moved, REF))

print("SELFTEST_TEST_CITY OK" if failed == 0 else "SELFTEST_TEST_CITY FAIL %d" % failed)
sys.exit(1 if failed else 0)
