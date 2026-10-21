"""city_junctions — the intersections of the surface network.

Every place where two roads meet gets one junction record, so the roads
unit can shape the intersection and the world unit can put a signal head
on it.  The rules:

* one record per intersection: the crossings that fall within 15 m of
  each other are merged into one record that lists every road involved;
* only the roads that are *at grade* there (|y| <= 0.3 m within 30 m of
  the point) are listed: a deck that flies over a street is not an
  intersection, but the foot of a ramp on a street is;
* signals where two roads of at least two lanes per direction meet.
"""
import math

import citylib

GRADE_TOL = 0.3        # the height a road must have to count as at grade
GRADE_WINDOW = 30.0    # the stretch of road that has to be at grade
MERGE_RADIUS = 15.0    # two crossings this close are one intersection
MAJOR_LANES = 2        # the lanes per direction that make a road major


def _coarse(points, step=10.0):
    """A polyline decimated to roughly `step` metres between the points."""
    out = [points[0]]
    acc = 0.0
    for a, b in zip(points, points[1:]):
        acc += math.dist(a, b)
        if acc >= step:
            out.append(b)
            acc = 0.0
    if out[-1] != points[-1]:
        out.append(points[-1])
    return out


def _sign(value):
    """The sign of a value, with zero in the middle (a touch is a cross)."""
    return (value > 0) - (value < 0)


def _seg_cross(p, q, r, s):
    """The intersection point of two segments, or None."""
    d1 = (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    d2 = (q[0] - p[0]) * (s[1] - p[1]) - (q[1] - p[1]) * (s[0] - p[0])
    d3 = (s[0] - r[0]) * (p[1] - r[1]) - (s[1] - r[1]) * (p[0] - r[0])
    d4 = (s[0] - r[0]) * (q[1] - r[1]) - (s[1] - r[1]) * (q[0] - p[0])
    if _sign(d1) == _sign(d2) or _sign(d3) == _sign(d4):
        return None
    den = (q[0] - p[0]) * (s[1] - r[1]) - (q[1] - p[1]) * (s[0] - r[0])
    if abs(den) < 1e-9:
        return None
    t = ((r[0] - p[0]) * (s[1] - r[1]) - (r[1] - p[1]) * (s[0] - r[0])) / den
    return (p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1]))


def _crossings(a, b):
    """The points where two polylines cross."""
    boxes = []
    for r, s in zip(b, b[1:]):
        boxes.append((min(r[0], s[0]), max(r[0], s[0]),
                      min(r[1], s[1]), max(r[1], s[1]), r, s))
    out = []
    for p, q in zip(a, a[1:]):
        px0, px1 = min(p[0], q[0]), max(p[0], q[0])
        pz0, pz1 = min(p[1], q[1]), max(p[1], q[1])
        for rx0, rx1, rz0, rz1, r, s in boxes:
            if px1 < rx0 or rx1 < px0 or pz1 < rz0 or rz1 < pz0:
                continue
            hit = _seg_cross(p, q, r, s)
            if hit is not None:
                out.append(hit)
    return out


def _near_poly(point, poly):
    """The distance from a point to a polyline."""
    best = 1e18
    for a, b in zip(poly, poly[1:]):
        best = min(best, citylib.point_seg_distance(point, a, b))
    return best


def at_grade(road, point):
    """True if the road runs at ground level where it passes `point`."""
    best, best_y = 1e18, 0.0
    for p, s in zip(road.points, road.dist):
        d = math.hypot(p[0] - point[0], p[2] - point[1])
        if d < best:
            best, best_y = d, p[1]
    if best > GRADE_WINDOW:
        return False
    return abs(best_y) <= GRADE_TOL


def is_major(road):
    """True if the road carries at least two lanes per direction."""
    return (road.lanes_fwd >= MAJOR_LANES
            and road.lanes_back + road.lanes_fwd >= MAJOR_LANES * 2)


def _candidates(roads):
    """The places where two roads meet, with the roads involved."""
    by_id = {road.id: road for road in roads}
    coarse = {}
    index = citylib.PolyIndex()
    widths = {}
    for road in roads:
        pts = [(p[0], p[2]) for p in road.points]
        c = _coarse(pts)
        coarse[road.id] = c
        widths[road.id] = citylib.road_width(road)
        index.add(road.id, c)
    out = []
    for road in roads:
        cands = set()
        for p in coarse[road.id][::2]:
            for name, _idx, _q in index.within(p, 40.0):
                if name != road.id:
                    cands.add(name)
        for other_id in sorted(cands):
            if other_id < road.id:
                continue
            other = by_id[other_id]
            for road_x, other_x in ((road, other), (other, road)):
                for end in (coarse[road_x.id][0], coarse[road_x.id][-1]):
                    if _near_poly(end, coarse[other_x.id]) <= \
                            widths[other_x.id] * 0.5 + 16.0:
                        out.append((end, road_x.id, other_x.id))
                        break
            for hit in _crossings(coarse[road.id], coarse[other_id]):
                out.append((hit, road.id, other_id))
    return out


def _cluster(points, radius=MERGE_RADIUS):
    """Merge the points that lie within `radius` of each other."""
    clusters = []
    for point, road_a, road_b in points:
        roads = (road_a, road_b)
        for cluster in clusters:
            if math.dist(cluster["centre"], point) <= radius:
                cluster["points"].append(point)
                cluster["roads"].update(roads)
                n = len(cluster["points"])
                cluster["centre"] = (sum(p[0] for p in cluster["points"]) / n,
                                     sum(p[1] for p in cluster["points"]) / n)
                break
        else:
            clusters.append({"centre": point, "points": [point],
                             "roads": set(roads)})
    return clusters


def _attach_candidates(roads):
    """The places where a ramp or a link road meets its parent at grade."""
    by_id = {r.id: r for r in roads}
    out = []
    for road in roads:
        for key in ("attach_start", "attach_end"):
            att = getattr(road, key, None)
            if not att:
                continue
            parent = by_id.get(att["road"])
            if parent is None:
                continue
            s = att.get("at", 0.0)
            p = parent.point_at(s)[0]
            if abs(p[1]) > GRADE_TOL:
                continue
            out.append(((p[0], p[2]), road.id, parent.id))
    return out


def _merge_close(clusters, radius=MERGE_RADIUS):
    """Merge the clusters whose centres are still within `radius`."""
    out = []
    for cluster in clusters:
        for other in out:
            if math.dist(other["centre"], cluster["centre"]) <= radius:
                other["points"].extend(cluster["points"])
                other["roads"].update(cluster["roads"])
                n = len(other["points"])
                other["centre"] = (sum(p[0] for p in other["points"]) / n,
                                   sum(p[1] for p in other["points"]) / n)
                break
        else:
            out.append(cluster)
    return out


def build_junctions(roads):
    """The junctions of the whole network, one record per intersection."""
    by_id = {road.id: road for road in roads}
    cands = _candidates(roads) + _attach_candidates(roads)
    clusters = _merge_close(_cluster(cands))
    out = []
    used_ids = {}
    for cluster in clusters:
        x, z = cluster["centre"]
        involved = sorted(rid for rid in cluster["roads"]
                          if at_grade(by_id[rid], (x, z)))
        if len(involved) < 2:
            continue
        major = sum(1 for rid in involved if is_major(by_id[rid]))
        name = "j_" + "_".join(involved)
        count = used_ids.get(name, 0)
        used_ids[name] = count + 1
        jid = name if count == 0 else "%s_%d" % (name, count)
        out.append({"id": jid, "x": round(x, 1), "z": round(z, 1),
                    "roads": involved, "signals": major >= 2})
    return out


