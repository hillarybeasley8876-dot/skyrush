"""Selftest of check_chain_links: build a plausible fix of the lane graph in Python and run the checker on it.

    python tools/city/selftest_chain_links.py <lanes.json>

The chain links of the given graph are removed first (break_chains), so any lanes.json works, repaired or not.
Expects: the repaired graph passes; three broken variants fail with the right rule letter.
"""
import copy
import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path

CELL = 8.0
HERE = Path(__file__).resolve().parent


def heading(a, b):
    return math.degrees(math.atan2(b[0] - a[0], -(b[2] - a[2]))) % 360.0


def turn(a, b):
    return abs((a - b + 180.0) % 360.0 - 180.0)


def bezier(p0, p1, p2, p3, n=10):
    out = []
    for k in range(n + 1):
        t = k / n
        u = 1 - t
        out.append([u ** 3 * p0[i] + 3 * u * u * t * p1[i] + 3 * u * t * t * p2[i] + t ** 3 * p3[i] for i in range(3)])
    return out


def candidates(lanes):
    starts = {}
    for l in lanes:
        if l.get("connector"):
            continue
        p = l["points"][0]
        starts.setdefault((int(p[0] // CELL), int(p[2] // CELL)), []).append(l)
    pairs = []
    for u in lanes:
        if u.get("connector"):
            continue
        e = u["points"][-1]
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for v in starts.get((int(e[0] // CELL) + dx, int(e[2] // CELL) + dz), ()):
                    if v["road"] == u["road"]:
                        continue
                    s = v["points"][0]
                    d = math.hypot(s[0] - e[0], s[2] - e[2])
                    if d <= 6.0 and abs(s[1] - e[1]) <= 1.5 and turn(heading(v["points"][0], v["points"][1]), heading(u["points"][-2], u["points"][-1])) <= 40.0:
                        pairs.append((d, u, v))
    return pairs


def repair(doc, dense=False, direct_everything=False, skip_one=False):
    doc = copy.deepcopy(doc)
    lanes = doc["lanes"]
    by_id = {l["id"]: l for l in lanes}
    pairs = candidates(lanes)
    has_prev = set(n for l in lanes for n in l.get("next", []))
    chosen = {}
    for d, u, v in sorted(pairs, key=lambda x: x[0]):
        if u.get("next"):
            continue
        if u["id"] not in chosen or dense:
            chosen.setdefault(u["id"], []).append((d, u, v))
    # lanes of the other road that nobody feeds: feed them from the nearest lane
    for d, u, v in sorted(pairs, key=lambda x: x[0]):
        if v["id"] not in has_prev and not any(v is c[2] for lst in chosen.values() for c in lst):
            chosen.setdefault(u["id"], []).append((d, u, v))
    n = 0
    for uid, lst in chosen.items():
        if skip_one and n == 0:
            n += 1
            continue
        for d, u, v in lst:
            if direct_everything or d <= 0.5:
                u["next"].append(v["id"])
                continue
            p0, p3 = u["points"][-1], v["points"][0]
            d0 = [u["points"][-1][i] - u["points"][-2][i] for i in range(3)]
            d1 = [v["points"][1][i] - v["points"][0][i] for i in range(3)]
            l0 = math.sqrt(sum(x * x for x in d0)) or 1.0
            l1 = math.sqrt(sum(x * x for x in d1)) or 1.0
            d0 = [x / l0 for x in d0]
            d1 = [x / l1 for x in d1]
            span = max(4.0, math.dist(p0, p3) * 0.5)
            p1 = [p0[i] + d0[i] * span for i in range(3)]
            p2 = [p3[i] - d1[i] * span for i in range(3)]
            cid = "chain_%s_%s" % (u["id"], v["id"])
            lanes.append({"id": cid, "road": u["road"], "dir": u["dir"], "index": u["index"], "connector": True, "points": bezier(p0, p1, p2, p3), "next": [v["id"]], "elevated": u["elevated"]})
            u["next"].append(cid)
    return doc


def run(doc):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as fh:
        json.dump(doc, fh)
        path = fh.name
    res = subprocess.run([sys.executable, str(HERE / "check_chain_links.py"), path], capture_output=True, text=True)
    return res.returncode, res.stdout


def break_chains(doc):
    """A copy of the graph without the chain links: the chain connectors are gone and no lane of one road continues
    directly into a lane of another road that starts within 6 m (junction movements, j_ lanes, are kept)."""
    doc = copy.deepcopy(doc)
    lanes = doc["lanes"]
    gone = {l["id"] for l in lanes if l["id"].startswith("chain_")}
    lanes[:] = [l for l in lanes if l["id"] not in gone]
    by_id = {l["id"]: l for l in lanes}
    for u in lanes:
        if u.get("connector"):
            continue
        e = u["points"][-1]
        keep = []
        for n in u.get("next", []):
            v = by_id.get(n)
            direct = (v is not None and not v.get("connector") and v["road"] != u["road"]
                      and math.hypot(v["points"][0][0] - e[0], v["points"][0][2] - e[2]) <= 6.0
                      and abs(v["points"][0][1] - e[1]) <= 1.5)
            if n not in gone and not direct:
                keep.append(n)
        u["next"] = keep
    return doc


def main():
    doc = break_chains(json.load(open(sys.argv[1], encoding="utf-8")))
    ok = True
    code, out = run(repair(doc))
    print("repaired graph:", out.strip().splitlines()[-1])
    ok &= code == 0
    for name, kw, letter in (("one lane left unlinked", dict(skip_one=True), "A"),
                              ("direct links across 1 m", dict(direct_everything=True), "D"),
                              ("everything linked to everything", dict(dense=True), "E")):
        code, out = run(repair(doc, **kw))
        letters = {line.split()[1] for line in out.splitlines() if line.startswith("FAIL")}
        good = code != 0 and letter in letters
        print("%-34s -> exit %d, rules %s  %s" % (name, code, sorted(letters), "as expected" if good else "NOT DETECTED"))
        ok &= good
    code, out = run(doc)
    print("graph as it is today:", out.strip().splitlines()[-1], "(must fail)")
    ok &= code != 0
    print("SELFTEST", "OK" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
