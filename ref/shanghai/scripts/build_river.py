"""Step 1: Huangpu banks + Suzhou Creek in GAME frame -> build/river.json

Banks = smoothed real centreline offset by median-filtered real bank distances,
then passed through T and simplified. Piers/docks/creek mouths are filtered out.

usage: python3 -E -s build_river.py <q1.json> <q5.json> <out.json>
"""
import json
import math
import sys

import maplib as M

q1, q5, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
el1, el5 = M.load(q1), M.load(q5)
segs = M.water_segments(el5)

raw = [p for p, t in M.way_polylines(el1, name="黄浦江")][0]
center = [p for p in raw if -4180 <= p[0] <= 2350 and -1412 <= p[1] <= 3180]
# the first kept vertex lies inside the window: re-insert the clipped southern segment up to z=3600
i0 = raw.index(center[0])
(xa, za), (xb, zb) = raw[i0 - 1], raw[i0]
t = (3600 - zb) / (za - zb)
center = [(xb + (xa - xb) * t, 3600.0)] + center
samples = M.resample(center, 40.0)

rows = []  # (origin, normal, dist_left, dist_right)
for a, b in zip(samples, samples[1:]):
    dx, dz = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dz)
    n = (dz / L, -dx / L)  # left of travel (south->north) = Puxi / west bank
    o = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    tl = M.ray_hit(o, n, segs, 450)
    tr = M.ray_hit(o, (-n[0], -n[1]), segs, 450)
    rows.append((o, n, tl, tr))

def fill(vals, default):
    good = [v for v in vals if v is not None and 120 < v < 330]
    med = sorted(good)[len(good) // 2] if good else default
    return [v if (v is not None and 120 < v < 330) else med for v in vals]

dl = M.median_filter(fill([r[2] for r in rows], 205.0), 9)
dr = M.median_filter(fill([r[3] for r in rows], 205.0), 9)
west = [(o[0] + n[0] * a, o[1] + n[1] * a) for (o, n, _, _), a in zip(rows, dl)]
east = [(o[0] - n[0] * b, o[1] - n[1] * b) for (o, n, _, _), b in zip(rows, dr)]
mid = [r[0] for r in rows]
width = [a + b for a, b in zip(dl, dr)]

def game(poly, eps):
    return [list(p) for p in M.rdp([M.T(p) for p in poly], eps)]


def no_backtrack(poly, guide):
    """Drop vertices whose projection on the guide polyline goes backwards (simplification zig-zags)."""
    def station(p):
        best, acc, s_best = None, 0.0, 0.0
        for (x1, z1), (x2, z2) in zip(guide, guide[1:]):
            L = math.hypot(x2 - x1, z2 - z1) or 1e-9
            t = max(0.0, min(1.0, ((p[0] - x1) * (x2 - x1) + (p[1] - z1) * (z2 - z1)) / L / L))
            d = math.hypot(x1 + t * (x2 - x1) - p[0], z1 + t * (z2 - z1) - p[1])
            if best is None or d < best:
                best, s_best = d, acc + t * L
            acc += L
        return s_best
    out, last = [], -1e9
    for p in poly:
        s = station(p)
        if s >= last - 3.0:
            out.append(p)
            last = max(last, s)
    return out

creek = []
for p, t in M.way_polylines(el5, pred=lambda t: t.get("name") in ("苏州河", "吴淞江")):
    creek += p
creek = sorted({(round(x), round(z)) for x, z in creek if x > -3200}, key=lambda q: -q[0])

mid_g = game(mid, 8.0)
west_g = no_backtrack(game(west, 5.0), mid_g)
east_g = no_backtrack(game(east, 5.0), mid_g)
creek_g = [p for p in game(creek, 6.0) if p[0] <= 40.0]
creek_g = [[40.0, -901.0]] + creek_g  # mouth: where the creek meets the Huangpu west bank

res = {
    "frame": "GAME metres, X east, Z south; origin Bund/Yan'an junction; compression T (maplib.fx/fz)",
    "huangpu_west_bank_puxi": west_g,
    "huangpu_east_bank_pudong": east_g,
    "huangpu_centerline": mid_g,
    "huangpu_real_width_m": {"min": round(min(width)), "max": round(max(width)),
                             "mean": round(sum(width) / len(width))},
    "suzhou_creek_centerline": creek_g,
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=1)
for k, v in res.items():
    print(k, v if not isinstance(v, list) else f"{len(v)} pts: {v}")
