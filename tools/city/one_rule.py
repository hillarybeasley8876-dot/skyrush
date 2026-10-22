#!/usr/bin/env python3
"""one_rule — run one rule (or all) of validate.py on a city.json and print its failing items.

    python tools/city/one_rule.py <city.json> ["part of the rule name"] [--time] [--max N]

Without a name every rule runs. --time prints the seconds each rule took. This is the fast inner loop:
the full gate (accept_rules.py) is only for when your change is ready.
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import citylib  # noqa: E402
import validate  # noqa: E402


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 2
    show_time = "--time" in argv
    limit = int(argv[argv.index("--max") + 1]) if "--max" in argv else 40
    if "--max" in argv:
        args = [a for a in args if a != str(limit)]
    city = citylib.load_json(args[0])
    part = args[1].lower() if len(args) > 1 else ""
    shown = 0
    for name, rule in validate.RULES:
        if part and part not in name.lower():
            continue
        t0 = time.time()
        result = rule(city)
        if isinstance(result, tuple):
            result = result[0]
        shown += 1
        print("%s %s: %d failing%s" % ("FAIL" if result else "PASS", name, len(result),
                                       "  (%.1f s)" % (time.time() - t0) if show_time else ""))
        for line in result[:limit]:
            print("      " + line)
        if len(result) > limit:
            print("      ... %d more" % (len(result) - limit))
    if not shown:
        print("no rule matches %r; rules: %s" % (part, "; ".join(n for n, _ in validate.RULES)))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
