#!/usr/bin/env python3
"""check_blocks_untouched — tiles that were under budget must come out with exactly their reference numbers.

    python tools/city/check_blocks_untouched.py <blocks dir> --ref <reference.json> --tiles "tx,tz;tx,tz"

For every listed tile the near triangle count (stats.tris of the sidecar) and the number of buildings must be equal to the
reference file's. Prints one line per tile and "BLOCKS_UNTOUCHED OK" or "BLOCKS_UNTOUCHED FAIL n".
"""
import json
import os
import sys


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    opt = lambda n, d: argv[argv.index(n) + 1] if n in argv else d  # noqa: E731
    ref = json.load(open(opt("--ref", ""), encoding="utf-8"))
    tiles = [t.strip().replace(",", "_") for t in opt("--tiles", "").split(";") if t.strip()]
    for n in ("--ref", "--tiles"):
        if n in argv:
            args.remove(argv[argv.index(n) + 1])
    bad = 0
    for t in tiles:
        name = "blocks_" + t
        path = os.path.join(args[0], name + ".json")
        r = ref.get(name)
        if r is None or not os.path.exists(path):
            print("BAD  %s: no reference or no tile" % t)
            bad += 1
            continue
        st = json.load(open(path, encoding="utf-8"))["stats"]
        same = st["tris"] == r["near"] and st["buildings"] == r["buildings"]
        bad += 0 if same else 1
        print("%s %s near %d (ref %d) buildings %d (ref %d)" % ("ok  " if same else "BAD ", t, st["tris"], r["near"], st["buildings"], r["buildings"]))
    print("BLOCKS_UNTOUCHED %s" % ("OK" if bad == 0 and tiles else "FAIL %d" % bad))
    return 0 if bad == 0 and tiles else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
