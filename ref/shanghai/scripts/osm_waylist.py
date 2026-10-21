import json, sys, math
# usage: python3 -I osm_waylist.py q.json lat0 lon0 xmin xmax zmin zmax -> list ways (name, layer, lanes, length, endpoints)
d = json.load(open(sys.argv[1], encoding="utf-8"))
lat0, lon0 = float(sys.argv[2]), float(sys.argv[3]); xmin, xmax, zmin, zmax = map(float, sys.argv[4:8])
KX = math.cos(math.radians(lat0)) * 111320; KZ = 110574
rows = []
for e in d["elements"]:
    t = e.get("tags", {}); p = [((q["lon"]-lon0)*KX, (lat0-q["lat"])*KZ) for q in e.get("geometry", [])]
    if not p or not any(xmin <= x <= xmax and zmin <= z <= zmax for x, z in p): continue
    L = sum(math.hypot(p[i+1][0]-p[i][0], p[i+1][1]-p[i][1]) for i in range(len(p)-1))
    rows.append((t.get("layer", "0"), t.get("name", "-")[:10], t.get("lanes", "?"), t.get("highway", ""), L, p[0], p[-1], t.get("oneway", "")))
for r in sorted(rows):
    print(f"L{r[0]:>2} {r[1]:10s} lanes={r[2]} {r[3]:13s} len={r[4]:4.0f} ({r[5][0]:.0f},{r[5][1]:.0f})->({r[6][0]:.0f},{r[6][1]:.0f}) {r[7]}")
