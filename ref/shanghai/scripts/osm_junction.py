import json, sys, math
# usage: python3 -I osm_junction.py q.json lat0 lon0 nameA nameB  -> closest approach between two named way sets
d = json.load(open(sys.argv[1], encoding="utf-8"))
lat0, lon0 = float(sys.argv[2]), float(sys.argv[3])
A, B = sys.argv[4], sys.argv[5]
def pts(name):
    out = []
    for e in d["elements"]:
        if e.get("tags", {}).get("name") == name:
            out += [(p["lat"], p["lon"]) for p in e.get("geometry", [])]
    return out
KX = math.cos(math.radians(lat0)) * 111320.0; KZ = 110574.0
pa, pb = pts(A), pts(B)
best = min(((math.hypot((a[1]-b[1])*KX, (a[0]-b[0])*KZ), a, b) for a in pa for b in pb))
dist, a, b = best
lat = (a[0]+b[0])/2; lon = (a[1]+b[1])/2
print(f"closest {A}~{B}: {dist:.1f} m at lat={lat:.6f} lon={lon:.6f}")
