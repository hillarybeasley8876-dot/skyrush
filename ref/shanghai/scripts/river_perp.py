import json, sys, math
# usage: python3 -I river_perp.py q2.json lat0 lon0 "x,z;x,z;..."  -> perpendicular river width at centerline points
d = json.load(open(sys.argv[1], encoding="utf-8"))
lat0, lon0 = float(sys.argv[2]), float(sys.argv[3])
cl = [tuple(map(float, s.split(","))) for s in sys.argv[4].split(";")]
KX = math.cos(math.radians(lat0)) * 111320.0; KZ = 110574.0
segs = []
for e in d["elements"]:
    if e.get("tags", {}).get("water") != "river": continue
    geoms = [e.get("geometry", [])] if e["type"] == "way" else [m.get("geometry", []) for m in e.get("members", []) if m.get("type") == "way"]
    for g in geoms:
        p = [((q["lon"]-lon0)*KX, (lat0-q["lat"])*KZ) for q in g if q]
        segs += [(p[i], p[i+1]) for i in range(len(p)-1)]
def hit(o, dvec):
    best = None
    for a, b in segs:
        ex, ez = b[0]-a[0], b[1]-a[1]
        den = dvec[0]*ez - dvec[1]*ex
        if abs(den) < 1e-9: continue
        t = ((a[0]-o[0])*ez - (a[1]-o[1])*ex) / den
        u = ((a[0]-o[0])*dvec[1] - (a[1]-o[1])*dvec[0]) / den
        if t > 1 and 0 <= u <= 1 and (best is None or t < best): best = t
    return best
for i in range(len(cl)-1):
    (x1,z1),(x2,z2) = cl[i], cl[i+1]
    mx, mz = (x1+x2)/2, (z1+z2)/2; L = math.hypot(x2-x1, z2-z1)
    nx, nz = -(z2-z1)/L, (x2-x1)/L
    l, r = hit((mx,mz), (nx,nz)), hit((mx,mz), (-nx,-nz))
    print(f"mid=({mx:.0f},{mz:.0f}) dir={math.degrees(math.atan2(x2-x1, -(z2-z1))):.0f}deg width={(l or 0)+(r or 0):.0f} (sides {l and round(l)}, {r and round(r)})")
