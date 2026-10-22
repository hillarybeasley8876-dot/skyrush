#!/usr/bin/env python3
"""selftest_attach — proves the ramp attach rule rejects bad ramps (mutation test).

    python tools/city/selftest_attach.py [data/city/city.json]

A rule that cannot fail is worthless: this takes a ramp that attaches cleanly, breaks it one way
at a time and requires check_attaches to name it each time.
"""
import copy
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import citylib  # noqa: E402
import city_attach  # noqa: E402
import city_rules_attach  # noqa: E402

RAMP = "ramp_l3_eb_nb"
KEY = "attach_start"


def failing(city):
    """The ramp ids the attach rule names."""
    return {line.split()[0] for line in city_rules_attach.check_attaches(city)}


def mutate(city, fn):
    out = copy.deepcopy(city)
    ramp = next(r for r in out["roads"] if r["id"] == RAMP)
    parent = next(r for r in out["roads"] if r["id"] == ramp[KEY]["road"])
    fn(ramp, parent)
    return out


def shift_lateral(metres):
    def apply(ramp, parent):
        p = ramp["points"][0]
        _s, _lat, heading, _y = city_attach.project(parent["points"], (p[0], p[2]))
        nx, nz = city_attach.right_normal(heading)
        p[0] += nx * metres
        p[2] += nz * metres
    return apply


def flip_side(ramp, _parent):
    ramp[KEY]["side"] = "left" if ramp[KEY]["side"] == "right" else "right"


def raise_start(ramp, _parent):
    ramp["points"][0][1] += 0.5


def main(argv):
    city = citylib.load_json(argv[1] if len(argv) > 1 else os.path.join(HERE, "..", "..", "data", "city", "city.json"))
    cases = [
        ("the unmodified ramp passes", None, False),
        ("2 m too far out is rejected", shift_lateral(2.0), True),
        ("2 m too far in is rejected", shift_lateral(-2.0), True),
        ("on the parent's centre-line is rejected", shift_lateral(-city_attach.asphalt_half(
            next(r for r in city["roads"] if r["id"] == next(
                x for x in city["roads"] if x["id"] == RAMP)[KEY]["road"])) - city_attach.asphalt_half(
            next(x for x in city["roads"] if x["id"] == RAMP))), True),
        ("the wrong side is rejected", flip_side, True),
        ("0.5 m too high is rejected", raise_start, True),
    ]
    bad = 0
    for label, fn, must_fail in cases:
        names = failing(city if fn is None else mutate(city, fn))
        hit = RAMP in names
        ok = hit == must_fail
        bad += 0 if ok else 1
        print("%s %s" % ("PASS" if ok else "FAIL", label))
    print("selftest_attach: %d case(s) wrong" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
