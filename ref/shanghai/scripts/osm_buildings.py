import json, sys, math
# usage: python3 -I osm_buildings.py q.json lat0 lon0  -> building list with local centroid, footprint dims, tags
d = json.load(open(sys.argv[1], encoding="utf-8"))
lat0, lon0 = float(sys.argv[2]), float(sys.argv[3])
KX = math.cos(math.radians(lat0)) * 111320.0; KZ = 110574.0
rows = []
for e in d["elements"]:
    t = e.get("tags", {})
    if "building" not in t: continue
    p = [((q["lon"]-lon0)*KX, (lat0-q["lat"])*KZ) for q in e.get("geometry", [])]
    if not p: continue
    xs = [a for a, b in p]; zs = [b for a, b in p]
    area = 0.5*abs(sum(p[i][0]*p[(i+1)%len(p)][1]-p[(i+1)%len(p)][0]*p[i][1] for i in range(len(p))))
    rows.append((sum(zs)/len(zs), sum(xs)/len(xs), max(xs)-min(xs), max(zs)-min(zs), area, t))
for cz, cx, w, h, a, t in sorted(rows, key=lambda r: -r[0]):
    if a < 300: continue
    nm = t.get("name", "-"); addr = t.get("addr:housenumber", ""); st = t.get("addr:street", "")
    print(f"z={cz:6.0f} x={cx:6.0f} bbox={w:4.0f}x{h:4.0f} area={a:6.0f} lv={t.get('building:levels','?'):>3} h={t.get('height','?'):>5} {nm} {st}{addr}")
