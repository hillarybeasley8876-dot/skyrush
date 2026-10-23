#!/usr/bin/env python3
"""check_lots_kept — clipping the lots off the roads must not eat the lots.

    python tools/city/check_lots_kept.py <city.json> <baseline lots json> [--keep 0.35] [--total 0.90]
    python tools/city/check_lots_kept.py <city.json> --write <baseline lots json>

The baseline file holds, for every lot of a reference city.json, its id and area.  A lot that was cut into
several pieces keeps its id on the largest piece; the other pieces are called <id>_s1, <id>_s2, ...
Requirements (every one prints a FAIL line):
  1. the total area of the lots is at least --total (default 0.90) of the baseline
  2. every baseline lot of at least 400 m2 still exists (id, or id plus its pieces) with at least --keep (default 0.35) of
     its area; a job that moves roads (the lots are re-formed and renumbered around the new road) passes --keep 0.0 and
     relies on rules 1, 3, 4 and 5
  3. no more than 12 baseline lots disappear altogether (lots that lay in the middle of a road)
  4. no lot (piece) is smaller than 80 m2
  5. no id is used twice
  6. every polygon has at least 3 points and runs counter-clockwise seen from above: the frame is x east, z south,
     so its shoelace area in the (x, z) plane is NEGATIVE (the rule 'the lots run counter-clockwise')
Prints "LOTS_KEPT OK" or "LOTS_KEPT FAIL n".
"""
import json
import sys


def area(poly):
    s = 0.0
    for (x0, z0), (x1, z1) in zip(poly, poly[1:] + poly[:1]):
        s += x0 * z1 - x1 * z0
    return 0.5 * s


def base_id(lot_id):
    head, sep, tail = lot_id.rpartition("_s")
    if sep and tail.isdigit() and head:
        return head
    return lot_id


def main(argv):
    if "--write" in argv:
        city = json.load(open(argv[1], encoding="utf-8"))
        out = argv[argv.index("--write") + 1]
        data = {}
        for b in city["blocks"]:
            # a lot that was cut into pieces is ONE lot of the baseline (its pieces are <id>_s1, <id>_s2, ...)
            data[base_id(b["id"])] = round(data.get(base_id(b["id"]), 0.0) + abs(area(b["polygon"])), 1)
        json.dump(data, open(out, "w", encoding="utf-8"), indent=0)
        print("written %d lots, %.0f m2 to %s" % (len(data), sum(data.values()), out))
        return 0
    opt = lambda n, d: float(argv[argv.index(n) + 1]) if n in argv else d  # noqa: E731
    keep_share, total_share = opt("--keep", 0.35), opt("--total", 0.90)
    city = json.load(open(argv[1], encoding="utf-8"))
    base = json.load(open(argv[2], encoding="utf-8"))
    bad = []
    now = {}
    seen = set()
    for b in city["blocks"]:
        if b["id"] in seen:
            bad.append("id %s is used twice" % b["id"])
        seen.add(b["id"])
        a = area(b["polygon"])
        if len(b["polygon"]) < 3 or a >= 0.0:
            bad.append("%s: polygon is empty or clockwise (shoelace area %.1f, must be negative)" % (b["id"], a))
        if abs(a) < 80.0:
            bad.append("%s is only %.0f m2" % (b["id"], abs(a)))
        now[base_id(b["id"])] = now.get(base_id(b["id"]), 0.0) + abs(a)
    total_base, total_now = sum(base.values()), sum(now.get(k, 0.0) for k in base) + sum(v for k, v in now.items() if k not in base)
    if total_now < total_share * total_base:
        bad.append("the lots lost too much: %.0f m2 now, %.0f m2 before (%.1f %%)" % (total_now, total_base, 100.0 * total_now / total_base))
    gone = 0
    for lot_id, a in base.items():
        got = now.get(lot_id, 0.0)
        if got <= 0.0:
            gone += 1
            continue
        if a >= 400.0 and got < keep_share * a:
            bad.append("%s kept only %.0f of %.0f m2" % (lot_id, got, a))
    if gone > 12:
        bad.append("%d lots disappeared altogether (at most 12 may)" % gone)
    for line in bad[:40]:
        print("FAIL", line)
    print("lots: %d (baseline %d), %.0f m2 (baseline %.0f m2), %d gone" % (len(city["blocks"]), len(base), total_now, total_base, gone))
    print("LOTS_KEPT %s" % ("OK" if not bad else "FAIL %d" % len(bad)))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
