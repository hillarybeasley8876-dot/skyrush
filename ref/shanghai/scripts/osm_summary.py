import json, sys, math, collections
# usage: python3 -I osm_summary.py q.json lat0 lon0
d = json.load(open(sys.argv[1], encoding="utf-8"))
lat0, lon0 = float(sys.argv[2]), float(sys.argv[3])
KX = math.cos(math.radians(lat0)) * 111320.0
KZ = 110574.0
def xz(lat, lon):
    return ((lon - lon0) * KX, (lat0 - lat) * KZ)  # X east, Z south
groups = collections.defaultdict(list)
for e in d["elements"]:
    t = e.get("tags", {})
    name = t.get("name", "?")
    g = e.get("geometry") or []
    if not g: continue
    pts = [xz(p["lat"], p["lon"]) for p in g]
    groups[name].append((e["type"], e["id"], t, pts))
for name, items in sorted(groups.items()):
    allp = [p for it in items for p in it[3]]
    xs = [p[0] for p in allp]; zs = [p[1] for p in allp]
    kinds = set()
    for typ, i, t, pts in items:
        for k in ("highway","building","bridge","tunnel","layer","waterway","man_made","height","building:levels","lanes","oneway"):
            if k in t: kinds.add(f"{k}={t[k]}")
    print(f"{name}: n_ways={len(items)} X[{min(xs):.0f},{max(xs):.0f}] Z[{min(zs):.0f},{max(zs):.0f}] cx={sum(xs)/len(xs):.0f} cz={sum(zs)/len(zs):.0f} | {' '.join(sorted(kinds))[:220]}")
