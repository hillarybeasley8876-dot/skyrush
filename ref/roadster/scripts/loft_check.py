"""Build the loft from roadster_loft.json exactly as DOSSIER 8.1 step 1 says and sanity-check it:
simple (non-self-intersecting) sections, closed-mesh volume, bounding box, glass area.
usage: python3 -I loft_check.py <loft.json>"""
import json
import sys
sys.path.append("/Users/minimax/Library/Python/3.9/lib/python/site-packages")
import numpy as np


def ring(sec):
    k = sec["K"]
    half = [(x, sec["y"], z) for x, z in k]                       # K0..K9, x >= 0
    mirror = [(-x, sec["y"], z) for x, z in reversed(k[1:-1])]   # K8..K1 mirrored
    return half + mirror                                          # 18 points, closed loop


def segs_intersect(p1, p2, p3, p4):
    d = lambda a, b, c: (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    d1, d2, d3, d4 = d(p3, p4, p1), d(p3, p4, p2), d(p1, p2, p3), d(p1, p2, p4)
    return (d1 * d2 < 0) and (d3 * d4 < 0)


def main():
    d = json.load(open(sys.argv[1]))
    secs = d["sections"]
    for s in secs:
        k = s["K"]
        bad = [(i, j) for i in range(9) for j in range(i + 2, 9) if segs_intersect(k[i], k[i + 1], k[j], k[j + 1])]
        if bad:
            print("SELF-INTERSECTION", s["id"], bad)
    rings = [np.array(ring(s)) for s in secs]
    tris = []
    for a, b in zip(rings[:-1], rings[1:]):
        n = len(a)
        for i in range(n):
            j = (i + 1) % n
            tris += [(a[i], b[i], b[j]), (a[i], b[j], a[j])]
    tip = rings[0].copy()
    tip[:, 0] = 0.0
    tip[:, 1] = 2.29
    for i in range(len(tip)):
        j = (i + 1) % len(tip)
        tris += [(tip[i], rings[0][i], rings[0][j]), (tip[i], rings[0][j], tip[j])]
    c = rings[-1].mean(axis=0)
    for i in range(len(rings[-1])):
        j = (i + 1) % len(rings[-1])
        tris.append((c, rings[-1][j], rings[-1][i]))
    vol = sum(np.dot(p, np.cross(q, r)) for p, q, r in tris) / 6.0
    pts = np.vstack(rings + [tip])
    print(f"triangles {len(tris)}, signed volume {vol:.2f} m3 (expect +5.5..7 if winding is outward; sign only shows winding)")
    print("bbox x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % (pts[:, 0].min(), pts[:, 0].max(), pts[:, 1].min(), pts[:, 1].max(), pts[:, 2].min(), pts[:, 2].max()))
    g = 0.0
    for s0, s1, r0, r1 in zip(secs[:-1], secs[1:], rings[:-1], rings[1:]):
        for j, band in enumerate(s0["bands"]):
            if band == "G":
                q = [r0[j], r0[j + 1], r1[j + 1], r1[j]]
                g += 2 * 0.5 * (np.linalg.norm(np.cross(q[1] - q[0], q[3] - q[0])) + np.linalg.norm(np.cross(q[2] - q[1], q[2] - q[3])))
    print(f"glass area (both sides) {g:.2f} m2")


if __name__ == "__main__":
    main()
