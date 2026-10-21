import json, sys, math
# usage: python3 -I osm_lines.py q.json lat0 lon0 tol_m xmin xmax zmin zmax name [name...]
d = json.load(open(sys.argv[1], encoding="utf-8"))
lat0, lon0, tol = float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
xmin, xmax, zmin, zmax = map(float, sys.argv[5:9]); names = sys.argv[9:]
KX = math.cos(math.radians(lat0)) * 111320.0; KZ = 110574.0
def xz(p): return ((p["lon"]-lon0)*KX, (lat0-p["lat"])*KZ)
def rdp(pts, eps):
    if len(pts) < 3: return pts
    (x1,z1),(x2,z2) = pts[0], pts[-1]; L = math.hypot(x2-x1, z2-z1) or 1e-9
    dmax, idx = 0, 0
    for i in range(1, len(pts)-1):
        x0,z0 = pts[i]; dd = abs((z2-z1)*x0-(x2-x1)*z0+x2*z1-z2*x1)/L
        if dd > dmax: dmax, idx = dd, i
    if dmax > eps: return rdp(pts[:idx+1], eps)[:-1] + rdp(pts[idx:], eps)
    return [pts[0], pts[-1]]
for e in d["elements"]:
    t = e.get("tags", {}); n = t.get("name")
    if n not in names: continue
    pts = [xz(p) for p in e.get("geometry", [])]
    pts = [p for p in pts if xmin <= p[0] <= xmax and zmin <= p[1] <= zmax]
    if len(pts) < 2: continue
    s = rdp(pts, tol)
    meta = ",".join(f"{k}={t[k]}" for k in ("layer","lanes","oneway","bridge","tunnel","highway") if k in t)
    print(f"{n} [{meta}] " + " ".join(f"({x:.0f},{z:.0f})" for x, z in s))
