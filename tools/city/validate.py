#!/usr/bin/env python3
"""validate — checks data/city/city.json against the brief and the dossier.

    python3 tools/city/validate.py data/city/city.json

Every rule prints PASS or FAIL; a failing rule lists *every* failure with
its value and its place in the map - a rule that hides its failures is
worthless.  The exit code is non-zero when a rule fails.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import citylib      # noqa: E402
import city_rules   # noqa: E402
import city_rules_attach  # noqa: E402
import city_rules_map  # noqa: E402
import city_rules_routes  # noqa: E402
import check_tunnel_portals  # noqa: E402

def _portals_rule(city):
    _lines, fails, _notes = check_tunnel_portals.check(city)
    return ["%s %s x %s: %d samples, s %.0f..%.0f, depth %.2f..%.2f m, at (%.0f, %.0f)"
            % (k[0], k[1], k[2], v[6], v[0], v[1], v[2], v[3], v[4], v[5]) for k, v in sorted(fails.items())]


def _decks_rule(city):
    fails, exempt = city_rules_map.check_decks(city)
    return fails, exempt


RULES = [
    ("schema fields", city_rules.check_schema),
    ("grades <= 5 % (spiral <= 4 %)", city_rules.check_grades),
    ("vertical curvature <= 0.5 %/10 m", city_rules.check_curvature),
    ("deck clearance >= 5.5 m", city_rules_attach.check_clearance),
    ("tunnel portals open to the sky", _portals_rule),
    ("no road in the water", city_rules.check_water),
    ("ramps attach to their parent", city_rules_attach.check_attaches),
    ("junctions meet their roads", city_rules_attach.check_junctions),
    ("key levels (pillar, tunnel)", city_rules.check_key_levels),
    ("no dead ends", city_rules.check_dead_ends),
    ("blocks clear of the roads", city_rules_map.check_blocks),
    ("blocks clear of the decks", _decks_rule),
    ("spawns on the lane centres", city_rules_map.check_spawns),
    ("route checkpoints on the lanes", city_rules_routes.check_routes),
    ("sky lanes", city_rules_routes.check_sky_lanes),
    ("pois", city_rules_map.check_pois),
    ("the lots cover the land", city_rules_map.check_coverage),
    ("the lots run counter-clockwise", city_rules_map.check_winding),
]


def main(argv):
    path = argv[1] if len(argv) > 1 else "data/city/city.json"
    city = citylib.load_json(path)
    failed = 0
    for name, rule in RULES:
        result = rule(city)
        exempt = []
        if isinstance(result, tuple):
            result, exempt = result
        if result:
            failed += 1
            print("FAIL %s: %d failing" % (name, len(result)))
            for line in result:
                print("       %s" % line)
        else:
            print("PASS %s" % name)
        for line in exempt:
            print("       EXEMPT %s" % line)
    total = 0.0
    lanes = 0.0
    for road in city["roads"]:
        length = sum(math.dist(a, b) for a, b in zip(road["points"],
                                                      road["points"][1:]))
        total += length
        lanes += length * max(1, road["lanes_fwd"] + road["lanes_back"])
    print("drivable: %.1f km of road (%.1f km of lanes), %d roads"
          % (total / 1000.0, lanes / 1000.0, len(city["roads"])))
    print("%d rules, %d failed" % (len(RULES), failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
