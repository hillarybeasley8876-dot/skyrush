"""Shared helpers for building the SKYRUSH Shanghai game map from OSM extracts.

Frames
- REAL: metres, X east, Z south, origin = Bund / Yan'an East Rd junction
  (lat 31.23514, lon 121.48739, WGS84 as stored in OSM).
- GAME: REAL passed through the piecewise-linear compression T (see fx/fz).
"""
import json
import math

LAT0, LON0 = 31.23514, 121.48739
KX = math.cos(math.radians(LAT0)) * 111320.0
KZ = 110574.0


def to_real(lat, lon):
    return ((lon - LON0) * KX, (LAT0 - lat) * KZ)


def fx(x):
    """Game X from real X: 0.85 in the core, 0.5 west of -600 and east of 1500."""
    if x < -600:
        return -510.0 + 0.5 * (x + 600)
    if x > 1500:
        return 1275.0 + 0.5 * (x - 1500)
    return 0.85 * x


def fz(z):
    """Game Z from real Z: 0.85 north of +600 (core), 0.5 south of it."""
    if z > 600:
        return 510.0 + 0.5 * (z - 600)
    return 0.85 * z


def T(p):
    return (round(fx(p[0]), 1), round(fz(p[1]), 1))


def rdp(pts, eps):
    """Ramer-Douglas-Peucker simplification of a 2D polyline."""
    if len(pts) < 3:
        return list(pts)
    (x1, z1), (x2, z2) = pts[0], pts[-1]
    seg = math.hypot(x2 - x1, z2 - z1) or 1e-9
    dmax, idx = -1.0, 0
    for i in range(1, len(pts) - 1):
        x0, z0 = pts[i]
        d = abs((z2 - z1) * x0 - (x2 - x1) * z0 + x2 * z1 - z2 * x1) / seg
        if d > dmax:
            dmax, idx = d, i
    if dmax > eps:
        return rdp(pts[: idx + 1], eps)[:-1] + rdp(pts[idx:], eps)
    return [pts[0], pts[-1]]


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)["elements"]


def way_polylines(elements, name=None, pred=None):
    """Real-frame polylines of ways matching a name (exact) or predicate on tags."""
    out = []
    for e in elements:
        if e["type"] != "way":
            continue
        t = e.get("tags", {})
        if name is not None and t.get("name") != name:
            continue
        if pred is not None and not pred(t):
            continue
        g = [q for q in e.get("geometry", []) if q]
        if len(g) >= 2:
            out.append(([to_real(q["lat"], q["lon"]) for q in g], t))
    return out


def water_segments(elements):
    """All boundary segments (real frame) of water=river polygons, incl. relation members."""
    segs = []
    for e in elements:
        t = e.get("tags", {})
        if t.get("water") != "river":
            continue
        if e["type"] == "way":
            geoms = [e.get("geometry", [])]
        else:
            geoms = [m.get("geometry", []) for m in e.get("members", []) if m.get("type") == "way"]
        for g in geoms:
            p = [to_real(q["lat"], q["lon"]) for q in g if q]
            segs += [(p[i], p[i + 1]) for i in range(len(p) - 1)]
    return segs


def ray_hit(o, d, segs, tmax=600.0):
    """Distance along unit ray o+t*d to the nearest segment, or None."""
    best = None
    for a, b in segs:
        ex, ez = b[0] - a[0], b[1] - a[1]
        den = d[0] * ez - d[1] * ex
        if abs(den) < 1e-9:
            continue
        t = ((a[0] - o[0]) * ez - (a[1] - o[1]) * ex) / den
        u = ((a[0] - o[0]) * d[1] - (a[1] - o[1]) * d[0]) / den
        if 0.5 < t < tmax and 0 <= u <= 1 and (best is None or t < best):
            best = t
    return best


def resample(pts, step):
    """Points every `step` metres along a polyline (plus the last vertex)."""
    out = [pts[0]]
    to_next = step
    for (x1, z1), (x2, z2) in zip(pts, pts[1:]):
        L = math.hypot(x2 - x1, z2 - z1)
        s = to_next
        while s <= L:
            out.append((x1 + (x2 - x1) * s / L, z1 + (z2 - z1) * s / L))
            s += step
        to_next = s - L
    if math.hypot(out[-1][0] - pts[-1][0], out[-1][1] - pts[-1][1]) > 1e-6:
        out.append(pts[-1])
    return out


def median_filter(vals, k):
    """Running median (odd window k) used to smooth bank distances."""
    h = k // 2
    res = []
    for i in range(len(vals)):
        w = sorted(vals[max(0, i - h): i + h + 1])
        res.append(w[len(w) // 2])
    return res
