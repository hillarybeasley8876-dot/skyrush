#!/usr/bin/env python3
"""accept_rules — the regression gate for map jobs.

    python tools/city/accept_rules.py <city.json> --baseline tools/city/rules_baseline.json
            [--target "rule name"]... [--max-target N] [--write-baseline]

Runs every rule of validate.py on <city.json> and compares each rule's failing items with the baseline.
An item is identified by its message with the numbers blanked (so moving a road a metre does not make
an old failure look new, but a failure on a road that passed before is new).

Exit 0 only when
  * no rule that is NOT a --target has an item the baseline did not have, and
  * every --target rule has at most --max-target items (default 0).
Prints one line per rule: baseline count, current count, new items, fixed items.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import citylib  # noqa: E402
import validate  # noqa: E402

NUMBER = re.compile(r"-?\d+(?:\.\d+)?")


def key(message):
    """A failing item's identity: the message with every number blanked."""
    return NUMBER.sub("#", message).strip()


def collect(city):
    """{rule name: [message, ...]} for every rule of validate.py."""
    out = {}
    for name, rule in validate.RULES:
        result = rule(city)
        if isinstance(result, tuple):
            result = result[0]
        out[name] = list(result)
    return out


def main(argv):
    args = argv[1:]
    if not args or args[0].startswith("--"):
        print(__doc__)
        return 2
    path = args[0]
    opts = {"--baseline": None, "--max-target": "0"}
    targets, write = [], False
    i = 1
    while i < len(args):
        if args[i] == "--target":
            targets.append(args[i + 1])
            i += 2
        elif args[i] == "--write-baseline":
            write = True
            i += 1
        elif args[i] in opts:
            opts[args[i]] = args[i + 1]
            i += 2
        else:
            print("unknown option", args[i])
            return 2
    now = collect(citylib.load_json(path))
    if write:
        with open(opts["--baseline"], "w", encoding="utf-8") as fh:
            json.dump({name: sorted({key(m) for m in msgs}) for name, msgs in now.items()}, fh, indent=1, ensure_ascii=False)
        print("baseline written:", opts["--baseline"], {n: len(m) for n, m in now.items() if m})
        return 0
    with open(opts["--baseline"], encoding="utf-8") as fh:
        base = json.load(fh)
    limit = int(opts["--max-target"])
    bad = 0
    print("%-34s %5s %5s %5s %5s" % ("rule", "base", "now", "new", "fixed"))
    for name, msgs in now.items():
        keys = {key(m) for m in msgs}
        old = set(base.get(name, []))
        new, fixed = sorted(keys - old), sorted(old - keys)
        is_target = any(t.lower() in name.lower() for t in targets)
        verdict = ""
        if is_target and len(msgs) > limit:
            verdict, bad = "  <-- target still failing", bad + 1
        elif not is_target and new:
            verdict, bad = "  <-- REGRESSION", bad + 1
        print("%-34s %5d %5d %5d %5d%s" % (name[:34], len(old), len(keys), len(new), len(fixed), verdict))
        for item in new[:6]:
            if not is_target:
                print("      new: %s" % item[:150])
    print("ACCEPT_RULES %s" % ("FAIL" if bad else "OK"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
